OrenValue oren_spawn0(OrenFn0 fn) {
    if (!fn) return OREN_NIL;
    // Ensure the main thread is registered before creating workers.
    (void)oren_thread_state();
    OrenThreadNode* n = (OrenThreadNode*)malloc(sizeof(OrenThreadNode));
    if (!n) {
        fprintf(stderr, "thread registry alloc failed\n");
        exit(1);
    }
    n->detached = 0;
    n->joined = 0;
    n->done = 0;
    pthread_mutex_init(&n->mu, NULL);
    pthread_cond_init(&n->cv, NULL);
    n->result = OREN_NIL;
    n->error = NULL;
    n->fn = OREN_NIL;
    n->args_list = OREN_NIL;
    n->next = NULL;

    OrenSpawn0Args* args = (OrenSpawn0Args*)malloc(sizeof(OrenSpawn0Args));
    if (!args) {
        thread_node_destroy(n);
        fprintf(stderr, "spawn alloc failed\n");
        exit(1);
    }
    args->fn = fn;
    args->node = n;
    pthread_t t;
    int rc = pthread_create(&t, NULL, oren_spawn0_entry, args);
    if (rc != 0) {
        free(args);
        thread_node_destroy(n);
        char buf[256];
        snprintf(buf, sizeof(buf), "pthread_create failed: %s", strerror(rc));
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    n->t = t;
    lock_collections();
    n->next = g_threads;
    g_threads = n;
    unlock_collections();
    return oren_int((long long)(intptr_t)n);
}

typedef struct {
    OrenValue fn;
    OrenValue args_list;
    OrenThreadNode* node;
} OrenSpawnCallArgs;

static void* oren_spawn_call_entry(void* p) {
    // Ensure this thread participates in safepoint GC accounting.
    OrenThreadState* st = oren_thread_state();
    OrenSpawnCallArgs* a = (OrenSpawnCallArgs*)p;

    if (setjmp(st->panic_buf) == 0) {
        st->has_panic_buf = 1;
        OrenValue res = oren_call_obj_list(a->fn, a->args_list);
        st->has_panic_buf = 0;
        if (a->node) {
            pthread_mutex_lock(&a->node->mu);
            a->node->done = 1;
            a->node->result = res;
            a->node->fn = OREN_NIL;
            a->node->args_list = OREN_NIL;
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
        if (a->node) {
            pthread_mutex_lock(&a->node->mu);
            a->node->done = 1;
            a->node->result = OREN_NIL;
            a->node->fn = OREN_NIL;
            a->node->args_list = OREN_NIL;
            a->node->error = strdup("Thread Panicked");
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

    free(a);
    oren_thread_unregister();
    return NULL;
}

OrenValue oren_spawn_call_list(OrenValue fn, OrenValue args_list) {
    // Ensure the main thread is registered before creating workers.
    (void)oren_thread_state();
    if (args_list.type != OREN_TYPE_LIST) {
        oren_panic("spawn_call_list expects args_list to be a list");
        return OREN_NIL; // Should not be reached
    }

    OrenThreadNode* n = (OrenThreadNode*)malloc(sizeof(OrenThreadNode));
    if (!n) {
        fprintf(stderr, "thread registry alloc failed\n");
        exit(1);
    }
    n->detached = 0;
    n->joined = 0;
    n->done = 0;
    pthread_mutex_init(&n->mu, NULL);
    pthread_cond_init(&n->cv, NULL);
    n->result = OREN_NIL;
    n->error = NULL;
    n->fn = fn;
    n->args_list = args_list;
    n->next = NULL;

    // Root callable + argument list so GC cannot collect them while the thread is running.
    // These roots are cleared when the thread node is freed (join/detach completion).
    oren_register_root(&n->fn);
    oren_register_root(&n->args_list);

    OrenSpawnCallArgs* args = (OrenSpawnCallArgs*)malloc(sizeof(OrenSpawnCallArgs));
    if (!args) {
        thread_node_destroy(n);
        fprintf(stderr, "spawn alloc failed\n");
        exit(1);
    }
    args->fn = fn;
    args->args_list = args_list;
    args->node = n;
    pthread_t t;
    int rc = pthread_create(&t, NULL, oren_spawn_call_entry, args);
    if (rc != 0) {
        free(args);
        thread_node_destroy(n);
        char buf[256];
        snprintf(buf, sizeof(buf), "pthread_create failed: %s", strerror(rc));
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    n->t = t;
    lock_collections();
    n->next = g_threads;
    g_threads = n;
    unlock_collections();
    return oren_int((long long)(intptr_t)n);
}

static OrenThreadNode* thread_from_value(OrenValue v) {
    if (v.type != OREN_TYPE_INT) return NULL;
    if (v.as.int_val == 0) return NULL;
    return (OrenThreadNode*)(intptr_t)v.as.int_val;
}

static void thread_node_destroy(OrenThreadNode* n) {
    if (!n) return;
    // Roots are safe to unregister even if they were never registered.
    oren_unregister_root(&n->fn);
    oren_unregister_root(&n->args_list);
    if (n->error) free(n->error);
    pthread_cond_destroy(&n->cv);
    pthread_mutex_destroy(&n->mu);
    free(n);
}

OrenValue oren_join(OrenValue thread) {
    OrenThreadNode* n = thread_from_value(thread);
    if (!n) return OREN_NIL;
    lock_collections();
    if (n->joined) {
        unlock_collections();
        return OREN_NIL;
    }
    if (n->detached) {
        unlock_collections();
        return OREN_NIL;
    }
    thread_list_remove(n);
    n->joined = 1;
    unlock_collections();
    pthread_join(n->t, NULL);
    
    OrenValue res = n->result;
    if (n->error) {
        char buf[256];
        snprintf(buf, sizeof(buf), "Joined thread failed: %s", n->error);
        thread_node_destroy(n);
        oren_panic(buf);
    }
    thread_node_destroy(n);
    return res;
}

OrenValue oren_join_timeout(OrenValue thread, OrenValue timeout_ms) {
    OrenThreadNode* n = thread_from_value(thread);
    if (!n) return OREN_NIL;

    long long ms = -1;
    if (timeout_ms.type == OREN_TYPE_INT) ms = timeout_ms.as.int_val;

    lock_collections();
    if (n->joined) { unlock_collections(); return OREN_NIL; }
    if (n->detached) { unlock_collections(); return OREN_NIL; }
    thread_list_remove(n);
    unlock_collections();

    if (ms < 0) {
        lock_collections();
        n->joined = 1;
        unlock_collections();
        pthread_join(n->t, NULL);
        OrenValue res = n->result;
        if (n->error) {
            char buf[256];
            snprintf(buf, sizeof(buf), "Joined thread failed: %s", n->error);
            thread_node_destroy(n);
            oren_panic(buf);
        }
        thread_node_destroy(n);
        return res;
    }

    int done = 0;
    pthread_mutex_lock(&n->mu);
    done = n->done;
    if (!done) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        long long ns = (long long)ts.tv_nsec + (ms * 1000000LL);
        ts.tv_sec += (time_t)(ns / 1000000000LL);
        ts.tv_nsec = (long)(ns % 1000000000LL);
        while (!n->done) {
            int rc = pthread_cond_timedwait(&n->cv, &n->mu, &ts);
            if (rc == ETIMEDOUT) break;
        }
        done = n->done;
    }
    pthread_mutex_unlock(&n->mu);

    if (!done) {
        lock_collections();
        n->detached = 1;
        unlock_collections();
        pthread_detach(n->t);
        return oren_int(-60); // BSD ETIMEDOUT
    }

    lock_collections();
    n->joined = 1;
    unlock_collections();
    pthread_join(n->t, NULL);
    OrenValue res = n->result;
    if (n->error) {
        char buf[256];
        snprintf(buf, sizeof(buf), "Joined thread failed: %s", n->error);
        thread_node_destroy(n);
        oren_panic(buf);
    }
    thread_node_destroy(n);
    return res;
}

OrenValue oren_detach(OrenValue thread) {
    OrenThreadNode* n = thread_from_value(thread);
    if (!n) return OREN_NIL;
    lock_collections();
    if (n->joined) {
        unlock_collections();
        return OREN_NIL;
    }
    if (n->detached) {
        unlock_collections();
        return OREN_NIL;
    }
    thread_list_remove(n);
    n->detached = 1;
    unlock_collections();
    pthread_detach(n->t);
    pthread_mutex_lock(&n->mu);
    int done = n->done;
    pthread_mutex_unlock(&n->mu);
    if (done) {
        thread_node_destroy(n);
    }
    return OREN_NIL;
}

OrenValue oren_is_done(OrenValue thread) {
    OrenThreadNode* n = thread_from_value(thread);
    if (!n) return OREN_FALSE;
    pthread_mutex_lock(&n->mu);
    int d = n->done;
    pthread_mutex_unlock(&n->mu);
    return oren_bool(d);
}

OrenValue oren_join_all() {
    // Join all known threads. Safe to call multiple times.
    while (1) {
        lock_collections();
        OrenThreadNode* n = g_threads;
        if (!n) {
            unlock_collections();
            break;
        }
        g_threads = n->next;
        unlock_collections();
        pthread_join(n->t, NULL);
        thread_node_destroy(n);
    }
    return OREN_NIL;
}

static void oren_store_args(int argc, char **argv) {
    if (argc <= 0) return;
    OREN_ARG_LIST = malloc(sizeof(OrenList));
    oren_register_alloc(OREN_ARG_LIST, OREN_ALLOC_LIST);
    OREN_ARG_LIST->count = argc;
    OREN_ARG_LIST->capacity = argc;
    OREN_ARG_LIST->items = malloc(sizeof(OrenValue) * argc);
    for (int i = 0; i < argc; i++) {
        OREN_ARG_LIST->items[i] = oren_string(argv[i]);
    }
}

OrenValue oren_args() {
    if (OREN_ARG_LIST == NULL) {
        OrenValue empty;
        empty.type = OREN_TYPE_LIST;
        empty.as.list_val = malloc(sizeof(OrenList));
        oren_register_alloc(empty.as.list_val, OREN_ALLOC_LIST);
        empty.as.list_val->count = 0;
        empty.as.list_val->capacity = 0;
        empty.as.list_val->items = NULL;
        return empty;
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = OREN_ARG_LIST;
    return v;
}

OrenValue oren_set_result(OrenValue v) {
    OREN_RESULT_VALUE = v;
    return v;
}

OrenValue oren_get_result() {
    return OREN_RESULT_VALUE;
}

void oren_init(int argc, char **argv) {
    OREN_NIL.type = OREN_TYPE_NIL;
    OREN_TRUE.type = OREN_TYPE_BOOL;
    OREN_TRUE.as.bool_val = 1;
    OREN_FALSE.type = OREN_TYPE_BOOL;
    OREN_FALSE.as.bool_val = 0;

    // Result selection is part of the agentic tooling surface; keep it GC-live as a root.
    OREN_RESULT_VALUE = OREN_NIL;
    oren_register_root(&OREN_RESULT_VALUE);

    oren_store_args(argc, argv);
    // Register the main thread for GC safepoint accounting.
    (void)oren_thread_state();

#ifdef OREN_ENABLE_PYTHON
    Py_Initialize();
    // Python manages its own argv; callers can set sys.argv from Oren if needed.
#endif
}

#ifdef OREN_ENABLE_PYTHON
static OrenValue oren_py_to_oren(PyObject* obj) {
    if (obj == Py_None) return OREN_NIL;
    if (PyBool_Check(obj)) return (obj == Py_True) ? OREN_TRUE : OREN_FALSE;
    if (PyLong_Check(obj)) return oren_int(PyLong_AsLongLong(obj));
    if (PyFloat_Check(obj)) return oren_float(PyFloat_AsDouble(obj));
    if (PyUnicode_Check(obj)) return oren_string(PyUnicode_AsUTF8(obj));

    // Wrap generic python object
    OrenValue v;
    v.type = OREN_TYPE_PY_OBJ;
    v.as.py_obj = obj;
    // IncRef? No, usually return new ref.
    return v;
}

static PyObject* oren_to_py(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_NIL: Py_RETURN_NONE;
        case OREN_TYPE_INT: return PyLong_FromLongLong(v.as.int_val);
        case OREN_TYPE_FLOAT: return PyFloat_FromDouble(v.as.float_val);
        case OREN_TYPE_BOOL: return PyBool_FromLong(v.as.bool_val);
        case OREN_TYPE_STRING: return PyUnicode_FromString(v.as.string_val);
        case OREN_TYPE_PY_OBJ:
            Py_INCREF(v.as.py_obj);
            return v.as.py_obj;
        case OREN_TYPE_LIST: {
            PyObject* list = PyList_New(v.as.list_val->count);
            for (int i = 0; i < v.as.list_val->count; i++) {
                 PyList_SetItem(list, i, oren_to_py(v.as.list_val->items[i]));
            }
            return list;
        }
        case OREN_TYPE_MAP: {
             PyObject* dict = PyDict_New();
             for (int i = 0; i < v.as.map_val->count; i++) {
                 PyDict_SetItem(dict, oren_to_py(v.as.map_val->keys[i]), oren_to_py(v.as.map_val->values[i]));
             }
             return dict;
        }
    }
    Py_RETURN_NONE;
}
#endif

OrenValue oren_int(long long v) {
    OrenValue val;
    val.type = OREN_TYPE_INT;
    val.as.int_val = v;
    return val;
}

OrenValue oren_float(double v) {
    OrenValue val;
    val.type = OREN_TYPE_FLOAT;
    val.as.float_val = v;
    return val;
}

OrenValue oren_string(const char* s) {
    OrenValue val;
    val.type = OREN_TYPE_STRING;
    val.as.string_val = strdup(s);
    oren_register_alloc(val.as.string_val, OREN_ALLOC_STRING);
    return val;
}

OrenValue oren_bool(int v) {
    return v ? OREN_TRUE : OREN_FALSE;
}

OrenValue oren_func(OrenFn fn, void* env) {
    OrenValue val;
    val.type = OREN_TYPE_FUNC;
    val.as.func_val.fn = fn;
    val.as.func_val.env = env;
    return val;
}

OrenValue oren_closure(OrenFn fn, int capture_count, ...) {
    if (!fn) return OREN_NIL;
    if (capture_count <= 0) {
        return oren_func(fn, NULL);
    }

    va_list args;
    va_start(args, capture_count);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        va_end(args);
        oren_panic("closure env alloc failed");
        return OREN_NIL; // Should not be reached
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = capture_count;
    list->capacity = capture_count;
    list->items = malloc(sizeof(OrenValue) * (size_t)capture_count);
    if (!list->items) {
        unlock_collections();
        va_end(args);
        oren_panic("closure env items alloc failed");
        return OREN_NIL; // Should not be reached
    }
    for (int i = 0; i < capture_count; i++) {
        list->items[i] = va_arg(args, OrenValue);
    }
    unlock_collections();

    va_end(args);
    return oren_func(fn, list);
}

int oren_is_truthy(OrenValue v) {
    if (v.type == OREN_TYPE_NIL) return 0;
    if (v.type == OREN_TYPE_BOOL) return v.as.bool_val;
    return 1;
}

