#include "avm_internal.h"
#include "avm_vm_sched.h"

#include <stdio.h>
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
        case 0x52: return "LOAD_LOCAL16";
        case 0x53: return "STORE_LOCAL16";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x1D: return "MUL";
        case 0x1E: return "DIV";
        case 0x1F: return "MOD";
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
        case 0x21: return "PRINT_LIST";
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x4E: return "JMP32";
        case 0x4F: return "JMP_IF32";
        case 0x38: return "CALL";
        case 0x50: return "CALL32";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x3C: return "PUSH_FUNC";
        case 0x51: return "PUSH_FUNC32";
        case 0x3D: return "CALL_INDIRECT";
        case 0x3E: return "MAKE_CLOSURE";
        case 0x3F: return "LOAD_ENV";
        case 0x40: return "NEW_LIST";
        case 0x5E: return "NEW_LIST_INT";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x57: return "GET_INDEX_LIST";
        case 0x58: return "LIST_DOT";
        case 0x59: return "LIST_PUSH_INT";
        case 0x5A: return "LIST_PUSH";
        case 0x5B: return "LIST_PUSH_INT_LOOP";
        case 0x5C: return "LIST_SUM_INT_LOOP";
        case 0x5D: return "LIST_SUM3_INT_LOOP";
        case 0x5F: return "LIST_PUSH2_INT_LOOP";
        case 0x60: return "LIST_PUSH3_INT_LOOP";
        case 0x61: return "INT_LCG_SUM_LOOP";
        case 0x43: return "SET_INDEX";
        case 0x44: return "CALL_INDIRECT_SPREAD";
        case 0x45: return "SPAWN_CALL_LIST";
        case 0x54: return "SPAWN_CALL_SPREAD";
        case 0x55: return "TYPE_CTOR_MAP_SPREAD";
        case 0x56: return "NEW_LIST_SPREAD";
        case 0x46: return "JOIN";
        case 0x47: return "CHAN_NEW";
        case 0x48: return "CHAN_SEND";
        case 0x49: return "CHAN_RECV";
        case 0x4A: return "SELECT_RECV";
        case 0x4B: return "YIELD";
        case 0x4C: return "JOIN_TIMEOUT";
        case 0x4D: return "SELECT";
        case 0x62: return "DETACH";
        case 0x63: return "TASK_CANCEL_AFTER_WAIT";
        case 0x64: return "TASK_CANCEL_WAIT";
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
    if (!vm) return NULL;
    vm->stack_base = (AvmValue*)malloc(sizeof(AvmValue) * AVM_STACK_SIZE);
    if (!vm->stack_base) {
        free(vm);
        return NULL;
    }
    vm->stack = vm->stack_base;
    vm->sp = 0;
    vm->pc = 0;
    vm->running = 0;
    vm->prog = NULL;
    vm->fp = 0;
    vm->env = avm_nil();
    vm->frame_count = 0;
    vm->frame_limit = MAX_FRAMES;
    vm->allowed_native_domains = 0;
    vm->fs_allow_prefixes = NULL;
    vm->fs_allow_prefix_count = 0;
    vm->fs_mounts_read_virt = NULL;
    vm->fs_mounts_read_host = NULL;
    vm->fs_mounts_read_count = 0;
    vm->fs_mounts_write_virt = NULL;
    vm->fs_mounts_write_host = NULL;
    vm->fs_mounts_write_count = 0;
    vm->fs_backend_kind = 0;
    vm->vfs = NULL;
    vm->proc_backend_kind = 0;
    vm->vproc = NULL;
    vm->proc_exit_code = 0;
    vm->net_backend_kind = 0;
    vm->vnet = NULL;
    vm->net_fetch_fn = NULL;
    vm->net_fetch_user_data = NULL;
    vm->net_session_open_fn = NULL;
    vm->net_session_write_fn = NULL;
    vm->net_session_read_fn = NULL;
    vm->net_session_poll_fn = NULL;
    vm->net_session_close_fn = NULL;
    vm->net_session_user_data = NULL;
    vm->gfx_frame_data = NULL;
    vm->gfx_frame_len = 0;
    vm->gfx_input_queue = NULL;
    vm->permission_request_data = NULL;
    vm->permission_request_len = 0;
    vm->permission_request_sequence = 0;
    vm->stdout_capture_enabled = 0;
    vm->stdout_capture = NULL;
    vm->stdout_capture_len = 0;
    vm->stdout_capture_cap = 0;
    vm->gas_remaining = 0;
    vm->deadline_ns = 0;
    vm->cancelled = 0;
    vm->heap_budget_bytes = 0;
    vm->heap_used_bytes = 0;
    vm->heap_allocs_head = NULL;
    vm->tmp_freelist_enabled = 0;
    for (int i = 0; i < AVM_FREELIST_BUCKETS; i++) vm->tmp_freelist_buckets[i] = NULL;
    vm->tmp_freelist_bytes = 0;
    vm->tmp_freelist_cap_bytes = 0;
    vm->tmp_freelist_max_block_bytes = 0;
    vm->tmp_freelist_hits = 0;
    vm->tmp_freelist_misses = 0;
    vm->tmp_freelist_evictions = 0;
    vm->list_freelist_enabled = 0;
    for (int i = 0; i < AVM_FREELIST_BUCKETS; i++) vm->list_freelist_buckets[i] = NULL;
    vm->list_freelist_bytes = 0;
    vm->list_freelist_cap_bytes = 0;
    vm->list_freelist_max_block_bytes = 0;
    vm->list_freelist_hits = 0;
    vm->list_freelist_misses = 0;
    vm->list_freelist_evictions = 0;
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
    vm->task_quantum_steps = 1000;
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
    memset(vm->ptr_handles, 0, sizeof(vm->ptr_handles));
    vm->ptr_handle_count = 0;
    vm->sched = NULL;
    vm->argc = 0;
    vm->argv = NULL;
    for (int i = 0; i < MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (!vm) return;

    // Close any open replay/record files (CLI can also close; best-effort here).
    if (vm->record_log) fclose(vm->record_log);
    if (vm->replay_log) fclose(vm->replay_log);

    // Best-effort: release heap objects reachable from VM roots.
    avm_release_heap_all(vm);
    // Release any remaining unreachable heap allocations (leak-free teardown).
    avm_release_unreachable_allocs(vm);
    // Release TMP freelist allocations (if enabled).
    avm_release_tmp_freelist(vm);
    // Release LIST/LIST_INT freelist allocations (if enabled).
    avm_release_list_freelist(vm);

    // Leak guard (must never fire): after teardown, no heap allocations should remain.
    // This is failure-only (no output on success) and intentionally fatal so leak
    // regressions cannot slip by silently during rolling development.
    if (vm->heap_allocs_head != NULL || vm->heap_used_bytes != 0) {
        fprintf(stderr, "AVM LEAK: heap_allocs_head=%p heap_used_bytes=%llu\n",
            vm->heap_allocs_head, (unsigned long long)vm->heap_used_bytes);
#if !defined(AVM_EMBED_NO_ABORT_ON_LEAK)
        abort();
#endif
    }

    // Tear down cooperative scheduler (tasks/channels) if it was initialized.
    // (Owned by this module; does not participate in the heap budget accounting.)
    if (vm->sched) avm_sched_free(vm);

    if (vm->stack_base) free(vm->stack_base);
    if (vm->break_pcs) free(vm->break_pcs);
    if (vm->stdout_capture) free(vm->stdout_capture);
    if (vm->gfx_frame_data) free(vm->gfx_frame_data);
    if (vm->permission_request_data) free(vm->permission_request_data);
    if (vm->gfx_input_queue) {
        AvmGfxInputQueue* q = (AvmGfxInputQueue*)vm->gfx_input_queue;
        if (q->entries) {
            for (uint32_t i = 0; i < q->count; i++) {
                if (q->entries[i].data) free(q->entries[i].data);
            }
            free(q->entries);
        }
        free(q);
    }
    if (vm->fs_allow_prefixes) {
        for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
            if (vm->fs_allow_prefixes[i]) free(vm->fs_allow_prefixes[i]);
        }
        free(vm->fs_allow_prefixes);
    }
    if (vm->fs_mounts_read_virt || vm->fs_mounts_read_host) {
        for (int i = 0; i < vm->fs_mounts_read_count; i++) {
            if (vm->fs_mounts_read_virt && vm->fs_mounts_read_virt[i]) free(vm->fs_mounts_read_virt[i]);
            if (vm->fs_mounts_read_host && vm->fs_mounts_read_host[i]) free(vm->fs_mounts_read_host[i]);
        }
        if (vm->fs_mounts_read_virt) free(vm->fs_mounts_read_virt);
        if (vm->fs_mounts_read_host) free(vm->fs_mounts_read_host);
    }
    if (vm->fs_mounts_write_virt || vm->fs_mounts_write_host) {
        for (int i = 0; i < vm->fs_mounts_write_count; i++) {
            if (vm->fs_mounts_write_virt && vm->fs_mounts_write_virt[i]) free(vm->fs_mounts_write_virt[i]);
            if (vm->fs_mounts_write_host && vm->fs_mounts_write_host[i]) free(vm->fs_mounts_write_host[i]);
        }
        if (vm->fs_mounts_write_virt) free(vm->fs_mounts_write_virt);
        if (vm->fs_mounts_write_host) free(vm->fs_mounts_write_host);
    }
    free(vm);
}

void avm_load(AvmVM* vm, AvmProgram* prog) {
    vm->prog = prog;
    vm->pc = 0;
    vm->sp = 0;
    vm->fp = 0;
    vm->env = avm_nil();
    vm->frame_count = 0;
    vm->stack = vm->stack_base;
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
