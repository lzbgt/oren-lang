#include "avm_internal.h"

#include <stdlib.h>
#include <string.h>

static uint64_t read_u64_le(FILE* f, int* ok) {
    uint8_t b[8];
    if (fread(b, 1, 8, f) != 8) { *ok = 0; return 0; }
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= ((uint64_t)b[i]) << (8 * i);
    return v;
}

static uint32_t read_u32_le(FILE* f, int* ok) {
    uint8_t b[4];
    if (fread(b, 1, 4, f) != 4) { *ok = 0; return 0; }
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) v |= ((uint32_t)b[i]) << (8 * i);
    return v;
}

static int write_u64_le(FILE* f, uint64_t v) {
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    return fwrite(b, 1, 8, f) == 8;
}

static int write_u32_le(FILE* f, uint32_t v) {
    uint8_t b[4];
    for (int i = 0; i < 4; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
    return fwrite(b, 1, 4, f) == 4;
}

static int write_u8(FILE* f, uint8_t v) {
    return fwrite(&v, 1, 1, f) == 1;
}

#include "avm_state.inc"

void avm_release_heap_all(AvmVM* vm) {
    // `avm_release_heap` is static inside avm_state.inc; expose a narrow wrapper for vm teardown.
    avm_release_heap(vm);
}
