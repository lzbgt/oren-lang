static int bytes_hex_nibble(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static char bytes_hex_char(uint8_t v) {
    return (char)(v < 10u ? ('0' + v) : ('a' + (v - 10u)));
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
    OrenValue nv = oren_bytes_len(bytes);
    if (oren_is_err(nv).as.bool_val) return nv;
    if (nv.type != OREN_TYPE_INT || nv.as.int_val < 0) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: invalid length"));
    }
    size_t n = (size_t)nv.as.int_val;
    if (n > ((SIZE_MAX - 1u) / 2u)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: bytes too large"));
    }

    char* out = (char*)malloc(n * 2u + 1u);
    if (!out) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_to_hex: alloc failed"));
    }

    lock_collections();
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u || b->len < n || (n > 0u && !b->data)) {
            unlock_collections();
            free(out);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: expected u8_buf"));
        }
        for (size_t i = 0; i < n; i++) {
            uint8_t bv = b->data[i];
            out[i * 2u + 0u] = bytes_hex_char((uint8_t)((bv >> 4) & 0x0Fu));
            out[i * 2u + 1u] = bytes_hex_char((uint8_t)(bv & 0x0Fu));
        }
    } else if (bytes.type == OREN_TYPE_LIST) {
        OrenList* list = bytes.as.list_val;
        if (!list || list->count < 0 || (size_t)list->count < n || (n > 0u && !list->items)) {
            unlock_collections();
            free(out);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: expected list<int 0..255>"));
        }
        for (size_t i = 0; i < n; i++) {
            OrenValue v = list->items[i];
            if (v.type != OREN_TYPE_INT || v.as.int_val < 0 || v.as.int_val > 255) {
                unlock_collections();
                free(out);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: expected list<int 0..255>"));
            }
            uint8_t bv = (uint8_t)v.as.int_val;
            out[i * 2u + 0u] = bytes_hex_char((uint8_t)((bv >> 4) & 0x0Fu));
            out[i * 2u + 1u] = bytes_hex_char((uint8_t)(bv & 0x0Fu));
        }
    } else {
        unlock_collections();
        free(out);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_to_hex: expected list<int 0..255> or u8_buf"));
    }
    unlock_collections();

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

    lock_collections();
    for (int i = 0; i < list->count; i++) {
        OrenValue v = list->items[i];
        if (v.type != OREN_TYPE_INT || v.as.int_val < 0 || v.as.int_val > 255) {
            unlock_collections();
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_pack: byte out of range"));
        }
        out->data[i] = (uint8_t)v.as.int_val;
    }
    unlock_collections();
    return outv;
}
