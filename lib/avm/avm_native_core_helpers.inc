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

static int avm_native_bytes_read_u64_span(AvmValue bytes, int64_t idx, int width, int little, uint64_t* out, const char** err_msg, const char* bounds_msg, const char* expected_msg, const char* range_msg) {
    if (!out || !err_msg) return 0;
    *out = 0;
    *err_msg = NULL;
    if (bytes.type == AVM_VAL_BYTES) {
        AvmBytes* b = bytes.as.b;
        if (!b || !avm_native_byte_span_ok((int64_t)b->len, idx, width) || (width > 0 && !b->data)) {
            *err_msg = bounds_msg;
            return 0;
        }
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
        if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, width)) {
            *err_msg = bounds_msg;
            return 0;
        }
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
        if (!list || !avm_native_byte_span_ok((int64_t)list->count, idx, width)) {
            *err_msg = bounds_msg;
            return 0;
        }
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
