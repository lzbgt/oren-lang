#include "avm_vm_values.h"

#include <limits.h>
#include <stdio.h>

AvmValue avm_list_int_new(int cap) {
    if (cap < 0) cap = 0;
    if (cap > INT_MAX) return avm_err(AVM_ERR_INVALID_ARG, "list_int_new cap too large");
    AvmListInt* list = (AvmListInt*)avm_heap_malloc_k(sizeof(AvmListInt), AVM_ALLOC_KIND_LIST_INT);
    if (!list) return avm_alloc_fail_value();
    list->count = 0;
    list->capacity = cap;
    list->items = NULL;
    if (cap > 0) {
        list->items = (int64_t*)avm_heap_malloc_k(sizeof(int64_t) * (size_t)cap, AVM_ALLOC_KIND_LIST_INT);
        if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
    }
    AvmValue v; v.type = AVM_VAL_LIST_INT; v.as.li = list;
    return v;
}

void avm_print_value_no_nl(AvmValue v) {
    if (v.type == AVM_VAL_INT) printf("%lld", (long long)v.as.i);
    else if (v.type == AVM_VAL_FLOAT) printf("%f", v.as.f);
    else if (v.type == AVM_VAL_STRING) printf("%s", (char*)v.as.p);
    else if (v.type == AVM_VAL_BOOL) printf("%s", v.as.i ? "true" : "false");
    else if (v.type == AVM_VAL_NIL) printf("nil");
    else if (v.type == AVM_VAL_LIST) printf("<list>");
    else if (v.type == AVM_VAL_LIST_INT) printf("<list_int>");
    else if (v.type == AVM_VAL_MAP) printf("<map>");
    else if (v.type == AVM_VAL_FUNC) printf("<func>");
    else if (v.type == AVM_VAL_I32_BUF) printf("<i32_buf>");
    else if (v.type == AVM_VAL_I64_BUF) printf("<i64_buf>");
    else if (v.type == AVM_VAL_F32_BUF) printf("<f32_buf>");
    else if (v.type == AVM_VAL_F64_BUF) printf("<f64_buf>");
    else if (v.type == AVM_VAL_GENERATOR) printf("<generator>");
    else if (v.type == AVM_VAL_GENERATOR_CONTEXT) printf("<generator_context>");
    else printf("<?>");
}

const char* avm_val_type_short(AvmValue v) {
    switch (v.type) {
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
        case AVM_VAL_GENERATOR: return "GENERATOR";
        case AVM_VAL_GENERATOR_CONTEXT: return "GENERATOR_CONTEXT";
        default: return "VAL?";
    }
}
