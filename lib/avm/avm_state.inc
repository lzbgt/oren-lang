typedef struct {
    void** ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP,4=BYTES,5=FUNC,6=I32_BUF,7=I64_BUF,8=F32_BUF,9=F64_BUF,10=LIST_INT,11=GENERATOR,12=GENERATOR_CONTEXT
    uint32_t* aux;
    uint32_t count;
    uint32_t cap;
} ObjTable;

static void collect_value_objects(ObjTable* t, AvmValue v);
static int objtable_find(ObjTable* t, void* ptr);
static uint32_t objtable_add(ObjTable* t, void* ptr, uint8_t type, uint32_t aux);
static int encode_value(FILE* f, ObjTable* objs, AvmValue v);
static int encode_value_mem(AvmBytes* out, uint32_t* pos, ObjTable* objs, AvmValue v);
static int decode_value_mem(const AvmBytes* in, uint32_t* pos, const uint8_t* obj_types, void* const* obj_ptrs, uint32_t obj_count, AvmValue* out);
static int encode_value_for_hash(AvmSha256Ctx* h, ObjTable* objs, AvmValue v);
static int decode_value(FILE* f, uint8_t* obj_types, void** obj_ptrs, uint32_t obj_count, AvmValue* out);

#include "avm_state_generator.inc"

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
            avm_heap_free(ptr);
        } else if (ty == 2) { // LIST
            AvmList* list = (AvmList*)ptr;
            if (list->items) avm_heap_free(list->items);
            avm_heap_free(list);
        } else if (ty == 3) { // MAP
            AvmMap* map = (AvmMap*)ptr;
            if (map->keys) avm_heap_free(map->keys);
            if (map->values) avm_heap_free(map->values);
            avm_heap_free(map);
        } else if (ty == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)ptr;
            if (b->data) avm_heap_free(b->data);
            avm_heap_free(b);
        } else if (ty == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)ptr;
            avm_heap_free(fn);
        } else if (ty == 6 || ty == 7 || ty == 8 || ty == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)ptr;
            if (b && b->data) avm_heap_free(b->data);
            if (b) avm_heap_free(b);
        } else if (avm_generator_free_object(ty, ptr)) {
            // handled
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
    collect_value_objects(&objs, vm->env);
    for (int i = 0; i < vm->frame_count; i++) collect_value_objects(&objs, vm->frames[i].env);

    // Program constants are roots only when the loader allocated referenced
    // constants on this VM heap. CLI/embed loaders still own their constant
    // pools externally and free them through their own pool cleanup path.
    if (vm->prog_constants_heap_owned && vm->prog && vm->prog->constants) {
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
    if (vm->trace_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->trace_bytes;
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
    if (v.type == AVM_VAL_LIST_INT && v.as.li) {
        if (objtable_find(t, v.as.li) >= 0) return;
        uint32_t cnt = (uint32_t)v.as.li->count;
        objtable_add(t, v.as.li, 10, cnt);
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
    if (v.type == AVM_VAL_FUNC && v.as.fn) {
        if (objtable_find(t, v.as.fn) >= 0) return;
        uint32_t addr = (uint32_t)v.as.fn->addr;
        objtable_add(t, v.as.fn, 5, addr);
        collect_value_objects(t, v.as.fn->env);
        return;
    }
    if ((v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) && v.as.buf) {
        if (objtable_find(t, v.as.buf) >= 0) return;
        uint8_t ot = 0;
        if (v.type == AVM_VAL_I32_BUF) ot = 6;
        else if (v.type == AVM_VAL_I64_BUF) ot = 7;
        else if (v.type == AVM_VAL_F32_BUF) ot = 8;
        else if (v.type == AVM_VAL_F64_BUF) ot = 9;
        uint32_t len = v.as.buf->len;
        objtable_add(t, v.as.buf, ot, len);
        return;
    }
    if (avm_generator_collect_value_object(t, v)) return;
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
    } else if (v.type == AVM_VAL_LIST_INT) {
        tag = 4;
        int id = objtable_find(objs, v.as.li);
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
    } else if (v.type == AVM_VAL_FUNC) {
        tag = 4;
        int id = objtable_find(objs, v.as.fn);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) {
        tag = 4;
        int id = objtable_find(objs, v.as.buf);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR) {
        tag = 4;
        int id = objtable_find(objs, v.as.gen);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR_CONTEXT) {
        tag = 4;
        int id = objtable_find(objs, v.as.gctx);
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
    } else if (v.type == AVM_VAL_LIST_INT) {
        tag = 4;
        int id = objtable_find(objs, v.as.li);
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
    } else if (v.type == AVM_VAL_FUNC) {
        tag = 4;
        int id = objtable_find(objs, v.as.fn);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) {
        tag = 4;
        int id = objtable_find(objs, v.as.buf);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR) {
        tag = 4;
        int id = objtable_find(objs, v.as.gen);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR_CONTEXT) {
        tag = 4;
        int id = objtable_find(objs, v.as.gctx);
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
        if (ot == 5) { out->type = AVM_VAL_FUNC; out->as.fn = (AvmFunc*)obj_ptrs[id]; return 1; }
        if (ot == 6) { out->type = AVM_VAL_I32_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 7) { out->type = AVM_VAL_I64_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 8) { out->type = AVM_VAL_F32_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 9) { out->type = AVM_VAL_F64_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 10) { out->type = AVM_VAL_LIST_INT; out->as.li = (AvmListInt*)obj_ptrs[id]; return 1; }
        if (avm_generator_decode_object_ref(id, obj_types, obj_ptrs, obj_count, out)) return 1;
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
    } else if (v.type == AVM_VAL_LIST_INT) {
        tag = 4;
        int id = objtable_find(objs, v.as.li);
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
    } else if (v.type == AVM_VAL_FUNC) {
        tag = 4;
        int id = objtable_find(objs, v.as.fn);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) {
        tag = 4;
        int id = objtable_find(objs, v.as.buf);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR) {
        tag = 4;
        int id = objtable_find(objs, v.as.gen);
        if (id < 0) return 0;
        payload = (uint64_t)id;
    } else if (v.type == AVM_VAL_GENERATOR_CONTEXT) {
        tag = 4;
        int id = objtable_find(objs, v.as.gctx);
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
    else if (v.type == AVM_VAL_LIST_INT) { tag = 4; int id = objtable_find(objs, v.as.li); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_MAP) { tag = 4; int id = objtable_find(objs, v.as.m); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_BYTES) { tag = 4; int id = objtable_find(objs, v.as.b); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_FUNC) { tag = 4; int id = objtable_find(objs, v.as.fn); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) { tag = 4; int id = objtable_find(objs, v.as.buf); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_GENERATOR) { tag = 4; int id = objtable_find(objs, v.as.gen); if (id < 0) return 0; payload = (uint64_t)id; }
    else if (v.type == AVM_VAL_GENERATOR_CONTEXT) { tag = 4; int id = objtable_find(objs, v.as.gctx); if (id < 0) return 0; payload = (uint64_t)id; }
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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, avm_int(list->items[i]))) { objtable_free(&objs); return 0; }
            }
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_hash_object_payload(&h, &objs, t, aux, objs.ptrs[id])) { objtable_free(&objs); return 0; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { objtable_free(&objs); return 0; }
            if (!encode_value_for_hash(&h, &objs, fn->env)) { objtable_free(&objs); return 0; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { objtable_free(&objs); return 0; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) avm_sha256_update(&h, b->data, (size_t)bytes_len);
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

#include "avm_state_rr.inc"

// Canonical state hash (rolling):
// - Hashes the same logical state deterministically.
// - Maps are hashed in canonical key order (by encoded key bytes) to avoid order-dependent hashes.

static int cmp_cstr_ptr(const void* a, const void* b) {
    const char* sa = *(const char* const*)a;
    const char* sb = *(const char* const*)b;
    if (!sa) sa = "";
    if (!sb) sb = "";
    return strcmp(sa, sb);
}

typedef struct { const char* v; const char* h; } MountPair;
static int cmp_mount_pair(const void* a, const void* b) {
    const MountPair* pa = (const MountPair*)a;
    const MountPair* pb = (const MountPair*)b;
    const char* av = pa && pa->v ? pa->v : "";
    const char* bv = pb && pb->v ? pb->v : "";
    int c = strcmp(av, bv);
    if (c != 0) return c;
    const char* ah = pa && pa->h ? pa->h : "";
    const char* bh = pb && pb->h ? pb->h : "";
    return strcmp(ah, bh);
}

int avm_state_hash(AvmVM* vm, uint8_t out[32]) {
    if (!vm || !vm->prog) return 0;

    // Hash policy/config state (rolling):
    // This must include anything that can affect semantics (permissions, backends, budgets, replay logs).
    // Do NOT include diagnostic counters like alloc_next_id.

    ObjTable objs = {0};
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);
    collect_value_objects(&objs, vm->env);
    for (int i = 0; i < vm->frame_count; i++) collect_value_objects(&objs, vm->frames[i].env);

    // Record/replay logs are part of VM state for deterministic replay and budget accounting.
    if (vm->record_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes; collect_value_objects(&objs, v); }
    if (vm->replay_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes; collect_value_objects(&objs, v); }

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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, avm_int(list->items[i]))) { objtable_free(&objs); return 0; }
            }
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_hash_object_payload(&h, &objs, t, aux, objs.ptrs[id])) { objtable_free(&objs); return 0; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { objtable_free(&objs); return 0; }
            if (!encode_value_for_hash(&h, &objs, fn->env)) { objtable_free(&objs); return 0; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { objtable_free(&objs); return 0; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) avm_sha256_update(&h, b->data, (size_t)bytes_len);
        } else {
            objtable_free(&objs);
            return 0;
        }
    }

    sha_u32_le(&h, (uint32_t)vm->pc);
    sha_u32_le(&h, (uint32_t)vm->sp);
    sha_u32_le(&h, (uint32_t)vm->fp);
    sha_u32_le(&h, (uint32_t)vm->frame_count);

    // Closure environment is semantically observable (LOAD_ENV), so it must be hashed.
    if (!encode_value_for_hash(&h, &objs, vm->env)) { objtable_free(&objs); return 0; }

    for (int i = 0; i < vm->frame_count; i++) {
        sha_u32_le(&h, (uint32_t)vm->frames[i].return_pc);
        sha_u32_le(&h, (uint32_t)vm->frames[i].fp);
        if (!encode_value_for_hash(&h, &objs, vm->frames[i].env)) { objtable_free(&objs); return 0; }
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

    // Budgets and cancellation are semantically observable (can abort runs).
    sha_u64_le(&h, vm->gas_remaining);
    sha_u64_le(&h, vm->deadline_ns);
    sha_u64_le(&h, vm->heap_budget_bytes);
    sha_u64_le(&h, vm->heap_used_bytes);
    sha_u64_le(&h, vm->io_budget_bytes);
    sha_u64_le(&h, vm->io_used_bytes);
    sha_u64_le(&h, vm->log_budget_bytes);
    sha_u64_le(&h, vm->log_used_bytes);
    sha_u32_le(&h, (uint32_t)vm->cancelled);

    // Record/replay config state.
    sha_u32_le(&h, (uint32_t)(vm->record_log_bytes ? 1 : 0));
    sha_u32_le(&h, (uint32_t)(vm->replay_log_bytes ? 1 : 0));
    sha_u32_le(&h, (uint32_t)vm->replay_log_pos);

    // Capability and backend config state.
    sha_u64_le(&h, vm->allowed_native_domains);
    sha_u32_le(&h, (uint32_t)vm->fs_backend_kind);
    sha_u32_le(&h, (uint32_t)vm->proc_backend_kind);
    sha_u32_le(&h, (uint32_t)vm->net_backend_kind);
    sha_u32_le(&h, (uint32_t)vm->proc_exit_code);

    // FS allow prefixes (canonical order: lexicographic).
    if (vm->fs_allow_prefix_count > 0 && vm->fs_allow_prefixes) {
        int n = vm->fs_allow_prefix_count;
        char** tmp = (char**)malloc(sizeof(char*) * (size_t)n);
        if (!tmp) { objtable_free(&objs); return 0; }
        for (int i = 0; i < n; i++) tmp[i] = vm->fs_allow_prefixes[i];
        qsort(tmp, (size_t)n, sizeof(char*), cmp_cstr_ptr);
        sha_u32_le(&h, (uint32_t)n);
        for (int i = 0; i < n; i++) {
            const char* s = tmp[i] ? tmp[i] : "";
            uint32_t sl = (uint32_t)strlen(s);
            sha_u32_le(&h, sl);
            if (sl > 0) avm_sha256_update(&h, (const uint8_t*)s, sl);
        }
        free(tmp);
    } else {
        sha_u32_le(&h, 0);
    }

    // FS mounts (canonical order: virt then host).
    {
        int n = (vm->fs_mounts_read_count > 0 && vm->fs_mounts_read_virt && vm->fs_mounts_read_host) ? vm->fs_mounts_read_count : 0;
        sha_u32_le(&h, (uint32_t)n);
        if (n > 0) {
            MountPair* pairs = (MountPair*)malloc(sizeof(MountPair) * (size_t)n);
            if (!pairs) { objtable_free(&objs); return 0; }
            for (int i = 0; i < n; i++) {
                pairs[i].v = vm->fs_mounts_read_virt[i] ? vm->fs_mounts_read_virt[i] : "";
                pairs[i].h = vm->fs_mounts_read_host[i] ? vm->fs_mounts_read_host[i] : "";
            }
            qsort(pairs, (size_t)n, sizeof(MountPair), cmp_mount_pair);
            for (int i = 0; i < n; i++) {
                uint32_t vl = (uint32_t)strlen(pairs[i].v);
                uint32_t hl = (uint32_t)strlen(pairs[i].h);
                sha_u32_le(&h, vl);
                if (vl > 0) avm_sha256_update(&h, (const uint8_t*)pairs[i].v, vl);
                sha_u32_le(&h, hl);
                if (hl > 0) avm_sha256_update(&h, (const uint8_t*)pairs[i].h, hl);
            }
            free(pairs);
        }
    }
    {
        int n = (vm->fs_mounts_write_count > 0 && vm->fs_mounts_write_virt && vm->fs_mounts_write_host) ? vm->fs_mounts_write_count : 0;
        sha_u32_le(&h, (uint32_t)n);
        if (n > 0) {
            MountPair* pairs = (MountPair*)malloc(sizeof(MountPair) * (size_t)n);
            if (!pairs) { objtable_free(&objs); return 0; }
            for (int i = 0; i < n; i++) {
                pairs[i].v = vm->fs_mounts_write_virt[i] ? vm->fs_mounts_write_virt[i] : "";
                pairs[i].h = vm->fs_mounts_write_host[i] ? vm->fs_mounts_write_host[i] : "";
            }
            qsort(pairs, (size_t)n, sizeof(MountPair), cmp_mount_pair);
            for (int i = 0; i < n; i++) {
                uint32_t vl = (uint32_t)strlen(pairs[i].v);
                uint32_t hl = (uint32_t)strlen(pairs[i].h);
                sha_u32_le(&h, vl);
                if (vl > 0) avm_sha256_update(&h, (const uint8_t*)pairs[i].v, vl);
                sha_u32_le(&h, hl);
                if (hl > 0) avm_sha256_update(&h, (const uint8_t*)pairs[i].h, hl);
            }
            free(pairs);
        }
    }

    // VirtualFS contents: hash canonicalized entries so insertion order doesn't affect state hash.
    if (vm->vfs) {
        AvmVfs* v = (AvmVfs*)vm->vfs;
        uint32_t cnt = v ? v->count : 0u;
        sha_u32_le(&h, cnt);
        if (cnt > 0 && v->entries) {
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * (size_t)cnt);
            if (!order) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < cnt; i++) order[i] = i;
            // Simple O(n^2) sort by path (bootstrap sizes).
            for (uint32_t i = 0; i < cnt; i++) {
                for (uint32_t j = i + 1; j < cnt; j++) {
                    const char* pi = v->entries[order[i]].path ? v->entries[order[i]].path : "";
                    const char* pj = v->entries[order[j]].path ? v->entries[order[j]].path : "";
                    if (strcmp(pi, pj) > 0) {
                        uint32_t tmpi = order[i];
                        order[i] = order[j];
                        order[j] = tmpi;
                    }
                }
            }
            for (uint32_t ii = 0; ii < cnt; ii++) {
                AvmVfsEntry* e = &v->entries[order[ii]];
                const char* p = (e && e->path) ? e->path : "";
                uint32_t pl = (uint32_t)strlen(p);
                sha_u32_le(&h, pl);
                if (pl > 0) avm_sha256_update(&h, (const uint8_t*)p, pl);
                uint32_t dl = e ? e->len : 0u;
                sha_u32_le(&h, dl);
                if (dl > 0 && e->data) avm_sha256_update(&h, e->data, dl);
            }
            free(order);
        }
    } else {
        sha_u32_le(&h, 0);
    }

    // VirtualPROC fixtures: canonical order by cmd.
    if (vm->vproc) {
        AvmVproc* vp = (AvmVproc*)vm->vproc;
        uint32_t cnt = vp ? vp->count : 0u;
        sha_u32_le(&h, cnt);
        if (cnt > 0 && vp->entries) {
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * (size_t)cnt);
            if (!order) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < cnt; i++) order[i] = i;
            for (uint32_t i = 0; i < cnt; i++) {
                for (uint32_t j = i + 1; j < cnt; j++) {
                    const char* ai = vp->entries[order[i]].cmd ? vp->entries[order[i]].cmd : "";
                    const char* aj = vp->entries[order[j]].cmd ? vp->entries[order[j]].cmd : "";
                    if (strcmp(ai, aj) > 0) {
                        uint32_t t = order[i]; order[i] = order[j]; order[j] = t;
                    }
                }
            }
            for (uint32_t ii = 0; ii < cnt; ii++) {
                AvmVprocEntry* e = &vp->entries[order[ii]];
                const char* cmd = (e && e->cmd) ? e->cmd : "";
                uint32_t cl = (uint32_t)strlen(cmd);
                sha_u32_le(&h, cl);
                if (cl > 0) avm_sha256_update(&h, (const uint8_t*)cmd, cl);
                sha_u32_le(&h, (uint32_t)e->exit_code);
            }
            free(order);
        }
    } else {
        sha_u32_le(&h, 0);
    }

    // VirtualNET fixtures: canonical order by url.
    if (vm->vnet) {
        AvmVnet* vn = (AvmVnet*)vm->vnet;
        uint32_t cnt = vn ? vn->count : 0u;
        sha_u32_le(&h, cnt);
        if (cnt > 0 && vn->entries) {
            uint32_t* order = (uint32_t*)malloc(sizeof(uint32_t) * (size_t)cnt);
            if (!order) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < cnt; i++) order[i] = i;
            for (uint32_t i = 0; i < cnt; i++) {
                for (uint32_t j = i + 1; j < cnt; j++) {
                    const char* ai = vn->entries[order[i]].url ? vn->entries[order[i]].url : "";
                    const char* aj = vn->entries[order[j]].url ? vn->entries[order[j]].url : "";
                    if (strcmp(ai, aj) > 0) {
                        uint32_t t = order[i]; order[i] = order[j]; order[j] = t;
                    }
                }
            }
            for (uint32_t ii = 0; ii < cnt; ii++) {
                AvmVnetEntry* e = &vn->entries[order[ii]];
                const char* url = (e && e->url) ? e->url : "";
                uint32_t ul = (uint32_t)strlen(url);
                sha_u32_le(&h, ul);
                if (ul > 0) avm_sha256_update(&h, (const uint8_t*)url, ul);
                uint32_t bl = e ? e->body_len : 0u;
                sha_u32_le(&h, bl);
                if (bl > 0 && e->body) avm_sha256_update(&h, e->body, bl);
            }
            free(order);
        }
    } else {
        sha_u32_le(&h, 0);
    }

    // GFX frame and input mailboxes are observable through embedder APIs and GFX poll ops.
    {
        uint32_t fl = (vm->gfx_frame_data && vm->gfx_frame_len <= (size_t)UINT32_MAX) ? (uint32_t)vm->gfx_frame_len : 0u;
        sha_u32_le(&h, fl);
        if (fl > 0) avm_sha256_update(&h, vm->gfx_frame_data, fl);
    }
    {
        AvmGfxInputQueue* q = vm->gfx_input_queue ? (AvmGfxInputQueue*)vm->gfx_input_queue : NULL;
        uint32_t cnt = (q && q->entries) ? q->count : 0u;
        sha_u32_le(&h, cnt);
        for (uint32_t i = 0; i < cnt; i++) {
            uint32_t len = q->entries[i].len;
            sha_u32_le(&h, len);
            if (len > 0 && q->entries[i].data) avm_sha256_update(&h, q->entries[i].data, len);
        }
    }

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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, avm_int(list->items[i]))) { objtable_free(&objs); return 0; }
            }
        } else if (t == 11) { // GENERATOR
            AvmGeneratorHandle* gen = (AvmGeneratorHandle*)objs.ptrs[id];
            if (!gen || aux != AVM_GENERATOR_HANDLE_SLOTS) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, gen->slots[i])) { objtable_free(&objs); return 0; }
            }
        } else if (t == 12) { // GENERATOR_CONTEXT
            AvmGeneratorContext* co = (AvmGeneratorContext*)objs.ptrs[id];
            if (!co || aux != AVM_GENERATOR_CONTEXT_SLOTS) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_for_hash(&h, &objs, co->slots[i])) { objtable_free(&objs); return 0; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { objtable_free(&objs); return 0; }
            if (!encode_value_for_hash(&h, &objs, fn->env)) { objtable_free(&objs); return 0; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { objtable_free(&objs); return 0; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) avm_sha256_update(&h, b->data, (size_t)bytes_len);
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
        } else if (ty == 10) {
            out->lists_count++;
            out->list_elems += aux;
            out->approx_total_bytes += sizeof(AvmListInt) + (uint64_t)aux * sizeof(int64_t);
        } else if (ty == 11) {
            out->approx_total_bytes += sizeof(AvmGeneratorHandle);
        } else if (ty == 12) {
            out->approx_total_bytes += sizeof(AvmGeneratorContext);
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
        if (ot == 5) { out->type = AVM_VAL_FUNC; out->as.fn = (AvmFunc*)obj_ptrs[id]; return 1; }
        if (ot == 6) { out->type = AVM_VAL_I32_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 7) { out->type = AVM_VAL_I64_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 8) { out->type = AVM_VAL_F32_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 9) { out->type = AVM_VAL_F64_BUF; out->as.buf = (AvmBuf*)obj_ptrs[id]; return 1; }
        if (ot == 10) { out->type = AVM_VAL_LIST_INT; out->as.li = (AvmListInt*)obj_ptrs[id]; return 1; }
        if (avm_generator_decode_object_ref(id, obj_types, obj_ptrs, obj_count, out)) return 1;
        return 0;
    }
    return 0;
}

#include "avm_state_snapshot.inc"

int avm_path_allowed(AvmVM* vm, const char* path) {
    if (!vm) return 0;
    if (vm->fs_allow_prefix_count <= 0) return 1;
    if (!path) return 0;

    // Normalize paths before allowlist checks.
    //
    // Security: prevent trivial traversal like "build/../secret" from matching "build/".
    // Ergonomics: accept "./tests/..." when allow prefixes are "tests/...".
    //
    // This is a purely lexical normalization (no host FS effects).
    const char* chk = path;
    char norm[4096];
    int seg_starts[1024];
    int seg_count = 0;

    size_t plen = strlen(path);
    if (plen >= sizeof(norm)) return 0; // deny overly long paths (avoid truncation bugs)

    int is_abs = (path[0] == '/');
    size_t wi = 0;
    if (is_abs) norm[wi++] = '/';

    size_t i = 0;
    while (i <= plen) {
        while (i < plen && path[i] == '/') i++;
        if (i >= plen) break;

        size_t start = i;
        while (i < plen && path[i] != '/') i++;
        size_t end = i;
        size_t sl = end - start;
        const char* seg = path + start;

        // "."
        if (sl == 1 && seg[0] == '.') continue;

        // ".."
        if (sl == 2 && seg[0] == '.' && seg[1] == '.') {
            if (seg_count > 0) {
                // Pop last segment.
                wi = (size_t)seg_starts[seg_count - 1];
                seg_count--;
                // Keep root slash if absolute.
                if (is_abs && wi == 0) { norm[wi++] = '/'; }
                continue;
            }
            if (!is_abs) {
                // Preserve leading ".." for relative paths.
                if (seg_count < (int)(sizeof(seg_starts) / sizeof(seg_starts[0]))) {
                    seg_starts[seg_count++] = (int)wi;
                }
                if (wi > 0 && norm[wi - 1] != '/') norm[wi++] = '/';
                if (wi + 2 >= sizeof(norm)) return 0;
                norm[wi++] = '.';
                norm[wi++] = '.';
            }
            continue;
        }

        if (seg_count < (int)(sizeof(seg_starts) / sizeof(seg_starts[0]))) {
            seg_starts[seg_count++] = (int)wi;
        }

        if (wi > 0 && norm[wi - 1] != '/') norm[wi++] = '/';
        if (wi + sl >= sizeof(norm)) return 0;
        memcpy(norm + wi, seg, sl);
        wi += sl;
    }

    if (wi == 0) {
        // Rootless relative empty path => "." (won't match most prefixes; conservative).
        norm[wi++] = '.';
    }
    norm[wi] = 0;
    chk = norm;

    for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
        const char* pref = vm->fs_allow_prefixes[i];
        if (!pref) continue;
        size_t n = strlen(pref);
        if (n == 0) continue;
        if (strncmp(chk, pref, n) == 0) {
            // Boundary check when prefix does not end with '/':
            // Avoid accidental matches like "build" matching "build2".
            if (n > 0 && pref[n - 1] != '/') {
                char nextc = chk[n];
                if (nextc != 0 && nextc != '/') continue;
            }
            return 1;
        }
    }
    return 0;
}
