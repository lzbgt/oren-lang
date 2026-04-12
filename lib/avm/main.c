#include "avm.h"
#include "avm_cli_disasm.h"
#include "avm_cli_dump.h"
#include "avm_cli_fs.h"
#include "avm_cli_policy.h"
#include "avm_cli_util.h"
#include "avm_cli_verify.h"
#include "avm_sig.h"
#include "sha256.h"
#include "avm_help.inc"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void sha_u8(AvmSha256Ctx* h, uint8_t v) { avm_sha256_update(h, &v, 1); }
static void sha_u32_le(AvmSha256Ctx* h, uint32_t v) {
    uint8_t b[4];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    b[2] = (uint8_t)((v >> 16) & 0xFFu);
    b[3] = (uint8_t)((v >> 24) & 0xFFu);
    avm_sha256_update(h, b, 4);
}

static uint64_t avm_effect_log_bytes_len(const AvmBytes* b) {
    if (!b || b->len <= 0) return 0;
    return (uint64_t)b->len;
}

static const char* avm_effect_record_sink(const AvmVM* vm) {
    if (!vm) return "none";
    if (vm->record_log_bytes) return "mem";
    if (vm->record_log) return "file";
    return "none";
}

static const char* avm_effect_replay_source(const AvmVM* vm) {
    if (!vm) return "none";
    if (vm->replay_log_bytes) return "mem";
    if (vm->replay_log) return "file";
    return "none";
}

static void print_effect_ledger_summary_json(FILE* out, const AvmVM* vm, uint64_t wall_elapsed_ns, uint64_t wall_limit_ms) {
    uint64_t record_bytes = vm && vm->record_log_bytes
        ? avm_effect_log_bytes_len(vm->record_log_bytes)
        : (vm ? vm->log_used_bytes : 0);
    uint64_t replay_bytes = vm && vm->replay_log_bytes
        ? avm_effect_log_bytes_len(vm->replay_log_bytes)
        : 0;
    int replayable = vm && (vm->deterministic || vm->record_log || vm->record_log_bytes || vm->replay_log || vm->replay_log_bytes);

    fprintf(out, ",\"effect_ledger_summary\":{");
    fprintf(out, "\"schema\":\"oren.effect-ledger-summary.v0\"");
    fprintf(out, ",\"backend\":\"bytecode\"");
    fprintf(out, ",\"runtime_profile\":\"avm\"");
    fprintf(out, ",\"determinism_grade\":\"%s\"", replayable ? "replayable-host" : "nondeterministic");
    fprintf(out, ",\"determinism\":{\"enabled\":%s,\"virtual_now_ns\":%llu,\"virtual_step_ns\":%llu,\"virtual_sleep_ns\":%llu}",
        (vm && vm->deterministic) ? "true" : "false",
        (unsigned long long)(vm ? vm->virtual_now_ns : 0),
        (unsigned long long)(vm ? vm->virtual_step_ns : 0),
        (unsigned long long)(vm ? vm->virtual_sleep_ns : 0));
    fprintf(out, ",\"record\":{\"enabled\":%s,\"sink\":\"%s\",\"bytes\":%llu}",
        (vm && (vm->record_log || vm->record_log_bytes)) ? "true" : "false",
        avm_effect_record_sink(vm),
        (unsigned long long)record_bytes);
    fprintf(out, ",\"replay\":{\"enabled\":%s,\"source\":\"%s\",\"bytes\":%llu,\"position\":%u}",
        (vm && (vm->replay_log || vm->replay_log_bytes)) ? "true" : "false",
        avm_effect_replay_source(vm),
        (unsigned long long)replay_bytes,
        (unsigned)(vm ? vm->replay_log_pos : 0));
    fprintf(out, ",\"budgets\":{");
    fprintf(out, "\"gas\":{\"executed\":%llu,\"remaining\":%llu,\"kind\":\"avm_opcode_cost_v0\",\"surface\":{\"schema\":\"oren.gas-surface.v0\",\"id\":\"avm_opcode_cost_v0\",\"backend\":\"bytecode\",\"unit\":\"opcode_cost\",\"unit_scope\":\"avm_canonical\",\"granularity\":\"opcode_dispatch\",\"runtime_path_aware\":true,\"cross_arch_comparable\":true,\"conversion_ready\":true,\"avm_canonical\":true}}",
        (unsigned long long)(vm ? vm->gas_executed : 0),
        (unsigned long long)(vm ? vm->gas_remaining : 0));
    fprintf(out, ",\"heap_bytes\":{\"limit\":%llu,\"used\":%llu}",
        (unsigned long long)(vm ? vm->heap_budget_bytes : 0),
        (unsigned long long)(vm ? vm->heap_used_bytes : 0));
    fprintf(out, ",\"wall_ms\":{\"limit\":%llu,\"elapsed_ns\":%llu}",
        (unsigned long long)wall_limit_ms,
        (unsigned long long)wall_elapsed_ns);
    fprintf(out, ",\"io_bytes\":{\"limit\":%llu,\"used\":%llu}",
        (unsigned long long)(vm ? vm->io_budget_bytes : 0),
        (unsigned long long)(vm ? vm->io_used_bytes : 0));
    fprintf(out, ",\"log_bytes\":{\"limit\":%llu,\"used\":%llu}",
        (unsigned long long)(vm ? vm->log_budget_bytes : 0),
        (unsigned long long)(vm ? vm->log_used_bytes : 0));
    fprintf(out, ",\"trace_bytes\":{\"enabled\":%s,\"limit\":%llu,\"used\":%llu,\"truncated\":%s}",
        (vm && vm->trace_bytes_enabled) ? "true" : "false",
        (unsigned long long)(vm ? vm->trace_budget_bytes : 0),
        (unsigned long long)(vm ? vm->trace_used_bytes : 0),
        (vm && vm->trace_bytes_truncated) ? "true" : "false");
    fprintf(out, "}}");
}

int main(int argc, char** argv) {
    const char* obc_path = NULL;
    const char* snap_in = NULL;
    const char* snap_out = NULL;
    const char* allow_domains_cli = NULL;
    const char* fs_allow_prefixes_cli = NULL;
    const char* fs_mounts_cli = NULL;
    const char* fs_mounts_read_cli = NULL;
    const char* fs_mounts_write_cli = NULL;
    const char* fs_backend_cli = NULL;
    const char* proc_backend_cli = NULL;
    const char* proc_exit_code_cli = NULL;
    const char* proc_fixtures_hex_cli = NULL;
    const char* net_backend_cli = NULL;
    const char* net_fixtures_hex_cli = NULL;
    int require_sig = 0;
    int require_cert_chain = 0;
    const char* trusted_pubkey_cli_list[16];
    int trusted_pubkey_cli_count = 0;
    const char* trusted_pubkey_hex_cli_list[16];
    int trusted_pubkey_hex_cli_count = 0;
    const char* timeout_ms_cli = NULL;
    const char* call_depth_max_cli = NULL;
    const char* task_quantum_cli = NULL;
    int prog_args_start = -1;
    int prog_argc = 0;
    char** prog_argv = NULL;
    uint64_t step_limit = 0;
    int verify_strict = 0;
    int capsule = 0;
    int deny_by_default = 0;
    int print_state_hash = 0;
    int print_result_hash = 0;
    int print_trace_hash = 0;
    int print_trace_bytes_hex = 0;
    int print_policy = 0;
    int print_policy_json = 0;
    int print_job = 0;
    int print_job_json = 0;
    int print_record_log_hex = 0;
    int print_mem_stats = 0;
    int print_rss = 0;
    int print_run_json = 0;
    int inspect = 0;
    int inspect_json = 0;
    int disasm = 0;
    int disasm_consts = 0;
    int disasm_json = 0;
    int disasm_json_consts = 0;
    int trace = 0;
    uint64_t trace_limit = 0;
    int print_stack = 0;
    int print_pause_json_flag = 0;
    int break_pc_count = 0;
    int break_pc_cap = 0;
    int* break_pcs = NULL;
    int repeat = 1;

    int i = 1;
    while (i < argc) {
        if (strcmp(argv[i], "--") == 0) {
            prog_args_start = i + 1;
            break;
        }
        if (strcmp(argv[i], "--snapshot-in") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --snapshot-in\n"); return 1; }
            snap_in = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--snapshot-out") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --snapshot-out\n"); return 1; }
            snap_out = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--step-limit") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --step-limit\n"); return 1; }
            step_limit = strtoull(argv[i + 1], NULL, 10);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--timeout-ms") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --timeout-ms\n"); return 1; }
            timeout_ms_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--call-depth-max") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --call-depth-max\n"); return 1; }
            call_depth_max_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--task-quantum") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --task-quantum\n"); return 1; }
            task_quantum_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--print-state-hash") == 0) {
            print_state_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-result-hash") == 0) {
            print_result_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-trace-hash") == 0) {
            print_trace_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-trace-bytes-hex") == 0) {
            print_trace_bytes_hex = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-record-log-hex") == 0) {
            print_record_log_hex = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-mem-stats") == 0) {
            print_mem_stats = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-rss") == 0) {
            print_rss = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-run-json") == 0) {
            print_run_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-policy") == 0) {
            print_policy = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-policy-json") == 0) {
            print_policy_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-job") == 0) {
            print_job = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-job-json") == 0) {
            print_job_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--inspect") == 0) {
            inspect = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--inspect-json") == 0) {
            inspect_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--verify-strict") == 0) {
            verify_strict = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--capsule") == 0 || strcmp(argv[i], "--untrusted") == 0) {
            capsule = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--deny-by-default") == 0) {
            deny_by_default = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--allow-domains") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --allow-domains\n"); return 1; }
            allow_domains_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-allow-prefixes") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-allow-prefixes\n"); return 1; }
            fs_allow_prefixes_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts\n"); return 1; }
            fs_mounts_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts-read") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts-read\n"); return 1; }
            fs_mounts_read_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts-write") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts-write\n"); return 1; }
            fs_mounts_write_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-backend\n"); return 1; }
            fs_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-backend\n"); return 1; }
            proc_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-exit-code") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-exit-code\n"); return 1; }
            proc_exit_code_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-fixtures-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-fixtures-hex\n"); return 1; }
            proc_fixtures_hex_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--net-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --net-backend\n"); return 1; }
            net_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--net-fixtures-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --net-fixtures-hex\n"); return 1; }
            net_fixtures_hex_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--require-sig") == 0) {
            require_sig = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--require-cert-chain") == 0) {
            require_sig = 1;
            require_cert_chain = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trusted-pubkey") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trusted-pubkey\n"); return 1; }
            if (trusted_pubkey_cli_count >= 16) { fprintf(stderr, "Too many --trusted-pubkey entries (cap=16)\n"); return 1; }
            trusted_pubkey_cli_list[trusted_pubkey_cli_count++] = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--trusted-pubkey-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trusted-pubkey-hex\n"); return 1; }
            if (trusted_pubkey_hex_cli_count >= 16) { fprintf(stderr, "Too many --trusted-pubkey-hex entries (cap=16)\n"); return 1; }
            trusted_pubkey_hex_cli_list[trusted_pubkey_hex_cli_count++] = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--disasm") == 0) {
            disasm = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-consts") == 0) {
            disasm = 1;
            disasm_consts = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-json") == 0) {
            disasm = 1;
            disasm_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-consts-json") == 0) {
            disasm = 1;
            disasm_json = 1;
            disasm_json_consts = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trace") == 0) {
            trace = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trace-limit") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trace-limit\n"); return 1; }
            trace = 1;
            trace_limit = strtoull(argv[i + 1], NULL, 10);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--print-stack") == 0) {
            print_stack = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-pause-json") == 0) {
            print_pause_json_flag = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--breakpc") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --breakpc\n"); return 1; }
            long pc = strtol(argv[i + 1], NULL, 10);
            if (pc < 0 || pc > INT_MAX) { fprintf(stderr, "Invalid --breakpc value\n"); return 1; }
            if (break_pc_count >= break_pc_cap) {
                int nc = break_pc_cap ? break_pc_cap * 2 : 8;
                int* np = (int*)realloc(break_pcs, sizeof(int) * (size_t)nc);
                if (!np) { fprintf(stderr, "OOM\n"); return 1; }
                break_pcs = np;
                break_pc_cap = nc;
            }
            break_pcs[break_pc_count++] = (int)pc;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--repeat") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --repeat\n"); return 1; }
            long n = strtol(argv[i + 1], NULL, 10);
            if (n <= 0 || n > 100000000) { fprintf(stderr, "Invalid --repeat value\n"); return 1; }
            repeat = (int)n;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fputs(AVM_HELP_TEXT, stdout);
            free(break_pcs);
            return 0;
        }
        if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown arg: %s\n", argv[i]);
            return 1;
        }
        obc_path = argv[i];
        i++;
    }

    if (!obc_path) {
        fputs(AVM_HELP_TEXT, stdout);
        free(break_pcs);
        return 1;
    }
    if (prog_args_start >= 0 && prog_args_start <= argc) {
        prog_argc = argc - prog_args_start;
        prog_argv = argv + prog_args_start;
    }
    if (repeat > 1 && (snap_in || snap_out)) {
        fprintf(stderr, "--repeat is not compatible with --snapshot-in/--snapshot-out (for now)\n");
        free(break_pcs);
        return 1;
    }
    size_t len;
    uint8_t* data = read_file(obc_path, &len);
    if (!data) {
        printf("Failed to read file\n");
        free(break_pcs);
        return 1;
    }

    // Signature verification (rolling, opt-in for host CLI).
    const char* require_sig_env = getenv("AVM_REQUIRE_SIG");
    if (require_sig_env && require_sig_env[0] && require_sig_env[0] != '0') require_sig = 1;
    const char* require_chain_env = getenv("AVM_REQUIRE_CERT_CHAIN");
    if (require_chain_env && require_chain_env[0] && require_chain_env[0] != '0') { require_sig = 1; require_cert_chain = 1; }

    uint8_t trusted_pks[16][32];
    size_t trusted_pk_count = 0;

    // Collect trusted keys from CLI.
    for (int k = 0; k < trusted_pubkey_hex_cli_count; k++) {
        if (!add_trusted_pubkey_hex_list(trusted_pks, &trusted_pk_count, 16, trusted_pubkey_hex_cli_list[k], "--trusted-pubkey-hex")) {
            free(break_pcs);
            free(data);
            return 1;
        }
    }
    for (int k = 0; k < trusted_pubkey_cli_count; k++) {
        const char* path = trusted_pubkey_cli_list[k];
        if (!path || !path[0]) continue;
        size_t pklen = 0;
        uint8_t* pkb = read_file(path, &pklen);
        if (!pkb || pklen != 32) {
            fprintf(stderr, "Invalid --trusted-pubkey (expected 32 raw bytes)\n");
            free(break_pcs);
            free(data);
            free(pkb);
            return 1;
        }
        if (!add_trusted_pubkey_32(trusted_pks, &trusted_pk_count, 16, pkb)) {
            fprintf(stderr, "Too many trusted pubkeys (cap=16)\n");
            free(break_pcs);
            free(data);
            free(pkb);
            return 1;
        }
        free(pkb);
    }

    // Also accept env-provided trusted root(s) (single 64-hex or comma-separated list).
    const char* env_pk_hex = getenv("AVM_TRUSTED_PUBKEY_HEX");
    if (env_pk_hex && env_pk_hex[0]) {
        if (!add_trusted_pubkey_hex_list(trusted_pks, &trusted_pk_count, 16, env_pk_hex, "AVM_TRUSTED_PUBKEY_HEX")) {
            free(break_pcs);
            free(data);
            return 1;
        }
    }

    if (require_sig) {
        char emsg[256];
        const uint8_t* pkptr = (trusted_pk_count > 0) ? (const uint8_t*)trusted_pks : NULL;
        size_t pkcount = (trusted_pk_count > 0) ? trusted_pk_count : 0;
        int require_chain = require_cert_chain ? 1 : 0;
        if (!avm_obc_verify_signature_with_chain_any(data, len, pkptr, pkcount, require_chain, emsg, sizeof(emsg))) {
            fprintf(stderr, "AVM signature verify failed: %s\n", emsg);
            free(data);
            free(break_pcs);
            return 1;
        }
    }

    // Signature verified above (if requested).

    // Verifier (rolling): reject malformed bytecode early to avoid crashes/hangs.
    // Disable only for debugging with AVM_VERIFY=0.
    const char* verify_env = getenv("AVM_VERIFY");
    int verify = 1;
    if (verify_env && verify_env[0] == '0') verify = 0;

    // Strict verification (rolling): reject legacy/native-bypass forms early.
    // Enable with either CLI `--verify-strict` or `AVM_VERIFY_STRICT=1`.
    const char* verify_strict_env = getenv("AVM_VERIFY_STRICT");
    if (verify_strict_env && verify_strict_env[0] && verify_strict_env[0] != '0') verify_strict = 1;

    // Capsule mode (rolling): safe defaults for running untrusted `.obc`.
    // Enable with `--capsule` / `--untrusted` or `AVM_CAPSULE=1`.
    const char* capsule_env = getenv("AVM_CAPSULE");
    const char* capsule_env_oren = getenv("OREN_CAPSULE");
    if (env_truthy(capsule_env) || env_truthy(capsule_env_oren)) capsule = 1;
    if (capsule) {
        verify_strict = 1;
        deny_by_default = 1;
    }

    // Deny-by-default mode (rolling): when AVM_ALLOW_DOMAINS is unset/empty, deny all non-CORE domains.
    const char* deny_env = getenv("AVM_DENY_BY_DEFAULT");
    if (deny_env && deny_env[0] && deny_env[0] != '0') deny_by_default = 1;

    const char* record_env0 = getenv("AVM_RECORD_LOG");
    const char* replay_env0 = getenv("AVM_REPLAY_LOG");
    if (repeat > 1 && ((record_env0 && record_env0[0]) || (replay_env0 && replay_env0[0]))) {
        fprintf(stderr, "--repeat is not compatible with AVM_RECORD_LOG/AVM_REPLAY_LOG (use AVM_RECORD_MEM/AVM_REPLAY_LOG_HEX)\n");
        free(data);
        free(break_pcs);
        return 1;
    }

    int exit_code = 0;
    for (int iter = 0; iter < repeat; iter++) {
        // Parse OBC
        // Header: CD 0E
        if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) {
            printf("Invalid magic\n");
            free(data);
            free(break_pcs);
            return 1;
        }

        // Const count (u16)
        size_t pos = 2;
        if (pos + 2 > len) {
            fprintf(stderr, "Invalid constant pool\n");
            free(data);
            free(break_pcs);
            return 1;
        }
        uint16_t n_consts = data[pos] | (data[pos + 1] << 8);
        pos += 2;

        AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * n_consts);
        if (!consts && n_consts > 0) {
            fprintf(stderr, "OOM\n");
            free(data);
            free(break_pcs);
            return 1;
        }
        for (int ci = 0; ci < n_consts; ci++) consts[ci].type = AVM_VAL_NIL;
        for (int ci = 0; ci < n_consts; ci++) {
            if (pos >= len) {
                fprintf(stderr, "Invalid constant pool\n");
                free_constant_pool(consts, (size_t)ci);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            uint8_t type = data[pos++];
            switch (type) {
                case 0: { // NIL
                    consts[ci].type = AVM_VAL_NIL;
                    break;
                }
                case 1: { // INT
                    if (pos + 8 > len) {
                        fprintf(stderr, "Invalid INT const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    int64_t val = 0;
                    for (int k = 0; k < 8; k++) {
                        val |= (int64_t)data[pos++] << (k * 8);
                    }
                    consts[ci].type = AVM_VAL_INT;
                    consts[ci].as.i = val;
                    break;
                }
                case 2: { // BOOL (rolling): u8 0|1
                    if (pos + 1 > len) {
                        fprintf(stderr, "Invalid BOOL const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    uint8_t b = data[pos++];
                    consts[ci].type = AVM_VAL_BOOL;
                    consts[ci].as.i = (b != 0) ? 1 : 0;
                    break;
                }
                case 3: { // FLOAT (rolling): IEEE-754 f64 bits as u64 little-endian
                    if (pos + 8 > len) {
                        fprintf(stderr, "Invalid FLOAT const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    uint64_t bits = 0;
                    for (int k = 0; k < 8; k++) {
                        bits |= (uint64_t)data[pos++] << (k * 8);
                    }
                    double d = 0.0;
                    memcpy(&d, &bits, sizeof(bits));
                    consts[ci].type = AVM_VAL_FLOAT;
                    consts[ci].as.f = d;
                    break;
                }
                case 4: { // STRING
                    if (pos + 2 > len) {
                        fprintf(stderr, "Invalid STRING const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
                    pos += 2;
                    if (pos + slen > len) {
                        fprintf(stderr, "Invalid STRING const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    char* s = (char*)malloc((size_t)slen + 1);
                    if (!s) {
                        fprintf(stderr, "OOM\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    for (uint16_t k = 0; k < slen; k++) s[k] = (char)data[pos++];
                    s[slen] = 0;
                    consts[ci].type = AVM_VAL_STRING;
                    consts[ci].as.p = s;
                    break;
                }
                case 8: { // BYTES (rolling): u32 len + raw bytes
                    if (pos + 4 > len) {
                        fprintf(stderr, "Invalid BYTES const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    uint32_t blen = (uint32_t)data[pos] | ((uint32_t)data[pos + 1] << 8) | ((uint32_t)data[pos + 2] << 16) | ((uint32_t)data[pos + 3] << 24);
                    pos += 4;
                    if (blen > (uint32_t)INT_MAX || pos + blen > len) {
                        fprintf(stderr, "Invalid BYTES const\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
                    if (!b) {
                        fprintf(stderr, "OOM\n");
                        free_constant_pool(consts, (size_t)ci);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    b->len = (int)blen;
                    b->capacity = (int)blen;
                    b->data = NULL;
                    if (blen > 0) {
                        b->data = (uint8_t*)malloc((size_t)blen);
                        if (!b->data) {
                            fprintf(stderr, "OOM\n");
                            free(b);
                            free_constant_pool(consts, (size_t)ci);
                            free(consts);
                            free(data);
                            free(break_pcs);
                            return 1;
                        }
                        memcpy(b->data, data + pos, blen);
                    }
                    pos += blen;
                    consts[ci].type = AVM_VAL_BYTES;
                    consts[ci].as.b = b;
                    break;
                }
                default:
                    fprintf(stderr, "Invalid constant type: %u\n", (unsigned)type);
                    free_constant_pool(consts, (size_t)ci);
                    free(consts);
                    free(data);
                    free(break_pcs);
                    return 1;
            }
        }

        // Code
        uint8_t* code = data + pos;
        size_t code_len = len - pos;

        AvmProgram prog;
        prog.code = code;
        prog.code_len = code_len;
        prog.constants = consts;
        prog.const_count = n_consts;

        if (verify && iter == 0) {
            VerifyResult vr = verify_program(&prog, verify_strict);
            if (!vr.ok) {
                fprintf(stderr, "AVM verify failed: %s\n", vr.msg);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            if (print_policy || print_policy_json || print_job || print_job_json || inspect || inspect_json) {
                uint64_t mask = 0;
                PolicyOp* ops = NULL;
                size_t ops_len = 0;
                if (!policy_scan_program(&prog, &mask, &ops, &ops_len)) {
                    fprintf(stderr, "AVM policy scan failed\n");
                    free_constant_pool(consts, n_consts);
                    free(consts);
                    free(data);
                    free(break_pcs);
                    return 1;
                }
                uint8_t phash[32];
                char phash_hex[65];
                policy_hash_sha256(mask, ops, ops_len, phash);
                avm_sha256_hex(phash, phash_hex);

                if (print_job || print_job_json) {
                    // program_hash: hash of the full .obc file bytes (including header)
                    uint8_t prog_hash[32];
                    char prog_hex[65];
                    sha256_bytes(data, len, prog_hash);
                    avm_sha256_hex(prog_hash, prog_hex);

                    // input_hash: hash of explicit inputs (args + snapshot + replay log, if any)
                    AvmSha256Ctx ih;
                    avm_sha256_init(&ih);
                    const uint8_t itag[8] = { 'A','V','M','I','N','P','0','1' };
                    avm_sha256_update(&ih, itag, 8);

                    // args (as passed after `--`)
                    sha_u32_le(&ih, (uint32_t)prog_argc);
                    for (int ai = 0; ai < prog_argc; ai++) {
                        const char* s = prog_argv ? prog_argv[ai] : NULL;
                        size_t sl = s ? strlen(s) : 0;
                        sha_u32_le(&ih, (uint32_t)sl);
                        if (s && sl > 0) avm_sha256_update(&ih, (const uint8_t*)s, sl);
                    }

                    // snapshot input (hash file contents)
                    uint8_t snap_hash[32];
                    int has_snap_hash = 0;
                    if (snap_in && snap_in[0]) {
                        size_t slen = 0;
                        uint8_t* sdata = read_file(snap_in, &slen);
                        if (sdata) {
                            sha256_tagged_bytes8("AVMSNAP1", sdata, slen, snap_hash);
                            has_snap_hash = 1;
                            free(sdata);
                        }
                    }
                    sha_u8(&ih, (uint8_t)(has_snap_hash ? 1 : 0));
                    if (has_snap_hash) avm_sha256_update(&ih, snap_hash, 32);

                    // replay log input (hash content if configured)
                    uint8_t rlog_hash[32];
                    int has_rlog_hash = 0;
                    const char* replay_env = getenv("AVM_REPLAY_LOG");
                    const char* replay_hex_env = getenv("AVM_REPLAY_LOG_HEX");
                    if (replay_env && replay_env[0]) {
                        size_t rlen = 0;
                        uint8_t* rdata = read_file(replay_env, &rlen);
                        if (rdata) {
                            sha256_tagged_bytes8("AVMRLOG1", rdata, rlen, rlog_hash);
                            has_rlog_hash = 1;
                            free(rdata);
                        }
                    } else if (replay_hex_env && replay_hex_env[0]) {
                        AvmBytes* b = bytes_from_hex(replay_hex_env);
                        if (b) {
                            sha256_tagged_bytes8("AVMRLOG1", b->data, (size_t)b->len, rlog_hash);
                            has_rlog_hash = 1;
                            free(b->data);
                            free(b);
                        }
                    }
                    sha_u8(&ih, (uint8_t)(has_rlog_hash ? 1 : 0));
                    if (has_rlog_hash) avm_sha256_update(&ih, rlog_hash, 32);

                    uint8_t input_hash[32];
                    char input_hex[65];
                    avm_sha256_final(&ih, input_hash);
                    avm_sha256_hex(input_hash, input_hex);

                    // execution context hash: bind budgets + capability allowlists + determinism knobs.
                    AvmExecContext ectx;
                    memset(&ectx, 0, sizeof(ectx));
                    ectx.capsule = capsule ? 1 : 0;
                    ectx.verify_strict = verify_strict ? 1 : 0;
                    ectx.deny_by_default = deny_by_default ? 1 : 0;
                    ectx.record_enabled = 0;
                    ectx.replay_enabled = has_rlog_hash ? 1 : 0;
                    ectx.snapshot_out_enabled = (snap_out && snap_out[0]) ? 1 : 0;
                    ectx.record_sink_kind = 0;
                    ectx.output_state_hash = print_state_hash ? 1 : 0;
                    ectx.output_result_hash = print_result_hash ? 1 : 0;
                    ectx.output_trace_hash = print_trace_hash ? 1 : 0;
                    ectx.output_trace_bytes = print_trace_bytes_hex ? 1 : 0;
                    ectx.output_record_log_hex = print_record_log_hex ? 1 : 0;
                    // Reuse --trace-limit as a generic step limit for trace hashing/bytes if provided (0 => unlimited).
                    ectx.trace_step_limit = trace_limit;
                    ectx.trace_bytes = 0;
                    ectx.fs_backend_kind = 0;
                    ectx.proc_backend_kind = 0;
                    ectx.proc_exit_code = 0;
                    ectx.has_proc_fixtures_hash = 0;
                    memset(ectx.proc_fixtures_hash, 0, 32);
                    ectx.net_backend_kind = 0;
                    ectx.has_net_fixtures_hash = 0;
                    memset(ectx.net_fixtures_hash, 0, 32);

                    // record enabled if any record sink is configured (file or mem).
                    const char* rec_env = getenv("AVM_RECORD_LOG");
                    const char* rec_mem_env = getenv("AVM_RECORD_MEM");
                    if ((rec_env && rec_env[0]) || (rec_mem_env && rec_mem_env[0] && rec_mem_env[0] != '0')) ectx.record_enabled = 1;
                    if (rec_env && rec_env[0]) ectx.record_sink_kind = 1;
                    else if (rec_mem_env && rec_mem_env[0] && rec_mem_env[0] != '0') ectx.record_sink_kind = 2;

                    // deterministic knobs (from env; capsule does not force determinism)
                    const char* det_env = getenv("AVM_DETERMINISTIC");
                    if (det_env && det_env[0] && det_env[0] != '0') ectx.deterministic = 1;
                    const char* t0_env = getenv("AVM_TIME_START_NS");
                    if (t0_env && t0_env[0]) ectx.time_start_ns = strtoull(t0_env, NULL, 10);
                    const char* step_env = getenv("AVM_TIME_STEP_NS");
                    if (step_env && step_env[0]) ectx.time_step_ns = strtoull(step_env, NULL, 10);
                    const char* seed_env = getenv("AVM_RNG_SEED");
                    if (seed_env && seed_env[0]) ectx.rng_seed = strtoull(seed_env, NULL, 10);
                    const char* tq_env = task_quantum_cli ? task_quantum_cli : getenv("AVM_TASK_QUANTUM");
                    if (!tq_env || !tq_env[0]) tq_env = getenv("AVM_TASK_QUANTUM_STEPS");
                    uint64_t tq = 0;
                    if (tq_env && tq_env[0]) tq = strtoull(tq_env, NULL, 10);
                    if (tq == 0) tq = 1000ull; // default semantics
                    if (tq > 1000000000ull) tq = 1000000000ull; // sanity cap
                    ectx.task_quantum_steps = tq;

                    // budgets (effective): capsule applies defaults only if env is unset.
                    const char* gas_env = getenv("AVM_GAS");
                    const char* timeout_env = timeout_ms_cli ? timeout_ms_cli : getenv("AVM_TIMEOUT_MS");
                    const char* depth_env = call_depth_max_cli ? call_depth_max_cli : getenv("AVM_CALL_DEPTH_MAX");
                    const char* mem_env = getenv("AVM_MEM_BYTES");
                    const char* io_env = getenv("AVM_IO_BYTES");
                    const char* log_env = getenv("AVM_LOG_BYTES");
                    const char* trace_env = getenv("AVM_TRACE_BYTES");

                    if (gas_env && gas_env[0]) ectx.gas = strtoull(gas_env, NULL, 10);
                    if (timeout_env && timeout_env[0]) ectx.timeout_ms = strtoull(timeout_env, NULL, 10);
                    // Call depth max is effectively bounded by MAX_FRAMES (fixed storage in AvmVM).
                    if (depth_env && depth_env[0]) {
                        uint64_t d = strtoull(depth_env, NULL, 10);
                        if (d == 0 || d > (uint64_t)MAX_FRAMES) ectx.call_depth_max = (uint64_t)MAX_FRAMES;
                        else ectx.call_depth_max = d;
                    } else {
                        ectx.call_depth_max = (uint64_t)MAX_FRAMES;
                    }
                    if (mem_env && mem_env[0]) ectx.mem_bytes = strtoull(mem_env, NULL, 10);
                    if (io_env && io_env[0]) ectx.io_bytes = strtoull(io_env, NULL, 10);
                    if (log_env && log_env[0]) ectx.log_bytes = strtoull(log_env, NULL, 10);
                    if (trace_env && trace_env[0]) ectx.trace_bytes = strtoull(trace_env, NULL, 10);
                    if (capsule) {
                        if ((!gas_env || !gas_env[0]) && ectx.gas == 0) ectx.gas = 5000000ull;
                        if ((!timeout_env || !timeout_env[0]) && ectx.timeout_ms == 0) ectx.timeout_ms = 2000ull;
                        if ((!mem_env || !mem_env[0]) && ectx.mem_bytes == 0) ectx.mem_bytes = 32ull * 1024ull * 1024ull;
                        if ((!io_env || !io_env[0]) && ectx.io_bytes == 0) ectx.io_bytes = 1024ull * 1024ull;
                        if ((!log_env || !log_env[0]) && ectx.log_bytes == 0) ectx.log_bytes = 1024ull * 1024ull;
                        // Keep trace-bytes default isolated and explicit: only default if trace output is requested.
                        if (ectx.output_trace_bytes && (!trace_env || !trace_env[0]) && ectx.trace_bytes == 0) {
                            ectx.trace_bytes = 1024ull * 1024ull;
                        }
                    }

                    // FS backend selection (host vs virtual). Used for job hashing because it changes whether the host is touched.
                    const char* fs_backend_s = fs_backend_cli ? fs_backend_cli : getenv("AVM_FS_BACKEND");
                    if (capsule && (!fs_backend_s || !fs_backend_s[0])) fs_backend_s = "vfs";
                    if (!parse_fs_backend_kind(fs_backend_s, &ectx.fs_backend_kind)) {
                        fprintf(stderr, "Invalid fs backend (expected 'host' or 'vfs')\n");
                        free(ops);
                        free_constant_pool(consts, n_consts);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }

                    // PROC backend selection (host vs virtual). Used for job hashing because it changes whether the host is touched.
                    const char* proc_backend_s = proc_backend_cli ? proc_backend_cli : getenv("AVM_PROC_BACKEND");
                    if (capsule && (!proc_backend_s || !proc_backend_s[0])) proc_backend_s = "vproc";
                    if (!parse_proc_backend_kind(proc_backend_s, &ectx.proc_backend_kind)) {
                        fprintf(stderr, "Invalid proc backend (expected 'host' or 'vproc')\n");
                        free(ops);
                        free_constant_pool(consts, n_consts);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    const char* proc_ec_s = proc_exit_code_cli ? proc_exit_code_cli : getenv("AVM_PROC_EXIT_CODE");
                    if (proc_ec_s && proc_ec_s[0]) ectx.proc_exit_code = (int)strtoll(proc_ec_s, NULL, 10);
                    const char* proc_fixtures_hex = proc_fixtures_hex_cli ? proc_fixtures_hex_cli : getenv("AVM_PROC_FIXTURES_HEX");
                    if (proc_fixtures_hex && proc_fixtures_hex[0]) {
                        AvmBytes* b = bytes_from_hex(proc_fixtures_hex);
                        if (!b) {
                            fprintf(stderr, "Invalid proc fixtures hex\n");
                            free(ops);
                            free_constant_pool(consts, n_consts);
                            free(consts);
                            free(data);
                            free(break_pcs);
                            return 1;
                        }
                        sha256_tagged_bytes8("AVMPRCF1", b->data, (size_t)b->len, ectx.proc_fixtures_hash);
                        ectx.has_proc_fixtures_hash = 1;
                        free(b->data);
                        free(b);
                    }

                    // NET backend selection (host vs virtual).
                    const char* net_backend_s = net_backend_cli ? net_backend_cli : getenv("AVM_NET_BACKEND");
                    if (capsule && (!net_backend_s || !net_backend_s[0])) net_backend_s = "vnet";
                    if (!parse_net_backend_kind(net_backend_s, &ectx.net_backend_kind)) {
                        fprintf(stderr, "Invalid net backend (expected 'host' or 'vnet')\n");
                        free(ops);
                        free_constant_pool(consts, n_consts);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }
                    const char* net_fixtures_hex = net_fixtures_hex_cli ? net_fixtures_hex_cli : getenv("AVM_NET_FIXTURES_HEX");
                    if (net_fixtures_hex && net_fixtures_hex[0]) {
                        AvmBytes* b = bytes_from_hex(net_fixtures_hex);
                        if (!b) {
                            fprintf(stderr, "Invalid net fixtures hex\n");
                            free(ops);
                            free_constant_pool(consts, n_consts);
                            free(consts);
                            free(data);
                            free(break_pcs);
                            return 1;
                        }
                        sha256_tagged_bytes8("AVMNETF1", b->data, (size_t)b->len, ectx.net_fixtures_hash);
                        ectx.has_net_fixtures_hash = 1;
                        free(b->data);
                        free(b);
                    }

                    // capability allowlist (effective): bind the *effective* mask.
                    // If deny-by-default is enabled and allowlist is absent, default to CORE+EXIT.
                    const char* domains_s = allow_domains_cli ? allow_domains_cli : getenv("AVM_ALLOW_DOMAINS");
                    uint64_t parsed_mask = 0;
                    const char* oren_domains_s = NULL;
                    if ((!domains_s || !domains_s[0]) && capsule) {
                        // Bridge Oren native capsule env into AVM when `avm` is spawned as a subprocess.
                        // Oren uses names; AVM uses numeric domains.
                        oren_domains_s = getenv("OREN_CAP_ALLOW_DOMAINS");
                    }

                    int has_allow = (domains_s && domains_s[0]) ? 1 : 0;
                    if (!has_allow && oren_domains_s && oren_domains_s[0]) has_allow = 1;

                    int ok = 1;
                    if (domains_s && domains_s[0]) {
                        ok = parse_domain_mask_strict(domains_s, &parsed_mask);
                    } else if (oren_domains_s && oren_domains_s[0]) {
                        ok = parse_oren_domains_mask(oren_domains_s, &parsed_mask);
                        // Always include CORE+EXIT for bootstrap usability and safety.
                        parsed_mask |= (1ULL << 0) | (1ULL << 6);
                    } else {
                        // no allowlist string => parsed_mask=0 (caller decides semantics)
                        parsed_mask = 0;
                    }

                    if (!ok) {
                        fprintf(stderr, "Invalid allow domains list\n");
                        free(ops);
                        free_constant_pool(consts, n_consts);
                        free(consts);
                        free(data);
                        free(break_pcs);
                        return 1;
                    }

                    if (deny_by_default && !has_allow) ectx.allow_domains_mask = (1ULL << 0) | (1ULL << 6);
                    else ectx.allow_domains_mask = parsed_mask;

                    const char* fs_allow_s = fs_allow_prefixes_cli ? fs_allow_prefixes_cli : getenv("AVM_FS_ALLOW_PREFIXES");
                    if ((!fs_allow_s || !fs_allow_s[0]) && capsule) {
                        fs_allow_s = getenv("OREN_FS_ALLOW_PREFIXES");
                        if (!fs_allow_s || !fs_allow_s[0]) fs_allow_s = getenv("OREN_FS_ALLOW_READ_PREFIXES");
                        if (!fs_allow_s || !fs_allow_s[0]) fs_allow_s = getenv("OREN_FS_ALLOW_WRITE_PREFIXES");
                    }
                    const char* fs_m_read_s = fs_mounts_read_cli ? fs_mounts_read_cli : getenv("AVM_FS_MOUNTS_READ");
                    const char* fs_m_write_s = fs_mounts_write_cli ? fs_mounts_write_cli : getenv("AVM_FS_MOUNTS_WRITE");
                    const char* fs_m_both_s = fs_mounts_cli ? fs_mounts_cli : getenv("AVM_FS_MOUNTS");
                    if ((!fs_m_read_s || !fs_m_read_s[0]) && fs_m_both_s && fs_m_both_s[0]) fs_m_read_s = fs_m_both_s;
                    if ((!fs_m_write_s || !fs_m_write_s[0]) && fs_m_both_s && fs_m_both_s[0]) fs_m_write_s = fs_m_both_s;
                    if (capsule) {
                        if ((!fs_m_read_s || !fs_m_read_s[0])) {
                            fs_m_read_s = getenv("OREN_FS_MOUNTS_READ");
                            if (!fs_m_read_s || !fs_m_read_s[0]) fs_m_read_s = getenv("OREN_FS_MOUNTS");
                        }
                        if ((!fs_m_write_s || !fs_m_write_s[0])) {
                            fs_m_write_s = getenv("OREN_FS_MOUNTS_WRITE");
                            if (!fs_m_write_s || !fs_m_write_s[0]) fs_m_write_s = getenv("OREN_FS_MOUNTS");
                        }
                    }
                    uint8_t ctx_hash[32];
                    char ctx_hex[65];
                    ctx_hash_sha256_v8(&ectx, fs_allow_s, fs_m_read_s, fs_m_write_s, ctx_hash);
                    avm_sha256_hex(ctx_hash, ctx_hex);

                    uint8_t job_hash[32];
                    char job_hex[65];
                    sha256_job_v7(prog_hash, phash, input_hash, ctx_hash, job_hash);
                    avm_sha256_hex(job_hash, job_hex);

                    if (print_job_json) {
                        printf("{\"schema\":\"avm.job.v7\",\"job_hash_sha256\":\"%s\",\"program_hash_sha256\":\"%s\",\"input_hash_sha256\":\"%s\",\"exec_hash_sha256\":\"%s\",\"policy\":{",
                            job_hex, prog_hex, input_hex, ctx_hex);
                        printf("\"schema\":\"avm.policy.v1\",\"used_domains_mask\":\"0x%016llx\",\"policy_hash_sha256\":\"%s\",\"ops\":[",
                            (unsigned long long)mask, phash_hex);
                        for (size_t j = 0; j < ops_len; j++) {
                            if (j) printf(",");
                            printf("{\"domain\":%u,\"op\":%u}", (unsigned)ops[j].domain, (unsigned)ops[j].op);
                        }
                        printf("]}");

                        // inputs section (explicit inputs only)
                        printf(",\"inputs\":{\"args\":[");
                        for (int ai = 0; ai < prog_argc; ai++) {
                            if (ai) printf(",");
                            const char* s = prog_argv ? prog_argv[ai] : "";
                            // Minimal JSON escaping (quotes + backslash)
                            printf("\"");
                            for (const char* p = s; *p; p++) {
                                if (*p == '\\' || *p == '\"') { printf("\\\\%c", *p); }
                                else if (*p == '\n') { printf("\\\\n"); }
                                else if (*p == '\r') { printf("\\\\r"); }
                                else if (*p == '\t') { printf("\\\\t"); }
                                else { printf("%c", *p); }
                            }
                            printf("\"");
                        }
                        printf("]");
                        if (has_snap_hash) {
                            char sh[65];
                            avm_sha256_hex(snap_hash, sh);
                            printf(",\"snapshot_in_sha256\":\"%s\"", sh);
                        }
                        if (has_rlog_hash) {
                            char rh[65];
                            avm_sha256_hex(rlog_hash, rh);
                            printf(",\"replay_log_sha256\":\"%s\"", rh);
                        }
                        printf("}");

                        // execution context (bound by exec_hash_sha256)
                        printf(",\"exec\":{");
                        printf("\"capsule\":%s", ectx.capsule ? "true" : "false");
                        printf(",\"verify_strict\":%s", ectx.verify_strict ? "true" : "false");
                        printf(",\"deny_by_default\":%s", ectx.deny_by_default ? "true" : "false");
                        printf(",\"record_enabled\":%s", ectx.record_enabled ? "true" : "false");
                        if (ectx.record_sink_kind == 1) printf(",\"record_sink\":\"file\"");
                        else if (ectx.record_sink_kind == 2) printf(",\"record_sink\":\"mem\"");
                        else printf(",\"record_sink\":\"none\"");
                        printf(",\"replay_enabled\":%s", ectx.replay_enabled ? "true" : "false");
                        printf(",\"snapshot_out_enabled\":%s", ectx.snapshot_out_enabled ? "true" : "false");
                        printf(",\"outputs\":{\"state_hash\":%s,\"result_hash\":%s,\"trace_hash\":%s,\"trace_bytes\":%s,\"record_log_hex\":%s}",
                            ectx.output_state_hash ? "true" : "false",
                            ectx.output_result_hash ? "true" : "false",
                            ectx.output_trace_hash ? "true" : "false",
                            ectx.output_trace_bytes ? "true" : "false",
                            ectx.output_record_log_hex ? "true" : "false");
                        printf(",\"trace\":{\"step_limit\":%llu,\"trace_bytes\":%llu}",
                            (unsigned long long)ectx.trace_step_limit,
                            (unsigned long long)ectx.trace_bytes);
                        printf(",\"allow_domains_mask\":\"0x%016llx\"", (unsigned long long)ectx.allow_domains_mask);
                        if (fs_allow_s && fs_allow_s[0]) {
                            // raw string for now (rolling); hash uses normalized tokenization.
                            printf(",\"fs_allow_prefixes\":\"");
                            for (const char* p = fs_allow_s; *p; p++) {
                                if (*p == '\\' || *p == '\"') { printf("\\\\%c", *p); }
                                else if (*p == '\n') { printf("\\\\n"); }
                                else if (*p == '\r') { printf("\\\\r"); }
                                else if (*p == '\t') { printf("\\\\t"); }
                                else { printf("%c", *p); }
                            }
                            printf("\"");
                        }
                        if (fs_m_read_s && fs_m_read_s[0]) {
                            printf(",\"fs_mounts_read\":\"");
                            for (const char* p = fs_m_read_s; *p; p++) {
                                if (*p == '\\' || *p == '\"') { printf("\\\\%c", *p); }
                                else if (*p == '\n') { printf("\\\\n"); }
                                else if (*p == '\r') { printf("\\\\r"); }
                                else if (*p == '\t') { printf("\\\\t"); }
                                else { printf("%c", *p); }
                            }
                            printf("\"");
                        }
                        if (fs_m_write_s && fs_m_write_s[0]) {
                            printf(",\"fs_mounts_write\":\"");
                            for (const char* p = fs_m_write_s; *p; p++) {
                                if (*p == '\\' || *p == '\"') { printf("\\\\%c", *p); }
                                else if (*p == '\n') { printf("\\\\n"); }
                                else if (*p == '\r') { printf("\\\\r"); }
                                else if (*p == '\t') { printf("\\\\t"); }
                                else { printf("%c", *p); }
                            }
                            printf("\"");
                        }
                        printf(",\"fs_backend\":\"%s\"", ectx.fs_backend_kind == 1 ? "vfs" : "host");
                        printf(",\"proc_backend\":\"%s\"", ectx.proc_backend_kind == 1 ? "vproc" : "host");
                        printf(",\"proc_exit_code\":%d", ectx.proc_exit_code);
                        if (ectx.has_proc_fixtures_hash) {
                            char prh[65];
                            avm_sha256_hex(ectx.proc_fixtures_hash, prh);
                            printf(",\"proc_fixtures_hash_sha256\":\"%s\"", prh);
                        }
                        printf(",\"net_backend\":\"%s\"", ectx.net_backend_kind == 1 ? "vnet" : "host");
                        if (ectx.has_net_fixtures_hash) {
                            char nh[65];
                            avm_sha256_hex(ectx.net_fixtures_hash, nh);
                            printf(",\"net_fixtures_hash_sha256\":\"%s\"", nh);
                        }
                        printf(",\"budgets\":{\"gas\":%llu,\"timeout_ms\":%llu,\"call_depth_max\":%llu,\"mem_bytes\":%llu,\"io_bytes\":%llu,\"log_bytes\":%llu,\"trace_bytes\":%llu}",
                            (unsigned long long)ectx.gas,
                            (unsigned long long)ectx.timeout_ms,
                            (unsigned long long)ectx.call_depth_max,
                            (unsigned long long)ectx.mem_bytes,
                            (unsigned long long)ectx.io_bytes,
                            (unsigned long long)ectx.log_bytes,
                            (unsigned long long)ectx.trace_bytes);
                        printf(",\"deterministic\":{\"enabled\":%s,\"time_start_ns\":%llu,\"time_step_ns\":%llu,\"rng_seed\":%llu}",
                            ectx.deterministic ? "true" : "false",
                            (unsigned long long)ectx.time_start_ns,
                            (unsigned long long)ectx.time_step_ns,
                            (unsigned long long)ectx.rng_seed);
                        printf("}");
                        printf("}\n");
                    } else {
                        printf("JOB_HASH_SHA256 %s\n", job_hex);
                        printf("PROGRAM_HASH_SHA256 %s\n", prog_hex);
                        printf("INPUT_HASH_SHA256 %s\n", input_hex);
                        printf("EXEC_HASH_SHA256 %s\n", ctx_hex);
                        printf("POLICY_USED_DOMAINS_MASK 0x%016llx\n", (unsigned long long)mask);
                        printf("POLICY_HASH_SHA256 %s\n", phash_hex);
                        for (size_t j = 0; j < ops_len; j++) {
                            printf("POLICY_USED_OP domain=%u op=%u\n", (unsigned)ops[j].domain, (unsigned)ops[j].op);
                        }
                    }
                } else if (inspect || inspect_json) {
                    uint8_t prog_hash[32];
                    char prog_hex[65];
                    sha256_bytes(data, len, prog_hash);
                    avm_sha256_hex(prog_hash, prog_hex);

                    if (inspect_json) {
                        printf("{\"schema\":\"avm.obc.v1\"");
                        printf(",\"magic\":\"0x0ecd\"");
                        printf(",\"file_len\":%llu", (unsigned long long)len);
                        printf(",\"program_hash_sha256\":\"%s\"", prog_hex);
                        printf(",\"const_count\":%u", (unsigned)n_consts);
                        printf(",\"code_len\":%llu", (unsigned long long)prog.code_len);
                        printf(",\"policy\":{");
                        printf("\"schema\":\"avm.policy.v1\"");
                        printf(",\"used_domains_mask\":\"0x%016llx\"", (unsigned long long)mask);
                        printf(",\"policy_hash_sha256\":\"%s\"", phash_hex);
                        printf(",\"ops\":[");
                        for (size_t j = 0; j < ops_len; j++) {
                            if (j) printf(",");
                            printf("{\"domain\":%u,\"op\":%u}", (unsigned)ops[j].domain, (unsigned)ops[j].op);
                        }
                        printf("]}");
                        printf("}\n");
                    } else {
                        printf("OBC_SCHEMA avm.obc.v1\n");
                        printf("OBC_MAGIC 0x0ecd\n");
                        printf("OBC_FILE_LEN %llu\n", (unsigned long long)len);
                        printf("PROGRAM_HASH_SHA256 %s\n", prog_hex);
                        printf("CONST_COUNT %u\n", (unsigned)n_consts);
                        printf("CODE_LEN %llu\n", (unsigned long long)prog.code_len);
                        printf("POLICY_USED_DOMAINS_MASK 0x%016llx\n", (unsigned long long)mask);
                        printf("POLICY_HASH_SHA256 %s\n", phash_hex);
                        for (size_t j = 0; j < ops_len; j++) {
                            printf("POLICY_USED_OP domain=%u op=%u\n", (unsigned)ops[j].domain, (unsigned)ops[j].op);
                        }
                    }
                } else if (print_policy_json) {
                    printf("{\"schema\":\"avm.policy.v1\",\"used_domains_mask\":\"0x%016llx\",\"policy_hash_sha256\":\"%s\",\"ops\":[",
                        (unsigned long long)mask, phash_hex);
                    for (size_t i = 0; i < ops_len; i++) {
                        if (i) printf(",");
                        printf("{\"domain\":%u,\"op\":%u}", (unsigned)ops[i].domain, (unsigned)ops[i].op);
                    }
                    printf("]}\n");
                } else {
                    printf("POLICY_USED_DOMAINS_MASK 0x%016llx\n", (unsigned long long)mask);
                    printf("POLICY_HASH_SHA256 %s\n", phash_hex);
                    for (size_t i = 0; i < ops_len; i++) {
                        printf("POLICY_USED_OP domain=%u op=%u\n", (unsigned)ops[i].domain, (unsigned)ops[i].op);
                    }
                }
                free(ops);

                // Safety guarantee: scan-only tooling must not execute bytecode.
                // (Disassembly is still allowed because it is non-effectful.)
                if (!disasm) {
                    free_constant_pool(consts, n_consts);
                    free(consts);
                    free(data);
                    free(break_pcs);
                    return 0;
                }
            }
        }

        if (disasm) {
            if (disasm_json) disasm_program_json(stdout, &prog, disasm_consts || disasm_json_consts);
            else disasm_program(stdout, &prog, disasm_consts);
            free_constant_pool(consts, n_consts);
            free(consts);
            exit_code = 0;
            break;
        }

        AvmVM* vm = avm_new();
        vm->argc = prog_argc;
        vm->argv = prog_argv;
        if (trace) {
            vm->trace_enabled = 1;
            vm->trace_limit = trace_limit;
            vm->trace_out = stderr;
        }
        if (print_trace_hash) {
            vm->trace_hash_enabled = 1;
            // Reuse --trace-limit as a generic step limit for trace hashing if provided.
            vm->trace_hash_limit = trace_limit;
        }
        if (print_trace_bytes_hex) {
            vm->trace_bytes_enabled = 1;
            vm->trace_bytes_limit = trace_limit;
            const char* trace_budget_env = getenv("AVM_TRACE_BYTES");
            if (trace_budget_env && trace_budget_env[0]) vm->trace_budget_bytes = strtoull(trace_budget_env, NULL, 10);
            if (capsule && (!trace_budget_env || !trace_budget_env[0]) && vm->trace_budget_bytes == 0) {
                vm->trace_budget_bytes = 1024ull * 1024ull; // 1 MiB default in capsule mode
            }
        }
        if (break_pc_count > 0) {
            if (repeat == 1) {
                vm->break_pcs = break_pcs;
                vm->break_pc_count = break_pc_count;
                break_pcs = NULL; // owned by vm now
            } else {
                vm->break_pcs = (int*)malloc(sizeof(int) * (size_t)break_pc_count);
                if (!vm->break_pcs) {
                    fprintf(stderr, "OOM\n");
                    avm_free(vm);
                    free_constant_pool(consts, n_consts);
                    free(consts);
                    free(data);
                    free(break_pcs);
                    return 1;
                }
                memcpy(vm->break_pcs, break_pcs, sizeof(int) * (size_t)break_pc_count);
                vm->break_pc_count = break_pc_count;
            }
        }

        // TMP freelist (best-effort perf): enabled only when requested via env.
        const char* tmp_free_env = getenv("AVM_TMP_FREELIST");
        const char* tmp_free_bytes_env = getenv("AVM_TMP_FREELIST_BYTES");
        const char* tmp_free_block_env = getenv("AVM_TMP_FREELIST_MAX_BLOCK_BYTES");
        int tmp_enable = 0;
        if (tmp_free_env && tmp_free_env[0]) {
            if (tmp_free_env[0] != '0') tmp_enable = 1;
        } else if (tmp_free_bytes_env && tmp_free_bytes_env[0]) {
            tmp_enable = 1;
        }
        if (tmp_enable) {
            uint64_t tmp_cap = 0;
            uint64_t tmp_block_cap = 0;
            if (tmp_free_bytes_env && tmp_free_bytes_env[0]) tmp_cap = strtoull(tmp_free_bytes_env, NULL, 10);
            if (tmp_cap == 0) tmp_cap = 1024ull * 1024ull; // default 1 MiB cap
            if (tmp_free_block_env && tmp_free_block_env[0]) tmp_block_cap = strtoull(tmp_free_block_env, NULL, 10);
            if (tmp_block_cap == 0) tmp_block_cap = 64ull * 1024ull; // default 64 KiB block cap
            vm->tmp_freelist_enabled = 1;
            vm->tmp_freelist_cap_bytes = tmp_cap;
            vm->tmp_freelist_max_block_bytes = tmp_block_cap;
        }

        const char* list_free_env = getenv("AVM_LIST_FREELIST");
        const char* list_free_bytes_env = getenv("AVM_LIST_FREELIST_BYTES");
        const char* list_free_block_env = getenv("AVM_LIST_FREELIST_MAX_BLOCK_BYTES");
        int list_enable = 0;
        if (list_free_env && list_free_env[0]) {
            if (list_free_env[0] != '0') list_enable = 1;
        } else if (list_free_bytes_env && list_free_bytes_env[0]) {
            list_enable = 1;
        }
        if (list_enable) {
            uint64_t list_cap = 0;
            uint64_t list_block_cap = 0;
            if (list_free_bytes_env && list_free_bytes_env[0]) list_cap = strtoull(list_free_bytes_env, NULL, 10);
            if (list_cap == 0) list_cap = 1024ull * 1024ull; // default 1 MiB cap
            if (list_free_block_env && list_free_block_env[0]) list_block_cap = strtoull(list_free_block_env, NULL, 10);
            if (list_block_cap == 0) list_block_cap = 64ull * 1024ull; // default 64 KiB block cap
            vm->list_freelist_enabled = 1;
            vm->list_freelist_cap_bytes = list_cap;
            vm->list_freelist_max_block_bytes = list_block_cap;
        }

        // Budgets/timeouts (macOS-first, rolling ABI):
        // - AVM_GAS: maximum instruction steps (0/unset = unlimited)
        // - AVM_TIMEOUT_MS: wall-time timeout in milliseconds (0/unset = unlimited)
        // - AVM_MEM_BYTES: heap budget for AVM heap objects (0/unset = unlimited)
        // - AVM_IO_BYTES: io budget for FS bytes read/written (0/unset = unlimited)
        // - AVM_LOG_BYTES: record/replay log budget (bytes appended, incl header) (0/unset = unlimited)
        // - AVM_CALL_DEPTH_MAX: maximum call depth (0/unset = MAX_FRAMES)
        const char* gas_env = getenv("AVM_GAS");
        if (gas_env && gas_env[0]) vm->gas_remaining = strtoull(gas_env, NULL, 10);
        uint64_t timeout_limit_ms = 0;
        const char* timeout_env = timeout_ms_cli ? timeout_ms_cli : getenv("AVM_TIMEOUT_MS");
        if (timeout_env && timeout_env[0]) {
            uint64_t ms = strtoull(timeout_env, NULL, 10);
            timeout_limit_ms = ms;
            uint64_t base = now_ns();
            if (base != 0 && ms > 0) vm->deadline_ns = base + ms * 1000000ull;
        }
        const char* depth_env = call_depth_max_cli ? call_depth_max_cli : getenv("AVM_CALL_DEPTH_MAX");
        if (depth_env && depth_env[0]) {
            uint64_t d = strtoull(depth_env, NULL, 10);
            if (d == 0) {
                vm->frame_limit = (uint32_t)MAX_FRAMES;
            } else if (d > (uint64_t)MAX_FRAMES) {
                vm->frame_limit = (uint32_t)MAX_FRAMES;
            } else {
                vm->frame_limit = (uint32_t)d;
            }
        }
        const char* mem_env = getenv("AVM_MEM_BYTES");
        if (mem_env && mem_env[0]) vm->heap_budget_bytes = strtoull(mem_env, NULL, 10);
        const char* io_env = getenv("AVM_IO_BYTES");
        if (io_env && io_env[0]) vm->io_budget_bytes = strtoull(io_env, NULL, 10);
        const char* log_env = getenv("AVM_LOG_BYTES");
        if (log_env && log_env[0]) vm->log_budget_bytes = strtoull(log_env, NULL, 10);

        // Capsule defaults (rolling): apply safe budgets unless explicitly overridden by env.
        // These defaults are intentionally conservative and may evolve while the repo is rolling.
        if (capsule) {
            if ((!gas_env || !gas_env[0]) && vm->gas_remaining == 0) vm->gas_remaining = 5000000ull;
            if ((!timeout_env || !timeout_env[0]) && vm->deadline_ns == 0) {
                uint64_t base = now_ns();
                if (base != 0) vm->deadline_ns = base + 2000ull * 1000000ull; // 2000ms
                timeout_limit_ms = 2000ull;
            }
            if ((!mem_env || !mem_env[0]) && vm->heap_budget_bytes == 0) vm->heap_budget_bytes = 32ull * 1024ull * 1024ull; // 32 MiB
            if ((!io_env || !io_env[0]) && vm->io_budget_bytes == 0) vm->io_budget_bytes = 1024ull * 1024ull; // 1 MiB
            if ((!log_env || !log_env[0]) && vm->log_budget_bytes == 0) vm->log_budget_bytes = 1024ull * 1024ull; // 1 MiB
        }

        // Deterministic record/replay (rolling):
        // - AVM_RECORD_LOG: path to write a native-call replay log (FS domain currently).
        // - AVM_REPLAY_LOG: path to read a native-call replay log (FS domain currently).
        // Only one may be set.
        const char* record_env = getenv("AVM_RECORD_LOG");
        const char* replay_env = getenv("AVM_REPLAY_LOG");
        const char* replay_hex_env = getenv("AVM_REPLAY_LOG_HEX");
        const char* record_mem_env = getenv("AVM_RECORD_MEM");
        if (record_env && record_env[0] && replay_env && replay_env[0]) {
            fprintf(stderr, "AVM_RECORD_LOG and AVM_REPLAY_LOG are mutually exclusive\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        if ((replay_env && replay_env[0]) && (replay_hex_env && replay_hex_env[0])) {
            fprintf(stderr, "AVM_REPLAY_LOG and AVM_REPLAY_LOG_HEX are mutually exclusive\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        if ((record_env && record_env[0]) && (record_mem_env && record_mem_env[0] && record_mem_env[0] != '0')) {
            fprintf(stderr, "AVM_RECORD_LOG and AVM_RECORD_MEM are mutually exclusive\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        if (record_env && record_env[0]) {
            FILE* rf = fopen(record_env, "wb");
            if (!rf) {
                fprintf(stderr, "Failed to open record log: %s\n", record_env);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
            if (vm->log_budget_bytes > 0 && 8 > vm->log_budget_bytes) {
                fprintf(stderr, "AVM_LOG_BYTES too small for log header (need 8)\n");
                fclose(rf);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            if (fwrite(magic, 1, 8, rf) != 8) {
                fprintf(stderr, "Failed to write log header: %s\n", record_env);
                fclose(rf);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            vm->record_log = rf;
            vm->log_used_bytes += 8;
        }
        if (replay_env && replay_env[0]) {
            FILE* rf = fopen(replay_env, "rb");
            if (!rf) {
                fprintf(stderr, "Failed to open replay log: %s\n", replay_env);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            uint8_t magic[8];
            if (fread(magic, 1, 8, rf) != 8) {
                fprintf(stderr, "Invalid replay log header: %s\n", replay_env);
                fclose(rf);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
            if (memcmp(magic, want, 8) != 0) {
                fprintf(stderr, "Invalid replay log magic: %s\n", replay_env);
                fclose(rf);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            vm->replay_log = rf;
        }
        if (record_mem_env && record_mem_env[0] && record_mem_env[0] != '0') {
            // In-memory log: prepopulate header and record into vm->record_log_bytes.
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { fprintf(stderr, "OOM\n"); avm_free(vm); free_constant_pool(consts, n_consts); free(consts); free(data); free(break_pcs); return 1; }
            b->len = 8;
            b->capacity = 64;
            b->data = (uint8_t*)malloc((size_t)b->capacity);
            if (!b->data) { fprintf(stderr, "OOM\n"); free(b); avm_free(vm); free_constant_pool(consts, n_consts); free(consts); free(data); free(break_pcs); return 1; }
            const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
            memcpy(b->data, magic, 8);
            vm->record_log_bytes = b;
            if (vm->log_budget_bytes > 0 && 8 > vm->log_budget_bytes) {
                fprintf(stderr, "AVM_LOG_BYTES too small for log header (need 8)\n");
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            vm->log_used_bytes += 8;
        }
        if (replay_hex_env && replay_hex_env[0]) {
            AvmBytes* b = bytes_from_hex(replay_hex_env);
            if (!b || b->len < 8) {
                fprintf(stderr, "Invalid AVM_REPLAY_LOG_HEX\n");
                if (b) { free(b->data); free(b); }
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
            if (memcmp(b->data, want, 8) != 0) {
                fprintf(stderr, "Invalid replay log magic (hex)\n");
                free(b->data); free(b);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            vm->replay_log_bytes = b;
            vm->replay_log_pos = 8;
        }

        // Deterministic mode (rolling):
        // - AVM_DETERMINISTIC=1 enables virtual TIME and deterministic RNG.
        // - AVM_TIME_START_NS sets initial virtual clock (default 0).
        // - AVM_TIME_STEP_NS sets virtual time per executed semantic step (gas unit).
        // - AVM_RNG_SEED seeds the deterministic RNG.
        const char* det_env = getenv("AVM_DETERMINISTIC");
        if (det_env && det_env[0] && det_env[0] != '0') vm->deterministic = 1;
        const char* t0_env = getenv("AVM_TIME_START_NS");
        if (t0_env && t0_env[0]) vm->virtual_now_ns = strtoull(t0_env, NULL, 10);
        const char* step_env = getenv("AVM_TIME_STEP_NS");
        if (step_env && step_env[0]) vm->virtual_step_ns = strtoull(step_env, NULL, 10);
        const char* seed_env = getenv("AVM_RNG_SEED");
        if (seed_env && seed_env[0]) vm->rng_state = strtoull(seed_env, NULL, 10);
        const char* tq_env = task_quantum_cli ? task_quantum_cli : getenv("AVM_TASK_QUANTUM");
        if (!tq_env || !tq_env[0]) tq_env = getenv("AVM_TASK_QUANTUM_STEPS");
        uint64_t tq = 0;
        if (tq_env && tq_env[0]) tq = strtoull(tq_env, NULL, 10);
        if (tq == 0) tq = 1000ull;
        if (tq > 1000000000ull) tq = 1000000000ull;
        vm->task_quantum_steps = (uint32_t)tq;

        // SIMD acceleration (rolling, off by default):
        // - AVM_ENABLE_SIMD=1 enables SIMD kernel implementations when available.
        // - This is an optimization only; semantics must match scalar fallback.
        const char* simd_env = getenv("AVM_ENABLE_SIMD");
        if (simd_env && simd_env[0] && simd_env[0] != '0') vm->enable_simd = 1;

        // Capability enforcement (rolling ABI):
        // - AVM_ALLOW_DOMAINS: comma-separated domain integers (e.g. "0,1"). Unset/empty means allow all.
        // - AVM_FS_ALLOW_PREFIXES: comma-separated path prefixes; if set, FS paths must start with an allowed prefix.
        const char* domains_s = allow_domains_cli ? allow_domains_cli : getenv("AVM_ALLOW_DOMAINS");
        uint64_t parsed_mask = 0;
        const char* oren_domains_s = NULL;
        if ((!domains_s || !domains_s[0]) && capsule) {
            oren_domains_s = getenv("OREN_CAP_ALLOW_DOMAINS");
        }
        int has_allow = (domains_s && domains_s[0]) ? 1 : 0;
        if (!has_allow && oren_domains_s && oren_domains_s[0]) has_allow = 1;

        int ok = 1;
        if (domains_s && domains_s[0]) {
            ok = parse_domain_mask_strict(domains_s, &parsed_mask);
        } else if (oren_domains_s && oren_domains_s[0]) {
            ok = parse_oren_domains_mask(oren_domains_s, &parsed_mask);
            parsed_mask |= (1ULL << 0) | (1ULL << 6);
        } else {
            parsed_mask = 0;
        }
        if (!ok) {
            fprintf(stderr, "Invalid allow domains list\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }

        if (deny_by_default && !has_allow) {
            // Minimal safe set: CORE (0) + EXIT (6).
            vm->allowed_native_domains = (1ULL << 0) | (1ULL << 6);
        } else {
            vm->allowed_native_domains = parsed_mask;
        }

        const char* fs_allow_s = fs_allow_prefixes_cli ? fs_allow_prefixes_cli : getenv("AVM_FS_ALLOW_PREFIXES");
        if ((!fs_allow_s || !fs_allow_s[0]) && capsule) {
            fs_allow_s = getenv("OREN_FS_ALLOW_PREFIXES");
            if (!fs_allow_s || !fs_allow_s[0]) fs_allow_s = getenv("OREN_FS_ALLOW_READ_PREFIXES");
            if (!fs_allow_s || !fs_allow_s[0]) fs_allow_s = getenv("OREN_FS_ALLOW_WRITE_PREFIXES");
        }
        parse_fs_allow_prefixes(vm, fs_allow_s);

        const char* fs_m_read_s = fs_mounts_read_cli ? fs_mounts_read_cli : getenv("AVM_FS_MOUNTS_READ");
        const char* fs_m_write_s = fs_mounts_write_cli ? fs_mounts_write_cli : getenv("AVM_FS_MOUNTS_WRITE");
        const char* fs_m_both_s = fs_mounts_cli ? fs_mounts_cli : getenv("AVM_FS_MOUNTS");
        if ((!fs_m_read_s || !fs_m_read_s[0]) && fs_m_both_s && fs_m_both_s[0]) fs_m_read_s = fs_m_both_s;
        if ((!fs_m_write_s || !fs_m_write_s[0]) && fs_m_both_s && fs_m_both_s[0]) fs_m_write_s = fs_m_both_s;
        if (capsule) {
            if ((!fs_m_read_s || !fs_m_read_s[0])) {
                fs_m_read_s = getenv("OREN_FS_MOUNTS_READ");
                if (!fs_m_read_s || !fs_m_read_s[0]) fs_m_read_s = getenv("OREN_FS_MOUNTS");
            }
            if ((!fs_m_write_s || !fs_m_write_s[0])) {
                fs_m_write_s = getenv("OREN_FS_MOUNTS_WRITE");
                if (!fs_m_write_s || !fs_m_write_s[0]) fs_m_write_s = getenv("OREN_FS_MOUNTS");
            }
        }
        parse_fs_mounts(&vm->fs_mounts_read_virt, &vm->fs_mounts_read_host, &vm->fs_mounts_read_count, fs_m_read_s);
        parse_fs_mounts(&vm->fs_mounts_write_virt, &vm->fs_mounts_write_host, &vm->fs_mounts_write_count, fs_m_write_s);

        const char* fs_backend_s = fs_backend_cli ? fs_backend_cli : getenv("AVM_FS_BACKEND");
        if (capsule && (!fs_backend_s || !fs_backend_s[0])) fs_backend_s = "vfs";
        if (!parse_fs_backend_kind(fs_backend_s, &vm->fs_backend_kind)) {
            fprintf(stderr, "Invalid fs backend (expected 'host' or 'vfs')\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        const char* proc_backend_s = proc_backend_cli ? proc_backend_cli : getenv("AVM_PROC_BACKEND");
        if (capsule && (!proc_backend_s || !proc_backend_s[0])) proc_backend_s = "vproc";
        if (!parse_proc_backend_kind(proc_backend_s, &vm->proc_backend_kind)) {
            fprintf(stderr, "Invalid proc backend (expected 'host' or 'vproc')\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        const char* proc_ec_s = proc_exit_code_cli ? proc_exit_code_cli : getenv("AVM_PROC_EXIT_CODE");
        if (proc_ec_s && proc_ec_s[0]) vm->proc_exit_code = (int)strtoll(proc_ec_s, NULL, 10);
        const char* proc_fixtures_hex = proc_fixtures_hex_cli ? proc_fixtures_hex_cli : getenv("AVM_PROC_FIXTURES_HEX");
        if (vm->proc_backend_kind == 1 && proc_fixtures_hex && proc_fixtures_hex[0]) {
            AvmBytes* b = bytes_from_hex(proc_fixtures_hex);
            if (!b) {
                fprintf(stderr, "Invalid proc fixtures hex\n");
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            if (!avm_proc_load_fixtures(vm, b->data, (size_t)b->len)) {
                fprintf(stderr, "Failed to load proc fixtures (expected magic AVMPRC01)\n");
                free(b->data);
                free(b);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            free(b->data);
            free(b);
        }

        const char* net_backend_s = net_backend_cli ? net_backend_cli : getenv("AVM_NET_BACKEND");
        if (capsule && (!net_backend_s || !net_backend_s[0])) net_backend_s = "vnet";
        if (!parse_net_backend_kind(net_backend_s, &vm->net_backend_kind)) {
            fprintf(stderr, "Invalid net backend (expected 'host' or 'vnet')\n");
            avm_free(vm);
            free_constant_pool(consts, n_consts);
            free(consts);
            free(data);
            free(break_pcs);
            return 1;
        }
        const char* net_fixtures_hex = net_fixtures_hex_cli ? net_fixtures_hex_cli : getenv("AVM_NET_FIXTURES_HEX");
        if (vm->net_backend_kind == 1 && net_fixtures_hex && net_fixtures_hex[0]) {
            AvmBytes* b = bytes_from_hex(net_fixtures_hex);
            if (!b) {
                fprintf(stderr, "Invalid net fixtures hex\n");
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            if (!avm_net_load_fixtures(vm, b->data, (size_t)b->len)) {
                fprintf(stderr, "Invalid net fixtures format\n");
                free(b->data);
                free(b);
                avm_free(vm);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            free(b->data);
            free(b);
        }

        avm_load(vm, &prog);

        if (snap_in) {
            if (avm_restore(vm, snap_in) != 0) {
                fprintf(stderr, "AVM restore failed: %s\n", snap_in);
                avm_free(vm);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
        }

        if (step_limit > 0) vm->pause_after_steps = step_limit;
        uint64_t run_wall_start_ns = now_ns();
        avm_run(vm);
        uint64_t run_wall_end_ns = now_ns();

        if (repeat > 1) printf("ITER %d\n", iter);
        if (print_pause_json_flag && vm->paused) {
            print_pause_json(stdout, vm);
        }
        if (print_run_json) {
            uint64_t elapsed_ns = 0;
            if (run_wall_start_ns != 0 && run_wall_end_ns != 0 && run_wall_end_ns >= run_wall_start_ns) {
                elapsed_ns = run_wall_end_ns - run_wall_start_ns;
            }
            fprintf(stdout, "{");
            fprintf(stdout, "\"schema\":\"avm.run.v1\"");
            fprintf(stdout, ",\"exit_code\":%d", vm->exit_code);
            fprintf(stdout, ",\"gas_executed\":%llu", (unsigned long long)vm->gas_executed);
            fprintf(stdout, ",\"wall_elapsed_ns\":%llu", (unsigned long long)elapsed_ns);
            if (elapsed_ns > 0 && vm->gas_executed > 0) {
                double ns_per_gas = (double)elapsed_ns / (double)vm->gas_executed;
                double gas_per_sec = (double)vm->gas_executed / ((double)elapsed_ns / 1e9);
                fprintf(stdout, ",\"ns_per_gas\":%.3f", ns_per_gas);
                fprintf(stdout, ",\"gas_per_sec\":%.3f", gas_per_sec);
            }
            // Result selection (rolling): expose explicit consensus result for orchestration.
            // This is especially important for "AVM-in-AVM" style workflows where the parent
            // needs a stable machine-readable value.
            fprintf(stdout, ",\"has_result\":%s", vm->has_result_value ? "true" : "false");
            AvmValue rv;
            if (vm->has_result_value) {
                rv = vm->result_value;
            } else {
                rv.type = AVM_VAL_NIL;
                rv.as.i = 0;
            }
            fprintf(stdout, ",\"result_type\":\"%s\"", avm_value_type_name(rv.type));
            fprintf(stdout, ",\"result\":");
            switch (rv.type) {
                case AVM_VAL_NIL:
                    fprintf(stdout, "null");
                    break;
                case AVM_VAL_BOOL:
                    fprintf(stdout, "%s", rv.as.i ? "true" : "false");
                    break;
                case AVM_VAL_INT:
                    fprintf(stdout, "%lld", (long long)rv.as.i);
                    break;
                case AVM_VAL_FLOAT:
                    fprintf(stdout, "%.17g", rv.as.f);
                    break;
                case AVM_VAL_STRING:
                    fputc('\"', stdout);
                    print_json_escaped_string(stdout, (const char*)rv.as.p);
                    fputc('\"', stdout);
                    break;
                default:
                    // Complex values are not yet serialized in v0 run JSON; callers can
                    // rely on hashes/logs for deterministic verification and treat this
                    // field as informational.
                    fprintf(stdout, "null");
                    break;
            }
            print_effect_ledger_summary_json(stdout, vm, elapsed_ns, timeout_limit_ms);
            fprintf(stdout, "}\n");
        }

        if (print_state_hash) {
            uint8_t hash[32];
            if (avm_state_hash(vm, hash)) {
                char hex[65];
                avm_sha256_hex(hash, hex);
                printf("STATE_HASH %s\n", hex);
            } else {
                printf("STATE_HASH_ERROR\n");
            }
        }

        if (print_result_hash) {
            uint8_t hash[32];
            if (avm_result_hash(vm, hash)) {
                char hex[65];
                avm_sha256_hex(hash, hex);
                printf("RESULT_HASH %s\n", hex);
            } else {
                printf("RESULT_HASH_ERROR\n");
            }
        }

        if (print_trace_hash) {
            uint8_t hash[32];
            if (avm_trace_hash(vm, hash)) {
                char hex[65];
                avm_sha256_hex(hash, hex);
                printf("TRACE_HASH %s\n", hex);
            } else {
                printf("TRACE_HASH_ERROR\n");
            }
        }

        if (print_trace_bytes_hex) {
            printf("TRACE_TRUNCATED %d\n", vm->trace_bytes_truncated ? 1 : 0);
            AvmBytes* tb = avm_trace_bytes(vm);
            if (tb && tb->data && tb->len >= 8) {
                char* hex = bytes_to_hex(tb->data, (size_t)tb->len);
                if (hex) {
                    printf("TRACE_BYTES_HEX %s\n", hex);
                    free(hex);
                } else {
                    printf("TRACE_BYTES_HEX_ERROR\n");
                }
            } else {
                printf("TRACE_BYTES_HEX_ERROR\n");
            }
        }

        if (print_mem_stats) {
            AvmHeapStats st;
            if (avm_heap_stats(vm, &st)) {
                printf("MEM_STATS strings=%llu strings_bytes=%llu bytes=%llu bytes_bytes=%llu lists=%llu list_elems=%llu maps=%llu map_entries=%llu approx_bytes=%llu\n",
                    (unsigned long long)st.strings_count,
                    (unsigned long long)st.strings_bytes,
                    (unsigned long long)st.bytes_count,
                    (unsigned long long)st.bytes_bytes,
                    (unsigned long long)st.lists_count,
                    (unsigned long long)st.list_elems,
                    (unsigned long long)st.maps_count,
                    (unsigned long long)st.map_entries,
                    (unsigned long long)st.approx_total_bytes);
                printf("FREELIST_STATS tmp_enabled=%d tmp_bytes=%llu tmp_cap=%llu tmp_hits=%llu tmp_misses=%llu tmp_evictions=%llu "
                       "list_enabled=%d list_bytes=%llu list_cap=%llu list_hits=%llu list_misses=%llu list_evictions=%llu\n",
                    vm->tmp_freelist_enabled ? 1 : 0,
                    (unsigned long long)vm->tmp_freelist_bytes,
                    (unsigned long long)vm->tmp_freelist_cap_bytes,
                    (unsigned long long)vm->tmp_freelist_hits,
                    (unsigned long long)vm->tmp_freelist_misses,
                    (unsigned long long)vm->tmp_freelist_evictions,
                    vm->list_freelist_enabled ? 1 : 0,
                    (unsigned long long)vm->list_freelist_bytes,
                    (unsigned long long)vm->list_freelist_cap_bytes,
                    (unsigned long long)vm->list_freelist_hits,
                    (unsigned long long)vm->list_freelist_misses,
                    (unsigned long long)vm->list_freelist_evictions);
            } else {
                printf("MEM_STATS_ERROR\n");
            }
        }

        if (print_rss) {
            uint64_t rss = current_rss_bytes();
            if (rss != 0) printf("RSS_BYTES %llu\n", (unsigned long long)rss);
            else printf("RSS_BYTES_ERROR\n");
        }

        if (snap_out) {
            if (avm_snapshot(vm, snap_out) != 0) {
                fprintf(stderr, "AVM snapshot failed: %s\n", snap_out);
                // Snapshot-out is primarily used for pause/resume workflows.
                // If we paused (exit_code==2) but failed to write a snapshot, resuming is impossible.
                // In that case, report a distinct non-pause exit code so orchestration does not
                // treat the run as a resumable pause.
                if (vm->exit_code == 2) {
                    vm->exit_code = 3;
                }
            }
        }
        if (vm->exit_code != 0) {
            dump_error(vm->last_error);
        }
        if (print_stack) dump_stack(stderr, vm, 32);
        exit_code = vm->exit_code;
        if (vm->record_log) { fclose(vm->record_log); vm->record_log = NULL; }
        if (vm->replay_log) { fclose(vm->replay_log); vm->replay_log = NULL; }

        if (print_record_log_hex) {
            if (vm->record_log_bytes && vm->record_log_bytes->data && vm->record_log_bytes->len >= 8) {
                char* hex = bytes_to_hex(vm->record_log_bytes->data, (size_t)vm->record_log_bytes->len);
                if (hex) {
                    printf("RECORD_LOG_HEX %s\n", hex);
                    free(hex);
                } else {
                    printf("RECORD_LOG_HEX_ERROR\n");
                }
            } else {
                printf("RECORD_LOG_HEX \n");
            }
        }

        avm_free(vm);
        free(consts);

        if (exit_code != 0) break;
    }

    free(data);
    free(break_pcs);

    return exit_code;
}
