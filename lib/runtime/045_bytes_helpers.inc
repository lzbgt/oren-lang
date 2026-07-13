static int bytes_hex_nibble(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

OrenValue oren_bytes_len(OrenValue bytes) {
    if (bytes.type == OREN_TYPE_LIST) {
        OrenList* list = bytes.as.list_val;
        if (!list) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_len: list is nil"));
        return oren_int((long long)list->count);
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_len: expected u8_buf"));
        }
        return oren_int((long long)b->len);
    }
    if (bytes.type == OREN_TYPE_NIL) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_len: bytes is nil"));
    }
    return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_len expects list<int> or u8_buf"));
}

OrenValue oren_bytes_from_hex(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_hex expects string"));
    }
    if (!s.as.string_val) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_hex: invalid string"));
    }
    size_t n = strlen(s.as.string_val);
    if ((n & 1u) != 0u) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_hex: odd length"));
    }
    if (n / 2u > (size_t)UINT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_hex: string too large"));
    }

    OrenValue outv = oren_u8_buf_new_uninit(oren_int((long long)(n / 2u)));
    if (oren_is_err(outv).as.bool_val) return outv;
    if (outv.type != OREN_TYPE_U8_BUF || !outv.as.buf_val || outv.as.buf_val->elem_size != 1u) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_hex: invalid buffer"));
    }

    OrenBuf* out = outv.as.buf_val;
    if (out->len > 0u && !out->data) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_hex: u8_buf payload is nil"));
    }

    for (uint32_t i = 0; i < out->len; i++) {
        int hi = bytes_hex_nibble((unsigned char)s.as.string_val[(size_t)i * 2u + 0u]);
        int lo = bytes_hex_nibble((unsigned char)s.as.string_val[(size_t)i * 2u + 1u]);
        if (hi < 0 || lo < 0) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_hex: invalid hex digit"));
        }
        out->data[i] = (uint8_t)((hi << 4) | lo);
    }
    return outv;
}

OrenValue oren_bytes_to_hex(OrenValue bytes) {
    const char* err_msg = NULL;
    size_t n = 0;
    if (!runtime_bytes_len_checked(bytes, &n, &err_msg)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "bytes_to_hex expects list<int> or u8_buf"));
    }
    if (n > ((SIZE_MAX - 1u) / 2u)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: bytes too large"));
    }

    char* out = (char*)malloc(n * 2u + 1u);
    if (!out) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_to_hex: alloc failed"));
    }

    lock_collections();
    int ok = runtime_bytes_write_hex(bytes, out, &err_msg);
    unlock_collections();
    if (!ok) {
        free(out);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "bytes_to_hex: expected list<int 0..255> or u8_buf"));
    }

    out[n * 2u] = 0;
    oren_register_alloc(out, OREN_ALLOC_STRING);
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = out;
    return v;
}

OrenValue oren_bytes_pack(OrenValue xs) {
    if (xs.type != OREN_TYPE_LIST) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_pack expects list<int 0..255>"));
    }
    OrenList* list = xs.as.list_val;
    if (!list) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_pack: list is nil"));
    }
    if (list->count < 0) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_pack: invalid list"));
    }

    OrenValue outv = oren_u8_buf_new_uninit(oren_int((long long)list->count));
    if (oren_is_err(outv).as.bool_val) return outv;
    if (outv.type != OREN_TYPE_U8_BUF || !outv.as.buf_val || outv.as.buf_val->elem_size != 1u) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_pack: invalid buffer"));
    }

    OrenBuf* out = outv.as.buf_val;
    if (out->len > 0u && !out->data) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_pack: u8_buf payload is nil"));
    }

    const char* err_msg = NULL;
    lock_collections();
    int ok = runtime_bytes_copy_span(xs, 0u, (size_t)list->count, out->data, &err_msg);
    unlock_collections();
    if (!ok) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "bytes_pack: byte out of range"));
    }
    return outv;
}
