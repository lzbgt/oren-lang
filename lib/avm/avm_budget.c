#include "avm_internal.h"

int avm_io_charge(AvmVM* vm, uint64_t bytes, int domain, int op) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->io_budget_bytes == 0) {
        vm->io_used_bytes += bytes;
        return 1;
    }
    if (bytes > vm->io_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (io)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    if (vm->io_used_bytes + bytes > vm->io_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (io)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    vm->io_used_bytes += bytes;
    return 1;
}

int avm_log_charge(AvmVM* vm, uint64_t bytes, int domain, int op) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->log_budget_bytes == 0) {
        vm->log_used_bytes += bytes;
        return 1;
    }
    if (bytes > vm->log_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    if (vm->log_used_bytes + bytes > vm->log_budget_bytes) {
        AvmValue e = avm_err_domop(AVM_ERR_BUDGET, "budget exceeded (log)", domain, op);
        avm_abort(vm, e);
        return 0;
    }
    vm->log_used_bytes += bytes;
    return 1;
}

int avm_log_can_fit(AvmVM* vm, uint64_t bytes) {
    if (!vm) return 0;
    if (bytes == 0) return 1;
    if (vm->log_budget_bytes == 0) return 1;
    if (bytes > vm->log_budget_bytes) return 0;
    if (vm->log_used_bytes + bytes > vm->log_budget_bytes) return 0;
    return 1;
}

