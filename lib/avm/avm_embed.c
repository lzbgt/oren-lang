#include "avm_embed.h"
#include "avm_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AVM_EMBED_HANDLE_MAGIC UINT64_C(0x41564d454d424544)

struct AvmEmbedHandle {
    uint64_t magic;
    AvmVM* vm;
};

static void avm_embed_set_message(AvmEmbedResult* result, const char* message) {
    if (!result) return;
    if (!message) message = "";
    snprintf(result->message, sizeof(result->message), "%s", message);
}

void avm_embed_result_clear(AvmEmbedResult* result) {
    if (!result) return;
    memset(result, 0, sizeof(*result));
}

void avm_embed_config_default(AvmEmbedConfig* config) {
    if (!config) return;
    memset(config, 0, sizeof(*config));
    config->abi_version = AVM_EMBED_ABI_VERSION;
    config->deterministic = 1;
    config->allowed_native_domains = (UINT64_C(1) << 0) | (UINT64_C(1) << 6);
    config->gas_limit = 5000000ull;
    config->heap_limit_bytes = 32ull * 1024ull * 1024ull;
    config->io_limit_bytes = 1024ull * 1024ull;
    config->frame_limit = 1024u;
    config->task_quantum_steps = 1000u;
    config->fs_backend_kind = 1;
    config->proc_backend_kind = 1;
    config->net_backend_kind = 1;
}

static int avm_embed_valid_handle(AvmEmbedHandle* handle) {
    return handle && handle->magic == AVM_EMBED_HANDLE_MAGIC && handle->vm;
}

static void avm_embed_apply_config(AvmVM* vm, const AvmEmbedConfig* config) {
    vm->deterministic = config->deterministic ? 1 : 0;
    vm->allowed_native_domains = config->allowed_native_domains;
    vm->gas_remaining = config->gas_limit;
    vm->heap_budget_bytes = config->heap_limit_bytes;
    vm->io_budget_bytes = config->io_limit_bytes;
    vm->frame_limit = config->frame_limit ? config->frame_limit : MAX_FRAMES;
    vm->task_quantum_steps = config->task_quantum_steps ? (int)config->task_quantum_steps : 1000;
    vm->fs_backend_kind = config->fs_backend_kind;
    vm->proc_backend_kind = config->proc_backend_kind;
    vm->net_backend_kind = config->net_backend_kind;
}

static void avm_embed_fill_from_vm(AvmVM* vm, AvmEmbedResult* result) {
    if (!result) return;
    avm_embed_result_clear(result);
    if (!vm) {
        result->status = AVM_EMBED_ERR_VM;
        result->avm_error_code = AVM_ERR_INTERNAL;
        avm_embed_set_message(result, "missing AVM VM");
        return;
    }

    result->exit_code = vm->exit_code;
    result->gas_executed = vm->gas_executed;
    result->heap_used_bytes = vm->heap_used_bytes;
    result->io_used_bytes = vm->io_used_bytes;

    if (avm_is_err_val(vm->last_error)) {
        AvmValue code = avm_map_get(vm->last_error.as.m, "code");
        AvmValue msg = avm_map_get(vm->last_error.as.m, "msg");
        result->status = AVM_EMBED_ERR_VM;
        result->avm_error_code = (code.type == AVM_VAL_INT) ? (int)code.as.i : AVM_ERR_INTERNAL;
        avm_embed_set_message(result, msg.type == AVM_VAL_STRING ? (const char*)msg.as.p : "AVM error");
        return;
    }

    if (vm->exit_code != 0) {
        result->status = AVM_EMBED_ERR_VM;
        result->avm_error_code = AVM_ERR_INTERNAL;
        avm_embed_set_message(result, "AVM exited with non-zero code");
        return;
    }

    result->status = AVM_EMBED_OK;
}

AvmEmbedHandle* avm_embed_open(const AvmEmbedConfig* config, AvmEmbedResult* result) {
    AvmEmbedConfig local;
    avm_embed_result_clear(result);
    if (!config) {
        avm_embed_config_default(&local);
        config = &local;
    } else if (config->abi_version != AVM_EMBED_ABI_VERSION) {
        if (result) {
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "unsupported AVM embed ABI version");
        }
        return NULL;
    }

    AvmEmbedHandle* handle = (AvmEmbedHandle*)calloc(1, sizeof(AvmEmbedHandle));
    if (!handle) {
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to allocate AVM embed handle");
        }
        return NULL;
    }

    handle->vm = avm_new();
    if (!handle->vm) {
        free(handle);
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to allocate AVM VM");
        }
        return NULL;
    }

    handle->magic = AVM_EMBED_HANDLE_MAGIC;
    avm_embed_apply_config(handle->vm, config);
    avm_embed_fill_from_vm(handle->vm, result);
    return handle;
}

void avm_embed_close(AvmEmbedHandle* handle) {
    if (!handle) return;
    if (handle->magic == AVM_EMBED_HANDLE_MAGIC && handle->vm) {
        avm_free(handle->vm);
    }
    handle->magic = 0;
    handle->vm = NULL;
    free(handle);
}

AvmVM* avm_embed_vm(AvmEmbedHandle* handle) {
    return avm_embed_valid_handle(handle) ? handle->vm : NULL;
}

int avm_embed_load_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !program) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid AVM embed load argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    avm_load(handle->vm, program);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_run_loaded(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid AVM embed run argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    avm_run(handle->vm);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : (handle->vm->exit_code == 0 ? AVM_EMBED_OK : AVM_EMBED_ERR_VM);
}

int avm_embed_run_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result) {
    int rc = avm_embed_load_program(handle, program, result);
    if (rc != AVM_EMBED_OK) return rc;
    return avm_embed_run_loaded(handle, result);
}
