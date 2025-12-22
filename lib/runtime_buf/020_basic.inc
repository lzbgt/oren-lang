OrenValue oren_i32_buf_new(OrenValue len) { return buf_new(4u, len, OREN_TYPE_I32_BUF); }
OrenValue oren_i64_buf_new(OrenValue len) { return buf_new(8u, len, OREN_TYPE_I64_BUF); }
OrenValue oren_f32_buf_new(OrenValue len) { return buf_new(4u, len, OREN_TYPE_F32_BUF); }
OrenValue oren_f64_buf_new(OrenValue len) { return buf_new(8u, len, OREN_TYPE_F64_BUF); }
OrenValue oren_u8_buf_new(OrenValue len) { return buf_new(1u, len, OREN_TYPE_U8_BUF); }

OrenValue oren_buf_len(OrenValue buf) {
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        return buf_err("buf_len expects (buf)");
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) return buf_err("buf_len: invalid buffer");
    return oren_int((long long)b->len);
}

OrenValue oren_buf_data_mod(OrenValue buf, OrenValue modv) {
    if (modv.type != OREN_TYPE_INT) return buf_err("buf_data_mod expects (buf, int)");
    long long m = modv.as.int_val;
    if (m <= 0) return buf_err("buf_data_mod: mod must be > 0");
    if ((uint64_t)m > 4096u) return buf_err("buf_data_mod: mod too large");
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        return buf_err("buf_data_mod expects (buf, int)");
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) return buf_err("buf_data_mod: invalid buffer");
    if (b->len == 0) return oren_int(0);
    if (!b->data) return buf_err("buf_data_mod: payload is nil");
    uintptr_t u = (uintptr_t)b->data;
    return oren_int((long long)(u % (uintptr_t)m));
}

static int buf_check_idx(OrenBuf* b, long long idx) {
    if (!b) return 0;
    if (idx < 0) return 0;
    if ((uint64_t)idx >= (uint64_t)b->len) return 0;
    if (!b->data && b->len != 0) return 0;
    return 1;
}

static uint32_t load_u32_le(uint8_t* p) {
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

static void store_u32_le(uint8_t* p, uint32_t u) {
    p[0] = (uint8_t)(u & 0xFFu);
    p[1] = (uint8_t)((u >> 8) & 0xFFu);
    p[2] = (uint8_t)((u >> 16) & 0xFFu);
    p[3] = (uint8_t)((u >> 24) & 0xFFu);
}

static uint64_t load_u64_le(uint8_t* p) {
    uint64_t u = 0;
    for (int i = 0; i < 8; i++) {
        u |= ((uint64_t)p[i] << (uint64_t)(i * 8));
    }
    return u;
}

static void store_u64_le(uint8_t* p, uint64_t u) {
    for (int i = 0; i < 8; i++) {
        p[i] = (uint8_t)((u >> (uint64_t)(i * 8)) & 0xFFu);
    }
}

OrenValue oren_buf_load_u8(OrenValue buf, OrenValue idxv) {
    if (!buf_is_u8(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_u8 expects (u8_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_u8: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx;
    return oren_int((long long)(*p));
}

OrenValue oren_buf_store_u8(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_u8(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_u8 expects (u8_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_u8: index out of bounds");
    long long v = vv.as.int_val;
    if (v < 0 || v > 255) return buf_err("buf_store_u8: byte out of range");
    uint8_t* p = buf_data(b) + (uint32_t)idx;
    *p = (uint8_t)v;
    return buf;
}

OrenValue oren_buf_load_i32(OrenValue buf, OrenValue idxv) {
    if (!buf_is_i32(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_i32 expects (i32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_i32: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    uint32_t u = load_u32_le(p);
    int32_t v = (int32_t)u;
    return oren_int((long long)v);
}

OrenValue oren_buf_store_i32(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_i32(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_i32 expects (i32_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_i32: index out of bounds");
    int32_t v = (int32_t)vv.as.int_val; // wrap
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    store_u32_le(p, (uint32_t)v);
    return buf;
}

OrenValue oren_buf_load_i64(OrenValue buf, OrenValue idxv) {
    if (!buf_is_i64(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_i64 expects (i64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_i64: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    uint64_t u = load_u64_le(p);
    int64_t v = 0;
    memcpy(&v, &u, sizeof(v));
    return oren_int((long long)v);
}

OrenValue oren_buf_store_i64(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_i64(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_store_i64 expects (i64_buf, int, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_i64: index out of bounds");
    int64_t v = (int64_t)vv.as.int_val;
    uint64_t u = 0;
    memcpy(&u, &v, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    store_u64_le(p, u);
    return buf;
}

OrenValue oren_buf_load_f64(OrenValue buf, OrenValue idxv) {
    if (!buf_is_f64(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_f64 expects (f64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_f64: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    uint64_t u = load_u64_le(p);
    double d = 0.0;
    memcpy(&d, &u, sizeof(d));
    return oren_float(d);
}

OrenValue oren_buf_store_f64(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_f64(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_store_f64 expects (f64_buf, int, float)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_f64: index out of bounds");
    double d = vv.as.float_val;
    uint64_t u = 0;
    memcpy(&u, &d, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 8u;
    store_u64_le(p, u);
    return buf;
}

OrenValue oren_buf_load_f32(OrenValue buf, OrenValue idxv) {
    if (!buf_is_f32(buf) || idxv.type != OREN_TYPE_INT) return buf_err("oren_buf_load_f32 expects (f32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_load_f32: index out of bounds");
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    uint32_t u = load_u32_le(p);
    float f = 0.0f;
    memcpy(&f, &u, sizeof(f));
    return oren_float((double)f);
}

OrenValue oren_buf_store_f32(OrenValue buf, OrenValue idxv, OrenValue vv) {
    if (!buf_is_f32(buf) || idxv.type != OREN_TYPE_INT || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_store_f32 expects (f32_buf, int, float)");
    OrenBuf* b = buf.as.buf_val;
    long long idx = idxv.as.int_val;
    if (!buf_check_idx(b, idx)) return buf_err("buf_store_f32: index out of bounds");
    float f = (float)vv.as.float_val; // deterministic float32 boundary
    uint32_t u = 0;
    memcpy(&u, &f, sizeof(u));
    uint8_t* p = buf_data(b) + (uint32_t)idx * 4u;
    store_u32_le(p, u);
    return buf;
}

OrenValue oren_buf_fill_u8(OrenValue buf, OrenValue vv) {
    if (!buf_is_u8(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_u8 expects (u8_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    long long v = vv.as.int_val;
    if (v < 0 || v > 255) return buf_err("buf_fill_u8: byte out of range");
    uint8_t u = (uint8_t)v;
    for (uint32_t i = 0; i < n; i++) {
        buf_data(b)[i] = u;
    }
    return buf;
}

OrenValue oren_buf_fill_i32(OrenValue buf, OrenValue vv) {
    if (!buf_is_i32(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_i32 expects (i32_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    int32_t v = (int32_t)vv.as.int_val;
    uint32_t u = (uint32_t)v;
    for (uint32_t i = 0; i < n; i++) {
        store_u32_le(buf_data(b) + i * 4u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_i64(OrenValue buf, OrenValue vv) {
    if (!buf_is_i64(buf) || vv.type != OREN_TYPE_INT) return buf_err("oren_buf_fill_i64 expects (i64_buf, int)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    int64_t v = (int64_t)vv.as.int_val;
    uint64_t u = 0;
    memcpy(&u, &v, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u64_le(buf_data(b) + i * 8u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_f64(OrenValue buf, OrenValue vv) {
    if (!buf_is_f64(buf) || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_fill_f64 expects (f64_buf, float)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    double d = vv.as.float_val;
    uint64_t u = 0;
    memcpy(&u, &d, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u64_le(buf_data(b) + i * 8u, u);
    }
    return buf;
}

OrenValue oren_buf_fill_f32(OrenValue buf, OrenValue vv) {
    if (!buf_is_f32(buf) || vv.type != OREN_TYPE_FLOAT) return buf_err("oren_buf_fill_f32 expects (f32_buf, float)");
    OrenBuf* b = buf.as.buf_val;
    uint32_t n = buf_len_u32(b);
    float f = (float)vv.as.float_val;
    uint32_t u = 0;
    memcpy(&u, &f, sizeof(u));
    for (uint32_t i = 0; i < n; i++) {
        store_u32_le(buf_data(b) + i * 4u, u);
    }
    return buf;
}

static OrenValue buf_new_like(OrenValue a) {
    if (buf_is_i32(a)) return oren_i32_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_i64(a)) return oren_i64_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_f32(a)) return oren_f32_buf_new(oren_int((long long)a.as.buf_val->len));
    if (buf_is_f64(a)) return oren_f64_buf_new(oren_int((long long)a.as.buf_val->len));
    return buf_err("buf_new_like: invalid buffer");
}

