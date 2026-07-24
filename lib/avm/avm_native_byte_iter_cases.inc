        case 35: { // oren_bytes_from_hex(string) -> bytes
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                const char* s = (const char*)args[0].as.p;
                size_t n = s ? strlen(s) : 0;
                if ((n & 1) != 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_from_hex: expected even-length hex"); break; }
                AvmValue bv = avm_bytes_new((int)(n / 2));
                if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "bytes_from_hex: out of memory"); break; }
                for (size_t i = 0; i < n; i += 2) {
                    int hi = hex_nibble(s[i]);
                    int lo = hex_nibble(s[i + 1]);
                    if (hi < 0 || lo < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_from_hex: invalid hex"); break; }
                    bv.as.b->data[i / 2] = (uint8_t)((hi << 4) | lo);
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_from_hex expects (string)");
            }
            break;
        }
        case 36: { // oren_bytes_to_hex(bytes|list<int 0..255>|list_int) -> string
            if (nargs > 0) { res = avm_native_bytes_to_hex_value(vm, args[0]); }
            else { res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_to_hex expects (bytes|list<int>|list_int)"); }
            break;
        }
        case 40: { // oren_avm_record_to_bytes() -> nil
            // Enable in-memory recording; resets any existing buffer.
            AvmValue bv = avm_bytes_new(0);
            if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "record_to_bytes: out of memory"); break; }
            // Preallocate header.
            uint32_t p = 0;
            const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
            vm->log_used_bytes = 0;
            if (!avm_log_charge(vm, 8, 0, 40)) { break; }
            if (!mem_write_bytes(bv.as.b, &p, magic, 8)) { res = avm_err(AVM_ERR_INTERNAL, "record_to_bytes: out of memory"); break; }
            vm->record_log_bytes = bv.as.b;
            vm->log_used_bytes = 8;
            res = avm_nil();
            break;
        }
        case 41: { // oren_avm_get_record_bytes() -> bytes|nil
            if (vm->record_log_bytes) {
                res.type = AVM_VAL_BYTES;
                res.as.b = vm->record_log_bytes;
            } else {
                res = avm_nil();
            }
            break;
        }
        case 42: { // oren_avm_set_replay_bytes(bytes) -> nil
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 8) { res = avm_err(AVM_ERR_INVALID_ARG, "set_replay_bytes: invalid log"); break; }
                const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
                if (memcmp(b->data, want, 8) != 0) { res = avm_err(AVM_ERR_INVALID_ARG, "set_replay_bytes: bad magic"); break; }
                vm->replay_log_bytes = b;
                vm->replay_log_pos = 8;
                res = avm_nil();
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_avm_set_replay_bytes expects (bytes)");
            }
            break;
        }
        case 43: { // oren_iter_next(container, idx:int, out_pair:list|nil) -> [ok:int, value]
            if ((nargs == 2 || nargs == 3) && args[1].type == AVM_VAL_INT) {
                AvmValue container = args[0];
                int64_t idx = args[1].as.i;
                AvmValue out_pair = (nargs == 3) ? args[2] : avm_nil();

                AvmValue okv = avm_int(0);
                AvmValue val = avm_nil();

                if (idx >= 0) {
                    // Typed buffer "view" lists (rolling, HPC):
	                    // - slice view:   [buf, off, len]
	                    // - strided view: [buf, off, len, stride]
	                    // These should iterate the underlying buffer elements rather than the metadata fields.
	                    if (container.type == AVM_VAL_LIST && container.as.l) {
	                        AvmList* l = container.as.l;
	                        int view_ok = 0;
	                        if (l->count == 3 || l->count == 4) {
	                            AvmValue b = l->items[0];
	                            // In AVM, u8 buffers are represented as BYTES. Support views for BYTES too.
	                            if (b.type == AVM_VAL_BYTES ||
	                                b.type == AVM_VAL_I32_BUF || b.type == AVM_VAL_I64_BUF || b.type == AVM_VAL_F32_BUF || b.type == AVM_VAL_F64_BUF) {
	                                AvmValue offv = l->items[1];
	                                AvmValue lenv = l->items[2];
	                                AvmValue stridev = (l->count == 4) ? l->items[3] : avm_int(1);
	                                if (offv.type == AVM_VAL_INT && lenv.type == AVM_VAL_INT && stridev.type == AVM_VAL_INT) {
	                                    int64_t off = offv.as.i;
	                                    int64_t n = lenv.as.i;
	                                    int64_t stride = stridev.as.i;
	                                    if (off >= 0 && n >= 0 && stride > 0) {
	                                        // Valid view shape: do not fall back to list metadata iteration.
	                                        view_ok = 1;
	                                        if (idx < n) {
	                                            int64_t elem_idx = off + idx * stride;
	                                            if (b.type == AVM_VAL_BYTES) {
	                                                AvmBytes* bb = b.as.b;
	                                                if (bb && elem_idx >= 0 && (uint64_t)elem_idx < (uint64_t)bb->len) {
	                                                    okv = avm_int(1);
	                                                    val = avm_int((int64_t)bb->data[(int)elem_idx]);
	                                                }
	                                            } else {
	                                                AvmBuf* buf = b.as.buf;
	                                                if (buf && elem_idx >= 0 && (uint64_t)elem_idx < (uint64_t)buf->len) {
	                                                    okv = avm_int(1);
	                                                    if (b.type == AVM_VAL_I32_BUF) {
	                                                        int32_t v; memcpy(&v, buf->data + (size_t)elem_idx * 4u, 4u);
	                                                        val = avm_int((int64_t)v);
	                                                    } else if (b.type == AVM_VAL_I64_BUF) {
	                                                        int64_t v; memcpy(&v, buf->data + (size_t)elem_idx * 8u, 8u);
	                                                        val = avm_int(v);
	                                                    } else if (b.type == AVM_VAL_F32_BUF) {
	                                                        float fv; memcpy(&fv, buf->data + (size_t)elem_idx * 4u, 4u);
	                                                        val.type = AVM_VAL_FLOAT;
	                                                        val.as.f = (double)fv;
	                                                    } else {
	                                                        double dv; memcpy(&dv, buf->data + (size_t)elem_idx * 8u, 8u);
	                                                        val.type = AVM_VAL_FLOAT;
	                                                        val.as.f = dv;
	                                                    }
	                                                }
	                                            }
	                                        }
	                                    }
	                                }
	                            }
	                        }
	                        if (view_ok == 0 && okv.as.i == 0 && idx < l->count) {
	                            okv = avm_int(1);
	                            val = l->items[(int)idx];
	                        }
	                    } else if (container.type == AVM_VAL_MAP && container.as.m) {
	                        AvmMap* m = container.as.m;
                        // Iterable map protocol (rolling): allow maps to represent stream-like iterables.
                        // Used by std/iter.oren:
                        //   {"__iter":"range","start":0,"end":N,"step":1}
                        AvmValue itv;
                        if (avm_map_get_key(container, "__iter", &itv) && itv.type == AVM_VAL_STRING && itv.as.p &&
                            strcmp((const char*)itv.as.p, "range") == 0) {
                            AvmValue sv, ev, stepv;
                            if (avm_map_get_key(container, "start", &sv) && avm_map_get_key(container, "end", &ev) && avm_map_get_key(container, "step", &stepv)) {
                                // Accept int or float (match v0 cast/coercion behavior).
                                // This avoids surprising "empty iteration" when a backend represents numeric literals differently.
                                int have = 1;
                                int64_t start = 0, end = 0, step = 0;
                                if (sv.type == AVM_VAL_INT) start = sv.as.i;
                                else if (sv.type == AVM_VAL_FLOAT) {
                                    double d = sv.as.f;
                                    if (d != d) start = 0;
                                    else {
                                        const double lim = 9223372036854775808.0;
                                        if (d >= lim) start = INT64_MAX;
                                        else if (d <= -lim) start = INT64_MIN;
                                        else start = (int64_t)d;
                                    }
                                } else have = 0;

                                if (ev.type == AVM_VAL_INT) end = ev.as.i;
                                else if (ev.type == AVM_VAL_FLOAT) {
                                    double d = ev.as.f;
                                    if (d != d) end = 0;
                                    else {
                                        const double lim = 9223372036854775808.0;
                                        if (d >= lim) end = INT64_MAX;
                                        else if (d <= -lim) end = INT64_MIN;
                                        else end = (int64_t)d;
                                    }
                                } else have = 0;

                                if (stepv.type == AVM_VAL_INT) step = stepv.as.i;
                                else if (stepv.type == AVM_VAL_FLOAT) {
                                    double d = stepv.as.f;
                                    if (d != d) step = 0;
                                    else {
                                        const double lim = 9223372036854775808.0;
                                        if (d >= lim) step = INT64_MAX;
                                        else if (d <= -lim) step = INT64_MIN;
                                        else step = (int64_t)d;
                                    }
                                } else have = 0;

                                if (have && step != 0) {
                                    int64_t v = start + idx * step;
                                    if ((step > 0 && v < end) || (step < 0 && v > end)) {
                                        okv = avm_int(1);
                                        val = avm_int(v);
                                    }
                                }
                            }
                        } else if (avm_map_get_key(container, "__iter", &itv) && itv.type == AVM_VAL_STRING && itv.as.p &&
                                   strcmp((const char*)itv.as.p, "list_slice") == 0) {
                            // Iterable map protocol (rolling): list slice view.
                            //
                            // Produced by std:list.slice_view(xs, off, n):
                            //   {"__iter":"list_slice","base":xs,"off":off,"len":n}
                            AvmValue basev, offv, lenv;
                            if (avm_map_get_key(container, "base", &basev) &&
                                avm_map_get_key(container, "off", &offv) &&
                                avm_map_get_key(container, "len", &lenv) &&
                                basev.type == AVM_VAL_LIST && basev.as.l &&
                                offv.type == AVM_VAL_INT && lenv.type == AVM_VAL_INT) {
                                int64_t off = offv.as.i;
                                int64_t n = lenv.as.i;
                                if (off >= 0 && n >= 0 && idx < n) {
                                    AvmList* bl = basev.as.l;
                                    if (off <= (int64_t)bl->count) {
                                        int64_t max_n = (int64_t)bl->count - off;
                                        if (n <= max_n) {
                                            int64_t elem_idx = off + idx;
                                            if (elem_idx >= 0 && elem_idx < (int64_t)bl->count) {
                                                okv = avm_int(1);
                                                val = bl->items[(int)elem_idx];
                                            }
                                        }
                                    }
                                }
                            }
                        } else if (idx < m->count) {
                            okv = avm_int(1);
                            val = m->keys[(int)idx]; // map iteration yields keys
                        }
                    } else if (container.type == AVM_VAL_STRING && container.as.p) {
                        const unsigned char* s = (const unsigned char*)container.as.p;
                        size_t n = strlen((const char*)s);
                        if ((uint64_t)idx < (uint64_t)n) {
                            unsigned char ch = s[idx];
                            okv = avm_int(1);
                            val = avm_int((int64_t)ch);
                        }
                    } else if (container.type == AVM_VAL_BYTES && container.as.b) {
                        AvmBytes* b = container.as.b;
                        if (idx < b->len) {
                            okv = avm_int(1);
                            val = avm_int((int64_t)b->data[(int)idx]);
                        }
                    } else if (container.type == AVM_VAL_I32_BUF || container.type == AVM_VAL_I64_BUF ||
                               container.type == AVM_VAL_F32_BUF || container.type == AVM_VAL_F64_BUF) {
                        AvmBuf* b = container.as.buf;
                        if (b && idx < (int64_t)b->len) {
                            okv = avm_int(1);
                            if (container.type == AVM_VAL_I32_BUF) {
                                int32_t v; memcpy(&v, b->data + (size_t)idx * 4u, 4u);
                                val = avm_int((int64_t)v);
                            } else if (container.type == AVM_VAL_I64_BUF) {
                                int64_t v; memcpy(&v, b->data + (size_t)idx * 8u, 8u);
                                val = avm_int(v);
                            } else if (container.type == AVM_VAL_F32_BUF) {
                                float fv; memcpy(&fv, b->data + (size_t)idx * 4u, 4u);
                                val.type = AVM_VAL_FLOAT;
                                val.as.f = (double)fv;
                            } else {
                                double dv; memcpy(&dv, b->data + (size_t)idx * 8u, 8u);
                                val.type = AVM_VAL_FLOAT;
                                val.as.f = dv;
                            }
                        }
                    }
                }

                if (out_pair.type == AVM_VAL_LIST && out_pair.as.l && out_pair.as.l->capacity >= 2 && out_pair.as.l->items) {
                    AvmList* out = out_pair.as.l;
                    if (out->count < 2) out->count = 2;
                    out->items[0] = okv;
                    out->items[1] = val;
                    out->all_int = (okv.type == AVM_VAL_INT && val.type == AVM_VAL_INT);
                    res = out_pair;
                } else {
                    AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                    if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    out->count = 2;
                    out->capacity = 2;
                    out->all_int = (okv.type == AVM_VAL_INT && val.type == AVM_VAL_INT);
                    out->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 2u, AVM_ALLOC_KIND_LIST);
                    if (!out->items) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    out->items[0] = okv;
                    out->items[1] = val;
                    res.type = AVM_VAL_LIST;
                    res.as.l = out;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_iter_next expects (container, int idx, out_pair:list|nil)");
            }
            break;
        }
        case 44: { // oren_string_from_bytes(bytes|list<int 0..255>|list_int) -> string
            if (nargs > 0 && (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int64_t n = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_len_checked(args[0], &n, &err_msg,
                        "string_from_bytes: invalid u8_buf",
                        "string_from_bytes: invalid list",
                        "string_from_bytes: invalid list_int",
                        "oren_string_from_bytes expects (bytes|list|list_int)")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_string_from_bytes expects (bytes|list|list_int)");
                    break;
                }
                char* out = (char*)avm_heap_malloc_k((size_t)n + 1u, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                if (!avm_native_bytes_copy_span(args[0], 0, n, (uint8_t*)out, &err_msg,
                        "string_from_bytes: invalid byte range",
                        "oren_string_from_bytes expects (bytes|list|list_int)",
                        "string_from_bytes: expected list<int 0..255>",
                        "string_from_bytes: expected list_int bytes 0..255")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "string_from_bytes: invalid byte range");
                    break;
                }
                if (!avm_is_err_val(res)) {
                    out[(size_t)n] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = out;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_from_bytes expects (bytes|list|list_int)");
            }
            break;
        }
        case 161: { // oren_string_from_bytes_slice(bytes|list<int 0..255>|list_int, start:int, len:int) -> string
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT &&
                (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int64_t start = args[1].as.i;
                int64_t n = args[2].as.i;
                int64_t total = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_len_checked(args[0], &total, &err_msg,
                        "string_from_bytes_slice: invalid u8_buf",
                        "string_from_bytes_slice: invalid list",
                        "string_from_bytes_slice: invalid list_int",
                        "oren_string_from_bytes_slice expects (bytes|list|list_int, int, int)")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_string_from_bytes_slice expects (bytes|list|list_int, int, int)");
                    break;
                }
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: negative range"); break; }
                if (!avm_native_byte_range_ok(total, start, n)) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: out of bounds"); break; }
                char* out = (char*)avm_heap_malloc_k((size_t)n + 1u, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                if (!avm_native_bytes_copy_span(args[0], start, n, (uint8_t*)out, &err_msg,
                        "string_from_bytes_slice: out of bounds",
                        "oren_string_from_bytes_slice expects (bytes|list|list_int, int, int)",
                        "string_from_bytes_slice: expected list<int 0..255>",
                        "string_from_bytes_slice: expected list_int bytes 0..255")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "string_from_bytes_slice: out of bounds");
                    break;
                }
                if (!avm_is_err_val(res)) {
                    out[(size_t)n] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = out;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_from_bytes_slice expects (bytes|list|list_int, int, int)");
            }
            break;
        }
        case 162: { // oren_u8_buf_from_bytes_slice(bytes|list<int 0..255>|list_int, start:int, len:int) -> u8_buf
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT &&
                (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int64_t start = args[1].as.i;
                int64_t n = args[2].as.i;
                int64_t total = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_len_checked(args[0], &total, &err_msg,
                        "u8_buf_from_bytes_slice: invalid u8_buf",
                        "u8_buf_from_bytes_slice: invalid list",
                        "u8_buf_from_bytes_slice: invalid list_int",
                        "oren_u8_buf_from_bytes_slice expects (bytes|list|list_int, int, int)")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_u8_buf_from_bytes_slice expects (bytes|list|list_int, int, int)");
                    break;
                }
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: negative range"); break; }
                if (!avm_native_byte_range_ok(total, start, n) || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: out of bounds"); break; }
                AvmValue bv = avm_bytes_new((int)n);
                if (bv.type != AVM_VAL_BYTES || !bv.as.b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                if (!avm_native_bytes_copy_span(args[0], start, n, bv.as.b->data, &err_msg,
                        "u8_buf_from_bytes_slice: out of bounds",
                        "oren_u8_buf_from_bytes_slice expects (bytes|list|list_int, int, int)",
                        "u8_buf_from_bytes_slice: expected list<int 0..255>",
                        "u8_buf_from_bytes_slice: expected list_int bytes 0..255")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "u8_buf_from_bytes_slice: out of bounds");
                    break;
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u8_buf_from_bytes_slice expects (bytes|list|list_int, int, int)");
            }
            break;
        }
        case 231: { // oren_u8_buf_from_string_slice(string, start:int, len:int) -> u8_buf
            if (nargs > 2 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                const char* s = (const char*)args[0].as.p;
                int64_t start = args[1].as.i;
                int64_t n = args[2].as.i;
                int64_t total = s ? (int64_t)strlen(s) : 0;
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_string_slice: negative range"); break; }
                if (!avm_native_byte_range_ok(total, start, n) || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_string_slice: out of bounds"); break; }
                AvmValue bv = avm_bytes_new((int)n);
                if (bv.type != AVM_VAL_BYTES || !bv.as.b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                if (n > 0) memcpy(bv.as.b->data, s + start, (size_t)n);
                res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u8_buf_from_string_slice expects (string, int, int)");
            }
            break;
        }
        case 232: { // oren_u8_buf_copy_from_string_slice(u8_buf, string, start:int, len:int) -> u8_buf
            if (nargs > 3 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_STRING &&
                args[2].type == AVM_VAL_INT && args[3].type == AVM_VAL_INT) {
                AvmBytes* out = args[0].as.b;
                const char* s = (const char*)args[1].as.p;
                int64_t start = args[2].as.i;
                int64_t n = args[3].as.i;
                int64_t total = s ? (int64_t)strlen(s) : 0;
                if (!out) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_copy_from_string_slice: out must be u8_buf"); break; }
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_copy_from_string_slice: negative range"); break; }
                if (out->len != (int)n || !avm_native_byte_range_ok(total, start, n) || n > 0x7fffffffLL) {
                    res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_copy_from_string_slice: out of bounds");
                    break;
                }
                if (n > 0) memcpy(out->data, s + start, (size_t)n);
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u8_buf_copy_from_string_slice expects (u8_buf, string, int, int)");
            }
            break;
        }
