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
    return oren_string_from_single_byte((unsigned char)v);
}

OrenValue oren_string_const(const char* s) {
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
    return oren_new_map_from_pairs(
        3,
        (OrenValue[]){
            oren_string_const("__err"), OREN_TRUE,
            oren_string_const("code"), code,
            oren_string_const("msg"), msg,
        }
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
