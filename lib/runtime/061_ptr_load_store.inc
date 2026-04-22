static uint8_t ptr_u8(uint64_t p) {
    return *((uint8_t*)(uintptr_t)p);
}

static void ptr_set_u8(uint64_t p, uint8_t v) {
    *((uint8_t*)(uintptr_t)p) = v;
}

OrenValue oren_ptr_get_u8(OrenValue p) {
    if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u8 expects int"); return OREN_NIL; }
    uint64_t addr = (uint64_t)p.as.int_val;
    return oren_int((int64_t)(ptr_u8(addr) & 0xFFu));
}

OrenValue oren_ptr_set_u8(OrenValue p, OrenValue v) {
    if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u8 expects (int,int)"); return OREN_NIL; }
    uint64_t addr = (uint64_t)p.as.int_val;
    uint8_t b = (uint8_t)(v.as.int_val & 0xFF);
    ptr_set_u8(addr, b);
    return oren_int((int64_t)b);
}

static uint16_t ptr_u16_be(uint64_t p) {
    return (uint16_t)((uint16_t)ptr_u8(p + 0) << 8) | (uint16_t)ptr_u8(p + 1);
}

static uint16_t ptr_u16_le(uint64_t p) {
    return (uint16_t)((uint16_t)ptr_u8(p + 1) << 8) | (uint16_t)ptr_u8(p + 0);
}

static void ptr_set_u16_be(uint64_t p, uint16_t v) {
    ptr_set_u8(p + 0, (uint8_t)((v >> 8) & 0xFF));
    ptr_set_u8(p + 1, (uint8_t)(v & 0xFF));
}

static void ptr_set_u16_le(uint64_t p, uint16_t v) {
    ptr_set_u8(p + 0, (uint8_t)(v & 0xFF));
    ptr_set_u8(p + 1, (uint8_t)((v >> 8) & 0xFF));
}

OrenValue oren_ptr_get_u16_be(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u16_be expects int"); return OREN_NIL; } return oren_int((int64_t)ptr_u16_be((uint64_t)p.as.int_val)); }
OrenValue oren_ptr_get_u16_le(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u16_le expects int"); return OREN_NIL; } return oren_int((int64_t)ptr_u16_le((uint64_t)p.as.int_val)); }

OrenValue oren_ptr_get_i16_be(OrenValue p) {
    if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_i16_be expects int"); return OREN_NIL; }
    uint16_t u = ptr_u16_be((uint64_t)p.as.int_val);
    int16_t s = (int16_t)u;
    return oren_int((int64_t)s);
}

OrenValue oren_ptr_get_i16_le(OrenValue p) {
    if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_i16_le expects int"); return OREN_NIL; }
    uint16_t u = ptr_u16_le((uint64_t)p.as.int_val);
    int16_t s = (int16_t)u;
    return oren_int((int64_t)s);
}

OrenValue oren_ptr_set_u16_be(OrenValue p, OrenValue v) {
    if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u16_be expects (int,int)"); return OREN_NIL; }
    uint16_t u = (uint16_t)(v.as.int_val & 0xFFFF);
    ptr_set_u16_be((uint64_t)p.as.int_val, u);
    return oren_int((int64_t)u);
}

OrenValue oren_ptr_set_u16_le(OrenValue p, OrenValue v) {
    if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u16_le expects (int,int)"); return OREN_NIL; }
    uint16_t u = (uint16_t)(v.as.int_val & 0xFFFF);
    ptr_set_u16_le((uint64_t)p.as.int_val, u);
    return oren_int((int64_t)u);
}

OrenValue oren_ptr_set_i16_be(OrenValue p, OrenValue v) { return oren_ptr_set_u16_be(p, v); }
OrenValue oren_ptr_set_i16_le(OrenValue p, OrenValue v) { return oren_ptr_set_u16_le(p, v); }

static uint32_t ptr_u32_be(uint64_t p) {
    return ((uint32_t)ptr_u8(p + 0) << 24) | ((uint32_t)ptr_u8(p + 1) << 16) | ((uint32_t)ptr_u8(p + 2) << 8) | (uint32_t)ptr_u8(p + 3);
}

static uint32_t ptr_u32_le(uint64_t p) {
    return ((uint32_t)ptr_u8(p + 3) << 24) | ((uint32_t)ptr_u8(p + 2) << 16) | ((uint32_t)ptr_u8(p + 1) << 8) | (uint32_t)ptr_u8(p + 0);
}

static void ptr_set_u32_be(uint64_t p, uint32_t v) {
    ptr_set_u8(p + 0, (uint8_t)((v >> 24) & 0xFF));
    ptr_set_u8(p + 1, (uint8_t)((v >> 16) & 0xFF));
    ptr_set_u8(p + 2, (uint8_t)((v >> 8) & 0xFF));
    ptr_set_u8(p + 3, (uint8_t)(v & 0xFF));
}

static void ptr_set_u32_le(uint64_t p, uint32_t v) {
    ptr_set_u8(p + 0, (uint8_t)(v & 0xFF));
    ptr_set_u8(p + 1, (uint8_t)((v >> 8) & 0xFF));
    ptr_set_u8(p + 2, (uint8_t)((v >> 16) & 0xFF));
    ptr_set_u8(p + 3, (uint8_t)((v >> 24) & 0xFF));
}

OrenValue oren_ptr_get_u32_be(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u32_be expects int"); return OREN_NIL; } return oren_int((int64_t)(uint64_t)ptr_u32_be((uint64_t)p.as.int_val)); }
OrenValue oren_ptr_get_u32_le(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u32_le expects int"); return OREN_NIL; } return oren_int((int64_t)(uint64_t)ptr_u32_le((uint64_t)p.as.int_val)); }

OrenValue oren_ptr_get_i32_be(OrenValue p) {
    if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_i32_be expects int"); return OREN_NIL; }
    uint32_t u = ptr_u32_be((uint64_t)p.as.int_val);
    int32_t s = (int32_t)u;
    return oren_int((int64_t)s);
}

OrenValue oren_ptr_get_i32_le(OrenValue p) {
    if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_i32_le expects int"); return OREN_NIL; }
    uint32_t u = ptr_u32_le((uint64_t)p.as.int_val);
    int32_t s = (int32_t)u;
    return oren_int((int64_t)s);
}

OrenValue oren_ptr_set_u32_be(OrenValue p, OrenValue v) {
    if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u32_be expects (int,int)"); return OREN_NIL; }
    uint32_t u = (uint32_t)(v.as.int_val & 0xFFFFFFFFu);
    ptr_set_u32_be((uint64_t)p.as.int_val, u);
    return oren_int((int64_t)(uint64_t)u);
}

OrenValue oren_ptr_set_u32_le(OrenValue p, OrenValue v) {
    if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u32_le expects (int,int)"); return OREN_NIL; }
    uint32_t u = (uint32_t)(v.as.int_val & 0xFFFFFFFFu);
    ptr_set_u32_le((uint64_t)p.as.int_val, u);
    return oren_int((int64_t)(uint64_t)u);
}

OrenValue oren_ptr_set_i32_be(OrenValue p, OrenValue v) { return oren_ptr_set_u32_be(p, v); }
OrenValue oren_ptr_set_i32_le(OrenValue p, OrenValue v) { return oren_ptr_set_u32_le(p, v); }

static uint64_t ptr_u64_be(uint64_t p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | (uint64_t)ptr_u8(p + (uint64_t)i);
    return v;
}

static uint64_t ptr_u64_le(uint64_t p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | (uint64_t)ptr_u8(p + (uint64_t)i);
    return v;
}

static void ptr_set_u64_be(uint64_t p, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        int shift = 56 - (i * 8);
        ptr_set_u8(p + (uint64_t)i, (uint8_t)((v >> shift) & 0xFF));
    }
}

static void ptr_set_u64_le(uint64_t p, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        int shift = i * 8;
        ptr_set_u8(p + (uint64_t)i, (uint8_t)((v >> shift) & 0xFF));
    }
}

OrenValue oren_ptr_get_u64_be(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u64_be expects int"); return OREN_NIL; } uint64_t u = ptr_u64_be((uint64_t)p.as.int_val); return oren_int((int64_t)u); }
OrenValue oren_ptr_get_u64_le(OrenValue p) { if (p.type != OREN_TYPE_INT) { oren_panic("ptr_get_u64_le expects int"); return OREN_NIL; } uint64_t u = ptr_u64_le((uint64_t)p.as.int_val); return oren_int((int64_t)u); }
OrenValue oren_ptr_get_i64_be(OrenValue p) { return oren_ptr_get_u64_be(p); }
OrenValue oren_ptr_get_i64_le(OrenValue p) { return oren_ptr_get_u64_le(p); }
OrenValue oren_ptr_set_u64_be(OrenValue p, OrenValue v) { if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u64_be expects (int,int)"); return OREN_NIL; } uint64_t u = (uint64_t)v.as.int_val; ptr_set_u64_be((uint64_t)p.as.int_val, u); return oren_int((int64_t)u); }
OrenValue oren_ptr_set_u64_le(OrenValue p, OrenValue v) { if (p.type != OREN_TYPE_INT || v.type != OREN_TYPE_INT) { oren_panic("ptr_set_u64_le expects (int,int)"); return OREN_NIL; } uint64_t u = (uint64_t)v.as.int_val; ptr_set_u64_le((uint64_t)p.as.int_val, u); return oren_int((int64_t)u); }
OrenValue oren_ptr_set_i64_be(OrenValue p, OrenValue v) { return oren_ptr_set_u64_be(p, v); }
OrenValue oren_ptr_set_i64_le(OrenValue p, OrenValue v) { return oren_ptr_set_u64_le(p, v); }
