#include "avm_internal.h"

#include <stdlib.h>
#include <string.h>

const char* avm_op_name(uint8_t op) {
    switch (op) {
        case 0x00: return "NOP";
        case 0x01: return "HALT";
        case 0x02: return "PUSH_CONST";
        case 0x03: return "POP";
        case 0x04: return "LOAD_LOCAL";
        case 0x05: return "STORE_LOCAL";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x12: return "LT";
        case 0x13: return "EQ";
        case 0x14: return "NEQ";
        case 0x15: return "GT";
        case 0x16: return "LE";
        case 0x17: return "GE";
        case 0x18: return "AND";
        case 0x19: return "OR";
        case 0x1A: return "XOR";
        case 0x1B: return "SHL";
        case 0x1C: return "SHR";
        case 0x20: return "PRINT";
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x38: return "CALL";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x40: return "NEW_LIST";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x43: return "SET_INDEX";
        default: return "OP?";
    }
}

uint32_t avm_gas_cost(uint8_t op) {
    (void)op;
    // Bootstrap rule: every opcode costs 1 gas.
    return 1u;
}

void avm_abort(AvmVM* vm, AvmValue err) {
    vm->last_error = err;
    vm->exit_code = 1;
    vm->running = 0;
}

AvmVM* avm_new() {
    AvmVM* vm = (AvmVM*)malloc(sizeof(AvmVM));
    vm->stack = (AvmValue*)malloc(sizeof(AvmValue) * AVM_STACK_SIZE);
    vm->sp = 0;
    vm->pc = 0;
    vm->running = 0;
    vm->prog = NULL;
    vm->fp = 0;
    vm->frame_count = 0;
    vm->allowed_native_domains = 0;
    vm->fs_allow_prefixes = NULL;
    vm->fs_allow_prefix_count = 0;
    vm->fs_backend_kind = 0;
    vm->vfs = NULL;
    vm->proc_backend_kind = 0;
    vm->vproc = NULL;
    vm->proc_exit_code = 0;
    vm->net_backend_kind = 0;
    vm->vnet = NULL;
    vm->gas_remaining = 0;
    vm->deadline_ns = 0;
    vm->cancelled = 0;
    vm->heap_budget_bytes = 0;
    vm->heap_used_bytes = 0;
    vm->heap_allocs_head = NULL;
    vm->io_budget_bytes = 0;
    vm->io_used_bytes = 0;
    vm->log_budget_bytes = 0;
    vm->log_used_bytes = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->exit_code = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    vm->record_log = NULL;
    vm->replay_log = NULL;
    vm->record_log_bytes = NULL;
    vm->replay_log_bytes = NULL;
    vm->replay_log_pos = 0;
    vm->deterministic = 0;
    vm->virtual_now_ns = 0;
    vm->virtual_step_ns = 1000ull; // 1us per executed instruction step (default; override with AVM_TIME_STEP_NS)
    vm->virtual_sleep_ns = 0;
    vm->rng_state = 0x123456789abcdef0ull;
    vm->gas_executed = 0;
    vm->alloc_next_id = 1;
    vm->pause_after_steps = 0;
    vm->paused = 0;
    vm->trace_enabled = 0;
    vm->trace_limit = 0;
    vm->trace_out = NULL;
    vm->trace_hash_enabled = 0;
    vm->trace_hash_limit = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_bytes_enabled = 0;
    vm->trace_bytes_limit = 0;
    vm->trace_budget_bytes = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
    vm->break_pcs = NULL;
    vm->break_pc_count = 0;
    for (int i = 0; i < MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (!vm) return;

    // Close any open replay/record files (CLI can also close; best-effort here).
    if (vm->record_log) fclose(vm->record_log);
    if (vm->replay_log) fclose(vm->replay_log);

    // Best-effort: release heap objects reachable from VM roots (including const pool objects).
    avm_release_heap_all(vm);
    // Release any remaining unreachable heap allocations (leak-free teardown).
    avm_release_unreachable_allocs(vm);

    if (vm->stack) free(vm->stack);
    if (vm->break_pcs) free(vm->break_pcs);
    if (vm->fs_allow_prefixes) {
        for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
            if (vm->fs_allow_prefixes[i]) free(vm->fs_allow_prefixes[i]);
        }
        free(vm->fs_allow_prefixes);
    }
    free(vm);
}

void avm_load(AvmVM* vm, AvmProgram* prog) {
    vm->prog = prog;
    vm->pc = 0;
    vm->sp = 0;
    vm->fp = 0;
    vm->frame_count = 0;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value = avm_nil();
    vm->last_error = avm_nil();
    vm->exit_code = 0;
    vm->virtual_sleep_ns = 0;
    vm->gas_executed = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
}

void avm_run(AvmVM* vm) {
    if (!vm || !vm->prog) return;

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(vm, &prev_owner);

    vm->running = 1;
    vm->exit_code = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    uint8_t* code = vm->prog->code;
    uint64_t steps = 0;

    while (vm->running && vm->pc < vm->prog->code_len) {
        steps++;
        if (vm->break_pc_count > 0 && vm->break_pcs) {
            for (int bi = 0; bi < vm->break_pc_count; bi++) {
                if (vm->pc == vm->break_pcs[bi]) {
                    vm->paused = 1;
                    vm->exit_code = 2; // paused (non-error)
                    vm->running = 0;
                    break;
                }
            }
            if (!vm->running) break;
        }
        if (vm->pause_after_steps > 0) {
            vm->pause_after_steps--;
            if (vm->pause_after_steps == 0) {
                vm->paused = 1;
                vm->exit_code = 2; // paused (non-error)
                vm->running = 0;
                break;
            }
        }
        if (vm->cancelled) {
            avm_abort(vm, avm_err(AVM_ERR_CANCELLED, "cancelled"));
            break;
        }
        if (vm->deadline_ns > 0 && ((steps & 1023ull) == 0)) {
            uint64_t now = avm_now_ns();
            if (now != 0 && now > vm->deadline_ns) {
                avm_abort(vm, avm_err(AVM_ERR_TIMEOUT, "deadline exceeded"));
                break;
            }
        }

        int op_pc = vm->pc;
        uint8_t op = code[vm->pc];
        uint32_t cost = avm_gas_cost(op);
        if (cost == 0) cost = 1u;

        // Charge gas budget using the semantic cost model.
        if (vm->gas_remaining > 0) {
            if (vm->gas_remaining < (uint64_t)cost) {
                avm_abort(vm, avm_err(AVM_ERR_BUDGET, "budget exceeded (gas)"));
                break;
            }
            vm->gas_remaining -= (uint64_t)cost;
            if (vm->gas_remaining == 0) {
                avm_abort(vm, avm_err(AVM_ERR_BUDGET, "budget exceeded (gas)"));
                break;
            }
        }

        // Semantic execution counter for deterministic TIME (bootstrap: 1 gas per opcode dispatch).
        vm->gas_executed += (uint64_t)cost;
        vm->pc++;

        // Tracing is best-effort and must never affect program semantics.
        (void)trace_emit_step(vm, op_pc, op);
        if (vm->trace_enabled && (!vm->trace_limit || vm->gas_executed <= vm->trace_limit)) {
            FILE* out = vm->trace_out ? vm->trace_out : stderr;
            fprintf(out, "TRACE pc=%d op=0x%02x %s sp=%d fp=%d depth=%d gas=%llu\n",
                op_pc,
                (unsigned)op,
                avm_op_name(op),
                vm->sp,
                vm->fp,
                vm->frame_count,
                (unsigned long long)vm->gas_executed);
        }

        switch (op) {
            case 0x00: // NOP
                break;
            case 0x01: // HALT
                vm->running = 0;
                break;
            case 0x02: { // PUSH_CONST u16
                if (vm->pc + 2 > vm->prog->code_len) { vm->running = 0; break; }
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < vm->prog->const_count) {
                    vm->stack[vm->sp++] = vm->prog->constants[idx];
                }
                break;
            }
            case 0x03: // POP
                if (vm->sp > 0) vm->sp--;
                break;
            case 0x04: { // LOAD_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->sp++] = vm->stack[vm->fp + idx];
                break;
            }
            case 0x05: { // STORE_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->fp + idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x06: { // LOAD_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->stack[vm->sp++] = vm->globals[idx];
                break;
            }
            case 0x07: { // STORE_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->globals[idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x10: { // ADD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT;
                    res.as.i = a.as.i + b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x11: { // SUB
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT;
                    res.as.i = a.as.i - b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x12: { // LT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(a.as.i < b.as.i);
                }
                break;
            }
            case 0x13: { // EQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    int eq = 0;
                    if (a.type == b.type) {
                        if (a.type == AVM_VAL_NIL) eq = 1;
                        else if (a.type == AVM_VAL_INT || a.type == AVM_VAL_BOOL) eq = (a.as.i == b.as.i);
                        else if (a.type == AVM_VAL_FLOAT) eq = (a.as.f == b.as.f);
                        else if (a.type == AVM_VAL_STRING) eq = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                        else eq = (a.as.p == b.as.p);
                    }
                    vm->stack[vm->sp++] = avm_bool(eq);
                }
                break;
            }
            case 0x14: { // NEQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    int eq = 0;
                    if (a.type == b.type) {
                        if (a.type == AVM_VAL_NIL) eq = 1;
                        else if (a.type == AVM_VAL_INT || a.type == AVM_VAL_BOOL) eq = (a.as.i == b.as.i);
                        else if (a.type == AVM_VAL_FLOAT) eq = (a.as.f == b.as.f);
                        else if (a.type == AVM_VAL_STRING) eq = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                        else eq = (a.as.p == b.as.p);
                    }
                    vm->stack[vm->sp++] = avm_bool(!eq);
                }
                break;
            }
            case 0x15: { // GT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(a.as.i > b.as.i);
                }
                break;
            }
            case 0x16: { // LE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(a.as.i <= b.as.i);
                }
                break;
            }
            case 0x17: { // GE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(a.as.i >= b.as.i);
                }
                break;
            }
            case 0x18: { // AND
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_int(a.as.i & b.as.i);
                }
                break;
            }
            case 0x19: { // OR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_int(a.as.i | b.as.i);
                }
                break;
            }
            case 0x1A: { // XOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_int(a.as.i ^ b.as.i);
                }
                break;
            }
            case 0x1B: { // SHL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_int(a.as.i << b.as.i);
                }
                break;
            }
            case 0x1C: { // SHR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_int((uint64_t)a.as.i >> (uint64_t)b.as.i);
                }
                break;
            }
            case 0x20: { // PRINT
                if (vm->sp > 0) {
                    AvmValue v = vm->stack[--vm->sp];
                    if (v.type == AVM_VAL_INT) printf("%lld\n", (long long)v.as.i);
                    else if (v.type == AVM_VAL_FLOAT) printf("%f\n", v.as.f);
                    else if (v.type == AVM_VAL_STRING) printf("%s\n", (char*)v.as.p);
                    else if (v.type == AVM_VAL_BOOL) printf("%s\n", v.as.i ? "true" : "false");
                    else printf("nil\n");
                }
                break;
            }
            case 0x30: { // JMP i16
                int16_t off = 0;
                off |= (int16_t)code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                vm->pc = (int)(vm->pc + off);
                break;
            }
            case 0x31: { // JMP_IF i16
                int16_t off = 0;
                off |= (int16_t)code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                AvmValue cond = vm->stack[--vm->sp];
                int truthy = 0;
                if (cond.type == AVM_VAL_BOOL) truthy = cond.as.i != 0;
                else if (cond.type == AVM_VAL_INT) truthy = cond.as.i != 0;
                else if (cond.type == AVM_VAL_NIL) truthy = 0;
                else truthy = 1;
                if (truthy) vm->pc = (int)(vm->pc + off);
                break;
            }
            case 0x38: { // CALL u16 u8
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                uint8_t argc = code[vm->pc++];
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frame_count++;
                vm->fp = vm->sp - argc;
                vm->pc = addr;
                break;
            }
            case 0x39: { // RET
                vm->frame_count--;
                if (vm->frame_count < 0) {
                    vm->running = 0;
                } else {
                    vm->pc = vm->frames[vm->frame_count].return_pc;
                    vm->fp = vm->frames[vm->frame_count].fp;
                }
                break;
            }
            case 0x3A: { // CALL_NATIVE u16 u8 (legacy mapping)
                uint16_t id = code[vm->pc++];
                id |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                uint8_t domain = 0;
                uint16_t op2 = 0;
                avm_legacy_native_to_domop(id, &domain, &op2);
                AvmValue* args = (nargs > 0) ? &vm->stack[vm->sp - nargs] : NULL;
                (void)trace_emit_native2(vm, op_pc, domain, op2, nargs);
                AvmValue res = avm_call_native2(vm, domain, op2, args, nargs);
                vm->sp -= nargs;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x3B: { // CALL_NATIVE2 u8 u16 u8
                uint8_t domain = code[vm->pc++];
                uint16_t op2 = code[vm->pc++];
                op2 |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                AvmValue* args = (nargs > 0) ? &vm->stack[vm->sp - nargs] : NULL;
                (void)trace_emit_native2(vm, op_pc, domain, op2, nargs);
                AvmValue res = avm_call_native2(vm, domain, op2, args, nargs);
                vm->sp -= nargs;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x40: { // NEW_LIST u16
                uint16_t len = code[vm->pc++];
                len |= (uint16_t)code[vm->pc++] << 8;
                if (vm->sp < (int)len) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow"));
                    break;
                }
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                list->count = (int)len;
                list->capacity = (int)len;
                list->items = NULL;
                if (len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)list->capacity, AVM_ALLOC_KIND_LIST);
                    if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    // NEW_LIST consumes `len` values from the stack, preserving push order:
                    // the last pushed value becomes the last element in the list.
                    for (int i = (int)len - 1; i >= 0; i--) {
                        list->items[i] = vm->stack[--vm->sp];
                    }
                }
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x41: { // NEW_MAP u16
                uint16_t pairs = code[vm->pc++];
                pairs |= (uint16_t)code[vm->pc++] << 8;
                AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                if (!map) { avm_abort(vm, avm_alloc_fail_value()); break; }
                map->count = 0;
                map->capacity = (pairs > 0) ? pairs * 2 : 8;
                map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                if (!map->keys || !map->values) {
                    if (map->keys) avm_heap_free(map->keys);
                    if (map->values) avm_heap_free(map->values);
                    avm_heap_free(map);
                    avm_abort(vm, avm_alloc_fail_value());
                    break;
                }
                for (uint16_t i = 0; i < pairs; i++) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    if (!avm_map_key_supported(key)) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                        break;
                    }
                    if (!avm_map_set_sorted(map, key, val)) {
                        avm_abort(vm, avm_alloc_fail_value());
                        break;
                    }
                }
                AvmValue res;
                res.type = AVM_VAL_MAP;
                res.as.m = map;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x42: { // GET_INDEX
                if (vm->sp >= 2) {
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    AvmValue res = avm_nil();

                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            res = obj.as.l->items[i];
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                            break;
                        }
                        int found = 0;
                        int idx = avm_map_find_index(obj.as.m, key, &found);
                        if (found) {
                            res = obj.as.m->values[idx];
                        }
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x43: { // SET_INDEX
                if (vm->sp >= 3) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];

                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            obj.as.l->items[i] = val;
                        } else if (i == obj.as.l->count) {
                            if (!avm_list_ensure_cap(obj.as.l, obj.as.l->count + 1)) {
                                avm_abort(vm, avm_alloc_fail_value());
                                break;
                            }
                            obj.as.l->items[obj.as.l->count++] = val;
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                            break;
                        }
                        if (!avm_map_set_sorted(obj.as.m, key, val)) {
                            avm_abort(vm, avm_alloc_fail_value());
                            break;
                        }
                    }
                }
                break;
            }
            default:
                avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "unknown opcode"));
                break;
        }
    }

    if (vm->trace_hash_enabled && vm->trace_hash_started && !vm->trace_hash_finalized) {
        avm_sha256_final(&vm->trace_hash_ctx, vm->trace_hash_out);
        vm->trace_hash_finalized = 1;
    }

    avm_alloc_owner_pop(prev_owner);
}
