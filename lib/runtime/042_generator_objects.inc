static const uint64_t OREN_GENERATOR_HANDLE_MAGIC = 0x47454E48414E444CULL;   // "GENHANDL"
static const uint64_t OREN_GENERATOR_CONTEXT_MAGIC = 0x47454E434F4E5448ULL;  // "GENCONTH"

static inline int oren_generator_handle_slot_count(void) {
    return (int)(sizeof(((OrenGeneratorHandle*)0)->slots) / sizeof(OrenValue));
}

static inline int oren_generator_context_slot_count(void) {
    return (int)(sizeof(((OrenGeneratorContext*)0)->slots) / sizeof(OrenValue));
}

static inline OrenGeneratorHandle* oren_generator_handle_ptr(OrenValue obj) {
    if (obj.type != OREN_TYPE_GENERATOR) return NULL;
    OrenGeneratorHandle* gen = obj.as.generator_val;
    if (!gen || gen->magic != OREN_GENERATOR_HANDLE_MAGIC) return NULL;
    return gen;
}

static inline OrenGeneratorContext* oren_generator_context_ptr(OrenValue obj) {
    if (obj.type != OREN_TYPE_GENERATOR_CONTEXT) return NULL;
    OrenGeneratorContext* co = obj.as.generator_context_val;
    if (!co || co->magic != OREN_GENERATOR_CONTEXT_MAGIC) return NULL;
    return co;
}

static inline OrenValue* oren_generator_slot_ptr_internal(OrenValue obj, OrenValue slot) {
    if (slot.type != OREN_TYPE_INT) return NULL;
    long long idx = slot.as.int_val;
    if (idx < 0) return NULL;
    OrenGeneratorHandle* gen = oren_generator_handle_ptr(obj);
    if (gen) {
        if (idx >= oren_generator_handle_slot_count()) return NULL;
        return &gen->slots[idx];
    }
    OrenGeneratorContext* co = oren_generator_context_ptr(obj);
    if (co) {
        if (idx >= oren_generator_context_slot_count()) return NULL;
        return &co->slots[idx];
    }
    return NULL;
}

static int oren_generator_mark_value_internal(OrenValue v) {
    OrenGeneratorHandle* gen = oren_generator_handle_ptr(v);
    if (gen) {
        OrenAllocNode* n = oren_find_node(gen);
        if (n && n->freed == 0 && n->kind == OREN_ALLOC_GENERATOR) {
            n->freed = -1;
            for (int i = 0; i < oren_generator_handle_slot_count(); i++) {
                oren_mark_value(gen->slots[i]);
            }
        }
        return 1;
    }
    OrenGeneratorContext* co = oren_generator_context_ptr(v);
    if (co) {
        OrenAllocNode* n = oren_find_node(co);
        if (n && n->freed == 0 && n->kind == OREN_ALLOC_GENERATOR_CONTEXT) {
            n->freed = -1;
            for (int i = 0; i < oren_generator_context_slot_count(); i++) {
                oren_mark_value(co->slots[i]);
            }
        }
        return 1;
    }
    return 0;
}

static int oren_generator_mark_alloc_internal(OrenAllocNode* n, void* ptr) {
    if (!n) return 0;
    if (n->kind == OREN_ALLOC_GENERATOR) {
        OrenGeneratorHandle* gen = (OrenGeneratorHandle*)ptr;
        if (!gen) return 1;
        n->freed = -1;
        for (int i = 0; i < oren_generator_handle_slot_count(); i++) {
            oren_mark_value(gen->slots[i]);
        }
        return 1;
    }
    if (n->kind == OREN_ALLOC_GENERATOR_CONTEXT) {
        OrenGeneratorContext* co = (OrenGeneratorContext*)ptr;
        if (!co) return 1;
        n->freed = -1;
        for (int i = 0; i < oren_generator_context_slot_count(); i++) {
            oren_mark_value(co->slots[i]);
        }
        return 1;
    }
    return 0;
}

static int oren_generator_ptr_from_value_internal(OrenValue v, uintptr_t* out_ptr) {
    if (!out_ptr) return 0;
    if (v.type == OREN_TYPE_GENERATOR) {
        *out_ptr = (uintptr_t)v.as.generator_val;
        return 1;
    }
    if (v.type == OREN_TYPE_GENERATOR_CONTEXT) {
        *out_ptr = (uintptr_t)v.as.generator_context_val;
        return 1;
    }
    return 0;
}

static int oren_generator_print_internal(OrenValue v) {
    if (v.type == OREN_TYPE_GENERATOR) {
        printf("<generator %p>", (void*)v.as.generator_val);
        return 1;
    }
    if (v.type == OREN_TYPE_GENERATOR_CONTEXT) {
        printf("<generator_context %p>", (void*)v.as.generator_context_val);
        return 1;
    }
    return 0;
}

static OrenValue oren_generator_type_name_internal(OrenValue v) {
    if (v.type == OREN_TYPE_GENERATOR) return oren_string_const("generator");
    if (v.type == OREN_TYPE_GENERATOR_CONTEXT) return oren_string_const("generator_context");
    return OREN_NIL;
}

OrenValue oren_generator_handle_new_internal(
    OrenValue worker,
    OrenValue args_list,
    OrenValue yield_ch,
    OrenValue resume_ch,
    OrenValue done_ch
) {
    OrenGeneratorHandle* gen = (OrenGeneratorHandle*)malloc(sizeof(OrenGeneratorHandle));
    if (!gen) {
        oren_panic("generator handle alloc failed");
        return OREN_NIL;
    }
    gen->magic = OREN_GENERATOR_HANDLE_MAGIC;
    for (int i = 0; i < oren_generator_handle_slot_count(); i++) {
        gen->slots[i] = OREN_NIL;
    }
    gen->slots[1] = worker;
    gen->slots[2] = args_list;
    gen->slots[3] = yield_ch;
    gen->slots[4] = resume_ch;
    gen->slots[5] = done_ch;
    gen->slots[0] = OREN_FALSE;
    gen->slots[7] = OREN_FALSE;
    gen->slots[8] = OREN_FALSE;
    oren_register_alloc(gen, OREN_ALLOC_GENERATOR);
    OrenValue out;
    out.type = OREN_TYPE_GENERATOR;
    out.as.generator_val = gen;
    return out;
}

OrenValue oren_generator_context_new_internal(
    OrenValue yield_ch,
    OrenValue resume_ch,
    OrenValue owner
) {
    OrenGeneratorContext* co = (OrenGeneratorContext*)malloc(sizeof(OrenGeneratorContext));
    if (!co) {
        oren_panic("generator context alloc failed");
        return OREN_NIL;
    }
    co->magic = OREN_GENERATOR_CONTEXT_MAGIC;
    for (int i = 0; i < oren_generator_context_slot_count(); i++) {
        co->slots[i] = OREN_NIL;
    }
    co->slots[1] = yield_ch;
    co->slots[2] = resume_ch;
    co->slots[3] = owner;
    oren_register_alloc(co, OREN_ALLOC_GENERATOR_CONTEXT);
    OrenValue out;
    out.type = OREN_TYPE_GENERATOR_CONTEXT;
    out.as.generator_context_val = co;
    return out;
}

OrenValue oren_generator_slot_get_internal(OrenValue obj, OrenValue slot) {
    OrenValue* p = oren_generator_slot_ptr_internal(obj, slot);
    if (!p) return OREN_NIL;
    return *p;
}

OrenValue oren_generator_slot_set_internal(OrenValue obj, OrenValue slot, OrenValue value) {
    OrenValue* p = oren_generator_slot_ptr_internal(obj, slot);
    if (!p) return OREN_NIL;
    *p = value;
    return value;
}
