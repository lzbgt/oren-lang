AvmValue avm_call_native(AvmVM* vm, uint16_t id, AvmValue* args, int nargs) {
    AvmValue res; res.type = AVM_VAL_NIL;
    switch(id) {
        case 0: { // oren_read_file
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                if (fseek(f, 0, SEEK_END) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: fseek failed");
                    break;
                }
                long len = ftell(f);
                if (len < 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: ftell failed");
                    break;
                }
                if (fseek(f, 0, SEEK_SET) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_file: fseek failed");
                    break;
                }
                // Preflight: ensure the record log has space BEFORE performing the read in record mode.
                // For read_file, the return shape is a single STRING of length `len`.
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    // entry_size = (domain/op header+hashes) 68 + value_size(STRING) (18 + len) = 86 + len
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    uint64_t need = 86ull + (uint64_t)len;
                    if (!avm_log_can_fit(vm, need)) {
                        fclose(f);
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        break;
                    }
                }
                char* buf = (char*)avm_heap_malloc((size_t)len + 1);
                if (!buf) {
                    fclose(f);
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                size_t n = fread(buf, 1, (size_t)len, f);
                buf[len] = 0;
                fclose(f);
                if (n != (size_t)len) {
                    avm_heap_free(buf);
                    res = avm_err(AVM_ERR_IO, "read_file: short read");
                    break;
                }
                (void)avm_io_charge(vm, (uint64_t)len, 1, 0);
                res.type = AVM_VAL_STRING;
                res.as.p = buf;
            }
            break;
        }
        case 1: { // oren_write_file
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                char* data = (char*)args[1].as.p;
                // Preflight: ensure record log can store this entry BEFORE performing any filesystem effects.
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    // entry_size for NIL return: 68 + value_size(NIL)=13 => 81
                    if (!avm_log_can_fit(vm, 81ull)) {
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        break;
                    }
                }
                FILE* f = fopen(path, "wb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for write: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                size_t len = strlen(data);
                if (!avm_io_charge(vm, (uint64_t)len, 1, 1)) { fclose(f); break; }
                size_t n = fwrite(data, 1, len, f);
                fclose(f);
                if (n != len) {
                    res = avm_err(AVM_ERR_IO, "write_file: short write");
                    break;
                }
            }
            break;
        }
        case 2: { // oren_system
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                // Preflight: ensure record log can store this entry BEFORE executing the command.
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    // entry_size for INT return: value_size(INT)=13 => 81
                    if (!avm_log_can_fit(vm, 81ull)) {
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        break;
                    }
                }
                int ret = system((char*)args[0].as.p);
                res.type = AVM_VAL_INT;
                res.as.i = ret;
            }
            break;
        }
        case 3: { // oren_args
            AvmList* list = (AvmList*)avm_heap_malloc(sizeof(AvmList));
            if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            list->count = vm->argc;
            list->capacity = vm->argc;
            list->items = NULL;
            if (vm->argc > 0) {
                list->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)vm->argc);
                if (!list->items) { avm_heap_free(list); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            }
            for (int i = 0; i < vm->argc; i++) {
                list->items[i] = avm_string(vm->argv ? vm->argv[i] : "");
                if (avm_is_err_val(list->items[i])) {
                    res = list->items[i];
                    avm_abort(vm, res);
                    break;
                }
            }
            if (!avm_is_err_val(res)) {
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 4: { // oren_env
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* val = getenv((char*)args[0].as.p);
                if (val) {
                    // Preflight (best-effort): ensure record log can store the returned string.
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        uint8_t dom = 0;
                        uint16_t capop = 0;
                        avm_legacy_native_to_domop(id, &dom, &capop);
                        uint64_t n = (uint64_t)strlen(val);
                        uint64_t need = 86ull + n;
                        if (!avm_log_can_fit(vm, need)) {
                            AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                            avm_abort(vm, e);
                            res = e;
                            break;
                        }
                    }
                    res.type = AVM_VAL_STRING;
                    res.as.p = my_strdup(val);
                }
            }
            break;
        }
        case 5: { // oren_exit
            // AVM semantics (rolling): exit terminates the VM run, not the host process.
            // This is required for record/replay and consensus hashing to work reliably.
            if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                uint8_t dom = 0;
                uint16_t capop = 0;
                avm_legacy_native_to_domop(id, &dom, &capop);
                if (!avm_log_can_fit(vm, 81ull)) {
                    AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                    avm_abort(vm, e);
                    res = e;
                    break;
                }
            }
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                vm->exit_code = (int)args[0].as.i;
            } else {
                vm->exit_code = 0;
            }
            vm->running = 0;
            res = avm_nil();
            break;
        }
        case 6: // oren_string_len
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                res.type = AVM_VAL_INT;
                res.as.i = strlen((char*)args[0].as.p);
            }
            break;
        case 7: // oren_string_char_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_INT) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_STRING;
                    char* buf = (char*)avm_heap_malloc(2);
                    if (!buf) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    buf[0] = s[idx];
                    buf[1] = 0;
                    res.as.p = buf;
                }
            }
            break;
        case 8: { // oren_string_slice
            if (nargs > 2 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int start = (int)args[1].as.i;
                int end = (int)args[2].as.i;
                int len = strlen(s);
                if (start >= 0 && end <= len && start <= end) {
                    int sublen = end - start;
                    char* buf = (char*)avm_heap_malloc((size_t)sublen + 1);
                    if (!buf) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    strncpy(buf, s + start, sublen);
                    buf[sublen] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = buf;
                }
            }
            break;
        }
        case 9: { // oren_string_char_code_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_INT;
                    res.as.i = (unsigned char)s[idx];
                }
            }
            break;
        }
        case 10: { // oren_int_to_string
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                char buf[32];
                sprintf(buf, "%lld", args[0].as.i);
                res.type = AVM_VAL_STRING;
                res.as.p = my_strdup(buf);
            }
            break;
        }
        case 12: // oren_list_len
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.l->count;
            }
            break;
        case 13: // oren_list_push
            if (nargs > 1 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (list->count >= list->capacity) {
                    int new_cap = list->capacity ? list->capacity * 2 : 8;
                    AvmValue* ni = (AvmValue*)avm_heap_realloc(list->items, sizeof(AvmValue) * (size_t)new_cap);
                    if (!ni) {
                        res = avm_alloc_fail_value();
                        avm_abort(vm, res);
                        break;
                    }
                    list->capacity = new_cap;
                    list->items = ni;
                }
                list->items[list->count++] = args[1];
            }
            break;
        case 14: { // oren_index_set
            if (nargs > 2 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < list->count) {
                    list->items[idx] = args[2];
                }
            }
            break;
        }
        case 15: { // int_mod
            if (nargs > 1) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.i % args[1].as.i;
            }
            break;
        }
        case 16: { // oren_bytes_from_string
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int len = strlen(s);
                AvmList* list = (AvmList*)avm_heap_malloc(sizeof(AvmList));
                if (!list) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->count = len;
                list->capacity = len;
                list->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)len);
                if (!list->items && len > 0) {
                    avm_heap_free(list);
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                for(int i=0; i<len; i++) {
                    list->items[i].type = AVM_VAL_INT;
                    list->items[i].as.i = (unsigned char)s[i];
                }
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 17: { // oren_write_bytes
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_LIST) {
                char* path = (char*)args[0].as.p;
                AvmList* list = args[1].as.l;
                // Preflight: ensure record log can store this entry BEFORE performing any filesystem effects.
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    if (!avm_log_can_fit(vm, 81ull)) {
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        break;
                    }
                }
                uint8_t* buf = (uint8_t*)avm_heap_malloc((size_t)list->count);
                if (!buf && list->count > 0) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                for(int i=0; i<list->count; i++) {
                    buf[i] = (uint8_t)list->items[i].as.i;
                }
                FILE* f = fopen(path, "wb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for write: %s (errno=%d)", path, err);
                    avm_heap_free(buf);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                if (!avm_io_charge(vm, (uint64_t)list->count, 1, 2)) { fclose(f); avm_heap_free(buf); break; }
                size_t n = fwrite(buf, 1, (size_t)list->count, f);
                fclose(f);
                avm_heap_free(buf);
                if (n != (size_t)list->count) {
                    res = avm_err(AVM_ERR_IO, "write_bytes: short write");
                    break;
                }
            }
            break;
        }
        case 18: { // oren_read_bytes
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }

                if (fseek(f, 0, SEEK_END) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: fseek failed");
                    break;
                }
                long len = ftell(f);
                if (len < 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: ftell failed");
                    break;
                }
                if (fseek(f, 0, SEEK_SET) != 0) {
                    int err = errno;
                    fclose(f);
                    res = avm_err(avm_err_from_errno(err), "read_bytes: fseek failed");
                    break;
                }

                // Preflight: ensure the record log has space BEFORE performing the read in record mode.
                // For read_bytes, the return shape is LIST<int> of length `len` (legacy behavior).
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    // value_size(LIST of aux=len): 18 + len*9; entry_size: 68 + that = 86 + len*9
                    uint64_t need = 86ull + (uint64_t)len * 9ull;
                    if (!avm_log_can_fit(vm, need)) {
                        fclose(f);
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        break;
                    }
                }

                uint8_t* buf = NULL;
                if (len > 0) {
                    buf = (uint8_t*)avm_heap_malloc((size_t)len);
                    if (!buf) {
                        fclose(f);
                        res = avm_alloc_fail_value();
                        avm_abort(vm, res);
                        break;
                    }
                    size_t n = fread(buf, 1, (size_t)len, f);
                    if (n != (size_t)len) {
                        avm_heap_free(buf);
                        fclose(f);
                        res = avm_err(AVM_ERR_IO, "read_bytes: short read");
                        break;
                    }
                }
                fclose(f);
                (void)avm_io_charge(vm, (uint64_t)len, 1, 3);

                AvmList* list = (AvmList*)avm_heap_malloc(sizeof(AvmList));
                if (!list) {
                    if (buf) avm_heap_free(buf);
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->count = (int)len;
                list->capacity = (int)len;
                if (len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)len);
                    if (!list->items) {
                        avm_heap_free(list);
                        if (buf) avm_heap_free(buf);
                        res = avm_alloc_fail_value();
                        avm_abort(vm, res);
                        break;
                    }
                    for (long i = 0; i < len; i++) {
                        list->items[i].type = AVM_VAL_INT;
                        list->items[i].as.i = (unsigned char)buf[i];
                    }
                } else {
                    list->items = NULL;
                }
                if (buf) avm_heap_free(buf);

                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 19: { // oren_err(code, msg)
            if (nargs > 1 && args[0].type == AVM_VAL_INT && args[1].type == AVM_VAL_STRING) {
                res = avm_err((int)args[0].as.i, (char*)args[1].as.p);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_err expects (int, string)");
            }
            break;
        }
        case 20: { // oren_is_err(v)
            if (nargs > 0) {
                res = avm_bool(avm_is_err_val(args[0]));
            } else {
                res = avm_bool(0);
            }
            break;
        }
        case 21: { // oren_err_code(v)
            if (nargs > 0 && avm_is_err_val(args[0])) {
                AvmValue c = avm_map_get(args[0].as.m, "code");
                if (c.type == AVM_VAL_INT) res = c;
                else res = avm_int(-1);
            } else {
                res = avm_int(-1);
            }
            break;
        }
        case 22: { // oren_err_msg(v)
            if (nargs > 0 && avm_is_err_val(args[0])) {
                AvmValue m = avm_map_get(args[0].as.m, "msg");
                if (m.type == AVM_VAL_STRING) res = m;
                else res = avm_nil();
            } else {
                res = avm_nil();
            }
            break;
        }
        case 23: { // oren_set_result(v)
            if (nargs > 0) {
                vm->result_value = args[0];
                vm->has_result_value = 1;
                res = args[0];
            } else {
                vm->result_value = avm_nil();
                vm->has_result_value = 0;
                res = avm_nil();
            }
            break;
        }
        case 24: { // oren_get_result()
            if (vm->has_result_value) res = vm->result_value;
            else res = avm_nil();
            break;
        }
        case 30: { // oren_bytes_pack(list<int 0..255>) -> bytes
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: invalid list"); break; }
                AvmValue bv = avm_bytes_new(list->count);
                if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "bytes_pack: out of memory"); break; }
                for (int i = 0; i < list->count; i++) {
                    AvmValue it = list->items[i];
                    if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                        res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: expected int bytes 0..255");
                        break;
                    }
                    bv.as.b->data[i] = (uint8_t)it.as.i;
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_pack expects (list)");
            }
            break;
        }
        case 31: { // oren_bytes_unpack(bytes) -> list<int>
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid bytes"); break; }
                AvmList* list = (AvmList*)avm_heap_malloc(sizeof(AvmList));
                if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                list->count = b->len;
                list->capacity = b->len;
                list->items = NULL;
                if (b->len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)b->len);
                    if (!list->items) { avm_heap_free(list); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                    for (int i = 0; i < b->len; i++) {
                        list->items[i] = avm_int((int64_t)b->data[i]);
                    }
                }
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_unpack expects (bytes)");
            }
            break;
        }
        case 32: { // oren_bytes_len(bytes) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                res = avm_int(b ? (int64_t)b->len : 0);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_len expects (bytes)");
            }
            break;
        }
        case 33: { // oren_bytes_get_u8(bytes, idx) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT) {
                AvmBytes* b = args[0].as.b;
                int64_t idx = args[1].as.i;
                if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: index out of bounds"); break; }
                res = avm_int((int64_t)b->data[(int)idx]);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u8 expects (bytes, int)");
            }
            break;
        }
        case 34: { // oren_bytes_set_u8(bytes, idx, val) -> bytes
            if (nargs > 2 && args[0].type == AVM_VAL_BYTES && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                AvmBytes* b = args[0].as.b;
                int64_t idx = args[1].as.i;
                int64_t val = args[2].as.i;
                if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: index out of bounds"); break; }
                if (val < 0 || val > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: expected 0..255"); break; }
                b->data[(int)idx] = (uint8_t)val;
                res = args[0];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u8 expects (bytes, int, int)");
            }
            break;
        }
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
        case 36: { // oren_bytes_to_hex(bytes) -> string
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                if (!b || b->len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: invalid bytes"); break; }
                static const char* hexd = "0123456789abcdef";
                size_t out_len = (size_t)b->len * 2;
                char* out = (char*)avm_heap_malloc(out_len + 1);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (int i = 0; i < b->len; i++) {
                    uint8_t v = b->data[i];
                    out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
                    out[(size_t)i * 2 + 1] = hexd[v & 0xF];
                }
                out[out_len] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_to_hex expects (bytes)");
            }
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
        // TODO: Implement others
        default:
            printf("Unknown native id: %d\n", id);
            break;
    }
    return res;
}

static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out) {
    if (!out) return 0;
    out->type = AVM_VAL_NIL;
    if (vmap.type != AVM_VAL_MAP || !vmap.as.m || !key) return 0;
    AvmMap* map = vmap.as.m;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && k.as.p && strcmp((const char*)k.as.p, key) == 0) {
            *out = map->values[i];
            return 1;
        }
    }
    return 0;
}

typedef struct {
    void** old_ptrs;
    void** new_ptrs;
    uint8_t* types; // 1=STRING,2=LIST,3=MAP,4=BYTES
    uint32_t count;
    uint32_t cap;
} CloneTable;

static void clonetab_free(CloneTable* t) {
    if (!t) return;
    free(t->old_ptrs);
    free(t->new_ptrs);
    free(t->types);
    t->old_ptrs = NULL;
    t->new_ptrs = NULL;
    t->types = NULL;
    t->count = 0;
    t->cap = 0;
}

static void* clonetab_find(CloneTable* t, void* old_ptr, uint8_t type) {
    if (!t || !old_ptr) return NULL;
    for (uint32_t i = 0; i < t->count; i++) {
        if (t->old_ptrs[i] == old_ptr && t->types[i] == type) return t->new_ptrs[i];
    }
    return NULL;
}

static int clonetab_add(CloneTable* t, void* old_ptr, void* new_ptr, uint8_t type) {
    if (!t) return 0;
    if (t->count >= t->cap) {
        uint32_t nc = t->cap ? t->cap * 2 : 64;
        void** no = (void**)realloc(t->old_ptrs, sizeof(void*) * nc);
        void** nn = (void**)realloc(t->new_ptrs, sizeof(void*) * nc);
        uint8_t* nt = (uint8_t*)realloc(t->types, sizeof(uint8_t) * nc);
        if (!no || !nn || !nt) return 0;
        t->old_ptrs = no;
        t->new_ptrs = nn;
        t->types = nt;
        t->cap = nc;
    }
    t->old_ptrs[t->count] = old_ptr;
    t->new_ptrs[t->count] = new_ptr;
    t->types[t->count] = type;
    t->count++;
    return 1;
}

static AvmValue avm_clone_value_rec(CloneTable* tab, AvmValue v);

static AvmValue avm_clone_string(CloneTable* tab, const char* s) {
    if (!s) return avm_string("");
    void* found = clonetab_find(tab, (void*)s, 1);
    if (found) { AvmValue r; r.type = AVM_VAL_STRING; r.as.p = found; return r; }
    char* d = my_strdup(s);
    if (!d) return avm_nil();
    if (!clonetab_add(tab, (void*)s, d, 1)) { avm_heap_free(d); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_STRING; r.as.p = d; return r;
}

static AvmValue avm_clone_bytes(CloneTable* tab, AvmBytes* b) {
    if (!b) return avm_nil();
    void* found = clonetab_find(tab, (void*)b, 4);
    if (found) { AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = (AvmBytes*)found; return r; }
    AvmBytes* nb = (AvmBytes*)avm_heap_malloc(sizeof(AvmBytes));
    if (!nb) return avm_nil();
    nb->len = b->len;
    nb->capacity = b->len;
    nb->data = NULL;
    if (b->len > 0) {
        nb->data = (uint8_t*)avm_heap_malloc((size_t)b->len);
        if (!nb->data) { avm_heap_free(nb); return avm_nil(); }
        memcpy(nb->data, b->data, (size_t)b->len);
    }
    if (!clonetab_add(tab, (void*)b, nb, 4)) { if (nb->data) avm_heap_free(nb->data); avm_heap_free(nb); return avm_nil(); }
    AvmValue r; r.type = AVM_VAL_BYTES; r.as.b = nb; return r;
}

static AvmValue avm_clone_list(CloneTable* tab, AvmList* list) {
    if (!list) return avm_nil();
    void* found = clonetab_find(tab, (void*)list, 2);
    if (found) { AvmValue r; r.type = AVM_VAL_LIST; r.as.l = (AvmList*)found; return r; }
    AvmList* nl = (AvmList*)avm_heap_malloc(sizeof(AvmList));
    if (!nl) return avm_nil();
    nl->count = list->count;
    nl->capacity = list->count;
    nl->items = NULL;
    if (nl->count > 0) {
        nl->items = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)nl->count);
        if (!nl->items) { avm_heap_free(nl); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)list, nl, 2)) { if (nl->items) avm_heap_free(nl->items); avm_heap_free(nl); return avm_nil(); }
    for (int i = 0; i < nl->count; i++) nl->items[i] = avm_clone_value_rec(tab, list->items[i]);
    AvmValue r; r.type = AVM_VAL_LIST; r.as.l = nl; return r;
}

static AvmValue avm_clone_map(CloneTable* tab, AvmMap* map) {
    if (!map) return avm_nil();
    void* found = clonetab_find(tab, (void*)map, 3);
    if (found) { AvmValue r; r.type = AVM_VAL_MAP; r.as.m = (AvmMap*)found; return r; }
    AvmMap* nm = (AvmMap*)avm_heap_malloc(sizeof(AvmMap));
    if (!nm) return avm_nil();
    nm->count = map->count;
    nm->capacity = map->count;
    nm->keys = NULL;
    nm->values = NULL;
    if (nm->count > 0) {
        nm->keys = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)nm->count);
        nm->values = (AvmValue*)avm_heap_malloc(sizeof(AvmValue) * (size_t)nm->count);
        if (!nm->keys || !nm->values) { if (nm->keys) avm_heap_free(nm->keys); if (nm->values) avm_heap_free(nm->values); avm_heap_free(nm); return avm_nil(); }
    }
    if (!clonetab_add(tab, (void*)map, nm, 3)) { if (nm->keys) avm_heap_free(nm->keys); if (nm->values) avm_heap_free(nm->values); avm_heap_free(nm); return avm_nil(); }
    for (int i = 0; i < nm->count; i++) {
        nm->keys[i] = avm_clone_value_rec(tab, map->keys[i]);
        nm->values[i] = avm_clone_value_rec(tab, map->values[i]);
    }
    AvmValue r; r.type = AVM_VAL_MAP; r.as.m = nm; return r;
}

static AvmValue avm_clone_value_rec(CloneTable* tab, AvmValue v) {
    if (v.type == AVM_VAL_NIL) return avm_nil();
    if (v.type == AVM_VAL_INT) return avm_int(v.as.i);
    if (v.type == AVM_VAL_BOOL) return avm_bool(v.as.i != 0);
    if (v.type == AVM_VAL_FLOAT) { AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = v.as.f; return r; }
    if (v.type == AVM_VAL_STRING) return avm_clone_string(tab, (const char*)v.as.p);
    if (v.type == AVM_VAL_BYTES) return avm_clone_bytes(tab, v.as.b);
    if (v.type == AVM_VAL_LIST) return avm_clone_list(tab, v.as.l);
    if (v.type == AVM_VAL_MAP) return avm_clone_map(tab, v.as.m);
    return avm_nil();
}

static AvmValue avm_clone_value(AvmValue v) {
    CloneTable tab = {0};
    AvmValue out = avm_clone_value_rec(&tab, v);
    clonetab_free(&tab);
    return out;
}

static uint64_t avm_value_u64(AvmValue v, uint64_t def) {
    if (v.type == AVM_VAL_INT) {
        if (v.as.i < 0) return def;
        return (uint64_t)v.as.i;
    }
    if (v.type == AVM_VAL_BOOL) return v.as.i ? 1ull : 0ull;
    return def;
}

static int avm_value_truthy(AvmValue v) {
    if (v.type == AVM_VAL_BOOL) return v.as.i != 0;
    if (v.type == AVM_VAL_INT) return v.as.i != 0;
    return 0;
}

static AvmBytes* avm_new_log_bytes() {
    AvmBytes* b = (AvmBytes*)avm_heap_malloc(sizeof(AvmBytes));
    if (!b) return NULL;
    b->len = 8;
    b->capacity = 64;
    b->data = (uint8_t*)avm_heap_malloc((size_t)b->capacity);
    if (!b->data) { avm_heap_free(b); return NULL; }
    const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
    memcpy(b->data, magic, 8);
    return b;
}

static int avm_parse_obc_from_bytes(const AvmBytes* obc, AvmProgram* out) {
    if (!obc || !out) return 0;
    if (!obc->data || obc->len < 4) return 0;

    const uint8_t* data = obc->data;
    size_t len = (size_t)obc->len;

    // Header: CD 0E
    if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) return 0;

    // Const count (u16)
    size_t pos = 2;
    if (pos + 2 > len) return 0;
    uint16_t n_consts = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
    pos += 2;

    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)n_consts);
    if (!consts && n_consts > 0) return 0;
    for (uint16_t i = 0; i < n_consts; i++) consts[i].type = AVM_VAL_NIL;

    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) return 0;
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
            continue;
        }
        if (type == 1) { // INT
            if (pos + 8 > len) return 0;
            int64_t val = 0;
            for (int k = 0; k < 8; k++) {
                val |= (int64_t)data[pos++] << (k * 8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
            continue;
        }
        if (type == 4) { // STRING
            if (pos + 2 > len) return 0;
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            if (pos + slen > len) return 0;
            char* s = (char*)malloc((size_t)slen + 1);
            if (!s) return 0;
            if (slen > 0) memcpy(s, data + pos, slen);
            s[slen] = 0;
            pos += slen;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
            continue;
        }
        if (type == 8) { // BYTES (rolling): u32 len + raw bytes
            if (pos + 4 > len) return 0;
            uint32_t blen = (uint32_t)data[pos] |
                ((uint32_t)data[pos + 1] << 8) |
                ((uint32_t)data[pos + 2] << 16) |
                ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (pos + blen > len) return 0;
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) return 0;
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)malloc((size_t)blen);
                if (!b->data) { free(b); return 0; }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
            continue;
        }
        return 0;
    }

    if (pos > len) return 0;
    out->code = (uint8_t*)(data + pos);
    out->code_len = len - pos;
    out->constants = consts;
    out->const_count = n_consts;
    return 1;
}

// Rolling ABI: CALL_NATIVE2(domain, op, nargs)
// For now, CORE domain (0) maps op -> legacy native id.
static AvmValue avm_call_native2(AvmVM* vm, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
    // Normalize legacy/compat calls to prevent CORE domain bypass:
    // - bootstrap tools or old bytecode may still call domain=0 with legacy IDs.
    // - if a legacy id maps to an effectful domain, route to that domain/op before policy checks.
    if (domain == 0) {
        uint8_t nd = 0;
        uint16_t nop = op;
        avm_legacy_native_to_domop(op, &nd, &nop);
        if (nd != 0) { domain = nd; op = nop; }
    }

    // Capability check (rolling behavior):
    // - allowed_native_domains == 0 => allow all (bootstrap default)
    // - otherwise require bit set for domain
    if (vm->allowed_native_domains != 0) {
        uint64_t mask = 1ULL << (domain & 63);
        if ((vm->allowed_native_domains & mask) == 0) {
            return avm_err_domop(AVM_ERR_PERM, "capability denied", domain, op);
        }
    }

    // Domain 0: CORE (bootstrap mapping: op == legacy native id)
    if (domain == 0) return avm_call_native(vm, op, args, nargs);

    // Domain 1: FS (filesystem). Map op -> legacy ids for now.
    // This is a rolling ABI: domain/op tables may evolve quickly.
    if (domain == 1) {
        if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
            const char* path = (const char*)args[0].as.p;
            if (!avm_path_allowed(vm, path)) {
                return avm_err_domop(AVM_ERR_PERM, "fs path denied", domain, op);
            }
        }

        // Deterministic replay (rolling): if enabled, avoid touching the real host.
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // read_file
                AvmValue ret = avm_call_native(vm, 0, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // write_file
                AvmValue ret = avm_call_native(vm, 1, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 2: { // write_bytes
                AvmValue ret = avm_call_native(vm, 17, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 3: { // read_bytes
                AvmValue ret = avm_call_native(vm, 18, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
    }

    // Domain 5: PROC (subprocess / system)
    if (domain == 5) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // system(cmd)
                AvmValue ret = avm_call_native(vm, 2, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // exit(code)
                AvmValue ret = avm_call_native(vm, 5, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 6: EXIT (terminate the VM)
    // Split from PROC so capsules can allow exit without allowing subprocesses.
    if (domain == 6) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // exit(code)
                AvmValue ret = avm_call_native(vm, 5, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 7: ENV (environment variables)
    if (domain == 7) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // env(name)
                AvmValue ret = avm_call_native(vm, 4, args, nargs);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 2: TIME
    if (domain == 2) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // now_ns()
                AvmValue ret;
                if (vm->deterministic) {
                    __uint128_t t = (__uint128_t)vm->virtual_now_ns;
                    t += (__uint128_t)vm->virtual_sleep_ns;
                    t += (__uint128_t)vm->gas_executed * (__uint128_t)vm->virtual_step_ns;
                    uint64_t t64 = (t > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)t;
                    int64_t out = (t64 > (uint64_t)INT64_MAX) ? INT64_MAX : (int64_t)t64;
                    ret = avm_int(out);
                } else {
                    ret = avm_int((int64_t)avm_now_ns());
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // sleep_ms(ms)
                AvmValue ret = avm_nil();
                int64_t ms = 0;
                if (nargs > 0 && args[0].type == AVM_VAL_INT) ms = args[0].as.i;
                if (ms < 0) ms = 0;
                if (vm->deterministic) {
                    __uint128_t add = (__uint128_t)(uint64_t)ms * 1000000ull;
                    uint64_t add64 = (add > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)add;
                    uint64_t prev = vm->virtual_sleep_ns;
                    vm->virtual_sleep_ns = prev + add64;
                    if (vm->virtual_sleep_ns < prev) vm->virtual_sleep_ns = UINT64_MAX;
                } else {
                    usleep((useconds_t)(ms * 1000));
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 3: RNG (non-crypto deterministic PRNG in deterministic mode)
    if (domain == 3) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // rand_u64()
                AvmValue ret;
                if (vm->deterministic) {
                    ret = avm_int((int64_t)prng_next_u64(&vm->rng_state));
                } else {
                    ret = avm_int((int64_t)host_random_u64());
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // rand_seed(u64)
                uint64_t seed = 0;
                if (nargs > 0 && args[0].type == AVM_VAL_INT) seed = (uint64_t)args[0].as.i;
                vm->rng_state = seed ? seed : 0x123456789abcdef0ull;
                AvmValue ret = avm_nil();
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 8: AVM (nested universes via host service)
    if (domain == 8) {
        switch (op) {
            case 0: { // run_obc_bytes(obc_bytes, cfg_map)
                if (nargs < 1 || args[0].type != AVM_VAL_BYTES || !args[0].as.b) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "avm.run_obc_bytes expects BYTES", domain, op);
                }
                AvmValue cfg = avm_nil();
                if (nargs >= 2) cfg = args[1];

                AvmProgram* prog = (AvmProgram*)malloc(sizeof(AvmProgram));
                if (!prog) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                if (!avm_parse_obc_from_bytes(args[0].as.b, prog)) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid obc bytes", domain, op);
                }

                AvmVM* child = avm_new();
                child->argc = 0;
                child->argv = NULL;

                // Capabilities (hierarchical, rolling): child must be subset of parent when parent is restricted.
                uint64_t parent_mask = vm ? vm->allowed_native_domains : 0;
                uint64_t child_mask = parent_mask;
                AvmValue v;
                if (avm_map_get_key(cfg, "allowed_domains", &v)) {
                    uint64_t req = avm_value_u64(v, 0);
                    if (parent_mask != 0 && (req & ~parent_mask) != 0) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_PERM, "child capabilities must be subset of parent", domain, op);
                    }
                    child_mask = req;
                }
                child->allowed_native_domains = child_mask;

                // Determinism knobs
                if (avm_map_get_key(cfg, "deterministic", &v)) child->deterministic = avm_value_truthy(v) ? 1 : 0;
                if (avm_map_get_key(cfg, "time_start_ns", &v)) child->virtual_now_ns = avm_value_u64(v, child->virtual_now_ns);
                if (avm_map_get_key(cfg, "time_step_ns", &v)) child->virtual_step_ns = avm_value_u64(v, child->virtual_step_ns);
                if (avm_map_get_key(cfg, "rng_seed", &v)) child->rng_state = avm_value_u64(v, child->rng_state);

                // Budgets (rolling): enforce child <= parent when parent is budgeted.
                if (avm_map_get_key(cfg, "gas_limit", &v)) {
                    uint64_t gl = avm_value_u64(v, 0);
                    if (vm && vm->gas_remaining > 0 && gl > vm->gas_remaining) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child gas_limit exceeds parent", domain, op);
                    }
                    child->gas_remaining = gl;
                }
                if (avm_map_get_key(cfg, "deadline_ns", &v)) {
                    uint64_t dl = avm_value_u64(v, 0);
                    if (vm && vm->deadline_ns > 0 && dl > vm->deadline_ns) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child deadline exceeds parent", domain, op);
                    }
                    child->deadline_ns = dl;
                }
                if (avm_map_get_key(cfg, "mem_bytes", &v)) {
                    uint64_t mb = avm_value_u64(v, 0);
                    if (vm && vm->heap_budget_bytes > 0 && mb > vm->heap_budget_bytes) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child mem_bytes exceeds parent", domain, op);
                    }
                    child->heap_budget_bytes = mb;
                } else {
                    // Default: inherit parent budget (0 means unlimited).
                    child->heap_budget_bytes = vm ? vm->heap_budget_bytes : 0;
                }
                if (avm_map_get_key(cfg, "io_bytes", &v)) {
                    uint64_t ib = avm_value_u64(v, 0);
                    if (vm && vm->io_budget_bytes > 0 && ib > vm->io_budget_bytes) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child io_bytes exceeds parent", domain, op);
                    }
                    child->io_budget_bytes = ib;
                } else {
                    child->io_budget_bytes = vm ? vm->io_budget_bytes : 0;
                }
                if (avm_map_get_key(cfg, "log_bytes", &v)) {
                    uint64_t lb = avm_value_u64(v, 0);
                    if (vm && vm->log_budget_bytes > 0 && lb > vm->log_budget_bytes) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child log_bytes exceeds parent", domain, op);
                    }
                    child->log_budget_bytes = lb;
                } else {
                    child->log_budget_bytes = vm ? vm->log_budget_bytes : 0;
                }

                // Record/replay logs as data (always create a record log, even if it stays empty).
                child->record_log_bytes = avm_new_log_bytes();
                if (!child->record_log_bytes) {
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }
                if (child->log_budget_bytes > 0 && 8 > child->log_budget_bytes) {
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", domain, op);
                }
                child->log_used_bytes = 8;
                if (avm_map_get_key(cfg, "replay_log", &v) && v.type == AVM_VAL_BYTES && v.as.b) {
                    if (v.as.b->len < 8 || !v.as.b->data) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "replay_log too short", domain, op);
                    }
                    const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
                    if (memcmp(v.as.b->data, want, 8) != 0) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid replay_log magic", domain, op);
                    }
                    // Copy replay log into child-owned memory so the child can be freed safely.
                    AvmValue copy = avm_clone_value(v);
                    if (copy.type != AVM_VAL_BYTES || !copy.as.b) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    }
                    child->replay_log_bytes = copy.as.b;
                    child->replay_log_pos = 8;
                }

                avm_load(child, prog);
                avm_run(child);

                uint8_t rh[32]; memset(rh, 0, sizeof(rh));
                uint8_t sh[32]; memset(sh, 0, sizeof(sh));
                (void)avm_result_hash(child, rh);
                (void)avm_state_hash(child, sh);

                AvmValue v_rh = avm_bytes_new(32);
                AvmValue v_sh = avm_bytes_new(32);
                if (v_rh.type == AVM_VAL_BYTES && v_rh.as.b && v_rh.as.b->data) memcpy(v_rh.as.b->data, rh, 32);
                if (v_sh.type == AVM_VAL_BYTES && v_sh.as.b && v_sh.as.b->data) memcpy(v_sh.as.b->data, sh, 32);

                AvmMap* out = (AvmMap*)malloc(sizeof(AvmMap));
                if (!out) { avm_free(child); return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op); }
                out->count = 5;
                out->capacity = 8;
                out->keys = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                out->values = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                if (!out->keys || !out->values) { avm_free(child); return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op); }

                out->keys[0] = avm_string("exit_code");
                out->values[0] = avm_int((int64_t)child->exit_code);
                out->keys[1] = avm_string("result_hash");
                out->values[1] = v_rh;
                out->keys[2] = avm_string("state_hash");
                out->values[2] = v_sh;
                out->keys[3] = avm_string("record_log");
                AvmValue v_log;
                v_log.type = AVM_VAL_BYTES;
                v_log.as.b = child->record_log_bytes;
                out->values[3] = avm_clone_value(v_log);
                out->keys[4] = avm_string("last_error");
                out->values[4] = avm_clone_value(child->last_error);

                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                avm_free(child);
                if (prog->constants) free(prog->constants);
                free(prog);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Unknown/unsupported domain in bootstrap.
    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
}
