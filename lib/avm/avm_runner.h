#ifndef AVM_RUNNER_H
#define AVM_RUNNER_H

#include "avm_embed.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AVM_RUNNER_ABI_VERSION 1u

typedef struct {
    uint32_t abi_version;
    uint32_t struct_size;
    AvmEmbedConfig embed_config;
    int capture_output;
    int argc;
    const char* const* argv;
} AvmRunnerConfig;

typedef struct {
    AvmEmbedResult embed_result;
    uint8_t* output_data;
    size_t output_len;
} AvmRunnerResult;

void avm_runner_config_default(AvmRunnerConfig* config);
void avm_runner_result_clear(AvmRunnerResult* result);
void avm_runner_result_free(AvmRunnerResult* result);
int avm_runner_run_obc_bytes(const uint8_t* data, size_t len, const AvmRunnerConfig* config, AvmRunnerResult* result);

#ifdef __cplusplus
}
#endif

#endif
