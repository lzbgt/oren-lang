    // Domain 1: FS (filesystem). Map op -> legacy ids for now.
    // This is a rolling ABI: domain/op tables may evolve quickly.
    if (domain == 1) {
        int is_write = (op == 1 || op == 2 || op == 6 || op == 7) ? 1 : 0;
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
                    if (!e) {
                        char msg[256];
                        snprintf(msg, sizeof(msg), "vfs: file not found: %s (entries=%u)", path ? path : "", v ? (unsigned)v->count : 0u);
                        return avm_err_domop(AVM_ERR_NOT_FOUND, msg, domain, op);
                    }
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
                    if (nargs < 2) return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: write_bytes expects (path, bytes|list)", domain, op);
                    uint32_t len = 0;
                    if (args[1].type == AVM_VAL_BYTES && args[1].as.b) {
                        len = (uint32_t)(args[1].as.b->len < 0 ? 0 : args[1].as.b->len);
                    } else if (args[1].type == AVM_VAL_LIST && args[1].as.l) {
                        len = (uint32_t)(args[1].as.l->count < 0 ? 0 : args[1].as.l->count);
                    } else {
                        return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: write_bytes expects (path, bytes|list)", domain, op);
                    }
                    // Preflight record log capacity, similar to host write_bytes: need 81
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)len, (int)domain, (int)op)) return vm->last_error;
                    int ok = 0;
                    if (args[1].type == AVM_VAL_BYTES) {
                        AvmBytes* b = args[1].as.b;
                        ok = avm_vfs_put(vm, path ? path : "", b ? b->data : NULL, len);
                    } else {
                        ok = avm_vfs_put_list(vm, path ? path : "", args[1].as.l);
                    }
                    if (!ok) {
                        AvmValue err = avm_alloc_fail_value();
                        avm_abort(vm, err);
                        return err;
                    }
                    AvmValue ret = avm_nil();
                    if (vm->record_log_bytes) { uint32_t p = (uint32_t)vm->record_log_bytes->len; (void)rr_write_entry_mem(vm, vm->record_log_bytes, &p, domain, op, args, nargs, ret); }
                    if (vm->record_log) (void)rr_write_entry(vm, vm->record_log, domain, op, args, nargs, ret);
                    return ret;
                }
                case 7: { // append_file -> NIL
                    if (nargs < 2 || args[1].type != AVM_VAL_STRING) return avm_err_domop(AVM_ERR_INVALID_ARG, "vfs: append_file expects (path, string)", domain, op);
                    const char* s = (const char*)args[1].as.p;
                    uint32_t len = (uint32_t)strlen(s ? s : "");
                    if (vm && vm->log_budget_bytes > 0 && (vm->record_log || vm->record_log_bytes)) {
                        if (!avm_log_can_fit(vm, 81ull)) {
                            AvmValue err = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", (int)domain, (int)op);
                            avm_abort(vm, err);
                            return err;
                        }
                    }
                    if (!avm_io_charge(vm, (uint64_t)len, (int)domain, (int)op)) return vm->last_error;
                    if (!avm_vfs_append(vm, path ? path : "", (const uint8_t*)s, len)) {
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
                    if (!e) {
                        char msg[256];
                        snprintf(msg, sizeof(msg), "vfs: file not found: %s (entries=%u)", path ? path : "", v ? (unsigned)v->count : 0u);
                        return avm_err_domop(AVM_ERR_NOT_FOUND, msg, domain, op);
                    }
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
                    out->all_int = 0;
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
            case 7: { // append_file
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
                AvmValue ret = avm_call_native(vm, 229, use_args, nargs);
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
                    out->all_int = 0;
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
