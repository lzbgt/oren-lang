#include "runtime.h"
#include <sys/stat.h>
#include <pthread.h>
#include <errno.h>
#include <setjmp.h>
#include <execinfo.h>
#include <time.h>

OrenValue OREN_NIL;
OrenValue OREN_TRUE;
OrenValue OREN_FALSE;
static OrenList *OREN_ARG_LIST = NULL;
static OrenValue OREN_RESULT_VALUE;

typedef enum {
    OREN_ALLOC_STRING = 1,
    OREN_ALLOC_LIST = 2,
    OREN_ALLOC_MAP = 3,
    OREN_ALLOC_STRUCT = 4
} OrenAllocKind;

typedef struct OrenAllocNode {
    void* ptr;
    OrenAllocKind kind;
    int freed;
    struct OrenAllocNode* next;
} OrenAllocNode;

static OrenAllocNode* g_allocs = NULL;
static pthread_mutex_t g_alloc_mutex = PTHREAD_MUTEX_INITIALIZER;
static OrenAllocNode* g_roots = NULL;
static pthread_mutex_t g_collection_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_collection_cv = PTHREAD_COND_INITIALIZER;
static int g_gc_requested = 0;
static int g_gc_in_progress = 0;
static int g_threads_total = 0;
static int g_threads_waiting = 0;
static pthread_key_t g_thread_key;
static pthread_once_t g_thread_key_once = PTHREAD_ONCE_INIT;
static struct OrenThreadState* g_thread_states = NULL;

typedef struct OrenThreadNode {
    pthread_t t;
    int detached;
    int joined;
    int done;
    pthread_mutex_t mu;
    pthread_cond_t cv;
    OrenValue result;
    char* error;
    // Spawned-call state (for closure-safe spawning). When using `oren_spawn0`, these remain NIL.
    OrenValue fn;
    OrenValue args_list;
    struct OrenThreadNode* next;
} OrenThreadNode;
static OrenThreadNode* g_threads = NULL;

static void thread_node_destroy(OrenThreadNode* n);

static void lock_collections() { pthread_mutex_lock(&g_collection_mutex); }
static void unlock_collections() { pthread_mutex_unlock(&g_collection_mutex); }

typedef struct OrenThreadState {
    int at_safepoint;
    void* stack_top;
    void* stack_sp;
    jmp_buf panic_buf;
    int has_panic_buf;
    struct OrenThreadState* next;
} OrenThreadState;

static void thread_key_init() {
    (void)pthread_key_create(&g_thread_key, free);
}

static OrenThreadState* oren_thread_state() {
    (void)pthread_once(&g_thread_key_once, thread_key_init);
    OrenThreadState* st = (OrenThreadState*)pthread_getspecific(g_thread_key);
    if (!st) {
        st = (OrenThreadState*)calloc(1, sizeof(OrenThreadState));
        if (!st) {
            fprintf(stderr, "thread state alloc failed\n");
            exit(1);
        }
        int stack_marker = 0;
        st->stack_top = (void*)&stack_marker;
        st->stack_sp = NULL;
        st->has_panic_buf = 0;
        pthread_setspecific(g_thread_key, st);
        lock_collections();
        g_threads_total++;
        st->next = g_thread_states;
        g_thread_states = st;
        unlock_collections();
    }
    return st;
}

void oren_panic(const char* msg) {
    OrenThreadState* st = oren_thread_state();
    if (st && st->has_panic_buf) {
        // We can't easily pass the string pointer through longjmp (int arg).
        // So we might need to store it in thread state or use a global if we were single threaded.
        // But since we are panicking, we can perhaps just longjmp and let the catcher
        // use a side-channel or just know *that* it panicked.
        // Ideally we store the message in the thread node?
        // But the thread node is owned by the spawner.
        // Let's print to stderr for now, and maybe store in thread-local static?
        fprintf(stderr, "Panic in thread: %s\n", msg);
        longjmp(st->panic_buf, 1);
    }
    fprintf(stderr, "Runtime Panic: %s\n", msg);
    
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    fprintf(stderr, "Stack Trace:\n");
    backtrace_symbols_fd(callstack, frames, 2);

    exit(1);
}

static void oren_thread_unregister() {
    (void)pthread_once(&g_thread_key_once, thread_key_init);
    OrenThreadState* st = (OrenThreadState*)pthread_getspecific(g_thread_key);
    if (!st) return;

    // Cooperate if a collection is in progress.
    if (g_gc_requested) {
        oren_gc_safepoint();
    }

    lock_collections();
    if (st->at_safepoint) {
        st->at_safepoint = 0;
        g_threads_waiting--;
        if (g_threads_waiting < 0) g_threads_waiting = 0;
    }
    g_threads_total--;
    if (g_threads_total < 0) g_threads_total = 0;

    // Remove from global thread-state list.
    OrenThreadState* prev = NULL;
    OrenThreadState* cur = g_thread_states;
    while (cur) {
        if (cur == st) {
            if (prev) prev->next = cur->next;
            else g_thread_states = cur->next;
            break;
        }
        prev = cur;
        cur = cur->next;
    }

    pthread_cond_broadcast(&g_collection_cv);
    unlock_collections();
    pthread_setspecific(g_thread_key, NULL);
    free(st);
}

static void thread_list_remove(OrenThreadNode* node) {
    if (!node) return;
    OrenThreadNode* prev = NULL;
    OrenThreadNode* cur = g_threads;
    while (cur) {
        if (cur == node) {
            if (prev) prev->next = cur->next;
            else g_threads = cur->next;
            return;
        }
        prev = cur;
        cur = cur->next;
    }
}

void oren_register_root(OrenValue* slot) {
#ifdef OREN_NO_GC
    (void)slot;
    return;
#endif
    if (slot == NULL) return;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = (OrenAllocNode*)malloc(sizeof(OrenAllocNode));
    if (!n) {
        fprintf(stderr, "root registry failed\n");
        exit(1);
    }
    n->ptr = slot;
    n->kind = 0; // root marker
    n->freed = 0;
    n->next = g_roots;
    g_roots = n;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_unregister_root(OrenValue* slot) {
#ifdef OREN_NO_GC
    (void)slot;
    return;
#endif
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* prev = NULL;
    OrenAllocNode* cur = g_roots;
    while (cur) {
        if (cur->ptr == slot) {
            if (prev) prev->next = cur->next; else g_roots = cur->next;
            free(cur);
            break;
        }
        prev = cur;
        cur = cur->next;
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

static void oren_register_alloc(void* ptr, OrenAllocKind kind) {
    if (ptr == NULL) return;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = (OrenAllocNode*)malloc(sizeof(OrenAllocNode));
    if (!n) {
        fprintf(stderr, "alloc registry failed\n");
        exit(1);
    }
    n->ptr = ptr;
    n->kind = kind;
    n->freed = 0;
    n->next = g_allocs;
    g_allocs = n;
    pthread_mutex_unlock(&g_alloc_mutex);
}

static OrenAllocNode* oren_find_node(void* ptr) {
    OrenAllocNode* cur = g_allocs;
    while (cur) {
        if (cur->ptr == ptr) return cur;
        cur = cur->next;
    }
    return NULL;
}

static void oren_mark_value(OrenValue v) {
#ifdef OREN_NO_GC
    return;
#endif
    if (v.type == OREN_TYPE_STRING) {
        OrenAllocNode* n = oren_find_node(v.as.string_val);
        if (n && n->freed == 0) n->freed = -1;
        return;
    }
    if (v.type == OREN_TYPE_LIST) {
        OrenList* lst = v.as.list_val;
        if (!lst) return;
        OrenAllocNode* n = oren_find_node(lst);
        if (n && n->freed == 0) {
            n->freed = -1;
            for (int i = 0; i < lst->count; i++) {
                oren_mark_value(lst->items[i]);
            }
        }
        return;
    }
    if (v.type == OREN_TYPE_MAP) {
        OrenMap* mp = v.as.map_val;
        if (!mp) return;
        OrenAllocNode* n = oren_find_node(mp);
        if (n && n->freed == 0) {
            n->freed = -1;
            for (int i = 0; i < mp->count; i++) {
                oren_mark_value(mp->keys[i]);
                oren_mark_value(mp->values[i]);
            }
        }
        return;
    }
    if (v.type == OREN_TYPE_FUNC) {
        // A function value is an immediate value, but its closure environment (if any)
        // may point to GC-tracked allocations (typically an OrenList of captured values).
        void* env = v.as.func_val.env;
        if (!env) return;
        OrenAllocNode* n = oren_find_node(env);
        if (!n || n->freed != 0) return;
        if (n->kind == OREN_ALLOC_LIST) {
            OrenValue tmp;
            tmp.type = OREN_TYPE_LIST;
            tmp.as.list_val = (OrenList*)env;
            oren_mark_value(tmp);
        } else if (n->kind == OREN_ALLOC_MAP) {
            OrenValue tmp;
            tmp.type = OREN_TYPE_MAP;
            tmp.as.map_val = (OrenMap*)env;
            oren_mark_value(tmp);
        } else if (n->kind == OREN_ALLOC_STRING) {
            OrenValue tmp;
            tmp.type = OREN_TYPE_STRING;
            tmp.as.string_val = (char*)env;
            oren_mark_value(tmp);
        } else {
            // Struct envs are not traversed. v0 closure env uses list/map.
            n->freed = -1;
        }
        return;
    }
}

static int oren_type_valid(int t);
static void oren_mark_stack_range(void* a, void* b);

void oren_gc_collect() {
#ifdef OREN_NO_GC
    return;
#endif
    OrenThreadState* self = oren_thread_state();
    (void)self;

    lock_collections();
    while (g_gc_in_progress) {
        pthread_cond_wait(&g_collection_cv, &g_collection_mutex);
    }
    g_gc_in_progress = 1;
    g_gc_requested = 1;
    pthread_cond_broadcast(&g_collection_cv);
    while (g_threads_waiting < (g_threads_total - 1)) {
        pthread_cond_wait(&g_collection_cv, &g_collection_mutex);
    }

    pthread_mutex_lock(&g_alloc_mutex);
    // Clear prior marks (-1 -> 0)
    OrenAllocNode* n = g_allocs;
    while (n) {
        if (n->freed == -1) n->freed = 0;
        n = n->next;
    }
    // Mark from roots
    OrenAllocNode* r = g_roots;
    while (r) {
        OrenValue* slot = (OrenValue*)r->ptr;
        if (slot) {
            oren_mark_value(*slot);
        }
        r = r->next;
    }

    // Mark results of completed threads (that haven't been joined/freed yet)
    OrenThreadNode* t = g_threads;
    while (t) {
        // Threads are tracked outside the GC heap, so we must explicitly keep any
        // referenced OrenValues alive across collections.
        //
        // - `result` keeps finished thread outputs alive until join/free.
        // - `fn` and `args_list` keep in-flight callables and their arguments alive.
        if (t->done) oren_mark_value(t->result);
        oren_mark_value(t->fn);
        oren_mark_value(t->args_list);
        t = t->next;
    }

    // Conservative stack scanning over all registered threads.
    int self_sp_marker = 0;
    void* self_sp = (void*)&self_sp_marker;
    OrenThreadState* cur = g_thread_states;
    while (cur) {
        void* sp = cur->stack_sp;
        void* top = cur->stack_top;
        if (cur == self) {
            sp = self_sp;
        }
        if (sp != NULL && top != NULL) {
            oren_mark_stack_range(sp, top);
        }
        cur = cur->next;
    }
    // Sweep: free unmarked (freed==0) tracked allocations
    OrenAllocNode* prev = NULL;
    n = g_allocs;
    while (n) {
        int marked = (n->freed == -1);
        if (!marked && n->freed == 0) {
            if (n->kind == OREN_ALLOC_STRING) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_LIST) {
                OrenList* lst = (OrenList*)n->ptr;
                if (lst->items) free(lst->items);
                free(lst);
            } else if (n->kind == OREN_ALLOC_MAP) {
                OrenMap* mp = (OrenMap*)n->ptr;
                if (mp->keys) free(mp->keys);
                if (mp->values) free(mp->values);
                free(mp);
            } else {
                free(n->ptr);
            }
            OrenAllocNode* to_free = n;
            n = n->next;
            if (prev) prev->next = n; else g_allocs = n;
            free(to_free);
            continue;
        }
        n->freed = 0; // clear mark
        prev = n;
        n = n->next;
    }
    pthread_mutex_unlock(&g_alloc_mutex);

    g_gc_requested = 0;
    g_gc_in_progress = 0;
    pthread_cond_broadcast(&g_collection_cv);
    unlock_collections();
}

void oren_gc_safepoint() {
#ifdef OREN_NO_GC
    return;
#endif
    OrenThreadState* st = oren_thread_state();
    if (!st) return;

    int sp_marker = 0;
    st->stack_sp = (void*)&sp_marker;

    lock_collections();
    if (!g_gc_requested) {
        unlock_collections();
        return;
    }
    if (!st->at_safepoint) {
        st->at_safepoint = 1;
        g_threads_waiting++;
        pthread_cond_broadcast(&g_collection_cv);
    }
    while (g_gc_requested) {
        pthread_cond_wait(&g_collection_cv, &g_collection_mutex);
    }
    if (st->at_safepoint) {
        st->at_safepoint = 0;
        g_threads_waiting--;
        if (g_threads_waiting < 0) g_threads_waiting = 0;
    }
    unlock_collections();
}

static int oren_type_valid(int t) {
    return t >= OREN_TYPE_NIL && t <= OREN_TYPE_FUNC;
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

    for (uintptr_t p = lo; p + sizeof(OrenValue) <= hi; p += 8) {
        OrenValue v;
        memcpy(&v, (void*)p, sizeof(OrenValue));
        if (!oren_type_valid((int)v.type)) continue;
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
    
    free(a);
    oren_thread_unregister();
    return NULL;
}

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

OrenValue oren_add(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val + b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val + b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val + b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val + (double)b.as.int_val);
    }
    // TODO: String concat
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
         // POC: simplistic concat
         char* new_s = malloc(strlen(a.as.string_val) + strlen(b.as.string_val) + 1);
         strcpy(new_s, a.as.string_val);
         strcat(new_s, b.as.string_val);
         OrenValue val;
         val.type = OREN_TYPE_STRING;
         val.as.string_val = new_s;
         return val;
    }
    oren_panic("Type mismatch in add");
    return OREN_NIL;
}

OrenValue oren_sub(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val - b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val - b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val - b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val - (double)b.as.int_val);
    }
    oren_panic("Type mismatch in sub");
    return OREN_NIL;
}

OrenValue oren_mul(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val * b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val * b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val * b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val * (double)b.as.int_val);
    }
    oren_panic("Type mismatch in mul");
    return OREN_NIL;
}

OrenValue oren_div(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val / b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val / b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val / b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val / (double)b.as.int_val);
    }
    oren_panic("Type mismatch in div");
    return OREN_NIL;
}

static uint64_t oren_u64(OrenValue v, const char *op) {
    if (v.type != OREN_TYPE_INT) {
        char buf[64];
        snprintf(buf, sizeof(buf), "%s expects int", op);
        oren_panic(buf);
        return 0ULL; // Should not be reached, but needed for compiler
    }
    return (uint64_t)v.as.int_val;
}

OrenValue oren_band(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitand");
    uint64_t y = oren_u64(b, "bitand");
    return oren_int((long long)(x & y));
}

OrenValue oren_bor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitor");
    uint64_t y = oren_u64(b, "bitor");
    return oren_int((long long)(x | y));
}

OrenValue oren_bxor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitxor");
    uint64_t y = oren_u64(b, "bitxor");
    return oren_int((long long)(x ^ y));
}

OrenValue oren_shl(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "shl");
    uint64_t s = oren_u64(b, "shl");
    if (s >= 64) return oren_int(0);
    return oren_int((long long)(x << s));
}

OrenValue oren_shr(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "shr");
    uint64_t s = oren_u64(b, "shr");
    if (s >= 64) return oren_int(0);
    return oren_int((long long)(x >> s));
}

OrenValue oren_bnot(OrenValue v) {
    uint64_t x = oren_u64(v, "bnot");
    return oren_int((long long)(~x));
}

OrenValue oren_eq(OrenValue a, OrenValue b) {
    if (a.type != b.type) return OREN_FALSE;
    switch (a.type) {
        case OREN_TYPE_INT: return oren_bool(a.as.int_val == b.as.int_val);
        case OREN_TYPE_FLOAT: return oren_bool(a.as.float_val == b.as.float_val);
        case OREN_TYPE_BOOL: return oren_bool(a.as.bool_val == b.as.bool_val);
        case OREN_TYPE_STRING: return oren_bool(strcmp(a.as.string_val, b.as.string_val) == 0);
        case OREN_TYPE_NIL: return OREN_TRUE;
        case OREN_TYPE_FUNC:
            return oren_bool(a.as.func_val.fn == b.as.func_val.fn && a.as.func_val.env == b.as.func_val.env);
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            // Check identity or equality
            int res = PyObject_RichCompareBool(a.as.py_obj, b.as.py_obj, Py_EQ);
            if (res == -1) { PyErr_Clear(); return OREN_FALSE; }
            return oren_bool(res);
#else
            oren_panic("Python support is disabled");
            return OREN_FALSE;
#endif
        }
        case OREN_TYPE_LIST:
            // Identity or deep equal? Identity for now
            return oren_bool(a.as.list_val == b.as.list_val);
        case OREN_TYPE_MAP:
            return oren_bool(a.as.map_val == b.as.map_val);
    }
    return OREN_FALSE;
}

#ifdef OREN_ENABLE_PYTHON
OrenValue oren_py_import(OrenValue name) {
    if (name.type != OREN_TYPE_STRING) {
        oren_panic("import expects string");
        return OREN_NIL; // Should not be reached
    }
    PyObject* mod = PyImport_ImportModule(name.as.string_val);
    if (!mod) {
        PyErr_Print();
        char buf[256];
        snprintf(buf, sizeof(buf), "Could not import python module %s", name.as.string_val);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    OrenValue v;
    v.type = OREN_TYPE_PY_OBJ;
    v.as.py_obj = mod;
    return v;
}
#else
OrenValue oren_py_import(OrenValue name) {
    (void)name;
    oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
    return OREN_NIL; // Should not be reached
}
#endif

OrenValue oren_get_attr(OrenValue obj, const char* attr) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* val = PyObject_GetAttrString(obj.as.py_obj, attr);
        if (!val) {
            PyErr_Print();
            char buf[256];
            snprintf(buf, sizeof(buf), "Python object has no attribute '%s'", attr);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        return oren_py_to_oren(val);
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_map_get(obj, oren_string(attr));
    }
    oren_panic("get_attr only supported for Python objects and maps currently");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_set_attr(OrenValue obj, const char* attr, OrenValue value) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_val = oren_to_py(value);
        if (PyObject_SetAttrString(obj.as.py_obj, attr, py_val) != 0) {
            PyErr_Print();
            char buf[256];
            snprintf(buf, sizeof(buf), "failed to set attribute '%s'", attr);
            oren_panic(buf);
            return value; // Should not be reached, but needed for compiler
        }
        Py_DECREF(py_val);
        return value;
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        (void)attr;
        (void)value;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return value; // Should not be reached
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_index_set(obj, oren_string(attr), value);
    }
    oren_panic("set_attr only supported for Python objects and maps currently");
    return value; // Should not be reached
}

OrenValue oren_new_list(int count, ...) {
    va_list args;
    va_start(args, count);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = count;
    list->capacity = count;
    list->items = malloc(sizeof(OrenValue) * count);

    for (int i = 0; i < count; i++) {
        list->items[i] = va_arg(args, OrenValue);
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    unlock_collections();
    return v;
}

OrenValue oren_list_len(OrenValue list) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("len on non-list");
        return OREN_NIL; // Should not be reached
    }
    lock_collections();
    int c = list.as.list_val->count;
    unlock_collections();
    return oren_int(c);
}

OrenValue oren_list_push(OrenValue list, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("push on non-list");
        return list; // Should not be reached
    }
    OrenList *l = list.as.list_val;
    lock_collections();
    if (l->count >= l->capacity) {
        int newCap = l->capacity == 0 ? 4 : l->capacity * 2;
        l->items = realloc(l->items, sizeof(OrenValue) * newCap);
        l->capacity = newCap;
    }
    l->items[l->count] = value;
    l->count += 1;
    unlock_collections();
    return list;
}

OrenValue oren_list_get(OrenValue list, OrenValue index) {
    if (list.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
             oren_panic("index must be integer");
             return OREN_NIL; // Should not be reached
        }
        int idx = (int)index.as.int_val;
        if (idx < 0 || idx >= list.as.list_val->count) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, list.as.list_val->count);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        lock_collections();
        OrenValue v = list.as.list_val->items[idx];
        unlock_collections();
        return v;
    }
    // Also support python list get item?
#ifdef OREN_ENABLE_PYTHON
    if (list.type == OREN_TYPE_PY_OBJ) {
         PyObject* item = PyObject_GetItem(list.as.py_obj, oren_to_py(index)); // This leaks the index py object reference
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
    int idx = (int)index.as.int_val;
    if (idx < 0 || idx >= list.as.list_val->count) {
        oren_panic("list_set index out of bounds");
        return value; // Should not be reached
    }
    lock_collections();
    list.as.list_val->items[idx] = value;
    unlock_collections();
    return value;
}

static int bytes_get_u8_checked(OrenValue bytes, int idx, uint8_t* out) {
    if (bytes.type != OREN_TYPE_LIST) return 0;
    if (idx < 0 || idx >= bytes.as.list_val->count) return 0;
    OrenValue v = bytes.as.list_val->items[idx];
    if (v.type != OREN_TYPE_INT) return 0;
    if (v.as.int_val < 0 || v.as.int_val > 255) return 0;
    *out = (uint8_t)v.as.int_val;
    return 1;
}

static int bytes_set_u8_checked(OrenValue bytes, int idx, uint8_t val) {
    if (bytes.type != OREN_TYPE_LIST) return 0;
    if (idx < 0 || idx >= bytes.as.list_val->count) return 0;
    bytes.as.list_val->items[idx] = oren_int((int64_t)val);
    return 1;
}


OrenValue oren_bytes_get_u8(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u8 expects (bytes:list<int>, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u8: index out of bounds or byte out of range"));
    return oren_int((int64_t)b0);
}

OrenValue oren_bytes_set_u8(OrenValue bytes, OrenValue index, OrenValue value) {
    if (bytes.type != OREN_TYPE_LIST) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8 expects (bytes:list<int>, idx:int, value:int 0..255)"));
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8 expects (bytes:list<int>, idx:int, value:int 0..255)"));
    if (value.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8 expects (bytes:list<int>, idx:int, value:int 0..255)"));
    int idx = (int)index.as.int_val;
    int64_t v = value.as.int_val;
    if (v < 0 || v > 255) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8: value out of range"));
    lock_collections();
    int ok = (idx >= 0 && idx < bytes.as.list_val->count);
    if (ok) bytes.as.list_val->items[idx] = oren_int(v);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8: index out of bounds"));
    return oren_int(v);
}

OrenValue oren_bytes_get_u16_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be expects (bytes:list<int>, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) && bytes_get_u8_checked(bytes, idx + 1, &b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be: index out of bounds or byte out of range"));
    return oren_int(((int64_t)b0 << 8) | (int64_t)b1);
}

OrenValue oren_bytes_get_u16_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le expects (bytes:list<int>, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) && bytes_get_u8_checked(bytes, idx + 1, &b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le: index out of bounds or byte out of range"));
    return oren_int(((int64_t)b1 << 8) | (int64_t)b0);
}

OrenValue oren_bytes_get_i16_be(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u16_be(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 32768) v -= 65536;
    return oren_int(v);
}

OrenValue oren_bytes_get_i16_le(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u16_le(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 32768) v -= 65536;
    return oren_int(v);
}

OrenValue oren_bytes_get_u32_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_be expects (bytes:list<int>, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1, b2, b3;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_be: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)b0 << 24) | ((int64_t)b1 << 16) | ((int64_t)b2 << 8) | (int64_t)b3;
    return oren_int(v);
}

OrenValue oren_bytes_get_u32_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le expects (bytes:list<int>, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1, b2, b3;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)b3 << 24) | ((int64_t)b2 << 16) | ((int64_t)b1 << 8) | (int64_t)b0;
    return oren_int(v);
}

OrenValue oren_bytes_get_i32_be(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u32_be(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 2147483648LL) v -= 4294967296LL;
    return oren_int(v);
}

OrenValue oren_bytes_get_i32_le(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u32_le(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 2147483648LL) v -= 4294967296LL;
    return oren_int(v);
}

OrenValue oren_bytes_set_u16_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_be expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b1 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_be: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_u16_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_le expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_le: index out of bounds"));
    return oren_int((int64_t)u);
}

static int64_t sign_extend16(uint64_t u) {
    int64_t v = (int64_t)(u & 0xFFFFu);
    if (v >= 32768) v -= 65536;
    return v;
}

static int64_t sign_extend32(uint64_t u) {
    int64_t v = (int64_t)(u & 0xFFFFFFFFu);
    if (v >= 2147483648LL) v -= 4294967296LL;
    return v;
}

OrenValue oren_bytes_set_i16_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_be expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b1 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_be: index out of bounds"));
    return oren_int(sign_extend16(u));
}

OrenValue oren_bytes_set_i16_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_le expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_le: index out of bounds"));
    return oren_int(sign_extend16(u));
}

OrenValue oren_bytes_set_u32_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_be expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b3 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_be: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_u32_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_le expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_le: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_i32_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_be expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b3 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_be: index out of bounds"));
    return oren_int(sign_extend32(u));
}

OrenValue oren_bytes_set_i32_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_le expects (bytes:list<int>, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_le: index out of bounds"));
    return oren_int(sign_extend32(u));
}

OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value) {
    if (container.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
            oren_panic("index must be integer");
            return value; // Should not be reached
        }
        int idx = (int)index.as.int_val;
        if (idx < 0) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, container.as.list_val->count);
            oren_panic(buf);
            return value; // Should not be reached
        }
        if (idx >= container.as.list_val->capacity) {
            int newCap = container.as.list_val->capacity == 0 ? (idx + 1) : container.as.list_val->capacity;
            while (newCap <= idx) { newCap *= 2; }
            container.as.list_val->items = realloc(container.as.list_val->items, sizeof(OrenValue) * newCap);
            container.as.list_val->capacity = newCap;
        }
        if (idx >= container.as.list_val->count) {
            // zero-fill new slots
            for (int i = container.as.list_val->count; i <= idx; i++) {
                container.as.list_val->items[i] = OREN_NIL;
            }
            container.as.list_val->count = idx + 1;
        }
        lock_collections();
        container.as.list_val->items[idx] = value;
        unlock_collections();
        return value;
    }

    if (container.type == OREN_TYPE_MAP) {
        OrenMap* map = container.as.map_val;
        lock_collections();
        if (!(index.type == OREN_TYPE_NIL || index.type == OREN_TYPE_BOOL || index.type == OREN_TYPE_INT || index.type == OREN_TYPE_STRING)) {
            unlock_collections();
            oren_panic("map key type not supported (need nil/bool/int/string)");
            return value; // Should not be reached
        }

        int rk = (index.type == OREN_TYPE_NIL) ? 0 : (index.type == OREN_TYPE_BOOL) ? 1 : (index.type == OREN_TYPE_INT) ? 2 : 3;

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int rmk = (mk.type == OREN_TYPE_NIL) ? 0 : (mk.type == OREN_TYPE_BOOL) ? 1 : (mk.type == OREN_TYPE_INT) ? 2 : 3;

            int cmp = 0;
            if (rmk != rk) {
                cmp = (rmk < rk) ? -1 : 1;
            } else if (index.type == OREN_TYPE_NIL) {
                cmp = 0;
            } else if (index.type == OREN_TYPE_BOOL) {
                cmp = (mk.as.bool_val < index.as.bool_val) ? -1 : (mk.as.bool_val > index.as.bool_val) ? 1 : 0;
            } else if (index.type == OREN_TYPE_INT) {
                cmp = (mk.as.int_val < index.as.int_val) ? -1 : (mk.as.int_val > index.as.int_val) ? 1 : 0;
            } else { // STRING
                cmp = strcmp(mk.as.string_val, index.as.string_val);
                if (cmp < 0) cmp = -1;
                else if (cmp > 0) cmp = 1;
            }

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_eq(map->keys[idx], index).as.bool_val) {
            map->values[idx] = value;
            unlock_collections();
            return value;
        }

        if (map->count >= map->capacity) {
            int newCap = map->capacity == 0 ? 8 : map->capacity * 2;
            map->keys = realloc(map->keys, sizeof(OrenValue) * newCap);
            map->values = realloc(map->values, sizeof(OrenValue) * newCap);
            map->capacity = newCap;
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = index;
        map->values[idx] = value;
        map->count += 1;
        unlock_collections();
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

    lock_collections();
    OrenMap* map = malloc(sizeof(OrenMap));
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = 0;
    map->capacity = count + 8;
    map->keys = malloc(sizeof(OrenValue) * map->capacity);
    map->values = malloc(sizeof(OrenValue) * map->capacity);

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

        int rk = (key.type == OREN_TYPE_NIL) ? 0 : (key.type == OREN_TYPE_BOOL) ? 1 : (key.type == OREN_TYPE_INT) ? 2 : 3;

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int rmk = (mk.type == OREN_TYPE_NIL) ? 0 : (mk.type == OREN_TYPE_BOOL) ? 1 : (mk.type == OREN_TYPE_INT) ? 2 : 3;

            int cmp = 0;
            if (rmk != rk) {
                cmp = (rmk < rk) ? -1 : 1;
            } else if (key.type == OREN_TYPE_NIL) {
                cmp = 0;
            } else if (key.type == OREN_TYPE_BOOL) {
                cmp = (mk.as.bool_val < key.as.bool_val) ? -1 : (mk.as.bool_val > key.as.bool_val) ? 1 : 0;
            } else if (key.type == OREN_TYPE_INT) {
                cmp = (mk.as.int_val < key.as.int_val) ? -1 : (mk.as.int_val > key.as.int_val) ? 1 : 0;
            } else { // STRING
                cmp = strcmp(mk.as.string_val, key.as.string_val);
                if (cmp < 0) cmp = -1;
                else if (cmp > 0) cmp = 1;
            }

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_eq(map->keys[idx], key).as.bool_val) {
            map->values[idx] = value;
            continue;
        }

        if (map->count >= map->capacity) {
            int newCap = map->capacity == 0 ? 8 : map->capacity * 2;
            map->keys = realloc(map->keys, sizeof(OrenValue) * newCap);
            map->values = realloc(map->values, sizeof(OrenValue) * newCap);
            map->capacity = newCap;
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
    unlock_collections();
    return v;
}

OrenValue oren_map_get(OrenValue map, OrenValue key) {
    if (map.type != OREN_TYPE_MAP) return OREN_NIL;
    lock_collections();
    for (int i = 0; i < map.as.map_val->count; i++) {
        OrenValue k = map.as.map_val->keys[i];
        if (oren_eq(k, key).as.bool_val) {
            OrenValue v = map.as.map_val->values[i];
            unlock_collections();
            return v;
        }
    }
    unlock_collections();
    return OREN_NIL;
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

static void print_value_no_newline(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_INT: printf("%lld", v.as.int_val); break;
        case OREN_TYPE_FLOAT: printf("%f", v.as.float_val); break;
        case OREN_TYPE_BOOL: printf("%s", v.as.bool_val ? "true" : "false"); break;
        case OREN_TYPE_STRING: printf("%s", v.as.string_val); break;
        case OREN_TYPE_NIL: printf("nil"); break;
        case OREN_TYPE_FUNC: printf("<func %p>", (void*)v.as.func_val.fn); break;
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            PyObject* str = PyObject_Str(v.as.py_obj);
            printf("%s", PyUnicode_AsUTF8(str));
            Py_DECREF(str);
            break;
#else
            oren_panic("Python support is disabled");
#endif
        }
        case OREN_TYPE_LIST: {
            printf("[");
            for (int i = 0; i < v.as.list_val->count; i++) {
                if (i > 0) printf(", ");
                print_value_no_newline(v.as.list_val->items[i]);
            }
            printf("]");
            break;
        }
        case OREN_TYPE_MAP: {
             printf("{");
             for (int i = 0; i < v.as.map_val->count; i++) {
                 if (i > 0) printf(", ");
                 print_value_no_newline(v.as.map_val->keys[i]);
                 printf(": ");
                 print_value_no_newline(v.as.map_val->values[i]);
             }
             printf("}");
             break;
        }
    }
}

void oren_print(OrenValue v) {
    print_value_no_newline(v);
    printf("\n");
}

void oren_print_multi(int count, ...) {
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) {
        OrenValue v = va_arg(args, OrenValue);
        print_value_no_newline(v);
        if (i < count - 1) printf(" ");
    }
    printf("\n");
    va_end(args);
}

void oren_print_fmt(OrenValue fmt_val, int count, ...) {
    if (fmt_val.type != OREN_TYPE_STRING) {
        oren_panic("print format must be string");
        return;
    }
    const char* fmt = fmt_val.as.string_val;
    va_list args;
    va_start(args, count);
    
    int arg_idx = 0;
    int len = strlen(fmt);
    int i = 0;
    while (i < len) {
        if (fmt[i] == '{' && i + 1 < len && fmt[i+1] == '}') {
            if (arg_idx < count) {
                OrenValue v = va_arg(args, OrenValue);
                print_value_no_newline(v);
                arg_idx++;
            } else {
                printf("{}");
            }
            i += 2;
        } else {
            putchar(fmt[i]);
            i++;
        }
    }
    printf("\n");
    va_end(args);
}

// Iterator hook for `for x in <container>` sugar.
// Contract:
//   oren_iter_next(container, idx:int) -> [ok:int, value]
// Where ok is 1 when a value exists, 0 when iteration is complete.
//
// v0 iteration rules:
// - list: yields elements (idx 0..len-1)
// - map: yields keys in deterministic key order (idx 0..count-1)
// - string: yields byte codepoints (unsigned 0..255), stops at NUL terminator
OrenValue oren_iter_next(OrenValue container, OrenValue idx) {
    if (idx.type != OREN_TYPE_INT) {
        oren_panic("iter_next expects (container, int idx)");
        return OREN_NIL; // Should not be reached
    }

    long long i = idx.as.int_val;
    if (i < 0) {
        return oren_new_list(2, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_LIST) {
        OrenList* l = container.as.list_val;
        if (i < l->count) {
            return oren_new_list(2, oren_int(1), l->items[(int)i]);
        }
        return oren_new_list(2, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_MAP) {
        OrenMap* m = container.as.map_val;
        if (i < m->count) {
            return oren_new_list(2, oren_int(1), m->keys[(int)i]);
        }
        return oren_new_list(2, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_STRING) {
        const unsigned char* s = (const unsigned char*)container.as.string_val;
        if (!s) {
            return oren_new_list(2, oren_int(0), OREN_NIL);
        }
        unsigned char ch = s[i];
        if (ch == 0) {
            return oren_new_list(2, oren_int(0), OREN_NIL);
        }
        return oren_new_list(2, oren_int(1), oren_int((long long)ch));
    }

    oren_panic("iter_next: unsupported container type (need list/map/string)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_string_len(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("string_len expects string");
        return OREN_NIL; // Should not be reached
    }
    return oren_int((long long)strlen(s.as.string_val));
}

OrenValue oren_string_char_at(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("char_at expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    size_t len = strlen(s.as.string_val);
    if (idx < 0 || (size_t)idx >= len) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char_at index out of range (idx=%lld, len=%zu)", idx, len);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    char buf[2];
    buf[0] = s.as.string_val[idx];
    buf[1] = '\0';
    return oren_string(buf);
}

OrenValue oren_char(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        oren_panic("char expects int");
        return OREN_NIL; // Should not be reached
    }
    long long v = code.as.int_val;
    if (v < 0 || v > 255) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char code out of range (code=%lld)", v);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    char buf[2];
    buf[0] = (char)v;
    buf[1] = '\0';
    return oren_string(buf);
}

static OrenValue oren_string_const(const char* s) {
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = (char*)s;
    return v;
}

OrenValue oren_err(OrenValue code, OrenValue msg) {
    if (code.type != OREN_TYPE_INT || msg.type != OREN_TYPE_STRING) {
        oren_panic("oren_err expects (int, string)");
        return OREN_NIL; // Should not be reached
    }
    return oren_new_map(
        3,
        oren_string_const("__err"), OREN_TRUE,
        oren_string_const("code"), code,
        oren_string_const("msg"), msg
    );
}

OrenValue oren_is_err(OrenValue v) {
    if (v.type != OREN_TYPE_MAP) return OREN_FALSE;
    OrenValue marker = oren_map_get(v, oren_string_const("__err"));
    return oren_bool(oren_is_truthy(marker));
}

OrenValue oren_err_code(OrenValue v) {
    if (!oren_is_err(v).as.bool_val) return oren_int(-1);
    OrenValue code = oren_map_get(v, oren_string_const("code"));
    if (code.type != OREN_TYPE_INT) return oren_int(-1);
    return code;
}

OrenValue oren_err_msg(OrenValue v) {
    if (!oren_is_err(v).as.bool_val) return OREN_NIL;
    OrenValue msg = oren_map_get(v, oren_string_const("msg"));
    if (msg.type != OREN_TYPE_STRING) return OREN_NIL;
    return msg;
}

static OrenValue oren_err_from_errno(const char* action, const char* path, int err) {
    int code = OREN_ERR_IO;
    if (err == EACCES || err == EPERM) code = OREN_ERR_PERM;
    else if (err == ENOENT) code = OREN_ERR_NOT_FOUND;

    char buf[512];
    if (path) snprintf(buf, sizeof(buf), "%s: %s (errno=%d)", action, path, err);
    else snprintf(buf, sizeof(buf), "%s (errno=%d)", action, err);
    return oren_err(oren_int(code), oren_string(buf));
}

OrenValue oren_read_file(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        oren_panic("read_file expects string path");
        return OREN_NIL; // Should not be reached
    }
    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        return oren_err_from_errno("cannot open file", path.as.string_val, errno);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0) {
        fclose(f);
        return oren_err_from_errno("cannot stat file", path.as.string_val, errno);
    }
    char *buf = malloc(size + 1);
    if (!buf) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("out of memory"));
    }
    size_t n = fread(buf, 1, (size_t)size, f);
    buf[size] = '\0';
    fclose(f);
    if (n != (size_t)size) {
        return oren_err_from_errno("cannot read file", path.as.string_val, errno);
    }
    return oren_string(buf);
}

OrenValue oren_write_file(OrenValue path, OrenValue content) {
    if (path.type != OREN_TYPE_STRING || content.type != OREN_TYPE_STRING) {
        oren_panic("write_file expects (string, string)");
        return OREN_NIL; // Should not be reached
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
    }
    size_t len = strlen(content.as.string_val);
    size_t n = fwrite(content.as.string_val, 1, len, f);
    fclose(f);
    if (n != len) {
        return oren_err_from_errno("cannot write file", path.as.string_val, errno);
    }
    return OREN_NIL;
}

OrenValue oren_write_bytes(OrenValue path, OrenValue bytes) {
    if (path.type != OREN_TYPE_STRING || bytes.type != OREN_TYPE_LIST) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes expects (string, list<int>)"));
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
    }
    for (int i = 0; i < bytes.as.list_val->count; i++) {
        OrenValue b = bytes.as.list_val->items[i];
        if (b.type != OREN_TYPE_INT) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes expects list of ints"));
        }
        long long v = b.as.int_val;
        if (v < 0 || v > 255) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes byte out of range"));
        }
        if (fputc((unsigned char)v, f) == EOF) {
            fclose(f);
            return oren_err_from_errno("cannot write bytes", path.as.string_val, errno);
        }
    }
    fclose(f);
    return OREN_NIL;
}

OrenValue oren_read_bytes(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        oren_panic("read_bytes expects string path");
        return OREN_NIL; // Should not be reached
    }

    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        return oren_err_from_errno("cannot open file", path.as.string_val, errno);
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: fseek failed", path.as.string_val, errno);
    }
    long size_long = ftell(f);
    if (size_long < 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: ftell failed", path.as.string_val, errno);
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: fseek failed", path.as.string_val, errno);
    }

    // Oren lists use int counts; reject files too large for the current runtime representation.
    if (size_long > (long)INT32_MAX) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("read_bytes: file too large"));
    }

    int size = (int)size_long;

    unsigned char* buf = NULL;
    if (size > 0) {
        buf = (unsigned char*)malloc((size_t)size);
        if (!buf) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
        }
        size_t nread = fread(buf, 1, (size_t)size, f);
        if ((int)nread != size) {
            free(buf);
            fclose(f);
            return oren_err_from_errno("read_bytes: short read", path.as.string_val, errno);
        }
    }

    fclose(f);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        free(buf);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);

    list->count = size;
    list->capacity = size;
    list->items = NULL;
    if (size > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)size);
        if (!list->items) {
            unlock_collections();
            free(buf);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
        }
        for (int i = 0; i < size; i++) {
            list->items[i] = oren_int((unsigned char)buf[i]);
        }
    }

    unlock_collections();
    free(buf);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_bytes_from_string(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("bytes_from_string expects string");
        return OREN_NIL; // Should not be reached
    }
    size_t n = strlen(s.as.string_val);
    OrenList* list = malloc(sizeof(OrenList));
    list->count = (int)n;
    list->capacity = (int)n;
    list->items = malloc(sizeof(OrenValue) * n);
    for (size_t i = 0; i < n; i++) {
        list->items[i] = oren_int((unsigned char)s.as.string_val[i]);
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_string_from_bytes(OrenValue bytes) {
    if (bytes.type != OREN_TYPE_LIST) {
        oren_panic("string_from_bytes expects list<int 0..255>");
        return OREN_NIL; // Should not be reached
    }
    OrenList* list = bytes.as.list_val;
    if (!list || list->count < 0) {
        oren_panic("string_from_bytes: invalid list");
        return OREN_NIL; // Should not be reached
    }
    size_t n = (size_t)list->count;
    char* buf = (char*)malloc(n + 1);
    if (!buf) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes: out of memory"));
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            free(buf);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes: expected list<int 0..255>"));
        }
        buf[i] = (char)(unsigned char)it.as.int_val;
    }
    buf[n] = 0;
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = buf;
    oren_register_alloc(buf, OREN_ALLOC_STRING);
    return v;
}

typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} OrenSha256Ctx;

static uint32_t oren_sha256_rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
static uint32_t oren_sha256_ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
static uint32_t oren_sha256_maj(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (x & z) ^ (y & z); }
static uint32_t oren_sha256_ep0(uint32_t x) { return oren_sha256_rotr(x, 2) ^ oren_sha256_rotr(x, 13) ^ oren_sha256_rotr(x, 22); }
static uint32_t oren_sha256_ep1(uint32_t x) { return oren_sha256_rotr(x, 6) ^ oren_sha256_rotr(x, 11) ^ oren_sha256_rotr(x, 25); }
static uint32_t oren_sha256_sig0(uint32_t x) { return oren_sha256_rotr(x, 7) ^ oren_sha256_rotr(x, 18) ^ (x >> 3); }
static uint32_t oren_sha256_sig1(uint32_t x) { return oren_sha256_rotr(x, 17) ^ oren_sha256_rotr(x, 19) ^ (x >> 10); }

static const uint32_t OREN_SHA256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void oren_sha256_transform(OrenSha256Ctx* ctx, const uint8_t data[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        int j = i * 4;
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) | ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
    }
    for (int i = 16; i < 64; i++) {
        m[i] = oren_sha256_sig1(m[i - 2]) + m[i - 7] + oren_sha256_sig0(m[i - 15]) + m[i - 16];
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + oren_sha256_ep1(e) + oren_sha256_ch(e, f, g) + OREN_SHA256_K[i] + m[i];
        uint32_t t2 = oren_sha256_ep0(a) + oren_sha256_maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void oren_sha256_init(OrenSha256Ctx* ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void oren_sha256_update(OrenSha256Ctx* ctx, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            oren_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void oren_sha256_final(OrenSha256Ctx* ctx, uint8_t out[32]) {
    uint32_t i = ctx->datalen;

    // Pad with a single 1 bit then zeros.
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        oren_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }

    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    oren_sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; i++) {
        out[i]      = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        out[i + 4]  = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        out[i + 8]  = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        out[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        out[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        out[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        out[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        out[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length) {
    if (bytes.type != OREN_TYPE_LIST || start.type != OREN_TYPE_INT || length.type != OREN_TYPE_INT) {
        oren_panic("sha256_range expects (list, int, int)");
        return OREN_NIL; // Should not be reached
    }
    long long s = start.as.int_val;
    long long n = length.as.int_val;
    if (s < 0 || n < 0 || s + n > bytes.as.list_val->count) {
        char buf[256];
        snprintf(buf, sizeof(buf), "sha256_range out of bounds (s=%lld, n=%lld, count=%d)", s, n, bytes.as.list_val->count);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);

    for (long long i = 0; i < n; i++) {
        OrenValue b = bytes.as.list_val->items[(int)(s + i)];
        if (b.type != OREN_TYPE_INT) {
            oren_panic("sha256_range expects list of ints");
            return OREN_NIL; // Should not be reached
        }
        long long v = b.as.int_val;
        if (v < 0 || v > 255) {
            char buf[128];
            snprintf(buf, sizeof(buf), "sha256_range byte out of range (val=%lld)", v);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        uint8_t byte = (uint8_t)v;
        oren_sha256_update(&ctx, &byte, 1);
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    OrenList* out = malloc(sizeof(OrenList));
    out->count = 32;
    out->capacity = 32;
    out->items = malloc(sizeof(OrenValue) * 32);
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}

OrenValue oren_chmod(OrenValue path, OrenValue mode) {
    if (path.type != OREN_TYPE_STRING || mode.type != OREN_TYPE_INT) {
        oren_panic("chmod expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    if (chmod(path.as.string_val, (mode_t)mode.as.int_val) != 0) {
        char buf[256];
        snprintf(buf, sizeof(buf), "chmod failed for %s", path.as.string_val);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    return OREN_NIL;
}

OrenValue oren_system(OrenValue cmd) {
    if (cmd.type != OREN_TYPE_STRING) {
        oren_panic("system expects string");
        return OREN_NIL; // Should not be reached
    }
    int res = system(cmd.as.string_val);
    return oren_int((long long)res);
}

OrenValue oren_net_get(OrenValue url) {
    (void)url;
    // Native/C backend runtime does not implement host networking in bootstrap.
    // Agentic networking is intended to run via AVM NET domain virtualization.
    return oren_err(oren_int(7), oren_string("net not implemented (use AVM)"));
}

OrenValue oren_exit(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        oren_panic("exit expects int");
        return OREN_NIL; // Should not be reached
    }
    exit((int)code.as.int_val);
    return OREN_NIL;
}

OrenValue oren_int_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_INT) {
        oren_panic("int_to_string expects int");
        return OREN_NIL; // Should not be reached
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%lld", v.as.int_val);
    return oren_string(buf);
}

OrenValue oren_float_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_FLOAT) {
        oren_panic("float_to_string expects float");
        return OREN_NIL; // Should not be reached
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%f", v.as.float_val);
    return oren_string(buf);
}

OrenValue oren_string_to_float_bits(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("string_to_float_bits expects string");
        return OREN_NIL;
    }
    double d = strtod(s.as.string_val, NULL);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return oren_int((long long)bits);
}

OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end) {
    if (s.type != OREN_TYPE_STRING || start.type != OREN_TYPE_INT || end.type != OREN_TYPE_INT) {
        oren_panic("string_slice type mismatch");
        return OREN_NIL; // Should not be reached
    }
    char* str = s.as.string_val;
    long long len = strlen(str);
    long long i = start.as.int_val;
    long long j = end.as.int_val;
    if (i < 0) i = 0;
    if (j > len) j = len;
    if (i >= j) {
        return oren_string("");
    }
    long long n = j - i;
    char* sub = malloc(n + 1);
    strncpy(sub, str + i, n);
    sub[n] = '\0';
    
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = sub;
    return v;
}

// getenv wrapper: returns string or NIL
OrenValue oren_env(OrenValue name) {
    if (name.type != OREN_TYPE_STRING || name.as.string_val == NULL) {
        return OREN_NIL;
    }
    const char* key = name.as.string_val;
    const char* val = getenv(key);
    if (val == NULL) {
        return OREN_NIL;
    }
    return oren_string(val);
}

// Recursive free for compound objects; skips primitives.
void oren_free(OrenValue v) {
    if (v.type == OREN_TYPE_STRING) {
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(v.as.string_val);
        if (n && !n->freed) {
            n->freed = 1;
            free(n->ptr);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_LIST) {
        OrenList* lst = v.as.list_val;
        if (lst == NULL) return;
        for (int i = 0; i < lst->count; i++) {
            oren_free(lst->items[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(lst);
        if (n && !n->freed) {
            n->freed = 1;
            if (lst->items) free(lst->items);
            free(lst);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_MAP) {
        OrenMap* mp = v.as.map_val;
        if (mp == NULL) return;
        for (int i = 0; i < mp->count; i++) {
            oren_free(mp->keys[i]);
            oren_free(mp->values[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(mp);
        if (n && !n->freed) {
            n->freed = 1;
            if (mp->keys) free(mp->keys);
            if (mp->values) free(mp->values);
            free(mp);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
}

void oren_shutdown() {
    // Ensure no threads are running while tearing down runtime allocations.
    oren_join_all();
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = g_allocs;
    while (n != NULL) {
        OrenAllocNode* next = n->next;
        if (!n->freed) {
            if (n->kind == OREN_ALLOC_STRING) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_LIST) {
                OrenList* lst = (OrenList*)n->ptr;
                if (lst->items) free(lst->items);
                free(lst);
            } else if (n->kind == OREN_ALLOC_MAP) {
                OrenMap* mp = (OrenMap*)n->ptr;
                if (mp->keys) free(mp->keys);
                if (mp->values) free(mp->values);
                free(mp);
            } else if (n->kind == OREN_ALLOC_STRUCT) {
                free(n->ptr);
            } else {
                free(n->ptr);
            }
        }
        free(n);
        n = next;
    }
    g_allocs = NULL;
    // Clear registered roots to release bookkeeping nodes
    OrenAllocNode* r = g_roots;
    while (r != NULL) {
        OrenAllocNode* next_r = r->next;
        free(r);
        r = next_r;
    }
    g_roots = NULL;
    pthread_mutex_unlock(&g_alloc_mutex);
}

uint64_t oren_alloc_struct(size_t bytes) {
#ifdef OREN_NO_GC
    void* p = malloc(bytes);
#else
    void* p = malloc(bytes);
    oren_register_alloc(p, OREN_ALLOC_STRUCT);
#endif
    if (!p) {
        oren_panic("struct alloc failed");
        return (uint64_t)p; // Should not be reached, but needed for compiler
    }
    return (uint64_t)p;
}

void oren_free_struct(uint64_t ptr) {
#ifdef OREN_NO_GC
    free((void*)ptr);
    return;
#endif
    void* p = (void*)ptr;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(p);
    if (n && !n->freed) {
        n->freed = 1;
        free(p);
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}
