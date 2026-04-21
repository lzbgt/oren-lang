#include <errno.h>
#include <limits.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#if !defined(_WIN32)
#include <dirent.h>
#if defined(__linux__)
#include <sched.h>
#endif
#include <unistd.h>
#endif

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN 1
#endif
#ifndef NOMINMAX
#define NOMINMAX 1
#endif

#include <malloc.h>
#include <process.h>
#include <io.h>
#include <windows.h>
#include <direct.h>

// MSVC uses `_strdup`; keep callsites portable.
#ifndef strdup
#define strdup _strdup
#endif

#ifndef ETIMEDOUT
#define ETIMEDOUT 110
#endif

// MSVC's UCRT provides `struct timespec` in <time.h> (VS2022 Tier‑1).
// Keep a fallback for non-MSVC toolchains.
#if !defined(_MSC_VER)
#ifndef _TIMESPEC_DEFINED
#define _TIMESPEC_DEFINED 1
struct timespec {
    time_t tv_sec;
    long tv_nsec;
};
#endif
#endif

typedef int clockid_t;
#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif

static uint64_t oren_win_time_unix_ns(void) {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER u;
    u.LowPart = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    // FILETIME is 100ns ticks since 1601-01-01 UTC.
    // Convert to Unix epoch nanoseconds.
    const uint64_t EPOCH_DIFF_100NS = 116444736000000000ULL;
    uint64_t t100 = (u.QuadPart >= EPOCH_DIFF_100NS) ? (u.QuadPart - EPOCH_DIFF_100NS) : 0ULL;
    return t100 * 100ULL;
}

static uint64_t oren_win_time_mono_ns(void) {
    static LARGE_INTEGER freq = {0};
    static int inited = 0;
    if (!inited) {
        QueryPerformanceFrequency(&freq);
        inited = 1;
    }
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    if (freq.QuadPart <= 0) return 0ULL;
    // Convert ticks -> ns with integer arithmetic (best-effort).
    uint64_t t = (uint64_t)c.QuadPart;
    uint64_t f = (uint64_t)freq.QuadPart;
    return (t * 1000000000ULL) / f;
}

static int clock_gettime(clockid_t clk, struct timespec* ts) {
    if (!ts) return -1;
    uint64_t ns = 0;
    if (clk == CLOCK_MONOTONIC) ns = oren_win_time_mono_ns();
    else ns = oren_win_time_unix_ns();
    ts->tv_sec = (time_t)(ns / 1000000000ULL);
    ts->tv_nsec = (long)(ns % 1000000000ULL);
    return 0;
}

static int nanosleep(const struct timespec* req, struct timespec* rem) {
    (void)rem;
    if (!req) return -1;
    // Windows `Sleep` is milliseconds. Round up so we don't sleep less than requested.
    uint64_t ns = 0;
    if (req->tv_sec > 0) ns += (uint64_t)req->tv_sec * 1000000000ULL;
    if (req->tv_nsec > 0) ns += (uint64_t)req->tv_nsec;
    DWORD ms = (DWORD)((ns + 999999ULL) / 1000000ULL);
    if (ms == 0) return 0;
    Sleep(ms);
    return 0;
}

// --- Minimal pthread shims for MSVC bootstrap builds (Windows) ---
//
// The stage0 compiler builds stage1 by emitting C and compiling `lib/runtime.c`.
// To support a native Windows bring-up (MSVC `cl.exe`), provide the small subset of the
// pthread API used by the C runtime, implemented on Win32 primitives.
//
// NOTE: this is intentionally minimal and may diverge from full pthread semantics.
// It is sufficient for the repo's current C-backend runtime needs.

typedef SRWLOCK pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef INIT_ONCE pthread_once_t;
typedef DWORD pthread_key_t;
typedef struct {
    SIZE_T stack_size;
} pthread_attr_t;
typedef struct {
    HANDLE handle;
} pthread_t;

#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
#define PTHREAD_COND_INITIALIZER CONDITION_VARIABLE_INIT
#define PTHREAD_ONCE_INIT INIT_ONCE_STATIC_INIT
#define PTHREAD_STACK_MIN 0u

static int pthread_mutex_init(pthread_mutex_t* mu, void* attr) {
    (void)attr;
    if (!mu) return EINVAL;
    InitializeSRWLock(mu);
    return 0;
}
static int pthread_mutex_destroy(pthread_mutex_t* mu) {
    (void)mu;
    return 0;
}
static int pthread_mutex_lock(pthread_mutex_t* mu) {
    if (!mu) return EINVAL;
    AcquireSRWLockExclusive(mu);
    return 0;
}
static int pthread_mutex_unlock(pthread_mutex_t* mu) {
    if (!mu) return EINVAL;
    ReleaseSRWLockExclusive(mu);
    return 0;
}
static int pthread_mutex_trylock(pthread_mutex_t* mu) {
    if (!mu) return EINVAL;
    return TryAcquireSRWLockExclusive(mu) ? 0 : 1;
}

static int pthread_cond_init(pthread_cond_t* cv, void* attr) {
    (void)attr;
    if (!cv) return EINVAL;
    InitializeConditionVariable(cv);
    return 0;
}
static int pthread_cond_destroy(pthread_cond_t* cv) {
    (void)cv;
    return 0;
}
static int pthread_cond_broadcast(pthread_cond_t* cv) {
    if (!cv) return EINVAL;
    WakeAllConditionVariable(cv);
    return 0;
}
static int pthread_cond_wait(pthread_cond_t* cv, pthread_mutex_t* mu) {
    if (!cv || !mu) return EINVAL;
    BOOL ok = SleepConditionVariableSRW(cv, mu, INFINITE, 0);
    return ok ? 0 : EINVAL;
}
static int pthread_cond_timedwait(pthread_cond_t* cv, pthread_mutex_t* mu, const struct timespec* abstime) {
    if (!cv || !mu || !abstime) return EINVAL;
    uint64_t target_ns = 0;
    if (abstime->tv_sec > 0) target_ns += (uint64_t)abstime->tv_sec * 1000000000ULL;
    if (abstime->tv_nsec > 0) target_ns += (uint64_t)abstime->tv_nsec;
    uint64_t now_ns = oren_win_time_unix_ns();
    DWORD timeout_ms = 0;
    if (target_ns > now_ns) {
        uint64_t diff_ns = target_ns - now_ns;
        uint64_t ms = (diff_ns + 999999ULL) / 1000000ULL; // ceil
        timeout_ms = (ms > (uint64_t)0xFFFFFFFFu) ? 0xFFFFFFFFu : (DWORD)ms;
    }
    BOOL ok = SleepConditionVariableSRW(cv, mu, timeout_ms, 0);
    if (ok) return 0;
    DWORD e = GetLastError();
    if (e == ERROR_TIMEOUT) return ETIMEDOUT;
    return EINVAL;
}

typedef struct {
    void* (*start)(void*);
    void* arg;
} OrenWinThreadStart;

static unsigned __stdcall oren_win_thread_start(void* p) {
    OrenWinThreadStart* a = (OrenWinThreadStart*)p;
    void* (*fn)(void*) = a ? a->start : NULL;
    void* arg = a ? a->arg : NULL;
    if (a) free(a);
    if (fn) (void)fn(arg);
    return 0;
}

static int pthread_attr_init(pthread_attr_t* attr) {
    if (!attr) return EINVAL;
    attr->stack_size = 0;
    return 0;
}
static int pthread_attr_setstacksize(pthread_attr_t* attr, size_t stack_size) {
    if (!attr) return EINVAL;
    attr->stack_size = (SIZE_T)stack_size;
    return 0;
}
static int pthread_attr_destroy(pthread_attr_t* attr) {
    (void)attr;
    return 0;
}

static int pthread_create(pthread_t* out, const pthread_attr_t* attr, void* (*start)(void*), void* arg) {
    if (!out || !start) return EINVAL;
    OrenWinThreadStart* a = (OrenWinThreadStart*)malloc(sizeof(OrenWinThreadStart));
    if (!a) return ENOMEM;
    a->start = start;
    a->arg = arg;
    SIZE_T stack_size = attr ? attr->stack_size : 0;
    unsigned tid = 0;
    uintptr_t h = _beginthreadex(NULL, (unsigned)stack_size, oren_win_thread_start, a, 0, &tid);
    if (h == 0) {
        free(a);
        return EAGAIN;
    }
    out->handle = (HANDLE)h;
    return 0;
}

static int pthread_detach(pthread_t t) {
    if (t.handle) CloseHandle(t.handle);
    return 0;
}

static int pthread_join(pthread_t t, void** ret) {
    (void)ret;
    if (!t.handle) return EINVAL;
    (void)WaitForSingleObject(t.handle, INFINITE);
    CloseHandle(t.handle);
    return 0;
}

static int pthread_key_create(pthread_key_t* key, void (*destructor)(void*)) {
    (void)destructor;
    if (!key) return EINVAL;
    DWORD k = TlsAlloc();
    if (k == TLS_OUT_OF_INDEXES) return EAGAIN;
    *key = k;
    return 0;
}
static void* pthread_getspecific(pthread_key_t key) { return TlsGetValue(key); }
static int pthread_setspecific(pthread_key_t key, const void* value) {
    return TlsSetValue(key, (LPVOID)value) ? 0 : EINVAL;
}

static BOOL CALLBACK oren_win_once_cb(PINIT_ONCE once, PVOID param, PVOID* ctx) {
    (void)once;
    (void)ctx;
    void (*fn)(void) = (void (*)(void))param;
    if (fn) fn();
    return TRUE;
}
static int pthread_once(pthread_once_t* once, void (*fn)(void)) {
    if (!once || !fn) return EINVAL;
    return InitOnceExecuteOnce(once, oren_win_once_cb, (PVOID)fn, NULL) ? 0 : EINVAL;
}

// --- Atomics (MSVC C mode does not provide C11 <stdatomic.h>) ---
typedef volatile LONG OrenAtomicInt;
typedef volatile LONGLONG OrenAtomicSize;

static inline int oren_atomic_load_int(OrenAtomicInt* p) {
    return (int)InterlockedCompareExchange((volatile LONG*)p, 0, 0);
}
static inline void oren_atomic_store_int(OrenAtomicInt* p, int v) {
    (void)InterlockedExchange((volatile LONG*)p, (LONG)v);
}
static inline size_t oren_atomic_load_size(OrenAtomicSize* p) {
    return (size_t)InterlockedCompareExchange64((volatile LONGLONG*)p, 0, 0);
}
static inline void oren_atomic_store_size(OrenAtomicSize* p, size_t v) {
    (void)InterlockedExchange64((volatile LONGLONG*)p, (LONGLONG)v);
}
static inline size_t oren_atomic_fetch_add_size(OrenAtomicSize* p, size_t v) {
    LONGLONG add = (LONGLONG)v;
    LONGLONG prev = InterlockedExchangeAdd64((volatile LONGLONG*)p, add);
    return (size_t)prev;
}

#define OREN_ATOMIC_LOAD_INT(p) oren_atomic_load_int((p))
#define OREN_ATOMIC_STORE_INT(p, v) oren_atomic_store_int((p), (v))
#define OREN_ATOMIC_LOAD_SIZE(p) oren_atomic_load_size((p))
#define OREN_ATOMIC_STORE_SIZE(p, v) oren_atomic_store_size((p), (v))
#define OREN_ATOMIC_FETCH_ADD_SIZE(p, v) oren_atomic_fetch_add_size((p), (v))

#else

#include <execinfo.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>

typedef _Atomic int OrenAtomicInt;
typedef _Atomic size_t OrenAtomicSize;

#define OREN_ATOMIC_LOAD_INT(p) atomic_load_explicit((p), memory_order_relaxed)
#define OREN_ATOMIC_STORE_INT(p, v) atomic_store_explicit((p), (v), memory_order_relaxed)
#define OREN_ATOMIC_LOAD_SIZE(p) atomic_load_explicit((p), memory_order_relaxed)
#define OREN_ATOMIC_STORE_SIZE(p, v) atomic_store_explicit((p), (v), memory_order_relaxed)
#define OREN_ATOMIC_FETCH_ADD_SIZE(p, v) atomic_fetch_add_explicit((p), (v), memory_order_relaxed)

#endif

// Some platforms name the anonymous-map flag MAP_ANON instead of MAP_ANONYMOUS.
#if !defined(_WIN32)
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif
#endif

OrenValue OREN_NIL;
OrenValue OREN_TRUE;
OrenValue OREN_FALSE;
static OrenList *OREN_ARG_LIST = NULL;
static OrenValue OREN_RESULT_VALUE;

// Forward decl: runtime uses "const string" keys in hot paths without heap allocation.
OrenValue oren_string_const(const char* s);

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

// Fast conservative-GC filter:
// Most machine words on the stack/register snapshots are not pointers into the Oren heap.
// Track a coarse [min,max] allocation address range so the mark phase can skip the vast
// majority of false positives without hashing into the alloc index.
//
// NOTE:
// This is an optimization only. The alloc registry/index remains authoritative.
static uintptr_t g_alloc_ptr_min = UINTPTR_MAX;
static uintptr_t g_alloc_ptr_max = 0;
static size_t oren_ptr_hash(void* p);
// Bloom filter to skip most false positives before doing an alloc-index lookup.
//
// IMPORTANT:
// This bloom is rebuilt during GC to avoid long-running saturation under allocation-heavy
// workloads (e.g. compiler stage2 self-hosting). A monotonic bloom quickly becomes all-ones,
// devolving the mark phase into expensive pointer-index lookups for almost every stack word.
#define OREN_ALLOC_BLOOM_WORDS 8192u // 8192 * 64 = 524,288 bits (64 KiB)
static uint64_t g_alloc_bloom[OREN_ALLOC_BLOOM_WORDS];

static inline void oren_alloc_bloom_add(uintptr_t p) {
    // Two hashes -> two bits. Deterministic and cheap.
    // NOTE: callers should canonicalize tagged pointers before inserting.
    size_t h1 = oren_ptr_hash((void*)p);
    size_t h2 = oren_ptr_hash((void*)(p ^ (uintptr_t)0x9e3779b97f4a7c15ULL));
    size_t i1 = h1 & (OREN_ALLOC_BLOOM_WORDS - 1u);
    size_t i2 = h2 & (OREN_ALLOC_BLOOM_WORDS - 1u);
    g_alloc_bloom[i1] |= (uint64_t)1u << ((h1 >> 16) & 63u);
    g_alloc_bloom[i2] |= (uint64_t)1u << ((h2 >> 16) & 63u);
}

static inline int oren_alloc_bloom_maybe_has(uintptr_t p) {
    // NOTE: callers should canonicalize tagged pointers before querying.
    size_t h1 = oren_ptr_hash((void*)p);
    size_t h2 = oren_ptr_hash((void*)(p ^ (uintptr_t)0x9e3779b97f4a7c15ULL));
    size_t i1 = h1 & (OREN_ALLOC_BLOOM_WORDS - 1u);
    size_t i2 = h2 & (OREN_ALLOC_BLOOM_WORDS - 1u);
    uint64_t b1 = g_alloc_bloom[i1] & ((uint64_t)1u << ((h1 >> 16) & 63u));
    uint64_t b2 = g_alloc_bloom[i2] & ((uint64_t)1u << ((h2 >> 16) & 63u));
    return (b1 != 0u) && (b2 != 0u);
}

static void oren_alloc_filters_rebuild_locked(void) {
    // Rebuild conservative-GC acceleration filters from the current allocation list.
    // Required to prevent bloom saturation and stale min/max ranges across long-running workloads.
    g_alloc_ptr_min = UINTPTR_MAX;
    g_alloc_ptr_max = 0;
    memset(g_alloc_bloom, 0, sizeof(g_alloc_bloom));

    OrenAllocNode* cur = g_allocs;
    while (cur) {
        uintptr_t p = (uintptr_t)cur->ptr;
#if defined(__aarch64__)
        p &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
        if (p != 0u) {
            if (p < g_alloc_ptr_min) g_alloc_ptr_min = p;
            if (p > g_alloc_ptr_max) g_alloc_ptr_max = p;
            oren_alloc_bloom_add(p);
        }
        cur = cur->next;
    }
}

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

// --- GC auto-collection (rolling) ---
//
// The safepoint+stop-the-world collector requires some thread to *initiate* a collection.
// In rolling builds we enable a conservative auto-trigger in single-threaded programs so
// long-running tools (like the compiler self-hosting stage2) don't balloon to multi‑GB RSS.
//
// Multi-threaded auto-GC remains opt-in; initiating a stop-the-world collection while other
// threads don't reach safepoints would deadlock. Keep this conservative until concurrency
// semantics are formalized.
static int gc_auto_enabled_cached(void);
static size_t gc_alloc_threshold_cached(void) {
    // 0 disables auto-GC.
    // Default tuned for compiler workloads; adjust via env as needed.
    static size_t cached = (size_t)-1;
    if (cached != (size_t)-1) return cached;
    // Rolling default:
    // - The compiler self-hosting stage2 build enables auto-GC (OREN_GC_AUTO=1).
    // - A too-small threshold causes frequent stop-the-world collections and can blow the
    //   3-minute self-hosting gate by >10x in large-module builds.
    //
    // If the user did not set OREN_GC_ALLOC_THRESHOLD explicitly, pick a much higher default
    // when auto-GC is enabled.
    const char* env = getenv("OREN_GC_ALLOC_THRESHOLD");
    if (env && env[0]) {
        cached = parse_env_size(env, 200000u);
    } else {
        cached = gc_auto_enabled_cached() ? 4000000u : 200000u;
    }
    return cached;
}

static int gc_auto_enabled_cached(void) {
    // 0 disables; any other non-empty numeric value enables. Default: disabled.
    static int cached = -1;
    if (cached != -1) return cached;
    // Default off: keep baseline fast and avoid unexpected stop-the-world pauses.
    // Compiler self-hosting can opt in via env (Makefile stage2 does this).
    size_t v = parse_env_size(getenv("OREN_GC_AUTO"), 0u);
    cached = (v != 0u);
    return cached;
}

static size_t gc_stack_scan_limit_bytes_cached(void) {
    // 0 disables the limit (scan the full [sp,top] range).
    // Keep this bounded by default to avoid pathological GC pauses on deep stacks.
    static size_t cached = (size_t)-1;
    if (cached != (size_t)-1) return cached;
    const char* env = getenv("OREN_GC_STACK_SCAN_LIMIT_BYTES");
    if (env && env[0]) {
        cached = parse_env_size(env, (size_t)(2u << 20)); // 2 MiB fallback
        return cached;
    }
    // Default policy (rolling):
    // - Auto-GC is used mainly for long-running tools (compiler stage2 self-hosting).
    // - Full-stack raw pointer scanning is extremely expensive and dominates runtime.
    // - Prefer a bounded scan by default; correctness for long-lived objects is ensured by
    //   explicit GC roots in hot components (parser/compiler structures) + setjmp snapshots.
    // - For debugging/maximum conservatism, users can set OREN_GC_STACK_SCAN_LIMIT_BYTES=0
    //   to scan the full stack.
    if (gc_auto_enabled_cached()) {
        // With precise per-thread roots (oren_roots_*), we do not need full-stack conservative
        // scanning for compiler correctness under parallel builds. Keep a bounded scan as a
        // best-effort safety net for non-generated C code and legacy paths.
        cached = (size_t)(2u << 20); // 2 MiB
    }
    else cached = (size_t)(2u << 20); // 2 MiB
    return cached;
}

static int gc_raw_ptr_scan_enabled_cached(void) {
    // Extra conservative scanning mode:
    // - When enabled, the GC scans the raw stack bytes as pointer words and tries to find
    //   heap allocations. This is expensive but can rescue pointers that are not present
    //   as well-formed OrenValue values on the stack (e.g., optimized register spills).
    //
    // For performance-sensitive tool workloads (compiler self-hosting), it can be disabled
    // via env `OREN_GC_RAW_PTR_SCAN=0` when explicit roots + register snapshots are sufficient.
    static int cached = -1;
    if (cached != -1) return cached;
    const char* env = getenv("OREN_GC_RAW_PTR_SCAN");
    if (env && env[0]) {
        cached = (env[0] != '0');
        return cached;
    }
    // Rolling policy:
    // - Raw stack-byte scanning is extremely expensive; on compiler workloads it can dominate.
    // - When auto-GC is enabled we prefer explicit roots + jmpbuf scanning over raw-byte scans.
    cached = gc_auto_enabled_cached() ? 0 : 1;
    return cached;
}

static int gc_jmpbuf_scan_enabled_cached(void) {
    // Conservative scanning of jmp_buf/register snapshots (setjmp/longjmp):
    // - This improves correctness under aggressive optimization (-O2) when values live only in registers.
    // - It can also increase retention because the saved register image is scanned as raw pointer words.
    //
    // For memory-sensitive workloads (compiler stage2 self-hosting), users can disable it via:
    //   OREN_GC_SCAN_JMPBUFS=0
    // and rely on explicit roots + OrenValue-shaped stack scanning instead.
    static int cached = -1;
    if (cached != -1) return cached;
    const char* env = getenv("OREN_GC_SCAN_JMPBUFS");
    if (env && env[0]) {
        cached = (env[0] != '0');
        return cached;
    }
    cached = 1;
    return cached;
}

static OrenAtomicSize g_gc_allocs_since_collect = 0;
static OrenAtomicInt g_gc_auto_pending = 0;

typedef struct {
    uint64_t magic;
    uint64_t total_size;   // bytes mapped/allocated for base (including this header)
    uint8_t backend;       // 0=malloc/posix_memalign, 1=mmap
    uint8_t _pad[47];
} OrenRawHdr;

static const uint64_t OREN_RAW_MAGIC = 0x4f52454e52415730ull; // "ORENRAW0"

static void oren_raw_free_hdr(OrenRawHdr* h) {
    if (!h) return;
    if (h->magic != OREN_RAW_MAGIC || h->total_size == 0) {
        // Unknown/corrupt header; best-effort fallback.
        free((void*)h);
        return;
    }
#if defined(_WIN32)
    if (h->backend == 1) {
        (void)VirtualFree((void*)h, 0, MEM_RELEASE);
        return;
    }
    _aligned_free((void*)h);
#else
    if (h->backend == 1) {
        (void)munmap((void*)h, (size_t)h->total_size);
        return;
    }
    free((void*)h);
#endif
}

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
            // Maintain an accurate occupied-entry count so the index does not grow
            // without bound across GC cycles (tombstones are not counted as live).
            if (g_alloc_index_len > 0) g_alloc_index_len--;
            return;
        }
        i = (i + 1) & mask;
    }
}
static pthread_mutex_t g_collection_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_collection_cv = PTHREAD_COND_INITIALIZER;
static OrenAtomicInt g_gc_requested = 0;
static OrenAtomicInt g_gc_in_progress = 0;
static int g_threads_total = 0;
static int g_threads_waiting = 0;
static OrenAtomicInt g_threads_started = 0;
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
    uint64_t safepoint_tick;
    uint64_t call_depth;
    uint64_t call_depth_max;
    OrenValue gc_pin;
    // Precise root stack (fast, rolling):
    // Stores addresses of OrenValue slots that must be considered GC roots.
    // Generated C code uses mark/reset to manage lifetimes deterministically.
    OrenValue** root_slots;
    size_t root_slots_len;
    size_t root_slots_cap;
    // Rooted temporaries by value (does not require taking the address of a local).
    // This avoids forcing large numbers of temporaries onto the C stack.
    OrenValue* root_vals;
    size_t root_vals_len;
    size_t root_vals_cap;
    // Thread-local allocation staging to reduce global mutex contention.
    // Allocations are registered into this per-thread list and flushed in batches.
    OrenAllocNode* local_allocs;
    size_t local_allocs_len;
    jmp_buf panic_buf;
    int has_panic_buf;
    // Best-effort register snapshot for conservative GC (setjmp spills caller-saved state).
    // Cleared by the collector after each collection so stale snapshots don't pin objects.
    jmp_buf gc_buf;
    int has_gc_buf;
    // Extra register snapshot for conservative GC (rolling):
    // Store a best-effort copy of general-purpose registers in stable memory so the collector
    // can find roots even when `setjmp` does not preserve caller-saved registers on a platform.
    uintptr_t gc_regs[64];
    int has_gc_regs;
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

static void thread_state_key_destructor(void* p) {
    if (!p) return;
    OrenThreadState* st = (OrenThreadState*)p;
    if (st->root_slots) {
        free(st->root_slots);
        st->root_slots = NULL;
        st->root_slots_len = 0u;
        st->root_slots_cap = 0u;
    }
    if (st->root_vals) {
        free(st->root_vals);
        st->root_vals = NULL;
        st->root_vals_len = 0u;
        st->root_vals_cap = 0u;
    }
    free(st);
}

static void thread_key_init(void) {
    (void)pthread_key_create(&g_thread_key, thread_state_key_destructor);
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
        // Capture a conservative "stack top" (highest address) so GC can scan all live frames.
        //
        // IMPORTANT:
        // Using the address of a local variable here is NOT sufficient, because that
        // address lives in the current call frame (and can be *below* older frames).
        // When GC runs later, scanning only up to that marker can miss live pointers
        // in outer frames, leading to use-after-free and memory corruption.
        //
        // Prefer OS APIs when available; fall back to a best-effort marker otherwise.
#if defined(__APPLE__)
        // Darwin nuance:
        // - `pthread_get_stackaddr_np` returns the "base" of the stack, but its exact meaning
        //   (high vs low address) depends on platform/ABI quirks.
        // - If we misinterpret it as the high end, GC stack scanning can walk into the
        //   guard page and crash with SIGBUS under multi-threaded workloads (stage2 build).
        //
        // Make it robust by using stack size and the current stack pointer to infer the
        // high address boundary deterministically.
        int stack_marker = 0;
        uintptr_t sp = (uintptr_t)&stack_marker;
        void* stack_addr = pthread_get_stackaddr_np(pthread_self());
        size_t stack_size = pthread_get_stacksize_np(pthread_self());
        if (stack_addr && stack_size > 0) {
            uintptr_t base = (uintptr_t)stack_addr;
            // If the reported base is below the current SP, treat it as the low address.
            // Otherwise treat it as the high address (common on Darwin where stacks grow down).
            uintptr_t high = (base <= sp) ? (base + (uintptr_t)stack_size) : base;
            st->stack_top = (void*)high;
        } else {
            st->stack_top = (void*)sp;
        }
#elif defined(__linux__)
        pthread_attr_t attr;
        if (pthread_getattr_np(pthread_self(), &attr) == 0) {
            void* stack_addr = NULL;
            size_t stack_size = 0;
            if (pthread_attr_getstack(&attr, &stack_addr, &stack_size) == 0 && stack_addr && stack_size > 0) {
                st->stack_top = (void*)((char*)stack_addr + stack_size); // high address
            }
            pthread_attr_destroy(&attr);
        }
        if (!st->stack_top) {
            int stack_marker = 0;
            st->stack_top = (void*)&stack_marker;
        }
#elif defined(_WIN32)
        // Win8+ provides an authoritative stack range API, but keep a dynamic lookup so
        // this compiles cleanly without requiring a specific SDK define.
        //
        // On Win11 (Tier‑1), this should always succeed and keeps GC stack scanning correct.
        typedef void(WINAPI* GetCurrentThreadStackLimitsFn)(PULONG_PTR, PULONG_PTR);
        static GetCurrentThreadStackLimitsFn pGetLimits = NULL;
        static int pGetLimits_inited = 0;
        if (!pGetLimits_inited) {
            HMODULE k32 = GetModuleHandleA("kernel32.dll");
            if (k32) {
                pGetLimits = (GetCurrentThreadStackLimitsFn)GetProcAddress(k32, "GetCurrentThreadStackLimits");
            }
            pGetLimits_inited = 1;
        }
        if (pGetLimits) {
            ULONG_PTR lo = 0, hi = 0;
            pGetLimits(&lo, &hi);
            if (hi != 0) st->stack_top = (void*)hi; // high address
        }
        if (!st->stack_top) {
            int stack_marker = 0;
            st->stack_top = (void*)&stack_marker;
        }
#else
        int stack_marker = 0;
        st->stack_top = (void*)&stack_marker;
#endif
        st->stack_sp = NULL;
        st->has_panic_buf = 0;
        st->call_depth = 0;
        st->call_depth_max = parse_env_u64(getenv("OREN_CALL_DEPTH_MAX"), OREN_CALL_DEPTH_MAX_DEFAULT);
        st->gc_pin = OREN_NIL;
        st->root_slots = NULL;
        st->root_slots_len = 0u;
        st->root_slots_cap = 0u;
        st->root_vals = NULL;
        st->root_vals_len = 0u;
        st->root_vals_cap = 0u;
        st->local_allocs = NULL;
        st->local_allocs_len = 0u;
        // Config contract: OREN_CALL_DEPTH_MAX=0 disables the deterministic guard (unlimited).
        if (st->call_depth_max == 0) st->call_depth_max = UINT64_MAX;
        pthread_setspecific(g_thread_key, st);
        lock_collections();
        g_threads_total++;
        st->next = g_thread_states;
        g_thread_states = st;
        unlock_collections();
    }
    return st;
}

OrenValue oren_gc_pin(OrenValue v) {
#ifdef OREN_NO_GC
    (void)v;
    return OREN_NIL;
#endif
    OrenThreadState* st = oren_thread_state();
    if (!st) return OREN_NIL;
    OrenValue prev = st->gc_pin;
    st->gc_pin = v;
    return prev;
}

size_t oren_roots_mark(void) {
#ifdef OREN_NO_GC
    return 0u;
#endif
    OrenThreadState* st = oren_thread_state();
    if (!st) return 0u;
    // Pack (slots_len, vals_len) into one size_t mark for cheap nested scopes.
    //  - low 32 bits: slot roots length
    //  - high 32 bits: value roots length
    // On 32-bit builds, fall back to slot roots only.
#if SIZE_MAX <= UINT32_MAX
    return st->root_slots_len;
#else
    size_t lo = (size_t)(st->root_slots_len & 0xFFFFFFFFu);
    size_t hi = (size_t)(st->root_vals_len & 0xFFFFFFFFu);
    return lo | (hi << 32);
#endif
}

void oren_roots_push(OrenValue* slot) {
#ifdef OREN_NO_GC
    (void)slot;
    return;
#endif
    if (!slot) return;
    OrenThreadState* st = oren_thread_state();
    if (!st) return;
    if (st->root_slots_len == st->root_slots_cap) {
        size_t new_cap = st->root_slots_cap ? (st->root_slots_cap * 2u) : 256u;
        OrenValue** np = (OrenValue**)realloc(st->root_slots, new_cap * sizeof(OrenValue*));
        if (!np) {
            fprintf(stderr, "root stack realloc failed\n");
            exit(1);
        }
        st->root_slots = np;
        st->root_slots_cap = new_cap;
    }
    st->root_slots[st->root_slots_len++] = slot;
}

void oren_roots_push_value(OrenValue v) {
#ifdef OREN_NO_GC
    (void)v;
    return;
#endif
    OrenThreadState* st = oren_thread_state();
    if (!st) return;
    if (st->root_vals_len == st->root_vals_cap) {
        size_t new_cap = st->root_vals_cap ? (st->root_vals_cap * 2u) : 256u;
        OrenValue* np = (OrenValue*)realloc(st->root_vals, new_cap * sizeof(OrenValue));
        if (!np) {
            fprintf(stderr, "root vals realloc failed\n");
            exit(1);
        }
        st->root_vals = np;
        st->root_vals_cap = new_cap;
    }
    st->root_vals[st->root_vals_len++] = v;
}

void oren_roots_reset(size_t mark) {
#ifdef OREN_NO_GC
    (void)mark;
    return;
#endif
    OrenThreadState* st = oren_thread_state();
    if (!st) return;
#if SIZE_MAX <= UINT32_MAX
    if (mark > st->root_slots_len) mark = st->root_slots_len;
    st->root_slots_len = mark;
    st->root_vals_len = 0u;
#else
    size_t slots_mark = (size_t)(mark & 0xFFFFFFFFu);
    size_t vals_mark = (size_t)(mark >> 32);
    if (slots_mark > st->root_slots_len) slots_mark = st->root_slots_len;
    if (vals_mark > st->root_vals_len) vals_mark = st->root_vals_len;
    st->root_slots_len = slots_mark;
    st->root_vals_len = vals_mark;
#endif
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
    
    fprintf(stderr, "Stack Trace:\n");
#if defined(_WIN32)
    fprintf(stderr, "  <stack trace not implemented for C runtime on Windows yet>\n");
#else
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    backtrace_symbols_fd(callstack, frames, 2);
#endif
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
    fprintf(stderr, "Stack Trace:\n");
#if defined(_WIN32)
    fprintf(stderr, "  <stack trace not implemented for C runtime on Windows yet>\n");
#else
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    backtrace_symbols_fd(callstack, frames, 2);
#endif
    exit(ec);
    return OREN_NIL;
}

static void oren_thread_unregister(void) {
    (void)pthread_once(&g_thread_key_once, thread_key_init);
    OrenThreadState* st = (OrenThreadState*)pthread_getspecific(g_thread_key);
    if (!st) return;

    // Cooperate if a collection is in progress.
    if (OREN_ATOMIC_LOAD_INT(&g_gc_requested)) {
        oren_gc_safepoint();
    }

    lock_collections();
    // Flush any thread-local staged allocations so they remain visible to GC and shutdown
    // after this thread state is removed.
    if (st->local_allocs) {
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* cur = st->local_allocs;
        st->local_allocs = NULL;
        st->local_allocs_len = 0u;
        while (cur) {
            OrenAllocNode* next = cur->next;
            cur->next = g_allocs;
            g_allocs = cur;
            oren_alloc_index_put_locked(cur);
            uintptr_t p = (uintptr_t)cur->ptr;
#if defined(__aarch64__)
            p &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
            if (p < g_alloc_ptr_min) g_alloc_ptr_min = p;
            if (p > g_alloc_ptr_max) g_alloc_ptr_max = p;
            oren_alloc_bloom_add(p);
            cur = next;
        }
        pthread_mutex_unlock(&g_alloc_mutex);
    }
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
    if (st->root_slots) {
        free(st->root_slots);
        st->root_slots = NULL;
        st->root_slots_len = 0u;
        st->root_slots_cap = 0u;
    }
    if (st->root_vals) {
        free(st->root_vals);
        st->root_vals = NULL;
        st->root_vals_len = 0u;
        st->root_vals_cap = 0u;
    }
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
    // PERF (rolling):
    // The self-hosted compiler allocates heavily (strings/tokens/AST nodes).
    // Registering every allocation under a single global mutex becomes the dominant cost
    // under parse parallelism. Stage2 (<3min) requires batching here.
    OrenThreadState* st = oren_thread_state();
    if (!st) {
        // Fallback: no TLS state, register globally.
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
        uintptr_t p = (uintptr_t)ptr;
#if defined(__aarch64__)
        p &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
        if (p < g_alloc_ptr_min) g_alloc_ptr_min = p;
        if (p > g_alloc_ptr_max) g_alloc_ptr_max = p;
        oren_alloc_bloom_add(p);
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }

    OrenAllocNode* n = (OrenAllocNode*)malloc(sizeof(OrenAllocNode));
    if (!n) {
        fprintf(stderr, "alloc registry failed\n");
        exit(1);
    }
    n->ptr = ptr;
    n->kind = kind;
    n->freed = 0;
    n->next = st->local_allocs;
    st->local_allocs = n;
    st->local_allocs_len++;

    // Flush in batches to keep global registry coherent and avoid unbounded per-thread staging.
    // Default chosen to amortize mutex cost while keeping GC scans bounded.
    static size_t flush_batch_cached = (size_t)-1;
    if (flush_batch_cached == (size_t)-1) {
        // Default: large batch to minimize global mutex contention under parallel compiler workloads.
        // GC flushes all staged allocations at collection start, so correctness does not require
        // frequent per-thread flushing in the steady state.
        flush_batch_cached = parse_env_size(getenv("OREN_ALLOC_FLUSH_BATCH"), 65536u);
        if (flush_batch_cached == 0u) flush_batch_cached = 4096u;
    }
    if (st->local_allocs_len >= flush_batch_cached) {
        pthread_mutex_lock(&g_alloc_mutex);
        // Splice staged allocations into the global list and update the alloc index/filters.
        OrenAllocNode* cur = st->local_allocs;
        st->local_allocs = NULL;
        st->local_allocs_len = 0u;
        while (cur) {
            OrenAllocNode* next = cur->next;
            cur->next = g_allocs;
            g_allocs = cur;
            oren_alloc_index_put_locked(cur);
            uintptr_t p = (uintptr_t)cur->ptr;
#if defined(__aarch64__)
            p &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
            if (p < g_alloc_ptr_min) g_alloc_ptr_min = p;
            if (p > g_alloc_ptr_max) g_alloc_ptr_max = p;
            oren_alloc_bloom_add(p);
            cur = next;
        }
        pthread_mutex_unlock(&g_alloc_mutex);
    }

#ifndef OREN_NO_GC
    // Single-thread auto-collection: keep memory bounded for long-running tools.
    if (!gc_auto_enabled_cached()) return;
    size_t thr = gc_alloc_threshold_cached();
    if (thr == 0u) return;
    size_t allocs_now = OREN_ATOMIC_FETCH_ADD_SIZE(&g_gc_allocs_since_collect, 1u) + 1u;
    if (allocs_now < thr) return;
    OREN_ATOMIC_STORE_SIZE(&g_gc_allocs_since_collect, 0u);

    // Avoid deadlocks: skip if the collections mutex is already held (or contended).
    // Mark a pending GC request instead; the next `oren_gc_safepoint()` will initiate the collection.
    if (pthread_mutex_trylock(&g_collection_mutex) != 0) return;
    if (!OREN_ATOMIC_LOAD_INT(&g_gc_in_progress)) {
        OREN_ATOMIC_STORE_INT(&g_gc_auto_pending, 1);
    }
    pthread_mutex_unlock(&g_collection_mutex);
#endif
}

static OrenAllocNode* oren_find_node(void* ptr) {
    // Contract: caller holds g_alloc_mutex (mark/sweep or explicit frees).
    // Fallback to linear scan only if index isn't initialized (should not happen in practice).
    // Canonicalize possible tagged/signed pointers from conservative stack/register scans.
#if defined(__aarch64__)
    uintptr_t canon_u = ((uintptr_t)ptr) & (uintptr_t)0x0000FFFFFFFFFFFFULL;
    ptr = (void*)canon_u;
#endif
    uintptr_t p = (uintptr_t)ptr;
    if (g_alloc_ptr_max < g_alloc_ptr_min) return NULL;
    if (p < g_alloc_ptr_min || p > g_alloc_ptr_max) return NULL;
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
static void oren_mark_ptr_range_words(void* a, void* b);
static void oren_mark_stack_range(void* a, void* b);

static inline void oren_capture_gp_regs_words(uintptr_t* out_words, size_t out_words_len) {
    if (!out_words || out_words_len == 0) return;
    // Deterministic init: avoid leaving uninitialized stack/register garbage in the snapshot.
    for (size_t i = 0; i < out_words_len; i++) out_words[i] = 0u;

#if defined(__aarch64__)
    // IMPORTANT (correctness under -O2 + inlining):
    // Do NOT force the output pointer into a fixed register (e.g. x16). When this helper is
    // inlined into hot loops (compiler stage2), the optimizer may keep live OrenValues in
    // arbitrary caller-saved registers, including x16. Forcing `%0` into x16 would overwrite
    // a live root *without* giving the compiler a chance to spill it, which can lead to GC
    // missing roots and freeing live objects (observed as type-tag drift / "index get on non-list/map").
    //
    // Let the compiler choose an operand register; it will spill any live values as needed.
    asm volatile(
        "stp x0,  x1,  [%0, #0]\n"
        "stp x2,  x3,  [%0, #16]\n"
        "stp x4,  x5,  [%0, #32]\n"
        "stp x6,  x7,  [%0, #48]\n"
        "stp x8,  x9,  [%0, #64]\n"
        "stp x10, x11, [%0, #80]\n"
        "stp x12, x13, [%0, #96]\n"
        "stp x14, x15, [%0, #112]\n"
        "stp x16, x17, [%0, #128]\n"
        "stp x18, x19, [%0, #144]\n"
        "stp x20, x21, [%0, #160]\n"
        "stp x22, x23, [%0, #176]\n"
        "stp x24, x25, [%0, #192]\n"
        "stp x26, x27, [%0, #208]\n"
        "stp x28, x29, [%0, #224]\n"
        "str x30,      [%0, #240]\n"
        :
        : "r"(out_words)
        : "memory");
#elif defined(__x86_64__) || defined(_M_X64)
#if defined(_MSC_VER)
    // MSVC x64 does not support GNU-style inline asm.
    // Best-effort: rely on jmp_buf snapshots + explicit roots for conservative GC.
    (void)out_words;
    (void)out_words_len;
#else
    asm volatile(
        "mov %%rax, 0(%0)\n"
        "mov %%rbx, 8(%0)\n"
        "mov %%rcx, 16(%0)\n"
        "mov %%rdx, 24(%0)\n"
        "mov %%rsi, 32(%0)\n"
        "mov %%rdi, 40(%0)\n"
        "mov %%rbp, 48(%0)\n"
        "mov %%r8,  56(%0)\n"
        "mov %%r9,  64(%0)\n"
        "mov %%r10, 72(%0)\n"
        "mov %%r11, 80(%0)\n"
        "mov %%r12, 88(%0)\n"
        "mov %%r13, 96(%0)\n"
        "mov %%r14, 104(%0)\n"
        "mov %%r15, 112(%0)\n"
        :
        : "r"(out_words)
        : "memory");
#endif
#else
    (void)out_words;
    (void)out_words_len;
#endif
}

void oren_gc_collect() {
#ifdef OREN_NO_GC
    return;
#endif
    OrenThreadState* self = oren_thread_state();
    (void)self;

    lock_collections();
    while (OREN_ATOMIC_LOAD_INT(&g_gc_in_progress)) {
        pthread_cond_wait(&g_collection_cv, &g_collection_mutex);
    }
    OREN_ATOMIC_STORE_INT(&g_gc_in_progress, 1);
    OREN_ATOMIC_STORE_INT(&g_gc_requested, 1);
    pthread_cond_broadcast(&g_collection_cv);
    while (g_threads_waiting < (g_threads_total - 1)) {
        pthread_cond_wait(&g_collection_cv, &g_collection_mutex);
    }

    pthread_mutex_lock(&g_alloc_mutex);
    // Flush thread-local staged allocations into the global registry before marking.
    // GC is stop-the-world at this point, so no other thread can mutate its local list.
    OrenThreadState* ts = g_thread_states;
    while (ts) {
        if (ts->local_allocs) {
            OrenAllocNode* cur = ts->local_allocs;
            ts->local_allocs = NULL;
            ts->local_allocs_len = 0u;
            while (cur) {
                OrenAllocNode* next = cur->next;
                cur->next = g_allocs;
                g_allocs = cur;
                oren_alloc_index_put_locked(cur);
                uintptr_t p = (uintptr_t)cur->ptr;
#if defined(__aarch64__)
                p &= (uintptr_t)0x0000FFFFFFFFFFFFULL;
#endif
                if (p < g_alloc_ptr_min) g_alloc_ptr_min = p;
                if (p > g_alloc_ptr_max) g_alloc_ptr_max = p;
                oren_alloc_bloom_add(p);
                cur = next;
            }
        }
        ts = ts->next;
    }
    // PERF (rolling):
    // Rebuilding the conservative-GC filters is O(n) over tracked allocations, and the sweep
    // phase is already O(n). Keep filter rebuild opt-in so stage2 self-hosting is not paying
    // for multiple full-heap scans per collection by default.
    if (getenv("OREN_GC_REBUILD_FILTERS") != NULL) {
        oren_alloc_filters_rebuild_locked();
    }
    OrenAllocNode* n = g_allocs;
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
        // IMPORTANT:
        // `done/result/fn/args_list` are mutated by worker threads under `t->mu`.
        // The collector must not read them without synchronization, otherwise the
        // data race can cause memory corruption (observed as SIGBUS / type-tag drift
        // during stage2 parallel builds).
        int done = 0;
        OrenValue result = OREN_NIL;
        OrenValue fn = OREN_NIL;
        OrenValue args_list = OREN_NIL;
        pthread_mutex_lock(&t->mu);
        done = t->done;
        result = t->result;
        fn = t->fn;
        args_list = t->args_list;
        pthread_mutex_unlock(&t->mu);
        if (done) oren_mark_value(result);
        oren_mark_value(fn);
        oren_mark_value(args_list);
        t = t->next;
    }

    // Conservative stack scanning over all registered threads.
    int self_sp_marker = 0;
    void* self_sp = (void*)&self_sp_marker;

    // Snapshot this thread's registers so GC can see OrenValues kept in registers under -O2.
    // We scan the saved register image as raw pointer words.
    if (gc_jmpbuf_scan_enabled_cached()) {
        jmp_buf self_regs;
        (void)setjmp(self_regs);
        oren_mark_ptr_range_words((void*)&self_regs, (void*)((char*)&self_regs + sizeof(self_regs)));
    }

        OrenThreadState* cur = g_thread_states;
        while (cur) {
            // Explicit thread-local GC pin (compiler uses this for parser state).
            oren_mark_value(cur->gc_pin);
            // Precise root stack (generated C code uses this for locals/temporaries).
            if (cur->root_slots && cur->root_slots_len > 0u) {
                for (size_t ri = 0; ri < cur->root_slots_len; ri++) {
                    OrenValue* slot = cur->root_slots[ri];
                    if (slot) oren_mark_value(*slot);
                }
            }
            if (cur->root_vals && cur->root_vals_len > 0u) {
                for (size_t ri = 0; ri < cur->root_vals_len; ri++) {
                    oren_mark_value(cur->root_vals[ri]);
                }
            }
            void* sp = cur->stack_sp;
            void* top = cur->stack_top;
        if (cur == self) {
            sp = self_sp;
        }
        if (sp != NULL && top != NULL) {
            uintptr_t lo = (uintptr_t)sp;
            uintptr_t hi = (uintptr_t)top;
            if (lo > hi) { uintptr_t tmp = lo; lo = hi; hi = tmp; }
            size_t lim = gc_stack_scan_limit_bytes_cached();
            if (lim != 0u && hi > lo && (hi - lo) > (uintptr_t)lim) {
                hi = lo + (uintptr_t)lim;
            }
            oren_mark_stack_range((void*)lo, (void*)hi);

            if (gc_raw_ptr_scan_enabled_cached()) {
                // Extra conservative scan: look for raw heap pointers even when the compiler
                // has split an OrenValue across registers/stack slots under -O2.
                oren_mark_ptr_range_words((void*)lo, (void*)hi);
            }
        }
        if (cur->has_panic_buf && gc_jmpbuf_scan_enabled_cached()) {
            // Panics are implemented via setjmp/longjmp. The saved register image can
            // contain live heap pointers (callee-saved regs) that may not be present
            // as a well-formed OrenValue on the stack.
            oren_mark_ptr_range_words((void*)&cur->panic_buf, (void*)((char*)&cur->panic_buf + sizeof(cur->panic_buf)));
        }
        if (cur->has_gc_regs) {
            if (gc_jmpbuf_scan_enabled_cached()) {
                oren_mark_ptr_range_words((void*)&cur->gc_regs, (void*)((char*)&cur->gc_regs + sizeof(cur->gc_regs)));
            }
            cur->has_gc_regs = 0;
        }
        if (cur->has_gc_buf) {
            if (gc_jmpbuf_scan_enabled_cached()) {
                oren_mark_ptr_range_words((void*)&cur->gc_buf, (void*)((char*)&cur->gc_buf + sizeof(cur->gc_buf)));
            }
            cur->has_gc_buf = 0;
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
                if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
                    oren_raw_free_hdr(h);
                } else {
                    // Fallback to free if something is inconsistent (best-effort).
                    free(n->ptr);
                }
            } else if (n->kind == OREN_ALLOC_RAW) {
                // aligned raw bytes allocated as base+header via posix_memalign.
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
                    oren_raw_free_hdr(h);
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

    OREN_ATOMIC_STORE_INT(&g_gc_requested, 0);
    OREN_ATOMIC_STORE_INT(&g_gc_in_progress, 0);
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

    // PERF (rolling):
    // Calling into the slow safepoint path on every loop iteration is very expensive for
    // compiler workloads (lexer/parser). Most safepoints do not need to take locks.
    //
    // Use a per-thread tick so we only poll the global GC flags periodically, while still
    // guaranteeing eventual stop-the-world progress.
    st->safepoint_tick++;
    uint64_t tick = st->safepoint_tick;
    if ((tick & 255u) != 0u) {
        if (!OREN_ATOMIC_LOAD_INT(&g_gc_requested) &&
            !OREN_ATOMIC_LOAD_INT(&g_gc_auto_pending)) {
            return;
        }
    }

    // Auto-GC initiation:
    // - request is set by allocation counting
    // - collected only at this safepoint call boundary (keeps stack/register state safe)
    // - safe under multi-threading via the stop-the-world protocol in `oren_gc_collect`
    int do_auto = 0;
    lock_collections();
    if (OREN_ATOMIC_LOAD_INT(&g_gc_auto_pending) &&
        !OREN_ATOMIC_LOAD_INT(&g_gc_in_progress)) {
        OREN_ATOMIC_STORE_INT(&g_gc_auto_pending, 0);
        do_auto = 1;
    }
    unlock_collections();
    if (do_auto) {
        if (gc_jmpbuf_scan_enabled_cached()) {
            // Spill registers to a stable memory image so the collector can conservatively
            // find live pointers even under -O2 (locals often live only in registers).
            oren_capture_gp_regs_words(st->gc_regs, sizeof(st->gc_regs) / sizeof(st->gc_regs[0]));
            st->has_gc_regs = 1;
            (void)setjmp(st->gc_buf);
            st->has_gc_buf = 1;
        }
        oren_gc_collect();
        return;
    }

    // If a collection is requested, snapshot registers so the collector can conservatively
    // find live pointers even when locals are optimized into registers.
    int req = OREN_ATOMIC_LOAD_INT(&g_gc_requested);
    if (req && gc_jmpbuf_scan_enabled_cached()) {
        oren_capture_gp_regs_words(st->gc_regs, sizeof(st->gc_regs) / sizeof(st->gc_regs[0]));
        st->has_gc_regs = 1;
        (void)setjmp(st->gc_buf);
        st->has_gc_buf = 1;
    }

    lock_collections();
    if (!OREN_ATOMIC_LOAD_INT(&g_gc_requested)) {
        unlock_collections();
        return;
    }
    if (!st->at_safepoint) {
        st->at_safepoint = 1;
        g_threads_waiting++;
        pthread_cond_broadcast(&g_collection_cv);
    }
    while (OREN_ATOMIC_LOAD_INT(&g_gc_requested)) {
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
