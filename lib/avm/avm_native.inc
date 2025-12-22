// Forward decls for helpers defined later in this include.
static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out);

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
                char* buf = (char*)avm_heap_malloc_k((size_t)len + 1, AVM_ALLOC_KIND_STRING);
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
            AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
            if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            list->count = vm->argc;
            list->capacity = vm->argc;
            list->items = NULL;
            if (vm->argc > 0) {
                list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)vm->argc, AVM_ALLOC_KIND_LIST);
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
                    char* buf = (char*)avm_heap_malloc_k(2, AVM_ALLOC_KIND_STRING);
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
                    char* buf = (char*)avm_heap_malloc_k((size_t)sublen + 1, AVM_ALLOC_KIND_STRING);
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
                sprintf(buf, "%lld", (long long)args[0].as.i);
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
                    AvmValue* ni = (AvmValue*)avm_heap_realloc_k(list->items, sizeof(AvmValue) * (size_t)new_cap, AVM_ALLOC_KIND_LIST);
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
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->count = len;
                list->capacity = len;
                list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)len, AVM_ALLOC_KIND_LIST);
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
                uint8_t* buf = (uint8_t*)avm_heap_malloc_k((size_t)list->count, AVM_ALLOC_KIND_BYTES);
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
                    buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES);
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

                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) {
                    if (buf) avm_heap_free(buf);
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->count = (int)len;
                list->capacity = (int)len;
                if (len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)len, AVM_ALLOC_KIND_LIST);
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
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                list->count = b->len;
                list->capacity = b->len;
                list->items = NULL;
                if (b->len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)b->len, AVM_ALLOC_KIND_LIST);
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
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: index out of bounds"); break; }
                    res = avm_int((int64_t)b->data[(int)idx]);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: index out of bounds"); break; }
                    AvmValue v = list->items[(int)idx];
                    if (v.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: expected list<int 0..255>"); break; }
                    if (v.as.i < 0 || v.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u8: byte out of range"); break; }
                    res = avm_int(v.as.i);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u8 expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u8 expects (bytes|list<int>, int)");
            }
            break;
        }
        case 34: { // oren_bytes_set_u8(bytes, idx, val) -> bytes
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                int64_t val = args[2].as.i;
                if (val < 0 || val > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: expected 0..255"); break; }

                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: index out of bounds"); break; }
                    b->data[(int)idx] = (uint8_t)val;
                    res = avm_int(val);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u8: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int(val);
                    res = avm_int(val);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u8 expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u8 expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 45: { // oren_bytes_set_u16_be(bytes|list<int>, idx, val) -> int (0..65535)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFu;
                uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b1 = (uint8_t)(u & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_be: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u16_be expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u16_be expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 46: { // oren_bytes_set_u16_le(bytes|list<int>, idx, val) -> int (0..65535)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFu;
                uint8_t b0 = (uint8_t)(u & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_le: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u16_le expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u16_le expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 47: { // oren_bytes_set_i16_be(bytes|list<int>, idx, val) -> int (-32768..32767)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFu;
                uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b1 = (uint8_t)(u & 0xFFu);
                int64_t v = (int64_t)u;
                if (v >= 32768) v -= 65536;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_be: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    res = avm_int(v);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i16_be expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i16_be expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 48: { // oren_bytes_set_i16_le(bytes|list<int>, idx, val) -> int (-32768..32767)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFu;
                uint8_t b0 = (uint8_t)(u & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
                int64_t v = (int64_t)u;
                if (v >= 32768) v -= 65536;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_le: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    res = avm_int(v);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i16_le expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i16_le expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 49: { // oren_bytes_set_u32_be(bytes|list<int>, idx, val) -> int (0..2^32-1)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFFFFFu;
                uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b3 = (uint8_t)(u & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_be: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u32_be expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u32_be expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 50: { // oren_bytes_set_u32_le(bytes|list<int>, idx, val) -> int (0..2^32-1)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFFFFFu;
                uint8_t b0 = (uint8_t)(u & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_le: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u32_le expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u32_le expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 51: { // oren_bytes_set_i32_be(bytes|list<int>, idx, val) -> int (-2^31..2^31-1)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFFFFFu;
                uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b3 = (uint8_t)(u & 0xFFu);
                int64_t v = (int64_t)u;
                if (v >= 2147483648LL) v -= 4294967296LL;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_be: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    res = avm_int(v);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i32_be expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i32_be expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 52: { // oren_bytes_set_i32_le(bytes|list<int>, idx, val) -> int (-2^31..2^31-1)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i & 0xFFFFFFFFu;
                uint8_t b0 = (uint8_t)(u & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
                int64_t v = (int64_t)u;
                if (v >= 2147483648LL) v -= 4294967296LL;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_le: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    res = avm_int(v);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i32_le expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_i32_le expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 90: { // oren_bytes_get_u16_be(bytes|list<int>, idx) -> int (0..65535)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_be: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx] << 8) | (uint64_t)b->data[(int)idx + 1];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_be: index out of bounds"); break; }
                    AvmValue v0 = list->items[(int)idx];
                    AvmValue v1 = list->items[(int)idx + 1];
                    if (v0.type != AVM_VAL_INT || v1.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_be: expected list<int 0..255>"); break; }
                    if (v0.as.i < 0 || v0.as.i > 255 || v1.as.i < 0 || v1.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_be: byte out of range"); break; }
                    uint64_t u = ((uint64_t)v0.as.i << 8) | (uint64_t)v1.as.i;
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u16_be expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u16_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 91: { // oren_bytes_get_u16_le(bytes|list<int>, idx) -> int (0..65535)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 1 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_le: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx + 1] << 8) | (uint64_t)b->data[(int)idx];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 1 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_le: index out of bounds"); break; }
                    AvmValue v0 = list->items[(int)idx];
                    AvmValue v1 = list->items[(int)idx + 1];
                    if (v0.type != AVM_VAL_INT || v1.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_le: expected list<int 0..255>"); break; }
                    if (v0.as.i < 0 || v0.as.i > 255 || v1.as.i < 0 || v1.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u16_le: byte out of range"); break; }
                    uint64_t u = ((uint64_t)v1.as.i << 8) | (uint64_t)v0.as.i;
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u16_le expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u16_le expects (bytes|list<int>, int)");
            }
            break;
        }
        case 92: { // oren_bytes_get_i16_be(bytes|list<int>, idx) -> int (-32768..32767)
            AvmValue u = avm_call_native(vm, 90, args, nargs);
            if (avm_is_err_val(u)) { res = u; break; }
            int64_t v = (u.type == AVM_VAL_INT) ? u.as.i : 0;
            if (v >= 32768) v -= 65536;
            res = avm_int(v);
            break;
        }
        case 93: { // oren_bytes_get_i16_le(bytes|list<int>, idx) -> int (-32768..32767)
            AvmValue u = avm_call_native(vm, 91, args, nargs);
            if (avm_is_err_val(u)) { res = u; break; }
            int64_t v = (u.type == AVM_VAL_INT) ? u.as.i : 0;
            if (v >= 32768) v -= 65536;
            res = avm_int(v);
            break;
        }
        case 94: { // oren_bytes_get_u32_be(bytes|list<int>, idx) -> int (0..2^32-1)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_be: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx] << 24) | ((uint64_t)b->data[(int)idx + 1] << 16) |
                                 ((uint64_t)b->data[(int)idx + 2] << 8) | (uint64_t)b->data[(int)idx + 3];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_be: index out of bounds"); break; }
                    AvmValue v0 = list->items[(int)idx];
                    AvmValue v1 = list->items[(int)idx + 1];
                    AvmValue v2 = list->items[(int)idx + 2];
                    AvmValue v3 = list->items[(int)idx + 3];
                    if (v0.type != AVM_VAL_INT || v1.type != AVM_VAL_INT || v2.type != AVM_VAL_INT || v3.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_be: expected list<int 0..255>"); break; }
                    if (v0.as.i < 0 || v0.as.i > 255 || v1.as.i < 0 || v1.as.i > 255 || v2.as.i < 0 || v2.as.i > 255 || v3.as.i < 0 || v3.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_be: byte out of range"); break; }
                    uint64_t u = ((uint64_t)v0.as.i << 24) | ((uint64_t)v1.as.i << 16) | ((uint64_t)v2.as.i << 8) | (uint64_t)v3.as.i;
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u32_be expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u32_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 95: { // oren_bytes_get_u32_le(bytes|list<int>, idx) -> int (0..2^32-1)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 3 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_le: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx + 3] << 24) | ((uint64_t)b->data[(int)idx + 2] << 16) |
                                 ((uint64_t)b->data[(int)idx + 1] << 8) | (uint64_t)b->data[(int)idx];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 3 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_le: index out of bounds"); break; }
                    AvmValue v0 = list->items[(int)idx];
                    AvmValue v1 = list->items[(int)idx + 1];
                    AvmValue v2 = list->items[(int)idx + 2];
                    AvmValue v3 = list->items[(int)idx + 3];
                    if (v0.type != AVM_VAL_INT || v1.type != AVM_VAL_INT || v2.type != AVM_VAL_INT || v3.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_le: expected list<int 0..255>"); break; }
                    if (v0.as.i < 0 || v0.as.i > 255 || v1.as.i < 0 || v1.as.i > 255 || v2.as.i < 0 || v2.as.i > 255 || v3.as.i < 0 || v3.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u32_le: byte out of range"); break; }
                    uint64_t u = ((uint64_t)v3.as.i << 24) | ((uint64_t)v2.as.i << 16) | ((uint64_t)v1.as.i << 8) | (uint64_t)v0.as.i;
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u32_le expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u32_le expects (bytes|list<int>, int)");
            }
            break;
        }
        case 96: { // oren_bytes_get_i32_be(bytes|list<int>, idx) -> int (-2^31..2^31-1)
            AvmValue u = avm_call_native(vm, 94, args, nargs);
            if (avm_is_err_val(u)) { res = u; break; }
            int64_t v = (u.type == AVM_VAL_INT) ? u.as.i : 0;
            if (v >= 2147483648LL) v -= 4294967296LL;
            res = avm_int(v);
            break;
        }
        case 97: { // oren_bytes_get_i32_le(bytes|list<int>, idx) -> int (-2^31..2^31-1)
            AvmValue u = avm_call_native(vm, 95, args, nargs);
            if (avm_is_err_val(u)) { res = u; break; }
            int64_t v = (u.type == AVM_VAL_INT) ? u.as.i : 0;
            if (v >= 2147483648LL) v -= 4294967296LL;
            res = avm_int(v);
            break;
        }
        case 98: { // oren_bytes_get_u64_be(bytes|list<int>, idx) -> int (signed int64 bits)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 7 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_be: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx] << 56) | ((uint64_t)b->data[(int)idx + 1] << 48) |
                                 ((uint64_t)b->data[(int)idx + 2] << 40) | ((uint64_t)b->data[(int)idx + 3] << 32) |
                                 ((uint64_t)b->data[(int)idx + 4] << 24) | ((uint64_t)b->data[(int)idx + 5] << 16) |
                                 ((uint64_t)b->data[(int)idx + 6] << 8) | (uint64_t)b->data[(int)idx + 7];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 7 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_be: index out of bounds"); break; }
                    uint64_t u = 0;
                    for (int i = 0; i < 8; i++) {
                        AvmValue v = list->items[(int)idx + i];
                        if (v.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_be: expected list<int 0..255>"); goto bytes_get_u64_be_done; }
                        if (v.as.i < 0 || v.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_be: byte out of range"); goto bytes_get_u64_be_done; }
                        u = (u << 8) | (uint64_t)v.as.i;
                    }
                    res = avm_int((int64_t)u);
                bytes_get_u64_be_done: ;
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u64_be expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u64_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 99: { // oren_bytes_get_u64_le(bytes|list<int>, idx) -> int (signed int64 bits)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 7 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_le: index out of bounds"); break; }
                    uint64_t u = ((uint64_t)b->data[(int)idx + 7] << 56) | ((uint64_t)b->data[(int)idx + 6] << 48) |
                                 ((uint64_t)b->data[(int)idx + 5] << 40) | ((uint64_t)b->data[(int)idx + 4] << 32) |
                                 ((uint64_t)b->data[(int)idx + 3] << 24) | ((uint64_t)b->data[(int)idx + 2] << 16) |
                                 ((uint64_t)b->data[(int)idx + 1] << 8) | (uint64_t)b->data[(int)idx];
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 7 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_le: index out of bounds"); break; }
                    uint64_t u = 0;
                    for (int i = 7; i >= 0; i--) {
                        AvmValue v = list->items[(int)idx + i];
                        if (v.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_le: expected list<int 0..255>"); goto bytes_get_u64_le_done; }
                        if (v.as.i < 0 || v.as.i > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_get_u64_le: byte out of range"); goto bytes_get_u64_le_done; }
                        u = (u << 8) | (uint64_t)v.as.i;
                    }
                    res = avm_int((int64_t)u);
                bytes_get_u64_le_done: ;
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u64_le expects (bytes|list<int>, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u64_le expects (bytes|list<int>, int)");
            }
            break;
        }
        case 100: { // oren_bytes_get_i64_be(bytes|list<int>, idx) -> int (signed int64)
            res = avm_call_native(vm, 98, args, nargs);
            break;
        }
        case 101: { // oren_bytes_get_i64_le(bytes|list<int>, idx) -> int (signed int64)
            res = avm_call_native(vm, 99, args, nargs);
            break;
        }
        case 102: { // oren_bytes_set_u64_be(bytes|list<int>, idx, val) -> int (signed int64 bits)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i;
                uint8_t b0 = (uint8_t)((u >> 56) & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 48) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 40) & 0xFFu);
                uint8_t b3 = (uint8_t)((u >> 32) & 0xFFu);
                uint8_t b4 = (uint8_t)((u >> 24) & 0xFFu);
                uint8_t b5 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b6 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b7 = (uint8_t)(u & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 7 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    b->data[(int)idx + 4] = b4;
                    b->data[(int)idx + 5] = b5;
                    b->data[(int)idx + 6] = b6;
                    b->data[(int)idx + 7] = b7;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 7 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_be: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    list->items[(int)idx + 4] = avm_int((int64_t)b4);
                    list->items[(int)idx + 5] = avm_int((int64_t)b5);
                    list->items[(int)idx + 6] = avm_int((int64_t)b6);
                    list->items[(int)idx + 7] = avm_int((int64_t)b7);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u64_be expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u64_be expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 103: { // oren_bytes_set_u64_le(bytes|list<int>, idx, val) -> int (signed int64 bits)
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                uint64_t u = (uint64_t)args[2].as.i;
                uint8_t b0 = (uint8_t)(u & 0xFFu);
                uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
                uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
                uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
                uint8_t b4 = (uint8_t)((u >> 32) & 0xFFu);
                uint8_t b5 = (uint8_t)((u >> 40) & 0xFFu);
                uint8_t b6 = (uint8_t)((u >> 48) & 0xFFu);
                uint8_t b7 = (uint8_t)((u >> 56) & 0xFFu);
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || idx < 0 || idx + 7 >= b->len) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    b->data[(int)idx + 4] = b4;
                    b->data[(int)idx + 5] = b5;
                    b->data[(int)idx + 6] = b6;
                    b->data[(int)idx + 7] = b7;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || idx < 0 || idx + 7 >= list->count) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_le: index out of bounds"); break; }
                    list->items[(int)idx] = avm_int((int64_t)b0);
                    list->items[(int)idx + 1] = avm_int((int64_t)b1);
                    list->items[(int)idx + 2] = avm_int((int64_t)b2);
                    list->items[(int)idx + 3] = avm_int((int64_t)b3);
                    list->items[(int)idx + 4] = avm_int((int64_t)b4);
                    list->items[(int)idx + 5] = avm_int((int64_t)b5);
                    list->items[(int)idx + 6] = avm_int((int64_t)b6);
                    list->items[(int)idx + 7] = avm_int((int64_t)b7);
                    res = avm_int((int64_t)u);
                } else {
                    res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u64_le expects (bytes|list<int>, int, int)");
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_set_u64_le expects (bytes|list<int>, int, int)");
            }
            break;
        }
        case 104: { // oren_bytes_set_i64_be(bytes|list<int>, idx, val) -> int (signed int64)
            res = avm_call_native(vm, 102, args, nargs);
            break;
        }
        case 105: { // oren_bytes_set_i64_le(bytes|list<int>, idx, val) -> int (signed int64)
            res = avm_call_native(vm, 103, args, nargs);
            break;
        }
        case 106: { // oren_f32_round(x: float) -> float
            if (nargs > 0 && args[0].type == AVM_VAL_FLOAT) {
                // Deterministic: round-trip through IEEE-754 float32.
                float f = (float)args[0].as.f;
                res.type = AVM_VAL_FLOAT;
                res.as.f = (double)f;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_f32_round expects (float)");
            }
            break;
        }
        case 107: { // oren_bool_norm(x) -> bool
            if (nargs > 0) {
                AvmValue x = args[0];
                res.type = AVM_VAL_BOOL;
                if (x.type == AVM_VAL_NIL) {
                    res.as.i = 0;
                } else if (x.type == AVM_VAL_BOOL) {
                    res.as.i = x.as.i ? 1 : 0;
                } else if (x.type == AVM_VAL_INT) {
                    res.as.i = x.as.i != 0 ? 1 : 0;
                } else if (x.type == AVM_VAL_FLOAT) {
                    res.as.i = x.as.f != 0.0 ? 1 : 0;
                } else {
                    // For all other heap/object types, treat as truthy.
                    res.as.i = 1;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bool_norm expects (x)");
            }
            break;
        }
        case 108: { // oren_trunc_int(x: int|float) -> int
            if (nargs > 0) {
                AvmValue x = args[0];
                if (x.type == AVM_VAL_INT) {
                    res = x;
                } else if (x.type == AVM_VAL_FLOAT) {
                    double d = x.as.f;
                    // Match C/native semantics (deterministic, no UB):
                    // - NaN -> 0
                    // - +inf/overflow -> INT64_MAX
                    // - -inf/overflow -> INT64_MIN
                    if (d != d) { res = avm_int(0); break; }
                    const double lim = 9223372036854775808.0; // 2^63
                    if (d >= lim) { res = avm_int(INT64_MAX); break; }
                    if (d <= -lim) { res = avm_int(INT64_MIN); break; }
                    res = avm_int((int64_t)d); // truncate toward zero
                } else {
                    // Non-numeric -> 0 (deterministic).
                    res = avm_int(0);
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_trunc_int expects (x)");
            }
            break;
        }
        case 109: { // oren_f32_to_u32_bits(x: float) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_FLOAT) {
                float f = (float)args[0].as.f;
                uint32_t u = 0;
                memcpy(&u, &f, sizeof(u));
                res = avm_int((int64_t)(uint64_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_f32_to_u32_bits expects (float)");
            }
            break;
        }
        case 110: { // oren_u32_bits_to_f32(x: int) -> float
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                uint32_t u = (uint32_t)(uint64_t)args[0].as.i;
                float f = 0.0f;
                memcpy(&f, &u, sizeof(u));
                res.type = AVM_VAL_FLOAT;
                res.as.f = (double)f;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u32_bits_to_f32 expects (int)");
            }
            break;
        }
        case 111: { // oren_f64_to_u64_bits(x: float) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_FLOAT) {
                uint64_t bits = 0;
                double d = args[0].as.f;
                memcpy(&bits, &d, sizeof(bits));
                res = avm_int((int64_t)bits);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_f64_to_u64_bits expects (float)");
            }
            break;
        }
        case 112: { // oren_u64_bits_to_f64(x: int) -> float
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                uint64_t bits = (uint64_t)args[0].as.i;
                double d = 0.0;
                memcpy(&d, &bits, sizeof(bits));
                res.type = AVM_VAL_FLOAT;
                res.as.f = d;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u64_bits_to_f64 expects (int)");
            }
            break;
        }
        case 113: { // oren_map_len(map) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_MAP) {
                res.type = AVM_VAL_INT;
                res.as.i = (int64_t)args[0].as.m->count;
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
                char* out = (char*)avm_heap_malloc_k(out_len + 1, AVM_ALLOC_KIND_STRING);
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
        case 43: { // oren_iter_next(container, idx:int) -> [ok:int, value]
            if (nargs == 2 && args[1].type == AVM_VAL_INT) {
                AvmValue container = args[0];
                int64_t idx = args[1].as.i;

                AvmValue okv = avm_int(0);
                AvmValue val = avm_nil();

                if (idx >= 0) {
                    // Typed buffer "view" lists (rolling, HPC):
                    // - slice view:   [buf, off, len]
                    // - strided view: [buf, off, len, stride]
                    // These should iterate the underlying buffer elements rather than the metadata fields.
                    if (container.type == AVM_VAL_LIST && container.as.l) {
                        AvmList* l = container.as.l;
                        if (l->count == 3 || l->count == 4) {
                            AvmValue b = l->items[0];
                            if (b.type == AVM_VAL_I32_BUF || b.type == AVM_VAL_I64_BUF || b.type == AVM_VAL_F32_BUF || b.type == AVM_VAL_F64_BUF) {
                                AvmValue offv = l->items[1];
                                AvmValue lenv = l->items[2];
                                AvmValue stridev = (l->count == 4) ? l->items[3] : avm_int(1);
                                if (offv.type == AVM_VAL_INT && lenv.type == AVM_VAL_INT && stridev.type == AVM_VAL_INT) {
                                    int64_t off = offv.as.i;
                                    int64_t n = lenv.as.i;
                                    int64_t stride = stridev.as.i;
                                    if (off >= 0 && n >= 0 && stride > 0 && idx < n) {
                                        int64_t elem_idx = off + idx * stride;
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
                        if (okv.as.i == 0 && idx < l->count) {
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

                AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->count = 2;
                out->capacity = 2;
                out->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 2u, AVM_ALLOC_KIND_LIST);
                if (!out->items) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->items[0] = okv;
                out->items[1] = val;
                res.type = AVM_VAL_LIST;
                res.as.l = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_iter_next expects (container, int)");
            }
            break;
        }
        case 44: { // oren_string_from_bytes(list<int 0..255>) -> string
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes: invalid list"); break; }
                size_t n = (size_t)list->count;
                char* out = (char*)avm_heap_malloc_k(n + 1, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (size_t i = 0; i < n; i++) {
                    AvmValue it = list->items[i];
                    if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                        res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes: expected list<int 0..255>");
                        break;
                    }
                    out[i] = (char)(unsigned char)it.as.i;
                }
                if (!avm_is_err_val(res)) {
                    out[n] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = out;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_from_bytes expects (list)");
            }
            break;
        }
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
            if (nargs > 0 && (args[0].type == AVM_VAL_I32_BUF || args[0].type == AVM_VAL_I64_BUF || args[0].type == AVM_VAL_F32_BUF || args[0].type == AVM_VAL_F64_BUF)) {
                AvmBuf* b = args[0].as.buf;
                if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "buf_len: null buffer"); break; }
                res = avm_int((int64_t)b->len);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_len expects (buf)");
            }
            break;
        }
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
        }
        case 119: { // oren_string_to_float_bits(s:string) -> int (u64 bits stored in i64 container)
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                double d = strtod((const char*)args[0].as.p, NULL);
                uint64_t bits = 0;
                memcpy(&bits, &d, sizeof(bits));
                res = avm_int((int64_t)bits);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_to_float_bits expects (string)");
            }
            break;
        }
        case 120: { // oren_sha256_range(bytes:list<int>, start:int, len:int) -> list<int 32>
            if (nargs > 2 && args[0].type == AVM_VAL_LIST && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                AvmList* bytes = args[0].as.l;
                int64_t start = args[1].as.i;
                int64_t len = args[2].as.i;
                if (!bytes || bytes->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: invalid list"); break; }
                if (start < 0 || len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: negative range"); break; }
                if (start + len > (int64_t)bytes->count) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: out of bounds"); break; }

                AvmSha256Ctx ctx;
                avm_sha256_init(&ctx);
                for (int64_t i = 0; i < len; i++) {
                    AvmValue it = bytes->items[(int)(start + i)];
                    if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                        res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: expected list<int 0..255>");
                        break;
                    }
                    uint8_t b = (uint8_t)it.as.i;
                    avm_sha256_update(&ctx, &b, 1);
                }
                if (avm_is_err_val(res)) break;

                uint8_t digest[32];
                avm_sha256_final(&ctx, digest);

                AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->count = 32;
                out->capacity = 32;
                out->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 32u, AVM_ALLOC_KIND_LIST);
                if (!out->items) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (int i = 0; i < 32; i++) out->items[i] = avm_int((int64_t)digest[i]);
                res.type = AVM_VAL_LIST;
                res.as.l = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_sha256_range expects (list,int,int)");
            }
            break;
        }
        case 121: { // oren_fail(code:int, msg:string) -> abort VM run
            if (nargs > 1 && args[0].type == AVM_VAL_INT && args[1].type == AVM_VAL_STRING) {
                int64_t code = args[0].as.i;
                const char* msg = (const char*)args[1].as.p;
                AvmValue e = avm_err((int)code, msg ? msg : "oren_fail");
                if (vm) {
                    vm->last_error = e;
                    vm->exit_code = (int)code;
                    vm->running = 0;
                }
                res = avm_nil();
            } else {
                AvmValue e = avm_err(AVM_ERR_INVALID_ARG, "oren_fail expects (int, string)");
                if (vm) avm_abort(vm, e);
                res = e;
            }
            break;
        }
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
    size_t keylen = strlen(key);
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && k.as.p && strcmp((const char*)k.as.p, key) == 0) {
            *out = map->values[i];
            return 1;
        }
        // Some compiler paths may use BYTES for keys (rolling). Support both string and bytes
        // keys for internal protocol lookups (e.g. "__iter", "__err").
        if (k.type == AVM_VAL_BYTES && k.as.b && k.as.b->data && k.as.b->len == keylen &&
            memcmp(k.as.b->data, key, keylen) == 0) {
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
    AvmBytes* nb = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
    if (!nb) return avm_nil();
    nb->len = b->len;
    nb->capacity = b->len;
    nb->data = NULL;
    if (b->len > 0) {
        nb->data = (uint8_t*)avm_heap_malloc_k((size_t)b->len, AVM_ALLOC_KIND_BYTES);
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
    AvmList* nl = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!nl) return avm_nil();
    nl->count = list->count;
    nl->capacity = list->count;
    nl->items = NULL;
    if (nl->count > 0) {
        nl->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nl->count, AVM_ALLOC_KIND_LIST);
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
    AvmMap* nm = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
    if (!nm) return avm_nil();
    nm->count = map->count;
    nm->capacity = map->count;
    nm->keys = NULL;
    nm->values = NULL;
    if (nm->count > 0) {
        nm->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nm->count, AVM_ALLOC_KIND_MAP);
        nm->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)nm->count, AVM_ALLOC_KIND_MAP);
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
    AvmBytes* b = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
    if (!b) return NULL;
    b->len = 8;
    b->capacity = 64;
    b->data = (uint8_t*)avm_heap_malloc_k((size_t)b->capacity, AVM_ALLOC_KIND_BYTES);
    if (!b->data) { avm_heap_free(b); return NULL; }
    const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
    memcpy(b->data, magic, 8);
    return b;
}

static AvmValue avm_vfs_snapshot_bytes_value(AvmVM* child) {
    // Serialize child's VirtualFS into AVMVFS01 bytes (as data), so parent universes
    // can consume child-produced artifacts without host filesystem effects.
    //
    // Format:
    //   magic[8] = "AVMVFS01"
    //   u32 count
    //   repeated:
    //     u32 path_len, path bytes (utf-8/bytes)
    //     u32 body_len, body bytes
    if (!child || child->fs_backend_kind != 1 || !child->vfs) return avm_nil();
    AvmVfs* v = (AvmVfs*)child->vfs;
    uint32_t cnt = v ? (uint32_t)v->count : 0u;

    AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
    if (!blob) return avm_alloc_fail_value();
    blob->data = NULL;
    blob->len = 0;
    blob->capacity = 0;
    uint32_t p = 0;

    if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); return avm_alloc_fail_value(); }
    const uint8_t magic[8] = {'A','V','M','V','F','S','0','1'};
    if (!mem_write_bytes(blob, &p, magic, 8)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
    if (!mem_write_u32_le(blob, &p, cnt)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }

    for (uint32_t i = 0; i < cnt; i++) {
        AvmVfsEntry* e = v ? &v->entries[i] : NULL;
        const char* path = (e && e->path) ? e->path : "";
        uint64_t pl64 = (uint64_t)strlen(path);
        if (pl64 > 0xFFFFFFFEu) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        uint32_t pl = (uint32_t)pl64;
        if (!mem_write_u32_le(blob, &p, pl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        if (pl > 0 && !mem_write_bytes(blob, &p, (const uint8_t*)path, pl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }

        uint32_t bl = (e && e->len > 0) ? (uint32_t)e->len : 0u;
        if (!mem_write_u32_le(blob, &p, bl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        if (bl > 0 && !mem_write_bytes(blob, &p, e ? e->data : NULL, bl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
    }

    blob->len = (int)p;
    AvmValue out;
    out.type = AVM_VAL_BYTES;
    out.as.b = blob;
    return out;
}

static int avm_parse_obc_from_bytes(const AvmBytes* obc, AvmProgram* out) {
    if (!obc || !out) return 0;
    if (!obc->data || obc->len < 4) return 0;

    const uint8_t* data = obc->data;
    size_t len = (size_t)obc->len;

    // Always initialize output so callers can safely call cleanup on failure.
    out->code = NULL;
    out->code_len = 0;
    out->constants = NULL;
    out->const_count = 0;

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
        if (pos >= len) goto fail;
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
            continue;
        }
        if (type == 1) { // INT
            if (pos + 8 > len) goto fail;
            int64_t val = 0;
            for (int k = 0; k < 8; k++) {
                val |= (int64_t)data[pos++] << (k * 8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
            continue;
        }
        if (type == 2) { // BOOL (u8 0|1)
            if (pos + 1 > len) goto fail;
            uint8_t b = data[pos++];
            consts[i].type = AVM_VAL_BOOL;
            consts[i].as.i = b ? 1 : 0;
            continue;
        }
        if (type == 4) { // STRING
            if (pos + 2 > len) goto fail;
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            if (pos + slen > len) goto fail;
            char* s = (char*)malloc((size_t)slen + 1);
            if (!s) goto fail;
            if (slen > 0) memcpy(s, data + pos, slen);
            s[slen] = 0;
            pos += slen;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
            continue;
        }
        if (type == 8) { // BYTES (rolling): u32 len + raw bytes
            if (pos + 4 > len) goto fail;
            uint32_t blen = (uint32_t)data[pos] |
                ((uint32_t)data[pos + 1] << 8) |
                ((uint32_t)data[pos + 2] << 16) |
                ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (pos + blen > len) goto fail;
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) goto fail;
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)malloc((size_t)blen);
                if (!b->data) { free(b); goto fail; }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
            continue;
        }
        goto fail;
    }

    if (pos > len) goto fail;
    out->code = (uint8_t*)(data + pos);
    out->code_len = len - pos;
    out->constants = consts;
    out->const_count = n_consts;
    return 1;

fail:
    if (consts) {
        for (uint16_t i = 0; i < n_consts; i++) {
            if (consts[i].type == AVM_VAL_STRING && consts[i].as.p) {
                free(consts[i].as.p);
            } else if (consts[i].type == AVM_VAL_BYTES && consts[i].as.b) {
                if (consts[i].as.b->data) free(consts[i].as.b->data);
                free(consts[i].as.b);
            }
            consts[i].type = AVM_VAL_NIL;
        }
        free(consts);
    }
    out->code = NULL;
    out->code_len = 0;
    out->constants = NULL;
    out->const_count = 0;
    return 0;
}

static int avm_clone_fs_allow_prefixes(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src) return 1;
    if (src->fs_allow_prefix_count <= 0 || !src->fs_allow_prefixes) return 1;

    int n = src->fs_allow_prefix_count;
    dst->fs_allow_prefix_count = 0;
    dst->fs_allow_prefixes = (char**)malloc(sizeof(char*) * (size_t)n);
    if (!dst->fs_allow_prefixes) return 0;
    for (int i = 0; i < n; i++) dst->fs_allow_prefixes[i] = NULL;

    for (int i = 0; i < n; i++) {
        const char* s = src->fs_allow_prefixes[i];
        if (!s) s = "";
        size_t sl = strlen(s);
        dst->fs_allow_prefixes[i] = (char*)malloc(sl + 1);
        if (!dst->fs_allow_prefixes[i]) {
            for (int j = 0; j < n; j++) { if (dst->fs_allow_prefixes[j]) free(dst->fs_allow_prefixes[j]); }
            free(dst->fs_allow_prefixes);
            dst->fs_allow_prefixes = NULL;
            dst->fs_allow_prefix_count = 0;
            return 0;
        }
        memcpy(dst->fs_allow_prefixes[i], s, sl);
        dst->fs_allow_prefixes[i][sl] = 0;
        dst->fs_allow_prefix_count++;
    }

    return 1;
}

static int avm_clone_fs_mounts(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src) return 1;

    // Clone read mounts
    if (src->fs_mounts_read_count > 0 && src->fs_mounts_read_virt && src->fs_mounts_read_host) {
        int n = src->fs_mounts_read_count;
        dst->fs_mounts_read_count = 0;
        dst->fs_mounts_read_virt = (char**)malloc(sizeof(char*) * (size_t)n);
        dst->fs_mounts_read_host = (char**)malloc(sizeof(char*) * (size_t)n);
        if (!dst->fs_mounts_read_virt || !dst->fs_mounts_read_host) {
            if (dst->fs_mounts_read_virt) free(dst->fs_mounts_read_virt);
            if (dst->fs_mounts_read_host) free(dst->fs_mounts_read_host);
            dst->fs_mounts_read_virt = NULL;
            dst->fs_mounts_read_host = NULL;
            dst->fs_mounts_read_count = 0;
            return 0;
        }
        for (int i = 0; i < n; i++) { dst->fs_mounts_read_virt[i] = NULL; dst->fs_mounts_read_host[i] = NULL; }
        for (int i = 0; i < n; i++) {
            const char* v = src->fs_mounts_read_virt[i] ? src->fs_mounts_read_virt[i] : "";
            const char* h = src->fs_mounts_read_host[i] ? src->fs_mounts_read_host[i] : "";
            size_t vl = strlen(v);
            size_t hl = strlen(h);
            dst->fs_mounts_read_virt[i] = (char*)malloc(vl + 1);
            dst->fs_mounts_read_host[i] = (char*)malloc(hl + 1);
            if (!dst->fs_mounts_read_virt[i] || !dst->fs_mounts_read_host[i]) {
                if (dst->fs_mounts_read_virt[i]) free(dst->fs_mounts_read_virt[i]);
                if (dst->fs_mounts_read_host[i]) free(dst->fs_mounts_read_host[i]);
                for (int j = 0; j < n; j++) {
                    if (dst->fs_mounts_read_virt[j]) free(dst->fs_mounts_read_virt[j]);
                    if (dst->fs_mounts_read_host[j]) free(dst->fs_mounts_read_host[j]);
                }
                free(dst->fs_mounts_read_virt);
                free(dst->fs_mounts_read_host);
                dst->fs_mounts_read_virt = NULL;
                dst->fs_mounts_read_host = NULL;
                dst->fs_mounts_read_count = 0;
                return 0;
            }
            memcpy(dst->fs_mounts_read_virt[i], v, vl); dst->fs_mounts_read_virt[i][vl] = 0;
            memcpy(dst->fs_mounts_read_host[i], h, hl); dst->fs_mounts_read_host[i][hl] = 0;
            dst->fs_mounts_read_count++;
        }
    }

    // Clone write mounts
    if (src->fs_mounts_write_count > 0 && src->fs_mounts_write_virt && src->fs_mounts_write_host) {
        int n = src->fs_mounts_write_count;
        dst->fs_mounts_write_count = 0;
        dst->fs_mounts_write_virt = (char**)malloc(sizeof(char*) * (size_t)n);
        dst->fs_mounts_write_host = (char**)malloc(sizeof(char*) * (size_t)n);
        if (!dst->fs_mounts_write_virt || !dst->fs_mounts_write_host) {
            if (dst->fs_mounts_write_virt) free(dst->fs_mounts_write_virt);
            if (dst->fs_mounts_write_host) free(dst->fs_mounts_write_host);
            dst->fs_mounts_write_virt = NULL;
            dst->fs_mounts_write_host = NULL;
            dst->fs_mounts_write_count = 0;
            return 0;
        }
        for (int i = 0; i < n; i++) { dst->fs_mounts_write_virt[i] = NULL; dst->fs_mounts_write_host[i] = NULL; }
        for (int i = 0; i < n; i++) {
            const char* v = src->fs_mounts_write_virt[i] ? src->fs_mounts_write_virt[i] : "";
            const char* h = src->fs_mounts_write_host[i] ? src->fs_mounts_write_host[i] : "";
            size_t vl = strlen(v);
            size_t hl = strlen(h);
            dst->fs_mounts_write_virt[i] = (char*)malloc(vl + 1);
            dst->fs_mounts_write_host[i] = (char*)malloc(hl + 1);
            if (!dst->fs_mounts_write_virt[i] || !dst->fs_mounts_write_host[i]) {
                if (dst->fs_mounts_write_virt[i]) free(dst->fs_mounts_write_virt[i]);
                if (dst->fs_mounts_write_host[i]) free(dst->fs_mounts_write_host[i]);
                for (int j = 0; j < n; j++) {
                    if (dst->fs_mounts_write_virt[j]) free(dst->fs_mounts_write_virt[j]);
                    if (dst->fs_mounts_write_host[j]) free(dst->fs_mounts_write_host[j]);
                }
                free(dst->fs_mounts_write_virt);
                free(dst->fs_mounts_write_host);
                dst->fs_mounts_write_virt = NULL;
                dst->fs_mounts_write_host = NULL;
                dst->fs_mounts_write_count = 0;
                return 0;
            }
            memcpy(dst->fs_mounts_write_virt[i], v, vl); dst->fs_mounts_write_virt[i][vl] = 0;
            memcpy(dst->fs_mounts_write_host[i], h, hl); dst->fs_mounts_write_host[i][hl] = 0;
            dst->fs_mounts_write_count++;
        }
    }

    return 1;
}

static char* avm_fs_map_path(const AvmVM* vm, const char* vpath, int is_write, int* matched_out) {
    if (matched_out) *matched_out = 0;
    if (!vm || !vpath) return NULL;
    if (vm->fs_backend_kind != 0) return NULL; // mapping is host-backend only

    const char* const* virt = is_write ? (const char* const*)vm->fs_mounts_write_virt : (const char* const*)vm->fs_mounts_read_virt;
    const char* const* host = is_write ? (const char* const*)vm->fs_mounts_write_host : (const char* const*)vm->fs_mounts_read_host;
    int n = is_write ? vm->fs_mounts_write_count : vm->fs_mounts_read_count;
    if (!virt || !host || n <= 0) return NULL;

    int best = -1;
    size_t best_len = 0;
    for (int i = 0; i < n; i++) {
        const char* vp = virt[i];
        if (!vp) continue;
        size_t vl = strlen(vp);
        if (vl == 0) continue;
        if (strncmp(vpath, vp, vl) == 0) {
            // Boundary check when virt_prefix does not end with '/':
            // Avoid accidental matches like 'v/mnt' matching 'v/mnt2'.
            int ok = 1;
            if (vl > 0 && vp[vl - 1] != '/') {
                char nextc = vpath[vl];
                if (nextc != 0 && nextc != '/') ok = 0;
            }
            if (ok) {
                if (vl > best_len) { best = i; best_len = vl; }
            }
        }
    }
    if (best < 0) {
        // Host-prefix fast path (parity with native runtime):
        // If the caller already passes a host path that starts with any enrolled host prefix,
        // allow it as-is. This keeps mounts as the enrollment mechanism even when higher-level
        // code pre-resolves paths.
        int best_h = -1;
        size_t best_hl = 0;
        for (int i = 0; i < n; i++) {
            const char* hp = host[i];
            if (!hp) continue;
            size_t hl = strlen(hp);
            if (hl == 0) continue;
            if (strncmp(vpath, hp, hl) == 0) {
                // Boundary check when host_prefix does not end with '/':
                // Avoid accidental matches like '/mnt' matching '/mnt2'.
                int ok = 1;
                if (hl > 0 && hp[hl - 1] != '/') {
                    char nextc = vpath[hl];
                    if (nextc != 0 && nextc != '/') ok = 0;
                }
                if (ok) {
                    if (hl > best_hl) { best_h = i; best_hl = hl; }
                }
            }
        }
        if (best_h < 0) return NULL;
        if (matched_out) *matched_out = 1;
        size_t pl = strlen(vpath);
        char* out = (char*)malloc(pl + 1);
        if (!out) return NULL;
        memcpy(out, vpath, pl);
        out[pl] = 0;
        return out;
    }
    if (matched_out) *matched_out = 1;

    const char* hp = host[best] ? host[best] : "";
    size_t hl = strlen(hp);
    const char* rest = vpath + best_len;
    size_t rl = strlen(rest);
    char* out = (char*)malloc(hl + rl + 1);
    if (!out) return NULL;
    if (hl) memcpy(out, hp, hl);
    if (rl) memcpy(out + hl, rest, rl);
    out[hl + rl] = 0;
    return out;
}

static const char* avm_fs_op_name(uint16_t op) {
    switch (op) {
        case 0: return "read_file";
        case 1: return "write_file";
        case 2: return "write_bytes";
        case 3: return "read_bytes";
        case 4: return "exists";
        case 5: return "readdir";
        default: return "fs_op";
    }
}

static void avm_format_path_short(char* out, size_t outn, const char* path) {
    if (!out || outn == 0) return;
    if (!path) {
        snprintf(out, outn, "<null>");
        return;
    }
    size_t n = strlen(path);
    if (n <= 160) {
        snprintf(out, outn, "'%s'", path);
        return;
    }
    // Keep a deterministic short prefix/suffix for diagnostics (avoid huge error strings).
    // Format: 'prefix...suffix'
    char pfx[81];
    char sfx[61];
    memcpy(pfx, path, 80);
    pfx[80] = 0;
    memcpy(sfx, path + (n - 60), 60);
    sfx[60] = 0;
    snprintf(out, outn, "'%s...%s'", pfx, sfx);
}

static AvmValue avm_err_fs_mount_denied(uint8_t domain, uint16_t op, const char* path, int is_write) {
    char pbuf[220];
    avm_format_path_short(pbuf, sizeof(pbuf), path);

    const char* opname = avm_fs_op_name(op);
    const char* rw = is_write ? "write" : "read";

    // Keep message concise but actionable. Mention both AVM_* and OREN_* env vars because
    // ./avm can be used as a runner for programs compiled from the same sources as native.
    char msg[600];
    snprintf(
        msg,
        sizeof(msg),
        "fs mount denied (%s/%s): path=%s; hint: set AVM_FS_MOUNTS[_READ|_WRITE] (or OREN_FS_MOUNTS[_READ|_WRITE])",
        opname,
        rw,
        pbuf
    );
    return avm_err_domop(AVM_ERR_PERM, msg, (int)domain, (int)op);
}

static int cmp_avm_value_string(const void* a, const void* b) {
    const AvmValue* va = (const AvmValue*)a;
    const AvmValue* vb = (const AvmValue*)b;
    const char* sa = (va && va->type == AVM_VAL_STRING && va->as.p) ? (const char*)va->as.p : "";
    const char* sb = (vb && vb->type == AVM_VAL_STRING && vb->as.p) ? (const char*)vb->as.p : "";
    return strcmp(sa, sb);
}

static AvmVfs* avm_vfs_get_or_create(AvmVM* vm) {
    if (!vm) return NULL;
    if (vm->vfs) return (AvmVfs*)vm->vfs;
    AvmVfs* v = (AvmVfs*)avm_heap_malloc_k(sizeof(AvmVfs), AVM_ALLOC_KIND_VFS);
    if (!v) return NULL;
    v->entries = NULL;
    v->count = 0;
    v->cap = 0;
    vm->vfs = v;
    return v;
}

static AvmVfsEntry* avm_vfs_find(AvmVfs* v, const char* path) {
    if (!v || !path) return NULL;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].path && strcmp(v->entries[i].path, path) == 0) return &v->entries[i];
    }
    return NULL;
}

static int avm_vfs_ensure_cap(AvmVfs* v, uint32_t need) {
    if (!v) return 0;
    if (need <= v->cap) return 1;
    uint32_t nc = v->cap ? v->cap : 16;
    while (nc < need) nc *= 2;
    AvmVfsEntry* ne = (AvmVfsEntry*)avm_heap_realloc_k(v->entries, sizeof(AvmVfsEntry) * (size_t)nc, AVM_ALLOC_KIND_VFS);
    if (!ne) return 0;
    // Initialize new slots to a safe state.
    for (uint32_t i = v->cap; i < nc; i++) {
        ne[i].path = NULL;
        ne[i].data = NULL;
        ne[i].len = 0;
    }
    v->entries = ne;
    v->cap = nc;
    return 1;
}

static int avm_vfs_put(AvmVM* vm, const char* path, const uint8_t* data, uint32_t len) {
    if (!vm || !path) return 0;
    AvmVfs* v = avm_vfs_get_or_create(vm);
    if (!v) return 0;

    AvmVfsEntry* e = avm_vfs_find(v, path);
    if (!e) {
        if (!avm_vfs_ensure_cap(v, v->count + 1)) return 0;
        e = &v->entries[v->count++];
        e->path = NULL;
        e->data = NULL;
        e->len = 0;

        size_t pl = strlen(path);
        e->path = (char*)avm_heap_malloc_k(pl + 1, AVM_ALLOC_KIND_VFS);
        if (!e->path) return 0;
        memcpy(e->path, path, pl);
        e->path[pl] = 0;
    } else {
        if (e->data) avm_heap_free(e->data);
        e->data = NULL;
        e->len = 0;
    }

    if (len > 0) {
        e->data = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_VFS);
        if (!e->data) return 0;
        memcpy(e->data, data, (size_t)len);
    }
    e->len = len;
    return 1;
}

static int avm_vfs_put_list(AvmVM* vm, const char* path, const AvmList* list) {
    if (!vm || !path) return 0;
    uint32_t len = 0;
    if (list && list->count > 0) len = (uint32_t)list->count;
    // Build a temporary buffer, then store it as file bytes.
    // This is bootstrap-simple and keeps VirtualFS data independent from list lifetime.
    uint8_t* buf = NULL;
    if (len > 0) {
        buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES);
        if (!buf) return 0;
        for (uint32_t i = 0; i < len; i++) {
            int64_t v = 0;
            if (list && list->items && (int)i < list->count) v = list->items[i].as.i;
            buf[i] = (uint8_t)(v & 0xFF);
        }
    }
    int ok = avm_vfs_put(vm, path, buf, len);
    if (buf) avm_heap_free(buf);
    return ok;
}

static int avm_vfs_clone(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src || !src->vfs) return 1;
    AvmVfs* sv = (AvmVfs*)src->vfs;
    if (!sv || sv->count == 0) return 1;

    for (uint32_t i = 0; i < sv->count; i++) {
        AvmVfsEntry* se = &sv->entries[i];
        const char* path = se->path ? se->path : "";
        const uint8_t* data = se->data;
        uint32_t len = se->len;
        if (!avm_vfs_put(dst, path, data, len)) return 0;
    }
    return 1;
}

// NOTE: legacy `oren_read_bytes` returns LIST<int>, not BYTES. VirtualFS matches that ABI.
static AvmValue avm_vfs_read_bytes_list_value(AvmVM* vm, const uint8_t* data, uint32_t len) {
    AvmValue res;
    res.type = AVM_VAL_NIL;

    AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!list) return avm_alloc_fail_value();
    list->count = (int)len;
    list->capacity = (int)len;
    list->items = NULL;
    if (len > 0) {
        list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)len, AVM_ALLOC_KIND_LIST);
        if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
        for (uint32_t i = 0; i < len; i++) {
            list->items[i].type = AVM_VAL_INT;
            list->items[i].as.i = (int64_t)(unsigned char)(data ? data[i] : 0);
        }
    }
    res.type = AVM_VAL_LIST;
    res.as.l = list;
    return res;
}

static AvmValue avm_vfs_read_string_value(AvmVM* vm, const uint8_t* data, uint32_t len) {
    AvmValue res;
    res.type = AVM_VAL_NIL;
    char* s = (char*)avm_heap_malloc_k((size_t)len + 1, AVM_ALLOC_KIND_STRING);
    if (!s) return avm_alloc_fail_value();
    if (len > 0) memcpy(s, data, (size_t)len);
    s[len] = 0;
    res.type = AVM_VAL_STRING;
    res.as.p = s;
    return res;
}

// Rolling ABI: CALL_NATIVE2(domain, op, nargs)
// For now, CORE domain (0) maps op -> legacy native id.
AvmValue avm_call_native2(AvmVM* vm, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
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
        int is_write = (op == 1 || op == 2 || op == 6) ? 1 : 0;
        int mounts_mode = 0;
        if (vm && vm->fs_backend_kind == 0) {
            // If any mounts are configured on the host FS backend, mounts become the explicit enrollment mechanism.
            // In mount mode:
            // - FS ops must match the corresponding read/write mount set
            // - there is no fallback to allow-prefixes (avoid surprising host effects)
            mounts_mode = (vm->fs_mounts_read_count > 0 || vm->fs_mounts_write_count > 0);
        }

        // Host filesystem allow-prefix policy only applies to the host FS backend, and only when mounts are not used.
        // VirtualFS is in-memory and has no host effects, so it should not be constrained by host path prefixes.
        if (vm && vm->fs_backend_kind == 0 && !mounts_mode && nargs > 0 && args[0].type == AVM_VAL_STRING) {
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

        // VirtualFS (in-memory; no host filesystem effects). Still record/replay-capable.
        if (vm && vm->fs_backend_kind == 1) {
            const char* path = (nargs > 0 && args[0].type == AVM_VAL_STRING) ? (const char*)args[0].as.p : NULL;
            AvmVfs* v = avm_vfs_get_or_create(vm);
            if (!v) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }

            switch (op) {
                case 0: { // read_file -> STRING
                    AvmVfsEntry* e = avm_vfs_find(v, path ? path : "");
                    if (!e) return avm_err_domop(AVM_ERR_NOT_FOUND, "vfs: file not found", domain, op);
                    // Preflight record log capacity, similar to host read_file: need 86 + len
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        uint64_t need = 86ull + (uint64_t)e->len;
                        if (!avm_log_can_fit(vm, need)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)e->len, (int)domain, (int)op)) return vm->last_error;
                    AvmValue ret = avm_vfs_read_string_value(vm, e->data, e->len);
                    if (avm_is_err_val(ret)) { avm_abort(vm, ret); }
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 1: { // write_file -> NIL
                    if (nargs < 2 || args[1].type != AVM_VAL_STRING) return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: write_file expects (path, string)", domain, op);
                    const char* s = (const char*)args[1].as.p;
                    uint32_t len = (uint32_t)strlen(s ? s : "");
                    // Preflight record log capacity, similar to host write_file: need 81
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)len, (int)domain, (int)op)) return vm->last_error;
                    if (!avm_vfs_put(vm, path ? path : "", (const uint8_t*)s, len)) {
                        AvmValue err = avm_alloc_fail_value();
                        avm_abort(vm, err);
                        return err;
                    }
                    AvmValue ret = avm_nil();
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 2: { // write_bytes -> NIL
                    if (nargs < 2 || args[1].type != AVM_VAL_LIST || !args[1].as.l) return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: write_bytes expects (path, list)", domain, op);
                    AvmList* list = args[1].as.l;
                    uint32_t len = (uint32_t)(list->count < 0 ? 0 : list->count);
                    // Preflight record log capacity, similar to host write_bytes: need 81
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)len, (int)domain, (int)op)) return vm->last_error;
                    if (!avm_vfs_put_list(vm, path ? path : "", list)) {
                        AvmValue err = avm_alloc_fail_value();
                        avm_abort(vm, err);
                        return err;
                    }
                    AvmValue ret = avm_nil();
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 3: { // read_bytes -> BYTES
                    AvmVfsEntry* e = avm_vfs_find(v, path ? path : "");
                    if (!e) return avm_err_domop(AVM_ERR_NOT_FOUND, "vfs: file not found", domain, op);
                    // Preflight record log capacity: legacy read_bytes returns LIST<int> of length len.
                    // value_size(LIST aux=len): 18 + len*9; entry_size: 68 + that = 86 + len*9
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        uint64_t need = 86ull + (uint64_t)e->len * 9ull;
                        if (!avm_log_can_fit(vm, need)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)e->len, (int)domain, (int)op)) return vm->last_error;
                    AvmValue ret = avm_vfs_read_bytes_list_value(vm, e->data, e->len);
                    if (avm_is_err_val(ret)) { avm_abort(vm, ret); }
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 4: { // exists(path) -> BOOL
                    // VFS semantics:
                    // - true if the exact path exists as a file
                    // - true if any entry exists under `path/` (treat as directory existence)
                    int ex = 0;
                    const char* pth = path ? path : "";
                    if (pth[0] != 0) {
                        AvmVfsEntry* fe = avm_vfs_find(v, pth);
                        if (fe) ex = 1;
                    }
                    if (!ex) {
                        size_t pl = strlen(pth);
                        if (pl > 0) {
                            for (uint32_t ii = 0; ii < v->count; ii++) {
                                const char* ep = v->entries[ii].path;
                                if (!ep) continue;
                                if (strncmp(ep, pth, pl) == 0 && ep[pl] == '/') { ex = 1; break; }
                            }
                        }
                    }

                    AvmValue ret = avm_bool(ex);
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 5: { // readdir(path) -> LIST<string>
                    const char* d = path ? path : "";
                    size_t dl = strlen(d);
                    int has_trailing = (dl > 0 && d[dl - 1] == '/');

                    AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                    if (!out) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }
                    out->count = 0;
                    out->capacity = 0;
                    out->items = NULL;

                    // Collect immediate child names by scanning VFS entries.
                    for (uint32_t ii = 0; ii < v->count; ii++) {
                        const char* ep = v->entries[ii].path;
                        if (!ep) continue;

                        const char* rest = NULL;
                        if (dl == 0) {
                            rest = ep;
                        } else if (has_trailing) {
                            if (strncmp(ep, d, dl) != 0) continue;
                            rest = ep + dl;
                        } else {
                            if (strncmp(ep, d, dl) != 0) continue;
                            if (ep[dl] != '/') continue;
                            rest = ep + dl + 1;
                        }

                        if (!rest || rest[0] == 0) continue;

                        // Immediate child name is up to next '/'.
                        const char* slash = strchr(rest, '/');
                        size_t nl = slash ? (size_t)(slash - rest) : strlen(rest);
                        if (nl == 0) continue;
                        if (nl == 1 && rest[0] == '.') continue;
                        if (nl == 2 && rest[0] == '.' && rest[1] == '.') continue;

                        // Deduplicate by linear scan (small lists; bootstrap).
                        int dup = 0;
                        for (int j = 0; j < out->count; j++) {
                            if (out->items[j].type != AVM_VAL_STRING || !out->items[j].as.p) continue;
                            const char* cur = (const char*)out->items[j].as.p;
                            if (strncmp(cur, rest, nl) == 0 && cur[nl] == 0) { dup = 1; break; }
                        }
                        if (dup) continue;

                        char* name = (char*)avm_heap_malloc_k(nl + 1, AVM_ALLOC_KIND_STRING);
                        if (!name) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }
                        memcpy(name, rest, nl);
                        name[nl] = 0;

                        if (!avm_list_ensure_cap(out, out->count + 1)) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }
                        AvmValue vv; vv.type = AVM_VAL_STRING; vv.as.p = name;
                        out->items[out->count++] = vv;
                    }

                    if (out->count > 1) qsort(out->items, (size_t)out->count, sizeof(AvmValue), cmp_avm_value_string);

                    AvmValue ret; ret.type = AVM_VAL_LIST; ret.as.l = out;
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 6: { // chmod(path, mode) -> NIL
                    // VirtualFS has no host effects and does not model POSIX permissions yet.
                    // Accept the call to keep compiler flows portable; record/replay still captures the call.
                    if (nargs < 2 || args[1].type != AVM_VAL_INT) return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: chmod expects (path, int)", domain, op);
                    if (!avm_io_charge(vm, 0, (int)domain, (int)op)) return vm->last_error;
                    AvmValue ret = avm_nil();
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }

                default:
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
            }
        }

        switch (op) {
            case 0: { // read_file
                AvmValue* use_args = args;
                AvmValue tmp_args[4];
                char* mapped = NULL;
                if (vm && vm->fs_backend_kind == 0 && mounts_mode && nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    int matched = 0;
                    mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                    if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                    if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    tmp_args[0] = args[0];
                    tmp_args[0].as.p = mapped;
                    for (int i = 1; i < nargs && i < 4; i++) tmp_args[i] = args[i];
                    use_args = tmp_args;
                }
                AvmValue ret = avm_call_native(vm, 0, use_args, nargs);
                if (mapped) free(mapped);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // write_file
                AvmValue* use_args = args;
                AvmValue tmp_args[4];
                char* mapped = NULL;
                if (vm && vm->fs_backend_kind == 0 && mounts_mode && nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    int matched = 0;
                    mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                    if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                    if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    tmp_args[0] = args[0];
                    tmp_args[0].as.p = mapped;
                    for (int i = 1; i < nargs && i < 4; i++) tmp_args[i] = args[i];
                    use_args = tmp_args;
                }
                AvmValue ret = avm_call_native(vm, 1, use_args, nargs);
                if (mapped) free(mapped);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 2: { // write_bytes
                AvmValue* use_args = args;
                AvmValue tmp_args[4];
                char* mapped = NULL;
                if (vm && vm->fs_backend_kind == 0 && mounts_mode && nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    int matched = 0;
                    mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                    if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                    if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    tmp_args[0] = args[0];
                    tmp_args[0].as.p = mapped;
                    for (int i = 1; i < nargs && i < 4; i++) tmp_args[i] = args[i];
                    use_args = tmp_args;
                }
                AvmValue ret = avm_call_native(vm, 17, use_args, nargs);
                if (mapped) free(mapped);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 3: { // read_bytes
                AvmValue* use_args = args;
                AvmValue tmp_args[4];
                char* mapped = NULL;
                if (vm && vm->fs_backend_kind == 0 && mounts_mode && nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    int matched = 0;
                    mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                    if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                    if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    tmp_args[0] = args[0];
                    tmp_args[0].as.p = mapped;
                    for (int i = 1; i < nargs && i < 4; i++) tmp_args[i] = args[i];
                    use_args = tmp_args;
                }
                AvmValue ret = avm_call_native(vm, 18, use_args, nargs);
                if (mapped) free(mapped);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 4: { // exists
                if (nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    AvmValue* use_args = args;
                    AvmValue tmp_args[1];
                    char* mapped = NULL;
                    if (vm && vm->fs_backend_kind == 0 && mounts_mode && args[0].as.p) {
                        int matched = 0;
                        mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                        if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                        if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                        tmp_args[0] = args[0];
                        tmp_args[0].as.p = mapped;
                        use_args = tmp_args;
                    }

                    const char* path2 = (use_args[0].as.p) ? (const char*)use_args[0].as.p : "";
                    int ok = (access(path2, F_OK) == 0);

                    if (mapped) free(mapped);

                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, e);
                            return e;
                        }
                    }
                    if (!avm_io_charge(vm, 0, (int)domain, (int)op)) return vm->last_error;

                    AvmValue ret = avm_bool(ok);
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                return avm_err_domop(AVM_ERR_INVALID_ARG, "exists expects (string)", domain, op);
            }
            case 5: { // readdir
                if (nargs > 0 && args && args[0].type == AVM_VAL_STRING) {
                    AvmValue* use_args = args;
                    AvmValue tmp_args[1];
                    char* mapped = NULL;
                    if (vm && vm->fs_backend_kind == 0 && mounts_mode && args[0].as.p) {
                        int matched = 0;
                        mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                        if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                        if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                        tmp_args[0] = args[0];
                        tmp_args[0].as.p = mapped;
                        use_args = tmp_args;
                    }

                    const char* path2 = (use_args[0].as.p) ? (const char*)use_args[0].as.p : "";
                    DIR* dir = opendir(path2);
                    if (!dir) {
                        int err = errno;
                        if (mapped) free(mapped);
                        return avm_err_domop(avm_err_from_errno(err), "readdir: cannot open dir", domain, op);
                    }

                    AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                    if (!out) { closedir(dir); if (mapped) free(mapped); AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }
                    out->count = 0;
                    out->capacity = 0;
                    out->items = NULL;

                    uint64_t io_bytes = 0;

                    for (;;) {
                        struct dirent* ent = readdir(dir);
                        if (!ent) break;
                        const char* name = ent->d_name;
                        if (!name) continue;
                        if (name[0] == '.' && name[1] == 0) continue;
                        if (name[0] == '.' && name[1] == '.' && name[2] == 0) continue;

                        AvmValue sv = avm_string(name);
                        if (avm_is_err_val(sv)) { closedir(dir); if (mapped) free(mapped); avm_abort(vm, sv); return sv; }
                        if (!avm_list_ensure_cap(out, out->count + 1)) { closedir(dir); if (mapped) free(mapped); AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); return e; }
                        out->items[out->count++] = sv;
                        io_bytes += (uint64_t)strlen(name);
                    }

                    closedir(dir);
                    if (mapped) free(mapped);

                    if (out->count > 1) qsort(out->items, (size_t)out->count, sizeof(AvmValue), cmp_avm_value_string);

                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 86ull + io_bytes + (uint64_t)out->count * 32ull)) {
                            AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, e);
                            return e;
                        }
                    }
                    if (!avm_io_charge(vm, io_bytes, (int)domain, (int)op)) return vm->last_error;

                    AvmValue ret; ret.type = AVM_VAL_LIST; ret.as.l = out;
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                return avm_err_domop(AVM_ERR_INVALID_ARG, "readdir expects (string)", domain, op);
            }
            case 6: { // chmod(path, mode) -> NIL
                if (nargs > 1 && args && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_INT) {
                    AvmValue* use_args = args;
                    AvmValue tmp_args[2];
                    char* mapped = NULL;
                    if (vm && vm->fs_backend_kind == 0 && mounts_mode && args[0].as.p) {
                        int matched = 0;
                        mapped = avm_fs_map_path(vm, (const char*)args[0].as.p, is_write, &matched);
                        if (!matched) return avm_err_fs_mount_denied(domain, op, (const char*)args[0].as.p, is_write);
                        if (!mapped) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                        tmp_args[0] = args[0];
                        tmp_args[0].as.p = mapped;
                        tmp_args[1] = args[1];
                        use_args = tmp_args;
                    }

                    // Preflight: ensure record log can store this entry BEFORE performing any filesystem effects.
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            if (mapped) free(mapped);
                            AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, e);
                            return e;
                        }
                    }

                    const char* path2 = (use_args[0].as.p) ? (const char*)use_args[0].as.p : "";
                    mode_t mode = (mode_t)use_args[1].as.i;
                    if (chmod(path2, mode) != 0) {
                        int err = errno;
                        if (mapped) free(mapped);
                        return avm_err_domop(avm_err_from_errno(err), "chmod failed", domain, op);
                    }

                    if (mapped) free(mapped);

                    if (!avm_io_charge(vm, 0, (int)domain, (int)op)) return vm->last_error;

                    AvmValue ret = avm_nil();
                    if (vm->record_log_bytes) { uint32_t ppos = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &ppos, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                return avm_err_domop(AVM_ERR_INVALID_ARG, "chmod expects (string, int)", domain, op);
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

        // VirtualPROC fixtures: do not execute host subprocesses; return a deterministic exit code.
        // If fixtures are loaded and cmd matches, use fixture exit code; otherwise fall back to vm->proc_exit_code.
        if (vm && vm->proc_backend_kind == 1) {
            switch (op) {
                case 0: { // system(cmd) -> INT
                    int64_t code = (int64_t)vm->proc_exit_code;
                    if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                        const char* cmd = (const char*)args[0].as.p;
                        AvmVprocEntry* e = avm_vproc_find(vm, cmd);
                        if (e) code = (int64_t)e->exit_code;
                    }
                    AvmValue ret = avm_int(code);
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }

                default:
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
            }
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

    // Domain 4: NET (bootstrap: VirtualNET fixtures only; host network is not implemented)
    if (domain == 4) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        if (vm && vm->net_backend_kind == 1) {
            switch (op) {
                case 0: { // http_get(url) -> STRING (fixture body)
                    if (nargs < 1 || args[0].type != AVM_VAL_STRING) {
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "net.get expects (url: string)", domain, op);
                    }
                    const char* url = (const char*)args[0].as.p;
                    AvmVnetEntry* e = avm_vnet_find(vm, url ? url : "");
                    if (!e) return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet: url not found", domain, op);

                    // For now, treat body as a byte string and return STRING.
                    AvmValue ret;
                    char* s = (char*)avm_heap_malloc_k((size_t)e->body_len + 1, AVM_ALLOC_KIND_STRING);
                    if (!s) { ret = avm_alloc_fail_value(); avm_abort(vm, ret); return ret; }
                    if (e->body_len > 0 && e->body) memcpy(s, e->body, e->body_len);
                    s[e->body_len] = 0;
                    ret.type = AVM_VAL_STRING;
                    ret.as.p = s;

                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }

                default:
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
            }
        }

        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "host net backend not implemented", domain, op);
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

                // Optional signature enforcement (rolling):
                // - nested universes may require that the child program is signed by a trusted root
                // - trusted_pubkey is passed as BYTES to avoid host filesystem reads in the child
                int require_sig = 0;
                int require_cert_chain = 0;
                const uint8_t* trusted_pk = NULL;
                AvmValue sv;
                if (avm_map_get_key(cfg, "require_sig", &sv)) require_sig = avm_value_truthy(sv) ? 1 : 0;
                if (avm_map_get_key(cfg, "require_cert_chain", &sv)) { if (avm_value_truthy(sv)) { require_sig = 1; require_cert_chain = 1; } }
                if (avm_map_get_key(cfg, "trusted_pubkey", &sv)) {
                    if (sv.type == AVM_VAL_BYTES && sv.as.b && sv.as.b->len == 32 && sv.as.b->data) {
                        trusted_pk = sv.as.b->data;
                    }
                }
                if (require_sig) {
                    char emsg[256];
                    const uint8_t* pkptr = trusted_pk;
                    if (!pkptr && avm_has_embedded_root_pubkey()) pkptr = NULL; // use embedded by passing NULL
                    if (!avm_obc_verify_signature_with_chain(args[0].as.b->data, (size_t)args[0].as.b->len, pkptr, require_cert_chain ? 1 : 0, emsg, sizeof(emsg))) {
                        return avm_err_domop(AVM_ERR_PERM, emsg, domain, op);
                    }
                }

                AvmProgram* prog = (AvmProgram*)malloc(sizeof(AvmProgram));
                if (!prog) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                if (!avm_parse_obc_from_bytes(args[0].as.b, prog)) {
                    free(prog);
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid obc bytes", domain, op);
                }

                AvmVM* child = avm_new();
                child->argc = 0;
                child->argv = NULL;
                char** child_argv = NULL;
                int child_argc = 0;
                // Nested universes must not touch the host filesystem by default.
                // If FS is allowed and record/replay is not configured, VirtualFS prevents accidental host effects.
                child->fs_backend_kind = 1;
                // FS allow-prefix enrollment is hierarchical: child must inherit parent restrictions by default.
                // This prevents a nested universe from widening host filesystem access by switching fs_backend to host.
                if (vm && vm->fs_allow_prefix_count > 0) {
                    if (!avm_clone_fs_allow_prefixes(child, vm)) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    }
                }
                // FS mounts enrollment is also hierarchical (host FS backend only).
                if (vm && vm->fs_backend_kind == 0 && (vm->fs_mounts_read_count > 0 || vm->fs_mounts_write_count > 0)) {
                    if (!avm_clone_fs_mounts(child, vm)) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    }
                }
                // Nested universes must not spawn host subprocesses by default.
                child->proc_backend_kind = 1;
                // Nested universes must not touch host network by default.
                child->net_backend_kind = 1;

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

                // Deterministic safety budget: call depth limit.
                // If parent is restricted, child must not exceed parent.
                child->frame_limit = vm ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (avm_map_get_key(cfg, "call_depth_max", &v)) {
                    uint64_t req = avm_value_u64(v, 0);
                    uint32_t want = (req == 0 || req > (uint64_t)MAX_FRAMES) ? (uint32_t)MAX_FRAMES : (uint32_t)req;
                    if (vm && vm->frame_limit > 0 && vm->frame_limit < (uint32_t)MAX_FRAMES && want > vm->frame_limit) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_BUDGET, "child call_depth_max exceeds parent", domain, op);
                    }
                    child->frame_limit = want;
                }

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

                // VirtualFS knobs (optional; default is safe vfs backend).
                if (avm_map_get_key(cfg, "fs_backend", &v)) child->fs_backend_kind = (int)avm_value_u64(v, (uint64_t)child->fs_backend_kind);
                // VirtualFS layering (rolling):
                // - default: inherit parent VirtualFS when the parent is using VirtualFS (nested universes).
                // - allow disabling via cfg["vfs_inherit"]=false for isolation.
                int vfs_inherit = (vm && vm->fs_backend_kind == 1) ? 1 : 0;
                if (avm_map_get_key(cfg, "vfs_inherit", &v)) vfs_inherit = avm_value_truthy(v) ? 1 : 0;
                if (vfs_inherit && child->fs_backend_kind == 1) {
                    if (!avm_vfs_clone(child, vm)) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                    }
                }
                if (avm_map_get_key(cfg, "vfs_fixtures", &v) && v.type == AVM_VAL_BYTES && v.as.b && v.as.b->data) {
                    if (child->fs_backend_kind == 1) {
                        const uint8_t* data = v.as.b->data;
                        size_t len = (size_t)v.as.b->len;
                        if (len < 12) { avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures (too short)", domain, op); }
                        const uint8_t want[8] = {'A','V','M','V','F','S','0','1'};
                        if (memcmp(data, want, 8) != 0) { avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures (expected magic AVMVFS01)", domain, op); }
                        size_t pos = 8;
                        uint32_t count = (uint32_t)data[pos] | ((uint32_t)data[pos+1] << 8) | ((uint32_t)data[pos+2] << 16) | ((uint32_t)data[pos+3] << 24);
                        pos += 4;
                        for (uint32_t i = 0; i < count; i++) {
                            if (pos + 4 > len) { avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures", domain, op); }
                            uint32_t path_len = (uint32_t)data[pos] | ((uint32_t)data[pos+1] << 8) | ((uint32_t)data[pos+2] << 16) | ((uint32_t)data[pos+3] << 24);
                            pos += 4;
                            if (pos + (size_t)path_len > len) { avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures", domain, op); }
                            char* path = (char*)malloc((size_t)path_len + 1);
                            if (!path) { avm_free(child); return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op); }
                            if (path_len > 0) memcpy(path, data + pos, path_len);
                            path[path_len] = 0;
                            pos += path_len;

                            if (pos + 4 > len) { free(path); avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures", domain, op); }
                            uint32_t body_len = (uint32_t)data[pos] | ((uint32_t)data[pos+1] << 8) | ((uint32_t)data[pos+2] << 16) | ((uint32_t)data[pos+3] << 24);
                            pos += 4;
                            if (pos + (size_t)body_len > len) { free(path); avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures", domain, op); }
                            if (!avm_vfs_put(child, path, data + pos, body_len)) { free(path); avm_free(child); return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op); }
                            free(path);
                            pos += body_len;
                        }
                        if (pos != len) { avm_free(child); return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid vfs_fixtures (trailing bytes)", domain, op); }
                    }
                }

                // VirtualPROC knobs (optional; default is safe vproc stub).
                if (avm_map_get_key(cfg, "proc_backend", &v)) child->proc_backend_kind = (int)avm_value_u64(v, (uint64_t)child->proc_backend_kind);
                if (avm_map_get_key(cfg, "proc_exit_code", &v)) child->proc_exit_code = (int)avm_value_u64(v, (uint64_t)child->proc_exit_code);
                if (avm_map_get_key(cfg, "proc_fixtures", &v) && v.type == AVM_VAL_BYTES && v.as.b && v.as.b->data) {
                    if (child->proc_backend_kind == 1) {
                        if (!avm_proc_load_fixtures(child, v.as.b->data, (size_t)v.as.b->len)) {
                            avm_free(child);
                            return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid proc_fixtures (expected magic AVMPRC01)", domain, op);
                        }
                    }
                }

                // VirtualNET knobs (optional).
                if (avm_map_get_key(cfg, "net_backend", &v)) child->net_backend_kind = (int)avm_value_u64(v, (uint64_t)child->net_backend_kind);
                if (avm_map_get_key(cfg, "net_fixtures", &v) && v.type == AVM_VAL_BYTES && v.as.b && v.as.b->data) {
                    if (child->net_backend_kind == 1) {
                        if (!avm_net_load_fixtures(child, v.as.b->data, (size_t)v.as.b->len)) {
                            avm_free(child);
                            return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid net_fixtures (expected magic AVMNET01)", domain, op);
                        }
                    }
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

                // argv (optional): list<string>
                // Needed to run CLI-like bytecode programs (compiler-in-AVM bootstrap).
                if (avm_map_get_key(cfg, "argv", &v) && v.type == AVM_VAL_LIST && v.as.l) {
                    AvmList* l = v.as.l;
                    if (l->count < 0 || l->count > 1024) {
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "argv too large", domain, op);
                    }
                    child_argc = l->count;
                    if (child_argc > 0) {
                        child_argv = (char**)malloc(sizeof(char*) * (size_t)child_argc);
                        if (!child_argv) { avm_free(child); return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op); }
                        for (int i = 0; i < child_argc; i++) child_argv[i] = NULL;
                        for (int i = 0; i < child_argc; i++) {
                            AvmValue a = l->items[i];
                            if (a.type != AVM_VAL_STRING || !a.as.p) {
                                for (int j = 0; j < child_argc; j++) if (child_argv[j]) free(child_argv[j]);
                                free(child_argv);
                                avm_free(child);
                                return avm_err_domop(AVM_ERR_INVALID_ARG, "argv expects list<string>", domain, op);
                            }
                            const char* s = (const char*)a.as.p;
                            size_t sl = strlen(s);
                            char* c = (char*)malloc(sl + 1);
                            if (!c) {
                                for (int j = 0; j < child_argc; j++) if (child_argv[j]) free(child_argv[j]);
                                free(child_argv);
                                avm_free(child);
                                return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                            }
                            memcpy(c, s, sl);
                            c[sl] = 0;
                            child_argv[i] = c;
                        }
                    }
                    child->argc = child_argc;
                    child->argv = child_argv;
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

                // Capture VirtualFS snapshot as data (optional).
                AvmValue v_vfs = avm_vfs_snapshot_bytes_value(child);
                if (v_vfs.type == AVM_VAL_BYTES && v_vfs.as.b == NULL) {
                    // Alloc fail sentinel; treat as internal error.
                    if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); }
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }

                AvmMap* out = (AvmMap*)malloc(sizeof(AvmMap));
                if (!out) {
                    if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); }
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }
                out->count = 6;
                out->capacity = 8;
                out->keys = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                out->values = (AvmValue*)malloc(sizeof(AvmValue) * out->capacity);
                if (!out->keys || !out->values) {
                    if (out->keys) free(out->keys);
                    if (out->values) free(out->values);
                    free(out);
                    if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); }
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }

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
                out->keys[5] = avm_string("vfs_snapshot");
                // v_vfs was constructed in the parent VM heap; keep it directly to avoid
                // double-allocation and to keep the snapshot reachable.
                out->values[5] = v_vfs;

                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); child->argv = NULL; child->argc = 0; }
                avm_free(child);
                // `prog->constants` may include malloc-allocated STRING/BYTES values; those were
                // freed by `avm_free(child)` via `avm_release_heap_all` (constants are roots).
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
