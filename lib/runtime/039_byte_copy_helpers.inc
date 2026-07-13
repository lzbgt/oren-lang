static int runtime_bytes_range_ok_size(size_t total, size_t start, size_t len) {
    if (start > total) return 0;
    return len <= total - start;
}

static char runtime_bytes_hex_char(uint8_t v) {
    return (char)(v < 10u ? ('0' + v) : ('a' + (v - 10u)));
}

static int runtime_bytes_len_checked(OrenValue bytes, size_t* out, const char** err_msg) {
    if (out) *out = 0;
    if (err_msg) *err_msg = NULL;
    if (bytes.type == OREN_TYPE_LIST) {
        OrenList* list = bytes.as.list_val;
        if (!list || list->count < 0) {
            if (err_msg) *err_msg = "expected list<int 0..255>";
            return 0;
        }
        if (out) *out = (size_t)list->count;
        return 1;
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u) {
            if (err_msg) *err_msg = "expected u8_buf";
            return 0;
        }
        if (out) *out = (size_t)b->len;
        return 1;
    }
    if (err_msg) *err_msg = "expected list<int 0..255> or u8_buf";
    return 0;
}

static int runtime_bytes_copy_span(OrenValue bytes, size_t start, size_t n, uint8_t* dst, const char** err_msg) {
    if (err_msg) *err_msg = NULL;
    if (n > 0u && !dst) {
        if (err_msg) *err_msg = "destination is nil";
        return 0;
    }
    size_t total = 0;
    if (!runtime_bytes_len_checked(bytes, &total, err_msg)) return 0;
    if (!runtime_bytes_range_ok_size(total, start, n)) {
        if (err_msg) *err_msg = "out of bounds";
        return 0;
    }
    if (n == 0u) return 1;
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b->data) {
            if (err_msg) *err_msg = "u8_buf payload is nil";
            return 0;
        }
        memcpy(dst, b->data + start, n);
        return 1;
    }
    OrenList* list = bytes.as.list_val;
    if (!list->items) {
        if (err_msg) *err_msg = "list buffer is nil";
        return 0;
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[start + i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            if (err_msg) *err_msg = "expected list<int 0..255>";
            return 0;
        }
        dst[i] = (uint8_t)it.as.int_val;
    }
    return 1;
}

static int runtime_bytes_write_hex(OrenValue bytes, char* dst, const char** err_msg) {
    if (err_msg) *err_msg = NULL;
    if (!dst) {
        if (err_msg) *err_msg = "destination is nil";
        return 0;
    }
    size_t n = 0;
    if (!runtime_bytes_len_checked(bytes, &n, err_msg)) return 0;
    if (n == 0u) return 1;
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b->data) {
            if (err_msg) *err_msg = "u8_buf payload is nil";
            return 0;
        }
        for (size_t i = 0; i < n; i++) {
            uint8_t bv = b->data[i];
            dst[i * 2u + 0u] = runtime_bytes_hex_char((uint8_t)((bv >> 4) & 0x0Fu));
            dst[i * 2u + 1u] = runtime_bytes_hex_char((uint8_t)(bv & 0x0Fu));
        }
        return 1;
    }
    OrenList* list = bytes.as.list_val;
    if (!list->items) {
        if (err_msg) *err_msg = "list buffer is nil";
        return 0;
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            if (err_msg) *err_msg = "expected list<int 0..255>";
            return 0;
        }
        uint8_t bv = (uint8_t)it.as.int_val;
        dst[i * 2u + 0u] = runtime_bytes_hex_char((uint8_t)((bv >> 4) & 0x0Fu));
        dst[i * 2u + 1u] = runtime_bytes_hex_char((uint8_t)(bv & 0x0Fu));
    }
    return 1;
}

static int runtime_bytes_copy_span_to_list(OrenValue bytes, size_t start, size_t n, OrenList* dst, const char** err_msg) {
    if (err_msg) *err_msg = NULL;
    if (!dst || (n > 0u && !dst->items)) {
        if (err_msg) *err_msg = "destination list is nil";
        return 0;
    }
    size_t total = 0;
    if (!runtime_bytes_len_checked(bytes, &total, err_msg)) return 0;
    if (!runtime_bytes_range_ok_size(total, start, n)) {
        if (err_msg) *err_msg = "out of bounds";
        return 0;
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (n > 0u && !b->data) {
            if (err_msg) *err_msg = "u8_buf payload is nil";
            return 0;
        }
        for (size_t i = 0; i < n; i++) {
            dst->items[i] = oren_int((int64_t)b->data[start + i]);
        }
        return 1;
    }
    OrenList* list = bytes.as.list_val;
    if (n > 0u && !list->items) {
        if (err_msg) *err_msg = "list buffer is nil";
        return 0;
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[start + i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            if (err_msg) *err_msg = "expected list<int 0..255>";
            return 0;
        }
        dst->items[i] = oren_int(it.as.int_val);
    }
    return 1;
}
