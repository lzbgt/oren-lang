#ifndef AVM_SHA256_H
#define AVM_SHA256_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} AvmSha256Ctx;

void avm_sha256_init(AvmSha256Ctx* ctx);
void avm_sha256_update(AvmSha256Ctx* ctx, const uint8_t* data, size_t len);
void avm_sha256_final(AvmSha256Ctx* ctx, uint8_t out[32]);

void avm_sha256_hex(const uint8_t hash[32], char out_hex[65]);

#endif

