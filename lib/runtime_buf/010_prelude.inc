#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static size_t parse_env_size_local(const char* s, size_t def) {
    if (!s || !s[0]) return def;
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

static size_t buf_align_cached(void) {
    static size_t cached = 0;
    if (cached) return cached;
    size_t a = parse_env_size_local(getenv("OREN_BUF_ALIGN"), 64u);
    // For now, keep alignment <= 64 because the RAW header size is fixed at 64 bytes
    // and the allocator contract assumes the payload pointer is header+64.
    // NEON/cache-line friendliness is satisfied by 64.
    if (a != 8u && a != 16u && a != 32u && a != 64u) a = 64u;
    cached = a;
    return cached;
}

static size_t buf_payload_limit_cached(void) {
    // Deterministic, testable safety knob:
    // - 0 means "unlimited" (default)
    // - otherwise caps typed-buffer payload bytes (not counting header)
    //
    // This enables a deterministic "OOM-like" test without relying on host memory
    // pressure or platform-specific mmap behavior.
    static size_t cached = (size_t)-1;
    if (cached != (size_t)-1) return cached;
    cached = parse_env_size_local(getenv("OREN_BUF_PAYLOAD_LIMIT_BYTES"), 0u);
    return cached;
}

#if defined(__aarch64__) && defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#include <arm_neon.h>
#define OREN_BUF_HAVE_NEON 1
#else
#define OREN_BUF_HAVE_NEON 0
#endif

// SIMD runtime opt-in (rolling):
//
// - SIMD must never change semantics. Scalar behavior is authoritative.
// - Off-by-default so determinism validation remains explicit.
//
// Env:
// - OREN_ENABLE_SIMD=1 enables SIMD fast paths (when compiled in).
// - OREN_NO_SIMD=1 disables SIMD fast paths (wins over OREN_ENABLE_SIMD).
static int oren_simd_enabled_cached(void) {
    static int cached = -1;
    if (cached != -1) return cached;
    cached = 0;
    const char* v_no = getenv("OREN_NO_SIMD");
    if (v_no && v_no[0] && v_no[0] != '0') { cached = 0; return cached; }
    const char* v = getenv("OREN_ENABLE_SIMD");
    if (v && v[0] && v[0] != '0') cached = 1;
    return cached;
}

static OrenValue buf_err(const char* msg) {
    return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(msg));
}

static int buf_is_u8(OrenValue v) { return v.type == OREN_TYPE_U8_BUF && v.as.buf_val != NULL; }
static int buf_is_i32(OrenValue v) { return v.type == OREN_TYPE_I32_BUF && v.as.buf_val != NULL; }
static int buf_is_i64(OrenValue v) { return v.type == OREN_TYPE_I64_BUF && v.as.buf_val != NULL; }
static int buf_is_f32(OrenValue v) { return v.type == OREN_TYPE_F32_BUF && v.as.buf_val != NULL; }
static int buf_is_f64(OrenValue v) { return v.type == OREN_TYPE_F64_BUF && v.as.buf_val != NULL; }

static uint32_t buf_len_u32(OrenBuf* b) { return b ? b->len : 0u; }

static uint8_t* buf_data(OrenBuf* b) { return b ? b->data : NULL; }

static int64_t i64_from_u64(uint64_t u) {
    int64_t out = 0;
    memcpy(&out, &u, sizeof(out));
    return out;
}

static uint64_t u64_from_i64(int64_t v) {
    uint64_t out = 0;
    memcpy(&out, &v, sizeof(out));
    return out;
}

static float f32_from_u32_bits(uint32_t u) {
    float out = 0.0f;
    memcpy(&out, &u, sizeof(out));
    return out;
}

static uint64_t f64_to_u64_bits(double v) {
    uint64_t out = 0;
    memcpy(&out, &v, sizeof(out));
    return out;
}

static OrenValue buf_new(uint32_t elem_size, OrenValue lenv, OrenType ty) {
    if (lenv.type != OREN_TYPE_INT) {
        return buf_err("buf_new expects (int)");
    }
    long long ln = lenv.as.int_val;
    if (ln < 0) {
        return buf_err("buf_new: negative length");
    }
    if (ln > (long long)UINT32_MAX) {
        return buf_err("buf_new: length too large");
    }
    uint32_t len = (uint32_t)ln;

    uint64_t bytes_len = (uint64_t)len * (uint64_t)elem_size;
    if (bytes_len > (uint64_t)SIZE_MAX) {
        return buf_err("buf_new: size overflow");
    }
    size_t lim = buf_payload_limit_cached();
    if (lim != 0u && bytes_len > (uint64_t)lim) {
        return oren_err(oren_int(OREN_ERR_BUDGET), oren_string("buf_new: payload limit exceeded"));
    }

    // Allocate:
    // - header as a GC-tracked struct
    // - payload as a separate RAW (opaque, unscanned) aligned block
    //
    // Rationale:
    // - typed buffer payload bytes contain no OrenValue pointers
    // - separating the payload makes the "raw/unscanned" guarantee explicit in the GC registry
    // - aligned payload enables SIMD-friendly kernels (arm64 NEON)
    uint64_t p = oren_alloc_struct(sizeof(OrenBuf));
    if (p == 0) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("buf_new: header alloc failed"));
    }
    OrenBuf* hdr = (OrenBuf*)(uintptr_t)p;
    hdr->len = len;
    hdr->elem_size = elem_size;
    hdr->data = NULL;
    if (bytes_len > 0) {
        uint64_t dp = oren_alloc_raw_aligned((size_t)bytes_len, (size_t)buf_align_cached());
        if (dp == 0) {
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("buf_new: payload alloc failed"));
        }
        hdr->data = (uint8_t*)(uintptr_t)dp;
        memset(hdr->data, 0, (size_t)bytes_len);
    }

    OrenValue out;
    out.type = ty;
    out.as.buf_val = hdr;
    return out;
}

