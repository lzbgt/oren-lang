        case 53: { // oren_realpath(path:string) -> string (pure lexical normalization)
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                const char* path = (const char*)args[0].as.p;
                size_t n = strlen(path);
                int is_abs = (n > 0 && path[0] == '/');

                typedef struct { const char* s; uint32_t len; } Seg;
                // Worst-case segments <= n (each char could be a 1-byte segment).
                Seg* segs = (Seg*)avm_heap_malloc_k(sizeof(Seg) * (n ? n : 1), AVM_ALLOC_KIND_TMP);
                if (!segs) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                uint32_t seg_count = 0;

                size_t i2 = 0;
                while (i2 <= n) {
                    while (i2 < n && path[i2] == '/') i2++;
                    if (i2 >= n) break;
                    size_t start = i2;
                    while (i2 < n && path[i2] != '/') i2++;
                    size_t end = i2;
                    uint32_t len = (uint32_t)(end - start);
                    const char* seg = path + start;

                    // "."
                    if (len == 1 && seg[0] == '.') continue;

                    // ".."
                    if (len == 2 && seg[0] == '.' && seg[1] == '.') {
                        if (seg_count > 0) {
                            Seg last = segs[seg_count - 1];
                            int last_is_dd = (last.len == 2 && last.s[0] == '.' && last.s[1] == '.');
                            if (is_abs || !last_is_dd) {
                                seg_count--;
                                continue;
                            }
                        }
                        if (!is_abs) {
                            segs[seg_count++] = (Seg){ seg, len };
                        }
                        continue;
                    }

                    segs[seg_count++] = (Seg){ seg, len };
                }

                if (seg_count == 0) {
                    const char* base = is_abs ? "/" : ".";
                    size_t bl = 1;
                    char* out_s = (char*)avm_heap_malloc_k(bl + 1, AVM_ALLOC_KIND_STRING);
                    if (!out_s) { avm_heap_free(segs); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    out_s[0] = base[0]; out_s[1] = 0;
                    avm_heap_free(segs);
                    res.type = AVM_VAL_STRING;
                    res.as.p = out_s;
                    break;
                }

                uint64_t total = is_abs ? 1ull : 0ull;
                for (uint32_t si = 0; si < seg_count; si++) {
                    total += (uint64_t)segs[si].len;
                    if (si + 1 < seg_count) total += 1ull;
                }
                if (total > 0x7fffffffULL) { avm_heap_free(segs); res = avm_err(AVM_ERR_INVALID_ARG, "oren_realpath: path too long"); break; }
                char* out_s = (char*)avm_heap_malloc_k((size_t)total + 1, AVM_ALLOC_KIND_STRING);
                if (!out_s) { avm_heap_free(segs); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }

                uint64_t off = 0;
                if (is_abs) { out_s[0] = '/'; off = 1; }
                for (uint32_t si = 0; si < seg_count; si++) {
                    Seg sg = segs[si];
                    if (sg.len) memcpy(out_s + off, sg.s, sg.len);
                    off += sg.len;
                    if (si + 1 < seg_count) out_s[off++] = '/';
                }
                out_s[total] = 0;
                avm_heap_free(segs);
                res.type = AVM_VAL_STRING;
                res.as.p = out_s;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_realpath expects (string)");
            }
            break;
        }
        case 54: { // oren_i32_buf_new(len:int) -> I32_BUF
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                int64_t n = args[0].as.i;
                if (n < 0 || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "i32_buf_new: invalid length"); break; }
                AvmBuf* b = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                b->len = (uint32_t)n;
                b->elem_size = 4u;
                b->data = NULL;
                uint64_t bytes_len = (uint64_t)b->len * 4ull;
                if (bytes_len > 0) {
                    b->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!b->data) { avm_heap_free(b); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    memset(b->data, 0, (size_t)bytes_len);
                }
                res.type = AVM_VAL_I32_BUF;
                res.as.buf = b;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_i32_buf_new expects (int)");
            }
            break;
        }
        case 152: { // oren_i32_buf_pack_list_int(xs:list<int>) -> i32_buf
            if (nargs > 0 && (args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int count = 0;
                int assume_int = 0;
                if (args[0].type == AVM_VAL_LIST) {
                    if (!args[0].as.l) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: expects list<int>"); break; }
                    count = args[0].as.l->count;
                    assume_int = args[0].as.l->all_int != 0;
                } else {
                    if (!args[0].as.li) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: expects list<int>"); break; }
                    count = args[0].as.li->count;
                    assume_int = 1;
                }
                AvmBuf* b = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                b->len = (uint32_t)count;
                b->elem_size = 4u;
                b->data = NULL;
                uint64_t bytes_len = (uint64_t)b->len * 4ull;
                if (bytes_len > 0) {
                    b->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!b->data) { avm_heap_free(b); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    memset(b->data, 0, (size_t)bytes_len);
                }
                AvmValue outv;
                outv.type = AVM_VAL_I32_BUF;
                outv.as.buf = b;
                if (args[0].type == AVM_VAL_LIST_INT) {
                    for (int i = 0; i < count; i++) {
                        int64_t v = args[0].as.li->items[i];
                        if (v < (int64_t)INT32_MIN || v > (int64_t)INT32_MAX) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: value out of i32 range");
                            break;
                        }
                        uint32_t u = (uint32_t)(int32_t)v;
                        uint32_t off = (uint32_t)i * 4u;
                        b->data[off] = (uint8_t)(u & 0xFFu);
                        b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                        b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                        b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    }
                    if (res.type == AVM_VAL_NIL) res = outv;
                } else {
                    for (int i = 0; i < count; i++) {
                        int32_t lane = 0;
                        int rc = avm_i32_pack_extract(args[0].as.l->items[i], assume_int, &lane);
                        if (rc == 1) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: value not int"); break; }
                        if (rc == 2) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: value out of i32 range"); break; }
                        uint32_t u = (uint32_t)lane;
                        uint32_t off = (uint32_t)i * 4u;
                        b->data[off] = (uint8_t)(u & 0xFFu);
                        b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                        b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                        b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    }
                    if (res.type == AVM_VAL_NIL) res = outv;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int: expects list<int>");
            }
            break;
        }
        case 153: { // oren_i32_buf_pack_list_int_into(out:i32_buf, xs:list<int>) -> i32_buf
            if (nargs > 1 && args[0].type == AVM_VAL_I32_BUF && (args[1].type == AVM_VAL_LIST || args[1].type == AVM_VAL_LIST_INT)) {
                AvmBuf* b = args[0].as.buf;
                if (!b || b->elem_size != 4u) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: expects []i32"); break; }
                int count = 0;
                int assume_int = 0;
                if (args[1].type == AVM_VAL_LIST) {
                    if (!args[1].as.l) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: expects list<int>"); break; }
                    count = args[1].as.l->count;
                    assume_int = args[1].as.l->all_int != 0;
                } else {
                    if (!args[1].as.li) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: expects list<int>"); break; }
                    count = args[1].as.li->count;
                    assume_int = 1;
                }
                if ((uint32_t)count != b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: length mismatch"); break; }
                if (count > 0 && !b->data) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: expects []i32"); break; }
                if (args[1].type == AVM_VAL_LIST_INT) {
                    for (int i = 0; i < count; i++) {
                        int64_t v = args[1].as.li->items[i];
                        if (v < (int64_t)INT32_MIN || v > (int64_t)INT32_MAX) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: value out of i32 range");
                            break;
                        }
                        uint32_t u = (uint32_t)(int32_t)v;
                        uint32_t off = (uint32_t)i * 4u;
                        b->data[off] = (uint8_t)(u & 0xFFu);
                        b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                        b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                        b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    }
                } else {
                    for (int i = 0; i < count; i++) {
                        int32_t lane = 0;
                        int rc = avm_i32_pack_extract(args[1].as.l->items[i], assume_int, &lane);
                        if (rc == 1) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: value not int"); break; }
                        if (rc == 2) { res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: value out of i32 range"); break; }
                        uint32_t u = (uint32_t)lane;
                        uint32_t off = (uint32_t)i * 4u;
                        b->data[off] = (uint8_t)(u & 0xFFu);
                        b->data[off + 1] = (uint8_t)((u >> 8) & 0xFFu);
                        b->data[off + 2] = (uint8_t)((u >> 16) & 0xFFu);
                        b->data[off + 3] = (uint8_t)((u >> 24) & 0xFFu);
                    }
                }
                if (res.type == AVM_VAL_NIL) res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "buffer.i32_pack_list_int_into: expects []i32");
            }
            break;
        }
        case 154: { // oren_is_list_int(v) -> bool
            if (nargs > 0) {
                int ok = 0;
                if (args[0].type == AVM_VAL_LIST_INT) {
                    ok = args[0].as.li != NULL;
                } else if (args[0].type == AVM_VAL_LIST) {
                    ok = (args[0].as.l != NULL && args[0].as.l->all_int != 0);
                }
                res.type = AVM_VAL_BOOL;
                res.as.i = ok ? 1 : 0;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_is_list_int expects (list)");
            }
            break;
        }
        case 155: { // oren_list_int_reduce_sum_slots(list) -> int
            if (nargs > 0) {
                if (args[0].type == AVM_VAL_NIL) {
                    res.type = AVM_VAL_INT;
                    res.as.i = 0;
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[0].as.li) {
                    AvmListInt* list = args[0].as.li;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i];
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[0].as.l && args[0].as.l->all_int != 0) {
                    AvmList* list = args[0].as.l;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i].as.i;
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_reduce_sum_slots expects list<int>");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_reduce_sum_slots expects list<int>");
            }
            break;
        }
        case 156: { // oren_list_int_reduce_sum_slots_unchecked(list) -> int
            if (nargs > 0) {
                if (args[0].type == AVM_VAL_NIL) {
                    res.type = AVM_VAL_INT;
                    res.as.i = 0;
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[0].as.li) {
                    AvmListInt* list = args[0].as.li;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i];
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[0].as.l && args[0].as.l->all_int != 0) {
                    AvmList* list = args[0].as.l;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i].as.i;
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_reduce_sum_slots_unchecked expects list<int>");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_reduce_sum_slots_unchecked expects list<int>");
            }
            break;
        }
        case 157: { // oren_list_int_dot_slots(a, b) -> int
            if (nargs > 1) {
                if (args[0].type == AVM_VAL_NIL || args[1].type == AVM_VAL_NIL) {
                    if (args[0].type == AVM_VAL_NIL && args[1].type == AVM_VAL_NIL) {
                        res.type = AVM_VAL_INT;
                        res.as.i = 0;
                    } else {
                        res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots: length mismatch");
                    }
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[1].type == AVM_VAL_LIST_INT &&
                    args[0].as.li && args[1].as.li) {
                    AvmListInt* a = args[0].as.li;
                    AvmListInt* b = args[1].as.li;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i] * (int64_t)b->items[i];
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[1].type == AVM_VAL_LIST &&
                    args[0].as.l && args[1].as.l &&
                    args[0].as.l->all_int != 0 && args[1].as.l->all_int != 0) {
                    AvmList* a = args[0].as.l;
                    AvmList* b = args[1].as.l;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i].as.i * (int64_t)b->items[i].as.i;
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_dot_slots expects (list<int>, list<int>)");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_dot_slots expects (list<int>, list<int>)");
            }
            break;
        }
        case 158: { // oren_list_int_dot_slots_unchecked(a, b) -> int
            if (nargs > 1) {
                if (args[0].type == AVM_VAL_NIL || args[1].type == AVM_VAL_NIL) {
                    if (args[0].type == AVM_VAL_NIL && args[1].type == AVM_VAL_NIL) {
                        res.type = AVM_VAL_INT;
                        res.as.i = 0;
                    } else {
                        res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots_unchecked: length mismatch");
                    }
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[1].type == AVM_VAL_LIST_INT &&
                    args[0].as.li && args[1].as.li) {
                    AvmListInt* a = args[0].as.li;
                    AvmListInt* b = args[1].as.li;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots_unchecked: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i] * (int64_t)b->items[i];
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[1].type == AVM_VAL_LIST &&
                    args[0].as.l && args[1].as.l &&
                    args[0].as.l->all_int != 0 && args[1].as.l->all_int != 0) {
                    AvmList* a = args[0].as.l;
                    AvmList* b = args[1].as.l;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots_unchecked: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i].as.i * (int64_t)b->items[i].as.i;
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_dot_slots_unchecked expects (list<int>, list<int>)");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_dot_slots_unchecked expects (list<int>, list<int>)");
            }
            break;
        }
        case 159: { // oren_list_int_reduce_sum_slots_try_fast(list) -> int|nil
            if (nargs > 0) {
                if (args[0].type == AVM_VAL_NIL) {
                    res.type = AVM_VAL_INT;
                    res.as.i = 0;
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[0].as.li) {
                    AvmListInt* list = args[0].as.li;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i];
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[0].as.l && args[0].as.l->all_int != 0) {
                    AvmList* list = args[0].as.l;
                    for (int i = 0; i < list->count; i++) acc += (uint64_t)list->items[i].as.i;
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res.type = AVM_VAL_NIL;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_reduce_sum_slots_try_fast expects (list)");
            }
            break;
        }
        case 160: { // oren_list_int_dot_slots_try_fast(a, b) -> int|err|nil
            if (nargs > 1) {
                if (args[0].type == AVM_VAL_NIL || args[1].type == AVM_VAL_NIL) {
                    if (args[0].type == AVM_VAL_NIL && args[1].type == AVM_VAL_NIL) {
                        res.type = AVM_VAL_INT;
                        res.as.i = 0;
                    } else {
                        res.type = AVM_VAL_NIL;
                    }
                    break;
                }
                uint64_t acc = 0;
                if (args[0].type == AVM_VAL_LIST_INT && args[1].type == AVM_VAL_LIST_INT &&
                    args[0].as.li && args[1].as.li) {
                    AvmListInt* a = args[0].as.li;
                    AvmListInt* b = args[1].as.li;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i] * (int64_t)b->items[i];
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                if (args[0].type == AVM_VAL_LIST && args[1].type == AVM_VAL_LIST &&
                    args[0].as.l && args[1].as.l &&
                    args[0].as.l->all_int != 0 && args[1].as.l->all_int != 0) {
                    AvmList* a = args[0].as.l;
                    AvmList* b = args[1].as.l;
                    if (a->count != b->count) { res = avm_err(AVM_ERR_INVALID_ARG, "list_int_dot_slots: length mismatch"); break; }
                    for (int i = 0; i < a->count; i++) {
                        int64_t prod = (int64_t)a->items[i].as.i * (int64_t)b->items[i].as.i;
                        acc += (uint64_t)prod;
                    }
                    res.type = AVM_VAL_INT;
                    res.as.i = (int64_t)acc;
                    break;
                }
                res.type = AVM_VAL_NIL;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_int_dot_slots_try_fast expects (a, b)");
            }
            break;
        }
        case 55: { // oren_i64_buf_new(len:int) -> I64_BUF
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                int64_t n = args[0].as.i;
                if (n < 0 || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "i64_buf_new: invalid length"); break; }
                AvmBuf* b = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                b->len = (uint32_t)n;
                b->elem_size = 8u;
                b->data = NULL;
                uint64_t bytes_len = (uint64_t)b->len * 8ull;
                if (bytes_len > 0) {
                    b->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!b->data) { avm_heap_free(b); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    memset(b->data, 0, (size_t)bytes_len);
                }
                res.type = AVM_VAL_I64_BUF;
                res.as.buf = b;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_i64_buf_new expects (int)");
            }
            break;
        }
        case 56: { // oren_f32_buf_new(len:int) -> F32_BUF
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                int64_t n = args[0].as.i;
                if (n < 0 || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "f32_buf_new: invalid length"); break; }
                AvmBuf* b = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                b->len = (uint32_t)n;
                b->elem_size = 4u;
                b->data = NULL;
                uint64_t bytes_len = (uint64_t)b->len * 4ull;
                if (bytes_len > 0) {
                    b->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!b->data) { avm_heap_free(b); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    memset(b->data, 0, (size_t)bytes_len);
                }
                res.type = AVM_VAL_F32_BUF;
                res.as.buf = b;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_f32_buf_new expects (int)");
            }
            break;
        }
        case 57: { // oren_f64_buf_new(len:int) -> F64_BUF
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                int64_t n = args[0].as.i;
                if (n < 0 || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "f64_buf_new: invalid length"); break; }
                AvmBuf* b = (AvmBuf*)avm_heap_malloc_k(sizeof(AvmBuf), AVM_ALLOC_KIND_BUF);
                if (!b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                b->len = (uint32_t)n;
                b->elem_size = 8u;
                b->data = NULL;
                uint64_t bytes_len = (uint64_t)b->len * 8ull;
                if (bytes_len > 0) {
                    b->data = (uint8_t*)avm_heap_malloc_k((size_t)bytes_len, AVM_ALLOC_KIND_RAW);
                    if (!b->data) { avm_heap_free(b); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    memset(b->data, 0, (size_t)bytes_len);
                }
                res.type = AVM_VAL_F64_BUF;
                res.as.buf = b;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_f64_buf_new expects (int)");
            }
            break;
        }
	        case 58: { // oren_buf_len(buf) -> int
	            // In AVM, u8 buffers are represented as BYTES.
	            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
	                AvmBytes* b = args[0].as.b;
	                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_len: null u8 buffer"); break; }
	                res = avm_int((int64_t)b->len);
	            } else if (nargs > 0 && (args[0].type == AVM_VAL_I32_BUF || args[0].type == AVM_VAL_I64_BUF || args[0].type == AVM_VAL_F32_BUF || args[0].type == AVM_VAL_F64_BUF)) {
	                AvmBuf* b = args[0].as.buf;
	                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_len: null buffer"); break; }
	                res = avm_int((int64_t)b->len);
	            } else {
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_len expects (buf)");
	            }
	            break;
	        }
	        case 142: { // oren_u8_buf_new(len:int) -> u8_buf (AVM: BYTES)
	            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
	                int64_t n = args[0].as.i;
	                if (n < 0 || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_new: invalid length"); break; }
	                AvmValue bv = avm_bytes_new((int)n);
	                if (bv.type != AVM_VAL_BYTES || !bv.as.b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
	                res = bv;
	            } else {
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u8_buf_new expects (int)");
	            }
	            break;
	        }
	        case 143: { // oren_buf_load_u8(u8_buf, idx) -> int
	            if (nargs > 1 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT) {
	                AvmBytes* b = args[0].as.b;
	                int64_t idx = args[1].as.i;
	                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_u8: null buffer"); break; }
	                if (idx < 0 || idx >= (int64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_load_u8: index out of bounds"); break; }
	                res = avm_int((int64_t)b->data[(int)idx]);
	            } else {
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_load_u8 expects (u8_buf, int)");
	            }
	            break;
	        }
	        case 144: { // oren_buf_store_u8(u8_buf, idx, val) -> u8_buf
	            if (nargs > 2 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
	                AvmBytes* b = args[0].as.b;
	                int64_t idx = args[1].as.i;
	                int64_t v = args[2].as.i;
	                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_u8: null buffer"); break; }
	                if (idx < 0 || idx >= (int64_t)b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_u8: index out of bounds"); break; }
	                if (v < 0 || v > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_store_u8: byte out of range"); break; }
	                b->data[(int)idx] = (uint8_t)v;
	                res = args[0];
	            } else {
	                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_store_u8 expects (u8_buf, int, int)");
	            }
	            break;
	        }
		        case 145: { // oren_buf_fill_u8(u8_buf, v) -> u8_buf
		            if (nargs > 1 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT) {
		                AvmBytes* b = args[0].as.b;
		                int64_t v = args[1].as.i;
		                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_u8: null buffer"); break; }
		                if (v < 0 || v > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_fill_u8: byte out of range"); break; }
		                if (b->len > 0 && b->data) memset(b->data, (unsigned char)v, (size_t)b->len);
		                res = args[0];
		            } else {
		                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_fill_u8 expects (u8_buf, int)");
		            }
		            break;
		        }
        case 146: { // oren_type_tag(v) -> int
            if (nargs > 0) {
                res = avm_int(avm_oren_type_tag(args[0]));
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_type_tag expects (value)");
            }
            break;
        }
        case 150: { // oren_type_name(v) -> string
            if (nargs > 0) {
                AvmValue v = args[0];
                if (v.type == AVM_VAL_MAP) {
                    AvmValue outv;
                    if (avm_map_get_key(v, "__oren_type", &outv)) {
                        if (outv.type == AVM_VAL_STRING) { res = outv; break; }
                    }
                    res = avm_string("map");
                } else {
                    res = avm_string(avm_oren_type_name_from_tag(avm_oren_type_tag(v)));
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_type_name expects (value)");
            }
            break;
        }
        case 163: { // oren_generator_handle_new_internal(worker, args_list, yield_ch, resume_ch, done_ch)
            if (nargs > 4) {
                res = avm_generator_handle_new_internal_value(vm, args[0], args[1], args[2], args[3], args[4]);
                if (avm_is_err_val(res)) avm_abort(vm, res);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_generator_handle_new_internal expects (worker, args_list, yield_ch, resume_ch, done_ch)");
            }
            break;
        }
        case 164: { // oren_generator_context_new_internal(yield_ch, resume_ch, owner)
            if (nargs > 2) {
                res = avm_generator_context_new_internal_value(vm, args[0], args[1], args[2]);
                if (avm_is_err_val(res)) avm_abort(vm, res);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_generator_context_new_internal expects (yield_ch, resume_ch, owner)");
            }
            break;
        }
        case 165: { // oren_generator_slot_get_internal(obj, slot)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                AvmValue* p = avm_generator_slot_ptr(args[0], args[1].as.i);
                res = p ? *p : avm_nil();
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_generator_slot_get_internal expects (generator_like, int)");
            }
            break;
        }
        case 166: { // oren_generator_slot_set_internal(obj, slot, value)
            if (nargs > 2 && args[1].type == AVM_VAL_INT) {
                AvmValue* p = avm_generator_slot_ptr(args[0], args[1].as.i);
                if (p) {
                    *p = args[2];
                    res = args[2];
                } else {
                    res = avm_nil();
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_generator_slot_set_internal expects (generator_like, int, value)");
            }
            break;
        }
        case 167: { // oren_task_is_handle(v) -> bool
            int ok = 0;
            if (nargs > 0 && args[0].type == AVM_VAL_INT && vm && vm->sched) {
                AvmSched* sched = (AvmSched*)vm->sched;
                int tid = (int)args[0].as.i - 1;
                if (tid >= 0 && tid < sched->task_cap && sched->tasks[tid].used) {
                    ok = 1;
                }
            }
            res = avm_bool(ok);
            break;
        }
        case 168: { // oren_task_is_done(v) -> bool
            int done = 0;
            if (nargs > 0 && args[0].type == AVM_VAL_INT && vm && vm->sched) {
                AvmSched* sched = (AvmSched*)vm->sched;
                int tid = (int)args[0].as.i - 1;
                if (tid >= 0 && tid < sched->task_cap && sched->tasks[tid].used) {
                    done = sched->tasks[tid].done ? 1 : 0;
                }
            }
            res = avm_bool(done);
            break;
        }
        case 178: { // oren_task_current_handle() -> handle|nil
            res = avm_task_current_handle(vm);
            break;
        }
        case 179: { // oren_task_request_cancel(handle, reason) -> nil|err
            if (!vm || nargs <= 1) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_request_cancel expects (handle, reason)");
                break;
            }
            res = avm_task_request_cancel(vm, args[0], args[1]);
            break;
        }
        case 180: { // oren_task_is_cancel_requested(handle) -> bool
            if (!vm || nargs <= 0) {
                res = avm_bool(0);
                break;
            }
            res = avm_task_is_cancel_requested(vm, args[0]);
            break;
        }
        case 181: { // oren_task_cancel_reason(handle) -> any|nil
            if (!vm || nargs <= 0) {
                res = avm_nil();
                break;
            }
            res = avm_task_cancel_reason(vm, args[0]);
            break;
        }
        case 186: { // oren_task_cancel_now(handle, reason) -> stop-result map
            if (!vm || nargs <= 1) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_cancel_now expects (handle, reason)");
                break;
            }
            res = avm_task_cancel_now(vm, args[0], args[1]);
            break;
        }
        case 169: { // oren_task_group_new() -> group_handle
            if (!vm) { res = avm_err(AVM_ERR_INTERNAL, "oren_task_group_new: missing vm"); break; }
            res = avm_task_group_new(vm);
            break;
        }
        case 170: { // oren_task_group_is_handle(v) -> bool
            int ok = (vm && nargs > 0) ? avm_task_group_is_handle(vm, args[0]) : 0;
            res = avm_bool(ok);
            break;
        }
        case 171: { // oren_task_group_add(group, handle) -> handle|err
            if (!vm || nargs <= 1) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_add expects (group, handle)");
                break;
            }
            res = avm_task_group_add(vm, args[0], args[1]);
            break;
        }
        case 172: { // oren_task_group_count(group) -> int
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_count expects (group)");
                break;
            }
            res = avm_task_group_count(vm, args[0]);
            break;
        }
        case 173: { // oren_task_group_members(group) -> list
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_members expects (group)");
                break;
            }
            res = avm_task_group_members(vm, args[0]);
            break;
        }
        case 182: { // oren_task_group_member_kinds(group) -> list
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_member_kinds expects (group)");
                break;
            }
            res = avm_task_group_member_kinds(vm, args[0]);
            break;
        }
        case 183: { // oren_task_group_member_snapshot(group) -> [members, kinds]
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_member_snapshot expects (group)");
                break;
            }
            res = avm_task_group_member_snapshot(vm, args[0]);
            break;
        }
        case 184: { // oren_task_group_snapshot(group) -> [members, kinds, default_policy]
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_snapshot expects (group)");
                break;
            }
            res = avm_task_group_snapshot(vm, args[0]);
            break;
        }
        case 185: { // oren_task_group_take_snapshot(group) -> [members, kinds, default_policy] and clear
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_take_snapshot expects (group)");
                break;
            }
            res = avm_task_group_take_snapshot(vm, args[0]);
            break;
        }
        case 174: { // oren_task_group_clear(group) -> nil
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_clear expects (group)");
                break;
            }
            res = avm_task_group_clear(vm, args[0]);
            break;
        }
        case 175: { // oren_task_group_spawn_call_list(group, fn, args_list) -> handle|err
            if (!vm || nargs <= 2) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_spawn_call_list expects (group, fn, args_list)");
                break;
            }
            res = avm_task_group_spawn_call_list(vm, args[0], args[1], args[2]);
            break;
        }
        case 176: { // oren_task_group_default_policy(group) -> map|nil
            if (!vm || nargs <= 0) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_default_policy expects (group)");
                break;
            }
            res = avm_task_group_default_policy(vm, args[0]);
            break;
        }
        case 177: { // oren_task_group_set_default_policy(group, policy) -> policy|nil|err
            if (!vm || nargs <= 1) {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_task_group_set_default_policy expects (group, policy)");
                break;
            }
            res = avm_task_group_set_default_policy(vm, args[0], args[1]);
            break;
        }
        case 151: { // oren_string_eq(a, b) -> bool
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) {
                const char* a = (const char*)args[0].as.p;
                const char* b = (const char*)args[1].as.p;
                if (!a || !b) { res = avm_bool(0); }
                else { res = avm_bool(strcmp(a, b) == 0); }
            } else {
                res = avm_bool(0);
            }
            break;
        }
		        case 147: { // oren_map_get_str(map, key:string) -> value|nil
		            if (nargs > 1) {
		                AvmValue mapv = args[0];
		                AvmValue keyv = args[1];
		                if (mapv.type != AVM_VAL_MAP || !mapv.as.m) { res = avm_nil(); break; }
		                if (keyv.type == AVM_VAL_NIL) { res = avm_nil(); break; }
		                if (keyv.type != AVM_VAL_STRING || !keyv.as.p) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_get_str expects (map, string)"); break; }
		                AvmValue outv;
		                if (avm_map_get_key(mapv, (const char*)keyv.as.p, &outv)) res = outv;
		                else res = avm_nil();
		            } else {
		                res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_get_str expects (map, string)");
		            }
		            break;
		        }
		        case 148: { // oren_map_set_str(map, key:string, value) -> value
		            if (nargs > 2) {
		                AvmValue mapv = args[0];
		                AvmValue keyv = args[1];
		                AvmValue valv = args[2];
		                if (mapv.type != AVM_VAL_MAP || !mapv.as.m) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_set_str expects (map, string, value)"); break; }
		                if (keyv.type != AVM_VAL_STRING || !keyv.as.p) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_set_str expects non-nil string key"); break; }
		                if (!avm_map_set_sorted(mapv.as.m, keyv, valv)) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
		                res = valv;
		            } else {
		                res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_set_str expects (map, string, value)");
		            }
		            break;
		        }
