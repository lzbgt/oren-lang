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
    if (argc > 1) {
        n = parse_u64(argv[1]);
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
        a[i] = (int)((i * 3 + 1) % 1000);
        b[i] = (int)((i * 7 + 2) % 1000);
    }
    long long checksum = 0;
    if (n != 0) {
        uint64_t last = n - 1;
        checksum = (long long)a[0] + (long long)b[0] + (long long)a[last] + (long long)b[last];
    }
    printf("%lld\n", checksum);
    free(a);
    free(b);
    return 0;
}
