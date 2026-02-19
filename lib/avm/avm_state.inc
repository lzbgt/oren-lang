typedef struct {
    void** ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP,4=BYTES,5=FUNC,6=I32_BUF,7=I64_BUF,8=F32_BUF,9=F64_BUF
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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, avm_int(list->items[i]))) { objtable_free(&objs); return 0; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { objtable_free(&objs); return 0; }
            if (!encode_value(f, &objs, fn->env)) { objtable_free(&objs); return 0; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { objtable_free(&objs); return 0; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fwrite(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { objtable_free(&objs); return 0; }
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
        else if (t == 10) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
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
            list->all_int = 1;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)malloc(sizeof(AvmListInt));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = NULL;
            if (aux > 0) {
                list->items = (int64_t*)malloc(sizeof(int64_t) * (size_t)aux);
                if (!list->items) { free(list); ok = 0; break; }
            }
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)malloc(sizeof(AvmFunc));
            if (!fn) { ok = 0; break; }
            fn->addr = aux;
            fn->env.type = AVM_VAL_NIL;
            fn->env.as.i = 0;
            obj_ptrs[id] = fn;
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)malloc(sizeof(AvmBuf));
            if (!b) { ok = 0; break; }
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            b->len = aux;
            b->elem_size = elem;
            b->data = NULL;
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                b->data = (uint8_t*)malloc((size_t)bytes_len);
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
            list->all_int = 1;
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
                if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
            }
            if (!ok) break;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                AvmValue v;
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { ok = 0; break; }
                if (v.type != AVM_VAL_INT) { ok = 0; break; }
                list->items[i] = v.as.i;
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)obj_ptrs[id];
            if (!fn || fn->addr != aux) { ok = 0; break; }
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &fn->env)) { ok = 0; break; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)obj_ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { ok = 0; break; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fread(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { ok = 0; break; }
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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { objtable_free(&objs); return 0; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value_mem(out, pos, &objs, avm_int(list->items[i]))) { objtable_free(&objs); return 0; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { objtable_free(&objs); return 0; }
            if (!encode_value_mem(out, pos, &objs, fn->env)) { objtable_free(&objs); return 0; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { objtable_free(&objs); return 0; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (bytes_len > (uint64_t)UINT32_MAX) { objtable_free(&objs); return 0; }
                if (!mem_write_bytes(out, pos, b->data, (uint32_t)bytes_len)) { objtable_free(&objs); return 0; }
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
        else if (t == 10) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
        else { ok = 0; break; }

        if (payload_len > (uint64_t)UINT32_MAX) { ok = 0; break; }
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
            list->all_int = 1;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)malloc(sizeof(AvmListInt));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = NULL;
            if (aux > 0) {
                list->items = (int64_t*)malloc(sizeof(int64_t) * (size_t)aux);
                if (!list->items) { free(list); ok = 0; break; }
            }
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)malloc(sizeof(AvmFunc));
            if (!fn) { ok = 0; break; }
            fn->addr = aux;
            fn->env.type = AVM_VAL_NIL;
            fn->env.as.i = 0;
            obj_ptrs[id] = fn;
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)malloc(sizeof(AvmBuf));
            if (!b) { ok = 0; break; }
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            b->len = aux;
            b->elem_size = elem;
            b->data = NULL;
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                b->data = (uint8_t*)malloc((size_t)bytes_len);
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
            list->all_int = 1;
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
                if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
            }
            if (!ok) break;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                AvmValue v;
                if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &v)) { ok = 0; break; }
                if (v.type != AVM_VAL_INT) { ok = 0; break; }
                list->items[i] = v.as.i;
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)obj_ptrs[id];
            if (!fn || fn->addr != aux) { ok = 0; break; }
            if (!decode_value_mem(in, &cur, obj_types, obj_ptrs, obj_count, &fn->env)) { ok = 0; break; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)obj_ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { ok = 0; break; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if ((uint64_t)cur + bytes_len > (uint64_t)in->len) { ok = 0; break; }
                memcpy(b->data, in->data + cur, (size_t)bytes_len);
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

static int rr_value_wire_size(AvmValue v, uint64_t* out_bytes) {
    if (!out_bytes) return 0;
    ObjTable objs = {0};
    collect_value_objects(&objs, v);

    uint64_t sz = 0;
    // obj_count (u32)
    sz += 4;

    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];

        // object header: type (u8) + aux (u32)
        if (sz > UINT64_MAX - 5) { objtable_free(&objs); return 0; }
        sz += 5;

        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;                    // STRING bytes
        else if (t == 2) payload_len = (uint64_t)aux * 9;  // LIST values
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull; // MAP key/value pairs
        else if (t == 10) payload_len = (uint64_t)aux * 9ull;       // LIST_INT values
        else if (t == 4) payload_len = aux;                // BYTES bytes
        else if (t == 5) payload_len = 9ull;               // FUNC env value
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull; // typed buf bytes
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
        else { objtable_free(&objs); return 0; }

        if (sz > UINT64_MAX - payload_len) { objtable_free(&objs); return 0; }
        sz += payload_len;
    }

    // root value encoding: fixed 9 bytes (tag u8 + payload u64)
    if (sz > UINT64_MAX - 9) { objtable_free(&objs); return 0; }
    sz += 9;

    objtable_free(&objs);
    *out_bytes = sz;
    return 1;
}

static int rr_entry_wire_size(uint8_t domain, uint16_t op, AvmValue ret, uint64_t* out_bytes) {
    if (!out_bytes) return 0;

    // domain (u8) + op (u16) + nargs (u8) + args_hash (32) + ret_hash (32)
    uint64_t base = 1 + 2 + 1 + 32 + 32;
    uint64_t vsz = 0;
    if (!rr_value_wire_size(ret, &vsz)) return 0;

    if (base > UINT64_MAX - vsz) return 0;
    *out_bytes = base + vsz;
    (void)domain;
    (void)op;
    return 1;
}

int rr_write_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
    uint64_t need = 0;
    if (!rr_entry_wire_size(domain, op, ret, &need)) return 0;
    if (!avm_log_charge(vm, need, (int)domain, (int)op)) return 0;

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

AvmValue rr_replay_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
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

int rr_write_entry_mem(AvmVM* vm, AvmBytes* out, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
    uint64_t need = 0;
    if (!rr_entry_wire_size(domain, op, ret, &need)) return 0;
    if (!avm_log_charge(vm, need, (int)domain, (int)op)) return 0;

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

AvmValue rr_replay_entry_mem(AvmVM* vm, const AvmBytes* in, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
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
        return 0;
    }
    return 0;
}

static int write_u8(FILE* f, uint8_t v);
static int write_u32_le(FILE* f, uint32_t v);
static int write_u64_le(FILE* f, uint64_t v);
static uint32_t read_u32_le(FILE* f, int* ok);
static uint64_t read_u64_le(FILE* f, int* ok);

static int snap_write_str(FILE* f, const char* s) {
    if (!f) return 0;
    if (!s) {
        return write_u32_le(f, 0xFFFFFFFFu);
    }
    uint64_t n64 = (uint64_t)strlen(s);
    if (n64 > 0xFFFFFFFEu) return 0;
    uint32_t n = (uint32_t)n64;
    if (!write_u32_le(f, n)) return 0;
    if (n > 0) {
        if (fwrite(s, 1, n, f) != n) return 0;
    }
    return 1;
}

static char* snap_read_str(FILE* f, int* ok) {
    if (!ok) return NULL;
    uint32_t n = read_u32_le(f, ok);
    if (!*ok) return NULL;
    if (n == 0xFFFFFFFFu) return NULL;
    // sanity cap (rolling): prevent hostile snapshots from allocating absurd strings
    if (n > 64u * 1024u * 1024u) { *ok = 0; return NULL; }
    char* s = (char*)avm_heap_malloc_k((size_t)n + 1u, AVM_ALLOC_KIND_TMP);
    if (!s) { *ok = 0; return NULL; }
    if (n > 0) {
        if (fread(s, 1, n, f) != n) { *ok = 0; avm_heap_free(s); return NULL; }
    }
    s[n] = 0;
    return s;
}

static int snap_write_bytes(FILE* f, const uint8_t* data, uint32_t len) {
    if (!write_u32_le(f, len)) return 0;
    if (len > 0) {
        if (fwrite(data, 1, len, f) != len) return 0;
    }
    return 1;
}

static uint8_t* snap_read_bytes(FILE* f, uint32_t* out_len, int* ok) {
    if (!ok) return NULL;
    uint32_t n = read_u32_le(f, ok);
    if (!*ok) return NULL;
    if (out_len) *out_len = n;
    // sanity cap (rolling): 512MB
    if (n > 512u * 1024u * 1024u) { *ok = 0; return NULL; }
    if (n == 0) return NULL;
    uint8_t* buf = (uint8_t*)avm_heap_malloc_k((size_t)n, AVM_ALLOC_KIND_TMP);
    if (!buf) { *ok = 0; return NULL; }
    if (fread(buf, 1, n, f) != n) { *ok = 0; avm_heap_free(buf); return NULL; }
    return buf;
}

int avm_snapshot(AvmVM* vm, const char* path) {
    if (!vm || !vm->prog || !path) return 1;

    // Cooperative tasks/channels (rolling): AVMSNAP7 adds scheduler snapshot support.

    ObjTable objs = {0};

    // Deterministic root traversal order:
    // - stack (0..sp-1)
    // - globals (0..MAX_GLOBALS-1)
    // - selected result + last_error (for pause/resume parity)
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    // Closure environments (rolling): required for pause/resume inside functions with captures.
    collect_value_objects(&objs, vm->env);
    for (int i = 0; i < vm->frame_count; i++) collect_value_objects(&objs, vm->frames[i].env);

    // Record/replay in-memory logs (rolling; AVMSNAP5+): needed for deterministic replay and nested universes.
    if (vm->record_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes; collect_value_objects(&objs, v); }
    if (vm->replay_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes; collect_value_objects(&objs, v); }

    // Cooperative tasks + channels (rolling; AVMSNAP7+):
    // Snapshot must include all values reachable from other tasks' stacks/envs and from channel queues.
    if (vm->sched) {
        AvmSched* s = (AvmSched*)vm->sched;
        if (s && s->init) {
            int cur = s->current_tid;
            // Tasks
            for (int ti = 0; ti < s->task_cap; ti++) {
                AvmTask* t = &s->tasks[ti];
                if (!t->used) continue;

                // Current task state may be newer in vm registers than in the stored task snapshot.
                if (ti == cur) {
                    collect_value_objects(&objs, vm->env);
                    for (int fi = 0; fi < vm->frame_count; fi++) collect_value_objects(&objs, vm->frames[fi].env);
                    for (int si = 0; si < vm->sp; si++) collect_value_objects(&objs, vm->stack[si]);
                } else {
                    collect_value_objects(&objs, t->env);
                    if (t->frames) {
                        int fc = t->frame_count;
                        if (fc < 0) fc = 0;
                        if (fc > (int)MAX_FRAMES) fc = (int)MAX_FRAMES;
                        for (int fi = 0; fi < fc; fi++) collect_value_objects(&objs, t->frames[fi].env);
                    }
                    if (t->stack) {
                        int sp = t->sp;
                        if (sp < 0) sp = 0;
                        if (sp > (int)AVM_STACK_SIZE) sp = (int)AVM_STACK_SIZE;
                        for (int si = 0; si < sp; si++) collect_value_objects(&objs, t->stack[si]);
                    }
                }

                collect_value_objects(&objs, t->wait_list);
                collect_value_objects(&objs, t->wake_value);
                collect_value_objects(&objs, t->ret);
            }

            // Channels: only queued message values are part of the VM semantic heap graph.
            for (int ci = 0; ci < s->chan_cap; ci++) {
                AvmChan* ch = &s->chans[ci];
                if (!ch->used) continue;
                if (ch->q && ch->q_len > 0) {
                    int qn = ch->q_len;
                    if (qn < 0) qn = 0;
                    if (qn > 4096) qn = 4096;
                    for (int qi = 0; qi < qn; qi++) collect_value_objects(&objs, ch->q[qi]);
                }
            }
        }
    }

    FILE* f = fopen(path, "wb");
    if (!f) {
        objtable_free(&objs);
        return 1;
    }

    // Magic (8 bytes)
    const uint8_t magic[8] = {'A','V','M','S','N','A','P','7'};
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
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, avm_int(list->items[i]))) { fclose(f); objtable_free(&objs); return 1; }
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
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { fclose(f); objtable_free(&objs); return 1; }
            if (!encode_value(f, &objs, fn->env)) { fclose(f); objtable_free(&objs); return 1; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { fclose(f); objtable_free(&objs); return 1; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fwrite(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { fclose(f); objtable_free(&objs); return 1; }
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
    // Current closure environment (rolling; AVMSNAP4+)
    if (!encode_value(f, &objs, vm->env)) { fclose(f); objtable_free(&objs); return 1; }

    if (!write_u32_le(f, (uint32_t)vm->frame_count)) { fclose(f); objtable_free(&objs); return 1; }

    for (int i = 0; i < vm->frame_count; i++) {
        if (!write_u32_le(f, (uint32_t)vm->frames[i].return_pc)) { fclose(f); objtable_free(&objs); return 1; }
        if (!write_u32_le(f, (uint32_t)vm->frames[i].fp)) { fclose(f); objtable_free(&objs); return 1; }
        if (!encode_value(f, &objs, vm->frames[i].env)) { fclose(f); objtable_free(&objs); return 1; }
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

    // Record/replay logs (rolling; AVMSNAP5+)
    if (!write_u8(f, (uint8_t)(vm->record_log_bytes ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (vm->record_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes;
        if (!encode_value(f, &objs, v)) { fclose(f); objtable_free(&objs); return 1; }
    }
    if (!write_u8(f, (uint8_t)(vm->replay_log_bytes ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (vm->replay_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes;
        if (!encode_value(f, &objs, v)) { fclose(f); objtable_free(&objs); return 1; }
    }
    if (!write_u32_le(f, (uint32_t)vm->replay_log_pos)) { fclose(f); objtable_free(&objs); return 1; }

    // Budgets + counters (rolling; AVMSNAP5+): ensures pause/resume does not widen budgets by accident.
    if (!write_u64_le(f, vm->gas_remaining)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->deadline_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->heap_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->heap_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->io_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->io_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->log_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->log_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u8(f, (uint8_t)(vm->cancelled ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }

    // VM configuration + virtual backends (rolling; AVMSNAP6+)
    if (!write_u64_le(f, vm->allowed_native_domains)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->fs_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->proc_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->net_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->proc_exit_code)) { fclose(f); objtable_free(&objs); return 1; }

    // Additional VM configuration (rolling; AVMSNAP7+)
    if (!write_u8(f, (uint8_t)(vm->enable_simd ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->task_quantum_steps)) { fclose(f); objtable_free(&objs); return 1; }

    // FS allow prefixes
    uint32_t apc = (vm->fs_allow_prefix_count > 0 && vm->fs_allow_prefixes) ? (uint32_t)vm->fs_allow_prefix_count : 0u;
    if (!write_u32_le(f, apc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < apc; i++) {
        if (!snap_write_str(f, vm->fs_allow_prefixes[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // FS mounts (read)
    uint32_t mrc = (vm->fs_mounts_read_count > 0 && vm->fs_mounts_read_virt && vm->fs_mounts_read_host) ? (uint32_t)vm->fs_mounts_read_count : 0u;
    if (!write_u32_le(f, mrc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < mrc; i++) {
        if (!snap_write_str(f, vm->fs_mounts_read_virt[i])) { fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_str(f, vm->fs_mounts_read_host[i])) { fclose(f); objtable_free(&objs); return 1; }
    }
    // FS mounts (write)
    uint32_t mwc = (vm->fs_mounts_write_count > 0 && vm->fs_mounts_write_virt && vm->fs_mounts_write_host) ? (uint32_t)vm->fs_mounts_write_count : 0u;
    if (!write_u32_le(f, mwc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < mwc; i++) {
        if (!snap_write_str(f, vm->fs_mounts_write_virt[i])) { fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_str(f, vm->fs_mounts_write_host[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualFS snapshot (AVMVFS01)
    if (vm->vfs) {
        if (fwrite("AVMVFS01", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
        AvmVfs* v = (AvmVfs*)vm->vfs;
        uint32_t cnt = v ? v->count : 0u;
        if (!write_u32_le(f, cnt)) { fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            AvmVfsEntry* e = &v->entries[i];
            if (!snap_write_str(f, e ? e->path : "")) { fclose(f); objtable_free(&objs); return 1; }
            uint32_t bl = e ? e->len : 0u;
            if (!snap_write_bytes(f, e ? e->data : NULL, bl)) { fclose(f); objtable_free(&objs); return 1; }
        }
    } else {
        if (fwrite("AVMVFS00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualPROC fixtures snapshot (AVMPRC01 blob)
    if (vm->vproc) {
        AvmVproc* vp = (AvmVproc*)vm->vproc;
        uint32_t cnt = vp ? vp->count : 0u;
        // Build a fixture blob in memory then write it as length-prefixed bytes.
        AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
        if (!blob) { fclose(f); objtable_free(&objs); return 1; }
        blob->data = NULL; blob->len = 0; blob->capacity = 0;
        uint32_t p = 0;
        if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        const uint8_t magicp[8] = {'A','V','M','P','R','C','0','1'};
        if (!mem_write_bytes(blob, &p, magicp, 8)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!mem_write_u32_le(blob, &p, cnt)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            const char* cmd = vp->entries[i].cmd ? vp->entries[i].cmd : "";
            uint64_t cl64 = (uint64_t)strlen(cmd);
            if (cl64 > 0xFFFFFFFEu) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t cl = (uint32_t)cl64;
            if (!mem_write_u32_le(blob, &p, cl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, (const uint8_t*)cmd, cl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_u32_le(blob, &p, (uint32_t)vp->entries[i].exit_code)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        }
        blob->len = (int)p;
        if (fwrite("AVMPRC1B", 1, 8, f) != 8) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_bytes(f, blob->data, (uint32_t)blob->len)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (blob->data) avm_heap_free(blob->data);
        avm_heap_free(blob);
    } else {
        if (fwrite("AVMPRC0B", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualNET fixtures snapshot (AVMNET01 blob)
    if (vm->vnet) {
        AvmVnet* vn = (AvmVnet*)vm->vnet;
        uint32_t cnt = vn ? vn->count : 0u;
        AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
        if (!blob) { fclose(f); objtable_free(&objs); return 1; }
        blob->data = NULL; blob->len = 0; blob->capacity = 0;
        uint32_t p = 0;
        if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        const uint8_t magicn[8] = {'A','V','M','N','E','T','0','1'};
        if (!mem_write_bytes(blob, &p, magicn, 8)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!mem_write_u32_le(blob, &p, cnt)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            const char* url = vn->entries[i].url ? vn->entries[i].url : "";
            uint64_t ul64 = (uint64_t)strlen(url);
            if (ul64 > 0xFFFFFFFEu) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t ul = (uint32_t)ul64;
            if (!mem_write_u32_le(blob, &p, ul)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, (const uint8_t*)url, ul)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t bl = vn->entries[i].body_len;
            if (!mem_write_u32_le(blob, &p, bl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, vn->entries[i].body, bl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        }
        blob->len = (int)p;
        if (fwrite("AVMNET1B", 1, 8, f) != 8) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_bytes(f, blob->data, (uint32_t)blob->len)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (blob->data) avm_heap_free(blob->data);
        avm_heap_free(blob);
    } else {
        if (fwrite("AVMNET0B", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // Scheduler snapshot (rolling; AVMSNAP7+): tasks + channels + queues.
    //
    // Layout: tagged chunk appended at end so older readers can ignore (they won't accept AVMSNAP7 anyway).
    if (vm->sched) {
        AvmSched* s = (AvmSched*)vm->sched;
        if (!s || !s->init) {
            if (fwrite("AVMSCH00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
        } else {
            if (fwrite("AVMSCH01", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }

            // Header
            if (!write_u32_le(f, (uint32_t)s->current_tid)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->quantum_steps)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->task_cap)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->task_count)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->ready_len)) { fclose(f); objtable_free(&objs); return 1; }
            for (int i = 0; i < s->ready_len; i++) {
                if (!write_u32_le(f, (uint32_t)s->ready[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
            if (!write_u32_le(f, (uint32_t)s->select_len)) { fclose(f); objtable_free(&objs); return 1; }
            for (int i = 0; i < s->select_len; i++) {
                if (!write_u32_le(f, (uint32_t)s->select_waiters[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
            if (!write_u32_le(f, (uint32_t)s->chan_cap)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->chan_count)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u64_le(f, (uint64_t)s->next_chan_id)) { fclose(f); objtable_free(&objs); return 1; }

            int cur = s->current_tid;

            // Tasks
            for (int ti = 0; ti < s->task_cap; ti++) {
                AvmTask* t = &s->tasks[ti];
                if (!write_u8(f, (uint8_t)(t->used ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!t->used) continue;

                if (!write_u8(f, (uint8_t)(t->done ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u8(f, (uint8_t)(t->blocked ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_kind)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_id)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_chan)) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->wait_list)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u64_le(f, t->join_deadline_ns)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u8(f, (uint8_t)(t->wake_pending ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->wake_value)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->slice_remaining)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->select_cursor)) { fclose(f); objtable_free(&objs); return 1; }

                // Task machine state: for the current task, prefer the live vm registers.
                int pc = t->pc;
                int sp = t->sp;
                int fp = t->fp;
                int fc = t->frame_count;
                AvmValue env = t->env;
                AvmValue* stack = t->stack;
                AvmFrame* frames = t->frames;
                if (ti == cur) {
                    pc = vm->pc;
                    sp = vm->sp;
                    fp = vm->fp;
                    fc = vm->frame_count;
                    env = vm->env;
                    stack = vm->stack;
                    frames = vm->frames;
                }
                if (sp < 0) sp = 0;
                if (sp > (int)AVM_STACK_SIZE) sp = (int)AVM_STACK_SIZE;
                if (fc < 0) fc = 0;
                if (fc > (int)MAX_FRAMES) fc = (int)MAX_FRAMES;

                if (!write_u32_le(f, (uint32_t)pc)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)sp)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)fp)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)fc)) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, env)) { fclose(f); objtable_free(&objs); return 1; }

                for (int fi = 0; fi < fc; fi++) {
                    int rpc = 0;
                    int fpp = 0;
                    AvmValue fenv = avm_nil();
                    if (frames) {
                        rpc = frames[fi].return_pc;
                        fpp = frames[fi].fp;
                        fenv = frames[fi].env;
                    }
                    if (!write_u32_le(f, (uint32_t)rpc)) { fclose(f); objtable_free(&objs); return 1; }
                    if (!write_u32_le(f, (uint32_t)fpp)) { fclose(f); objtable_free(&objs); return 1; }
                    if (!encode_value(f, &objs, fenv)) { fclose(f); objtable_free(&objs); return 1; }
                }

                for (int si = 0; si < sp; si++) {
                    AvmValue sv = avm_nil();
                    if (stack) sv = stack[si];
                    if (!encode_value(f, &objs, sv)) { fclose(f); objtable_free(&objs); return 1; }
                }

                if (!write_u8(f, (uint8_t)(t->has_ret ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->ret)) { fclose(f); objtable_free(&objs); return 1; }
            }

            // Channels
            for (int ci = 0; ci < s->chan_cap; ci++) {
                AvmChan* ch = &s->chans[ci];
                if (!write_u8(f, (uint8_t)(ch->used ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!ch->used) continue;
                if (!write_u64_le(f, (uint64_t)ch->id)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)ch->recv_count)) { fclose(f); objtable_free(&objs); return 1; }
                for (int wi = 0; wi < ch->recv_count; wi++) {
                    if (!write_u32_le(f, (uint32_t)ch->recv_waiters[wi])) { fclose(f); objtable_free(&objs); return 1; }
                }
                if (!write_u32_le(f, (uint32_t)ch->q_len)) { fclose(f); objtable_free(&objs); return 1; }
                for (int qi = 0; qi < ch->q_len; qi++) {
                    if (!encode_value(f, &objs, ch->q[qi])) { fclose(f); objtable_free(&objs); return 1; }
                }
            }
        }
    } else {
        if (fwrite("AVMSCH00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

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
    const uint8_t want4[8] = {'A','V','M','S','N','A','P','4'};
    const uint8_t want5[8] = {'A','V','M','S','N','A','P','5'};
    const uint8_t want6[8] = {'A','V','M','S','N','A','P','6'};
    const uint8_t want7[8] = {'A','V','M','S','N','A','P','7'};
    int snap_ver = 0;
    if (memcmp(magic, want2, 8) == 0) snap_ver = 2;
    if (memcmp(magic, want3, 8) == 0) snap_ver = 3;
    if (memcmp(magic, want4, 8) == 0) snap_ver = 4;
    if (memcmp(magic, want5, 8) == 0) snap_ver = 5;
    if (memcmp(magic, want6, 8) == 0) snap_ver = 6;
    if (memcmp(magic, want7, 8) == 0) snap_ver = 7;
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
        else if (t == 10) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
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
            list->all_int = 1;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)malloc(sizeof(AvmListInt));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = NULL;
            if (aux > 0) {
                list->items = (int64_t*)malloc(sizeof(int64_t) * (size_t)aux);
                if (!list->items) { free(list); ok = 0; break; }
            }
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)malloc(sizeof(AvmFunc));
            if (!fn) { ok = 0; break; }
            fn->addr = aux;
            fn->env.type = AVM_VAL_NIL;
            fn->env.as.i = 0;
            obj_ptrs[id] = fn;
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)malloc(sizeof(AvmBuf));
            if (!b) { ok = 0; break; }
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            b->len = aux;
            b->elem_size = elem;
            b->data = NULL;
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                b->data = (uint8_t*)malloc((size_t)bytes_len);
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
            list->all_int = 1;
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
                if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
            }
            if (!ok) break;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                AvmValue v;
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { ok = 0; break; }
                if (v.type != AVM_VAL_INT) { ok = 0; break; }
                list->items[i] = v.as.i;
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
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)obj_ptrs[id];
            if (!fn || fn->addr != aux) { ok = 0; break; }
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &fn->env)) { ok = 0; break; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)obj_ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { ok = 0; break; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fread(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { ok = 0; break; }
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
        else if (t == 10) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
        else { ok = 0; break; }
        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    // Read VM state
    uint32_t pc = read_u32_le(f, &ok);
    uint32_t sp = read_u32_le(f, &ok);
    uint32_t fp = read_u32_le(f, &ok);

    // Current closure environment (rolling; AVMSNAP4+).
    if (snap_ver >= 4) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->env)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    } else {
        vm->env.type = AVM_VAL_NIL;
        vm->env.as.i = 0;
    }

    uint32_t frame_count = read_u32_le(f, &ok);
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (frame_count > MAX_FRAMES) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (sp > AVM_STACK_SIZE) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (pc > vm->prog->code_len) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    vm->pc = (int)pc;
    vm->sp = (int)sp;
    vm->fp = (int)fp;
    vm->frame_count = (int)frame_count;
    {
        uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
        if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
        if (frame_count > fl) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }

    for (uint32_t i = 0; i < frame_count; i++) {
        uint32_t rpc = read_u32_le(f, &ok);
        uint32_t fpp = read_u32_le(f, &ok);
        if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->frames[i].return_pc = (int)rpc;
        vm->frames[i].fp = (int)fpp;
        if (snap_ver >= 4) {
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->frames[i].env)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        } else {
            vm->frames[i].env.type = AVM_VAL_NIL;
            vm->frames[i].env.as.i = 0;
        }
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

    // Record/replay logs + budgets (rolling; AVMSNAP5+)
    if (snap_ver >= 5) {
        uint8_t has_rec = 0;
        if (fread(&has_rec, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->record_log_bytes = NULL;
        if (has_rec) {
            AvmValue v = avm_nil();
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (v.type != AVM_VAL_BYTES || !v.as.b) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->record_log_bytes = v.as.b;
        }

        uint8_t has_rep = 0;
        if (fread(&has_rep, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->replay_log_bytes = NULL;
        if (has_rep) {
            AvmValue v = avm_nil();
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (v.type != AVM_VAL_BYTES || !v.as.b) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->replay_log_bytes = v.as.b;
        }

        uint32_t rpos = read_u32_le(f, &ok);
        if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->replay_log_pos = rpos;

        int ok3 = 1;
        vm->gas_remaining = read_u64_le(f, &ok3);
        vm->deadline_ns = read_u64_le(f, &ok3);
        vm->heap_budget_bytes = read_u64_le(f, &ok3);
        vm->heap_used_bytes = read_u64_le(f, &ok3);
        vm->io_budget_bytes = read_u64_le(f, &ok3);
        vm->io_used_bytes = read_u64_le(f, &ok3);
        vm->log_budget_bytes = read_u64_le(f, &ok3);
        vm->log_used_bytes = read_u64_le(f, &ok3);
        if (!ok3) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        uint8_t cancelled = 0;
        if (fread(&cancelled, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->cancelled = cancelled ? 1 : 0;
    }

    // VM configuration + virtual backends (rolling; AVMSNAP6+)
    if (snap_ver >= 6) {
        int okc = 1;
        vm->allowed_native_domains = read_u64_le(f, &okc);
        uint32_t fs_kind = read_u32_le(f, &okc);
        uint32_t proc_kind = read_u32_le(f, &okc);
        uint32_t net_kind = read_u32_le(f, &okc);
        uint32_t proc_ec = read_u32_le(f, &okc);
        if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_backend_kind = (int)fs_kind;
        vm->proc_backend_kind = (int)proc_kind;
        vm->net_backend_kind = (int)net_kind;
        vm->proc_exit_code = (int)proc_ec;

        // Additional VM configuration (rolling; AVMSNAP7+)
        if (snap_ver >= 7) {
            uint8_t en_simd = 0;
            if (fread(&en_simd, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->enable_simd = (en_simd != 0) ? 1 : 0;
            uint32_t tq = read_u32_le(f, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->task_quantum_steps = tq;
        }

        // FS allow prefixes
        uint32_t apc = read_u32_le(f, &okc);
        if (!okc || apc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_allow_prefix_count = 0;
        vm->fs_allow_prefixes = NULL;
        if (apc > 0) {
            vm->fs_allow_prefixes = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)apc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_allow_prefixes) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < apc; i++) vm->fs_allow_prefixes[i] = NULL;
            for (uint32_t i = 0; i < apc; i++) {
                char* s = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                vm->fs_allow_prefixes[i] = s ? s : (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP);
                if (!vm->fs_allow_prefixes[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!s) vm->fs_allow_prefixes[i][0] = 0;
            }
            vm->fs_allow_prefix_count = (int)apc;
        }

        // FS mounts (read)
        uint32_t mrc = read_u32_le(f, &okc);
        if (!okc || mrc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_mounts_read_count = 0;
        vm->fs_mounts_read_virt = NULL;
        vm->fs_mounts_read_host = NULL;
        if (mrc > 0) {
            vm->fs_mounts_read_virt = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mrc, AVM_ALLOC_KIND_TMP);
            vm->fs_mounts_read_host = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mrc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_mounts_read_virt || !vm->fs_mounts_read_host) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < mrc; i++) { vm->fs_mounts_read_virt[i] = NULL; vm->fs_mounts_read_host[i] = NULL; }
            for (uint32_t i = 0; i < mrc; i++) {
                vm->fs_mounts_read_virt[i] = snap_read_str(f, &okc);
                vm->fs_mounts_read_host[i] = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!vm->fs_mounts_read_virt[i]) { vm->fs_mounts_read_virt[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_read_virt[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_read_virt[i][0]=0; }
                if (!vm->fs_mounts_read_host[i]) { vm->fs_mounts_read_host[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_read_host[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_read_host[i][0]=0; }
            }
            vm->fs_mounts_read_count = (int)mrc;
        }

        // FS mounts (write)
        uint32_t mwc = read_u32_le(f, &okc);
        if (!okc || mwc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_mounts_write_count = 0;
        vm->fs_mounts_write_virt = NULL;
        vm->fs_mounts_write_host = NULL;
        if (mwc > 0) {
            vm->fs_mounts_write_virt = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mwc, AVM_ALLOC_KIND_TMP);
            vm->fs_mounts_write_host = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mwc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_mounts_write_virt || !vm->fs_mounts_write_host) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < mwc; i++) { vm->fs_mounts_write_virt[i] = NULL; vm->fs_mounts_write_host[i] = NULL; }
            for (uint32_t i = 0; i < mwc; i++) {
                vm->fs_mounts_write_virt[i] = snap_read_str(f, &okc);
                vm->fs_mounts_write_host[i] = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!vm->fs_mounts_write_virt[i]) { vm->fs_mounts_write_virt[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_write_virt[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_write_virt[i][0]=0; }
                if (!vm->fs_mounts_write_host[i]) { vm->fs_mounts_write_host[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_write_host[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_write_host[i][0]=0; }
            }
            vm->fs_mounts_write_count = (int)mwc;
        }

        // VirtualFS blob
        char tag[8];
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMVFS01", 8) == 0) {
            uint32_t cnt = read_u32_le(f, &okc);
            if (!okc || cnt > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            AvmVfs* v = (AvmVfs*)avm_heap_malloc_k(sizeof(AvmVfs), AVM_ALLOC_KIND_VFS);
            if (!v) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            v->entries = NULL;
            v->count = cnt;
            v->cap = cnt;
            if (cnt > 0) {
                v->entries = (AvmVfsEntry*)avm_heap_malloc_k(sizeof(AvmVfsEntry) * (size_t)cnt, AVM_ALLOC_KIND_VFS);
                if (!v->entries) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                for (uint32_t i = 0; i < cnt; i++) { v->entries[i].path = NULL; v->entries[i].data = NULL; v->entries[i].len = 0; }
            }
            for (uint32_t i = 0; i < cnt; i++) {
                char* path = snap_read_str(f, &okc);
                uint32_t bl = 0;
                uint8_t* data = snap_read_bytes(f, &bl, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!path) { path = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_VFS); if (!path) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } path[0] = 0; }
                uint8_t* body = NULL;
                if (bl > 0) {
                    body = (uint8_t*)avm_heap_malloc_k((size_t)bl, AVM_ALLOC_KIND_VFS);
                    if (!body) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    memcpy(body, data, bl);
                }
                if (data) avm_heap_free(data);
                v->entries[i].path = path;
                v->entries[i].data = body;
                v->entries[i].len = bl;
            }
            vm->vfs = v;
        } else if (memcmp(tag, "AVMVFS00", 8) == 0) {
            vm->vfs = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // VirtualPROC fixtures blob
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMPRC1B", 8) == 0) {
            uint32_t bl = 0;
            uint8_t* buf = snap_read_bytes(f, &bl, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (bl > 0 && buf) {
                (void)avm_proc_load_fixtures(vm, buf, (size_t)bl);
            }
            if (buf) avm_heap_free(buf);
        } else if (memcmp(tag, "AVMPRC0B", 8) == 0) {
            vm->vproc = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // VirtualNET fixtures blob
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMNET1B", 8) == 0) {
            uint32_t bl = 0;
            uint8_t* buf = snap_read_bytes(f, &bl, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (bl > 0 && buf) {
                (void)avm_net_load_fixtures(vm, buf, (size_t)bl);
            }
            if (buf) avm_heap_free(buf);
        } else if (memcmp(tag, "AVMNET0B", 8) == 0) {
            vm->vnet = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // Scheduler chunk (rolling; AVMSNAP7+)
        if (snap_ver >= 7) {
            if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (memcmp(tag, "AVMSCH00", 8) == 0) {
                vm->sched = NULL;
                vm->stack = vm->stack_base;
            } else if (memcmp(tag, "AVMSCH01", 8) == 0) {
                int oks = 1;
                uint32_t cur_tid = read_u32_le(f, &oks);
                uint32_t quantum_steps = read_u32_le(f, &oks);
                uint32_t task_cap = read_u32_le(f, &oks);
                uint32_t task_count = read_u32_le(f, &oks);
                uint32_t ready_len = read_u32_le(f, &oks);
                if (!oks) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (task_cap == 0 || task_cap > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (task_count > task_cap) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (ready_len > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

                uint32_t* ready = NULL;
                if (ready_len > 0) {
                    ready = (uint32_t*)calloc(ready_len, sizeof(uint32_t));
                    if (!ready) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    for (uint32_t i = 0; i < ready_len; i++) ready[i] = read_u32_le(f, &oks);
                    if (!oks) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                }

                uint32_t select_len = read_u32_le(f, &oks);
                if (!oks || select_len > 1000000u) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                uint32_t* select_waiters = NULL;
                if (select_len > 0) {
                    select_waiters = (uint32_t*)calloc(select_len, sizeof(uint32_t));
                    if (!select_waiters) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    for (uint32_t i = 0; i < select_len; i++) select_waiters[i] = read_u32_le(f, &oks);
                    if (!oks) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                }

                uint32_t chan_cap = read_u32_le(f, &oks);
                uint32_t chan_count = read_u32_le(f, &oks);
                uint64_t next_chan_id_u64 = read_u64_le(f, &oks);
                if (!oks) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (chan_cap > 1000000u) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (chan_cap > 0 && chan_count > chan_cap) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

                // Create scheduler
                AvmSched* s = (AvmSched*)calloc(1, sizeof(AvmSched));
                if (!s) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                s->init = 1;
                s->current_tid = (int)cur_tid;
                s->quantum_steps = (int)quantum_steps;
                s->task_cap = (int)task_cap;
                s->task_count = (int)task_count;
                s->ready = NULL;
                s->ready_len = (int)ready_len;
                s->ready_cap = (int)ready_len;
                s->select_waiters = NULL;
                s->select_len = (int)select_len;
                s->select_cap = (int)select_len;
                s->chan_cap = (int)chan_cap;
                s->chan_count = (int)chan_count;
                s->next_chan_id = (int64_t)next_chan_id_u64;

                s->tasks = (AvmTask*)calloc((size_t)s->task_cap, sizeof(AvmTask));
                if (!s->tasks) {
                    free(s);
                    fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                if (s->chan_cap > 0) {
                    s->chans = (AvmChan*)calloc((size_t)s->chan_cap, sizeof(AvmChan));
                    if (!s->chans) {
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                } else {
                    s->chans = NULL;
                }

                if (ready_len > 0) {
                    s->ready = (int*)calloc(ready_len, sizeof(int));
                    if (!s->ready) {
                        free(s->chans);
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    for (uint32_t i = 0; i < ready_len; i++) s->ready[i] = (int)ready[i];
                }
                if (select_len > 0) {
                    s->select_waiters = (int*)calloc(select_len, sizeof(int));
                    if (!s->select_waiters) {
                        if (s->ready) free(s->ready);
                        free(s->chans);
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    for (uint32_t i = 0; i < select_len; i++) s->select_waiters[i] = (int)select_waiters[i];
                }
                free(select_waiters);
                free(ready);

                // Tasks
                for (int ti = 0; ti < s->task_cap; ti++) {
                    uint8_t used = 0;
                    if (fread(&used, 1, 1, f) != 1) { oks = 0; break; }
                    if (!used) {
                        s->tasks[ti].used = 0;
                        continue;
                    }
                    AvmTask* t = &s->tasks[ti];
                    memset(t, 0, sizeof(*t));
                    t->used = 1;
                    uint8_t done = 0, blocked = 0;
                    if (fread(&done, 1, 1, f) != 1) { oks = 0; break; }
                    if (fread(&blocked, 1, 1, f) != 1) { oks = 0; break; }
                    t->done = done ? 1 : 0;
                    t->blocked = blocked ? 1 : 0;
                    t->wait_kind = (int)read_u32_le(f, &oks);
                    t->wait_id = (int)read_u32_le(f, &oks);
                    t->wait_chan = (int)read_u32_le(f, &oks);
                    if (!oks) break;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->wait_list)) { oks = 0; break; }
                    t->join_deadline_ns = read_u64_le(f, &oks);
                    if (!oks) break;
                    uint8_t wakep = 0;
                    if (fread(&wakep, 1, 1, f) != 1) { oks = 0; break; }
                    t->wake_pending = wakep ? 1 : 0;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->wake_value)) { oks = 0; break; }
                    t->slice_remaining = (int)read_u32_le(f, &oks);
                    t->select_cursor = (int)read_u32_le(f, &oks);
                    if (!oks) break;

                    t->pc = (int)read_u32_le(f, &oks);
                    t->sp = (int)read_u32_le(f, &oks);
                    t->fp = (int)read_u32_le(f, &oks);
                    t->frame_count = (int)read_u32_le(f, &oks);
                    if (!oks) break;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->env)) { oks = 0; break; }

                    if (t->sp < 0) t->sp = 0;
                    if (t->sp > (int)AVM_STACK_SIZE) t->sp = (int)AVM_STACK_SIZE;
                    if (t->frame_count < 0) t->frame_count = 0;
                    if (t->frame_count > (int)MAX_FRAMES) t->frame_count = (int)MAX_FRAMES;

                    // Allocate task stack + frames.
                    if (ti == 0) {
                        t->stack = vm->stack_base;
                    } else {
                        t->stack = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)AVM_STACK_SIZE);
                        if (!t->stack) { oks = 0; break; }
                    }
                    t->frames = (AvmFrame*)malloc(sizeof(AvmFrame) * (size_t)MAX_FRAMES);
                    if (!t->frames) { oks = 0; break; }
                    memset(t->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

                    for (int fi = 0; fi < t->frame_count; fi++) {
                        uint32_t rpc = read_u32_le(f, &oks);
                        uint32_t fpp = read_u32_le(f, &oks);
                        if (!oks) break;
                        t->frames[fi].return_pc = (int)rpc;
                        t->frames[fi].fp = (int)fpp;
                        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->frames[fi].env)) { oks = 0; break; }
                    }
                    if (!oks) break;

                    for (int si = 0; si < t->sp; si++) {
                        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->stack[si])) { oks = 0; break; }
                    }
                    if (!oks) break;

                    uint8_t has_ret = 0;
                    if (fread(&has_ret, 1, 1, f) != 1) { oks = 0; break; }
                    t->has_ret = has_ret ? 1 : 0;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->ret)) { oks = 0; break; }
                }
                if (!oks) {
                    // Best-effort cleanup on parse failure.
                    if (s->tasks) {
                        for (int i = 0; i < s->task_cap; i++) {
                            if (!s->tasks[i].used) continue;
                            if (s->tasks[i].frames) free(s->tasks[i].frames);
                            if (i != 0 && s->tasks[i].stack) free(s->tasks[i].stack);
                        }
                    }
                    if (s->ready) free(s->ready);
                    if (s->select_waiters) free(s->select_waiters);
                    if (s->chans) free(s->chans);
                    if (s->tasks) free(s->tasks);
                    free(s);
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }

                // Channels
                for (int ci = 0; ci < s->chan_cap; ci++) {
                    uint8_t used = 0;
                    if (fread(&used, 1, 1, f) != 1) { oks = 0; break; }
                    if (!used) {
                        s->chans[ci].used = 0;
                        continue;
                    }
                    AvmChan* ch = &s->chans[ci];
                    memset(ch, 0, sizeof(*ch));
                    ch->used = 1;
                    ch->id = (int64_t)read_u64_le(f, &oks);
                    uint32_t recv_count = read_u32_le(f, &oks);
                    if (!oks || recv_count > 1000000u) { oks = 0; break; }
                    ch->recv_count = (int)recv_count;
                    ch->recv_cap = (int)recv_count;
                    ch->recv_waiters = NULL;
                    if (recv_count > 0) {
                        ch->recv_waiters = (int*)calloc(recv_count, sizeof(int));
                        if (!ch->recv_waiters) { oks = 0; break; }
                        for (uint32_t i = 0; i < recv_count; i++) ch->recv_waiters[i] = (int)read_u32_le(f, &oks);
                        if (!oks) break;
                    }
                    uint32_t q_len = read_u32_le(f, &oks);
                    if (!oks || q_len > 1000000u) { oks = 0; break; }
                    ch->q_len = (int)q_len;
                    ch->q_cap = (int)q_len;
                    ch->q = NULL;
                    if (q_len > 0) {
                        ch->q = (AvmValue*)calloc(q_len, sizeof(AvmValue));
                        if (!ch->q) { oks = 0; break; }
                        for (uint32_t i = 0; i < q_len; i++) {
                            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &ch->q[i])) { oks = 0; break; }
                        }
                        if (!oks) break;
                    }
                }
                if (!oks) {
                    if (s->tasks) {
                        for (int i = 0; i < s->task_cap; i++) {
                            if (!s->tasks[i].used) continue;
                            if (s->tasks[i].frames) free(s->tasks[i].frames);
                            if (i != 0 && s->tasks[i].stack) free(s->tasks[i].stack);
                        }
                    }
                    if (s->chans) {
                        for (int i = 0; i < s->chan_cap; i++) {
                            if (!s->chans[i].used) continue;
                            if (s->chans[i].recv_waiters) free(s->chans[i].recv_waiters);
                            if (s->chans[i].q) free(s->chans[i].q);
                        }
                        free(s->chans);
                    }
                    if (s->ready) free(s->ready);
                    if (s->select_waiters) free(s->select_waiters);
                    if (s->tasks) free(s->tasks);
                    free(s);
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }

                // Attach scheduler and load current task state into VM.
                if (vm->sched) {
                    // Restore expects a fresh VM; be conservative.
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                // Best-effort sanity: ensure quantum is consistent with VM config.
                if (vm->task_quantum_steps > 0 && quantum_steps != 0 && vm->task_quantum_steps != quantum_steps) {
                    // If mismatch occurs, prefer snapshot scheduler quantum (semantics) and overwrite vm config.
                    vm->task_quantum_steps = quantum_steps;
                }
                vm->sched = s;

                int cur = s->current_tid;
                if (cur < 0 || cur >= s->task_cap || !s->tasks[cur].used) {
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                AvmTask* ct = &s->tasks[cur];
                vm->stack = ct->stack ? ct->stack : vm->stack_base;
                vm->pc = ct->pc;
                vm->sp = ct->sp;
                vm->fp = ct->fp;
                vm->frame_count = ct->frame_count;
                vm->env = ct->env;
                if (ct->frames) memcpy(vm->frames, ct->frames, sizeof(AvmFrame) * (size_t)MAX_FRAMES);
                else memset(vm->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

                if (ct->wake_pending) {
                    if (vm->sp < (int)AVM_STACK_SIZE) {
                        vm->stack[vm->sp++] = ct->wake_value;
                    } else {
                        fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    ct->wake_pending = 0;
                    ct->wake_value = avm_nil();
                }
            } else {
                fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
            }
        }
    }

    fclose(f);

    // NOTE: heap objects allocated here are intentionally leaked for now (consistent with bootstrap AVM design).
    free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
    return 0;
}

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
