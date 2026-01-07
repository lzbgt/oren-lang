OrenValue oren_buf_add_i32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i32(dst) || !buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_add_i32_into expects (i32_buf, i32_buf, i32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_add_i32_into: length mismatch");

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)buf_data(ba);
        const int32_t* pb = (const int32_t*)(const void*)buf_data(bb);
        int32_t* pd = (int32_t*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 4u <= od->len; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vb = vld1q_s32(pb + i);
            int32x4_t vs = vaddq_s32(va, vb); // wrap
            vst1q_s32(pd + i, vs);
        }
        // Tail uses endian-safe scalar path.
        for (; i < od->len; i++) {
            uint32_t ua = load_u32_le(buf_data(ba) + i * 4u);
            uint32_t ub = load_u32_le(buf_data(bb) + i * 4u);
            uint32_t us = ua + ub; // wrap
            store_u32_le(buf_data(od) + i * 4u, us);
        }
        return dst;
    }
#endif

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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const float* pa = (const float*)(const void*)buf_data(ba);
        const float* pb = (const float*)(const void*)buf_data(bb);
        float* pd = (float*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 4u <= od->len; i += 4u) {
            float32x4_t va = vld1q_f32(pa + i);
            float32x4_t vb = vld1q_f32(pb + i);
            float32x4_t vs = vaddq_f32(va, vb);
            vst1q_f32(pd + i, vs);
        }
        // Tail uses endian-safe scalar path.
        for (; i < od->len; i++) {
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
#endif

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

OrenValue oren_buf_add_i64_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i64(dst) || !buf_is_i64(a) || !buf_is_i64(b)) return buf_err("oren_buf_add_i64_into expects (i64_buf, i64_buf, i64_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_add_i64_into: length mismatch");

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 2u) {
        const uint64_t* pa = (const uint64_t*)(const void*)buf_data(ba);
        const uint64_t* pb = (const uint64_t*)(const void*)buf_data(bb);
        uint64_t* pd = (uint64_t*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 2u <= od->len; i += 2u) {
            uint64x2_t va = vld1q_u64(pa + i);
            uint64x2_t vb = vld1q_u64(pb + i);
            uint64x2_t vs = vaddq_u64(va, vb); // wrap
            vst1q_u64(pd + i, vs);
        }
        for (; i < od->len; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
            uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
            store_u64_le(buf_data(od) + i * 8u, ua + ub);
        }
        return dst;
    }
#endif

    for (uint32_t i = 0; i < od->len; i++) {
        uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
        store_u64_le(buf_data(od) + i * 8u, ua + ub);
    }
    return dst;
}

OrenValue oren_buf_add_i64(OrenValue a, OrenValue b) {
    if (!buf_is_i64(a) || !buf_is_i64(b)) return buf_err("oren_buf_add_i64 expects (i64_buf, i64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_add_i64: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_add_i64_into(out, a, b);
}

OrenValue oren_buf_add_f64_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_f64(dst) || !buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_add_f64_into expects (f64_buf, f64_buf, f64_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_add_f64_into: length mismatch");

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 2u) {
        const double* pa = (const double*)(const void*)buf_data(ba);
        const double* pb = (const double*)(const void*)buf_data(bb);
        double* pd = (double*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 2u <= od->len; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb = vld1q_f64(pb + i);
            float64x2_t vs = vaddq_f64(va, vb);
            vst1q_f64(pd + i, vs);
        }
        for (; i < od->len; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
            uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
            double da = 0.0, dbv = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&dbv, &ub, sizeof(dbv));
            double ds = da + dbv;
            uint64_t us = 0;
            memcpy(&us, &ds, sizeof(us));
            store_u64_le(buf_data(od) + i * 8u, us);
        }
        return dst;
    }
#endif

    for (uint32_t i = 0; i < od->len; i++) {
        uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
        double da = 0.0, dbv = 0.0;
        memcpy(&da, &ua, sizeof(da));
        memcpy(&dbv, &ub, sizeof(dbv));
        double ds = da + dbv;
        uint64_t us = 0;
        memcpy(&us, &ds, sizeof(us));
        store_u64_le(buf_data(od) + i * 8u, us);
    }
    return dst;
}

OrenValue oren_buf_add_f64(OrenValue a, OrenValue b) {
    if (!buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_add_f64 expects (f64_buf, f64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_add_f64: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_add_f64_into(out, a, b);
}

OrenValue oren_buf_mul_i32_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i32(dst) || !buf_is_i32(a) || !buf_is_i32(b)) return buf_err("oren_buf_mul_i32_into expects (i32_buf, i32_buf, i32_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_mul_i32_into: length mismatch");

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)buf_data(ba);
        const int32_t* pb = (const int32_t*)(const void*)buf_data(bb);
        int32_t* pd = (int32_t*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 4u <= od->len; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vb = vld1q_s32(pb + i);
            int32x4_t vp = vmulq_s32(va, vb); // wrap (low 32 bits)
            vst1q_s32(pd + i, vp);
        }
        for (; i < od->len; i++) {
            int32_t va = (int32_t)load_u32_le(buf_data(ba) + i * 4u);
            int32_t vb = (int32_t)load_u32_le(buf_data(bb) + i * 4u);
            int64_t prod = (int64_t)va * (int64_t)vb;
            int32_t vp = (int32_t)prod; // wrap
            store_u32_le(buf_data(od) + i * 4u, (uint32_t)vp);
        }
        return dst;
    }
#endif

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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const float* pa = (const float*)(const void*)buf_data(ba);
        const float* pb = (const float*)(const void*)buf_data(bb);
        float* pd = (float*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 4u <= od->len; i += 4u) {
            float32x4_t va = vld1q_f32(pa + i);
            float32x4_t vb = vld1q_f32(pb + i);
            float32x4_t vp = vmulq_f32(va, vb);
            vst1q_f32(pd + i, vp);
        }
        // Tail uses endian-safe scalar path.
        for (; i < od->len; i++) {
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
#endif

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

OrenValue oren_buf_mul_i64_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_i64(dst) || !buf_is_i64(a) || !buf_is_i64(b)) return buf_err("oren_buf_mul_i64_into expects (i64_buf, i64_buf, i64_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_mul_i64_into: length mismatch");

    // NEON does not have a 2x i64 lane multiply in AArch64 NEON, so this is scalar.
    for (uint32_t i = 0; i < od->len; i++) {
        uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
        // Unsigned overflow is well-defined in C: multiplication wraps mod 2^64.
        uint64_t up = ua * ub;
        store_u64_le(buf_data(od) + i * 8u, up);
    }
    return dst;
}

OrenValue oren_buf_mul_i64(OrenValue a, OrenValue b) {
    if (!buf_is_i64(a) || !buf_is_i64(b)) return buf_err("oren_buf_mul_i64 expects (i64_buf, i64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_mul_i64: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_mul_i64_into(out, a, b);
}

OrenValue oren_buf_mul_f64_into(OrenValue dst, OrenValue a, OrenValue b) {
    if (!buf_is_f64(dst) || !buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_mul_f64_into expects (f64_buf, f64_buf, f64_buf)");
    OrenBuf* od = dst.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    if (od->len != ba->len || od->len != bb->len) return buf_err("buf_mul_f64_into: length mismatch");

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 2u) {
        const double* pa = (const double*)(const void*)buf_data(ba);
        const double* pb = (const double*)(const void*)buf_data(bb);
        double* pd = (double*)(void*)buf_data(od);
        uint32_t i = 0;
        for (; i + 2u <= od->len; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb = vld1q_f64(pb + i);
            float64x2_t vp = vmulq_f64(va, vb);
            vst1q_f64(pd + i, vp);
        }
        for (; i < od->len; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
            uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
            double da = 0.0, dbv = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&dbv, &ub, sizeof(dbv));
            double dp = da * dbv;
            uint64_t up = 0;
            memcpy(&up, &dp, sizeof(up));
            store_u64_le(buf_data(od) + i * 8u, up);
        }
        return dst;
    }
#endif

    for (uint32_t i = 0; i < od->len; i++) {
        uint64_t ua = load_u64_le(buf_data(ba) + i * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + i * 8u);
        double da = 0.0, dbv = 0.0;
        memcpy(&da, &ua, sizeof(da));
        memcpy(&dbv, &ub, sizeof(dbv));
        double dp = da * dbv;
        uint64_t up = 0;
        memcpy(&up, &dp, sizeof(up));
        store_u64_le(buf_data(od) + i * 8u, up);
    }
    return dst;
}

OrenValue oren_buf_mul_f64(OrenValue a, OrenValue b) {
    if (!buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_mul_f64 expects (f64_buf, f64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_mul_f64: length mismatch");
    OrenValue out = buf_new_like(a);
    if (oren_is_err(out).as.bool_val) return out;
    return oren_buf_mul_f64_into(out, a, b);
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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const float* pa = (const float*)(const void*)buf_data(ba);
        float* pd = (float*)(void*)buf_data(od);
        uint32_t i = 0;
        float32x4_t vs = vdupq_n_f32(s);
        for (; i + 4u <= od->len; i += 4u) {
            float32x4_t va = vld1q_f32(pa + i);
            float32x4_t vo = vmulq_f32(va, vs);
            vst1q_f32(pd + i, vo);
        }
        for (; i < od->len; i++) {
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
#endif

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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && od->len >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)buf_data(ba);
        int32_t* pd = (int32_t*)(void*)buf_data(od);
        uint32_t i = 0;
        int32x4_t vs = vdupq_n_s32(s);
        for (; i + 4u <= od->len; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vp = vmulq_s32(va, vs); // wrap (low 32 bits)
            vst1q_s32(pd + i, vp);
        }
        for (; i < od->len; i++) {
            int32_t v = (int32_t)load_u32_le(buf_data(ba) + i * 4u);
            int64_t prod = (int64_t)v * (int64_t)s;
            int32_t vp = (int32_t)prod;
            store_u32_le(buf_data(od) + i * 4u, (uint32_t)vp);
        }
        return dst;
    }
#endif

    for (uint32_t i = 0; i < od->len; i++) {
        int32_t v = (int32_t)load_u32_le(buf_data(ba) + i * 4u);
        int64_t prod = (int64_t)v * (int64_t)s;
        int32_t vp = (int32_t)prod;
        store_u32_le(buf_data(od) + i * 4u, (uint32_t)vp);
    }
    return dst;
}
