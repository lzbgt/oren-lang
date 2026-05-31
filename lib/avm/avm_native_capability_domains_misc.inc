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
                AvmValue ret = avm_int(0);
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
            case 2: { // unix_ns()
                AvmValue ret;
                if (vm->deterministic) {
                    __uint128_t t = (__uint128_t)vm->virtual_now_ns;
                    t += (__uint128_t)vm->virtual_sleep_ns;
                    t += (__uint128_t)vm->gas_executed * (__uint128_t)vm->virtual_step_ns;
                    uint64_t t64 = (t > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)t;
                    int64_t out = (t64 > (uint64_t)INT64_MAX) ? INT64_MAX : (int64_t)t64;
                    ret = avm_int(out);
                } else {
                    ret = avm_int((int64_t)avm_unix_ns());
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

    // Domain 4: NET. OBC sees fixture/live-fetch results through the same
    // operation; embedders own host network policy and callbacks.
    if (domain == 4) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }

        switch (op) {
            case 0: { // http_get(url) -> STRING
                if (nargs < 1 || args[0].type != AVM_VAL_STRING) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.get expects (url: string)", domain, op);
                }
                const char* url = (const char*)args[0].as.p;
                const uint8_t* body = NULL;
                uint32_t body_len = 0;
                uint8_t* callback_body = NULL;
                size_t callback_len = 0;

                if (vm && vm->net_backend_kind == 1) {
                    AvmVnetEntry* e = avm_vnet_find(vm, url ? url : "");
                    if (e) {
                        body = e->body;
                        body_len = e->body_len;
                    } else if (vm->net_fetch_fn) {
                        if (vm->net_fetch_fn(vm->net_fetch_user_data, url ? url : "", &callback_body, &callback_len) != 0) {
                            return avm_err_domop(AVM_ERR_NOT_FOUND, "net host fetch failed", domain, op);
                        }
                        if (callback_len > (size_t)UINT32_MAX || (callback_len > 0 && !callback_body)) {
                            if (callback_body) free(callback_body);
                            return avm_err_domop(AVM_ERR_BUDGET, "net host fetch response too large", domain, op);
                        }
                        body = callback_body;
                        body_len = (uint32_t)callback_len;
                    } else {
                        return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet: url not found", domain, op);
                    }
                } else {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "host net backend not implemented", domain, op);
                }

                // For now, treat body as a byte string and return STRING.
                AvmValue ret;
                char* s = (char*)avm_heap_malloc_k((size_t)body_len + 1, AVM_ALLOC_KIND_STRING);
                if (!s) {
                    if (callback_body) free(callback_body);
                    ret = avm_alloc_fail_value(); avm_abort(vm, ret); return ret;
                }
                if (body_len > 0 && body) memcpy(s, body, body_len);
                s[body_len] = 0;
                if (callback_body) free(callback_body);
                ret.type = AVM_VAL_STRING;
                ret.as.p = s;

                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 1: { // session_open(spec, timeout_ms) -> INT virtual session id
                if (nargs < 1 || args[0].type != AVM_VAL_STRING) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_open expects (spec: string, timeout_ms?: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_session_open_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet session open not implemented", domain, op);
                }
                uint32_t timeout_ms = 0;
                if (nargs >= 2) timeout_ms = (uint32_t)avm_value_u64(args[1], 0);
                uint32_t session_id = 0;
                if (vm->net_session_open_fn(vm->net_session_user_data, (const char*)args[0].as.p, timeout_ms, &session_id) != 0 || session_id == 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet session open failed", domain, op);
                }
                AvmValue ret = avm_int((int64_t)session_id);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 2: { // session_write(session_id, data, timeout_ms) -> INT bytes written
                if (nargs < 2 || args[0].type != AVM_VAL_INT || (!((args[1].type == AVM_VAL_BYTES && args[1].as.b) || args[1].type == AVM_VAL_STRING))) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_write expects (session_id: int, data: bytes|string, timeout_ms?: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_session_write_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet session write not implemented", domain, op);
                }
                const uint8_t* data = NULL;
                size_t len = 0;
                if (args[1].type == AVM_VAL_BYTES) {
                    data = args[1].as.b->data;
                    len = (size_t)args[1].as.b->len;
                } else {
                    const char* s = (const char*)args[1].as.p;
                    data = (const uint8_t*)s;
                    len = s ? strlen(s) : 0;
                }
                if (!avm_io_charge(vm, (uint64_t)len, domain, op)) return vm->last_error;
                uint32_t timeout_ms = 0;
                if (nargs >= 3) timeout_ms = (uint32_t)avm_value_u64(args[2], 0);
                size_t written = 0;
                if (vm->net_session_write_fn(vm->net_session_user_data, (uint32_t)avm_value_u64(args[0], 0), data, len, timeout_ms, &written) != 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet session write failed", domain, op);
                }
                AvmValue ret = avm_int((int64_t)written);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 3: { // session_read(session_id, max_len, timeout_ms) -> BYTES
                if (nargs < 2 || args[0].type != AVM_VAL_INT || args[1].type != AVM_VAL_INT) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_read expects (session_id: int, max_len: int, timeout_ms?: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_session_read_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet session read not implemented", domain, op);
                }
                uint64_t max_len64 = avm_value_u64(args[1], 0);
                if (max_len64 > (uint64_t)UINT32_MAX) {
                    return avm_err_domop(AVM_ERR_BUDGET, "vnet session read too large", domain, op);
                }
                uint32_t timeout_ms = 0;
                if (nargs >= 3) timeout_ms = (uint32_t)avm_value_u64(args[2], 0);
                uint8_t* callback_body = NULL;
                size_t callback_len = 0;
                if (vm->net_session_read_fn(vm->net_session_user_data, (uint32_t)avm_value_u64(args[0], 0), (size_t)max_len64, timeout_ms, &callback_body, &callback_len) != 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet session read failed", domain, op);
                }
                if (callback_len > (size_t)UINT32_MAX || callback_len > (size_t)max_len64 || (callback_len > 0 && !callback_body)) {
                    if (callback_body) free(callback_body);
                    return avm_err_domop(AVM_ERR_BUDGET, "vnet session read response too large", domain, op);
                }
                if (!avm_io_charge(vm, (uint64_t)callback_len, domain, op)) {
                    if (callback_body) free(callback_body);
                    return vm->last_error;
                }
                AvmValue ret = avm_bytes_new((int)callback_len);
                if (ret.type != AVM_VAL_BYTES || !ret.as.b) {
                    if (callback_body) free(callback_body);
                    avm_abort(vm, ret); return ret;
                }
                if (callback_len > 0 && callback_body) memcpy(ret.as.b->data, callback_body, callback_len);
                if (callback_body) free(callback_body);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 4: { // session_close(session_id) -> INT
                if (nargs < 1 || args[0].type != AVM_VAL_INT) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_close expects (session_id: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_session_close_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet session close not implemented", domain, op);
                }
                if (vm->net_session_close_fn(vm->net_session_user_data, (uint32_t)avm_value_u64(args[0], 0)) != 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet session close failed", domain, op);
                }
                AvmValue ret = avm_int(0);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 5: { // session_poll(session_id, events, timeout_ms) -> INT ready mask
                if (nargs < 2 || args[0].type != AVM_VAL_INT || args[1].type != AVM_VAL_INT) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_poll expects (session_id: int, events: int, timeout_ms?: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_session_poll_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet session poll not implemented", domain, op);
                }
                uint32_t events = (uint32_t)avm_value_u64(args[1], 0);
                if ((events & ~3u) != 0 || events == 0) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.session_poll events must use read=1/write=2", domain, op);
                }
                uint32_t timeout_ms = 0;
                if (nargs >= 3) timeout_ms = (uint32_t)avm_value_u64(args[2], 0);
                uint32_t ready = 0;
                if (vm->net_session_poll_fn(vm->net_session_user_data, (uint32_t)avm_value_u64(args[0], 0), events, timeout_ms, &ready) != 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet session poll failed", domain, op);
                }
                AvmValue ret = avm_int((int64_t)(ready & events));
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            case 6: { // resolve_host(host, timeout_ms) -> LIST<STRING>
                if (nargs < 1 || args[0].type != AVM_VAL_STRING) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "net.resolve_host expects (host: string, timeout_ms?: int)", domain, op);
                }
                if (!vm || vm->net_backend_kind != 1 || !vm->net_resolve_fn) {
                    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "vnet host resolve not implemented", domain, op);
                }
                uint32_t timeout_ms = 0;
                if (nargs >= 2) timeout_ms = (uint32_t)avm_value_u64(args[1], 0);
                char** ips = NULL;
                size_t ip_count = 0;
                if (vm->net_resolve_fn(vm->net_resolve_user_data, (const char*)args[0].as.p, timeout_ms, &ips, &ip_count) != 0) {
                    return avm_err_domop(AVM_ERR_NOT_FOUND, "vnet host resolve failed", domain, op);
                }
                if (ip_count > 64 || (ip_count > 0 && !ips)) {
                    if (ips) {
                        for (size_t i = 0; i < ip_count; i++) free(ips[i]);
                        free(ips);
                    }
                    return avm_err_domop(AVM_ERR_BUDGET, "vnet host resolve response too large", domain, op);
                }
                uint64_t total_len = 0;
                for (size_t i = 0; i < ip_count; i++) {
                    if (!ips[i]) {
                        for (size_t j = 0; j < ip_count; j++) free(ips[j]);
                        free(ips);
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "vnet host resolve returned nil IP", domain, op);
                    }
                    total_len += (uint64_t)strlen(ips[i]);
                }
                if (!avm_io_charge(vm, total_len, domain, op)) {
                    for (size_t i = 0; i < ip_count; i++) free(ips[i]);
                    free(ips);
                    return vm->last_error;
                }
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) {
                    for (size_t i = 0; i < ip_count; i++) free(ips[i]);
                    free(ips);
                    AvmValue err = avm_alloc_fail_value(); avm_abort(vm, err); return err;
                }
                list->count = (int)ip_count;
                list->capacity = (int)ip_count;
                list->all_int = 0;
                list->items = NULL;
                if (ip_count > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * ip_count, AVM_ALLOC_KIND_LIST);
                    if (!list->items) {
                        for (size_t i = 0; i < ip_count; i++) free(ips[i]);
                        free(ips);
                        AvmValue err = avm_alloc_fail_value(); avm_abort(vm, err); return err;
                    }
                    for (size_t i = 0; i < ip_count; i++) {
                        char* copy = (char*)avm_heap_malloc_k(strlen(ips[i]) + 1u, AVM_ALLOC_KIND_STRING);
                        if (!copy) {
                            for (size_t j = 0; j < ip_count; j++) free(ips[j]);
                            free(ips);
                            AvmValue err = avm_alloc_fail_value(); avm_abort(vm, err); return err;
                        }
                        strcpy(copy, ips[i]);
                        list->items[i].type = AVM_VAL_STRING;
                        list->items[i].as.p = copy;
                    }
                }
                for (size_t i = 0; i < ip_count; i++) free(ips[i]);
                free(ips);
                AvmValue ret;
                ret.type = AVM_VAL_LIST;
                ret.as.l = list;
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }

            default:
                return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
        }
    }

    // Domain 9: GFX frame mailbox.
    // Oren owns portable command-frame data; the host app owns rendering devices.
    if (domain == 9) {
        switch (op) {
            case 0: { // present_frame(frame_bytes: bytes|string) -> INT
                const uint8_t* data = NULL;
                size_t len = 0;
                if (nargs >= 1 && args[0].type == AVM_VAL_BYTES && args[0].as.b) {
                    AvmBytes* b = args[0].as.b;
                    data = b->data;
                    len = (size_t)b->len;
                } else if (nargs >= 1 && args[0].type == AVM_VAL_STRING && args[0].as.p) {
                    const char* s = (const char*)args[0].as.p;
                    data = (const uint8_t*)s;
                    len = strlen(s);
                } else {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "gfx.present_frame expects frame bytes", domain, op);
                }
                if (!data || len == 0 || len > (size_t)UINT32_MAX) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "gfx.present_frame invalid frame size", domain, op);
                }
                char gfx_err[160];
                if (!avm_gfx_validate_frame(data, len, gfx_err, sizeof(gfx_err))) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, gfx_err, domain, op);
                }
                if (!avm_io_charge(vm, (uint64_t)len, domain, op)) return vm->last_error;
                uint8_t* copy = (uint8_t*)malloc(len);
                if (!copy) return avm_err_domop(AVM_ERR_BUDGET, "gfx.present_frame allocation failed", domain, op);
                memcpy(copy, data, len);
                if (vm->gfx_frame_data) free(vm->gfx_frame_data);
                vm->gfx_frame_data = copy;
                vm->gfx_frame_len = len;
                AvmValue ret = avm_int(0);
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            case 1: { // poll_input() -> BYTES|NIL
                if (vm->replay_log_bytes) {
                    return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
                }
                if (vm->replay_log) {
                    return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
                }
                AvmValue ret = avm_nil();
                AvmGfxInputQueue* q = vm ? (AvmGfxInputQueue*)vm->gfx_input_queue : NULL;
                if (q && q->count > 0 && q->entries) {
                    AvmGfxInputEntry entry = q->entries[0];
                    if (!avm_io_charge(vm, (uint64_t)entry.len, domain, op)) return vm->last_error;
                    ret = avm_bytes_new((int)entry.len);
                    if (ret.type != AVM_VAL_BYTES || !ret.as.b) { avm_abort(vm, ret); return ret; }
                    if (entry.len > 0 && entry.data) memcpy(ret.as.b->data, entry.data, entry.len);
                    if (entry.data) free(entry.data);
                    if (q->count > 1u) {
                        memmove(q->entries, q->entries + 1, sizeof(AvmGfxInputEntry) * (size_t)(q->count - 1u));
                    }
                    q->count--;
                    if (q->entries) {
                        q->entries[q->count].data = NULL;
                        q->entries[q->count].len = 0;
                    }
                }
                if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default:
                return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported GFX domain/op", domain, op);
        }
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

                AvmVM* child = avm_new();
                if (!child) return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                AvmProgram* prog = (AvmProgram*)malloc(sizeof(AvmProgram));
                if (!prog) {
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }
                if (!avm_parse_obc_from_bytes(child, args[0].as.b, prog)) {
                    avm_free(child);
                    free(prog);
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "invalid obc bytes", domain, op);
                }

                child->argc = 0;
                child->argv = NULL;
                child->prog_constants_heap_owned = 1;
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
                // TMP freelist config (inherit from parent by default).
                child->tmp_freelist_enabled = vm ? vm->tmp_freelist_enabled : 0;
                child->tmp_freelist_cap_bytes = vm ? vm->tmp_freelist_cap_bytes : 0;
                child->tmp_freelist_max_block_bytes = vm ? vm->tmp_freelist_max_block_bytes : 0;
                child->list_freelist_enabled = vm ? vm->list_freelist_enabled : 0;
                child->list_freelist_cap_bytes = vm ? vm->list_freelist_cap_bytes : 0;
                child->list_freelist_max_block_bytes = vm ? vm->list_freelist_max_block_bytes : 0;

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
                if (avm_map_get_key(cfg, "vfs_fixtures", &v)) {
                    if (v.type != AVM_VAL_BYTES || !v.as.b || !v.as.b->data) {
                        char msg[128];
                        snprintf(msg, sizeof(msg), "vfs_fixtures expects BYTES, got type=%d", (int)v.type);
                        avm_free(child);
                        return avm_err_domop(AVM_ERR_INVALID_ARG, msg, domain, op);
                    }
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

                // Return a deterministic map.
                //
                // Important: AVM map lookups use a deterministic sorted-key representation
                // (binary search). Build the map via `avm_map_set_sorted`, not by manually
                // populating arrays in arbitrary order.
                AvmMap* out = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                if (!out) {
                    if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); }
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }
                out->count = 0;
                out->capacity = 0;
                out->keys = NULL;
                out->values = NULL;

                int ok = 1;
                ok = ok && avm_map_set_sorted(out, avm_string("exit_code"), avm_int((int64_t)child->exit_code));
                ok = ok && avm_map_set_sorted(out, avm_string("result_hash"), v_rh);
                ok = ok && avm_map_set_sorted(out, avm_string("state_hash"), v_sh);
                AvmValue v_log;
                v_log.type = AVM_VAL_BYTES;
                v_log.as.b = child->record_log_bytes;
                ok = ok && avm_map_set_sorted(out, avm_string("record_log"), avm_clone_value(v_log));
                ok = ok && avm_map_set_sorted(out, avm_string("last_error"), avm_clone_value(child->last_error));
                // v_vfs was constructed in the parent VM heap; keep it directly to avoid
                // double-allocation and to keep the snapshot reachable.
                ok = ok && avm_map_set_sorted(out, avm_string("vfs_snapshot"), v_vfs);
                ok = ok && avm_map_set_sorted(out, avm_string("result"), child->has_result_value ? avm_clone_value(child->result_value) : avm_nil());
                if (!ok) {
                    if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); }
                    avm_free(child);
                    return avm_err_domop(AVM_ERR_INTERNAL, "oom", domain, op);
                }

                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                if (child_argv) { for (int i = 0; i < child_argc; i++) if (child_argv[i]) free(child_argv[i]); free(child_argv); child->argv = NULL; child->argc = 0; }
                avm_free(child);
                // The constants array is malloc-owned, while referenced constants are child-heap
                // objects and are released by `avm_free(child)` because constants are VM roots.
                if (prog->constants) free(prog->constants);
                free(prog);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
    }

    // Domain 10: Permission request mailbox. OBC publishes intent; the embedder
    // decides whether to grant/restrict the corresponding virtual provider.
    if (domain == 10) {
        switch (op) {
            case 0: { // permission_request(domain, action, detail) -> INT sequence
                if (nargs < 2 || args[0].type != AVM_VAL_STRING || args[1].type != AVM_VAL_STRING) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "permission.request expects (domain: string, action: string, detail?: string)", domain, op);
                }
                const char* req_domain = (const char*)args[0].as.p;
                const char* req_action = (const char*)args[1].as.p;
                const char* req_detail = "";
                if (nargs >= 3) {
                    if (args[2].type != AVM_VAL_STRING) {
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "permission.request detail must be string", domain, op);
                    }
                    req_detail = (const char*)args[2].as.p;
                }
                if (!req_domain || !req_action || !req_detail) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "permission.request strings must be non-null", domain, op);
                }
                size_t domain_len = strlen(req_domain);
                size_t action_len = strlen(req_action);
                size_t detail_len = strlen(req_detail);
                if (domain_len == 0 || action_len == 0 || domain_len > 255u || action_len > 255u || detail_len > 4096u) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "permission.request field length out of range", domain, op);
                }
                size_t total_len = 20u + domain_len + action_len + detail_len;
                if (!avm_io_charge(vm, (uint64_t)total_len, domain, op)) return vm->last_error;
                uint8_t* payload = (uint8_t*)malloc(total_len);
                if (!payload) return avm_err_domop(AVM_ERR_BUDGET, "failed to allocate permission request", domain, op);
                uint32_t seq = vm ? (vm->permission_request_sequence + 1u) : 1u;
                if (seq == 0) seq = 1u;
                size_t p = 0;
                payload[p++] = 'O'; payload[p++] = 'P'; payload[p++] = 'R'; payload[p++] = '0';
                payload[p++] = 1; payload[p++] = 0;
                payload[p++] = 20; payload[p++] = 0;
                payload[p++] = (uint8_t)(seq & 0xffu);
                payload[p++] = (uint8_t)((seq >> 8) & 0xffu);
                payload[p++] = (uint8_t)((seq >> 16) & 0xffu);
                payload[p++] = (uint8_t)((seq >> 24) & 0xffu);
                payload[p++] = (uint8_t)domain_len; payload[p++] = 0;
                payload[p++] = (uint8_t)action_len; payload[p++] = 0;
                uint32_t dl = (uint32_t)detail_len;
                payload[p++] = (uint8_t)(dl & 0xffu);
                payload[p++] = (uint8_t)((dl >> 8) & 0xffu);
                payload[p++] = (uint8_t)((dl >> 16) & 0xffu);
                payload[p++] = (uint8_t)((dl >> 24) & 0xffu);
                memcpy(payload + p, req_domain, domain_len); p += domain_len;
                memcpy(payload + p, req_action, action_len); p += action_len;
                if (detail_len > 0) memcpy(payload + p, req_detail, detail_len);
                if (vm) {
                    if (vm->permission_request_data) free(vm->permission_request_data);
                    vm->permission_request_data = payload;
                    vm->permission_request_len = total_len;
                    vm->permission_request_sequence = seq;
                } else {
                    free(payload);
                }
                AvmValue ret = avm_int((int64_t)seq);
                if (vm && vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                if (vm && vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                return ret;
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported permission domain/op", domain, op);
    }

    // Domain 11: AVM virtual-resource event bus. OBC watches virtual handles and
    // mailboxes; host adapters may map those to select/kqueue/dispatch internally.
    if (domain == 11) {
        if (vm->replay_log_bytes) {
            return rr_replay_entry_mem(vm, vm->replay_log_bytes, &vm->replay_log_pos, domain, op, args, nargs);
        }
        if (vm->replay_log) {
            return rr_replay_entry(vm, vm->replay_log, domain, op, args, nargs);
        }
        switch (op) {
            case 0: { // event_select(watches: list<map>, timeout_ms?: int) -> map|nil
                if (nargs < 1 || args[0].type != AVM_VAL_LIST || !args[0].as.l) {
                    return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select expects (watches: list, timeout_ms?: int)", domain, op);
                }
                AvmList* watches = args[0].as.l;
                if (watches->count < 0 || watches->count > 1024) {
                    return avm_err_domop(AVM_ERR_BUDGET, "event.select watch count too large", domain, op);
                }
                uint32_t timeout_ms = 0;
                if (nargs >= 2) timeout_ms = (uint32_t)avm_value_u64(args[1], 0);
                uint64_t start_ns = 0;
                if (vm->deterministic) {
                    __uint128_t t = (__uint128_t)vm->virtual_now_ns + (__uint128_t)vm->virtual_sleep_ns + (__uint128_t)vm->gas_executed * (__uint128_t)vm->virtual_step_ns;
                    start_ns = (t > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)t;
                } else {
                    start_ns = avm_now_ns();
                }
                uint64_t deadline_ns = start_ns;
                if (timeout_ms > 0) {
                    __uint128_t d = (__uint128_t)start_ns + (__uint128_t)timeout_ms * 1000000ull;
                    deadline_ns = (d > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)d;
                }

                while (1) {
                    uint64_t now_ns = 0;
                    if (vm->deterministic) {
                        __uint128_t t = (__uint128_t)vm->virtual_now_ns + (__uint128_t)vm->virtual_sleep_ns + (__uint128_t)vm->gas_executed * (__uint128_t)vm->virtual_step_ns;
                        now_ns = (t > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)t;
                    } else {
                        now_ns = avm_now_ns();
                    }

                    uint32_t session_ids[1024];
                    uint32_t session_events[1024];
                    int session_watch_index[1024];
                    int net_count = 0;
                    int has_cancel_watch = 0;
                    uint64_t nearest_timer_ns = UINT64_MAX;

                    for (int i = 0; i < watches->count; i++) {
                        AvmValue wv = watches->items[i];
                        if (wv.type != AVM_VAL_MAP || !wv.as.m) {
                            return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select watch must be map", domain, op);
                        }
                        AvmValue kindv;
                        if (!avm_map_get_key(wv, "kind", &kindv) || kindv.type != AVM_VAL_STRING || !kindv.as.p) {
                            return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select watch missing kind", domain, op);
                        }
                        const char* kind = (const char*)kindv.as.p;
                        if (strcmp(kind, "timer") == 0) {
                            AvmValue dv;
                            if (!avm_map_get_key(wv, "deadline_ns", &dv) || dv.type != AVM_VAL_INT) {
                                return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select timer watch missing deadline_ns", domain, op);
                            }
                            uint64_t d = (dv.as.i < 0) ? 0u : (uint64_t)dv.as.i;
                            if (d <= now_ns) {
                                AvmMap* out = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                                if (!out) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                memset(out, 0, sizeof(*out));
                                AvmValue idv;
                                if (!avm_map_get_key(wv, "id", &idv)) idv = avm_int(i);
                                int ok = 1;
                                ok = ok && avm_map_set_sorted(out, avm_string("kind"), avm_string("timer"));
                                ok = ok && avm_map_set_sorted(out, avm_string("id"), idv);
                                ok = ok && avm_map_set_sorted(out, avm_string("index"), avm_int(i));
                                ok = ok && avm_map_set_sorted(out, avm_string("deadline_ns"), dv);
                                if (!ok) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                                if (vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                                return ret;
                            }
                            if (d < nearest_timer_ns) nearest_timer_ns = d;
                            continue;
                        }
                        if (strcmp(kind, "ui") == 0 || strcmp(kind, "gfx") == 0 || strcmp(kind, "input") == 0) {
                            AvmGfxInputQueue* q = vm ? (AvmGfxInputQueue*)vm->gfx_input_queue : NULL;
                            if (q && q->count > 0 && q->entries) {
                                AvmGfxInputEntry entry = q->entries[0];
                                if (!avm_io_charge(vm, (uint64_t)entry.len, domain, op)) return vm->last_error;
                                AvmValue raw = avm_bytes_new((int)entry.len);
                                if (raw.type != AVM_VAL_BYTES || !raw.as.b) { avm_abort(vm, raw); return raw; }
                                if (entry.len > 0 && entry.data) memcpy(raw.as.b->data, entry.data, entry.len);
                                if (entry.data) free(entry.data);
                                if (q->count > 1u) memmove(q->entries, q->entries + 1, sizeof(AvmGfxInputEntry) * (size_t)(q->count - 1u));
                                q->count--;
                                if (q->entries) { q->entries[q->count].data = NULL; q->entries[q->count].len = 0; }
                                AvmMap* out = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                                if (!out) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                memset(out, 0, sizeof(*out));
                                AvmValue idv;
                                if (!avm_map_get_key(wv, "id", &idv)) idv = avm_int(i);
                                int ok = 1;
                                ok = ok && avm_map_set_sorted(out, avm_string("kind"), avm_string("ui"));
                                ok = ok && avm_map_set_sorted(out, avm_string("id"), idv);
                                ok = ok && avm_map_set_sorted(out, avm_string("index"), avm_int(i));
                                ok = ok && avm_map_set_sorted(out, avm_string("raw"), raw);
                                if (!ok) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                                if (vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                                return ret;
                            }
                            continue;
                        }
                        if (strcmp(kind, "net") == 0 || strcmp(kind, "vnet") == 0) {
                            AvmValue sidv;
                            if (!avm_map_get_key(wv, "session_id", &sidv) || sidv.type != AVM_VAL_INT) {
                                return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select net watch missing session_id", domain, op);
                            }
                            AvmValue evv;
                            uint32_t evs = 1u;
                            if (avm_map_get_key(wv, "events", &evv) && evv.type == AVM_VAL_INT) evs = (uint32_t)avm_value_u64(evv, 1);
                            if (evs == 0 || (evs & ~3u) != 0) {
                                return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select net events must use read=1/write=2", domain, op);
                            }
                            session_ids[net_count] = (uint32_t)avm_value_u64(sidv, 0);
                            session_events[net_count] = evs;
                            session_watch_index[net_count] = i;
                            net_count++;
                            continue;
                        }
                        if (strcmp(kind, "cancel") == 0 || strcmp(kind, "cancellation") == 0) {
                            has_cancel_watch = 1;
                            if (vm && vm->cancelled) {
                                AvmMap* out = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                                if (!out) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                memset(out, 0, sizeof(*out));
                                AvmValue idv;
                                if (!avm_map_get_key(wv, "id", &idv)) idv = avm_int(i);
                                int ok = 1;
                                ok = ok && avm_map_set_sorted(out, avm_string("kind"), avm_string("cancel"));
                                ok = ok && avm_map_set_sorted(out, avm_string("id"), idv);
                                ok = ok && avm_map_set_sorted(out, avm_string("index"), avm_int(i));
                                ok = ok && avm_map_set_sorted(out, avm_string("source"), avm_string("host"));
                                if (!ok) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                                vm->cancelled = 0;
                                vm->last_error = avm_nil();
                                AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                                if (vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                                if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                                return ret;
                            }
                            continue;
                        }
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "event.select unsupported watch kind", domain, op);
                    }

                    uint32_t wait_ms = timeout_ms;
                    if (timeout_ms > 0) {
                        if (now_ns >= deadline_ns) wait_ms = 0;
                        else {
                            uint64_t remaining_ns = deadline_ns - now_ns;
                            wait_ms = (uint32_t)(remaining_ns / 1000000ull);
                            if ((remaining_ns % 1000000ull) != 0) wait_ms++;
                        }
                    }
                    if (nearest_timer_ns != UINT64_MAX && nearest_timer_ns > now_ns) {
                        uint64_t timer_ns = nearest_timer_ns - now_ns;
                        uint32_t timer_ms = (uint32_t)(timer_ns / 1000000ull);
                        if ((timer_ns % 1000000ull) != 0) timer_ms++;
                        if (timeout_ms == 0 || timer_ms < wait_ms) wait_ms = timer_ms;
                    }
                    if (has_cancel_watch && wait_ms > 8) wait_ms = 8;

                    if (net_count > 0) {
                        size_t ready_index = 0;
                        uint32_t ready_mask = 0;
                        int got = 0;
                        if (vm && vm->net_backend_kind == 1 && vm->net_session_select_fn) {
                            if (vm->net_session_select_fn(vm->net_session_user_data, session_ids, session_events, (size_t)net_count, wait_ms, &ready_index, &ready_mask) != 0) {
                                return avm_err_domop(AVM_ERR_NOT_FOUND, "event.select vnet provider failed", domain, op);
                            }
                            if (ready_index < (size_t)net_count && (ready_mask & session_events[ready_index]) != 0) got = 1;
                        } else if (vm && vm->net_backend_kind == 1 && vm->net_session_poll_fn) {
                            for (int ni = 0; ni < net_count; ni++) {
                                uint32_t r = 0;
                                if (vm->net_session_poll_fn(vm->net_session_user_data, session_ids[ni], session_events[ni], 0, &r) != 0) {
                                    return avm_err_domop(AVM_ERR_NOT_FOUND, "event.select vnet poll failed", domain, op);
                                }
                                if ((r & session_events[ni]) != 0) {
                                    ready_index = (size_t)ni;
                                    ready_mask = r;
                                    got = 1;
                                    break;
                                }
                            }
                        }
                        if (got) {
                            int wi = session_watch_index[ready_index];
                            AvmValue wv = watches->items[wi];
                            AvmMap* out = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                            if (!out) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                            memset(out, 0, sizeof(*out));
                            AvmValue idv;
                            if (!avm_map_get_key(wv, "id", &idv)) idv = avm_int(wi);
                            int ok = 1;
                            ok = ok && avm_map_set_sorted(out, avm_string("kind"), avm_string("net"));
                            ok = ok && avm_map_set_sorted(out, avm_string("id"), idv);
                            ok = ok && avm_map_set_sorted(out, avm_string("index"), avm_int(wi));
                            ok = ok && avm_map_set_sorted(out, avm_string("session_id"), avm_int((int64_t)session_ids[ready_index]));
                            ok = ok && avm_map_set_sorted(out, avm_string("events"), avm_int((int64_t)session_events[ready_index]));
                            ok = ok && avm_map_set_sorted(out, avm_string("ready"), avm_int((int64_t)(ready_mask & session_events[ready_index])));
                            if (!ok) return avm_err_domop(AVM_ERR_BUDGET, "event.select allocation failed", domain, op);
                            AvmValue ret; ret.type = AVM_VAL_MAP; ret.as.m = out;
                            if (vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                            if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                            return ret;
                        }
                    }

                    if (timeout_ms == 0 || now_ns >= deadline_ns) {
                        AvmValue ret = avm_nil();
                        if (vm->record_log_bytes) { uint32_t rp = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &rp, domain, op, args, nargs, ret); }
                        if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                        return ret;
                    }

                    uint32_t sleep_ms = wait_ms;
                    if (sleep_ms == 0) sleep_ms = 1;
                    if (sleep_ms > 8 && (net_count == 0 || !vm || !vm->net_session_select_fn)) sleep_ms = 8;
                    if (vm->deterministic) {
                        __uint128_t add = (__uint128_t)sleep_ms * 1000000ull;
                        uint64_t add64 = (add > (__uint128_t)UINT64_MAX) ? UINT64_MAX : (uint64_t)add;
                        uint64_t prev = vm->virtual_sleep_ns;
                        vm->virtual_sleep_ns = prev + add64;
                        if (vm->virtual_sleep_ns < prev) vm->virtual_sleep_ns = UINT64_MAX;
                    } else if (net_count == 0 || !vm || !vm->net_session_select_fn) {
                        usleep((useconds_t)sleep_ms * 1000u);
                    }
                }
            }
            default: break;
        }
        return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported event domain/op", domain, op);
    }

    // Unknown/unsupported domain in bootstrap.
    return avm_err_domop(AVM_ERR_NOT_IMPLEMENTED, "unsupported capability domain/op", domain, op);
