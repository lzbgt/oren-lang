#include <sys/stat.h>
#include <pthread.h>
#include <errno.h>
#include <setjmp.h>
#include <execinfo.h>
#include <time.h>
#include <sys/time.h>
#include <limits.h>
#include <sys/mman.h>

// Some platforms name the anonymous-map flag MAP_ANON instead of MAP_ANONYMOUS.
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

OrenValue OREN_NIL;
OrenValue OREN_TRUE;
OrenValue OREN_FALSE;
static OrenList *OREN_ARG_LIST = NULL;
static OrenValue OREN_RESULT_VALUE;

// Forward decl: runtime uses "const string" keys in hot paths without heap allocation.
static OrenValue oren_string_const(const char* s);

typedef enum {
    OREN_ALLOC_STRING = 1,
    OREN_ALLOC_LIST = 2,
    OREN_ALLOC_MAP = 3,
    OREN_ALLOC_STRUCT = 4,
    // Opaque raw bytes (no pointers). Used for typed buffer payloads and other HPC blobs.
    OREN_ALLOC_RAW = 5,
    // mmap-backed opaque raw bytes (returned to OS via munmap on free/GC sweep).
    OREN_ALLOC_RAW_MMAP = 6
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

// Large raw blocks: use mmap so memory can be returned to the OS on free/GC sweep.
// Keep this conservative; below this threshold libc allocation is typically faster.
#define OREN_RAW_MMAP_THRESHOLD_DEFAULT ((size_t)(1u << 20)) // 1 MiB

static size_t parse_env_size(const char* s, size_t def) {
    if (!s || !s[0]) return def;
    // Decimal only, no suffixes, deterministic.
    size_t out = 0;
    for (size_t i = 0; s[i]; i++) {
        char c = s[i];
        if (c < '0' || c > '9') return def;
        size_t d = (size_t)(c - '0');
        if (out > (SIZE_MAX - d) / 10) return def;
        out = out * 10 + d;
    }
    return out;
}

static size_t raw_mmap_threshold_cached(void) {
    // Cached to keep allocation hot path fast and deterministic.
    static size_t cached = (size_t)-1;
    if (cached != (size_t)-1) return cached;
    size_t thr = parse_env_size(getenv("OREN_RAW_MMAP_THRESHOLD"), OREN_RAW_MMAP_THRESHOLD_DEFAULT);
    // Allow:
    // - 0: disable mmap path entirely (always posix_memalign/malloc backend)
    // - 1: effectively "always mmap" for non-empty allocations
    cached = thr;
    return cached;
}

typedef struct {
    uint64_t magic;
    uint64_t total_size;   // bytes mapped/allocated for base (including this header)
    uint8_t backend;       // 0=malloc/posix_memalign, 1=mmap
    uint8_t _pad[47];
} OrenRawHdr;

static const uint64_t OREN_RAW_MAGIC = 0x4f52454e52415730ull; // "ORENRAW0"

// Allocation registry acceleration:
//
// g_allocs remains the canonical linked list for sweep iteration.
// g_alloc_index is an O(1) pointer->node index to avoid O(n) scans in `oren_find_node`,
// which becomes a bottleneck for allocation-heavy workloads (HPC, serde, etc.).
//
// IMPORTANT:
// - All access to this index must happen under g_alloc_mutex, matching existing registry discipline.
// - We intentionally keep a simple open-addressing table: deterministic, no libc hash maps.
static OrenAllocNode** g_alloc_index = NULL;
static size_t g_alloc_index_cap = 0;
static size_t g_alloc_index_len = 0;
#define OREN_ALLOC_INDEX_TOMBSTONE ((OrenAllocNode*)(uintptr_t)1)

static size_t oren_ptr_hash(void* p) {
    uintptr_t x = (uintptr_t)p;
    // Mix like a splitmix-ish avalanche (deterministic).
    x ^= x >> 33;
    x *= (uintptr_t)0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= (uintptr_t)0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return (size_t)x;
}

static void oren_alloc_index_init_locked(size_t cap) {
    if (cap < 1024) cap = 1024;
    // Keep power-of-two for fast masking.
    size_t c = 1;
    while (c < cap) c <<= 1;
    g_alloc_index = (OrenAllocNode**)calloc(c, sizeof(OrenAllocNode*));
    if (!g_alloc_index) {
        fprintf(stderr, "alloc index init failed\n");
        exit(1);
    }
    g_alloc_index_cap = c;
    g_alloc_index_len = 0;
}

static void oren_alloc_index_put_locked(OrenAllocNode* n);

static void oren_alloc_index_rebuild_locked(size_t new_cap) {
    OrenAllocNode** old = g_alloc_index;
    g_alloc_index = NULL;
    g_alloc_index_cap = 0;
    g_alloc_index_len = 0;
    oren_alloc_index_init_locked(new_cap);

    // Reinsert all current nodes (including freed markers; they remain addressable).
    OrenAllocNode* cur = g_allocs;
    while (cur) {
        oren_alloc_index_put_locked(cur);
        cur = cur->next;
    }

    free(old);
}

static void oren_alloc_index_maybe_grow_locked() {
    if (g_alloc_index == NULL) {
        oren_alloc_index_init_locked(2048);
        return;
    }
    // Keep load factor <= ~0.7 (tombstones are cleaned on rebuild).
    if ((g_alloc_index_len + 1) * 10 >= g_alloc_index_cap * 7) {
        oren_alloc_index_rebuild_locked(g_alloc_index_cap * 2);
    }
}

static void oren_alloc_index_put_locked(OrenAllocNode* n) {
    if (!n || !n->ptr) return;
    oren_alloc_index_maybe_grow_locked();
    size_t mask = g_alloc_index_cap - 1;
    size_t i = oren_ptr_hash(n->ptr) & mask;
    size_t first_tomb = (size_t)-1;
    while (1) {
        OrenAllocNode* slot = g_alloc_index[i];
        if (slot == NULL) {
            if (first_tomb != (size_t)-1) i = first_tomb;
            g_alloc_index[i] = n;
            g_alloc_index_len++;
            return;
        }
        if (slot == OREN_ALLOC_INDEX_TOMBSTONE) {
            if (first_tomb == (size_t)-1) first_tomb = i;
        } else if (slot->ptr == n->ptr) {
            // Replace (shouldn't happen, but keep deterministic).
            g_alloc_index[i] = n;
            return;
        }
        i = (i + 1) & mask;
    }
}

static OrenAllocNode* oren_alloc_index_get_locked(void* ptr) {
    if (!ptr || !g_alloc_index || g_alloc_index_cap == 0) return NULL;
    size_t mask = g_alloc_index_cap - 1;
    size_t i = oren_ptr_hash(ptr) & mask;
    while (1) {
        OrenAllocNode* slot = g_alloc_index[i];
        if (slot == NULL) return NULL;
        if (slot != OREN_ALLOC_INDEX_TOMBSTONE && slot->ptr == ptr) return slot;
        i = (i + 1) & mask;
    }
}

static void oren_alloc_index_remove_locked(void* ptr) {
    if (!ptr || !g_alloc_index || g_alloc_index_cap == 0) return;
    size_t mask = g_alloc_index_cap - 1;
    size_t i = oren_ptr_hash(ptr) & mask;
    while (1) {
        OrenAllocNode* slot = g_alloc_index[i];
        if (slot == NULL) return;
        if (slot != OREN_ALLOC_INDEX_TOMBSTONE && slot->ptr == ptr) {
            g_alloc_index[i] = OREN_ALLOC_INDEX_TOMBSTONE;
            return;
        }
        i = (i + 1) & mask;
    }
}
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
    uint64_t call_depth;
    uint64_t call_depth_max;
    jmp_buf panic_buf;
    int has_panic_buf;
    struct OrenThreadState* next;
} OrenThreadState;

// Native/C stack safety: guard recursion depth deterministically to avoid host OS stack overflows.
// Conservative default; override per-process via env.
#define OREN_CALL_DEPTH_MAX_DEFAULT ((uint64_t)8192u)

static uint64_t parse_env_u64(const char* s, uint64_t def) {
    if (!s || !s[0]) return def;
    uint64_t out = 0;
    for (size_t i = 0; s[i]; i++) {
        char c = s[i];
        if (c < '0' || c > '9') return def;
        uint64_t d = (uint64_t)(c - '0');
        if (out > (UINT64_MAX - d) / 10) return def;
        out = out * 10 + d;
    }
    return out;
}

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
        st->call_depth = 0;
        st->call_depth_max = parse_env_u64(getenv("OREN_CALL_DEPTH_MAX"), OREN_CALL_DEPTH_MAX_DEFAULT);
        if (st->call_depth_max == 0) st->call_depth_max = OREN_CALL_DEPTH_MAX_DEFAULT;
        pthread_setspecific(g_thread_key, st);
        lock_collections();
        g_threads_total++;
        st->next = g_thread_states;
        g_thread_states = st;
        unlock_collections();
    }
    return st;
}

static void oren_diag_emit(const char* kind, int code, const char* msg) {
    // Stable, machine-readable diagnostic header for tools/AI agents.
    //
    // Format:
    //   OREN_DIAG kind=<kind> code=<code> msg=<sanitized>
    //
    // Best-effort: keep this allocation-free and robust even during failure.
    if (!kind) kind = "unknown";
    if (!msg) msg = "";
    fprintf(stderr, "OREN_DIAG kind=%s code=%d msg=", kind, code);
    // Sanitize newlines/tabs so logs stay single-line and parseable.
    for (int i = 0; msg[i] && i < 1024; i++) {
        unsigned char c = (unsigned char)msg[i];
        if (c == '\n') { fputs("\\n", stderr); continue; }
        if (c == '\r') { fputs("\\r", stderr); continue; }
        if (c == '\t') { fputs("\\t", stderr); continue; }
        fputc(c, stderr);
    }
    fputc('\n', stderr);
}

void oren_call_depth_enter() {
    OrenThreadState* st = oren_thread_state();
    if (!st) return;
    st->call_depth++;
    if (st->call_depth > st->call_depth_max) {
        oren_panic("call depth exceeded");
    }
}

void oren_call_depth_exit() {
    OrenThreadState* st = oren_thread_state();
    if (!st) return;
    if (st->call_depth > 0) st->call_depth--;
}

void oren_panic(const char* msg) {
    oren_diag_emit("panic", 1, msg);
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

OrenValue oren_fail(OrenValue code, OrenValue msg) {
    // Fail-fast helper for tests + internal invariants.
    // Emits an AI-friendly diagnostic line + a stack trace.
    int ec = 1;
    const char* s = "";
    if (code.type == OREN_TYPE_INT) {
        ec = (int)code.as.int_val;
    }
    if (msg.type == OREN_TYPE_STRING) {
        s = msg.as.string_val ? msg.as.string_val : "";
    }
    oren_diag_emit("fail", ec, s);
    fprintf(stderr, "Runtime Fail: %s\n", s);
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    fprintf(stderr, "Stack Trace:\n");
    backtrace_symbols_fd(callstack, frames, 2);
    exit(ec);
    return OREN_NIL;
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
    oren_alloc_index_put_locked(n);
    pthread_mutex_unlock(&g_alloc_mutex);
}

static OrenAllocNode* oren_find_node(void* ptr) {
    // Contract: caller holds g_alloc_mutex (mark/sweep or explicit frees).
    // Fallback to linear scan only if index isn't initialized (should not happen in practice).
    OrenAllocNode* n = oren_alloc_index_get_locked(ptr);
    if (n) return n;
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
        if (n && n->freed == 0 && n->kind == OREN_ALLOC_LIST) {
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
        if (n && n->freed == 0 && n->kind == OREN_ALLOC_MAP) {
            n->freed = -1;
            for (int i = 0; i < mp->count; i++) {
                oren_mark_value(mp->keys[i]);
                oren_mark_value(mp->values[i]);
            }
        }
        return;
    }
    if (v.type == OREN_TYPE_U8_BUF || v.type == OREN_TYPE_I32_BUF || v.type == OREN_TYPE_I64_BUF || v.type == OREN_TYPE_F32_BUF || v.type == OREN_TYPE_F64_BUF) {
        // Buffers are GC-tracked heap headers + raw payload bytes. Payload contains no pointers.
        // Mark both header and payload allocations so payload cannot be collected independently.
        OrenBuf* b = v.as.buf_val;
        if (!b) return;
        OrenAllocNode* n = oren_find_node(b);
        if (n && n->freed == 0 && n->kind == OREN_ALLOC_STRUCT) {
            n->freed = -1;
            // Payload is a separate RAW allocation (aligned); keep it alive too.
            if (b->data) {
                OrenAllocNode* dn = oren_find_node(b->data);
                if (dn && dn->freed == 0 && (dn->kind == OREN_ALLOC_RAW || dn->kind == OREN_ALLOC_RAW_MMAP)) dn->freed = -1;
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
            void* dead_ptr = n->ptr;
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
            } else if (n->kind == OREN_ALLOC_RAW_MMAP) {
                // munmap-backed raw bytes (header is stored immediately before payload).
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->backend == 1 && h->total_size > 0) {
                    (void)munmap((void*)h, (size_t)h->total_size);
                } else {
                    // Fallback to free if something is inconsistent (best-effort).
                    free(n->ptr);
                }
            } else if (n->kind == OREN_ALLOC_RAW) {
                // aligned raw bytes allocated as base+header via posix_memalign.
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->backend == 0 && h->total_size > 0) {
                    free((void*)h);
                } else {
                    free(n->ptr);
                }
            } else {
                free(n->ptr);
            }
            OrenAllocNode* to_free = n;
            n = n->next;
            if (prev) prev->next = n; else g_allocs = n;
            if (dead_ptr) oren_alloc_index_remove_locked(dead_ptr);
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
    return t >= OREN_TYPE_NIL && t <= OREN_TYPE_F64_BUF;
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
