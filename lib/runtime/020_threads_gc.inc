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
    // Thread stack sizing (rolling):
    // Compiler workloads (stage2 self-hosting) use deep recursion in the parser/typechecker.
    // On macOS, the default pthread stack for non-main threads can be small enough to crash
    // quickly with EXC_BAD_ACCESS when parsing in parallel. Use an explicit, conservative
    // stack size to keep `spawn` robust.
    size_t stack_size = (size_t)(8u << 20); // 8 MiB default
    const char* env_ss = getenv("OREN_THREAD_STACK_SIZE");
    if (env_ss && env_ss[0]) {
        // Decimal bytes only (deterministic; no suffixes).
        size_t out = 0;
        for (size_t i = 0; env_ss[i]; i++) {
            char c = env_ss[i];
            if (c < '0' || c > '9') { out = 0; break; }
            size_t d = (size_t)(c - '0');
            if (out > (SIZE_MAX - d) / 10) { out = 0; break; }
            out = out * 10 + d;
        }
        if (out != 0u) stack_size = out;
    }
    if (stack_size < (size_t)PTHREAD_STACK_MIN) stack_size = (size_t)PTHREAD_STACK_MIN;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    (void)pthread_attr_setstacksize(&attr, stack_size);
    int rc = pthread_create(&t, &attr, oren_spawn0_entry, args);
    pthread_attr_destroy(&attr);
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

// --- POSIX fork-based spawn (opt-in) ---
//
// Why this exists:
// - The self-hosted compiler uses `spawn` for parallel parsing as a pipeline optimization.
// - The C backend runtime GC is not thread-safe yet, so thread-based spawn can corrupt the heap.
// - On POSIX (macOS/Linux) we can safely use fork+pipe for *isolated* workers.
//
// Semantics:
// - Enabled only when env `OREN_SPAWN_FORK=1` (default remains pthread threads).
// - Return value is transferred via pipe as a raw OrenValue struct.
// - Only scalar return types are supported across process boundary:
//   nil/int/bool/float. Pointer-backed values (string/list/map/buf/func/py_obj) are rejected.
//
// NOTE: This is intended for tooling/compilation workers, not general shared-memory concurrency.
#if !defined(_WIN32)
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>

// Track fork-spawned child PIDs so we can reap/kill them if the parent is terminated.
static pthread_mutex_t g_spawn_fork_mu = PTHREAD_MUTEX_INITIALIZER;
static pid_t* g_spawn_fork_pids = NULL;
static size_t g_spawn_fork_pids_len = 0;
static size_t g_spawn_fork_pids_cap = 0;
static int g_spawn_fork_handlers_installed = 0;

static void spawn_fork_pids_add(pid_t pid) {
    if (pid <= 0) return;
    pthread_mutex_lock(&g_spawn_fork_mu);
    if (g_spawn_fork_pids_len == g_spawn_fork_pids_cap) {
        size_t new_cap = g_spawn_fork_pids_cap ? (g_spawn_fork_pids_cap * 2) : 64;
        pid_t* np = (pid_t*)realloc(g_spawn_fork_pids, new_cap * sizeof(pid_t));
        if (np) {
            g_spawn_fork_pids = np;
            g_spawn_fork_pids_cap = new_cap;
        }
    }
    if (g_spawn_fork_pids_len < g_spawn_fork_pids_cap) {
        g_spawn_fork_pids[g_spawn_fork_pids_len++] = pid;
    }
    pthread_mutex_unlock(&g_spawn_fork_mu);
}

static void spawn_fork_pids_remove(pid_t pid) {
    if (pid <= 0) return;
    pthread_mutex_lock(&g_spawn_fork_mu);
    for (size_t i = 0; i < g_spawn_fork_pids_len; i++) {
        if (g_spawn_fork_pids[i] == pid) {
            g_spawn_fork_pids[i] = g_spawn_fork_pids[g_spawn_fork_pids_len - 1];
            g_spawn_fork_pids_len--;
            break;
        }
    }
    pthread_mutex_unlock(&g_spawn_fork_mu);
}

static void spawn_fork_kill_all(int sig) {
    // Best-effort: terminate all tracked children.
    pthread_mutex_lock(&g_spawn_fork_mu);
    for (size_t i = 0; i < g_spawn_fork_pids_len; i++) {
        pid_t pid = g_spawn_fork_pids[i];
        if (pid > 0) (void)kill(pid, sig);
    }
    pthread_mutex_unlock(&g_spawn_fork_mu);
}

static void spawn_fork_reap_all(void) {
    // Best-effort: reap all tracked children (blocking).
    pthread_mutex_lock(&g_spawn_fork_mu);
    for (size_t i = 0; i < g_spawn_fork_pids_len; i++) {
        pid_t pid = g_spawn_fork_pids[i];
        if (pid > 0) {
            int status = 0;
            (void)waitpid(pid, &status, 0);
        }
    }
    g_spawn_fork_pids_len = 0;
    pthread_mutex_unlock(&g_spawn_fork_mu);
}

static void spawn_fork_on_signal(int sig) {
    // Try to kill and reap children, then re-raise default signal.
    spawn_fork_kill_all(SIGTERM);
    spawn_fork_reap_all();
    signal(sig, SIG_DFL);
    raise(sig);
}

static void spawn_fork_install_handlers(void) {
    if (g_spawn_fork_handlers_installed) return;
    g_spawn_fork_handlers_installed = 1;
    signal(SIGTERM, spawn_fork_on_signal);
    signal(SIGINT, spawn_fork_on_signal);
    signal(SIGHUP, spawn_fork_on_signal);
    signal(SIGQUIT, spawn_fork_on_signal);
}
static int oren_spawn_fork_enabled(void) {
    const char* v = getenv("OREN_SPAWN_FORK");
    return (v && v[0] == '1' && v[1] == '\0');
}

static int oren_spawn_debug_enabled(void) {
    const char* v = getenv("OREN_DEBUG_SPAWN");
    return (v && v[0] == '1' && v[1] == '\0');
}

static int write_full(int fd, const void* buf, size_t n) {
    const char* p = (const char*)buf;
    size_t off = 0;
    while (off < n) {
        ssize_t w = write(fd, p + off, n - off);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        off += (size_t)w;
    }
    return 0;
}

static int read_full(int fd, void* buf, size_t n) {
    char* p = (char*)buf;
    size_t off = 0;
    while (off < n) {
        ssize_t r = read(fd, p + off, n - off);
        if (r == 0) return -1;
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        off += (size_t)r;
    }
    return 0;
}
#endif

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

#if !defined(_WIN32)
    if (oren_spawn_fork_enabled()) {
        spawn_fork_install_handlers();
        int fds[2] = {-1, -1};
        if (pipe(fds) != 0) {
            oren_panic("spawn_call_list fork mode: pipe failed");
            return OREN_NIL;
        }
        pid_t pid = fork();
        if (pid < 0) {
            close(fds[0]);
            close(fds[1]);
            oren_panic("spawn_call_list fork mode: fork failed");
            return OREN_NIL;
        }
        if (pid == 0) {
            // Child: run call and write scalar result.
            close(fds[0]);
            if (oren_spawn_debug_enabled()) {
                fprintf(stderr, "[spawn] fork child pid=%lld\n", (long long)getpid());
            }
            OrenValue res = OREN_NIL;
            // IMPORTANT:
            // Stage2 builds often run with conservative scanning knobs disabled
            // (e.g. register/jmpbuf scanning and raw pointer scanning), so we must
            // explicitly root the callable and args list to prevent GC from reclaiming
            // them while the worker runs.
            oren_register_root(&fn);
            oren_register_root(&args_list);
            // Best-effort: isolate panics to a non-zero result.
            OrenThreadState* st = oren_thread_state();
            if (setjmp(st->panic_buf) == 0) {
                st->has_panic_buf = 1;
                res = oren_call_obj_list(fn, args_list);
                st->has_panic_buf = 0;
            } else {
                st->has_panic_buf = 0;
                res = oren_int(1);
            }
            oren_unregister_root(&args_list);
            oren_unregister_root(&fn);

            if (!(res.type == OREN_TYPE_NIL || res.type == OREN_TYPE_INT || res.type == OREN_TYPE_BOOL || res.type == OREN_TYPE_FLOAT)) {
                // Cannot transfer pointer-backed values across fork boundary.
                res = oren_int(1);
            }

            (void)write_full(fds[1], &res, sizeof(res));
            close(fds[1]);
            fflush(NULL);
            _exit(0);
        }

        // Parent: return a process-handle list [pid, read_fd].
        close(fds[1]);
        spawn_fork_pids_add(pid);
        if (oren_spawn_debug_enabled()) {
            fprintf(stderr, "[spawn] fork parent pid=%lld child=%lld rfd=%d\n", (long long)getpid(), (long long)pid, fds[0]);
        }
        OrenValue h = oren_new_list_from_array(2, (OrenValue[]){oren_int((long long)pid), oren_int((long long)fds[0])});
        return h;
    }
#endif

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
    // See `oren_spawn0`: explicit stack size to avoid pthread default-stack crashes
    // under recursive compiler workloads.
    size_t stack_size = (size_t)(8u << 20); // 8 MiB default
    const char* env_ss = getenv("OREN_THREAD_STACK_SIZE");
    if (env_ss && env_ss[0]) {
        size_t out = 0;
        for (size_t i = 0; env_ss[i]; i++) {
            char c = env_ss[i];
            if (c < '0' || c > '9') { out = 0; break; }
            size_t d = (size_t)(c - '0');
            if (out > (SIZE_MAX - d) / 10) { out = 0; break; }
            out = out * 10 + d;
        }
        if (out != 0u) stack_size = out;
    }
    if (stack_size < (size_t)PTHREAD_STACK_MIN) stack_size = (size_t)PTHREAD_STACK_MIN;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    (void)pthread_attr_setstacksize(&attr, stack_size);
    int rc = pthread_create(&t, &attr, oren_spawn_call_entry, args);
    pthread_attr_destroy(&attr);
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
#if !defined(_WIN32)
    // Fork-based spawn handle: [pid, read_fd]
    if (thread.type == OREN_TYPE_LIST && thread.as.list_val && thread.as.list_val->count == 2) {
        OrenValue pidv = thread.as.list_val->items[0];
        OrenValue fdv = thread.as.list_val->items[1];
        if (pidv.type != OREN_TYPE_INT || fdv.type != OREN_TYPE_INT) {
            oren_panic("join: invalid fork handle");
            return OREN_NIL;
        }
        pid_t pid = (pid_t)pidv.as.int_val;
        int rfd = (int)fdv.as.int_val;
        if (oren_spawn_debug_enabled()) {
            fprintf(stderr, "[join] fork parent pid=%lld child=%lld rfd=%d\n", (long long)getpid(), (long long)pid, rfd);
        }
        OrenValue res = OREN_NIL;
        (void)read_full(rfd, &res, sizeof(res));
        close(rfd);
        int status = 0;
        (void)waitpid(pid, &status, 0);
        spawn_fork_pids_remove(pid);
        return res;
    }
#endif

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
    // Join must be GC-cooperative:
    // A worker thread may initiate a stop-the-world GC at a safepoint, which requires
    // *all other threads* (including the main thread waiting in join) to enter safepoints.
    // Blocking in `pthread_join` prevents that and can deadlock stage2 self-hosting builds.
    //
    // Wait for completion via the per-thread condition variable (with periodic GC safepoints),
    // then `pthread_join` only once we know the thread is finished.
    pthread_mutex_lock(&n->mu);
    while (!n->done) {
        // Release the node lock while entering a safepoint to avoid lock inversion.
        pthread_mutex_unlock(&n->mu);
        oren_gc_safepoint();
        pthread_mutex_lock(&n->mu);

        // Sleep briefly while waiting (absolute time) so we don't busy-spin.
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        long ns = ts.tv_nsec + 10 * 1000 * 1000; // 10ms
        ts.tv_sec += (time_t)(ns / 1000000000L);
        ts.tv_nsec = (long)(ns % 1000000000L);
        (void)pthread_cond_timedwait(&n->cv, &n->mu, &ts);
    }
    pthread_mutex_unlock(&n->mu);
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
        // Infinite wait: use the same GC-cooperative join loop as `oren_join`.
        lock_collections();
        n->joined = 1;
        unlock_collections();
        pthread_mutex_lock(&n->mu);
        while (!n->done) {
            pthread_mutex_unlock(&n->mu);
            oren_gc_safepoint();
            pthread_mutex_lock(&n->mu);
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            long ns = ts.tv_nsec + 10 * 1000 * 1000; // 10ms
            ts.tv_sec += (time_t)(ns / 1000000000L);
            ts.tv_nsec = (long)(ns % 1000000000L);
            (void)pthread_cond_timedwait(&n->cv, &n->mu, &ts);
        }
        pthread_mutex_unlock(&n->mu);
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
        // GC-cooperative finite wait:
        // wait in small slices so we can enter GC safepoints while the caller is blocked.
        struct timespec end;
        clock_gettime(CLOCK_REALTIME, &end);
        long long end_ns = (long long)end.tv_nsec + (ms * 1000000LL);
        end.tv_sec += (time_t)(end_ns / 1000000000LL);
        end.tv_nsec = (long)(end_ns % 1000000000LL);

        while (!n->done) {
            struct timespec now;
            clock_gettime(CLOCK_REALTIME, &now);
            // Check timeout.
            if (now.tv_sec > end.tv_sec || (now.tv_sec == end.tv_sec && now.tv_nsec >= end.tv_nsec)) {
                break;
            }
            // Wait for up to 10ms (or until end).
            struct timespec slice = now;
            long ns2 = slice.tv_nsec + 10 * 1000 * 1000;
            slice.tv_sec += (time_t)(ns2 / 1000000000L);
            slice.tv_nsec = (long)(ns2 % 1000000000L);
            if (slice.tv_sec > end.tv_sec || (slice.tv_sec == end.tv_sec && slice.tv_nsec > end.tv_nsec)) {
                slice = end;
            }
            int rc = pthread_cond_timedwait(&n->cv, &n->mu, &slice);
            if (n->done) break;
            if (rc == ETIMEDOUT) {
                // Release lock and hit a GC safepoint between slices.
                pthread_mutex_unlock(&n->mu);
                oren_gc_safepoint();
                pthread_mutex_lock(&n->mu);
                continue;
            }
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
    OREN_ARG_LIST->items = malloc(sizeof(OrenValue) * (size_t)argc);
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

#if !defined(_WIN32)
static void oren_raise_stack_limit_best_effort(void) {
    // Stage2 self-hosting (native backend) uses deep recursion in compiler passes (parser/typechecker/codegen).
    // On macOS, the default soft stack limit can be ~8MiB, which is too small and can crash with
    // EXC_BAD_ACCESS in `___chkstk_darwin`. Raise the soft limit up to the hard limit when possible.
    struct rlimit rl;
    if (getrlimit(RLIMIT_STACK, &rl) != 0) return;
    if (rl.rlim_cur >= rl.rlim_max) return;
    rlim_t want = rl.rlim_max;
    if (want == RLIM_INFINITY) {
        // Conservative fallback when the hard limit is reported as infinite.
        want = (rlim_t)(64u * 1024u * 1024u);
        if (rl.rlim_cur >= want) return;
    }
    rl.rlim_cur = want;
    (void)setrlimit(RLIMIT_STACK, &rl);
}
#endif

void oren_init(int argc, char **argv) {
#if !defined(_WIN32)
    oren_raise_stack_limit_best_effort();
#endif
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

OrenValue oren_closure_from_array(OrenFn fn, int capture_count, const OrenValue* captures) {
    if (!fn) return OREN_NIL;
    if (capture_count <= 0) {
        return oren_func(fn, NULL);
    }

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        oren_panic("closure_from_array: env alloc failed");
        return OREN_NIL; // Should not be reached
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = capture_count;
    list->capacity = capture_count;
    list->items = malloc(sizeof(OrenValue) * (size_t)capture_count);
    if (!list->items) {
        unlock_collections();
        oren_panic("closure_from_array: env items alloc failed");
        return OREN_NIL; // Should not be reached
    }
    if (captures) {
        memcpy(list->items, captures, sizeof(OrenValue) * (size_t)capture_count);
    } else {
        for (int i = 0; i < capture_count; i++) list->items[i] = OREN_NIL;
    }
    unlock_collections();
    return oren_func(fn, list);
}

int oren_is_truthy(OrenValue v) {
    if (v.type == OREN_TYPE_NIL) return 0;
    if (v.type == OREN_TYPE_BOOL) return v.as.bool_val;
    return 1;
}
