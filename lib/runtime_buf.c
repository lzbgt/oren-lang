#include "runtime.h"

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

OrenValue oren_i32_buf_new(OrenValue len) { return buf_new(4u, len, OREN_TYPE_I32_BUF); }
OrenValue oren_i64_buf_new(OrenValue len) { return buf_new(8u, len, OREN_TYPE_I64_BUF); }
OrenValue oren_f32_buf_new(OrenValue len) { return buf_new(4u, len, OREN_TYPE_F32_BUF); }
OrenValue oren_f64_buf_new(OrenValue len) { return buf_new(8u, len, OREN_TYPE_F64_BUF); }
OrenValue oren_u8_buf_new(OrenValue len) { return buf_new(1u, len, OREN_TYPE_U8_BUF); }

OrenValue oren_buf_len(OrenValue buf) {
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        return buf_err("buf_len expects (buf)");
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) return buf_err("buf_len: invalid buffer");
    return oren_int((long long)b->len);
}

OrenValue oren_buf_data_mod(OrenValue buf, OrenValue modv) {
    if (modv.type != OREN_TYPE_INT) return buf_err("buf_data_mod expects (buf, int)");
    long long m = modv.as.int_val;
    if (m <= 0) return buf_err("buf_data_mod: mod must be > 0");
    if ((uint64_t)m > 4096u) return buf_err("buf_data_mod: mod too large");
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        return buf_err("buf_data_mod expects (buf, int)");
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) return buf_err("buf_data_mod: invalid buffer");
    if (b->len == 0) return oren_int(0);
    if (!b->data) return buf_err("buf_data_mod: payload is nil");
    uintptr_t u = (uintptr_t)b->data;
    return oren_int((long long)(u % (uintptr_t)m));
}

static int buf_check_idx(OrenBuf* b, long long idx) {
    if (!b) return 0;
    if (idx < 0) return 0;
    if ((uint64_t)idx >= (uint64_t)b->len) return 0;
    if (!b->data && b->len != 0) return 0;
    return 1;
}

static uint32_t load_u32_le(uint8_t* p) {
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

static void store_u32_le(uint8_t* p, uint32_t u) {
    p[0] = (uint8_t)(u & 0xFFu);
    p[1] = (uint8_t)((u >> 8) & 0xFFu);
    p[2] = (uint8_t)((u >> 16) & 0xFFu);
    p[3] = (uint8_t)((u >> 24) & 0xFFu);
}

static uint64_t load_u64_le(uint8_t* p) {
    uint64_t u = 0;
    for (int i = 0; i < 8; i++) {
        u |= ((uint64_t)p[i] << (uint64_t)(i * 8));
    }
    return u;
}

static void store_u64_le(uint8_t* p, uint64_t u) {
    for (int i = 0; i < 8; i++) {
        p[i] = (uint8_t)((u >> (uint64_t)(i * 8)) & 0xFFu);
    }
}

OrenValue oren_buf_load_u8(OrenValue buf, OrenValue idxv) {
    if (!buf_is_u8(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_u8 expects (u8_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_u8: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx;
    return oren_int((long long)(*p));
}

OrenValue oren_buf_store_u8(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_u8(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_u8 expects (u8_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_u8: index out of bounds");
    long long v = vv.as.int_val;
    if (v < 0 || v > 255) return buf_err("buf_store_u8: byte out of range");
    uint8_t* p = buf_data(b) + (uint32_t)idx;
    *p = (uint8_t)v;
    return buf;
}

OrenValue oren_buf_load_i32(OrenValue buf, OrenValue idxv) {
    if (!buf_is_i32(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_i32 expects (i32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_i32: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    uint32_t u = load_u32_le(p);
    int32_t v = (int32_t)u;
    return oren_int((long long)v);
}

OrenValue oren_buf_store_i32(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_i32(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_i32 expects (i32_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_i32: index out of bounds");
    int32_t v = (int32_t)vv.as.int_val; // wrap
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    store_u32_le(p, (uint32_t)v);
    return buf;
}

OrenValue oren_buf_load_i64(OrenValue buf, OrenValue idxv) {
    if (!buf_is_i64(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_i64 expects (i64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_i64: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    uint64_t u = load_u64_le(p);
    int64_t v = 0;
    memcpy(&v, &u, sizeof(v));
    return oren_int((long long)v);
}

OrenValue oren_buf_store_i64(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_i64(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_i64 expects (i64_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_i64: index out of bounds");
    int64_t v = (int64_t)vv.as.int_val;
    uint64_t u = 0;
    memcpy(&u, &v, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    store_u64_le(p, u);
    return buf;
}

OrenValue oren_buf_load_f64(OrenValue buf, OrenValue idxv) {
    if (!buf_is_f64(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_f64 expects (f64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_f64: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    uint64_t u = load_u64_le(p);
    double d = 0.0;
    memcpy(&d, &u, sizeof(d));
    return oren_float(d);
}

OrenValue oren_buf_store_f64(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_f64(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_store_f64 expects (f64_buf, int, float)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_f64: index out of bounds");
    double d = vv.as.float_val;
    uint64_t u = 0;
    memcpy(&u, &d, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    store_u64_le(p, u);
    return buf;
}

OrenValue oren_buf_load_f32(OrenValue buf, OrenValue idxv) {
    if (!buf_is_f32(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_f32 expects (f32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_f32: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    uint32_t u = load_u32_le(p);
    float f = 0.0f;
    memcpy(&f, &u, sizeof(f));
    return oren_float((double)f);
}

OrenValue oren_buf_store_f32(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_f32(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_store_f32 expects (f32_buf, int, float)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_f32: index out of bounds");
    float f = (float)vv.as.float_val; // deterministic float32 boundary
    uint32_t u = 0;
    memcpy(&u, &f, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    store_u32_le(p, u);
    return buf;
}

OrenValue oren_buf_fill_u8(OrenValue buf, OrenValue vv) {
    if (!buf_is_u8(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_u8 expects (u8_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    long long v = vv.as.int_val;
    if (v < 0 || v > 255) return buf_err("buf_fill_u8: byte out of range");
    uint8_t u = (uint8_t)v;
    for (uint32_t i = 0; i < n; i++) {
        buf_data(b)[i] = u;
    }
    return buf;
}

OrenValue oren_buf_fill_i32(OrenValue buf, OrenValue vv) {
    if (!buf_is_i32(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_i32 expects (i32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    int32_t v = (int32_t)vv.as.int_val;
    uint32_t u = (uint32_t)v;
    for (uint32_t i = 0; i < n; i++) {
        store_u32_le(buf_data(b) + i * 4u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_i64(OrenValue buf, OrenValue vv) {
    if (!buf_is_i64(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_i64 expects (i64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    int64_t v = (int64_t)vv.as.int_val;
    uint64_t u = 0;
    memcpy(&u, &v, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u64_le(buf_data(b) + i * 8u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_f64(OrenValue buf, OrenValue vv) {
    if (!buf_is_f64(buf) || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_fill_f64 expects (f64_buf, float)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    double d = vv.as.float_val;
    uint64_t u = 0;
    memcpy(&u, &d, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u64_le(buf_data(b) + i * 8u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_f32(OrenValue buf, OrenValue vv) {
    if (!buf_is_f32(buf) || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_fill_f32 expects (f32_buf, float)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    float f = (float)vv.as.float_val;
    uint32_t u = 0;
    memcpy(&u, &f, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u32_le(buf_data(b) + i * 4u, u);
    }
    return buf;
}

static OrenValue buf_new_like(OrenValue a) {
    if (buf_is_i32(a)) return oren_i32_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_i64(a)) return oren_i64_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_f32(a)) return oren_f32_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_f64(a)) return oren_f64_buf_new(oren_int((long long)a.as.buf_val->len));
    return buf_err("buf_new_like: invalid buffer");
}

OrenValue oren_buf_add_i32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i32(dst) || !buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_add_i32_into expects (i32_buf, i32_buf, i32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_add_i32_into: length mismatch");
    for (uint32_t i = 0; i < od->len; i++) {
        uint32_t ua = load_u32_le(buf_data(ba) + i * 4u);
        uint32_t ub = load_u32_le(buf_data(bb) + i * 4u);
        uint32_t us = ua + ub; // wrap
        store_u32_le(buf_data(od) + i * 4u, us);
    }
    return dst;
}

OrenValue oren_buf_add_i32(OrenValue a, OrenValue b) {
    if (!buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_add_i32 expects (i32_buf, i32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_add_i32: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_add_i32_into(out, a, b);
}

OrenValue oren_buf_add_f32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_f32(dst) || !buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_add_f32_into expects (f32_buf, f32_buf, f32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_add_f32_into: length mismatch");
    for (uint32_t i = 0; i < od->len; i++) {
        uint32_t ua = load_u32_le(buf_data(ba) + i * 4u);
        uint32_t ub = load_u32_le(buf_data(bb) + i * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        float fs = fa + fb;
        uint32_t us = 0;
        memcpy(&us, &fs, sizeof(us));
        store_u32_le(buf_data(od) + i * 4u, us);
    }
    return dst;
}

OrenValue oren_buf_add_f32(OrenValue a, OrenValue b) {
    if (!buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_add_f32 expects (f32_buf, f32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_add_f32: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_add_f32_into(out, a, b);
}

OrenValue oren_buf_mul_i32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i32(dst) || !buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_mul_i32_into expects (i32_buf, i32_buf, i32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_mul_i32_into: length mismatch");
    for (uint32_t i = 0; i < od->len; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(ba) + i * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(bb) + i * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        int32_t vp = (int32_t)prod; // wrap
        store_u32_le(buf_data(od) + i * 4u, (uint32_t)vp);
    }
    return dst;
}

OrenValue oren_buf_mul_i32(OrenValue a, OrenValue b) {
    if (!buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_mul_i32 expects (i32_buf, i32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_mul_i32: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_mul_i32_into(out, a, b);
}

OrenValue oren_buf_mul_f32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_f32(dst) || !buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_mul_f32_into expects (f32_buf, f32_buf, f32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_mul_f32_into: length mismatch");
    for (uint32_t i = 0; i < od->len; i++) {
        uint32_t ua = load_u32_le(buf_data(ba) + i * 4u);
        uint32_t ub = load_u32_le(buf_data(bb) + i * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        float fp = fa * fb;
        uint32_t up = 0;
        memcpy(&up, &fp, sizeof(up));
        store_u32_le(buf_data(od) + i * 4u, up);
    }
    return dst;
}

OrenValue oren_buf_mul_f32(OrenValue a, OrenValue b) {
    if (!buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_mul_f32 expects (f32_buf, f32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_mul_f32: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_mul_f32_into(out, a, b);
}

OrenValue oren_buf_scale_f32(OrenValue buf, OrenValue scalar) {
    if (!buf_is_f32(buf) || scalar.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_scale_f32 expects (f32_buf, float)");
    OrenBuf* b = buf.as.buf_val;
    float s = (float)scalar.as.float_val;
    for (uint32_t i = 0; i < b->len; i++) {
        uint32_t u = load_u32_le(buf_data(b) + i * 4u);
        float f = 0.0f;
        memcpy(&f, &u, sizeof(f));
        float outv = f * s;
        uint32_t outu = 0;
        memcpy(&outu, &outv, sizeof(outu));
        store_u32_le(buf_data(b) + i * 4u, outu);
    }
    return buf;
}

OrenValue oren_buf_scale_f32_into(OrenValue dst, OrenValue a, OrenValue scalar) {
    if (!buf_is_f32(dst) || !buf_is_f32(a) || scalar.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_scale_f32_into expects (f32_buf, f32_buf, float)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    if (od->len != ba->len) return buf_err("buf_scale_f32_into: length mismatch");
    float s = (float)scalar.as.float_val;
    for (uint32_t i = 0; i < od->len; i++) {
        uint32_t u = load_u32_le(buf_data(ba) + i * 4u);
        float f = 0.0f;
        memcpy(&f, &u, sizeof(f));
        float outv = f * s;
        uint32_t outu = 0;
        memcpy(&outu, &outv, sizeof(outu));
        store_u32_le(buf_data(od) + i * 4u, outu);
    }
    return dst;
}

OrenValue oren_buf_scale_i32_into(OrenValue dst, OrenValue a, OrenValue scalar) {
    if (!buf_is_i32(dst) || !buf_is_i32(a) || scalar.type != OREN_TYPE_INT) return buf_err("oren_buf_scale_i32_into expects (i32_buf, i32_buf, int)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    if (od->len != ba->len) return buf_err("buf_scale_i32_into: length mismatch");
    long long sv = scalar.as.int_val;
    if (sv < (long long)INT32_MIN || sv > (long long)INT32_MAX) return buf_err("buf_scale_i32_into: scalar out of range");
    int32_t s = (int32_t)sv;
    for (uint32_t i = 0; i < od->len; i++) {
        int32_t v = (int32_t)load_u32_le(buf_data(ba) + i * 4u);
        int64_t prod = (int64_t)v * (int64_t)s;
        int32_t vp = (int32_t)prod;
        store_u32_le(buf_data(od) + i * 4u, (uint32_t)vp);
    }
    return dst;
}

OrenValue oren_buf_dot_i32(OrenValue a, OrenValue b) {
    if (!buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_dot_i32 expects (i32_buf, i32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_i32: length mismatch");
    uint32_t n = a.as.buf_val->len;

    // Wrap semantics: sum is modulo 2^64 then reinterpreted as signed i64.
    // This avoids UB on signed overflow and matches the project's wrap-int philosophy.
    uint64_t acc = 0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached()) {
        const int32_t* pa = (const int32_t*)(const void*)buf_data(a.as.buf_val);
        const int32_t* pb = (const int32_t*)(const void*)buf_data(b.as.buf_val);
        uint32_t i = 0;
        uint64x2_t vacc = vdupq_n_u64(0);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vb = vld1q_s32(pb + i);
            int64x2_t prod_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb));
            int64x2_t prod_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_lo));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_hi));
        }
        uint64_t tmp[2];
        vst1q_u64(tmp, vacc);
        acc = tmp[0] + tmp[1];
        for (; i < n; i++) {
            int64_t prod = (int64_t)pa[i] * (int64_t)pb[i];
            acc += u64_from_i64(prod);
        }
    } else {
        for (uint32_t i = 0; i < n; i++) {
            int32_t va = (int32_t)load_u32_le(buf_data(a.as.buf_val) + i * 4u);
            int32_t vb = (int32_t)load_u32_le(buf_data(b.as.buf_val) + i * 4u);
            int64_t prod = (int64_t)va * (int64_t)vb;
            acc += u64_from_i64(prod);
        }
    }
#else
    for (uint32_t i = 0; i < n; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(b.as.buf_val) + i * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        acc += u64_from_i64(prod);
    }
#endif

    return oren_int((long long)i64_from_u64(acc));
}

OrenValue oren_buf_dot_i32_slice(OrenValue a, OrenValue a_offv, OrenValue b, OrenValue b_offv, OrenValue nv) {
    if (!buf_is_i32(a) || !buf_is_i32(b) || a_offv.type != OREN_TYPE_INT || b_offv.type != OREN_TYPE_INT || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_i32_slice expects (i32_buf, int, i32_buf, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long n_ll = nv.as.int_val;
    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_i32_slice: negative arg");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_i32_slice: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_slice: b_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_i32_slice: a range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b_off_ll) return buf_err("buf_dot_i32_slice: b range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;

    uint64_t acc = 0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const int32_t* pb = (const int32_t*)(const void*)(buf_data(bb) + b_off * 4u);
        uint32_t i = 0;
        uint64x2_t vacc = vdupq_n_u64(0);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vb = vld1q_s32(pb + i);
            int64x2_t prod_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb));
            int64x2_t prod_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_lo));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_hi));
        }
        uint64_t tmp[2];
        vst1q_u64(tmp, vacc);
        acc = tmp[0] + tmp[1];
        for (; i < n; i++) {
            int64_t prod = (int64_t)pa[i] * (int64_t)pb[i];
            acc += u64_from_i64(prod);
        }
    } else {
        for (uint32_t i = 0; i < n; i++) {
            int32_t va = (int32_t)load_u32_le(buf_data(ba) + (a_off + i) * 4u);
            int32_t vb = (int32_t)load_u32_le(buf_data(bb) + (b_off + i) * 4u);
            int64_t prod = (int64_t)va * (int64_t)vb;
            acc += u64_from_i64(prod);
        }
    }
#else
    for (uint32_t i = 0; i < n; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(ba) + (a_off + i) * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(bb) + (b_off + i) * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        acc += u64_from_i64(prod);
    }
#endif

    return oren_int((long long)i64_from_u64(acc));
}

OrenValue oren_buf_dot_f32(OrenValue a, OrenValue b) {
    if (!buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_dot_f32 expects (f32_buf, f32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_f32: length mismatch");
    double acc = 0.0;
    uint32_t n = a.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ua = load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        uint32_t ub = load_u32_le(buf_data(b.as.buf_val) + i * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        acc += (double)fa * (double)fb;
    }
    return oren_float(acc);
}

OrenValue oren_buf_dot_f32_slice(OrenValue a, OrenValue a_offv, OrenValue b, OrenValue b_offv, OrenValue nv) {
    if (!buf_is_f32(a) || !buf_is_f32(b) || a_offv.type != OREN_TYPE_INT || b_offv.type != OREN_TYPE_INT || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f32_slice expects (f32_buf, int, f32_buf, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long n_ll = nv.as.int_val;
    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_f32_slice: negative arg");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f32_slice: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_slice: b_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_f32_slice: a range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b_off_ll) return buf_err("buf_dot_f32_slice: b range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;

    double acc = 0.0;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ua = load_u32_le(buf_data(ba) + (a_off + i) * 4u);
        uint32_t ub = load_u32_le(buf_data(bb) + (b_off + i) * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        acc += (double)fa * (double)fb;
    }
    return oren_float(acc);
}

OrenValue oren_buf_dot_i32_strided(OrenValue a, OrenValue a_offv, OrenValue a_stridev, OrenValue b, OrenValue b_offv, OrenValue b_stridev, OrenValue nv) {
    if (!buf_is_i32(a) || !buf_is_i32(b)
        || a_offv.type != OREN_TYPE_INT || a_stridev.type != OREN_TYPE_INT
        || b_offv.type != OREN_TYPE_INT || b_stridev.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_i32_strided expects (i32_buf, int, int, i32_buf, int, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long a_stride_ll = a_stridev.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long b_stride_ll = b_stridev.as.int_val;
    long long n_ll = nv.as.int_val;

    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_i32_strided: negative arg");
    if (a_stride_ll <= 0 || b_stride_ll <= 0) return buf_err("buf_dot_i32_strided: stride must be > 0");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_i32_strided: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_strided: b_off out of bounds");

    // Bounds check last index: off + (n-1)*stride
    if (n_ll > 0) {
        uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
        uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
        if (alast >= (uint64_t)ba->len) return buf_err("buf_dot_i32_strided: a range out of bounds");
        if (blast >= (uint64_t)bb->len) return buf_err("buf_dot_i32_strided: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;
    uint32_t a_stride = (uint32_t)a_stride_ll;
    uint32_t b_stride = (uint32_t)b_stride_ll;

    uint64_t acc = 0;
    for (uint32_t i = 0; i < n; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(ba) + (a_off + i * a_stride) * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(bb) + (b_off + i * b_stride) * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        acc += u64_from_i64(prod);
    }
    return oren_int((long long)i64_from_u64(acc));
}

OrenValue oren_buf_dot_f32_strided(OrenValue a, OrenValue a_offv, OrenValue a_stridev, OrenValue b, OrenValue b_offv, OrenValue b_stridev, OrenValue nv) {
    if (!buf_is_f32(a) || !buf_is_f32(b)
        || a_offv.type != OREN_TYPE_INT || a_stridev.type != OREN_TYPE_INT
        || b_offv.type != OREN_TYPE_INT || b_stridev.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f32_strided expects (f32_buf, int, int, f32_buf, int, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long a_stride_ll = a_stridev.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long b_stride_ll = b_stridev.as.int_val;
    long long n_ll = nv.as.int_val;

    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_f32_strided: negative arg");
    if (a_stride_ll <= 0 || b_stride_ll <= 0) return buf_err("buf_dot_f32_strided: stride must be > 0");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f32_strided: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_strided: b_off out of bounds");

    if (n_ll > 0) {
        uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
        uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
        if (alast >= (uint64_t)ba->len) return buf_err("buf_dot_f32_strided: a range out of bounds");
        if (blast >= (uint64_t)bb->len) return buf_err("buf_dot_f32_strided: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;
    uint32_t a_stride = (uint32_t)a_stride_ll;
    uint32_t b_stride = (uint32_t)b_stride_ll;

    double acc = 0.0;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ua = load_u32_le(buf_data(ba) + (a_off + i * a_stride) * 4u);
        uint32_t ub = load_u32_le(buf_data(bb) + (b_off + i * b_stride) * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        acc += (double)fa * (double)fb;
    }
    return oren_float(acc);
}

OrenValue oren_buf_reduce_sum_i32(OrenValue buf) {
    if (!buf_is_i32(buf)) return buf_err("oren_buf_reduce_sum_i32 expects (i32_buf)");
    uint32_t n = buf.as.buf_val->len;
    uint64_t acc = 0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached()) {
        const int32_t* p = (const int32_t*)(const void*)buf_data(buf.as.buf_val);
        uint32_t i = 0;
        uint64x2_t vacc = vdupq_n_u64(0);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t v = vld1q_s32(p + i);
            int64x2_t lo = vmovl_s32(vget_low_s32(v));
            int64x2_t hi = vmovl_s32(vget_high_s32(v));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(lo));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(hi));
        }
        uint64_t tmp[2];
        vst1q_u64(tmp, vacc);
        acc = tmp[0] + tmp[1];
        for (; i < n; i++) {
            acc += u64_from_i64((int64_t)p[i]);
        }
    } else {
        for (uint32_t i = 0; i < n; i++) {
            int32_t v = (int32_t)load_u32_le(buf_data(buf.as.buf_val) + i * 4u);
            acc += u64_from_i64((int64_t)v);
        }
    }
#else
    for (uint32_t i = 0; i < n; i++) {
        int32_t v = (int32_t)load_u32_le(buf_data(buf.as.buf_val) + i * 4u);
        acc += u64_from_i64((int64_t)v);
    }
#endif

    return oren_int((long long)i64_from_u64(acc));
}

OrenValue oren_buf_reduce_sum_f32(OrenValue buf) {
    if (!buf_is_f32(buf)) return buf_err("oren_buf_reduce_sum_f32 expects (f32_buf)");
    double acc = 0.0;
    uint32_t n = buf.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t u = load_u32_le(buf_data(buf.as.buf_val) + i * 4u);
        float f = 0.0f;
        memcpy(&f, &u, sizeof(f));
        acc += (double)f;
    }
    return oren_float(acc);
}

static OrenValue buf_store_f64_at0(OrenValue out, double d, const char* expects) {
    if (!buf_is_f64(out)) return buf_err(expects);
    OrenBuf* b = out.as.buf_val;
    if (!b || b->len < 1u || !b->data) return buf_err("buf_store_f64_at0: out must have len>=1");
    uint64_t u = 0;
    memcpy(&u, &d, sizeof(u));
    store_u64_le(buf_data(b), u);
    return out;
}

static OrenValue buf_store_i64_at0(OrenValue out, int64_t v, const char* expects) {
    if (!buf_is_i64(out)) return buf_err(expects);
    OrenBuf* b = out.as.buf_val;
    if (!b || b->len < 1u || !b->data) return buf_err("buf_store_i64_at0: out must have len>=1");
    uint64_t u = 0;
    memcpy(&u, &v, sizeof(u));
    store_u64_le(buf_data(b), u);
    return out;
}

static OrenValue buf_store_u64_at0(OrenValue out, uint64_t u, const char* expects) {
    if (!buf_is_i64(out)) return buf_err(expects);
    OrenBuf* b = out.as.buf_val;
    if (!b || b->len < 1u || !b->data) return buf_err("buf_store_u64_at0: out must have len>=1");
    store_u64_le(buf_data(b), u);
    return out;
}

OrenValue oren_buf_dot_f32_into(OrenValue out, OrenValue a, OrenValue b) {
    if (!buf_is_f64(out) || !buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_f32_into: length mismatch");
    double acc = 0.0;
    uint32_t n = a.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ua = load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        uint32_t ub = load_u32_le(buf_data(b.as.buf_val) + i * 4u);
        float fa = 0.0f, fb = 0.0f;
        memcpy(&fa, &ua, sizeof(fa));
        memcpy(&fb, &ub, sizeof(fb));
        acc += (double)fa * (double)fb;
    }
    return buf_store_f64_at0(out, acc, "oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
}

OrenValue oren_buf_reduce_sum_f32_into(OrenValue out, OrenValue a) {
    if (!buf_is_f64(out) || !buf_is_f32(a)) return buf_err("oren_buf_reduce_sum_f32_into expects (f64_buf, f32_buf)");
    double acc = 0.0;
    uint32_t n = a.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t u = load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        float f = 0.0f;
        memcpy(&f, &u, sizeof(f));
        acc += (double)f;
    }
    return buf_store_f64_at0(out, acc, "oren_buf_reduce_sum_f32_into expects (f64_buf, f32_buf)");
}

OrenValue oren_buf_dot_i32_into(OrenValue out, OrenValue a, OrenValue b) {
    if (!buf_is_i64(out) || !buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_dot_i32_into expects (i64_buf, i32_buf, i32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_i32_into: length mismatch");
    uint64_t acc = 0;
    uint32_t n = a.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(b.as.buf_val) + i * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        acc += u64_from_i64(prod);
    }
    return buf_store_u64_at0(out, acc, "oren_buf_dot_i32_into expects (i64_buf, i32_buf, i32_buf)");
}

OrenValue oren_buf_reduce_sum_i32_into(OrenValue out, OrenValue a) {
    if (!buf_is_i64(out) || !buf_is_i32(a)) return buf_err("oren_buf_reduce_sum_i32_into expects (i64_buf, i32_buf)");
    uint64_t acc = 0;
    uint32_t n = a.as.buf_val->len;
    for (uint32_t i = 0; i < n; i++) {
        int32_t v = (int32_t)load_u32_le(buf_data(a.as.buf_val) + i * 4u);
        acc += u64_from_i64((int64_t)v);
    }
    return buf_store_u64_at0(out, acc, "oren_buf_reduce_sum_i32_into expects (i64_buf, i32_buf)");
}

OrenValue oren_buf_axpy_f32_into(OrenValue dst, OrenValue alpha, OrenValue x, OrenValue y) {
    if (!buf_is_f32(dst) || !buf_is_f32(x) || !buf_is_f32(y) || alpha.type != OREN_TYPE_FLOAT) {
        return buf_err("oren_buf_axpy_f32_into expects (f32_buf, float, f32_buf, f32_buf)");
    }
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* bx = x.as.buf_val;
    OrenBuf* by = y.as.buf_val;
    if (od->len != bx->len || od->len != by->len) return buf_err("buf_axpy_f32_into: length mismatch");

    float a = (float)alpha.as.float_val; // float32 boundary
#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached()) {
        const float* px = (const float*)(const void*)buf_data(bx);
        const float* py = (const float*)(const void*)buf_data(by);
        float* pd = (float*)(void*)buf_data(od);
        uint32_t n = od->len;
        uint32_t i = 0;
        float32x4_t va = vdupq_n_f32(a);
        for (; i + 4u <= n; i += 4u) {
            float32x4_t vx = vld1q_f32(px + i);
            float32x4_t vy = vld1q_f32(py + i);
            float32x4_t vm = vmulq_f32(va, vx);
            float32x4_t vo = vaddq_f32(vm, vy);
            vst1q_f32(pd + i, vo);
        }
        // Tail uses endian-safe scalar path.
        for (; i < n; i++) {
            uint32_t ux = load_u32_le(buf_data(bx) + i * 4u);
            uint32_t uy = load_u32_le(buf_data(by) + i * 4u);
            float fx = 0.0f, fy = 0.0f;
            memcpy(&fx, &ux, sizeof(fx));
            memcpy(&fy, &uy, sizeof(fy));
            float outv = a * fx + fy;
            uint32_t uo = 0;
            memcpy(&uo, &outv, sizeof(uo));
            store_u32_le(buf_data(od) + i * 4u, uo);
        }
        return dst;
    } else {
        uint32_t n = od->len;
        for (uint32_t i = 0; i < n; i++) {
            uint32_t ux = load_u32_le(buf_data(bx) + i * 4u);
            uint32_t uy = load_u32_le(buf_data(by) + i * 4u);
            float fx = 0.0f, fy = 0.0f;
            memcpy(&fx, &ux, sizeof(fx));
            memcpy(&fy, &uy, sizeof(fy));
            float outv = a * fx + fy;
            uint32_t uo = 0;
            memcpy(&uo, &outv, sizeof(uo));
            store_u32_le(buf_data(od) + i * 4u, uo);
        }
        return dst;
    }
#else
    uint32_t n = od->len;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ux = load_u32_le(buf_data(bx) + i * 4u);
        uint32_t uy = load_u32_le(buf_data(by) + i * 4u);
        float fx = 0.0f, fy = 0.0f;
        memcpy(&fx, &ux, sizeof(fx));
        memcpy(&fy, &uy, sizeof(fy));
        float outv = a * fx + fy;
        uint32_t uo = 0;
        memcpy(&uo, &outv, sizeof(uo));
        store_u32_le(buf_data(od) + i * 4u, uo);
    }
    return dst;
#endif
}

OrenValue oren_buf_axpy_f32_in_place(OrenValue alpha, OrenValue x, OrenValue y) {
    return oren_buf_axpy_f32_into(y, alpha, x, y);
}

OrenValue oren_buf_axpy_i32_into(OrenValue dst, OrenValue alpha, OrenValue x, OrenValue y) {
    if (!buf_is_i32(dst) || !buf_is_i32(x) || !buf_is_i32(y) || alpha.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_axpy_i32_into expects (i32_buf, int, i32_buf, i32_buf)");
    }
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* bx = x.as.buf_val;
    OrenBuf* by = y.as.buf_val;
    if (od->len != bx->len || od->len != by->len) return buf_err("buf_axpy_i32_into: length mismatch");

    int32_t a = (int32_t)alpha.as.int_val;
    uint32_t n = od->len;
    for (uint32_t i = 0; i < n; i++) {
        int32_t xi = (int32_t)load_u32_le(buf_data(bx) + i * 4u);
        int32_t yi = (int32_t)load_u32_le(buf_data(by) + i * 4u);
        int32_t outv = (int32_t)((int64_t)a * (int64_t)xi + (int64_t)yi);
        store_u32_le(buf_data(od) + i * 4u, (uint32_t)outv);
    }
    return dst;
}

OrenValue oren_buf_axpy_i32_in_place(OrenValue alpha, OrenValue x, OrenValue y) {
    return oren_buf_axpy_i32_into(y, alpha, x, y);
}
