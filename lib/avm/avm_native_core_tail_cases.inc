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
        case 120: { // oren_sha256_range(bytes|list<int 0..255>|list_int, start:int, len:int) -> list<int 32>
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT) {
                int64_t start = args[1].as.i;
                int64_t len = args[2].as.i;
                int64_t total = 0;
                const char* err_msg = NULL;
                if (!avm_native_bytes_len_checked(args[0], &total, &err_msg,
                        "sha256_range: invalid u8_buf",
                        "sha256_range: invalid list",
                        "sha256_range: invalid list_int",
                        "oren_sha256_range expects (bytes|list|list_int,int,int)")) {
                    res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_sha256_range expects (bytes|list|list_int,int,int)");
                    break;
                }
                if (start < 0 || len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: negative range"); break; }
                if (start > total || len > total - start) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: out of bounds"); break; }

                AvmSha256Ctx ctx;
                avm_sha256_init(&ctx);

                uint8_t chunk[64 * 1024];
                int64_t off = 0;
                while (off < len) {
                    int64_t remaining = len - off;
                    int64_t want_i64 = remaining > (int64_t)sizeof(chunk) ? (int64_t)sizeof(chunk) : remaining;
                    if (!avm_native_bytes_copy_span(args[0], start + off, want_i64, chunk, &err_msg,
                            "sha256_range: out of bounds",
                            "oren_sha256_range expects (bytes|list|list_int,int,int)",
                            "sha256_range: expected list<int 0..255>",
                            "sha256_range: expected list_int bytes 0..255")) {
                        res = avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "sha256_range: expected bytes 0..255");
                        break;
                    }
                    avm_sha256_update(&ctx, chunk, (size_t)want_i64);
                    off += want_i64;
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
                res = avm_err(AVM_ERR_INVALID_ARG, "oren_sha256_range expects (bytes|list|list_int,int,int)");
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
