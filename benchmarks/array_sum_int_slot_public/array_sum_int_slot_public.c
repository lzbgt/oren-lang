#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t parse_u64(const char *s) {
    if (s == NULL || *s == '\0') {
        return 0ULL;
    }
    return (uint64_t)strtoull(s, NULL, 10);
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

    int64_t *xs = (int64_t *)malloc((size_t)n * sizeof(int64_t));
    if (!xs) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        xs[i] = (int64_t)((i * 3ULL + 7ULL) % 1000ULL);
    }

    int64_t sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += xs[i];
        }
    }

    printf("%" PRId64 "\n", sum);
    free(xs);
    return 0;
}
