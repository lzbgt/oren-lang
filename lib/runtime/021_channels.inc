static int oren_channel_fds_extract(OrenValue ch, int* out_rfd, int* out_wfd) {
    if (ch.type != OREN_TYPE_LIST || ch.as.list_val == NULL) return 0;
    OrenList* l = ch.as.list_val;
    if (l->count < 2) return 0;
    OrenValue r = l->items[0];
    OrenValue w = l->items[1];
    if (r.type != OREN_TYPE_INT || w.type != OREN_TYPE_INT) return 0;
    if (out_rfd) *out_rfd = (int)r.as.int_val;
    if (out_wfd) *out_wfd = (int)w.as.int_val;
    return 1;
}

static int oren_channel_os_pipe(int fds[2]) {
#if defined(_WIN32)
    return _pipe(fds, (unsigned int)(sizeof(OrenValue) * 32u), _O_BINARY);
#else
    return pipe(fds);
#endif
}

static int oren_channel_write_fd(int fd, const void* buf, size_t n) {
    const char* p = (const char*)buf;
    size_t off = 0;
    while (off < n) {
#if defined(_WIN32)
        int w = _write(fd, p + off, (unsigned int)(n - off));
#else
        ssize_t w = write(fd, p + off, n - off);
#endif
        if (w < 0) {
#if defined(_WIN32)
            if (errno == EINTR) continue;
#else
            if (errno == EINTR) continue;
#endif
            return -1;
        }
        if (w == 0) return -1;
        off += (size_t)w;
    }
    return 0;
}

static int oren_channel_read_fd(int fd, void* buf, size_t n) {
    char* p = (char*)buf;
    size_t off = 0;
    while (off < n) {
#if defined(_WIN32)
        int r = _read(fd, p + off, (unsigned int)(n - off));
#else
        ssize_t r = read(fd, p + off, n - off);
#endif
        if (r == 0) return -1;
        if (r < 0) {
#if defined(_WIN32)
            if (errno == EINTR) continue;
#else
            if (errno == EINTR) continue;
#endif
            return -1;
        }
        off += (size_t)r;
    }
    return 0;
}

OrenValue oren_new_channel(void) {
    int fds[2] = {-1, -1};
    if (oren_channel_os_pipe(fds) != 0) return oren_int(0);
    OrenValue items[2];
    items[0] = oren_int((long long)fds[0]);
    items[1] = oren_int((long long)fds[1]);
    return oren_new_list_from_array(2, items);
}

OrenValue oren_chan_send(OrenValue ch, OrenValue value) {
    int rfd = -1;
    int wfd = -1;
    if (!oren_channel_fds_extract(ch, &rfd, &wfd)) {
        oren_panic("chan_send expects channel [rfd, wfd]");
        return OREN_NIL;
    }
    (void)rfd;
    if (oren_channel_write_fd(wfd, &value, sizeof(OrenValue)) != 0) {
        return oren_int(0);
    }
    return oren_int(1);
}

OrenValue oren_chan_recv(OrenValue ch) {
    int rfd = -1;
    int wfd = -1;
    OrenValue value = OREN_NIL;
    if (!oren_channel_fds_extract(ch, &rfd, &wfd)) {
        oren_panic("chan_recv expects channel [rfd, wfd]");
        return OREN_NIL;
    }
    (void)wfd;
    if (oren_channel_read_fd(rfd, &value, sizeof(OrenValue)) != 0) {
        return OREN_NIL;
    }
    return value;
}
