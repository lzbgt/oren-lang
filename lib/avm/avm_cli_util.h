#ifndef AVM_CLI_UTIL_H
#define AVM_CLI_UTIL_H

#include "avm.h"
#include <stddef.h>
#include <stdint.h>

uint8_t* read_file(const char* path, size_t* len);
uint64_t now_ns(void);
uint64_t current_rss_bytes(void);
AvmBytes* bytes_from_hex(const char* s);
void free_bytes_obj(AvmBytes* b);
int add_trusted_pubkey_32(uint8_t out_pks[][32], size_t* out_count, size_t cap, const uint8_t* pk32);
int add_trusted_pubkey_hex_list(uint8_t out_pks[][32], size_t* out_count, size_t cap, const char* s, const char* label);
char* bytes_to_hex(const uint8_t* data, size_t len);
void free_constant_pool(AvmValue* consts, size_t n);
void dump_error(AvmValue v);
int env_truthy(const char* s);

#endif
