#include "avm.h"
#include "sha256.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <stdint.h>
#include <unistd.h>

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
    char* d = malloc(strlen(s) + 1);
    strcpy(d, s);
    return d;
}

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
    AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
    if (!b) return avm_nil();
    b->len = len;
    b->capacity = len;
    b->data = NULL;
    if (len > 0) {
        b->data = (uint8_t*)malloc((size_t)len);
        if (!b->data) { free(b); return avm_nil(); }
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
    AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
    map->count = 3;
    map->capacity = 8;
    map->keys = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);
    map->values = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);

    map->keys[0] = avm_string("__err");
    map->values[0] = avm_bool(1);

    map->keys[1] = avm_string("code");
    map->values[1] = avm_int(code);

    map->keys[2] = avm_string("msg");
    map->values[2] = avm_string(msg ? msg : "");

    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;
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
    uint8_t* nd = (uint8_t*)realloc(b->data, (size_t)new_cap);
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

typedef struct {
    void** ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP,4=BYTES
    uint32_t* aux;
    uint32_t count;
    uint32_t cap;
} ObjTable;

static void collect_value_objects(ObjTable* t, AvmValue v);

static void objtable_free(ObjTable* t) {
    if (!t) return;
    if (t->ptrs) free(t->ptrs);
    if (t->types) free(t->types);
    if (t->aux) free(t->aux);
    t->ptrs = NULL;
    t->types = NULL;
    t->aux = NULL;
    t->count = 0;
    t->cap = 0;
}

static void avm_free_object_table_objects(ObjTable* t) {
    if (!t) return;
    for (uint32_t id = 0; id < t->count; id++) {
        uint8_t ty = t->types[id];
        void* ptr = t->ptrs[id];
        if (!ptr) continue;
        if (ty == 1) { // STRING (char*)
            free(ptr);
        } else if (ty == 2) { // LIST
            AvmList* list = (AvmList*)ptr;
            if (list->items) free(list->items);
            free(list);
        } else if (ty == 3) { // MAP
            AvmMap* map = (AvmMap*)ptr;
            if (map->keys) free(map->keys);
            if (map->values) free(map->values);
            free(map);
        } else if (ty == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)ptr;
            if (b->data) free(b->data);
            free(b);
        }
        t->ptrs[id] = NULL;
    }
}

static void avm_release_heap(AvmVM* vm) {
    if (!vm) return;

    ObjTable objs = {0};

    // VM roots
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    // Program constants are part of VM semantics (PUSH_CONST copies references).
    if (vm->prog && vm->prog->constants) {
        for (size_t i = 0; i < vm->prog->const_count; i++) {
            collect_value_objects(&objs, vm->prog->constants[i]);
        }
    }

    // Record/replay logs and buffers (owned by this VM instance in the CLI path).
    if (vm->record_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes;
        collect_value_objects(&objs, v);
    }
    if (vm->replay_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes;
        collect_value_objects(&objs, v);
    }

    avm_free_object_table_objects(&objs);
    objtable_free(&objs);
}

static int objtable_find(ObjTable* t, void* ptr) {
    if (!t || !ptr) return -1;
    for (uint32_t i = 0; i < t->count; i++) {
        if (t->ptrs[i] == ptr) return (int)i;
    }
    return -1;
}

static uint32_t objtable_add(ObjTable* t, void* ptr, uint8_t type, uint32_t aux) {
    if (t->count >= t->cap) {
        uint32_t new_cap = t->cap ? t->cap * 2 : 64;
        void** np = (void**)realloc(t->ptrs, sizeof(void*) * new_cap);
        uint8_t* nt = (uint8_t*)realloc(t->types, sizeof(uint8_t) * new_cap);
        uint32_t* na = (uint32_t*)realloc(t->aux, sizeof(uint32_t) * new_cap);
        if (!np || !nt || !na) {
            // best effort; crash is acceptable for now in snapshotting path
            fprintf(stderr, "snapshot: out of memory\n");
            exit(1);
        }
        t->ptrs = np;
        t->types = nt;
        t->aux = na;
        t->cap = new_cap;
    }
    uint32_t id = t->count++;
    t->ptrs[id] = ptr;
    t->types[id] = type;
    t->aux[id] = aux;
    return id;
}

static void collect_value_objects(ObjTable* t, AvmValue v);

static void collect_list_objects(ObjTable* t, AvmList* list) {
    if (!list) return;
    for (int i = 0; i < list->count; i++) {
        collect_value_objects(t, list->items[i]);
    }
}

static void collect_map_objects(ObjTable* t, AvmMap* map) {
    if (!map) return;
    for (int i = 0; i < map->count; i++) {
        collect_value_objects(t, map->keys[i]);
        collect_value_objects(t, map->values[i]);
    }
}

static void collect_value_objects(ObjTable* t, AvmValue v) {
    if (v.type == AVM_VAL_STRING && v.as.p) {
        if (objtable_find(t, v.as.p) >= 0) return;
        uint32_t len = (uint32_t)strlen((char*)v.as.p);
        objtable_add(t, v.as.p, 1, len);
        return;
    }
    if (v.type == AVM_VAL_LIST && v.as.l) {
        if (objtable_find(t, v.as.l) >= 0) return;
        uint32_t cnt = (uint32_t)v.as.l->count;
        objtable_add(t, v.as.l, 2, cnt);
        collect_list_objects(t, v.as.l);
        return;
    }
    if (v.type == AVM_VAL_MAP && v.as.m) {
        if (objtable_find(t, v.as.m) >= 0) return;
        uint32_t cnt = (uint32_t)v.as.m->count;
        objtable_add(t, v.as.m, 3, cnt);
        collect_map_objects(t, v.as.m);
        return;
    }
    if (v.type == AVM_VAL_BYTES && v.as.b) {
        if (objtable_find(t, v.as.b) >= 0) return;
        uint32_t len = (uint32_t)v.as.b->len;
        objtable_add(t, v.as.b, 4, len);
        return;
    }
}

static int encode_value(FILE* f, ObjTable* objs, AvmValue v) {
    uint8_t tag = 0;
    uint64_t payload = 0;

    if (v.type == AVM_VAL_NIL) {
        tag = 0;
    } else if (v.type == AVM_VAL_INT) {
        tag = 1;
        payload = (uint64_t)v.as.i;
    } else if (v.type == AVM_VAL_FLOAT) {
        tag = 2;
        uint64_t bits = 0;
        memcpy(&bits, &v.as.f, sizeof(bits));
        payload = bits;
    } else if (v.type == AVM_VAL_BOOL) {
        tag = 3;
        payload = v.as.i ? 1 : 0;
    } else if (v.type == AVM_VAL_STRING) {
        tag = 4;
        int id = objtable_find(objs, v.as.p);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_LIST) {
        tag = 4;
        int id = objtable_find(objs, v.as.l);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_MAP) {
        tag = 4;
        int id = objtable_find(objs, v.as.m);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_BYTES) {
        tag = 4;
        int id = objtable_find(objs, v.as.b);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else {
        // Unknown value type in bootstrap: encode as NIL.
        tag = 0;
        payload = 0;
    }

    if (!write_u8(f, tag)) return 0;
    if (!write_u64_le(f, payload)) return 0;
    return 1;
}

static int encode_value_mem(AvmBytes* out, uint32_t* pos, ObjTable* objs, AvmValue v) {
    uint8_t tag = 0;
    uint64_t payload = 0;

    if (v.type == AVM_VAL_NIL) {
        tag = 0;
    } else if (v.type == AVM_VAL_INT) {
        tag = 1;
        payload = (uint64_t)v.as.i;
    } else if (v.type == AVM_VAL_FLOAT) {
        tag = 2;
        uint64_t bits = 0;
        memcpy(&bits, &v.as.f, sizeof(bits));
        payload = bits;
    } else if (v.type == AVM_VAL_BOOL) {
        tag = 3;
        payload = v.as.i ? 1 : 0;
    } else if (v.type == AVM_VAL_STRING) {
        tag = 4;
        int id = objtable_find(objs, v.as.p);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_LIST) {
        tag = 4;
        int id = objtable_find(objs, v.as.l);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_MAP) {
        tag = 4;
        int id = objtable_find(objs, v.as.m);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_BYTES) {
        tag = 4;
        int id = objtable_find(objs, v.as.b);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else {
        tag = 0;
        payload = 0;
    }

    if (!mem_write_u8(out, pos, tag)) return 0;
    if (!mem_write_u64_le(out, pos, payload)) return 0;
    return 1;
}

static int decode_value_mem(const AvmBytes* in, uint32_t* pos, const uint8_t* obj_types, void* const* obj_ptrs, uint32_t obj_count, AvmValue* out) {
    uint8_t tag = 0;
    uint64_t payload = 0;
    if (!mem_read_u8(in, pos, &tag)) return 0;
    if (!mem_read_u64_le(in, pos, &payload)) return 0;

    if (tag == 0) { out->type = AVM_VAL_NIL; out->as.i = 0; return 1; }
    if (tag == 1) { out->type = AVM_VAL_INT; out->as.i = (int64_t)payload; return 1; }
    if (tag == 2) { out->type = AVM_VAL_FLOAT; double fval = 0; memcpy(&fval, &payload, sizeof(fval)); out->as.f = fval; return 1; }
    if (tag == 3) { out->type = AVM_VAL_BOOL; out->as.i = (payload != 0) ? 1 : 0; return 1; }
    if (tag == 4) {
        if (payload >= obj_count) return 0;
        uint32_t id = (uint32_t)payload;
        uint8_t ot = obj_types[id];
        if (ot == 1) { out->type = AVM_VAL_STRING; out->as.p = obj_ptrs[id]; return 1; }
        if (ot == 2) { out->type = AVM_VAL_LIST; out->as.l = (AvmList*)obj_ptrs[id]; return 1; }
        if (ot == 3) { out->type = AVM_VAL_MAP; out->as.m = (AvmMap*)obj_ptrs[id]; return 1; }
        if (ot == 4) { out->type = AVM_VAL_BYTES; out->as.b = (AvmBytes*)obj_ptrs[id]; return 1; }
        return 0;
    }
    return 0;
}

static void sha_u8(AvmSha256Ctx* h, uint8_t v) { avm_sha256_update(h, &v, 1); }
static void sha_u32_le(AvmSha256Ctx* h, uint32_t v) {
    uint8_t b[4];
    for (int i = 0; i < 4; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    avm_sha256_update(h, b, 4);
}
static void sha_u64_le(AvmSha256Ctx* h, uint64_t v) {
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    avm_sha256_update(h, b, 8);
}

static int encode_value_for_hash(AvmSha256Ctx* h, ObjTable* objs, AvmValue v) {
    uint8_t tag = 0;
    uint64_t payload = 0;

    if (v.type == AVM_VAL_NIL) {
        tag = 0;
    } else if (v.type == AVM_VAL_INT) {
        tag = 1;
        payload = (uint64_t)v.as.i;
    } else if (v.type == AVM_VAL_FLOAT) {
        tag = 2;
        uint64_t bits = 0;
        memcpy(&bits, &v.as.f, sizeof(bits));
        payload = bits;
    } else if (v.type == AVM_VAL_BOOL) {
        tag = 3;
        payload = v.as.i ? 1 : 0;
    } else if (v.type == AVM_VAL_STRING) {
        tag = 4;
        int id = objtable_find(objs, v.as.p);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_LIST) {
        tag = 4;
        int id = objtable_find(objs, v.as.l);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_MAP) {
        tag = 4;
        int id = objtable_find(objs, v.as.m);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_BYTES) {
        tag = 4;
        int id = objtable_find(objs, v.as.b);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else {
        tag = 0;
        payload = 0;
    }

    sha_u8(h, tag);
    sha_u64_le(h, payload);
    return 1;
}

typedef struct {
    uint8_t* bytes;
    uint32_t len;
} KeyBytes;

static int key_bytes_cmp(const void* a, const void* b) {
    const KeyBytes* ka = (const KeyBytes*)a;
    const KeyBytes* kb = (const KeyBytes*)b;
    uint32_t min = ka->len < kb->len ? ka->len : kb->len;
    int r = memcmp(ka->bytes, kb->bytes, min);
    if (r != 0) return r;
    if (ka->len < kb->len) return -1;
    if (ka->len > kb->len) return 1;
    return 0;
}

static int encode_value_bytes(ObjTable* objs, AvmValue v, uint8_t out[9]) {
    uint8_t tag = 0;
    uint64_t payload = 0;

    if (v.type == AVM_VAL_NIL) { tag = 0; payload = 0; }
    else if (v.type == AVM_VAL_INT) { tag = 1; payload = (uint64_t)v.as.i; }
    else if (v.type == AVM_VAL_FLOAT) { tag = 2; memcpy(&payload, &v.as.f, sizeof(payload)); }
    else if (v.type == AVM_VAL_BOOL) { tag = 3; payload = v.as.i ? 1 : 0; }
    else if (v.type == AVM_VAL_STRING) { tag = 4; int id = objtable_find(objs, v.as.p); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_LIST) { tag = 4; int id = objtable_find(objs, v.as.l); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_MAP) { tag = 4; int id = objtable_find(objs, v.as.m); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_BYTES) { tag = 4; int id = objtable_find(objs, v.as.b); if (id < 0) return 0; payload = (uint64_t)id; }
    else { tag = 0; payload = 0; }

    out[0] = tag;
    for (int i = 0; i < 8; i++) out[1 + i] = (uint8_t)((payload >> (8 * i)) & 0xFF);
    return 1;
}

static void sha_u16_le(AvmSha256Ctx* h, uint16_t v) {
    uint8_t b[2];
    b[0] = (uint8_t)(v & 0xFF);
    b[1] = (uint8_t)((v >> 8) & 0xFF);
    avm_sha256_update(h, b, 2);
}

static int decode_value(FILE* f, uint8_t* obj_types, void** obj_ptrs, uint32_t obj_count, AvmValue* out);

static int avm_value_hash(AvmValue v, uint8_t out[32]) {
    ObjTable objs = {0};
    collect_value_objects(&objs, v);

    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = {'A','V','M','V','A','L','H','1'};
    avm_sha256_update(&h, tag, 8);

    sha_u32_le(&h, objs.count);

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        sha_u8(&h, t);
        sha_u32_le(&h, aux);

        if (t == 1) { // STRING
            const uint8_t* s = (const uint8_t*)objs.ptrs[id];
            if (aux > 0) avm_sha256_update(&h, s, aux);
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, list->items[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 3) { // MAP (canonicalize by key)
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (aux == 0) continue;

            KeyBytes* keys = (KeyBytes*)malloc(sizeof(KeyBytes) * aux);
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * aux);
            if (!keys || !order) { free(keys); free(order); objtable_free(&objs); return 0; }

            for (uint32_t i = 0; i < aux; i++) {
                uint8_t* kb = (uint8_t*)malloc(9);
                if (!kb) { free(keys); free(order); objtable_free(&objs); return 0; }
                if (!encode_value_bytes(&objs, map->keys[i], kb)) { free(kb); free(keys); free(order); objtable_free(&objs); return 0; }
                keys[i].bytes = kb;
                keys[i].len = 9;
                order[i] = i;
            }

            typedef struct { KeyBytes k; uint32_t idx; } KeyIdx;
            KeyIdx* arr = (KeyIdx*)malloc(sizeof(KeyIdx) * aux);
            if (!arr) { for (uint32_t i=0;i<aux;i++) free(keys[i].bytes); free(keys); free(order); objtable_free(&objs); return 0; }
            for (uint32_t i=0;i<aux;i++) { arr[i].k = keys[i]; arr[i].idx = order[i]; }
            qsort(arr, aux, sizeof(KeyIdx), (int(*)(const void*,const void*))key_bytes_cmp);

            for (uint32_t i = 0; i < aux; i++) {
                uint32_t idx = arr[i].idx;
                if (!encode_value_for_hash(&h, &objs, map->keys[idx])) { objtable_free(&objs); return 0; }
                if (!encode_value_for_hash(&h, &objs, map->values[idx])) { objtable_free(&objs); return 0; }
            }

            for (uint32_t i = 0; i < aux; i++) free(keys[i].bytes);
            free(arr);
            free(keys);
            free(order);
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { objtable_free(&objs); return 0; }
            if (aux > 0) avm_sha256_update(&h, b->data, aux);
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    if (!encode_value_for_hash(&h, &objs, v)) { objtable_free(&objs); return 0; }

    avm_sha256_final(&h, out);
    objtable_free(&objs);
    return 1;
}

static int avm_args_hash(uint8_t domain, uint16_t op, AvmValue* args, int nargs, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = {'A','V','M','A','R','G','S','1'};
    avm_sha256_update(&h, tag, 8);
    sha_u8(&h, domain);
    sha_u16_le(&h, op);
    sha_u8(&h, (uint8_t)(nargs & 0xFF));

    for (int i = 0; i < nargs; i++) {
        uint8_t vh[32];
        if (!avm_value_hash(args[i], vh)) return 0;
        avm_sha256_update(&h, vh, 32);
    }

    avm_sha256_final(&h, out);
    return 1;
}

static int rr_write_u16_le(FILE* f, uint16_t v) {
    uint8_t b[2];
    b[0] = (uint8_t)(v & 0xFF);
    b[1] = (uint8_t)((v >> 8) & 0xFF);
    return fwrite(b, 1, 2, f) == 2;
}

static int rr_read_u16_le(FILE* f, uint16_t* out) {
    uint8_t b[2];
    if (fread(b, 1, 2, f) != 2) return 0;
    *out = (uint16_t)b[0] | ((uint16_t)b[1] << 8);
    return 1;
}

static int rr_write_u32_le(FILE* f, uint32_t v) {
    uint8_t b[4];
    b[0] = (uint8_t)(v & 0xFF);
    b[1] = (uint8_t)((v >> 8) & 0xFF);
    b[2] = (uint8_t)((v >> 16) & 0xFF);
    b[3] = (uint8_t)((v >> 24) & 0xFF);
    return fwrite(b, 1, 4, f) == 4;
}

static int rr_read_u32_le(FILE* f, uint32_t* out) {
    uint8_t b[4];
    if (fread(b, 1, 4, f) != 4) return 0;
    *out = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    return 1;
}

static int rr_write_bytes(FILE* f, const uint8_t* data, size_t len) {
    if (len == 0) return 1;
    return fwrite(data, 1, len, f) == len;
}

static int rr_read_bytes(FILE* f, uint8_t* data, size_t len) {
    if (len == 0) return 1;
    return fread(data, 1, len, f) == len;
}

static int rr_write_value(FILE* f, AvmValue v) {
    ObjTable objs = {0};
    collect_value_objects(&objs, v);

    if (!rr_write_u32_le(f, objs.count)) { objtable_free(&objs); return 0; }

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        if (fwrite(&t, 1, 1, f) != 1) { objtable_free(&objs); return 0; }
        if (!rr_write_u32_le(f, aux)) { objtable_free(&objs); return 0; }

        if (t == 1) { // STRING
            if (aux > 0) {
                if (fwrite(objs.ptrs[id], 1, aux, f) != aux) { objtable_free(&objs); return 0; }
            }
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, list->items[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 3) { // MAP
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (!map || (uint32_t)map->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, map->keys[i])) { objtable_free(&objs); return 0; }
                if (!encode_value(f, &objs, map->values[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { objtable_free(&objs); return 0; }
            if (aux > 0) {
                if (fwrite(b->data, 1, aux, f) != aux) { objtable_free(&objs); return 0; }
            }
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    int ok = encode_value(f, &objs, v);
    objtable_free(&objs);
    return ok;
}

static int rr_read_value(FILE* f, AvmValue* out) {
    uint32_t obj_count = 0;
    if (!rr_read_u32_le(f, &obj_count)) return 0;
    if (obj_count > 1000000) return 0;

    uint8_t* obj_types = NULL;
    uint32_t* obj_aux = NULL;
    uint64_t* payload_off = NULL;
    void** obj_ptrs = NULL;
    if (obj_count > 0) {
        obj_types = (uint8_t*)calloc(obj_count, 1);
        obj_aux = (uint32_t*)calloc(obj_count, sizeof(uint32_t));
        payload_off = (uint64_t*)calloc(obj_count, sizeof(uint64_t));
        obj_ptrs = (void**)calloc(obj_count, sizeof(void*));
        if (!obj_types || !obj_aux || !payload_off || !obj_ptrs) {
            free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
            return 0;
        }
    }

    int ok = 1;

    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        if (fread(&t, 1, 1, f) != 1) { ok = 0; break; }
        uint32_t aux = 0;
        if (!rr_read_u32_le(f, &aux)) { ok = 0; break; }

        obj_types[id] = t;
        obj_aux[id] = aux;
        payload_off[id] = (uint64_t)ftell(f);

        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 4) payload_len = aux;
        else { ok = 0; break; }

        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    long end_of_object_table = ftell(f);
    if (!ok) {
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            char* s = (char*)malloc((size_t)aux + 1);
            if (!s) { ok = 0; break; }
            s[aux] = 0;
            obj_ptrs[id] = s;
        } else if (t == 2) {
            AvmList* list = (AvmList*)malloc(sizeof(AvmList));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
            if (!map) { ok = 0; break; }
            map->count = (int)aux;
            map->capacity = (int)aux;
            map->keys = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            map->values = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if ((!map->keys || !map->values) && aux > 0) {
                if (map->keys) free(map->keys);
                if (map->values) free(map->values);
                free(map);
                ok = 0;
                break;
            }
            obj_ptrs[id] = map;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { ok = 0; break; }
            b->len = (int)aux;
            b->capacity = (int)aux;
            b->data = NULL;
            if (aux > 0) {
                b->data = (uint8_t*)malloc((size_t)aux);
                if (!b->data) { free(b); ok = 0; break; }
            }
            obj_ptrs[id] = b;
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        for (uint32_t i = 0; i < obj_count; i++) if (obj_ptrs[i]) free(obj_ptrs[i]);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    for (uint32_t id = 0; id < obj_count; id++) {
        if (fseek(f, (long)payload_off[id], SEEK_SET) != 0) { ok = 0; break; }
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            if (aux > 0) {
                if (fread(obj_ptrs[id], 1, aux, f) != aux) { ok = 0; break; }
            }
            ((char*)obj_ptrs[id])[aux] = 0;
        } else if (t == 2) {
            AvmList* list = (AvmList*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->keys[i])) { ok = 0; break; }
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->values[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)obj_ptrs[id];
            if (!b || (uint32_t)b->len != aux) { ok = 0; break; }
            if (aux > 0) {
                if (fread(b->data, 1, aux, f) != aux) { ok = 0; break; }
            }
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    if (fseek(f, end_of_object_table, SEEK_SET) != 0) { free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 0; }

    AvmValue v;
    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 0; }
    *out = v;

    // NOTE: allocated objects are intentionally leaked for now (bootstrap AVM behavior).
    free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
    return 1;
}

static int rr_write_value_mem(AvmBytes* out, uint32_t* pos, AvmValue v) {
    ObjTable objs = {0};
    collect_value_objects(&objs, v);

    if (!mem_write_u32_le(out, pos, objs.count)) { objtable_free(&objs); return 0; }

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        if (!mem_write_u8(out, pos, t)) { objtable_free(&objs); return 0; }
        if (!mem_write_u32_le(out, pos, aux)) { objtable_free(&objs); return 0; }

        if (t == 1) { // STRING
            if (aux > 0) {
                if (!mem_write_bytes(out, pos, (const uint8_t*)objs.ptrs[id], aux)) { objtable_free(&objs); return 0; }
            }
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_mem(out, pos, &objs, list->items[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 3) { // MAP
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (!map || (uint32_t)map->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_mem(out, pos, &objs, map->keys[i])) { objtable_free(&objs); return 0; }
                if (!encode_value_mem(out, pos, &objs, map->values[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { objtable_free(&objs); return 0; }
            if (aux > 0) {
                if (!mem_write_bytes(out, pos, b->data, aux)) { objtable_free(&objs); return 0; }
            }
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    int ok = encode_value_mem(out, pos, &objs, v);
    objtable_free(&objs);
    return ok;
}

static int rr_read_value_mem(const AvmBytes* in, uint32_t* pos, AvmValue* out) {
    uint32_t obj_count = 0;
    if (!mem_read_u32_le(in, pos, &obj_count)) return 0;
    if (obj_count > 1000000) return 0;

    uint8_t* obj_types = NULL;
    uint32_t* obj_aux = NULL;
    uint32_t* payload_off = NULL;
    void** obj_ptrs = NULL;

    if (obj_count > 0) {
        obj_types = (uint8_t*)calloc(obj_count, 1);
        obj_aux = (uint32_t*)calloc(obj_count, sizeof(uint32_t));
        payload_off = (uint32_t*)calloc(obj_count, sizeof(uint32_t));
        obj_ptrs = (void**)calloc(obj_count, sizeof(void*));
        if (!obj_types || !obj_aux || !payload_off || !obj_ptrs) {
            free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
            return 0;
        }
    }

    int ok = 1;
    uint32_t after_headers_pos = 0;

    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        uint32_t aux = 0;
        if (!mem_read_u8(in, pos, &t)) { ok = 0; break; }
        if (!mem_read_u32_le(in, pos, &aux)) { ok = 0; break; }
        obj_types[id] = t;
        obj_aux[id] = aux;
        payload_off[id] = *pos;

        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 4) payload_len = aux;
        else { ok = 0; break; }

        if ((uint64_t)(*pos) + payload_len > (uint64_t)in->len) { ok = 0; break; }
        *pos += (uint32_t)payload_len;
    }
    after_headers_pos = *pos;

    if (!ok) {
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            char* s = (char*)malloc((size_t)aux + 1);
            if (!s) { ok = 0; break; }
            s[aux] = 0;
            obj_ptrs[id] = s;
        } else if (t == 2) {
            AvmList* list = (AvmList*)malloc(sizeof(AvmList));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
            if (!map) { ok = 0; break; }
            map->count = (int)aux;
            map->capacity = (int)aux;
            map->keys = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            map->values = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if ((!map->keys || !map->values) && aux > 0) {
                if (map->keys) free(map->keys);
                if (map->values) free(map->values);
                free(map);
                ok = 0;
                break;
            }
            obj_ptrs[id] = map;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { ok = 0; break; }
            b->len = (int)aux;
            b->capacity = (int)aux;
            b->data = NULL;
            if (aux > 0) {
                b->data = (uint8_t*)malloc((size_t)aux);
                if (!b->data) { free(b); ok = 0; break; }
            }
            obj_ptrs[id] = b;
        } else {
            ok = 0;
            break;
        }
    }

    if (!ok) {
        for (uint32_t i = 0; i < obj_count; i++) if (obj_ptrs && obj_ptrs[i]) free(obj_ptrs[i]);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    // Fill payloads (seek-and-decode)
    for (uint32_t id = 0; id < obj_count; id++) {
        uint32_t cur = payload_off[id];
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            if (aux > 0) {
                if ((uint64_t)cur + (uint64_t)aux > (uint64_t)in->len) { ok = 0; break; }
                memcpy(obj_ptrs[id], in->data + cur, aux);
            }
            ((char*)obj_ptrs[id])[aux] = 0;
        } else if (t == 2) {
            AvmList* list = (AvmList*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &map->keys[i])) { ok = 0; break; }
                if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &map->values[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)obj_ptrs[id];
            if (!b || (uint32_t)b->len != aux) { ok = 0; break; }
            if (aux > 0) {
                if ((uint64_t)cur + (uint64_t)aux > (uint64_t)in->len) { ok = 0; break; }
                memcpy(b->data, in->data + cur, aux);
            }
        } else {
            ok = 0;
            break;
        }
    }

    if (!ok) {
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }

    // Root decode: position to end-of-object-table (after headers skip)
    uint32_t root_pos = after_headers_pos;
    if (!decode_value_mem(in, &root_pos, obj_types, obj_ptrs, obj_count, out)) {
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 0;
    }
    *pos = root_pos;

    // NOTE: allocated objects are intentionally leaked for now (bootstrap AVM behavior).
    free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
    return 1;
}

static int rr_write_entry(FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
    uint8_t args_h[32];
    uint8_t ret_h[32];
    if (!avm_args_hash(domain, op, args, nargs, args_h)) return 0;
    if (!avm_value_hash(ret, ret_h)) return 0;

    if (fwrite(&domain, 1, 1, f) != 1) return 0;
    if (!rr_write_u16_le(f, op)) return 0;
    uint8_t na = (uint8_t)(nargs & 0xFF);
    if (fwrite(&na, 1, 1, f) != 1) return 0;
    if (!rr_write_bytes(f, args_h, 32)) return 0;
    if (!rr_write_bytes(f, ret_h, 32)) return 0;
    if (!rr_write_value(f, ret)) return 0;
    fflush(f);
    return 1;
}

static AvmValue rr_replay_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
    uint8_t got_domain = 0;
    uint16_t got_op = 0;
    uint8_t got_nargs = 0;
    uint8_t got_args_h[32];
    uint8_t got_ret_h[32];

    if (fread(&got_domain, 1, 1, f) != 1) return avm_err(AVM_ERR_IO, "replay: unexpected EOF");
    if (!rr_read_u16_le(f, &got_op)) return avm_err(AVM_ERR_IO, "replay: truncated op");
    if (fread(&got_nargs, 1, 1, f) != 1) return avm_err(AVM_ERR_IO, "replay: truncated nargs");
    if (!rr_read_bytes(f, got_args_h, 32)) return avm_err(AVM_ERR_IO, "replay: truncated args hash");
    if (!rr_read_bytes(f, got_ret_h, 32)) return avm_err(AVM_ERR_IO, "replay: truncated ret hash");

    if (got_domain != domain || got_op != op || got_nargs != (uint8_t)(nargs & 0xFF)) {
        return avm_err(AVM_ERR_INTERNAL, "replay: call shape mismatch");
    }

    uint8_t want_args_h[32];
    if (!avm_args_hash(domain, op, args, nargs, want_args_h)) return avm_err(AVM_ERR_INTERNAL, "replay: args hash failed");
    if (memcmp(got_args_h, want_args_h, 32) != 0) {
        return avm_err(AVM_ERR_INTERNAL, "replay: args hash mismatch");
    }

    AvmValue ret = avm_nil();
    if (!rr_read_value(f, &ret)) return avm_err(AVM_ERR_IO, "replay: failed to read return value");

    uint8_t want_ret_h[32];
    if (avm_value_hash(ret, want_ret_h)) {
        if (memcmp(got_ret_h, want_ret_h, 32) != 0) {
            // Corruption or incompatibility: return a structured error.
            (void)vm;
            return avm_err(AVM_ERR_INTERNAL, "replay: return hash mismatch");
        }
    }

    return ret;
}

static int rr_write_entry_mem(AvmBytes* out, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
    uint8_t args_h[32];
    uint8_t ret_h[32];
    if (!avm_args_hash(domain, op, args, nargs, args_h)) return 0;
    if (!avm_value_hash(ret, ret_h)) return 0;

    if (!mem_write_u8(out, pos, domain)) return 0;
    if (!mem_write_u16_le(out, pos, op)) return 0;
    if (!mem_write_u8(out, pos, (uint8_t)(nargs & 0xFF))) return 0;
    if (!mem_write_bytes(out, pos, args_h, 32)) return 0;
    if (!mem_write_bytes(out, pos, ret_h, 32)) return 0;
    if (!rr_write_value_mem(out, pos, ret)) return 0;
    return 1;
}

static AvmValue rr_replay_entry_mem(AvmVM* vm, const AvmBytes* in, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
    uint8_t got_domain = 0;
    uint16_t got_op = 0;
    uint8_t got_nargs = 0;
    uint8_t got_args_h[32];
    uint8_t got_ret_h[32];

    if (!mem_read_u8(in, pos, &got_domain)) return avm_err(AVM_ERR_IO, "replay(mem): unexpected EOF");
    if (!mem_read_u16_le(in, pos, &got_op)) return avm_err(AVM_ERR_IO, "replay(mem): truncated op");
    if (!mem_read_u8(in, pos, &got_nargs)) return avm_err(AVM_ERR_IO, "replay(mem): truncated nargs");
    if (!mem_read_bytes(in, pos, got_args_h, 32)) return avm_err(AVM_ERR_IO, "replay(mem): truncated args hash");
    if (!mem_read_bytes(in, pos, got_ret_h, 32)) return avm_err(AVM_ERR_IO, "replay(mem): truncated ret hash");

    if (got_domain != domain || got_op != op || got_nargs != (uint8_t)(nargs & 0xFF)) {
        return avm_err(AVM_ERR_INTERNAL, "replay(mem): call shape mismatch");
    }

    uint8_t want_args_h[32];
    if (!avm_args_hash(domain, op, args, nargs, want_args_h)) return avm_err(AVM_ERR_INTERNAL, "replay(mem): args hash failed");
    if (memcmp(got_args_h, want_args_h, 32) != 0) {
        return avm_err(AVM_ERR_INTERNAL, "replay(mem): args hash mismatch");
    }

    AvmValue ret = avm_nil();
    if (!rr_read_value_mem(in, pos, &ret)) return avm_err(AVM_ERR_IO, "replay(mem): failed to read return value");

    uint8_t want_ret_h[32];
    if (avm_value_hash(ret, want_ret_h)) {
        if (memcmp(got_ret_h, want_ret_h, 32) != 0) {
            (void)vm;
            return avm_err(AVM_ERR_INTERNAL, "replay(mem): return hash mismatch");
        }
    }

    return ret;
}

// Canonical state hash (rolling):
// - Hashes the same logical state deterministically.
// - Maps are hashed in canonical key order (by encoded key bytes) to avoid order-dependent hashes.
int avm_state_hash(AvmVM* vm, uint8_t out[32]) {
    if (!vm || !vm->prog) return 0;

    ObjTable objs = {0};
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    AvmSha256Ctx h;
    avm_sha256_init(&h);

    const uint8_t tag[8] = {'A','V','M','S','T','A','T','E'};
    avm_sha256_update(&h, tag, 8);
    sha_u32_le(&h, objs.count);

    // Object table payloads
    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        sha_u8(&h, t);
        sha_u32_le(&h, aux);

        if (t == 1) { // STRING
            const uint8_t* s = (const uint8_t*)objs.ptrs[id];
            if (aux > 0) avm_sha256_update(&h, s, aux);
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, list->items[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 3) { // MAP (canonicalize by key)
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (aux == 0) continue;

            KeyBytes* keys = (KeyBytes*)malloc(sizeof(KeyBytes) * aux);
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * aux);
            if (!keys || !order) { free(keys); free(order); objtable_free(&objs); return 0; }

            for (uint32_t i = 0; i < aux; i++) {
                uint8_t* kb = (uint8_t*)malloc(9);
                if (!kb) { free(keys); free(order); objtable_free(&objs); return 0; }
                if (!encode_value_bytes(&objs, map->keys[i], kb)) { free(kb); free(keys); free(order); objtable_free(&objs); return 0; }
                keys[i].bytes = kb;
                keys[i].len = 9;
                order[i] = i;
            }

            // Sort by key bytes, but keep indices aligned.
            // We'll sort a KeyBytes array and then map it back by scanning order[] (O(n^2) worst); ok for bootstrap sizes.
            // Simpler: sort pairs by key bytes using an array of structs {KeyBytes, idx}.
            typedef struct { KeyBytes k; uint32_t idx; } KeyIdx;
            KeyIdx* arr = (KeyIdx*)malloc(sizeof(KeyIdx) * aux);
            if (!arr) { for (uint32_t i=0;i<aux;i++) free(keys[i].bytes); free(keys); free(order); objtable_free(&objs); return 0; }
            for (uint32_t i=0;i<aux;i++) { arr[i].k = keys[i]; arr[i].idx = order[i]; }
            qsort(arr, aux, sizeof(KeyIdx), (int(*)(const void*,const void*))key_bytes_cmp);

            for (uint32_t i = 0; i < aux; i++) {
                uint32_t idx = arr[i].idx;
                if (!encode_value_for_hash(&h, &objs, map->keys[idx])) { /* fallthrough */ }
                if (!encode_value_for_hash(&h, &objs, map->values[idx])) { /* fallthrough */ }
            }

            for (uint32_t i = 0; i < aux; i++) free(keys[i].bytes);
            free(arr);
            free(keys);
            free(order);
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { objtable_free(&objs); return 0; }
            if (aux > 0) avm_sha256_update(&h, b->data, aux);
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    sha_u32_le(&h, (uint32_t)vm->pc);
    sha_u32_le(&h, (uint32_t)vm->sp);
    sha_u32_le(&h, (uint32_t)vm->fp);
    sha_u32_le(&h, (uint32_t)vm->frame_count);

    for (int i = 0; i < vm->frame_count; i++) {
        sha_u32_le(&h, (uint32_t)vm->frames[i].return_pc);
        sha_u32_le(&h, (uint32_t)vm->frames[i].fp);
    }

    for (int i = 0; i < MAX_GLOBALS; i++) {
        if (!encode_value_for_hash(&h, &objs, vm->globals[i])) { objtable_free(&objs); return 0; }
    }
    for (int i = 0; i < vm->sp; i++) {
        if (!encode_value_for_hash(&h, &objs, vm->stack[i])) { objtable_free(&objs); return 0; }
    }

    // Include run result/error status as part of state.
    sha_u32_le(&h, (uint32_t)vm->exit_code);
    sha_u32_le(&h, (uint32_t)vm->paused);
    sha_u32_le(&h, (uint32_t)vm->has_result_value);
    if (!encode_value_for_hash(&h, &objs, vm->result_value)) { objtable_free(&objs); return 0; }
    if (!encode_value_for_hash(&h, &objs, vm->last_error)) { objtable_free(&objs); return 0; }

    // Deterministic TIME/RNG state is observable (via TIME/RNG domains), so it must be hashed.
    sha_u32_le(&h, (uint32_t)vm->deterministic);
    sha_u64_le(&h, vm->virtual_now_ns);
    sha_u64_le(&h, vm->virtual_step_ns);
    sha_u64_le(&h, vm->virtual_sleep_ns);
    sha_u64_le(&h, vm->rng_state);
    sha_u64_le(&h, vm->gas_executed);

    avm_sha256_final(&h, out);
    objtable_free(&objs);
    return 1;
}

// Canonical result hash (rolling):
// - Hashes only the outcome contract for swarm consensus.
// - Includes exit_code to distinguish success vs failure.
// - On success (exit_code==0): hashes selected result (oren_set_result), else nil.
// - On failure (exit_code!=0): hashes last_error.
int avm_result_hash(AvmVM* vm, uint8_t out[32]) {
    if (!vm || !vm->prog) return 0;

    AvmValue result = avm_nil();
    if (vm->exit_code == 0 && vm->has_result_value) result = vm->result_value;
    AvmValue err = avm_nil();
    if (vm->exit_code != 0) err = vm->last_error;

    ObjTable objs = {0};
    collect_value_objects(&objs, result);
    collect_value_objects(&objs, err);

    AvmSha256Ctx h;
    avm_sha256_init(&h);

    const uint8_t tag[8] = {'A','V','M','R','E','S','L','T'};
    avm_sha256_update(&h, tag, 8);

    sha_u32_le(&h, (uint32_t)vm->exit_code);
    sha_u32_le(&h, (uint32_t)vm->has_result_value);
    sha_u32_le(&h, objs.count);

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        sha_u8(&h, t);
        sha_u32_le(&h, aux);

        if (t == 1) { // STRING
            const uint8_t* s = (const uint8_t*)objs.ptrs[id];
            if (aux > 0) avm_sha256_update(&h, s, aux);
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, list->items[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 3) { // MAP (canonicalize by key)
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (aux == 0) continue;

            KeyBytes* keys = (KeyBytes*)malloc(sizeof(KeyBytes) * aux);
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * aux);
            if (!keys || !order) { free(keys); free(order); objtable_free(&objs); return 0; }

            for (uint32_t i = 0; i < aux; i++) {
                uint8_t* kb = (uint8_t*)malloc(9);
                if (!kb) { free(keys); free(order); objtable_free(&objs); return 0; }
                if (!encode_value_bytes(&objs, map->keys[i], kb)) { free(kb); free(keys); free(order); objtable_free(&objs); return 0; }
                keys[i].bytes = kb;
                keys[i].len = 9;
                order[i] = i;
            }

            typedef struct { KeyBytes k; uint32_t idx; } KeyIdx;
            KeyIdx* arr = (KeyIdx*)malloc(sizeof(KeyIdx) * aux);
            if (!arr) { for (uint32_t i=0;i<aux;i++) free(keys[i].bytes); free(keys); free(order); objtable_free(&objs); return 0; }
            for (uint32_t i=0;i<aux;i++) { arr[i].k = keys[i]; arr[i].idx = order[i]; }
            qsort(arr, aux, sizeof(KeyIdx), (int(*)(const void*,const void*))key_bytes_cmp);

            for (uint32_t i = 0; i < aux; i++) {
                uint32_t idx = arr[i].idx;
                if (!encode_value_for_hash(&h, &objs, map->keys[idx])) { objtable_free(&objs); return 0; }
                if (!encode_value_for_hash(&h, &objs, map->values[idx])) { objtable_free(&objs); return 0; }
            }

            for (uint32_t i = 0; i < aux; i++) free(keys[i].bytes);
            free(arr);
            free(keys);
            free(order);
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { objtable_free(&objs); return 0; }
            if (aux > 0) avm_sha256_update(&h, b->data, aux);
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    if (!encode_value_for_hash(&h, &objs, result)) { objtable_free(&objs); return 0; }
    if (!encode_value_for_hash(&h, &objs, err)) { objtable_free(&objs); return 0; }

    avm_sha256_final(&h, out);
    objtable_free(&objs);
    return 1;
}

int avm_heap_stats(AvmVM* vm, AvmHeapStats* out) {
    if (!vm || !vm->prog || !out) return 0;
    memset(out, 0, sizeof(*out));

    ObjTable objs = {0};

    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    if (vm->prog && vm->prog->constants) {
        for (size_t i = 0; i < vm->prog->const_count; i++) {
            collect_value_objects(&objs, vm->prog->constants[i]);
        }
    }

    if (vm->record_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes; collect_value_objects(&objs, v); }
    if (vm->replay_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes; collect_value_objects(&objs, v); }

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t ty = objs.types[id];
        uint32_t aux = objs.aux[id];
        if (ty == 1) {
            out->strings_count++;
            out->strings_bytes += aux;
            out->approx_total_bytes += aux + 1;
        } else if (ty == 4) {
            out->bytes_count++;
            out->bytes_bytes += aux;
            out->approx_total_bytes += aux;
        } else if (ty == 2) {
            out->lists_count++;
            out->list_elems += aux;
            out->approx_total_bytes += sizeof(AvmList) + (uint64_t)aux * sizeof(AvmValue);
        } else if (ty == 3) {
            out->maps_count++;
            out->map_entries += aux;
            out->approx_total_bytes += sizeof(AvmMap) + (uint64_t)aux * sizeof(AvmValue) * 2ull;
        }
    }

    objtable_free(&objs);
    return 1;
}

static int decode_value(FILE* f, uint8_t* obj_types, void** obj_ptrs, uint32_t obj_count, AvmValue* out) {
    uint8_t tag = 0;
    if (fread(&tag, 1, 1, f) != 1) return 0;
    int ok = 1;
    uint64_t payload = read_u64_le(f, &ok);
    if (!ok) return 0;

    if (tag == 0) {
        out->type = AVM_VAL_NIL;
        out->as.i = 0;
        return 1;
    }
    if (tag == 1) {
        out->type = AVM_VAL_INT;
        out->as.i = (int64_t)payload;
        return 1;
    }
    if (tag == 2) {
        out->type = AVM_VAL_FLOAT;
        double fval = 0;
        memcpy(&fval, &payload, sizeof(fval));
        out->type = AVM_VAL_FLOAT;
        out->as.f = fval;
        return 1;
    }
    if (tag == 3) {
        out->type = AVM_VAL_BOOL;
        out->as.i = (payload != 0) ? 1 : 0;
        return 1;
    }
    if (tag == 4) {
        if (payload >= obj_count) return 0;
        uint32_t id = (uint32_t)payload;
        uint8_t ot = obj_types[id];
        if (ot == 1) { out->type = AVM_VAL_STRING; out->as.p = obj_ptrs[id]; return 1; }
        if (ot == 2) { out->type = AVM_VAL_LIST; out->as.l = (AvmList*)obj_ptrs[id]; return 1; }
        if (ot == 3) { out->type = AVM_VAL_MAP; out->as.m = (AvmMap*)obj_ptrs[id]; return 1; }
        if (ot == 4) { out->type = AVM_VAL_BYTES; out->as.b = (AvmBytes*)obj_ptrs[id]; return 1; }
        return 0;
    }
    return 0;
}

int avm_snapshot(AvmVM* vm, const char* path) {
    if (!vm || !vm->prog || !path) return 1;

    ObjTable objs = {0};

    // Deterministic root traversal order:
    // - stack (0..sp-1)
    // - globals (0..MAX_GLOBALS-1)
    // - selected result + last_error (for pause/resume parity)
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    FILE* f = fopen(path, "wb");
    if (!f) {
        objtable_free(&objs);
        return 1;
    }

    // Magic (8 bytes)
    const uint8_t magic[8] = {'A','V','M','S','N','A','P','3'};
    if (fwrite(magic, 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }

    if (!write_u32_le(f, (uint32_t)objs.count)) { fclose(f); objtable_free(&objs); return 1; }

    // Object table, ids are 0..count-1 in insertion order (deterministic for a given state).
    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        if (!write_u8(f, t)) { fclose(f); objtable_free(&objs); return 1; }
        if (!write_u32_le(f, aux)) { fclose(f); objtable_free(&objs); return 1; }

        if (t == 1) { // STRING
            if (aux > 0) {
                if (fwrite(objs.ptrs[id], 1, aux, f) != aux) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, list->items[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 3) { // MAP
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (!map || (uint32_t)map->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, map->keys[i])) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, map->values[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { fclose(f); objtable_free(&objs); return 1; }
            if (aux > 0) {
                if (fwrite(b->data, 1, aux, f) != aux) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else {
            fclose(f);
            objtable_free(&objs);
            return 1;
        }
    }

    // VM state
    if (!write_u32_le(f, (uint32_t)vm->pc)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->sp)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->fp)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->frame_count)) { fclose(f); objtable_free(&objs); return 1; }

    for (int i = 0; i < vm->frame_count; i++) {
        if (!write_u32_le(f, (uint32_t)vm->frames[i].return_pc)) { fclose(f); objtable_free(&objs); return 1; }
        if (!write_u32_le(f, (uint32_t)vm->frames[i].fp)) { fclose(f); objtable_free(&objs); return 1; }
    }

    for (int i = 0; i < MAX_GLOBALS; i++) {
        if (!encode_value(f, &objs, vm->globals[i])) { fclose(f); objtable_free(&objs); return 1; }
    }
    for (int i = 0; i < vm->sp; i++) {
        if (!encode_value(f, &objs, vm->stack[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // Additional VM state (rolling): selected result + last_error
    if (!write_u8(f, (uint8_t)(vm->has_result_value ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!encode_value(f, &objs, vm->result_value)) { fclose(f); objtable_free(&objs); return 1; }
    if (!encode_value(f, &objs, vm->last_error)) { fclose(f); objtable_free(&objs); return 1; }

    // Deterministic TIME/RNG state (rolling; AVMSNAP3+)
    if (!write_u8(f, (uint8_t)(vm->deterministic ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_now_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_step_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_sleep_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->rng_state)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->gas_executed)) { fclose(f); objtable_free(&objs); return 1; }

    fclose(f);
    objtable_free(&objs);
    return 0;
}

int avm_restore(AvmVM* vm, const char* path) {
    if (!vm || !vm->prog || !path) return 1;

    FILE* f = fopen(path, "rb");
    if (!f) return 1;

    uint8_t magic[8];
    if (fread(magic, 1, 8, f) != 8) { fclose(f); return 1; }
    const uint8_t want2[8] = {'A','V','M','S','N','A','P','2'};
    const uint8_t want3[8] = {'A','V','M','S','N','A','P','3'};
    int snap_ver = 0;
    if (memcmp(magic, want2, 8) == 0) snap_ver = 2;
    if (memcmp(magic, want3, 8) == 0) snap_ver = 3;
    if (snap_ver == 0) { fclose(f); return 1; }

    int ok = 1;
    uint32_t obj_count = read_u32_le(f, &ok);
    if (!ok) { fclose(f); return 1; }
    if (obj_count > 1000000) { fclose(f); return 1; } // sanity cap

    uint8_t* obj_types = NULL;
    uint32_t* obj_aux = NULL;
    uint64_t* payload_off = NULL;
    void** obj_ptrs = NULL;

    obj_types = (uint8_t*)calloc(obj_count, 1);
    obj_aux = (uint32_t*)calloc(obj_count, sizeof(uint32_t));
    payload_off = (uint64_t*)calloc(obj_count, sizeof(uint64_t));
    obj_ptrs = (void**)calloc(obj_count, sizeof(void*));
    if (!obj_types || !obj_aux || !payload_off || !obj_ptrs) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 1: read headers, record payload offsets, skip payloads
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        if (fread(&t, 1, 1, f) != 1) { ok = 0; break; }
        uint32_t aux = read_u32_le(f, &ok);
        if (!ok) break;

        obj_types[id] = t;
        obj_aux[id] = aux;
        payload_off[id] = (uint64_t)ftell(f);

        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 4) payload_len = aux;
        else { ok = 0; break; }

        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    if (!ok) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 2: allocate objects based on headers (so references can resolve)
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            char* s = (char*)malloc((size_t)aux + 1);
            if (!s) { ok = 0; break; }
            s[aux] = 0;
            obj_ptrs[id] = s;
        } else if (t == 2) {
            AvmList* list = (AvmList*)malloc(sizeof(AvmList));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
            if (!map) { ok = 0; break; }
            map->count = (int)aux;
            map->capacity = (int)aux;
            map->keys = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            map->values = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if ((!map->keys || !map->values) && aux > 0) {
                if (map->keys) free(map->keys);
                if (map->values) free(map->values);
                free(map);
                ok = 0;
                break;
            }
            obj_ptrs[id] = map;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { ok = 0; break; }
            b->len = (int)aux;
            b->capacity = (int)aux;
            b->data = NULL;
            if (aux > 0) {
                b->data = (uint8_t*)malloc((size_t)aux);
                if (!b->data) { free(b); ok = 0; break; }
            }
            obj_ptrs[id] = b;
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        fclose(f);
        for (uint32_t i = 0; i < obj_count; i++) if (obj_ptrs[i]) free(obj_ptrs[i]);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 3: fill payloads
    for (uint32_t id = 0; id < obj_count; id++) {
        if (fseek(f, (long)payload_off[id], SEEK_SET) != 0) { ok = 0; break; }
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            if (aux > 0) {
                if (fread(obj_ptrs[id], 1, aux, f) != aux) { ok = 0; break; }
            }
            ((char*)obj_ptrs[id])[aux] = 0;
        } else if (t == 2) {
            AvmList* list = (AvmList*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->keys[i])) { ok = 0; break; }
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->values[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)obj_ptrs[id];
            if (!b || (uint32_t)b->len != aux) { ok = 0; break; }
            if (aux > 0) {
                if (fread(b->data, 1, aux, f) != aux) { ok = 0; break; }
            }
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Seek to VM state (end of object table). We are currently positioned at last payload end; compute by seeking:
    // easiest: after pass1 we left file position at end of object table; store it.
    // Instead, re-run pass1 cursor quickly here by seeking after magic+count.
    if (fseek(f, 8 + 4, SEEK_SET) != 0) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        if (fread(&t, 1, 1, f) != 1) { ok = 0; break; }
        uint32_t aux = read_u32_le(f, &ok);
        if (!ok) break;
        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 4) payload_len = aux;
        else { ok = 0; break; }
        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    // Read VM state
    uint32_t pc = read_u32_le(f, &ok);
    uint32_t sp = read_u32_le(f, &ok);
    uint32_t fp = read_u32_le(f, &ok);
    uint32_t frame_count = read_u32_le(f, &ok);
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (frame_count > MAX_FRAMES) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (sp > AVM_STACK_SIZE) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (pc > vm->prog->code_len) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    vm->pc = (int)pc;
    vm->sp = (int)sp;
    vm->fp = (int)fp;
    vm->frame_count = (int)frame_count;

    for (uint32_t i = 0; i < frame_count; i++) {
        uint32_t rpc = read_u32_le(f, &ok);
        uint32_t fpp = read_u32_le(f, &ok);
        if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->frames[i].return_pc = (int)rpc;
        vm->frames[i].fp = (int)fpp;
    }

    for (int i = 0; i < MAX_GLOBALS; i++) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->globals[i])) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }
    for (uint32_t i = 0; i < sp; i++) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->stack[i])) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }

    // Additional VM state (rolling): selected result + last_error
    uint8_t has_res = 0;
    if (fread(&has_res, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    vm->has_result_value = (has_res != 0) ? 1 : 0;
    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->result_value)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->last_error)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    // Deterministic TIME/RNG state (rolling; AVMSNAP3+)
    if (snap_ver >= 3) {
        uint8_t det = 0;
        if (fread(&det, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->deterministic = (det != 0) ? 1 : 0;
        int ok2 = 1;
        vm->virtual_now_ns = read_u64_le(f, &ok2);
        vm->virtual_step_ns = read_u64_le(f, &ok2);
        vm->virtual_sleep_ns = read_u64_le(f, &ok2);
        vm->rng_state = read_u64_le(f, &ok2);
        vm->gas_executed = read_u64_le(f, &ok2);
        if (!ok2) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    } else {
        // AVMSNAP2 did not capture deterministic state; reset rolling fields.
        vm->virtual_sleep_ns = 0;
        vm->gas_executed = 0;
    }

    fclose(f);

    // NOTE: heap objects allocated here are intentionally leaked for now (consistent with bootstrap AVM design).
    free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
    return 0;
}

static int avm_path_allowed(AvmVM* vm, const char* path) {
    if (!vm) return 0;
    if (vm->fs_allow_prefix_count <= 0) return 1;
    if (!path) return 0;
    for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
        const char* pref = vm->fs_allow_prefixes[i];
        if (!pref) continue;
        size_t n = strlen(pref);
        if (n == 0) continue;
        if (strncmp(path, pref, n) == 0) return 1;
    }
    return 0;
}

AvmValue avm_call_native(AvmVM* vm, uint16_t id, AvmValue* args, int nargs) {
    AvmValue res; res.type = AVM_VAL_NIL;
    switch(id) {
        case 0: { // oren_read_file
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                if (fseek(f, 0, SEEK_END) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: fseek failed");
                    break;
                }
                long len = ftell(f);
                if (len < 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: ftell failed");
                    break;
                }
                if (fseek(f, 0, SEEK_SET) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: fseek failed");
                    break;
                }
                char* buf = malloc((size_t)len + 1);
                if (!buf) {
                    fclose(f);
                    res = avm_err(AVM_ERR_INTERNAL, "read_file: out of memory");
                    break;
                }
                size_t n = fread(buf, 1, (size_t)len, f);
                buf[len] = 0;
                fclose(f);
                if (n != (size_t)len) {
                    free(buf);
                    res = avm_err(AVM_ERR_IO, "read_file: short read");
                    break;
                }
                res.type = AVM_VAL_STRING;
                res.as.p = buf;
            }
            break;
        }
        case 1: { // oren_write_file
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                char* data = (char*)args[1].as.p;
                FILE* f = fopen(path, "wb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for write: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                size_t len = strlen(data);
                size_t n = fwrite(data, 1, len, f);
                fclose(f);
                if (n != len) {
                    res = avm_err(AVM_ERR_IO, "write_file: short write");
                    break;
                }
            }
            break;
        }
        case 2: { // oren_system
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                int ret = system((char*)args[0].as.p);
                res.type = AVM_VAL_INT;
                res.as.i = ret;
            }
            break;
        }
        case 3: { // oren_args
            AvmList* list = malloc(sizeof(AvmList));
            list->count = vm->argc;
            list->capacity = vm->argc;
            list->items = malloc(sizeof(AvmValue) * vm->argc);
            for(int i=0; i<vm->argc; i++) {
                list->items[i].type = AVM_VAL_STRING;
                list->items[i].as.p = vm->argv[i];
            }
            res.type = AVM_VAL_LIST;
            res.as.l = list;
            break;
        }
        case 4: { // oren_env
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* val = getenv((char*)args[0].as.p);
                if (val) {
                    res.type = AVM_VAL_STRING;
                    res.as.p = my_strdup(val);
                }
            }
            break;
        }
        case 5: { // oren_exit
            // AVM semantics (rolling): exit terminates the VM run, not the host process.
            // This is required for record/replay and consensus hashing to work reliably.
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                vm->exit_code = (int)args[0].as.i;
            } else {
                vm->exit_code = 0;
            }
            vm->running = 0;
            res = avm_nil();
            break;
        }
        case 6: // oren_string_len
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                res.type = AVM_VAL_INT;
                res.as.i = strlen((char*)args[0].as.p);
            }
            break;
        case 7: // oren_string_char_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_INT) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_STRING;
                    char* buf = malloc(2);
                    buf[0] = s[idx];
                    buf[1] = 0;
                    res.as.p = buf;
                }
            }
            break;
        case 8: { // oren_string_slice
            if (nargs > 2 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int start = (int)args[1].as.i;
                int end = (int)args[2].as.i;
                int len = strlen(s);
                if (start >= 0 && end <= len && start <= end) {
                    int sublen = end - start;
                    char* buf = malloc(sublen + 1);
                    strncpy(buf, s + start, sublen);
                    buf[sublen] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = buf;
                }
            }
            break;
        }
        case 9: { // oren_string_char_code_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_INT;
                    res.as.i = (unsigned char)s[idx];
                }
            }
            break;
        }
        case 10: { // oren_int_to_string
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                char buf[32];
                sprintf(buf, "%lld", args[0].as.i);
                res.type = AVM_VAL_STRING;
                res.as.p = my_strdup(buf);
            }
            break;
        }
        case 12: // oren_list_len
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.l->count;
            }
            break;
        case 13: // oren_list_push
            if (nargs > 1 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (list->count >= list->capacity) {
                    list->capacity *= 2;
                    list->items = realloc(list->items, sizeof(AvmValue) * list->capacity);
                }
                list->items[list->count++] = args[1];
            }
            break;
        case 14: { // oren_index_set
            if (nargs > 2 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < list->count) {
                    list->items[idx] = args[2];
                }
            }
            break;
        }
        case 15: { // int_mod
            if (nargs > 1) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.i % args[1].as.i;
            }
            break;
        }
        case 16: { // oren_bytes_from_string
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int len = strlen(s);
                AvmList* list = malloc(sizeof(AvmList));
                list->count = len;
                list->capacity = len;
                list->items = malloc(sizeof(AvmValue) * len);
                for(int i=0; i<len; i++) {
                    list->items[i].type = AVM_VAL_INT;
                    list->items[i].as.i = (unsigned char)s[i];
                }
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 17: { // oren_write_bytes
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_LIST) {
                char* path = (char*)args[0].as.p;
                AvmList* list = args[1].as.l;
                uint8_t* buf = malloc(list->count);
                if (!buf && list->count > 0) {
                    res = avm_err(AVM_ERR_INTERNAL, "write_bytes: out of memory");
                    break;
                }
                for(int i=0; i<list->count; i++) {
                    buf[i] = (uint8_t)list->items[i].as.i;
                }
                FILE* f = fopen(path, "wb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for write: %s (errno=%d)", path, err);
                    free(buf);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                size_t n = fwrite(buf, 1, (size_t)list->count, f);
                fclose(f);
                free(buf);
                if (n != (size_t)list->count) {
                    res = avm_err(AVM_ERR_IO, "write_bytes: short write");
                    break;
                }
            }
            break;
        }
        case 18: { // oren_read_bytes
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }

                if (fseek(f, 0, SEEK_END) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: fseek failed");
                    break;
                }
                long len = ftell(f);
                if (len < 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: ftell failed");
                    break;
                }
                if (fseek(f, 0, SEEK_SET) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: fseek failed");
                    break;
                }

                uint8_t* buf = NULL;
                if (len > 0) {
                    buf = (uint8_t*)malloc((size_t)len);
                    if (!buf) {
                        fclose(f);
                        res = avm_err(AVM_ERR_INTERNAL, "read_bytes: out of memory");
                        break;
                    }
                    size_t n = fread(buf, 1, (size_t)len, f);
                    if (n != (size_t)len) {
                        free(buf);
                        fclose(f);
                        res = avm_err(AVM_ERR_IO, "read_bytes: short read");
                        break;
                    }
                }
                fclose(f);

                AvmList* list = malloc(sizeof(AvmList));
                if (!list) {
                    free(buf);
                    res = avm_err(AVM_ERR_INTERNAL, "read_bytes: out of memory");
                    break;
                }
                list->count = (int)len;
                list->capacity = (int)len;
                if (len > 0) {
                    list->items = malloc(sizeof(AvmValue) * (size_t)len);
                    if (!list->items) {
                        free(list);
                        free(buf);
                        res = avm_err(AVM_ERR_INTERNAL, "read_bytes: out of memory");
                        break;
                    }
                    for (long i = 0; i < len; i++) {
                        list->items[i].type = AVM_VAL_INT;
                        list->items[i].as.i = (unsigned char)buf[i];
                    }
                } else {
                    list->items = NULL;
                }
                free(buf);

                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 19: { // oren_err(code, msg)
            if (nargs > 1 && args[0].type == AVM_VAL_INT && args[1].type == AVM_VAL_STRING) {
                res = avm_err((int)args[0].as.i, (char*)args[1].as.p);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_err expects (int, string)");
            }
            break;
        }
        case 20: { // oren_is_err(v)
            if (nargs > 0) {
                res = avm_bool(avm_is_err_val(args[0]));
            } else {
                res = avm_bool(0);
            }
            break;
        }
        case 21: { // oren_err_code(v)
            if (nargs > 0 && avm_is_err_val(args[0])) {
                AvmValue c = avm_map_get(args[0].as.m, "code");
                if (c.type == AVM_VAL_INT) res = c;
                else res = avm_int(-1);
            } else {
                res = avm_int(-1);
            }
            break;
        }
        case 22: { // oren_err_msg(v)
            if (nargs > 0 && avm_is_err_val(args[0])) {
                AvmValue m = avm_map_get(args[0].as.m, "msg");
                if (m.type == AVM_VAL_STRING) res = m;
                else res = avm_nil();
            } else {
                res = avm_nil();
            }
            break;
        }
        case 23: { // oren_set_result(v)
            if (nargs > 0) {
                vm->result_value = args[0];
                vm->has_result_value = 1;
                res = args[0];
            } else {
                vm->result_value = avm_nil();
                vm->has_result_value = 0;
                res = avm_nil();
            }
            break;
        }
        case 24: { // oren_get_result()
            if (vm->has_result_value) res = vm->result_value;
            else res = avm_nil();
            break;
        }
        case 30: { // oren_bytes_pack(list<int 0..255>) -> bytes
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: invalid list"); break; }
                AvmValue bv = avm_bytes_new(list->count);
                if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "bytes_pack: out of memory"); break; }
                for (int i = 0; i < list->count; i++) {
                    AvmValue it = list->items[i];
                    if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                        res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: expected int bytes 0..255");
                        break;
                    }
                    bv.as.b->data[i] = (uint8_t)it.as.i;
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_pack expects (list)");
            }
            break;
        }
        case 31: { // oren_bytes_unpack(bytes) -> list<int>
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid bytes"); break; }
                AvmList* list = (AvmList*)malloc(sizeof(AvmList));
                if (!list) { res = avm_err(AVM_ERR_INTERNAL, "bytes_unpack: out of memory"); break; }
                list->count = b->len;
                list->capacity = b->len;
                list->items = NULL;
                if (b->len > 0) {
                    list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)b->len);
                    if (!list->items) { free(list); res = avm_err(AVM_ERR_INTERNAL, "bytes_unpack: out of memory"); break; }
                    for (int i = 0; i < b->len; i++) {
                        list->items[i] = avm_int((int64_t)b->data[i]);
                    }
                }
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_unpack expects (bytes)");
            }
            break;
        }
        case 32: { // oren_bytes_len(bytes) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                res = avm_int(b ? (int64_t)b->len : 0);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_len expects (bytes)");
            }
            break;
        }
        case 33: { // oren_bytes_get_u8(bytes, idx) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT) {
                AvmBytes* b = args[0].as.b;
                int64_t idx = args[1].as.i;
                if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: index out of bounds"); break; }
                res = avm_int((int64_t)b->data[(int)idx]);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u8 expects (bytes, int)");
            }
            break;
        }
        case 34: { // oren_bytes_set_u8(bytes, idx, val) -> bytes
            if (nargs > 2 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                AvmBytes* b = args[0].as.b;
                int64_t idx = args[1].as.i;
                int64_t val = args[2].as.i;
                if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: index out of bounds"); break; }
                if (val < 0 || val > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: expected 0..255"); break; }
                b->data[(int)idx] = (uint8_t)val;
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u8 expects (bytes, int, int)");
            }
            break;
        }
        case 35: { // oren_bytes_from_hex(string) -> bytes
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                const char* s = (const char*)args[0].as.p;
                size_t n = s ? strlen(s) : 0;
                if ((n & 1) != 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_from_hex: expected even-length hex"); break; }
                AvmValue bv = avm_bytes_new((int)(n / 2));
                if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "bytes_from_hex: out of memory"); break; }
                for (size_t i = 0; i < n; i += 2) {
                    int hi = hex_nibble(s[i]);
                    int lo = hex_nibble(s[i + 1]);
                    if (hi < 0 || lo < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_from_hex: invalid hex"); break; }
                    bv.as.b->data[i / 2] = (uint8_t)((hi << 4) | lo);
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_from_hex expects (string)");
            }
            break;
        }
        case 36: { // oren_bytes_to_hex(bytes) -> string
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: invalid bytes"); break; }
                static const char* hexd = "0123456789abcdef";
                size_t out_len = (size_t)b->len * 2;
                char* out = (char*)malloc(out_len + 1);
                if (!out) { res = avm_err(AVM_ERR_INTERNAL, "bytes_to_hex: out of memory"); break; }
                for (int i = 0; i < b->len; i++) {
                    uint8_t v = b->data[i];
                    out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
                    out[(size_t)i * 2 + 1] = hexd[v & 0xF];
                }
                out[out_len] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_to_hex expects (bytes)");
            }
            break;
        }
        case 40: { // oren_avm_record_to_bytes() -> nil
            // Enable in-memory recording; resets any existing buffer.
            AvmValue bv = avm_bytes_new(0);
            if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "record_to_bytes: out of memory"); break; }
            // Preallocate header.
            uint32_t p = 0;
            const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
            if (!mem_write_bytes(bv.as.b, &p, magic, 8)) { res = avm_err(AVM_ERR_INTERNAL, "record_to_bytes: out of memory"); break; }
            vm->record_log_bytes = bv.as.b;
            res = avm_nil();
            break;
        }
        case 41: { // oren_avm_get_record_bytes() -> bytes|nil
            if (vm->record_log_bytes) {
                res.type = AVM_VAL_BYTES;
                res.as.b = vm->record_log_bytes;
            } else {
                res = avm_nil();
            }
            break;
        }
        case 42: { // oren_avm_set_replay_bytes(bytes) -> nil
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 8) { res = avm_err(AVM_ERR_INVALID_ARG, "set_replay_bytes: invalid log"); break; }
                const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
                if (memcmp(b->data, want, 8) != 0) { res = avm_err(AVM_ERR_INVALID_ARG, "set_replay_bytes: bad magic"); break; }
                vm->replay_log_bytes = b;
                vm->replay_log_pos = 8;
                res = avm_nil();
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_avm_set_replay_bytes expects (bytes)");
            }
            break;
        }
        // TODO: Implement others
        default:
            printf("Unknown native id: %d\n", id);
            break;
    }
    return res;
}

static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out) {
    if (!out) return 0;
    out->type = AVM_VAL_NIL;
    if (vmap.type != AVM_VAL_MAP || !vmap.as.m || !key) return 0;
    AvmMap* map = vmap.as.m;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && k.as.p && strcmp((const char*)k.as.p, key) == 0) {
            *out = map->values[i];
            return 1;
        }
    }
    return 0;
}

typedef struct {
    void** old_ptrs;
    void** new_ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP,4=BYTES
    uint32_t count;
    uint32_t cap;
} CloneTable;

static void clonetab_free(CloneTable* t) {
    if (!t) return;
    free(t->old_ptrs);
    free(t->new_ptrs);
    free(t->types);
    t->old_ptrs = NULL;
    t->new_ptrs = NULL;
    t->types = NULL;
    t->count = 0;
    t->cap = 0;
}

static void* clonetab_find(CloneTable* t, void* old_ptr, uint8_t type) {
    if (!t || !old_ptr) return NULL;
    for (uint32_t i = 0; i < t->count; i++) {
        if (t->old_ptrs[i] == old_ptr && t->types[i] == type) return t->new_ptrs[i];
    }
    return NULL;
}

static int clonetab_add(CloneTable* t, void* old_ptr, void* new_ptr, uint8_t type) {
    if (!t) return 0;
    if (t->count >= t->cap) {
        uint32_t nc = t->cap ? t->cap * 2 : 64;
        void** no = (void**)realloc(t->old_ptrs, sizeof(void*) * nc);
        void** nn = (void**)realloc(t->new_ptrs, sizeof(void*) * nc);
        uint8_t* nt = (uint8_t*)realloc(t->types, sizeof(uint8_t) * nc);
        if (!no || !nn || !nt) return 0;
        t->old_ptrs = no;
        t->new_ptrs = nn;
        t->types = nt;
        t->cap = nc;
    }
    t->old_ptrs[t->count] = old_ptr;
    t->new_ptrs[t->count] = new_ptr;
    t->types[t->count] = type;
    t->count++;
    return 1;
}

static AvmValue avm_clone_value_rec(CloneTable* tab, AvmValue v);

static AvmValue avm_clone_string(CloneTable* tab, const char* s) {
    if (!s) return avm_string("");
    void* found = clonetab_find(tab, (void*)s, 1);
    if (found) { AvmValue r; r.type = AVM_VAL_STRING; r.as.p = found; return r; }
    char* d = my_strdup(s);
    if (!d) return avm_nil();
    if (!clonetab_add(tab, (void*)s, d, 1)) { free(d); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_STRING; r.as.p = d; return r;
}

static AvmValue avm_clone_bytes(CloneTable* tab, AvmBytes* b) {
    if (!b) return avm_nil();
    void* found = clonetab_find(tab, (void*)b, 4);
    if (found) { AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = (AvmBytes*)found; return r; }
    AvmBytes* nb = (AvmBytes*)malloc(sizeof(AvmBytes));
    if (!nb) return avm_nil();
    nb->len = b->len;
    nb->capacity = b->len;
    nb->data = NULL;
    if (b->len > 0) {
        nb->data = (uint8_t*)malloc((size_t)b->len);
        if (!nb->data) { free(nb); return avm_nil(); }
        memcpy(nb->data, b->data, (size_t)b->len);
    }
    if (!clonetab_add(tab, (void*)b, nb, 4)) { free(nb->data); free(nb); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = nb; return r;
}

static AvmValue avm_clone_list(CloneTable* tab, AvmList* list) {
    if (!list) return avm_nil();
    void* found = clonetab_find(tab, (void*)list, 2);
    if (found) { AvmValue r; r.type = AVM_VAL_LIST; r.as.l = (AvmList*)found; return r; }
    AvmList* nl = (AvmList*)malloc(sizeof(AvmList));
    if (!nl) return avm_nil();
    nl->count = list->count;
    nl->capacity = list->count;
    nl->items = NULL;
    if (nl->count > 0) {
        nl->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)nl->count);
        if (!nl->items) { free(nl); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)list, nl, 2)) { free(nl->items); free(nl); return avm_nil(); }
    for (int i = 0; i < nl->count; i++) nl->items[i] = avm_clone_value_rec(tab, list->items[i]);
    AvmValue r; r.type = AVM_VAL_LIST; r.as.l = nl; return r;
}

static AvmValue avm_clone_map(CloneTable* tab, AvmMap* map) {
    if (!map) return avm_nil();
    void* found = clonetab_find(tab, (void*)map, 3);
    if (found) { AvmValue r; r.type = AVM_VAL_MAP; r.as.m = (AvmMap*)found; return r; }
    AvmMap* nm = (AvmMap*)malloc(sizeof(AvmMap));
    if (!nm) return avm_nil();
    nm->count = map->count;
    nm->capacity = map->count;
    nm->keys = NULL;
    nm->values = NULL;
    if (nm->count > 0) {
        nm->keys = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)nm->count);
        nm->values = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)nm->count);
        if (!nm->keys || !nm->values) { free(nm->keys); free(nm->values); free(nm); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)map, nm, 3)) { free(nm->keys); free(nm->values); free(nm); return avm_nil(); }
    for (int i = 0; i < nm->count; i++) {
        nm->keys[i] = avm_clone_value_rec(tab, map->keys[i]);
        nm->values[i] = avm_clone_value_rec(tab, map->values[i]);
    }
    AvmValue r; r.type = AVM_VAL_MAP; r.as.m = nm; return r;
}

static AvmValue avm_clone_value_rec(CloneTable* tab, AvmValue v) {
    if (v.type == AVM_VAL_NIL) return avm_nil();
    if (v.type == AVM_VAL_INT) return avm_int(v.as.i);
    if (v.type == AVM_VAL_BOOL) return avm_bool(v.as.i != 0);
    if (v.type == AVM_VAL_FLOAT) { AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = v.as.f; return r; }
    if (v.type == AVM_VAL_STRING) return avm_clone_string(tab, (const char*)v.as.p);
    if (v.type == AVM_VAL_BYTES) return avm_clone_bytes(tab, v.as.b);
    if (v.type == AVM_VAL_LIST) return avm_clone_list(tab, v.as.l);
    if (v.type == AVM_VAL_MAP) return avm_clone_map(tab, v.as.m);
    return avm_nil();
}

static AvmValue avm_clone_value(AvmValue v) {
    CloneTable tab = {0};
    AvmValue out = avm_clone_value_rec(&tab, v);
    clonetab_free(&tab);
    return out;
}

static uint64_t avm_value_u64(AvmValue v, uint64_t def) {
    if (v.type == AVM_VAL_INT) {
        if (v.as.i < 0) return def;
        return (uint64_t)v.as.i;
    }
    if (v.type == AVM_VAL_BOOL) return v.as.i ? 1ull : 0ull;
    return def;
}

static int avm_value_truthy(AvmValue v) {
    if (v.type == AVM_VAL_BOOL) return v.as.i != 0;
    if (v.type == AVM_VAL_INT) return v.as.i != 0;
    return 0;
}

static AvmBytes* avm_new_log_bytes() {
    AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
    if (!b) return NULL;
    b->len = 8;
    b->capacity = 64;
    b->data = (uint8_t*)malloc((size_t)b->capacity);
    if (!b->data) { free(b); return NULL; }
    const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
    memcpy(b->data, magic, 8);
    return b;
}

static int avm_parse_obc_from_bytes(const AvmBytes* obc, AvmProgram* out) {
    if (!obc || !out) return 0;
    if (!obc->data || obc->len < 4) return 0;

    const uint8_t* data = obc->data;
    size_t len = (size_t)obc->len;

    // Header: CD 0E
    if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) return 0;

    // Const count (u16)
    size_t pos = 2;
    if (pos + 2 > len) return 0;
    uint16_t n_consts = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
    pos += 2;

    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)n_consts);
    if (!consts && n_consts > 0) return 0;
    for (uint16_t i = 0; i < n_consts; i++) consts[i].type = AVM_VAL_NIL;

    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) return 0;
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
            continue;
        }
        if (type == 1) { // INT
            if (pos + 8 > len) return 0;
            int64_t val = 0;
            for (int k = 0; k < 8; k++) {
                val |= (int64_t)data[pos++] << (k * 8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
            continue;
        }
        if (type == 4) { // STRING
            if (pos + 2 > len) return 0;
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            if (pos + slen > len) return 0;
            char* s = (char*)malloc((size_t)slen + 1);
            if (!s) return 0;
            if (slen > 0) memcpy(s, data + pos, slen);
            s[slen] = 0;
            pos += slen;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
            continue;
        }
        if (type == 8) { // BYTES (rolling): u32 len + raw bytes
            if (pos + 4 > len) return 0;
            uint32_t blen = (uint32_t)data[pos] |
                ((uint32_t)data[pos + 1] << 8) |
                ((uint32_t)data[pos + 2] << 16) |
                ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (pos + blen > len) return 0;
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) return 0;
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)malloc((size_t)blen);
                if (!b->data) { free(b); return 0; }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
            continue;
        }
        return 0;
    }

    if (pos > len) return 0;
    out->code = (uint8_t*)(data + pos);
    out->code_len = len - pos;
    out->constants = consts;
    out->const_count = n_consts;
    return 1;
}

// Rolling ABI: CALL_NATIVE2(domain, op, nargs)
// For now, CORE domain (0) maps op -> legacy native id.
static AvmValue avm_call_native2(AvmVM* vm, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
    // Capability check (rolling behavior):
    // - allowed_native_domains == 0 => allow all (bootstrap default)
    // - otherwise require bit set for domain
    if (vm->allowed_native_domains != 0) {
        uint64_t mask = 1ULL << (domain & 63);
        if ((vm->allowed_native_domains & mask) == 0) {
            return avm_err(AVM_ERR_PERM, "capability denied");
        }
    }

    // Domain 0: CORE (bootstrap mapping: op == legacy native id)
    if (domain == 0) return avm_call_native(vm, op, args, nargs);

    // Domain 1: FS (filesystem). Map op -> legacy ids for now.
    // This is a rolling ABI: domain/op tables may evolve quickly.
    if (domain == 1) {
        if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
            const char* path = (const char*)args[0].as.p;
            if (!avm_path_allowed(vm, path)) {
                return avm_err(AVM_ERR_PERM, "fs path denied");
            }
        }

        // Deterministic replay (rolling): if enabled, avoid touching the real host.
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // read_file
                AvmValue ret = avm_call_native(vm, 0, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // write_file
                AvmValue ret = avm_call_native(vm, 1, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 2: { // write_bytes
                AvmValue ret = avm_call_native(vm, 17, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 3: { // read_bytes
                AvmValue ret = avm_call_native(vm, 18, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
    }

    // Domain 5: PROC (subprocess / system)
    if (domain == 5) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // system(cmd)
                AvmValue ret = avm_call_native(vm, 2, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // exit(code)
                AvmValue ret = avm_call_native(vm, 5, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
    }

    // Domain 7: ENV (environment variables)
    if (domain == 7) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // env(name)
                AvmValue ret = avm_call_native(vm, 4, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
    }

    // Domain 2: TIME
    if (domain == 2) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // now_ns()
                AvmValue ret;
                if (vm->deterministic) {
                    __uint128_t t = (__uint128_t)vm->virtual_now_ns;
                    t += (__uint128_t)vm->virtual_sleep_ns;
                    t += (__uint128_t)vm->gas_executed * (__uint128_t)vm->virtual_step_ns;
                    uint64_t t64 = (t > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)t;
                    int64_t out = (t64 > (uint64_t)INT64_MAX) ? INT64_MAX : (int64_t)t64;
                    ret = avm_int(out);
                } else {
                    ret = avm_int((int64_t)avm_now_ns());
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // sleep_ms(ms)
                AvmValue ret = avm_nil();
                int64_t ms = 0;
                if (nargs > 0 && args[0].type == AVM_VAL_INT) ms = args[0].as.i;
                if (ms < 0) ms = 0;
                if (vm->deterministic) {
                    __uint128_t add = (__uint128_t)(uint64_t)ms * 1000000ull;
                    uint64_t add64 = (add > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)add;
                    uint64_t prev = vm->virtual_sleep_ns;
                    vm->virtual_sleep_ns = prev + add64;
                    if (vm->virtual_sleep_ns < prev) vm->virtual_sleep_ns = UINT64_MAX;
                } else {
                    usleep((useconds_t)(ms * 1000));
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
    }

    // Domain 3: RNG (non-crypto deterministic PRNG in deterministic mode)
    if (domain == 3) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // rand_u64()
                AvmValue ret;
                if (vm->deterministic) {
                    ret = avm_int((int64_t)prng_next_u64(&vm->rng_state));
                } else {
                    ret = avm_int((int64_t)host_random_u64());
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // rand_seed(u64)
                uint64_t seed = 0;
                if (nargs > 0 && args[0].type == AVM_VAL_INT) seed = (uint64_t)args[0].as.i;
                vm->rng_state = seed ? seed : 0x123456789abcdef0ull;
                AvmValue ret = avm_nil();
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
    }

    // Domain 8: AVM (nested universes via host service)
    if (domain == 8) {
        switch (op) {
            case 0: { // run_obc_bytes(obc_bytes, cfg_map)
                if (nargs < 1 || args[0].type != AVM_VAL_BYTES || !args[0].as.b) {
                    return avm_err(AVM_ERR_INVALID_ARG, "avm.run_obc_bytes expects BYTES");
                }
                AvmValue cfg = avm_nil();
                if (nargs >= 2) cfg = args[1];

                AvmProgram* prog = (AvmProgram*)malloc(sizeof(AvmProgram));
                if (!prog) return avm_err(AVM_ERR_INTERNAL, "oom");
                if (!avm_parse_obc_from_bytes(args[0].as.b, prog)) {
                    return avm_err(AVM_ERR_INVALID_ARG, "invalid obc bytes");
                }

                AvmVM* child = avm_new();
                child->argc = 0;
                child->argv = NULL;

                // Capabilities (hierarchical, rolling): child must be subset of parent when parent is restricted.
                uint64_t parent_mask = vm ? vm->allowed_native_domains : 0;
                uint64_t child_mask = parent_mask;
                AvmValue v;
                if (avm_map_get_key(cfg, "allowed_domains", &v)) {
                    uint64_t req = avm_value_u64(v, 0);
                    if (parent_mask != 0 && (req & ~parent_mask) != 0) {
                        avm_free(child);
                        return avm_err(AVM_ERR_PERM, "child capabilities must be subset of parent");
                    }
                    child_mask = req;
                }
                child->allowed_native_domains = child_mask;

                // Determinism knobs
                if (avm_map_get_key(cfg, "deterministic", &v)) child->deterministic = avm_value_truthy(v) ? 1 : 0;
                if (avm_map_get_key(cfg, "time_start_ns", &v)) child->virtual_now_ns = avm_value_u64(v, child->virtual_now_ns);
                if (avm_map_get_key(cfg, "time_step_ns", &v)) child->virtual_step_ns = avm_value_u64(v, child->virtual_step_ns);
                if (avm_map_get_key(cfg, "rng_seed", &v)) child->rng_state = avm_value_u64(v, child->rng_state);

                // Budgets (rolling): enforce child <= parent when parent is budgeted.
                if (avm_map_get_key(cfg, "gas_limit", &v)) {
                    uint64_t gl = avm_value_u64(v, 0);
                    if (vm && vm->gas_remaining > 0 && gl > vm->gas_remaining) {
                        avm_free(child);
                        return avm_err(AVM_ERR_BUDGET, "child gas_limit exceeds parent");
                    }
                    child->gas_remaining = gl;
                }
                if (avm_map_get_key(cfg, "deadline_ns", &v)) {
                    uint64_t dl = avm_value_u64(v, 0);
                    if (vm && vm->deadline_ns > 0 && dl > vm->deadline_ns) {
                        avm_free(child);
                        return avm_err(AVM_ERR_BUDGET, "child deadline exceeds parent");
                    }
                    child->deadline_ns = dl;
                }

                // Record/replay logs as data (always create a record log, even if it stays empty).
                child->record_log_bytes = avm_new_log_bytes();
                if (!child->record_log_bytes) {
                    avm_free(child);
                    return avm_err(AVM_ERR_INTERNAL, "oom");
                }
                if (avm_map_get_key(cfg, "replay_log", &v) && v.type == AVM_VAL_BYTES && v.as.b) {
                    if (v.as.b->len < 8 || !v.as.b->data) {
                        avm_free(child);
                        return avm_err(AVM_ERR_INVALID_ARG, "replay_log too short");
                    }
                    const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
                    if (memcmp(v.as.b->data, want, 8) != 0) {
                        avm_free(child);
                        return avm_err(AVM_ERR_INVALID_ARG, "invalid replay_log magic");
                    }
                    // Copy replay log into child-owned memory so the child can be freed safely.
                    AvmValue copy = avm_clone_value(v);
                    if (copy.type != AVM_VAL_BYTES || !copy.as.b) {
                        avm_free(child);
                        return avm_err(AVM_ERR_INTERNAL, "oom");
                    }
                    child->replay_log_bytes = copy.as.b;
                    child->replay_log_pos = 8;
                }

                avm_load(child, prog);
                avm_run(child);

                uint8_t rh[32]; memset(rh, 0, sizeof(rh));
                uint8_t sh[32]; memset(sh, 0, sizeof(sh));
                (void)avm_result_hash(child, rh);
                (void)avm_state_hash(child, sh);

                AvmValue v_rh = avm_bytes_new(32);
                AvmValue v_sh = avm_bytes_new(32);
                if (v_rh.type == AVM_VAL_BYTES && v_rh.as.b && v_rh.as.b->data) memcpy(v_rh.as.b->data, rh, 32);
                if (v_sh.type == AVM_VAL_BYTES && v_sh.as.b && v_sh.as.b->data) memcpy(v_sh.as.b->data, sh, 32);

                AvmMap* out = (AvmMap*)malloc(sizeof(AvmMap));
                if (!out) { avm_free(child); return avm_err(AVM_ERR_INTERNAL, "oom"); }
                out->count = 5;
                out->capacity = 8;
                out->keys = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                out->values = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                if (!out->keys || !out->values) { avm_free(child); return avm_err(AVM_ERR_INTERNAL, "oom"); }

                out->keys[0] = avm_string("exit_code");
                out->values[0] = avm_int((int64_t)child->exit_code);
                out->keys[1] = avm_string("result_hash");
                out->values[1] = v_rh;
                out->keys[2] = avm_string("state_hash");
                out->values[2] = v_sh;
                out->keys[3] = avm_string("record_log");
                AvmValue v_log;
                v_log.type = AVM_VAL_BYTES;
                v_log.as.b = child->record_log_bytes;
                out->values[3] = avm_clone_value(v_log);
                out->keys[4] = avm_string("last_error");
                out->values[4] = avm_clone_value(child->last_error);

                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                avm_free(child);
                if (prog->constants) free(prog->constants);
                free(prog);
                return ret;
            }
            default: break;
        }
        return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
    }

    // Unknown/unsupported domain in bootstrap.
    return avm_err(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op");
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
    vm->gas_remaining = 0;
    vm->deadline_ns = 0;
    vm->cancelled = 0;
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
}

void avm_run(AvmVM* vm) {
    if (!vm->prog) return;
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
                uint16_t op = id;
                if (id == 0) { domain = 1; op = 0; }   // read_file
                if (id == 1) { domain = 1; op = 1; }   // write_file
                if (id == 17) { domain = 1; op = 2; }  // write_bytes
                if (id == 18) { domain = 1; op = 3; }  // read_bytes

                AvmValue res = avm_call_native2(vm, domain, op, args, nargs);
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x3B: { // CALL_NATIVE2: u8 domain, u16 op, u8 nargs
                uint8_t domain = code[vm->pc++];
                uint16_t op = code[vm->pc++];
                op |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];

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
                
                AvmList* list = (AvmList*)malloc(sizeof(AvmList));
                list->count = count;
                list->capacity = count + 8;
                list->items = (AvmValue*)malloc(sizeof(AvmValue) * list->capacity);
                
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
                
                AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
                map->count = count;
                map->capacity = count + 8;
                map->keys = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);
                map->values = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);
                
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
}
