#include "avm.h"
#include "sha256.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <stdint.h>
#include <unistd.h>

// Error codes (must match the C runtime's rolling conventions in lib/runtime.h)
#define AVM_ERR_PERM 1
#define AVM_ERR_NOT_FOUND 2
#define AVM_ERR_IO 3
#define AVM_ERR_INVALID_ARG 4
#define AVM_ERR_TIMEOUT 5
#define AVM_ERR_CANCELLED 6
#define AVM_ERR_NOT_IMPLEMENTED 7
#define AVM_ERR_INTERNAL 8
#define AVM_ERR_BUDGET 9

// Rolling heap budgeting (bootstrap implementation):
// - Applies to heap allocations for AVM value objects/buffers (STRING/LIST/MAP/BYTES), plus record/replay buffers.
// - Does NOT attempt to budget the VM operand stack allocation (which is currently a large fixed buffer).
// - When the budget is exceeded, allocation helpers return NULL and set a thread-local-ish last error code.

typedef struct AvmAllocHdr {
    uint64_t magic;
    AvmVM* owner;
    uint64_t size;
    uint64_t charged_size;
    struct AvmAllocHdr* prev;
    struct AvmAllocHdr* next;
} AvmAllocHdr;

static const uint64_t AVM_ALLOC_MAGIC = 0x41564d414c4c4f43ull; // "AVMALLOC"

static AvmVM* g_alloc_owner = NULL;
static int g_alloc_unbudgeted = 0;
static int g_last_alloc_err = 0; // 0=none, else AVM_ERR_* (budget/internal)

static AvmValue avm_err(int code, const char* msg); // forward decl (used by alloc helpers)
static AvmValue avm_err_domop(int code, const char* msg, int domain, int op); // forward decl (used by budget/cap helpers)
static void avm_abort(AvmVM* vm, AvmValue err); // forward decl (used by budget helpers)

static void avm_alloc_owner_push(AvmVM* vm, AvmVM** prev) {
    if (prev) *prev = g_alloc_owner;
    g_alloc_owner = vm;
}

static void avm_alloc_owner_pop(AvmVM* prev) {
    g_alloc_owner = prev;
}

static void avm_alloc_unbudgeted_push(int* prev) {
    if (prev) *prev = g_alloc_unbudgeted;
    g_alloc_unbudgeted = 1;
}

static void avm_alloc_unbudgeted_pop(int prev) {
    g_alloc_unbudgeted = prev;
}

static void* avm_heap_malloc(size_t size) {
    g_last_alloc_err = 0;
    AvmVM* owner = g_alloc_owner;
    if (!g_alloc_unbudgeted && owner && owner->heap_budget_bytes > 0) {
        if (size > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
        if (owner->heap_used_bytes + size > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
    }

    size_t total = sizeof(AvmAllocHdr) + size;
    AvmAllocHdr* h = (AvmAllocHdr*)malloc(total);
    if (!h) {
        g_last_alloc_err = AVM_ERR_INTERNAL;
        return NULL;
    }
    h->magic = AVM_ALLOC_MAGIC;
    h->owner = owner;
    h->size = size;
    h->charged_size = (!g_alloc_unbudgeted && owner) ? size : 0;
    h->prev = NULL;
    h->next = NULL;
    if (owner) {
        h->next = (AvmAllocHdr*)owner->heap_allocs_head;
        if (h->next) h->next->prev = h;
        owner->heap_allocs_head = h;
    }
    if (h->charged_size && owner) owner->heap_used_bytes += h->charged_size;
    return (void*)(h + 1);
}

static AvmAllocHdr* avm_alloc_hdr_from_ptr(void* p) {
    if (!p) return NULL;
    AvmAllocHdr* h = ((AvmAllocHdr*)p) - 1;
    if (h->magic != AVM_ALLOC_MAGIC) return NULL;
    return h;
}

static void avm_heap_free(void* p) {
    if (!p) return;
    AvmAllocHdr* h = avm_alloc_hdr_from_ptr(p);
    if (!h) {
        free(p);
        return;
    }
    if (h->owner) {
        // Remove from owner allocation list (if still linked).
        if (h->prev) h->prev->next = h->next;
        else if ((AvmAllocHdr*)h->owner->heap_allocs_head == h) h->owner->heap_allocs_head = h->next;
        if (h->next) h->next->prev = h->prev;
        h->prev = NULL;
        h->next = NULL;

        if (h->charged_size && h->owner->heap_used_bytes >= h->charged_size) h->owner->heap_used_bytes -= h->charged_size;
        else if (h->charged_size) h->owner->heap_used_bytes = 0;
    }
    h->magic = 0;
    free(h);
}

static void* avm_heap_realloc(void* p, size_t new_size) {
    g_last_alloc_err = 0;
    if (!p) return avm_heap_malloc(new_size);

    AvmAllocHdr* h = avm_alloc_hdr_from_ptr(p);
    if (!h) {
        // Unknown pointer: fallback to libc realloc (unbudgeted).
        void* np = realloc(p, new_size);
        if (!np) g_last_alloc_err = AVM_ERR_INTERNAL;
        return np;
    }

    AvmVM* owner = h->owner;
    uint64_t old_size = h->size;
    uint64_t old_charged = h->charged_size;
    uint64_t new_charged = (old_charged != 0) ? (uint64_t)new_size : 0;

    uint64_t used_without_old = 0;
    if (owner) {
        used_without_old = owner->heap_used_bytes;
        if (used_without_old >= old_charged) used_without_old -= old_charged;
        else used_without_old = 0;
    }

    if (!g_alloc_unbudgeted && owner && owner->heap_budget_bytes > 0 && new_charged != 0) {
        if (new_charged > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
        if (used_without_old + new_charged > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
    }

    size_t total = sizeof(AvmAllocHdr) + new_size;
    AvmAllocHdr* nh = (AvmAllocHdr*)malloc(total);
    if (!nh) {
        g_last_alloc_err = AVM_ERR_INTERNAL;
        return NULL;
    }
    nh->magic = AVM_ALLOC_MAGIC;
    nh->owner = owner;
    nh->size = new_size;
    nh->charged_size = new_charged;
    nh->prev = NULL;
    nh->next = NULL;

    size_t copy_n = (old_size < new_size) ? (size_t)old_size : new_size;
    if (copy_n > 0) memcpy(nh + 1, h + 1, copy_n);

    if (owner) {
        // Link new header into owner list.
        nh->next = (AvmAllocHdr*)owner->heap_allocs_head;
        if (nh->next) nh->next->prev = nh;
        owner->heap_allocs_head = nh;
        // Update accounting in one step (old already subtracted).
        owner->heap_used_bytes = used_without_old + new_charged;
    }

    // Unlink and free old header without adjusting accounting again (already handled above).
    if (owner) {
        if (h->prev) h->prev->next = h->next;
        else if ((AvmAllocHdr*)owner->heap_allocs_head == h) owner->heap_allocs_head = h->next;
        if (h->next) h->next->prev = h->prev;
    }
    h->magic = 0;
    free(h);

    return (void*)(nh + 1);
}

static int avm_io_charge(AvmVM* vm, uint64_t bytes, int domain, int op) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->io_budget_bytes == 0) {
        vm->io_used_bytes += bytes;
        return 1;
    }
    if (bytes > vm->io_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (io)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    if (vm->io_used_bytes + bytes > vm->io_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (io)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    vm->io_used_bytes += bytes;
    return 1;
}

static int avm_log_charge(AvmVM* vm, uint64_t bytes, int domain, int op) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->log_budget_bytes == 0) {
        vm->log_used_bytes += bytes;
        return 1;
    }
    if (bytes > vm->log_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    if (vm->log_used_bytes + bytes > vm->log_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    vm->log_used_bytes += bytes;
    return 1;
}

static int avm_log_can_fit(AvmVM* vm, uint64_t bytes) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->log_budget_bytes == 0) return 1;
    if (bytes > vm->log_budget_bytes) return 0;
    if (vm->log_used_bytes + bytes > vm->log_budget_bytes) return 0;
    return 1;
}

static AvmValue avm_alloc_fail_value() {
    if (g_last_alloc_err == AVM_ERR_BUDGET) return avm_err(AVM_ERR_BUDGET, "budget exceeded (mem)");
    return avm_err(AVM_ERR_INTERNAL, "oom");
}

static const char* avm_op_name(uint8_t op) {
    switch (op) {
        case 0x00: return "NOP";
        case 0x01: return "HALT";
        case 0x02: return "PUSH_CONST";
        case 0x03: return "POP";
        case 0x04: return "LOAD_LOCAL";
        case 0x05: return "STORE_LOCAL";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x12: return "LT";
        case 0x13: return "EQ";
        case 0x14: return "NEQ";
        case 0x15: return "GT";
        case 0x16: return "LE";
        case 0x17: return "GE";
        case 0x18: return "AND";
        case 0x19: return "OR";
        case 0x1A: return "XOR";
        case 0x1B: return "SHL";
        case 0x1C: return "SHR";
        case 0x20: return "PRINT";
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x38: return "CALL";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x40: return "NEW_LIST";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x43: return "SET_INDEX";
        default: return "OP?";
    }
}

char* my_strdup(const char* s) {
    if (!s) s = "";
    size_t n = strlen(s);
    char* d = (char*)avm_heap_malloc(n + 1);
    if (!d) return NULL;
    memcpy(d, s, n + 1);
    return d;
}

// Snapshot format (rolling):
// - file magic: "AVMSNAP1" (7 bytes) + 0x00 terminator (8 bytes total)
// - u32 object_count
// - object table, id 0..count-1:
//     u8 obj_type: 1=STRING,2=LIST,3=MAP
//     u32 aux: string_len (bytes) / list_count / map_count
//     payload:
//       STRING: aux bytes (no NUL)
//       LIST: aux values, each encoded as 1 byte tag + 8 byte payload (little-endian)
//       MAP: aux pairs, each key then value encoded (2*aux values)
// - VM state:
//     u32 pc, u32 sp, u32 fp, u32 frame_count
//     frames[frame_count]: u32 return_pc, u32 fp
//     globals[MAX_GLOBALS]: encoded values
//     stack[sp]: encoded values
//
// Value encoding (fixed size):
// - tag 0: NIL (payload ignored)
// - tag 1: INT (payload is int64 bits)
// - tag 2: FLOAT (payload is IEEE754 bits)
// - tag 3: BOOL (payload 0/1)
// - tag 4: OBJREF (payload is u64 object id)

static int avm_err_from_errno(int err) {
    if (err == EACCES || err == EPERM) return AVM_ERR_PERM;
    if (err == ENOENT) return AVM_ERR_NOT_FOUND;
    return AVM_ERR_IO;
}

static AvmValue avm_string(const char* s) {
    AvmValue v;
    v.type = AVM_VAL_STRING;
    v.as.p = my_strdup(s ? s : "");
    if (!v.as.p) return avm_alloc_fail_value();
    return v;
}

static AvmValue avm_int(int64_t i) {
    AvmValue v;
    v.type = AVM_VAL_INT;
    v.as.i = i;
    return v;
}

static AvmValue avm_bool(int b) {
    AvmValue v;
    v.type = AVM_VAL_BOOL;
    v.as.i = b ? 1 : 0;
    return v;
}

static AvmValue avm_nil() {
    AvmValue v;
    v.type = AVM_VAL_NIL;
    v.as.i = 0;
    return v;
}

static AvmValue avm_bytes_new(int len) {
    if (len < 0) return avm_nil();
    AvmBytes* b = (AvmBytes*)avm_heap_malloc(sizeof(AvmBytes));
    if (!b) return avm_alloc_fail_value();
    b->len = len;
    b->capacity = len;
    b->data = NULL;
    if (len > 0) {
        b->data = (uint8_t*)avm_heap_malloc((size_t)len);
        if (!b->data) { avm_heap_free(b); return avm_alloc_fail_value(); }
        memset(b->data, 0, (size_t)len);
    }
    AvmValue v;
    v.type = AVM_VAL_BYTES;
    v.as.b = b;
    return v;
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

// Structured error representation (rolling): map {"__err": true, "code": int, "msg": string}
static AvmValue avm_err(int code, const char* msg) {
    int prev_budget = 0;
    avm_alloc_unbudgeted_push(&prev_budget);

    AvmMap* map = (AvmMap*)avm_heap_malloc(sizeof(AvmMap));
    if (!map) { avm_alloc_unbudgeted_pop(prev_budget); return avm_nil(); }
    map->count = 3;
    map->capacity = 8;
    map->keys = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * map->capacity);
    map->values = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * map->capacity);
    if (!map->keys || !map->values) {
        if (map->keys) avm_heap_free(map->keys);
        if (map->values) avm_heap_free(map->values);
        avm_heap_free(map);
        avm_alloc_unbudgeted_pop(prev_budget);
        return avm_nil();
    }

    map->keys[0] = avm_string("__err");
    map->values[0] = avm_bool(1);

    map->keys[1] = avm_string("code");
    map->values[1] = avm_int(code);

    map->keys[2] = avm_string("msg");
    map->values[2] = avm_string(msg ? msg : "");

    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;

    avm_alloc_unbudgeted_pop(prev_budget);
    return v;
}

// Extended structured error (rolling): optionally includes domain/op metadata.
// This enables policy-aware debugging for agentic workflows, without changing the base error fields.
static AvmValue avm_err_domop(int code, const char* msg, int domain, int op) {
    int prev_budget = 0;
    avm_alloc_unbudgeted_push(&prev_budget);

    int extra = 0;
    if (domain >= 0) extra++;
    if (op >= 0) extra++;

    AvmMap* map = (AvmMap*)avm_heap_malloc(sizeof(AvmMap));
    if (!map) { avm_alloc_unbudgeted_pop(prev_budget); return avm_nil(); }
    map->count = 3 + extra;
    map->capacity = 8;
    map->keys = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * map->capacity);
    map->values = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * map->capacity);
    if (!map->keys || !map->values) {
        if (map->keys) avm_heap_free(map->keys);
        if (map->values) avm_heap_free(map->values);
        avm_heap_free(map);
        avm_alloc_unbudgeted_pop(prev_budget);
        return avm_nil();
    }

    map->keys[0] = avm_string("__err");
    map->values[0] = avm_bool(1);

    map->keys[1] = avm_string("code");
    map->values[1] = avm_int(code);

    map->keys[2] = avm_string("msg");
    map->values[2] = avm_string(msg ? msg : "");

    int at = 3;
    if (domain >= 0) {
        map->keys[at] = avm_string("domain");
        map->values[at] = avm_int(domain);
        at++;
    }
    if (op >= 0) {
        map->keys[at] = avm_string("op");
        map->values[at] = avm_int(op);
        at++;
    }

    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;

    avm_alloc_unbudgeted_pop(prev_budget);
    return v;
}

static int avm_map_get_bool(AvmMap* map, const char* key) {
    if (!map) return 0;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && strcmp((char*)k.as.p, key) == 0) {
            AvmValue v = map->values[i];
            if (v.type == AVM_VAL_BOOL) return v.as.i != 0;
            if (v.type == AVM_VAL_INT) return v.as.i != 0;
            return 0;
        }
    }
    return 0;
}

static AvmValue avm_map_get(AvmMap* map, const char* key) {
    if (!map) return avm_nil();
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && strcmp((char*)k.as.p, key) == 0) {
            return map->values[i];
        }
    }
    return avm_nil();
}

static int avm_is_err_val(AvmValue v) {
    if (v.type != AVM_VAL_MAP) return 0;
    return avm_map_get_bool(v.as.m, "__err");
}

static uint64_t avm_now_ns() {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static void avm_abort(AvmVM* vm, AvmValue err) {
    vm->last_error = err;
    vm->exit_code = 1;
    vm->running = 0;
}

static uint64_t read_u64_le(FILE* f, int* ok) {
    uint8_t b[8];
    if (fread(b, 1, 8, f) != 8) { *ok = 0; return 0; }
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= ((uint64_t)b[i]) << (8 * i);
    return v;
}

static uint32_t read_u32_le(FILE* f, int* ok) {
    uint8_t b[4];
    if (fread(b, 1, 4, f) != 4) { *ok = 0; return 0; }
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) v |= ((uint32_t)b[i]) << (8 * i);
    return v;
}

static int write_u64_le(FILE* f, uint64_t v) {
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    return fwrite(b, 1, 8, f) == 8;
}

static int write_u32_le(FILE* f, uint32_t v) {
    uint8_t b[4];
    for (int i = 0; i < 4; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    return fwrite(b, 1, 4, f) == 4;
}

static int write_u8(FILE* f, uint8_t v) {
    return fwrite(&v, 1, 1, f) == 1;
}

static int bytes_ensure_cap(AvmBytes* b, int need) {
    if (!b) return 0;
    if (need <= b->capacity) return 1;
    int new_cap = b->capacity ? b->capacity : 64;
    while (new_cap < need) new_cap *= 2;
    uint8_t* nd = (uint8_t*)avm_heap_realloc(b->data, (size_t)new_cap);
    if (!nd) return 0;
    b->data = nd;
    b->capacity = new_cap;
    return 1;
}

static int mem_write_u8(AvmBytes* b, uint32_t* pos, uint8_t v) {
    if (!b || !pos) return 0;
    uint32_t p = *pos;
    if (!bytes_ensure_cap(b, (int)(p + 1))) return 0;
    b->data[p] = v;
    p += 1;
    if ((int)p > b->len) b->len = (int)p;
    *pos = p;
    return 1;
}

static int mem_write_u16_le(AvmBytes* b, uint32_t* pos, uint16_t v) {
    if (!mem_write_u8(b, pos, (uint8_t)(v & 0xFF))) return 0;
    if (!mem_write_u8(b, pos, (uint8_t)((v >> 8) & 0xFF))) return 0;
    return 1;
}

static int mem_write_u32_le(AvmBytes* b, uint32_t* pos, uint32_t v) {
    for (int i = 0; i < 4; i++) {
        if (!mem_write_u8(b, pos, (uint8_t)((v >> (8 * i)) & 0xFF))) return 0;
    }
    return 1;
}

static int mem_write_u64_le(AvmBytes* b, uint32_t* pos, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        if (!mem_write_u8(b, pos, (uint8_t)((v >> (8 * i)) & 0xFF))) return 0;
    }
    return 1;
}

static int mem_write_bytes(AvmBytes* b, uint32_t* pos, const uint8_t* data, uint32_t len) {
    if (!b || !pos) return 0;
    uint32_t p = *pos;
    if (len == 0) return 1;
    if (!bytes_ensure_cap(b, (int)(p + len))) return 0;
    memcpy(b->data + p, data, len);
    p += len;
    if ((int)p > b->len) b->len = (int)p;
    *pos = p;
    return 1;
}

static int mem_read_u8(const AvmBytes* b, uint32_t* pos, uint8_t* out) {
    if (!b || !pos || !out) return 0;
    if (*pos >= (uint32_t)b->len) return 0;
    *out = b->data[*pos];
    *pos += 1;
    return 1;
}

static int mem_read_u16_le(const AvmBytes* b, uint32_t* pos, uint16_t* out) {
    uint8_t b0, b1;
    if (!mem_read_u8(b, pos, &b0)) return 0;
    if (!mem_read_u8(b, pos, &b1)) return 0;
    *out = (uint16_t)b0 | ((uint16_t)b1 << 8);
    return 1;
}

static int mem_read_u32_le(const AvmBytes* b, uint32_t* pos, uint32_t* out) {
    uint8_t bb[4];
    for (int i = 0; i < 4; i++) if (!mem_read_u8(b, pos, &bb[i])) return 0;
    *out = (uint32_t)bb[0] | ((uint32_t)bb[1] << 8) | ((uint32_t)bb[2] << 16) | ((uint32_t)bb[3] << 24);
    return 1;
}

static int mem_read_u64_le(const AvmBytes* b, uint32_t* pos, uint64_t* out) {
    uint64_t v = 0;
    uint8_t bb = 0;
    for (int i = 0; i < 8; i++) {
        if (!mem_read_u8(b, pos, &bb)) return 0;
        v |= ((uint64_t)bb) << (8 * i);
    }
    *out = v;
    return 1;
}

static int mem_read_bytes(const AvmBytes* b, uint32_t* pos, uint8_t* out, uint32_t len) {
    if (!b || !pos || (!out && len > 0)) return 0;
    if ((uint64_t)(*pos) + (uint64_t)len > (uint64_t)b->len) return 0;
    if (len > 0) memcpy(out, b->data + *pos, len);
    *pos += len;
    return 1;
}

static uint64_t prng_next_u64(uint64_t* state) {
    // xorshift64* (deterministic, fast). Not cryptographically secure.
    uint64_t x = *state;
    if (x == 0) x = 0x9e3779b97f4a7c15ull;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1Dull;
}

static uint64_t host_random_u64() {
    uint64_t v = 0;
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    arc4random_buf(&v, sizeof(v));
    return v;
#else
    FILE* f = fopen("/dev/urandom", "rb");
    if (f) {
        if (fread(&v, 1, sizeof(v), f) == sizeof(v)) {
            fclose(f);
            return v;
        }
        fclose(f);
    }
    // Last resort (non-crypto).
    v = ((uint64_t)rand() << 32) ^ (uint64_t)rand();
    return v;
#endif
}

// VirtualNET fixtures (bootstrap):
// - domain=4 uses an in-memory fixture table so nested universes and capsules can simulate network deterministically.
typedef struct {
    char* url;
    uint8_t* body;
    uint32_t body_len;
} AvmVnetEntry;

typedef struct {
    AvmVnetEntry* entries;
    uint32_t count;
} AvmVnet;

static AvmVnetEntry* avm_vnet_find(AvmVM* vm, const char* url) {
    if (!vm || !vm->vnet || !url) return NULL;
    AvmVnet* v = (AvmVnet*)vm->vnet;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].url && strcmp(v->entries[i].url, url) == 0) return &v->entries[i];
    }
    return NULL;
}

// VirtualPROC fixtures (bootstrap):
// - domain=5 uses an in-memory fixture table so nested universes and capsules can simulate subprocess calls deterministically.
// - vproc returns a deterministic exit code: fixture match if present; otherwise vm->proc_exit_code.
typedef struct {
    char* cmd;
    int32_t exit_code;
} AvmVprocEntry;

typedef struct {
    AvmVprocEntry* entries;
    uint32_t count;
} AvmVproc;

static AvmVprocEntry* avm_vproc_find(AvmVM* vm, const char* cmd) {
    if (!vm || !vm->vproc || !cmd) return NULL;
    AvmVproc* v = (AvmVproc*)vm->vproc;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].cmd && strcmp(v->entries[i].cmd, cmd) == 0) return &v->entries[i];
    }
    return NULL;
}


#include "avm_state.inc"
#include "avm_native.inc"

// Release any remaining heap allocations that are no longer reachable from VM roots.
// AVM does not have a tracing GC yet; without this, allocations that become unreachable
// during execution can accumulate across multiple `avm_run()` invocations in the same process.
static void avm_release_unreachable_allocs(AvmVM* vm) {
    if (!vm) return;
    AvmAllocHdr* h = (AvmAllocHdr*)vm->heap_allocs_head;
    while (h) {
        AvmAllocHdr* next = h->next;
        if (h->charged_size && vm->heap_used_bytes >= h->charged_size) vm->heap_used_bytes -= h->charged_size;
        else if (h->charged_size) vm->heap_used_bytes = 0;
        h->magic = 0;
        free(h);
        h = next;
    }
    vm->heap_allocs_head = NULL;
    vm->heap_used_bytes = 0;
}

AvmVM* avm_new() {
    AvmVM* vm = (AvmVM*)malloc(sizeof(AvmVM));
    vm->stack = (AvmValue*)malloc(sizeof(AvmValue) * AVM_STACK_SIZE);
    vm->sp = 0;
    vm->pc = 0;
    vm->running = 0;
    vm->prog = NULL;
    vm->fp = 0;
    vm->frame_count = 0;
    vm->allowed_native_domains = 0;
    vm->fs_allow_prefixes = NULL;
    vm->fs_allow_prefix_count = 0;
    vm->fs_backend_kind = 0;
    vm->vfs = NULL;
    vm->proc_backend_kind = 0;
    vm->vproc = NULL;
    vm->proc_exit_code = 0;
    vm->net_backend_kind = 0;
    vm->vnet = NULL;
    vm->gas_remaining = 0;
    vm->deadline_ns = 0;
    vm->cancelled = 0;
    vm->heap_budget_bytes = 0;
    vm->heap_used_bytes = 0;
    vm->heap_allocs_head = NULL;
    vm->io_budget_bytes = 0;
    vm->io_used_bytes = 0;
    vm->log_budget_bytes = 0;
    vm->log_used_bytes = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->exit_code = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    vm->record_log = NULL;
    vm->replay_log = NULL;
    vm->record_log_bytes = NULL;
    vm->replay_log_bytes = NULL;
    vm->replay_log_pos = 0;
    vm->deterministic = 0;
    vm->virtual_now_ns = 0;
    vm->virtual_step_ns = 1000ull; // 1us per executed instruction step (default; override with AVM_TIME_STEP_NS)
    vm->virtual_sleep_ns = 0;
    vm->rng_state = 0x123456789abcdef0ull;
    vm->gas_executed = 0;
    vm->pause_after_steps = 0;
    vm->paused = 0;
    vm->trace_enabled = 0;
    vm->trace_limit = 0;
    vm->trace_out = NULL;
    vm->trace_hash_enabled = 0;
    vm->trace_hash_limit = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_bytes_enabled = 0;
    vm->trace_bytes_limit = 0;
    vm->trace_budget_bytes = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
    vm->break_pcs = NULL;
    vm->break_pc_count = 0;
    for(int i=0; i<MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (!vm) return;

    // Close any open replay/record files (CLI can also close; best-effort here).
    if (vm->record_log) fclose(vm->record_log);
    if (vm->replay_log) fclose(vm->replay_log);

    // Best-effort: release heap objects reachable from VM roots (including const pool objects).
    avm_release_heap(vm);
    // Release any remaining unreachable heap allocations (leak-free teardown).
    avm_release_unreachable_allocs(vm);

    if (vm->stack) free(vm->stack);
    if (vm->break_pcs) free(vm->break_pcs);
    if (vm->fs_allow_prefixes) {
        for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
            if (vm->fs_allow_prefixes[i]) free(vm->fs_allow_prefixes[i]);
        }
        free(vm->fs_allow_prefixes);
    }
    free(vm);
}

void avm_load(AvmVM* vm, AvmProgram* prog) {
    vm->prog = prog;
    vm->pc = 0;
    vm->sp = 0;
    vm->fp = 0;
    vm->frame_count = 0;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value = avm_nil();
    vm->last_error = avm_nil();
    vm->exit_code = 0;
    vm->virtual_sleep_ns = 0;
    vm->gas_executed = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
}

static void trace_sha_u8(AvmSha256Ctx* h, uint8_t v) { avm_sha256_update(h, &v, 1); }
static void trace_sha_u16_le(AvmSha256Ctx* h, uint16_t v) {
    uint8_t b[2];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    avm_sha256_update(h, b, 2);
}
static void trace_sha_u32_le(AvmSha256Ctx* h, uint32_t v) {
    uint8_t b[4];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    b[2] = (uint8_t)((v >> 16) & 0xFFu);
    b[3] = (uint8_t)((v >> 24) & 0xFFu);
    avm_sha256_update(h, b, 4);
}

static size_t trace_insn_len(const uint8_t* code, size_t code_len, size_t pc) {
    if (!code || pc >= code_len) return 1;
    uint8_t op = code[pc];
    if (op == 0x02) return 3;                 // PUSH_CONST u16
    if (op == 0x04 || op == 0x05) return 2;   // LOAD/STORE_LOCAL u8
    if (op == 0x06 || op == 0x07) return 3;   // LOAD/STORE_GLOBAL u16
    if (op == 0x30 || op == 0x31) return 3;   // JMP/JMP_IF i16
    if (op == 0x38) return 4;                 // CALL u16 u8
    if (op == 0x3A) return 4;                 // CALL_NATIVE u16 u8
    if (op == 0x3B) return 5;                 // CALL_NATIVE2 u8 u16 u8
    if (op == 0x40 || op == 0x41) return 3;   // NEW_LIST/NEW_MAP u16
    return 1;
}

static AvmBytes* trace_bytes_new(void) {
    // Trace bytes are diagnostic data, not program heap. Do not charge to heap budget.
    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    AvmBytes* b = (AvmBytes*)avm_heap_malloc(sizeof(AvmBytes));
    avm_alloc_unbudgeted_pop(prev);
    if (!b) return NULL;
    b->data = NULL;
    b->len = 0;
    b->capacity = 0;
    return b;
}

static void trace_bytes_disable_truncated(AvmVM* vm) {
    if (!vm) return;
    vm->trace_bytes_enabled = 0;
    vm->trace_bytes_truncated = 1;
}

static int trace_bytes_can_fit(AvmVM* vm, uint64_t add) {
    if (!vm) return 0;
    if (add == 0) return 1;
    if (vm->trace_budget_bytes == 0) return 1;
    if (vm->trace_used_bytes > vm->trace_budget_bytes) return 0;
    if (add > vm->trace_budget_bytes - vm->trace_used_bytes) return 0;
    return 1;
}

static int trace_bytes_prepare(AvmVM* vm, uint64_t add) {
    if (!vm || !vm->trace_bytes_enabled) return 1;
    if (add == 0) return 1;

    if (!vm->trace_bytes) {
        vm->trace_bytes = trace_bytes_new();
        if (!vm->trace_bytes) {
            trace_bytes_disable_truncated(vm);
            return 1;
        }
    }

    if (!trace_bytes_can_fit(vm, add)) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }

    uint64_t need_u64 = (uint64_t)vm->trace_bytes->len + add;
    if (need_u64 > (uint64_t)INT32_MAX) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    // Trace bytes are diagnostic data; don't charge these reallocations to the heap budget.
    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    int ok = bytes_ensure_cap(vm->trace_bytes, (int)need_u64);
    avm_alloc_unbudgeted_pop(prev);
    if (!ok) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    return 1;
}

enum {
    TRACE_EVT_STEP = 1,
    TRACE_EVT_NATIVE2 = 2,
    TRACE_EVT_ABORT = 3
};

static int trace_begin_if_needed(AvmVM* vm) {
    if (!vm) return 0;
    int want_any = (vm->trace_hash_enabled != 0) || (vm->trace_bytes_enabled != 0);
    if (!want_any) return 1;

    if ((vm->trace_hash_enabled && vm->trace_hash_started) || (vm->trace_bytes_enabled && vm->trace_bytes)) return 1;

    const uint8_t tag[8] = { 'A','V','M','T','R','C','0','2' };

    if (vm->trace_hash_enabled && !vm->trace_hash_started) {
        avm_sha256_init(&vm->trace_hash_ctx);
        avm_sha256_update(&vm->trace_hash_ctx, tag, 8);
        vm->trace_hash_started = 1;
        vm->trace_hash_finalized = 0;
    }

    if (vm->trace_bytes_enabled && !vm->trace_bytes) {
        // Trace bytes are best-effort: never fail execution if tracing can't allocate or hits budget.
        if (!trace_bytes_prepare(vm, 8)) return 1;
        if (!vm->trace_bytes_enabled) return 1;
        int prev = 0;
        avm_alloc_unbudgeted_push(&prev);
        uint32_t p = (uint32_t)vm->trace_bytes->len;
        int ok = mem_write_bytes(vm->trace_bytes, &p, tag, 8);
        avm_alloc_unbudgeted_pop(prev);
        if (!ok) {
            trace_bytes_disable_truncated(vm);
            return 1;
        }
        vm->trace_used_bytes += 8;
    }

    return 1;
}

static void trace_hash_u8(AvmVM* vm, uint8_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u8(&vm->trace_hash_ctx, v);
}
static void trace_hash_u16(AvmVM* vm, uint16_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u16_le(&vm->trace_hash_ctx, v);
}
static void trace_hash_u32(AvmVM* vm, uint32_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u32_le(&vm->trace_hash_ctx, v);
}
static void trace_hash_bytes(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    if (data && len > 0) avm_sha256_update(&vm->trace_hash_ctx, data, len);
}

static int trace_emit_step(AvmVM* vm, int op_pc, uint8_t op) {
    if (!vm) return 0;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // STEP event encoding:
    // kind=u8(1), pc=u32, op=u8, ilen=u16, bytes[ilen]
    size_t pc = (size_t)op_pc;
    size_t ilen = trace_insn_len(vm->prog ? vm->prog->code : NULL, vm->prog ? vm->prog->code_len : 0, pc);
    if (ilen > 65535) ilen = 65535;

    // hash
    trace_hash_u8(vm, TRACE_EVT_STEP);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u8(vm, op);
    trace_hash_u16(vm, (uint16_t)ilen);
    if (vm->prog && vm->prog->code && pc + ilen <= vm->prog->code_len) trace_hash_bytes(vm, vm->prog->code + pc, ilen);
    else trace_hash_bytes(vm, &op, 1);

    // bytes
    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 1 + 2 + (uint64_t)ilen;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_STEP) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u8(vm->trace_bytes, &p, op) ||
                !mem_write_u16_le(vm->trace_bytes, &p, (uint16_t)ilen)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            if (vm->prog && vm->prog->code && pc + ilen <= vm->prog->code_len) {
                if (!mem_write_bytes(vm->trace_bytes, &p, vm->prog->code + pc, (uint32_t)ilen)) {
                    avm_alloc_unbudgeted_pop(prev);
                    trace_bytes_disable_truncated(vm);
                    return 1;
                }
            } else {
                if (!mem_write_u8(vm->trace_bytes, &p, op)) {
                    avm_alloc_unbudgeted_pop(prev);
                    trace_bytes_disable_truncated(vm);
                    return 1;
                }
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }

    return 1;
}

static int trace_emit_native2(AvmVM* vm, int op_pc, uint8_t domain, uint16_t op, uint8_t nargs) {
    if (!vm) return 0;
    if (!vm->trace_hash_enabled && !vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // NATIVE2 event encoding:
    // kind=u8(2), pc=u32, domain=u8, op=u16, nargs=u8
    trace_hash_u8(vm, TRACE_EVT_NATIVE2);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u8(vm, domain);
    trace_hash_u16(vm, op);
    trace_hash_u8(vm, nargs);

    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 1 + 2 + 1;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_NATIVE2) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u8(vm->trace_bytes, &p, domain) ||
                !mem_write_u16_le(vm->trace_bytes, &p, op) ||
                !mem_write_u8(vm->trace_bytes, &p, nargs)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }
    return 1;
}

static int trace_emit_abort(AvmVM* vm, int op_pc, uint16_t err_code) {
    if (!vm) return 0;
    if (!vm->trace_hash_enabled && !vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // ABORT event encoding:
    // kind=u8(3), pc=u32, code=u16
    trace_hash_u8(vm, TRACE_EVT_ABORT);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u16(vm, err_code);

    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 2;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_ABORT) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u16_le(vm->trace_bytes, &p, err_code)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }
    return 1;
}

void avm_run(AvmVM* vm) {
    if (!vm->prog) return;

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(vm, &prev_owner);

    vm->running = 1;
    vm->exit_code = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    uint8_t* code = vm->prog->code;
    uint64_t steps = 0;
    
    while (vm->running && vm->pc < vm->prog->code_len) {
        steps++;
        if (vm->break_pc_count > 0 && vm->break_pcs) {
            for (int bi = 0; bi < vm->break_pc_count; bi++) {
                if (vm->pc == vm->break_pcs[bi]) {
                    vm->paused = 1;
                    vm->exit_code = 2; // paused (non-error)
                    vm->running = 0;
                    break;
                }
            }
            if (!vm->running) break;
        }
        if (vm->pause_after_steps > 0) {
            vm->pause_after_steps--;
            if (vm->pause_after_steps == 0) {
                vm->paused = 1;
                vm->exit_code = 2; // paused (non-error)
                vm->running = 0;
                break;
            }
        }
        if (vm->gas_remaining > 0) {
            vm->gas_remaining--;
            if (vm->gas_remaining == 0) {
                avm_abort(vm, avm_err(AVM_ERR_BUDGET, "budget exceeded (gas)"));
                break;
            }
        }
        if (vm->cancelled) {
            avm_abort(vm, avm_err(AVM_ERR_CANCELLED, "cancelled"));
            break;
        }
        if (vm->deadline_ns > 0 && ((steps & 1023ull) == 0)) {
            uint64_t now = avm_now_ns();
            if (now != 0 && now > vm->deadline_ns) {
                avm_abort(vm, avm_err(AVM_ERR_TIMEOUT, "deadline exceeded"));
                break;
            }
        }

        // Semantic execution counter for deterministic TIME (bootstrap: 1 gas per opcode dispatch).
        vm->gas_executed++;
        int op_pc = vm->pc;
        uint8_t op = code[vm->pc++];
        // Tracing is best-effort and must never affect program semantics.
        (void)trace_emit_step(vm, op_pc, op);
        if (vm->trace_enabled && (!vm->trace_limit || vm->gas_executed <= vm->trace_limit)) {
            FILE* out = vm->trace_out ? vm->trace_out : stderr;
            fprintf(out, "TRACE pc=%d op=0x%02x %s sp=%d fp=%d depth=%d gas=%llu\n",
                op_pc,
                (unsigned)op,
                avm_op_name(op),
                vm->sp,
                vm->fp,
                vm->frame_count,
                (unsigned long long)vm->gas_executed);
        }
        // printf("PC: %d, OP: %d, SP: %d, FP: %d\n", vm->pc-1, op, vm->sp, vm->fp);
        switch (op) {
            case 0x00: // NOP
                break;
            case 0x01: // HALT
                vm->running = 0;
                break;
            case 0x02: { // PUSH_CONST u16
                if (vm->pc + 2 > vm->prog->code_len) { vm->running = 0; break; }
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < vm->prog->const_count) {
                    vm->stack[vm->sp++] = vm->prog->constants[idx];
                }
                break;
            }
            case 0x03: // POP
                if (vm->sp > 0) vm->sp--;
                break;
            case 0x04: { // LOAD_LOCAL u8
                uint8_t idx = code[vm->pc++];
                // Check bounds?
                vm->stack[vm->sp++] = vm->stack[vm->fp + idx];
                break;
            }
            case 0x05: { // STORE_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->fp + idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x06: { // LOAD_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->stack[vm->sp++] = vm->globals[idx];
                break;
            }
            case 0x07: { // STORE_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->globals[idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x10: { // ADD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT; 
                    res.as.i = a.as.i + b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x11: { // SUB
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT; 
                    res.as.i = a.as.i - b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x12: { // LT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i < b.as.i) ? 1 : 0;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x13: { // EQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    if (a.type != b.type) res.as.i = 0;
                    else if (a.type == AVM_VAL_INT) res.as.i = (a.as.i == b.as.i);
                    else if (a.type == AVM_VAL_STRING) res.as.i = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                    else res.as.i = 0;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x14: { // NEQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    if (a.type != b.type) res.as.i = 1;
                    else if (a.type == AVM_VAL_INT) res.as.i = (a.as.i != b.as.i);
                    else if (a.type == AVM_VAL_STRING) res.as.i = (strcmp((char*)a.as.p, (char*)b.as.p) != 0);
                    else res.as.i = 1;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x15: { // GT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i > b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x16: { // LTE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i <= b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x17: { // GTE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i >= b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x18: { // BITAND
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i & b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x19: { // BITOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i | b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1A: { // BITXOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i ^ b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1B: { // SHL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i << b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1C: { // SHR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i >> b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x20: { // PRINT
                if (vm->sp > 0) {
                    AvmValue v = vm->stack[--vm->sp];
                    if (v.type == AVM_VAL_INT) printf("%lld\n", v.as.i);
                    else if (v.type == AVM_VAL_FLOAT) printf("%f\n", v.as.f);
                    else if (v.type == AVM_VAL_STRING) printf("%s\n", (char*)v.as.p);
                    else if (v.type == AVM_VAL_BOOL) printf("%s\n", v.as.i ? "true" : "false");
                    else if (v.type == AVM_VAL_NIL) printf("nil\n");
                    else if (v.type == AVM_VAL_LIST) printf("[list]\n");
                    else if (v.type == AVM_VAL_MAP) printf("{map}\n");
                    else if (v.type == AVM_VAL_BYTES) printf("<bytes len=%d>\n", v.as.b ? v.as.b->len : 0);
                    else printf("?\n");
                }
                break;
            }
            case 0x30: { // JMP i16
                int16_t off = code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                vm->pc += off;
                break;
            }
            case 0x31: { // JMP_IF i16
                int16_t off = code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                if (vm->sp > 0) {
                    AvmValue cond = vm->stack[--vm->sp];
                    int truthy = 0;
                    if (cond.type == AVM_VAL_INT && cond.as.i != 0) truthy = 1;
                    else if (cond.type == AVM_VAL_BOOL && cond.as.i != 0) truthy = 1;
                    
                    if (truthy) vm->pc += off;
                }
                break;
            }
            case 0x38: { // CALL u16_addr u8_nargs
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                
                if (vm->frame_count > 65000) {
                    printf("CALL addr: %d, depth: %d\n", addr, vm->frame_count);
                }
                
                if (vm->frame_count >= MAX_FRAMES) {
                    printf("Stack overflow (depth %d)\n", vm->frame_count);
                    vm->running = 0;
                    break;
                }
                
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frame_count++;
                
                vm->fp = vm->sp - nargs;
                vm->pc = addr;
                break;
            }
            case 0x39: { // RET
                if (vm->frame_count == 0) {
                    vm->running = 0;
                    break;
                }
                
                AvmValue ret_val;
                ret_val.type = AVM_VAL_NIL;
                if (vm->sp > vm->fp) {
                     ret_val = vm->stack[--vm->sp];
                }
                
                vm->frame_count--;
                vm->pc = vm->frames[vm->frame_count].return_pc;
                int old_fp = vm->frames[vm->frame_count].fp;
                
                vm->sp = vm->fp;
                vm->fp = old_fp;
                
                vm->stack[vm->sp++] = ret_val;
                break;
            }
            case 0x3A: { // CALL_NATIVE
                uint16_t id = code[vm->pc++];
                id |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                
                AvmValue args[16];
                for(int i=nargs-1; i>=0; i--) {
                    args[i] = vm->stack[--vm->sp];
                }
                
                // Legacy CALL_NATIVE is mapped through the domain/op capability system to prevent bypass.
                uint8_t domain = 0;
                uint16_t op = 0;
                avm_legacy_native_to_domop(id, &domain, &op);
                (void)trace_emit_native2(vm, op_pc, domain, op, nargs);

                AvmValue res = avm_call_native2(vm, domain, op, args, nargs);
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x3B: { // CALL_NATIVE2: u8 domain, u16 op, u8 nargs
                uint8_t domain = code[vm->pc++];
                uint16_t op = code[vm->pc++];
                op |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                (void)trace_emit_native2(vm, op_pc, domain, op, nargs);

                AvmValue args[16];
                for (int i = nargs - 1; i >= 0; i--) {
                    args[i] = vm->stack[--vm->sp];
                }

                AvmValue res = avm_call_native2(vm, domain, op, args, nargs);
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x40: { // NEW_LIST u16_count
                uint16_t count = code[vm->pc++];
                count |= (uint16_t)code[vm->pc++] << 8;
                
                AvmList* list = (AvmList*)avm_heap_malloc(sizeof(AvmList));
                if (!list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                list->count = count;
                list->capacity = (int)count + 8;
                list->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)list->capacity);
                if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                
                for(int i=count-1; i>=0; i--) {
                    list->items[i] = vm->stack[--vm->sp];
                }
                
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x41: { // NEW_MAP u16_count
                uint16_t count = code[vm->pc++];
                count |= (uint16_t)code[vm->pc++] << 8;
                
                AvmMap* map = (AvmMap*)avm_heap_malloc(sizeof(AvmMap));
                if (!map) { avm_abort(vm, avm_alloc_fail_value()); break; }
                map->count = count;
                map->capacity = (int)count + 8;
                map->keys = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)map->capacity);
                map->values = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)map->capacity);
                if (!map->keys || !map->values) {
                    if (map->keys) avm_heap_free(map->keys);
                    if (map->values) avm_heap_free(map->values);
                    avm_heap_free(map);
                    avm_abort(vm, avm_alloc_fail_value());
                    break;
                }
                
                for(int i=count-1; i>=0; i--) {
                    map->values[i] = vm->stack[--vm->sp];
                    map->keys[i] = vm->stack[--vm->sp];
                }
                
                AvmValue res;
                res.type = AVM_VAL_MAP;
                res.as.m = map;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x42: { // GET_INDEX
                if (vm->sp >= 2) {
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_NIL;
                    
                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            res = obj.as.l->items[i];
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        for(int i=0; i<obj.as.m->count; i++) {
                            AvmValue k = obj.as.m->keys[i];
                            int match = 0;
                            if (k.type == key.type) {
                                if (k.type == AVM_VAL_INT) match = (k.as.i == key.as.i);
                                else if (k.type == AVM_VAL_STRING) match = (strcmp((char*)k.as.p, (char*)key.as.p) == 0);
                            }
                            if (match) {
                                res = obj.as.m->values[i];
                                break;
                            }
                        }
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x43: { // SET_INDEX
                if (vm->sp >= 3) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    
                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            obj.as.l->items[i] = val;
                        } else if (i == obj.as.l->count) {
                            if (obj.as.l->count < obj.as.l->capacity) {
                                obj.as.l->items[obj.as.l->count++] = val;
                            }
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        int found = 0;
                        for(int i=0; i<obj.as.m->count; i++) {
                            AvmValue k = obj.as.m->keys[i];
                            int match = 0;
                            if (k.type == key.type) {
                                if (k.type == AVM_VAL_INT) match = (k.as.i == key.as.i);
                                else if (k.type == AVM_VAL_STRING) match = (strcmp((char*)k.as.p, (char*)key.as.p) == 0);
                            }
                            if (match) {
                                obj.as.m->values[i] = val;
                                found = 1;
                                break;
                            }
                        }
                        if (!found && obj.as.m->count < obj.as.m->capacity) {
                            obj.as.m->keys[obj.as.m->count] = key;
                            obj.as.m->values[obj.as.m->count] = val;
                            obj.as.m->count++;
                        }
                    }
                }
                break;
            }
            default:
                printf("Unknown opcode: %d\n", op);
                avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "unknown opcode"));
                break;
        }
    }

    if (vm->trace_hash_enabled && vm->trace_hash_started && !vm->trace_hash_finalized) {
        avm_sha256_final(&vm->trace_hash_ctx, vm->trace_hash_out);
        vm->trace_hash_finalized = 1;
    }

    avm_alloc_owner_pop(prev_owner);
}

int avm_trace_hash(AvmVM* vm, uint8_t out[32]) {
    if (!vm || !out) return 0;
    if (!vm->trace_hash_finalized) return 0;
    memcpy(out, vm->trace_hash_out, 32);
    return 1;
}

AvmBytes* avm_trace_bytes(AvmVM* vm) {
    if (!vm) return NULL;
    return vm->trace_bytes;
}

int avm_net_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !data) return 0;
    if (len < 12) return 0; // magic + count
    if (len > (size_t)INT32_MAX) return 0;

    AvmBytes in;
    in.data = (uint8_t*)data;
    in.len = (int)len;
    in.capacity = (int)len;

    uint32_t pos = 0;
    uint8_t magic[8];
    if (!mem_read_bytes(&in, &pos, magic, 8)) return 0;
    const uint8_t want[8] = {'A','V','M','N','E','T','0','1'};
    if (memcmp(magic, want, 8) != 0) return 0;

    uint32_t count = 0;
    if (!mem_read_u32_le(&in, &pos, &count)) return 0;
    if (count > 1000000u) return 0; // sanity cap (rolling)

    AvmVnet* v = (AvmVnet*)avm_heap_malloc(sizeof(AvmVnet));
    if (!v) return 0;
    v->entries = NULL;
    v->count = count;

    if (count > 0) {
        if (count > (uint32_t)(SIZE_MAX / sizeof(AvmVnetEntry))) return 0;
        v->entries = (AvmVnetEntry*)avm_heap_malloc(sizeof(AvmVnetEntry) * (size_t)count);
        if (!v->entries) return 0;
        for (uint32_t i = 0; i < count; i++) {
            v->entries[i].url = NULL;
            v->entries[i].body = NULL;
            v->entries[i].body_len = 0;
        }
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t url_len = 0;
        if (!mem_read_u32_le(&in, &pos, &url_len)) return 0;
        if ((uint64_t)pos + (uint64_t)url_len > (uint64_t)in.len) return 0;
        char* url = (char*)avm_heap_malloc((size_t)url_len + 1);
        if (!url) return 0;
        if (url_len > 0) memcpy(url, in.data + pos, url_len);
        url[url_len] = 0;
        pos += url_len;

        uint32_t body_len = 0;
        if (!mem_read_u32_le(&in, &pos, &body_len)) return 0;
        if ((uint64_t)pos + (uint64_t)body_len > (uint64_t)in.len) return 0;
        uint8_t* body = NULL;
        if (body_len > 0) {
            body = (uint8_t*)avm_heap_malloc((size_t)body_len);
            if (!body) return 0;
            memcpy(body, in.data + pos, body_len);
        }
        pos += body_len;

        v->entries[i].url = url;
        v->entries[i].body = body;
        v->entries[i].body_len = body_len;
    }

    vm->vnet = v;
    return 1;
}

int avm_proc_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !data) return 0;
    if (len < 12) return 0; // magic + count
    if (len > (size_t)INT32_MAX) return 0;

    AvmBytes in;
    in.data = (uint8_t*)data;
    in.len = (int)len;
    in.capacity = (int)len;

    uint32_t pos = 0;
    uint8_t magic[8];
    if (!mem_read_bytes(&in, &pos, magic, 8)) return 0;
    const uint8_t want[8] = {'A','V','M','P','R','C','0','1'};
    if (memcmp(magic, want, 8) != 0) return 0;

    uint32_t count = 0;
    if (!mem_read_u32_le(&in, &pos, &count)) return 0;
    if (count > 1000000u) return 0; // sanity cap (rolling)

    AvmVproc* v = (AvmVproc*)avm_heap_malloc(sizeof(AvmVproc));
    if (!v) return 0;
    v->entries = NULL;
    v->count = count;

    if (count > 0) {
        if (count > (uint32_t)(SIZE_MAX / sizeof(AvmVprocEntry))) return 0;
        v->entries = (AvmVprocEntry*)avm_heap_malloc(sizeof(AvmVprocEntry) * (size_t)count);
        if (!v->entries) return 0;
        for (uint32_t i = 0; i < count; i++) {
            v->entries[i].cmd = NULL;
            v->entries[i].exit_code = 0;
        }
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t cmd_len = 0;
        if (!mem_read_u32_le(&in, &pos, &cmd_len)) return 0;
        if ((uint64_t)pos + (uint64_t)cmd_len > (uint64_t)in.len) return 0;
        char* cmd = (char*)avm_heap_malloc((size_t)cmd_len + 1);
        if (!cmd) return 0;
        if (cmd_len > 0) memcpy(cmd, in.data + pos, cmd_len);
        cmd[cmd_len] = 0;
        pos += cmd_len;

        uint32_t exit_u32 = 0;
        if (!mem_read_u32_le(&in, &pos, &exit_u32)) return 0;
        int32_t exit_i32 = (int32_t)exit_u32;

        v->entries[i].cmd = cmd;
        v->entries[i].exit_code = exit_i32;
    }

    if (pos != (uint32_t)in.len) return 0;
    vm->vproc = v;
    return 1;
}
