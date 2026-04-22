static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out) {
    if (!out) return 0;
    out->type = AVM_VAL_NIL;
    if (vmap.type != AVM_VAL_MAP || !vmap.as.m || !key) return 0;
    AvmMap* map = vmap.as.m;
    size_t keylen = strlen(key);
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && k.as.p && strcmp((const char*)k.as.p, key) == 0) {
            *out = map->values[i];
            return 1;
        }
        // Some compiler paths may use BYTES for keys (rolling). Support both string and bytes
        // keys for internal protocol lookups (e.g. "__iter", "__err").
        if (k.type == AVM_VAL_BYTES && k.as.b && k.as.b->data && k.as.b->len == keylen &&
            memcmp(k.as.b->data, key, keylen) == 0) {
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
    if (!clonetab_add(tab, (void*)s, d, 1)) { avm_heap_free(d); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_STRING; r.as.p = d; return r;
}

static AvmValue avm_clone_bytes(CloneTable* tab, AvmBytes* b) {
    if (!b) return avm_nil();
    void* found = clonetab_find(tab, (void*)b, 4);
    if (found) { AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = (AvmBytes*)found; return r; }
    AvmBytes* nb = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
    if (!nb) return avm_nil();
    nb->len = b->len;
    nb->capacity = b->len;
    nb->data = NULL;
    if (b->len > 0) {
        nb->data = (uint8_t*)avm_heap_malloc_k((size_t)b->len, AVM_ALLOC_KIND_BYTES);
        if (!nb->data) { avm_heap_free(nb); return avm_nil(); }
        memcpy(nb->data, b->data, (size_t)b->len);
    }
    if (!clonetab_add(tab, (void*)b, nb, 4)) { if (nb->data) avm_heap_free(nb->data); avm_heap_free(nb); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = nb; return r;
}

static AvmValue avm_clone_list(CloneTable* tab, AvmList* list) {
    if (!list) return avm_nil();
    void* found = clonetab_find(tab, (void*)list, 2);
    if (found) { AvmValue r; r.type = AVM_VAL_LIST; r.as.l = (AvmList*)found; return r; }
    AvmList* nl = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!nl) return avm_nil();
    nl->count = list->count;
    nl->capacity = list->count;
    nl->all_int = list->all_int;
    nl->items = NULL;
    if (nl->count > 0) {
        nl->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nl->count, AVM_ALLOC_KIND_LIST);
        if (!nl->items) { avm_heap_free(nl); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)list, nl, 2)) { if (nl->items) avm_heap_free(nl->items); avm_heap_free(nl); return avm_nil(); }
    for (int i = 0; i < nl->count; i++) nl->items[i] = avm_clone_value_rec(tab, list->items[i]);
    AvmValue r; r.type = AVM_VAL_LIST; r.as.l = nl; return r;
}

static AvmValue avm_clone_map(CloneTable* tab, AvmMap* map) {
    if (!map) return avm_nil();
    void* found = clonetab_find(tab, (void*)map, 3);
    if (found) { AvmValue r; r.type = AVM_VAL_MAP; r.as.m = (AvmMap*)found; return r; }
    AvmMap* nm = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
    if (!nm) return avm_nil();
    nm->count = map->count;
    nm->capacity = map->count;
    nm->keys = NULL;
    nm->values = NULL;
    if (nm->count > 0) {
        nm->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nm->count, AVM_ALLOC_KIND_MAP);
        nm->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nm->count, AVM_ALLOC_KIND_MAP);
        if (!nm->keys || !nm->values) { if (nm->keys) avm_heap_free(nm->keys); if (nm->values) avm_heap_free(nm->values); avm_heap_free(nm); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)map, nm, 3)) { if (nm->keys) avm_heap_free(nm->keys); if (nm->values) avm_heap_free(nm->values); avm_heap_free(nm); return avm_nil(); }
    for (int i = 0; i < nm->count; i++) {
        nm->keys[i] = avm_clone_value_rec(tab, map->keys[i]);
        nm->values[i] = avm_clone_value_rec(tab, map->values[i]);
    }
    AvmValue r; r.type = AVM_VAL_MAP; r.as.m = nm; return r;
}

#include "avm_generator_clone.inc"

static AvmValue avm_clone_value_rec(CloneTable* tab, AvmValue v) {
    if (v.type == AVM_VAL_NIL) return avm_nil();
    if (v.type == AVM_VAL_INT) return avm_int(v.as.i);
    if (v.type == AVM_VAL_BOOL) return avm_bool(v.as.i != 0);
    if (v.type == AVM_VAL_FLOAT) { AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = v.as.f; return r; }
    if (v.type == AVM_VAL_STRING) return avm_clone_string(tab, (const char*)v.as.p);
    if (v.type == AVM_VAL_BYTES) return avm_clone_bytes(tab, v.as.b);
    if (v.type == AVM_VAL_LIST) return avm_clone_list(tab, v.as.l);
    if (v.type == AVM_VAL_MAP) return avm_clone_map(tab, v.as.m);
    if (v.type == AVM_VAL_GENERATOR) return avm_clone_generator_handle(tab, v.as.gen);
    if (v.type == AVM_VAL_GENERATOR_CONTEXT) return avm_clone_generator_context(tab, v.as.gctx);
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
    if (v.type == AVM_VAL_NIL) return 0;
    return 1;
}

static AvmBytes* avm_new_log_bytes() {
    AvmBytes* b = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
    if (!b) return NULL;
    b->len = 8;
    b->capacity = 64;
    b->data = (uint8_t*)avm_heap_malloc_k((size_t)b->capacity, AVM_ALLOC_KIND_BYTES);
    if (!b->data) { avm_heap_free(b); return NULL; }
    const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
    memcpy(b->data, magic, 8);
    return b;
}
