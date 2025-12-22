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
    uint32_t n = buf.as.buf_val->len;
    double acc = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        // Preserve scalar semantics: convert f32 -> f64 and add to scalar acc in fixed order.
        const uint32_t* pu = (const uint32_t*)(const void*)buf_data(buf.as.buf_val);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t vu_u = vld1q_u32(pu + i);
            float32x4_t vf = vreinterpretq_f32_u32(vu_u);

            float32x2_t v_lo = vget_low_f32(vf);
            float32x2_t v_hi = vget_high_f32(vf);
            float64x2_t d0 = vcvt_f64_f32(v_lo);
            float64x2_t d1 = vcvt_f64_f32(v_hi);

            acc = acc + vgetq_lane_f64(d0, 0);
            acc = acc + vgetq_lane_f64(d0, 1);
            acc = acc + vgetq_lane_f64(d1, 0);
            acc = acc + vgetq_lane_f64(d1, 1);
        }
        for (; i < n; i++) {
            uint32_t u = load_u32_le(buf_data(buf.as.buf_val) + i * 4u);
            float f = 0.0f;
            memcpy(&f, &u, sizeof(f));
            acc += (double)f;
        }
        return oren_float(acc);
    }
#endif

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

OrenValue oren_buf_dot_f64_into(OrenValue out, OrenValue a, OrenValue b) {
    if (!buf_is_f64(out) || !buf_is_f64(a) || !buf_is_f64(b)) return buf_err("oren_buf_dot_f64_into expects (f64_buf, f64_buf, f64_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_f64_into: length mismatch");
    OrenValue s = oren_buf_dot_f64(a, b);
    if (oren_is_err(s).as.bool_val) return s;
    return buf_store_f64_at0(out, s.as.float_val, "oren_buf_dot_f64_into expects (f64_buf, f64_buf, f64_buf)");
}

OrenValue oren_buf_reduce_sum_f64(OrenValue buf) {
    if (!buf_is_f64(buf)) return buf_err("oren_buf_reduce_sum_f64 expects (f64_buf)");
    uint32_t n = buf.as.buf_val->len;
    double acc = 0.0;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 2u) {
        const double* p = (const double*)(const void*)buf_data(buf.as.buf_val);
        uint32_t i = 0;
        for (; i + 2u <= n; i += 2u) {
            float64x2_t v = vld1q_f64(p + i);
            acc = acc + vgetq_lane_f64(v, 0);
            acc = acc + vgetq_lane_f64(v, 1);
        }
        for (; i < n; i++) {
            uint64_t u = load_u64_le(buf_data(buf.as.buf_val) + i * 8u);
            double d = 0.0;
            memcpy(&d, &u, sizeof(d));
            acc += d;
        }
        return oren_float(acc);
    }
#endif

    for (uint32_t i = 0; i < n; i++) {
        uint64_t u = load_u64_le(buf_data(buf.as.buf_val) + i * 8u);
        double d = 0.0;
        memcpy(&d, &u, sizeof(d));
        acc += d;
    }
    return oren_float(acc);
}

OrenValue oren_buf_reduce_sum_f64_into(OrenValue out, OrenValue a) {
    if (!buf_is_f64(out) || !buf_is_f64(a)) return buf_err("oren_buf_reduce_sum_f64_into expects (f64_buf, f64_buf)");
    OrenValue s = oren_buf_reduce_sum_f64(a);
    if (oren_is_err(s).as.bool_val) return s;
    return buf_store_f64_at0(out, s.as.float_val, "oren_buf_reduce_sum_f64_into expects (f64_buf, f64_buf)");
}

OrenValue oren_buf_dot_f32_into(OrenValue out, OrenValue a, OrenValue b) {
    if (!buf_is_f64(out) || !buf_is_f32(a) || !buf_is_f32(b)) return buf_err("oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
    if (a.as.buf_val->len != b.as.buf_val->len) return buf_err("buf_dot_f32_into: length mismatch");
    double acc = 0.0;
    uint32_t n = a.as.buf_val->len;

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
        return buf_store_f64_at0(out, acc, "oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
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
    return buf_store_f64_at0(out, acc, "oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
}

OrenValue oren_buf_reduce_sum_f32_into(OrenValue out, OrenValue a) {
    if (!buf_is_f64(out) || !buf_is_f32(a)) return buf_err("oren_buf_reduce_sum_f32_into expects (f64_buf, f32_buf)");
    double acc = 0.0;
    uint32_t n = a.as.buf_val->len;

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const uint32_t* pu = (const uint32_t*)(const void*)buf_data(a.as.buf_val);
        uint32_t i = 0;
        for (; i + 4u <= n; i += 4u) {
            uint32x4_t vu_u = vld1q_u32(pu + i);
            float32x4_t vf = vreinterpretq_f32_u32(vu_u);

            float32x2_t v_lo = vget_low_f32(vf);
            float32x2_t v_hi = vget_high_f32(vf);
            float64x2_t d0 = vcvt_f64_f32(v_lo);
            float64x2_t d1 = vcvt_f64_f32(v_hi);

            acc = acc + vgetq_lane_f64(d0, 0);
            acc = acc + vgetq_lane_f64(d0, 1);
            acc = acc + vgetq_lane_f64(d1, 0);
            acc = acc + vgetq_lane_f64(d1, 1);
        }
        for (; i < n; i++) {
            uint32_t u = load_u32_le(buf_data(a.as.buf_val) + i * 4u);
            float f = 0.0f;
            memcpy(&f, &u, sizeof(f));
            acc += (double)f;
        }
        return buf_store_f64_at0(out, acc, "oren_buf_reduce_sum_f32_into expects (f64_buf, f32_buf)");
    }
#endif

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

#if OREN_BUF_HAVE_NEON
    if (oren_simd_enabled_cached() && n >= 4u) {
        const int32_t* px = (const int32_t*)(const void*)buf_data(bx);
        const int32_t* py = (const int32_t*)(const void*)buf_data(by);
        int32_t* pd = (int32_t*)(void*)buf_data(od);
        uint32_t i = 0;
        int32x4_t va = vdupq_n_s32(a);
        for (; i + 4u <= n; i += 4u) {
            int32x4_t vx = vld1q_s32(px + i);
            int32x4_t vy = vld1q_s32(py + i);
            int32x4_t vm = vmulq_s32(va, vx); // wrap
            int32x4_t vo = vaddq_s32(vm, vy); // wrap
            vst1q_s32(pd + i, vo);
        }
        for (; i < n; i++) {
            int32_t xi = (int32_t)load_u32_le(buf_data(bx) + i * 4u);
            int32_t yi = (int32_t)load_u32_le(buf_data(by) + i * 4u);
            int32_t outv = (int32_t)((int64_t)a * (int64_t)xi + (int64_t)yi);
            store_u32_le(buf_data(od) + i * 4u, (uint32_t)outv);
        }
        return dst;
    }
#endif

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
