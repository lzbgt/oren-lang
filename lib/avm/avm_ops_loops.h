#ifndef AVM_OPS_LOOPS_H
#define AVM_OPS_LOOPS_H

#include "avm_fastmod.h"
#include "avm_int_math.h"
#include "avm_vm_values.h"

#include <limits.h>

static inline void avm_op_int_lcg_sum_loop(AvmVM* vm) {
    if (vm->sp < 9) return;
    AvmValue modiv = vm->stack[--vm->sp];
    AvmValue modxv = vm->stack[--vm->sp];
    AvmValue modv = vm->stack[--vm->sp];
    AvmValue addv = vm->stack[--vm->sp];
    AvmValue mulv = vm->stack[--vm->sp];
    AvmValue endv = vm->stack[--vm->sp];
    AvmValue idxv = vm->stack[--vm->sp];
    AvmValue sumv = vm->stack[--vm->sp];
    AvmValue xv = vm->stack[--vm->sp];
    AvmValue one = avm_int(1);
    if (xv.type == AVM_VAL_INT && sumv.type == AVM_VAL_INT &&
        idxv.type == AVM_VAL_INT && endv.type == AVM_VAL_INT &&
        mulv.type == AVM_VAL_INT && addv.type == AVM_VAL_INT &&
        modv.type == AVM_VAL_INT && modxv.type == AVM_VAL_INT &&
        modiv.type == AVM_VAL_INT) {
        int64_t mod = modv.as.i;
        int64_t modx = modxv.as.i;
        int64_t modi = modiv.as.i;
        if (mod > 0 && modx > 0 && modi > 0) {
            int64_t i = idxv.as.i;
            int64_t end = endv.as.i;
            int64_t x = xv.as.i;
            int64_t sum = sumv.as.i;
            int64_t mul = mulv.as.i;
            int64_t add = addv.as.i;
            if (i >= 0 && end >= 0 && x >= 0 && sum >= 0) {
                uint64_t mod_u = (uint64_t)mod;
                uint64_t modx_u = (uint64_t)modx;
                uint64_t modi_u = (uint64_t)modi;
                uint64_t mul_u = (uint64_t)mul;
                uint64_t add_u = (uint64_t)add;
                uint64_t i_u = (uint64_t)i;
                uint64_t end_u = (uint64_t)end;
                uint64_t x_u = (uint64_t)x;
                uint64_t sum_u = (uint64_t)sum;
                if (mod_u <= UINT32_MAX && modx_u <= UINT32_MAX && modi_u <= UINT32_MAX &&
                    mul_u <= UINT32_MAX && add_u <= UINT32_MAX &&
                    i_u <= UINT32_MAX && end_u <= UINT32_MAX &&
                    x_u <= UINT32_MAX && sum_u <= UINT32_MAX) {
                    uint32_t mod32 = (uint32_t)mod_u;
                    uint32_t modx32 = (uint32_t)modx_u;
                    uint32_t modi32 = (uint32_t)modi_u;
                    uint32_t mul32 = (uint32_t)mul_u;
                    uint32_t add32 = (uint32_t)add_u;
                    uint32_t i32 = (uint32_t)i_u;
                    uint32_t end32 = (uint32_t)end_u;
                    uint32_t x32 = (uint32_t)x_u;
                    uint32_t sum32 = (uint32_t)sum_u;
                    uint32_t i_mod32 = (modi32 == 0) ? 0u : (uint32_t)((uint64_t)i32 % (uint64_t)modi32);
                    int fast_sum32 = ((uint64_t)modx32 + (uint64_t)modi32 <= (uint64_t)mod32);
                    if (i32 < end32) {
                        if (fast_sum32) {
                            for (; (uint32_t)(end32 - i32) >= 4u;) {
                                uint64_t x_next0 = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next0 % (uint64_t)mod32);
                                uint32_t term_x0 = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i0 = i_mod32;
                                uint64_t sum_next0 = (uint64_t)sum32 + (uint64_t)term_x0 + (uint64_t)term_i0;
                                if (sum_next0 >= (uint64_t)mod32) sum_next0 -= (uint64_t)mod32;
                                sum32 = (uint32_t)sum_next0;
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                                i32++;

                                uint64_t x_next1 = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next1 % (uint64_t)mod32);
                                uint32_t term_x1 = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i1 = i_mod32;
                                uint64_t sum_next1 = (uint64_t)sum32 + (uint64_t)term_x1 + (uint64_t)term_i1;
                                if (sum_next1 >= (uint64_t)mod32) sum_next1 -= (uint64_t)mod32;
                                sum32 = (uint32_t)sum_next1;
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                                i32++;

                                uint64_t x_next2 = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next2 % (uint64_t)mod32);
                                uint32_t term_x2 = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i2 = i_mod32;
                                uint64_t sum_next2 = (uint64_t)sum32 + (uint64_t)term_x2 + (uint64_t)term_i2;
                                if (sum_next2 >= (uint64_t)mod32) sum_next2 -= (uint64_t)mod32;
                                sum32 = (uint32_t)sum_next2;
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                                i32++;

                                uint64_t x_next3 = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next3 % (uint64_t)mod32);
                                uint32_t term_x3 = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i3 = i_mod32;
                                uint64_t sum_next3 = (uint64_t)sum32 + (uint64_t)term_x3 + (uint64_t)term_i3;
                                if (sum_next3 >= (uint64_t)mod32) sum_next3 -= (uint64_t)mod32;
                                sum32 = (uint32_t)sum_next3;
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                                i32++;
                            }
                            for (; i32 < end32; i32++) {
                                uint64_t x_next = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next % (uint64_t)mod32);
                                uint32_t term_x = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i = i_mod32;
                                uint64_t sum_next = (uint64_t)sum32 + (uint64_t)term_x + (uint64_t)term_i;
                                if (sum_next >= (uint64_t)mod32) sum_next -= (uint64_t)mod32;
                                sum32 = (uint32_t)sum_next;
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                            }
                        } else {
                            for (; i32 < end32; i32++) {
                                uint64_t x_next = (uint64_t)x32 * (uint64_t)mul32 + (uint64_t)add32;
                                x32 = (uint32_t)(x_next % (uint64_t)mod32);
                                uint32_t term_x = (uint32_t)((uint64_t)x32 % (uint64_t)modx32);
                                uint32_t term_i = i_mod32;
                                uint64_t sum_next = (uint64_t)sum32 + (uint64_t)term_x + (uint64_t)term_i;
                                sum32 = (uint32_t)(sum_next % (uint64_t)mod32);
                                i_mod32++;
                                if (i_mod32 >= modi32) i_mod32 = 0;
                            }
                        }
                    }
                    i_u = (uint64_t)i32;
                    sum_u = (uint64_t)sum32;
                    x_u = (uint64_t)x32;
                } else {
                    uint64_t mod_m = avm_fastmod_prepare_u64(mod_u);
                    uint64_t modx_m = avm_fastmod_prepare_u64(modx_u);
                    uint64_t modi_m = avm_fastmod_prepare_u64(modi_u);
                    uint64_t i_mod = avm_fastmod_u64(i_u, modi_u, modi_m);
                    int fast_sum = (modx_u + modi_u <= mod_u);
                    if (i_u < end_u) {
                        if (fast_sum) {
                            for (; end_u - i_u >= 4;) {
                                uint64_t x_next0 = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next0, mod_u, mod_m);
                                uint64_t term_x0 = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i0 = i_mod;
                                sum_u = sum_u + term_x0 + term_i0;
                                if (sum_u >= mod_u) {
                                    sum_u -= mod_u;
                                }
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                                i_u++;

                                uint64_t x_next1 = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next1, mod_u, mod_m);
                                uint64_t term_x1 = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i1 = i_mod;
                                sum_u = sum_u + term_x1 + term_i1;
                                if (sum_u >= mod_u) {
                                    sum_u -= mod_u;
                                }
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                                i_u++;

                                uint64_t x_next2 = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next2, mod_u, mod_m);
                                uint64_t term_x2 = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i2 = i_mod;
                                sum_u = sum_u + term_x2 + term_i2;
                                if (sum_u >= mod_u) {
                                    sum_u -= mod_u;
                                }
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                                i_u++;

                                uint64_t x_next3 = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next3, mod_u, mod_m);
                                uint64_t term_x3 = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i3 = i_mod;
                                sum_u = sum_u + term_x3 + term_i3;
                                if (sum_u >= mod_u) {
                                    sum_u -= mod_u;
                                }
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                                i_u++;
                            }
                            for (; i_u < end_u; i_u++) {
                                uint64_t x_next = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next, mod_u, mod_m);
                                uint64_t term_x = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i = i_mod;
                                sum_u = sum_u + term_x + term_i;
                                if (sum_u >= mod_u) {
                                    sum_u -= mod_u;
                                }
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                            }
                        } else {
                            for (; i_u < end_u; i_u++) {
                                uint64_t x_next = x_u * mul_u + add_u;
                                x_u = avm_fastmod_u64(x_next, mod_u, mod_m);
                                uint64_t term_x = avm_fastmod_u64(x_u, modx_u, modx_m);
                                uint64_t term_i = i_mod;
                                uint64_t sum_next = sum_u + term_x + term_i;
                                sum_u = avm_fastmod_u64(sum_next, mod_u, mod_m);
                                i_mod++;
                                if (i_mod >= modi_u) {
                                    i_mod = 0;
                                }
                            }
                        }
                    }
                }
                idxv = avm_int((int64_t)i_u);
                sumv = avm_int((int64_t)sum_u);
                xv = avm_int((int64_t)x_u);
                goto lcg_sum_push;
            }
            if (i < end) {
                for (; i < end; i++) {
                    x = avm_i64_add_wrap(avm_i64_mul_wrap(x, mul), add);
                    x = x % mod;
                    int64_t term_x = x % modx;
                    int64_t term_i = i % modi;
                    sum = avm_i64_add_wrap(sum, term_x);
                    sum = avm_i64_add_wrap(sum, term_i);
                    sum = sum % mod;
                }
            }
            idxv = avm_int(i);
            sumv = avm_int(sum);
            xv = avm_int(x);
            goto lcg_sum_push;
        }
    }

    while (1) {
        AvmValue cond = avm_lt_values(idxv, endv);
        if (!avm_truthy(cond)) break;
        int ok = 1;
        AvmValue mul = avm_mul_values(xv, mulv);
        AvmValue tmp = avm_add_values(vm, mul, addv, &ok);
        if (!ok || !vm->running) break;
        xv = avm_mod_values(vm, tmp, modv, &ok);
        if (!ok || !vm->running) break;
        AvmValue term_x = avm_mod_values(vm, xv, modxv, &ok);
        if (!ok || !vm->running) break;
        AvmValue term_i = avm_mod_values(vm, idxv, modiv, &ok);
        if (!ok || !vm->running) break;
        tmp = avm_add_values(vm, sumv, term_x, &ok);
        if (!ok || !vm->running) break;
        tmp = avm_add_values(vm, tmp, term_i, &ok);
        if (!ok || !vm->running) break;
        sumv = avm_mod_values(vm, tmp, modv, &ok);
        if (!ok || !vm->running) break;
        idxv = avm_add_values(vm, idxv, one, &ok);
        if (!ok || !vm->running) break;
    }

lcg_sum_push:
    vm->stack[vm->sp++] = idxv;
    vm->stack[vm->sp++] = sumv;
    vm->stack[vm->sp++] = xv;
}

static inline void avm_op_list_sum_int_loop(AvmVM* vm) {
    if (vm->sp < 4) return;
    AvmValue sum = vm->stack[--vm->sp];
    AvmValue n = vm->stack[--vm->sp];
    AvmValue idx = vm->stack[--vm->sp];
    AvmValue list = vm->stack[--vm->sp];
    AvmValue one = avm_int(1);
    if (list.type == AVM_VAL_LIST_INT &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list.as.li) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count = list.as.li->count;
                int64_t acc = sum.as.i;
                if (end <= count) {
                    for (; i < end; i++) {
                        acc = avm_i64_add_wrap(acc, list.as.li->items[i]);
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_sum_push;
                        }
                        acc = avm_i64_add_wrap(acc, list.as.li->items[i]);
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_sum_push;
            }
        }
    }
    if (list.type == AVM_VAL_LIST &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list.as.l) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count = list.as.l->count;
                int64_t acc = sum.as.i;
                int all_int = list.as.l->all_int;
                if (end <= count) {
                    if (all_int) {
                        for (; i < end; i++) {
                            AvmValue va = list.as.l->items[i];
                            acc = avm_i64_add_wrap(acc, va.as.i);
                        }
                    } else {
                        for (; i < end; i++) {
                            AvmValue va = list.as.l->items[i];
                            if (va.type != AVM_VAL_INT) {
                                idx = avm_int(i);
                                sum = avm_int(acc);
                                goto list_sum_slow;
                            }
                            acc = avm_i64_add_wrap(acc, va.as.i);
                        }
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_sum_push;
                        }
                        AvmValue va = list.as.l->items[i];
                        if (!all_int && va.type != AVM_VAL_INT) {
                            idx = avm_int(i);
                            sum = avm_int(acc);
                            goto list_sum_slow;
                        }
                        acc = avm_i64_add_wrap(acc, va.as.i);
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_sum_push;
            }
        }
    }

list_sum_slow:
    while (1) {
        AvmValue cond = avm_lt_values(idx, n);
        if (!avm_truthy(cond)) break;
        AvmValue acc = avm_add_values(vm, sum, avm_list_get_value(list, idx), NULL);
        if (acc.type == AVM_VAL_NIL) { sum = avm_nil(); break; }
        sum = acc;
        idx = avm_add_values(vm, idx, one, NULL);
    }

list_sum_push:
    vm->stack[vm->sp++] = sum;
    vm->stack[vm->sp++] = idx;
}

static inline void avm_op_list_sum3_int_loop(AvmVM* vm) {
    if (vm->sp < 6) return;
    AvmValue sum = vm->stack[--vm->sp];
    AvmValue n = vm->stack[--vm->sp];
    AvmValue idx = vm->stack[--vm->sp];
    AvmValue list_c = vm->stack[--vm->sp];
    AvmValue list_b = vm->stack[--vm->sp];
    AvmValue list_a = vm->stack[--vm->sp];
    AvmValue one = avm_int(1);
    if (list_a.type == AVM_VAL_LIST_INT && list_b.type == AVM_VAL_LIST_INT &&
        list_c.type == AVM_VAL_LIST_INT &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list_a.as.li && list_b.as.li && list_c.as.li) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count_a = list_a.as.li->count;
                int count_b = list_b.as.li->count;
                int count_c = list_c.as.li->count;
                int64_t acc = sum.as.i;
                if (end <= count_a && end <= count_b && end <= count_c) {
                    for (; i < end; i++) {
                        acc = avm_i64_add_wrap(acc, list_a.as.li->items[i]);
                        acc = avm_i64_add_wrap(acc, list_b.as.li->items[i]);
                        acc = avm_i64_add_wrap(acc, list_c.as.li->items[i]);
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count_a || i >= count_b || i >= count_c) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_sum3_push;
                        }
                        acc = avm_i64_add_wrap(acc, list_a.as.li->items[i]);
                        acc = avm_i64_add_wrap(acc, list_b.as.li->items[i]);
                        acc = avm_i64_add_wrap(acc, list_c.as.li->items[i]);
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_sum3_push;
            }
        }
    }
    if (list_a.type == AVM_VAL_LIST && list_b.type == AVM_VAL_LIST &&
        list_c.type == AVM_VAL_LIST &&
        idx.type == AVM_VAL_INT && n.type == AVM_VAL_INT &&
        sum.type == AVM_VAL_INT) {
        int64_t i64 = idx.as.i;
        int64_t end64 = n.as.i;
        if (i64 >= 0 && i64 <= (int64_t)INT_MAX &&
            end64 >= (int64_t)INT_MIN && end64 <= (int64_t)INT_MAX &&
            list_a.as.l && list_b.as.l && list_c.as.l) {
            int i = (int)i64;
            int end = (int)end64;
            if (i < end) {
                int count_a = list_a.as.l->count;
                int count_b = list_b.as.l->count;
                int count_c = list_c.as.l->count;
                int64_t acc = sum.as.i;
                int all_int = list_a.as.l->all_int && list_b.as.l->all_int && list_c.as.l->all_int;
                if (end <= count_a && end <= count_b && end <= count_c) {
                    if (all_int) {
                        for (; i < end; i++) {
                            AvmValue va = list_a.as.l->items[i];
                            AvmValue vb = list_b.as.l->items[i];
                            AvmValue vc = list_c.as.l->items[i];
                            acc = avm_i64_add_wrap(acc, va.as.i);
                            acc = avm_i64_add_wrap(acc, vb.as.i);
                            acc = avm_i64_add_wrap(acc, vc.as.i);
                        }
                    } else {
                        for (; i < end; i++) {
                            AvmValue va = list_a.as.l->items[i];
                            AvmValue vb = list_b.as.l->items[i];
                            AvmValue vc = list_c.as.l->items[i];
                            if (va.type != AVM_VAL_INT || vb.type != AVM_VAL_INT || vc.type != AVM_VAL_INT) {
                                idx = avm_int(i);
                                sum = avm_int(acc);
                                goto list_sum3_slow;
                            }
                            acc = avm_i64_add_wrap(acc, va.as.i);
                            acc = avm_i64_add_wrap(acc, vb.as.i);
                            acc = avm_i64_add_wrap(acc, vc.as.i);
                        }
                    }
                } else {
                    for (; i < end; i++) {
                        if (i < 0 || i >= count_a || i >= count_b || i >= count_c) {
                            sum = avm_nil();
                            idx = avm_int(end);
                            goto list_sum3_push;
                        }
                        AvmValue va = list_a.as.l->items[i];
                        AvmValue vb = list_b.as.l->items[i];
                        AvmValue vc = list_c.as.l->items[i];
                        if (!all_int && (va.type != AVM_VAL_INT || vb.type != AVM_VAL_INT || vc.type != AVM_VAL_INT)) {
                            idx = avm_int(i);
                            sum = avm_int(acc);
                            goto list_sum3_slow;
                        }
                        acc = avm_i64_add_wrap(acc, va.as.i);
                        acc = avm_i64_add_wrap(acc, vb.as.i);
                        acc = avm_i64_add_wrap(acc, vc.as.i);
                    }
                }
                sum = avm_int(acc);
                idx = avm_int(i);
                goto list_sum3_push;
            }
        }
    }

list_sum3_slow:
    while (1) {
        AvmValue cond = avm_lt_values(idx, n);
        if (!avm_truthy(cond)) break;
        int ok = 1;
        AvmValue tmp = avm_add_values(vm, sum, avm_list_get_value(list_a, idx), &ok);
        if (!ok || !vm->running) break;
        tmp = avm_add_values(vm, tmp, avm_list_get_value(list_b, idx), &ok);
        if (!ok || !vm->running) break;
        tmp = avm_add_values(vm, tmp, avm_list_get_value(list_c, idx), &ok);
        if (!ok || !vm->running) break;
        sum = tmp;
        idx = avm_add_values(vm, idx, one, &ok);
        if (!ok || !vm->running) break;
    }

list_sum3_push:
    vm->stack[vm->sp++] = sum;
    vm->stack[vm->sp++] = idx;
}

#endif
