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

    uint64_t checksum = 0ULL;
    for (uint64_t rep = 0; rep < reps; rep++) {
        uint64_t *xs = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
        if (!xs) {
            fprintf(stderr, "alloc failed\n");
            return 1;
        }
        for (uint64_t i = 0; i < n; i++) {
            xs[i] = (i * 3ULL + 7ULL) % 1000ULL;
        }
        if (n != 0) {
            checksum += xs[0] + xs[n - 1];
        }
        free(xs);
    }

    printf("%" PRIu64 "\n", checksum);
    return 0;
}
