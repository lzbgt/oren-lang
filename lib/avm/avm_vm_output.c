#include "avm_vm_values.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int avm_stdout_capture_append(AvmVM* vm, const char* data, size_t len) {
    if (!vm || !vm->stdout_capture_enabled) return 0;
    if (!data && len > 0) return 0;
    if (len > SIZE_MAX - vm->stdout_capture_len - 1u) {
        avm_abort(vm, avm_err(AVM_ERR_BUDGET, "stdout capture too large"));
        return 0;
    }
    size_t need = vm->stdout_capture_len + len + 1u;
    if (need > vm->stdout_capture_cap) {
        size_t nc = vm->stdout_capture_cap ? vm->stdout_capture_cap : 256u;
        while (nc < need) {
            if (nc > SIZE_MAX / 2u) {
                nc = need;
                break;
            }
            nc *= 2u;
        }
        char* next = (char*)realloc(vm->stdout_capture, nc);
        if (!next) {
            avm_abort(vm, avm_err(AVM_ERR_BUDGET, "stdout capture allocation failed"));
            return 0;
        }
        vm->stdout_capture = next;
        vm->stdout_capture_cap = nc;
    }
    if (len > 0) memcpy(vm->stdout_capture + vm->stdout_capture_len, data, len);
    vm->stdout_capture_len += len;
    vm->stdout_capture[vm->stdout_capture_len] = 0;
    return 1;
}

void avm_output_text(AvmVM* vm, const char* data, size_t len) {
    if (vm && vm->stdout_capture_enabled) {
        (void)avm_stdout_capture_append(vm, data, len);
    } else if (len > 0 && data) {
        fwrite(data, 1, len, stdout);
    }
}

static void avm_output_cstr(AvmVM* vm, const char* s) {
    if (!s) s = "";
    avm_output_text(vm, s, strlen(s));
}

void avm_output_value_no_nl(AvmVM* vm, AvmValue v) {
    char buf[96];
    if (v.type == AVM_VAL_STRING) {
        avm_output_cstr(vm, (const char*)v.as.p);
    } else if (v.type == AVM_VAL_INT) {
        snprintf(buf, sizeof(buf), "%lld", (long long)v.as.i);
        avm_output_cstr(vm, buf);
    } else if (v.type == AVM_VAL_FLOAT) {
        snprintf(buf, sizeof(buf), "%f", v.as.f);
        avm_output_cstr(vm, buf);
    } else if (v.type == AVM_VAL_BOOL) {
        avm_output_cstr(vm, v.as.i ? "true" : "false");
    } else if (v.type == AVM_VAL_NIL) {
        avm_output_cstr(vm, "nil");
    } else if (v.type == AVM_VAL_LIST) {
        avm_output_cstr(vm, "<list>");
    } else if (v.type == AVM_VAL_LIST_INT) {
        avm_output_cstr(vm, "<list_int>");
    } else if (v.type == AVM_VAL_MAP) {
        avm_output_cstr(vm, "<map>");
    } else if (v.type == AVM_VAL_FUNC) {
        avm_output_cstr(vm, "<func>");
    } else if (v.type == AVM_VAL_I32_BUF) {
        avm_output_cstr(vm, "<i32_buf>");
    } else if (v.type == AVM_VAL_I64_BUF) {
        avm_output_cstr(vm, "<i64_buf>");
    } else if (v.type == AVM_VAL_F32_BUF) {
        avm_output_cstr(vm, "<f32_buf>");
    } else if (v.type == AVM_VAL_F64_BUF) {
        avm_output_cstr(vm, "<f64_buf>");
    } else if (v.type == AVM_VAL_GENERATOR) {
        avm_output_cstr(vm, "<generator>");
    } else if (v.type == AVM_VAL_GENERATOR_CONTEXT) {
        avm_output_cstr(vm, "<generator_context>");
    } else {
        avm_output_cstr(vm, "<?>");
    }
}
