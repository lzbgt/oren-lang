        case 192: { // ptr_get(ptr_handle) -> int
            if (nargs > 0) res = avm_ptr_get_u64_value(vm, args[0]);
            else res = avm_err(AVM_ERR_INVALID_ARG, "ptr_get expects (ptr)");
            break;
        }
        case 193: { // ptr_set(ptr_handle, int) -> nil
            if (nargs > 1) res = avm_ptr_set_u64_value(vm, args[0], args[1]);
            else res = avm_err(AVM_ERR_INVALID_ARG, "ptr_set expects (ptr, int)");
            break;
        }
        case 194: { // ptr_get_byte(ptr_handle) -> int
            if (nargs > 0) res = avm_ptr_get_byte_value(vm, args[0]);
            else res = avm_err(AVM_ERR_INVALID_ARG, "ptr_get_byte expects (ptr)");
            break;
        }
        case 195: { // ptr_set_byte(ptr_handle, int) -> nil
            if (nargs > 1) res = avm_ptr_set_byte_value(vm, args[0], args[1]);
            else res = avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte expects (ptr, int)");
            break;
        }
        case 196: { // iadd(base_ptr, byte_offset) -> ptr_handle
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t base = 0;
                if (avm_ptr_base_from_value(vm, args[0], &base)) res = avm_int(base + args[1].as.i);
                else res = avm_err(AVM_ERR_INVALID_ARG, "iadd expects VM pointer base");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "iadd expects (ptr, int)");
            }
            break;
        }
        case 197: { // oren_buf_data_ptr_unchecked(buf) -> ptr_handle
            if (nargs > 0) {
                int64_t base = 0;
                if (avm_ptr_base_from_value(vm, args[0], &base)) res = avm_int(base);
                else res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_data_ptr_unchecked expects buffer-like value");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_buf_data_ptr_unchecked expects (buf)");
            }
            break;
        }
        case 198: { // oren_gc_pin(v) -> v
            res = (nargs > 0) ? args[0] : avm_nil();
            break;
        }
        case 199: { // oren_is_u8_buf(v) -> bool
            res = avm_bool(nargs > 0 && args[0].type == AVM_VAL_BYTES);
            break;
        }
        case 200: { // oren_string_byte_at_unchecked(s, idx) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[0].as.p && args[1].type == AVM_VAL_INT) {
                const unsigned char* s = (const unsigned char*)args[0].as.p;
                int64_t idx = args[1].as.i;
                res = (idx >= 0 && (uint64_t)idx < (uint64_t)strlen((const char*)s)) ? avm_int((int64_t)s[idx]) : avm_err(AVM_ERR_INVALID_ARG, "string_byte_at_unchecked: out of bounds");
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_byte_at_unchecked expects (string, int)");
            }
            break;
        }
        case 201: { // oren_iter_next_entry(map, idx, out_pair) -> bool
            if (nargs > 2 && args[0].type == AVM_VAL_MAP && args[0].as.m && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_LIST && args[2].as.l) {
                AvmMap* m = args[0].as.m;
                int64_t idx = args[1].as.i;
                if (idx < 0 || idx >= m->count) { res = avm_bool(0); break; }
                AvmList* out = args[2].as.l;
                if (!avm_list_ensure_cap(out, 2)) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                if (out->count < 2) out->count = 2;
                out->items[0] = m->keys[(int)idx];
                out->items[1] = m->values[(int)idx];
                out->all_int = (out->items[0].type == AVM_VAL_INT && out->items[1].type == AVM_VAL_INT);
                res = avm_bool(1);
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_iter_next_entry expects (map, int, list)");
            }
            break;
        }
        case 202: { res = avm_bool(nargs > 0 && args[0].type == AVM_VAL_STRING); break; } // oren_is_string
        case 203: { // oren_string_char_at_unchecked(s, idx) -> string
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[0].as.p && args[1].type == AVM_VAL_INT) {
                const char* s = (const char*)args[0].as.p;
                int64_t idx = args[1].as.i;
                size_t n = strlen(s);
                if (idx < 0 || (uint64_t)idx >= (uint64_t)n) { res = avm_err(AVM_ERR_INVALID_ARG, "char_at_unchecked: out of bounds"); break; }
                char* out = (char*)avm_heap_malloc_k(2, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out[0] = s[idx];
                out[1] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_char_at_unchecked expects (string, int)");
            }
            break;
        }
        case 204: { // oren_string_slice_unchecked(s, start, end) -> string
            if (nargs > 2 && args[0].type == AVM_VAL_STRING && args[0].as.p && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                const char* s = (const char*)args[0].as.p;
                int64_t start = args[1].as.i;
                int64_t end = args[2].as.i;
                int64_t len = (int64_t)strlen(s);
                if (start < 0) start = 0;
                if (end < start) end = start;
                if (end > len) end = len;
                size_t n = (size_t)(end - start);
                char* out = (char*)avm_heap_malloc_k(n + 1, AVM_ALLOC_KIND_STRING);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                memcpy(out, s + start, n);
                out[n] = 0;
                res.type = AVM_VAL_STRING;
                res.as.p = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_slice_unchecked expects (string, int, int)");
            }
            break;
        }
        case 205: { // oren_map_set_int(map, int, value) -> value
            if (nargs > 2 && args[0].type == AVM_VAL_MAP && args[0].as.m && args[1].type == AVM_VAL_INT) {
                if (!avm_map_set_sorted(args[0].as.m, args[1], args[2])) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                res = args[2];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_set_int expects (map, int, value)");
            }
            break;
        }
        case 206: { // oren_string_join(list<string>) -> string
            if (nargs <= 0 || args[0].type == AVM_VAL_NIL) { res = avm_string(""); break; }
            if (args[0].type != AVM_VAL_LIST || !args[0].as.l) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_string_join expects list"); break; }
            AvmList* list = args[0].as.l;
            size_t total = 0;
            for (int i = 0; i < list->count; i++) if (list->items[i].type == AVM_VAL_STRING && list->items[i].as.p) total += strlen((const char*)list->items[i].as.p);
            char* out = (char*)avm_heap_malloc_k(total + 1, AVM_ALLOC_KIND_STRING);
            if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            size_t off = 0;
            for (int i = 0; i < list->count; i++) {
                if (list->items[i].type != AVM_VAL_STRING || !list->items[i].as.p) continue;
                const char* s = (const char*)list->items[i].as.p;
                size_t n = strlen(s);
                memcpy(out + off, s, n);
                off += n;
            }
            out[off] = 0;
            res.type = AVM_VAL_STRING;
            res.as.p = out;
            break;
        }
        case 207: { res = avm_bool(nargs > 0 && (args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)); break; } // oren_is_list
        case 208: { res = avm_bool(nargs > 0 && args[0].type == AVM_VAL_MAP); break; } // oren_is_map
        case 209: { // oren_is_buf(v) -> bool
            int ok = nargs > 0 && (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_I32_BUF || args[0].type == AVM_VAL_I64_BUF || args[0].type == AVM_VAL_F32_BUF || args[0].type == AVM_VAL_F64_BUF);
            res = avm_bool(ok);
            break;
        }
        case 210: { // oren_map_set_str_unchecked(map, string, value) -> value
            if (nargs > 2 && args[0].type == AVM_VAL_MAP && args[0].as.m && args[1].type == AVM_VAL_STRING) {
                if (!avm_map_set_sorted(args[0].as.m, args[1], args[2])) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                res = args[2];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_map_set_str_unchecked expects (map, string, value)");
            }
            break;
        }
        case 211: { // oren_list_new_cap(cap) -> list
            int64_t cap64 = (nargs > 0 && args[0].type == AVM_VAL_INT) ? args[0].as.i : 0;
            if (cap64 < 0) cap64 = 0;
            if (cap64 > INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "list_new_cap too large"); break; }
            AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
            if (!list) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            list->count = 0;
            list->capacity = (int)cap64;
            list->all_int = 1;
            list->items = NULL;
            if (cap64 > 0) {
                list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)cap64, AVM_ALLOC_KIND_LIST);
                if (!list->items) { avm_heap_free(list); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            }
            res.type = AVM_VAL_LIST;
            res.as.l = list;
            break;
        }
        case 212: { // oren_map_new_cap(cap) -> map
            int64_t cap64 = (nargs > 0 && args[0].type == AVM_VAL_INT) ? args[0].as.i : 0;
            if (cap64 < 4) cap64 = 4;
            if (cap64 > INT32_MAX) { res = avm_err(AVM_ERR_INVALID_ARG, "map_new_cap too large"); break; }
            AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
            if (!map) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            map->count = 0;
            map->capacity = (int)cap64;
            map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
            map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
            if (!map->keys || !map->values) { if (map->keys) avm_heap_free(map->keys); if (map->values) avm_heap_free(map->values); avm_heap_free(map); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            res.type = AVM_VAL_MAP;
            res.as.m = map;
            break;
        }
        case 213: // oren_map_push_entry_str_unchecked(map, key, value) -> value
        case 214: { // oren_map_push_entry_int_unchecked(map, key, value) -> value
            if (nargs > 2 && args[0].type == AVM_VAL_MAP && args[0].as.m) {
                if ((id == 213 && args[1].type != AVM_VAL_STRING) || (id == 214 && args[1].type != AVM_VAL_INT)) {
                    res = avm_err(AVM_ERR_INVALID_ARG, "map_push_entry_unchecked key type mismatch");
                    break;
                }
                if (!avm_map_set_sorted(args[0].as.m, args[1], args[2])) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                res = args[2];
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "map_push_entry_unchecked expects (map, key, value)");
            }
            break;
        }
        case 215: { res = (nargs > 0) ? args[0] : avm_nil(); break; } // oren_map_build_finalize_unchecked
        case 216: { // oren_sha256_string(string) -> list<int 32>
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                const char* s = (const char*)args[0].as.p;
                AvmSha256Ctx ctx;
                avm_sha256_init(&ctx);
                avm_sha256_update(&ctx, (const uint8_t*)s, strlen(s));
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_sha256_string expects (string)");
            }
            break;
        }
        case 217: { // oren_read_u8_buf(path) -> bytes
            res = avm_call_native2(vm, 1, 8, args, nargs);
            break;
        }
        case 218: { // oren_file_stat_size_mtime_ns(path) -> [size, mtime_ns]|err
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                struct stat st;
                if (stat((const char*)args[0].as.p, &st) != 0) { res = avm_err(avm_err_from_errno(errno), "stat failed"); break; }
                AvmList* out = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!out) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
                out->count = 2;
                out->capacity = 2;
                out->all_int = 1;
                out->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 2u, AVM_ALLOC_KIND_LIST);
                if (!out->items) { avm_heap_free(out); res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
#if defined(__APPLE__)
                int64_t mtime_ns = (int64_t)st.st_mtimespec.tv_sec * 1000000000LL + (int64_t)st.st_mtimespec.tv_nsec;
#elif defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 200809L
                int64_t mtime_ns = (int64_t)st.st_mtim.tv_sec * 1000000000LL + (int64_t)st.st_mtim.tv_nsec;
#else
                int64_t mtime_ns = (int64_t)st.st_mtime * 1000000000LL;
#endif
                out->items[0] = avm_int((int64_t)st.st_size);
                out->items[1] = avm_int(mtime_ns);
                res.type = AVM_VAL_LIST;
                res.as.l = out;
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_file_stat_size_mtime_ns expects (string)");
            }
            break;
        }
        case 219: { // oren_rename(from, to) -> int
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) res = avm_int(rename((const char*)args[0].as.p, (const char*)args[1].as.p) == 0 ? 0 : -errno);
            else res = avm_err(AVM_ERR_INVALID_ARG, "oren_rename expects (string, string)");
            break;
        }
        case 220: { // oren_list_get(list, idx) -> value|nil
            if (nargs > 1 && args[1].type == AVM_VAL_INT) {
                int64_t idx = args[1].as.i;
                if (args[0].type == AVM_VAL_LIST && args[0].as.l && idx >= 0 && idx < args[0].as.l->count) res = args[0].as.l->items[(int)idx];
                else if (args[0].type == AVM_VAL_LIST_INT && args[0].as.li && idx >= 0 && idx < args[0].as.li->count) res = avm_int(args[0].as.li->items[(int)idx]);
                else if (args[0].type == AVM_VAL_BYTES && args[0].as.b && idx >= 0 && idx < args[0].as.b->len) res = avm_int((int64_t)args[0].as.b->data[(int)idx]);
                else res = avm_nil();
            } else {
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_list_get expects (list, int)");
            }
            break;
        }
        case 221: { // oren_mkdir_p(path) -> int
            if (nargs <= 0 || args[0].type != AVM_VAL_STRING || !args[0].as.p) { res = avm_err(AVM_ERR_INVALID_ARG, "oren_mkdir_p expects (string)"); break; }
            char* path = my_strdup((const char*)args[0].as.p);
            if (!path) { res = avm_alloc_fail_value(); avm_abort(vm, res); break; }
            int rc = 0;
            for (char* p = path + 1; *p; p++) {
                if (*p == '/') {
                    *p = 0;
                    if (avm_native_mkdir_portable(path, 0777) != 0 && errno != EEXIST) { rc = -errno; *p = '/'; break; }
                    *p = '/';
                }
            }
            if (rc == 0 && avm_native_mkdir_portable(path, 0777) != 0 && errno != EEXIST) rc = -errno;
            res = avm_int(rc);
            break;
        }
        case 222: { // oren_is_file(path) -> bool
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                struct stat st;
                res = avm_bool(stat((const char*)args[0].as.p, &st) == 0 && S_ISREG(st.st_mode));
            } else {
                res = avm_bool(0);
            }
            break;
        }
        case 223: // oren_rm_rf(path) -> int
        case 227: { // oren_unlink(path) -> int
            if (nargs > 0 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                int rc = unlink((const char*)args[0].as.p);
                if (rc == 0 || errno == ENOENT) res = avm_int(0);
                else res = avm_int(-errno);
            } else {
                res = avm_int(0);
            }
            break;
        }
        case 224: { // oren_sleep_ns(ns) -> int
            int64_t ns = (nargs > 0 && args[0].type == AVM_VAL_INT) ? args[0].as.i : 0;
            if (ns < 0) ns = 0;
            if (vm && vm->deterministic) {
                uint64_t prev = vm->virtual_sleep_ns;
                vm->virtual_sleep_ns = prev + (uint64_t)ns;
                if (vm->virtual_sleep_ns < prev) vm->virtual_sleep_ns = UINT64_MAX;
            } else if (ns > 0) {
                usleep((useconds_t)((ns + 999) / 1000));
            }
            res = avm_int(0);
            break;
        }
        case 225: { res = avm_call_native(vm, 168, args, nargs); break; } // oren_is_done
        case 226: { res = avm_nil(); break; } // oren_gc_safepoint
        case 228: { res = avm_string("???"); break; } // oren_resolve_symbol
