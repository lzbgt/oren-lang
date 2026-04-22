        case 122: { // oren_buf_dot_i32_4_slice_into(out:i64_buf, out_off:int, a:i32_buf, a_off:int, b:i32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> i64_buf
            if (nargs > 9
                && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_INT
                && args[2].type == AVM_VAL_I32_BUF && args[3].type == AVM_VAL_INT
                && args[4].type == AVM_VAL_I32_BUF
                && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT && args[7].type == AVM_VAL_INT && args[8].type == AVM_VAL_INT
                && args[9].type == AVM_VAL_INT) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[2].as.buf;
                AvmBuf* b = args[4].as.buf;
                int64_t out_off_ll = args[1].as.i;
                int64_t a_off_ll = args[3].as.i;
                int64_t b0_off_ll = args[5].as.i;
                int64_t b1_off_ll = args[6].as.i;
                int64_t b2_off_ll = args[7].as.i;
                int64_t b3_off_ll = args[8].as.i;
                int64_t n_ll = args[9].as.i;
                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: invalid buffers"); break; }
                if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: negative arg"); break; }
                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: out range out of bounds"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: a_off out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: a range out of bounds"); break; }
                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: b_off out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_4_slice_into: b range out of bounds"); break; }

                uint32_t out_off = (uint32_t)out_off_ll;
                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b0_off = (uint32_t)b0_off_ll;
                uint32_t b1_off = (uint32_t)b1_off_ll;
                uint32_t b2_off = (uint32_t)b2_off_ll;
                uint32_t b3_off = (uint32_t)b3_off_ll;
                uint32_t n = (uint32_t)n_ll;

                uint64_t s0 = 0, s1 = 0, s2 = 0, s3 = 0;

#if AVM_HAS_NEON
                if (vm && vm->enable_simd && n >= 4u) {
                    uint32_t i = 0;
                    uint64x2_t vacc0 = vdupq_n_u64(0);
                    uint64x2_t vacc1 = vdupq_n_u64(0);
                    uint64x2_t vacc2 = vdupq_n_u64(0);
                    uint64x2_t vacc3 = vdupq_n_u64(0);
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t off0 = (b0_off + i) * 4u;
                        uint32_t off1 = (b1_off + i) * 4u;
                        uint32_t off2 = (b2_off + i) * 4u;
                        uint32_t off3 = (b3_off + i) * 4u;

                        uint32_t wa[4], wb0[4], wb1[4], wb2[4], wb3[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb0, b->data + off0, 16);
                        memcpy(wb1, b->data + off1, 16);
                        memcpy(wb2, b->data + off2, 16);
                        memcpy(wb3, b->data + off3, 16);

                        int32x4_t va = vreinterpretq_s32_u32(vld1q_u32(wa));
                        int32x4_t vb0 = vreinterpretq_s32_u32(vld1q_u32(wb0));
                        int32x4_t vb1 = vreinterpretq_s32_u32(vld1q_u32(wb1));
                        int32x4_t vb2 = vreinterpretq_s32_u32(vld1q_u32(wb2));
                        int32x4_t vb3 = vreinterpretq_s32_u32(vld1q_u32(wb3));

                        // lane-ordered accumulation, preserved as u64 bits (wrap modulo 2^64)
                        {
                            int64x2_t p0_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb0));
                            int64x2_t p0_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb0));
                            vacc0 = vaddq_u64(vacc0, vreinterpretq_u64_s64(p0_lo));
                            vacc0 = vaddq_u64(vacc0, vreinterpretq_u64_s64(p0_hi));
                        }
                        {
                            int64x2_t p1_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb1));
                            int64x2_t p1_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb1));
                            vacc1 = vaddq_u64(vacc1, vreinterpretq_u64_s64(p1_lo));
                            vacc1 = vaddq_u64(vacc1, vreinterpretq_u64_s64(p1_hi));
                        }
                        {
                            int64x2_t p2_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb2));
                            int64x2_t p2_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb2));
                            vacc2 = vaddq_u64(vacc2, vreinterpretq_u64_s64(p2_lo));
                            vacc2 = vaddq_u64(vacc2, vreinterpretq_u64_s64(p2_hi));
                        }
                        {
                            int64x2_t p3_lo = vmull_s32(vget_low_s32(va), vget_low_s32(vb3));
                            int64x2_t p3_hi = vmull_s32(vget_high_s32(va), vget_high_s32(vb3));
                            vacc3 = vaddq_u64(vacc3, vreinterpretq_u64_s64(p3_lo));
                            vacc3 = vaddq_u64(vacc3, vreinterpretq_u64_s64(p3_hi));
                        }
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
                        uint32_t offa2 = (a_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa2]
                                    | ((uint32_t)a->data[offa2 + 1] << 8)
                                    | ((uint32_t)a->data[offa2 + 2] << 16)
                                    | ((uint32_t)a->data[offa2 + 3] << 24);
                        int64_t av = (int64_t)(int32_t)ua;

                        uint32_t off0_2 = (b0_off + i) * 4u;
                        uint32_t off1_2 = (b1_off + i) * 4u;
                        uint32_t off2_2 = (b2_off + i) * 4u;
                        uint32_t off3_2 = (b3_off + i) * 4u;

                        uint32_t ub0 = (uint32_t)b->data[off0_2]
                                     | ((uint32_t)b->data[off0_2 + 1] << 8)
                                     | ((uint32_t)b->data[off0_2 + 2] << 16)
                                     | ((uint32_t)b->data[off0_2 + 3] << 24);
                        uint32_t ub1 = (uint32_t)b->data[off1_2]
                                     | ((uint32_t)b->data[off1_2 + 1] << 8)
                                     | ((uint32_t)b->data[off1_2 + 2] << 16)
                                     | ((uint32_t)b->data[off1_2 + 3] << 24);
                        uint32_t ub2 = (uint32_t)b->data[off2_2]
                                     | ((uint32_t)b->data[off2_2 + 1] << 8)
                                     | ((uint32_t)b->data[off2_2 + 2] << 16)
                                     | ((uint32_t)b->data[off2_2 + 3] << 24);
                        uint32_t ub3 = (uint32_t)b->data[off3_2]
                                     | ((uint32_t)b->data[off3_2 + 1] << 8)
                                     | ((uint32_t)b->data[off3_2 + 2] << 16)
                                     | ((uint32_t)b->data[off3_2 + 3] << 24);

                        s0 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub0);
                        s1 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub1);
                        s2 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub2);
                        s3 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub3);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        int64_t av = (int64_t)(int32_t)ua;

                        uint32_t off0 = (b0_off + i) * 4u;
                        uint32_t off1 = (b1_off + i) * 4u;
                        uint32_t off2 = (b2_off + i) * 4u;
                        uint32_t off3 = (b3_off + i) * 4u;

                        uint32_t ub0 = (uint32_t)b->data[off0]
                                     | ((uint32_t)b->data[off0 + 1] << 8)
                                     | ((uint32_t)b->data[off0 + 2] << 16)
                                     | ((uint32_t)b->data[off0 + 3] << 24);
                        uint32_t ub1 = (uint32_t)b->data[off1]
                                     | ((uint32_t)b->data[off1 + 1] << 8)
                                     | ((uint32_t)b->data[off1 + 2] << 16)
                                     | ((uint32_t)b->data[off1 + 3] << 24);
                        uint32_t ub2 = (uint32_t)b->data[off2]
                                     | ((uint32_t)b->data[off2 + 1] << 8)
                                     | ((uint32_t)b->data[off2 + 2] << 16)
                                     | ((uint32_t)b->data[off2 + 3] << 24);
                        uint32_t ub3 = (uint32_t)b->data[off3]
                                     | ((uint32_t)b->data[off3 + 1] << 8)
                                     | ((uint32_t)b->data[off3 + 2] << 16)
                                     | ((uint32_t)b->data[off3 + 3] << 24);

                        s0 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub0);
                        s1 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub1);
                        s2 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub2);
                        s3 += avm_u64_bits_i64_native(av * (int64_t)(int32_t)ub3);
                    }
                }

                uint64_t u0 = s0, u1 = s1, u2 = s2, u3 = s3;
                uint32_t o0 = (out_off + 0u) * 8u;
                uint32_t o1 = (out_off + 1u) * 8u;
                uint32_t o2 = (out_off + 2u) * 8u;
                uint32_t o3 = (out_off + 3u) * 8u;
                out->data[o0 + 0] = (uint8_t)(u0 & 0xFFu);
                out->data[o0 + 1] = (uint8_t)((u0 >> 8) & 0xFFu);
                out->data[o0 + 2] = (uint8_t)((u0 >> 16) & 0xFFu);
                out->data[o0 + 3] = (uint8_t)((u0 >> 24) & 0xFFu);
                out->data[o0 + 4] = (uint8_t)((u0 >> 32) & 0xFFu);
                out->data[o0 + 5] = (uint8_t)((u0 >> 40) & 0xFFu);
                out->data[o0 + 6] = (uint8_t)((u0 >> 48) & 0xFFu);
                out->data[o0 + 7] = (uint8_t)((u0 >> 56) & 0xFFu);

                out->data[o1 + 0] = (uint8_t)(u1 & 0xFFu);
                out->data[o1 + 1] = (uint8_t)((u1 >> 8) & 0xFFu);
                out->data[o1 + 2] = (uint8_t)((u1 >> 16) & 0xFFu);
                out->data[o1 + 3] = (uint8_t)((u1 >> 24) & 0xFFu);
                out->data[o1 + 4] = (uint8_t)((u1 >> 32) & 0xFFu);
                out->data[o1 + 5] = (uint8_t)((u1 >> 40) & 0xFFu);
                out->data[o1 + 6] = (uint8_t)((u1 >> 48) & 0xFFu);
                out->data[o1 + 7] = (uint8_t)((u1 >> 56) & 0xFFu);

                out->data[o2 + 0] = (uint8_t)(u2 & 0xFFu);
                out->data[o2 + 1] = (uint8_t)((u2 >> 8) & 0xFFu);
                out->data[o2 + 2] = (uint8_t)((u2 >> 16) & 0xFFu);
                out->data[o2 + 3] = (uint8_t)((u2 >> 24) & 0xFFu);
                out->data[o2 + 4] = (uint8_t)((u2 >> 32) & 0xFFu);
                out->data[o2 + 5] = (uint8_t)((u2 >> 40) & 0xFFu);
                out->data[o2 + 6] = (uint8_t)((u2 >> 48) & 0xFFu);
                out->data[o2 + 7] = (uint8_t)((u2 >> 56) & 0xFFu);

                out->data[o3 + 0] = (uint8_t)(u3 & 0xFFu);
                out->data[o3 + 1] = (uint8_t)((u3 >> 8) & 0xFFu);
                out->data[o3 + 2] = (uint8_t)((u3 >> 16) & 0xFFu);
                out->data[o3 + 3] = (uint8_t)((u3 >> 24) & 0xFFu);
                out->data[o3 + 4] = (uint8_t)((u3 >> 32) & 0xFFu);
                out->data[o3 + 5] = (uint8_t)((u3 >> 40) & 0xFFu);
                out->data[o3 + 6] = (uint8_t)((u3 >> 48) & 0xFFu);
                out->data[o3 + 7] = (uint8_t)((u3 >> 56) & 0xFFu);

                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_i32_4_slice_into expects (i64_buf,int,i32_buf,int,i32_buf,int,int,int,int,int)");
            }
            break;
        }
	        case 127: { // oren_buf_dot_f32_4_slice_into(out:f64_buf, out_off:int, a:f32_buf, a_off:int, b:f32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
            if (nargs > 9
                && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT
                && args[2].type == AVM_VAL_F32_BUF && args[3].type == AVM_VAL_INT
                && args[4].type == AVM_VAL_F32_BUF
                && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT && args[7].type == AVM_VAL_INT && args[8].type == AVM_VAL_INT
                && args[9].type == AVM_VAL_INT) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[2].as.buf;
                AvmBuf* b = args[4].as.buf;
                int64_t out_off_ll = args[1].as.i;
                int64_t a_off_ll = args[3].as.i;
                int64_t b0_off_ll = args[5].as.i;
                int64_t b1_off_ll = args[6].as.i;
                int64_t b2_off_ll = args[7].as.i;
                int64_t b3_off_ll = args[8].as.i;
                int64_t n_ll = args[9].as.i;
                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: invalid buffers"); break; }
                if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: negative arg"); break; }
                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: out range out of bounds"); break; }
                if ((uint64_t)a_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: a_off out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: a range out of bounds"); break; }
                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: b_off out of bounds"); break; }
                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_4_slice_into: b range out of bounds"); break; }

                uint32_t out_off = (uint32_t)out_off_ll;
                uint32_t a_off = (uint32_t)a_off_ll;
                uint32_t b0_off = (uint32_t)b0_off_ll;
                uint32_t b1_off = (uint32_t)b1_off_ll;
                uint32_t b2_off = (uint32_t)b2_off_ll;
                uint32_t b3_off = (uint32_t)b3_off_ll;
                uint32_t n = (uint32_t)n_ll;

                double s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && n >= 4u) {
                    uint32_t i = 0;
                    for (; i + 4u <= n; i += 4u) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t off0 = (b0_off + i) * 4u;
                        uint32_t off1 = (b1_off + i) * 4u;
                        uint32_t off2 = (b2_off + i) * 4u;
                        uint32_t off3 = (b3_off + i) * 4u;
                        uint32_t wa[4], wb0[4], wb1[4], wb2[4], wb3[4];
                        memcpy(wa, a->data + offa, 16);
                        memcpy(wb0, b->data + off0, 16);
                        memcpy(wb1, b->data + off1, 16);
                        memcpy(wb2, b->data + off2, 16);
                        memcpy(wb3, b->data + off3, 16);

                        uint32x4_t va_u = vld1q_u32(wa);
                        float32x4_t va_f = vreinterpretq_f32_u32(va_u);
                        float32x2_t va_lo = vget_low_f32(va_f);
                        float32x2_t va_hi = vget_high_f32(va_f);
                        float64x2_t da0 = vcvt_f64_f32(va_lo);
                        float64x2_t da1 = vcvt_f64_f32(va_hi);

                        uint32x4_t vb0_u = vld1q_u32(wb0);
                        uint32x4_t vb1_u = vld1q_u32(wb1);
                        uint32x4_t vb2_u = vld1q_u32(wb2);
                        uint32x4_t vb3_u = vld1q_u32(wb3);

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
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        float fa = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        double da = (double)fa;

                        uint32_t off0 = (b0_off + i) * 4u;
                        uint32_t off1 = (b1_off + i) * 4u;
                        uint32_t off2 = (b2_off + i) * 4u;
                        uint32_t off3 = (b3_off + i) * 4u;
                        uint32_t ub0 = (uint32_t)b->data[off0]
                                     | ((uint32_t)b->data[off0 + 1] << 8)
                                     | ((uint32_t)b->data[off0 + 2] << 16)
                                     | ((uint32_t)b->data[off0 + 3] << 24);
                        uint32_t ub1 = (uint32_t)b->data[off1]
                                     | ((uint32_t)b->data[off1 + 1] << 8)
                                     | ((uint32_t)b->data[off1 + 2] << 16)
                                     | ((uint32_t)b->data[off1 + 3] << 24);
                        uint32_t ub2 = (uint32_t)b->data[off2]
                                     | ((uint32_t)b->data[off2 + 1] << 8)
                                     | ((uint32_t)b->data[off2 + 2] << 16)
                                     | ((uint32_t)b->data[off2 + 3] << 24);
                        uint32_t ub3 = (uint32_t)b->data[off3]
                                     | ((uint32_t)b->data[off3 + 1] << 8)
                                     | ((uint32_t)b->data[off3 + 2] << 16)
                                     | ((uint32_t)b->data[off3 + 3] << 24);
                        float fb0 = 0.0f, fb1 = 0.0f, fb2 = 0.0f, fb3 = 0.0f;
                        memcpy(&fb0, &ub0, sizeof(fb0));
                        memcpy(&fb1, &ub1, sizeof(fb1));
                        memcpy(&fb2, &ub2, sizeof(fb2));
                        memcpy(&fb3, &ub3, sizeof(fb3));
                        s0 += da * (double)fb0;
                        s1 += da * (double)fb1;
                        s2 += da * (double)fb2;
                        s3 += da * (double)fb3;
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < n; i++) {
                        uint32_t offa = (a_off + i) * 4u;
                        uint32_t ua = (uint32_t)a->data[offa]
                                    | ((uint32_t)a->data[offa + 1] << 8)
                                    | ((uint32_t)a->data[offa + 2] << 16)
                                    | ((uint32_t)a->data[offa + 3] << 24);
                        float fa = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        double da = (double)fa;

                        uint32_t off0 = (b0_off + i) * 4u;
                        uint32_t off1 = (b1_off + i) * 4u;
                        uint32_t off2 = (b2_off + i) * 4u;
                        uint32_t off3 = (b3_off + i) * 4u;
                        uint32_t ub0 = (uint32_t)b->data[off0]
                                     | ((uint32_t)b->data[off0 + 1] << 8)
                                     | ((uint32_t)b->data[off0 + 2] << 16)
                                     | ((uint32_t)b->data[off0 + 3] << 24);
                        uint32_t ub1 = (uint32_t)b->data[off1]
                                     | ((uint32_t)b->data[off1 + 1] << 8)
                                     | ((uint32_t)b->data[off1 + 2] << 16)
                                     | ((uint32_t)b->data[off1 + 3] << 24);
                        uint32_t ub2 = (uint32_t)b->data[off2]
                                     | ((uint32_t)b->data[off2 + 1] << 8)
                                     | ((uint32_t)b->data[off2 + 2] << 16)
                                     | ((uint32_t)b->data[off2 + 3] << 24);
                        uint32_t ub3 = (uint32_t)b->data[off3]
                                     | ((uint32_t)b->data[off3 + 1] << 8)
                                     | ((uint32_t)b->data[off3 + 2] << 16)
                                     | ((uint32_t)b->data[off3 + 3] << 24);
                        float fb0 = 0.0f, fb1 = 0.0f, fb2 = 0.0f, fb3 = 0.0f;
                        memcpy(&fb0, &ub0, sizeof(fb0));
                        memcpy(&fb1, &ub1, sizeof(fb1));
                        memcpy(&fb2, &ub2, sizeof(fb2));
                        memcpy(&fb3, &ub3, sizeof(fb3));
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
                uint32_t o0 = (out_off + 0u) * 8u;
                uint32_t o1 = (out_off + 1u) * 8u;
                uint32_t o2 = (out_off + 2u) * 8u;
                uint32_t o3 = (out_off + 3u) * 8u;

                out->data[o0 + 0] = (uint8_t)(u0 & 0xFFu);
                out->data[o0 + 1] = (uint8_t)((u0 >> 8) & 0xFFu);
                out->data[o0 + 2] = (uint8_t)((u0 >> 16) & 0xFFu);
                out->data[o0 + 3] = (uint8_t)((u0 >> 24) & 0xFFu);
                out->data[o0 + 4] = (uint8_t)((u0 >> 32) & 0xFFu);
                out->data[o0 + 5] = (uint8_t)((u0 >> 40) & 0xFFu);
                out->data[o0 + 6] = (uint8_t)((u0 >> 48) & 0xFFu);
                out->data[o0 + 7] = (uint8_t)((u0 >> 56) & 0xFFu);

                out->data[o1 + 0] = (uint8_t)(u1 & 0xFFu);
                out->data[o1 + 1] = (uint8_t)((u1 >> 8) & 0xFFu);
                out->data[o1 + 2] = (uint8_t)((u1 >> 16) & 0xFFu);
                out->data[o1 + 3] = (uint8_t)((u1 >> 24) & 0xFFu);
                out->data[o1 + 4] = (uint8_t)((u1 >> 32) & 0xFFu);
                out->data[o1 + 5] = (uint8_t)((u1 >> 40) & 0xFFu);
                out->data[o1 + 6] = (uint8_t)((u1 >> 48) & 0xFFu);
                out->data[o1 + 7] = (uint8_t)((u1 >> 56) & 0xFFu);

                out->data[o2 + 0] = (uint8_t)(u2 & 0xFFu);
                out->data[o2 + 1] = (uint8_t)((u2 >> 8) & 0xFFu);
                out->data[o2 + 2] = (uint8_t)((u2 >> 16) & 0xFFu);
                out->data[o2 + 3] = (uint8_t)((u2 >> 24) & 0xFFu);
                out->data[o2 + 4] = (uint8_t)((u2 >> 32) & 0xFFu);
                out->data[o2 + 5] = (uint8_t)((u2 >> 40) & 0xFFu);
                out->data[o2 + 6] = (uint8_t)((u2 >> 48) & 0xFFu);
                out->data[o2 + 7] = (uint8_t)((u2 >> 56) & 0xFFu);

                out->data[o3 + 0] = (uint8_t)(u3 & 0xFFu);
                out->data[o3 + 1] = (uint8_t)((u3 >> 8) & 0xFFu);
                out->data[o3 + 2] = (uint8_t)((u3 >> 16) & 0xFFu);
                out->data[o3 + 3] = (uint8_t)((u3 >> 24) & 0xFFu);
                out->data[o3 + 4] = (uint8_t)((u3 >> 32) & 0xFFu);
                out->data[o3 + 5] = (uint8_t)((u3 >> 40) & 0xFFu);
                out->data[o3 + 6] = (uint8_t)((u3 >> 48) & 0xFFu);
                out->data[o3 + 7] = (uint8_t)((u3 >> 56) & 0xFFu);

                res = args[0];
		            } else {
		                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f32_4_slice_into expects (f64_buf,int,f32_buf,int,f32_buf,int,int,int,int,int)");
		            }
		            break;
		        }
			        case 130: { // oren_buf_dot_f64_4_slice_into(out:f64_buf, out_off:int, a:f64_buf, a_off:int, b:f64_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
			            if (nargs > 9
			                && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT
			                && args[2].type == AVM_VAL_F64_BUF && args[3].type == AVM_VAL_INT
			                && args[4].type == AVM_VAL_F64_BUF
		                && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT && args[7].type == AVM_VAL_INT && args[8].type == AVM_VAL_INT
		                && args[9].type == AVM_VAL_INT) {
		                AvmBuf* out = args[0].as.buf;
		                AvmBuf* a = args[2].as.buf;
		                AvmBuf* b = args[4].as.buf;
		                int64_t out_off_ll = args[1].as.i;
		                int64_t a_off_ll = args[3].as.i;
		                int64_t b0_off_ll = args[5].as.i;
		                int64_t b1_off_ll = args[6].as.i;
		                int64_t b2_off_ll = args[7].as.i;
		                int64_t b3_off_ll = args[8].as.i;
		                int64_t n_ll = args[9].as.i;
		                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: invalid buffers"); break; }
		                if (out_off_ll < 0 || a_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: negative arg"); break; }
		                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: out range out of bounds"); break; }
		                if ((uint64_t)a_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: a_off out of bounds"); break; }
		                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: a range out of bounds"); break; }
		                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: b_off out of bounds"); break; }
		                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
		                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
		                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
		                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_4_slice_into: b range out of bounds"); break; }
		
		                uint32_t out_off = (uint32_t)out_off_ll;
		                uint32_t a_off = (uint32_t)a_off_ll;
		                uint32_t b0_off = (uint32_t)b0_off_ll;
		                uint32_t b1_off = (uint32_t)b1_off_ll;
		                uint32_t b2_off = (uint32_t)b2_off_ll;
		                uint32_t b3_off = (uint32_t)b3_off_ll;
		                uint32_t n = (uint32_t)n_ll;
		
		                double s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
		#if AVM_HAS_NEON
		                if (vm && vm->enable_simd && n >= 2u) {
		                    uint32_t i = 0;
		                    for (; i + 2u <= n; i += 2u) {
		                        uint32_t offa = (a_off + i) * 8u;
		                        uint32_t off0 = (b0_off + i) * 8u;
		                        uint32_t off1 = (b1_off + i) * 8u;
		                        uint32_t off2 = (b2_off + i) * 8u;
		                        uint32_t off3 = (b3_off + i) * 8u;
		                        uint64_t wa[2], wb0[2], wb1[2], wb2[2], wb3[2];
		                        memcpy(wa, a->data + offa, 16);
		                        memcpy(wb0, b->data + off0, 16);
		                        memcpy(wb1, b->data + off1, 16);
		                        memcpy(wb2, b->data + off2, 16);
		                        memcpy(wb3, b->data + off3, 16);
		
		                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
		                        float64x2_t vb0 = vreinterpretq_f64_u64(vld1q_u64(wb0));
		                        float64x2_t vb1 = vreinterpretq_f64_u64(vld1q_u64(wb1));
		                        float64x2_t vb2 = vreinterpretq_f64_u64(vld1q_u64(wb2));
		                        float64x2_t vb3 = vreinterpretq_f64_u64(vld1q_u64(wb3));
		
		                        float64x2_t p0 = vmulq_f64(va, vb0);
		                        float64x2_t p1 = vmulq_f64(va, vb1);
		                        float64x2_t p2 = vmulq_f64(va, vb2);
		                        float64x2_t p3 = vmulq_f64(va, vb3);
		
		                        s0 += vgetq_lane_f64(p0, 0); s0 += vgetq_lane_f64(p0, 1);
		                        s1 += vgetq_lane_f64(p1, 0); s1 += vgetq_lane_f64(p1, 1);
		                        s2 += vgetq_lane_f64(p2, 0); s2 += vgetq_lane_f64(p2, 1);
		                        s3 += vgetq_lane_f64(p3, 0); s3 += vgetq_lane_f64(p3, 1);
		                    }
		                    for (; i < n; i++) {
		                        uint32_t offai = (a_off + i) * 8u;
		                        uint32_t off0i = (b0_off + i) * 8u;
		                        uint32_t off1i = (b1_off + i) * 8u;
		                        uint32_t off2i = (b2_off + i) * 8u;
		                        uint32_t off3i = (b3_off + i) * 8u;
		                        uint64_t ua = (uint64_t)a->data[offai]
		                                     | ((uint64_t)a->data[offai + 1] << 8)
		                                     | ((uint64_t)a->data[offai + 2] << 16)
		                                     | ((uint64_t)a->data[offai + 3] << 24)
		                                     | ((uint64_t)a->data[offai + 4] << 32)
		                                     | ((uint64_t)a->data[offai + 5] << 40)
		                                     | ((uint64_t)a->data[offai + 6] << 48)
		                                     | ((uint64_t)a->data[offai + 7] << 56);
		                        uint64_t ub0 = (uint64_t)b->data[off0i]
		                                     | ((uint64_t)b->data[off0i + 1] << 8)
		                                     | ((uint64_t)b->data[off0i + 2] << 16)
		                                     | ((uint64_t)b->data[off0i + 3] << 24)
		                                     | ((uint64_t)b->data[off0i + 4] << 32)
		                                     | ((uint64_t)b->data[off0i + 5] << 40)
		                                     | ((uint64_t)b->data[off0i + 6] << 48)
		                                     | ((uint64_t)b->data[off0i + 7] << 56);
		                        uint64_t ub1 = (uint64_t)b->data[off1i]
		                                     | ((uint64_t)b->data[off1i + 1] << 8)
		                                     | ((uint64_t)b->data[off1i + 2] << 16)
		                                     | ((uint64_t)b->data[off1i + 3] << 24)
		                                     | ((uint64_t)b->data[off1i + 4] << 32)
		                                     | ((uint64_t)b->data[off1i + 5] << 40)
		                                     | ((uint64_t)b->data[off1i + 6] << 48)
		                                     | ((uint64_t)b->data[off1i + 7] << 56);
		                        uint64_t ub2 = (uint64_t)b->data[off2i]
		                                     | ((uint64_t)b->data[off2i + 1] << 8)
		                                     | ((uint64_t)b->data[off2i + 2] << 16)
		                                     | ((uint64_t)b->data[off2i + 3] << 24)
		                                     | ((uint64_t)b->data[off2i + 4] << 32)
		                                     | ((uint64_t)b->data[off2i + 5] << 40)
		                                     | ((uint64_t)b->data[off2i + 6] << 48)
		                                     | ((uint64_t)b->data[off2i + 7] << 56);
		                        uint64_t ub3 = (uint64_t)b->data[off3i]
		                                     | ((uint64_t)b->data[off3i + 1] << 8)
		                                     | ((uint64_t)b->data[off3i + 2] << 16)
		                                     | ((uint64_t)b->data[off3i + 3] << 24)
		                                     | ((uint64_t)b->data[off3i + 4] << 32)
		                                     | ((uint64_t)b->data[off3i + 5] << 40)
		                                     | ((uint64_t)b->data[off3i + 6] << 48)
		                                     | ((uint64_t)b->data[off3i + 7] << 56);
		                        double da = 0.0, db0 = 0.0, db1 = 0.0, db2 = 0.0, db3 = 0.0;
		                        memcpy(&da, &ua, 8);
		                        memcpy(&db0, &ub0, 8);
		                        memcpy(&db1, &ub1, 8);
		                        memcpy(&db2, &ub2, 8);
		                        memcpy(&db3, &ub3, 8);
		                        s0 += da * db0;
		                        s1 += da * db1;
		                        s2 += da * db2;
		                        s3 += da * db3;
		                    }
		                } else
		#endif
		                {
		                    for (uint32_t i = 0; i < n; i++) {
		                        uint32_t offai = (a_off + i) * 8u;
		                        uint32_t off0i = (b0_off + i) * 8u;
		                        uint32_t off1i = (b1_off + i) * 8u;
		                        uint32_t off2i = (b2_off + i) * 8u;
		                        uint32_t off3i = (b3_off + i) * 8u;
		                        uint64_t ua = (uint64_t)a->data[offai]
		                                     | ((uint64_t)a->data[offai + 1] << 8)
		                                     | ((uint64_t)a->data[offai + 2] << 16)
		                                     | ((uint64_t)a->data[offai + 3] << 24)
		                                     | ((uint64_t)a->data[offai + 4] << 32)
		                                     | ((uint64_t)a->data[offai + 5] << 40)
		                                     | ((uint64_t)a->data[offai + 6] << 48)
		                                     | ((uint64_t)a->data[offai + 7] << 56);
		                        uint64_t ub0 = (uint64_t)b->data[off0i]
		                                     | ((uint64_t)b->data[off0i + 1] << 8)
		                                     | ((uint64_t)b->data[off0i + 2] << 16)
		                                     | ((uint64_t)b->data[off0i + 3] << 24)
		                                     | ((uint64_t)b->data[off0i + 4] << 32)
		                                     | ((uint64_t)b->data[off0i + 5] << 40)
		                                     | ((uint64_t)b->data[off0i + 6] << 48)
		                                     | ((uint64_t)b->data[off0i + 7] << 56);
		                        uint64_t ub1 = (uint64_t)b->data[off1i]
		                                     | ((uint64_t)b->data[off1i + 1] << 8)
		                                     | ((uint64_t)b->data[off1i + 2] << 16)
		                                     | ((uint64_t)b->data[off1i + 3] << 24)
		                                     | ((uint64_t)b->data[off1i + 4] << 32)
		                                     | ((uint64_t)b->data[off1i + 5] << 40)
		                                     | ((uint64_t)b->data[off1i + 6] << 48)
		                                     | ((uint64_t)b->data[off1i + 7] << 56);
		                        uint64_t ub2 = (uint64_t)b->data[off2i]
		                                     | ((uint64_t)b->data[off2i + 1] << 8)
		                                     | ((uint64_t)b->data[off2i + 2] << 16)
		                                     | ((uint64_t)b->data[off2i + 3] << 24)
		                                     | ((uint64_t)b->data[off2i + 4] << 32)
		                                     | ((uint64_t)b->data[off2i + 5] << 40)
		                                     | ((uint64_t)b->data[off2i + 6] << 48)
		                                     | ((uint64_t)b->data[off2i + 7] << 56);
		                        uint64_t ub3 = (uint64_t)b->data[off3i]
		                                     | ((uint64_t)b->data[off3i + 1] << 8)
		                                     | ((uint64_t)b->data[off3i + 2] << 16)
		                                     | ((uint64_t)b->data[off3i + 3] << 24)
		                                     | ((uint64_t)b->data[off3i + 4] << 32)
		                                     | ((uint64_t)b->data[off3i + 5] << 40)
		                                     | ((uint64_t)b->data[off3i + 6] << 48)
		                                     | ((uint64_t)b->data[off3i + 7] << 56);
		                        double da = 0.0, db0 = 0.0, db1 = 0.0, db2 = 0.0, db3 = 0.0;
		                        memcpy(&da, &ua, 8);
		                        memcpy(&db0, &ub0, 8);
		                        memcpy(&db1, &ub1, 8);
		                        memcpy(&db2, &ub2, 8);
		                        memcpy(&db3, &ub3, 8);
		                        s0 += da * db0;
		                        s1 += da * db1;
		                        s2 += da * db2;
		                        s3 += da * db3;
		                    }
		                }

		                uint64_t u0 = 0, u1 = 0, u2 = 0, u3 = 0;
		                memcpy(&u0, &s0, 8);
		                memcpy(&u1, &s1, 8);
		                memcpy(&u2, &s2, 8);
		                memcpy(&u3, &s3, 8);
		                uint32_t o0 = (out_off + 0u) * 8u;
		                uint32_t o1 = (out_off + 1u) * 8u;
		                uint32_t o2 = (out_off + 2u) * 8u;
		                uint32_t o3 = (out_off + 3u) * 8u;
		
		                out->data[o0 + 0] = (uint8_t)(u0 & 0xFFu);
		                out->data[o0 + 1] = (uint8_t)((u0 >> 8) & 0xFFu);
		                out->data[o0 + 2] = (uint8_t)((u0 >> 16) & 0xFFu);
		                out->data[o0 + 3] = (uint8_t)((u0 >> 24) & 0xFFu);
		                out->data[o0 + 4] = (uint8_t)((u0 >> 32) & 0xFFu);
		                out->data[o0 + 5] = (uint8_t)((u0 >> 40) & 0xFFu);
		                out->data[o0 + 6] = (uint8_t)((u0 >> 48) & 0xFFu);
		                out->data[o0 + 7] = (uint8_t)((u0 >> 56) & 0xFFu);
		
		                out->data[o1 + 0] = (uint8_t)(u1 & 0xFFu);
		                out->data[o1 + 1] = (uint8_t)((u1 >> 8) & 0xFFu);
		                out->data[o1 + 2] = (uint8_t)((u1 >> 16) & 0xFFu);
		                out->data[o1 + 3] = (uint8_t)((u1 >> 24) & 0xFFu);
		                out->data[o1 + 4] = (uint8_t)((u1 >> 32) & 0xFFu);
		                out->data[o1 + 5] = (uint8_t)((u1 >> 40) & 0xFFu);
		                out->data[o1 + 6] = (uint8_t)((u1 >> 48) & 0xFFu);
		                out->data[o1 + 7] = (uint8_t)((u1 >> 56) & 0xFFu);
		
		                out->data[o2 + 0] = (uint8_t)(u2 & 0xFFu);
		                out->data[o2 + 1] = (uint8_t)((u2 >> 8) & 0xFFu);
		                out->data[o2 + 2] = (uint8_t)((u2 >> 16) & 0xFFu);
		                out->data[o2 + 3] = (uint8_t)((u2 >> 24) & 0xFFu);
		                out->data[o2 + 4] = (uint8_t)((u2 >> 32) & 0xFFu);
		                out->data[o2 + 5] = (uint8_t)((u2 >> 40) & 0xFFu);
		                out->data[o2 + 6] = (uint8_t)((u2 >> 48) & 0xFFu);
		                out->data[o2 + 7] = (uint8_t)((u2 >> 56) & 0xFFu);
		
		                out->data[o3 + 0] = (uint8_t)(u3 & 0xFFu);
		                out->data[o3 + 1] = (uint8_t)((u3 >> 8) & 0xFFu);
		                out->data[o3 + 2] = (uint8_t)((u3 >> 16) & 0xFFu);
		                out->data[o3 + 3] = (uint8_t)((u3 >> 24) & 0xFFu);
		                out->data[o3 + 4] = (uint8_t)((u3 >> 32) & 0xFFu);
		                out->data[o3 + 5] = (uint8_t)((u3 >> 40) & 0xFFu);
		                out->data[o3 + 6] = (uint8_t)((u3 >> 48) & 0xFFu);
		                out->data[o3 + 7] = (uint8_t)((u3 >> 56) & 0xFFu);
		
		                res = args[0];
		            } else {
		                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f64_4_slice_into expects (f64_buf,int,f64_buf,int,f64_buf,int,int,int,int,int)");
			            }
			            break;
			        }
			        case 131: { // oren_buf_gemm_f64_4x4_slice_into(out:f64_buf, out_off:int, a:f64_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:f64_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
			            if (nargs > 12
			                && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT
			                && args[2].type == AVM_VAL_F64_BUF
			                && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT
			                && args[7].type == AVM_VAL_F64_BUF
			                && args[8].type == AVM_VAL_INT && args[9].type == AVM_VAL_INT && args[10].type == AVM_VAL_INT && args[11].type == AVM_VAL_INT
			                && args[12].type == AVM_VAL_INT) {
			                AvmBuf* out = args[0].as.buf;
			                AvmBuf* a = args[2].as.buf;
			                AvmBuf* b = args[7].as.buf;
			                int64_t out_off_ll = args[1].as.i;
			                int64_t a0_off_ll = args[3].as.i;
			                int64_t a1_off_ll = args[4].as.i;
			                int64_t a2_off_ll = args[5].as.i;
			                int64_t a3_off_ll = args[6].as.i;
			                int64_t b0_off_ll = args[8].as.i;
			                int64_t b1_off_ll = args[9].as.i;
			                int64_t b2_off_ll = args[10].as.i;
			                int64_t b3_off_ll = args[11].as.i;
			                int64_t n_ll = args[12].as.i;
			                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: invalid buffers"); break; }
			                if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: negative arg"); break; }
			                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 16u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: out range out of bounds"); break; }
			                if ((uint64_t)a0_off_ll > (uint64_t)a->len || (uint64_t)a1_off_ll > (uint64_t)a->len || (uint64_t)a2_off_ll > (uint64_t)a->len || (uint64_t)a3_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: a_off out of bounds"); break; }
			                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a0_off_ll
			                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a1_off_ll
			                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a2_off_ll
			                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: a range out of bounds"); break; }
			                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: b_off out of bounds"); break; }
			                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
			                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
			                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
			                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f64_4x4_slice_into: b range out of bounds"); break; }
			
			                uint32_t out_off = (uint32_t)out_off_ll;
			                uint32_t a0_off = (uint32_t)a0_off_ll;
			                uint32_t a1_off = (uint32_t)a1_off_ll;
			                uint32_t a2_off = (uint32_t)a2_off_ll;
			                uint32_t a3_off = (uint32_t)a3_off_ll;
			                uint32_t b0_off = (uint32_t)b0_off_ll;
			                uint32_t b1_off = (uint32_t)b1_off_ll;
			                uint32_t b2_off = (uint32_t)b2_off_ll;
			                uint32_t b3_off = (uint32_t)b3_off_ll;
			                uint32_t n = (uint32_t)n_ll;
			
			                double c00 = 0.0, c01 = 0.0, c02 = 0.0, c03 = 0.0;
			                double c10 = 0.0, c11 = 0.0, c12 = 0.0, c13 = 0.0;
			                double c20 = 0.0, c21 = 0.0, c22 = 0.0, c23 = 0.0;
			                double c30 = 0.0, c31 = 0.0, c32 = 0.0, c33 = 0.0;
			
			#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && n >= 2u) {
			                    // NEON fast path (arm64 only), determinism-safe:
			                    // - multiply in f64
			                    // - accumulate in strict increasing-k order (lane0 then lane1; no reassociation; no FMA)
			                    uint32_t i = 0;
			                    for (; i + 2u <= n; i += 2u) {
			                        uint32_t oa0 = (a0_off + i) * 8u;
			                        uint32_t oa1 = (a1_off + i) * 8u;
			                        uint32_t oa2 = (a2_off + i) * 8u;
			                        uint32_t oa3 = (a3_off + i) * 8u;
			                        uint32_t ob0 = (b0_off + i) * 8u;
			                        uint32_t ob1 = (b1_off + i) * 8u;
			                        uint32_t ob2 = (b2_off + i) * 8u;
			                        uint32_t ob3 = (b3_off + i) * 8u;

			                        uint64_t wa0[2], wa1[2], wa2[2], wa3[2];
			                        uint64_t wb0[2], wb1[2], wb2[2], wb3[2];
			                        memcpy(wa0, a->data + oa0, 16);
			                        memcpy(wa1, a->data + oa1, 16);
			                        memcpy(wa2, a->data + oa2, 16);
			                        memcpy(wa3, a->data + oa3, 16);
			                        memcpy(wb0, b->data + ob0, 16);
			                        memcpy(wb1, b->data + ob1, 16);
			                        memcpy(wb2, b->data + ob2, 16);
			                        memcpy(wb3, b->data + ob3, 16);

			                        float64x2_t va0 = vreinterpretq_f64_u64(vld1q_u64(wa0));
			                        float64x2_t va1 = vreinterpretq_f64_u64(vld1q_u64(wa1));
			                        float64x2_t va2 = vreinterpretq_f64_u64(vld1q_u64(wa2));
			                        float64x2_t va3 = vreinterpretq_f64_u64(vld1q_u64(wa3));
			                        float64x2_t vb0 = vreinterpretq_f64_u64(vld1q_u64(wb0));
			                        float64x2_t vb1 = vreinterpretq_f64_u64(vld1q_u64(wb1));
			                        float64x2_t vb2 = vreinterpretq_f64_u64(vld1q_u64(wb2));
			                        float64x2_t vb3 = vreinterpretq_f64_u64(vld1q_u64(wb3));

			                        // Row 0
			                        {
			                            float64x2_t p = vmulq_f64(va0, vb0); c00 += vgetq_lane_f64(p, 0); c00 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va0, vb1); c01 += vgetq_lane_f64(p, 0); c01 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va0, vb2); c02 += vgetq_lane_f64(p, 0); c02 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va0, vb3); c03 += vgetq_lane_f64(p, 0); c03 += vgetq_lane_f64(p, 1);
			                        }
			                        // Row 1
			                        {
			                            float64x2_t p = vmulq_f64(va1, vb0); c10 += vgetq_lane_f64(p, 0); c10 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va1, vb1); c11 += vgetq_lane_f64(p, 0); c11 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va1, vb2); c12 += vgetq_lane_f64(p, 0); c12 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va1, vb3); c13 += vgetq_lane_f64(p, 0); c13 += vgetq_lane_f64(p, 1);
			                        }
			                        // Row 2
			                        {
			                            float64x2_t p = vmulq_f64(va2, vb0); c20 += vgetq_lane_f64(p, 0); c20 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va2, vb1); c21 += vgetq_lane_f64(p, 0); c21 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va2, vb2); c22 += vgetq_lane_f64(p, 0); c22 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va2, vb3); c23 += vgetq_lane_f64(p, 0); c23 += vgetq_lane_f64(p, 1);
			                        }
			                        // Row 3
			                        {
			                            float64x2_t p = vmulq_f64(va3, vb0); c30 += vgetq_lane_f64(p, 0); c30 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va3, vb1); c31 += vgetq_lane_f64(p, 0); c31 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va3, vb2); c32 += vgetq_lane_f64(p, 0); c32 += vgetq_lane_f64(p, 1);
			                            p = vmulq_f64(va3, vb3); c33 += vgetq_lane_f64(p, 0); c33 += vgetq_lane_f64(p, 1);
			                        }
			                    }
			                    for (; i < n; i++) {
			                        uint32_t oa0 = (a0_off + i) * 8u;
			                        uint32_t oa1 = (a1_off + i) * 8u;
			                        uint32_t oa2 = (a2_off + i) * 8u;
			                        uint32_t oa3 = (a3_off + i) * 8u;
			                        uint32_t ob0 = (b0_off + i) * 8u;
			                        uint32_t ob1 = (b1_off + i) * 8u;
			                        uint32_t ob2 = (b2_off + i) * 8u;
			                        uint32_t ob3 = (b3_off + i) * 8u;
			                        uint64_t ua0 = 0, ua1 = 0, ua2 = 0, ua3 = 0;
			                        uint64_t ub0 = 0, ub1 = 0, ub2 = 0, ub3 = 0;
			                        ua0 = (uint64_t)a->data[oa0]
			                             | ((uint64_t)a->data[oa0 + 1] << 8)
			                             | ((uint64_t)a->data[oa0 + 2] << 16)
			                             | ((uint64_t)a->data[oa0 + 3] << 24)
			                             | ((uint64_t)a->data[oa0 + 4] << 32)
			                             | ((uint64_t)a->data[oa0 + 5] << 40)
			                             | ((uint64_t)a->data[oa0 + 6] << 48)
			                             | ((uint64_t)a->data[oa0 + 7] << 56);
			                        ua1 = (uint64_t)a->data[oa1]
			                             | ((uint64_t)a->data[oa1 + 1] << 8)
			                             | ((uint64_t)a->data[oa1 + 2] << 16)
			                             | ((uint64_t)a->data[oa1 + 3] << 24)
			                             | ((uint64_t)a->data[oa1 + 4] << 32)
			                             | ((uint64_t)a->data[oa1 + 5] << 40)
			                             | ((uint64_t)a->data[oa1 + 6] << 48)
			                             | ((uint64_t)a->data[oa1 + 7] << 56);
			                        ua2 = (uint64_t)a->data[oa2]
			                             | ((uint64_t)a->data[oa2 + 1] << 8)
			                             | ((uint64_t)a->data[oa2 + 2] << 16)
			                             | ((uint64_t)a->data[oa2 + 3] << 24)
			                             | ((uint64_t)a->data[oa2 + 4] << 32)
			                             | ((uint64_t)a->data[oa2 + 5] << 40)
			                             | ((uint64_t)a->data[oa2 + 6] << 48)
			                             | ((uint64_t)a->data[oa2 + 7] << 56);
			                        ua3 = (uint64_t)a->data[oa3]
			                             | ((uint64_t)a->data[oa3 + 1] << 8)
			                             | ((uint64_t)a->data[oa3 + 2] << 16)
			                             | ((uint64_t)a->data[oa3 + 3] << 24)
			                             | ((uint64_t)a->data[oa3 + 4] << 32)
			                             | ((uint64_t)a->data[oa3 + 5] << 40)
			                             | ((uint64_t)a->data[oa3 + 6] << 48)
			                             | ((uint64_t)a->data[oa3 + 7] << 56);
			                        ub0 = (uint64_t)b->data[ob0]
			                             | ((uint64_t)b->data[ob0 + 1] << 8)
			                             | ((uint64_t)b->data[ob0 + 2] << 16)
			                             | ((uint64_t)b->data[ob0 + 3] << 24)
			                             | ((uint64_t)b->data[ob0 + 4] << 32)
			                             | ((uint64_t)b->data[ob0 + 5] << 40)
			                             | ((uint64_t)b->data[ob0 + 6] << 48)
			                             | ((uint64_t)b->data[ob0 + 7] << 56);
			                        ub1 = (uint64_t)b->data[ob1]
			                             | ((uint64_t)b->data[ob1 + 1] << 8)
			                             | ((uint64_t)b->data[ob1 + 2] << 16)
			                             | ((uint64_t)b->data[ob1 + 3] << 24)
			                             | ((uint64_t)b->data[ob1 + 4] << 32)
			                             | ((uint64_t)b->data[ob1 + 5] << 40)
			                             | ((uint64_t)b->data[ob1 + 6] << 48)
			                             | ((uint64_t)b->data[ob1 + 7] << 56);
			                        ub2 = (uint64_t)b->data[ob2]
			                             | ((uint64_t)b->data[ob2 + 1] << 8)
			                             | ((uint64_t)b->data[ob2 + 2] << 16)
			                             | ((uint64_t)b->data[ob2 + 3] << 24)
			                             | ((uint64_t)b->data[ob2 + 4] << 32)
			                             | ((uint64_t)b->data[ob2 + 5] << 40)
			                             | ((uint64_t)b->data[ob2 + 6] << 48)
			                             | ((uint64_t)b->data[ob2 + 7] << 56);
			                        ub3 = (uint64_t)b->data[ob3]
			                             | ((uint64_t)b->data[ob3 + 1] << 8)
			                             | ((uint64_t)b->data[ob3 + 2] << 16)
			                             | ((uint64_t)b->data[ob3 + 3] << 24)
			                             | ((uint64_t)b->data[ob3 + 4] << 32)
			                             | ((uint64_t)b->data[ob3 + 5] << 40)
			                             | ((uint64_t)b->data[ob3 + 6] << 48)
			                             | ((uint64_t)b->data[ob3 + 7] << 56);

			                        double a0v = 0.0, a1v = 0.0, a2v = 0.0, a3v = 0.0;
			                        double b0v = 0.0, b1v = 0.0, b2v = 0.0, b3v = 0.0;
			                        memcpy(&a0v, &ua0, 8); memcpy(&a1v, &ua1, 8); memcpy(&a2v, &ua2, 8); memcpy(&a3v, &ua3, 8);
			                        memcpy(&b0v, &ub0, 8); memcpy(&b1v, &ub1, 8); memcpy(&b2v, &ub2, 8); memcpy(&b3v, &ub3, 8);

			                        c00 += a0v * b0v; c01 += a0v * b1v; c02 += a0v * b2v; c03 += a0v * b3v;
			                        c10 += a1v * b0v; c11 += a1v * b1v; c12 += a1v * b2v; c13 += a1v * b3v;
			                        c20 += a2v * b0v; c21 += a2v * b1v; c22 += a2v * b2v; c23 += a2v * b3v;
			                        c30 += a3v * b0v; c31 += a3v * b1v; c32 += a3v * b2v; c33 += a3v * b3v;
			                    }
			                } else
			#endif
			                {
			                    for (uint32_t i = 0; i < n; i++) {
			                        uint32_t oa0 = (a0_off + i) * 8u;
			                        uint32_t oa1 = (a1_off + i) * 8u;
			                        uint32_t oa2 = (a2_off + i) * 8u;
			                        uint32_t oa3 = (a3_off + i) * 8u;
			                        uint32_t ob0 = (b0_off + i) * 8u;
			                        uint32_t ob1 = (b1_off + i) * 8u;
			                        uint32_t ob2 = (b2_off + i) * 8u;
			                        uint32_t ob3 = (b3_off + i) * 8u;
			
			                        uint64_t ua0 = (uint64_t)a->data[oa0]
			                                     | ((uint64_t)a->data[oa0 + 1] << 8)
			                                     | ((uint64_t)a->data[oa0 + 2] << 16)
			                                     | ((uint64_t)a->data[oa0 + 3] << 24)
			                                     | ((uint64_t)a->data[oa0 + 4] << 32)
			                                     | ((uint64_t)a->data[oa0 + 5] << 40)
			                                     | ((uint64_t)a->data[oa0 + 6] << 48)
			                                     | ((uint64_t)a->data[oa0 + 7] << 56);
			                        uint64_t ua1 = (uint64_t)a->data[oa1]
			                                     | ((uint64_t)a->data[oa1 + 1] << 8)
			                                     | ((uint64_t)a->data[oa1 + 2] << 16)
			                                     | ((uint64_t)a->data[oa1 + 3] << 24)
			                                     | ((uint64_t)a->data[oa1 + 4] << 32)
			                                     | ((uint64_t)a->data[oa1 + 5] << 40)
			                                     | ((uint64_t)a->data[oa1 + 6] << 48)
			                                     | ((uint64_t)a->data[oa1 + 7] << 56);
			                        uint64_t ua2 = (uint64_t)a->data[oa2]
			                                     | ((uint64_t)a->data[oa2 + 1] << 8)
			                                     | ((uint64_t)a->data[oa2 + 2] << 16)
			                                     | ((uint64_t)a->data[oa2 + 3] << 24)
			                                     | ((uint64_t)a->data[oa2 + 4] << 32)
			                                     | ((uint64_t)a->data[oa2 + 5] << 40)
			                                     | ((uint64_t)a->data[oa2 + 6] << 48)
			                                     | ((uint64_t)a->data[oa2 + 7] << 56);
			                        uint64_t ua3 = (uint64_t)a->data[oa3]
			                                     | ((uint64_t)a->data[oa3 + 1] << 8)
			                                     | ((uint64_t)a->data[oa3 + 2] << 16)
			                                     | ((uint64_t)a->data[oa3 + 3] << 24)
			                                     | ((uint64_t)a->data[oa3 + 4] << 32)
			                                     | ((uint64_t)a->data[oa3 + 5] << 40)
			                                     | ((uint64_t)a->data[oa3 + 6] << 48)
			                                     | ((uint64_t)a->data[oa3 + 7] << 56);
			                        uint64_t ub0 = (uint64_t)b->data[ob0]
			                                     | ((uint64_t)b->data[ob0 + 1] << 8)
			                                     | ((uint64_t)b->data[ob0 + 2] << 16)
			                                     | ((uint64_t)b->data[ob0 + 3] << 24)
			                                     | ((uint64_t)b->data[ob0 + 4] << 32)
			                                     | ((uint64_t)b->data[ob0 + 5] << 40)
			                                     | ((uint64_t)b->data[ob0 + 6] << 48)
			                                     | ((uint64_t)b->data[ob0 + 7] << 56);
			                        uint64_t ub1 = (uint64_t)b->data[ob1]
			                                     | ((uint64_t)b->data[ob1 + 1] << 8)
			                                     | ((uint64_t)b->data[ob1 + 2] << 16)
			                                     | ((uint64_t)b->data[ob1 + 3] << 24)
			                                     | ((uint64_t)b->data[ob1 + 4] << 32)
			                                     | ((uint64_t)b->data[ob1 + 5] << 40)
			                                     | ((uint64_t)b->data[ob1 + 6] << 48)
			                                     | ((uint64_t)b->data[ob1 + 7] << 56);
			                        uint64_t ub2 = (uint64_t)b->data[ob2]
			                                     | ((uint64_t)b->data[ob2 + 1] << 8)
			                                     | ((uint64_t)b->data[ob2 + 2] << 16)
			                                     | ((uint64_t)b->data[ob2 + 3] << 24)
			                                     | ((uint64_t)b->data[ob2 + 4] << 32)
			                                     | ((uint64_t)b->data[ob2 + 5] << 40)
			                                     | ((uint64_t)b->data[ob2 + 6] << 48)
			                                     | ((uint64_t)b->data[ob2 + 7] << 56);
			                        uint64_t ub3 = (uint64_t)b->data[ob3]
			                                     | ((uint64_t)b->data[ob3 + 1] << 8)
			                                     | ((uint64_t)b->data[ob3 + 2] << 16)
			                                     | ((uint64_t)b->data[ob3 + 3] << 24)
			                                     | ((uint64_t)b->data[ob3 + 4] << 32)
			                                     | ((uint64_t)b->data[ob3 + 5] << 40)
			                                     | ((uint64_t)b->data[ob3 + 6] << 48)
			                                     | ((uint64_t)b->data[ob3 + 7] << 56);
			
			                        double a0v = 0.0, a1v = 0.0, a2v = 0.0, a3v = 0.0;
			                        double b0v = 0.0, b1v = 0.0, b2v = 0.0, b3v = 0.0;
			                        memcpy(&a0v, &ua0, 8); memcpy(&a1v, &ua1, 8); memcpy(&a2v, &ua2, 8); memcpy(&a3v, &ua3, 8);
			                        memcpy(&b0v, &ub0, 8); memcpy(&b1v, &ub1, 8); memcpy(&b2v, &ub2, 8); memcpy(&b3v, &ub3, 8);
			
			                        c00 += a0v * b0v; c01 += a0v * b1v; c02 += a0v * b2v; c03 += a0v * b3v;
			                        c10 += a1v * b0v; c11 += a1v * b1v; c12 += a1v * b2v; c13 += a1v * b3v;
			                        c20 += a2v * b0v; c21 += a2v * b1v; c22 += a2v * b2v; c23 += a2v * b3v;
			                        c30 += a3v * b0v; c31 += a3v * b1v; c32 += a3v * b2v; c33 += a3v * b3v;
			                    }
			                }
			
			                uint64_t u[16] = {0};
			                memcpy(&u[0], &c00, 8); memcpy(&u[1], &c01, 8); memcpy(&u[2], &c02, 8); memcpy(&u[3], &c03, 8);
			                memcpy(&u[4], &c10, 8); memcpy(&u[5], &c11, 8); memcpy(&u[6], &c12, 8); memcpy(&u[7], &c13, 8);
			                memcpy(&u[8], &c20, 8); memcpy(&u[9], &c21, 8); memcpy(&u[10], &c22, 8); memcpy(&u[11], &c23, 8);
			                memcpy(&u[12], &c30, 8); memcpy(&u[13], &c31, 8); memcpy(&u[14], &c32, 8); memcpy(&u[15], &c33, 8);
			
			                for (uint32_t j = 0; j < 16u; j++) {
			                    uint64_t uj = u[j];
			                    uint32_t oj = (out_off + j) * 8u;
			                    out->data[oj + 0] = (uint8_t)(uj & 0xFFu);
			                    out->data[oj + 1] = (uint8_t)((uj >> 8) & 0xFFu);
			                    out->data[oj + 2] = (uint8_t)((uj >> 16) & 0xFFu);
			                    out->data[oj + 3] = (uint8_t)((uj >> 24) & 0xFFu);
			                    out->data[oj + 4] = (uint8_t)((uj >> 32) & 0xFFu);
			                    out->data[oj + 5] = (uint8_t)((uj >> 40) & 0xFFu);
			                    out->data[oj + 6] = (uint8_t)((uj >> 48) & 0xFFu);
			                    out->data[oj + 7] = (uint8_t)((uj >> 56) & 0xFFu);
			                }
			
			                res = args[0];
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_gemm_f64_4x4_slice_into expects (f64_buf,int,f64_buf,int,int,int,int,f64_buf,int,int,int,int,int)");
			            }
			            break;
			        }

