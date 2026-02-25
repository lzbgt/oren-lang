#ifndef AVM_CLI_POLICY_H
#define AVM_CLI_POLICY_H

#include "avm.h"
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t domain;
    uint16_t op;
} PolicyOp;

typedef struct {
    // capability config (effective)
    uint64_t allow_domains_mask;
    // budgets (effective)
    uint64_t gas;
    uint64_t timeout_ms;
    uint64_t call_depth_max;
    uint64_t mem_bytes;
    uint64_t io_bytes;
    uint64_t log_bytes;
    // trace budget (effective, output-configurable; independent from AVM_MEM_BYTES)
    uint64_t trace_bytes;
    // deterministic knobs
    int deterministic;
    uint64_t time_start_ns;
    uint64_t time_step_ns;
    uint64_t rng_seed;
    uint64_t task_quantum_steps;
    // execution mode flags
    int capsule;
    int verify_strict;
    int deny_by_default;
    int record_enabled;
    int replay_enabled;
    // output mode (hashable, path-free)
    int record_sink_kind;   // 0 none, 1 file, 2 mem
    int snapshot_out_enabled;
    // requested output surfaces (must be bound for swarm-style jobs)
    int output_state_hash;
    int output_result_hash;
    int output_trace_hash;
    int output_trace_bytes;
    int output_record_log_hex;
    // trace limits (affect trace outputs)
    uint64_t trace_step_limit; // 0 => unlimited
    // FS backend selection (affects whether host is touched)
    int fs_backend_kind; // 0 host, 1 vfs
    // PROC backend selection (affects whether host is touched)
    int proc_backend_kind; // 0 host, 1 vproc
    int proc_exit_code;    // only meaningful for vproc
    int has_proc_fixtures_hash;
    uint8_t proc_fixtures_hash[32];
    // NET backend selection (affects whether host is touched)
    int net_backend_kind; // 0 host, 1 vnet
    int has_net_fixtures_hash;
    uint8_t net_fixtures_hash[32];
} AvmExecContext;

void sha256_bytes(const uint8_t* data, size_t len, uint8_t out[32]);
void sha256_tagged_bytes8(const char tag8[8], const uint8_t* data, size_t len, uint8_t out[32]);
void sha256_job_v1(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], uint8_t out[32]);
void sha256_job_v2(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], const uint8_t exec_ctx_hash[32], uint8_t out[32]);
void sha256_job_v3(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], const uint8_t exec_ctx_hash[32], uint8_t out[32]);
void sha256_job_v4(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], const uint8_t exec_ctx_hash[32], uint8_t out[32]);
void sha256_job_v6(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], const uint8_t exec_ctx_hash[32], uint8_t out[32]);
void sha256_job_v7(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], const uint8_t exec_ctx_hash[32], uint8_t out[32]);
void ctx_hash_sha256_v8(
    const AvmExecContext* ctx,
    const char* fs_allow_prefixes_raw,
    const char* fs_mounts_read_raw,
    const char* fs_mounts_write_raw,
    uint8_t out[32]
);
void policy_hash_sha256(uint64_t used_domains_mask, const PolicyOp* ops, size_t ops_len, uint8_t out[32]);
int policy_scan_program(const AvmProgram* prog, uint64_t* used_domains_mask_out, PolicyOp** ops_out, size_t* ops_len_out);
int parse_oren_domains_mask(const char* s, uint64_t* out_mask);
int parse_domain_mask_strict(const char* s, uint64_t* out_mask);

#endif
