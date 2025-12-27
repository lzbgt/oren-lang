OrenValue oren_new_list(int count, ...) {
    va_list args;
    va_start(args, count);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = count;
    list->capacity = count;
    list->items = malloc(sizeof(OrenValue) * count);

    for (int i = 0; i < count; i++) {
        list->items[i] = va_arg(args, OrenValue);
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    unlock_collections();
    return v;
}

OrenValue oren_list_len(OrenValue list) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("len on non-list");
        return OREN_NIL; // Should not be reached
    }
    lock_collections();
    int c = list.as.list_val->count;
    unlock_collections();
    return oren_int(c);
}

OrenValue oren_list_push(OrenValue list, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("push on non-list");
        return list; // Should not be reached
    }
    OrenList *l = list.as.list_val;
    lock_collections();
    if (l->count >= l->capacity) {
        int newCap = l->capacity == 0 ? 4 : l->capacity * 2;
        l->items = realloc(l->items, sizeof(OrenValue) * newCap);
        l->capacity = newCap;
    }
    l->items[l->count] = value;
    l->count += 1;
    unlock_collections();
    return list;
}

OrenValue oren_list_get(OrenValue list, OrenValue index) {
    if (list.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
             oren_panic("index must be integer");
             return OREN_NIL; // Should not be reached
        }
        int idx = (int)index.as.int_val;
        if (idx < 0 || idx >= list.as.list_val->count) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, list.as.list_val->count);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        lock_collections();
        OrenValue v = list.as.list_val->items[idx];
        unlock_collections();
        return v;
    }
    // Also support python list get item?
#ifdef OREN_ENABLE_PYTHON
    if (list.type == OREN_TYPE_PY_OBJ) {
         PyObject* item = PyObject_GetItem(list.as.py_obj, oren_to_py(index)); // This leaks the index py object reference
         if (!item) {
             PyErr_Print();
             oren_panic("Python list get item failed");
             return OREN_NIL; // Should not be reached
         }
         return oren_py_to_oren(item);
    }
#else
    if (list.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    // Support map access via []
    if (list.type == OREN_TYPE_MAP) {
        return oren_map_get(list, index);
    }

    oren_panic("index get on non-list/map");
    return OREN_NIL; // Should not be reached
}

// Set list element in-bounds (does not grow). Returns the written value.
OrenValue oren_list_set(OrenValue list, OrenValue index, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        oren_panic("list_set on non-list");
        return value; // Should not be reached
    }
    if (index.type != OREN_TYPE_INT) {
        oren_panic("list_set index must be int");
        return value; // Should not be reached
    }
    int idx = (int)index.as.int_val;
    if (idx < 0 || idx >= list.as.list_val->count) {
        oren_panic("list_set index out of bounds");
        return value; // Should not be reached
    }
    lock_collections();
    list.as.list_val->items[idx] = value;
    unlock_collections();
    return value;
}

static int bytes_get_u8_checked(OrenValue bytes, int idx, uint8_t* out) {
    if (bytes.type == OREN_TYPE_LIST) {
        if (idx < 0 || idx >= bytes.as.list_val->count) return 0;
        OrenValue v = bytes.as.list_val->items[idx];
        if (v.type != OREN_TYPE_INT) return 0;
        if (v.as.int_val < 0 || v.as.int_val > 255) return 0;
        *out = (uint8_t)v.as.int_val;
        return 1;
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b) return 0;
        if (b->elem_size != 1u) return 0;
        if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) return 0;
        if (!b->data && b->len != 0) return 0;
        *out = b->data[(uint32_t)idx];
        return 1;
    }
    return 0;
}

static int bytes_set_u8_checked(OrenValue bytes, int idx, uint8_t val) {
    if (bytes.type == OREN_TYPE_LIST) {
        if (idx < 0 || idx >= bytes.as.list_val->count) return 0;
        bytes.as.list_val->items[idx] = oren_int((int64_t)val);
        return 1;
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b) return 0;
        if (b->elem_size != 1u) return 0;
        if (idx < 0 || (uint64_t)idx >= (uint64_t)b->len) return 0;
        if (!b->data && b->len != 0) return 0;
        b->data[(uint32_t)idx] = val;
        return 1;
    }
    return 0;
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

OrenValue oren_bytes_get_u16_be(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) && bytes_get_u8_checked(bytes, idx + 1, &b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_be: index out of bounds or byte out of range"));
    return oren_int(((int64_t)b0 << 8) | (int64_t)b1);
}

OrenValue oren_bytes_get_u16_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) && bytes_get_u8_checked(bytes, idx + 1, &b1);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u16_le: index out of bounds or byte out of range"));
    return oren_int(((int64_t)b1 << 8) | (int64_t)b0);
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
    uint8_t b0, b1, b2, b3;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_be: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)b0 << 24) | ((int64_t)b1 << 16) | ((int64_t)b2 << 8) | (int64_t)b3;
    return oren_int(v);
}

OrenValue oren_bytes_get_u32_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1, b2, b3;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u32_le: index out of bounds or byte out of range"));
    int64_t v = ((int64_t)b3 << 24) | ((int64_t)b2 << 16) | ((int64_t)b1 << 8) | (int64_t)b0;
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
    uint8_t b0, b1, b2, b3, b4, b5, b6, b7;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3) &&
             bytes_get_u8_checked(bytes, idx + 4, &b4) &&
             bytes_get_u8_checked(bytes, idx + 5, &b5) &&
             bytes_get_u8_checked(bytes, idx + 6, &b6) &&
             bytes_get_u8_checked(bytes, idx + 7, &b7);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_be: index out of bounds or byte out of range"));
    uint64_t u = ((uint64_t)b0 << 56) | ((uint64_t)b1 << 48) | ((uint64_t)b2 << 40) | ((uint64_t)b3 << 32) |
                 ((uint64_t)b4 << 24) | ((uint64_t)b5 << 16) | ((uint64_t)b6 << 8) | (uint64_t)b7;
    return oren_int((int64_t)u);
}

OrenValue oren_bytes_get_u64_le(OrenValue bytes, OrenValue index) {
    if (index.type != OREN_TYPE_INT) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_le expects (bytes:list<int>|u8_buf, idx:int)"));
    int idx = (int)index.as.int_val;
    uint8_t b0, b1, b2, b3, b4, b5, b6, b7;
    lock_collections();
    int ok = bytes_get_u8_checked(bytes, idx, &b0) &&
             bytes_get_u8_checked(bytes, idx + 1, &b1) &&
             bytes_get_u8_checked(bytes, idx + 2, &b2) &&
             bytes_get_u8_checked(bytes, idx + 3, &b3) &&
             bytes_get_u8_checked(bytes, idx + 4, &b4) &&
             bytes_get_u8_checked(bytes, idx + 5, &b5) &&
             bytes_get_u8_checked(bytes, idx + 6, &b6) &&
             bytes_get_u8_checked(bytes, idx + 7, &b7);
    unlock_collections();
    if (!ok) return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_get_u64_le: index out of bounds or byte out of range"));
    uint64_t u = ((uint64_t)b7 << 56) | ((uint64_t)b6 << 48) | ((uint64_t)b5 << 40) | ((uint64_t)b4 << 32) |
                 ((uint64_t)b3 << 24) | ((uint64_t)b2 << 16) | ((uint64_t)b1 << 8) | (uint64_t)b0;
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
    uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b1 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
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
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
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
    uint8_t b0 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b1 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
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
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) && bytes_set_u8_checked(bytes, idx + 1, b1);
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
    uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b3 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
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
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
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
    uint8_t b0 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b3 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
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
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3);
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
    uint8_t b0 = (uint8_t)((u >> 56) & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 48) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 40) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 32) & 0xFFu);
    uint8_t b4 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b5 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b6 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b7 = (uint8_t)(u & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3) &&
             bytes_set_u8_checked(bytes, idx + 4, b4) &&
             bytes_set_u8_checked(bytes, idx + 5, b5) &&
             bytes_set_u8_checked(bytes, idx + 6, b6) &&
             bytes_set_u8_checked(bytes, idx + 7, b7);
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
    uint8_t b0 = (uint8_t)(u & 0xFFu);
    uint8_t b1 = (uint8_t)((u >> 8) & 0xFFu);
    uint8_t b2 = (uint8_t)((u >> 16) & 0xFFu);
    uint8_t b3 = (uint8_t)((u >> 24) & 0xFFu);
    uint8_t b4 = (uint8_t)((u >> 32) & 0xFFu);
    uint8_t b5 = (uint8_t)((u >> 40) & 0xFFu);
    uint8_t b6 = (uint8_t)((u >> 48) & 0xFFu);
    uint8_t b7 = (uint8_t)((u >> 56) & 0xFFu);
    lock_collections();
    int ok = bytes_set_u8_checked(bytes, idx, b0) &&
             bytes_set_u8_checked(bytes, idx + 1, b1) &&
             bytes_set_u8_checked(bytes, idx + 2, b2) &&
             bytes_set_u8_checked(bytes, idx + 3, b3) &&
             bytes_set_u8_checked(bytes, idx + 4, b4) &&
             bytes_set_u8_checked(bytes, idx + 5, b5) &&
             bytes_set_u8_checked(bytes, idx + 6, b6) &&
             bytes_set_u8_checked(bytes, idx + 7, b7);
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

OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value) {
    if (container.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
            oren_panic("index must be integer");
            return value; // Should not be reached
        }
        int idx = (int)index.as.int_val;
        if (idx < 0) {
            char buf[128];
            snprintf(buf, sizeof(buf), "index out of bounds (idx=%d, count=%d)", idx, container.as.list_val->count);
            oren_panic(buf);
            return value; // Should not be reached
        }
        if (idx >= container.as.list_val->capacity) {
            int newCap = container.as.list_val->capacity == 0 ? (idx + 1) : container.as.list_val->capacity;
            while (newCap <= idx) { newCap *= 2; }
            container.as.list_val->items = realloc(container.as.list_val->items, sizeof(OrenValue) * newCap);
            container.as.list_val->capacity = newCap;
        }
        if (idx >= container.as.list_val->count) {
            // zero-fill new slots
            for (int i = container.as.list_val->count; i <= idx; i++) {
                container.as.list_val->items[i] = OREN_NIL;
            }
            container.as.list_val->count = idx + 1;
        }
        lock_collections();
        container.as.list_val->items[idx] = value;
        unlock_collections();
        return value;
    }

    if (container.type == OREN_TYPE_MAP) {
        OrenMap* map = container.as.map_val;
        lock_collections();
        if (!(index.type == OREN_TYPE_NIL || index.type == OREN_TYPE_BOOL || index.type == OREN_TYPE_INT || index.type == OREN_TYPE_STRING)) {
            unlock_collections();
            oren_panic("map key type not supported (need nil/bool/int/string)");
            return value; // Should not be reached
        }

        int rk = (index.type == OREN_TYPE_NIL) ? 0 : (index.type == OREN_TYPE_BOOL) ? 1 : (index.type == OREN_TYPE_INT) ? 2 : 3;

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int rmk = (mk.type == OREN_TYPE_NIL) ? 0 : (mk.type == OREN_TYPE_BOOL) ? 1 : (mk.type == OREN_TYPE_INT) ? 2 : 3;

            int cmp = 0;
            if (rmk != rk) {
                cmp = (rmk < rk) ? -1 : 1;
            } else if (index.type == OREN_TYPE_NIL) {
                cmp = 0;
            } else if (index.type == OREN_TYPE_BOOL) {
                cmp = (mk.as.bool_val < index.as.bool_val) ? -1 : (mk.as.bool_val > index.as.bool_val) ? 1 : 0;
            } else if (index.type == OREN_TYPE_INT) {
                cmp = (mk.as.int_val < index.as.int_val) ? -1 : (mk.as.int_val > index.as.int_val) ? 1 : 0;
            } else { // STRING
                cmp = strcmp(mk.as.string_val, index.as.string_val);
                if (cmp < 0) cmp = -1;
                else if (cmp > 0) cmp = 1;
            }

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_eq(map->keys[idx], index).as.bool_val) {
            map->values[idx] = value;
            unlock_collections();
            return value;
        }

        if (map->count >= map->capacity) {
            int newCap = map->capacity == 0 ? 8 : map->capacity * 2;
            map->keys = realloc(map->keys, sizeof(OrenValue) * newCap);
            map->values = realloc(map->values, sizeof(OrenValue) * newCap);
            map->capacity = newCap;
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = index;
        map->values[idx] = value;
        map->count += 1;
        unlock_collections();
        return value;
    }

#ifdef OREN_ENABLE_PYTHON
    if (container.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_index = oren_to_py(index);
        PyObject* py_value = oren_to_py(value);
        if (PyObject_SetItem(container.as.py_obj, py_index, py_value) != 0) {
            PyErr_Print();
            oren_panic("python setitem failed");
            return value; // Should not be reached
        }
        Py_DECREF(py_index);
        Py_DECREF(py_value);
        return value;
    }
#else
    if (container.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        (void)value;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return value; // Should not be reached
    }
#endif

    oren_panic("index set on non-list/map");
    return value; // Should not be reached
}

OrenValue oren_new_map(int count, ...) {
    va_list args;
    va_start(args, count);

    lock_collections();
    OrenMap* map = malloc(sizeof(OrenMap));
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = 0;
    map->capacity = count + 8;
    map->keys = malloc(sizeof(OrenValue) * map->capacity);
    map->values = malloc(sizeof(OrenValue) * map->capacity);

    // Deterministic ordered maps (rolling): keep keys in sorted order.
    // Supported key types: NIL, BOOL, INT, STRING.
    // Ordering: NIL < BOOL < INT < STRING.
    // Duplicate keys: last assignment wins.
    for (int i = 0; i < count; i++) {
        OrenValue key = va_arg(args, OrenValue);
        OrenValue value = va_arg(args, OrenValue);

        if (!(key.type == OREN_TYPE_NIL || key.type == OREN_TYPE_BOOL || key.type == OREN_TYPE_INT || key.type == OREN_TYPE_STRING)) {
            oren_panic("map key type not supported (need nil/bool/int/string)");
            break;
        }

        int rk = (key.type == OREN_TYPE_NIL) ? 0 : (key.type == OREN_TYPE_BOOL) ? 1 : (key.type == OREN_TYPE_INT) ? 2 : 3;

        int lo = 0;
        int hi = map->count;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            OrenValue mk = map->keys[mid];
            int rmk = (mk.type == OREN_TYPE_NIL) ? 0 : (mk.type == OREN_TYPE_BOOL) ? 1 : (mk.type == OREN_TYPE_INT) ? 2 : 3;

            int cmp = 0;
            if (rmk != rk) {
                cmp = (rmk < rk) ? -1 : 1;
            } else if (key.type == OREN_TYPE_NIL) {
                cmp = 0;
            } else if (key.type == OREN_TYPE_BOOL) {
                cmp = (mk.as.bool_val < key.as.bool_val) ? -1 : (mk.as.bool_val > key.as.bool_val) ? 1 : 0;
            } else if (key.type == OREN_TYPE_INT) {
                cmp = (mk.as.int_val < key.as.int_val) ? -1 : (mk.as.int_val > key.as.int_val) ? 1 : 0;
            } else { // STRING
                cmp = strcmp(mk.as.string_val, key.as.string_val);
                if (cmp < 0) cmp = -1;
                else if (cmp > 0) cmp = 1;
            }

            if (cmp < 0) lo = mid + 1;
            else hi = mid;
        }
        int idx = lo;

        if (idx < map->count && oren_eq(map->keys[idx], key).as.bool_val) {
            map->values[idx] = value;
            continue;
        }

        if (map->count >= map->capacity) {
            int newCap = map->capacity == 0 ? 8 : map->capacity * 2;
            map->keys = realloc(map->keys, sizeof(OrenValue) * newCap);
            map->values = realloc(map->values, sizeof(OrenValue) * newCap);
            map->capacity = newCap;
        }
        for (int j = map->count; j > idx; j--) {
            map->keys[j] = map->keys[j - 1];
            map->values[j] = map->values[j - 1];
        }
        map->keys[idx] = key;
        map->values[idx] = value;
        map->count += 1;
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_MAP;
    v.as.map_val = map;
    unlock_collections();
    return v;
}

OrenValue oren_map_get(OrenValue map, OrenValue key) {
    if (map.type != OREN_TYPE_MAP) return OREN_NIL;
    lock_collections();
    for (int i = 0; i < map.as.map_val->count; i++) {
        OrenValue k = map.as.map_val->keys[i];
        if (oren_eq(k, key).as.bool_val) {
            OrenValue v = map.as.map_val->values[i];
            unlock_collections();
            return v;
        }
    }
    unlock_collections();
    return OREN_NIL;
}

OrenValue oren_map_len(OrenValue map) {
    if (map.type != OREN_TYPE_MAP) {
        oren_panic("len on non-map");
        return OREN_NIL; // Should not be reached
    }
    lock_collections();
    int c = map.as.map_val->count;
    unlock_collections();
    return oren_int(c);
}

OrenValue oren_call_obj_argv(OrenValue fn, int argc, OrenValue* argv) {
    if (fn.type == OREN_TYPE_FUNC) {
        return fn.as.func_val.fn(fn.as.func_val.env, argc, argv);
    }

#ifdef OREN_ENABLE_PYTHON
    if (fn.type == OREN_TYPE_PY_OBJ) {
        if (!PyCallable_Check(fn.as.py_obj)) {
            oren_panic("Python object is not callable");
            return OREN_NIL; // Should not be reached
        }
        PyObject* py_args = PyTuple_New(argc);
        for (int i = 0; i < argc; i++) {
            PyTuple_SetItem(py_args, i, oren_to_py(argv[i])); // Steals ref
        }
        PyObject* result = PyObject_CallObject(fn.as.py_obj, py_args);
        Py_DECREF(py_args);
        if (!result) {
            PyErr_Print();
            oren_panic("Python call failed");
            return OREN_NIL; // Should not be reached
        }
        return oren_py_to_oren(result);
    }
#else
    if (fn.type == OREN_TYPE_PY_OBJ) {
        (void)argc;
        (void)argv;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    oren_panic("Calling non-callable object");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_call_obj_list(OrenValue fn, OrenValue args_list) {
    if (args_list.type != OREN_TYPE_LIST) {
        oren_panic("call_obj_list expects args_list to be a list");
        return OREN_NIL; // Should not be reached
    }
    OrenList* l = args_list.as.list_val;
    int argc = 0;
    OrenValue* argv = NULL;
    if (l) {
        argc = l->count;
        argv = l->items;
    }
    return oren_call_obj_argv(fn, argc, argv);
}

OrenValue oren_call_obj(OrenValue fn, int count, ...) {
    if (fn.type == OREN_TYPE_FUNC) {
        OrenValue* argv = NULL;
        if (count > 0) {
            argv = (OrenValue*)calloc((size_t)count, sizeof(OrenValue));
            if (!argv) {
                oren_panic("oren_call_obj: out of memory");
            }
        }
        va_list args;
        va_start(args, count);
        for (int i = 0; i < count; i++) {
            argv[i] = va_arg(args, OrenValue);
        }
        va_end(args);
        OrenValue out = fn.as.func_val.fn(fn.as.func_val.env, count, argv);
        if (argv) free(argv);
        return out;
    }

    va_list args;
    va_start(args, count);

#ifdef OREN_ENABLE_PYTHON
    if (fn.type == OREN_TYPE_PY_OBJ) {
        if (!PyCallable_Check(fn.as.py_obj)) {
            oren_panic("Python object is not callable");
            return OREN_NIL; // Should not be reached
        }
        PyObject* py_args = PyTuple_New(count);
        for (int i = 0; i < count; i++) {
            OrenValue arg = va_arg(args, OrenValue);
            PyTuple_SetItem(py_args, i, oren_to_py(arg)); // Steals ref
        }
        PyObject* result = PyObject_CallObject(fn.as.py_obj, py_args);
        Py_DECREF(py_args);
        if (!result) {
            PyErr_Print();
            oren_panic("Python call failed");
            return OREN_NIL; // Should not be reached
        }
        va_end(args);
        return oren_py_to_oren(result);
    }
#else
    if (fn.type == OREN_TYPE_PY_OBJ) {
        (void)count;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif

    oren_panic("Calling non-callable object (only Python callables supported via generic call so far)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_neq(OrenValue a, OrenValue b) {
    OrenValue eq = oren_eq(a, b);
    return eq.as.bool_val ? OREN_FALSE : OREN_TRUE;
}

OrenValue oren_bool_norm(OrenValue v) {
    // bool cast semantics (rolling):
    // - nil  -> false
    // - bool -> identity
    // - int  -> (v != 0)
    // - float-> (v != 0.0)
    // - other heap/object values -> true
    //
    // IMPORTANT: do not use `oren_is_truthy` for ints here; v0 truthiness treats all ints as truthy.
    switch (v.type) {
        case OREN_TYPE_NIL: return OREN_FALSE;
        case OREN_TYPE_BOOL: return v;
        case OREN_TYPE_INT: return oren_bool(v.as.int_val != 0);
        case OREN_TYPE_FLOAT: return oren_bool(v.as.float_val != 0.0);
        default: return OREN_TRUE;
    }
}

OrenValue oren_trunc_int(OrenValue v) {
    // Numeric truncation semantics (rolling, cross-backend deterministic):
    // - int   -> identity
    // - float -> truncate toward zero (discard fractional part)
    //
    // Special float values (deterministic, no UB):
    // - NaN   -> 0
    // - +inf / overflow -> INT64_MAX
    // - -inf / overflow -> INT64_MIN
    //
    // Rationale:
    // - Native backend uses an ARM64 lowering equivalent to FCVTZS behavior on IEEE-754 inputs.
    // - Returning a structured Err here would leak into arithmetic ops and create non-uniform
    //   behavior unless the whole numeric tower becomes Result-aware.
    if (v.type == OREN_TYPE_INT) { return v; }
    if (v.type == OREN_TYPE_FLOAT) {
        double d = v.as.float_val;
        // NaN check without <math.h>.
        if (d != d) { return oren_int(0); }

        // Avoid undefined behavior in (int64_t)d by clamping.
        //
        // Valid int64 range is [-2^63, 2^63-1]. Use lim=2^63 as the boundary.
        const double lim = 9223372036854775808.0; // 2^63
        if (d >= lim) { return oren_int(LLONG_MAX); }
        if (d <= -lim) { return oren_int(LLONG_MIN); }

        int64_t i = (int64_t)d; // truncate toward zero for finite values in range.
        return oren_int((long long)i);
    }
    // Keep behavior deterministic: non-numeric -> 0.
    return oren_int(0);
}

OrenValue oren_ptr_alloc(OrenValue bytes) {
    if (bytes.type != OREN_TYPE_INT) {
        oren_panic("ptr_alloc expects int");
        return OREN_NIL;
    }
    int64_t n = bytes.as.int_val;
    if (n < 0) {
        oren_panic("ptr_alloc: negative size");
        return OREN_NIL;
    }
    uint64_t p = oren_alloc_struct((size_t)n);
    return oren_int((int64_t)p);
}

OrenValue oren_ptr_free(OrenValue ptr) {
    if (ptr.type != OREN_TYPE_INT) {
        oren_panic("ptr_free expects int");
        return OREN_NIL;
    }
    uint64_t p = (uint64_t)ptr.as.int_val;
    oren_free_struct(p);
    return OREN_NIL;
}

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

OrenValue oren_lt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val < b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val < (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) < 0);
    }
    oren_panic("Type mismatch in lt");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_gt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val > b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val > (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) > 0);
    }
    oren_panic("Type mismatch in gt");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_lte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val <= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val <= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) <= 0);
    }
    oren_panic("Type mismatch in lte");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_gte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val >= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val >= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) >= 0);
    }
    oren_panic("Type mismatch in gte");
    return OREN_NIL;
}

static void print_value_no_newline(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_INT: printf("%lld", v.as.int_val); break;
        case OREN_TYPE_FLOAT: printf("%f", v.as.float_val); break;
        case OREN_TYPE_BOOL: printf("%s", v.as.bool_val ? "true" : "false"); break;
        case OREN_TYPE_STRING: printf("%s", v.as.string_val); break;
        case OREN_TYPE_NIL: printf("nil"); break;
        case OREN_TYPE_FUNC: printf("<func %p>", (void*)v.as.func_val.fn); break;
        case OREN_TYPE_U8_BUF:
            printf("<u8_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_I32_BUF:
            printf("<i32_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_I64_BUF:
            printf("<i64_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_F32_BUF:
            printf("<f32_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_F64_BUF:
            printf("<f64_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            PyObject* str = PyObject_Str(v.as.py_obj);
            printf("%s", PyUnicode_AsUTF8(str));
            Py_DECREF(str);
            break;
#else
            oren_panic("Python support is disabled");
#endif
        }
        case OREN_TYPE_LIST: {
            printf("[");
            for (int i = 0; i < v.as.list_val->count; i++) {
                if (i > 0) printf(", ");
                print_value_no_newline(v.as.list_val->items[i]);
            }
            printf("]");
            break;
        }
        case OREN_TYPE_MAP: {
             printf("{");
             for (int i = 0; i < v.as.map_val->count; i++) {
                 if (i > 0) printf(", ");
                 print_value_no_newline(v.as.map_val->keys[i]);
                 printf(": ");
                 print_value_no_newline(v.as.map_val->values[i]);
             }
             printf("}");
             break;
        }
    }
}

void oren_print(OrenValue v) {
    print_value_no_newline(v);
    printf("\n");
}

void oren_print_multi(int count, ...) {
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) {
        OrenValue v = va_arg(args, OrenValue);
        print_value_no_newline(v);
        if (i < count - 1) printf(" ");
    }
    printf("\n");
    va_end(args);
}

void oren_print_fmt(OrenValue fmt_val, int count, ...) {
    if (fmt_val.type != OREN_TYPE_STRING) {
        oren_panic("print format must be string");
        return;
    }
    const char* fmt = fmt_val.as.string_val;
    va_list args;
    va_start(args, count);
    
    int arg_idx = 0;
    int len = strlen(fmt);
    int i = 0;
    while (i < len) {
        if (fmt[i] == '{' && i + 1 < len && fmt[i+1] == '}') {
            if (arg_idx < count) {
                OrenValue v = va_arg(args, OrenValue);
                print_value_no_newline(v);
                arg_idx++;
            } else {
                printf("{}");
            }
            i += 2;
        } else {
            putchar(fmt[i]);
            i++;
        }
    }
    printf("\n");
    va_end(args);
}

void oren_print_list(OrenValue args_list) {
    if (args_list.type == OREN_TYPE_NIL) {
        printf("\n");
        return;
    }
    if (args_list.type != OREN_TYPE_LIST) {
        oren_panic("print_list expects list");
        return;
    }
    OrenList* l = args_list.as.list_val;
    if (!l || l->count <= 0) {
        printf("\n");
        return;
    }
    for (int i = 0; i < l->count; i++) {
        print_value_no_newline(l->items[i]);
        if (i < l->count - 1) printf(" ");
    }
    printf("\n");
}

void oren_print_fmt_list(OrenValue fmt_val, OrenValue args_list) {
    if (fmt_val.type != OREN_TYPE_STRING) {
        oren_panic("print format must be string");
        return;
    }
    if (args_list.type != OREN_TYPE_LIST && args_list.type != OREN_TYPE_NIL) {
        oren_panic("print_fmt_list expects args list");
        return;
    }
    OrenList* l = (args_list.type == OREN_TYPE_LIST) ? args_list.as.list_val : NULL;
    int count = l ? l->count : 0;
    const char* fmt = fmt_val.as.string_val;

    int arg_idx = 0;
    int len = (int)strlen(fmt);
    int i = 0;
    while (i < len) {
        if (fmt[i] == '{' && i + 1 < len && fmt[i + 1] == '}') {
            if (arg_idx < count) {
                print_value_no_newline(l->items[arg_idx]);
                arg_idx++;
            } else {
                printf("{}");
            }
            i += 2;
        } else {
            putchar(fmt[i]);
            i++;
        }
    }
    printf("\n");
}

static void print_build_args(OrenValue* out_list, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = oren_new_list(0);
    if (fixed_args.type != OREN_TYPE_NIL) {
        if (fixed_args.type != OREN_TYPE_LIST) {
            oren_panic("spread fixed args must be list");
            *out_list = OREN_NIL;
            return;
        }
        OrenList* f = fixed_args.as.list_val;
        for (int i = 0; i < f->count; i++) {
            oren_list_push(args, f->items[i]);
        }
    }
    if (spread_list.type != OREN_TYPE_NIL) {
        if (spread_list.type != OREN_TYPE_LIST) {
            oren_panic("spread list must be list");
            *out_list = OREN_NIL;
            return;
        }
        OrenList* s = spread_list.as.list_val;
        for (int i = 0; i < s->count; i++) {
            oren_list_push(args, s->items[i]);
        }
    }
    *out_list = args;
}

void oren_print_spread(OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return;
    oren_print_list(args);
}

void oren_print_fmt_spread(OrenValue fmt, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return;
    oren_print_fmt_list(fmt, args);
}

OrenValue oren_call_obj_spread(OrenValue fn, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return OREN_NIL;
    return oren_call_obj_list(fn, args);
}

// Iterator hook for `for x in <container>` sugar.
// Contract:
//   oren_iter_next(container, idx:int, out_pair:list|nil) -> [ok:int, value]
// Where ok is 1 when a value exists, 0 when iteration is complete.
//
// v0 iteration rules:
// - list: yields elements (idx 0..len-1)
// - map: yields keys in deterministic key order (idx 0..count-1)
// - string: yields byte codepoints (unsigned 0..255), stops at NUL terminator
static OrenValue iter_fill_pair(OrenValue out_pair, OrenValue okv, OrenValue val) {
    if (out_pair.type == OREN_TYPE_LIST && out_pair.as.list_val) {
        OrenList* l = out_pair.as.list_val;
        if (l->capacity >= 2 && l->items) {
            if (l->count < 2) l->count = 2;
            l->items[0] = okv;
            l->items[1] = val;
            return out_pair;
        }
    }
    return oren_new_list(2, okv, val);
}

OrenValue oren_iter_next(OrenValue container, OrenValue idx, OrenValue out_pair) {
    if (idx.type != OREN_TYPE_INT) {
        oren_panic("iter_next expects (container, int idx, list|nil out_pair)");
        return OREN_NIL; // Should not be reached
    }

    long long i = idx.as.int_val;
    if (i < 0) {
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    // Typed buffer "view" lists (rolling, HPC):
    // - slice view:   [buf, off, len]
    // - strided view: [buf, off, len, stride]
    //
    // These are represented as normal lists for portability, but `for x in view`
    // should iterate the underlying buffer elements, not the metadata fields.
    if (container.type == OREN_TYPE_LIST && container.as.list_val) {
        OrenList* l = container.as.list_val;
        if (l->count == 3 || l->count == 4) {
            OrenValue b = l->items[0];
            if (b.type == OREN_TYPE_U8_BUF || b.type == OREN_TYPE_I32_BUF || b.type == OREN_TYPE_I64_BUF ||
                b.type == OREN_TYPE_F32_BUF || b.type == OREN_TYPE_F64_BUF) {
                OrenValue offv = l->items[1];
                OrenValue lenv = l->items[2];
                OrenValue stridev = (l->count == 4) ? l->items[3] : oren_int(1);
                if (offv.type != OREN_TYPE_INT || lenv.type != OREN_TYPE_INT || stridev.type != OREN_TYPE_INT) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                long long off = offv.as.int_val;
                long long n = lenv.as.int_val;
                long long stride = stridev.as.int_val;
                if (off < 0 || n < 0 || stride <= 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                if (i < n) {
                    long long elem_idx = off + i * stride;
                    OrenValue v = OREN_NIL;
                    OrenValue idxv = oren_int(elem_idx);
                    if (b.type == OREN_TYPE_U8_BUF) v = oren_buf_load_u8(b, idxv);
                    else if (b.type == OREN_TYPE_I32_BUF) v = oren_buf_load_i32(b, idxv);
                    else if (b.type == OREN_TYPE_I64_BUF) v = oren_buf_load_i64(b, idxv);
                    else if (b.type == OREN_TYPE_F32_BUF) v = oren_buf_load_f32(b, idxv);
                    else v = oren_buf_load_f64(b, idxv);
                    if (oren_is_err(v).as.bool_val) {
                        oren_panic("iter_next: buffer view load failed");
                        return OREN_NIL;
                    }
                    return iter_fill_pair(out_pair, oren_int(1), v);
                }
                return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
            }
        }
    }

    if (container.type == OREN_TYPE_LIST) {
        OrenList* l = container.as.list_val;
        if (i < l->count) {
            return iter_fill_pair(out_pair, oren_int(1), l->items[(int)i]);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_MAP) {
        // "Iterable map" protocol (rolling): allow maps to represent stream-like iterables.
        //
        // This is used by std/iter.oren's `range(...)` helpers:
        //   {"__iter":"range","start":0,"end":N,"step":1}
        //
        // Note: normal maps still iterate keys deterministically.
        OrenValue it = oren_map_get(container, oren_string_const("__iter"));
        if (it.type == OREN_TYPE_STRING && it.as.string_val && strcmp(it.as.string_val, "range") == 0) {
            OrenValue startv = oren_map_get(container, oren_string_const("start"));
            OrenValue endv = oren_map_get(container, oren_string_const("end"));
            OrenValue stepv = oren_map_get(container, oren_string_const("step"));
            // If the iterable map is malformed, treat it as an empty sequence (deterministic,
            // avoids crashing in production).
            if (startv.type == OREN_TYPE_INT && endv.type == OREN_TYPE_INT && stepv.type == OREN_TYPE_INT) {
                long long start = startv.as.int_val;
                long long end = endv.as.int_val;
                long long step = stepv.as.int_val;
                if (step == 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                long long v = start + (long long)i * step;
                if ((step > 0 && v < end) || (step < 0 && v > end)) {
                    return iter_fill_pair(out_pair, oren_int(1), oren_int(v));
                }
            }
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        if (it.type == OREN_TYPE_STRING && it.as.string_val && strcmp(it.as.string_val, "list_slice") == 0) {
            // Iterable map protocol (rolling): list slice view.
            //
            // Produced by std:list.slice_view(xs, off, n):
            //   {"__iter":"list_slice","base":xs,"off":off,"len":n}
            //
            // If malformed, treat as empty iteration (deterministic, avoids crashes).
            OrenValue basev = oren_map_get(container, oren_string_const("base"));
            OrenValue offv = oren_map_get(container, oren_string_const("off"));
            OrenValue lenv = oren_map_get(container, oren_string_const("len"));
            if (basev.type == OREN_TYPE_LIST && basev.as.list_val && offv.type == OREN_TYPE_INT && lenv.type == OREN_TYPE_INT) {
                long long off = offv.as.int_val;
                long long n = lenv.as.int_val;
                if (off < 0 || n < 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                OrenList* l = basev.as.list_val;
                if (off <= l->count) {
                    long long max_n = (long long)l->count - off;
                    if (n <= max_n && i < n) {
                        long long elem_idx = off + i;
                        if (elem_idx >= 0 && elem_idx < (long long)l->count) {
                            return iter_fill_pair(out_pair, oren_int(1), l->items[(int)elem_idx]);
                        }
                    }
                }
            }
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        OrenMap* m = container.as.map_val;
        if (i < m->count) {
            return iter_fill_pair(out_pair, oren_int(1), m->keys[(int)i]);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_STRING) {
        const unsigned char* s = (const unsigned char*)container.as.string_val;
        if (!s) {
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        unsigned char ch = s[i];
        if (ch == 0) {
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        return iter_fill_pair(out_pair, oren_int(1), oren_int((long long)ch));
    }

    // Typed numeric buffers (C backend).
    if (container.type == OREN_TYPE_U8_BUF || container.type == OREN_TYPE_I32_BUF || container.type == OREN_TYPE_I64_BUF ||
        container.type == OREN_TYPE_F32_BUF || container.type == OREN_TYPE_F64_BUF) {
        OrenBuf* b = container.as.buf_val;
        if (!b) { return iter_fill_pair(out_pair, oren_int(0), OREN_NIL); }
        if (i < (long long)b->len) {
            OrenValue v = OREN_NIL;
            OrenValue idxv = oren_int(i);
            if (container.type == OREN_TYPE_U8_BUF) v = oren_buf_load_u8(container, idxv);
            else if (container.type == OREN_TYPE_I32_BUF) v = oren_buf_load_i32(container, idxv);
            else if (container.type == OREN_TYPE_I64_BUF) v = oren_buf_load_i64(container, idxv);
            else if (container.type == OREN_TYPE_F32_BUF) v = oren_buf_load_f32(container, idxv);
            else v = oren_buf_load_f64(container, idxv);
            // `oren_buf_load_*` can return an Err map only if the buffer is corrupted
            // or index checks diverge; treat this as a hard failure (bug).
            if (oren_is_err(v).as.bool_val) {
                oren_panic("iter_next: buffer load failed");
                return OREN_NIL;
            }
            return iter_fill_pair(out_pair, oren_int(1), v);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    oren_panic("iter_next: unsupported container type (need list/map/string/buf)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_string_len(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("string_len expects string");
        return OREN_NIL; // Should not be reached
    }
    return oren_int((long long)strlen(s.as.string_val));
}

OrenValue oren_string_char_at(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("char_at expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    size_t len = strlen(s.as.string_val);
    if (idx < 0 || (size_t)idx >= len) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char_at index out of range (idx=%lld, len=%zu)", idx, len);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    char buf[2];
    buf[0] = s.as.string_val[idx];
    buf[1] = '\0';
    return oren_string(buf);
}

OrenValue oren_char(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        oren_panic("char expects int");
        return OREN_NIL; // Should not be reached
    }
    long long v = code.as.int_val;
    if (v < 0 || v > 255) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char code out of range (code=%lld)", v);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    char buf[2];
    buf[0] = (char)v;
    buf[1] = '\0';
    return oren_string(buf);
}

static OrenValue oren_string_const(const char* s) {
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = (char*)s;
    return v;
}

OrenValue oren_err(OrenValue code, OrenValue msg) {
    if (code.type != OREN_TYPE_INT || msg.type != OREN_TYPE_STRING) {
        oren_panic("oren_err expects (int, string)");
        return OREN_NIL; // Should not be reached
    }
    return oren_new_map(
        3,
        oren_string_const("__err"), OREN_TRUE,
        oren_string_const("code"), code,
        oren_string_const("msg"), msg
    );
}

OrenValue oren_is_err(OrenValue v) {
    if (v.type != OREN_TYPE_MAP) return OREN_FALSE;
    OrenValue marker = oren_map_get(v, oren_string_const("__err"));
    return oren_bool(oren_is_truthy(marker));
}

OrenValue oren_err_code(OrenValue v) {
    if (!oren_is_err(v).as.bool_val) return oren_int(-1);
    OrenValue code = oren_map_get(v, oren_string_const("code"));
    if (code.type != OREN_TYPE_INT) return oren_int(-1);
    return code;
}

OrenValue oren_err_msg(OrenValue v) {
    if (!oren_is_err(v).as.bool_val) return OREN_NIL;
    OrenValue msg = oren_map_get(v, oren_string_const("msg"));
    if (msg.type != OREN_TYPE_STRING) return OREN_NIL;
    return msg;
}

static OrenValue oren_err_from_errno(const char* action, const char* path, int err) {
    int code = OREN_ERR_IO;
    if (err == EACCES || err == EPERM) code = OREN_ERR_PERM;
    else if (err == ENOENT) code = OREN_ERR_NOT_FOUND;

    char buf[512];
    if (path) snprintf(buf, sizeof(buf), "%s: %s (errno=%d)", action, path, err);
    else snprintf(buf, sizeof(buf), "%s (errno=%d)", action, err);
    return oren_err(oren_int(code), oren_string(buf));
}
