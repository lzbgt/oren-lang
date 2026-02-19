#ifndef AVM_INT_MATH_H
#define AVM_INT_MATH_H

#include <stdint.h>
#include <string.h>

// Deterministic integer semantics: two's-complement wrap with defined behavior.
static inline uint64_t avm_u64_bits_i64(int64_t x) {
    uint64_t u = 0;
    memcpy(&u, &x, sizeof(u));
    return u;
}

static inline int64_t avm_i64_from_u64_bits(uint64_t u) {
    int64_t x = 0;
    memcpy(&x, &u, sizeof(x));
    return x;
}

static inline int64_t avm_i64_add_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) + avm_u64_bits_i64(b));
}

static inline int64_t avm_i64_sub_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) - avm_u64_bits_i64(b));
}

static inline int64_t avm_i64_mul_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) * avm_u64_bits_i64(b));
}

static inline int avm_i64_is_min(int64_t x) {
    // Compile-time-safe i64 min without relying on implementation-defined casts.
    // -(2^63) == (-9223372036854775807 - 1)
    return x == ((int64_t)-9223372036854775807LL - 1LL);
}

#endif
