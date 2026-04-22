#include "avm_cli_disasm.h"
#include "avm_cli_dump.h"
#include "avm_cli_util.h"
#include <stdlib.h>
#include <string.h>

static const char* op_name(uint8_t op) {
    switch (op) {
        case 0x00: return "NOP";
        case 0x01: return "HALT";
        case 0x02: return "PUSH_CONST";
        case 0x03: return "POP";
        case 0x04: return "LOAD_LOCAL";
        case 0x05: return "STORE_LOCAL";
        case 0x52: return "LOAD_LOCAL16";
        case 0x53: return "STORE_LOCAL16";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x1D: return "MUL";
        case 0x1E: return "DIV";
        case 0x1F: return "MOD";
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
        case 0x4E: return "JMP32";
        case 0x4F: return "JMP_IF32";
        case 0x38: return "CALL";
        case 0x50: return "CALL32";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x3C: return "PUSH_FUNC";
        case 0x51: return "PUSH_FUNC32";
        case 0x3D: return "CALL_INDIRECT";
        case 0x44: return "CALL_INDIRECT_SPREAD";
        case 0x3E: return "MAKE_CLOSURE";
        case 0x3F: return "LOAD_ENV";
        case 0x40: return "NEW_LIST";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x57: return "GET_INDEX_LIST";
        case 0x58: return "LIST_DOT";
        case 0x59: return "LIST_PUSH_INT";
        case 0x5A: return "LIST_PUSH";
        case 0x5B: return "LIST_PUSH_INT_LOOP";
        case 0x5C: return "LIST_SUM_INT_LOOP";
        case 0x5D: return "LIST_SUM3_INT_LOOP";
        case 0x5F: return "LIST_PUSH2_INT_LOOP";
        case 0x60: return "LIST_PUSH3_INT_LOOP";
        case 0x61: return "INT_LCG_SUM_LOOP";
        case 0x43: return "SET_INDEX";
        case 0x45: return "SPAWN_CALL_LIST";
        case 0x54: return "SPAWN_CALL_SPREAD";
        case 0x55: return "TYPE_CTOR_MAP_SPREAD";
        case 0x5E: return "NEW_LIST_INT";
        case 0x56: return "NEW_LIST_SPREAD";
        case 0x46: return "JOIN";
        case 0x47: return "CHAN_NEW";
        case 0x48: return "CHAN_SEND";
        case 0x49: return "CHAN_RECV";
        case 0x4A: return "SELECT_RECV";
        case 0x4B: return "YIELD";
        case 0x4C: return "JOIN_TIMEOUT";
        case 0x4D: return "SELECT";
        case 0x62: return "DETACH";
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
    else if (v.type == AVM_VAL_LIST_INT) fprintf(out, "<list_int>");
    else if (v.type == AVM_VAL_LIST_INT) fprintf(out, "<list_int>");
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

static size_t disasm_insn_len(const uint8_t* code, size_t code_len, size_t pc) {
    if (!code || pc >= code_len) return 1;
    uint8_t op = code[pc];
    if (op == 0x02) return 3;                 // PUSH_CONST u16
    if (op == 0x04 || op == 0x05) return 2;   // LOAD/STORE_LOCAL u8
    if (op == 0x52 || op == 0x53) return 3;   // LOAD/STORE_LOCAL16 u16
    if (op == 0x06 || op == 0x07) return 3;   // LOAD/STORE_GLOBAL u16
    if (op == 0x30 || op == 0x31) return 3;   // JMP/JMP_IF i16
    if (op == 0x4E || op == 0x4F) return 5;   // JMP32/JMP_IF32 i32
    if (op == 0x38) return 4;                 // CALL u16 u8
    if (op == 0x50) return 6;                 // CALL32 u32 u8
    if (op == 0x3A) return 4;                 // CALL_NATIVE u16 u8
    if (op == 0x3B) return 5;                 // CALL_NATIVE2 u8 u16 u8
    if (op == 0x3C) return 3;                 // PUSH_FUNC u16
    if (op == 0x51) return 5;                 // PUSH_FUNC32 u32
    if (op == 0x3D) return 2;                 // CALL_INDIRECT u8
    if (op == 0x44) return 2;                 // CALL_INDIRECT_SPREAD u8
    if (op == 0x3E) return 2;                 // MAKE_CLOSURE u8
    if (op == 0x3F) return 2;                 // LOAD_ENV u8
    if (op == 0x40 || op == 0x41) return 3;   // NEW_LIST/NEW_MAP u16
    if (op == 0x54) return 3;                 // SPAWN_CALL_SPREAD u16
    if (op == 0x55) return 3;                 // TYPE_CTOR_MAP_SPREAD u16
    if (op == 0x56) return 3;                 // NEW_LIST_SPREAD u16
    return 1;
}

void disasm_program_json(FILE* out, const AvmProgram* prog, int show_consts) {
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
            } else if (op == 0x52 || op == 0x53) { // LOAD/STORE_LOCAL16 u16
                uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"local\":%u}", (unsigned)idx);
            } else if (op == 0x06 || op == 0x07) { // LOAD/STORE_GLOBAL u16
                uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                fprintf(out, ",\"operands\":{\"global\":%u}", (unsigned)idx);
            } else if (op == 0x30 || op == 0x31) { // JMP/JMP_IF i16
                int16_t off = (int16_t)((uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8));
                size_t pc_after = pc + 3;
                int64_t target = (int64_t)pc_after + (int64_t)off;
                fprintf(out, ",\"operands\":{\"off\":%d,\"target\":%lld}", (int)off, (long long)target);
            } else if (op == 0x4E || op == 0x4F) { // JMP32/JMP_IF32 i32
                uint32_t u = (uint32_t)code[pc + 1]
                           | ((uint32_t)code[pc + 2] << 8)
                           | ((uint32_t)code[pc + 3] << 16)
                           | ((uint32_t)code[pc + 4] << 24);
                int32_t off = 0;
                memcpy(&off, &u, sizeof(off));
                size_t pc_after = pc + 5;
                int64_t target = (int64_t)pc_after + (int64_t)off;
                fprintf(out, ",\"operands\":{\"off\":%d,\"target\":%lld}", (int)off, (long long)target);
            } else if (op == 0x38) { // CALL u16_addr u8_nargs
                uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
                uint8_t nargs = code[pc + 3];
                fprintf(out, ",\"operands\":{\"addr\":%u,\"nargs\":%u}", (unsigned)addr, (unsigned)nargs);
            } else if (op == 0x50) { // CALL32 u32_addr u8_nargs
                uint32_t addr = (uint32_t)code[pc + 1]
                              | ((uint32_t)code[pc + 2] << 8)
                              | ((uint32_t)code[pc + 3] << 16)
                              | ((uint32_t)code[pc + 4] << 24);
                uint8_t nargs = code[pc + 5];
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
            } else if (op == 0x51) { // PUSH_FUNC32 u32 addr
                uint32_t addr = (uint32_t)code[pc + 1]
                              | ((uint32_t)code[pc + 2] << 8)
                              | ((uint32_t)code[pc + 3] << 16)
                              | ((uint32_t)code[pc + 4] << 24);
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

void disasm_program(FILE* out, const AvmProgram* prog, int show_consts) {
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
        } else if (op == 0x52 && pc + 3 <= prog->code_len) { // LOAD_LOCAL16 u16
            uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " l%u", (unsigned)idx);
            pc += 3;
        } else if (op == 0x53 && pc + 3 <= prog->code_len) { // STORE_LOCAL16 u16
            uint16_t idx = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            fprintf(out, " l%u", (unsigned)idx);
            pc += 3;
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
        } else if ((op == 0x4E || op == 0x4F) && pc + 5 <= prog->code_len) { // JMP32/JMP_IF32 i32
            uint32_t u = (uint32_t)code[pc + 1]
                       | ((uint32_t)code[pc + 2] << 8)
                       | ((uint32_t)code[pc + 3] << 16)
                       | ((uint32_t)code[pc + 4] << 24);
            int32_t off = 0;
            memcpy(&off, &u, sizeof(off));
            size_t pc_after = pc + 5;
            int64_t target = (int64_t)pc_after + (int64_t)off;
            fprintf(out, " off=%d -> %lld", (int)off, (long long)target);
            pc += 5;
        } else if (op == 0x38 && pc + 4 <= prog->code_len) { // CALL u16_addr u8_nargs
            uint16_t addr = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            uint8_t nargs = code[pc + 3];
            fprintf(out, " addr=%u nargs=%u", (unsigned)addr, (unsigned)nargs);
            pc += 4;
        } else if (op == 0x50 && pc + 6 <= prog->code_len) { // CALL32 u32_addr u8_nargs
            uint32_t addr = (uint32_t)code[pc + 1]
                          | ((uint32_t)code[pc + 2] << 8)
                          | ((uint32_t)code[pc + 3] << 16)
                          | ((uint32_t)code[pc + 4] << 24);
            uint8_t nargs = code[pc + 5];
            fprintf(out, " addr=%u nargs=%u", (unsigned)addr, (unsigned)nargs);
            pc += 6;
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
        } else if ((op == 0x51) && pc + 5 <= prog->code_len) { // PUSH_FUNC32 u32 addr
            uint32_t addr = (uint32_t)code[pc + 1]
                          | ((uint32_t)code[pc + 2] << 8)
                          | ((uint32_t)code[pc + 3] << 16)
                          | ((uint32_t)code[pc + 4] << 24);
            fprintf(out, " addr=%u", (unsigned)addr);
            pc += 5;
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
