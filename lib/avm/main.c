#include "avm.h"
#include "sha256.h"
#include "avm_help.inc"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#endif

uint8_t* read_file(const char* path, size_t* len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    *len = (size_t)sz;
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = NULL;
    if (*len > 0) {
        buf = (uint8_t*)malloc(*len);
        if (!buf) { fclose(f); return NULL; }
        size_t got = fread(buf, 1, *len, f);
        if (got != *len) { free(buf); fclose(f); return NULL; }
    }
    fclose(f);
    return buf;
}

static uint64_t now_ns() {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t current_rss_bytes() {
#if defined(__APPLE__)
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return 0;
    return (uint64_t)info.resident_size;
#elif defined(__linux__)
    FILE* f = fopen("/proc/self/statm", "r");
    if (!f) return 0;
    unsigned long size_pages = 0;
    unsigned long rss_pages = 0;
    int ok = fscanf(f, "%lu %lu", &size_pages, &rss_pages);
    fclose(f);
    if (ok != 2) return 0;
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) return 0;
    return (uint64_t)rss_pages * (uint64_t)page_size;
#else
    return 0;
#endif
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

static void free_constant_value(AvmValue v) {
    if (v.type == AVM_VAL_STRING) {
        if (v.as.p) free(v.as.p);
        return;
    }
    if (v.type == AVM_VAL_BYTES) {
        AvmBytes* b = v.as.b;
        if (!b) return;
        if (b->data) free(b->data);
        free(b);
        return;
    }
    if (v.type == AVM_VAL_LIST) {
        AvmList* l = v.as.l;
        if (!l) return;
        if (l->items) free(l->items);
        free(l);
        return;
    }
    if (v.type == AVM_VAL_MAP) {
        AvmMap* m = v.as.m;
        if (!m) return;
        if (m->keys) free(m->keys);
        if (m->values) free(m->values);
        free(m);
        return;
    }
}

static void free_constant_pool(AvmValue* consts, size_t n) {
    if (!consts) return;
    for (size_t i = 0; i < n; i++) free_constant_value(consts[i]);
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

// Verifier (rolling, incremental, now function-aware):
// - validates operand bounds / jump targets / const bounds
// - validates stack underflow/overflow + consistent stack height at CFG joins
// - extracts used capability domains for policy scanning
//
// Function-aware model (bootstrap):
// - "stack depth" tracked by the verifier is relative to the current frame pointer (fp), i.e. `sp - fp`.
// - root region starts at pc=0 with depth=0
// - a function entry is verified with initial depth = nargs (arguments on stack above fp)
// - CALL is *not* interprocedurally explored in the same CFG; instead, callees are queued and verified separately.
// - arity is enforced: all CALL sites to the same addr must use the same nargs.
static VerifyResult verify_program_region(
    const AvmProgram* prog,
    size_t start_pc,
    int start_depth,
    uint16_t region_id,
    uint64_t* used_domains_io,
    uint16_t* callees_out,
    uint8_t* callee_nargs_out,
    size_t* callee_count_io,
    size_t callee_cap,
    int strict_legacy
) {
    if (!prog || !prog->code || prog->code_len == 0) return err_result("empty program");
    const uint8_t* code = prog->code;
    size_t code_len = prog->code_len;

    if (start_pc >= code_len) return err_result("verify: entry pc out of bounds");
    if (start_depth < 0) return err_result("verify: negative entry stack depth");
    if (start_depth > AVM_STACK_SIZE) return err_result("verify: entry stack overflow");

    int* depth_at = (int*)malloc(sizeof(int) * code_len);
    size_t qcap = code_len ? code_len : 1;
    size_t* queue = (size_t*)malloc(sizeof(size_t) * qcap);
    int* qdepth = (int*)malloc(sizeof(int) * qcap);
    if (!depth_at || !queue || !qdepth) {
        free(depth_at);
        free(queue);
        free(qdepth);
        return err_result("verify: out of memory");
    }
    for (size_t i = 0; i < code_len; i++) depth_at[i] = INT_MIN;

    size_t qh = 0, qt = 0;
    queue[qt] = start_pc;
    qdepth[qt] = start_depth;
    qt++;

    while (qh < qt) {
        size_t pc = queue[qh];
        int depth = qdepth[qh];
        qh++;

        if (pc >= code_len) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: pc out of bounds");
        }
        if (depth < 0) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: negative stack depth");
        }
        if (depth > AVM_STACK_SIZE) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: stack overflow");
        }

        if (depth_at[pc] != INT_MIN) {
            if (depth_at[pc] != depth) {
                free(depth_at); free(queue); free(qdepth);
                VerifyResult r = ok_result();
                r.ok = 0;
                snprintf(r.msg, sizeof(r.msg),
                    "verify: stack height mismatch at join region=%u pc=%zu have=%d want=%d",
                    (unsigned)region_id, pc, depth, depth_at[pc]);
                r.used_domains_mask = used_domains_io ? *used_domains_io : 0;
                return r;
            }
            continue;
        }
        depth_at[pc] = depth;

        uint8_t op = code[pc];
        size_t len = 1;
        int pop = 0;
        int push = 0;

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
        } else if (op >= 0x10 && op <= 0x1E) { // binary numeric ops + shifts + comparisons
            len = 1;
            pop = 2;
            push = 1;
        } else if (op == 0x20) { // PRINT
            len = 1;
            pop = 1;
        } else if (op == 0x21) { // PRINT_LIST
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
            push = 1;

            // Record callee for outer verifier (call graph).
            if (callees_out && callee_nargs_out && callee_count_io && *callee_count_io < callee_cap) {
                callees_out[*callee_count_io] = addr;
                callee_nargs_out[*callee_count_io] = nargs;
                (*callee_count_io)++;
            }
        } else if (op == 0x39) { // RET
            len = 1;
            pop = 1;
        } else if (op == 0x3A) { // CALL_NATIVE u16_id u8_nargs
            len = 4;
            if (strict_legacy) { free(depth_at); free(queue); free(qdepth); return err_result("verify: legacy CALL_NATIVE is disallowed (strict)"); }
            uint16_t id = 0;
            if (!decode_u16(code, code_len, pc + 1, &id)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE"); }
            uint8_t nargs = code[pc + 3];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE nargs too large"); }
            pop = (int)nargs;
            push = 1;

            uint8_t dom = 0;
            uint16_t capop = 0;
            avm_legacy_native_to_domop(id, &dom, &capop);
            if (used_domains_io) *used_domains_io |= (1ULL << (dom & 63));
        } else if (op == 0x3B) { // CALL_NATIVE2 u8_domain u16_op u8_nargs
            len = 5;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE2"); }
            uint8_t dom = code[pc + 1];
            uint16_t cop = (uint16_t)code[pc + 2] | ((uint16_t)code[pc + 3] << 8);
            uint8_t nargs = code[pc + 4];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE2 nargs too large"); }
            pop = (int)nargs;
            push = 1;

            // Strict mode: disallow CORE-domain encoding when it actually targets an effectful domain
            // via legacy-id remapping (bypass form).
            uint8_t eff_dom = dom;
            if (dom == 0) {
                uint8_t nd = 0;
                uint16_t nop = cop;
                avm_legacy_native_to_domop(cop, &nd, &nop);
                if (nd != 0) {
                    if (strict_legacy) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CORE/legacy bypass CALL_NATIVE2 is disallowed (strict)"); }
                    eff_dom = nd;
                }
            }
            if (used_domains_io) *used_domains_io |= (1ULL << (eff_dom & 63));
        } else if (op == 0x3C) { // PUSH_FUNC u16_addr
            len = 3;
            uint16_t addr = 0;
            if (!decode_u16(code, code_len, pc + 1, &addr)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated PUSH_FUNC"); }
            if (addr >= code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: PUSH_FUNC addr out of bounds"); }
            pop = 0;
            push = 1;
        } else if (op == 0x3D) { // CALL_INDIRECT u8_nargs
            len = 2;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_INDIRECT"); }
            uint8_t nargs = code[pc + 1];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_INDIRECT nargs too large"); }
            pop = (int)nargs + 1; // fn + args
            push = 1;
        } else if (op == 0x44) { // CALL_INDIRECT_SPREAD u8_fixed
            len = 2;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_INDIRECT_SPREAD"); }
            uint8_t fixed = code[pc + 1];
            if (fixed > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_INDIRECT_SPREAD fixed too large"); }
            pop = (int)fixed + 2; // fn + fixed args + spread list
            push = 1;
        } else if (op == 0x3E) { // MAKE_CLOSURE u8_ncap
            len = 2;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated MAKE_CLOSURE"); }
            uint8_t ncap = code[pc + 1];
            if (ncap > 32) { free(depth_at); free(queue); free(qdepth); return err_result("verify: MAKE_CLOSURE ncap too large"); }
            pop = (int)ncap + 1; // captures + base fn
            push = 1;
        } else if (op == 0x3F) { // LOAD_ENV u8_idx
            len = 2;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated LOAD_ENV"); }
            pop = 0;
            push = 1;
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
        } else if (op == 0x45) { // SPAWN_CALL_LIST
            len = 1;
            pop = 2;  // fn + args_list
            push = 1; // handle
        } else if (op == 0x46) { // JOIN
            len = 1;
            pop = 1;
            push = 1;
        } else if (op == 0x47) { // CHAN_NEW
            len = 1;
            pop = 0;
            push = 1;
        } else if (op == 0x48) { // CHAN_SEND
            len = 1;
            pop = 2;  // ch + val
            push = 1; // ok
        } else if (op == 0x49) { // CHAN_RECV
            len = 1;
            pop = 1;  // ch
            push = 1; // val
        } else if (op == 0x4A) { // SELECT_RECV
            len = 1;
            pop = 1;  // list<ch>
            push = 1; // [idx, val]
        } else if (op == 0x4B) { // YIELD
            len = 1;
            pop = 0;
            push = 0;
        } else {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: unknown opcode");
        }

        if (pc + len > code_len) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: truncated instruction");
        }

        if (depth < pop) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: stack underflow");
        }
        int next_depth = depth - pop + push;
        if (next_depth < 0 || next_depth > AVM_STACK_SIZE) {
            free(depth_at); free(queue); free(qdepth);
            return err_result("verify: stack overflow/underflow");
        }

        size_t pc_after = pc + len;

        // successors
        if (op == 0x01) continue; // HALT
        if (op == 0x39) continue; // RET terminates the region path

        if (op == 0x30 || op == 0x31) { // JMP/JMP_IF
            int16_t off = 0;
            if (!decode_i16(code, code_len, pc + 1, &off)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated JMP"); }
            int64_t target64 = (int64_t)pc_after + (int64_t)off;
            if (target64 < 0 || target64 >= (int64_t)code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: jump target out of bounds"); }
            size_t target = (size_t)target64;

            if (qt >= qcap) {
                size_t nc = qcap * 2;
                size_t* nq = (size_t*)realloc(queue, sizeof(size_t) * nc);
                int* nd = (int*)realloc(qdepth, sizeof(int) * nc);
                if (!nq || !nd) {
                    free(nq ? nq : queue);
                    free(nd ? nd : qdepth);
                    free(depth_at);
                    return err_result("verify: out of memory");
                }
                queue = nq;
                qdepth = nd;
                qcap = nc;
            }
            queue[qt] = target;
            qdepth[qt] = next_depth;
            qt++;

            if (op == 0x31) {
                if (pc_after < code_len) {
                    if (qt >= qcap) {
                        size_t nc = qcap * 2;
                        size_t* nq = (size_t*)realloc(queue, sizeof(size_t) * nc);
                        int* nd = (int*)realloc(qdepth, sizeof(int) * nc);
                        if (!nq || !nd) {
                            free(nq ? nq : queue);
                            free(nd ? nd : qdepth);
                            free(depth_at);
                            return err_result("verify: out of memory");
                        }
                        queue = nq;
                        qdepth = nd;
                        qcap = nc;
                    }
                    queue[qt] = pc_after;
                    qdepth[qt] = next_depth;
                    qt++;
                }
            }
            continue;
        }

        // default fallthrough
        if (pc_after < code_len) {
            if (qt >= qcap) {
                size_t nc = qcap * 2;
                size_t* nq = (size_t*)realloc(queue, sizeof(size_t) * nc);
                int* nd = (int*)realloc(qdepth, sizeof(int) * nc);
                if (!nq || !nd) {
                    free(nq ? nq : queue);
                    free(nd ? nd : qdepth);
                    free(depth_at);
                    return err_result("verify: out of memory");
                }
                queue = nq;
                qdepth = nd;
                qcap = nc;
            }
            queue[qt] = pc_after;
            qdepth[qt] = next_depth;
            qt++;
        }
    }

    free(depth_at);
    free(queue);
    free(qdepth);

    VerifyResult r = ok_result();
    r.used_domains_mask = used_domains_io ? *used_domains_io : 0;
    return r;
}

typedef struct {
    uint16_t addr;
    uint8_t nargs;
    uint8_t verified;
} VerifyFunc;

static int find_func(VerifyFunc* funcs, size_t n, uint16_t addr) {
    for (size_t i = 0; i < n; i++) if (funcs[i].addr == addr) return (int)i;
    return -1;
}

static VerifyResult ensure_funcs_cap(VerifyFunc** funcs_io, size_t* cap_io, size_t need) {
    if (!funcs_io || !cap_io) return err_result("verify: internal error");
    if (need <= *cap_io) return ok_result();
    size_t nc = (*cap_io) ? (*cap_io) * 2 : 16;
    while (nc < need) nc *= 2;
    void* np = realloc(*funcs_io, sizeof(VerifyFunc) * nc);
    if (!np) return err_result("verify: out of memory");
    *funcs_io = (VerifyFunc*)np;
    *cap_io = nc;
    return ok_result();
}

static VerifyResult ensure_worklist_cap(
    uint16_t** wl_io,
    uint8_t** wl_nargs_io,
    size_t* cap_io,
    size_t need
) {
    if (!wl_io || !wl_nargs_io || !cap_io) return err_result("verify: internal error");
    if (need <= *cap_io) return ok_result();
    size_t nc = (*cap_io) ? (*cap_io) * 2 : 16;
    while (nc < need) nc *= 2;
    uint16_t* nw = (uint16_t*)realloc(*wl_io, sizeof(uint16_t) * nc);
    if (!nw) return err_result("verify: out of memory");
    uint8_t* nn = (uint8_t*)realloc(*wl_nargs_io, sizeof(uint8_t) * nc);
    if (!nn) {
        *wl_io = nw;
        return err_result("verify: out of memory");
    }
    *wl_io = nw;
    *wl_nargs_io = nn;
    *cap_io = nc;
    return ok_result();
}

static VerifyResult enqueue_func(
    VerifyFunc** funcs_io,
    size_t* funcs_len_io,
    size_t* funcs_cap_io,
    uint16_t** wl_io,
    uint8_t** wl_nargs_io,
    size_t* wl_t_io,
    size_t* wl_cap_io,
    uint64_t used_domains_mask,
    uint16_t addr,
    uint8_t nargs
) {
    if (!funcs_io || !funcs_len_io || !funcs_cap_io || !wl_io || !wl_nargs_io || !wl_t_io || !wl_cap_io) {
        return err_result("verify: internal error");
    }

    int idx = find_func(*funcs_io, *funcs_len_io, addr);
    if (idx >= 0) {
        if ((*funcs_io)[(size_t)idx].nargs != nargs) {
            VerifyResult r = ok_result();
            r.ok = 0;
            snprintf(r.msg, sizeof(r.msg), "verify: CALL arity mismatch addr=%u have=%u want=%u",
                (unsigned)addr, (unsigned)nargs, (unsigned)(*funcs_io)[(size_t)idx].nargs);
            r.used_domains_mask = used_domains_mask;
            return r;
        }
        if (!(*funcs_io)[(size_t)idx].verified) {
            VerifyResult cr = ensure_worklist_cap(wl_io, wl_nargs_io, wl_cap_io, (*wl_t_io) + 1);
            if (!cr.ok) return cr;
            (*wl_io)[*wl_t_io] = addr;
            (*wl_nargs_io)[*wl_t_io] = nargs;
            (*wl_t_io)++;
        }
        return ok_result();
    }

    VerifyResult fr = ensure_funcs_cap(funcs_io, funcs_cap_io, (*funcs_len_io) + 1);
    if (!fr.ok) return fr;
    (*funcs_io)[*funcs_len_io].addr = addr;
    (*funcs_io)[*funcs_len_io].nargs = nargs;
    (*funcs_io)[*funcs_len_io].verified = 0;
    (*funcs_len_io)++;

    VerifyResult cr = ensure_worklist_cap(wl_io, wl_nargs_io, wl_cap_io, (*wl_t_io) + 1);
    if (!cr.ok) return cr;
    (*wl_io)[*wl_t_io] = addr;
    (*wl_nargs_io)[*wl_t_io] = nargs;
    (*wl_t_io)++;
    return ok_result();
}

static VerifyResult verify_program(const AvmProgram* prog, int strict_legacy) {
    if (!prog || !prog->code || prog->code_len == 0) return err_result("empty program");

    uint64_t used_domains = 0;

    VerifyFunc* funcs = NULL;
    size_t funcs_len = 0;
    size_t funcs_cap = 0;

    uint16_t* wl = NULL;
    uint8_t* wl_nargs = NULL;
    size_t wl_h = 0, wl_t = 0, wl_cap = 0;

    // Verify root region (pc=0). Collect initial call graph.
    {
        // Use local buffers for callee discovery (worst-case: code_len CALL sites).
        size_t cap = prog->code_len;
        uint16_t* callees = (uint16_t*)malloc(sizeof(uint16_t) * cap);
        uint8_t* cnargs = (uint8_t*)malloc(sizeof(uint8_t) * cap);
        size_t ccnt = 0;
        if ((!callees || !cnargs) && cap > 0) { free(callees); free(cnargs); free(funcs); free(wl); free(wl_nargs); return err_result("verify: out of memory"); }

        VerifyResult vr = verify_program_region(prog, 0, 0, 0xFFFFu, &used_domains, callees, cnargs, &ccnt, cap, strict_legacy);
        for (size_t i = 0; i < ccnt && vr.ok; i++) {
            VerifyResult er = enqueue_func(&funcs, &funcs_len, &funcs_cap, &wl, &wl_nargs, &wl_t, &wl_cap, used_domains, callees[i], cnargs[i]);
            if (!er.ok) vr = er;
        }

        free(callees);
        free(cnargs);
        if (!vr.ok) { free(funcs); free(wl); free(wl_nargs); return vr; }
    }

    // Verify each reachable function region once.
    while (wl_h < wl_t) {
        uint16_t addr = wl[wl_h];
        uint8_t nargs = wl_nargs[wl_h];
        wl_h++;

        int idx = find_func(funcs, funcs_len, addr);
        if (idx < 0) continue;
        if (funcs[idx].verified) continue;

        size_t cap = prog->code_len;
        uint16_t* callees = (uint16_t*)malloc(sizeof(uint16_t) * cap);
        uint8_t* cnargs = (uint8_t*)malloc(sizeof(uint8_t) * cap);
        size_t ccnt = 0;
        if ((!callees || !cnargs) && cap > 0) { free(callees); free(cnargs); free(funcs); free(wl); free(wl_nargs); return err_result("verify: out of memory"); }

        VerifyResult vr = verify_program_region(prog, (size_t)addr, (int)nargs, addr, &used_domains, callees, cnargs, &ccnt, cap, strict_legacy);
        for (size_t i = 0; i < ccnt && vr.ok; i++) {
            VerifyResult er = enqueue_func(&funcs, &funcs_len, &funcs_cap, &wl, &wl_nargs, &wl_t, &wl_cap, used_domains, callees[i], cnargs[i]);
            if (!er.ok) vr = er;
        }

        free(callees);
        free(cnargs);

        if (!vr.ok) { free(funcs); free(wl); free(wl_nargs); return vr; }
        funcs[idx].verified = 1;
    }

    free(funcs);
    free(wl);
    free(wl_nargs);

    VerifyResult r = ok_result();
    r.used_domains_mask = used_domains;
    return r;
}

typedef struct {
    uint8_t domain;
    uint16_t op;
} PolicyOp;

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

static void sha256_bytes(const uint8_t* data, size_t len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    if (data && len > 0) avm_sha256_update(&h, data, len);
    avm_sha256_final(&h, out);
}

static void sha256_tagged_bytes8(const char tag8[8], const uint8_t* data, size_t len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    if (tag8) avm_sha256_update(&h, (const uint8_t*)tag8, 8);
    if (data && len > 0) avm_sha256_update(&h, data, len);
    avm_sha256_final(&h, out);
}

static void sha256_job_v1(const uint8_t program_hash[32], const uint8_t policy_hash[32], const uint8_t input_hash[32], uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t tag[8] = { 'A','V','M','J','O','B','0','1' };
    avm_sha256_update(&h, tag, 8);
    avm_sha256_update(&h, program_hash, 32);
    avm_sha256_update(&h, policy_hash, 32);
    avm_sha256_update(&h, input_hash, 32);
    avm_sha256_final(&h, out);
}

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

static void ctx_hash_sha256_v8(
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

    avm_sha256_final(&h, out);
}

static void sha256_job_v2(
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

static void sha256_job_v3(
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

static void sha256_job_v4(
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

static void sha256_job_v6(
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

static void sha256_job_v7(
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

static void policy_hash_sha256(uint64_t used_domains_mask, const PolicyOp* ops, size_t ops_len, uint8_t out[32]) {
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

// Policy scanner (rolling): best-effort extraction of used (domain, op) pairs from bytecode.
// This is intended to be used "before execute" for governance/inspection, so it must be non-effectful.
// Conservative behavior is OK: scanning unreachable code is acceptable (over-approximation).
static int policy_scan_program(const AvmProgram* prog, uint64_t* used_domains_mask_out, PolicyOp** ops_out, size_t* ops_len_out) {
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
        else if (op == 0x06 || op == 0x07) len = 3;
        else if (op == 0x30 || op == 0x31) len = 3;
        else if (op == 0x38) len = 4;
        else if (op == 0x3A) len = 4;
        else if (op == 0x3B) len = 5;
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

static int env_truthy(const char* s) {
    if (!s || !s[0]) return 0;
    if (s[0] == '0' && !s[1]) return 0;
    return 1;
}

static int parse_oren_domains_mask(const char* s, uint64_t* out_mask) {
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

static int parse_domain_mask_strict(const char* s, uint64_t* out_mask) {
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

static void free_fs_mounts(char*** virt, char*** host, int* count) {
    if (virt && *virt) {
        for (int i = 0; count && i < *count; i++) {
            if ((*virt)[i]) free((*virt)[i]);
        }
        free(*virt);
        *virt = NULL;
    }
    if (host && *host) {
        for (int i = 0; count && i < *count; i++) {
            if ((*host)[i]) free((*host)[i]);
        }
        free(*host);
        *host = NULL;
    }
    if (count) *count = 0;
}

static void parse_fs_mounts(char*** out_virt, char*** out_host, int* out_count, const char* s) {
    if (!out_virt || !out_host || !out_count) return;
    free_fs_mounts(out_virt, out_host, out_count);
    if (!s || !s[0]) return; // empty => no mounts configured

    // Count candidate tokens (CSV)
    int count = 0;
    for (const char* p = s; *p; p++) {
        if (*p == ',') count++;
    }
    count++; // commas + 1

    char** v = (char**)calloc((size_t)count, sizeof(char*));
    char** h = (char**)calloc((size_t)count, sizeof(char*));
    if (!v || !h) { if (v) free(v); if (h) free(h); return; }

    int n = 0;
    const char* cur = s;
    while (*cur) {
        while (*cur == ' ') cur++;
        const char* start = cur;
        while (*cur && *cur != ',') cur++;
        const char* end = cur;
        while (end > start && end[-1] == ' ') end--;

        // Split on first '='
        const char* eq = NULL;
        for (const char* p = start; p < end; p++) {
            if (*p == '=') { eq = p; break; }
        }
        if (eq && eq > start && (eq + 1) < end) {
            const char* vs = start;
            const char* ve = eq;
            const char* hs = eq + 1;
            const char* he = end;
            while (ve > vs && ve[-1] == ' ') ve--;
            while (hs < he && *hs == ' ') hs++;
            while (he > hs && he[-1] == ' ') he--;

            size_t vl = (size_t)(ve - vs);
            size_t hl = (size_t)(he - hs);
            if (vl > 0 && hl > 0) {
                v[n] = (char*)malloc(vl + 1);
                h[n] = (char*)malloc(hl + 1);
                if (!v[n] || !h[n]) {
                    if (v[n]) free(v[n]);
                    if (h[n]) free(h[n]);
                } else {
                    memcpy(v[n], vs, vl); v[n][vl] = 0;
                    memcpy(h[n], hs, hl); h[n][hl] = 0;
                    n++;
                }
            }
        }

        if (*cur == ',') cur++;
    }

    *out_virt = v;
    *out_host = h;
    *out_count = n;
}

static int parse_fs_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vfs") == 0) { *out_kind = 1; return 1; }
    return 0;
}

static int parse_proc_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vproc") == 0) { *out_kind = 1; return 1; }
    return 0;
}

static int parse_net_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vnet") == 0) { *out_kind = 1; return 1; }
    return 0;
}

static const char* op_name(uint8_t op) {
    switch (op) {
        case 0x00: return "NOP";
        case 0x01: return "HALT";
        case 0x02: return "PUSH_CONST";
        case 0x03: return "POP";
        case 0x04: return "LOAD_LOCAL";
        case 0x05: return "STORE_LOCAL";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x12: return "LT";
        case 0x13: return "EQ";
        case 0x14: return "NEQ";
        case 0x15: return "GT";
        case 0x16: return "LE";
        case 0x17: return "GE";
        case 0x18: return "AND";
        case 0x19: return "OR";
        case 0x1A: return "XOR";
        case 0x1B: return "SHL";
        case 0x1C: return "SHR";
        case 0x20: return "PRINT";
        case 0x21: return "PRINT_LIST";
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x38: return "CALL";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x3C: return "PUSH_FUNC";
        case 0x3D: return "CALL_INDIRECT";
        case 0x44: return "CALL_INDIRECT_SPREAD";
        case 0x3E: return "MAKE_CLOSURE";
        case 0x3F: return "LOAD_ENV";
        case 0x40: return "NEW_LIST";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x43: return "SET_INDEX";
        default: return "OP?";
    }
}

static void disasm_const(FILE* out, const AvmProgram* prog, uint16_t idx) {
    if (!out || !prog || idx >= prog->const_count) return;
    AvmValue v = prog->constants[idx];
    fprintf(out, "c%u=", (unsigned)idx);
    if (v.type == AVM_VAL_NIL) fprintf(out, "nil");
    else if (v.type == AVM_VAL_INT) fprintf(out, "%lld", (long long)v.as.i);
    else if (v.type == AVM_VAL_BOOL) fprintf(out, "%s", v.as.i ? "true" : "false");
    else if (v.type == AVM_VAL_FLOAT) fprintf(out, "%f", v.as.f);
    else if (v.type == AVM_VAL_STRING) fprintf(out, "\"%s\"", v.as.p ? (char*)v.as.p : "");
    else if (v.type == AVM_VAL_BYTES) fprintf(out, "<bytes len=%d>", v.as.b ? v.as.b->len : 0);
    else if (v.type == AVM_VAL_LIST) fprintf(out, "<list>");
    else if (v.type == AVM_VAL_MAP) fprintf(out, "<map>");
    else if (v.type == AVM_VAL_FUNC) fprintf(out, "<func addr=%u>", v.as.fn ? (unsigned)v.as.fn->addr : 0u);
    else fprintf(out, "<val?>");
}

static void json_print_escaped(FILE* out, const char* s) {
    if (!out) return;
    if (!s) s = "";
    for (const char* p = s; *p; p++) {
        if (*p == '\\' || *p == '\"') { fprintf(out, "\\%c", *p); }
        else if (*p == '\n') { fprintf(out, "\\n"); }
        else if (*p == '\r') { fprintf(out, "\\r"); }
        else if (*p == '\t') { fprintf(out, "\\t"); }
        else { fputc(*p, out); }
    }
}

static const char* avm_val_type_name(AvmValue v) {
    switch (v.type) {
        case AVM_VAL_NIL: return "NIL";
        case AVM_VAL_INT: return "INT";
        case AVM_VAL_BOOL: return "BOOL";
        case AVM_VAL_FLOAT: return "FLOAT";
        case AVM_VAL_STRING: return "STRING";
        case AVM_VAL_BYTES: return "BYTES";
        case AVM_VAL_LIST: return "LIST";
        case AVM_VAL_MAP: return "MAP";
        case AVM_VAL_FUNC: return "FUNC";
        default: return "VAL?";
    }
}

static size_t disasm_insn_len(const uint8_t* code, size_t code_len, size_t pc) {
    if (!code || pc >= code_len) return 1;
    uint8_t op = code[pc];
    if (op == 0x02) return 3;                 // PUSH_CONST u16
    if (op == 0x04 || op == 0x05) return 2;   // LOAD/STORE_LOCAL u8
    if (op == 0x06 || op == 0x07) return 3;   // LOAD/STORE_GLOBAL u16
    if (op == 0x30 || op == 0x31) return 3;   // JMP/JMP_IF i16
    if (op == 0x38) return 4;                 // CALL u16 u8
    if (op == 0x3A) return 4;                 // CALL_NATIVE u16 u8
    if (op == 0x3B) return 5;                 // CALL_NATIVE2 u8 u16 u8
    if (op == 0x3C) return 3;                 // PUSH_FUNC u16
    if (op == 0x3D) return 2;                 // CALL_INDIRECT u8
    if (op == 0x44) return 2;                 // CALL_INDIRECT_SPREAD u8
    if (op == 0x3E) return 2;                 // MAKE_CLOSURE u8
    if (op == 0x3F) return 2;                 // LOAD_ENV u8
    if (op == 0x40 || op == 0x41) return 3;   // NEW_LIST/NEW_MAP u16
    return 1;
}

static void disasm_program_json(FILE* out, const AvmProgram* prog, int show_consts) {
    if (!out || !prog) return;

    fprintf(out, "{");
    fprintf(out, "\"schema\":\"avm.disasm.v1\"");
    fprintf(out, ",\"const_count\":%llu", (unsigned long long)prog->const_count);
    fprintf(out, ",\"code_len\":%llu", (unsigned long long)prog->code_len);

    if (show_consts) {
        fprintf(out, ",\"consts\":[");
        for (uint16_t i = 0; i < prog->const_count; i++) {
            if (i) fprintf(out, ",");
            AvmValue v = prog->constants[i];
            fprintf(out, "{\"idx\":%u,\"type\":\"%s\"", (unsigned)i, avm_val_type_name(v));
            if (v.type == AVM_VAL_INT) {
                fprintf(out, ",\"i64\":%lld", (long long)v.as.i);
            } else if (v.type == AVM_VAL_BOOL) {
                fprintf(out, ",\"value\":%s", v.as.i ? "true" : "false");
            } else if (v.type == AVM_VAL_FLOAT) {
                fprintf(out, ",\"value\":%f", v.as.f);
            } else if (v.type == AVM_VAL_STRING) {
                fprintf(out, ",\"value\":\"");
                json_print_escaped(out, v.as.p ? (const char*)v.as.p : "");
                fprintf(out, "\"");
            } else if (v.type == AVM_VAL_BYTES) {
                fprintf(out, ",\"len\":%d", v.as.b ? v.as.b->len : 0);
            }
            fprintf(out, "}");
        }
        fprintf(out, "]");
    }

    fprintf(out, ",\"code\":[");
    size_t pc = 0;
    const uint8_t* code = prog->code;
    int first = 1;
    while (pc < prog->code_len) {
        uint8_t op = code[pc];
        size_t want_len = disasm_insn_len(code, prog->code_len, pc);
        size_t remain = prog->code_len - pc;
        size_t actual_len = want_len <= remain ? want_len : remain;
        int truncated = (want_len > remain) ? 1 : 0;

        char* hx = bytes_to_hex(code + pc, actual_len);

        if (!first) fprintf(out, ",");
        first = 0;
        fprintf(out, "{\"pc\":%llu", (unsigned long long)pc);
        fprintf(out, ",\"op\":%u", (unsigned)op);
        fprintf(out, ",\"op_name\":\"%s\"", op_name(op));
        fprintf(out, ",\"len\":%llu", (unsigned long long)actual_len);
        fprintf(out, ",\"truncated\":%s", truncated ? "true" : "false");
        fprintf(out, ",\"bytes_hex\":\"%s\"", hx ? hx : "");

        if (!truncated) {
            if (op == 0x02) { // PUSH_CONST u16
                uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"const_idx\":%u}", (unsigned)idx);
            } else if (op == 0x04 || op == 0x05) { // LOAD/STORE_LOCAL u8
                fprintf(out, ",\"operands\":{\"local\":%u}", (unsigned)code[pc + 1]);
            } else if (op == 0x06 || op == 0x07) { // LOAD/STORE_GLOBAL u16
                uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"global\":%u}", (unsigned)idx);
            } else if (op == 0x30 || op == 0x31) { // JMP/JMP_IF i16
                int16_t off = (int16_t)((uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8));
                size_t pc_after = pc + 3;
                int64_t target = (int64_t)pc_after + (int64_t)off;
                fprintf(out, ",\"operands\":{\"off\":%d,\"target\":%lld}", (int)off, (long long)target);
            } else if (op == 0x38) { // CALL u16_addr u8_nargs
                uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                uint8_t nargs = code[pc + 3];
                fprintf(out, ",\"operands\":{\"addr\":%u,\"nargs\":%u}", (unsigned)addr, (unsigned)nargs);
            } else if (op == 0x3A) { // CALL_NATIVE u16 id u8 nargs
                uint16_t id = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                uint8_t nargs = code[pc + 3];
                fprintf(out, ",\"operands\":{\"id\":%u,\"nargs\":%u}", (unsigned)id, (unsigned)nargs);
            } else if (op == 0x3B) { // CALL_NATIVE2 u8 dom u16 op u8 nargs
                uint8_t dom = code[pc + 1];
                uint16_t nop = (uint16_t)code[pc + 2] | ((uint16_t)code[pc + 3] << 8);
                uint8_t nargs = code[pc + 4];
                fprintf(out, ",\"operands\":{\"domain\":%u,\"capop\":%u,\"nargs\":%u}", (unsigned)dom, (unsigned)nop, (unsigned)nargs);
            } else if (op == 0x3C) { // PUSH_FUNC u16 addr
                uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"addr\":%u}", (unsigned)addr);
            } else if (op == 0x3D) { // CALL_INDIRECT u8 nargs
                uint8_t nargs = code[pc + 1];
                fprintf(out, ",\"operands\":{\"nargs\":%u}", (unsigned)nargs);
            } else if (op == 0x44) { // CALL_INDIRECT_SPREAD u8 fixed
                uint8_t fixed = code[pc + 1];
                fprintf(out, ",\"operands\":{\"fixed\":%u}", (unsigned)fixed);
            } else if (op == 0x3E) { // MAKE_CLOSURE u8 ncap
                uint8_t ncap = code[pc + 1];
                fprintf(out, ",\"operands\":{\"ncap\":%u}", (unsigned)ncap);
            } else if (op == 0x3F) { // LOAD_ENV u8 idx
                uint8_t idx = code[pc + 1];
                fprintf(out, ",\"operands\":{\"idx\":%u}", (unsigned)idx);
            } else if (op == 0x40 || op == 0x41) { // NEW_LIST/NEW_MAP u16 count
                uint16_t cnt = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"count\":%u}", (unsigned)cnt);
            }
        }

        fprintf(out, "}");
        if (hx) free(hx);
        pc += actual_len ? actual_len : 1;
    }
    fprintf(out, "]");
    fprintf(out, "}\n");
}

static void disasm_program(FILE* out, const AvmProgram* prog, int show_consts) {
    if (!out || !prog) return;
    if (show_consts) {
        fprintf(out, "== CONSTS (%zu) ==\n", prog->const_count);
        for (uint16_t i = 0; i < prog->const_count; i++) {
            fprintf(out, "  ");
            disasm_const(out, prog, i);
            fprintf(out, "\n");
        }
    }

    fprintf(out, "== CODE (%zu bytes) ==\n", prog->code_len);
    size_t pc = 0;
    const uint8_t* code = prog->code;
    while (pc < prog->code_len) {
        uint8_t op = code[pc];
        fprintf(out, "%04zu: 0x%02x %-12s", pc, (unsigned)op, op_name(op));

        if (op == 0x02 && pc + 3 <= prog->code_len) { // PUSH_CONST u16
            uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " ");
            disasm_const(out, prog, idx);
            pc += 3;
        } else if (op == 0x04 && pc + 2 <= prog->code_len) { // LOAD_LOCAL u8
            fprintf(out, " l%u", (unsigned)code[pc + 1]);
            pc += 2;
        } else if (op == 0x05 && pc + 2 <= prog->code_len) { // STORE_LOCAL u8
            fprintf(out, " l%u", (unsigned)code[pc + 1]);
            pc += 2;
        } else if (op == 0x06 && pc + 3 <= prog->code_len) { // LOAD_GLOBAL u16
            uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " g%u", (unsigned)idx);
            pc += 3;
        } else if (op == 0x07 && pc + 3 <= prog->code_len) { // STORE_GLOBAL u16
            uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " g%u", (unsigned)idx);
            pc += 3;
        } else if ((op == 0x30 || op == 0x31) && pc + 3 <= prog->code_len) { // JMP/JMP_IF i16
            int16_t off = (int16_t)((uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8));
            size_t pc_after = pc + 3;
            int64_t target = (int64_t)pc_after + (int64_t)off;
            fprintf(out, " off=%d -> %lld", (int)off, (long long)target);
            pc += 3;
        } else if (op == 0x38 && pc + 4 <= prog->code_len) { // CALL u16_addr u8_nargs
            uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            uint8_t nargs = code[pc + 3];
            fprintf(out, " addr=%u nargs=%u", (unsigned)addr, (unsigned)nargs);
            pc += 4;
        } else if ((op == 0x3A) && pc + 4 <= prog->code_len) { // CALL_NATIVE u16 id u8 nargs
            uint16_t id = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            uint8_t nargs = code[pc + 3];
            fprintf(out, " id=%u nargs=%u", (unsigned)id, (unsigned)nargs);
            pc += 4;
        } else if ((op == 0x3B) && pc + 5 <= prog->code_len) { // CALL_NATIVE2 u8 dom u16 op u8 nargs
            uint8_t dom = code[pc + 1];
            uint16_t nop = (uint16_t)code[pc + 2] | ((uint16_t)code[pc + 3] << 8);
            uint8_t nargs = code[pc + 4];
            fprintf(out, " dom=%u op=%u nargs=%u", (unsigned)dom, (unsigned)nop, (unsigned)nargs);
            pc += 5;
        } else if ((op == 0x3C) && pc + 3 <= prog->code_len) { // PUSH_FUNC u16 addr
            uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " addr=%u", (unsigned)addr);
            pc += 3;
        } else if ((op == 0x3D) && pc + 2 <= prog->code_len) { // CALL_INDIRECT u8 nargs
            uint8_t nargs = code[pc + 1];
            fprintf(out, " nargs=%u", (unsigned)nargs);
            pc += 2;
        } else if ((op == 0x44) && pc + 2 <= prog->code_len) { // CALL_INDIRECT_SPREAD u8 fixed
            uint8_t fixed = code[pc + 1];
            fprintf(out, " fixed=%u", (unsigned)fixed);
            pc += 2;
        } else if ((op == 0x3E) && pc + 2 <= prog->code_len) { // MAKE_CLOSURE u8 ncap
            uint8_t ncap = code[pc + 1];
            fprintf(out, " ncap=%u", (unsigned)ncap);
            pc += 2;
        } else if ((op == 0x3F) && pc + 2 <= prog->code_len) { // LOAD_ENV u8 idx
            uint8_t idx = code[pc + 1];
            fprintf(out, " idx=%u", (unsigned)idx);
            pc += 2;
        } else if ((op == 0x40 || op == 0x41) && pc + 3 <= prog->code_len) { // NEW_LIST/NEW_MAP u16 count
            uint16_t cnt = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " count=%u", (unsigned)cnt);
            pc += 3;
        } else {
            pc += 1;
        }

        fprintf(out, "\n");
    }
}

static void dump_value_short(FILE* out, AvmValue v) {
    if (!out) out = stderr;
    if (v.type == AVM_VAL_NIL) { fprintf(out, "nil"); return; }
    if (v.type == AVM_VAL_INT) { fprintf(out, "%lld", (long long)v.as.i); return; }
    if (v.type == AVM_VAL_BOOL) { fprintf(out, "%s", v.as.i ? "true" : "false"); return; }
    if (v.type == AVM_VAL_FLOAT) { fprintf(out, "%f", v.as.f); return; }
    if (v.type == AVM_VAL_STRING) { fprintf(out, "\"%s\"", v.as.p ? (char*)v.as.p : ""); return; }
    if (v.type == AVM_VAL_BYTES) { fprintf(out, "<bytes len=%d>", v.as.b ? v.as.b->len : 0); return; }
    if (v.type == AVM_VAL_LIST) { fprintf(out, "<list n=%d>", v.as.l ? v.as.l->count : 0); return; }
    if (v.type == AVM_VAL_MAP) { fprintf(out, "<map n=%d>", v.as.m ? v.as.m->count : 0); return; }
    if (v.type == AVM_VAL_FUNC) { fprintf(out, "<func addr=%u>", v.as.fn ? (unsigned)v.as.fn->addr : 0u); return; }
    fprintf(out, "<val?>");
}

static void dump_stack(FILE* out, AvmVM* vm, int limit) {
    if (!out) out = stderr;
    if (!vm) return;
    int n = vm->sp;
    if (n < 0) n = 0;
    if (limit <= 0) limit = 32;
    int start = n - limit;
    if (start < 0) start = 0;
    fprintf(out, "STACK sp=%d (showing %d..%d)\n", vm->sp, start, n);
    for (int i = start; i < n; i++) {
        fprintf(out, "  [%d] ", i);
        dump_value_short(out, vm->stack[i]);
        fprintf(out, "\n");
    }
}

static void json_dump_value_short(FILE* out, AvmValue v) {
    if (!out) return;
    fprintf(out, "{");
    fprintf(out, "\"type\":\"%s\"", avm_val_type_name(v));
    if (v.type == AVM_VAL_INT) {
        fprintf(out, ",\"i64\":%lld", (long long)v.as.i);
    } else if (v.type == AVM_VAL_BOOL) {
        fprintf(out, ",\"value\":%s", v.as.i ? "true" : "false");
    } else if (v.type == AVM_VAL_FLOAT) {
        fprintf(out, ",\"value\":%f", v.as.f);
    } else if (v.type == AVM_VAL_STRING) {
        fprintf(out, ",\"value\":\"");
        json_print_escaped(out, v.as.p ? (const char*)v.as.p : "");
        fprintf(out, "\"");
    } else if (v.type == AVM_VAL_BYTES) {
        fprintf(out, ",\"len\":%d", v.as.b ? v.as.b->len : 0);
    } else if (v.type == AVM_VAL_LIST) {
        fprintf(out, ",\"len\":%d", v.as.l ? v.as.l->count : 0);
    } else if (v.type == AVM_VAL_MAP) {
        fprintf(out, ",\"len\":%d", v.as.m ? v.as.m->count : 0);
    }
    fprintf(out, "}");
}

static void print_pause_json(FILE* out, AvmVM* vm) {
    if (!out || !vm) return;
    fprintf(out, "{");
    fprintf(out, "\"schema\":\"avm.pause.v1\"");
    fprintf(out, ",\"paused\":%s", vm->paused ? "true" : "false");
    fprintf(out, ",\"exit_code\":%d", vm->exit_code);
    fprintf(out, ",\"pc\":%d", vm->pc);
    fprintf(out, ",\"sp\":%d", vm->sp);
    fprintf(out, ",\"fp\":%d", vm->fp);
    fprintf(out, ",\"frame_count\":%d", vm->frame_count);
    fprintf(out, ",\"gas_executed\":%llu", (unsigned long long)vm->gas_executed);

    // Top-of-stack preview (best-effort, shallow): last up to 8 values.
    int n = vm->sp;
    if (n < 0) n = 0;
    int start = n - 8;
    if (start < 0) start = 0;
    fprintf(out, ",\"stack\":[");
    int first = 1;
    for (int i = start; i < n; i++) {
        if (!first) fprintf(out, ",");
        first = 0;
        json_dump_value_short(out, vm->stack[i]);
    }
    fprintf(out, "]");

    fprintf(out, "}\n");
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
    const char* timeout_ms_cli = NULL;
    const char* call_depth_max_cli = NULL;
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
            if (type == 0) { // NIL
                consts[ci].type = AVM_VAL_NIL;
            }
            if (type == 1) { // INT
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
            }
            if (type == 2) { // BOOL (rolling): u8 0|1
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
            }
            if (type == 3) { // FLOAT (rolling): IEEE-754 f64 bits as u64 little-endian
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
            }
            if (type == 4) { // STRING
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
            }
            if (type == 8) { // BYTES (rolling): u32 len + raw bytes
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
                if (pos + blen > len) {
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

        // Budgets/timeouts (macOS-first, rolling ABI):
    // - AVM_GAS: maximum instruction steps (0/unset = unlimited)
    // - AVM_TIMEOUT_MS: wall-time timeout in milliseconds (0/unset = unlimited)
    // - AVM_MEM_BYTES: heap budget for AVM heap objects (0/unset = unlimited)
    // - AVM_IO_BYTES: io budget for FS bytes read/written (0/unset = unlimited)
    // - AVM_LOG_BYTES: record/replay log budget (bytes appended, incl header) (0/unset = unlimited)
    // - AVM_CALL_DEPTH_MAX: maximum call depth (0/unset = MAX_FRAMES)
    const char* gas_env = getenv("AVM_GAS");
    if (gas_env && gas_env[0]) vm->gas_remaining = strtoull(gas_env, NULL, 10);
    const char* timeout_env = timeout_ms_cli ? timeout_ms_cli : getenv("AVM_TIMEOUT_MS");
    if (timeout_env && timeout_env[0]) {
        uint64_t ms = strtoull(timeout_env, NULL, 10);
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
            }
            if ((!mem_env || !mem_env[0]) && vm->heap_budget_bytes == 0) vm->heap_budget_bytes = 32ull * 1024ull * 1024ull; // 32 MiB
            if ((!io_env || !io_env[0]) && vm->io_budget_bytes == 0) vm->io_budget_bytes = 1024ull * 1024ull; // 1 MiB
            if ((!log_env || !log_env[0]) && vm->log_budget_bytes == 0) vm->log_budget_bytes = 1024ull * 1024ull; // 1 MiB
        }

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
                // do not override execution result; just report and continue
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
