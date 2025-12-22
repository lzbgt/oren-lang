#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// TweetNaCl requires a `randombytes()` symbol for key generation APIs.
// AVM uses TweetNaCl only for signature verification, so this must never be called.
//
// If this is called, abort: it indicates an unintended dependency on host RNG.
void randombytes(uint8_t* x, unsigned long long xlen) {
    (void)x;
    (void)xlen;
    fprintf(stderr, "FATAL: randombytes() called (TweetNaCl) - AVM should not use host RNG here\n");
    abort();
}

