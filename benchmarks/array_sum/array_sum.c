#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t parse_u64(const char *s) {
    if (!s || !*s) return 0ULL;
    char *end = NULL;
    unsigned long long v = strtoull(s, &end, 10);
    if (!end || *end != '\0') return 0ULL;
    return (uint64_t)v;
}

int main(int argc, char **argv) {
    uint64_t n = 2000000ULL;
    uint64_t reps = 1ULL;
    if (argc > 1) {
        n = parse_u64(argv[1]);
    }
    if (argc > 2) {
        reps = parse_u64(argv[2]);
    }
    uint64_t *xs = (uint64_t *)malloc(n * sizeof(uint64_t));
    if (!xs) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        xs[i] = (i * 3ULL + 7ULL) % 1000ULL;
    }

    uint64_t sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += xs[i];
        }
    }

    printf("%" PRIu64 "\n", sum);
    free(xs);
    return 0;
}
