static void oren_list_grow(OrenList* l, int newCap) {
    if (!l) return;
    if (newCap <= l->capacity) return;
    if (newCap < 1) newCap = 1;
    OrenValue* np = (OrenValue*)realloc(l->items, sizeof(OrenValue) * (size_t)newCap);
    if (!np) {
        oren_panic("list grow: realloc failed");
        return;
    }
    l->items = np;
    l->capacity = newCap;
}

void oren_list_reserve_raw(OrenList* l, int newCap) {
    if (!l) return;
    if (newCap <= l->capacity) return;
    if (newCap < 1) newCap = 1;
    oren_list_grow(l, newCap);
}

OrenValue oren_list_reserve(OrenValue list, OrenValue new_cap) {
    if (list.type == OREN_TYPE_NIL) return OREN_NIL;
    if (new_cap.type == OREN_TYPE_NIL) return OREN_NIL;
    if (new_cap.type == OREN_TYPE_BOOL) {
        oren_panic("list_reserve expects int (got bool)");
        return OREN_NIL;
    }
    if (new_cap.type != OREN_TYPE_INT) {
        oren_panic("list_reserve expects int (got pointer)");
        return OREN_NIL;
    }
    if (new_cap.as.int_val < 0) return OREN_NIL;
    if (list.type != OREN_TYPE_LIST || list.as.list_val == NULL) {
        oren_panic("list_reserve on non-list");
        return OREN_NIL;
    }
    oren_list_reserve_raw(list.as.list_val, (int)new_cap.as.int_val);
    return OREN_NIL;
}

static inline int oren_list_int_check_value(OrenValue v) {
    if (v.type != OREN_TYPE_INT) {
        oren_panic("list_int expects int");
        return 0;
    }
    return 1;
}

static void oren_map_grow(OrenMap* m, int newCap) {
    if (!m) return;
    if (newCap <= m->capacity) return;
    if (newCap < 1) newCap = 1;
    OrenValue* nk = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)newCap);
    OrenValue* nv = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)newCap);
    if (!nk || !nv) {
        if (nk) free(nk);
        if (nv) free(nv);
        oren_panic("map grow: alloc failed");
        return;
    }
    if (m->count > 0) {
        memcpy(nk, m->keys, sizeof(OrenValue) * (size_t)m->count);
        memcpy(nv, m->values, sizeof(OrenValue) * (size_t)m->count);
    }
    if (m->keys) free(m->keys);
    if (m->values) free(m->values);
    m->keys = nk;
    m->values = nv;
    m->capacity = newCap;
}

// --- Thread-safe container ops (rolling) ---
//
// The compiler uses OS threads for parallel parsing. Oren source and compiler subsystems
// still contain shared global state, so list/map operations must be thread-safe.
//
// Use striped mutexes keyed by object address to avoid a single global lock while also
// keeping per-object overhead near-zero (important: AST nodes are tiny maps).
//
// GC note:
// - The collector is stop-the-world (cooperative), so it does not take these locks.
// - Container operations must not call into GC while holding a container lock.

#define OREN_OBJ_LOCKS 4096u
static pthread_mutex_t g_obj_locks[OREN_OBJ_LOCKS];
static pthread_once_t g_obj_locks_once = PTHREAD_ONCE_INIT;
static int g_obj_locks_skip = -1;
static int g_obj_locks_force = -1;
static int g_obj_locks_trace = -1;
static int g_obj_locks_trace_done = 0;

static void oren_obj_locks_init(void) {
    for (size_t i = 0; i < (size_t)OREN_OBJ_LOCKS; i++) {
        pthread_mutex_init(&g_obj_locks[i], NULL);
    }
}

static inline int oren_obj_locks_skip_enabled(void) {
    if (g_obj_locks_skip != -1) return g_obj_locks_skip;
    const char* env = getenv("OREN_LIST_SKIP_LOCKS");
    if (env && env[0] != 0 && env[0] != '0') {
        g_obj_locks_skip = 1;
    } else {
        g_obj_locks_skip = 0;
    }
    return g_obj_locks_skip;
}

static inline int oren_obj_locks_force_enabled(void) {
    if (g_obj_locks_force != -1) return g_obj_locks_force;
    const char* env = getenv("OREN_LIST_FORCE_LOCKS");
    if (env && env[0] != 0 && env[0] != '0') {
        g_obj_locks_force = 1;
    } else {
        g_obj_locks_force = 0;
    }
    return g_obj_locks_force;
}

static inline int oren_obj_locks_trace_enabled(void) {
    if (g_obj_locks_trace != -1) return g_obj_locks_trace;
    const char* env = getenv("OREN_TRACE_LIST_LOCKS");
    if (env && env[0] != 0 && env[0] != '0') {
        g_obj_locks_trace = 1;
    } else {
        g_obj_locks_trace = 0;
    }
    return g_obj_locks_trace;
}

static inline pthread_mutex_t* oren_obj_lock_for_ptr(void* p) {
    if (oren_obj_locks_trace_enabled() && !g_obj_locks_trace_done) {
        g_obj_locks_trace_done = 1;
        fprintf(stderr,
                "trace: list locks skip=%d force=%d threads_started=%d\n",
                oren_obj_locks_skip_enabled(),
                oren_obj_locks_force_enabled(),
                (int)OREN_ATOMIC_LOAD_INT(&g_threads_started));
    }
    if (!oren_obj_locks_force_enabled()) {
        if (oren_obj_locks_skip_enabled()) return NULL;
        if (OREN_ATOMIC_LOAD_INT(&g_threads_started) == 0) return NULL;
    }
    (void)pthread_once(&g_obj_locks_once, oren_obj_locks_init);
    size_t h = oren_ptr_hash(p);
    return &g_obj_locks[h & (OREN_OBJ_LOCKS - 1u)];
}

int oren_list_locking_needed(void) {
    if (oren_obj_locks_force_enabled()) return 1;
    if (oren_obj_locks_skip_enabled()) return 0;
    if (OREN_ATOMIC_LOAD_INT(&g_threads_started) == 0) return 0;
    return 1;
}

static inline void oren_obj_lock(pthread_mutex_t* mu) {
    if (!mu) return;
    pthread_mutex_lock(mu);
}

static inline void oren_obj_unlock(pthread_mutex_t* mu) {
    if (!mu) return;
    pthread_mutex_unlock(mu);
}

static inline int oren_map_key_rank(OrenType t) {
    // Keep in sync with map insertion ordering.
    return (t == OREN_TYPE_NIL) ? 0 :
           (t == OREN_TYPE_BOOL) ? 1 :
           (t == OREN_TYPE_INT) ? 2 :
           (t == OREN_TYPE_STRING) ? 3 : 99;
}

static inline int oren_map_key_cmp(OrenValue a, OrenValue b) {
    int ra = oren_map_key_rank(a.type);
    int rb = oren_map_key_rank(b.type);
    if (ra != rb) return (ra < rb) ? -1 : 1;
    if (a.type == OREN_TYPE_NIL) return 0;
    if (a.type == OREN_TYPE_BOOL) {
        return (a.as.bool_val < b.as.bool_val) ? -1 : (a.as.bool_val > b.as.bool_val) ? 1 : 0;
    }
    if (a.type == OREN_TYPE_INT) {
        return (a.as.int_val < b.as.int_val) ? -1 : (a.as.int_val > b.as.int_val) ? 1 : 0;
    }
    if (a.type == OREN_TYPE_STRING) {
        int c = strcmp(a.as.string_val, b.as.string_val);
        if (c < 0) return -1;
        if (c > 0) return 1;
        return 0;
    }
    // Unsupported key types should be rejected at call sites.
    return 0;
}

static inline int oren_map_key_eq(OrenValue a, OrenValue b) {
    if (a.type != b.type) return 0;
    if (a.type == OREN_TYPE_NIL) return 1;
    if (a.type == OREN_TYPE_BOOL) return a.as.bool_val == b.as.bool_val;
    if (a.type == OREN_TYPE_INT) return a.as.int_val == b.as.int_val;
    if (a.type == OREN_TYPE_STRING) return strcmp(a.as.string_val, b.as.string_val) == 0;
    return 0;
}

OrenValue oren_new_list(int count, ...) {
    va_list args;
    va_start(args, count);

    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    if (count < 0) count = 0;
    list->count = count;
    list->capacity = count;
    list->items = NULL;
    list->all_int = 1;
    if (count > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)count);
        if (!list->items) {
            va_end(args);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("new_list: alloc failed"));
        }
    }

    for (int i = 0; i < count; i++) {
        list->items[i] = va_arg(args, OrenValue); // NOTE: passing structs via varargs is UB; avoid in new codegen.
        if (list->all_int && list->items[i].type != OREN_TYPE_INT) list->all_int = 0;
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_new_list_from_array(int count, const OrenValue* items) {
    if (count < 0) count = 0;
    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = count;
    list->capacity = count;
    list->items = NULL;
    list->all_int = 1;
    if (count > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)count);
        if (!list->items) {
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("new_list_from_array: alloc failed"));
        }
    }
    if (items) {
        if (count > 0) {
            memcpy(list->items, items, sizeof(OrenValue) * (size_t)count);
            for (int i = 0; i < count; i++) {
                if (list->items[i].type != OREN_TYPE_INT) { list->all_int = 0; break; }
            }
        }
    } else {
        for (int i = 0; i < count; i++) list->items[i] = OREN_NIL;
        if (count > 0) list->all_int = 0;
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_list_len(OrenValue list) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("len on non-list");
        return OREN_NIL; // Should not be reached
    }
    OrenList* l = list.as.list_val;
    if (!l) return oren_int(0);
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
    oren_obj_lock(mu);
    int c = l->count;
    oren_obj_unlock(mu);
    return oren_int(c);
}

OrenValue oren_is_list(OrenValue v) {
    return oren_bool(v.type == OREN_TYPE_LIST);
}

OrenValue oren_is_list_int(OrenValue v) {
    return oren_bool(v.type == OREN_TYPE_LIST && v.as.list_val && v.as.list_val->all_int);
}

OrenValue oren_list_push(OrenValue list, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("push on non-list");
        return OREN_NIL; // Should not be reached
    }
    OrenList *l = list.as.list_val;
    if (!l) {
        oren_panic("push on nil list");
        return OREN_NIL;
    }
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
    oren_obj_lock(mu);
    if (l->count >= l->capacity) {
        int newCap = l->capacity < 1 ? 4 : l->capacity * 2;
        oren_list_grow(l, newCap);
    }
    l->items[l->count] = value;
    l->count += 1;
    if (l->all_int && value.type != OREN_TYPE_INT) l->all_int = 0;
    oren_obj_unlock(mu);
    // Language-level semantics: `oren_list_push` returns `nil`.
    return OREN_NIL;
}

OrenValue oren_list_push_unchecked(OrenValue list, OrenValue value) {
    // Tooling/internal fast-path: still validates the outer type, but otherwise behaves like push.
    // This keeps the portable API surface consistent across backends.
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("push_unchecked on non-list");
        return OREN_NIL;
    }
    OrenList *l = list.as.list_val;
    if (!l) {
        oren_panic("push_unchecked on nil list");
        return OREN_NIL;
    }
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
    oren_obj_lock(mu);
    if (l->count >= l->capacity) {
        int newCap = l->capacity < 1 ? 4 : l->capacity * 2;
        oren_list_grow(l, newCap);
    }
    l->items[l->count] = value;
    l->count += 1;
    if (l->all_int && value.type != OREN_TYPE_INT) l->all_int = 0;
    oren_obj_unlock(mu);
    return OREN_NIL;
}

OrenValue oren_list_get(OrenValue list, OrenValue index) {
    if (list.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
             oren_panic("index must be integer");
             return OREN_NIL; // Should not be reached
        }
        OrenList* l = list.as.list_val;
        if (!l) {
            oren_panic("index get on nil list");
            return OREN_NIL;
        }
        pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
        oren_obj_lock(mu);
        int idx = (int)index.as.int_val;
        int cnt = l->count;
        if (idx < 0 || idx >= cnt) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, cnt);
            oren_obj_unlock(mu);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        OrenValue v = l->items[idx];
        oren_obj_unlock(mu);
        return v;
    }
    // Also support python list get item?
#ifdef OREN_ENABLE_PYTHON
    if (list.type == OREN_TYPE_PY_OBJ) {
         PyObject* py_index = oren_to_py(index);
         PyObject* item = PyObject_GetItem(list.as.py_obj, py_index);
         Py_DECREF(py_index);
         if (!item) {
             PyErr_Print();
             oren_panic("Python list get item failed");
             return OREN_NIL; // Should not be reached
         }
         return oren_py_to_oren(item);
    }
#else
    if (list.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    // Support map access via []
    if (list.type == OREN_TYPE_MAP) {
        return oren_map_get(list, index);
    }

    oren_panic("index get on non-list/map");
    return OREN_NIL; // Should not be reached
}

// Set list element in-bounds (does not grow). Returns the written value.
OrenValue oren_list_set(OrenValue list, OrenValue index, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("list_set on non-list");
        return value; // Should not be reached
    }
    if (index.type != OREN_TYPE_INT) {
        oren_panic("list_set index must be int");
        return value; // Should not be reached
    }
    OrenList* l = list.as.list_val;
    if (!l) {
        oren_panic("list_set on nil list");
        return value;
    }
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
    oren_obj_lock(mu);
    int idx = (int)index.as.int_val;
    int cnt = l->count;
    if (idx < 0 || idx >= cnt) {
        oren_obj_unlock(mu);
        oren_panic("list_set index out of bounds");
        return value; // Should not be reached
    }
    l->items[idx] = value;
    if (l->all_int && value.type != OREN_TYPE_INT) l->all_int = 0;
    oren_obj_unlock(mu);
    return value;
}

// --- list<int> helpers (boxed ints in C backend) ---
OrenValue oren_new_list_int(OrenValue cap) {
    return oren_list_new_cap(cap);
}

// Arena helpers (C backend fallback: arenas are not supported, so use GC list allocs).
OrenValue oren_arena_push(void) { return OREN_NIL; }
OrenValue oren_arena_pop(void) { return OREN_NIL; }
OrenValue oren_arena_new_list(OrenValue cap) { return oren_list_new_cap(cap); }
OrenValue oren_arena_new_list_int(OrenValue cap) { return oren_new_list_int(cap); }
OrenValue oren_arena_new_list_auto(OrenValue cap) { return oren_arena_new_list(cap); }
OrenValue oren_arena_new_list_int_auto(OrenValue cap) { return oren_arena_new_list_int(cap); }

OrenValue oren_list_int_len(OrenValue list) {
    return oren_list_len(list);
}

OrenValue oren_list_int_len_unchecked(OrenValue list) {
    if (list.type != OREN_TYPE_LIST || list.as.list_val == NULL) return oren_int(0);
    return oren_int(list.as.list_val->count);
}

OrenValue oren_list_int_push(OrenValue list, OrenValue value) {
    if (!oren_list_int_check_value(value)) return OREN_NIL;
    return oren_list_push(list, value);
}

OrenValue oren_list_int_push_unchecked(OrenValue list, OrenValue value) {
    if (!oren_list_int_check_value(value)) return OREN_NIL;
    return oren_list_push_unchecked(list, value);
}

OrenValue oren_list_int_get(OrenValue list, OrenValue index) {
    if (list.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
             oren_panic("index must be integer");
             return OREN_NIL; // Should not be reached
        }
        OrenList* l = list.as.list_val;
        if (!l) {
            oren_panic("index get on nil list");
            return OREN_NIL;
        }
        pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
        oren_obj_lock(mu);
        int idx = (int)index.as.int_val;
        int cnt = l->count;
        if (idx < 0 || idx >= cnt) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, cnt);
            oren_obj_unlock(mu);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        OrenValue v = l->items[idx];
        oren_obj_unlock(mu);
        return v;
    }
#ifdef OREN_ENABLE_PYTHON
    if (list.type == OREN_TYPE_PY_OBJ) {
         PyObject* py_index = oren_to_py(index);
         PyObject* item = PyObject_GetItem(list.as.py_obj, py_index);
         Py_DECREF(py_index);
         if (!item) {
             PyErr_Print();
             oren_panic("Python list get item failed");
             return OREN_NIL; // Should not be reached
         }
         return oren_py_to_oren(item);
    }
#else
    if (list.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    if (list.type == OREN_TYPE_MAP) {
        return oren_map_get(list, index);
    }

    oren_panic("index get on non-list/map");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_list_int_set(OrenValue list, OrenValue index, OrenValue value) {
    if (!oren_list_int_check_value(value)) return OREN_NIL;
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("list_set on non-list");
        return value; // Should not be reached
    }
    if (index.type != OREN_TYPE_INT) {
        oren_panic("list_set index must be int");
        return value; // Should not be reached
    }
    OrenList* l = list.as.list_val;
    if (!l) {
        oren_panic("list_set on nil list");
        return value;
    }
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
    oren_obj_lock(mu);
    int idx = (int)index.as.int_val;
    int cnt = l->count;
    if (idx < 0 || idx >= cnt) {
        oren_obj_unlock(mu);
        oren_panic("list_set index out of bounds");
        return value; // Should not be reached
    }
    l->items[idx] = value;
    oren_obj_unlock(mu);
    return value;
}

OrenValue oren_list_int_reserve(OrenValue list, OrenValue new_cap) {
    if (list.type == OREN_TYPE_NIL) return OREN_NIL;
    if (new_cap.type == OREN_TYPE_NIL) return OREN_NIL;
    if (new_cap.type == OREN_TYPE_BOOL) {
        oren_panic("list_int_reserve expects int (got bool)");
        return OREN_NIL;
    }
    if (new_cap.type != OREN_TYPE_INT) {
        oren_panic("list_int_reserve expects int (got pointer)");
        return OREN_NIL;
    }
    if (new_cap.as.int_val < 0) return OREN_NIL;
    if (list.type != OREN_TYPE_LIST || list.as.list_val == NULL) {
        oren_panic("list_int_reserve on non-list");
        return OREN_NIL;
    }
    oren_list_reserve_raw(list.as.list_val, (int)new_cap.as.int_val);
    return OREN_NIL;
}

static int list_int_slots_try_get(OrenValue list, OrenList** out) {
    if (list.type != OREN_TYPE_LIST || list.as.list_val == NULL) return 0;
    OrenList* l = list.as.list_val;
    if (!l->all_int) return 0;
    *out = l;
    return 1;
}

static int list_int_slots_require_unchecked(OrenValue list, const char* ctx, OrenList** out) {
    if (list_int_slots_try_get(list, out)) return 1;
    oren_panic(ctx);
    return 0;
}

static OrenValue list_int_slots_invalid_arg(const char* msg) {
    return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(msg));
}

OrenValue oren_list_int_reduce_sum_slots(OrenValue list) {
    if (list.type == OREN_TYPE_NIL) return oren_int(0);
    lock_collections();
    OrenList* l = NULL;
    if (!list_int_slots_try_get(list, &l)) {
        unlock_collections();
        return list_int_slots_invalid_arg("oren_list_int_reduce_sum_slots expects list<int>");
    }
    uint64_t acc = 0;
    for (int i = 0; i < l->count; i++) acc += (uint64_t)l->items[i].as.int_val;
    unlock_collections();
    return oren_int((int64_t)acc);
}

OrenValue oren_list_int_reduce_sum_slots_try_fast(OrenValue list) {
    if (list.type == OREN_TYPE_NIL) return oren_int(0);
    lock_collections();
    OrenList* l = NULL;
    if (!list_int_slots_try_get(list, &l)) {
        unlock_collections();
        return OREN_NIL;
    }
    uint64_t acc = 0;
    for (int i = 0; i < l->count; i++) acc += (uint64_t)l->items[i].as.int_val;
    unlock_collections();
    return oren_int((int64_t)acc);
}

OrenValue oren_list_int_reduce_sum_slots_unchecked(OrenValue list) {
    if (list.type == OREN_TYPE_NIL) return oren_int(0);
    lock_collections();
    OrenList* l = NULL;
    if (!list_int_slots_require_unchecked(list, "list_int_reduce_sum_slots_unchecked on non-list", &l)) {
        unlock_collections();
        return OREN_NIL;
    }
    uint64_t acc = 0;
    for (int i = 0; i < l->count; i++) acc += (uint64_t)l->items[i].as.int_val;
    unlock_collections();
    return oren_int((int64_t)acc);
}

OrenValue oren_list_int_dot_slots(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_NIL || b.type == OREN_TYPE_NIL) {
        if (a.type == OREN_TYPE_NIL && b.type == OREN_TYPE_NIL) return oren_int(0);
        return list_int_slots_invalid_arg("list_int_dot_slots: length mismatch");
    }
    lock_collections();
    OrenList* la = NULL;
    OrenList* lb = NULL;
    if (!list_int_slots_try_get(a, &la) ||
        !list_int_slots_try_get(b, &lb)) {
        unlock_collections();
        return list_int_slots_invalid_arg("oren_list_int_dot_slots expects (list<int>, list<int>)");
    }
    if (la->count != lb->count) {
        unlock_collections();
        return list_int_slots_invalid_arg("list_int_dot_slots: length mismatch");
    }
    uint64_t acc = 0;
    for (int i = 0; i < la->count; i++) {
        int64_t prod = (int64_t)la->items[i].as.int_val * (int64_t)lb->items[i].as.int_val;
        acc += (uint64_t)prod;
    }
    unlock_collections();
    return oren_int((int64_t)acc);
}

OrenValue oren_list_int_dot_slots_try_fast(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_NIL || b.type == OREN_TYPE_NIL) {
        if (a.type == OREN_TYPE_NIL && b.type == OREN_TYPE_NIL) return oren_int(0);
        return OREN_NIL;
    }
    lock_collections();
    OrenList* la = NULL;
    OrenList* lb = NULL;
    if (!list_int_slots_try_get(a, &la) ||
        !list_int_slots_try_get(b, &lb)) {
        unlock_collections();
        return OREN_NIL;
    }
    if (la->count != lb->count) {
        unlock_collections();
        return list_int_slots_invalid_arg("list_int_dot_slots: length mismatch");
    }
    uint64_t acc = 0;
    for (int i = 0; i < la->count; i++) {
        int64_t prod = (int64_t)la->items[i].as.int_val * (int64_t)lb->items[i].as.int_val;
        acc += (uint64_t)prod;
    }
    unlock_collections();
    return oren_int((int64_t)acc);
}

OrenValue oren_list_int_dot_slots_unchecked(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_NIL || b.type == OREN_TYPE_NIL) {
        if (a.type == OREN_TYPE_NIL && b.type == OREN_TYPE_NIL) return oren_int(0);
        oren_panic("list_int_dot_slots_unchecked: length mismatch");
        return OREN_NIL;
    }
    lock_collections();
    OrenList* la = NULL;
    OrenList* lb = NULL;
    if (!list_int_slots_require_unchecked(a, "list_int_dot_slots_unchecked on non-list", &la) ||
        !list_int_slots_require_unchecked(b, "list_int_dot_slots_unchecked on non-list", &lb)) {
        unlock_collections();
        return OREN_NIL;
    }
    if (la->count != lb->count) {
        unlock_collections();
        oren_panic("list_int_dot_slots_unchecked: length mismatch");
        return OREN_NIL;
    }
    uint64_t acc = 0;
    for (int i = 0; i < la->count; i++) {
        int64_t prod = (int64_t)la->items[i].as.int_val * (int64_t)lb->items[i].as.int_val;
        acc += (uint64_t)prod;
    }
    unlock_collections();
    return oren_int((int64_t)acc);
}


OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value) {
    if (container.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
            oren_panic("index must be integer");
            return value; // Should not be reached
        }
        OrenList* l = container.as.list_val;
        if (!l) {
            oren_panic("index_set on nil list");
            return value;
        }
        pthread_mutex_t* mu = oren_obj_lock_for_ptr(l);
        oren_obj_lock(mu);
        int idx = (int)index.as.int_val;
        if (idx < 0) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, l->count);
            oren_obj_unlock(mu);
            oren_panic(buf);
            return value; // Should not be reached
        }
        if (idx >= l->capacity) {
            int newCap = (l->capacity == 0) ? (idx + 1) : l->capacity;
            if (newCap < 4) newCap = 4;
            while (newCap <= idx) { newCap *= 2; }
            oren_list_grow(l, newCap);
        }
        if (idx >= l->count) {
            // zero-fill new slots
            for (int i = l->count; i <= idx; i++) {
                l->items[i] = OREN_NIL;
            }
            l->count = idx + 1;
            if (l->all_int) l->all_int = 0;
        }
        l->items[idx] = value;
        if (l->all_int && value.type != OREN_TYPE_INT) l->all_int = 0;
        oren_obj_unlock(mu);
        return value;
    }

    if (container.type == OREN_TYPE_MAP) {
        OrenMap* map = container.as.map_val;
        if (!map) {
            oren_panic("index_set on nil map");
            return value;
        }
        pthread_mutex_t* mu = oren_obj_lock_for_ptr(map);
        oren_obj_lock(mu);
        if (!(index.type == OREN_TYPE_NIL || index.type == OREN_TYPE_BOOL || index.type == OREN_TYPE_INT || index.type == OREN_TYPE_STRING)) {
            oren_obj_unlock(mu);
            oren_panic("map key type not supported (need nil/bool/int/string)");
            return value; // Should not be reached
        }

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int cmp = oren_map_key_cmp(mk, index);

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_map_key_eq(map->keys[idx], index)) {
            map->values[idx] = value;
            oren_obj_unlock(mu);
            return value;
        }

        if (map->count >= map->capacity) {
            int newCap = (map->capacity == 0) ? 4 : map->capacity * 2;
            oren_map_grow(map, newCap);
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = index;
        map->values[idx] = value;
        map->count += 1;
        oren_obj_unlock(mu);
        return value;
    }

#ifdef OREN_ENABLE_PYTHON
    if (container.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_index = oren_to_py(index);
        PyObject* py_value = oren_to_py(value);
        if (PyObject_SetItem(container.as.py_obj, py_index, py_value) != 0) {
            PyErr_Print();
            oren_panic("python setitem failed");
            return value; // Should not be reached
        }
        Py_DECREF(py_index);
        Py_DECREF(py_value);
        return value;
    }
#else
    if (container.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        (void)value;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return value; // Should not be reached
    }
#endif

    oren_panic("index set on non-list/map");
    return value; // Should not be reached
}

OrenValue oren_new_map(int count, ...) {
    va_list args;
    va_start(args, count);

    OrenMap* map = malloc(sizeof(OrenMap));
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = 0;
    if (count < 0) count = 0;
    map->capacity = count;
    map->keys = NULL;
    map->values = NULL;
    if (count > 0) {
        map->keys = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)count);
        map->values = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)count);
        if (!map->keys || !map->values) {
            if (map->keys) free(map->keys);
            if (map->values) free(map->values);
            va_end(args);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("new_map: alloc failed"));
        }
    }

    // Deterministic ordered maps (rolling): keep keys in sorted order.
    // Supported key types: NIL, BOOL, INT, STRING.
    // Ordering: NIL < BOOL < INT < STRING.
    // Duplicate keys: last assignment wins.
    for (int i = 0; i < count; i++) {
        OrenValue key = va_arg(args, OrenValue);
        OrenValue value = va_arg(args, OrenValue);

        if (!(key.type == OREN_TYPE_NIL || key.type == OREN_TYPE_BOOL || key.type == OREN_TYPE_INT || key.type == OREN_TYPE_STRING)) {
            oren_panic("map key type not supported (need nil/bool/int/string)");
            break;
        }

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int cmp = oren_map_key_cmp(mk, key);

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_map_key_eq(map->keys[idx], key)) {
            map->values[idx] = value;
            continue;
        }

        if (map->count >= map->capacity) {
            int newCap = (map->capacity == 0) ? 4 : map->capacity * 2;
            oren_map_grow(map, newCap);
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = key;
        map->values[idx] = value;
        map->count += 1;
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_MAP;
    v.as.map_val = map;
    return v;
}

OrenValue oren_list_new_cap(OrenValue capv) {
    if (capv.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("list_new_cap expects int"));
    }
    long long cap0 = capv.as.int_val;
    if (cap0 < 0) cap0 = 0;
    if (cap0 > (long long)INT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("list_new_cap: cap too large"));
    }

    int cap = (int)cap0;
    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("list_new_cap: alloc failed"));
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = 0;
    list->capacity = cap;
    list->items = NULL;
    list->all_int = 1;
    if (cap > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)cap);
        if (!list->items) {
            free(list);
            unlock_collections();
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("list_new_cap: alloc failed"));
        }
    }
    unlock_collections();

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_map_new_cap(OrenValue capv) {
    if (capv.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("map_new_cap expects int"));
    }
    long long cap0 = capv.as.int_val;
    if (cap0 < 0) cap0 = 0;
    if (cap0 > (long long)INT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("map_new_cap: cap too large"));
    }

    int cap = (int)cap0;
    lock_collections();
    OrenMap* map = malloc(sizeof(OrenMap));
    if (!map) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("map_new_cap: alloc failed"));
    }
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = 0;
    map->capacity = cap;
    map->keys = NULL;
    map->values = NULL;
    if (cap > 0) {
        map->keys = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)cap);
        map->values = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)cap);
        if (!map->keys || !map->values) {
            if (map->keys) free(map->keys);
            if (map->values) free(map->values);
            free(map);
            unlock_collections();
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("map_new_cap: alloc failed"));
        }
    }
    unlock_collections();

    OrenValue v;
    v.type = OREN_TYPE_MAP;
    v.as.map_val = map;
    return v;
}

OrenValue oren_new_map_from_pairs(int count, const OrenValue* kv_pairs) {
    if (count < 0) count = 0;
    OrenMap* map = malloc(sizeof(OrenMap));
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = 0;
    map->capacity = count;
    map->keys = NULL;
    map->values = NULL;
    if (count > 0) {
        map->keys = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)count);
        map->values = (OrenValue*)malloc(sizeof(OrenValue) * (size_t)count);
        if (!map->keys || !map->values) {
            if (map->keys) free(map->keys);
            if (map->values) free(map->values);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("new_map_from_pairs: alloc failed"));
        }
    }

    for (int i = 0; i < count; i++) {
        OrenValue key = kv_pairs ? kv_pairs[i * 2 + 0] : OREN_NIL;
        OrenValue value = kv_pairs ? kv_pairs[i * 2 + 1] : OREN_NIL;

        if (!(key.type == OREN_TYPE_NIL || key.type == OREN_TYPE_BOOL || key.type == OREN_TYPE_INT || key.type == OREN_TYPE_STRING)) {
            oren_panic("map key type not supported (need nil/bool/int/string)");
            break;
        }

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int cmp = oren_map_key_cmp(mk, key);

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_map_key_eq(map->keys[idx], key)) {
            map->values[idx] = value;
            continue;
        }

        if (map->count >= map->capacity) {
            int newCap = (map->capacity == 0) ? 4 : map->capacity * 2;
            oren_map_grow(map, newCap);
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = key;
        map->values[idx] = value;
        map->count += 1;
    }

    OrenValue v;
    v.type = OREN_TYPE_MAP;
    v.as.map_val = map;
    return v;
}

OrenValue oren_map_get(OrenValue map, OrenValue key) {
    if (map.type != OREN_TYPE_MAP) return OREN_NIL;
    OrenMap* m = map.as.map_val;
    if (!m) return OREN_NIL;
    if (!(key.type == OREN_TYPE_NIL || key.type == OREN_TYPE_BOOL || key.type == OREN_TYPE_INT || key.type == OREN_TYPE_STRING)) {
        oren_panic("map key type not supported (need nil/bool/int/string)");
        return OREN_NIL; // Should not be reached
    }

    pthread_mutex_t* mu = oren_obj_lock_for_ptr(m);
    oren_obj_lock(mu);
    int lo = 0;
    int hi = m->count;
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        OrenValue mk = m->keys[mid];
        int cmp = oren_map_key_cmp(mk, key);
        if (cmp < 0) lo = mid + 1;
        else hi = mid;
    }

    OrenValue out = OREN_NIL;
    if (lo < m->count && oren_map_key_eq(m->keys[lo], key)) {
        out = m->values[lo];
    }
    oren_obj_unlock(mu);
    return out;
}

OrenValue oren_map_get_int(OrenValue map, OrenValue key) {
    if (key.type != OREN_TYPE_INT) {
        if (key.type == OREN_TYPE_NIL) return OREN_NIL;
        oren_panic("map_get_int expects int key");
        return OREN_NIL; // Should not be reached
    }
    return oren_map_get(map, key);
}

OrenValue oren_map_get_str(OrenValue map, OrenValue key) {
    if (key.type != OREN_TYPE_STRING) {
        if (key.type == OREN_TYPE_NIL) return OREN_NIL;
        oren_panic("map_get_str expects string key");
        return OREN_NIL; // Should not be reached
    }
    return oren_map_get(map, key);
}

OrenValue oren_map_set(OrenValue map, OrenValue key, OrenValue value) {
    // Keep runtime behavior consistent with `m[key] = value`.
    return oren_index_set(map, key, value);
}

OrenValue oren_map_set_int(OrenValue map, OrenValue key, OrenValue value) {
    if (key.type != OREN_TYPE_INT) {
        oren_panic("map_set_int expects int key");
        return value; // Should not be reached
    }
    return oren_index_set(map, key, value);
}

OrenValue oren_map_set_str(OrenValue map, OrenValue key, OrenValue value) {
    if (key.type != OREN_TYPE_STRING) {
        if (key.type == OREN_TYPE_NIL) {
            oren_panic("map_set_str expects non-nil string key");
            return value; // Should not be reached
        }
        oren_panic("map_set_str expects string key");
        return value; // Should not be reached
    }
    return oren_index_set(map, key, value);
}

OrenValue oren_map_set_int_unchecked(OrenValue map, OrenValue key, OrenValue value) {
    // Tooling/internal fast-path: keep behavior deterministic but avoid extra layering in the compiler.
    return oren_map_set_int(map, key, value);
}

OrenValue oren_map_set_str_unchecked(OrenValue map, OrenValue key, OrenValue value) {
    return oren_map_set_str(map, key, value);
}

OrenValue oren_map_push_entry_int_unchecked(OrenValue map, OrenValue key, OrenValue value) {
    // Tooling/internal builder fast-path (portable):
    // C backend keeps maps sorted; implement this in terms of the regular set helper.
    return oren_map_set_int_unchecked(map, key, value);
}

OrenValue oren_map_push_entry_str_unchecked(OrenValue map, OrenValue key, OrenValue value) {
    return oren_map_set_str_unchecked(map, key, value);
}

OrenValue oren_map_build_finalize_unchecked(OrenValue map, OrenValue want_entries) {
    // No-op for the C backend map representation (always sorted, no hash index).
    (void)want_entries;
    return map;
}

OrenValue oren_map_len(OrenValue map) {
    if (map.type != OREN_TYPE_MAP) {
        oren_panic("len on non-map");
        return OREN_NIL; // Should not be reached
    }
    OrenMap* m = map.as.map_val;
    if (!m) return oren_int(0);
    pthread_mutex_t* mu = oren_obj_lock_for_ptr(m);
    oren_obj_lock(mu);
    int c = m->count;
    oren_obj_unlock(mu);
    return oren_int(c);
}

OrenValue oren_is_map(OrenValue v) {
    return oren_bool(v.type == OREN_TYPE_MAP);
}

OrenValue oren_call_obj_argv(OrenValue fn, int argc, OrenValue* argv) {
    if (fn.type == OREN_TYPE_FUNC) {
        return fn.as.func_val.fn(fn.as.func_val.env, argc, argv);
    }

#ifdef OREN_ENABLE_PYTHON
    if (fn.type == OREN_TYPE_PY_OBJ) {
        if (!PyCallable_Check(fn.as.py_obj)) {
            oren_panic("Python object is not callable");
            return OREN_NIL; // Should not be reached
        }
        PyObject* py_args = PyTuple_New(argc);
        for (int i = 0; i < argc; i++) {
            PyTuple_SetItem(py_args, i, oren_to_py(argv[i])); // Steals ref
        }
        PyObject* result = PyObject_CallObject(fn.as.py_obj, py_args);
        Py_DECREF(py_args);
        if (!result) {
            PyErr_Print();
            oren_panic("Python call failed");
            return OREN_NIL; // Should not be reached
        }
        return oren_py_to_oren(result);
    }
#else
    if (fn.type == OREN_TYPE_PY_OBJ) {
        (void)argc;
        (void)argv;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    oren_panic("Calling non-callable object");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_call_obj_list(OrenValue fn, OrenValue args_list) {
    if (args_list.type != OREN_TYPE_LIST) {
        oren_panic("call_obj_list expects args_list to be a list");
        return OREN_NIL; // Should not be reached
    }
    OrenList* l = args_list.as.list_val;
    int argc = 0;
    OrenValue* argv = NULL;
    if (l) {
        argc = l->count;
        argv = l->items;
    }
    return oren_call_obj_argv(fn, argc, argv);
}

OrenValue oren_call_obj(OrenValue fn, int count, ...) {
    if (fn.type == OREN_TYPE_FUNC) {
        OrenValue* argv = NULL;
        if (count > 0) {
            argv = (OrenValue*)calloc((size_t)count, sizeof(OrenValue));
            if (!argv) {
                oren_panic("oren_call_obj: out of memory");
            }
        }
        va_list args;
        va_start(args, count);
        for (int i = 0; i < count; i++) {
            argv[i] = va_arg(args, OrenValue);
        }
        va_end(args);
        OrenValue out = fn.as.func_val.fn(fn.as.func_val.env, count, argv);
        if (argv) free(argv);
        return out;
    }

    va_list args;
    va_start(args, count);

#ifdef OREN_ENABLE_PYTHON
    if (fn.type == OREN_TYPE_PY_OBJ) {
        if (!PyCallable_Check(fn.as.py_obj)) {
            oren_panic("Python object is not callable");
            return OREN_NIL; // Should not be reached
        }
        PyObject* py_args = PyTuple_New(count);
        for (int i = 0; i < count; i++) {
            OrenValue arg = va_arg(args, OrenValue);
            PyTuple_SetItem(py_args, i, oren_to_py(arg)); // Steals ref
        }
        PyObject* result = PyObject_CallObject(fn.as.py_obj, py_args);
        Py_DECREF(py_args);
        if (!result) {
            PyErr_Print();
            oren_panic("Python call failed");
            return OREN_NIL; // Should not be reached
        }
        va_end(args);
        return oren_py_to_oren(result);
    }
#else
    if (fn.type == OREN_TYPE_PY_OBJ) {
        (void)count;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    oren_panic("Calling non-callable object (only Python callables supported via generic call so far)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_neq(OrenValue a, OrenValue b) {
    OrenValue eq = oren_eq(a, b);
    return eq.as.bool_val ? OREN_FALSE : OREN_TRUE;
}

OrenValue oren_bool_norm(OrenValue v) {
    // bool cast semantics (rolling):
    // - nil  -> false
    // - bool -> identity
    // - int  -> (v != 0)
    // - float-> (v != 0.0)
    // - other heap/object values -> true
    //
    // IMPORTANT: do not use `oren_is_truthy` for ints here; v0 truthiness treats all ints as truthy.
    switch (v.type) {
        case OREN_TYPE_NIL: return OREN_FALSE;
        case OREN_TYPE_BOOL: return v;
        case OREN_TYPE_INT: return oren_bool(v.as.int_val != 0);
        case OREN_TYPE_FLOAT: return oren_bool(v.as.float_val != 0.0);
        default: return OREN_TRUE;
    }
}

OrenValue oren_trunc_int(OrenValue v) {
    // Numeric truncation semantics (rolling, cross-backend deterministic):
    // - int   -> identity
    // - float -> truncate toward zero (discard fractional part)
    //
    // Special float values (deterministic, no UB):
    // - NaN   -> 0
    // - +inf / overflow -> INT64_MAX
    // - -inf / overflow -> INT64_MIN
    //
    // Rationale:
    // - Native backend uses an ARM64 lowering equivalent to FCVTZS behavior on IEEE-754 inputs.
    // - Returning a structured Err here would leak into arithmetic ops and create non-uniform
    //   behavior unless the whole numeric tower becomes Result-aware.
    if (v.type == OREN_TYPE_INT) { return v; }
    if (v.type == OREN_TYPE_FLOAT) {
        double d = v.as.float_val;
        // NaN check without <math.h>.
        if (d != d) { return oren_int(0); }

        // Avoid undefined behavior in (int64_t)d by clamping.
        //
        // Valid int64 range is [-2^63, 2^63-1]. Use lim=2^63 as the boundary.
        const double lim = 9223372036854775808.0; // 2^63
        if (d >= lim) { return oren_int(LLONG_MAX); }
        if (d <= -lim) { return oren_int(LLONG_MIN); }

        int64_t i = (int64_t)d; // truncate toward zero for finite values in range.
        return oren_int((long long)i);
    }
    // Keep behavior deterministic: non-numeric -> 0.
    return oren_int(0);
}

OrenValue oren_ptr_alloc(OrenValue bytes) {
    if (bytes.type != OREN_TYPE_INT) {
        oren_panic("ptr_alloc expects int");
        return OREN_NIL;
    }
    int64_t n = bytes.as.int_val;
    if (n < 0) {
        oren_panic("ptr_alloc: negative size");
        return OREN_NIL;
    }
    uint64_t p = oren_alloc_struct((size_t)n);
    return oren_int((int64_t)p);
}

OrenValue oren_ptr_free(OrenValue ptr) {
    if (ptr.type != OREN_TYPE_INT) {
        oren_panic("ptr_free expects int");
        return OREN_NIL;
    }
    uint64_t p = (uint64_t)ptr.as.int_val;
    oren_free_struct(p);
    return OREN_NIL;
}

OrenValue oren_lt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val < b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val < (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) < 0);
    }
    oren_panic("Type mismatch in lt");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_gt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val > b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val > (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) > 0);
    }
    if (getenv("OREN_TRACE_GT_MISMATCH")) {
        fprintf(stderr, "[trace] gt mismatch a.type=%d b.type=%d\n", a.type, b.type);
#if defined(__GNUC__) || defined(__clang__)
        void* ra0 = __builtin_return_address(0);
        fprintf(stderr, "[trace] gt mismatch ra0=%p\n", ra0);
#endif
        if (a.type == OREN_TYPE_INT) fprintf(stderr, "[trace] a.int=%lld\n", (long long)a.as.int_val);
        if (b.type == OREN_TYPE_INT) fprintf(stderr, "[trace] b.int=%lld\n", (long long)b.as.int_val);
        if (a.type == OREN_TYPE_FLOAT) fprintf(stderr, "[trace] a.float=%f\n", a.as.float_val);
        if (b.type == OREN_TYPE_FLOAT) fprintf(stderr, "[trace] b.float=%f\n", b.as.float_val);
        if (a.type == OREN_TYPE_STRING) fprintf(stderr, "[trace] a.str=%.120s\n", a.as.string_val ? a.as.string_val : "<null>");
        if (b.type == OREN_TYPE_STRING) fprintf(stderr, "[trace] b.str=%.120s\n", b.as.string_val ? b.as.string_val : "<null>");
    }
    oren_panic("Type mismatch in gt");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_lte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val <= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val <= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) <= 0);
    }
    oren_panic("Type mismatch in lte");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_gte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val >= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val >= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) >= 0);
    }
    oren_panic("Type mismatch in gte");
    return OREN_NIL;
}
