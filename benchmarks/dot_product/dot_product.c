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
    int *a = (int *)malloc((size_t)n * sizeof(int));
    int *b = (int *)malloc((size_t)n * sizeof(int));
    if (!a || !b) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }
    for (uint64_t i = 0; i < n; i++) {
        a[i] = (int)((i * 3ULL + 1ULL) % 1000ULL);
        b[i] = (int)((i * 7ULL + 2ULL) % 1000ULL);
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
