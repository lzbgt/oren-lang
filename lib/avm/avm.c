#include "avm.h"
#include "sha256.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <stdint.h>

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

typedef struct {
    void** ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP
    uint32_t* aux;
    uint32_t count;
    uint32_t cap;
} ObjTable;

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
    } else {
        // Unknown value type in bootstrap: encode as NIL.
        tag = 0;
        payload = 0;
    }

    if (!write_u8(f, tag)) return 0;
    if (!write_u64_le(f, payload)) return 0;
    return 1;
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
    else { tag = 0; payload = 0; }

    out[0] = tag;
    for (int i = 0; i < 8; i++) out[1 + i] = (uint8_t)((payload >> (8 * i)) & 0xFF);
    return 1;
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
    const uint8_t magic[8] = {'A','V','M','S','N','A','P','2'};
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
    const uint8_t want[8] = {'A','V','M','S','N','A','P','2'};
    if (memcmp(magic, want, 8) != 0) { fclose(f); return 1; }

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
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                exit((int)args[0].as.i);
            }
            exit(0);
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
        // TODO: Implement others
        default:
            printf("Unknown native id: %d\n", id);
            break;
    }
    return res;
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
        switch (op) {
            case 0: return avm_call_native(vm, 0, args, nargs);  // read_file
            case 1: return avm_call_native(vm, 1, args, nargs);  // write_file
            case 2: return avm_call_native(vm, 17, args, nargs); // write_bytes
            case 3: return avm_call_native(vm, 18, args, nargs); // read_bytes
            default: break;
        }
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
    vm->pause_after_steps = 0;
    vm->paused = 0;
    for(int i=0; i<MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (vm->stack) free(vm->stack);
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

        uint8_t op = code[vm->pc++];
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
