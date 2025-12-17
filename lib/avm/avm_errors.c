#include "avm_internal.h"

#include <string.h>

int avm_err_from_errno(int err) {
    if (err == EACCES || err == EPERM) return AVM_ERR_PERM;
    if (err == ENOENT) return AVM_ERR_NOT_FOUND;
    return AVM_ERR_IO;
}

char* my_strdup(const char* s) {
    if (!s) s = "";
    size_t n = strlen(s);
    char* d = (char*)avm_heap_malloc_k(n + 1, AVM_ALLOC_KIND_STRING);
    if (!d) return NULL;
    memcpy(d, s, n + 1);
    return d;
}

AvmValue avm_string(const char* s) {
    AvmValue v;
    v.type = AVM_VAL_STRING;
    v.as.p = my_strdup(s ? s : "");
    if (!v.as.p) return avm_alloc_fail_value();
    return v;
}

int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

AvmValue avm_bytes_new(int len) {
    if (len < 0) return avm_nil();
    AvmBytes* b = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
    if (!b) return avm_alloc_fail_value();
    b->len = len;
    b->capacity = len;
    b->data = NULL;
    if (len > 0) {
        b->data = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES);
        if (!b->data) { avm_heap_free(b); return avm_alloc_fail_value(); }
        memset(b->data, 0, (size_t)len);
    }
    AvmValue v;
    v.type = AVM_VAL_BYTES;
    v.as.b = b;
    return v;
}

// Structured error representation (rolling): map {"__err": true, "code": int, "msg": string}
AvmValue avm_err(int code, const char* msg) {
    int prev_budget = 0;
    avm_alloc_unbudgeted_push(&prev_budget);

    AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
    if (!map) { avm_alloc_unbudgeted_pop(prev_budget); return avm_nil(); }
    map->count = 0;
    map->capacity = 8;
    map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * map->capacity, AVM_ALLOC_KIND_MAP);
    map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * map->capacity, AVM_ALLOC_KIND_MAP);
    if (!map->keys || !map->values) {
        if (map->keys) avm_heap_free(map->keys);
        if (map->values) avm_heap_free(map->values);
        avm_heap_free(map);
        avm_alloc_unbudgeted_pop(prev_budget);
        return avm_nil();
    }

    // Insert through sorted-map API so all maps are stored key-ordered in memory.
    (void)avm_map_set_sorted(map, avm_string("__err"), avm_bool(1));
    (void)avm_map_set_sorted(map, avm_string("code"), avm_int(code));
    (void)avm_map_set_sorted(map, avm_string("msg"), avm_string(msg ? msg : ""));

    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;

    avm_alloc_unbudgeted_pop(prev_budget);
    return v;
}

// Extended structured error (rolling): optionally includes domain/op metadata.
AvmValue avm_err_domop(int code, const char* msg, int domain, int op) {
    int prev_budget = 0;
    avm_alloc_unbudgeted_push(&prev_budget);

    AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
    if (!map) { avm_alloc_unbudgeted_pop(prev_budget); return avm_nil(); }
    map->count = 0;
    map->capacity = 8;
    map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * map->capacity, AVM_ALLOC_KIND_MAP);
    map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * map->capacity, AVM_ALLOC_KIND_MAP);
    if (!map->keys || !map->values) {
        if (map->keys) avm_heap_free(map->keys);
        if (map->values) avm_heap_free(map->values);
        avm_heap_free(map);
        avm_alloc_unbudgeted_pop(prev_budget);
        return avm_nil();
    }

    (void)avm_map_set_sorted(map, avm_string("__err"), avm_bool(1));
    (void)avm_map_set_sorted(map, avm_string("code"), avm_int(code));
    (void)avm_map_set_sorted(map, avm_string("msg"), avm_string(msg ? msg : ""));

    if (domain >= 0) {
        (void)avm_map_set_sorted(map, avm_string("domain"), avm_int(domain));
    }
    if (op >= 0) {
        (void)avm_map_set_sorted(map, avm_string("op"), avm_int(op));
    }

    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;

    avm_alloc_unbudgeted_pop(prev_budget);
    return v;
}

int avm_is_err_val(AvmValue v) {
    if (v.type != AVM_VAL_MAP) return 0;
    return avm_map_get_bool(v.as.m, "__err");
}
