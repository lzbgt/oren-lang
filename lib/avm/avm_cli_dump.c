#include "avm_cli_dump.h"

const char* avm_val_type_name(AvmValue v) {
    switch (v.type) {
        case AVM_VAL_NIL: return "NIL";
        case AVM_VAL_INT: return "INT";
        case AVM_VAL_BOOL: return "BOOL";
        case AVM_VAL_FLOAT: return "FLOAT";
        case AVM_VAL_STRING: return "STRING";
        case AVM_VAL_BYTES: return "BYTES";
        case AVM_VAL_LIST: return "LIST";
        case AVM_VAL_LIST_INT: return "LIST_INT";
        case AVM_VAL_MAP: return "MAP";
        case AVM_VAL_FUNC: return "FUNC";
        case AVM_VAL_I32_BUF: return "I32_BUF";
        case AVM_VAL_I64_BUF: return "I64_BUF";
        case AVM_VAL_F32_BUF: return "F32_BUF";
        case AVM_VAL_F64_BUF: return "F64_BUF";
        default: return "VAL?";
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
    if (v.type == AVM_VAL_LIST_INT) { fprintf(out, "<list_int n=%d>", v.as.li ? v.as.li->count : 0); return; }
    if (v.type == AVM_VAL_MAP) { fprintf(out, "<map n=%d>", v.as.m ? v.as.m->count : 0); return; }
    if (v.type == AVM_VAL_FUNC) { fprintf(out, "<func addr=%u>", v.as.fn ? (unsigned)v.as.fn->addr : 0u); return; }
    if (v.type == AVM_VAL_I32_BUF) { fprintf(out, "<i32_buf len=%u>", v.as.buf ? (unsigned)v.as.buf->len : 0u); return; }
    if (v.type == AVM_VAL_I64_BUF) { fprintf(out, "<i64_buf len=%u>", v.as.buf ? (unsigned)v.as.buf->len : 0u); return; }
    if (v.type == AVM_VAL_F32_BUF) { fprintf(out, "<f32_buf len=%u>", v.as.buf ? (unsigned)v.as.buf->len : 0u); return; }
    if (v.type == AVM_VAL_F64_BUF) { fprintf(out, "<f64_buf len=%u>", v.as.buf ? (unsigned)v.as.buf->len : 0u); return; }
    fprintf(out, "<val?>");
}

void dump_stack(FILE* out, AvmVM* vm, int limit) {
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
        for (const char* p = v.as.p ? (const char*)v.as.p : ""; *p; p++) {
            if (*p == '\\' || *p == '\"') { fprintf(out, "\\%c", *p); }
            else if (*p == '\n') { fprintf(out, "\\n"); }
            else if (*p == '\r') { fprintf(out, "\\r"); }
            else if (*p == '\t') { fprintf(out, "\\t"); }
            else { fputc(*p, out); }
        }
        fprintf(out, "\"");
    } else if (v.type == AVM_VAL_BYTES) {
        fprintf(out, ",\"len\":%d", v.as.b ? v.as.b->len : 0);
    } else if (v.type == AVM_VAL_LIST) {
        fprintf(out, ",\"len\":%d", v.as.l ? v.as.l->count : 0);
    } else if (v.type == AVM_VAL_LIST_INT) {
        fprintf(out, ",\"len\":%d", v.as.li ? v.as.li->count : 0);
    } else if (v.type == AVM_VAL_MAP) {
        fprintf(out, ",\"len\":%d", v.as.m ? v.as.m->count : 0);
    }
    fprintf(out, "}");
}

void print_pause_json(FILE* out, AvmVM* vm) {
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

void print_json_escaped_string(FILE* out, const char* s) {
    // Minimal JSON string escaping:
    // - quotes and backslash
    // - common control chars: \n, \r, \t
    //
    // This is intentionally conservative; AVM is rolling and the primary consumer
    // today is tooling that needs stable machine-readable output.
    if (!out) return;
    if (!s) { fputs("", out); return; }
    for (const unsigned char* p = (const unsigned char*)s; *p; p++) {
        unsigned char c = *p;
        if (c == '\\' || c == '\"') { fputc('\\', out); fputc((int)c, out); continue; }
        if (c == '\n') { fputs("\\n", out); continue; }
        if (c == '\r') { fputs("\\r", out); continue; }
        if (c == '\t') { fputs("\\t", out); continue; }
        if (c < 0x20) {
            // Escape other control bytes as \u00XX.
            static const char* hex = "0123456789abcdef";
            fputs("\\u00", out);
            fputc(hex[(c >> 4) & 0xF], out);
            fputc(hex[c & 0xF], out);
            continue;
        }
        fputc((int)c, out);
    }
}

const char* avm_value_type_name(int t) {
    switch (t) {
        case AVM_VAL_INT: return "INT";
        case AVM_VAL_FLOAT: return "FLOAT";
        case AVM_VAL_STRING: return "STRING";
        case AVM_VAL_BOOL: return "BOOL";
        case AVM_VAL_NIL: return "NIL";
        case AVM_VAL_LIST: return "LIST";
        case AVM_VAL_LIST_INT: return "LIST_INT";
        case AVM_VAL_MAP: return "MAP";
        case AVM_VAL_FUNC: return "FUNC";
        case AVM_VAL_I32_BUF: return "I32_BUF";
        case AVM_VAL_I64_BUF: return "I64_BUF";
        case AVM_VAL_F32_BUF: return "F32_BUF";
        case AVM_VAL_F64_BUF: return "F64_BUF";
        default: return "VAL?";
    }
}
