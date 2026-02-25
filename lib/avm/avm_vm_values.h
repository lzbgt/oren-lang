#ifndef AVM_VM_VALUES_H
#define AVM_VM_VALUES_H

#include "avm_internal.h"
#include "avm_int_math.h"

#include <string.h>

static inline int avm_truthy(AvmValue v) {
    if (v.type == AVM_VAL_BOOL) return v.as.i != 0;
    if (v.type == AVM_VAL_INT) return v.as.i != 0;
    if (v.type == AVM_VAL_NIL) return 0;
    return 1;
}

static inline AvmValue avm_list_get_value(AvmValue obj, AvmValue key) {
    AvmValue res = avm_nil();
    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
        int i = (int)key.as.i;
        if (i >= 0 && i < obj.as.l->count) {
            res = obj.as.l->items[i];
        }
    } else if (obj.type == AVM_VAL_LIST_INT && key.type == AVM_VAL_INT) {
        int i = (int)key.as.i;
        if (i >= 0 && i < obj.as.li->count) {
            res = avm_int(obj.as.li->items[i]);
        }
    }
    return res;
}

static inline AvmValue avm_lt_values(AvmValue a, AvmValue b) {
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) return avm_bool(a.as.i < b.as.i);
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) return avm_bool(a.as.f < b.as.f);
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) return avm_bool((double)a.as.i < b.as.f);
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) return avm_bool(a.as.f < (double)b.as.i);
    if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) return avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) < 0);
    return avm_nil();
}

static inline AvmValue avm_mul_values(AvmValue a, AvmValue b) {
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
        return avm_int(avm_i64_mul_wrap(a.as.i, b.as.i));
    }
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * b.as.f; return r;
    }
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i * b.as.f; return r;
    }
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * (double)b.as.i; return r;
    }
    return avm_nil();
}

static inline AvmValue avm_add_values(AvmVM* vm, AvmValue a, AvmValue b, int* ok) {
    if (ok) *ok = 1;
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
        return avm_int(avm_i64_add_wrap(a.as.i, b.as.i));
    }
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + b.as.f; return r;
    }
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i + b.as.f; return r;
    }
    if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + (double)b.as.i; return r;
    }
    if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) {
        const char* sa = a.as.p ? (const char*)a.as.p : "";
        const char* sb = b.as.p ? (const char*)b.as.p : "";
        size_t la = strlen(sa);
        size_t lb = strlen(sb);
        char* s = (char*)avm_heap_malloc_k(la + lb + 1, AVM_ALLOC_KIND_STRING);
        if (!s) {
            AvmValue e = avm_alloc_fail_value();
            avm_abort(vm, e);
            if (ok) *ok = 0;
            return e;
        }
        memcpy(s, sa, la);
        memcpy(s + la, sb, lb);
        s[la + lb] = 0;
        AvmValue r; r.type = AVM_VAL_STRING; r.as.p = s; return r;
    }
    return avm_nil();
}

static inline AvmValue avm_mod_values(AvmVM* vm, AvmValue a, AvmValue b, int* ok) {
    if (ok) *ok = 1;
    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
        if (b.as.i == 0) {
            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo by zero"));
            if (ok) *ok = 0;
            return avm_nil();
        }
        if (avm_i64_is_min(a.as.i) && b.as.i == -1) {
            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo overflow (i64_min % -1)"));
            if (ok) *ok = 0;
            return avm_nil();
        }
        return avm_int(a.as.i % b.as.i);
    }
    return avm_nil();
}

AvmValue avm_list_int_new(int cap);
void avm_print_value_no_nl(AvmValue v);
const char* avm_val_type_short(AvmValue v);

#endif
