#ifndef AVM_EMBED_H
#define AVM_EMBED_H

#include "avm.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AVM_EMBED_ABI_VERSION 2u

enum {
    AVM_EMBED_OK = 0,
    AVM_EMBED_ERR_INVALID_ARG = 1,
    AVM_EMBED_ERR_ALLOC = 2,
    AVM_EMBED_ERR_VM = 3
};

typedef struct AvmEmbedHandle AvmEmbedHandle;
typedef struct AvmEmbedProgram AvmEmbedProgram;

typedef struct {
    uint32_t abi_version;
    uint32_t struct_size;
    int deterministic;
    int verify_strict;
    uint64_t allowed_native_domains;
    uint64_t gas_limit;
    uint64_t heap_limit_bytes;
    uint64_t io_limit_bytes;
    uint32_t frame_limit;
    uint32_t task_quantum_steps;
    int fs_backend_kind;
    int proc_backend_kind;
    int net_backend_kind;
} AvmEmbedConfig;

typedef struct {
    int status;
    int avm_error_code;
    int exit_code;
    uint64_t gas_executed;
    uint64_t heap_used_bytes;
    uint64_t io_used_bytes;
    char message[256];
} AvmEmbedResult;

void avm_embed_config_default(AvmEmbedConfig* config);
void avm_embed_result_clear(AvmEmbedResult* result);

AvmEmbedHandle* avm_embed_open(const AvmEmbedConfig* config, AvmEmbedResult* result);
void avm_embed_close(AvmEmbedHandle* handle);

AvmVM* avm_embed_vm(AvmEmbedHandle* handle);
int avm_embed_set_argv(AvmEmbedHandle* handle, int argc, const char* const* argv, AvmEmbedResult* result);
int avm_embed_vfs_put(AvmEmbedHandle* handle, const char* path, const uint8_t* data, size_t len, AvmEmbedResult* result);
int avm_embed_vfs_get(AvmEmbedHandle* handle, const char* path, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result);
int avm_embed_vfs_snapshot(AvmEmbedHandle* handle, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result);
void avm_embed_free_bytes(uint8_t* data);
int avm_embed_program_from_obc_bytes(const uint8_t* data, size_t len, int verify_strict, AvmEmbedProgram** out_program, AvmEmbedResult* result);
void avm_embed_program_free(AvmEmbedProgram* program);
AvmProgram* avm_embed_program_view(AvmEmbedProgram* program);
int avm_embed_load_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result);
int avm_embed_load_obc_bytes(AvmEmbedHandle* handle, const uint8_t* data, size_t len, AvmEmbedResult* result);
int avm_embed_run_loaded(AvmEmbedHandle* handle, AvmEmbedResult* result);
int avm_embed_run_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result);
int avm_embed_run_obc_bytes(AvmEmbedHandle* handle, const uint8_t* data, size_t len, AvmEmbedResult* result);

#ifdef __cplusplus
}
#endif

#endif
