#include "avm.h"
#include "sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <limits.h>

uint8_t* read_file(const char* path, size_t* len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    *len = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = (uint8_t*)malloc(*len);
    fread(buf, 1, *len, f);
    fclose(f);
    return buf;
}

static uint64_t now_ns() {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int is_err_map(AvmValue v) {
    if (v.type != AVM_VAL_MAP) return 0;
    AvmMap* map = v.as.m;
    if (!map) return 0;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && strcmp((char*)k.as.p, "__err") == 0) {
            AvmValue val = map->values[i];
            if (val.type == AVM_VAL_BOOL) return val.as.i != 0;
            if (val.type == AVM_VAL_INT) return val.as.i != 0;
            return 0;
        }
    }
    return 0;
}

static void dump_error(AvmValue v) {
    if (!is_err_map(v)) return;
    AvmMap* map = v.as.m;
    int64_t code = -1;
    const char* msg = NULL;

    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type != AVM_VAL_STRING) continue;
        if (strcmp((char*)k.as.p, "code") == 0 && map->values[i].type == AVM_VAL_INT) {
            code = map->values[i].as.i;
        }
        if (strcmp((char*)k.as.p, "msg") == 0 && map->values[i].type == AVM_VAL_STRING) {
            msg = (const char*)map->values[i].as.p;
        }
    }

    fprintf(stderr, "AVM error: code=%lld", (long long)code);
    if (msg) fprintf(stderr, " msg=%s", msg);
    fprintf(stderr, "\n");
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

static AvmBytes* bytes_from_hex(const char* s) {
    if (!s) return NULL;
    size_t n = strlen(s);
    if ((n & 1) != 0) return NULL;
    AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
    if (!b) return NULL;
    b->len = (int)(n / 2);
    b->capacity = b->len;
    b->data = NULL;
    if (b->len > 0) {
        b->data = (uint8_t*)malloc((size_t)b->len);
        if (!b->data) { free(b); return NULL; }
    }
    for (size_t i = 0; i < n; i += 2) {
        int hi = hex_nibble(s[i]);
        int lo = hex_nibble(s[i + 1]);
        if (hi < 0 || lo < 0) { free(b->data); free(b); return NULL; }
        b->data[i / 2] = (uint8_t)((hi << 4) | lo);
    }
    return b;
}

static char* bytes_to_hex(const uint8_t* data, size_t len) {
    static const char* hexd = "0123456789abcdef";
    char* out = (char*)malloc(len * 2 + 1);
    if (!out) return NULL;
    for (size_t i = 0; i < len; i++) {
        uint8_t v = data[i];
        out[i * 2] = hexd[(v >> 4) & 0xF];
        out[i * 2 + 1] = hexd[v & 0xF];
    }
    out[len * 2] = 0;
    return out;
}

typedef struct {
    int ok;
    char msg[512];
    uint64_t used_domains_mask;
} VerifyResult;

static VerifyResult ok_result() {
    VerifyResult r;
    r.ok = 1;
    r.msg[0] = 0;
    r.used_domains_mask = 0;
    return r;
}

static VerifyResult err_result(const char* msg) {
    VerifyResult r;
    r.ok = 0;
    snprintf(r.msg, sizeof(r.msg), "%s", msg ? msg : "verify failed");
    r.used_domains_mask = 0;
    return r;
}

static int decode_i16(const uint8_t* code, size_t code_len, size_t pos, int16_t* out) {
    if (pos + 2 > code_len) return 0;
    int16_t v = (int16_t)code[pos] | ((int16_t)code[pos + 1] << 8);
    *out = v;
    return 1;
}

static int decode_u16(const uint8_t* code, size_t code_len, size_t pos, uint16_t* out) {
    if (pos + 2 > code_len) return 0;
    uint16_t v = (uint16_t)code[pos] | ((uint16_t)code[pos + 1] << 8);
    *out = v;
    return 1;
}

// Minimal verifier (rolling, incremental):
// - validates operand bounds / jump targets / const bounds
// - validates stack underflow/overflow along reachable control flow (approximate for CALL/RET)
// - extracts used capability domains for policy scanning
//
// Notes:
// - CALL/RET are approximated to enable useful checking without full interprocedural analysis.
// - This verifier is meant to be strict enough to reject malformed bytecode and prevent common crashes/hangs.
static VerifyResult verify_program(const AvmProgram* prog) {
    if (!prog || !prog->code || prog->code_len == 0) return err_result("empty program");

    const uint8_t* code = prog->code;
    size_t code_len = prog->code_len;

    int* depth_at = (int*)malloc(sizeof(int) * code_len);
    if (!depth_at) return err_result("verify: out of memory");
    for (size_t i = 0; i < code_len; i++) depth_at[i] = INT_MIN;

    size_t* queue = (size_t*)malloc(sizeof(size_t) * code_len);
    int* qdepth = (int*)malloc(sizeof(int) * code_len);
    if (!queue || !qdepth) {
        free(depth_at);
        free(queue);
        free(qdepth);
        return err_result("verify: out of memory");
    }

    size_t qh = 0, qt = 0;
    queue[qt] = 0;
    qdepth[qt] = 0;
    qt++;

    uint64_t used_domains = 0;

    while (qh < qt) {
        size_t pc = queue[qh];
        int depth = qdepth[qh];
        qh++;

        if (pc >= code_len) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: pc out of bounds");
        }

        if (depth < 0) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: negative stack depth");
        }
        if (depth > AVM_STACK_SIZE) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: stack overflow");
        }

        if (depth_at[pc] != INT_MIN) {
            if (depth_at[pc] != depth) {
                free(depth_at);
                free(queue);
                free(qdepth);
                return err_result("verify: stack height mismatch at join");
            }
            continue;
        }
        depth_at[pc] = depth;

        uint8_t op = code[pc];
        size_t len = 1;
        int pop = 0;
        int push = 0;

        // decode/validate operands and compute instruction length + stack effect
        if (op == 0x00) { // NOP
            len = 1;
        } else if (op == 0x01) { // HALT
            len = 1;
        } else if (op == 0x02) { // PUSH_CONST u16
            len = 3;
            uint16_t idx = 0;
            if (!decode_u16(code, code_len, pc + 1, &idx)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated PUSH_CONST"); }
            if (idx >= prog->const_count) { free(depth_at); free(queue); free(qdepth); return err_result("verify: const index out of bounds"); }
            push = 1;
        } else if (op == 0x03) { // POP
            len = 1;
            pop = 1;
        } else if (op == 0x04) { // LOAD_LOCAL u8
            len = 2;
            push = 1;
        } else if (op == 0x05) { // STORE_LOCAL u8
            len = 2;
            pop = 1;
        } else if (op == 0x06) { // LOAD_GLOBAL u16
            len = 3;
            uint16_t idx = 0;
            if (!decode_u16(code, code_len, pc + 1, &idx)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated LOAD_GLOBAL"); }
            if (idx >= MAX_GLOBALS) { free(depth_at); free(queue); free(qdepth); return err_result("verify: global index out of bounds"); }
            push = 1;
        } else if (op == 0x07) { // STORE_GLOBAL u16
            len = 3;
            uint16_t idx = 0;
            if (!decode_u16(code, code_len, pc + 1, &idx)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated STORE_GLOBAL"); }
            if (idx >= MAX_GLOBALS) { free(depth_at); free(queue); free(qdepth); return err_result("verify: global index out of bounds"); }
            pop = 1;
        } else if (op >= 0x10 && op <= 0x1C) { // binary numeric ops + shifts + comparisons
            len = 1;
            pop = 2;
            push = 1;
        } else if (op == 0x20) { // PRINT
            len = 1;
            pop = 1;
        } else if (op == 0x30) { // JMP i16
            len = 3;
        } else if (op == 0x31) { // JMP_IF i16
            len = 3;
            pop = 1;
        } else if (op == 0x38) { // CALL u16_addr u8_nargs
            len = 4;
            uint16_t addr = 0;
            if (!decode_u16(code, code_len, pc + 1, &addr)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL"); }
            if (addr >= code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL addr out of bounds"); }
            uint8_t nargs = code[pc + 3];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL nargs too large"); }
            pop = (int)nargs;
            push = 1; // approximate: call returns a value
        } else if (op == 0x39) { // RET
            len = 1;
            pop = 1; // requires a return value on stack in current frame
        } else if (op == 0x3A) { // CALL_NATIVE u16_id u8_nargs
            len = 4;
            uint16_t id = 0;
            if (!decode_u16(code, code_len, pc + 1, &id)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE"); }
            uint8_t nargs = code[pc + 3];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE nargs too large"); }
            pop = (int)nargs;
            push = 1;

            // Legacy domain usage mapping (rolling):
            // FS ids: 0(read_file),1(write_file),17(write_bytes),18(read_bytes)
            uint8_t dom = 0;
            if (id == 0 || id == 1 || id == 17 || id == 18) dom = 1;
            used_domains |= (1ULL << (dom & 63));
        } else if (op == 0x3B) { // CALL_NATIVE2 u8_domain u16_op u8_nargs
            len = 5;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE2"); }
            uint8_t dom = code[pc + 1];
            uint8_t nargs = code[pc + 4];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE2 nargs too large"); }
            pop = (int)nargs;
            push = 1;
            used_domains |= (1ULL << (dom & 63));
        } else if (op == 0x40) { // NEW_LIST u16_count
            len = 3;
            uint16_t count = 0;
            if (!decode_u16(code, code_len, pc + 1, &count)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated NEW_LIST"); }
            pop = (int)count;
            push = 1;
        } else if (op == 0x41) { // NEW_MAP u16_count (pairs)
            len = 3;
            uint16_t count = 0;
            if (!decode_u16(code, code_len, pc + 1, &count)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated NEW_MAP"); }
            pop = (int)(count * 2);
            push = 1;
        } else if (op == 0x42) { // GET_INDEX
            len = 1;
            pop = 2;
            push = 1;
        } else if (op == 0x43) { // SET_INDEX
            len = 1;
            pop = 3;
            push = 0;
        } else {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: unknown opcode");
        }

        if (pc + len > code_len) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: truncated instruction");
        }

        if (depth < pop) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: stack underflow");
        }
        int next_depth = depth - pop + push;
        if (next_depth < 0 || next_depth > AVM_STACK_SIZE) {
            free(depth_at);
            free(queue);
            free(qdepth);
            return err_result("verify: stack overflow/underflow");
        }

        size_t pc_after = pc + len;

        // successors
        if (op == 0x01) { // HALT
            continue;
        }
        if (op == 0x39) { // RET: terminates this control-flow path in the verifier model
            continue;
        }
        if (op == 0x30 || op == 0x31) { // JMP/JMP_IF
            int16_t off = 0;
            if (!decode_i16(code, code_len, pc + 1, &off)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated JMP"); }
            int64_t target64 = (int64_t)pc_after + (int64_t)off;
            if (target64 < 0 || target64 >= (int64_t)code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: jump target out of bounds"); }
            size_t target = (size_t)target64;

            // push target successor
            queue[qt] = target;
            qdepth[qt] = next_depth;
            qt++;

            // JMP_IF also falls through
            if (op == 0x31) {
                if (pc_after < code_len) {
                    queue[qt] = pc_after;
                    qdepth[qt] = next_depth;
                    qt++;
                }
            }
            continue;
        }
        if (op == 0x38) { // CALL: explore callee entry too (best-effort)
            uint16_t addr = 0;
            if (!decode_u16(code, code_len, pc + 1, &addr)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL"); }
            if (addr < code_len) {
                queue[qt] = (size_t)addr;
                qdepth[qt] = depth; // interpreter keeps sp; args remain on stack in callee
                qt++;
            }
        }

        // default fallthrough
        if (pc_after < code_len) {
            queue[qt] = pc_after;
            qdepth[qt] = next_depth;
            qt++;
        }
    }

    free(depth_at);
    free(queue);
    free(qdepth);

    VerifyResult r = ok_result();
    r.used_domains_mask = used_domains;
    return r;
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

static void parse_fs_allow_prefixes(AvmVM* vm, const char* s) {
    if (!vm) return;
    if (!s || !s[0]) return; // empty => allow all

    // First pass: count commas + 1
    int count = 1;
    for (const char* p = s; *p; p++) {
        if (*p == ',') count++;
    }

    vm->fs_allow_prefixes = (char**)calloc((size_t)count, sizeof(char*));
    vm->fs_allow_prefix_count = 0;

    const char* cur = s;
    while (*cur) {
        while (*cur == ' ') cur++;
        const char* start = cur;
        while (*cur && *cur != ',') cur++;
        const char* end = cur;
        while (end > start && end[-1] == ' ') end--;

        size_t len = (size_t)(end - start);
        if (len > 0) {
            char* pref = (char*)malloc(len + 1);
            memcpy(pref, start, len);
            pref[len] = 0;
            vm->fs_allow_prefixes[vm->fs_allow_prefix_count++] = pref;
        }

        if (*cur == ',') cur++;
    }
}

int main(int argc, char** argv) {
    const char* obc_path = NULL;
    const char* snap_in = NULL;
    const char* snap_out = NULL;
    uint64_t step_limit = 0;
    int print_state_hash = 0;
    int print_result_hash = 0;
    int print_policy = 0;
    int print_record_log_hex = 0;

    int i = 1;
    while (i < argc) {
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
        if (strcmp(argv[i], "--print-record-log-hex") == 0) {
            print_record_log_hex = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-policy") == 0) {
            print_policy = 1;
            i += 1;
            continue;
        }
        if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown arg: %s\n", argv[i]);
            return 1;
        }
        obc_path = argv[i];
        i++;
    }

    if (!obc_path) {
        printf("Usage: avm [--snapshot-in file] [--snapshot-out file] [--step-limit N] [--print-state-hash] [--print-result-hash] [--print-record-log-hex] [--print-policy] <file.obc>\n");
        return 1;
    }
    size_t len;
    uint8_t* data = read_file(obc_path, &len);
    if (!data) {
        printf("Failed to read file\n");
        return 1;
    }
    
    // Parse OBC
    // Header: CD 0E
    if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) {
        printf("Invalid magic\n");
        return 1;
    }
    
    // Const count (u16)
    size_t pos = 2;
    uint16_t n_consts = data[pos] | (data[pos+1] << 8);
    pos += 2;
    
    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * n_consts);
    for (int i = 0; i < n_consts; i++) {
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
        }
        if (type == 1) { // INT
            int64_t val = 0;
            for (int k=0; k<8; k++) {
                val |= (int64_t)data[pos++] << (k*8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
        }
        if (type == 4) { // STRING
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            char* s = (char*)malloc((size_t)slen + 1);
            for (uint16_t k = 0; k < slen; k++) s[k] = (char)data[pos++];
            s[slen] = 0;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
        }
        if (type == 8) { // BYTES (rolling): u32 len + raw bytes
            if (pos + 4 > len) { fprintf(stderr, "Invalid BYTES const\n"); return 1; }
            uint32_t blen = (uint32_t)data[pos] | ((uint32_t)data[pos + 1] << 8) | ((uint32_t)data[pos + 2] << 16) | ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (pos + blen > len) { fprintf(stderr, "Invalid BYTES const\n"); return 1; }
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { fprintf(stderr, "OOM\n"); return 1; }
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)malloc((size_t)blen);
                if (!b->data) { fprintf(stderr, "OOM\n"); return 1; }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
        }
        // TODO: Other types
    }
    
    // Code
    uint8_t* code = data + pos;
    size_t code_len = len - pos;
    
    AvmProgram prog;
    prog.code = code;
    prog.code_len = code_len;
    prog.constants = consts;
    prog.const_count = n_consts;

    // Verifier (rolling): reject malformed bytecode early to avoid crashes/hangs.
    // Disable only for debugging with AVM_VERIFY=0.
    const char* verify_env = getenv("AVM_VERIFY");
    int verify = 1;
    if (verify_env && verify_env[0] == '0') verify = 0;
    if (verify) {
        VerifyResult vr = verify_program(&prog);
        if (!vr.ok) {
            fprintf(stderr, "AVM verify failed: %s\n", vr.msg);
            return 1;
        }
        if (print_policy) {
            printf("POLICY_USED_DOMAINS_MASK 0x%016llx\n", (unsigned long long)vr.used_domains_mask);
        }
    }
    
    AvmVM* vm = avm_new();
    vm->argc = argc - 1;
    vm->argv = argv + 1;

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
        return 1;
    }
    if ((replay_env && replay_env[0]) && (replay_hex_env && replay_hex_env[0])) {
        fprintf(stderr, "AVM_REPLAY_LOG and AVM_REPLAY_LOG_HEX are mutually exclusive\n");
        avm_free(vm);
        return 1;
    }
    if ((record_env && record_env[0]) && (record_mem_env && record_mem_env[0] && record_mem_env[0] != '0')) {
        fprintf(stderr, "AVM_RECORD_LOG and AVM_RECORD_MEM are mutually exclusive\n");
        avm_free(vm);
        return 1;
    }
    if (record_env && record_env[0]) {
        FILE* rf = fopen(record_env, "wb");
        if (!rf) {
            fprintf(stderr, "Failed to open record log: %s\n", record_env);
            avm_free(vm);
            return 1;
        }
        const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
        if (fwrite(magic, 1, 8, rf) != 8) {
            fprintf(stderr, "Failed to write log header: %s\n", record_env);
            fclose(rf);
            avm_free(vm);
            return 1;
        }
        vm->record_log = rf;
    }
    if (replay_env && replay_env[0]) {
        FILE* rf = fopen(replay_env, "rb");
        if (!rf) {
            fprintf(stderr, "Failed to open replay log: %s\n", replay_env);
            avm_free(vm);
            return 1;
        }
        uint8_t magic[8];
        if (fread(magic, 1, 8, rf) != 8) {
            fprintf(stderr, "Invalid replay log header: %s\n", replay_env);
            fclose(rf);
            avm_free(vm);
            return 1;
        }
        const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
        if (memcmp(magic, want, 8) != 0) {
            fprintf(stderr, "Invalid replay log magic: %s\n", replay_env);
            fclose(rf);
            avm_free(vm);
            return 1;
        }
        vm->replay_log = rf;
    }
    if (record_mem_env && record_mem_env[0] && record_mem_env[0] != '0') {
        // In-memory log: prepopulate header and record into vm->record_log_bytes.
        AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
        if (!b) { fprintf(stderr, "OOM\n"); avm_free(vm); return 1; }
        b->len = 8;
        b->capacity = 64;
        b->data = (uint8_t*)malloc((size_t)b->capacity);
        if (!b->data) { fprintf(stderr, "OOM\n"); free(b); avm_free(vm); return 1; }
        const uint8_t magic[8] = {'A','V','M','L','O','G','0','1'};
        memcpy(b->data, magic, 8);
        vm->record_log_bytes = b;
    }
    if (replay_hex_env && replay_hex_env[0]) {
        AvmBytes* b = bytes_from_hex(replay_hex_env);
        if (!b || b->len < 8) {
            fprintf(stderr, "Invalid AVM_REPLAY_LOG_HEX\n");
            if (b) { free(b->data); free(b); }
            avm_free(vm);
            return 1;
        }
        const uint8_t want[8] = {'A','V','M','L','O','G','0','1'};
        if (memcmp(b->data, want, 8) != 0) {
            fprintf(stderr, "Invalid replay log magic (hex)\n");
            free(b->data); free(b);
            avm_free(vm);
            return 1;
        }
        vm->replay_log_bytes = b;
        vm->replay_log_pos = 8;
    }

    // Deterministic mode (rolling):
    // - AVM_DETERMINISTIC=1 enables virtual TIME and deterministic RNG.
    // - AVM_TIME_START_NS sets initial virtual clock (default 0).
    // - AVM_TIME_STEP_NS sets per-now() increment (default 1ms).
    // - AVM_RNG_SEED seeds the deterministic RNG.
    const char* det_env = getenv("AVM_DETERMINISTIC");
    if (det_env && det_env[0] && det_env[0] != '0') vm->deterministic = 1;
    const char* t0_env = getenv("AVM_TIME_START_NS");
    if (t0_env && t0_env[0]) vm->virtual_now_ns = strtoull(t0_env, NULL, 10);
    const char* step_env = getenv("AVM_TIME_STEP_NS");
    if (step_env && step_env[0]) vm->virtual_step_ns = strtoull(step_env, NULL, 10);
    const char* seed_env = getenv("AVM_RNG_SEED");
    if (seed_env && seed_env[0]) vm->rng_state = strtoull(seed_env, NULL, 10);

    // Budgets/timeouts (macOS-first, rolling ABI):
    // - AVM_GAS: maximum instruction steps (0/unset = unlimited)
    // - AVM_TIMEOUT_MS: wall-time timeout in milliseconds (0/unset = unlimited)
    const char* gas_env = getenv("AVM_GAS");
    if (gas_env && gas_env[0]) vm->gas_remaining = strtoull(gas_env, NULL, 10);
    const char* timeout_env = getenv("AVM_TIMEOUT_MS");
    if (timeout_env && timeout_env[0]) {
        uint64_t ms = strtoull(timeout_env, NULL, 10);
        uint64_t base = now_ns();
        if (base != 0 && ms > 0) vm->deadline_ns = base + ms * 1000000ull;
    }

    // Capability enforcement (rolling ABI):
    // - AVM_ALLOW_DOMAINS: comma-separated domain integers (e.g. "0,1"). Unset/empty means allow all.
    // - AVM_FS_ALLOW_PREFIXES: comma-separated path prefixes; if set, FS paths must start with an allowed prefix.
    const char* domains_env = getenv("AVM_ALLOW_DOMAINS");
    vm->allowed_native_domains = parse_domain_mask(domains_env);
    const char* fs_allow_env = getenv("AVM_FS_ALLOW_PREFIXES");
    parse_fs_allow_prefixes(vm, fs_allow_env);

    avm_load(vm, &prog);

    if (snap_in) {
        if (avm_restore(vm, snap_in) != 0) {
            fprintf(stderr, "AVM restore failed: %s\n", snap_in);
            avm_free(vm);
            return 1;
        }
    }

    if (step_limit > 0) vm->pause_after_steps = step_limit;
    avm_run(vm);

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

    if (snap_out) {
        if (avm_snapshot(vm, snap_out) != 0) {
            fprintf(stderr, "AVM snapshot failed: %s\n", snap_out);
            // do not override execution result; just report and continue
        }
    }
    if (vm->exit_code != 0) {
        dump_error(vm->last_error);
    }
    int exit_code = vm->exit_code;
    if (vm->record_log) fclose(vm->record_log);
    if (vm->replay_log) fclose(vm->replay_log);

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
    
    return exit_code;
}
