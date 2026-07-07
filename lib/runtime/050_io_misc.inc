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

OrenValue oren_append_file(OrenValue path, OrenValue content) {
    if (path.type != OREN_TYPE_STRING || content.type != OREN_TYPE_STRING) {
        oren_panic("append_file expects (string, string)");
        return OREN_NIL; // Should not be reached
    }
    FILE *f = fopen(path.as.string_val, "ab");
    if (!f) {
        return oren_err_from_errno("cannot open file for append", path.as.string_val, errno);
    }
    size_t len = strlen(content.as.string_val);
    size_t n = fwrite(content.as.string_val, 1, len, f);
    fclose(f);
    if (n != len) {
        return oren_err_from_errno("cannot append file", path.as.string_val, errno);
    }
    return OREN_NIL;
}

OrenValue oren_write_bytes(OrenValue path, OrenValue bytes) {
    if (path.type != OREN_TYPE_STRING || !(bytes.type == OREN_TYPE_LIST || bytes.type == OREN_TYPE_U8_BUF)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes expects (string, list<int>|u8_buf)"));
    }

    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes: expected u8_buf"));
        }
        if (b->len != 0u && !b->data) {
            return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("write_bytes: u8_buf payload is nil"));
        }
        FILE *f = fopen(path.as.string_val, "wb");
        if (!f) {
            return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
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
        for (int i = 0; i < nbytes; i++) {
            OrenValue v = bytes.as.list_val->items[i];
            if (v.type != OREN_TYPE_INT) {
                char buf[160];
                snprintf(buf, sizeof(buf), "write_bytes expects list<int>; element %d has type=%d", i, v.type);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(buf));
            }
            long long b = v.as.int_val;
            if (b < 0 || b > 255) {
                char buf[160];
                snprintf(buf, sizeof(buf), "write_bytes byte out of range: element %d has value=%lld", i, b);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(buf));
            }
        }
    }

    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        return oren_err_from_errno("cannot open file for write", path.as.string_val, errno);
    }

    if (nbytes > 0) {
        uint8_t chunk[64 * 1024];
        int off = 0;
        while (off < nbytes) {
            size_t want = (size_t)(nbytes - off);
            if (want > sizeof(chunk)) want = sizeof(chunk);
            for (size_t i = 0; i < want; i++) {
                chunk[i] = (uint8_t)(bytes.as.list_val->items[off + (int)i].as.int_val & 255);
            }
            size_t nw = fwrite(chunk, 1, want, f);
            if (nw != want) {
                fclose(f);
                return oren_err_from_errno("cannot write bytes", path.as.string_val, errno);
            }
            off += (int)want;
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

#if defined(_WIN32)
static int oren_win_is_dir_path(const char* path) {
    if (!path || !path[0]) return 0;
    DWORD attrs = GetFileAttributesA(path);
    if (attrs == INVALID_FILE_ATTRIBUTES) return 0;
    return (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static int oren_win_mkdir_one(const char* path) {
    if (!path || !path[0]) return -EINVAL;
    if (CreateDirectoryA(path, NULL)) return 0;
    DWORD e = GetLastError();
    if (e == ERROR_ALREADY_EXISTS) {
        if (oren_win_is_dir_path(path)) return 0;
        return -EEXIST;
    }
    if (e == ERROR_PATH_NOT_FOUND) return -ENOENT;
    if (e == ERROR_ACCESS_DENIED) return -EACCES;
    return -EIO;
}

static size_t oren_win_mkdirp_min_prefix(const char* path) {
    if (!path) return 0;
    // UNC prefix: \\server\share\ (UNC root)
    if (path[0] == '\\' && path[1] == '\\') {
        const char* p = path + 2;
        while (*p && *p != '\\') p++;
        if (!*p) return (size_t)strlen(path);
        p++; // after server '\'
        while (*p && *p != '\\') p++;
        if (!*p) return (size_t)strlen(path);
        // Include trailing '\' so mkdir starts after the share root.
        return (size_t)(p - path + 1);
    }
    // Drive prefix: C:\...
    char c0 = path[0];
    if ((c0 >= 'A' && c0 <= 'Z') || (c0 >= 'a' && c0 <= 'z')) {
        if (path[1] == ':') {
            if (path[2] == '\\') return 3;
            return 2;
        }
    }
    return 0;
}
#endif

#if !defined(_WIN32)
static int oren_is_dir_path(const char* path) {
    if (!path || !path[0]) return 0;
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return (st.st_mode & S_IFDIR) != 0;
}
#endif

// Recursive directory creation.
//
// Return convention (syscall-like):
// - 0 on success
// - negative errno on failure
OrenValue oren_mkdir_p(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_int(-EINVAL);
    }

    const char* s = path.as.string_val;
    if (!s || !s[0]) {
        return oren_int(0);
    }

    char* buf = strdup(s);
    if (!buf) {
        return oren_int(-ENOMEM);
    }

    size_t len = strlen(buf);

#if defined(_WIN32)
    // Normalize separators to '\'.
    for (size_t i = 0; i < len; i++) {
        if (buf[i] == '/') buf[i] = '\\';
    }
    size_t min_prefix = oren_win_mkdirp_min_prefix(buf);
#endif

    for (size_t i = 0; i < len; i++) {
#if defined(_WIN32)
        int is_sep = (buf[i] == '\\');
#else
        int is_sep = (buf[i] == '/');
#endif
        if (!is_sep) continue;
        if (i == 0) continue;
        // Skip repeated separators (avoid empty segments).
        if (i > 0) {
#if defined(_WIN32)
            if (buf[i - 1] == '\\') continue;
#else
            if (buf[i - 1] == '/') continue;
#endif
        }
#if defined(_WIN32)
        if (i < min_prefix) continue;
#endif

        char saved = buf[i];
        buf[i] = '\0';

#if defined(_WIN32)
        int rc = oren_win_mkdir_one(buf);
        if (rc != 0) {
            free(buf);
            return oren_int(rc);
        }
#else
        if (mkdir(buf, 0755) != 0) {
            if (errno == EEXIST) {
                if (!oren_is_dir_path(buf)) {
                    free(buf);
                    return oren_int(-EEXIST);
                }
            } else {
                int e = errno;
                free(buf);
                return oren_int(-e);
            }
        }
#endif

        buf[i] = saved;
    }

#if defined(_WIN32)
    {
        int rc = oren_win_mkdir_one(buf);
        free(buf);
        return oren_int(rc);
    }
#else
    if (mkdir(buf, 0755) != 0) {
        if (errno == EEXIST) {
            if (!oren_is_dir_path(buf)) {
                free(buf);
                return oren_int(-EEXIST);
            }
        } else {
            int e = errno;
            free(buf);
            return oren_int(-e);
        }
    }
    free(buf);
    return oren_int(0);
#endif
}

static char* oren_path_strdup_norm_win(const char* s) {
    if (!s) return NULL;
    char* buf = strdup(s);
    if (!buf) return NULL;
    for (char* p = buf; *p; p++) {
        if (*p == '/') *p = '\\';
    }
    return buf;
}

OrenValue oren_unlink(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_int(-EINVAL);
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) return oren_int(0);
#if defined(_WIN32)
    char* p = oren_path_strdup_norm_win(s);
    if (!p) return oren_int(-ENOMEM);
    int rc = _unlink(p);
    int e = errno;
    free(p);
    if (rc == 0) return oren_int(0);
    if (e == ENOENT) return oren_int(0);
    return oren_int(-e);
#else
    if (unlink(s) != 0) {
        if (errno == ENOENT) return oren_int(0);
        return oren_int(-errno);
    }
    return oren_int(0);
#endif
}

OrenValue oren_rmdir(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_int(-EINVAL);
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) return oren_int(0);
#if defined(_WIN32)
    char* p = oren_path_strdup_norm_win(s);
    if (!p) return oren_int(-ENOMEM);
    int rc = _rmdir(p);
    int e = errno;
    free(p);
    if (rc == 0) return oren_int(0);
    if (e == ENOENT) return oren_int(0);
    return oren_int(-e);
#else
    if (rmdir(s) != 0) {
        if (errno == ENOENT) return oren_int(0);
        return oren_int(-errno);
    }
    return oren_int(0);
#endif
}

#if defined(_WIN32)
static int oren_win_path_exists_cstr(const char* path) {
    DWORD attrs = GetFileAttributesA(path);
    return attrs != INVALID_FILE_ATTRIBUTES;
}

static int oren_win_is_file_cstr(const char* path) {
    DWORD attrs = GetFileAttributesA(path);
    if (attrs == INVALID_FILE_ATTRIBUTES) return 0;
    return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}
#endif

OrenValue oren_exists(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return OREN_FALSE;
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) return OREN_FALSE;
#if defined(_WIN32)
    char* p = oren_path_strdup_norm_win(s);
    if (!p) return OREN_FALSE;
    int ok = oren_win_path_exists_cstr(p);
    free(p);
    return ok ? OREN_TRUE : OREN_FALSE;
#else
    struct stat st;
    if (stat(s, &st) != 0) return OREN_FALSE;
    return OREN_TRUE;
#endif
}

OrenValue oren_is_file(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return OREN_FALSE;
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) return OREN_FALSE;
#if defined(_WIN32)
    char* p = oren_path_strdup_norm_win(s);
    if (!p) return OREN_FALSE;
    int ok = oren_win_is_file_cstr(p);
    free(p);
    return ok ? OREN_TRUE : OREN_FALSE;
#else
    struct stat st;
    if (stat(s, &st) != 0) return OREN_FALSE;
    if ((st.st_mode & S_IFREG) != 0) return OREN_TRUE;
    return OREN_FALSE;
#endif
}

#if defined(_WIN32)
static char* oren_win_join_path(const char* a, const char* b) {
    if (!a || !b) return NULL;
    size_t la = strlen(a);
    size_t lb = strlen(b);
    int need_sep = 1;
    if (la > 0) {
        char last = a[la - 1];
        if (last == '\\' || last == '/') need_sep = 0;
    }
    size_t n = la + (need_sep ? 1u : 0u) + lb + 1u;
    char* out = (char*)malloc(n);
    if (!out) return NULL;
    memcpy(out, a, la);
    size_t off = la;
    if (need_sep) out[off++] = '\\';
    memcpy(out + off, b, lb);
    out[off + lb] = '\0';
    // Normalize.
    for (char* p = out; *p; p++) {
        if (*p == '/') *p = '\\';
    }
    return out;
}

static int oren_win_rm_rf_cstr(const char* path);

static int oren_win_rm_rf_dir(const char* path) {
    // Enumerate children.
    size_t lp = strlen(path);
    size_t pat_len = lp + 3;
    char* pat = (char*)malloc(pat_len);
    if (!pat) return -ENOMEM;
    memcpy(pat, path, lp);
    size_t off = lp;
    if (off > 0 && pat[off - 1] != '\\' && pat[off - 1] != '/') {
        pat[off++] = '\\';
    }
    pat[off++] = '*';
    pat[off] = '\0';
    for (char* q = pat; *q; q++) if (*q == '/') *q = '\\';

    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pat, &fd);
    free(pat);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD e = GetLastError();
        if (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) {
            // Directory does not exist or is empty after deletion races.
        } else {
            return -EIO;
        }
    } else {
        for (;;) {
            const char* name = fd.cFileName;
            if (!(name[0] == '.' && name[1] == '\0') && !(name[0] == '.' && name[1] == '.' && name[2] == '\0')) {
                char* child = oren_win_join_path(path, name);
                if (!child) {
                    FindClose(h);
                    return -ENOMEM;
                }
                int rc = oren_win_rm_rf_cstr(child);
                free(child);
                if (rc != 0) {
                    FindClose(h);
                    return rc;
                }
            }
            if (!FindNextFileA(h, &fd)) break;
        }
        FindClose(h);
    }

    // Remove directory itself.
    if (_rmdir(path) != 0) {
        if (errno == ENOENT) return 0;
        return -errno;
    }
    return 0;
}

static int oren_win_rm_rf_cstr(const char* path) {
    if (!path || !path[0]) return 0;
    char* p = oren_path_strdup_norm_win(path);
    if (!p) return -ENOMEM;
    DWORD attrs = GetFileAttributesA(p);
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        DWORD e = GetLastError();
        free(p);
        if (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) return 0;
        return -EIO;
    }
    if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
        int rc = oren_win_rm_rf_dir(p);
        free(p);
        return rc;
    }
    // File.
    if (_unlink(p) != 0) {
        if (errno == ENOENT) {
            free(p);
            return 0;
        }
        int e = errno;
        free(p);
        return -e;
    }
    free(p);
    return 0;
}
#endif

#if !defined(_WIN32)
static int oren_posix_rm_rf_cstr(const char* path) {
    if (!path || !path[0]) return 0;
    struct stat st;
    if (lstat(path, &st) != 0) {
        if (errno == ENOENT) return 0;
        return -errno;
    }
    if ((st.st_mode & S_IFDIR) != 0) {
        DIR* d = opendir(path);
        if (!d) {
            if (errno == ENOENT) return 0;
            return -errno;
        }
        struct dirent* ent;
        while ((ent = readdir(d)) != NULL) {
            const char* name = ent->d_name;
            if (name[0] == '.' && name[1] == '\0') continue;
            if (name[0] == '.' && name[1] == '.' && name[2] == '\0') continue;
            size_t lp = strlen(path);
            size_t ln = strlen(name);
            size_t n = lp + 1 + ln + 1;
            char* child = (char*)malloc(n);
            if (!child) {
                closedir(d);
                return -ENOMEM;
            }
            memcpy(child, path, lp);
            child[lp] = '/';
            memcpy(child + lp + 1, name, ln);
            child[lp + 1 + ln] = '\0';
            int rc = oren_posix_rm_rf_cstr(child);
            free(child);
            if (rc != 0) {
                closedir(d);
                return rc;
            }
        }
        closedir(d);
        if (rmdir(path) != 0) {
            if (errno == ENOENT) return 0;
            return -errno;
        }
        return 0;
    }
    // File or symlink.
    if (unlink(path) != 0) {
        if (errno == ENOENT) return 0;
        return -errno;
    }
    return 0;
}
#endif

OrenValue oren_rm_rf(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_int(-EINVAL);
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) return oren_int(0);
#if defined(_WIN32)
    return oren_int(oren_win_rm_rf_cstr(s));
#else
    return oren_int(oren_posix_rm_rf_cstr(s));
#endif
}

OrenValue oren_readdir(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("readdir expects string path"));
    }
    const char* s = path.as.string_val;
    if (!s || !s[0]) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("readdir expects non-empty path"));
    }

    OrenValue out = oren_new_list(0);
    if (oren_is_err(out).as.bool_val) return out;

#if defined(_WIN32)
    char* p = oren_path_strdup_norm_win(s);
    if (!p) return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("readdir: alloc failed"));
    size_t lp = strlen(p);
    size_t pat_len = lp + 3u;
    char* pat = (char*)malloc(pat_len);
    if (!pat) {
        free(p);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("readdir: alloc failed"));
    }
    memcpy(pat, p, lp);
    size_t off = lp;
    if (off > 0 && pat[off - 1] != '\\' && pat[off - 1] != '/') pat[off++] = '\\';
    pat[off++] = '*';
    pat[off] = '\0';
    for (char* q = pat; *q; q++) {
        if (*q == '/') *q = '\\';
    }

    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pat, &fd);
    free(pat);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD e = GetLastError();
        free(p);
        int code = (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) ? OREN_ERR_NOT_FOUND : OREN_ERR_IO;
        char msg[512];
        snprintf(msg, sizeof(msg), "readdir: %s (winerr=%lu)", s, (unsigned long)e);
        return oren_err(oren_int(code), oren_string(msg));
    }
    for (;;) {
        const char* name = fd.cFileName;
        if (!(name[0] == '.' && name[1] == '\0') && !(name[0] == '.' && name[1] == '.' && name[2] == '\0')) {
            oren_list_push(out, oren_string(name));
        }
        if (!FindNextFileA(h, &fd)) break;
    }
    FindClose(h);
    free(p);
    return out;
#else
    DIR* d = opendir(s);
    if (!d) {
        return oren_err_from_errno("readdir: opendir failed", s, errno);
    }
    errno = 0;
    struct dirent* ent;
    while ((ent = readdir(d)) != NULL) {
        const char* name = ent->d_name;
        if (name[0] == '.' && name[1] == '\0') continue;
        if (name[0] == '.' && name[1] == '.' && name[2] == '\0') continue;
        oren_list_push(out, oren_string(name));
    }
    int err = errno;
    closedir(d);
    if (err != 0) {
        return oren_err_from_errno("readdir failed", s, err);
    }
    return out;
#endif
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

    OrenList* list = malloc(sizeof(OrenList));
    if (!list) {
        fclose(f);
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
    }

    list->count = size;
    list->capacity = size;
    list->items = NULL;
    list->all_int = 1;
    if (size > 0) {
        list->items = malloc(sizeof(OrenValue) * (size_t)size);
        if (!list->items) {
            free(list);
            fclose(f);
            return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("read_bytes: alloc failed"));
        }
        unsigned char chunk[64 * 1024];
        int off = 0;
        while (off < size) {
            size_t want = (size_t)(size - off);
            if (want > sizeof(chunk)) want = sizeof(chunk);
            size_t nread = fread(chunk, 1, want, f);
            if (nread != want) {
                free(list->items);
                free(list);
                fclose(f);
                return oren_err_from_errno("read_bytes: short read", path.as.string_val, errno);
            }
            for (size_t i = 0; i < nread; i++) {
                list->items[off + (int)i] = oren_int((unsigned char)chunk[i]);
            }
            off += (int)nread;
        }
    }

    fclose(f);
    oren_register_alloc(list, OREN_ALLOC_LIST);

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

    OrenValue out = oren_u8_buf_new_uninit(oren_int((long long)size));
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

    OrenValue out = oren_u8_buf_new_uninit(oren_int((long long)n));
    if (oren_is_err(out).as.bool_val) return out;
    if (out.type != OREN_TYPE_U8_BUF || !out.as.buf_val || out.as.buf_val->elem_size != 1u) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_string: invalid u8_buf"));
    }
    OrenBuf* b = out.as.buf_val;
    if (n > 0 && !b->data) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("bytes_from_string: u8_buf payload is nil"));
    }
    if (n > 0) memcpy(b->data, s.as.string_val, n);
    return out;
}

OrenValue oren_string_from_bytes(OrenValue bytes) {
    if (!(bytes.type == OREN_TYPE_LIST || bytes.type == OREN_TYPE_U8_BUF)) {
        oren_panic("string_from_bytes expects list<int 0..255> or u8_buf");
        return OREN_NIL; // Should not be reached
    }
    size_t n = 0;
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (!b || b->elem_size != 1u || (b->len > 0 && !b->data)) {
            oren_panic("string_from_bytes: invalid u8_buf");
            return OREN_NIL; // Should not be reached
        }
        n = (size_t)b->len;
    } else {
        OrenList* list = bytes.as.list_val;
        if (!list || list->count < 0) {
            oren_panic("string_from_bytes: invalid list");
            return OREN_NIL; // Should not be reached
        }
        n = (size_t)list->count;
    }
    char* buf = (char*)malloc(n + 1);
    if (!buf) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes: out of memory"));
    }
    if (bytes.type == OREN_TYPE_U8_BUF) {
        OrenBuf* b = bytes.as.buf_val;
        if (n > 0) memcpy(buf, b->data, n);
    } else {
        OrenList* list = bytes.as.list_val;
        for (size_t i = 0; i < n; i++) {
            OrenValue it = list->items[i];
            if (it.type != OREN_TYPE_INT || it.as.int_val < 0 || it.as.int_val > 255) {
                free(buf);
                return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes: expected list<int 0..255>"));
            }
            buf[i] = (char)(unsigned char)it.as.int_val;
        }
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

    size_t total = 0;
    const char* err_msg = NULL;
    if (!runtime_bytes_len_checked(bytes, &total, &err_msg)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "string_from_bytes_slice expects list<int 0..255> or u8_buf"));
    }
    if (!runtime_bytes_range_ok_size(total, s, n)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("string_from_bytes_slice: out of bounds"));
    }
    char* out = (char*)malloc(n + 1u);
    if (!out) {
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("string_from_bytes_slice: out of memory"));
    }
    lock_collections();
    int ok = runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out, &err_msg);
    unlock_collections();
    if (!ok) {
        free(out);
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "string_from_bytes_slice: expected bytes list<int 0..255>"));
    }
    out[n] = 0;
    lock_collections();
    oren_register_alloc(out, OREN_ALLOC_STRING);
    unlock_collections();
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = out;
    return v;
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

    size_t total = 0;
    const char* err_msg = NULL;
    if (!runtime_bytes_len_checked(bytes, &total, &err_msg)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "u8_buf_from_bytes_slice expects list<int 0..255> or u8_buf"));
    }

    if (!runtime_bytes_range_ok_size(total, s, n)) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string("u8_buf_from_bytes_slice: out of bounds"));
    }

    OrenValue outv = oren_u8_buf_new_uninit(oren_int((long long)n0));
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

    lock_collections();
    int ok = runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out->data, &err_msg);
    unlock_collections();
    if (!ok) {
        return oren_err(oren_int(OREN_ERR_INVALID_ARG), oren_string(err_msg ? err_msg : "u8_buf_from_bytes_slice: expected bytes list<int 0..255>"));
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

#include "050_io_misc_sha256.inc"

OrenValue oren_chmod(OrenValue path, OrenValue mode) {
    if (path.type != OREN_TYPE_STRING || mode.type != OREN_TYPE_INT) {
        oren_panic("chmod expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
#if defined(_WIN32)
    if (_chmod(path.as.string_val, (int)mode.as.int_val) != 0) {
#else
    if (chmod(path.as.string_val, (mode_t)mode.as.int_val) != 0) {
#endif
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
                if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
                    oren_raw_free_hdr(h);
                } else {
                    free(n->ptr);
                }
            } else if (n->kind == OREN_ALLOC_RAW) {
                OrenRawHdr* h = ((OrenRawHdr*)n->ptr) - 1;
                if (h->magic == OREN_RAW_MAGIC && h->total_size > 0) {
                    oren_raw_free_hdr(h);
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

    // Large allocation: prefer mmap/VirtualAlloc so free/GC sweep can return memory to OS.
    // This is important for long-running workloads (compiler, HPC) to keep RSS bounded.
    size_t thr = raw_mmap_threshold_cached();
#if defined(_WIN32)
    // Win32: use VirtualAlloc for large blocks; use _aligned_malloc otherwise.
    size_t hdr_size = sizeof(OrenRawHdr); // 64 bytes; keeps payload 64B-aligned
    size_t total = hdr_size + bytes;
    if (thr != 0 && bytes >= thr) {
        base = VirtualAlloc(NULL, total, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (!base) {
            oren_panic("raw VirtualAlloc failed");
            return 0;
        }
        used_mmap = 1;
    } else {
        base = _aligned_malloc(total, align);
        if (!base) {
            oren_panic("raw alloc failed");
            return 0;
        }
        used_mmap = 0;
    }
    OrenRawHdr* h = (OrenRawHdr*)base;
    h->magic = OREN_RAW_MAGIC;
    h->total_size = (uint64_t)total;
    h->backend = used_mmap ? 1 : 0;
    p = (uint8_t*)base + hdr_size;
#else
    // POSIX: use mmap for large blocks; posix_memalign for smaller ones.
    // `mmap` returns page-aligned memory, which satisfies any <= page alignment.
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
#endif
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
        oren_raw_free_hdr(h);
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
            oren_raw_free_hdr(h);
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
