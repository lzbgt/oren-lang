#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    const uint64_t n = 2000000ULL;
    uint64_t *xs = (uint64_t *)malloc(n * sizeof(uint64_t));
    if (!xs) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        xs[i] = (i * 3ULL + 7ULL) % 1000ULL;
    }

    uint64_t sum = 0;
    for (uint64_t i = 0; i < n; i++) {
        sum += xs[i];
    }

    printf("%" PRIu64 "\n", sum);
    free(xs);
    return 0;
}
