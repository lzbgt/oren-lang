// Unsafe pointer primitives (tooling/internal).
//
// These are used by the self-hosted compiler and native runtime support code to do
// high-performance byte operations without going through list/buffer APIs.
//
// Contract:
// - Pointers are passed as OREN_TYPE_INT containing a (uintptr_t) address.
// - These are intentionally unsafe: they may crash if handed invalid pointers.
// - We keep a small guard against obvious non-pointer values (< 4096) to reduce footguns.

static inline uintptr_t oren_ptr_unsafe_addr(OrenValue ptr, const char* who) {
    if (ptr.type != OREN_TYPE_INT) {
        oren_panic(who);
        return (uintptr_t)0;
    }
    uintptr_t addr = (uintptr_t)ptr.as.int_val;
    if (addr < (uintptr_t)4096u) {
        oren_panic(who);
        return (uintptr_t)0;
    }
    return addr;
}

static OrenValue oren_ptr_get_raw(OrenValue ptr) {
    uintptr_t addr = oren_ptr_unsafe_addr(ptr, "ptr_get expects int pointer");
    // Use memcpy to avoid undefined behavior on unaligned loads.
    // (Stage1 runs on arm64 macOS where unaligned 64-bit accesses via uint64_t*
    //  are not guaranteed safe under C aliasing/alignment rules.)
    uint64_t v = 0;
    memcpy(&v, (const void*)addr, sizeof(v));
    return oren_int((long long)v);
}

static OrenValue oren_ptr_set_raw(OrenValue ptr, OrenValue val) {
    uintptr_t addr = oren_ptr_unsafe_addr(ptr, "ptr_set expects int pointer");
    if (val.type != OREN_TYPE_INT) {
        oren_panic("ptr_set expects int value");
        return OREN_NIL;
    }
    // Use memcpy to avoid undefined behavior on unaligned stores.
    uint64_t v = (uint64_t)val.as.int_val;
    memcpy((void*)addr, &v, sizeof(v));
    return val;
}

static OrenValue oren_ptr_get_byte_raw(OrenValue ptr) {
    uintptr_t addr = oren_ptr_unsafe_addr(ptr, "ptr_get_byte expects int pointer");
    uint8_t v = *(const uint8_t*)addr;
    return oren_int((long long)v);
}

static OrenValue oren_ptr_set_byte_raw(OrenValue ptr, OrenValue val) {
    uintptr_t addr = oren_ptr_unsafe_addr(ptr, "ptr_set_byte expects int pointer");
    if (val.type != OREN_TYPE_INT) {
        oren_panic("ptr_set_byte expects int value");
        return OREN_NIL;
    }
    uint8_t v = (uint8_t)(val.as.int_val & 255ll);
    *(uint8_t*)addr = v;
    return oren_int((long long)v);
}

OrenValue oren_memcpy(OrenValue dst, OrenValue src, OrenValue len) {
    if (len.type != OREN_TYPE_INT) {
        oren_panic("oren_memcpy expects int len");
        return OREN_NIL;
    }
    if (len.as.int_val < 0) {
        oren_panic("oren_memcpy: negative len");
        return OREN_NIL;
    }
    if (len.as.int_val == 0) return oren_int(0);
    uintptr_t dst_addr = oren_ptr_unsafe_addr(dst, "oren_memcpy expects int destination pointer");
    uintptr_t src_addr = oren_ptr_unsafe_addr(src, "oren_memcpy expects int source pointer");
    memcpy((void*)dst_addr, (const void*)src_addr, (size_t)len.as.int_val);
    return oren_int(0);
}

// Expose as function values so generated C code can call them via `oren_call_obj_*`.
// (Stage0 C transpiler does not special-case these to direct calls.)
OrenValue ptr_get;
OrenValue ptr_set;
OrenValue ptr_get_byte;
OrenValue ptr_set_byte;

static OrenValue ptr_get__oren_fnwrap(void* env, int argc, OrenValue* argv) {
    (void)env;
    if (argc != 1) { oren_panic("arity mismatch"); }
    return oren_ptr_get_raw(argv[0]);
}

static OrenValue ptr_set__oren_fnwrap(void* env, int argc, OrenValue* argv) {
    (void)env;
    if (argc != 2) { oren_panic("arity mismatch"); }
    return oren_ptr_set_raw(argv[0], argv[1]);
}

static OrenValue ptr_get_byte__oren_fnwrap(void* env, int argc, OrenValue* argv) {
    (void)env;
    if (argc != 1) { oren_panic("arity mismatch"); }
    return oren_ptr_get_byte_raw(argv[0]);
}

static OrenValue ptr_set_byte__oren_fnwrap(void* env, int argc, OrenValue* argv) {
    (void)env;
    if (argc != 2) { oren_panic("arity mismatch"); }
    return oren_ptr_set_byte_raw(argv[0], argv[1]);
}
