#include "avm_internal.h"

#include <string.h>

int avm_map_get_bool(AvmMap* map, const char* key) {
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

AvmValue avm_map_get(AvmMap* map, const char* key) {
    if (!map) return avm_nil();
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && strcmp((char*)k.as.p, key) == 0) {
            return map->values[i];
        }
    }
    return avm_nil();
}

// --- Deterministic map key ordering (v0) ---
// Supported key types: NIL, BOOL, INT, STRING
// Ordering: NIL < BOOL < INT < STRING
int avm_map_key_supported(AvmValue k) {
    return (k.type == AVM_VAL_NIL || k.type == AVM_VAL_BOOL || k.type == AVM_VAL_INT || k.type == AVM_VAL_STRING);
}

static int avm_key_rank(AvmValue k) {
    if (k.type == AVM_VAL_NIL) return 0;
    if (k.type == AVM_VAL_BOOL) return 1;
    if (k.type == AVM_VAL_INT) return 2;
    if (k.type == AVM_VAL_STRING) return 3;
    return 99;
}

static int avm_key_cmp(AvmValue a, AvmValue b) {
    int ra = avm_key_rank(a);
    int rb = avm_key_rank(b);
    if (ra < rb) return -1;
    if (ra > rb) return 1;
    if (a.type == AVM_VAL_NIL) return 0;
    if (a.type == AVM_VAL_BOOL) {
        if (a.as.i < b.as.i) return -1;
        if (a.as.i > b.as.i) return 1;
        return 0;
    }
    if (a.type == AVM_VAL_INT) {
        if (a.as.i < b.as.i) return -1;
        if (a.as.i > b.as.i) return 1;
        return 0;
    }
    if (a.type == AVM_VAL_STRING) {
        int r = strcmp((char*)a.as.p, (char*)b.as.p);
        if (r < 0) return -1;
        if (r > 0) return 1;
        return 0;
    }
    return 0;
}

static int avm_key_eq(AvmValue a, AvmValue b) {
    if (a.type != b.type) return 0;
    if (a.type == AVM_VAL_NIL) return 1;
    if (a.type == AVM_VAL_BOOL) return a.as.i == b.as.i;
    if (a.type == AVM_VAL_INT) return a.as.i == b.as.i;
    if (a.type == AVM_VAL_STRING) return strcmp((char*)a.as.p, (char*)b.as.p) == 0;
    return 0;
}

int avm_map_find_index(AvmMap* map, AvmValue key, int* found) {
    if (found) *found = 0;
    if (!map) return 0;
    int lo = 0;
    int hi = map->count;
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        int c = avm_key_cmp(map->keys[mid], key);
        if (c < 0) lo = mid + 1;
        else hi = mid;
    }
    int idx = lo;
    if (idx < map->count && avm_key_eq(map->keys[idx], key)) {
        if (found) *found = 1;
    }
    return idx;
}

int avm_list_ensure_cap(AvmList* list, int need) {
    if (!list) return 0;
    if (need <= list->capacity) return 1;
    int new_cap = list->capacity ? list->capacity : 8;
    while (new_cap < need) new_cap *= 2;
    AvmValue* ni = (AvmValue*)avm_heap_realloc_k(list->items, sizeof(AvmValue) * (size_t)new_cap, AVM_ALLOC_KIND_LIST);
    if (!ni) return 0;
    list->items = ni;
    list->capacity = new_cap;
    return 1;
}

static int avm_map_ensure_cap(AvmMap* map, int need) {
    if (!map) return 0;
    if (need <= map->capacity) return 1;
    int new_cap = map->capacity ? map->capacity : 8;
    while (new_cap < need) new_cap *= 2;
    // Avoid partial realloc success by allocating new buffers.
    AvmValue* nk = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)new_cap, AVM_ALLOC_KIND_MAP);
    AvmValue* nv = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)new_cap, AVM_ALLOC_KIND_MAP);
    if (!nk || !nv) {
        if (nk) avm_heap_free(nk);
        if (nv) avm_heap_free(nv);
        return 0;
    }
    if (map->count > 0) {
        memcpy(nk, map->keys, sizeof(AvmValue) * (size_t)map->count);
        memcpy(nv, map->values, sizeof(AvmValue) * (size_t)map->count);
    }
    if (map->keys) avm_heap_free(map->keys);
    if (map->values) avm_heap_free(map->values);
    map->keys = nk;
    map->values = nv;
    map->capacity = new_cap;
    return 1;
}

int avm_map_set_sorted(AvmMap* map, AvmValue key, AvmValue val) {
    if (!map) return 0;

    int found = 0;
    int idx = avm_map_find_index(map, key, &found);
    if (found) {
        map->values[idx] = val;
        return 1;
    }

    if (!avm_map_ensure_cap(map, map->count + 1)) return 0;
    for (int i = map->count; i > idx; i--) {
        map->keys[i] = map->keys[i - 1];
        map->values[i] = map->values[i - 1];
    }
    map->keys[idx] = key;
    map->values[idx] = val;
    map->count++;
    return 1;
}

