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
            if (nargs > 2 && args[1].type == AVM_VAL_INT && args[2].type == AVM_VAL_INT &&
                (args[0].type == AVM_VAL_BYTES || args[0].type == AVM_VAL_LIST || args[0].type == AVM_VAL_LIST_INT)) {
                int64_t start = args[1].as.i;
                int64_t len = args[2].as.i;
                int64_t total = 0;
                AvmBytes* bytes = NULL;
                AvmList* list = NULL;
                AvmListInt* list_int = NULL;
                if (args[0].type == AVM_VAL_BYTES) {
                    bytes = args[0].as.b;
                    if (!bytes || bytes->len < 0 || (bytes->len > 0 && !bytes->data)) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: invalid u8_buf"); break; }
                    total = (int64_t)bytes->len;
                } else if (args[0].type == AVM_VAL_LIST) {
                    list = args[0].as.l;
                    if (!list || list->count < 0 || (list->count > 0 && !list->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: invalid list"); break; }
                    total = (int64_t)list->count;
                } else {
                    list_int = args[0].as.li;
                    if (!list_int || list_int->count < 0 || (list_int->count > 0 && !list_int->items)) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: invalid list_int"); break; }
                    total = (int64_t)list_int->count;
                }
                if (start < 0 || len < 0) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: negative range"); break; }
                if (start > total || len > total - start) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: out of bounds"); break; }

                AvmSha256Ctx ctx;
                avm_sha256_init(&ctx);
                if (bytes) {
                    if (len > 0) avm_sha256_update(&ctx, bytes->data + (size_t)start, (size_t)len);
                } else {
                    for (int64_t i = 0; i < len; i++) {
                        int64_t v = 0;
                        if (list) {
                            AvmValue it = list->items[(int)(start + i)];
                            if (it.type != AVM_VAL_INT) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: expected list<int 0..255>"); break; }
                            v = it.as.i;
                        } else {
                            v = list_int->items[(int)(start + i)];
                        }
                        if (v < 0 || v > 255) { res = avm_err(AVM_ERR_INVALID_ARG, "sha256_range: expected bytes 0..255"); break; }
                        uint8_t b = (uint8_t)v;
                        avm_sha256_update(&ctx, &b, 1);
                    }
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
