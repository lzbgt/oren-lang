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

static int g_oren_select_cursor = 0;

static int oren_select_case_parse(
    OrenValue cv,
    int* out_kind,
    OrenValue* out_ch,
    OrenValue* out_sendv,
    int* out_fd
) {
    int kind = -1;
    OrenValue ch = OREN_NIL;
    OrenValue sendv = OREN_NIL;
    int rfd = -1;
    int wfd = -1;

    if (cv.type != OREN_TYPE_LIST || cv.as.list_val == NULL) return 0;
    OrenList* l = cv.as.list_val;

    if (l->count == 2) {
        OrenValue a0 = l->items[0];
        OrenValue a1 = l->items[1];
        if (a0.type == OREN_TYPE_INT && a0.as.int_val == 0 &&
            a1.type == OREN_TYPE_LIST && a1.as.list_val != NULL) {
            kind = 0;
            ch = a1;
        } else {
            // Convenience form: treat the list itself as a recv channel case.
            kind = 0;
            ch = cv;
        }
    } else if (l->count == 3) {
        OrenValue a0 = l->items[0];
        OrenValue a1 = l->items[1];
        if (a0.type == OREN_TYPE_INT && a0.as.int_val == 1 &&
            a1.type == OREN_TYPE_LIST && a1.as.list_val != NULL) {
            kind = 1;
            ch = a1;
            sendv = l->items[2];
        }
    }

    if (kind != 0 && kind != 1) return 0;
    if (!oren_channel_fds_extract(ch, &rfd, &wfd)) return 0;

    if (out_kind) *out_kind = kind;
    if (out_ch) *out_ch = ch;
    if (out_sendv) *out_sendv = sendv;
    if (out_fd) *out_fd = (kind == 0) ? rfd : wfd;
    return 1;
}

static OrenValue oren_select_result(int idx, OrenValue payload) {
    OrenValue items[2];
    items[0] = oren_int((long long)idx);
    items[1] = payload;
    return oren_new_list_from_array(2, items);
}

OrenValue oren_select(OrenValue cases) {
    if (cases.type != OREN_TYPE_LIST || cases.as.list_val == NULL) return oren_int(0);
    OrenList* outer = cases.as.list_val;
    int ncases = outer->count;
    if (ncases <= 0) return oren_int(0);

    // Keep the visible rolling contract aligned with native/AVM: duplicate fds are invalid.
    for (int i = 0; i < ncases; i++) {
        int ki = -1;
        int fdi = -1;
        OrenValue chi = OREN_NIL;
        OrenValue sendi = OREN_NIL;
        if (!oren_select_case_parse(outer->items[i], &ki, &chi, &sendi, &fdi)) continue;
        for (int j = 0; j < i; j++) {
            int kj = -1;
            int fdj = -1;
            OrenValue chj = OREN_NIL;
            OrenValue sendj = OREN_NIL;
            if (!oren_select_case_parse(outer->items[j], &kj, &chj, &sendj, &fdj)) continue;
            if (fdi >= 0 && fdj == fdi) return oren_int(-(long long)EINVAL);
        }
    }

#if defined(_WIN32)
    // Windows C backend channels are `_pipe`-backed and do not currently have a shared readiness
    // wait primitive equivalent to native mem-channel select. Keep the surface explicit instead of
    // pretending it works: compile-time/runtime callers receive ENOSYS until the C backend grows a
    // scheduler-aware multi-channel wait path on Windows.
    return oren_int(-(long long)ENOSYS);
#else
    struct pollfd* pfds = (struct pollfd*)calloc((size_t)ncases, sizeof(struct pollfd));
    if (pfds == NULL) return oren_int(-(long long)ENOMEM);

    for (;;) {
        int valid_count = 0;
        for (int i = 0; i < ncases; i++) {
            pfds[i].fd = -1;
            pfds[i].events = 0;
            pfds[i].revents = 0;

            int kind = -1;
            int fd = -1;
            OrenValue ch = OREN_NIL;
            OrenValue sendv = OREN_NIL;
            if (!oren_select_case_parse(outer->items[i], &kind, &ch, &sendv, &fd)) continue;
            pfds[i].fd = fd;
            pfds[i].events = (short)((kind == 0) ? POLLIN : POLLOUT);
            valid_count += 1;
        }

        if (valid_count <= 0) {
            free(pfds);
            return oren_int(0);
        }

        int rc = poll(pfds, (nfds_t)ncases, -1);
        if (rc < 0) {
            if (errno == EINTR) continue;
            int err = errno;
            free(pfds);
            return oren_int(-(long long)err);
        }
        if (rc == 0) continue;

        int start = 0;
        if (ncases > 0) {
            start = g_oren_select_cursor % ncases;
            if (start < 0) start += ncases;
        }

        for (int off = 0; off < ncases; off++) {
            int idx = (start + off) % ncases;
            short revents = pfds[idx].revents;
            if ((revents & (POLLIN | POLLOUT | POLLHUP | POLLERR | POLLNVAL)) == 0) continue;

            int kind = -1;
            int fd = -1;
            OrenValue ch = OREN_NIL;
            OrenValue sendv = OREN_NIL;
            if (!oren_select_case_parse(outer->items[idx], &kind, &ch, &sendv, &fd)) continue;

            if (kind == 0 && (revents & (POLLIN | POLLHUP | POLLERR))) {
                OrenValue payload = oren_chan_recv(ch);
                g_oren_select_cursor = (idx + 1) % ncases;
                free(pfds);
                return oren_select_result(idx, payload);
            }
            if (kind == 1 && (revents & (POLLOUT | POLLERR))) {
                OrenValue sent = oren_chan_send(ch, sendv);
                g_oren_select_cursor = (idx + 1) % ncases;
                free(pfds);
                return oren_select_result(idx, sent);
            }
        }
    }
#endif
}

OrenValue oren_select_recv(OrenValue chs) {
    return oren_select(chs);
}
