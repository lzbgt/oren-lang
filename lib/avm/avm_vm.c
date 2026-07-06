#include "avm_internal.h"
#include "avm_int_math.h"
#include "avm_ops_loops.h"
#include "avm_vm_list_ops.h"
#include "avm_vm_sched.h"
#include "avm_vm_values.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "avm_vm_helpers.inc"

void avm_run(AvmVM* vm) {
    if (!vm || !vm->prog) return;

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(vm, &prev_owner);

    AvmSched* sched = avm_sched_get(vm);

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
        if (vm->trace_hash_enabled || vm->trace_bytes_enabled) {
            (void)trace_emit_step(vm, op_pc, op);
        }
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
                // HALT ends the current task. Task 0 halts the VM; other tasks complete normally.
                if (sched && sched->current_tid != 0) {
                    int tid = sched->current_tid;
                    AvmTask* t = &sched->tasks[tid];
                    t->done = 1;
                    t->blocked = 0;
                    t->wait_kind = 0;
                    t->has_ret = 1;
                    t->ret = (vm->sp > 0) ? vm->stack[vm->sp - 1] : avm_nil();
                    task_save_from_vm(vm, t);

                    avm_task_wake_join_waiters(sched, tid, t->ret);
                    if (t->detached) {
                        free(t->frames);
                        free(t->stack);
                        t->frames = NULL;
                        t->stack = NULL;
                        t->used = 0;
                    }

                    // Switch to next runnable task.
                    int next = -1;
                    if (sched_ready_pop(sched, &next)) {
                        sched_switch(vm, sched, next);
                        continue;
                    }
                    // No runnable tasks: if main task is still running, resume it; else stop.
                    sched_switch(vm, sched, 0);
                    continue;
                }
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
            case 0x52: { // LOAD_LOCAL16 u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                int pos = vm->fp + (int)idx;
                if (pos < 0 || pos >= (int)AVM_STACK_SIZE) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_LOCAL16 out of range"));
                    break;
                }
                vm->stack[vm->sp++] = vm->stack[pos];
                break;
            }
            case 0x53: { // STORE_LOCAL16 u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                int pos = vm->fp + (int)idx;
                if (pos < 0 || pos >= (int)AVM_STACK_SIZE) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "STORE_LOCAL16 out of range"));
                    break;
                }
                vm->stack[pos] = vm->stack[--vm->sp];
                break;
            }
            case 0x06: { // LOAD_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx >= MAX_GLOBALS) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_GLOBAL out of range"));
                    break;
                }
                vm->stack[vm->sp++] = vm->globals[idx];
                break;
            }
            case 0x07: { // STORE_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx >= MAX_GLOBALS) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "STORE_GLOBAL out of range"));
                    break;
                }
                vm->globals[idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x10: { // ADD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_add_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i + b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) {
                        const char* sa = a.as.p ? (const char*)a.as.p : "";
                        const char* sb = b.as.p ? (const char*)b.as.p : "";
                        size_t la = strlen(sa);
                        size_t lb = strlen(sb);
                        char* s = (char*)avm_heap_malloc_k(la + lb + 1, AVM_ALLOC_KIND_STRING);
                        if (!s) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); vm->stack[vm->sp++] = e; break; }
                        memcpy(s, sa, la);
                        memcpy(s + la, sb, lb);
                        s[la + lb] = 0;
                        AvmValue r; r.type = AVM_VAL_STRING; r.as.p = s; vm->stack[vm->sp++] = r;
                    } else if ((a.type == AVM_VAL_LIST || a.type == AVM_VAL_LIST_INT) &&
                               (b.type == AVM_VAL_LIST || b.type == AVM_VAL_LIST_INT)) {
                        AvmValue r = avm_concat_list_values(a, b);
                        if (avm_is_err_val(r)) { avm_abort(vm, r); break; }
                        vm->stack[vm->sp++] = r;
                    } else {
                        // Rolling behavior: type mismatch yields nil (avoid host crash).
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x11: { // SUB
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_sub_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f - b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i - b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f - (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1D: { // MUL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_mul_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i * b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1E: { // DIV
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        if (b.as.i == 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "division by zero"));
                            break;
                        }
                        // INT64_MIN / -1 overflows in two's complement; define as an error.
                        if (avm_i64_is_min(a.as.i) && b.as.i == -1) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "division overflow (i64_min / -1)"));
                            break;
                        }
                        vm->stack[vm->sp++] = avm_int(a.as.i / b.as.i);
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f / b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i / b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f / (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1F: { // MOD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        if (b.as.i == 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo by zero"));
                            break;
                        }
                        // INT64_MIN % -1 is invalid because it implies INT64_MIN / -1 overflow.
                        if (avm_i64_is_min(a.as.i) && b.as.i == -1) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo overflow (i64_min % -1)"));
                            break;
                        }
                        vm->stack[vm->sp++] = avm_int(a.as.i % b.as.i);
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x12: { // LT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i < b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f < b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i < b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f < (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) < 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x13: { // EQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(avm_value_equal_depth(a, b, 0));
                }
                break;
            }
            case 0x14: { // NEQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    vm->stack[vm->sp++] = avm_bool(!avm_value_equal_depth(a, b, 0));
                }
                break;
            }
            case 0x15: { // GT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i > b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f > b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i > b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f > (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) > 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x16: { // LE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i <= b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f <= b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i <= b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f <= (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) <= 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x17: { // GE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i >= b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f >= b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i >= b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f >= (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) >= 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x18: { // AND
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i & b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x19: { // OR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i | b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x1A: { // XOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i ^ b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x1B: { // SHL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type != AVM_VAL_INT || b.type != AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (b.as.i < 0 || b.as.i >= 64) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SHL shift count out of range (need 0..63)"));
                        break;
                    }
                    uint64_t ua = avm_u64_bits_i64(a.as.i);
                    uint64_t ur = ua << (uint64_t)b.as.i;
                    vm->stack[vm->sp++] = avm_int(avm_i64_from_u64_bits(ur));
                }
                break;
            }
            case 0x1C: { // SHR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type != AVM_VAL_INT || b.type != AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (b.as.i < 0 || b.as.i >= 64) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SHR shift count out of range (need 0..63)"));
                        break;
                    }
                    uint64_t ua = avm_u64_bits_i64(a.as.i);
                    uint64_t ur = ua >> (uint64_t)b.as.i;
                    vm->stack[vm->sp++] = avm_int(avm_i64_from_u64_bits(ur));
                }
                break;
            }
            case 0x20: { // PRINT
                if (vm->sp > 0) {
                    AvmValue v = vm->stack[--vm->sp];
                    avm_output_value_no_nl(vm, v);
                    avm_output_text(vm, "\n", 1u);
                }
                break;
            }
            case 0x21: { // PRINT_LIST
                if (vm->sp <= 0) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on PRINT_LIST"));
                    break;
                }
                AvmValue lst = vm->stack[--vm->sp];
                if (lst.type == AVM_VAL_NIL) {
                    avm_output_text(vm, "\n", 1u);
                    break;
                }
                if (lst.type != AVM_VAL_LIST || !lst.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "PRINT_LIST expects list"));
                    break;
                }
                AvmList* l = lst.as.l;
                for (int i = 0; i < l->count; i++) {
                    avm_output_value_no_nl(vm, l->items[i]);
                    if (i < l->count - 1) avm_output_text(vm, " ", 1u);
                }
                avm_output_text(vm, "\n", 1u);
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
                if (avm_truthy(cond)) vm->pc = (int)(vm->pc + off);
                break;
            }
            case 0x4E: { // JMP32 i32
                uint32_t u = 0;
                u |= (uint32_t)code[vm->pc++];
                u |= (uint32_t)code[vm->pc++] << 8;
                u |= (uint32_t)code[vm->pc++] << 16;
                u |= (uint32_t)code[vm->pc++] << 24;
                int32_t off = 0;
                memcpy(&off, &u, sizeof(off));
                vm->pc = (int)((int64_t)vm->pc + (int64_t)off);
                break;
            }
            case 0x4F: { // JMP_IF32 i32
                uint32_t u = 0;
                u |= (uint32_t)code[vm->pc++];
                u |= (uint32_t)code[vm->pc++] << 8;
                u |= (uint32_t)code[vm->pc++] << 16;
                u |= (uint32_t)code[vm->pc++] << 24;
                int32_t off = 0;
                memcpy(&off, &u, sizeof(off));
                AvmValue cond = vm->stack[--vm->sp];
                if (avm_truthy(cond)) vm->pc = (int)((int64_t)vm->pc + (int64_t)off);
                break;
            }
            #include "avm_vm_call_spread_cases.inc"
            case AVM_OP_JOIN: { // JOIN
                // stack: [... handle] -> [... ret] (blocks if not done)
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on JOIN")); break; }
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN expects int handle")); break; }
                int tid = (int)hv.as.i - 1;
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN invalid handle"));
                    break;
                }
                if (tid == sched->current_tid) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN self")); break; }
                AvmTask* tgt = &sched->tasks[tid];
                if (tgt->detached) {
                    vm->stack[vm->sp++] = avm_nil();
                    break;
                }
                if (tgt->done) {
                    vm->stack[vm->sp++] = tgt->has_ret ? tgt->ret : avm_nil();
                    break;
                }

                // Block current task until target completes.
                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 1;
                ct->wait_id = tid;
                ct->join_deadline_ns = 0;
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_JOIN_TIMEOUT: { // JOIN_TIMEOUT
                // stack: [... handle timeout_ms] -> [... ret_or_timeout]
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on JOIN_TIMEOUT")); break; }
                AvmValue tv = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT || tv.type != AVM_VAL_INT) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT expects (int handle, int timeout_ms)"));
                    break;
                }
                int tid = (int)hv.as.i - 1;
                int64_t timeout_ms = tv.as.i;
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT invalid handle"));
                    break;
                }
                if (tid == sched->current_tid) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT self")); break; }

                AvmTask* tgt = &sched->tasks[tid];
                if (tgt->detached) {
                    vm->stack[vm->sp++] = avm_nil();
                    break;
                }
                if (tgt->done) {
                    vm->stack[vm->sp++] = tgt->has_ret ? tgt->ret : avm_nil();
                    break;
                }

                if (timeout_ms < 0) {
                    // Equivalent to JOIN (block).
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 1;
                    ct->wait_id = tid;
                    ct->join_deadline_ns = 0;
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

                if (timeout_ms == 0) {
                    // Fast-path: non-blocking join probe.
                    vm->stack[vm->sp++] = avm_int(-60); // ETIMEDOUT (BSD)
                    break;
                }

                // If there are no runnable tasks besides us, joining can never make progress; treat as timeout.
                if (sched->ready_len <= 0) {
                    vm->stack[vm->sp++] = avm_int(-60); // ETIMEDOUT (BSD)
                    break;
                }

                // Block current task with an absolute deadline in deterministic virtual time.
                uint64_t now = avm_vm_now_ns(vm);
                uint64_t dl = now + (uint64_t)timeout_ms * 1000000ull;

                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 4; // join_timeout
                ct->wait_id = tid;
                ct->join_deadline_ns = dl;
                ct->wake_pending = 0;
                ct->wake_value = avm_nil();
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    // No runnable tasks => immediate timeout (must not hang).
                    ct->blocked = 0;
                    ct->wait_kind = 0;
                    ct->join_deadline_ns = 0;
                    vm->stack[vm->sp++] = avm_int(-60);
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_DETACH: { // DETACH
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on DETACH")); break; }
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "DETACH expects int handle")); break; }
                int tid = (int)hv.as.i - 1;
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "DETACH invalid handle"));
                    break;
                }
                AvmTask* tgt = &sched->tasks[tid];
                tgt->detached = 1;
                if (tgt->done) {
                    free(tgt->frames);
                    free(tgt->stack);
                    tgt->frames = NULL;
                    tgt->stack = NULL;
                    tgt->used = 0;
                }
                break;
            }
            case AVM_OP_TASK_CANCEL_WAIT: { // TASK_CANCEL_WAIT
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 3) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INTERNAL, "stack underflow on TASK_CANCEL_WAIT");
                    break;
                }
                AvmValue reason = vm->stack[--vm->sp];
                AvmValue waitv = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT || waitv.type != AVM_VAL_INT) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "TASK_CANCEL_WAIT expects (int handle, int wait_ms, reason)");
                    break;
                }
                int tid = (int)hv.as.i - 1;
                if (tid == sched->current_tid) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "TASK_CANCEL_WAIT self");
                    break;
                }
                int transitioned = 0;
                AvmValue rv = avm_task_cancel_wait_result_or_transition(vm, sched, sched->current_tid, tid, waitv.as.i, reason, &transitioned);
                if (!transitioned) {
                    vm->stack[vm->sp++] = rv;
                    break;
                }
                task_save_from_vm(vm, &sched->tasks[sched->current_tid]);
                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_task_clear_wait_state(&sched->tasks[sched->current_tid]);
                    vm->stack[vm->sp++] = avm_task_stop_result("detached", avm_int(-60), reason, avm_nil());
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_TASK_CANCEL_AFTER_WAIT: { // TASK_CANCEL_AFTER_WAIT
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 4) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INTERNAL, "stack underflow on TASK_CANCEL_AFTER_WAIT");
                    break;
                }
                AvmValue reason = vm->stack[--vm->sp];
                AvmValue waitv = vm->stack[--vm->sp];
                AvmValue delayv = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT || delayv.type != AVM_VAL_INT || waitv.type != AVM_VAL_INT) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "TASK_CANCEL_AFTER_WAIT expects (int handle, int delay_ms, int wait_ms, reason)");
                    break;
                }
                int tid = (int)hv.as.i - 1;
                if (tid == sched->current_tid) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "TASK_CANCEL_AFTER_WAIT self");
                    break;
                }
                if (delayv.as.i <= 0) {
                    int transitioned = 0;
                    AvmValue rv = avm_task_cancel_wait_result_or_transition(vm, sched, sched->current_tid, tid, waitv.as.i, reason, &transitioned);
                    if (!transitioned) {
                        vm->stack[vm->sp++] = rv;
                        break;
                    }
                    task_save_from_vm(vm, &sched->tasks[sched->current_tid]);
                    int next0 = -1;
                    if (!sched_ready_pop(sched, &next0)) {
                        avm_task_clear_wait_state(&sched->tasks[sched->current_tid]);
                        vm->stack[vm->sp++] = avm_task_stop_result("detached", avm_int(-60), reason, avm_nil());
                        break;
                    }
                    sched_switch(vm, sched, next0);
                    continue;
                }
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "TASK_CANCEL_AFTER_WAIT invalid handle");
                    break;
                }
                avm_add_virtual_sleep_ms(vm, delayv.as.i);
                int transitioned = 0;
                AvmValue rv = avm_task_cancel_wait_result_or_transition(vm, sched, sched->current_tid, tid, waitv.as.i, reason, &transitioned);
                if (!transitioned) {
                    vm->stack[vm->sp++] = rv;
                    break;
                }
                task_save_from_vm(vm, &sched->tasks[sched->current_tid]);
                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_task_clear_wait_state(&sched->tasks[sched->current_tid]);
                    vm->stack[vm->sp++] = avm_task_stop_result("detached", avm_int(-60), reason, avm_nil());
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_CHAN_NEW: { // CHAN_NEW
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                int hid = sched_chan_new(sched);
                if (hid <= 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "CHAN_NEW failed")); break; }
                vm->stack[vm->sp++] = avm_int((int64_t)hid);
                break;
            }
            case AVM_OP_CHAN_SEND: { // CHAN_SEND
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CHAN_SEND")); break; }
                AvmValue val = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_SEND expects int channel")); break; }
                AvmChan* ch = sched_chan_get(sched, hv.as.i);
                if (!ch) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_SEND invalid channel")); break; }

                if (!chan_send_value(sched, ch, val)) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "channel queue overflow"));
                    break;
                }

                // A send can make a previously-blocked select waiter runnable.
                sched_try_wake_select_waiters(vm, sched);
                if (vm->last_error.type != AVM_VAL_NIL) break;

                vm->stack[vm->sp++] = avm_int(1);
                break;
            }
            case AVM_OP_CHAN_RECV: { // CHAN_RECV
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CHAN_RECV")); break; }
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_RECV expects int channel")); break; }
                AvmChan* ch = sched_chan_get(sched, hv.as.i);
                if (!ch) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_RECV invalid channel")); break; }

                AvmValue msg;
                if (chan_queue_pop(ch, &msg)) {
                    vm->stack[vm->sp++] = msg;
                    break;
                }

                // Block current task on this channel.
                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 2;
                ct->wait_chan = (int)hv.as.i;
                (void)chan_recv_waiter_push(ch, cur);
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_SELECT_RECV: { // SELECT_RECV
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SELECT_RECV")); break; }
                AvmValue lv = vm->stack[--vm->sp];
                if (lv.type != AVM_VAL_LIST || !lv.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SELECT_RECV expects list")); break; }

                AvmList* lst = lv.as.l;
                int cnt = lst->count;
                int cur = sched->current_tid;
                int start = 0;
                if (cnt > 0) {
                    start = sched->tasks[cur].select_cursor % cnt;
                    if (start < 0) start = 0;
                }
                for (int off = 0; off < cnt; off++) {
                    int i = (start + off) % cnt;
                    AvmValue hv = lst->items[i];
                    if (hv.type != AVM_VAL_INT) continue;
                    AvmChan* ch = sched_chan_get(sched, hv.as.i);
                    if (!ch) continue;
                    AvmValue msg;
                    if (chan_queue_pop(ch, &msg)) {
                        AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), msg);
                        if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                        if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                        vm->stack[vm->sp++] = pair;
                        goto select_done;
                    }
                }

                // Block current task, registering as a select waiter.
                {
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 3;
                    ct->wait_list = lv;
                    (void)sched_select_waiter_add(sched, cur);
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

select_done:
                break;
            }
            case AVM_OP_SELECT: { // SELECT
                if (!sched) {
                    sched = avm_sched_lazy_ensure(vm, sched);
                    if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)")); break; }
                }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SELECT")); break; }
                AvmValue lv = vm->stack[--vm->sp];
                if (lv.type != AVM_VAL_LIST || !lv.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SELECT expects list")); break; }

                AvmList* lst = lv.as.l;
                int cnt = lst->count;
                int cur = sched->current_tid;
                int start = 0;
                if (cnt > 0) {
                    start = sched->tasks[cur].select_cursor % cnt;
                    if (start < 0) start = 0;
                }
                for (int off = 0; off < cnt; off++) {
                    int i = (start + off) % cnt;
                    int kind = -1;
                    int64_t chid = 0;
                    AvmValue sendv = avm_nil();
                    if (!select_case_parse(lst->items[i], &kind, &chid, &sendv)) continue;
                    AvmChan* ch = sched_chan_get(sched, chid);
                    if (!ch) continue;

                    if (kind == 0) { // recv
                        AvmValue msg;
                        if (chan_queue_pop(ch, &msg)) {
                            AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), msg);
                            if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                            if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                            vm->stack[vm->sp++] = pair;
                            goto select2_done;
                        }
                    } else if (kind == 1) { // send
                        if (!chan_can_send(ch)) continue;
                        if (!chan_send_value(sched, ch, sendv)) { avm_abort(vm, avm_err(AVM_ERR_BUDGET, "channel queue overflow")); break; }
                        AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), avm_int(1));
                        if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                        if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                        vm->stack[vm->sp++] = pair;
                        goto select2_done;
                    }
                }

                // Block current task, registering as a select waiter.
                {
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 5;
                    ct->wait_list = lv;
                    (void)sched_select_waiter_add(sched, cur);
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

select2_done:
                // Sending via SELECT can also wake other blocked select waiters.
                sched_try_wake_select_waiters(vm, sched);
                break;
            }
            case AVM_OP_YIELD: { // YIELD
                if (!sched) break;
                int cur = sched->current_tid;
                // If no other runnable tasks, yield is a no-op.
                if (sched->ready_len <= 0) break;
                AvmTask* ct = &sched->tasks[cur];
                task_save_from_vm(vm, ct);
                (void)sched_ready_push(sched, cur);
                int next = -1;
                if (sched_ready_pop(sched, &next)) {
                    sched_switch(vm, sched, next);
                    continue;
                }
                break;
            }
            case 0x3E: { // MAKE_CLOSURE u8
                uint8_t ncap = code[vm->pc++];
                if (vm->sp < (int)ncap + 1) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on MAKE_CLOSURE"));
                    break;
                }
                AvmValue base = vm->stack[vm->sp - 1];
                if (base.type != AVM_VAL_FUNC || !base.as.fn) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "MAKE_CLOSURE expects function value"));
                    break;
                }

                AvmList* env_list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!env_list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                env_list->count = (int)ncap;
                env_list->capacity = (int)ncap;
                env_list->all_int = 1;
                env_list->items = NULL;
                if (ncap > 0) {
                    env_list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)ncap, AVM_ALLOC_KIND_LIST);
                    if (!env_list->items) { avm_heap_free(env_list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    // Capture values are below the base function on the stack:
                    //   [... cap0 cap1 ... cap(n-1) base_fn]
                    int start = vm->sp - 1 - (int)ncap;
                    for (int i = 0; i < (int)ncap; i++) {
                        env_list->items[i] = vm->stack[start + i];
                        if (env_list->all_int && env_list->items[i].type != AVM_VAL_INT) env_list->all_int = 0;
                    }
                }

                AvmValue envv;
                envv.type = AVM_VAL_LIST;
                envv.as.l = env_list;
                AvmValue clo = avm_func_new(vm, base.as.fn->addr, envv);
                if (avm_is_err_val(clo)) { avm_abort(vm, clo); break; }

                vm->sp -= (int)ncap + 1;
                vm->stack[vm->sp++] = clo;
                break;
            }
            case 0x3F: { // LOAD_ENV u8
                uint8_t idx = code[vm->pc++];
                if (vm->env.type != AVM_VAL_LIST || !vm->env.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_ENV with nil env"));
                    break;
                }
                AvmList* env_list = vm->env.as.l;
                if ((int)idx >= env_list->count) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_ENV out of range"));
                    break;
                }
                vm->stack[vm->sp++] = env_list->items[(int)idx];
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
                list->all_int = 1;
                list->items = NULL;
                if (len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)list->capacity, AVM_ALLOC_KIND_LIST);
                    if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    // NEW_LIST consumes `len` values from the stack, preserving push order:
                    // the last pushed value becomes the last element in the list.
                    for (int i = (int)len - 1; i >= 0; i--) {
                        list->items[i] = vm->stack[--vm->sp];
                        if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
                    }
                }
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x5E: { // NEW_LIST_INT (cap on stack)
                if (vm->sp < 1) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow"));
                    break;
                }
                AvmValue capv = vm->stack[--vm->sp];
                if (capv.type != AVM_VAL_INT) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_new expects int");
                    break;
                }
                int64_t cap64 = capv.as.i;
                if (cap64 < 0) cap64 = 0;
                if (cap64 > (int64_t)INT_MAX) {
                    vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_new cap too large");
                    break;
                }
                AvmValue res = avm_list_int_new((int)cap64);
                if (avm_is_err_val(res)) {
                    avm_abort(vm, res);
                }
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
                        char msg[192];
                        snprintf(msg, sizeof(msg),
                            "NEW_MAP key type not supported (need nil/bool/int/string): type=%d pc=%d pair=%u/%u sp=%d val_type=%d",
                            (int)key.type, vm ? vm->pc : -1, (unsigned)i, (unsigned)pairs, vm ? vm->sp : -1, (int)val.type);
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, msg));
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
                        if (i < 0 || i >= obj.as.l->count) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        res = obj.as.l->items[i];
                    } else if (obj.type == AVM_VAL_LIST_INT && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i < 0 || i >= obj.as.li->count) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        res = avm_int(obj.as.li->items[i]);
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err_map_key_unsupported_at(vm, key, "GET_INDEX"));
                            break;
                        }
                        int found = 0;
                        int idx = avm_map_find_index(obj.as.m, key, &found);
                        if (found) {
                            res = obj.as.m->values[idx];
                        }
                    } else {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index get on non-list/map"));
                        break;
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x57: { // GET_INDEX_LIST
                if (vm->sp >= 2) {
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    AvmValue res = avm_nil();

                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i < 0 || i >= obj.as.l->count) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        res = obj.as.l->items[i];
                    } else if (obj.type == AVM_VAL_LIST_INT && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i < 0 || i >= obj.as.li->count) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        res = avm_int(obj.as.li->items[i]);
                    } else {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index get on non-list/map"));
                        break;
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x58: { // LIST_DOT
                avm_op_list_dot(vm);
                break;
            }
            case 0x59: { // LIST_PUSH_INT
                if (vm->sp >= 2) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    if (val.type != AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push expects int");
                        break;
                    }
                    if (obj.type == AVM_VAL_LIST_INT && obj.as.li) {
                        AvmListInt* list = obj.as.li;
                        if (!avm_list_int_ensure_cap(list, list->count + 1)) {
                            AvmValue e = avm_alloc_fail_value();
                            avm_abort(vm, e);
                            vm->stack[vm->sp++] = e;
                            break;
                        }
                        list->items[list->count++] = val.as.i;
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (obj.type != AVM_VAL_LIST || !obj.as.l) {
                        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push expects (list, int)");
                        break;
                    }
                    AvmList* list = obj.as.l;
                    if (list->count >= list->capacity) {
                        if (!avm_list_ensure_cap(list, list->count + 1)) {
                            AvmValue e = avm_alloc_fail_value();
                            avm_abort(vm, e);
                            vm->stack[vm->sp++] = e;
                            break;
                        }
                    }
                    if (list->count == 0) {
                        // list_int_push is only used for list<int> writes; mark int-fast.
                        list->all_int = 1;
                    }
                    list->items[list->count++] = val;
                    // list_int_push enforces int values, so keep all_int true if already set.
                    vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x5A: { // LIST_PUSH
                if (vm->sp >= 2) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    if (obj.type == AVM_VAL_LIST_INT && obj.as.li) {
                        if (val.type != AVM_VAL_INT) {
                            vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_push expects int for list_int");
                            break;
                        }
                        AvmListInt* list = obj.as.li;
                        if (!avm_list_int_ensure_cap(list, list->count + 1)) {
                            AvmValue e = avm_alloc_fail_value();
                            avm_abort(vm, e);
                            vm->stack[vm->sp++] = e;
                            break;
                        }
                        list->items[list->count++] = val.as.i;
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (obj.type != AVM_VAL_LIST || !obj.as.l) {
                        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_push expects list");
                        break;
                    }
                    AvmList* list = obj.as.l;
                    if (list->count >= list->capacity) {
                        if (!avm_list_ensure_cap(list, list->count + 1)) {
                            AvmValue e = avm_alloc_fail_value();
                            avm_abort(vm, e);
                            vm->stack[vm->sp++] = e;
                            break;
                        }
                    }
                    list->items[list->count++] = val;
                    if (list->all_int && val.type != AVM_VAL_INT) list->all_int = 0;
                    vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x5B: { // LIST_PUSH_INT_LOOP
                avm_op_list_push_int_loop(vm);
                break;
            }
            case 0x5F: { // LIST_PUSH2_INT_LOOP
                avm_op_list_push2_int_loop(vm);
                break;
            }
            case 0x60: { // LIST_PUSH3_INT_LOOP
                avm_op_list_push3_int_loop(vm);
                break;
            }
            case 0x61: { // INT_LCG_SUM_LOOP
                avm_op_int_lcg_sum_loop(vm);
                break;
            }
            case 0x5C: { // LIST_SUM_INT_LOOP
                avm_op_list_sum_int_loop(vm);
                break;
            }
            case 0x5D: { // LIST_SUM3_INT_LOOP
                avm_op_list_sum3_int_loop(vm);
                break;
            }
            case 0x43: { // SET_INDEX
                if (vm->sp >= 3) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];

                    if (obj.type == AVM_VAL_LIST_INT && key.type == AVM_VAL_INT) {
                        if (val.type != AVM_VAL_INT) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "list_int_set expects int"));
                            break;
                        }
                        int idx = (int)key.as.i;
                        if (idx < 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        AvmListInt* list = obj.as.li;
                        if (idx < list->count) {
                            list->items[idx] = val.as.i;
                        } else {
                            if (!avm_list_int_ensure_cap(list, idx + 1)) {
                                avm_abort(vm, avm_alloc_fail_value());
                                break;
                            }
                            while (list->count < idx) {
                                list->items[list->count++] = 0;
                            }
                            list->items[list->count++] = val.as.i;
                        }
                    } else if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i < 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "index out of bounds"));
                            break;
                        }
                        if (i < obj.as.l->count) {
                            obj.as.l->items[i] = val;
                        } else {
                            if (!avm_list_ensure_cap(obj.as.l, i + 1)) {
                                avm_abort(vm, avm_alloc_fail_value());
                                break;
                            }
                            if (obj.as.l->all_int && i > obj.as.l->count) obj.as.l->all_int = 0;
                            while (obj.as.l->count < i) {
                                obj.as.l->items[obj.as.l->count++] = avm_nil();
                            }
                            obj.as.l->items[obj.as.l->count++] = val;
                        }
                        if (obj.as.l->all_int && val.type != AVM_VAL_INT) obj.as.l->all_int = 0;
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err_map_key_unsupported_at(vm, key, "SET_INDEX"));
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

        // Deterministic time-sliced scheduling (gas quantum):
        // If there is another runnable task, decrement current slice and yield when it reaches 0.
        if (sched && sched->ready_len > 0) {
            int cur = sched->current_tid;
            if (cur >= 0 && cur < sched->task_cap && sched->tasks[cur].used && !sched->tasks[cur].done && !sched->tasks[cur].blocked) {
                AvmTask* ct = &sched->tasks[cur];
                ct->slice_remaining--;
                if (ct->slice_remaining <= 0) {
                    ct->slice_remaining = sched->quantum_steps;
                    task_save_from_vm(vm, ct);
                    (void)sched_ready_push(sched, cur);
                    int next = -1;
                    if (sched_ready_pop(sched, &next)) {
                        sched_switch(vm, sched, next);
                        continue;
                    }
                }
            }
        }

        #include "avm_vm_deadline_waits.inc"
    }

    if (vm->trace_hash_enabled && vm->trace_hash_started && !vm->trace_hash_finalized) {
        avm_sha256_final(&vm->trace_hash_ctx, vm->trace_hash_out);
        vm->trace_hash_finalized = 1;
    }

    avm_alloc_owner_pop(prev_owner);
}
