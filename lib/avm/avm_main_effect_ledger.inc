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

static int avm_error_fields(AvmValue v, int64_t* code_out, const char** msg_out) {
    if (code_out) *code_out = -1;
    if (msg_out) *msg_out = NULL;
    if (v.type != AVM_VAL_MAP || !v.as.m) return 0;

    AvmMap* map = v.as.m;
    int is_err = 0;
    int64_t code = -1;
    const char* msg = NULL;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type != AVM_VAL_STRING) continue;
        const char* key = (const char*)k.as.p;
        AvmValue val = map->values[i];
        if (strcmp(key, "__err") == 0) {
            if (val.type == AVM_VAL_BOOL || val.type == AVM_VAL_INT) is_err = val.as.i != 0;
        } else if (strcmp(key, "code") == 0 && val.type == AVM_VAL_INT) {
            code = val.as.i;
        } else if (strcmp(key, "msg") == 0 && val.type == AVM_VAL_STRING) {
            msg = (const char*)val.as.p;
        }
    }
    if (!is_err) return 0;
    if (code_out) *code_out = code;
    if (msg_out) *msg_out = msg;
    return 1;
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
