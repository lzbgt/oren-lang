            case 0x38: { // CALL u16 u8
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                uint8_t argc = code[vm->pc++];
                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - argc;
                vm->env = avm_nil();
                vm->pc = addr;
                break;
            }
            case 0x50: { // CALL32 u32 u8
                uint32_t addr = 0;
                addr |= (uint32_t)code[vm->pc++];
                addr |= (uint32_t)code[vm->pc++] << 8;
                addr |= (uint32_t)code[vm->pc++] << 16;
                addr |= (uint32_t)code[vm->pc++] << 24;
                uint8_t argc = code[vm->pc++];
                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - argc;
                vm->env = avm_nil();
                vm->pc = (int)addr;
                break;
            }
            case 0x39: { // RET
                // Function return convention (production/rolling):
                // - Callee leaves a single return value on the stack.
                // - RET pops that value, discards the entire callee frame (args+locals+temps),
                //   then pushes the return value for the caller.
                //
                // This matches the verifier model: CALL pops nargs and pushes 1.
                if (vm->sp <= 0) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on RET"));
                    break;
                }
                AvmValue ret = vm->stack[--vm->sp];
                int callee_fp = vm->fp;

                vm->frame_count--;
                if (vm->frame_count < 0) {
                    // Returning from top-level:
                    // - task 0: halt the VM (existing behavior)
                    // - other tasks: mark task done and yield to scheduler
                    if (sched && sched->current_tid != 0) {
                        int tid = sched->current_tid;
                        AvmTask* t = &sched->tasks[tid];
                        t->done = 1;
                        t->blocked = 0;
                        t->wait_kind = 0;
                        t->has_ret = 1;
                        t->ret = ret;
                        // Preserve a minimal stack with the return value.
                        vm->sp = 0;
                        vm->stack[vm->sp++] = ret;
                        task_save_from_vm(vm, t);

                        avm_task_wake_join_waiters(sched, tid, ret);
                        if (t->detached) {
                            free(t->frames);
                            free(t->stack);
                            t->frames = NULL;
                            t->stack = NULL;
                            t->used = 0;
                        }

                        int next = -1;
                        if (sched_ready_pop(sched, &next)) {
                            sched_switch(vm, sched, next);
                            continue;
                        }
                        // No runnable tasks: resume main.
                        sched_switch(vm, sched, 0);
                        continue;
                    }

                    vm->sp = 0;
                    vm->stack[vm->sp++] = ret;
                    vm->running = 0;
                    break;
                }

                // Discard callee frame contents and present return value to caller.
                vm->sp = callee_fp;
                vm->stack[vm->sp++] = ret;

                vm->pc = vm->frames[vm->frame_count].return_pc;
                vm->fp = vm->frames[vm->frame_count].fp;
                vm->env = vm->frames[vm->frame_count].env;
                break;
            }
            case 0x3C: { // PUSH_FUNC u16
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                AvmValue fv = avm_func_new(vm, (uint32_t)addr, avm_nil());
                if (avm_is_err_val(fv)) { avm_abort(vm, fv); break; }
                vm->stack[vm->sp++] = fv;
                break;
            }
            case 0x51: { // PUSH_FUNC32 u32
                uint32_t addr = 0;
                addr |= (uint32_t)code[vm->pc++];
                addr |= (uint32_t)code[vm->pc++] << 8;
                addr |= (uint32_t)code[vm->pc++] << 16;
                addr |= (uint32_t)code[vm->pc++] << 24;
                AvmValue fv = avm_func_new(vm, addr, avm_nil());
                if (avm_is_err_val(fv)) { avm_abort(vm, fv); break; }
                vm->stack[vm->sp++] = fv;
                break;
            }
            case 0x3D: { // CALL_INDIRECT u8
                uint8_t argc = code[vm->pc++];
                if (vm->sp < (int)argc + 1) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CALL_INDIRECT"));
                    break;
                }
                int fn_idx = vm->sp - (int)argc - 1;
                AvmValue fv = vm->stack[fn_idx];
                if (fv.type != AVM_VAL_FUNC || !fv.as.fn) {
                    char msg[160];
                    snprintf(msg, sizeof(msg),
                        "CALL_INDIRECT expects function value (pc=%d argc=%u got=%s)",
                        op_pc, (unsigned)argc, avm_val_type_short(fv));
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, msg));
                    break;
                }
                uint32_t addr = fv.as.fn->addr;
                AvmValue callee_env = fv.as.fn->env;

                // Remove fn value from the stack by shifting args down over it.
                for (int i = fn_idx; i < vm->sp - 1; i++) {
                    vm->stack[i] = vm->stack[i + 1];
                }
                vm->sp -= 1;

                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - (int)argc;
                vm->env = callee_env;
                vm->pc = (int)addr;
                break;
            }
            case 0x44: { // CALL_INDIRECT_SPREAD u8_fixed
                uint8_t fixed = code[vm->pc++];
                if (vm->sp < (int)fixed + 2) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CALL_INDIRECT_SPREAD"));
                    break;
                }
                int fn_idx = vm->sp - (int)fixed - 2;
                AvmValue fv = vm->stack[fn_idx];
                if (fv.type != AVM_VAL_FUNC || !fv.as.fn) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD expects function value"));
                    break;
                }
                AvmValue spread = vm->stack[vm->sp - 1];
                if (spread.type != AVM_VAL_LIST || !spread.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD expects list as spread arg"));
                    break;
                }
                uint32_t addr = fv.as.fn->addr;
                AvmValue callee_env = fv.as.fn->env;

                AvmList* sl = spread.as.l;
                if ((int)fixed + sl->count > 255) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD argc too large"));
                    break;
                }

                // Pop spread list value.
                vm->sp -= 1;

                // Remove fn value by shifting fixed args down over it.
                for (int i = fn_idx; i < vm->sp - 1; i++) {
                    vm->stack[i] = vm->stack[i + 1];
                }
                vm->sp -= 1;

                // Append spread items to stack as additional args.
                if (vm->sp + sl->count > (int)AVM_STACK_SIZE) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "stack overflow on CALL_INDIRECT_SPREAD"));
                    break;
                }
                for (int i = 0; i < sl->count; i++) {
                    vm->stack[vm->sp++] = sl->items[i];
                }

                uint8_t argc = (uint8_t)((int)fixed + sl->count);
                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - (int)argc;
                vm->env = callee_env;
                vm->pc = (int)addr;
                break;
            }
            case AVM_OP_SPAWN_CALL_LIST: { // SPAWN_CALL_LIST
                // stack: [... fn args_list] -> [... handle_int]
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SPAWN_CALL_LIST")); break; }
                AvmValue args_list = vm->stack[--vm->sp];
                AvmValue fnv = vm->stack[--vm->sp];
                int tid = sched_new_task(vm, sched, fnv, args_list);
                if (tid < 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "spawn failed")); break; }
                // Public handle is tid+1 so 0 can represent nil/invalid.
                vm->stack[vm->sp++] = avm_int((int64_t)(tid + 1));
                break;
            }
            case 0x54: { // SPAWN_CALL_SPREAD u16_fixed
                // stack: [... fn fixed_args spread_list] -> [... handle_int]
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->pc + 2 > vm->prog->code_len) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "truncated SPAWN_CALL_SPREAD")); break; }
                uint16_t fixed = code[vm->pc++];
                fixed |= (uint16_t)code[vm->pc++] << 8;
                if (vm->sp < (int)fixed + 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SPAWN_CALL_SPREAD")); break; }
                int fn_idx = vm->sp - (int)fixed - 2;
                AvmValue fnv = vm->stack[fn_idx];
                if (fnv.type != AVM_VAL_FUNC || !fnv.as.fn) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SPAWN_CALL_SPREAD expects function value")); break; }
                AvmValue spread = vm->stack[vm->sp - 1];
                if (spread.type != AVM_VAL_LIST || !spread.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SPAWN_CALL_SPREAD expects list as spread arg")); break; }
                AvmList* sl = spread.as.l;
                int total = (int)fixed + sl->count;
                if (sl->count < 0 || total < 0 || total > (int)AVM_STACK_SIZE) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SPAWN_CALL_SPREAD argc too large"));
                    break;
                }

                // Build args_list = [fixed_args..., spread_items...].
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                list->count = total; list->capacity = total; list->all_int = 1;
                list->items = NULL;
                if (total > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)total, AVM_ALLOC_KIND_LIST);
                    if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    for (int i = 0; i < (int)fixed; i++) {
                        list->items[i] = vm->stack[fn_idx + 1 + i];
                        if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
                    }
                    for (int i = 0; i < sl->count; i++) {
                        list->items[(int)fixed + i] = sl->items[i];
                        if (list->all_int && list->items[(int)fixed + i].type != AVM_VAL_INT) list->all_int = 0;
                    }
                }
                AvmValue args_list;
                args_list.type = AVM_VAL_LIST;
                args_list.as.l = list;

                // Pop operands.
                vm->sp = fn_idx;

                int tid = sched_new_task(vm, sched, fnv, args_list);
                if (tid < 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "spawn failed")); break; }
                vm->stack[vm->sp++] = avm_int((int64_t)(tid + 1));
                break;
            }
            case 0x55: { // TYPE_CTOR_MAP_SPREAD u16_fixed
                // stack: [... keys_list fixed_args spread_list] -> [... map]
                if (vm->pc + 2 > vm->prog->code_len) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "truncated TYPE_CTOR_MAP_SPREAD")); break; }
                uint16_t fixed = code[vm->pc++];
                fixed |= (uint16_t)code[vm->pc++] << 8;
                if (vm->sp < (int)fixed + 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on TYPE_CTOR_MAP_SPREAD")); break; }

                AvmValue spread = vm->stack[vm->sp - 1];
                if (spread.type != AVM_VAL_LIST || !spread.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "TYPE_CTOR_MAP_SPREAD expects list as spread arg")); break; }
                AvmList* sl = spread.as.l;

                int keys_idx = vm->sp - (int)fixed - 2;
                AvmValue keys_v = vm->stack[keys_idx];
                if (keys_v.type != AVM_VAL_LIST || !keys_v.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "TYPE_CTOR_MAP_SPREAD expects keys list")); break; }
                AvmList* kl = keys_v.as.l;
                int nkeys = kl->count;
                if (nkeys < 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "TYPE_CTOR_MAP_SPREAD invalid keys list")); break; }
                if ((int)fixed > nkeys) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "TYPE_CTOR_MAP_SPREAD fixed args > fields")); break; }
                int expected_spread = nkeys - (int)fixed;
                if (sl->count != expected_spread) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "TYPE_CTOR_MAP_SPREAD arity mismatch")); break; }

                AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                if (!map) { avm_abort(vm, avm_alloc_fail_value()); break; }
                map->count = 0;
                map->capacity = (nkeys > 0) ? nkeys * 2 : 8;
                map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                if (!map->keys || !map->values) {
                    if (map->keys) avm_heap_free(map->keys);
                    if (map->values) avm_heap_free(map->values);
                    avm_heap_free(map);
                    avm_abort(vm, avm_alloc_fail_value());
                    break;
                }

                for (int i = 0; i < nkeys; i++) {
                    AvmValue key = kl->items[i];
                    AvmValue val = avm_nil();
                    if (i < (int)fixed) {
                        val = vm->stack[keys_idx + 1 + i];
                    } else {
                        val = sl->items[i - (int)fixed];
                    }
                    if (!avm_map_key_supported(key)) {
                        avm_abort(vm, avm_err_map_key_unsupported_at(vm, key, "TYPE_CTOR_MAP_SPREAD"));
                        break;
                    }
                    if (!avm_map_set_sorted(map, key, val)) {
                        avm_abort(vm, avm_alloc_fail_value());
                        break;
                    }
                }

                // Pop operands and push result.
                vm->sp = keys_idx;
                AvmValue res;
                res.type = AVM_VAL_MAP;
                res.as.m = map;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x56: { // NEW_LIST_SPREAD u16_fixed
                // stack: [... fixed_values spread_list] -> [... list]
                if (vm->pc + 2 > vm->prog->code_len) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "truncated NEW_LIST_SPREAD")); break; }
                uint16_t fixed = code[vm->pc++];
                fixed |= (uint16_t)code[vm->pc++] << 8;
                if (vm->sp < (int)fixed + 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on NEW_LIST_SPREAD")); break; }
                AvmValue spread = vm->stack[vm->sp - 1];
                int spread_count = -1;
                if (spread.type == AVM_VAL_LIST && spread.as.l) spread_count = spread.as.l->count;
                else if (spread.type == AVM_VAL_LIST_INT && spread.as.li) spread_count = spread.as.li->count;
                if (spread_count < 0) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "NEW_LIST_SPREAD expects list as spread arg"));
                    break;
                }
                int total = (int)fixed + spread_count;
                if (total < 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "NEW_LIST_SPREAD invalid count")); break; }

                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                list->count = total;
                list->capacity = total;
                list->all_int = 1;
                list->items = NULL;
                if (total > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)total, AVM_ALLOC_KIND_LIST);
                    if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    int base = vm->sp - (int)fixed - 1;
                    for (int i = 0; i < (int)fixed; i++) {
                        list->items[i] = vm->stack[base + i];
                        if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
                    }
                    if (spread.type == AVM_VAL_LIST) {
                        AvmList* sl = spread.as.l;
                        for (int i = 0; i < spread_count; i++) {
                            list->items[(int)fixed + i] = sl->items[i];
                            if (list->all_int && list->items[(int)fixed + i].type != AVM_VAL_INT) list->all_int = 0;
                        }
                    } else {
                        AvmListInt* sl = spread.as.li;
                        for (int i = 0; i < spread_count; i++) {
                            list->items[(int)fixed + i] = avm_int(sl->items[i]);
                        }
                    }
                }

                vm->sp -= (int)fixed + 1;
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
