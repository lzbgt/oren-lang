		        case 59: { // oren_buf_load_i32(i32_buf, idx) -> int
		            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT) {
		                AvmBuf* b = args[0].as.buf;
		                int64_t idx = args[1].as.i;
	                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_i32: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_i32: index out of bounds"); break; }
                uint32_t off = (uint32_t)idx * 4u;
                uint32_t u = (uint32_t)b->data[off]
                           | ((uint32_t)b->data[off + 1] << 8)
                           | ((uint32_t)b->data[off + 2] << 16)
                           | ((uint32_t)b->data[off + 3] << 24);
                res = avm_int((int64_t)(int32_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_load_i32 expects (i32_buf, int)");
            }
            break;
        }
        case 60: { // oren_buf_store_i32(i32_buf, idx, val) -> i32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                int64_t v = args[2].as.i;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_i32: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_i32: index out of bounds"); break; }
                if (v < (int64_t)INT32_MIN || v > (int64_t)INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_i32: out of range"); break; }
                uint32_t u = (uint32_t)(int32_t)v;
                uint32_t off = (uint32_t)idx * 4u;
                b->data[off] = (uint8_t)(u & 0xFFu);
                b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_store_i32 expects (i32_buf, int, int)");
            }
            break;
        }
        case 61: { // oren_buf_load_i64(i64_buf, idx) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_i64: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_i64: index out of bounds"); break; }
                uint32_t off = (uint32_t)idx * 8u;
                uint64_t u = (uint64_t)b->data[off]
                           | ((uint64_t)b->data[off + 1] << 8)
                           | ((uint64_t)b->data[off + 2] << 16)
                           | ((uint64_t)b->data[off + 3] << 24)
                           | ((uint64_t)b->data[off + 4] << 32)
                           | ((uint64_t)b->data[off + 5] << 40)
                           | ((uint64_t)b->data[off + 6] << 48)
                           | ((uint64_t)b->data[off + 7] << 56);
                res = avm_int((int64_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_load_i64 expects (i64_buf, int)");
            }
            break;
        }
        case 62: { // oren_buf_store_i64(i64_buf, idx, val) -> i64_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_i64: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_i64: index out of bounds"); break; }
                uint32_t off = (uint32_t)idx * 8u;
                b->data[off] = (uint8_t)(u & 0xFFu);
                b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                b->data[off + 4] = (uint8_t)((u >> 32) & 0xFFu);
                b->data[off + 5] = (uint8_t)((u >> 40) & 0xFFu);
                b->data[off + 6] = (uint8_t)((u >> 48) & 0xFFu);
                b->data[off + 7] = (uint8_t)((u >> 56) & 0xFFu);
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_store_i64 expects (i64_buf, int, int)");
            }
            break;
        }
        case 63: { // oren_buf_load_f32(f32_buf, idx) -> float
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_f32: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_f32: index out of bounds"); break; }
                uint32_t off = (uint32_t)idx * 4u;
                uint32_t u = (uint32_t)b->data[off]
                           | ((uint32_t)b->data[off + 1] << 8)
                           | ((uint32_t)b->data[off + 2] << 16)
                           | ((uint32_t)b->data[off + 3] << 24);
                float fv = 0.0f;
                memcpy(&fv, &u, sizeof(fv));
                res.type = AVM_VAL_FLOAT;
                res.as.f = (double)fv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_load_f32 expects (f32_buf, int)");
            }
            break;
        }
        case 64: { // oren_buf_store_f32(f32_buf, idx, val) -> f32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_FLOAT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_f32: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_f32: index out of bounds"); break; }
                float fv = (float)args[2].as.f;
                uint32_t u = 0;
                memcpy(&u, &fv, sizeof(u));
                uint32_t off = (uint32_t)idx * 4u;
                b->data[off] = (uint8_t)(u & 0xFFu);
                b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_store_f32 expects (f32_buf, int, float)");
            }
            break;
        }
        case 65: { // oren_buf_load_f64(f64_buf, idx) -> float
            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_f64: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_f64: index out of bounds"); break; }
                uint32_t off = (uint32_t)idx * 8u;
                uint64_t u = (uint64_t)b->data[off]
                           | ((uint64_t)b->data[off + 1] << 8)
                           | ((uint64_t)b->data[off + 2] << 16)
                           | ((uint64_t)b->data[off + 3] << 24)
                           | ((uint64_t)b->data[off + 4] << 32)
                           | ((uint64_t)b->data[off + 5] << 40)
                           | ((uint64_t)b->data[off + 6] << 48)
                           | ((uint64_t)b->data[off + 7] << 56);
                double dv = 0.0;
                memcpy(&dv, &u, sizeof(dv));
                res.type = AVM_VAL_FLOAT;
                res.as.f = dv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_load_f64 expects (f64_buf, int)");
            }
            break;
        }
        case 66: { // oren_buf_store_f64(f64_buf, idx, val) -> f64_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_FLOAT) {
                AvmBuf* b = args[0].as.buf;
                int64_t idx = args[1].as.i;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_f64: invalid buffer"); break; }
                if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_f64: index out of bounds"); break; }
                uint64_t u = 0;
                memcpy(&u, &args[2].as.f, sizeof(u));
                uint32_t off = (uint32_t)idx * 8u;
                b->data[off] = (uint8_t)(u & 0xFFu);
                b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                b->data[off + 4] = (uint8_t)((u >> 32) & 0xFFu);
                b->data[off + 5] = (uint8_t)((u >> 40) & 0xFFu);
                b->data[off + 6] = (uint8_t)((u >> 48) & 0xFFu);
                b->data[off + 7] = (uint8_t)((u >> 56) & 0xFFu);
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_store_f64 expects (f64_buf, int, float)");
            }
            break;
        }
        case 190: { // oren_buf_data_mod(buf, mod:int) -> int
            if (nargs > 1
                && (args[0].type == AVM_VAL_I32_BUF || args[0].type == AVM_VAL_I64_BUF || args[0].type == AVM_VAL_F32_BUF || args[0].type == AVM_VAL_F64_BUF)
                && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t modv = args[1].as.i;
                if (modv <= 0) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_data_mod: mod must be > 0"); break; }
                if (modv > 4096) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_data_mod: mod too large"); break; }
                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_data_mod: invalid buffer"); break; }
                if (b->len == 0) { res = avm_int(0); break; }
                if (!b->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_data_mod: payload is nil"); break; }
                // AVM never exposes raw buffer pointers to bytecode. Its typed-buffer kernels use
                // deterministic byte loads/memcpy, so report the logical alignment contract shared
                // with C/native instead of leaking private heap-header placement.
                res = avm_int(0);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_data_mod expects (buf, int)");
            }
            break;
        }
        case 67: { // oren_buf_fill_i32(i32_buf, val:int) -> i32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                int64_t v = args[1].as.i;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_i32: invalid buffer"); break; }
                if (v < (int64_t)INT32_MIN || v > (int64_t)INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_i32: out of range"); break; }
                uint32_t u = (uint32_t)(int32_t)v;
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 4u;
                    b->data[off] = (uint8_t)(u & 0xFFu);
                    b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                    b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                    b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_fill_i32 expects (i32_buf, int)");
            }
            break;
        }
        case 68: { // oren_buf_fill_i64(i64_buf, val:int) -> i64_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_INT) {
                AvmBuf* b = args[0].as.buf;
                uint64_t u = (uint64_t)args[1].as.i;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_i64: invalid buffer"); break; }
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 8u;
                    b->data[off] = (uint8_t)(u & 0xFFu);
                    b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                    b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                    b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    b->data[off + 4] = (uint8_t)((u >> 32) & 0xFFu);
                    b->data[off + 5] = (uint8_t)((u >> 40) & 0xFFu);
                    b->data[off + 6] = (uint8_t)((u >> 48) & 0xFFu);
                    b->data[off + 7] = (uint8_t)((u >> 56) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_fill_i64 expects (i64_buf, int)");
            }
            break;
        }
        case 69: { // oren_buf_fill_f32(f32_buf, val:float) -> f32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_FLOAT) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_f32: invalid buffer"); break; }
                float fv = (float)args[1].as.f;
                uint32_t u = 0;
                memcpy(&u, &fv, sizeof(u));
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 4u;
                    b->data[off] = (uint8_t)(u & 0xFFu);
                    b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                    b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                    b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_fill_f32 expects (f32_buf, float)");
            }
            break;
        }
        case 70: { // oren_buf_fill_f64(f64_buf, val:float) -> f64_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_FLOAT) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_f64: invalid buffer"); break; }
                uint64_t u = 0;
                memcpy(&u, &args[1].as.f, sizeof(u));
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 8u;
                    b->data[off] = (uint8_t)(u & 0xFFu);
                    b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                    b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                    b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    b->data[off + 4] = (uint8_t)((u >> 32) & 0xFFu);
                    b->data[off + 5] = (uint8_t)((u >> 40) & 0xFFu);
                    b->data[off + 6] = (uint8_t)((u >> 48) & 0xFFu);
                    b->data[off + 7] = (uint8_t)((u >> 56) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_fill_f64 expects (f64_buf, float)");
            }
            break;
        }
        case 71: { // oren_buf_add_i32(a:i32_buf, b:i32_buf) -> i32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i32: length mismatch"); break; }
                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->len = a->len;
                out->elem_size = 4u;
                uint64_t bytes_len = (uint64_t)out->len * 4ull;
                out->data = NULL;
                if (bytes_len > 0) {
                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                }
                for (uint32_t i = 0; i < out->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ua = (uint32_t)a->data[off]
                                | ((uint32_t)a->data[off + 1] << 8)
                                | ((uint32_t)a->data[off + 2] << 16)
                                | ((uint32_t)a->data[off + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[off]
                                | ((uint32_t)b->data[off + 1] << 8)
                                | ((uint32_t)b->data[off + 2] << 16)
                                | ((uint32_t)b->data[off + 3] << 24);
                    uint32_t us = ua + ub; // wrap
                    out->data[off] = (uint8_t)(us & 0xFFu);
                    out->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                    out->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                    out->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                }
                res.type = AVM_VAL_I32_BUF;
                res.as.buf = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_i32 expects (i32_buf, i32_buf)");
            }
            break;
        }
        case 72: { // oren_buf_add_f32(a:f32_buf, b:f32_buf) -> f32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f32: length mismatch"); break; }
                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->len = a->len;
                out->elem_size = 4u;
                uint64_t bytes_len = (uint64_t)out->len * 4ull;
                out->data = NULL;
                if (bytes_len > 0) {
                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                }
                for (uint32_t i = 0; i < out->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ua = (uint32_t)a->data[off]
                                | ((uint32_t)a->data[off + 1] << 8)
                                | ((uint32_t)a->data[off + 2] << 16)
                                | ((uint32_t)a->data[off + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[off]
                                | ((uint32_t)b->data[off + 1] << 8)
                                | ((uint32_t)b->data[off + 2] << 16)
                                | ((uint32_t)b->data[off + 3] << 24);
                    float fa = 0.0f;
                    float fb = 0.0f;
                    memcpy(&fa, &ua, sizeof(fa));
                    memcpy(&fb, &ub, sizeof(fb));
                    float fs = fa + fb;
                    uint32_t us = 0;
                    memcpy(&us, &fs, sizeof(us));
                    out->data[off] = (uint8_t)(us & 0xFFu);
                    out->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                    out->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                    out->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                }
                res.type = AVM_VAL_F32_BUF;
                res.as.buf = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_f32 expects (f32_buf, f32_buf)");
            }
            break;
        }
        case 73: { // oren_buf_dot_i32(a:i32_buf, b:i32_buf) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32: length mismatch"); break; }
                // Wrap semantics: sum is modulo 2^64 then reinterpreted as signed i64.
                // Avoid UB on signed overflow by accumulating on u64 bit patterns.
                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4], wb[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
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
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                }
                res = avm_int(avm_i64_from_u64_bits_native(acc_u));
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_i32 expects (i32_buf, i32_buf)");
            }
            break;
        }
        case 74: { // oren_buf_dot_f32(a:f32_buf, b:f32_buf) -> float
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32: length mismatch"); break; }
                // Determinism hardening:
                // - Accumulate in double (fixed loop order) to reduce platform drift.
                // - FP contraction is disabled at TU level in avm_native.c.
                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t wa[4], wb[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
                        uint32x4_t va_u = vld1q_u32(wa);
                        uint32x4_t vb_u = vld1q_u32(wb);
                        float32x4_t va_f = vreinterpretq_f32_u32(va_u);
                        float32x4_t vb_f = vreinterpretq_f32_u32(vb_u);

                        // Preserve scalar semantics:
                        // - compute products in f64 (not f32), and accumulate into a f64 scalar in fixed element order.
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
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        double prod = (double)fa * (double)fb;
                        acc = acc + prod;
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        double prod = (double)fa * (double)fb;
                        acc = acc + prod;
                    }
                }
                res.type = AVM_VAL_FLOAT;
                res.as.f = acc;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f32 expects (f32_buf, f32_buf)");
            }
            break;
        }
        case 75: { // oren_buf_add_i32_into(dst:i32_buf, a:i32_buf, b:i32_buf) -> i32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF && args[2].type == AVM_VAL_I32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!dst || !a || !b || dst->elem_size != 4u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i32_into: invalid buffers"); break; }
                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i32_into: length mismatch"); break; }
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4], wb[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int32x4_t vb = vld1q_s32(wb);
                        int32x4_t vs = vaddq_s32(va, vb); // wrap
                        vst1q_s32(wo, vs);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        uint32_t us = ua + ub; // wrap
                        dst->data[off] = (uint8_t)(us & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                for (uint32_t i = 0; i < dst->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ua = (uint32_t)a->data[off]
                                | ((uint32_t)a->data[off + 1] << 8)
                                | ((uint32_t)a->data[off + 2] << 16)
                                | ((uint32_t)a->data[off + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[off]
                                | ((uint32_t)b->data[off + 1] << 8)
                                | ((uint32_t)b->data[off + 2] << 16)
                                | ((uint32_t)b->data[off + 3] << 24);
                    uint32_t us = ua + ub; // wrap
                    dst->data[off] = (uint8_t)(us & 0xFFu);
                    dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                    dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                    dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_i32_into expects (i32_buf, i32_buf, i32_buf)");
            }
            break;
        }
        case 191: { // oren_buf_add_i64_into(dst:i64_buf, a:i64_buf, b:i64_buf) -> i64_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_I64_BUF && args[2].type == AVM_VAL_I64_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!dst || !a || !b || dst->elem_size != 8u || a->elem_size != 8u || b->elem_size != 8u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i64_into: invalid buffers"); break; }
                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_i64_into: length mismatch"); break; }
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
                    uint64_t us = ua + ub;
                    dst->data[off] = (uint8_t)(us & 0xFFu);
                    dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                    dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                    dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    dst->data[off + 4] = (uint8_t)((us >> 32) & 0xFFu);
                    dst->data[off + 5] = (uint8_t)((us >> 40) & 0xFFu);
                    dst->data[off + 6] = (uint8_t)((us >> 48) & 0xFFu);
                    dst->data[off + 7] = (uint8_t)((us >> 56) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_i64_into expects (i64_buf, i64_buf, i64_buf)");
            }
            break;
        }
        case 76: { // oren_buf_add_f32_into(dst:f32_buf, a:f32_buf, b:f32_buf) -> f32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF && args[2].type == AVM_VAL_F32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!dst || !a || !b || dst->elem_size != 4u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f32_into: invalid buffers"); break; }
                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_add_f32_into: length mismatch"); break; }
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t wa[4], wb[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
                        uint32x4_t va_u = vld1q_u32(wa);
                        uint32x4_t vb_u = vld1q_u32(wb);
                        float32x4_t va = vreinterpretq_f32_u32(va_u);
                        float32x4_t vb = vreinterpretq_f32_u32(vb_u);
                        float32x4_t vs = vaddq_f32(va, vb);
                        uint32x4_t vo_u = vreinterpretq_u32_f32(vs);
                        vst1q_u32(wo, vo_u);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        float fs = fa + fb;
                        uint32_t us = 0;
                        memcpy(&us, &fs, sizeof(us));
                        dst->data[off] = (uint8_t)(us & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        float fs = fa + fb;
                        uint32_t us = 0;
                        memcpy(&us, &fs, sizeof(us));
                        dst->data[off] = (uint8_t)(us & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_add_f32_into expects (f32_buf, f32_buf, f32_buf)");
            }
            break;
        }
        case 77: { // oren_buf_scale_f32(buf:f32_buf, scalar:float) -> f32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_FLOAT) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_f32: invalid buffer"); break; }
                float s = (float)args[1].as.f;
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t u = (uint32_t)b->data[off]
                               | ((uint32_t)b->data[off + 1] << 8)
                               | ((uint32_t)b->data[off + 2] << 16)
                               | ((uint32_t)b->data[off + 3] << 24);
                    float v = 0.0f;
                    memcpy(&v, &u, sizeof(v));
                    float outv = v * s;
                    uint32_t outu = 0;
                    memcpy(&outu, &outv, sizeof(outu));
                    b->data[off] = (uint8_t)(outu & 0xFFu);
                    b->data[off + 1] = (uint8_t)((outu >> 8) & 0xFFu);
                    b->data[off + 2] = (uint8_t)((outu >> 16) & 0xFFu);
                    b->data[off + 3] = (uint8_t)((outu >> 24) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_scale_f32 expects (f32_buf, float)");
            }
            break;
        }
        case 78: { // oren_buf_reduce_sum_f32(buf:f32_buf) -> float
            if (nargs > 0 && args[0].type == AVM_VAL_F32_BUF) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f32: invalid buffer"); break; }
                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= b->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t w[4];
                        memcpy(w, b->data + off, 16);
                        uint32x4_t vu_u = vld1q_u32(w);
                        float32x4_t vf = vreinterpretq_f32_u32(vu_u);

                        // Preserve scalar semantics:
                        // - convert to f64 and add to scalar acc in fixed order.
                        float32x2_t v_lo = vget_low_f32(vf);
                        float32x2_t v_hi = vget_high_f32(vf);
                        float64x2_t d0 = vcvt_f64_f32(v_lo);
                        float64x2_t d1 = vcvt_f64_f32(v_hi);

                        acc = acc + vgetq_lane_f64(d0, 0);
                        acc = acc + vgetq_lane_f64(d0, 1);
                        acc = acc + vgetq_lane_f64(d1, 0);
                        acc = acc + vgetq_lane_f64(d1, 1);
                    }
                    for (; i < b->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)b->data[off]
                                   | ((uint32_t)b->data[off + 1] << 8)
                                   | ((uint32_t)b->data[off + 2] << 16)
                                   | ((uint32_t)b->data[off + 3] << 24);
                        float v = 0.0f;
                        memcpy(&v, &u, sizeof(v));
                        acc += (double)v;
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < b->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)b->data[off]
                                   | ((uint32_t)b->data[off + 1] << 8)
                                   | ((uint32_t)b->data[off + 2] << 16)
                                   | ((uint32_t)b->data[off + 3] << 24);
                        float v = 0.0f;
                        memcpy(&v, &u, sizeof(v));
                        acc += (double)v;
                    }
                }
                res.type = AVM_VAL_FLOAT;
                res.as.f = acc;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_f32 expects (f32_buf)");
            }
            break;
        }
        case 79: { // oren_buf_mul_f32_into(dst:f32_buf, a:f32_buf, b:f32_buf) -> f32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF && args[2].type == AVM_VAL_F32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!dst || !a || !b || dst->elem_size != 4u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f32_into: invalid buffers"); break; }
                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f32_into: length mismatch"); break; }
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t wa[4], wb[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
                        uint32x4_t va_u = vld1q_u32(wa);
                        uint32x4_t vb_u = vld1q_u32(wb);
                        float32x4_t va = vreinterpretq_f32_u32(va_u);
                        float32x4_t vb = vreinterpretq_f32_u32(vb_u);
                        float32x4_t vmul = vmulq_f32(va, vb);
                        uint32x4_t vo_u = vreinterpretq_u32_f32(vmul);
                        vst1q_u32(wo, vo_u);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        float fm = fa * fb;
                        uint32_t um = 0;
                        memcpy(&um, &fm, sizeof(um));
                        dst->data[off] = (uint8_t)(um & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((um >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((um >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((um >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        float fm = fa * fb;
                        uint32_t um = 0;
                        memcpy(&um, &fm, sizeof(um));
                        dst->data[off] = (uint8_t)(um & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((um >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((um >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((um >> 24) & 0xFFu);
                    }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_f32_into expects (f32_buf, f32_buf, f32_buf)");
            }
            break;
        }
        case 80: { // oren_buf_mul_f32(a:f32_buf, b:f32_buf) -> f32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_f32: length mismatch"); break; }
                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->len = a->len;
                out->elem_size = 4u;
                uint64_t bytes_len = (uint64_t)out->len * 4ull;
                out->data = NULL;
                if (bytes_len > 0) {
                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                }
                // Reuse the in-place kernel semantics for determinism (fixed loop order).
                AvmValue dstv; dstv.type = AVM_VAL_F32_BUF; dstv.as.buf = out;
                AvmValue argv[3]; argv[0] = dstv; argv[1] = args[0]; argv[2] = args[1];
                res = avm_call_native(vm, 79, argv, 3);
                if (avm_is_err_val(res)) break;
                res.type = AVM_VAL_F32_BUF;
                res.as.buf = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_f32 expects (f32_buf, f32_buf)");
            }
            break;
        }
        case 81: { // oren_buf_mul_i32_into(dst:i32_buf, a:i32_buf, b:i32_buf) -> i32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF && args[2].type == AVM_VAL_I32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!dst || !a || !b || dst->elem_size != 4u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_i32_into: invalid buffers"); break; }
                if (dst->len != a->len || dst->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_i32_into: length mismatch"); break; }
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4], wb[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int32x4_t vb = vld1q_s32(wb);
                        int32x4_t vp = vmulq_s32(va, vb); // wrap (low 32 bits)
                        vst1q_s32(wo, vp);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        int32_t va = (int32_t)ua;
                        int32_t vb = (int32_t)ub;
                        int64_t prod = (int64_t)va * (int64_t)vb;
                        uint32_t up = (uint32_t)(int32_t)prod; // wrap to i32
                        dst->data[off] = (uint8_t)(up & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                for (uint32_t i = 0; i < dst->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ua = (uint32_t)a->data[off]
                                | ((uint32_t)a->data[off + 1] << 8)
                                | ((uint32_t)a->data[off + 2] << 16)
                                | ((uint32_t)a->data[off + 3] << 24);
                    uint32_t ub = (uint32_t)b->data[off]
                                | ((uint32_t)b->data[off + 1] << 8)
                                | ((uint32_t)b->data[off + 2] << 16)
                                | ((uint32_t)b->data[off + 3] << 24);
                    int32_t va = (int32_t)ua;
                    int32_t vb = (int32_t)ub;
                    int64_t prod = (int64_t)va * (int64_t)vb;
                    uint32_t up = (uint32_t)(int32_t)prod; // wrap to i32
                    dst->data[off] = (uint8_t)(up & 0xFFu);
                    dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
                    dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
                    dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
                }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_i32_into expects (i32_buf, i32_buf, i32_buf)");
            }
            break;
        }
        case 82: { // oren_buf_mul_i32(a:i32_buf, b:i32_buf) -> i32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF) {
                AvmBuf* a = args[0].as.buf;
                AvmBuf* b = args[1].as.buf;
                if (!a || !b || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_i32: invalid buffers"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_mul_i32: length mismatch"); break; }
                AvmBuf* out = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->len = a->len;
                out->elem_size = 4u;
                uint64_t bytes_len = (uint64_t)out->len * 4ull;
                out->data = NULL;
                if (bytes_len > 0) {
                    out->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!out->data) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                }
                AvmValue dstv; dstv.type = AVM_VAL_I32_BUF; dstv.as.buf = out;
                AvmValue argv[3]; argv[0] = dstv; argv[1] = args[0]; argv[2] = args[1];
                res = avm_call_native(vm, 81, argv, 3);
                if (avm_is_err_val(res)) break;
                res.type = AVM_VAL_I32_BUF;
                res.as.buf = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_mul_i32 expects (i32_buf, i32_buf)");
            }
            break;
        }
        case 83: { // oren_buf_reduce_sum_i32(buf:i32_buf) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_I32_BUF) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_i32: invalid buffer"); break; }
                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= b->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t w[4];
                        memcpy(w, b->data + off, 16);
                        int32x4_t v = vld1q_s32(w);
                        int64x2_t lo = vmovl_s32(vget_low_s32(v));
                        int64x2_t hi = vmovl_s32(vget_high_s32(v));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(lo));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(hi));
                    }
                    uint64_t tmp[2];
                    vst1q_u64(tmp, vacc);
                    acc_u += tmp[0] + tmp[1];
                    for (; i < b->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)b->data[off]
                                   | ((uint32_t)b->data[off + 1] << 8)
                                   | ((uint32_t)b->data[off + 2] << 16)
                                   | ((uint32_t)b->data[off + 3] << 24);
                        int32_t v = (int32_t)u;
                        acc_u += avm_u64_bits_i64_native((int64_t)v);
                    }
                } else
#endif
                {
                for (uint32_t i = 0; i < b->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t u = (uint32_t)b->data[off]
                               | ((uint32_t)b->data[off + 1] << 8)
                               | ((uint32_t)b->data[off + 2] << 16)
                               | ((uint32_t)b->data[off + 3] << 24);
                    int32_t v = (int32_t)u;
                    acc_u += avm_u64_bits_i64_native((int64_t)v);
                }
                }
                res = avm_int(avm_i64_from_u64_bits_native(acc_u));
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_i32 expects (i32_buf)");
            }
            break;
        }
        case 84: { // oren_buf_scale_f32_into(dst:f32_buf, a:f32_buf, scalar:float) -> f32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_F32_BUF && args[2].type == AVM_VAL_FLOAT) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                if (!dst || !a || dst->elem_size != 4u || a->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_f32_into: invalid buffers"); break; }
                if (dst->len != a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_f32_into: length mismatch"); break; }
                float s = (float)args[2].as.f;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    float32x4_t vs = vdupq_n_f32(s);
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t wa[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        uint32x4_t va_u = vld1q_u32(wa);
                        float32x4_t va = vreinterpretq_f32_u32(va_u);
                        float32x4_t vout = vmulq_f32(va, vs);
                        uint32x4_t vo_u = vreinterpretq_u32_f32(vout);
                        vst1q_u32(wo, vo_u);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        float fa = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        float fs = fa * s;
                        uint32_t us = 0;
                        memcpy(&us, &fs, sizeof(us));
                        dst->data[off] = (uint8_t)(us & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        float fa = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        float fs = fa * s;
                        uint32_t us = 0;
                        memcpy(&us, &fs, sizeof(us));
                        dst->data[off] = (uint8_t)(us & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((us >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((us >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((us >> 24) & 0xFFu);
                    }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_scale_f32_into expects (f32_buf, f32_buf, float)");
            }
            break;
        }
        case 85: { // oren_buf_scale_i32_into(dst:i32_buf, a:i32_buf, scalar:int) -> i32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_I32_BUF && args[2].type == AVM_VAL_INT) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                if (!dst || !a || dst->elem_size != 4u || a->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_i32_into: invalid buffers"); break; }
                if (dst->len != a->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_i32_into: length mismatch"); break; }
                int64_t sv = args[2].as.i;
                if (sv < (int64_t)INT32_MIN || sv > (int64_t)INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_scale_i32_into: scalar out of range"); break; }
                int32_t s = (int32_t)sv;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    int32x4_t vs = vdupq_n_s32(s);
                    uint32_t i = 0;
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4], wo[4];
                        memcpy(wa, a->data + off, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int32x4_t vp = vmulq_s32(va, vs); // wrap
                        vst1q_s32(wo, vp);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        int32_t v = (int32_t)ua;
                        int64_t prod = (int64_t)v * (int64_t)s;
                        uint32_t up = (uint32_t)(int32_t)prod; // wrap to i32
                        dst->data[off] = (uint8_t)(up & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                for (uint32_t i = 0; i < dst->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ua = (uint32_t)a->data[off]
                                | ((uint32_t)a->data[off + 1] << 8)
                                | ((uint32_t)a->data[off + 2] << 16)
                                | ((uint32_t)a->data[off + 3] << 24);
                    int32_t v = (int32_t)ua;
                    int64_t prod = (int64_t)v * (int64_t)s;
                    uint32_t up = (uint32_t)(int32_t)prod; // wrap to i32
                    dst->data[off] = (uint8_t)(up & 0xFFu);
                    dst->data[off + 1] = (uint8_t)((up >> 8) & 0xFFu);
                    dst->data[off + 2] = (uint8_t)((up >> 16) & 0xFFu);
                    dst->data[off + 3] = (uint8_t)((up >> 24) & 0xFFu);
                }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_scale_i32_into expects (i32_buf, i32_buf, int)");
            }
            break;
        }
        case 123: { // oren_buf_axpy_i32_into(dst:i32_buf, alpha:int, x:i32_buf, y:i32_buf) -> i32_buf
            if (nargs > 3 && args[0].type == AVM_VAL_I32_BUF && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_I32_BUF && args[3].type == AVM_VAL_I32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                int64_t av = args[1].as.i;
                AvmBuf* x = args[2].as.buf;
                AvmBuf* y = args[3].as.buf;
                if (!dst || !x || !y || dst->elem_size != 4u || x->elem_size != 4u || y->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_axpy_i32_into: invalid buffers"); break; }
                if (dst->len != x->len || dst->len != y->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_axpy_i32_into: length mismatch"); break; }
                if (av < (int64_t)INT32_MIN || av > (int64_t)INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_axpy_i32_into: alpha out of range"); break; }
                int32_t alpha = (int32_t)av;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    int32x4_t va = vdupq_n_s32(alpha);
                    for (; i + 4u <= dst->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wx[4], wy[4], wo[4];
                        memcpy(wx, x->data + off, 16);
                        memcpy(wy, y->data + off, 16);
                        int32x4_t vx = vld1q_s32(wx);
                        int32x4_t vy = vld1q_s32(wy);
                        // out = alpha*x + y (wrap to i32)
                        int32x4_t vout = vaddq_s32(vmulq_s32(vx, va), vy);
                        vst1q_s32(wo, vout);
                        memcpy(dst->data + off, wo, 16);
                    }
                    for (; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ux = (uint32_t)x->data[off]
                                    | ((uint32_t)x->data[off + 1] << 8)
                                    | ((uint32_t)x->data[off + 2] << 16)
                                    | ((uint32_t)x->data[off + 3] << 24);
                        uint32_t uy = (uint32_t)y->data[off]
                                    | ((uint32_t)y->data[off + 1] << 8)
                                    | ((uint32_t)y->data[off + 2] << 16)
                                    | ((uint32_t)y->data[off + 3] << 24);
                        int32_t xi = (int32_t)ux;
                        int32_t yi = (int32_t)uy;
                        int64_t prod = (int64_t)alpha * (int64_t)xi;
                        int64_t sum = prod + (int64_t)yi;
                        uint32_t uo = (uint32_t)(int32_t)sum; // wrap to i32
                        dst->data[off] = (uint8_t)(uo & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((uo >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((uo >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((uo >> 24) & 0xFFu);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < dst->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ux = (uint32_t)x->data[off]
                                    | ((uint32_t)x->data[off + 1] << 8)
                                    | ((uint32_t)x->data[off + 2] << 16)
                                    | ((uint32_t)x->data[off + 3] << 24);
                        uint32_t uy = (uint32_t)y->data[off]
                                    | ((uint32_t)y->data[off + 1] << 8)
                                    | ((uint32_t)y->data[off + 2] << 16)
                                    | ((uint32_t)y->data[off + 3] << 24);
                        int32_t xi = (int32_t)ux;
                        int32_t yi = (int32_t)uy;
                        int64_t prod = (int64_t)alpha * (int64_t)xi;
                        int64_t sum = prod + (int64_t)yi;
                        uint32_t uo = (uint32_t)(int32_t)sum; // wrap to i32
                        dst->data[off] = (uint8_t)(uo & 0xFFu);
                        dst->data[off + 1] = (uint8_t)((uo >> 8) & 0xFFu);
                        dst->data[off + 2] = (uint8_t)((uo >> 16) & 0xFFu);
                        dst->data[off + 3] = (uint8_t)((uo >> 24) & 0xFFu);
                    }
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_axpy_i32_into expects (i32_buf, int, i32_buf, i32_buf)");
            }
            break;
        }
        case 124: { // oren_buf_axpy_i32_in_place(alpha:int, x:i32_buf, y:i32_buf) -> i32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_INT && args[1].type == AVM_VAL_I32_BUF && args[2].type == AVM_VAL_I32_BUF) {
                AvmValue argv[4];
                argv[0] = args[2]; // dst = y
                argv[1] = args[0]; // alpha
                argv[2] = args[1]; // x
                argv[3] = args[2]; // y
                res = avm_call_native(vm, 123, argv, 4);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_axpy_i32_in_place expects (int, i32_buf, i32_buf)");
            }
            break;
        }
        case 125: { // oren_buf_axpy_f32_into(dst:f32_buf, alpha:float, x:f32_buf, y:f32_buf) -> f32_buf
            if (nargs > 3 && args[0].type == AVM_VAL_F32_BUF && args[1].type == AVM_VAL_FLOAT && args[2].type == AVM_VAL_F32_BUF && args[3].type == AVM_VAL_F32_BUF) {
                AvmBuf* dst = args[0].as.buf;
                AvmBuf* x = args[2].as.buf;
                AvmBuf* y = args[3].as.buf;
                if (!dst || !x || !y || dst->elem_size != 4u || x->elem_size != 4u || y->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_axpy_f32_into: invalid buffers"); break; }
                if (dst->len != x->len || dst->len != y->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_axpy_f32_into: length mismatch"); break; }
                float alpha = (float)args[1].as.f;
                // Keep scalar order deterministic; avoid fused multiply-add (FMA) differences.
                for (uint32_t i = 0; i < dst->len; i++) {
                    uint32_t off = i * 4u;
                    uint32_t ux = (uint32_t)x->data[off]
                                | ((uint32_t)x->data[off + 1] << 8)
                                | ((uint32_t)x->data[off + 2] << 16)
                                | ((uint32_t)x->data[off + 3] << 24);
                    uint32_t uy = (uint32_t)y->data[off]
                                | ((uint32_t)y->data[off + 1] << 8)
                                | ((uint32_t)y->data[off + 2] << 16)
                                | ((uint32_t)y->data[off + 3] << 24);
                    float fx = 0.0f, fy = 0.0f;
                    memcpy(&fx, &ux, sizeof(fx));
                    memcpy(&fy, &uy, sizeof(fy));
                    float t = fx * alpha;
                    float out = t + fy;
                    uint32_t uo = 0;
                    memcpy(&uo, &out, sizeof(uo));
                    dst->data[off] = (uint8_t)(uo & 0xFFu);
                    dst->data[off + 1] = (uint8_t)((uo >> 8) & 0xFFu);
                    dst->data[off + 2] = (uint8_t)((uo >> 16) & 0xFFu);
                    dst->data[off + 3] = (uint8_t)((uo >> 24) & 0xFFu);
                }
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_axpy_f32_into expects (f32_buf, float, f32_buf, f32_buf)");
            }
            break;
        }
        case 126: { // oren_buf_axpy_f32_in_place(alpha:float, x:f32_buf, y:f32_buf) -> f32_buf
            if (nargs > 2 && args[0].type == AVM_VAL_FLOAT && args[1].type == AVM_VAL_F32_BUF && args[2].type == AVM_VAL_F32_BUF) {
                AvmValue argv[4];
                argv[0] = args[2]; // dst = y
                argv[1] = args[0]; // alpha
                argv[2] = args[1]; // x
                argv[3] = args[2]; // y
                res = avm_call_native(vm, 125, argv, 4);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_axpy_f32_in_place expects (float, f32_buf, f32_buf)");
            }
            break;
        }
        case 86: { // oren_buf_dot_f32_into(out:f64_buf, a:f32_buf, b:f32_buf) -> f64_buf
            if (nargs > 2 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F32_BUF && args[2].type == AVM_VAL_F32_BUF) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_into: invalid buffers"); break; }
                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_into: out len must be >= 1"); break; }
                if (!out->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_into: out data is null"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_f32_into: length mismatch"); break; }
                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t wa[4], wb[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
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

                        acc = acc + vgetq_lane_f64(p0, 0);
                        acc = acc + vgetq_lane_f64(p0, 1);
                        acc = acc + vgetq_lane_f64(p1, 0);
                        acc = acc + vgetq_lane_f64(p1, 1);
                    }
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        acc = acc + ((double)fa * (double)fb);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        float fa = 0.0f;
                        float fb = 0.0f;
                        memcpy(&fa, &ua, sizeof(fa));
                        memcpy(&fb, &ub, sizeof(fb));
                        acc = acc + ((double)fa * (double)fb);
                    }
                }
                uint64_t u = 0;
                memcpy(&u, &acc, sizeof(u));
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_f32_into expects (f64_buf, f32_buf, f32_buf)");
            }
            break;
        }
        case 87: { // oren_buf_reduce_sum_f32_into(out:f64_buf, a:f32_buf) -> f64_buf
            if (nargs > 1 && args[0].type == AVM_VAL_F64_BUF && args[1].type == AVM_VAL_F32_BUF) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                if (!out || !a || out->elem_size != 8u || a->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f32_into: invalid buffers"); break; }
                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f32_into: out len must be >= 1"); break; }
                if (!out->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_f32_into: out data is null"); break; }
                double acc = 0.0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd) {
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        uint32_t w[4];
                        memcpy(w, a->data + off, 16);
                        uint32x4_t vu_u = vld1q_u32(w);
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
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)a->data[off]
                                   | ((uint32_t)a->data[off + 1] << 8)
                                   | ((uint32_t)a->data[off + 2] << 16)
                                   | ((uint32_t)a->data[off + 3] << 24);
                        float v = 0.0f;
                        memcpy(&v, &u, sizeof(v));
                        acc += (double)v;
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)a->data[off]
                                   | ((uint32_t)a->data[off + 1] << 8)
                                   | ((uint32_t)a->data[off + 2] << 16)
                                   | ((uint32_t)a->data[off + 3] << 24);
                        float v = 0.0f;
                        memcpy(&v, &u, sizeof(v));
                        acc += (double)v;
                    }
                }
                uint64_t u = 0;
                memcpy(&u, &acc, sizeof(u));
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_f32_into expects (f64_buf, f32_buf)");
            }
            break;
        }
        case 88: { // oren_buf_dot_i32_into(out:i64_buf, a:i32_buf, b:i32_buf) -> i64_buf
            if (nargs > 2 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_I32_BUF && args[2].type == AVM_VAL_I32_BUF) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                AvmBuf* b = args[2].as.buf;
                if (!out || !a || !b || out->elem_size != 8u || a->elem_size != 4u || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_into: invalid buffers"); break; }
                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_into: out len must be >= 1"); break; }
                if (!out->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_into: out data is null"); break; }
                if (a->len != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_dot_i32_into: length mismatch"); break; }
                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && a->len >= 4u) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4], wb[4];
                        memcpy(wa, a->data + off, 16);
                        memcpy(wb, b->data + off, 16);
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
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t ua = (uint32_t)a->data[off]
                                    | ((uint32_t)a->data[off + 1] << 8)
                                    | ((uint32_t)a->data[off + 2] << 16)
                                    | ((uint32_t)a->data[off + 3] << 24);
                        uint32_t ub = (uint32_t)b->data[off]
                                    | ((uint32_t)b->data[off + 1] << 8)
                                    | ((uint32_t)b->data[off + 2] << 16)
                                    | ((uint32_t)b->data[off + 3] << 24);
                        int64_t prod = (int64_t)(int32_t)ua * (int64_t)(int32_t)ub;
                        acc_u += avm_u64_bits_i64_native(prod);
                    }
                }
                uint64_t u = acc_u;
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_dot_i32_into expects (i64_buf, i32_buf, i32_buf)");
            }
            break;
        }
        case 89: { // oren_buf_reduce_sum_i32_into(out:i64_buf, a:i32_buf) -> i64_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I64_BUF && args[1].type == AVM_VAL_I32_BUF) {
                AvmBuf* out = args[0].as.buf;
                AvmBuf* a = args[1].as.buf;
                if (!out || !a || out->elem_size != 8u || a->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_i32_into: invalid buffers"); break; }
                if (out->len < 1u) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_i32_into: out len must be >= 1"); break; }
                if (!out->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_reduce_sum_i32_into: out data is null"); break; }
                uint64_t acc_u = 0;
#if AVM_HAS_NEON
                if (vm && vm->enable_simd && a->len >= 4u) {
                    uint64x2_t vacc = vdupq_n_u64(0);
                    uint32_t i = 0;
                    for (; i + 4u <= a->len; i += 4u) {
                        uint32_t off = i * 4u;
                        int32_t wa[4];
                        memcpy(wa, a->data + off, 16);
                        int32x4_t va = vld1q_s32(wa);
                        int64x2_t lo = vmovl_s32(vget_low_s32(va));
                        int64x2_t hi = vmovl_s32(vget_high_s32(va));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(lo));
                        vacc = vaddq_u64(vacc, vreinterpretq_u64_s64(hi));
                    }
                    uint64_t tmp[2];
                    vst1q_u64(tmp, vacc);
                    acc_u += tmp[0] + tmp[1];
                    for (; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)a->data[off]
                                   | ((uint32_t)a->data[off + 1] << 8)
                                   | ((uint32_t)a->data[off + 2] << 16)
                                   | ((uint32_t)a->data[off + 3] << 24);
                        acc_u += avm_u64_bits_i64_native((int64_t)(int32_t)u);
                    }
                } else
#endif
                {
                    for (uint32_t i = 0; i < a->len; i++) {
                        uint32_t off = i * 4u;
                        uint32_t u = (uint32_t)a->data[off]
                                   | ((uint32_t)a->data[off + 1] << 8)
                                   | ((uint32_t)a->data[off + 2] << 16)
                                   | ((uint32_t)a->data[off + 3] << 24);
                        acc_u += avm_u64_bits_i64_native((int64_t)(int32_t)u);
                    }
                }
                uint64_t u = acc_u;
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_reduce_sum_i32_into expects (i64_buf, i32_buf)");
            }
            break;
        }
