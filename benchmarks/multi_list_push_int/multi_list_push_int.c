#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    const uint64_t n = 2000000ULL;
    uint64_t *xs = (uint64_t *)malloc(n * sizeof(uint64_t));
    uint64_t *ys = (uint64_t *)malloc(n * sizeof(uint64_t));
    uint64_t *zs = (uint64_t *)malloc(n * sizeof(uint64_t));
    if (!xs || !ys || !zs) {
        fprintf(stderr, "alloc failed\n");
        free(xs);
        free(ys);
        free(zs);
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        xs[i] = (i * 3ULL + 7ULL) % 1000ULL;
        ys[i] = (i * 5ULL + 11ULL) % 1000ULL;
        zs[i] = (i * 7ULL + 13ULL) % 1000ULL;
    }

    uint64_t sum = 0;
    for (uint64_t i = 0; i < n; i++) {
        sum += xs[i];
        sum += ys[i];
        sum += zs[i];
    }

    printf("%" PRIu64 "\n", sum);
    free(xs);
    free(ys);
    free(zs);
    return 0;
}
