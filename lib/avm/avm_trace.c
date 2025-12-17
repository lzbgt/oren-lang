#include "avm_internal.h"

#include <string.h>

static void trace_sha_u8(AvmSha256Ctx* h, uint8_t v) { avm_sha256_update(h, &v, 1); }
static void trace_sha_u16_le(AvmSha256Ctx* h, uint16_t v) {
    uint8_t b[2];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    avm_sha256_update(h, b, 2);
}
static void trace_sha_u32_le(AvmSha256Ctx* h, uint32_t v) {
    uint8_t b[4];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    b[2] = (uint8_t)((v >> 16) & 0xFFu);
    b[3] = (uint8_t)((v >> 24) & 0xFFu);
    avm_sha256_update(h, b, 4);
}

static size_t trace_insn_len(const uint8_t* code, size_t code_len, size_t pc) {
    if (!code || pc >= code_len) return 1;
    uint8_t op = code[pc];
    if (op == 0x02) return 3;                 // PUSH_CONST u16
    if (op == 0x04 || op == 0x05) return 2;   // LOAD/STORE_LOCAL u8
    if (op == 0x06 || op == 0x07) return 3;   // LOAD/STORE_GLOBAL u16
    if (op == 0x30 || op == 0x31) return 3;   // JMP/JMP_IF i16
    if (op == 0x38) return 4;                 // CALL u16 u8
    if (op == 0x3A) return 4;                 // CALL_NATIVE u16 u8
    if (op == 0x3B) return 5;                 // CALL_NATIVE2 u8 u16 u8
    if (op == 0x40 || op == 0x41) return 3;   // NEW_LIST/NEW_MAP u16
    return 1;
}

static AvmBytes* trace_bytes_new(void) {
    // Trace bytes are diagnostic data, not program heap. Do not charge to heap budget.
    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    AvmBytes* b = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
    avm_alloc_unbudgeted_pop(prev);
    if (!b) return NULL;
    b->data = NULL;
    b->len = 0;
    b->capacity = 0;
    return b;
}

static void trace_bytes_disable_truncated(AvmVM* vm) {
    if (!vm) return;
    vm->trace_bytes_enabled = 0;
    vm->trace_bytes_truncated = 1;
}

static int trace_bytes_can_fit(AvmVM* vm, uint64_t add) {
    if (!vm) return 0;
    if (add == 0) return 1;
    if (vm->trace_budget_bytes == 0) return 1;
    if (vm->trace_used_bytes > vm->trace_budget_bytes) return 0;
    if (add > vm->trace_budget_bytes - vm->trace_used_bytes) return 0;
    return 1;
}

static int trace_bytes_prepare(AvmVM* vm, uint64_t add) {
    if (!vm || !vm->trace_bytes_enabled) return 1;
    if (add == 0) return 1;

    if (!vm->trace_bytes) {
        vm->trace_bytes = trace_bytes_new();
        if (!vm->trace_bytes) {
            trace_bytes_disable_truncated(vm);
            return 1;
        }
    }

    if (!trace_bytes_can_fit(vm, add)) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }

    uint64_t need_u64 = (uint64_t)vm->trace_bytes->len + add;
    if (need_u64 > (uint64_t)INT32_MAX) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    // Trace bytes are diagnostic data; don't charge these reallocations to the heap budget.
    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    int ok = bytes_ensure_cap(vm->trace_bytes, (int)need_u64);
    avm_alloc_unbudgeted_pop(prev);
    if (!ok) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    return 1;
}

enum {
    TRACE_EVT_STEP = 1,
    TRACE_EVT_NATIVE2 = 2,
    TRACE_EVT_ABORT = 3,
    TRACE_EVT_ALLOC = 4,
    TRACE_EVT_FREE = 5,
    TRACE_EVT_REALLOC = 6
};

static int trace_begin_if_needed(AvmVM* vm) {
    if (!vm) return 0;
    int want_any = (vm->trace_hash_enabled != 0) || (vm->trace_bytes_enabled != 0);
    if (!want_any) return 1;

    if ((vm->trace_hash_enabled && vm->trace_hash_started) || (vm->trace_bytes_enabled && vm->trace_bytes)) return 1;

    const uint8_t tag[8] = { 'A','V','M','T','R','C','0','2' };

    if (vm->trace_hash_enabled && !vm->trace_hash_started) {
        avm_sha256_init(&vm->trace_hash_ctx);
        avm_sha256_update(&vm->trace_hash_ctx, tag, 8);
        vm->trace_hash_started = 1;
        vm->trace_hash_finalized = 0;
    }

    if (vm->trace_bytes_enabled && !vm->trace_bytes) {
        // Trace bytes are best-effort: never fail execution if tracing can't allocate or hits budget.
        (void)trace_bytes_prepare(vm, 8);
        if (!vm->trace_bytes_enabled) return 1;
        int prev = 0;
        avm_alloc_unbudgeted_push(&prev);
        uint32_t p = (uint32_t)vm->trace_bytes->len;
        int ok = mem_write_bytes(vm->trace_bytes, &p, tag, 8);
        avm_alloc_unbudgeted_pop(prev);
        if (!ok) {
            trace_bytes_disable_truncated(vm);
            return 1;
        }
        vm->trace_used_bytes += 8;
    }

    return 1;
}

static void trace_hash_u8(AvmVM* vm, uint8_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u8(&vm->trace_hash_ctx, v);
}
static void trace_hash_u16(AvmVM* vm, uint16_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u16_le(&vm->trace_hash_ctx, v);
}
static void trace_hash_u32(AvmVM* vm, uint32_t v) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    trace_sha_u32_le(&vm->trace_hash_ctx, v);
}
static void trace_hash_bytes(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !vm->trace_hash_enabled || !vm->trace_hash_started) return;
    if (data && len > 0) avm_sha256_update(&vm->trace_hash_ctx, data, len);
}

int trace_emit_step(AvmVM* vm, int op_pc, uint8_t op) {
    if (!vm) return 0;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // STEP event encoding:
    // kind=u8(1), pc=u32, op=u8, ilen=u16, bytes[ilen]
    size_t pc = (size_t)op_pc;
    size_t ilen = trace_insn_len(vm->prog ? vm->prog->code : NULL, vm->prog ? vm->prog->code_len : 0, pc);
    if (ilen > 65535) ilen = 65535;

    // hash
    trace_hash_u8(vm, TRACE_EVT_STEP);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u8(vm, op);
    trace_hash_u16(vm, (uint16_t)ilen);
    if (vm->prog && vm->prog->code && pc + ilen <= vm->prog->code_len) trace_hash_bytes(vm, vm->prog->code + pc, ilen);
    else trace_hash_bytes(vm, &op, 1);

    // bytes
    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 1 + 2 + (uint64_t)ilen;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_STEP) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u8(vm->trace_bytes, &p, op) ||
                !mem_write_u16_le(vm->trace_bytes, &p, (uint16_t)ilen)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            if (vm->prog && vm->prog->code && pc + ilen <= vm->prog->code_len) {
                if (!mem_write_bytes(vm->trace_bytes, &p, vm->prog->code + pc, (uint32_t)ilen)) {
                    avm_alloc_unbudgeted_pop(prev);
                    trace_bytes_disable_truncated(vm);
                    return 1;
                }
            } else {
                if (!mem_write_u8(vm->trace_bytes, &p, op)) {
                    avm_alloc_unbudgeted_pop(prev);
                    trace_bytes_disable_truncated(vm);
                    return 1;
                }
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }

    return 1;
}

int trace_emit_native2(AvmVM* vm, int op_pc, uint8_t domain, uint16_t op, uint8_t nargs) {
    if (!vm) return 0;
    if (!vm->trace_hash_enabled && !vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // NATIVE2 event encoding:
    // kind=u8(2), pc=u32, domain=u8, op=u16, nargs=u8
    trace_hash_u8(vm, TRACE_EVT_NATIVE2);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u8(vm, domain);
    trace_hash_u16(vm, op);
    trace_hash_u8(vm, nargs);

    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 1 + 2 + 1;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_NATIVE2) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u8(vm->trace_bytes, &p, domain) ||
                !mem_write_u16_le(vm->trace_bytes, &p, op) ||
                !mem_write_u8(vm->trace_bytes, &p, nargs)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }
    return 1;
}

int trace_emit_abort(AvmVM* vm, int op_pc, uint16_t err_code) {
    if (!vm) return 0;
    if (!vm->trace_hash_enabled && !vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_hash_limit && vm->gas_executed > vm->trace_hash_limit) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    // ABORT event encoding:
    // kind=u8(3), pc=u32, code=u16
    trace_hash_u8(vm, TRACE_EVT_ABORT);
    trace_hash_u32(vm, (uint32_t)op_pc);
    trace_hash_u16(vm, err_code);

    if (vm->trace_bytes_enabled) {
        uint64_t need = 1 + 4 + 2;
        (void)trace_bytes_prepare(vm, need);
        if (vm->trace_bytes_enabled && vm->trace_bytes) {
            int prev = 0;
            avm_alloc_unbudgeted_push(&prev);
            uint32_t p = (uint32_t)vm->trace_bytes->len;
            if (!mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_ABORT) ||
                !mem_write_u32_le(vm->trace_bytes, &p, (uint32_t)op_pc) ||
                !mem_write_u16_le(vm->trace_bytes, &p, err_code)) {
                avm_alloc_unbudgeted_pop(prev);
                trace_bytes_disable_truncated(vm);
                return 1;
            }
            avm_alloc_unbudgeted_pop(prev);
            vm->trace_used_bytes += need;
        }
    }
    return 1;
}

int trace_emit_alloc_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t size, uint32_t charged) {
    if (!vm) return 0;
    if (!vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    uint64_t need = 1 + 4 + 4 + 1 + 4 + 4;
    (void)trace_bytes_prepare(vm, need);
    if (!vm->trace_bytes_enabled || !vm->trace_bytes) return 1;

    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    uint32_t p = (uint32_t)vm->trace_bytes->len;
    int ok = mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_ALLOC) &&
        mem_write_u32_le(vm->trace_bytes, &p, pc) &&
        mem_write_u32_le(vm->trace_bytes, &p, alloc_id) &&
        mem_write_u8(vm->trace_bytes, &p, kind) &&
        mem_write_u32_le(vm->trace_bytes, &p, size) &&
        mem_write_u32_le(vm->trace_bytes, &p, charged);
    avm_alloc_unbudgeted_pop(prev);
    if (!ok) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    vm->trace_used_bytes += need;
    return 1;
}

int trace_emit_free_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t size, uint32_t charged) {
    if (!vm) return 0;
    if (!vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    uint64_t need = 1 + 4 + 4 + 1 + 4 + 4;
    (void)trace_bytes_prepare(vm, need);
    if (!vm->trace_bytes_enabled || !vm->trace_bytes) return 1;

    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    uint32_t p = (uint32_t)vm->trace_bytes->len;
    int ok = mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_FREE) &&
        mem_write_u32_le(vm->trace_bytes, &p, pc) &&
        mem_write_u32_le(vm->trace_bytes, &p, alloc_id) &&
        mem_write_u8(vm->trace_bytes, &p, kind) &&
        mem_write_u32_le(vm->trace_bytes, &p, size) &&
        mem_write_u32_le(vm->trace_bytes, &p, charged);
    avm_alloc_unbudgeted_pop(prev);
    if (!ok) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    vm->trace_used_bytes += need;
    return 1;
}

int trace_emit_realloc_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t old_size, uint32_t new_size, uint32_t old_charged, uint32_t new_charged) {
    if (!vm) return 0;
    if (!vm->trace_bytes_enabled) return 1;
    if (!trace_begin_if_needed(vm)) return 1;
    if (vm->trace_bytes_limit && vm->gas_executed > vm->trace_bytes_limit) return 1;

    uint64_t need = 1 + 4 + 4 + 1 + 4 + 4 + 4 + 4;
    (void)trace_bytes_prepare(vm, need);
    if (!vm->trace_bytes_enabled || !vm->trace_bytes) return 1;

    int prev = 0;
    avm_alloc_unbudgeted_push(&prev);
    uint32_t p = (uint32_t)vm->trace_bytes->len;
    int ok = mem_write_u8(vm->trace_bytes, &p, TRACE_EVT_REALLOC) &&
        mem_write_u32_le(vm->trace_bytes, &p, pc) &&
        mem_write_u32_le(vm->trace_bytes, &p, alloc_id) &&
        mem_write_u8(vm->trace_bytes, &p, kind) &&
        mem_write_u32_le(vm->trace_bytes, &p, old_size) &&
        mem_write_u32_le(vm->trace_bytes, &p, new_size) &&
        mem_write_u32_le(vm->trace_bytes, &p, old_charged) &&
        mem_write_u32_le(vm->trace_bytes, &p, new_charged);
    avm_alloc_unbudgeted_pop(prev);
    if (!ok) {
        trace_bytes_disable_truncated(vm);
        return 1;
    }
    vm->trace_used_bytes += need;
    return 1;
}

int avm_trace_hash(AvmVM* vm, uint8_t out[32]) {
    if (!vm || !out) return 0;
    if (!vm->trace_hash_finalized) return 0;
    memcpy(out, vm->trace_hash_out, 32);
    return 1;
}

AvmBytes* avm_trace_bytes(AvmVM* vm) {
    if (!vm) return NULL;
    return vm->trace_bytes;
}

