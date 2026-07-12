// Forward decls for helpers defined later in this include.
static int avm_map_get_key(AvmValue vmap, const char* key, AvmValue* out);

static int64_t avm_oren_type_tag(AvmValue v) {
    switch (v.type) {
        case AVM_VAL_NIL: return 0;
        case AVM_VAL_INT: return 1;
        case AVM_VAL_FLOAT: return 2;
        case AVM_VAL_BOOL: return 3;
        case AVM_VAL_STRING: return 4;
        case AVM_VAL_LIST: return 6;
        case AVM_VAL_LIST_INT: return 6;
        case AVM_VAL_MAP: return 7;
        case AVM_VAL_FUNC: return 8;
        case AVM_VAL_BYTES: return 9;
        case AVM_VAL_I32_BUF: return 10;
        case AVM_VAL_I64_BUF: return 11;
        case AVM_VAL_F32_BUF: return 12;
        case AVM_VAL_F64_BUF: return 13;
        case AVM_VAL_GENERATOR: return 14;
        case AVM_VAL_GENERATOR_CONTEXT: return 15;
        default: return 0;
    }
}

static const char* avm_oren_type_name_from_tag(int64_t tag) {
    switch (tag) {
        case 0: return "nil";
        case 1: return "int";
        case 2: return "float";
        case 3: return "bool";
        case 4: return "string";
        case 5: return "py_obj";
        case 6: return "list";
        case 7: return "map";
        case 8: return "func";
        case 9: return "u8_buf";
        case 10: return "i32_buf";
        case 11: return "i64_buf";
        case 12: return "f32_buf";
        case 13: return "f64_buf";
        case 14: return "generator";
        case 15: return "generator_context";
        default: return "unknown";
    }
}

#include "avm_native_ptr_helpers.inc"

#include "avm_generator_native_helpers.inc"

static int avm_i32_pack_extract(AvmValue v, int assume_int, int32_t* out) {
    if (!assume_int && v.type != AVM_VAL_INT) return 1;
    int64_t iv = v.as.i;
    if (iv < (int64_t)INT32_MIN || iv > (int64_t)INT32_MAX) return 2;
    *out = (int32_t)iv;
    return 0;
}

static int avm_native_byte_span_ok(int64_t len, int64_t idx, int width) {
    if (len < 0 || idx < 0 || width < 1 || width > 8) return 0;
    if ((uint64_t)idx > (uint64_t)len) return 0;
    return (uint64_t)width <= (uint64_t)len - (uint64_t)idx;
}

static int avm_native_byte_range_ok(int64_t len, int64_t start, int64_t n) {
    if (len < 0 || start < 0 || n < 0) return 0;
    if ((uint64_t)start > (uint64_t)len) return 0;
    return (uint64_t)n <= (uint64_t)len - (uint64_t)start;
}

static int avm_native_bytes_len_checked(AvmValue bytes, int64_t* out, const char** err_msg, const char* bytes_msg, const char* list_msg, const char* list_int_msg, const char* expected_msg) {
    if (!out || !err_msg) return 0;
    *out = 0;
    *err_msg = NULL;
    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        if (!b || b->len < 0 || (b->len > 0 && !b->data)) { *err_msg = bytes_msg; return 0; }
        *out = (int64_t)b->len;
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        if (!list || list->count < 0 || (list->count > 0 && !list->items)) { *err_msg = list_msg; return 0; }
        *out = (int64_t)list->count;
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        if (!list || list->count < 0 || (list->count > 0 && !list->items)) { *err_msg = list_int_msg; return 0; }
        *out = (int64_t)list->count;
        return 1;
    }
    *err_msg = expected_msg;
    return 0;
}

static int avm_native_bytes_copy_span(AvmValue bytes, int64_t start, int64_t n, uint8_t* dst, const char** err_msg, const char* bounds_msg, const char* expected_msg, const char* list_range_msg, const char* list_int_range_msg) {
    if (!err_msg) return 0;
    *err_msg = NULL;
    int64_t total = 0;
    if (!avm_native_bytes_len_checked(bytes, &total, err_msg, bounds_msg, bounds_msg, bounds_msg, expected_msg)) return 0;
    if (!avm_native_byte_range_ok(total, start, n)) { *err_msg = bounds_msg; return 0; }
    if (n == 0) return 1;
    if (!dst) { *err_msg = bounds_msg; return 0; }
    if (bytes.type == AVM_VAL_BYTES) {
        memcpy(dst, bytes.as.b->data + (size_t)start, (size_t)n);
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        for (int64_t i = 0; i < n; i++) {
            AvmValue it = list->items[(int)(start + i)];
            if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) { *err_msg = list_range_msg; return 0; }
            dst[(size_t)i] = (uint8_t)it.as.i;
        }
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        for (int64_t i = 0; i < n; i++) {
            int64_t it = list->items[(int)(start + i)];
            if (it < 0 || it > 255) { *err_msg = list_int_range_msg; return 0; }
            dst[(size_t)i] = (uint8_t)it;
        }
        return 1;
    }
    *err_msg = expected_msg;
    return 0;
}

static int avm_native_bytes_copy_span_to_list_int(AvmValue bytes, int64_t start, int64_t n, AvmListInt* dst, const char** err_msg, const char* bounds_msg, const char* expected_msg, const char* list_range_msg, const char* list_int_range_msg) {
    if (!dst || !err_msg) return 0;
    *err_msg = NULL;
    int64_t total = 0;
    if (!avm_native_bytes_len_checked(bytes, &total, err_msg, bounds_msg, bounds_msg, bounds_msg, expected_msg)) return 0;
    if (!avm_native_byte_range_ok(total, start, n) || (n > 0 && !dst->items)) { *err_msg = bounds_msg; return 0; }
    if (n == 0) return 1;
    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        for (int64_t i = 0; i < n; i++) dst->items[(int)i] = (int64_t)b->data[(int)(start + i)];
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        for (int64_t i = 0; i < n; i++) {
            AvmValue it = list->items[(int)(start + i)];
            if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) { *err_msg = list_range_msg; return 0; }
            dst->items[(int)i] = it.as.i;
        }
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        for (int64_t i = 0; i < n; i++) {
            int64_t it = list->items[(int)(start + i)];
            if (it < 0 || it > 255) { *err_msg = list_int_range_msg; return 0; }
            dst->items[(int)i] = it;
        }
        return 1;
    }
    *err_msg = expected_msg;
    return 0;
}

static AvmValue avm_native_bytes_to_hex_value(AvmVM* vm, AvmValue bytes) {
    int64_t byte_len = 0;
    const char* err_msg = NULL;
    if (!avm_native_bytes_len_checked(bytes, &byte_len, &err_msg,
            "bytes_to_hex: invalid bytes",
            "bytes_to_hex: invalid list",
            "bytes_to_hex: invalid list_int",
            "oren_bytes_to_hex expects (bytes|list<int>|list_int)")) {
        return avm_err(AVM_ERR_INVALID_ARG, err_msg ? err_msg : "oren_bytes_to_hex expects (bytes|list<int>|list_int)");
    }
    if (byte_len > (INT64_MAX / 2)) {
        return avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: input too large");
    }

    static const char* hexd = "0123456789abcdef";
    size_t out_len = (size_t)byte_len * 2u;
    char* out = (char*)avm_heap_malloc_k(out_len + 1, AVM_ALLOC_KIND_STRING);
    if (!out) {
        AvmValue e = avm_alloc_fail_value();
        avm_abort(vm, e);
        return e;
    }

    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        for (int64_t i = 0; i < byte_len; i++) {
            uint8_t v = b->data[(int)i];
            out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
            out[(size_t)i * 2 + 1] = hexd[v & 0xF];
        }
    } else if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        for (int64_t i = 0; i < byte_len; i++) {
            AvmValue it = list->items[(int)i];
            if (it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255) {
                avm_heap_free(out);
                return avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: expected list<int 0..255>");
            }
            uint8_t v = (uint8_t)it.as.i;
            out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
            out[(size_t)i * 2 + 1] = hexd[v & 0xF];
        }
    } else if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        for (int64_t i = 0; i < byte_len; i++) {
            int64_t it = list->items[(int)i];
            if (it < 0 || it > 255) {
                avm_heap_free(out);
                return avm_err(AVM_ERR_INVALID_ARG, "bytes_to_hex: expected list_int bytes 0..255");
            }
            uint8_t v = (uint8_t)it;
            out[(size_t)i * 2] = hexd[(v >> 4) & 0xF];
            out[(size_t)i * 2 + 1] = hexd[v & 0xF];
        }
    }

    out[out_len] = 0;
    AvmValue res;
    res.type = AVM_VAL_STRING;
    res.as.p = out;
    return res;
}

static int avm_native_bytes_read_u64_span(AvmValue bytes, int64_t idx, int width, int little, uint64_t* out, const char** err_msg, const char* bounds_msg, const char* expected_msg, const char* range_msg) {
    if (!out || !err_msg) return 0;
    *out = 0;
    *err_msg = NULL;
    int64_t total = 0;
    if (!avm_native_bytes_len_checked(bytes, &total, err_msg, bounds_msg, bounds_msg, bounds_msg, expected_msg)) return 0;
    if (!avm_native_byte_span_ok(total, idx, width)) {
        *err_msg = bounds_msg;
        return 0;
    }
    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        uint64_t u = 0;
        for (int step = 0; step < width; step++) {
            int rel = little ? (width - 1 - step) : step;
            u = (u << 8) | (uint64_t)b->data[(int)idx + rel];
        }
        *out = u;
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        uint64_t u = 0;
        for (int step = 0; step < width; step++) {
            int rel = little ? (width - 1 - step) : step;
            AvmValue v = list->items[(int)idx + rel];
            if (v.type != AVM_VAL_INT) { *err_msg = expected_msg; return 0; }
            if (v.as.i < 0 || v.as.i > 255) { *err_msg = range_msg; return 0; }
            u = (u << 8) | (uint64_t)v.as.i;
        }
        *out = u;
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        uint64_t u = 0;
        for (int step = 0; step < width; step++) {
            int rel = little ? (width - 1 - step) : step;
            int64_t v = list->items[(int)idx + rel];
            if (v < 0 || v > 255) { *err_msg = range_msg; return 0; }
            u = (u << 8) | (uint64_t)v;
        }
        *out = u;
        return 1;
    }
    *err_msg = expected_msg;
    return 0;
}

static int avm_native_bytes_write_span(AvmValue bytes, int64_t idx, const uint8_t* src, int width, const char** err_msg, const char* bounds_msg, const char* expected_msg) {
    if (!src || !err_msg) return 0;
    *err_msg = NULL;
    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, width) || (width > 0 && !b->data)) {
            *err_msg = bounds_msg;
            return 0;
        }
        for (int i = 0; i < width; i++) b->data[(int)idx + i] = src[i];
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST) {
        AvmList* list = bytes.as.l;
        if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, width) || (width > 0 && !list->items)) {
            *err_msg = bounds_msg;
            return 0;
        }
        for (int i = 0; i < width; i++) list->items[(int)idx + i] = avm_int((int64_t)src[i]);
        return 1;
    }
    if (bytes.type == AVM_VAL_LIST_INT) {
        AvmListInt* list = bytes.as.li;
        if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, width) || (width > 0 && !list->items)) {
            *err_msg = bounds_msg;
            return 0;
        }
        for (int i = 0; i < width; i++) list->items[(int)idx + i] = (int64_t)src[i];
        return 1;
    }
    *err_msg = expected_msg;
    return 0;
}
