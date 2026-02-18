#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(void) {
    const int n = 2000000;
    int *a = (int *)malloc((size_t)n * sizeof(int));
    int *b = (int *)malloc((size_t)n * sizeof(int));
    if (!a || !b) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }
    for (int i = 0; i < n; i++) {
        a[i] = (i * 3 + 1) % 1000;
        b[i] = (i * 7 + 2) % 1000;
    }
    long long sum = 0;
    for (int i = 0; i < n; i++) {
        sum += (long long)a[i] * (long long)b[i];
    }
    printf("%lld\n", sum);
    free(a);
    free(b);
    return 0;
}
