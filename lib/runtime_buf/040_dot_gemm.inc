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
    uint32_t n = a.as.buf_val->len;

    // Determinism hardening:
    // - Accumulate in double in a fixed element order.
    // - Avoid FMA drift in SIMD paths by using explicit f64 ops (no contraction).
    double acc = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const uint32_t* pa = (const uint32_t*)(const void*)buf_data(a.as.buf_val);
        const uint32_t* pb = (const uint32_t*)(const void*)buf_data(b.as.buf_val);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t va_u = vld1q_u32(pa + i);
            uint32x4_t vb_u = vld1q_u32(pb + i);
            float32x4_t va_f = vreinterpretq_f32_u32(va_u);
            float32x4_t vb_f = vreinterpretq_f32_u32(vb_u);

            float32x2_t va_lo = vget_low_f32(va_f);
            float32x2_t va_hi = vget_high_f32(va_f);
            float32x2_t vb_lo = vget_low_f32(vb_f);
            float32x2_t vb_hi = vget_high_f32(vb_f);

            float64x2_t da0 = vcvt_f64_f32(va_lo);
            float64x2_t da1 = vcvt_f64_f32(va_hi);
            float64x2_t db0 = vcvt_f64_f32(vb_lo);
            float64x2_t db1 = vcvt_f64_f32(vb_hi);

            float64x2_t p0 = vmulq_f64(da0, db0);
            float64x2_t p1 = vmulq_f64(da1, db1);

            // Fixed order: i,i+1,i+2,i+3 (matches scalar loop).
            acc = acc + vgetq_lane_f64(p0, 0);
            acc = acc + vgetq_lane_f64(p0, 1);
            acc = acc + vgetq_lane_f64(p1, 0);
            acc = acc + vgetq_lane_f64(p1, 1);
        }
        for (; i < n; i++) {
            uint32_t ua = load_u32_le(buf_data(a.as.buf_val) + i * 4u);
            uint32_t ub = load_u32_le(buf_data(b.as.buf_val) + i * 4u);
            float fa = 0.0f, fb = 0.0f;
            memcpy(&fa, &ua, sizeof(fa));
            memcpy(&fb, &ub, sizeof(fb));
            acc += (double)fa * (double)fb;
        }
        return oren_float(acc);
    }
#endif

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

OrenValue oren_buf_dot_f64(OrenValue a, OrenValue b) {
    if (!buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_dot_f64 expects (f64_buf, f64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_f64: length mismatch");
    uint32_t n = a.as.buf_val->len;

    // Determinism hardening:
    // - Accumulate in double in fixed element order.
    // - SIMD path uses lane extraction in the same order (i,i+1,...).
    double acc = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const double* pa = (const double*)(const void*)buf_data(a.as.buf_val);
        const double* pb = (const double*)(const void*)buf_data(b.as.buf_val);
        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb = vld1q_f64(pb + i);
            float64x2_t p = vmulq_f64(va, vb);
            acc = acc + vgetq_lane_f64(p, 0);
            acc = acc + vgetq_lane_f64(p, 1);
        }
        for (; i < n; i++) {
            uint64_t ua = load_u64_le(buf_data(a.as.buf_val) + i * 8u);
            uint64_t ub = load_u64_le(buf_data(b.as.buf_val) + i * 8u);
            double da = 0.0, dbv = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&dbv, &ub, sizeof(dbv));
            acc += da * dbv;
        }
        return oren_float(acc);
    }
#endif

    for (uint32_t i = 0; i < n; i++) {
        uint64_t ua = load_u64_le(buf_data(a.as.buf_val) + i * 8u);
        uint64_t ub = load_u64_le(buf_data(b.as.buf_val) + i * 8u);
        double da = 0.0, dbv = 0.0;
        memcpy(&da, &ua, sizeof(da));
        memcpy(&dbv, &ub, sizeof(dbv));
        acc += da * dbv;
    }
    return oren_float(acc);
}

OrenValue oren_buf_dot_f64_slice(OrenValue a, OrenValue a_offv, OrenValue b, OrenValue b_offv, OrenValue nv) {
    if (!buf_is_f64(a) || !buf_is_f64(b) || a_offv.type != OREN_TYPE_INT || b_offv.type != OREN_TYPE_INT || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f64_slice expects (f64_buf, int, f64_buf, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long n_ll = nv.as.int_val;
    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_f64_slice: negative arg");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f64_slice: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_slice: b_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_f64_slice: a range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b_off_ll) return buf_err("buf_dot_f64_slice: b range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;

    double acc = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const double* pa = (const double*)(const void*)(buf_data(ba) + a_off * 8u);
        const double* pb = (const double*)(const void*)(buf_data(bb) + b_off * 8u);
        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb = vld1q_f64(pb + i);
            float64x2_t p = vmulq_f64(va, vb);
            acc = acc + vgetq_lane_f64(p, 0);
            acc = acc + vgetq_lane_f64(p, 1);
        }
        for (; i < n; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + (a_off + i) * 8u);
            uint64_t ub = load_u64_le(buf_data(bb) + (b_off + i) * 8u);
            double da = 0.0, dbv = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&dbv, &ub, sizeof(dbv));
            acc += da * dbv;
        }
        return oren_float(acc);
    }
#endif

    for (uint32_t i = 0; i < n; i++) {
        uint64_t ua = load_u64_le(buf_data(ba) + (a_off + i) * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + (b_off + i) * 8u);
        double da = 0.0, dbv = 0.0;
        memcpy(&da, &ua, sizeof(da));
        memcpy(&dbv, &ub, sizeof(dbv));
        acc += da * dbv;
    }
    return oren_float(acc);
}

OrenValue oren_buf_dot_f64_strided(OrenValue a, OrenValue a_offv, OrenValue a_stridev, OrenValue b, OrenValue b_offv, OrenValue b_stridev, OrenValue nv) {
    if (!buf_is_f64(a) || !buf_is_f64(b)
        || a_offv.type != OREN_TYPE_INT || a_stridev.type != OREN_TYPE_INT
        || b_offv.type != OREN_TYPE_INT || b_stridev.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f64_strided expects (f64_buf, int, int, f64_buf, int, int, int)");
    }
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long a_off_ll = a_offv.as.int_val;
    long long a_stride_ll = a_stridev.as.int_val;
    long long b_off_ll = b_offv.as.int_val;
    long long b_stride_ll = b_stridev.as.int_val;
    long long n_ll = nv.as.int_val;

    if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) return buf_err("buf_dot_f64_strided: negative arg");
    if (a_stride_ll <= 0 || b_stride_ll <= 0) return buf_err("buf_dot_f64_strided: stride must be > 0");
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f64_strided: a_off out of bounds");
    if ((uint64_t)b_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_strided: b_off out of bounds");
    if (n_ll > 0) {
        uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
        uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
        if (alast >= (uint64_t)ba->len) return buf_err("buf_dot_f64_strided: a range out of bounds");
        if (blast >= (uint64_t)bb->len) return buf_err("buf_dot_f64_strided: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b_off = (uint32_t)b_off_ll;
    uint32_t a_stride = (uint32_t)a_stride_ll;
    uint32_t b_stride = (uint32_t)b_stride_ll;

    double acc = 0.0;
#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && a_stride == 1u && b_stride == 1u && n >= 2u) {
        const double* pa = (const double*)(const void*)(buf_data(ba) + a_off * 8u);
        const double* pb = (const double*)(const void*)(buf_data(bb) + b_off * 8u);
        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb = vld1q_f64(pb + i);
            float64x2_t p = vmulq_f64(va, vb);
            // lane-ordered accumulation matches scalar i,i+1 order
            acc = acc + vgetq_lane_f64(p, 0);
            acc = acc + vgetq_lane_f64(p, 1);
        }
        for (; i < n; i++) {
            uint32_t ai = a_off + i;
            uint32_t bi = b_off + i;
            uint64_t ua = load_u64_le(buf_data(ba) + ai * 8u);
            uint64_t ub = load_u64_le(buf_data(bb) + bi * 8u);
            double da = 0.0, dbv = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&dbv, &ub, sizeof(dbv));
            acc += da * dbv;
        }
        return oren_float(acc);
    }
#endif
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ai = a_off + i * a_stride;
        uint32_t bi = b_off + i * b_stride;
        uint64_t ua = load_u64_le(buf_data(ba) + ai * 8u);
        uint64_t ub = load_u64_le(buf_data(bb) + bi * 8u);
        double da = 0.0, dbv = 0.0;
        memcpy(&da, &ua, sizeof(da));
        memcpy(&dbv, &ub, sizeof(dbv));
        acc += da * dbv;
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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const uint32_t* pa = (const uint32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const uint32_t* pb = (const uint32_t*)(const void*)(buf_data(bb) + b_off * 4u);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t va_u = vld1q_u32(pa + i);
            uint32x4_t vb_u = vld1q_u32(pb + i);
            float32x4_t va_f = vreinterpretq_f32_u32(va_u);
            float32x4_t vb_f = vreinterpretq_f32_u32(vb_u);

            float32x2_t va_lo = vget_low_f32(va_f);
            float32x2_t va_hi = vget_high_f32(va_f);
            float32x2_t vb_lo = vget_low_f32(vb_f);
            float32x2_t vb_hi = vget_high_f32(vb_f);

            float64x2_t da0 = vcvt_f64_f32(va_lo);
            float64x2_t da1 = vcvt_f64_f32(va_hi);
            float64x2_t db0 = vcvt_f64_f32(vb_lo);
            float64x2_t db1 = vcvt_f64_f32(vb_hi);

            float64x2_t p0 = vmulq_f64(da0, db0);
            float64x2_t p1 = vmulq_f64(da1, db1);

            acc = acc + vgetq_lane_f64(p0, 0);
            acc = acc + vgetq_lane_f64(p0, 1);
            acc = acc + vgetq_lane_f64(p1, 0);
            acc = acc + vgetq_lane_f64(p1, 1);
        }
        for (; i < n; i++) {
            uint32_t ua = load_u32_le(buf_data(ba) + (a_off + i) * 4u);
            uint32_t ub = load_u32_le(buf_data(bb) + (b_off + i) * 4u);
            float fa = 0.0f, fb = 0.0f;
            memcpy(&fa, &ua, sizeof(fa));
            memcpy(&fb, &ub, sizeof(fb));
            acc += (double)fa * (double)fb;
        }
        return oren_float(acc);
    }
#endif

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
#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && a_stride == 1u && b_stride == 1u && n >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const int32_t* pb = (const int32_t*)(const void*)(buf_data(bb) + b_off * 4u);
        uint32_t i = 0;
        uint64x2_t vacc = vdupq_n_u64(0);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);
            int32x4_t vb = vld1q_s32(pb + i);
            int64x2_t p_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb));
            int64x2_t p_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(p_lo));
            vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(p_hi));
        }
        uint64_t tmp[2];
        vst1q_u64(tmp, vacc);
        acc = tmp[0] + tmp[1];
        for (; i < n; i++) {
            int64_t prod = (int64_t)pa[i] * (int64_t)pb[i];
            acc += u64_from_i64(prod);
        }
        return oren_int((long long)i64_from_u64(acc));
    }
#endif
    for (uint32_t i = 0; i < n; i++) {
        int32_t va = (int32_t)load_u32_le(buf_data(ba) + (a_off + i * a_stride) * 4u);
        int32_t vb = (int32_t)load_u32_le(buf_data(bb) + (b_off + i * b_stride) * 4u);
        int64_t prod = (int64_t)va * (int64_t)vb;
        acc += u64_from_i64(prod);
    }
    return oren_int((long long)i64_from_u64(acc));
}

OrenValue oren_buf_dot_i32_4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_i64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_i32(a) || a_offv.type != OREN_TYPE_INT
        || !buf_is_i32(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_i32_4_slice_into expects (i64_buf,int,i32_buf,int,i32_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_dot_i32_4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 4u) {
        return buf_err("buf_dot_i32_4_slice_into: out range out of bounds");
    }
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_i32_4_slice_into: a_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_i32_4_slice_into: a range out of bounds");

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_4_slice_into: b0_off out of bounds");
    if ((uint64_t)b1_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_4_slice_into: b1_off out of bounds");
    if ((uint64_t)b2_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_4_slice_into: b2_off out of bounds");
    if ((uint64_t)b3_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_i32_4_slice_into: b3_off out of bounds");

    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll) return buf_err("buf_dot_i32_4_slice_into: b0 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll) return buf_err("buf_dot_i32_4_slice_into: b1 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll) return buf_err("buf_dot_i32_4_slice_into: b2 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) return buf_err("buf_dot_i32_4_slice_into: b3 range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    uint64_t s0 = 0, s1 = 0, s2 = 0, s3 = 0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const int32_t* pa = (const int32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const int32_t* pb0 = (const int32_t*)(const void*)(buf_data(bb) + b0_off * 4u);
        const int32_t* pb1 = (const int32_t*)(const void*)(buf_data(bb) + b1_off * 4u);
        const int32_t* pb2 = (const int32_t*)(const void*)(buf_data(bb) + b2_off * 4u);
        const int32_t* pb3 = (const int32_t*)(const void*)(buf_data(bb) + b3_off * 4u);

        uint32_t i = 0;
        uint64x2_t vacc0 = vdupq_n_u64(0);
        uint64x2_t vacc1 = vdupq_n_u64(0);
        uint64x2_t vacc2 = vdupq_n_u64(0);
        uint64x2_t vacc3 = vdupq_n_u64(0);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t va = vld1q_s32(pa + i);

            int32x4_t vb0 = vld1q_s32(pb0 + i);
            int32x4_t vb1 = vld1q_s32(pb1 + i);
            int32x4_t vb2 = vld1q_s32(pb2 + i);
            int32x4_t vb3 = vld1q_s32(pb3 + i);

            int64x2_t p0_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb0));
            int64x2_t p0_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb0));
            vacc0 = vaddq_u64(vacc0, vreinterpretq_u64_s64(p0_lo));
            vacc0 = vaddq_u64(vacc0, vreinterpretq_u64_s64(p0_hi));

            int64x2_t p1_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb1));
            int64x2_t p1_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb1));
            vacc1 = vaddq_u64(vacc1, vreinterpretq_u64_s64(p1_lo));
            vacc1 = vaddq_u64(vacc1, vreinterpretq_u64_s64(p1_hi));

            int64x2_t p2_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb2));
            int64x2_t p2_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb2));
            vacc2 = vaddq_u64(vacc2, vreinterpretq_u64_s64(p2_lo));
            vacc2 = vaddq_u64(vacc2, vreinterpretq_u64_s64(p2_hi));

            int64x2_t p3_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb3));
            int64x2_t p3_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb3));
            vacc3 = vaddq_u64(vacc3, vreinterpretq_u64_s64(p3_lo));
            vacc3 = vaddq_u64(vacc3, vreinterpretq_u64_s64(p3_hi));
        }

        uint64_t t0[2], t1[2], t2[2], t3[2];
        vst1q_u64(t0, vacc0);
        vst1q_u64(t1, vacc1);
        vst1q_u64(t2, vacc2);
        vst1q_u64(t3, vacc3);
        s0 = t0[0] + t0[1];
        s1 = t1[0] + t1[1];
        s2 = t2[0] + t2[1];
        s3 = t3[0] + t3[1];

        for (; i < n; i++) {
            int64_t av = pa[i];
            s0 += u64_from_i64(av * (int64_t)pb0[i]);
            s1 += u64_from_i64(av * (int64_t)pb1[i]);
            s2 += u64_from_i64(av * (int64_t)pb2[i]);
            s3 += u64_from_i64(av * (int64_t)pb3[i]);
        }
    } else
#endif
    {
        for (uint32_t i = 0; i < n; i++) {
            int32_t av = (int32_t)load_u32_le(buf_data(ba) + (a_off + i) * 4u);
            int32_t b0v = (int32_t)load_u32_le(buf_data(bb) + (b0_off + i) * 4u);
            int32_t b1v = (int32_t)load_u32_le(buf_data(bb) + (b1_off + i) * 4u);
            int32_t b2v = (int32_t)load_u32_le(buf_data(bb) + (b2_off + i) * 4u);
            int32_t b3v = (int32_t)load_u32_le(buf_data(bb) + (b3_off + i) * 4u);
            int64_t av64 = (int64_t)av;
            s0 += u64_from_i64(av64 * (int64_t)b0v);
            s1 += u64_from_i64(av64 * (int64_t)b1v);
            s2 += u64_from_i64(av64 * (int64_t)b2v);
            s3 += u64_from_i64(av64 * (int64_t)b3v);
        }
    }

    // Store as i64 elements (little-endian).
    uint64_t u0 = s0, u1 = s1, u2 = s2, u3 = s3;
    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, u0);
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, u1);
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, u2);
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, u3);
    return out;
}

OrenValue oren_buf_dot_f32_4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_f64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_f32(a) || a_offv.type != OREN_TYPE_INT
        || !buf_is_f32(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f32_4_slice_into expects (f64_buf,int,f32_buf,int,f32_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_dot_f32_4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 4u) {
        return buf_err("buf_dot_f32_4_slice_into: out range out of bounds");
    }
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f32_4_slice_into: a_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_f32_4_slice_into: a range out of bounds");

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_4_slice_into: b0_off out of bounds");
    if ((uint64_t)b1_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_4_slice_into: b1_off out of bounds");
    if ((uint64_t)b2_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_4_slice_into: b2_off out of bounds");
    if ((uint64_t)b3_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f32_4_slice_into: b3_off out of bounds");

    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll) return buf_err("buf_dot_f32_4_slice_into: b0 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll) return buf_err("buf_dot_f32_4_slice_into: b1 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll) return buf_err("buf_dot_f32_4_slice_into: b2 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) return buf_err("buf_dot_f32_4_slice_into: b3 range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    double s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const uint32_t* pa = (const uint32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const uint32_t* pb0 = (const uint32_t*)(const void*)(buf_data(bb) + b0_off * 4u);
        const uint32_t* pb1 = (const uint32_t*)(const void*)(buf_data(bb) + b1_off * 4u);
        const uint32_t* pb2 = (const uint32_t*)(const void*)(buf_data(bb) + b2_off * 4u);
        const uint32_t* pb3 = (const uint32_t*)(const void*)(buf_data(bb) + b3_off * 4u);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t va_u = vld1q_u32(pa + i);
            float32x4_t va_f = vreinterpretq_f32_u32(va_u);
            float32x2_t va_lo = vget_low_f32(va_f);
            float32x2_t va_hi = vget_high_f32(va_f);
            float64x2_t da0 = vcvt_f64_f32(va_lo);
            float64x2_t da1 = vcvt_f64_f32(va_hi);

            uint32x4_t vb0_u = vld1q_u32(pb0 + i);
            uint32x4_t vb1_u = vld1q_u32(pb1 + i);
            uint32x4_t vb2_u = vld1q_u32(pb2 + i);
            uint32x4_t vb3_u = vld1q_u32(pb3 + i);

            float32x4_t vb0_f = vreinterpretq_f32_u32(vb0_u);
            float32x4_t vb1_f = vreinterpretq_f32_u32(vb1_u);
            float32x4_t vb2_f = vreinterpretq_f32_u32(vb2_u);
            float32x4_t vb3_f = vreinterpretq_f32_u32(vb3_u);

            // b0
            {
                float32x2_t vb_lo = vget_low_f32(vb0_f);
                float32x2_t vb_hi = vget_high_f32(vb0_f);
                float64x2_t db0 = vcvt_f64_f32(vb_lo);
                float64x2_t db1 = vcvt_f64_f32(vb_hi);
                float64x2_t p0 = vmulq_f64(da0, db0);
                float64x2_t p1 = vmulq_f64(da1, db1);
                s0 = s0 + vgetq_lane_f64(p0, 0);
                s0 = s0 + vgetq_lane_f64(p0, 1);
                s0 = s0 + vgetq_lane_f64(p1, 0);
                s0 = s0 + vgetq_lane_f64(p1, 1);
            }
            // b1
            {
                float32x2_t vb_lo = vget_low_f32(vb1_f);
                float32x2_t vb_hi = vget_high_f32(vb1_f);
                float64x2_t db0 = vcvt_f64_f32(vb_lo);
                float64x2_t db1 = vcvt_f64_f32(vb_hi);
                float64x2_t p0 = vmulq_f64(da0, db0);
                float64x2_t p1 = vmulq_f64(da1, db1);
                s1 = s1 + vgetq_lane_f64(p0, 0);
                s1 = s1 + vgetq_lane_f64(p0, 1);
                s1 = s1 + vgetq_lane_f64(p1, 0);
                s1 = s1 + vgetq_lane_f64(p1, 1);
            }
            // b2
            {
                float32x2_t vb_lo = vget_low_f32(vb2_f);
                float32x2_t vb_hi = vget_high_f32(vb2_f);
                float64x2_t db0 = vcvt_f64_f32(vb_lo);
                float64x2_t db1 = vcvt_f64_f32(vb_hi);
                float64x2_t p0 = vmulq_f64(da0, db0);
                float64x2_t p1 = vmulq_f64(da1, db1);
                s2 = s2 + vgetq_lane_f64(p0, 0);
                s2 = s2 + vgetq_lane_f64(p0, 1);
                s2 = s2 + vgetq_lane_f64(p1, 0);
                s2 = s2 + vgetq_lane_f64(p1, 1);
            }
            // b3
            {
                float32x2_t vb_lo = vget_low_f32(vb3_f);
                float32x2_t vb_hi = vget_high_f32(vb3_f);
                float64x2_t db0 = vcvt_f64_f32(vb_lo);
                float64x2_t db1 = vcvt_f64_f32(vb_hi);
                float64x2_t p0 = vmulq_f64(da0, db0);
                float64x2_t p1 = vmulq_f64(da1, db1);
                s3 = s3 + vgetq_lane_f64(p0, 0);
                s3 = s3 + vgetq_lane_f64(p0, 1);
                s3 = s3 + vgetq_lane_f64(p1, 0);
                s3 = s3 + vgetq_lane_f64(p1, 1);
            }
        }
        for (; i < n; i++) {
            uint32_t ua = load_u32_le(buf_data(ba) + (a_off + i) * 4u);
            uint32_t ub0 = load_u32_le(buf_data(bb) + (b0_off + i) * 4u);
            uint32_t ub1 = load_u32_le(buf_data(bb) + (b1_off + i) * 4u);
            uint32_t ub2 = load_u32_le(buf_data(bb) + (b2_off + i) * 4u);
            uint32_t ub3 = load_u32_le(buf_data(bb) + (b3_off + i) * 4u);
            float fa = 0.0f, fb0 = 0.0f, fb1 = 0.0f, fb2 = 0.0f, fb3 = 0.0f;
            memcpy(&fa, &ua, sizeof(fa));
            memcpy(&fb0, &ub0, sizeof(fb0));
            memcpy(&fb1, &ub1, sizeof(fb1));
            memcpy(&fb2, &ub2, sizeof(fb2));
            memcpy(&fb3, &ub3, sizeof(fb3));
            double da = (double)fa;
            s0 += da * (double)fb0;
            s1 += da * (double)fb1;
            s2 += da * (double)fb2;
            s3 += da * (double)fb3;
        }
    } else
#endif
    {
        for (uint32_t i = 0; i < n; i++) {
            uint32_t ua = load_u32_le(buf_data(ba) + (a_off + i) * 4u);
            uint32_t ub0 = load_u32_le(buf_data(bb) + (b0_off + i) * 4u);
            uint32_t ub1 = load_u32_le(buf_data(bb) + (b1_off + i) * 4u);
            uint32_t ub2 = load_u32_le(buf_data(bb) + (b2_off + i) * 4u);
            uint32_t ub3 = load_u32_le(buf_data(bb) + (b3_off + i) * 4u);
            float fa = 0.0f, fb0 = 0.0f, fb1 = 0.0f, fb2 = 0.0f, fb3 = 0.0f;
            memcpy(&fa, &ua, sizeof(fa));
            memcpy(&fb0, &ub0, sizeof(fb0));
            memcpy(&fb1, &ub1, sizeof(fb1));
            memcpy(&fb2, &ub2, sizeof(fb2));
            memcpy(&fb3, &ub3, sizeof(fb3));
            double da = (double)fa;
            s0 += da * (double)fb0;
            s1 += da * (double)fb1;
            s2 += da * (double)fb2;
            s3 += da * (double)fb3;
        }
    }

    uint64_t u0 = 0, u1 = 0, u2 = 0, u3 = 0;
    memcpy(&u0, &s0, sizeof(u0));
    memcpy(&u1, &s1, sizeof(u1));
    memcpy(&u2, &s2, sizeof(u2));
    memcpy(&u3, &s3, sizeof(u3));
    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, u0);
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, u1);
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, u2);
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, u3);
    return out;
}

OrenValue oren_buf_dot_f64_4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_f64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_f64(a) || a_offv.type != OREN_TYPE_INT
        || !buf_is_f64(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_dot_f64_4_slice_into expects (f64_buf,int,f64_buf,int,f64_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a_off_ll = a_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_dot_f64_4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 4u) {
        return buf_err("buf_dot_f64_4_slice_into: out range out of bounds");
    }
    if ((uint64_t)a_off_ll > (uint64_t)ba->len) return buf_err("buf_dot_f64_4_slice_into: a_off out of bounds");
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a_off_ll) return buf_err("buf_dot_f64_4_slice_into: a range out of bounds");

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_4_slice_into: b0_off out of bounds");
    if ((uint64_t)b1_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_4_slice_into: b1_off out of bounds");
    if ((uint64_t)b2_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_4_slice_into: b2_off out of bounds");
    if ((uint64_t)b3_off_ll > (uint64_t)bb->len) return buf_err("buf_dot_f64_4_slice_into: b3_off out of bounds");

    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll) return buf_err("buf_dot_f64_4_slice_into: b0 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll) return buf_err("buf_dot_f64_4_slice_into: b1 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll) return buf_err("buf_dot_f64_4_slice_into: b2 range out of bounds");
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) return buf_err("buf_dot_f64_4_slice_into: b3 range out of bounds");

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a_off = (uint32_t)a_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    double s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const double* pa = (const double*)(const void*)(buf_data(ba) + a_off * 8u);
        const double* pb0 = (const double*)(const void*)(buf_data(bb) + b0_off * 8u);
        const double* pb1 = (const double*)(const void*)(buf_data(bb) + b1_off * 8u);
        const double* pb2 = (const double*)(const void*)(buf_data(bb) + b2_off * 8u);
        const double* pb3 = (const double*)(const void*)(buf_data(bb) + b3_off * 8u);

        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t va = vld1q_f64(pa + i);
            float64x2_t vb0 = vld1q_f64(pb0 + i);
            float64x2_t vb1 = vld1q_f64(pb1 + i);
            float64x2_t vb2 = vld1q_f64(pb2 + i);
            float64x2_t vb3 = vld1q_f64(pb3 + i);

            float64x2_t p0 = vmulq_f64(va, vb0);
            float64x2_t p1 = vmulq_f64(va, vb1);
            float64x2_t p2 = vmulq_f64(va, vb2);
            float64x2_t p3 = vmulq_f64(va, vb3);

            // Preserve scalar accumulation order: element i then i+1.
            s0 += vgetq_lane_f64(p0, 0); s0 += vgetq_lane_f64(p0, 1);
            s1 += vgetq_lane_f64(p1, 0); s1 += vgetq_lane_f64(p1, 1);
            s2 += vgetq_lane_f64(p2, 0); s2 += vgetq_lane_f64(p2, 1);
            s3 += vgetq_lane_f64(p3, 0); s3 += vgetq_lane_f64(p3, 1);
        }
        for (; i < n; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + (a_off + i) * 8u);
            uint64_t ub0 = load_u64_le(buf_data(bb) + (b0_off + i) * 8u);
            uint64_t ub1 = load_u64_le(buf_data(bb) + (b1_off + i) * 8u);
            uint64_t ub2 = load_u64_le(buf_data(bb) + (b2_off + i) * 8u);
            uint64_t ub3 = load_u64_le(buf_data(bb) + (b3_off + i) * 8u);
            double da = 0.0, db0 = 0.0, db1 = 0.0, db2 = 0.0, db3 = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&db0, &ub0, sizeof(db0));
            memcpy(&db1, &ub1, sizeof(db1));
            memcpy(&db2, &ub2, sizeof(db2));
            memcpy(&db3, &ub3, sizeof(db3));
            s0 += da * db0;
            s1 += da * db1;
            s2 += da * db2;
            s3 += da * db3;
        }
    } else
#endif
    {
        for (uint32_t i = 0; i < n; i++) {
            uint64_t ua = load_u64_le(buf_data(ba) + (a_off + i) * 8u);
            uint64_t ub0 = load_u64_le(buf_data(bb) + (b0_off + i) * 8u);
            uint64_t ub1 = load_u64_le(buf_data(bb) + (b1_off + i) * 8u);
            uint64_t ub2 = load_u64_le(buf_data(bb) + (b2_off + i) * 8u);
            uint64_t ub3 = load_u64_le(buf_data(bb) + (b3_off + i) * 8u);
            double da = 0.0, db0 = 0.0, db1 = 0.0, db2 = 0.0, db3 = 0.0;
            memcpy(&da, &ua, sizeof(da));
            memcpy(&db0, &ub0, sizeof(db0));
            memcpy(&db1, &ub1, sizeof(db1));
            memcpy(&db2, &ub2, sizeof(db2));
            memcpy(&db3, &ub3, sizeof(db3));
            s0 += da * db0;
            s1 += da * db1;
            s2 += da * db2;
            s3 += da * db3;
        }
    }

    uint64_t u0 = 0, u1 = 0, u2 = 0, u3 = 0;
    memcpy(&u0, &s0, sizeof(u0));
    memcpy(&u1, &s1, sizeof(u1));
    memcpy(&u2, &s2, sizeof(u2));
    memcpy(&u3, &s3, sizeof(u3));
    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, u0);
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, u1);
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, u2);
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, u3);
    return out;
}

OrenValue oren_buf_gemm_f64_4x4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a0_offv, OrenValue a1_offv, OrenValue a2_offv, OrenValue a3_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_f64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_f64(a) || a0_offv.type != OREN_TYPE_INT || a1_offv.type != OREN_TYPE_INT || a2_offv.type != OREN_TYPE_INT || a3_offv.type != OREN_TYPE_INT
        || !buf_is_f64(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_gemm_f64_4x4_slice_into expects (f64_buf,int,f64_buf,int,int,int,int,f64_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a0_off_ll = a0_offv.as.int_val;
    long long a1_off_ll = a1_offv.as.int_val;
    long long a2_off_ll = a2_offv.as.int_val;
    long long a3_off_ll = a3_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0
        || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_gemm_f64_4x4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 16u) {
        return buf_err("buf_gemm_f64_4x4_slice_into: out range out of bounds");
    }

    if ((uint64_t)a0_off_ll > (uint64_t)ba->len || (uint64_t)a1_off_ll > (uint64_t)ba->len
        || (uint64_t)a2_off_ll > (uint64_t)ba->len || (uint64_t)a3_off_ll > (uint64_t)ba->len) {
        return buf_err("buf_gemm_f64_4x4_slice_into: a_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a0_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a1_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a2_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a3_off_ll) {
        return buf_err("buf_gemm_f64_4x4_slice_into: a range out of bounds");
    }

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len || (uint64_t)b1_off_ll > (uint64_t)bb->len
        || (uint64_t)b2_off_ll > (uint64_t)bb->len || (uint64_t)b3_off_ll > (uint64_t)bb->len) {
        return buf_err("buf_gemm_f64_4x4_slice_into: b_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) {
        return buf_err("buf_gemm_f64_4x4_slice_into: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a0_off = (uint32_t)a0_off_ll;
    uint32_t a1_off = (uint32_t)a1_off_ll;
    uint32_t a2_off = (uint32_t)a2_off_ll;
    uint32_t a3_off = (uint32_t)a3_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    // Accumulate in deterministic increasing-k order.
    double c00 = 0.0, c01 = 0.0, c02 = 0.0, c03 = 0.0;
    double c10 = 0.0, c11 = 0.0, c12 = 0.0, c13 = 0.0;
    double c20 = 0.0, c21 = 0.0, c22 = 0.0, c23 = 0.0;
    double c30 = 0.0, c31 = 0.0, c32 = 0.0, c33 = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const double* pa0 = (const double*)(const void*)(buf_data(ba) + a0_off * 8u);
        const double* pa1 = (const double*)(const void*)(buf_data(ba) + a1_off * 8u);
        const double* pa2 = (const double*)(const void*)(buf_data(ba) + a2_off * 8u);
        const double* pa3 = (const double*)(const void*)(buf_data(ba) + a3_off * 8u);
        const double* pb0 = (const double*)(const void*)(buf_data(bb) + b0_off * 8u);
        const double* pb1 = (const double*)(const void*)(buf_data(bb) + b1_off * 8u);
        const double* pb2 = (const double*)(const void*)(buf_data(bb) + b2_off * 8u);
        const double* pb3 = (const double*)(const void*)(buf_data(bb) + b3_off * 8u);

        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t va0 = vld1q_f64(pa0 + i);
            float64x2_t va1 = vld1q_f64(pa1 + i);
            float64x2_t va2 = vld1q_f64(pa2 + i);
            float64x2_t va3 = vld1q_f64(pa3 + i);

            float64x2_t vb0 = vld1q_f64(pb0 + i);
            float64x2_t vb1 = vld1q_f64(pb1 + i);
            float64x2_t vb2 = vld1q_f64(pb2 + i);
            float64x2_t vb3 = vld1q_f64(pb3 + i);

            // Preserve scalar accumulation order: element i then i+1 for every accumulator.
            // Row 0
            { float64x2_t p = vmulq_f64(va0, vb0); c00 += vgetq_lane_f64(p, 0); c00 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va0, vb1); c01 += vgetq_lane_f64(p, 0); c01 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va0, vb2); c02 += vgetq_lane_f64(p, 0); c02 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va0, vb3); c03 += vgetq_lane_f64(p, 0); c03 += vgetq_lane_f64(p, 1); }
            // Row 1
            { float64x2_t p = vmulq_f64(va1, vb0); c10 += vgetq_lane_f64(p, 0); c10 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va1, vb1); c11 += vgetq_lane_f64(p, 0); c11 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va1, vb2); c12 += vgetq_lane_f64(p, 0); c12 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va1, vb3); c13 += vgetq_lane_f64(p, 0); c13 += vgetq_lane_f64(p, 1); }
            // Row 2
            { float64x2_t p = vmulq_f64(va2, vb0); c20 += vgetq_lane_f64(p, 0); c20 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va2, vb1); c21 += vgetq_lane_f64(p, 0); c21 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va2, vb2); c22 += vgetq_lane_f64(p, 0); c22 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va2, vb3); c23 += vgetq_lane_f64(p, 0); c23 += vgetq_lane_f64(p, 1); }
            // Row 3
            { float64x2_t p = vmulq_f64(va3, vb0); c30 += vgetq_lane_f64(p, 0); c30 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va3, vb1); c31 += vgetq_lane_f64(p, 0); c31 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va3, vb2); c32 += vgetq_lane_f64(p, 0); c32 += vgetq_lane_f64(p, 1); }
            { float64x2_t p = vmulq_f64(va3, vb3); c33 += vgetq_lane_f64(p, 0); c33 += vgetq_lane_f64(p, 1); }
        }
        for (; i < n; i++) {
            uint64_t ua0 = load_u64_le(buf_data(ba) + (a0_off + i) * 8u);
            uint64_t ua1 = load_u64_le(buf_data(ba) + (a1_off + i) * 8u);
            uint64_t ua2 = load_u64_le(buf_data(ba) + (a2_off + i) * 8u);
            uint64_t ua3 = load_u64_le(buf_data(ba) + (a3_off + i) * 8u);
            uint64_t ub0 = load_u64_le(buf_data(bb) + (b0_off + i) * 8u);
            uint64_t ub1 = load_u64_le(buf_data(bb) + (b1_off + i) * 8u);
            uint64_t ub2 = load_u64_le(buf_data(bb) + (b2_off + i) * 8u);
            uint64_t ub3 = load_u64_le(buf_data(bb) + (b3_off + i) * 8u);
            double a0v = 0.0, a1v = 0.0, a2v = 0.0, a3v = 0.0;
            double b0v = 0.0, b1v = 0.0, b2v = 0.0, b3v = 0.0;
            memcpy(&a0v, &ua0, sizeof(a0v));
            memcpy(&a1v, &ua1, sizeof(a1v));
            memcpy(&a2v, &ua2, sizeof(a2v));
            memcpy(&a3v, &ua3, sizeof(a3v));
            memcpy(&b0v, &ub0, sizeof(b0v));
            memcpy(&b1v, &ub1, sizeof(b1v));
            memcpy(&b2v, &ub2, sizeof(b2v));
            memcpy(&b3v, &ub3, sizeof(b3v));

            c00 += a0v * b0v; c01 += a0v * b1v; c02 += a0v * b2v; c03 += a0v * b3v;
            c10 += a1v * b0v; c11 += a1v * b1v; c12 += a1v * b2v; c13 += a1v * b3v;
            c20 += a2v * b0v; c21 += a2v * b1v; c22 += a2v * b2v; c23 += a2v * b3v;
            c30 += a3v * b0v; c31 += a3v * b1v; c32 += a3v * b2v; c33 += a3v * b3v;
        }
    } else
#endif
    for (uint32_t i = 0; i < n; i++) {
        uint64_t ua0 = load_u64_le(buf_data(ba) + (a0_off + i) * 8u);
        uint64_t ua1 = load_u64_le(buf_data(ba) + (a1_off + i) * 8u);
        uint64_t ua2 = load_u64_le(buf_data(ba) + (a2_off + i) * 8u);
        uint64_t ua3 = load_u64_le(buf_data(ba) + (a3_off + i) * 8u);
        uint64_t ub0 = load_u64_le(buf_data(bb) + (b0_off + i) * 8u);
        uint64_t ub1 = load_u64_le(buf_data(bb) + (b1_off + i) * 8u);
        uint64_t ub2 = load_u64_le(buf_data(bb) + (b2_off + i) * 8u);
        uint64_t ub3 = load_u64_le(buf_data(bb) + (b3_off + i) * 8u);
        double a0v = 0.0, a1v = 0.0, a2v = 0.0, a3v = 0.0;
        double b0v = 0.0, b1v = 0.0, b2v = 0.0, b3v = 0.0;
        memcpy(&a0v, &ua0, sizeof(a0v));
        memcpy(&a1v, &ua1, sizeof(a1v));
        memcpy(&a2v, &ua2, sizeof(a2v));
        memcpy(&a3v, &ua3, sizeof(a3v));
        memcpy(&b0v, &ub0, sizeof(b0v));
        memcpy(&b1v, &ub1, sizeof(b1v));
        memcpy(&b2v, &ub2, sizeof(b2v));
        memcpy(&b3v, &ub3, sizeof(b3v));

        c00 += a0v * b0v; c01 += a0v * b1v; c02 += a0v * b2v; c03 += a0v * b3v;
        c10 += a1v * b0v; c11 += a1v * b1v; c12 += a1v * b2v; c13 += a1v * b3v;
        c20 += a2v * b0v; c21 += a2v * b1v; c22 += a2v * b2v; c23 += a2v * b3v;
        c30 += a3v * b0v; c31 += a3v * b1v; c32 += a3v * b2v; c33 += a3v * b3v;
    }

    uint64_t u00 = 0, u01 = 0, u02 = 0, u03 = 0;
    uint64_t u10 = 0, u11 = 0, u12 = 0, u13 = 0;
    uint64_t u20 = 0, u21 = 0, u22 = 0, u23 = 0;
    uint64_t u30 = 0, u31 = 0, u32 = 0, u33 = 0;
    memcpy(&u00, &c00, sizeof(u00)); memcpy(&u01, &c01, sizeof(u01)); memcpy(&u02, &c02, sizeof(u02)); memcpy(&u03, &c03, sizeof(u03));
    memcpy(&u10, &c10, sizeof(u10)); memcpy(&u11, &c11, sizeof(u11)); memcpy(&u12, &c12, sizeof(u12)); memcpy(&u13, &c13, sizeof(u13));
    memcpy(&u20, &c20, sizeof(u20)); memcpy(&u21, &c21, sizeof(u21)); memcpy(&u22, &c22, sizeof(u22)); memcpy(&u23, &c23, sizeof(u23));
    memcpy(&u30, &c30, sizeof(u30)); memcpy(&u31, &c31, sizeof(u31)); memcpy(&u32, &c32, sizeof(u32)); memcpy(&u33, &c33, sizeof(u33));

    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, u00);
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, u01);
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, u02);
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, u03);
    store_u64_le(buf_data(bout) + (out_off + 4u) * 8u, u10);
    store_u64_le(buf_data(bout) + (out_off + 5u) * 8u, u11);
    store_u64_le(buf_data(bout) + (out_off + 6u) * 8u, u12);
    store_u64_le(buf_data(bout) + (out_off + 7u) * 8u, u13);
    store_u64_le(buf_data(bout) + (out_off + 8u) * 8u, u20);
    store_u64_le(buf_data(bout) + (out_off + 9u) * 8u, u21);
    store_u64_le(buf_data(bout) + (out_off + 10u) * 8u, u22);
    store_u64_le(buf_data(bout) + (out_off + 11u) * 8u, u23);
    store_u64_le(buf_data(bout) + (out_off + 12u) * 8u, u30);
    store_u64_le(buf_data(bout) + (out_off + 13u) * 8u, u31);
    store_u64_le(buf_data(bout) + (out_off + 14u) * 8u, u32);
    store_u64_le(buf_data(bout) + (out_off + 15u) * 8u, u33);
    return out;
}

OrenValue oren_buf_gemm_i32_4x4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a0_offv, OrenValue a1_offv, OrenValue a2_offv, OrenValue a3_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_i64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_i32(a) || a0_offv.type != OREN_TYPE_INT || a1_offv.type != OREN_TYPE_INT || a2_offv.type != OREN_TYPE_INT || a3_offv.type != OREN_TYPE_INT
        || !buf_is_i32(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_gemm_i32_4x4_slice_into expects (i64_buf,int,i32_buf,int,int,int,int,i32_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a0_off_ll = a0_offv.as.int_val;
    long long a1_off_ll = a1_offv.as.int_val;
    long long a2_off_ll = a2_offv.as.int_val;
    long long a3_off_ll = a3_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0
        || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_gemm_i32_4x4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 16u) {
        return buf_err("buf_gemm_i32_4x4_slice_into: out range out of bounds");
    }

    if ((uint64_t)a0_off_ll > (uint64_t)ba->len || (uint64_t)a1_off_ll > (uint64_t)ba->len
        || (uint64_t)a2_off_ll > (uint64_t)ba->len || (uint64_t)a3_off_ll > (uint64_t)ba->len) {
        return buf_err("buf_gemm_i32_4x4_slice_into: a_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a0_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a1_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a2_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a3_off_ll) {
        return buf_err("buf_gemm_i32_4x4_slice_into: a range out of bounds");
    }

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len || (uint64_t)b1_off_ll > (uint64_t)bb->len
        || (uint64_t)b2_off_ll > (uint64_t)bb->len || (uint64_t)b3_off_ll > (uint64_t)bb->len) {
        return buf_err("buf_gemm_i32_4x4_slice_into: b_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) {
        return buf_err("buf_gemm_i32_4x4_slice_into: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a0_off = (uint32_t)a0_off_ll;
    uint32_t a1_off = (uint32_t)a1_off_ll;
    uint32_t a2_off = (uint32_t)a2_off_ll;
    uint32_t a3_off = (uint32_t)a3_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    // Accumulate in uint64_t to make wrap semantics explicit (avoid signed overflow UB).
    uint64_t c00 = 0, c01 = 0, c02 = 0, c03 = 0;
    uint64_t c10 = 0, c11 = 0, c12 = 0, c13 = 0;
    uint64_t c20 = 0, c21 = 0, c22 = 0, c23 = 0;
    uint64_t c30 = 0, c31 = 0, c32 = 0, c33 = 0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const int32_t* pa0 = (const int32_t*)(const void*)(buf_data(ba) + a0_off * 4u);
        const int32_t* pa1 = (const int32_t*)(const void*)(buf_data(ba) + a1_off * 4u);
        const int32_t* pa2 = (const int32_t*)(const void*)(buf_data(ba) + a2_off * 4u);
        const int32_t* pa3 = (const int32_t*)(const void*)(buf_data(ba) + a3_off * 4u);
        const int32_t* pb0 = (const int32_t*)(const void*)(buf_data(bb) + b0_off * 4u);
        const int32_t* pb1 = (const int32_t*)(const void*)(buf_data(bb) + b1_off * 4u);
        const int32_t* pb2 = (const int32_t*)(const void*)(buf_data(bb) + b2_off * 4u);
        const int32_t* pb3 = (const int32_t*)(const void*)(buf_data(bb) + b3_off * 4u);

        uint32_t i = 0;
        uint64x2_t acc00 = vdupq_n_u64(0), acc01 = vdupq_n_u64(0), acc02 = vdupq_n_u64(0), acc03 = vdupq_n_u64(0);
        uint64x2_t acc10 = vdupq_n_u64(0), acc11 = vdupq_n_u64(0), acc12 = vdupq_n_u64(0), acc13 = vdupq_n_u64(0);
        uint64x2_t acc20 = vdupq_n_u64(0), acc21 = vdupq_n_u64(0), acc22 = vdupq_n_u64(0), acc23 = vdupq_n_u64(0);
        uint64x2_t acc30 = vdupq_n_u64(0), acc31 = vdupq_n_u64(0), acc32 = vdupq_n_u64(0), acc33 = vdupq_n_u64(0);

        for (; i + 2u <= n; i += 2u) {
            int32x2_t va0 = vld1_s32(pa0 + i);
            int32x2_t va1 = vld1_s32(pa1 + i);
            int32x2_t va2 = vld1_s32(pa2 + i);
            int32x2_t va3 = vld1_s32(pa3 + i);

            int32x2_t vb0 = vld1_s32(pb0 + i);
            int32x2_t vb1 = vld1_s32(pb1 + i);
            int32x2_t vb2 = vld1_s32(pb2 + i);
            int32x2_t vb3 = vld1_s32(pb3 + i);

            // Wrap semantics match scalar by accumulating in u64 lanes.
            acc00 = vaddq_u64(acc00, vreinterpretq_u64_s64(vmull_s32(va0, vb0)));
            acc01 = vaddq_u64(acc01, vreinterpretq_u64_s64(vmull_s32(va0, vb1)));
            acc02 = vaddq_u64(acc02, vreinterpretq_u64_s64(vmull_s32(va0, vb2)));
            acc03 = vaddq_u64(acc03, vreinterpretq_u64_s64(vmull_s32(va0, vb3)));

            acc10 = vaddq_u64(acc10, vreinterpretq_u64_s64(vmull_s32(va1, vb0)));
            acc11 = vaddq_u64(acc11, vreinterpretq_u64_s64(vmull_s32(va1, vb1)));
            acc12 = vaddq_u64(acc12, vreinterpretq_u64_s64(vmull_s32(va1, vb2)));
            acc13 = vaddq_u64(acc13, vreinterpretq_u64_s64(vmull_s32(va1, vb3)));

            acc20 = vaddq_u64(acc20, vreinterpretq_u64_s64(vmull_s32(va2, vb0)));
            acc21 = vaddq_u64(acc21, vreinterpretq_u64_s64(vmull_s32(va2, vb1)));
            acc22 = vaddq_u64(acc22, vreinterpretq_u64_s64(vmull_s32(va2, vb2)));
            acc23 = vaddq_u64(acc23, vreinterpretq_u64_s64(vmull_s32(va2, vb3)));

            acc30 = vaddq_u64(acc30, vreinterpretq_u64_s64(vmull_s32(va3, vb0)));
            acc31 = vaddq_u64(acc31, vreinterpretq_u64_s64(vmull_s32(va3, vb1)));
            acc32 = vaddq_u64(acc32, vreinterpretq_u64_s64(vmull_s32(va3, vb2)));
            acc33 = vaddq_u64(acc33, vreinterpretq_u64_s64(vmull_s32(va3, vb3)));
        }

        uint64_t t00[2], t01[2], t02[2], t03[2];
        uint64_t t10[2], t11[2], t12[2], t13[2];
        uint64_t t20[2], t21[2], t22[2], t23[2];
        uint64_t t30[2], t31[2], t32[2], t33[2];
        vst1q_u64(t00, acc00); vst1q_u64(t01, acc01); vst1q_u64(t02, acc02); vst1q_u64(t03, acc03);
        vst1q_u64(t10, acc10); vst1q_u64(t11, acc11); vst1q_u64(t12, acc12); vst1q_u64(t13, acc13);
        vst1q_u64(t20, acc20); vst1q_u64(t21, acc21); vst1q_u64(t22, acc22); vst1q_u64(t23, acc23);
        vst1q_u64(t30, acc30); vst1q_u64(t31, acc31); vst1q_u64(t32, acc32); vst1q_u64(t33, acc33);
        c00 = t00[0] + t00[1]; c01 = t01[0] + t01[1]; c02 = t02[0] + t02[1]; c03 = t03[0] + t03[1];
        c10 = t10[0] + t10[1]; c11 = t11[0] + t11[1]; c12 = t12[0] + t12[1]; c13 = t13[0] + t13[1];
        c20 = t20[0] + t20[1]; c21 = t21[0] + t21[1]; c22 = t22[0] + t22[1]; c23 = t23[0] + t23[1];
        c30 = t30[0] + t30[1]; c31 = t31[0] + t31[1]; c32 = t32[0] + t32[1]; c33 = t33[0] + t33[1];

        for (; i < n; i++) {
            int64_t a0v = (int64_t)pa0[i];
            int64_t a1v = (int64_t)pa1[i];
            int64_t a2v = (int64_t)pa2[i];
            int64_t a3v = (int64_t)pa3[i];
            int64_t b0v = (int64_t)pb0[i];
            int64_t b1v = (int64_t)pb1[i];
            int64_t b2v = (int64_t)pb2[i];
            int64_t b3v = (int64_t)pb3[i];
            c00 += (uint64_t)(a0v * b0v); c01 += (uint64_t)(a0v * b1v); c02 += (uint64_t)(a0v * b2v); c03 += (uint64_t)(a0v * b3v);
            c10 += (uint64_t)(a1v * b0v); c11 += (uint64_t)(a1v * b1v); c12 += (uint64_t)(a1v * b2v); c13 += (uint64_t)(a1v * b3v);
            c20 += (uint64_t)(a2v * b0v); c21 += (uint64_t)(a2v * b1v); c22 += (uint64_t)(a2v * b2v); c23 += (uint64_t)(a2v * b3v);
            c30 += (uint64_t)(a3v * b0v); c31 += (uint64_t)(a3v * b1v); c32 += (uint64_t)(a3v * b2v); c33 += (uint64_t)(a3v * b3v);
        }
    } else
#endif
    for (uint32_t i = 0; i < n; i++) {
        int64_t a0v = (int64_t)(int32_t)load_u32_le(buf_data(ba) + (a0_off + i) * 4u);
        int64_t a1v = (int64_t)(int32_t)load_u32_le(buf_data(ba) + (a1_off + i) * 4u);
        int64_t a2v = (int64_t)(int32_t)load_u32_le(buf_data(ba) + (a2_off + i) * 4u);
        int64_t a3v = (int64_t)(int32_t)load_u32_le(buf_data(ba) + (a3_off + i) * 4u);
        int64_t b0v = (int64_t)(int32_t)load_u32_le(buf_data(bb) + (b0_off + i) * 4u);
        int64_t b1v = (int64_t)(int32_t)load_u32_le(buf_data(bb) + (b1_off + i) * 4u);
        int64_t b2v = (int64_t)(int32_t)load_u32_le(buf_data(bb) + (b2_off + i) * 4u);
        int64_t b3v = (int64_t)(int32_t)load_u32_le(buf_data(bb) + (b3_off + i) * 4u);

        c00 += (uint64_t)(a0v * b0v); c01 += (uint64_t)(a0v * b1v); c02 += (uint64_t)(a0v * b2v); c03 += (uint64_t)(a0v * b3v);
        c10 += (uint64_t)(a1v * b0v); c11 += (uint64_t)(a1v * b1v); c12 += (uint64_t)(a1v * b2v); c13 += (uint64_t)(a1v * b3v);
        c20 += (uint64_t)(a2v * b0v); c21 += (uint64_t)(a2v * b1v); c22 += (uint64_t)(a2v * b2v); c23 += (uint64_t)(a2v * b3v);
        c30 += (uint64_t)(a3v * b0v); c31 += (uint64_t)(a3v * b1v); c32 += (uint64_t)(a3v * b2v); c33 += (uint64_t)(a3v * b3v);
    }

    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, c00);
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, c01);
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, c02);
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, c03);
    store_u64_le(buf_data(bout) + (out_off + 4u) * 8u, c10);
    store_u64_le(buf_data(bout) + (out_off + 5u) * 8u, c11);
    store_u64_le(buf_data(bout) + (out_off + 6u) * 8u, c12);
    store_u64_le(buf_data(bout) + (out_off + 7u) * 8u, c13);
    store_u64_le(buf_data(bout) + (out_off + 8u) * 8u, c20);
    store_u64_le(buf_data(bout) + (out_off + 9u) * 8u, c21);
    store_u64_le(buf_data(bout) + (out_off + 10u) * 8u, c22);
    store_u64_le(buf_data(bout) + (out_off + 11u) * 8u, c23);
    store_u64_le(buf_data(bout) + (out_off + 12u) * 8u, c30);
    store_u64_le(buf_data(bout) + (out_off + 13u) * 8u, c31);
    store_u64_le(buf_data(bout) + (out_off + 14u) * 8u, c32);
    store_u64_le(buf_data(bout) + (out_off + 15u) * 8u, c33);
    return out;
}

OrenValue oren_buf_gemm_f32_4x4_slice_into(
    OrenValue out, OrenValue out_offv,
    OrenValue a, OrenValue a0_offv, OrenValue a1_offv, OrenValue a2_offv, OrenValue a3_offv,
    OrenValue b, OrenValue b0_offv, OrenValue b1_offv, OrenValue b2_offv, OrenValue b3_offv,
    OrenValue nv) {
    if (!buf_is_f64(out) || out_offv.type != OREN_TYPE_INT
        || !buf_is_f32(a) || a0_offv.type != OREN_TYPE_INT || a1_offv.type != OREN_TYPE_INT || a2_offv.type != OREN_TYPE_INT || a3_offv.type != OREN_TYPE_INT
        || !buf_is_f32(b)
        || b0_offv.type != OREN_TYPE_INT || b1_offv.type != OREN_TYPE_INT || b2_offv.type != OREN_TYPE_INT || b3_offv.type != OREN_TYPE_INT
        || nv.type != OREN_TYPE_INT) {
        return buf_err("oren_buf_gemm_f32_4x4_slice_into expects (f64_buf,int,f32_buf,int,int,int,int,f32_buf,int,int,int,int,int)");
    }

    OrenBuf* bout = out.as.buf_val;
    OrenBuf* ba = a.as.buf_val;
    OrenBuf* bb = b.as.buf_val;
    long long out_off_ll = out_offv.as.int_val;
    long long a0_off_ll = a0_offv.as.int_val;
    long long a1_off_ll = a1_offv.as.int_val;
    long long a2_off_ll = a2_offv.as.int_val;
    long long a3_off_ll = a3_offv.as.int_val;
    long long b0_off_ll = b0_offv.as.int_val;
    long long b1_off_ll = b1_offv.as.int_val;
    long long b2_off_ll = b2_offv.as.int_val;
    long long b3_off_ll = b3_offv.as.int_val;
    long long n_ll = nv.as.int_val;

    if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0
        || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) {
        return buf_err("buf_gemm_f32_4x4_slice_into: negative arg");
    }
    if ((uint64_t)out_off_ll > (uint64_t)bout->len || (uint64_t)bout->len - (uint64_t)out_off_ll < 16u) {
        return buf_err("buf_gemm_f32_4x4_slice_into: out range out of bounds");
    }

    if ((uint64_t)a0_off_ll > (uint64_t)ba->len || (uint64_t)a1_off_ll > (uint64_t)ba->len
        || (uint64_t)a2_off_ll > (uint64_t)ba->len || (uint64_t)a3_off_ll > (uint64_t)ba->len) {
        return buf_err("buf_gemm_f32_4x4_slice_into: a_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a0_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a1_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a2_off_ll
        || (uint64_t)n_ll > (uint64_t)ba->len - (uint64_t)a3_off_ll) {
        return buf_err("buf_gemm_f32_4x4_slice_into: a range out of bounds");
    }

    if ((uint64_t)b0_off_ll > (uint64_t)bb->len || (uint64_t)b1_off_ll > (uint64_t)bb->len
        || (uint64_t)b2_off_ll > (uint64_t)bb->len || (uint64_t)b3_off_ll > (uint64_t)bb->len) {
        return buf_err("buf_gemm_f32_4x4_slice_into: b_off out of bounds");
    }
    if ((uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b0_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b1_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b2_off_ll
        || (uint64_t)n_ll > (uint64_t)bb->len - (uint64_t)b3_off_ll) {
        return buf_err("buf_gemm_f32_4x4_slice_into: b range out of bounds");
    }

    uint32_t n = (uint32_t)n_ll;
    uint32_t out_off = (uint32_t)out_off_ll;
    uint32_t a0_off = (uint32_t)a0_off_ll;
    uint32_t a1_off = (uint32_t)a1_off_ll;
    uint32_t a2_off = (uint32_t)a2_off_ll;
    uint32_t a3_off = (uint32_t)a3_off_ll;
    uint32_t b0_off = (uint32_t)b0_off_ll;
    uint32_t b1_off = (uint32_t)b1_off_ll;
    uint32_t b2_off = (uint32_t)b2_off_ll;
    uint32_t b3_off = (uint32_t)b3_off_ll;

    // Accumulate in f64, deterministic k order.
    double c00 = 0.0, c01 = 0.0, c02 = 0.0, c03 = 0.0;
    double c10 = 0.0, c11 = 0.0, c12 = 0.0, c13 = 0.0;
    double c20 = 0.0, c21 = 0.0, c22 = 0.0, c23 = 0.0;
    double c30 = 0.0, c31 = 0.0, c32 = 0.0, c33 = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const uint32_t* pa0 = (const uint32_t*)(const void*)(buf_data(ba) + a0_off * 4u);
        const uint32_t* pa1 = (const uint32_t*)(const void*)(buf_data(ba) + a1_off * 4u);
        const uint32_t* pa2 = (const uint32_t*)(const void*)(buf_data(ba) + a2_off * 4u);
        const uint32_t* pa3 = (const uint32_t*)(const void*)(buf_data(ba) + a3_off * 4u);

        const uint32_t* pb0 = (const uint32_t*)(const void*)(buf_data(bb) + b0_off * 4u);
        const uint32_t* pb1 = (const uint32_t*)(const void*)(buf_data(bb) + b1_off * 4u);
        const uint32_t* pb2 = (const uint32_t*)(const void*)(buf_data(bb) + b2_off * 4u);
        const uint32_t* pb3 = (const uint32_t*)(const void*)(buf_data(bb) + b3_off * 4u);

        // Vectorize across columns (pairs) using f64 lanes; no FMA to avoid contraction.
        for (uint32_t i = 0; i < n; i++) {
            float64_t a0d = (float64_t)f32_from_u32_bits(pa0[i]);
            float64_t a1d = (float64_t)f32_from_u32_bits(pa1[i]);
            float64_t a2d = (float64_t)f32_from_u32_bits(pa2[i]);
            float64_t a3d = (float64_t)f32_from_u32_bits(pa3[i]);

            float64_t b0d = (float64_t)f32_from_u32_bits(pb0[i]);
            float64_t b1d = (float64_t)f32_from_u32_bits(pb1[i]);
            float64_t b2d = (float64_t)f32_from_u32_bits(pb2[i]);
            float64_t b3d = (float64_t)f32_from_u32_bits(pb3[i]);

            float64x2_t vb01 = {b0d, b1d};
            float64x2_t vb23 = {b2d, b3d};

            // row 0
            {
                float64x2_t va = vdupq_n_f64(a0d);
                float64x2_t p01 = vmulq_f64(va, vb01);
                float64x2_t p23 = vmulq_f64(va, vb23);
                c00 += vgetq_lane_f64(p01, 0);
                c01 += vgetq_lane_f64(p01, 1);
                c02 += vgetq_lane_f64(p23, 0);
                c03 += vgetq_lane_f64(p23, 1);
            }
            // row 1
            {
                float64x2_t va = vdupq_n_f64(a1d);
                float64x2_t p01 = vmulq_f64(va, vb01);
                float64x2_t p23 = vmulq_f64(va, vb23);
                c10 += vgetq_lane_f64(p01, 0);
                c11 += vgetq_lane_f64(p01, 1);
                c12 += vgetq_lane_f64(p23, 0);
                c13 += vgetq_lane_f64(p23, 1);
            }
            // row 2
            {
                float64x2_t va = vdupq_n_f64(a2d);
                float64x2_t p01 = vmulq_f64(va, vb01);
                float64x2_t p23 = vmulq_f64(va, vb23);
                c20 += vgetq_lane_f64(p01, 0);
                c21 += vgetq_lane_f64(p01, 1);
                c22 += vgetq_lane_f64(p23, 0);
                c23 += vgetq_lane_f64(p23, 1);
            }
            // row 3
            {
                float64x2_t va = vdupq_n_f64(a3d);
                float64x2_t p01 = vmulq_f64(va, vb01);
                float64x2_t p23 = vmulq_f64(va, vb23);
                c30 += vgetq_lane_f64(p01, 0);
                c31 += vgetq_lane_f64(p01, 1);
                c32 += vgetq_lane_f64(p23, 0);
                c33 += vgetq_lane_f64(p23, 1);
            }
        }
    } else
#endif
    {
        for (uint32_t i = 0; i < n; i++) {
            float a0v = f32_from_u32_bits(load_u32_le(buf_data(ba) + (a0_off + i) * 4u));
            float a1v = f32_from_u32_bits(load_u32_le(buf_data(ba) + (a1_off + i) * 4u));
            float a2v = f32_from_u32_bits(load_u32_le(buf_data(ba) + (a2_off + i) * 4u));
            float a3v = f32_from_u32_bits(load_u32_le(buf_data(ba) + (a3_off + i) * 4u));

            float b0v = f32_from_u32_bits(load_u32_le(buf_data(bb) + (b0_off + i) * 4u));
            float b1v = f32_from_u32_bits(load_u32_le(buf_data(bb) + (b1_off + i) * 4u));
            float b2v = f32_from_u32_bits(load_u32_le(buf_data(bb) + (b2_off + i) * 4u));
            float b3v = f32_from_u32_bits(load_u32_le(buf_data(bb) + (b3_off + i) * 4u));

            double da0 = (double)a0v, da1 = (double)a1v, da2 = (double)a2v, da3 = (double)a3v;
            double db0 = (double)b0v, db1 = (double)b1v, db2 = (double)b2v, db3 = (double)b3v;

            c00 += da0 * db0; c01 += da0 * db1; c02 += da0 * db2; c03 += da0 * db3;
            c10 += da1 * db0; c11 += da1 * db1; c12 += da1 * db2; c13 += da1 * db3;
            c20 += da2 * db0; c21 += da2 * db1; c22 += da2 * db2; c23 += da2 * db3;
            c30 += da3 * db0; c31 += da3 * db1; c32 += da3 * db2; c33 += da3 * db3;
        }
    }

    // Store as f64 elements (little-endian), row-major.
    store_u64_le(buf_data(bout) + (out_off + 0u) * 8u, f64_to_u64_bits(c00));
    store_u64_le(buf_data(bout) + (out_off + 1u) * 8u, f64_to_u64_bits(c01));
    store_u64_le(buf_data(bout) + (out_off + 2u) * 8u, f64_to_u64_bits(c02));
    store_u64_le(buf_data(bout) + (out_off + 3u) * 8u, f64_to_u64_bits(c03));

    store_u64_le(buf_data(bout) + (out_off + 4u) * 8u, f64_to_u64_bits(c10));
    store_u64_le(buf_data(bout) + (out_off + 5u) * 8u, f64_to_u64_bits(c11));
    store_u64_le(buf_data(bout) + (out_off + 6u) * 8u, f64_to_u64_bits(c12));
    store_u64_le(buf_data(bout) + (out_off + 7u) * 8u, f64_to_u64_bits(c13));

    store_u64_le(buf_data(bout) + (out_off + 8u) * 8u, f64_to_u64_bits(c20));
    store_u64_le(buf_data(bout) + (out_off + 9u) * 8u, f64_to_u64_bits(c21));
    store_u64_le(buf_data(bout) + (out_off + 10u) * 8u, f64_to_u64_bits(c22));
    store_u64_le(buf_data(bout) + (out_off + 11u) * 8u, f64_to_u64_bits(c23));

    store_u64_le(buf_data(bout) + (out_off + 12u) * 8u, f64_to_u64_bits(c30));
    store_u64_le(buf_data(bout) + (out_off + 13u) * 8u, f64_to_u64_bits(c31));
    store_u64_le(buf_data(bout) + (out_off + 14u) * 8u, f64_to_u64_bits(c32));
    store_u64_le(buf_data(bout) + (out_off + 15u) * 8u, f64_to_u64_bits(c33));

    return out;
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
#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && a_stride == 1u && b_stride == 1u && n >= 4u) {
        const uint32_t* pa = (const uint32_t*)(const void*)(buf_data(ba) + a_off * 4u);
        const uint32_t* pb = (const uint32_t*)(const void*)(buf_data(bb) + b_off * 4u);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t va_u = vld1q_u32(pa + i);
            uint32x4_t vb_u = vld1q_u32(pb + i);
            float32x4_t va_f = vreinterpretq_f32_u32(va_u);
            float32x4_t vb_f = vreinterpretq_f32_u32(vb_u);

            float32x2_t va_lo = vget_low_f32(va_f);
            float32x2_t va_hi = vget_high_f32(va_f);
            float32x2_t vb_lo = vget_low_f32(vb_f);
            float32x2_t vb_hi = vget_high_f32(vb_f);

            float64x2_t da0 = vcvt_f64_f32(va_lo);
            float64x2_t da1 = vcvt_f64_f32(va_hi);
            float64x2_t db0 = vcvt_f64_f32(vb_lo);
            float64x2_t db1 = vcvt_f64_f32(vb_hi);

            float64x2_t p0 = vmulq_f64(da0, db0);
            float64x2_t p1 = vmulq_f64(da1, db1);

            // lane-ordered accumulation matches scalar i,i+1,i+2,i+3
            acc = acc + vgetq_lane_f64(p0, 0);
            acc = acc + vgetq_lane_f64(p0, 1);
            acc = acc + vgetq_lane_f64(p1, 0);
            acc = acc + vgetq_lane_f64(p1, 1);
        }
        for (; i < n; i++) {
            uint32_t ai = a_off + i;
            uint32_t bi = b_off + i;
            uint32_t ua = load_u32_le(buf_data(ba) + ai * 4u);
            uint32_t ub = load_u32_le(buf_data(bb) + bi * 4u);
            float fa = 0.0f, fb = 0.0f;
            memcpy(&fa, &ua, sizeof(fa));
            memcpy(&fb, &ub, sizeof(fb));
            acc += (double)fa * (double)fb;
        }
        return oren_float(acc);
    }
#endif
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

