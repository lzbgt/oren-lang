#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *s;
    int *arr;
} KeepItem;

static long parse_iters_env(void) {
    const char *env = getenv("OREN_BENCH_ITERS");
    if (!env || !env[0]) return 10000;
    char *end = NULL;
    long v = strtol(env, &end, 10);
    if (v == 0) return 10000;
    return v;
}

int main(void) {
    long iters = parse_iters_env();
    if (iters < 0) iters = 10000;

    size_t keep_cap = 1024;
    KeepItem *keep = (KeepItem *)calloc(keep_cap, sizeof(KeepItem));
    size_t keep_len = 0;
    int keep_mod = 0;

    for (long i = 0; i < iters; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "s%ld", i);
        char *s = strdup(buf);
        if (!s) return 1;

        int *arr = (int *)malloc(sizeof(int) * 4);
        if (!arr) return 1;
        arr[0] = (int)i;
        arr[1] = (int)(i + 1);
        arr[2] = (int)(i + 2);
        arr[3] = (int)(i + 3);

        if (keep_mod == 0) {
            size_t slot = keep_len % keep_cap;
            if (keep[slot].s) free(keep[slot].s);
            if (keep[slot].arr) free(keep[slot].arr);
            keep[slot].s = s;
            keep[slot].arr = arr;
            keep_len++;
        } else {
            free(s);
            free(arr);
        }
        keep_mod++;
        if (keep_mod == 97) keep_mod = 0;

        if ((i % 1000) == 0) {
            for (size_t k = 0; k < keep_cap; k++) {
                if (keep[k].s) { free(keep[k].s); keep[k].s = NULL; }
                if (keep[k].arr) { free(keep[k].arr); keep[k].arr = NULL; }
            }
            keep_len = 0;
        }
    }

    size_t alive = 0;
    for (size_t k = 0; k < keep_cap; k++) {
        if (keep[k].s) alive++;
    }
    printf("alloc_drop keep=%zu\n", alive);

    for (size_t k = 0; k < keep_cap; k++) {
        if (keep[k].s) free(keep[k].s);
        if (keep[k].arr) free(keep[k].arr);
    }
    free(keep);
    return 0;
}
