#include "avm_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <unistd.h>

uint64_t avm_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

uint64_t prng_next_u64(uint64_t* state) {
    // xorshift64* (deterministic, fast). Not cryptographically secure.
    uint64_t x = *state;
    if (x == 0) x = 0x9e3779b97f4a7c15ull;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1Dull;
}

uint64_t host_random_u64(void) {
    uint64_t v = 0;
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    arc4random_buf(&v, sizeof(v));
    return v;
#else
    FILE* f = fopen("/dev/urandom", "rb");
    if (f) {
        if (fread(&v, 1, sizeof(v), f) == sizeof(v)) {
            fclose(f);
            return v;
        }
        fclose(f);
    }
    // Last resort (non-crypto).
    v = ((uint64_t)rand() << 32) ^ (uint64_t)rand();
    return v;
#endif
}

