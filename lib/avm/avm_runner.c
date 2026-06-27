#include "avm_runner.h"

#include <stdio.h>
#include <string.h>

static void avm_runner_set_error(AvmRunnerResult* result, int status, const char* message) {
    if (!result) return;
    avm_runner_result_clear(result);
    result->embed_result.status = status;
    snprintf(result->embed_result.message, sizeof(result->embed_result.message), "%s", message ? message : "");
}

void avm_runner_config_default(AvmRunnerConfig* config) {
    if (!config) return;
    memset(config, 0, sizeof(*config));
    config->abi_version = AVM_RUNNER_ABI_VERSION;
    config->struct_size = (uint32_t)sizeof(*config);
    avm_embed_config_default(&config->embed_config);
    config->capture_output = 1;
}

void avm_runner_result_clear(AvmRunnerResult* result) {
    if (!result) return;
    memset(result, 0, sizeof(*result));
}

void avm_runner_result_free(AvmRunnerResult* result) {
    if (!result) return;
    avm_embed_free_bytes(result->output_data);
    result->output_data = NULL;
    result->output_len = 0;
}

int avm_runner_run_obc_bytes(const uint8_t* data, size_t len, const AvmRunnerConfig* config, AvmRunnerResult* result) {
    if (result) avm_runner_result_clear(result);
    if (!data || len == 0 || !config || config->abi_version != AVM_RUNNER_ABI_VERSION ||
        config->struct_size < sizeof(AvmRunnerConfig) || config->argc < 0 ||
        (config->argc > 0 && !config->argv)) {
        avm_runner_set_error(result, AVM_EMBED_ERR_INVALID_ARG, "invalid AVM runner argument");
        return AVM_EMBED_ERR_INVALID_ARG;
    }

    AvmEmbedResult embed_result;
    avm_embed_result_clear(&embed_result);
    AvmEmbedHandle* handle = avm_embed_open(&config->embed_config, &embed_result);
    if (!handle) {
        if (result) result->embed_result = embed_result;
        return embed_result.status ? embed_result.status : AVM_EMBED_ERR_VM;
    }

    int rc = AVM_EMBED_OK;
    if (config->argc > 0) {
        rc = avm_embed_set_argv(handle, config->argc, config->argv, &embed_result);
    }
    if (rc == AVM_EMBED_OK && config->capture_output) {
        rc = avm_embed_set_output_capture(handle, 1, &embed_result);
    }
    if (rc == AVM_EMBED_OK) {
        rc = avm_embed_run_obc_bytes(handle, data, len, &embed_result);
    }
    if (rc == AVM_EMBED_OK && config->capture_output && result) {
        rc = avm_embed_output_get(handle, &result->output_data, &result->output_len, &embed_result);
    }

    if (result) result->embed_result = embed_result;
    avm_embed_close(handle);
    if (rc != AVM_EMBED_OK && result) {
        avm_runner_result_free(result);
    }
    return rc;
}
