#include "avm_native_core_helpers.inc"

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
        case 229: { // oren_append_file
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                char* data = (char*)args[1].as.p;
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
                FILE* f = fopen(path, "ab");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for append: %s (errno=%d)", path, err);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                size_t len = strlen(data);
                if (!avm_io_charge(vm, (uint64_t)len, 1, 7)) { fclose(f); break; }
                size_t n = fwrite(data, 1, len, f);
                fclose(f);
                if (n != len) {
                    res = avm_err(AVM_ERR_IO, "append_file: short write");
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
#if defined(AVM_IOS_EMBED)
                res = avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "host subprocess unavailable in iOS embed build", 5, 0);
                break;
#else
                int ret = system((char*)args[0].as.p);
                res.type = AVM_VAL_INT;
                res.as.i = ret;
#endif
            }
            break;
        }
        case 3: { // oren_args
            AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
            if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            list->count = vm->argc;
            list->capacity = vm->argc;
            list->all_int = 0;
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
        case 11: { // oren_float_to_string
            if (nargs > 0 && args[0].type == AVM_VAL_FLOAT) {
                char buf[64];
                snprintf(buf, sizeof(buf), "%f", args[0].as.f);
                res.type = AVM_VAL_STRING;
                res.as.p = my_strdup(buf);
            }
            break;
        }
        case 12: // oren_list_len
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.l->count;
            } else if (nargs > 0 && args[0].type == AVM_VAL_LIST_INT) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.li->count;
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
                if (list->all_int && args[1].type != AVM_VAL_INT) list->all_int = 0;
            } else if (nargs > 1 && args[0].type == AVM_VAL_LIST_INT) {
                if (args[1].type != AVM_VAL_INT) {
                    res = avm_err(AVM_ERR_INVALID_ARG, "list_push expects int for list_int");
                    break;
                }
                AvmListInt* list = args[0].as.li;
                if (!avm_list_int_ensure_cap(list, list->count + 1)) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->items[list->count++] = args[1].as.i;
            }
            break;
        case 149: // oren_list_int_push
            if (nargs > 1 && args[0].type == AVM_VAL_LIST_INT) {
                if (args[1].type != AVM_VAL_INT) {
                    res = avm_err(AVM_ERR_INVALID_ARG, "list_int_push expects int");
                    break;
                }
                AvmListInt* list = args[0].as.li;
                if (!avm_list_int_ensure_cap(list, list->count + 1)) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                list->items[list->count++] = args[1].as.i;
            } else if (nargs > 1 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (args[1].type != AVM_VAL_INT) {
                    res = avm_err(AVM_ERR_INVALID_ARG, "list_int_push expects int");
                    break;
                }
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
                // list_int_push enforces int values, so all_int can remain true when set.
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "list_int_push expects (list, int)");
            }
            break;
        case 14: { // oren_index_set
            if (nargs > 2 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < list->count) {
                    list->items[idx] = args[2];
                    if (list->all_int && args[2].type != AVM_VAL_INT) list->all_int = 0;
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
                const char* s = (const char*)args[0].as.p;
                int len = s ? (int)strlen(s) : 0;
                AvmValue bv = avm_bytes_new(len);
                if (bv.type != AVM_VAL_BYTES || !bv.as.b) {
                    res = avm_alloc_fail_value();
                    avm_abort(vm, res);
                    break;
                }
                if (len > 0) memcpy(bv.as.b->data, s, (size_t)len);
                res = bv;
            }
            break;
        }
        case 17: { // oren_write_bytes
            if (nargs > 1 && args[0].type == AVM_VAL_STRING &&
                (args[1].type == AVM_VAL_LIST || args[1].type == AVM_VAL_BYTES)) {
                char* path = (char*)args[0].as.p;
                uint8_t* buf = NULL;
                int len = 0;
                int owns_buf = 0;

                if (args[1].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[1].as.b;
                    if (!b) { res = avm_err(AVM_ERR_INVALID_ARG, "write_bytes: null u8 buffer"); break; }
                    if (b->len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "write_bytes: invalid u8 buffer length"); break; }
                    if (b->len > 0 && !b->data) { res = avm_err(AVM_ERR_INVALID_ARG, "write_bytes: u8_buf payload is nil"); break; }
                    buf = b->data;
                    len = b->len;
                } else {
                    AvmList* list = args[1].as.l;
                    if (!list) { res = avm_err(AVM_ERR_INVALID_ARG, "write_bytes: list is nil"); break; }
                    len = list->count;
                    buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES);
                    if (!buf && len > 0) {
                        res = avm_alloc_fail_value();
                        avm_abort(vm, res);
                        break;
                    }
                    owns_buf = 1;
                    for (int i = 0; i < len; i++) {
                        buf[i] = (uint8_t)list->items[i].as.i;
                    }
                }

                // Preflight: ensure record log can store this entry BEFORE performing any filesystem effects.
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    if (!avm_log_can_fit(vm, 81ull)) {
                        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)dom, (int)capop);
                        avm_abort(vm, e);
                        res = e;
                        if (owns_buf) avm_heap_free(buf);
                        break;
                    }
                }

                FILE* f = fopen(path, "wb");
                if (!f) {
                    int err = errno;
                    char msg[512];
                    snprintf(msg, sizeof(msg), "cannot open file for write: %s (errno=%d)", path, err);
                    if (owns_buf) avm_heap_free(buf);
                    res = avm_err(avm_err_from_errno(err), msg);
                    break;
                }
                if (!avm_io_charge(vm, (uint64_t)len, 1, 2)) { fclose(f); if (owns_buf) avm_heap_free(buf); break; }
                size_t n = 0;
                if (len > 0) {
                    n = fwrite(buf, 1, (size_t)len, f);
                }
                fclose(f);
                if (owns_buf) avm_heap_free(buf);
                if (n != (size_t)len) {
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
                if (len > 2147483647L) {
                    fclose(f);
                    res = avm_err(AVM_ERR_INVALID_ARG, "read_bytes: file too large");
                    break;
                }

                // Preflight: ensure the record log has space BEFORE performing the read in record mode.
                // For read_bytes, the return shape is LIST_INT<int> of length `len` (legacy behavior).
                if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                    uint8_t dom = 0;
                    uint16_t capop = 0;
                    avm_legacy_native_to_domop(id, &dom, &capop);
                    // value_size(LIST_INT of aux=len): 18 + len*9; entry_size: 68 + that = 86 + len*9
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

                AvmValue out = avm_list_int_new((int)len);
                if (out.type != AVM_VAL_LIST_INT || !out.as.li) {
                    if (buf) avm_heap_free(buf);
                    res = out;
                    if (avm_is_err_val(res)) avm_abort(vm, res);
                    break;
                }
                AvmListInt* list = out.as.li;
                list->count = (int)len;
                if (len > 0) {
                    if (!list->items) {
                        if (buf) avm_heap_free(buf);
                        res = avm_err(AVM_ERR_INTERNAL, "read_bytes: invalid list_int output");
                        avm_abort(vm, res);
                        break;
                    }
                    for (long i = 0; i < len; i++) {
                        list->items[i] = (int64_t)(unsigned char)buf[i];
                    }
                }
                if (buf) avm_heap_free(buf);
                res = out;
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
            if (nargs > 0 && (args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int count = 0;
                if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: invalid list"); break; }
                    count = list->count;
                } else {
                    AvmListInt* list = args[0].as.li;
                    if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: invalid list_int"); break; }
                    count = list->count;
                }
                AvmValue bv = avm_bytes_new(count);
                if (bv.type != AVM_VAL_BYTES) { res = avm_err(AVM_ERR_INTERNAL, "bytes_pack: out of memory"); break; }
                if (args[0].type == AVM_VAL_LIST_INT) {
                    AvmListInt* list = args[0].as.li;
                    for (int i = 0; i < count; i++) {
                        int64_t it = list->items[i];
                        if (it < 0 || it > 255) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: expected int bytes 0..255");
                            break;
                        }
                        bv.as.b->data[i] = (uint8_t)it;
                    }
                } else {
                    AvmList* list = args[0].as.l;
                    for (int i = 0; i < count; i++) {
                        AvmValue it = list->items[i];
                        if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "bytes_pack: expected int bytes 0..255");
                            break;
                        }
                        bv.as.b->data[i] = (uint8_t)it.as.i;
                    }
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_pack expects (list)");
            }
            break;
        }
        case 31: { // oren_bytes_unpack(bytes|list<int 0..255>|list_int) -> list<int>
            if (nargs > 0 && (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int count = 0;
                AvmBytes* b = NULL;
                AvmList* src_list = NULL;
                AvmListInt* src_list_int = NULL;
                if (args[0].type == AVM_VAL_BYTES) {
                    b = args[0].as.b;
                    if (!b || b->len < 0 || (b->len > 0 && !b->data)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid bytes"); break; }
                    count = b->len;
                } else if (args[0].type == AVM_VAL_LIST) {
                    src_list = args[0].as.l;
                    if (!src_list || src_list->count < 0 || (src_list->count > 0 && !src_list->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid list"); break; }
                    count = src_list->count;
                } else {
                    src_list_int = args[0].as.li;
                    if (!src_list_int || src_list_int->count < 0 || (src_list_int->count > 0 && !src_list_int->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid list_int"); break; }
                    count = src_list_int->count;
                }
                AvmValue out = avm_list_int_new(count);
                if (out.type != AVM_VAL_LIST_INT || !out.as.li) { res = out; if (avm_is_err_val(res)) avm_abort(vm, res); break; }
                AvmListInt* list = out.as.li;
                list->count = count;
                if (count > 0) {
                    if (!list->items) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: invalid output"); break; }
                    for (int i = 0; i < count; i++) {
                        if (b) {
                            list->items[i] = (int64_t)b->data[i];
                        } else if (src_list) {
                            AvmValue it = src_list->items[i];
                            if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                                res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: expected list<int 0..255>");
                                break;
                            }
                            list->items[i] = it.as.i;
                        } else {
                            int64_t it = src_list_int->items[i];
                            if (it < 0 || it > 255) {
                                res = avm_err(AVM_ERR_INVALID_ARG, "bytes_unpack: expected list_int bytes 0..255");
                                break;
                            }
                            list->items[i] = it;
                        }
                    }
                }
                if (!avm_is_err_val(res)) res = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_unpack expects (bytes|list|list_int)");
            }
            break;
        }
        case 32: { // oren_bytes_len(bytes) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_BYTES) {
                AvmBytes* b = args[0].as.b;
                res = avm_int(b ? (int64_t)b->len : 0);
            } else if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_len: invalid list"); break; }
                res = avm_int((int64_t)list->count);
            } else if (nargs > 0 && args[0].type == AVM_VAL_LIST_INT) {
                AvmListInt* list = args[0].as.li;
                if (!list || list->count < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_len: invalid list_int"); break; }
                res = avm_int((int64_t)list->count);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_len expects (bytes|list<int>)");
            }
            break;
        }
        case 33: { // oren_bytes_get_u8(bytes, idx) -> int
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 1, 0, &u, &err_msg,
                        "bytes_get_u8: index out of bounds",
                        "oren_bytes_get_u8 expects (bytes|list<int>, int)",
                        "bytes_get_u8: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u8 expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_be: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u16_le: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_be: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 2)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i16_le: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_be: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int((int64_t)u);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u32_le: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_be: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_be: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_le: index out of bounds"); break; }
                    b->data[(int)idx] = b0;
                    b->data[(int)idx + 1] = b1;
                    b->data[(int)idx + 2] = b2;
                    b->data[(int)idx + 3] = b3;
                    res = avm_int(v);
                } else if (args[0].type == AVM_VAL_LIST) {
                    AvmList* list = args[0].as.l;
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 4)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_i32_le: index out of bounds"); break; }
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
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 2, 0, &u, &err_msg,
                        "bytes_get_u16_be: index out of bounds",
                        "oren_bytes_get_u16_be expects (bytes|list<int>, int)",
                        "bytes_get_u16_be: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u16_be expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u16_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 91: { // oren_bytes_get_u16_le(bytes|list<int>, idx) -> int (0..65535)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 2, 1, &u, &err_msg,
                        "bytes_get_u16_le: index out of bounds",
                        "oren_bytes_get_u16_le expects (bytes|list<int>, int)",
                        "bytes_get_u16_le: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u16_le expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
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
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 4, 0, &u, &err_msg,
                        "bytes_get_u32_be: index out of bounds",
                        "oren_bytes_get_u32_be expects (bytes|list<int>, int)",
                        "bytes_get_u32_be: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u32_be expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u32_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 95: { // oren_bytes_get_u32_le(bytes|list<int>, idx) -> int (0..2^32-1)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 4, 1, &u, &err_msg,
                        "bytes_get_u32_le: index out of bounds",
                        "oren_bytes_get_u32_le expects (bytes|list<int>, int)",
                        "bytes_get_u32_le: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u32_le expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
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
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 8, 0, &u, &err_msg,
                        "bytes_get_u64_be: index out of bounds",
                        "oren_bytes_get_u64_be expects (bytes|list<int>, int)",
                        "bytes_get_u64_be: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u64_be expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_get_u64_be expects (bytes|list<int>, int)");
            }
            break;
        }
        case 99: { // oren_bytes_get_u64_le(bytes|list<int>, idx) -> int (signed int64 bits)
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                uint64_t u = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_read_u64_span(args[0], args[1].as.i, 8, 1, &u, &err_msg,
                        "bytes_get_u64_le: index out of bounds",
                        "oren_bytes_get_u64_le expects (bytes|list<int>, int)",
                        "bytes_get_u64_le: byte out of range")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_get_u64_le expects (bytes|list<int>, int)");
                    break;
                }
                res = avm_int((int64_t)u);
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 8)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_be: index out of bounds"); break; }
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
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 8)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_be: index out of bounds"); break; }
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
                    if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, 8)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_le: index out of bounds"); break; }
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
                    if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, 8)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_set_u64_le: index out of bounds"); break; }
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
#include "avm_native_compiler_cases.inc"
#include "avm_native_byte_iter_cases.inc"

#include "avm_native_object_buffer_cases_a.inc"

#include "avm_native_buffer_cases_b.inc"

#include "avm_native_buffer_cases_e.inc"

#include "avm_native_buffer_cases_c.inc"

#include "avm_native_buffer_cases_d.inc"
        }
#include "avm_native_core_tail_cases.inc"
        default:
            printf("Unknown native id: %d\n", id);
            break;
    }
    return res;
}

#include "avm_native_clone_helpers.inc"


#include "avm_native_fs_universe_helpers.inc"


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

#include "avm_native_capability_domain_fs.inc"


#include "avm_native_capability_domains_misc.inc"
}
