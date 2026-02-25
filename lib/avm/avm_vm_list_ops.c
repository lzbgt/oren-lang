#include "avm_vm_list_ops.h"
#include "avm_vm_values.h"

#include <limits.h>

void avm_op_list_dot(AvmVM* vm) {
    if (!vm || vm->sp < 5) return;
    AvmValue sum = vm->stack[--vm->sp];
    AvmValue n = vm->stack[--vm->sp];
    AvmValue idx = vm->stack[--vm->sp];
    AvmValue list_b = vm->stack[--vm->sp];
    AvmValue list_a = vm->stack[--vm->sp];
    AvmValue one = avm_int(1);
    if (list_a.type == AVM_VAL_LIST_INT && list_b.type == AVM_VAL_LIST_INT &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list_a.as.li && list_b.as.li) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count_a = list_a.as.li->count;
                int count_b = list_b.as.li->count;
                int64_t acc = sum.as.i;
                if (end <= count_a && end <= count_b) {
                    for (; i < end; i++) {
                        acc = avm_i64_add_wrap(acc, avm_i64_mul_wrap(list_a.as.li->items[i], list_b.as.li->items[i]));
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count_a || i >= count_b) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_dot_push;
                        }
                        acc = avm_i64_add_wrap(acc, avm_i64_mul_wrap(list_a.as.li->items[i], list_b.as.li->items[i]));
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_dot_push;
            }
        }
    }
    if (list_a.type == AVM_VAL_LIST && list_b.type == AVM_VAL_LIST &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list_a.as.l && list_b.as.l) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count_a = list_a.as.l->count;
                int count_b = list_b.as.l->count;
                int64_t acc = sum.as.i;
                int all_int = list_a.as.l->all_int && list_b.as.l->all_int;
                if (end <= count_a && end <= count_b) {
                    if (all_int) {
                        for (; i < end; i++) {
                            AvmValue va = list_a.as.l->items[i];
                            AvmValue vb = list_b.as.l->items[i];
                            acc = avm_i64_add_wrap(acc, avm_i64_mul_wrap(va.as.i, vb.as.i));
                        }
                    } else {
                        for (; i < end; i++) {
                            AvmValue va = list_a.as.l->items[i];
                            AvmValue vb = list_b.as.l->items[i];
                            if (va.type != AVM_VAL_INT || vb.type != AVM_VAL_INT) {
                                idx = avm_int(i);
                                sum = avm_int(acc);
                                goto list_dot_slow;
                            }
                            acc = avm_i64_add_wrap(acc, avm_i64_mul_wrap(va.as.i, vb.as.i));
                        }
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count_a || i >= count_b) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_dot_push;
                        }
                        AvmValue va = list_a.as.l->items[i];
                        AvmValue vb = list_b.as.l->items[i];
                        if (!all_int && (va.type != AVM_VAL_INT || vb.type != AVM_VAL_INT)) {
                            idx = avm_int(i);
                            sum = avm_int(acc);
                            goto list_dot_slow;
                        }
                        acc = avm_i64_add_wrap(acc, avm_i64_mul_wrap(va.as.i, vb.as.i));
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_dot_push;
            }
        }
    }

list_dot_slow:
    while (1) {
        AvmValue cond = avm_lt_values(idx, n);
        if (!avm_truthy(cond)) break;
        AvmValue va = avm_list_get_value(list_a, idx);
        AvmValue vb = avm_list_get_value(list_b, idx);
        AvmValue mul = avm_mul_values(va, vb);
        int ok = 1;
        sum = avm_add_values(vm, sum, mul, &ok);
        if (!ok || !vm->running) break;
        idx = avm_add_values(vm, idx, one, &ok);
        if (!ok || !vm->running) break;
    }
list_dot_push:
    vm->stack[vm->sp++] = idx;
    vm->stack[vm->sp++] = sum;
}

void avm_op_list_push_int_loop(AvmVM* vm) {
    if (!vm || vm->sp < 6) return;
    AvmValue modv = vm->stack[--vm->sp];
    AvmValue addv = vm->stack[--vm->sp];
    AvmValue mulv = vm->stack[--vm->sp];
    AvmValue endv = vm->stack[--vm->sp];
    AvmValue idxv = vm->stack[--vm->sp];
    AvmValue obj = vm->stack[--vm->sp];
    if (idxv.type != AVM_VAL_INT || endv.type != AVM_VAL_INT ||
        mulv.type != AVM_VAL_INT || addv.type != AVM_VAL_INT ||
        modv.type != AVM_VAL_INT) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push_loop expects (list, idx, end, mul, add, mod)");
        return;
    }
    int use_list_int = (obj.type == AVM_VAL_LIST_INT && obj.as.li);
    if (!use_list_int && (obj.type != AVM_VAL_LIST || !obj.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push_loop expects (list, idx, end, mul, add, mod)");
        return;
    }
    int64_t i = idxv.as.i;
    int64_t end = endv.as.i;
    int64_t mul = mulv.as.i;
    int64_t add = addv.as.i;
    int64_t mod = modv.as.i;
    int64_t final_i = i;
    if (mod < 0) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push_loop mod must be >= 0");
        return;
    }
    if (i < end) {
        int64_t iters = end - i;
        int64_t cur_count = use_list_int ? (int64_t)obj.as.li->count : (int64_t)obj.as.l->count;
        int64_t new_count = cur_count + iters;
        if (new_count > (int64_t)INT_MAX) {
            AvmValue e = avm_err(AVM_ERR_INVALID_ARG, "list_int_push_loop size overflow");
            avm_abort(vm, e);
            vm->stack[vm->sp++] = e;
            return;
        }
        if (use_list_int) {
            AvmListInt* listi = obj.as.li;
            if (listi->capacity < (int)new_count) {
                if (!avm_list_int_ensure_cap(listi, (int)new_count)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
            for (; i < end; i++) {
                int64_t v = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul), add);
                if (mod > 0) {
                    v = v % mod;
                }
                listi->items[listi->count++] = v;
            }
        } else {
            AvmList* list = obj.as.l;
            if (list->count == 0) {
                // list_int_push_loop only writes ints; mark int-fast.
                list->all_int = 1;
            }
            if (list->capacity < (int)new_count) {
                if (!avm_list_ensure_cap(list, (int)new_count)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
            for (; i < end; i++) {
                int64_t v = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul), add);
                if (mod > 0) {
                    v = v % mod;
                }
                list->items[list->count++] = avm_int(v);
            }
        }
        final_i = end;
    }
    vm->stack[vm->sp++] = avm_int(final_i);
}

void avm_op_list_push2_int_loop(AvmVM* vm) {
    if (!vm || vm->sp < 10) return;
    AvmValue modb = vm->stack[--vm->sp];
    AvmValue addb = vm->stack[--vm->sp];
    AvmValue mulb = vm->stack[--vm->sp];
    AvmValue moda = vm->stack[--vm->sp];
    AvmValue adda = vm->stack[--vm->sp];
    AvmValue mula = vm->stack[--vm->sp];
    AvmValue endv = vm->stack[--vm->sp];
    AvmValue idxv = vm->stack[--vm->sp];
    AvmValue list_b = vm->stack[--vm->sp];
    AvmValue list_a = vm->stack[--vm->sp];
    if (idxv.type != AVM_VAL_INT || endv.type != AVM_VAL_INT ||
        mula.type != AVM_VAL_INT || adda.type != AVM_VAL_INT ||
        moda.type != AVM_VAL_INT || mulb.type != AVM_VAL_INT ||
        addb.type != AVM_VAL_INT || modb.type != AVM_VAL_INT) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop expects (list_a, list_b, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b)");
        return;
    }
    int use_list_int_a = (list_a.type == AVM_VAL_LIST_INT && list_a.as.li);
    int use_list_int_b = (list_b.type == AVM_VAL_LIST_INT && list_b.as.li);
    if (!use_list_int_a && (list_a.type != AVM_VAL_LIST || !list_a.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop expects list_a");
        return;
    }
    if (!use_list_int_b && (list_b.type != AVM_VAL_LIST || !list_b.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop expects list_b");
        return;
    }
    if (use_list_int_a && use_list_int_b && list_a.as.li == list_b.as.li) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop expects distinct lists");
        return;
    }
    if (!use_list_int_a && !use_list_int_b && list_a.as.l == list_b.as.l) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop expects distinct lists");
        return;
    }
    int64_t i = idxv.as.i;
    int64_t end = endv.as.i;
    int64_t mul_a = mula.as.i;
    int64_t add_a = adda.as.i;
    int64_t mod_a = moda.as.i;
    int64_t mul_b = mulb.as.i;
    int64_t add_b = addb.as.i;
    int64_t mod_b = modb.as.i;
    int64_t final_i = i;
    if (mod_a < 0 || mod_b < 0) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop mod must be >= 0");
        return;
    }
    if (i < end) {
        int64_t iters = end - i;
        int64_t cur_a = use_list_int_a ? (int64_t)list_a.as.li->count : (int64_t)list_a.as.l->count;
        int64_t cur_b = use_list_int_b ? (int64_t)list_b.as.li->count : (int64_t)list_b.as.l->count;
        int64_t new_a = cur_a + iters;
        int64_t new_b = cur_b + iters;
        if (new_a > (int64_t)INT_MAX || new_b > (int64_t)INT_MAX) {
            AvmValue e = avm_err(AVM_ERR_INVALID_ARG, "list_int_push2_loop size overflow");
            avm_abort(vm, e);
            vm->stack[vm->sp++] = e;
            return;
        }
        if (use_list_int_a) {
            if (list_a.as.li->capacity < (int)new_a) {
                if (!avm_list_int_ensure_cap(list_a.as.li, (int)new_a)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        } else {
            AvmList* la = list_a.as.l;
            if (la->count == 0) la->all_int = 1;
            if (la->capacity < (int)new_a) {
                if (!avm_list_ensure_cap(la, (int)new_a)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        }
        if (use_list_int_b) {
            if (list_b.as.li->capacity < (int)new_b) {
                if (!avm_list_int_ensure_cap(list_b.as.li, (int)new_b)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        } else {
            AvmList* lb = list_b.as.l;
            if (lb->count == 0) lb->all_int = 1;
            if (lb->capacity < (int)new_b) {
                if (!avm_list_ensure_cap(lb, (int)new_b)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        }
        for (; i < end; i++) {
            int64_t va = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul_a), add_a);
            if (mod_a > 0) {
                va = va % mod_a;
            }
            int64_t vb = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul_b), add_b);
            if (mod_b > 0) {
                vb = vb % mod_b;
            }
            if (use_list_int_a) {
                list_a.as.li->items[list_a.as.li->count++] = va;
            } else {
                list_a.as.l->items[list_a.as.l->count++] = avm_int(va);
            }
            if (use_list_int_b) {
                list_b.as.li->items[list_b.as.li->count++] = vb;
            } else {
                list_b.as.l->items[list_b.as.l->count++] = avm_int(vb);
            }
        }
        final_i = end;
    }
    vm->stack[vm->sp++] = avm_int(final_i);
}

void avm_op_list_push3_int_loop(AvmVM* vm) {
    if (!vm || vm->sp < 14) return;
    AvmValue modc = vm->stack[--vm->sp];
    AvmValue addc = vm->stack[--vm->sp];
    AvmValue mulc = vm->stack[--vm->sp];
    AvmValue modb = vm->stack[--vm->sp];
    AvmValue addb = vm->stack[--vm->sp];
    AvmValue mulb = vm->stack[--vm->sp];
    AvmValue moda = vm->stack[--vm->sp];
    AvmValue adda = vm->stack[--vm->sp];
    AvmValue mula = vm->stack[--vm->sp];
    AvmValue endv = vm->stack[--vm->sp];
    AvmValue idxv = vm->stack[--vm->sp];
    AvmValue list_c = vm->stack[--vm->sp];
    AvmValue list_b = vm->stack[--vm->sp];
    AvmValue list_a = vm->stack[--vm->sp];
    if (idxv.type != AVM_VAL_INT || endv.type != AVM_VAL_INT ||
        mula.type != AVM_VAL_INT || adda.type != AVM_VAL_INT ||
        moda.type != AVM_VAL_INT || mulb.type != AVM_VAL_INT ||
        addb.type != AVM_VAL_INT || modb.type != AVM_VAL_INT ||
        mulc.type != AVM_VAL_INT || addc.type != AVM_VAL_INT ||
        modc.type != AVM_VAL_INT) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects (list_a, list_b, list_c, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b, mul_c, add_c, mod_c)");
        return;
    }
    int use_list_int_a = (list_a.type == AVM_VAL_LIST_INT && list_a.as.li);
    int use_list_int_b = (list_b.type == AVM_VAL_LIST_INT && list_b.as.li);
    int use_list_int_c = (list_c.type == AVM_VAL_LIST_INT && list_c.as.li);
    if (!use_list_int_a && (list_a.type != AVM_VAL_LIST || !list_a.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects list_a");
        return;
    }
    if (!use_list_int_b && (list_b.type != AVM_VAL_LIST || !list_b.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects list_b");
        return;
    }
    if (!use_list_int_c && (list_c.type != AVM_VAL_LIST || !list_c.as.l)) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects list_c");
        return;
    }
    if (use_list_int_a && use_list_int_b && list_a.as.li == list_b.as.li) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    if (use_list_int_a && use_list_int_c && list_a.as.li == list_c.as.li) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    if (use_list_int_b && use_list_int_c && list_b.as.li == list_c.as.li) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    if (!use_list_int_a && !use_list_int_b && list_a.as.l == list_b.as.l) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    if (!use_list_int_a && !use_list_int_c && list_a.as.l == list_c.as.l) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    if (!use_list_int_b && !use_list_int_c && list_b.as.l == list_c.as.l) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop expects distinct lists");
        return;
    }
    int64_t i = idxv.as.i;
    int64_t end = endv.as.i;
    int64_t mul_a = mula.as.i;
    int64_t add_a = adda.as.i;
    int64_t mod_a = moda.as.i;
    int64_t mul_b = mulb.as.i;
    int64_t add_b = addb.as.i;
    int64_t mod_b = modb.as.i;
    int64_t mul_c = mulc.as.i;
    int64_t add_c = addc.as.i;
    int64_t mod_c = modc.as.i;
    int64_t final_i = i;
    if (mod_a < 0 || mod_b < 0 || mod_c < 0) {
        vm->stack[vm->sp++] = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop mod must be >= 0");
        return;
    }
    if (i < end) {
        int64_t iters = end - i;
        int64_t cur_a = use_list_int_a ? (int64_t)list_a.as.li->count : (int64_t)list_a.as.l->count;
        int64_t cur_b = use_list_int_b ? (int64_t)list_b.as.li->count : (int64_t)list_b.as.l->count;
        int64_t cur_c = use_list_int_c ? (int64_t)list_c.as.li->count : (int64_t)list_c.as.l->count;
        int64_t new_a = cur_a + iters;
        int64_t new_b = cur_b + iters;
        int64_t new_c = cur_c + iters;
        if (new_a > (int64_t)INT_MAX || new_b > (int64_t)INT_MAX || new_c > (int64_t)INT_MAX) {
            AvmValue e = avm_err(AVM_ERR_INVALID_ARG, "list_int_push3_loop size overflow");
            avm_abort(vm, e);
            vm->stack[vm->sp++] = e;
            return;
        }
        if (use_list_int_a) {
            if (list_a.as.li->capacity < (int)new_a) {
                if (!avm_list_int_ensure_cap(list_a.as.li, (int)new_a)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        } else {
            AvmList* la = list_a.as.l;
            if (la->count == 0) la->all_int = 1;
            if (la->capacity < (int)new_a) {
                if (!avm_list_ensure_cap(la, (int)new_a)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        }
        if (use_list_int_b) {
            if (list_b.as.li->capacity < (int)new_b) {
                if (!avm_list_int_ensure_cap(list_b.as.li, (int)new_b)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        } else {
            AvmList* lb = list_b.as.l;
            if (lb->count == 0) lb->all_int = 1;
            if (lb->capacity < (int)new_b) {
                if (!avm_list_ensure_cap(lb, (int)new_b)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        }
        if (use_list_int_c) {
            if (list_c.as.li->capacity < (int)new_c) {
                if (!avm_list_int_ensure_cap(list_c.as.li, (int)new_c)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        } else {
            AvmList* lc = list_c.as.l;
            if (lc->count == 0) lc->all_int = 1;
            if (lc->capacity < (int)new_c) {
                if (!avm_list_ensure_cap(lc, (int)new_c)) {
                    AvmValue e = avm_alloc_fail_value();
                    avm_abort(vm, e);
                    vm->stack[vm->sp++] = e;
                    return;
                }
            }
        }
        for (; i < end; i++) {
            int64_t va = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul_a), add_a);
            if (mod_a > 0) {
                va = va % mod_a;
            }
            int64_t vb = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul_b), add_b);
            if (mod_b > 0) {
                vb = vb % mod_b;
            }
            int64_t vc = avm_i64_add_wrap(avm_i64_mul_wrap(i, mul_c), add_c);
            if (mod_c > 0) {
                vc = vc % mod_c;
            }
            if (use_list_int_a) {
                list_a.as.li->items[list_a.as.li->count++] = va;
            } else {
                list_a.as.l->items[list_a.as.l->count++] = avm_int(va);
            }
            if (use_list_int_b) {
                list_b.as.li->items[list_b.as.li->count++] = vb;
            } else {
                list_b.as.l->items[list_b.as.l->count++] = avm_int(vb);
            }
            if (use_list_int_c) {
                list_c.as.li->items[list_c.as.li->count++] = vc;
            } else {
                list_c.as.l->items[list_c.as.l->count++] = avm_int(vc);
            }
        }
        final_i = end;
    }
    vm->stack[vm->sp++] = avm_int(final_i);
}
