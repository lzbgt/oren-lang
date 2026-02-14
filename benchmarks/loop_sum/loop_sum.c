#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t parse_u64(const char *s) {
    if (s == NULL || *s == '\0') {
        return 0;
    }
    return (uint64_t)strtoull(s, NULL, 10);
}

int main(int argc, char **argv) {
    uint64_t n = 20000000ULL;
    if (argc > 1) {
        uint64_t v = parse_u64(argv[1]);
        if (v > 0) {
            n = v;
        }
    }

    const uint64_t mod = 1000000007ULL;
    uint64_t x = 1ULL;
    uint64_t sum = 0ULL;
    for (uint64_t i = 0; i < n; i++) {
        x = (x * 1664525ULL + 1013904223ULL) % mod;
        sum += (x % 1000ULL) + (i % 7ULL);
        sum %= mod;
    }

    printf("%" PRIu64 "\n", sum);
    return 0;
}
