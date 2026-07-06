        case 114: { // oren_buf_dot_i32_slice(a:i32_buf, a_off:int, b:i32_buf, b_off:int, n:int) -> int
            if (nargs > 4 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_I32_BUF && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[2].as.buf;
                int64_t a_off_ll = args[1].as.i;
                int64_t b_off_ll = args[3].as.i;
                int64_t n_ll = args[4].as.i;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_slice: invalid buffers"); break; }
                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_slice: negative arg"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_slice: offset out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_slice: a range out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_slice: b range out of bounds"); break; }

                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b_off = (uint32_t)b_off_ll;
                uint32_t n = (uint32_t)n_ll;

                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && n >= 4u) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        int32_t wa[4], wb[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb, b->data + offb, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int32x4_t vb = vld1q_s32(wb);
                        int64x2_t prod_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb));
                        int64x2_t prod_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_lo));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_hi));
                    }
                    uint64_t tmp[2];
                    vst1q_u64(tmp, vacc);
                    acc_u += tmp[0] + tmp[1];
                    for (; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[offb]
                                    | ((uint32_t)b->data[offb + 1] << 8)
                                    | ((uint32_t)b->data[offb + 2] << 16)
                                    | ((uint32_t)b->data[offb + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[offb]
                                    | ((uint32_t)b->data[offb + 1] << 8)
                                    | ((uint32_t)b->data[offb + 2] << 16)
                                    | ((uint32_t)b->data[offb + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                }

                res = avm_int(avm_i64_from_u64_bits_native(acc_u));
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_i32_slice expects (i32_buf, int, i32_buf, int, int)");
            }
            break;
        }
        case 115: { // oren_buf_dot_f32_slice(a:f32_buf, a_off:int, b:f32_buf, b_off:int, n:int) -> float
            if (nargs > 4 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_F32_BUF && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[2].as.buf;
                int64_t a_off_ll = args[1].as.i;
                int64_t b_off_ll = args[3].as.i;
                int64_t n_ll = args[4].as.i;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_slice: invalid buffers"); break; }
                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_slice: negative arg"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_slice: offset out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_slice: a range out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_slice: b range out of bounds"); break; }

                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b_off = (uint32_t)b_off_ll;
                uint32_t n = (uint32_t)n_ll;

                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && n >= 4u) {
                    uint32_t i = 0;
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t wa[4], wb[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb, b->data + offb, 16);

                        uint32x4_t va_u = vld1q_u32(wa);
                        uint32x4_t vb_u = vld1q_u32(wb);
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
                        acc += vgetq_lane_f64(p0, 0);
                        acc += vgetq_lane_f64(p0, 1);
                        acc += vgetq_lane_f64(p1, 0);
                        acc += vgetq_lane_f64(p1, 1);
                    }
                    for (; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[offb]
                                    | ((uint32_t)b->data[offb + 1] << 8)
                                    | ((uint32_t)b->data[offb + 2] << 16)
                                    | ((uint32_t)b->data[offb + 3] << 24);
                        float fa = 0.0f, fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        acc += (double)fa * (double)fb;
                    }
                } else
#endif
                for (uint32_t i = 0; i < n; i++) {
                    uint32_t offa = (a_off + i) * 4u;
                    uint32_t offb = (b_off + i) * 4u;
                    uint32_t ua = (uint32_t)a->data[offa]
                                | ((uint32_t)a->data[offa + 1] << 8)
                                | ((uint32_t)a->data[offa + 2] << 16)
                                | ((uint32_t)a->data[offa + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[offb]
                                | ((uint32_t)b->data[offb + 1] << 8)
                                | ((uint32_t)b->data[offb + 2] << 16)
                                | ((uint32_t)b->data[offb + 3] << 24);
                    float fa = 0.0f, fb = 0.0f;
                    memcpy(&fa, &ua, sizeof(fa));
                    memcpy(&fb, &ub, sizeof(fb));
                    acc += (double)fa * (double)fb;
                }
                res.type = AVM_VAL_FLOAT;
                res.as.f = acc;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f32_slice expects (f32_buf, int, f32_buf, int, int)");
            }
            break;
        }
        case 116: { // oren_buf_dot_i32_strided(a:i32_buf, a_off:int, a_stride:int, b:i32_buf, b_off:int, b_stride:int, n:int) -> int
            if (nargs > 6
                && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT
                && args[3].type == AVM_VAL_I32_BUF && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT
                && args[6].type == AVM_VAL_INT) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[3].as.buf;
                int64_t a_off_ll = args[1].as.i;
                int64_t a_stride_ll = args[2].as.i;
                int64_t b_off_ll = args[4].as.i;
                int64_t b_stride_ll = args[5].as.i;
                int64_t n_ll = args[6].as.i;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: invalid buffers"); break; }
                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: negative arg"); break; }
                if (a_stride_ll <= 0 || b_stride_ll <= 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: stride must be > 0"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: offset out of bounds"); break; }
                if (n_ll > 0) {
                    uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
                    uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
                    if (alast >= (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: a range out of bounds"); break; }
                    if (blast >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_strided: b range out of bounds"); break; }
                }
                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b_off = (uint32_t)b_off_ll;
                uint32_t a_stride = (uint32_t)a_stride_ll;
                uint32_t b_stride = (uint32_t)b_stride_ll;
                uint32_t n = (uint32_t)n_ll;

                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && a_stride == 1u && b_stride == 1u && n >= 4u) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        int32_t wa[4], wb[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb, b->data + offb, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int32x4_t vb = vld1q_s32(wb);
                        int64x2_t prod_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb));
                        int64x2_t prod_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_lo));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(prod_hi));
                    }
                    uint64_t tmp[2];
                    vst1q_u64(tmp, vacc);
                    acc_u += tmp[0] + tmp[1];
                    for (; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[offb]
                                    | ((uint32_t)b->data[offb + 1] << 8)
                                    | ((uint32_t)b->data[offb + 2] << 16)
                                    | ((uint32_t)b->data[offb + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                } else
#endif
                for (uint32_t i = 0; i < n; i++) {
                    uint32_t offa = (a_off + i * a_stride) * 4u;
                    uint32_t offb = (b_off + i * b_stride) * 4u;
                    uint32_t ua = (uint32_t)a->data[offa]
                                | ((uint32_t)a->data[offa + 1] << 8)
                                | ((uint32_t)a->data[offa + 2] << 16)
                                | ((uint32_t)a->data[offa + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[offb]
                                | ((uint32_t)b->data[offb + 1] << 8)
                                | ((uint32_t)b->data[offb + 2] << 16)
                                | ((uint32_t)b->data[offb + 3] << 24);
                    int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                    acc_u += avm_u64_bits_i64_native(prod);
                }
                res = avm_int(avm_i64_from_u64_bits_native(acc_u));
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_i32_strided expects (i32_buf,int,int,i32_buf,int,int,int)");
            }
            break;
        }
        case 117: { // oren_buf_dot_f32_strided(a:f32_buf, a_off:int, a_stride:int, b:f32_buf, b_off:int, b_stride:int, n:int) -> float
            if (nargs > 6
                && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT
                && args[3].type == AVM_VAL_F32_BUF && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT
                && args[6].type == AVM_VAL_INT) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[3].as.buf;
                int64_t a_off_ll = args[1].as.i;
                int64_t a_stride_ll = args[2].as.i;
                int64_t b_off_ll = args[4].as.i;
                int64_t b_stride_ll = args[5].as.i;
                int64_t n_ll = args[6].as.i;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: invalid buffers"); break; }
                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: negative arg"); break; }
                if (a_stride_ll <= 0 || b_stride_ll <= 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: stride must be > 0"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: offset out of bounds"); break; }
                if (n_ll > 0) {
                    uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
                    uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
                    if (alast >= (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: a range out of bounds"); break; }
                    if (blast >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_strided: b range out of bounds"); break; }
                }
                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b_off = (uint32_t)b_off_ll;
                uint32_t a_stride = (uint32_t)a_stride_ll;
                uint32_t b_stride = (uint32_t)b_stride_ll;
                uint32_t n = (uint32_t)n_ll;

                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && a_stride == 1u && b_stride == 1u && n >= 4u) {
                    uint32_t i = 0;
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t wa[4], wb[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb, b->data + offb, 16);

                        uint32x4_t va_u = vld1q_u32(wa);
                        uint32x4_t vb_u = vld1q_u32(wb);
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
                        acc += vgetq_lane_f64(p0, 0);
                        acc += vgetq_lane_f64(p0, 1);
                        acc += vgetq_lane_f64(p1, 0);
                        acc += vgetq_lane_f64(p1, 1);
                    }
                    for (; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t offb = (b_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[offb]
                                    | ((uint32_t)b->data[offb + 1] << 8)
                                    | ((uint32_t)b->data[offb + 2] << 16)
                                    | ((uint32_t)b->data[offb + 3] << 24);
                        float fa = 0.0f, fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        acc += (double)fa * (double)fb;
                    }
                } else
#endif
                for (uint32_t i = 0; i < n; i++) {
                    uint32_t offa = (a_off + i * a_stride) * 4u;
                    uint32_t offb = (b_off + i * b_stride) * 4u;
                    uint32_t ua = (uint32_t)a->data[offa]
                                | ((uint32_t)a->data[offa + 1] << 8)
                                | ((uint32_t)a->data[offa + 2] << 16)
                                | ((uint32_t)a->data[offa + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[offb]
                                | ((uint32_t)b->data[offb + 1] << 8)
                                | ((uint32_t)b->data[offb + 2] << 16)
                                | ((uint32_t)b->data[offb + 3] << 24);
                    float fa = 0.0f, fb = 0.0f;
                    memcpy(&fa, &ua, sizeof(fa));
                    memcpy(&fb, &ub, sizeof(fb));
                    acc += (double)fa * (double)fb;
                }
                res.type = AVM_VAL_FLOAT;
                res.as.f = acc;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f32_strided expects (f32_buf,int,int,f32_buf,int,int,int)");
            }
            break;
        }
