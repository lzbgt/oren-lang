#include "avm_cli_policy.h"
#include "avm_sig.h"
#include "sha256.h"
#include <stdlib.h>
#include <string.h>

static void sha_u8(AvmSha256Ctx* h, uint8_t v) { avm_sha256_update(h, &v, 1); }
static void sha_u16_le(AvmSha256Ctx* h, uint16_t v) {
    uint8_t b[2];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    avm_sha256_update(h, b, 2);
}
static void sha_u32_le(AvmSha256Ctx* h, uint32_t v) {
    uint8_t b[4];
    b[0] = (uint8_t)(v & 0xFFu);
    b[1] = (uint8_t)((v >> 8) & 0xFFu);
    b[2] = (uint8_t)((v >> 16) & 0xFFu);
    b[3] = (uint8_t)((v >> 24) & 0xFFu);
    avm_sha256_update(h, b, 4);
}
static void sha_u64_le(AvmSha256Ctx* h, uint64_t v) {
    uint8_t b[8];
    b[0] = (uint8_t)(v & 0xFFull);
    b[1] = (uint8_t)((v >> 8) & 0xFFull);
    b[2] = (uint8_t)((v >> 16) & 0xFFull);
    b[3] = (uint8_t)((v >> 24) & 0xFFull);
    b[4] = (uint8_t)((v >> 32) & 0xFFull);
    b[5] = (uint8_t)((v >> 40) & 0xFFull);
    b[6] = (uint8_t)((v >> 48) & 0xFFull);
    b[7] = (uint8_t)((v >> 56) & 0xFFull);
    avm_sha256_update(h, b, 8);
}

static int policy_ops_cmp(const void* a, const void* b) {
    const PolicyOp* pa = (const PolicyOp*)a;
    const PolicyOp* pb = (const PolicyOp*)b;
    if (pa->domain != pb->domain) return (pa->domain < pb->domain) ? -1 : 1;
    if (pa->op != pb->op) return (pa->op < pb->op) ? -1 : 1;
    return 0;
}

static int policy_ops_add(PolicyOp** ops_io, size_t* len_io, size_t* cap_io, uint8_t domain, uint16_t op) {
    if (!ops_io || !len_io || !cap_io) return 0;
    for (size_t i = 0; i < *len_io; i++) {
        if ((*ops_io)[i].domain == domain && (*ops_io)[i].op == op) return 1;
    }
    if (*len_io >= *cap_io) {
        size_t nc = (*cap_io) ? (*cap_io) * 2 : 32;
        void* np = realloc(*ops_io, sizeof(PolicyOp) * nc);
        if (!np) return 0;
        *ops_io = (PolicyOp*)np;
        *cap_io = nc;
    }
    (*ops_io)[*len_io].domain = domain;
    (*ops_io)[*len_io].op = op;
    (*len_io)++;
    return 1;
}

void sha256_bytes(const uint8_t* data, size_t len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    if (data && len > 0) avm_sha256_update(&h, data, len);
    avm_sha256_final(&h, out);
}

void sha256_tagged_bytes8(const char tag8[8], const uint8_t* data, size_t len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    if (tag8) avm_sha256_update(&h, (const uint8_t*)tag8, 8);
    if (data && len > 0) avm_sha256_update(&h, data, len);
    avm_sha256_final(&h, out);
}

void sha256_job_v1(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','1' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_final(&h, out);
}

void sha256_job_v2(
    const uint8_t program_hash[32],
    const uint8_t policy_hash[32],
    const uint8_t input_hash[32],
    const uint8_t exec_ctx_hash[32],
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','2' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_update(&h, exec_ctx_hash, 32);
    avm_sha256_final(&h, out);
}

void sha256_job_v3(
    const uint8_t program_hash[32],
    const uint8_t policy_hash[32],
    const uint8_t input_hash[32],
    const uint8_t exec_ctx_hash[32],
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','3' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_update(&h, exec_ctx_hash, 32);
    avm_sha256_final(&h, out);
}

void sha256_job_v4(
    const uint8_t program_hash[32],
    const uint8_t policy_hash[32],
    const uint8_t input_hash[32],
    const uint8_t exec_ctx_hash[32],
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','4' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_update(&h, exec_ctx_hash, 32);
    avm_sha256_final(&h, out);
}

void sha256_job_v6(
    const uint8_t program_hash[32],
    const uint8_t policy_hash[32],
    const uint8_t input_hash[32],
    const uint8_t exec_ctx_hash[32],
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','6' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_update(&h, exec_ctx_hash, 32);
    avm_sha256_final(&h, out);
}

void sha256_job_v7(
    const uint8_t program_hash[32],
    const uint8_t policy_hash[32],
    const uint8_t input_hash[32],
    const uint8_t exec_ctx_hash[32],
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','7' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_update(&h, exec_ctx_hash, 32);
    avm_sha256_final(&h, out);
}

void ctx_hash_sha256_v8(
    const AvmExecContext* ctx,
    const char* fs_allow_prefixes_raw,
    const char* fs_mounts_read_raw,
    const char* fs_mounts_write_raw,
    uint8_t out[32]
) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','C','T','X','0','8' };
    avm_sha256_update(&h, tag, 8);

    // flags
    sha_u8(&h, (uint8_t)(ctx && ctx->capsule ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->verify_strict ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->deny_by_default ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->record_enabled ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->replay_enabled ? 1 : 0));

    // output config (hashable, path-free)
    sha_u8(&h, (uint8_t)(ctx ? ctx->record_sink_kind : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->snapshot_out_enabled ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->output_state_hash ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->output_result_hash ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->output_trace_hash ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->output_trace_bytes ? 1 : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->output_record_log_hex ? 1 : 0));
    sha_u64_le(&h, ctx ? ctx->trace_step_limit : 0);

    // backend selection
    sha_u8(&h, (uint8_t)(ctx ? ctx->fs_backend_kind : 0));
    sha_u8(&h, (uint8_t)(ctx ? ctx->proc_backend_kind : 0));
    sha_u64_le(&h, (uint64_t)(ctx ? (uint64_t)(uint32_t)ctx->proc_exit_code : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->has_proc_fixtures_hash ? 1 : 0));
    if (ctx && ctx->has_proc_fixtures_hash) avm_sha256_update(&h, ctx->proc_fixtures_hash, 32);
    sha_u8(&h, (uint8_t)(ctx ? ctx->net_backend_kind : 0));
    sha_u8(&h, (uint8_t)(ctx && ctx->has_net_fixtures_hash ? 1 : 0));
    if (ctx && ctx->has_net_fixtures_hash) avm_sha256_update(&h, ctx->net_fixtures_hash, 32);

    // allowlist (effective)
    sha_u64_le(&h, ctx ? ctx->allow_domains_mask : 0);

    // fs allow prefixes (normalized as: count + len-prefixed bytes)
    // Empty/unset means "allow all" at the FS layer (but domain gating may still deny FS).
    const char* s = fs_allow_prefixes_raw;
    if (!s || !s[0]) {
        sha_u32_le(&h, 0);
    } else {
        // Count prefixes
        uint32_t cnt = 0;
        const char* cur = s;
        while (*cur) {
            while (*cur == ' ') cur++;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            if (end > start) cnt++;
            if (*cur == ',') cur++;
        }
        sha_u32_le(&h, cnt);

        // Emit each prefix
        cur = s;
        while (*cur) {
            while (*cur == ' ') cur++;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            if (end > start) {
                uint32_t len = (uint32_t)(end - start);
                sha_u32_le(&h, len);
                avm_sha256_update(&h, (const uint8_t*)start, (size_t)len);
            }
            if (*cur == ',') cur++;
        }
    }

    // fs mounts (raw strings, normalized as tokenization like allow prefixes):
    // - empty/unset means "no mounts configured"
    // - when mounts are set for an op type, host FS calls must match a mount
    // Format (rolling, v0): CSV of entries "virt=host" (both are prefixes).
    const char* mounts_read = fs_mounts_read_raw;
    const char* mounts_write = fs_mounts_write_raw;
    if ((!mounts_read || !mounts_read[0])) sha_u32_le(&h, 0);
    else {
        uint32_t cnt = 0;
        const char* cur = mounts_read;
        while (*cur) {
            while (*cur == ' ' || *cur == ',') cur++;
            if (!*cur) break;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            // Require at least one '=' in the token; otherwise ignore (still hashed as absent).
            int has_eq = 0;
            for (const char* p = start; p < end; p++) { if (*p == '=') { has_eq = 1; break; } }
            if (end > start && has_eq) cnt++;
            if (*cur == ',') cur++;
        }
        sha_u32_le(&h, cnt);
        cur = mounts_read;
        while (*cur) {
            while (*cur == ' ' || *cur == ',') cur++;
            if (!*cur) break;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            int has_eq = 0;
            for (const char* p = start; p < end; p++) { if (*p == '=') { has_eq = 1; break; } }
            if (end > start && has_eq) {
                uint32_t len = (uint32_t)(end - start);
                sha_u32_le(&h, len);
                avm_sha256_update(&h, (const uint8_t*)start, (size_t)len);
            }
            if (*cur == ',') cur++;
        }
    }
    if ((!mounts_write || !mounts_write[0])) sha_u32_le(&h, 0);
    else {
        uint32_t cnt = 0;
        const char* cur = mounts_write;
        while (*cur) {
            while (*cur == ' ' || *cur == ',') cur++;
            if (!*cur) break;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            int has_eq = 0;
            for (const char* p = start; p < end; p++) { if (*p == '=') { has_eq = 1; break; } }
            if (end > start && has_eq) cnt++;
            if (*cur == ',') cur++;
        }
        sha_u32_le(&h, cnt);
        cur = mounts_write;
        while (*cur) {
            while (*cur == ' ' || *cur == ',') cur++;
            if (!*cur) break;
            const char* start = cur;
            while (*cur && *cur != ',') cur++;
            const char* end = cur;
            while (end > start && end[-1] == ' ') end--;
            int has_eq = 0;
            for (const char* p = start; p < end; p++) { if (*p == '=') { has_eq = 1; break; } }
            if (end > start && has_eq) {
                uint32_t len = (uint32_t)(end - start);
                sha_u32_le(&h, len);
                avm_sha256_update(&h, (const uint8_t*)start, (size_t)len);
            }
            if (*cur == ',') cur++;
        }
    }

    // budgets (effective)
    sha_u64_le(&h, ctx ? ctx->gas : 0);
    sha_u64_le(&h, ctx ? ctx->timeout_ms : 0);
    sha_u64_le(&h, ctx ? ctx->call_depth_max : 0);
    sha_u64_le(&h, ctx ? ctx->mem_bytes : 0);
    sha_u64_le(&h, ctx ? ctx->io_bytes : 0);
    sha_u64_le(&h, ctx ? ctx->log_bytes : 0);
    sha_u64_le(&h, ctx ? ctx->trace_bytes : 0);

    // deterministic knobs
    sha_u8(&h, (uint8_t)(ctx && ctx->deterministic ? 1 : 0));
    sha_u64_le(&h, ctx ? ctx->time_start_ns : 0);
    sha_u64_le(&h, ctx ? ctx->time_step_ns : 0);
    sha_u64_le(&h, ctx ? ctx->rng_seed : 0);
    sha_u64_le(&h, ctx ? ctx->task_quantum_steps : 0);

    avm_sha256_final(&h, out);
}

void policy_hash_sha256(uint64_t used_domains_mask, const PolicyOp* ops, size_t ops_len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','P','O','L','0','1' };
    avm_sha256_update(&h, tag, 8);
    sha_u64_le(&h, used_domains_mask);
    sha_u32_le(&h, (uint32_t)ops_len);
    for (size_t i = 0; i < ops_len; i++) {
        sha_u8(&h, ops[i].domain);
        sha_u16_le(&h, ops[i].op);
    }
    avm_sha256_final(&h, out);
}

static int decode_u16(const uint8_t* code, size_t code_len, size_t pos, uint16_t* out) {
    if (pos + 2 > code_len) return 0;
    uint16_t v = (uint16_t)code[pos] | ((uint16_t)code[pos + 1] << 8);
    *out = v;
    return 1;
}

// Policy scanner (rolling): best-effort extraction of used (domain, op) pairs from bytecode.
// This is intended to be used "before execute" for governance/inspection, so it must be non-effectful.
// Conservative behavior is OK: scanning unreachable code is acceptable (over-approximation).
int policy_scan_program(const AvmProgram* prog, uint64_t* used_domains_mask_out, PolicyOp** ops_out, size_t* ops_len_out) {
    if (!prog || !prog->code || prog->code_len == 0) return 0;
    const uint8_t* code = prog->code;
    size_t code_len = prog->code_len;

    uint64_t domains = 0;
    PolicyOp* ops = NULL;
    size_t ops_len = 0;
    size_t ops_cap = 0;

    size_t pc = 0;
    while (pc < code_len) {
        uint8_t op = code[pc];
        size_t len = 1;

        if (op == 0x02) len = 3;
        else if (op == 0x04 || op == 0x05) len = 2;
        else if (op == 0x52 || op == 0x53) len = 3;
        else if (op == 0x06 || op == 0x07) len = 3;
        else if (op == 0x30 || op == 0x31) len = 3;
        else if (op == 0x4E || op == 0x4F) len = 5;
        else if (op == 0x38) len = 4;
        else if (op == 0x50) len = 6;
        else if (op == 0x3A) len = 4;
        else if (op == 0x3B) len = 5;
        else if (op == 0x3C) len = 3;
        else if (op == 0x51) len = 5;
        else if (op == 0x3D) len = 2;
        else if (op == 0x44) len = 2;
        else if (op == 0x3E) len = 2;
        else if (op == 0x3F) len = 2;
        else if (op == 0x40 || op == 0x41) len = 3;

        if (pc + len > code_len) { free(ops); return 0; }

        if (op == 0x3A) { // CALL_NATIVE u16_id u8_nargs
            uint16_t id = 0;
            if (!decode_u16(code, code_len, pc + 1, &id)) { free(ops); return 0; }
            uint8_t dom = 0;
            uint16_t capop = 0;
            avm_legacy_native_to_domop(id, &dom, &capop);
            domains |= (1ULL << (dom & 63));
            if (!policy_ops_add(&ops, &ops_len, &ops_cap, dom, capop)) { free(ops); return 0; }
        } else if (op == 0x3B) { // CALL_NATIVE2 u8_domain u16_op u8_nargs
            uint8_t dom = code[pc + 1];
            uint16_t capop = (uint16_t)code[pc + 2] | ((uint16_t)code[pc + 3] << 8);
            if (dom == 0) {
                uint8_t nd = 0;
                uint16_t nop = capop;
                avm_legacy_native_to_domop(capop, &nd, &nop);
                if (nd != 0) { dom = nd; capop = nop; }
            }
            domains |= (1ULL << (dom & 63));
            if (!policy_ops_add(&ops, &ops_len, &ops_cap, dom, capop)) { free(ops); return 0; }
        }

        pc += len;
    }

    qsort(ops, ops_len, sizeof(PolicyOp), policy_ops_cmp);

    if (used_domains_mask_out) *used_domains_mask_out = domains;
    if (ops_out) *ops_out = ops;
    else free(ops);
    if (ops_len_out) *ops_len_out = ops_len;
    return 1;
}

static uint64_t parse_domain_mask(const char* s) {
    if (!s || !s[0]) return 0; // 0 => allow all

    uint64_t mask = 0;
    const char* cur = s;
    while (*cur) {
        while (*cur == ' ' || *cur == ',') cur++;
        if (!*cur) break;

        char* end = NULL;
        unsigned long dom = strtoul(cur, &end, 10);
        if (end == cur) {
            // stop on invalid token
            break;
        }
        mask |= (1ULL << (dom & 63));
        cur = end;
        while (*cur == ' ' || *cur == ',') cur++;
    }
    return mask;
}

int parse_oren_domains_mask(const char* s, uint64_t* out_mask) {
    // Parse Oren-style capability domain names into an AVM domain bitmask.
    //
    // Accepts CSV tokens (case-insensitive):
    //   CORE, FS, TIME, RNG, NET, PROC, EXIT, ENV, AVM, ALL
    //
    // Used to bridge Oren native capsule env into AVM when running `avm` as a child process.
    if (!out_mask) return 0;
    *out_mask = 0;
    if (!s || !s[0]) return 1;

    uint64_t mask = 0;
    int saw_any = 0;
    const char* cur = s;
    while (*cur) {
        while (*cur == ' ' || *cur == ',') cur++;
        if (!*cur) break;

        const char* start = cur;
        while (*cur && *cur != ',') cur++;
        const char* end = cur;
        while (end > start && end[-1] == ' ') end--;
        if (end <= start) continue;

        saw_any = 1;
        size_t len = (size_t)(end - start);
        // fold to uppercase into a small temp buffer
        char t[16];
        if (len >= sizeof(t)) return 0;
        for (size_t i = 0; i < len; i++) {
            char c = start[i];
            if (c >= 'a' && c <= 'z') c = (char)(c - 32);
            t[i] = c;
        }
        t[len] = 0;

        if (strcmp(t, "ALL") == 0) { mask = ~0ULL; continue; }
        if (strcmp(t, "CORE") == 0) { mask |= (1ULL << 0); continue; }
        if (strcmp(t, "FS") == 0) { mask |= (1ULL << 1); continue; }
        if (strcmp(t, "TIME") == 0) { mask |= (1ULL << 2); continue; }
        if (strcmp(t, "RNG") == 0) { mask |= (1ULL << 3); continue; }
        if (strcmp(t, "NET") == 0) { mask |= (1ULL << 4); continue; }
        if (strcmp(t, "PROC") == 0) { mask |= (1ULL << 5); continue; }
        if (strcmp(t, "EXIT") == 0) { mask |= (1ULL << 6); continue; }
        if (strcmp(t, "ENV") == 0) { mask |= (1ULL << 7); continue; }
        if (strcmp(t, "AVM") == 0) { mask |= (1ULL << 8); continue; }
        return 0;
    }

    if (!saw_any) return 0;
    *out_mask = mask;
    return 1;
}

int parse_domain_mask_strict(const char* s, uint64_t* out_mask) {
    if (!out_mask) return 0;
    *out_mask = 0;
    if (!s || !s[0]) return 1; // empty is allowed (caller decides semantics)

    uint64_t mask = 0;
    int saw_any = 0;
    const char* cur = s;
    while (*cur) {
        while (*cur == ' ' || *cur == ',') cur++;
        if (!*cur) break;

        char* end = NULL;
        unsigned long dom = strtoul(cur, &end, 10);
        if (end == cur) return 0; // invalid token
        // After the number, only space/comma/end is valid.
        if (*end && *end != ' ' && *end != ',') return 0;

        saw_any = 1;
        mask |= (1ULL << (dom & 63));
        cur = end;
    }

    if (!saw_any) return 0;
    *out_mask = mask;
    return 1;
}
