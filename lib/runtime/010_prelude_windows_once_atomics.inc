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
