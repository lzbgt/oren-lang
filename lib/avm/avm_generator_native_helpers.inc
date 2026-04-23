static AvmGeneratorHandle* avm_generator_handle_ptr(AvmValue v) {
    if (v.type != AVM_VAL_GENERATOR || !v.as.gen) return NULL;
    if (v.as.gen->magic != AVM_GENERATOR_HANDLE_MAGIC) return NULL;
    return v.as.gen;
}

static AvmGeneratorContext* avm_generator_context_ptr(AvmValue v) {
    if (v.type != AVM_VAL_GENERATOR_CONTEXT || !v.as.gctx) return NULL;
    if (v.as.gctx->magic != AVM_GENERATOR_CONTEXT_MAGIC) return NULL;
    return v.as.gctx;
}

static AvmValue* avm_generator_slot_ptr(AvmValue obj, int64_t slot) {
    if (slot < 0) return NULL;
    if (obj.type == AVM_VAL_GENERATOR) {
        AvmGeneratorHandle* gen = avm_generator_handle_ptr(obj);
        if (!gen || slot >= AVM_GENERATOR_HANDLE_SLOTS) return NULL;
        return &gen->slots[slot];
    }
    if (obj.type == AVM_VAL_GENERATOR_CONTEXT) {
        AvmGeneratorContext* co = avm_generator_context_ptr(obj);
        if (!co || slot >= 4) return NULL;
        return &co->slots[slot];
    }
    return NULL;
}

static AvmValue avm_generator_handle_new_internal_value(AvmVM* vm, AvmValue worker, AvmValue args_list, AvmValue yield_ch, AvmValue resume_ch, AvmValue done_ch) {
    (void)vm;
    AvmGeneratorHandle* gen = (AvmGeneratorHandle*)avm_heap_malloc_k(sizeof(AvmGeneratorHandle), AVM_ALLOC_KIND_GENERATOR);
    if (!gen) return avm_alloc_fail_value();
    gen->magic = AVM_GENERATOR_HANDLE_MAGIC;
    for (int i = 0; i < AVM_GENERATOR_HANDLE_SLOTS; i++) gen->slots[i] = avm_nil();
    gen->slots[1] = worker;
    gen->slots[2] = args_list;
    gen->slots[3] = yield_ch;
    gen->slots[4] = resume_ch;
    gen->slots[5] = done_ch;
    gen->slots[7] = avm_bool(0);
    gen->slots[8] = avm_bool(0);
    AvmValue out;
    out.type = AVM_VAL_GENERATOR;
    out.as.gen = gen;
    return out;
}

static AvmValue avm_generator_context_new_internal_value(AvmVM* vm, AvmValue yield_ch, AvmValue resume_ch, AvmValue owner) {
    (void)vm;
    AvmGeneratorContext* co = (AvmGeneratorContext*)avm_heap_malloc_k(sizeof(AvmGeneratorContext), AVM_ALLOC_KIND_GENERATOR_CONTEXT);
    if (!co) return avm_alloc_fail_value();
    co->magic = AVM_GENERATOR_CONTEXT_MAGIC;
    for (int i = 0; i < 4; i++) co->slots[i] = avm_nil();
    co->slots[1] = yield_ch;
    co->slots[2] = resume_ch;
    co->slots[3] = owner;
    AvmValue out;
    out.type = AVM_VAL_GENERATOR_CONTEXT;
    out.as.gctx = co;
    return out;
}
