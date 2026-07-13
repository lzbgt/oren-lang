static int bytes_get_u8_checked(OrenValue bytes, int idx, uint8_t* out) {
    if (idx < 0 || !out) return 0;
    const char* err_msg = NULL;
    return runtime_bytes_copy_span(bytes, (size_t)idx, 1u, out, &err_msg);
}

static int bytes_set_u8_checked(OrenValue bytes, int idx, uint8_t val) {
    if (idx < 0) return 0;
    const char* err_msg = NULL;
    return runtime_bytes_write_span(bytes, (size_t)idx, &val, 1u, &err_msg);
}

static int bytes_read_u8_span_checked(OrenValue bytes, int idx, uint8_t* out, int width) {
    if (idx < 0 || width < 0 || !out) return 0;
    const char* err_msg = NULL;
    return runtime_bytes_copy_span(bytes, (size_t)idx, (size_t)width, out, &err_msg);
}

static int bytes_write_u8_span_checked(OrenValue bytes, int idx, const uint8_t* src, int width) {
    if (idx < 0 || width < 0 || !src) return 0;
    const char* err_msg = NULL;
    return runtime_bytes_write_span(bytes, (size_t)idx, src, (size_t)width, &err_msg);
}

OrenValue oren_bytes_get_u8(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u8 expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u8: index out of bounds or byte out of range"));
    return oren_int((int64_t)b0);
}

OrenValue oren_bytes_set_u8(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8 expects (bytes:list<int>|u8_buf, idx:int, value:int 0..255)"));
    if (value.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8 expects (bytes:list<int>|u8_buf, idx:int, value:int 0..255)"));
    int idx = (int)index.as.int_val;
    int64_t v = value.as.int_val;
    if (v < 0 || v > 255) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8: value out of range"));
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, (uint8_t)v);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u8: index out of bounds"));
    return oren_int(v);
}

OrenValue oren_bytes_unpack(OrenValue bytes) {
    if (!(bytes.type == OREN_TYPE_LIST || bytes.type == OREN_TYPE_U8_BUF)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_unpack expects list<int> or u8_buf"));
    }
    const char* err_msg = NULL;
    size_t count_size = 0;
    if (!runtime_bytes_len_checked(bytes, &count_size, &err_msg)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "bytes_unpack: invalid bytes"));
    }
    if (count_size > (size_t)INT_MAX) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_unpack: length too large"));
    int count = (int)count_size;

    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = count;
    list->capacity = count;
    list->items = NULL;
    list->all_int = 1;
    if (count > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)count);
        if (!list->items) {
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_unpack: alloc failed"));
        }
    }

    lock_collections();
    int ok = runtime_bytes_copy_span_to_list(bytes, 0u, count_size, list, &err_msg);
    unlock_collections();
    if (!ok) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "bytes_unpack: invalid bytes"));
    }

    OrenValue out;
    out.type = OREN_TYPE_LIST;
    out.as.list_val = list;
    return out;
}

OrenValue oren_bytes_get_u16_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[2];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be: index out of bounds or byte out of range"));
    return oren_int(((int64_t)bs[0] << 8) | (int64_t)bs[1]);
}

OrenValue oren_bytes_get_u16_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[2];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le: index out of bounds or byte out of range"));
    return oren_int(((int64_t)bs[1] << 8) | (int64_t)bs[0]);
}

OrenValue oren_bytes_get_i16_be(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u16_be(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 32768) v -= 65536;
    return oren_int(v);
}

OrenValue oren_bytes_get_i16_le(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u16_le(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 32768) v -= 65536;
    return oren_int(v);
}

OrenValue oren_bytes_get_u32_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_be expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[4];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_be: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)bs[0] << 24) | ((int64_t)bs[1] << 16) | ((int64_t)bs[2] << 8) | (int64_t)bs[3];
    return oren_int(v);
}

OrenValue oren_bytes_get_u32_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[4];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)bs[3] << 24) | ((int64_t)bs[2] << 16) | ((int64_t)bs[1] << 8) | (int64_t)bs[0];
    return oren_int(v);
}

OrenValue oren_bytes_get_i32_be(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u32_be(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 2147483648LL) v -= 4294967296LL;
    return oren_int(v);
}

OrenValue oren_bytes_get_i32_le(OrenValue bytes, OrenValue index) {
    OrenValue u = oren_bytes_get_u32_le(bytes, index);
    if (oren_is_err(u).as.bool_val) return u;
    int64_t v = u.as.int_val;
    if (v >= 2147483648LL) v -= 4294967296LL;
    return oren_int(v);
}

OrenValue oren_bytes_get_u64_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_be expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[8];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 8);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_be: index out of bounds or byte out of range"));
    uint64_t u = ((uint64_t)bs[0] << 56) | ((uint64_t)bs[1] << 48) | ((uint64_t)bs[2] << 40) | ((uint64_t)bs[3] << 32) |
                 ((uint64_t)bs[4] << 24) | ((uint64_t)bs[5] << 16) | ((uint64_t)bs[6] << 8) | (uint64_t)bs[7];
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_get_u64_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t bs[8];
    lock_collections();
    int ok = bytes_read_u8_span_checked(bytes, idx, bs, 8);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_le: index out of bounds or byte out of range"));
    uint64_t u = ((uint64_t)bs[7] << 56) | ((uint64_t)bs[6] << 48) | ((uint64_t)bs[5] << 40) | ((uint64_t)bs[4] << 32) |
                 ((uint64_t)bs[3] << 24) | ((uint64_t)bs[2] << 16) | ((uint64_t)bs[1] << 8) | (uint64_t)bs[0];
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_get_i64_be(OrenValue bytes, OrenValue index) {
    // int64 and uint64 share the same in-memory representation in v0; unsigned
    // values above MAX_I64 are not representable in OrenValue.
    return oren_bytes_get_u64_be(bytes, index);
}

OrenValue oren_bytes_get_i64_le(OrenValue bytes, OrenValue index) {
    return oren_bytes_get_u64_le(bytes, index);
}

OrenValue oren_bytes_set_u16_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_be expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t bs[2] = {(uint8_t)((u >> 8) & 0xFFu), (uint8_t)(u & 0xFFu)};
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_be: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_u16_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_le expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t bs[2] = {(uint8_t)(u & 0xFFu), (uint8_t)((u >> 8) & 0xFFu)};
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u16_le: index out of bounds"));
    return oren_int((int64_t)u);
}

static int64_t sign_extend16(uint64_t u) {
    int64_t v = (int64_t)(u & 0xFFFFu);
    if (v >= 32768) v -= 65536;
    return v;
}

static int64_t sign_extend32(uint64_t u) {
    int64_t v = (int64_t)(u & 0xFFFFFFFFu);
    if (v >= 2147483648LL) v -= 4294967296LL;
    return v;
}

OrenValue oren_bytes_set_i16_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_be expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t bs[2] = {(uint8_t)((u >> 8) & 0xFFu), (uint8_t)(u & 0xFFu)};
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_be: index out of bounds"));
    return oren_int(sign_extend16(u));
}

OrenValue oren_bytes_set_i16_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_le expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFu;
    uint8_t bs[2] = {(uint8_t)(u & 0xFFu), (uint8_t)((u >> 8) & 0xFFu)};
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 2);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i16_le: index out of bounds"));
    return oren_int(sign_extend16(u));
}

OrenValue oren_bytes_set_u32_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_be expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t bs[4] = {
        (uint8_t)((u >> 24) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)(u & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_be: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_u32_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_le expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t bs[4] = {
        (uint8_t)(u & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 24) & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u32_le: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_i32_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_be expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t bs[4] = {
        (uint8_t)((u >> 24) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)(u & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_be: index out of bounds"));
    return oren_int(sign_extend32(u));
}

OrenValue oren_bytes_set_i32_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_le expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val & 0xFFFFFFFFu;
    uint8_t bs[4] = {
        (uint8_t)(u & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 24) & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 4);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_i32_le: index out of bounds"));
    return oren_int(sign_extend32(u));
}

OrenValue oren_bytes_set_u64_be(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u64_be expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val;
    uint8_t bs[8] = {
        (uint8_t)((u >> 56) & 0xFFu),
        (uint8_t)((u >> 48) & 0xFFu),
        (uint8_t)((u >> 40) & 0xFFu),
        (uint8_t)((u >> 32) & 0xFFu),
        (uint8_t)((u >> 24) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)(u & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 8);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u64_be: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_u64_le(OrenValue bytes, OrenValue index, OrenValue value) {
    if (index.type != OREN_TYPE_INT || value.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u64_le expects (bytes:list<int>|u8_buf, idx:int, value:int)"));
    }
    int idx = (int)index.as.int_val;
    uint64_t u = (uint64_t)value.as.int_val;
    uint8_t bs[8] = {
        (uint8_t)(u & 0xFFu),
        (uint8_t)((u >> 8) & 0xFFu),
        (uint8_t)((u >> 16) & 0xFFu),
        (uint8_t)((u >> 24) & 0xFFu),
        (uint8_t)((u >> 32) & 0xFFu),
        (uint8_t)((u >> 40) & 0xFFu),
        (uint8_t)((u >> 48) & 0xFFu),
        (uint8_t)((u >> 56) & 0xFFu)
    };
    lock_collections();
    int ok = bytes_write_u8_span_checked(bytes, idx, bs, 8);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_set_u64_le: index out of bounds"));
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_set_i64_be(OrenValue bytes, OrenValue index, OrenValue value) {
    return oren_bytes_set_u64_be(bytes, index, value);
}

OrenValue oren_bytes_set_i64_le(OrenValue bytes, OrenValue index, OrenValue value) {
    return oren_bytes_set_u64_le(bytes, index, value);
}
