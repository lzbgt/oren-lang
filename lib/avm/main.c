#include "avm.h"
#include "sha256.h"
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
    size_t callee_cap
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
            uint16_t id = 0;
            if (!decode_u16(code, code_len, pc + 1, &id)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE"); }
            uint8_t nargs = code[pc + 3];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE nargs too large"); }
            pop = (int)nargs;
            push = 1;

            uint8_t dom = 0;
            if (id == 0 || id == 1 || id == 17 || id == 18) dom = 1;
            if (used_domains_io) *used_domains_io |= (1ULL << (dom & 63));
        } else if (op == 0x3B) { // CALL_NATIVE2 u8_domain u16_op u8_nargs
            len = 5;
            if (pc + len > code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL_NATIVE2"); }
            uint8_t dom = code[pc + 1];
            uint8_t nargs = code[pc + 4];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL_NATIVE2 nargs too large"); }
            pop = (int)nargs;
            push = 1;
            if (used_domains_io) *used_domains_io |= (1ULL << (dom & 63));
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

static VerifyResult verify_program(const AvmProgram* prog) {
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

        VerifyResult vr = verify_program_region(prog, 0, 0, 0xFFFFu, &used_domains, callees, cnargs, &ccnt, cap);
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

        VerifyResult vr = verify_program_region(prog, (size_t)addr, (int)nargs, addr, &used_domains, callees, cnargs, &ccnt, cap);
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
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x38: return "CALL";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
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
    else fprintf(out, "<val?>");
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

int main(int argc, char** argv) {
    const char* obc_path = NULL;
    const char* snap_in = NULL;
    const char* snap_out = NULL;
    uint64_t step_limit = 0;
    int print_state_hash = 0;
    int print_result_hash = 0;
    int print_policy = 0;
    int print_record_log_hex = 0;
    int print_mem_stats = 0;
    int print_rss = 0;
    int disasm = 0;
    int disasm_consts = 0;
    int trace = 0;
    uint64_t trace_limit = 0;
    int print_stack = 0;
    int break_pc_count = 0;
    int break_pc_cap = 0;
    int* break_pcs = NULL;
    int repeat = 1;

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
        if (strcmp(argv[i], "--print-policy") == 0) {
            print_policy = 1;
            i += 1;
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
        if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown arg: %s\n", argv[i]);
            return 1;
        }
        obc_path = argv[i];
        i++;
    }

    if (!obc_path) {
        printf("Usage: avm [--disasm|--disasm-consts] [--trace|--trace-limit N] [--breakpc PC] [--print-stack] [--snapshot-in file] [--snapshot-out file] [--step-limit N] [--repeat N] [--print-state-hash] [--print-result-hash] [--print-record-log-hex] [--print-mem-stats] [--print-rss] [--print-policy] <file.obc>\n");
        free(break_pcs);
        return 1;
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
            VerifyResult vr = verify_program(&prog);
            if (!vr.ok) {
                fprintf(stderr, "AVM verify failed: %s\n", vr.msg);
                free_constant_pool(consts, n_consts);
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
            if (print_policy) {
                printf("POLICY_USED_DOMAINS_MASK 0x%016llx\n", (unsigned long long)vr.used_domains_mask);
            }
        }

        if (disasm) {
            disasm_program(stdout, &prog, disasm_consts);
            free_constant_pool(consts, n_consts);
            free(consts);
            exit_code = 0;
            break;
        }

        AvmVM* vm = avm_new();
        vm->argc = argc - 1;
        vm->argv = argv + 1;
        if (trace) {
            vm->trace_enabled = 1;
            vm->trace_limit = trace_limit;
            vm->trace_out = stderr;
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
    // - AVM_MEM_BYTES: heap budget for AVM heap objects (0/unset = unlimited)
    // - AVM_IO_BYTES: io budget for FS bytes read/written (0/unset = unlimited)
    const char* gas_env = getenv("AVM_GAS");
    if (gas_env && gas_env[0]) vm->gas_remaining = strtoull(gas_env, NULL, 10);
    const char* timeout_env = getenv("AVM_TIMEOUT_MS");
    if (timeout_env && timeout_env[0]) {
        uint64_t ms = strtoull(timeout_env, NULL, 10);
        uint64_t base = now_ns();
        if (base != 0 && ms > 0) vm->deadline_ns = base + ms * 1000000ull;
    }
    const char* mem_env = getenv("AVM_MEM_BYTES");
    if (mem_env && mem_env[0]) vm->heap_budget_bytes = strtoull(mem_env, NULL, 10);
    const char* io_env = getenv("AVM_IO_BYTES");
    if (io_env && io_env[0]) vm->io_budget_bytes = strtoull(io_env, NULL, 10);

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
                free(consts);
                free(data);
                free(break_pcs);
                return 1;
            }
        }

        if (step_limit > 0) vm->pause_after_steps = step_limit;
        avm_run(vm);

        if (repeat > 1) printf("ITER %d\n", iter);

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
