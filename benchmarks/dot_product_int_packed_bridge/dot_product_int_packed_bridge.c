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

    int32_t *a = (int32_t *)malloc((size_t)n * sizeof(int32_t));
    int32_t *b = (int32_t *)malloc((size_t)n * sizeof(int32_t));
    if (!a || !b) {
        fprintf(stderr, "alloc failed\n");
        free(a);
        free(b);
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        a[i] = (int32_t)((i * 3ULL + 1ULL) % 1000ULL);
        b[i] = (int32_t)((i * 7ULL + 2ULL) % 1000ULL);
    }

    int64_t sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += (int64_t)a[i] * (int64_t)b[i];
        }
    }

    printf("%" PRId64 "\n", sum);
    free(a);
    free(b);
    return 0;
}
