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
        else if (t == 4) payload_len = aux;                // BYTES bytes
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

static int rr_write_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
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

static int rr_write_entry_mem(AvmVM* vm, AvmBytes* out, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret) {
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
