static AvmValue avm_clone_generator_handle(CloneTable* tab, AvmGeneratorHandle* gen) {
    if (!gen) return avm_nil();
    void* found = clonetab_find(tab, (void*)gen, 11);
    if (found) { AvmValue r; r.type = AVM_VAL_GENERATOR; r.as.gen = (AvmGeneratorHandle*)found; return r; }
    AvmGeneratorHandle* ng = (AvmGeneratorHandle*)avm_heap_malloc_k(sizeof(AvmGeneratorHandle), AVM_ALLOC_KIND_GENERATOR);
    if (!ng) return avm_nil();
    ng->magic = AVM_GENERATOR_HANDLE_MAGIC;
    for (int i = 0; i < AVM_GENERATOR_HANDLE_SLOTS; i++) ng->slots[i] = avm_nil();
    if (!clonetab_add(tab, (void*)gen, ng, 11)) { avm_heap_free(ng); return avm_nil(); }
    for (int i = 0; i < AVM_GENERATOR_HANDLE_SLOTS; i++) ng->slots[i] = avm_clone_value_rec(tab, gen->slots[i]);
    AvmValue r; r.type = AVM_VAL_GENERATOR; r.as.gen = ng; return r;
}

static AvmValue avm_clone_generator_context(CloneTable* tab, AvmGeneratorContext* co) {
    if (!co) return avm_nil();
    void* found = clonetab_find(tab, (void*)co, 12);
    if (found) { AvmValue r; r.type = AVM_VAL_GENERATOR_CONTEXT; r.as.gctx = (AvmGeneratorContext*)found; return r; }
    AvmGeneratorContext* nc = (AvmGeneratorContext*)avm_heap_malloc_k(sizeof(AvmGeneratorContext), AVM_ALLOC_KIND_GENERATOR_CONTEXT);
    if (!nc) return avm_nil();
    nc->magic = AVM_GENERATOR_CONTEXT_MAGIC;
    for (int i = 0; i < AVM_GENERATOR_CONTEXT_SLOTS; i++) nc->slots[i] = avm_nil();
    if (!clonetab_add(tab, (void*)co, nc, 12)) { avm_heap_free(nc); return avm_nil(); }
    for (int i = 0; i < AVM_GENERATOR_CONTEXT_SLOTS; i++) nc->slots[i] = avm_clone_value_rec(tab, co->slots[i]);
    AvmValue r; r.type = AVM_VAL_GENERATOR_CONTEXT; r.as.gctx = nc; return r;
}
