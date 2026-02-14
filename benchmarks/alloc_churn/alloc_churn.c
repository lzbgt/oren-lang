#include <stdio.h>
#include <stdlib.h>

int main(void) {
    const long n = 20000;
    long acc = 0;
    for (long i = 0; i < n; i++) {
        long *xs = (long *)malloc(sizeof(long) * 128);
        if (!xs) {
            return 2;
        }
        for (int j = 0; j < 128; j++) {
            xs[j] = i + j;
        }
        acc += xs[0];
        free(xs);
    }
    printf("%ld\n", acc);
    return 0;
}
