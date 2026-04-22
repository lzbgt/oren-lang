static inline int avm_generator_object_type(uint8_t t) {
    return t == 11 || t == 12;
}

static inline uint32_t avm_generator_slot_count_for_type(uint8_t t) {
    if (t == 11) return 14u;
    if (t == 12) return 4u;
    return 0u;
}

static int avm_generator_free_object(uint8_t t, void* ptr) {
    if (!avm_generator_object_type(t) || !ptr) return 0;
    avm_heap_free(ptr);
    return 1;
}

static int avm_generator_collect_value_object(ObjTable* t, AvmValue v) {
    if (v.type == AVM_VAL_GENERATOR && v.as.gen) {
        if (objtable_find(t, v.as.gen) >= 0) return 1;
        objtable_add(t, v.as.gen, 11, 14);
        for (int i = 0; i < 14; i++) collect_value_objects(t, v.as.gen->slots[i]);
        return 1;
    }
    if (v.type == AVM_VAL_GENERATOR_CONTEXT && v.as.gctx) {
        if (objtable_find(t, v.as.gctx) >= 0) return 1;
        objtable_add(t, v.as.gctx, 12, 4);
        for (int i = 0; i < 4; i++) collect_value_objects(t, v.as.gctx->slots[i]);
        return 1;
    }
    return 0;
}

static int avm_generator_decode_object_ref(uint32_t id, const uint8_t* obj_types, void* const* obj_ptrs, uint32_t obj_count, AvmValue* out) {
    if (!out || id >= obj_count) return 0;
    uint8_t ot = obj_types[id];
    if (ot == 11) { out->type = AVM_VAL_GENERATOR; out->as.gen = (AvmGeneratorHandle*)obj_ptrs[id]; return 1; }
    if (ot == 12) { out->type = AVM_VAL_GENERATOR_CONTEXT; out->as.gctx = (AvmGeneratorContext*)obj_ptrs[id]; return 1; }
    return 0;
}

static int avm_generator_hash_object_payload(AvmSha256Ctx* h, ObjTable* objs, uint8_t t, uint32_t aux, void* ptr) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    AvmValue* values = NULL;
    if (!slots || aux != slots || !ptr) return 0;
    values = (t == 11) ? ((AvmGeneratorHandle*)ptr)->slots : ((AvmGeneratorContext*)ptr)->slots;
    for (uint32_t i = 0; i < slots; i++) {
        if (!encode_value_for_hash(h, objs, values[i])) return 0;
    }
    return 1;
}

static int avm_generator_write_object_payload(FILE* f, ObjTable* objs, uint8_t t, uint32_t aux, void* ptr) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    AvmValue* values = NULL;
    if (!slots || aux != slots || !ptr) return 0;
    values = (t == 11) ? ((AvmGeneratorHandle*)ptr)->slots : ((AvmGeneratorContext*)ptr)->slots;
    for (uint32_t i = 0; i < slots; i++) {
        if (!encode_value(f, objs, values[i])) return 0;
    }
    return 1;
}

static int avm_generator_write_object_payload_mem(AvmBytes* out, uint32_t* pos, ObjTable* objs, uint8_t t, uint32_t aux, void* ptr) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    AvmValue* values = NULL;
    if (!slots || aux != slots || !ptr) return 0;
    values = (t == 11) ? ((AvmGeneratorHandle*)ptr)->slots : ((AvmGeneratorContext*)ptr)->slots;
    for (uint32_t i = 0; i < slots; i++) {
        if (!encode_value_mem(out, pos, objs, values[i])) return 0;
    }
    return 1;
}

static int avm_generator_payload_len(uint8_t t, uint32_t aux, uint64_t* out_payload_len) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    if (!slots || aux != slots || !out_payload_len) return 0;
    *out_payload_len = (uint64_t)slots * 9ull;
    return 1;
}

static int avm_generator_alloc_object(uint8_t t, uint32_t aux, void** out_ptr) {
    if (!out_ptr) return 0;
    *out_ptr = NULL;
    if (t == 11) {
        if (aux != 14) return 0;
        AvmGeneratorHandle* gen = (AvmGeneratorHandle*)malloc(sizeof(AvmGeneratorHandle));
        if (!gen) return 0;
        gen->magic = AVM_GENERATOR_HANDLE_MAGIC;
        for (int i = 0; i < 14; i++) gen->slots[i] = avm_nil();
        *out_ptr = gen;
        return 1;
    }
    if (t == 12) {
        if (aux != 4) return 0;
        AvmGeneratorContext* co = (AvmGeneratorContext*)malloc(sizeof(AvmGeneratorContext));
        if (!co) return 0;
        co->magic = AVM_GENERATOR_CONTEXT_MAGIC;
        for (int i = 0; i < 4; i++) co->slots[i] = avm_nil();
        *out_ptr = co;
        return 1;
    }
    return 0;
}

static int avm_generator_fill_object_mem(const AvmBytes* in, uint32_t* pos, const uint8_t* obj_types, void* const* obj_ptrs, uint32_t obj_count, uint8_t t, uint32_t aux, void* ptr) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    AvmValue* values = NULL;
    if (!slots || aux != slots || !ptr) return 0;
    values = (t == 11) ? ((AvmGeneratorHandle*)ptr)->slots : ((AvmGeneratorContext*)ptr)->slots;
    for (uint32_t i = 0; i < slots; i++) {
        if (!decode_value_mem(in, pos, obj_types, obj_ptrs, obj_count, &values[i])) return 0;
    }
    return 1;
}

static int avm_generator_fill_object_file(FILE* f, uint8_t* obj_types, void** obj_ptrs, uint32_t obj_count, uint8_t t, uint32_t aux, void* ptr) {
    uint32_t slots = avm_generator_slot_count_for_type(t);
    AvmValue* values = NULL;
    if (!slots || aux != slots || !ptr) return 0;
    values = (t == 11) ? ((AvmGeneratorHandle*)ptr)->slots : ((AvmGeneratorContext*)ptr)->slots;
    for (uint32_t i = 0; i < slots; i++) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &values[i])) return 0;
    }
    return 1;
}
