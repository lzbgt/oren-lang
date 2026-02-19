#ifndef AVM_FASTMOD_H
#define AVM_FASTMOD_H

#include <stdint.h>

#if defined(__SIZEOF_INT128__)
#define AVM_HAVE_U128 1
#else
#define AVM_HAVE_U128 0
#endif

// Prepare a reciprocal for Barrett-style fast modulo. Returns 0 for d <= 1.
static inline uint64_t avm_fastmod_prepare_u64(uint64_t d) {
#if AVM_HAVE_U128
    if (d <= 1) return 0;
    return (uint64_t)(((__uint128_t)1u << 64) / d);
#else
    (void)d;
    return 0;
#endif
}

// Compute n % d using a precomputed reciprocal. Safe for d > 0; returns 0 for d <= 1.
static inline uint64_t avm_fastmod_u64(uint64_t n, uint64_t d, uint64_t recip) {
#if AVM_HAVE_U128
    if (d <= 1) return 0;
    __uint128_t prod = ( (__uint128_t)n * (__uint128_t)recip );
    uint64_t q = (uint64_t)(prod >> 64);
    uint64_t r = n - q * d;
    if (r >= d) r -= d;
    return r;
#else
    (void)recip;
    return d ? (n % d) : 0;
#endif
}

#endif
