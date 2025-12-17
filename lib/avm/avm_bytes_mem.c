#include "avm_internal.h"

#include <string.h>

int bytes_ensure_cap(AvmBytes* b, int need) {
    if (!b) return 0;
    if (need <= b->capacity) return 1;
    int new_cap = b->capacity ? b->capacity : 64;
    while (new_cap < need) new_cap *= 2;
    uint8_t* nd = (uint8_t*)avm_heap_realloc_k(b->data, (size_t)new_cap, AVM_ALLOC_KIND_BYTES);
    if (!nd) return 0;
    b->data = nd;
    b->capacity = new_cap;
    return 1;
}

int mem_write_u8(AvmBytes* b, uint32_t* pos, uint8_t v) {
    if (!b || !pos) return 0;
    uint32_t p = *pos;
    if (!bytes_ensure_cap(b, (int)(p + 1))) return 0;
    b->data[p] = v;
    p += 1;
    if ((int)p > b->len) b->len = (int)p;
    *pos = p;
    return 1;
}

int mem_write_u16_le(AvmBytes* b, uint32_t* pos, uint16_t v) {
    if (!mem_write_u8(b, pos, (uint8_t)(v & 0xFF))) return 0;
    if (!mem_write_u8(b, pos, (uint8_t)((v >> 8) & 0xFF))) return 0;
    return 1;
}

int mem_write_u32_le(AvmBytes* b, uint32_t* pos, uint32_t v) {
    for (int i = 0; i < 4; i++) {
        if (!mem_write_u8(b, pos, (uint8_t)((v >> (8 * i)) & 0xFF))) return 0;
    }
    return 1;
}

int mem_write_u64_le(AvmBytes* b, uint32_t* pos, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        if (!mem_write_u8(b, pos, (uint8_t)((v >> (8 * i)) & 0xFF))) return 0;
    }
    return 1;
}

int mem_write_bytes(AvmBytes* b, uint32_t* pos, const uint8_t* data, uint32_t len) {
    if (!b || !pos) return 0;
    uint32_t p = *pos;
    if (len == 0) return 1;
    if (!bytes_ensure_cap(b, (int)(p + len))) return 0;
    memcpy(b->data + p, data, len);
    p += len;
    if ((int)p > b->len) b->len = (int)p;
    *pos = p;
    return 1;
}

int mem_read_u8(const AvmBytes* b, uint32_t* pos, uint8_t* out) {
    if (!b || !pos || !out) return 0;
    if (*pos >= (uint32_t)b->len) return 0;
    *out = b->data[*pos];
    *pos += 1;
    return 1;
}

int mem_read_u16_le(const AvmBytes* b, uint32_t* pos, uint16_t* out) {
    uint8_t b0, b1;
    if (!mem_read_u8(b, pos, &b0)) return 0;
    if (!mem_read_u8(b, pos, &b1)) return 0;
    *out = (uint16_t)b0 | ((uint16_t)b1 << 8);
    return 1;
}

int mem_read_u32_le(const AvmBytes* b, uint32_t* pos, uint32_t* out) {
    uint8_t bb[4];
    for (int i = 0; i < 4; i++) if (!mem_read_u8(b, pos, &bb[i])) return 0;
    *out = (uint32_t)bb[0] | ((uint32_t)bb[1] << 8) | ((uint32_t)bb[2] << 16) | ((uint32_t)bb[3] << 24);
    return 1;
}

int mem_read_u64_le(const AvmBytes* b, uint32_t* pos, uint64_t* out) {
    uint64_t v = 0;
    uint8_t bb = 0;
    for (int i = 0; i < 8; i++) {
        if (!mem_read_u8(b, pos, &bb)) return 0;
        v |= ((uint64_t)bb) << (8 * i);
    }
    *out = v;
    return 1;
}

int mem_read_bytes(const AvmBytes* b, uint32_t* pos, uint8_t* out, uint32_t len) {
    if (!b || !pos || (!out && len > 0)) return 0;
    if ((uint64_t)(*pos) + (uint64_t)len > (uint64_t)b->len) return 0;
    if (len > 0) memcpy(out, b->data + *pos, len);
    *pos += len;
    return 1;
}

