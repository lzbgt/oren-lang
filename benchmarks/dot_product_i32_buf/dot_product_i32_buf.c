#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

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
    int *a = (int *)malloc((size_t)n * sizeof(int));
    int *b = (int *)malloc((size_t)n * sizeof(int));
    if (!a || !b) {
        fprintf(stderr, "alloc failed\n");
        free(a);
        free(b);
        return 1;
    }
    for (uint64_t i = 0; i < n; i++) {
        a[i] = (i * 3 + 1) % 1000;
        b[i] = (i * 7 + 2) % 1000;
    }
    long long sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += (long long)a[i] * (long long)b[i];
        }
    }
    printf("%lld\n", sum);
    free(a);
    free(b);
    return 0;
}
