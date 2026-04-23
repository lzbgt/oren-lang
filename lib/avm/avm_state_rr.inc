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
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_write_object_payload(f, &objs, t, aux, objs.ptrs[id])) { objtable_free(&objs); return 0; }
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
        else if (t == 10 || t == 11 || t == 12) payload_len = (uint64_t)aux * 9ull;
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
        } else if (t == 11) {
            AvmGeneratorHandle* gen = (AvmGeneratorHandle*)malloc(sizeof(AvmGeneratorHandle));
            if (!gen) { ok = 0; break; }
            gen->magic = AVM_GENERATOR_HANDLE_MAGIC;
            for (int i = 0; i < AVM_GENERATOR_HANDLE_SLOTS; i++) gen->slots[i] = avm_nil();
            obj_ptrs[id] = gen;
        } else if (t == 12) {
            AvmGeneratorContext* co = (AvmGeneratorContext*)malloc(sizeof(AvmGeneratorContext));
            if (!co) { ok = 0; break; }
            co->magic = AVM_GENERATOR_CONTEXT_MAGIC;
            for (int i = 0; i < AVM_GENERATOR_CONTEXT_SLOTS; i++) co->slots[i] = avm_nil();
            obj_ptrs[id] = co;
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
        } else if (t == 11) {
            AvmGeneratorHandle* gen = (AvmGeneratorHandle*)obj_ptrs[id];
            if (!gen || aux != AVM_GENERATOR_HANDLE_SLOTS) { ok = 0; break; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &gen->slots[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 12) {
            AvmGeneratorContext* co = (AvmGeneratorContext*)obj_ptrs[id];
            if (!co || aux != AVM_GENERATOR_CONTEXT_SLOTS) { ok = 0; break; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &co->slots[i])) { ok = 0; break; }
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
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_write_object_payload_mem(out, pos, &objs, t, aux, objs.ptrs[id])) { objtable_free(&objs); return 0; }
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
        else if (avm_generator_object_type(t)) {
            if (!avm_generator_payload_len(t, aux, &payload_len)) { ok = 0; break; }
        }
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
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_alloc_object(t, aux, &obj_ptrs[id])) { ok = 0; break; }
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
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_fill_object_mem(in, &cur, obj_types, obj_ptrs, obj_count, t, aux, obj_ptrs[id])) { ok = 0; break; }
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
        else if (avm_generator_object_type(t)) {
            if (!avm_generator_payload_len(t, aux, &payload_len)) { objtable_free(&objs); return 0; }
        }
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
