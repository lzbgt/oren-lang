OrenValue oren_read_file(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        oren_panic("read_file expects string path");
        return OREN_NIL; // Should not be reached
    }
    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        return oren_err_from_errno("cannot open file", path.as.string_val, errno);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0) {
        fclose(f);
        return oren_err_from_errno("cannot stat file", path.as.string_val, errno);
    }
    char *buf = malloc(size + 1);
    if (!buf) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("out of memory"));
    }
    size_t n = fread(buf, 1, (size_t)size, f);
    buf[size] = '\0';
    fclose(f);
    if (n != (size_t)size) {
        return oren_err_from_errno("cannot read file", path.as.string_val, errno);
    }
    return oren_string(buf);
}

OrenValue oren_file_stat_size_mtime_ns(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("file_stat_size_mtime_ns expects string path"));
    }
    struct stat st;
    if (stat(path.as.string_val, &st) != 0) {
        return oren_err_from_errno("cannot stat file", path.as.string_val, errno);
    }

    long long size = (long long)st.st_size;
    long long sec = 0;
    long long nsec = 0;

#if defined(__APPLE__)
    sec = (long long)st.st_mtimespec.tv_sec;
    nsec = (long long)st.st_mtimespec.tv_nsec;
#elif defined(_WIN32)
    // Best-effort: second resolution only.
    sec = (long long)st.st_mtime;
    nsec = 0;
#else
    // POSIX (Linux): require XOPEN2K8/GNU features for st_mtim.
    sec = (long long)st.st_mtim.tv_sec;
    nsec = (long long)st.st_mtim.tv_nsec;
#endif

    long long mtime_ns = sec * 1000000000LL + nsec;
    return oren_new_list(2, oren_int(size), oren_int(mtime_ns));
}

OrenValue oren_write_file(OrenValue path, OrenValue content) {
    if (path.type != OREN_TYPE_STRING || content.type != OREN_TYPE_STRING) {
        oren_panic("write_file expects (string, string)");
        return OREN_NIL; // Should not be reached
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
    }
    size_t len = strlen(content.as.string_val);
    size_t n = fwrite(content.as.string_val, 1, len, f);
    fclose(f);
    if (n != len) {
        return oren_err_from_errno("cannot write file", path.as.string_val, errno);
    }
    return OREN_NIL;
}

OrenValue oren_write_bytes(OrenValue path, OrenValue bytes) {
    if (path.type != OREN_TYPE_STRING || !(bytes.type == OREN_TYPE_LIST || bytes.type == OREN_TYPE_U8_BUF)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes expects (string, list<int>|u8_buf)"));
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
    }

    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes: expected u8_buf"));
        }
        if (b->len != 0u && !b->data) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes: u8_buf payload is nil"));
        }
        if (b->len != 0u) {
            size_t n = fwrite(b->data, 1, (size_t)b->len, f);
            if (n != (size_t)b->len) {
                fclose(f);
                return oren_err_from_errno("cannot write bytes", path.as.string_val, errno);
            }
        }
        fclose(f);
        return OREN_NIL;
    }

    // list<int 0..255>
    int nbytes = bytes.as.list_val ? bytes.as.list_val->count : 0;
    if (nbytes > 0) {
        uint8_t* tmp = (uint8_t*)malloc((size_t)nbytes);
        if (!tmp) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("write_bytes: alloc failed"));
        }
        for (int i = 0; i < nbytes; i++) {
            OrenValue v = bytes.as.list_val->items[i];
            if (v.type != OREN_TYPE_INT) {
                free(tmp);
                fclose(f);
                char buf[160];
                snprintf(buf, sizeof(buf), "write_bytes expects list<int>; element %d has type=%d", i, v.type);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(buf));
            }
            long long b = v.as.int_val;
            if (b < 0 || b > 255) {
                free(tmp);
                fclose(f);
                char buf[160];
                snprintf(buf, sizeof(buf), "write_bytes byte out of range: element %d has value=%lld", i, b);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(buf));
            }
            tmp[i] = (uint8_t)b;
        }
        size_t nw = fwrite(tmp, 1, (size_t)nbytes, f);
        free(tmp);
        if (nw != (size_t)nbytes) {
            fclose(f);
            return oren_err_from_errno("cannot write bytes", path.as.string_val, errno);
        }
    }
    fclose(f);
    return OREN_NIL;
}

// Rename a filesystem entry.
//
// Return convention (syscall-like):
// - 0 on success
// - negative errno on failure
//
// This is used by compiler tooling to atomically install cached artifacts on macOS
// (avoid in-place overwrites that can trip kernel code-sign caches).
OrenValue oren_rename(OrenValue from, OrenValue to) {
    if (from.type != OREN_TYPE_STRING || to.type != OREN_TYPE_STRING) {
        return oren_int(-EINVAL);
    }
    if (rename(from.as.string_val, to.as.string_val) != 0) {
        return oren_int(-errno);
    }
    return oren_int(0);
}

OrenValue oren_read_bytes(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        oren_panic("read_bytes expects string path");
        return OREN_NIL; // Should not be reached
    }

    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        return oren_err_from_errno("cannot open file", path.as.string_val, errno);
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: fseek failed", path.as.string_val, errno);
    }
    long size_long = ftell(f);
    if (size_long < 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: ftell failed", path.as.string_val, errno);
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return oren_err_from_errno("read_bytes: fseek failed", path.as.string_val, errno);
    }

    // Oren lists use int counts; reject files too large for the current runtime representation.
    if (size_long > (long)INT32_MAX) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("read_bytes: file too large"));
    }

    int size = (int)size_long;

    unsigned char* buf = NULL;
    if (size > 0) {
        buf = (unsigned char*)malloc((size_t)size);
        if (!buf) {
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
        }
        size_t nread = fread(buf, 1, (size_t)size, f);
        if ((int)nread != size) {
            free(buf);
            fclose(f);
            return oren_err_from_errno("read_bytes: short read", path.as.string_val, errno);
        }
    }

    fclose(f);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        free(buf);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);

    list->count = size;
    list->capacity = size;
    list->items = NULL;
    if (size > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)size);
        if (!list->items) {
            unlock_collections();
            free(buf);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
        }
        for (int i = 0; i < size; i++) {
            list->items[i] = oren_int((unsigned char)buf[i]);
        }
    }

    unlock_collections();
    free(buf);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_read_u8_buf(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        oren_panic("read_u8_buf expects string path");
        return OREN_NIL; // Should not be reached
    }

    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        return oren_err_from_errno("cannot open file", path.as.string_val, errno);
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return oren_err_from_errno("read_u8_buf: fseek failed", path.as.string_val, errno);
    }
    long size_long = ftell(f);
    if (size_long < 0) {
        fclose(f);
        return oren_err_from_errno("read_u8_buf: ftell failed", path.as.string_val, errno);
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return oren_err_from_errno("read_u8_buf: fseek failed", path.as.string_val, errno);
    }

    if (size_long > (long)UINT32_MAX) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("read_u8_buf: file too large"));
    }
    uint32_t size = (uint32_t)size_long;

    OrenValue out = oren_u8_buf_new(oren_int((long long)size));
    if (oren_is_err(out).as.bool_val) {
        fclose(f);
        return out;
    }
    if (out.type != OREN_TYPE_U8_BUF || !out.as.buf_val) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_u8_buf: invalid buffer"));
    }
    OrenBuf* b = out.as.buf_val;
    if (b->elem_size != 1u) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_u8_buf: invalid elem_size"));
    }
    if (size > 0 && !b->data) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_u8_buf: u8_buf payload is nil"));
    }

    if (size > 0) {
        size_t nread = fread((void*)b->data, 1, (size_t)size, f);
        if (nread != (size_t)size) {
            fclose(f);
            return oren_err_from_errno("read_u8_buf: short read", path.as.string_val, errno);
        }
    }
    fclose(f);
    return out;
}

OrenValue oren_bytes_from_string(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("bytes_from_string expects string");
        return OREN_NIL; // Should not be reached
    }
    size_t n = strlen(s.as.string_val);
    if (n > (size_t)INT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("bytes_from_string: string too large"));
    }

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_string: alloc failed"));
    }
    oren_register_alloc(list, OREN_ALLOC_LIST);

    list->count = (int)n;
    list->capacity = (int)n;
    list->items = NULL;
    if (n > 0) {
        list->items = malloc(sizeof(OrenValue) * n);
        if (!list->items) {
            unlock_collections();
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_string: alloc failed"));
        }
        for (size_t i = 0; i < n; i++) {
            list->items[i] = oren_int((unsigned char)s.as.string_val[i]);
        }
    }
    unlock_collections();

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

OrenValue oren_string_from_bytes(OrenValue bytes) {
    if (bytes.type != OREN_TYPE_LIST) {
        oren_panic("string_from_bytes expects list<int 0..255>");
        return OREN_NIL; // Should not be reached
    }
    OrenList* list = bytes.as.list_val;
    if (!list || list->count < 0) {
        oren_panic("string_from_bytes: invalid list");
        return OREN_NIL; // Should not be reached
    }
    size_t n = (size_t)list->count;
    char* buf = (char*)malloc(n + 1);
    if (!buf) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes: out of memory"));
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            free(buf);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes: expected list<int 0..255>"));
        }
        buf[i] = (char)(unsigned char)it.as.int_val;
    }
    buf[n] = 0;
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = buf;
    oren_register_alloc(buf, OREN_ALLOC_STRING);
    return v;
}

OrenValue oren_string_from_bytes_slice(OrenValue bytes, OrenValue start, OrenValue len) {
    if (start.type != OREN_TYPE_INT || len.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice expects (bytes, int start, int len)"));
    }
    long long s0 = start.as.int_val;
    long long n0 = len.as.int_val;
    if (s0 < 0 || n0 < 0) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: negative range"));
    }
    if (n0 > (long long)INT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: len too large"));
    }

    size_t s = (size_t)s0;
    size_t n = (size_t)n0;

    // u8_buf fast path (preferred for astbin decoding).
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || !b->data) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: invalid u8_buf"));
        }
        size_t bn = (size_t)b->len;
        if (s > bn || n > bn || s + n > bn) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: out of bounds"));
        }
        char* out = (char*)malloc(n + 1u);
        if (!out) {
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes_slice: out of memory"));
        }
        memcpy(out, b->data + s, n);
        out[n] = 0;
        lock_collections();
        oren_register_alloc(out, OREN_ALLOC_STRING);
        unlock_collections();
        OrenValue v;
        v.type = OREN_TYPE_STRING;
        v.as.string_val = out;
        return v;
    }

    // list<int> slow path
    if (bytes.type != OREN_TYPE_LIST) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice expects list<int 0..255> or u8_buf"));
    }
    OrenList* list = bytes.as.list_val;
    if (!list || list->count < 0) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: invalid list"));
    }
    size_t bn2 = (size_t)list->count;
    if (s > bn2 || n > bn2 || s + n > bn2) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: out of bounds"));
    }
    char* out2 = (char*)malloc(n + 1u);
    if (!out2) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes_slice: out of memory"));
    }
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[s + i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            free(out2);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: expected bytes list<int 0..255>"));
        }
        out2[i] = (char)(unsigned char)it.as.int_val;
    }
    out2[n] = 0;
    lock_collections();
    oren_register_alloc(out2, OREN_ALLOC_STRING);
    unlock_collections();
    OrenValue v2;
    v2.type = OREN_TYPE_STRING;
    v2.as.string_val = out2;
    return v2;
}

OrenValue oren_u8_buf_from_bytes_slice(OrenValue bytes, OrenValue start, OrenValue len) {
    if (start.type != OREN_TYPE_INT || len.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice expects (bytes, int start, int len)"));
    }
    long long s0 = start.as.int_val;
    long long n0 = len.as.int_val;
    if (s0 < 0 || n0 < 0) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: negative range"));
    }
    if (n0 > (long long)INT32_MAX) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: len too large"));
    }

    size_t s = (size_t)s0;
    size_t n = (size_t)n0;

    // Determine source length.
    size_t total = 0;
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u || (b->len > 0 && !b->data)) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: invalid u8_buf"));
        }
        total = (size_t)b->len;
    } else if (bytes.type == OREN_TYPE_LIST) {
        OrenList* list = bytes.as.list_val;
        if (!list || list->count < 0) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: invalid list"));
        }
        total = (size_t)list->count;
    } else {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice expects list<int 0..255> or u8_buf"));
    }

    if (s > total || n > total || s + n > total) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: out of bounds"));
    }

    OrenValue outv = oren_u8_buf_new(oren_int((long long)n0));
    if (oren_is_err(outv).as.bool_val) {
        return outv;
    }
    if (outv.type != OREN_TYPE_U8_BUF || !outv.as.buf_val) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("u8_buf_from_bytes_slice: invalid buffer"));
    }
    OrenBuf* out = outv.as.buf_val;
    if (out->elem_size != 1u) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("u8_buf_from_bytes_slice: invalid elem_size"));
    }
    if (n > 0 && !out->data) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("u8_buf_from_bytes_slice: u8_buf payload is nil"));
    }

    if (n == 0) return outv;

    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        memcpy(out->data, b->data + s, n);
        return outv;
    }

    // list<int> slow path
    OrenList* list = bytes.as.list_val;
    for (size_t i = 0; i < n; i++) {
        OrenValue it = list->items[s + i];
        if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: expected bytes list<int 0..255>"));
        }
        ((unsigned char*)out->data)[i] = (unsigned char)it.as.int_val;
    }
    return outv;
}

OrenValue oren_string_join(OrenValue parts) {
    if (parts.type != OREN_TYPE_LIST) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_join expects list<string>"));
    }
    OrenList* list = parts.as.list_val;
    if (!list) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_join: invalid list"));
    }

    size_t total = 0;
    for (int i = 0; i < list->count; i++) {
        OrenValue it = list->items[i];
        if (it.type == OREN_TYPE_NIL) continue;
        if (it.type != OREN_TYPE_STRING) {
            char buf[160];
            snprintf(buf, sizeof(buf), "string_join expects list<string>; element %d has type=%d", i, it.type);
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(buf));
        }
        const char* s = it.as.string_val ? it.as.string_val : "";
        total += strlen(s);
    }

    // total+1 fits in size_t by construction unless overflowed; best-effort guard.
    if (total > (SIZE_MAX - 1u)) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_join: size overflow"));
    }

    char* out = (char*)malloc(total + 1u);
    if (!out) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_join: out of memory"));
    }

    char* p = out;
    for (int i = 0; i < list->count; i++) {
        OrenValue it = list->items[i];
        if (it.type != OREN_TYPE_STRING) continue;
        const char* s = it.as.string_val ? it.as.string_val : "";
        size_t n = strlen(s);
        if (n) {
            memcpy(p, s, n);
            p += n;
        }
    }
    out[total] = 0;

    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = out;
    oren_register_alloc(out, OREN_ALLOC_STRING);
    return v;
}

typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} OrenSha256Ctx;

static uint32_t oren_sha256_rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
static uint32_t oren_sha256_ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
static uint32_t oren_sha256_maj(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (x & z) ^ (y & z); }
static uint32_t oren_sha256_ep0(uint32_t x) { return oren_sha256_rotr(x, 2) ^ oren_sha256_rotr(x, 13) ^ oren_sha256_rotr(x, 22); }
static uint32_t oren_sha256_ep1(uint32_t x) { return oren_sha256_rotr(x, 6) ^ oren_sha256_rotr(x, 11) ^ oren_sha256_rotr(x, 25); }
static uint32_t oren_sha256_sig0(uint32_t x) { return oren_sha256_rotr(x, 7) ^ oren_sha256_rotr(x, 18) ^ (x >> 3); }
static uint32_t oren_sha256_sig1(uint32_t x) { return oren_sha256_rotr(x, 17) ^ oren_sha256_rotr(x, 19) ^ (x >> 10); }

static const uint32_t OREN_SHA256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void oren_sha256_transform(OrenSha256Ctx* ctx, const uint8_t data[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        int j = i * 4;
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) | ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
    }
    for (int i = 16; i < 64; i++) {
        m[i] = oren_sha256_sig1(m[i - 2]) + m[i - 7] + oren_sha256_sig0(m[i - 15]) + m[i - 16];
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + oren_sha256_ep1(e) + oren_sha256_ch(e, f, g) + OREN_SHA256_K[i] + m[i];
        uint32_t t2 = oren_sha256_ep0(a) + oren_sha256_maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void oren_sha256_init(OrenSha256Ctx* ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void oren_sha256_update(OrenSha256Ctx* ctx, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            oren_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void oren_sha256_final(OrenSha256Ctx* ctx, uint8_t out[32]) {
    uint32_t i = ctx->datalen;

    // Pad with a single 1 bit then zeros.
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        oren_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }

    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    oren_sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; i++) {
        out[i]      = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        out[i + 4]  = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        out[i + 8]  = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        out[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        out[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        out[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        out[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        out[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length) {
    if (!(bytes.type == OREN_TYPE_LIST || bytes.type == OREN_TYPE_U8_BUF) || start.type != OREN_TYPE_INT || length.type != OREN_TYPE_INT) {
        oren_panic("sha256_range expects (list<int>|u8_buf, int, int)");
        return OREN_NIL; // Should not be reached
    }
    long long s = start.as.int_val;
    long long n = length.as.int_val;

    long long total = 0;
    if (bytes.type == OREN_TYPE_LIST) {
        total = (long long)bytes.as.list_val->count;
    } else {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u) {
            oren_panic("sha256_range expects u8_buf");
            return OREN_NIL;
        }
        total = (long long)b->len;
    }

    if (s < 0 || n < 0 || s + n > total) {
        char buf[256];
        snprintf(buf, sizeof(buf), "sha256_range out of bounds (s=%lld, n=%lld, count=%lld)", s, n, total);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);

    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (n > 0 && !b->data) {
            oren_panic("sha256_range: u8_buf payload is nil");
            return OREN_NIL;
        }
        if (n > 0) {
            if ((uint64_t)n > (uint64_t)SIZE_MAX) {
                oren_panic("sha256_range: length too large");
                return OREN_NIL;
            }
            oren_sha256_update(&ctx, (uint8_t*)b->data + (size_t)s, (size_t)n);
        }
    } else {
        for (long long i = 0; i < n; i++) {
            OrenValue b = bytes.as.list_val->items[(int)(s + i)];
            if (b.type != OREN_TYPE_INT) {
                oren_panic("sha256_range expects list of ints");
                return OREN_NIL; // Should not be reached
            }
            long long v = b.as.int_val;
            if (v < 0 || v > 255) {
                char buf[128];
                snprintf(buf, sizeof(buf), "sha256_range byte out of range (val=%lld)", v);
                oren_panic(buf);
                return OREN_NIL; // Should not be reached
            }
            uint8_t byte = (uint8_t)v;
            oren_sha256_update(&ctx, &byte, 1);
        }
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    lock_collections();
    OrenList* out = malloc(sizeof(OrenList));
    if (!out) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_range: alloc failed"));
    }
    oren_register_alloc(out, OREN_ALLOC_LIST);

    out->count = 32;
    out->capacity = 32;
    out->items = malloc(sizeof(OrenValue) * 32);
    if (!out->items) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_range: alloc failed"));
    }
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    unlock_collections();
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}

OrenValue oren_sha256_string(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("sha256_string expects string");
        return OREN_NIL; // Should not be reached
    }
    const unsigned char* p = (const unsigned char*)s.as.string_val;
    size_t n = strlen((const char*)p);

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);
    if (n > 0) {
        oren_sha256_update(&ctx, p, n);
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    lock_collections();
    OrenList* out = malloc(sizeof(OrenList));
    if (!out) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_string: alloc failed"));
    }
    oren_register_alloc(out, OREN_ALLOC_LIST);

    out->count = 32;
    out->capacity = 32;
    out->items = malloc(sizeof(OrenValue) * 32);
    if (!out->items) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_string: alloc failed"));
    }
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    unlock_collections();

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}

OrenValue oren_chmod(OrenValue path, OrenValue mode) {
    if (path.type != OREN_TYPE_STRING || mode.type != OREN_TYPE_INT) {
        oren_panic("chmod expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    if (chmod(path.as.string_val, (mode_t)mode.as.int_val) != 0) {
        char buf[256];
        snprintf(buf, sizeof(buf), "chmod failed for %s", path.as.string_val);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    return OREN_NIL;
}

OrenValue oren_system(OrenValue cmd) {
    if (cmd.type != OREN_TYPE_STRING) {
        oren_panic("system expects string");
        return OREN_NIL; // Should not be reached
    }
    int res = system(cmd.as.string_val);
    return oren_int((long long)res);
}

OrenValue oren_net_get(OrenValue url) {
    (void)url;
    // Native/C backend runtime does not implement host networking in bootstrap.
    // Agentic networking is intended to run via AVM NET domain virtualization.
    return oren_err(oren_int(7), oren_string("net not implemented (use AVM)"));
}

OrenValue oren_exit(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        oren_panic("exit expects int");
        return OREN_NIL; // Should not be reached
    }
    exit((int)code.as.int_val);
    return OREN_NIL;
}

OrenValue oren_int_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_INT) {
        oren_panic("int_to_string expects int");
        return OREN_NIL; // Should not be reached
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%lld", v.as.int_val);
    return oren_string(buf);
}

OrenValue oren_float_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_FLOAT) {
        oren_panic("float_to_string expects float");
        return OREN_NIL; // Should not be reached
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%f", v.as.float_val);
    return oren_string(buf);
}

OrenValue oren_string_to_float_bits(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("string_to_float_bits expects string");
        return OREN_NIL;
    }
    double d = strtod(s.as.string_val, NULL);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return oren_int((long long)bits);
}

OrenValue oren_f32_round(OrenValue v) {
    if (v.type != OREN_TYPE_FLOAT) {
        // In rolling mode, avoid UB: return a structured error rather than panicking.
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("f32_round expects float"));
    }
    float f = (float)v.as.float_val;
    return oren_float((double)f);
}

OrenValue oren_f32_to_u32_bits(OrenValue v) {
    // Unsafe bitcast: float32 bits -> u32 (returned as int64 container).
    //
    // Input is a float (f64 container); we first round to float32 semantics, then extract bits.
    if (v.type != OREN_TYPE_FLOAT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("f32_to_u32_bits expects float"));
    }
    float f = (float)v.as.float_val;
    uint32_t bits = 0;
    memcpy(&bits, &f, sizeof(bits));
    return oren_int((int64_t)(uint64_t)bits);
}

OrenValue oren_u32_bits_to_f32(OrenValue v) {
    // Unsafe bitcast: interpret low 32 bits of int as float32.
    if (v.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u32_bits_to_f32 expects int"));
    }
    uint32_t bits = (uint32_t)(uint64_t)v.as.int_val;
    float f = 0.0f;
    memcpy(&f, &bits, sizeof(bits));
    // Return in the v0 float container (f64) while preserving float32 rounding boundary.
    return oren_float((double)f);
}

OrenValue oren_f64_to_u64_bits(OrenValue v) {
    // Unsafe bitcast: float64 bits -> u64 (returned as int64 container).
    if (v.type != OREN_TYPE_FLOAT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("f64_to_u64_bits expects float"));
    }
    uint64_t bits = 0;
    double d = v.as.float_val;
    memcpy(&bits, &d, sizeof(bits));
    return oren_int((int64_t)bits);
}

OrenValue oren_u64_bits_to_f64(OrenValue v) {
    // Unsafe bitcast: int64 bits -> float64.
    if (v.type != OREN_TYPE_INT) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u64_bits_to_f64 expects int"));
    }
    uint64_t bits = (uint64_t)v.as.int_val;
    double d = 0.0;
    memcpy(&d, &bits, sizeof(bits));
    return oren_float(d);
}

OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end) {
    if (s.type != OREN_TYPE_STRING || start.type != OREN_TYPE_INT || end.type != OREN_TYPE_INT) {
        oren_panic("string_slice type mismatch");
        return OREN_NIL; // Should not be reached
    }
    char* str = s.as.string_val;
    long long len = strlen(str);
    long long i = start.as.int_val;
    long long j = end.as.int_val;
    if (i < 0) i = 0;
    if (j > len) j = len;
    if (i >= j) {
        return oren_string_const("");
    }
    long long n = j - i;
    char* sub = malloc(n + 1);
    if (!sub) {
        oren_panic("string_slice: malloc failed");
        return OREN_NIL; // Should not be reached
    }
    memcpy(sub, str + i, (size_t)n);
    sub[n] = '\0';
    oren_register_alloc(sub, OREN_ALLOC_STRING);
    
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = sub;
    return v;
}

OrenValue oren_string_slice_unchecked(OrenValue s, OrenValue start, OrenValue end) {
    if (s.type != OREN_TYPE_STRING || start.type != OREN_TYPE_INT || end.type != OREN_TYPE_INT) {
        oren_panic("string_slice_unchecked type mismatch");
        return OREN_NIL; // Should not be reached
    }
    char* str = s.as.string_val;
    long long i = start.as.int_val;
    long long j = end.as.int_val;
    if (i < 0) i = 0;
    if (j < i) j = i;
    long long n = j - i;
    if (n <= 0) {
        return oren_string_const("");
    }
    char* sub = malloc((size_t)n + 1);
    if (!sub) {
        oren_panic("string_slice_unchecked: malloc failed");
        return OREN_NIL; // Should not be reached
    }
    memcpy(sub, str + i, (size_t)n);
    sub[n] = '\0';
    oren_register_alloc(sub, OREN_ALLOC_STRING);

    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = sub;
    return v;
}

// getenv wrapper: returns string or NIL
OrenValue oren_env(OrenValue name) {
    if (name.type != OREN_TYPE_STRING || name.as.string_val == NULL) {
        return OREN_NIL;
    }
    const char* key = name.as.string_val;
    const char* val = getenv(key);
    if (val == NULL) {
        return OREN_NIL;
    }
    return oren_string(val);
}

// Recursive free for compound objects; skips primitives.
void oren_free(OrenValue v) {
    if (v.type == OREN_TYPE_STRING) {
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(v.as.string_val);
        if (n && !n->freed) {
            n->freed = 1;
            free(n->ptr);
        }
        // Remove tracking node to keep registry bounded.
        // (Leaving freed nodes around makes `g_allocs` grow without bound under manual frees.)
        if (n) {
            void* p = n->ptr;
            // unlink from list
            OrenAllocNode* prev = NULL;
            OrenAllocNode* cur = g_allocs;
            while (cur) {
                if (cur == n) {
                    if (prev) prev->next = cur->next; else g_allocs = cur->next;
                    break;
                }
                prev = cur;
                cur = cur->next;
            }
            if (p) oren_alloc_index_remove_locked(p);
            free(n);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_LIST) {
        OrenList* lst = v.as.list_val;
        if (lst == NULL) return;
        for (int i = 0; i < lst->count; i++) {
            oren_free(lst->items[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(lst);
        if (n && !n->freed) {
            n->freed = 1;
            if (lst->items) free(lst->items);
            free(lst);
        }
        if (n) {
            void* p = n->ptr;
            OrenAllocNode* prev = NULL;
            OrenAllocNode* cur = g_allocs;
            while (cur) {
                if (cur == n) {
                    if (prev) prev->next = cur->next; else g_allocs = cur->next;
                    break;
                }
                prev = cur;
                cur = cur->next;
            }
            if (p) oren_alloc_index_remove_locked(p);
            free(n);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_MAP) {
        OrenMap* mp = v.as.map_val;
        if (mp == NULL) return;
        for (int i = 0; i < mp->count; i++) {
            oren_free(mp->keys[i]);
            oren_free(mp->values[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(mp);
        if (n && !n->freed) {
            n->freed = 1;
            if (mp->keys) free(mp->keys);
            if (mp->values) free(mp->values);
            free(mp);
        }
        if (n) {
            void* p = n->ptr;
            OrenAllocNode* prev = NULL;
            OrenAllocNode* cur = g_allocs;
            while (cur) {
                if (cur == n) {
                    if (prev) prev->next = cur->next; else g_allocs = cur->next;
                    break;
                }
                prev = cur;
                cur = cur->next;
            }
            if (p) oren_alloc_index_remove_locked(p);
            free(n);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
}

void oren_shutdown() {
    // Ensure no threads are running while tearing down runtime allocations.
    oren_join_all();
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = g_allocs;
    while (n != NULL) {
        OrenAllocNode* next = n->next;
        if (!n->freed) {
            if (n->kind == OREN_ALLOC_STRING) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_LIST) {
                OrenList* lst = (OrenList*)n->ptr;
                if (lst->items) free(lst->items);
                free(lst);
            } else if (n->kind == OREN_ALLOC_MAP) {
                OrenMap* mp = (OrenMap*)n->ptr;
                if (mp->keys) free(mp->keys);
                if (mp->values) free(mp->values);
                free(mp);
            } else if (n->kind == OREN_ALLOC_STRUCT) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_RAW_MMAP) {
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->backend == 1 && h->total_size > 0) {
                    (void)munmap((void*)h, (size_t)h->total_size);
                } else {
                    free(n->ptr);
                }
            } else if (n->kind == OREN_ALLOC_RAW) {
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->backend == 0 && h->total_size > 0) {
                    free((void*)h);
                } else {
                    free(n->ptr);
                }
            } else {
                free(n->ptr);
            }
        }
        free(n);
        n = next;
    }
    g_allocs = NULL;
    if (g_alloc_index) {
        free(g_alloc_index);
        g_alloc_index = NULL;
        g_alloc_index_cap = 0;
        g_alloc_index_len = 0;
    }
    // Clear registered roots to release bookkeeping nodes
    OrenAllocNode* r = g_roots;
    while (r != NULL) {
        OrenAllocNode* next_r = r->next;
        free(r);
        r = next_r;
    }
    g_roots = NULL;
    pthread_mutex_unlock(&g_alloc_mutex);
}

uint64_t oren_alloc_struct(size_t bytes) {
#ifdef OREN_NO_GC
    void* p = malloc(bytes);
#else
    void* p = malloc(bytes);
    oren_register_alloc(p, OREN_ALLOC_STRUCT);
#endif
    if (!p) {
        oren_panic("struct alloc failed");
        return (uint64_t)p; // Should not be reached, but needed for compiler
    }
    return (uint64_t)p;
}

void oren_free_struct(uint64_t ptr) {
#ifdef OREN_NO_GC
    free((void*)ptr);
    return;
#endif
    void* p = (void*)ptr;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(p);
    if (n && !n->freed) {
        n->freed = 1;
        free(p);
    }
    if (n) {
        // Remove tracking node to keep registry bounded under explicit frees.
        OrenAllocNode* prev = NULL;
        OrenAllocNode* cur = g_allocs;
        while (cur) {
            if (cur == n) {
                if (prev) prev->next = cur->next; else g_allocs = cur->next;
                break;
            }
            prev = cur;
            cur = cur->next;
        }
        oren_alloc_index_remove_locked(p);
        free(n);
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

uint64_t oren_alloc_raw_aligned(size_t bytes, size_t align) {
    void* base = NULL;
    void* p = NULL;
    int used_mmap = 0;
    if (align == 0) align = sizeof(void*);
    if ((align & (align - 1)) != 0 || align < sizeof(void*)) {
        oren_panic("raw alloc align invalid");
        return 0;
    }

    // Large allocation: prefer mmap so free/GC sweep can return memory to OS.
    // `mmap` returns page-aligned memory, which satisfies any <= page alignment.
    size_t thr = raw_mmap_threshold_cached();
    if (thr != 0 && bytes >= thr) {
        size_t hdr_size = sizeof(OrenRawHdr); // 64 bytes; keeps payload 64B-aligned
        size_t total = hdr_size + bytes;
        base = mmap(NULL, total, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (base == MAP_FAILED) {
            oren_panic("raw mmap alloc failed");
            return 0;
        }
        OrenRawHdr* h = (OrenRawHdr*)base;
        h->magic = OREN_RAW_MAGIC;
        h->total_size = (uint64_t)total;
        h->backend = 1;
        p = (uint8_t*)base + hdr_size;
        used_mmap = 1;
    } else {
        size_t hdr_size = sizeof(OrenRawHdr);
        size_t total = hdr_size + bytes;
        int er = posix_memalign(&base, align, total);
        if (er != 0 || !base) {
            oren_panic("raw alloc failed");
            return 0;
        }
        OrenRawHdr* h = (OrenRawHdr*)base;
        h->magic = OREN_RAW_MAGIC;
        h->total_size = (uint64_t)total;
        h->backend = 0;
        p = (uint8_t*)base + hdr_size;
    }
    if (!p) {
        oren_panic("raw alloc failed");
        return 0;
    }
#ifndef OREN_NO_GC
    oren_register_alloc(p, used_mmap ? OREN_ALLOC_RAW_MMAP : OREN_ALLOC_RAW);
#endif
    return (uint64_t)p;
}

void oren_free_raw(uint64_t ptr) {
    void* p = (void*)ptr;
    if (!p) return;

    // Raw blocks always store a 64-byte header immediately before the returned pointer.
    OrenRawHdr* h = ((OrenRawHdr*)p) - 1;

#ifdef OREN_NO_GC
    if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
        if (h->backend == 1) {
            (void)munmap((void*)h, (size_t)h->total_size);
            return;
        }
        free((void*)h);
        return;
    }
    // Fallback: unknown pointer.
    free(p);
    return;
#endif

    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(p);
    if (n && !n->freed) {
        n->freed = 1;
        if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
            if (h->backend == 1) {
                (void)munmap((void*)h, (size_t)h->total_size);
            } else {
                free((void*)h);
            }
        } else {
            // Corrupt/mismatched header; best-effort fallback.
            free(p);
        }
    }
    if (n) {
        OrenAllocNode* prev = NULL;
        OrenAllocNode* cur = g_allocs;
        while (cur) {
            if (cur == n) {
                if (prev) prev->next = cur->next; else g_allocs = cur->next;
                break;
            }
            prev = cur;
            cur = cur->next;
        }
        oren_alloc_index_remove_locked(p);
        free(n);
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

OrenValue oren_buf_payload_is_raw(OrenValue buf) {
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        oren_panic("buf_payload_is_raw expects (buf)");
        return OREN_NIL;
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) {
        oren_panic("buf_payload_is_raw: invalid buffer");
        return OREN_NIL;
    }
    if (b->len == 0) return OREN_TRUE;
    if (!b->data) return OREN_FALSE;

    // Typed buffer payloads allocated by `oren_alloc_raw_aligned` always have a header.
    OrenRawHdr* h = ((OrenRawHdr*)b->data) - 1;
    if (h->magic == OREN_RAW_MAGIC) return OREN_TRUE;

#ifndef OREN_NO_GC
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(b->data);
    int ok = (n && n->freed == 0 && (n->kind == OREN_ALLOC_RAW || n->kind == OREN_ALLOC_RAW_MMAP));
    pthread_mutex_unlock(&g_alloc_mutex);
    return oren_bool(ok);
#else
    return OREN_TRUE;
#endif
}

OrenValue oren_buf_payload_is_mmap(OrenValue buf) {
    if (buf.type != OREN_TYPE_U8_BUF && buf.type != OREN_TYPE_I32_BUF && buf.type != OREN_TYPE_I64_BUF && buf.type != OREN_TYPE_F32_BUF && buf.type != OREN_TYPE_F64_BUF) {
        oren_panic("buf_payload_is_mmap expects (buf)");
        return OREN_NIL;
    }
    OrenBuf* b = buf.as.buf_val;
    if (!b) {
        oren_panic("buf_payload_is_mmap: invalid buffer");
        return OREN_NIL;
    }
    if (b->len == 0) return OREN_FALSE;
    if (!b->data) return OREN_FALSE;

    // Typed buffer payloads allocated by `oren_alloc_raw_aligned` always have a header.
    OrenRawHdr* h = ((OrenRawHdr*)b->data) - 1;
    if (h->magic == OREN_RAW_MAGIC && h->backend == 1) return OREN_TRUE;

#ifndef OREN_NO_GC
    // Fallback to registry classification (for debug / mixed alloc cases).
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(b->data);
    int ok = (n && n->freed == 0 && n->kind == OREN_ALLOC_RAW_MMAP);
    pthread_mutex_unlock(&g_alloc_mutex);
    return oren_bool(ok);
#else
    return OREN_FALSE;
#endif
}
