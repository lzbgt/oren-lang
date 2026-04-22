			        case 132: { // oren_buf_dot_f64(a:f64_buf, b:f64_buf) -> float
			            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF) {
			                AvmBuf* a = args[0].as.buf;
			                AvmBuf* b = args[1].as.buf;
			                if (!a || !b || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64: invalid buffers"); break; }
			                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64: length mismatch"); break; }

			                // Determinism hardening:
			                // - Accumulate in double (fixed element order).
			                // - FP contraction is disabled at TU level in avm_native.c.
			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && a->len >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= a->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2], wb[2];
			                        memcpy(wa, a->data + off, 16);
			                        memcpy(wb, b->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t p = vmulq_f64(va, vb);
			                        // lane-ordered accumulation matches scalar i,i+1
			                        acc += vgetq_lane_f64(p, 0);
			                        acc += vgetq_lane_f64(p, 1);
			                    }
			                    for (; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                }
			                res.type = AVM_VAL_FLOAT;
			                res.as.f = acc;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f64 expects (f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 133: { // oren_buf_dot_f64_slice(a:f64_buf, a_off:int, b:f64_buf, b_off:int, n:int) -> float
			            if (nargs > 4 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_F64_BUF && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT) {
			                AvmBuf* a = args[0].as.buf;
			                AvmBuf* b = args[2].as.buf;
			                int64_t a_off_ll = args[1].as.i;
			                int64_t b_off_ll = args[3].as.i;
			                int64_t n_ll = args[4].as.i;
			                if (!a || !b || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_slice: invalid buffers"); break; }
			                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_slice: negative arg"); break; }
			                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_slice: offset out of bounds"); break; }
			                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_slice: a range out of bounds"); break; }
			                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_slice: b range out of bounds"); break; }

			                uint32_t a_off = (uint32_t)a_off_ll;
			                uint32_t b_off = (uint32_t)b_off_ll;
			                uint32_t n = (uint32_t)n_ll;
			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && n >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= n; i += 2u) {
			                        uint32_t offa = (a_off + i) * 8u;
			                        uint32_t offb = (b_off + i) * 8u;
			                        uint64_t wa[2], wb[2];
			                        memcpy(wa, a->data + offa, 16);
			                        memcpy(wb, b->data + offb, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t p = vmulq_f64(va, vb);
			                        acc += vgetq_lane_f64(p, 0);
			                        acc += vgetq_lane_f64(p, 1);
			                    }
			                    for (; i < n; i++) {
			                        uint32_t offa = (a_off + i) * 8u;
			                        uint32_t offb = (b_off + i) * 8u;
			                        uint64_t ua = (uint64_t)a->data[offa]
			                                   | ((uint64_t)a->data[offa + 1] << 8)
			                                   | ((uint64_t)a->data[offa + 2] << 16)
			                                   | ((uint64_t)a->data[offa + 3] << 24)
			                                   | ((uint64_t)a->data[offa + 4] << 32)
			                                   | ((uint64_t)a->data[offa + 5] << 40)
			                                   | ((uint64_t)a->data[offa + 6] << 48)
			                                   | ((uint64_t)a->data[offa + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[offb]
			                                   | ((uint64_t)b->data[offb + 1] << 8)
			                                   | ((uint64_t)b->data[offb + 2] << 16)
			                                   | ((uint64_t)b->data[offb + 3] << 24)
			                                   | ((uint64_t)b->data[offb + 4] << 32)
			                                   | ((uint64_t)b->data[offb + 5] << 40)
			                                   | ((uint64_t)b->data[offb + 6] << 48)
			                                   | ((uint64_t)b->data[offb + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                } else
#endif
			                for (uint32_t i = 0; i < n; i++) {
			                    uint32_t offa = (a_off + i) * 8u;
			                    uint32_t offb = (b_off + i) * 8u;
			                    uint64_t ua = (uint64_t)a->data[offa]
			                               | ((uint64_t)a->data[offa + 1] << 8)
			                               | ((uint64_t)a->data[offa + 2] << 16)
			                               | ((uint64_t)a->data[offa + 3] << 24)
			                               | ((uint64_t)a->data[offa + 4] << 32)
			                               | ((uint64_t)a->data[offa + 5] << 40)
			                               | ((uint64_t)a->data[offa + 6] << 48)
			                               | ((uint64_t)a->data[offa + 7] << 56);
			                    uint64_t ub = (uint64_t)b->data[offb]
			                               | ((uint64_t)b->data[offb + 1] << 8)
			                               | ((uint64_t)b->data[offb + 2] << 16)
			                               | ((uint64_t)b->data[offb + 3] << 24)
			                               | ((uint64_t)b->data[offb + 4] << 32)
			                               | ((uint64_t)b->data[offb + 5] << 40)
			                               | ((uint64_t)b->data[offb + 6] << 48)
			                               | ((uint64_t)b->data[offb + 7] << 56);
			                    double da = 0.0, dbv = 0.0;
			                    memcpy(&da, &ua, 8);
			                    memcpy(&dbv, &ub, 8);
			                    acc += da * dbv;
			                }
			                res.type = AVM_VAL_FLOAT;
			                res.as.f = acc;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f64_slice expects (f64_buf, int, f64_buf, int, int)");
			            }
			            break;
			        }

			        case 134: { // oren_buf_dot_f64_strided(a:f64_buf, a_off:int, a_stride:int, b:f64_buf, b_off:int, b_stride:int, n:int) -> float
			            if (nargs > 6
			                && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT
			                && args[3].type == AVM_VAL_F64_BUF && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT
			                && args[6].type == AVM_VAL_INT) {
			                AvmBuf* a = args[0].as.buf;
			                AvmBuf* b = args[3].as.buf;
			                int64_t a_off_ll = args[1].as.i;
			                int64_t a_stride_ll = args[2].as.i;
			                int64_t b_off_ll = args[4].as.i;
			                int64_t b_stride_ll = args[5].as.i;
			                int64_t n_ll = args[6].as.i;
			                if (!a || !b || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: invalid buffers"); break; }
			                if (a_off_ll < 0 || b_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: negative arg"); break; }
			                if (a_stride_ll <= 0 || b_stride_ll <= 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: stride must be > 0"); break; }
			                if ((uint64_t)a_off_ll > (uint64_t)a->len || (uint64_t)b_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: offset out of bounds"); break; }
			                if (n_ll > 0) {
			                    uint64_t alast = (uint64_t)a_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)a_stride_ll;
			                    uint64_t blast = (uint64_t)b_off_ll + (uint64_t)(n_ll - 1) * (uint64_t)b_stride_ll;
			                    if (alast >= (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: a range out of bounds"); break; }
			                    if (blast >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_strided: b range out of bounds"); break; }
			                }
			                uint32_t a_off = (uint32_t)a_off_ll;
			                uint32_t b_off = (uint32_t)b_off_ll;
			                uint32_t a_stride = (uint32_t)a_stride_ll;
			                uint32_t b_stride = (uint32_t)b_stride_ll;
			                uint32_t n = (uint32_t)n_ll;

			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && a_stride == 1u && b_stride == 1u && n >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= n; i += 2u) {
			                        uint32_t offa = (a_off + i) * 8u;
			                        uint32_t offb = (b_off + i) * 8u;
			                        uint64_t wa[2], wb[2];
			                        memcpy(wa, a->data + offa, 16);
			                        memcpy(wb, b->data + offb, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t p = vmulq_f64(va, vb);
			                        acc += vgetq_lane_f64(p, 0);
			                        acc += vgetq_lane_f64(p, 1);
			                    }
			                    for (; i < n; i++) {
			                        uint32_t ai = a_off + i;
			                        uint32_t bi = b_off + i;
			                        uint32_t offa = ai * 8u;
			                        uint32_t offb = bi * 8u;
			                        uint64_t ua = (uint64_t)a->data[offa]
			                                   | ((uint64_t)a->data[offa + 1] << 8)
			                                   | ((uint64_t)a->data[offa + 2] << 16)
			                                   | ((uint64_t)a->data[offa + 3] << 24)
			                                   | ((uint64_t)a->data[offa + 4] << 32)
			                                   | ((uint64_t)a->data[offa + 5] << 40)
			                                   | ((uint64_t)a->data[offa + 6] << 48)
			                                   | ((uint64_t)a->data[offa + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[offb]
			                                   | ((uint64_t)b->data[offb + 1] << 8)
			                                   | ((uint64_t)b->data[offb + 2] << 16)
			                                   | ((uint64_t)b->data[offb + 3] << 24)
			                                   | ((uint64_t)b->data[offb + 4] << 32)
			                                   | ((uint64_t)b->data[offb + 5] << 40)
			                                   | ((uint64_t)b->data[offb + 6] << 48)
			                                   | ((uint64_t)b->data[offb + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                } else
#endif
			                for (uint32_t i = 0; i < n; i++) {
			                    uint32_t ai = a_off + i * a_stride;
			                    uint32_t bi = b_off + i * b_stride;
			                    uint32_t offa = ai * 8u;
			                    uint32_t offb = bi * 8u;
			                    uint64_t ua = (uint64_t)a->data[offa]
			                               | ((uint64_t)a->data[offa + 1] << 8)
			                               | ((uint64_t)a->data[offa + 2] << 16)
			                               | ((uint64_t)a->data[offa + 3] << 24)
			                               | ((uint64_t)a->data[offa + 4] << 32)
			                               | ((uint64_t)a->data[offa + 5] << 40)
			                               | ((uint64_t)a->data[offa + 6] << 48)
			                               | ((uint64_t)a->data[offa + 7] << 56);
			                    uint64_t ub = (uint64_t)b->data[offb]
			                               | ((uint64_t)b->data[offb + 1] << 8)
			                               | ((uint64_t)b->data[offb + 2] << 16)
			                               | ((uint64_t)b->data[offb + 3] << 24)
			                               | ((uint64_t)b->data[offb + 4] << 32)
			                               | ((uint64_t)b->data[offb + 5] << 40)
			                               | ((uint64_t)b->data[offb + 6] << 48)
			                               | ((uint64_t)b->data[offb + 7] << 56);
			                    double da = 0.0, dbv = 0.0;
			                    memcpy(&da, &ua, 8);
			                    memcpy(&dbv, &ub, 8);
			                    acc += da * dbv;
			                }
			                res.type = AVM_VAL_FLOAT;
			                res.as.f = acc;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f64_strided expects (f64_buf,int,int,f64_buf,int,int,int)");
			            }
			            break;
			        }

			        case 135: { // oren_buf_reduce_sum_f64(a:f64_buf) -> float
			            if (nargs > 0 && args[0].type == AVM_VAL_F64_BUF) {
			                AvmBuf* a = args[0].as.buf;
			                if (!a || a->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f64: invalid buffer"); break; }
			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && a->len >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= a->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2];
			                        memcpy(wa, a->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        acc += vgetq_lane_f64(va, 0);
			                        acc += vgetq_lane_f64(va, 1);
			                    }
			                    for (; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        double da = 0.0;
			                        memcpy(&da, &ua, 8);
			                        acc += da;
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        double da = 0.0;
			                        memcpy(&da, &ua, 8);
			                        acc += da;
			                    }
			                }
			                res.type = AVM_VAL_FLOAT;
			                res.as.f = acc;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_f64 expects (f64_buf)");
			            }
			            break;
			        }

			        case 136: { // oren_buf_dot_f64_into(out:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
			            if (nargs > 2 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF && args[2].type == AVM_VAL_F64_BUF) {
			                AvmBuf* out = args[0].as.buf;
			                AvmBuf* a = args[1].as.buf;
			                AvmBuf* b = args[2].as.buf;
			                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_into: invalid buffers"); break; }
			                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_into: out len < 1"); break; }
			                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f64_into: length mismatch"); break; }
			                // Inline: compute acc then store at out[0] as f64 bits.
			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && a->len >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= a->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2], wb[2];
			                        memcpy(wa, a->data + off, 16);
			                        memcpy(wb, b->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t p = vmulq_f64(va, vb);
			                        acc += vgetq_lane_f64(p, 0);
			                        acc += vgetq_lane_f64(p, 1);
			                    }
			                    for (; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        acc += da * dbv;
			                    }
			                }

			                uint64_t u = 0;
			                memcpy(&u, &acc, 8);
			                out->data[0] = (uint8_t)(u & 0xFFu);
			                out->data[1] = (uint8_t)((u >> 8) & 0xFFu);
			                out->data[2] = (uint8_t)((u >> 16) & 0xFFu);
			                out->data[3] = (uint8_t)((u >> 24) & 0xFFu);
			                out->data[4] = (uint8_t)((u >> 32) & 0xFFu);
			                out->data[5] = (uint8_t)((u >> 40) & 0xFFu);
			                out->data[6] = (uint8_t)((u >> 48) & 0xFFu);
			                out->data[7] = (uint8_t)((u >> 56) & 0xFFu);
			                res = args[0];
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f64_into expects (f64_buf, f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 137: { // oren_buf_reduce_sum_f64_into(out:f64_buf, a:f64_buf) -> f64_buf
			            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF) {
			                AvmBuf* out = args[0].as.buf;
			                AvmBuf* a = args[1].as.buf;
			                if (!out || !a || out->elem_size != 8u || a->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f64_into: invalid buffers"); break; }
			                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f64_into: out len < 1"); break; }
			                double acc = 0.0;
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd && a->len >= 2u) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= a->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2];
			                        memcpy(wa, a->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        acc += vgetq_lane_f64(va, 0);
			                        acc += vgetq_lane_f64(va, 1);
			                    }
			                    for (; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        double da = 0.0;
			                        memcpy(&da, &ua, 8);
			                        acc += da;
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < a->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        double da = 0.0;
			                        memcpy(&da, &ua, 8);
			                        acc += da;
			                    }
			                }
			                uint64_t u = 0;
			                memcpy(&u, &acc, 8);
			                out->data[0] = (uint8_t)(u & 0xFFu);
			                out->data[1] = (uint8_t)((u >> 8) & 0xFFu);
			                out->data[2] = (uint8_t)((u >> 16) & 0xFFu);
			                out->data[3] = (uint8_t)((u >> 24) & 0xFFu);
			                out->data[4] = (uint8_t)((u >> 32) & 0xFFu);
			                out->data[5] = (uint8_t)((u >> 40) & 0xFFu);
			                out->data[6] = (uint8_t)((u >> 48) & 0xFFu);
			                out->data[7] = (uint8_t)((u >> 56) & 0xFFu);
			                res = args[0];
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_f64_into expects (f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 138: { // oren_buf_add_f64(a:f64_buf, b:f64_buf) -> f64_buf
			            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF) {
			                AvmBuf* a = args[0].as.buf;
			                AvmBuf* b = args[1].as.buf;
			                if (!a || !b || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f64: invalid buffers"); break; }
			                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f64: length mismatch"); break; }
			                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
			                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
			                out->len = a->len;
			                out->elem_size = 8u;
			                uint64_t bytes_len = (uint64_t)out->len * 8ull;
			                out->data = NULL;
			                if (bytes_len > 0) {
			                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
			                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
			                }
			                // Reuse the in-place kernel semantics for determinism (fixed loop order).
			                AvmValue dstv; dstv.type = AVM_VAL_F64_BUF; dstv.as.buf = out;
			                AvmValue argv[3]; argv[0] = dstv; argv[1] = args[0]; argv[2] = args[1];
			                res = avm_call_native(vm, 139, argv, 3);
			                if (avm_is_err_val(res)) break;
			                res.type = AVM_VAL_F64_BUF;
			                res.as.buf = out;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_f64 expects (f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 139: { // oren_buf_add_f64_into(dst:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
			            if (nargs > 2 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF && args[2].type == AVM_VAL_F64_BUF) {
			                AvmBuf* dst = args[0].as.buf;
			                AvmBuf* a = args[1].as.buf;
			                AvmBuf* b = args[2].as.buf;
			                if (!dst || !a || !b || dst->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f64_into: invalid buffers"); break; }
			                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f64_into: length mismatch"); break; }
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= dst->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2], wb[2], wo[2];
			                        memcpy(wa, a->data + off, 16);
			                        memcpy(wb, b->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t vs = vaddq_f64(va, vb);
			                        uint64x2_t vo_u = vreinterpretq_u64_f64(vs);
			                        vst1q_u64(wo, vo_u);
			                        memcpy(dst->data + off, wo, 16);
			                    }
			                    for (; i < dst->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        double ds = da + dbv;
			                        uint64_t us = 0;
			                        memcpy(&us, &ds, 8);
			                        dst->data[off + 0] = (uint8_t)(us & 0xFFu);
			                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
			                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
			                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
			                        dst->data[off + 4] = (uint8_t)((us >> 32) & 0xFFu);
			                        dst->data[off + 5] = (uint8_t)((us >> 40) & 0xFFu);
			                        dst->data[off + 6] = (uint8_t)((us >> 48) & 0xFFu);
			                        dst->data[off + 7] = (uint8_t)((us >> 56) & 0xFFu);
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < dst->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        double ds = da + dbv;
			                        uint64_t us = 0;
			                        memcpy(&us, &ds, 8);
			                        dst->data[off + 0] = (uint8_t)(us & 0xFFu);
			                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
			                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
			                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
			                        dst->data[off + 4] = (uint8_t)((us >> 32) & 0xFFu);
			                        dst->data[off + 5] = (uint8_t)((us >> 40) & 0xFFu);
			                        dst->data[off + 6] = (uint8_t)((us >> 48) & 0xFFu);
			                        dst->data[off + 7] = (uint8_t)((us >> 56) & 0xFFu);
			                    }
			                }
			                res = args[0];
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_f64_into expects (f64_buf, f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 140: { // oren_buf_mul_f64_into(dst:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
			            if (nargs > 2 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF && args[2].type == AVM_VAL_F64_BUF) {
			                AvmBuf* dst = args[0].as.buf;
			                AvmBuf* a = args[1].as.buf;
			                AvmBuf* b = args[2].as.buf;
			                if (!dst || !a || !b || dst->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f64_into: invalid buffers"); break; }
			                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f64_into: length mismatch"); break; }
#if AVM_HAS_NEON
			                if (vm && vm->enable_simd) {
			                    uint32_t i = 0;
			                    for (; i + 2u <= dst->len; i += 2u) {
			                        uint32_t off = i * 8u;
			                        uint64_t wa[2], wb[2], wo[2];
			                        memcpy(wa, a->data + off, 16);
			                        memcpy(wb, b->data + off, 16);
			                        float64x2_t va = vreinterpretq_f64_u64(vld1q_u64(wa));
			                        float64x2_t vb = vreinterpretq_f64_u64(vld1q_u64(wb));
			                        float64x2_t vp = vmulq_f64(va, vb);
			                        uint64x2_t vo_u = vreinterpretq_u64_f64(vp);
			                        vst1q_u64(wo, vo_u);
			                        memcpy(dst->data + off, wo, 16);
			                    }
			                    for (; i < dst->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        double dp = da * dbv;
			                        uint64_t up = 0;
			                        memcpy(&up, &dp, 8);
			                        dst->data[off + 0] = (uint8_t)(up & 0xFFu);
			                        dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
			                        dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
			                        dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
			                        dst->data[off + 4] = (uint8_t)((up >> 32) & 0xFFu);
			                        dst->data[off + 5] = (uint8_t)((up >> 40) & 0xFFu);
			                        dst->data[off + 6] = (uint8_t)((up >> 48) & 0xFFu);
			                        dst->data[off + 7] = (uint8_t)((up >> 56) & 0xFFu);
			                    }
			                } else
#endif
			                {
			                    for (uint32_t i = 0; i < dst->len; i++) {
			                        uint32_t off = i * 8u;
			                        uint64_t ua = (uint64_t)a->data[off]
			                                   | ((uint64_t)a->data[off + 1] << 8)
			                                   | ((uint64_t)a->data[off + 2] << 16)
			                                   | ((uint64_t)a->data[off + 3] << 24)
			                                   | ((uint64_t)a->data[off + 4] << 32)
			                                   | ((uint64_t)a->data[off + 5] << 40)
			                                   | ((uint64_t)a->data[off + 6] << 48)
			                                   | ((uint64_t)a->data[off + 7] << 56);
			                        uint64_t ub = (uint64_t)b->data[off]
			                                   | ((uint64_t)b->data[off + 1] << 8)
			                                   | ((uint64_t)b->data[off + 2] << 16)
			                                   | ((uint64_t)b->data[off + 3] << 24)
			                                   | ((uint64_t)b->data[off + 4] << 32)
			                                   | ((uint64_t)b->data[off + 5] << 40)
			                                   | ((uint64_t)b->data[off + 6] << 48)
			                                   | ((uint64_t)b->data[off + 7] << 56);
			                        double da = 0.0, dbv = 0.0;
			                        memcpy(&da, &ua, 8);
			                        memcpy(&dbv, &ub, 8);
			                        double dp = da * dbv;
			                        uint64_t up = 0;
			                        memcpy(&up, &dp, 8);
			                        dst->data[off + 0] = (uint8_t)(up & 0xFFu);
			                        dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
			                        dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
			                        dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
			                        dst->data[off + 4] = (uint8_t)((up >> 32) & 0xFFu);
			                        dst->data[off + 5] = (uint8_t)((up >> 40) & 0xFFu);
			                        dst->data[off + 6] = (uint8_t)((up >> 48) & 0xFFu);
			                        dst->data[off + 7] = (uint8_t)((up >> 56) & 0xFFu);
			                    }
			                }
			                res = args[0];
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_f64_into expects (f64_buf, f64_buf, f64_buf)");
			            }
			            break;
			        }

			        case 141: { // oren_buf_mul_f64(a:f64_buf, b:f64_buf) -> f64_buf
			            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F64_BUF) {
			                AvmBuf* a = args[0].as.buf;
			                AvmBuf* b = args[1].as.buf;
			                if (!a || !b || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f64: invalid buffers"); break; }
			                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f64: length mismatch"); break; }
			                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
			                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
			                out->len = a->len;
			                out->elem_size = 8u;
			                uint64_t bytes_len = (uint64_t)out->len * 8ull;
			                out->data = NULL;
			                if (bytes_len > 0) {
			                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
			                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
			                }
			                // Reuse the in-place kernel semantics for determinism (fixed loop order).
			                AvmValue dstv; dstv.type = AVM_VAL_F64_BUF; dstv.as.buf = out;
			                AvmValue argv[3]; argv[0] = dstv; argv[1] = args[0]; argv[2] = args[1];
			                res = avm_call_native(vm, 140, argv, 3);
			                if (avm_is_err_val(res)) break;
			                res.type = AVM_VAL_F64_BUF;
			                res.as.buf = out;
			            } else {
			                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_f64 expects (f64_buf, f64_buf)");
			            }
			            break;
			        }
			        case 128: { // oren_buf_gemm_f32_4x4_slice_into(out:f64_buf, out_off:int, a:f32_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:f32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
			            if (nargs > 12
			                && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT
			                && args[2].type == AVM_VAL_F32_BUF
	                && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT
	                && args[7].type == AVM_VAL_F32_BUF
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
	                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: invalid buffers"); break; }
	                if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: negative arg"); break; }
	                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 16u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: out range out of bounds"); break; }
	                if ((uint64_t)a0_off_ll > (uint64_t)a->len || (uint64_t)a1_off_ll > (uint64_t)a->len || (uint64_t)a2_off_ll > (uint64_t)a->len || (uint64_t)a3_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: a_off out of bounds"); break; }
	                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a0_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a1_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a2_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: a range out of bounds"); break; }
	                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: b_off out of bounds"); break; }
	                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_f32_4x4_slice_into: b range out of bounds"); break; }

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

	                uint32_t i = 0;
#if AVM_HAS_NEON
	                // Optional SIMD (arm64 NEON) fast path.
	                //
	                // Determinism rule:
	                // - We must match scalar exactly.
	                // - Scalar semantics are: load f32 bits -> float -> cast to double -> multiply in double -> accumulate in strict i order.
	                // - Here, we process i in blocks of 2, but we still add lane0 then lane1 so the total accumulation order is identical.
	                if (vm && vm->enable_simd && n >= 2) {
	                    for (; i + 1 < n; i += 2) {
	                        uint32_t a0_bits[2] = {0}, a1_bits[2] = {0}, a2_bits[2] = {0}, a3_bits[2] = {0};
	                        uint32_t b0_bits[2] = {0}, b1_bits[2] = {0}, b2_bits[2] = {0}, b3_bits[2] = {0};

	                        memcpy(a0_bits, a->data + (a0_off + i) * 4u, 8);
	                        memcpy(a1_bits, a->data + (a1_off + i) * 4u, 8);
	                        memcpy(a2_bits, a->data + (a2_off + i) * 4u, 8);
	                        memcpy(a3_bits, a->data + (a3_off + i) * 4u, 8);
	                        memcpy(b0_bits, b->data + (b0_off + i) * 4u, 8);
	                        memcpy(b1_bits, b->data + (b1_off + i) * 4u, 8);
	                        memcpy(b2_bits, b->data + (b2_off + i) * 4u, 8);
	                        memcpy(b3_bits, b->data + (b3_off + i) * 4u, 8);

	                        float32x2_t fa0 = vreinterpret_f32_u32(vld1_u32(a0_bits));
	                        float32x2_t fa1 = vreinterpret_f32_u32(vld1_u32(a1_bits));
	                        float32x2_t fa2 = vreinterpret_f32_u32(vld1_u32(a2_bits));
	                        float32x2_t fa3 = vreinterpret_f32_u32(vld1_u32(a3_bits));
	                        float32x2_t fb0 = vreinterpret_f32_u32(vld1_u32(b0_bits));
	                        float32x2_t fb1 = vreinterpret_f32_u32(vld1_u32(b1_bits));
	                        float32x2_t fb2 = vreinterpret_f32_u32(vld1_u32(b2_bits));
	                        float32x2_t fb3 = vreinterpret_f32_u32(vld1_u32(b3_bits));

	                        float64x2_t da0 = vcvt_f64_f32(fa0);
	                        float64x2_t da1 = vcvt_f64_f32(fa1);
	                        float64x2_t da2 = vcvt_f64_f32(fa2);
	                        float64x2_t da3 = vcvt_f64_f32(fa3);
	                        float64x2_t db0 = vcvt_f64_f32(fb0);
	                        float64x2_t db1 = vcvt_f64_f32(fb1);
	                        float64x2_t db2 = vcvt_f64_f32(fb2);
	                        float64x2_t db3 = vcvt_f64_f32(fb3);

	                        float64x2_t p00 = vmulq_f64(da0, db0);
	                        float64x2_t p01 = vmulq_f64(da0, db1);
	                        float64x2_t p02 = vmulq_f64(da0, db2);
	                        float64x2_t p03 = vmulq_f64(da0, db3);
	                        float64x2_t p10 = vmulq_f64(da1, db0);
	                        float64x2_t p11 = vmulq_f64(da1, db1);
	                        float64x2_t p12 = vmulq_f64(da1, db2);
	                        float64x2_t p13 = vmulq_f64(da1, db3);
	                        float64x2_t p20 = vmulq_f64(da2, db0);
	                        float64x2_t p21 = vmulq_f64(da2, db1);
	                        float64x2_t p22 = vmulq_f64(da2, db2);
	                        float64x2_t p23 = vmulq_f64(da2, db3);
	                        float64x2_t p30 = vmulq_f64(da3, db0);
	                        float64x2_t p31 = vmulq_f64(da3, db1);
	                        float64x2_t p32 = vmulq_f64(da3, db2);
	                        float64x2_t p33 = vmulq_f64(da3, db3);

	                        c00 += vgetq_lane_f64(p00, 0); c00 += vgetq_lane_f64(p00, 1);
	                        c01 += vgetq_lane_f64(p01, 0); c01 += vgetq_lane_f64(p01, 1);
	                        c02 += vgetq_lane_f64(p02, 0); c02 += vgetq_lane_f64(p02, 1);
	                        c03 += vgetq_lane_f64(p03, 0); c03 += vgetq_lane_f64(p03, 1);
	                        c10 += vgetq_lane_f64(p10, 0); c10 += vgetq_lane_f64(p10, 1);
	                        c11 += vgetq_lane_f64(p11, 0); c11 += vgetq_lane_f64(p11, 1);
	                        c12 += vgetq_lane_f64(p12, 0); c12 += vgetq_lane_f64(p12, 1);
	                        c13 += vgetq_lane_f64(p13, 0); c13 += vgetq_lane_f64(p13, 1);
	                        c20 += vgetq_lane_f64(p20, 0); c20 += vgetq_lane_f64(p20, 1);
	                        c21 += vgetq_lane_f64(p21, 0); c21 += vgetq_lane_f64(p21, 1);
	                        c22 += vgetq_lane_f64(p22, 0); c22 += vgetq_lane_f64(p22, 1);
	                        c23 += vgetq_lane_f64(p23, 0); c23 += vgetq_lane_f64(p23, 1);
	                        c30 += vgetq_lane_f64(p30, 0); c30 += vgetq_lane_f64(p30, 1);
	                        c31 += vgetq_lane_f64(p31, 0); c31 += vgetq_lane_f64(p31, 1);
	                        c32 += vgetq_lane_f64(p32, 0); c32 += vgetq_lane_f64(p32, 1);
	                        c33 += vgetq_lane_f64(p33, 0); c33 += vgetq_lane_f64(p33, 1);
	                    }
	                }
#endif

	                for (; i < n; i++) {
	                    uint32_t oa0 = (a0_off + i) * 4u;
	                    uint32_t oa1 = (a1_off + i) * 4u;
	                    uint32_t oa2 = (a2_off + i) * 4u;
	                    uint32_t oa3 = (a3_off + i) * 4u;
	                    uint32_t ob0 = (b0_off + i) * 4u;
	                    uint32_t ob1 = (b1_off + i) * 4u;
	                    uint32_t ob2 = (b2_off + i) * 4u;
	                    uint32_t ob3 = (b3_off + i) * 4u;

	                    uint32_t ua0 = (uint32_t)a->data[oa0] | ((uint32_t)a->data[oa0 + 1] << 8) | ((uint32_t)a->data[oa0 + 2] << 16) | ((uint32_t)a->data[oa0 + 3] << 24);
	                    uint32_t ua1 = (uint32_t)a->data[oa1] | ((uint32_t)a->data[oa1 + 1] << 8) | ((uint32_t)a->data[oa1 + 2] << 16) | ((uint32_t)a->data[oa1 + 3] << 24);
	                    uint32_t ua2 = (uint32_t)a->data[oa2] | ((uint32_t)a->data[oa2 + 1] << 8) | ((uint32_t)a->data[oa2 + 2] << 16) | ((uint32_t)a->data[oa2 + 3] << 24);
	                    uint32_t ua3 = (uint32_t)a->data[oa3] | ((uint32_t)a->data[oa3 + 1] << 8) | ((uint32_t)a->data[oa3 + 2] << 16) | ((uint32_t)a->data[oa3 + 3] << 24);
	                    uint32_t ub0 = (uint32_t)b->data[ob0] | ((uint32_t)b->data[ob0 + 1] << 8) | ((uint32_t)b->data[ob0 + 2] << 16) | ((uint32_t)b->data[ob0 + 3] << 24);
	                    uint32_t ub1 = (uint32_t)b->data[ob1] | ((uint32_t)b->data[ob1 + 1] << 8) | ((uint32_t)b->data[ob1 + 2] << 16) | ((uint32_t)b->data[ob1 + 3] << 24);
	                    uint32_t ub2 = (uint32_t)b->data[ob2] | ((uint32_t)b->data[ob2 + 1] << 8) | ((uint32_t)b->data[ob2 + 2] << 16) | ((uint32_t)b->data[ob2 + 3] << 24);
	                    uint32_t ub3 = (uint32_t)b->data[ob3] | ((uint32_t)b->data[ob3 + 1] << 8) | ((uint32_t)b->data[ob3 + 2] << 16) | ((uint32_t)b->data[ob3 + 3] << 24);

	                    float fa0 = 0.0f, fa1 = 0.0f, fa2 = 0.0f, fa3 = 0.0f;
	                    float fb0 = 0.0f, fb1 = 0.0f, fb2 = 0.0f, fb3 = 0.0f;
	                    memcpy(&fa0, &ua0, sizeof(fa0));
	                    memcpy(&fa1, &ua1, sizeof(fa1));
	                    memcpy(&fa2, &ua2, sizeof(fa2));
	                    memcpy(&fa3, &ua3, sizeof(fa3));
	                    memcpy(&fb0, &ub0, sizeof(fb0));
	                    memcpy(&fb1, &ub1, sizeof(fb1));
	                    memcpy(&fb2, &ub2, sizeof(fb2));
	                    memcpy(&fb3, &ub3, sizeof(fb3));

	                    double da0 = (double)fa0, da1 = (double)fa1, da2 = (double)fa2, da3 = (double)fa3;
	                    double db0 = (double)fb0, db1 = (double)fb1, db2 = (double)fb2, db3 = (double)fb3;

	                    c00 += da0 * db0; c01 += da0 * db1; c02 += da0 * db2; c03 += da0 * db3;
	                    c10 += da1 * db0; c11 += da1 * db1; c12 += da1 * db2; c13 += da1 * db3;
	                    c20 += da2 * db0; c21 += da2 * db1; c22 += da2 * db2; c23 += da2 * db3;
	                    c30 += da3 * db0; c31 += da3 * db1; c32 += da3 * db2; c33 += da3 * db3;
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
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_gemm_f32_4x4_slice_into expects (f64_buf,int,f32_buf,int,int,int,int,f32_buf,int,int,int,int,int)");
	            }
	            break;
	        }
	        case 129: { // oren_buf_gemm_i32_4x4_slice_into(out:i64_buf, out_off:int, a:i32_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:i32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> i64_buf
	            if (nargs > 12
	                && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_INT
	                && args[2].type == AVM_VAL_I32_BUF
	                && args[3].type == AVM_VAL_INT && args[4].type == AVM_VAL_INT && args[5].type == AVM_VAL_INT && args[6].type == AVM_VAL_INT
	                && args[7].type == AVM_VAL_I32_BUF
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
	                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: invalid buffers"); break; }
	                if (out_off_ll < 0 || a0_off_ll < 0 || a1_off_ll < 0 || a2_off_ll < 0 || a3_off_ll < 0 || b0_off_ll < 0 || b1_off_ll < 0 || b2_off_ll < 0 || b3_off_ll < 0 || n_ll < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: negative arg"); break; }
	                if ((uint64_t)out_off_ll > (uint64_t)out->len || (uint64_t)out->len - (uint64_t)out_off_ll < 16u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: out range out of bounds"); break; }
	                if ((uint64_t)a0_off_ll > (uint64_t)a->len || (uint64_t)a1_off_ll > (uint64_t)a->len || (uint64_t)a2_off_ll > (uint64_t)a->len || (uint64_t)a3_off_ll > (uint64_t)a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: a_off out of bounds"); break; }
	                if ((uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a0_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a1_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a2_off_ll
	                    || (uint64_t)n_ll > (uint64_t)a->len - (uint64_t)a3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: a range out of bounds"); break; }
	                if ((uint64_t)b0_off_ll > (uint64_t)b->len || (uint64_t)b1_off_ll > (uint64_t)b->len || (uint64_t)b2_off_ll > (uint64_t)b->len || (uint64_t)b3_off_ll > (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: b_off out of bounds"); break; }
	                if ((uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b0_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b1_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b2_off_ll
	                    || (uint64_t)n_ll > (uint64_t)b->len - (uint64_t)b3_off_ll) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_gemm_i32_4x4_slice_into: b range out of bounds"); break; }

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

	                uint64_t c00 = 0, c01 = 0, c02 = 0, c03 = 0;
	                uint64_t c10 = 0, c11 = 0, c12 = 0, c13 = 0;
	                uint64_t c20 = 0, c21 = 0, c22 = 0, c23 = 0;
	                uint64_t c30 = 0, c31 = 0, c32 = 0, c33 = 0;

	                uint32_t i = 0;
#if AVM_HAS_NEON
	                // Optional SIMD (arm64 NEON) fast path.
	                //
	                // Determinism rule:
	                // - Scalar semantics are: load i32 -> sign-extend to i64 -> multiply -> cast to u64 -> accumulate in strict i order.
	                // - Here, we process i in blocks of 2, but we still add lane0 then lane1 so the total accumulation order is identical.
	                if (vm && vm->enable_simd && n >= 2) {
	                    for (; i + 1 < n; i += 2) {
	                        int32_t a0_i32[2] = {0}, a1_i32[2] = {0}, a2_i32[2] = {0}, a3_i32[2] = {0};
	                        int32_t b0_i32[2] = {0}, b1_i32[2] = {0}, b2_i32[2] = {0}, b3_i32[2] = {0};

	                        memcpy(a0_i32, a->data + (a0_off + i) * 4u, 8);
	                        memcpy(a1_i32, a->data + (a1_off + i) * 4u, 8);
	                        memcpy(a2_i32, a->data + (a2_off + i) * 4u, 8);
	                        memcpy(a3_i32, a->data + (a3_off + i) * 4u, 8);
	                        memcpy(b0_i32, b->data + (b0_off + i) * 4u, 8);
	                        memcpy(b1_i32, b->data + (b1_off + i) * 4u, 8);
	                        memcpy(b2_i32, b->data + (b2_off + i) * 4u, 8);
	                        memcpy(b3_i32, b->data + (b3_off + i) * 4u, 8);

	                        int32x2_t va0 = vld1_s32(a0_i32);
	                        int32x2_t va1 = vld1_s32(a1_i32);
	                        int32x2_t va2 = vld1_s32(a2_i32);
	                        int32x2_t va3 = vld1_s32(a3_i32);
	                        int32x2_t vb0 = vld1_s32(b0_i32);
	                        int32x2_t vb1 = vld1_s32(b1_i32);
	                        int32x2_t vb2 = vld1_s32(b2_i32);
	                        int32x2_t vb3 = vld1_s32(b3_i32);

	                        int64x2_t p00 = vmull_s32(va0, vb0);
	                        int64x2_t p01 = vmull_s32(va0, vb1);
	                        int64x2_t p02 = vmull_s32(va0, vb2);
	                        int64x2_t p03 = vmull_s32(va0, vb3);
	                        int64x2_t p10 = vmull_s32(va1, vb0);
	                        int64x2_t p11 = vmull_s32(va1, vb1);
	                        int64x2_t p12 = vmull_s32(va1, vb2);
	                        int64x2_t p13 = vmull_s32(va1, vb3);
	                        int64x2_t p20 = vmull_s32(va2, vb0);
	                        int64x2_t p21 = vmull_s32(va2, vb1);
	                        int64x2_t p22 = vmull_s32(va2, vb2);
	                        int64x2_t p23 = vmull_s32(va2, vb3);
	                        int64x2_t p30 = vmull_s32(va3, vb0);
	                        int64x2_t p31 = vmull_s32(va3, vb1);
	                        int64x2_t p32 = vmull_s32(va3, vb2);
	                        int64x2_t p33 = vmull_s32(va3, vb3);

	                        c00 += (uint64_t)vgetq_lane_s64(p00, 0); c00 += (uint64_t)vgetq_lane_s64(p00, 1);
	                        c01 += (uint64_t)vgetq_lane_s64(p01, 0); c01 += (uint64_t)vgetq_lane_s64(p01, 1);
	                        c02 += (uint64_t)vgetq_lane_s64(p02, 0); c02 += (uint64_t)vgetq_lane_s64(p02, 1);
	                        c03 += (uint64_t)vgetq_lane_s64(p03, 0); c03 += (uint64_t)vgetq_lane_s64(p03, 1);
	                        c10 += (uint64_t)vgetq_lane_s64(p10, 0); c10 += (uint64_t)vgetq_lane_s64(p10, 1);
	                        c11 += (uint64_t)vgetq_lane_s64(p11, 0); c11 += (uint64_t)vgetq_lane_s64(p11, 1);
	                        c12 += (uint64_t)vgetq_lane_s64(p12, 0); c12 += (uint64_t)vgetq_lane_s64(p12, 1);
	                        c13 += (uint64_t)vgetq_lane_s64(p13, 0); c13 += (uint64_t)vgetq_lane_s64(p13, 1);
	                        c20 += (uint64_t)vgetq_lane_s64(p20, 0); c20 += (uint64_t)vgetq_lane_s64(p20, 1);
	                        c21 += (uint64_t)vgetq_lane_s64(p21, 0); c21 += (uint64_t)vgetq_lane_s64(p21, 1);
	                        c22 += (uint64_t)vgetq_lane_s64(p22, 0); c22 += (uint64_t)vgetq_lane_s64(p22, 1);
	                        c23 += (uint64_t)vgetq_lane_s64(p23, 0); c23 += (uint64_t)vgetq_lane_s64(p23, 1);
	                        c30 += (uint64_t)vgetq_lane_s64(p30, 0); c30 += (uint64_t)vgetq_lane_s64(p30, 1);
	                        c31 += (uint64_t)vgetq_lane_s64(p31, 0); c31 += (uint64_t)vgetq_lane_s64(p31, 1);
	                        c32 += (uint64_t)vgetq_lane_s64(p32, 0); c32 += (uint64_t)vgetq_lane_s64(p32, 1);
	                        c33 += (uint64_t)vgetq_lane_s64(p33, 0); c33 += (uint64_t)vgetq_lane_s64(p33, 1);
	                    }
	                }
#endif

	                for (; i < n; i++) {
	                    uint32_t oa0 = (a0_off + i) * 4u;
	                    uint32_t oa1 = (a1_off + i) * 4u;
	                    uint32_t oa2 = (a2_off + i) * 4u;
	                    uint32_t oa3 = (a3_off + i) * 4u;
	                    uint32_t ob0 = (b0_off + i) * 4u;
	                    uint32_t ob1 = (b1_off + i) * 4u;
	                    uint32_t ob2 = (b2_off + i) * 4u;
	                    uint32_t ob3 = (b3_off + i) * 4u;

	                    int64_t a0v = (int64_t)(int32_t)((uint32_t)a->data[oa0] | ((uint32_t)a->data[oa0 + 1] << 8) | ((uint32_t)a->data[oa0 + 2] << 16) | ((uint32_t)a->data[oa0 + 3] << 24));
	                    int64_t a1v = (int64_t)(int32_t)((uint32_t)a->data[oa1] | ((uint32_t)a->data[oa1 + 1] << 8) | ((uint32_t)a->data[oa1 + 2] << 16) | ((uint32_t)a->data[oa1 + 3] << 24));
	                    int64_t a2v = (int64_t)(int32_t)((uint32_t)a->data[oa2] | ((uint32_t)a->data[oa2 + 1] << 8) | ((uint32_t)a->data[oa2 + 2] << 16) | ((uint32_t)a->data[oa2 + 3] << 24));
	                    int64_t a3v = (int64_t)(int32_t)((uint32_t)a->data[oa3] | ((uint32_t)a->data[oa3 + 1] << 8) | ((uint32_t)a->data[oa3 + 2] << 16) | ((uint32_t)a->data[oa3 + 3] << 24));
	                    int64_t b0v = (int64_t)(int32_t)((uint32_t)b->data[ob0] | ((uint32_t)b->data[ob0 + 1] << 8) | ((uint32_t)b->data[ob0 + 2] << 16) | ((uint32_t)b->data[ob0 + 3] << 24));
	                    int64_t b1v = (int64_t)(int32_t)((uint32_t)b->data[ob1] | ((uint32_t)b->data[ob1 + 1] << 8) | ((uint32_t)b->data[ob1 + 2] << 16) | ((uint32_t)b->data[ob1 + 3] << 24));
	                    int64_t b2v = (int64_t)(int32_t)((uint32_t)b->data[ob2] | ((uint32_t)b->data[ob2 + 1] << 8) | ((uint32_t)b->data[ob2 + 2] << 16) | ((uint32_t)b->data[ob2 + 3] << 24));
	                    int64_t b3v = (int64_t)(int32_t)((uint32_t)b->data[ob3] | ((uint32_t)b->data[ob3 + 1] << 8) | ((uint32_t)b->data[ob3 + 2] << 16) | ((uint32_t)b->data[ob3 + 3] << 24));

	                    c00 += (uint64_t)(a0v * b0v); c01 += (uint64_t)(a0v * b1v); c02 += (uint64_t)(a0v * b2v); c03 += (uint64_t)(a0v * b3v);
	                    c10 += (uint64_t)(a1v * b0v); c11 += (uint64_t)(a1v * b1v); c12 += (uint64_t)(a1v * b2v); c13 += (uint64_t)(a1v * b3v);
	                    c20 += (uint64_t)(a2v * b0v); c21 += (uint64_t)(a2v * b1v); c22 += (uint64_t)(a2v * b2v); c23 += (uint64_t)(a2v * b3v);
	                    c30 += (uint64_t)(a3v * b0v); c31 += (uint64_t)(a3v * b1v); c32 += (uint64_t)(a3v * b2v); c33 += (uint64_t)(a3v * b3v);
	                }

	                uint64_t u[16] = {0};
	                u[0] = c00; u[1] = c01; u[2] = c02; u[3] = c03;
	                u[4] = c10; u[5] = c11; u[6] = c12; u[7] = c13;
	                u[8] = c20; u[9] = c21; u[10] = c22; u[11] = c23;
	                u[12] = c30; u[13] = c31; u[14] = c32; u[15] = c33;

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
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_gemm_i32_4x4_slice_into expects (i64_buf,int,i32_buf,int,int,int,int,i32_buf,int,int,int,int,int)");
	            }
	            break;
	        }
	        case 118: { // oren_char(code:int) -> string(1)
	            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
	                int64_t v = args[0].as.i;
                if (v < 0 || v > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_char: code out of range (0..255)"); break; }
                char* buf = (char*)avm_heap_malloc_k(2, AVM_ALLOC_KIND_STRING);
                if (!buf) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                buf[0] = (char)(unsigned char)v;
                buf[1] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = buf;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_char expects (int)");
            }
            break;
