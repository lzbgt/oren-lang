static int oren_type_valid(int t) {
    return t >= OREN_TYPE_NIL && t <= OREN_TYPE_GENERATOR_CONTEXT;
}

static void oren_mark_alloc_ptr(void* ptr) {
#ifdef OREN_NO_GC
    (void)ptr;
    return;
#endif
    if (!ptr) return;
    OrenAllocNode* n = oren_find_node(ptr);
    if (!n || n->freed != 0) return;

    if (n->kind == OREN_ALLOC_STRING) {
        n->freed = -1;
        return;
    }
    if (n->kind == OREN_ALLOC_LIST) {
        n->freed = -1;
        OrenList* lst = (OrenList*)ptr;
        if (!lst) return;
        for (int i = 0; i < lst->count; i++) {
            oren_mark_value(lst->items[i]);
        }
        return;
    }
    if (n->kind == OREN_ALLOC_MAP) {
        n->freed = -1;
        OrenMap* mp = (OrenMap*)ptr;
        if (!mp) return;
        for (int i = 0; i < mp->count; i++) {
            oren_mark_value(mp->keys[i]);
            oren_mark_value(mp->values[i]);
        }
        return;
    }
    if (n->kind == OREN_ALLOC_STRUCT) {
        n->freed = -1;
        // Best-effort: if this looks like an OrenBuf header, keep its payload alive too.
        OrenBuf* b = (OrenBuf*)ptr;
        if (b && (b->elem_size == 1u || b->elem_size == 4u || b->elem_size == 8u)) {
            if (b->data) {
                OrenAllocNode* dn = oren_find_node(b->data);
                if (dn && dn->freed == 0 && (dn->kind == OREN_ALLOC_RAW || dn->kind == OREN_ALLOC_RAW_MMAP)) dn->freed = -1;
            }
        }
        return;
    }
    if (oren_generator_mark_alloc_internal(n, ptr)) return;

    // RAW / unknown allocations are leaf nodes from the GC perspective.
    n->freed = -1;
}

static void oren_mark_ptr_range_words(void* a, void* b) {
    uintptr_t lo = (uintptr_t)a;
    uintptr_t hi = (uintptr_t)b;
    if (lo == 0 || hi == 0) return;
    if (lo > hi) {
        uintptr_t tmp = lo;
        lo = hi;
        hi = tmp;
    }
    lo &= ~(uintptr_t)0x7;
    hi &= ~(uintptr_t)0x7;
    for (uintptr_t p = lo; p + sizeof(uintptr_t) <= hi; p += sizeof(uintptr_t)) {
        uintptr_t w = 0;
        memcpy(&w, (void*)p, sizeof(w));
        if ((w & (uintptr_t)0x7) != 0) continue;
#if defined(__aarch64__)
        w &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
        if (g_alloc_ptr_max < g_alloc_ptr_min) continue;
        if (w < g_alloc_ptr_min || w > g_alloc_ptr_max) continue;
        if (!oren_alloc_bloom_maybe_has(w)) continue;
        oren_mark_alloc_ptr((void*)w);
    }
}

static void oren_mark_stack_range(void* a, void* b) {
    uintptr_t lo = (uintptr_t)a;
    uintptr_t hi = (uintptr_t)b;
    if (lo == 0 || hi == 0) return;
    if (lo > hi) {
        uintptr_t tmp = lo;
        lo = hi;
        hi = tmp;
    }
    lo &= ~(uintptr_t)0x7;
    hi &= ~(uintptr_t)0x7;

    // OrenValue-shaped stack scan (fast path): scan for well-formed OrenValues and mark them.
    // Register-only values are handled separately via `setjmp` snapshots + pointer scanning.
    for (uintptr_t p = lo; p + sizeof(OrenValue) <= hi; p += 8) {
        OrenValue v;
        memcpy(&v, (void*)p, sizeof(OrenValue));
        if (!oren_type_valid((int)v.type)) continue;
        // PERF: Most stack slots are not real OrenValues. Avoid calling into the full mark
        // logic unless the value looks like it contains a plausible heap pointer.
        //
        // For primitive types, there is nothing to mark.
        if (v.type == OREN_TYPE_NIL || v.type == OREN_TYPE_INT || v.type == OREN_TYPE_FLOAT || v.type == OREN_TYPE_BOOL) {
            continue;
        }

        uintptr_t ptr = 0;
        if (v.type == OREN_TYPE_STRING) ptr = (uintptr_t)v.as.string_val;
        else if (v.type == OREN_TYPE_LIST) ptr = (uintptr_t)v.as.list_val;
        else if (v.type == OREN_TYPE_MAP) ptr = (uintptr_t)v.as.map_val;
        else if (v.type == OREN_TYPE_U8_BUF || v.type == OREN_TYPE_I32_BUF || v.type == OREN_TYPE_I64_BUF || v.type == OREN_TYPE_F32_BUF || v.type == OREN_TYPE_F64_BUF) ptr = (uintptr_t)v.as.buf_val;
        else if (oren_generator_ptr_from_value_internal(v, &ptr)) {}
        else if (v.type == OREN_TYPE_FUNC) ptr = (uintptr_t)v.as.func_val.env;
        else {
            // OREN_TYPE_PY_OBJ or unknown future types: nothing for the GC to do here.
            continue;
        }

        // Require natural alignment for GC-managed heap allocations (malloc/posix_memalign).
        if ((ptr & (uintptr_t)0x7) != 0) continue;
#if defined(__aarch64__)
        ptr &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
        if (ptr == 0u) continue;

        // Cheap reject before hitting the allocation index.
        if (g_alloc_ptr_max < g_alloc_ptr_min) continue;
        if (ptr < g_alloc_ptr_min || ptr > g_alloc_ptr_max) continue;
        if (!oren_alloc_bloom_maybe_has(ptr)) continue;

        oren_mark_value(v);
    }
}

typedef struct {
    OrenFn0 fn;
    OrenThreadNode* node;
} OrenSpawn0Args;

static void* oren_spawn0_entry(void* p) {
    // Ensure this thread participates in safepoint GC accounting.
    OrenThreadState* st = oren_thread_state();
    OrenSpawn0Args* a = (OrenSpawn0Args*)p;
    if (st && a && a->node) st->current_task = a->node;

    if (setjmp(st->panic_buf) == 0) {
        st->has_panic_buf = 1;
        OrenValue res = a->fn();
        st->has_panic_buf = 0;
        if (a->node) {
            pthread_mutex_lock(&a->node->mu);
            a->node->done = 1;
            a->node->result = res;
            pthread_cond_broadcast(&a->node->cv);
            pthread_mutex_unlock(&a->node->mu);

            lock_collections();
            int should_free = (a->node->detached && !a->node->joined);
            unlock_collections();
            if (should_free) {
                thread_node_destroy(a->node);
            }
        }
    } else {
        st->has_panic_buf = 0;
        // Panic caught
        if (a->node) {
            pthread_mutex_lock(&a->node->mu);
            a->node->done = 1;
            a->node->result = OREN_NIL;
            a->node->error = strdup("Thread Panicked"); // Generic msg for now
            pthread_cond_broadcast(&a->node->cv);
            pthread_mutex_unlock(&a->node->mu);

            lock_collections();
            int should_free = (a->node->detached && !a->node->joined);
            unlock_collections();
            if (should_free) {
                thread_node_destroy(a->node);
            }
        }
    }
    if (st) st->current_task = NULL;
    free(a);
    oren_thread_unregister();
    return NULL;
}
