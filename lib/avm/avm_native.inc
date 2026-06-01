// Forward decls for helpers defined later in this include.
static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out);

static int64_t avm_oren_type_tag(AvmValue v) {
    switch (v.type) {
        case AVM_VAL_NIL: return 0;
        case AVM_VAL_INT: return 1;
        case AVM_VAL_FLOAT: return 2;
        case AVM_VAL_BOOL: return 3;
        case AVM_VAL_STRING: return 4;
        case AVM_VAL_LIST: return 6;
        case AVM_VAL_LIST_INT: return 6;
        case AVM_VAL_MAP: return 7;
        case AVM_VAL_FUNC: return 8;
        case AVM_VAL_BYTES: return 9;
        case AVM_VAL_I32_BUF: return 10;
        case AVM_VAL_I64_BUF: return 11;
        case AVM_VAL_F32_BUF: return 12;
        case AVM_VAL_F64_BUF: return 13;
        case AVM_VAL_GENERATOR: return 14;
        case AVM_VAL_GENERATOR_CONTEXT: return 15;
        default: return 0;
    }
}

static const char* avm_oren_type_name_from_tag(int64_t tag) {
    switch (tag) {
        case 0: return "nil";
        case 1: return "int";
        case 2: return "float";
        case 3: return "bool";
        case 4: return "string";
        case 5: return "py_obj";
        case 6: return "list";
        case 7: return "map";
        case 8: return "func";
        case 9: return "u8_buf";
        case 10: return "i32_buf";
        case 11: return "i64_buf";
        case 12: return "f32_buf";
        case 13: return "f64_buf";
        case 14: return "generator";
        case 15: return "generator_context";
        default: return "unknown";
    }
}

#include "avm_native_ptr_helpers.inc"

#include "avm_generator_native_helpers.inc"

static int avm_i32_pack_extract(AvmValue v, int assume_int, int32_t* out) {
    if (!assume_int && v.type != AVM_VAL_INT) return 1;
    int64_t iv = v.as.i;
    if (iv < (int64_t)INT32_MIN || iv > (int64_t)INT32_MAX) return 2;
    *out = (int32_t)iv;
    return 0;
}

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
                list->all_int = 1;
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
                list->all_int = 1;
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
                list->all_int = 1;
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
#include "avm_native_compiler_cases.inc"
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
        case 36: { // oren_bytes_to_hex(bytes|list<int 0..255>) -> string
            if (nargs > 0 && (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST)) {
                int byte_len = 0;
                AvmBytes* b = NULL;
                AvmList* list = NULL;
                if (args[0].type == AVM_VAL_BYTES) {
                    b = args[0].as.b;
                    if (!b || b->len < 0 || (b->len > 0 && !b->data)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: invalid bytes"); break; }
                    byte_len = b->len;
                } else {
                    list = args[0].as.l;
                    if (!list || list->count < 0 || (list->count > 0 && !list->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: invalid list"); break; }
                    byte_len = list->count;
                }
                static const char* hexd = "0123456789abcdef";
                size_t out_len = (size_t)byte_len * 2u;
                char* out = (char*)avm_heap_malloc_k(out_len + 1, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (int i = 0; i < byte_len; i++) {
                    uint8_t v = 0;
                    if (b) {
                        v = b->data[i];
                    } else {
                        AvmValue it = list->items[i];
                        if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: expected list<int 0..255>");
                            break;
                        }
                        v = (uint8_t)it.as.i;
                    }
                    out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
                    out[(size_t)i * 2 + 1] = hexd[v & 0xF];
                }
                if (avm_is_err_val(res)) { break; }
                out[out_len] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_bytes_to_hex expects (bytes|list<int>)");
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
        case 161: { // oren_string_from_bytes_slice(bytes|list<int 0..255>, start:int, len:int) -> string
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT &&
                (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST)) {
                int64_t start = args[1].as.i;
                int64_t n = args[2].as.i;
                int64_t total = 0;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || b->len < 0 || (b->len > 0 && !b->data)) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: invalid u8_buf"); break; }
                    total = (int64_t)b->len;
                } else {
                    AvmList* list = args[0].as.l;
                    if (!list || list->count < 0 || (list->count > 0 && !list->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: invalid list"); break; }
                    total = (int64_t)list->count;
                }
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: negative range"); break; }
                if (start > total || n > total - start) { res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: out of bounds"); break; }
                char* out = (char*)avm_heap_malloc_k((size_t)n + 1u, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (int64_t i = 0; i < n; i++) {
                    uint8_t byte = 0;
                    if (args[0].type == AVM_VAL_BYTES) {
                        byte = args[0].as.b->data[(int)(start + i)];
                    } else {
                        AvmValue it = args[0].as.l->items[(int)(start + i)];
                        if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "string_from_bytes_slice: expected list<int 0..255>");
                            break;
                        }
                        byte = (uint8_t)it.as.i;
                    }
                    out[(size_t)i] = (char)byte;
                }
                if (!avm_is_err_val(res)) {
                    out[(size_t)n] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = out;
                }
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_from_bytes_slice expects (bytes|list, int, int)");
            }
            break;
        }
        case 162: { // oren_u8_buf_from_bytes_slice(bytes|list<int 0..255>, start:int, len:int) -> u8_buf
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT &&
                (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST)) {
                int64_t start = args[1].as.i;
                int64_t n = args[2].as.i;
                int64_t total = 0;
                if (args[0].type == AVM_VAL_BYTES) {
                    AvmBytes* b = args[0].as.b;
                    if (!b || b->len < 0 || (b->len > 0 && !b->data)) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: invalid u8_buf"); break; }
                    total = (int64_t)b->len;
                } else {
                    AvmList* list = args[0].as.l;
                    if (!list || list->count < 0 || (list->count > 0 && !list->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: invalid list"); break; }
                    total = (int64_t)list->count;
                }
                if (start < 0 || n < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: negative range"); break; }
                if (start > total || n > total - start || n > 0x7fffffffLL) { res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: out of bounds"); break; }
                AvmValue bv = avm_bytes_new((int)n);
                if (bv.type != AVM_VAL_BYTES || !bv.as.b) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                for (int64_t i = 0; i < n; i++) {
                    uint8_t byte = 0;
                    if (args[0].type == AVM_VAL_BYTES) {
                        byte = args[0].as.b->data[(int)(start + i)];
                    } else {
                        AvmValue it = args[0].as.l->items[(int)(start + i)];
                        if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                            res = avm_err(AVM_ERR_INVALID_ARG, "u8_buf_from_bytes_slice: expected list<int 0..255>");
                            break;
                        }
                        byte = (uint8_t)it.as.i;
                    }
                    bv.as.b->data[(int)i] = byte;
                }
                if (!avm_is_err_val(res)) res = bv;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_u8_buf_from_bytes_slice expects (bytes|list, int, int)");
            }
            break;
        }
#include "avm_native_object_buffer_cases_a.inc"

#include "avm_native_buffer_cases_b.inc"

#include "avm_native_buffer_cases_c.inc"

#include "avm_native_buffer_cases_d.inc"
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
                out->all_int = 1;
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
