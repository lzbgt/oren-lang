#include "avm_cli_verify.h"
#include "avm_sig.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static int decode_i32(const uint8_t* code, size_t code_len, size_t pos, int32_t* out) {
    if (pos + 4 > code_len) return 0;
    uint32_t u = 0;
    u |= (uint32_t)code[pos];
    u |= (uint32_t)code[pos + 1] << 8;
    u |= (uint32_t)code[pos + 2] << 16;
    u |= (uint32_t)code[pos + 3] << 24;
    int32_t v = 0;
    memcpy(&v, &u, sizeof(v));
    *out = v;
    return 1;
}

static int decode_u16(const uint8_t* code, size_t code_len, size_t pos, uint16_t* out) {
    if (pos + 2 > code_len) return 0;
    uint16_t v = (uint16_t)code[pos] | ((uint16_t)code[pos + 1] << 8);
    *out = v;
    return 1;
}

static int decode_u32(const uint8_t* code, size_t code_len, size_t pos, uint32_t* out) {
    if (pos + 4 > code_len) return 0;
    uint32_t v = 0;
    v |= (uint32_t)code[pos];
    v |= (uint32_t)code[pos + 1] << 8;
    v |= (uint32_t)code[pos + 2] << 16;
    v |= (uint32_t)code[pos + 3] << 24;
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
    uint32_t region_id,
    uint64_t* used_domains_io,
    uint32_t* callees_out,
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
        } else if (op == 0x52) { // LOAD_LOCAL16 u16
            len = 3;
            push = 1;
        } else if (op == 0x53) { // STORE_LOCAL16 u16
            len = 3;
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
        } else if (op >= 0x10 && op <= 0x1F) { // binary numeric ops + shifts + comparisons (incl MUL/DIV/MOD)
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
        } else if (op == 0x4E) { // JMP32 i32
            len = 5;
        } else if (op == 0x4F) { // JMP_IF32 i32
            len = 5;
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
                callees_out[*callee_count_io] = (uint32_t)addr;
                callee_nargs_out[*callee_count_io] = nargs;
                (*callee_count_io)++;
            }
        } else if (op == 0x50) { // CALL32 u32_addr u8_nargs
            len = 6;
            uint32_t addr = 0;
            if (!decode_u32(code, code_len, pc + 1, &addr)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated CALL32"); }
            if (addr >= code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL32 addr out of bounds"); }
            uint8_t nargs = code[pc + 5];
            if (nargs > 16) { free(depth_at); free(queue); free(qdepth); return err_result("verify: CALL32 nargs too large"); }
            pop = (int)nargs;
            push = 1;

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
        } else if (op == 0x51) { // PUSH_FUNC32 u32_addr
            len = 5;
            uint32_t addr = 0;
            if (!decode_u32(code, code_len, pc + 1, &addr)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated PUSH_FUNC32"); }
            if (addr >= code_len) { free(depth_at); free(queue); free(qdepth); return err_result("verify: PUSH_FUNC32 addr out of bounds"); }
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
        } else if (op == 0x5E) { // NEW_LIST_INT (cap on stack)
            len = 1;
            pop = 1;
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
        } else if (op == 0x57) { // GET_INDEX_LIST
            len = 1;
            pop = 2;
            push = 1;
        } else if (op == 0x59) { // LIST_PUSH_INT
            len = 1;
            pop = 2; // list, val
            push = 1; // nil or err
        } else if (op == 0x5A) { // LIST_PUSH
            len = 1;
            pop = 2; // list, val
            push = 1; // nil or err
        } else if (op == 0x5B) { // LIST_PUSH_INT_LOOP
            len = 1;
            pop = 6; // list, idx, end, mul, add, mod
            push = 1; // idx
        } else if (op == 0x5F) { // LIST_PUSH2_INT_LOOP
            len = 1;
            pop = 10; // list_a, list_b, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b
            push = 1; // idx
        } else if (op == 0x60) { // LIST_PUSH3_INT_LOOP
            len = 1;
            pop = 14; // list_a, list_b, list_c, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b, mul_c, add_c, mod_c
            push = 1; // idx
        } else if (op == 0x61) { // INT_LCG_SUM_LOOP
            len = 1;
            pop = 9; // x, sum, idx, end, mul, add, mod, mod_x, mod_i
            push = 3; // idx, sum, x
        } else if (op == 0x5C) { // LIST_SUM_INT_LOOP
            len = 1;
            pop = 4; // list, idx, n, sum
            push = 2; // idx, sum
        } else if (op == 0x5D) { // LIST_SUM3_INT_LOOP
            len = 1;
            pop = 6; // list_a, list_b, list_c, idx, n, sum
            push = 2; // idx, sum
        } else if (op == 0x58) { // LIST_DOT
            len = 1;
            pop = 5; // list_a, list_b, idx, n, sum
            push = 2; // idx, sum
        } else if (op == 0x43) { // SET_INDEX
            len = 1;
            pop = 3;
            push = 0;
        } else if (op == 0x56) { // NEW_LIST_SPREAD u16_fixed
            len = 3;
            uint16_t fixed = 0;
            if (!decode_u16(code, code_len, pc + 1, &fixed)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated NEW_LIST_SPREAD"); }
            pop = (int)fixed + 1; // fixed vals + spread list
            push = 1;
        } else if (op == 0x45) { // SPAWN_CALL_LIST
            len = 1;
            pop = 2;  // fn + args_list
            push = 1; // handle
        } else if (op == 0x54) { // SPAWN_CALL_SPREAD u16_fixed
            len = 3;
            uint16_t fixed = 0;
            if (!decode_u16(code, code_len, pc + 1, &fixed)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated SPAWN_CALL_SPREAD"); }
            pop = (int)fixed + 2;  // fn + fixed args + spread list
            push = 1;              // handle
        } else if (op == 0x55) { // TYPE_CTOR_MAP_SPREAD u16_fixed
            len = 3;
            uint16_t fixed = 0;
            if (!decode_u16(code, code_len, pc + 1, &fixed)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated TYPE_CTOR_MAP_SPREAD"); }
            pop = (int)fixed + 2;  // keys_list + fixed args + spread list
            push = 1;              // map
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
        } else if (op == 0x4C) { // JOIN_TIMEOUT
            len = 1;
            pop = 2;  // handle + timeout_ms
            push = 1; // ret or ETIMEDOUT
        } else if (op == 0x4D) { // SELECT
            len = 1;
            pop = 1;  // list<case>
            push = 1; // [idx, payload]
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
            char buf[256];
            snprintf(buf, sizeof(buf), "verify: stack underflow at pc=%zu op=0x%02x (need pop=%d, have depth=%d)", pc, (unsigned)op, pop, depth);
            return err_result(buf);
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

        if (op == 0x4E || op == 0x4F) { // JMP32/JMP_IF32
            int32_t off = 0;
            if (!decode_i32(code, code_len, pc + 1, &off)) { free(depth_at); free(queue); free(qdepth); return err_result("verify: truncated JMP32"); }
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

            if (op == 0x4F) {
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
    uint32_t addr;
    uint8_t nargs;
    uint8_t verified;
} VerifyFunc;

static int find_func(VerifyFunc* funcs, size_t n, uint32_t addr) {
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
    uint32_t** wl_io,
    uint8_t** wl_nargs_io,
    size_t* cap_io,
    size_t need
) {
    if (!wl_io || !wl_nargs_io || !cap_io) return err_result("verify: internal error");
    if (need <= *cap_io) return ok_result();
    size_t nc = (*cap_io) ? (*cap_io) * 2 : 16;
    while (nc < need) nc *= 2;
    uint32_t* nw = (uint32_t*)realloc(*wl_io, sizeof(uint32_t) * nc);
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
    uint32_t** wl_io,
    uint8_t** wl_nargs_io,
    size_t* wl_t_io,
    size_t* wl_cap_io,
    uint64_t used_domains_mask,
    uint32_t addr,
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

VerifyResult verify_program(const AvmProgram* prog, int strict_legacy) {
    if (!prog || !prog->code || prog->code_len == 0) return err_result("empty program");

    uint64_t used_domains = 0;

    VerifyFunc* funcs = NULL;
    size_t funcs_len = 0;
    size_t funcs_cap = 0;

    uint32_t* wl = NULL;
    uint8_t* wl_nargs = NULL;
    size_t wl_h = 0, wl_t = 0, wl_cap = 0;

    // Verify root region (pc=0). Collect initial call graph.
    {
        // Use local buffers for callee discovery (worst-case: code_len CALL sites).
        size_t cap = prog->code_len;
        uint32_t* callees = (uint32_t*)malloc(sizeof(uint32_t) * cap);
        uint8_t* cnargs = (uint8_t*)malloc(sizeof(uint8_t) * cap);
        size_t ccnt = 0;
        if ((!callees || !cnargs) && cap > 0) { free(callees); free(cnargs); free(funcs); free(wl); free(wl_nargs); return err_result("verify: out of memory"); }

        VerifyResult vr = verify_program_region(prog, 0, 0, 0xFFFFFFFFu, &used_domains, callees, cnargs, &ccnt, cap, strict_legacy);
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
        uint32_t addr = wl[wl_h];
        uint8_t nargs = wl_nargs[wl_h];
        wl_h++;

        int idx = find_func(funcs, funcs_len, addr);
        if (idx < 0) continue;
        if (funcs[idx].verified) continue;

        size_t cap = prog->code_len;
        uint32_t* callees = (uint32_t*)malloc(sizeof(uint32_t) * cap);
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
