static AvmValue avm_vfs_snapshot_bytes_value(AvmVM* child) {
    // Serialize child's VirtualFS into AVMVFS01 bytes (as data), so parent universes
    // can consume child-produced artifacts without host filesystem effects.
    //
    // Format:
    //   magic[8] = "AVMVFS01"
    //   u32 count
    //   repeated:
    //     u32 path_len, path bytes (utf-8/bytes)
    //     u32 body_len, body bytes
    if (!child || child->fs_backend_kind != 1 || !child->vfs) return avm_nil();
    AvmVfs* v = (AvmVfs*)child->vfs;
    uint32_t cnt = v ? (uint32_t)v->count : 0u;

    AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
    if (!blob) return avm_alloc_fail_value();
    blob->data = NULL;
    blob->len = 0;
    blob->capacity = 0;
    uint32_t p = 0;

    if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); return avm_alloc_fail_value(); }
    const uint8_t magic[8] = {'A','V','M','V','F','S','0','1'};
    if (!mem_write_bytes(blob, &p, magic, 8)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
    if (!mem_write_u32_le(blob, &p, cnt)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }

    for (uint32_t i = 0; i < cnt; i++) {
        AvmVfsEntry* e = v ? &v->entries[i] : NULL;
        const char* path = (e && e->path) ? e->path : "";
        uint64_t pl64 = (uint64_t)strlen(path);
        if (pl64 > 0xFFFFFFFEu) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        uint32_t pl = (uint32_t)pl64;
        if (!mem_write_u32_le(blob, &p, pl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        if (pl > 0 && !mem_write_bytes(blob, &p, (const uint8_t*)path, pl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }

        uint32_t bl = (e && e->len > 0) ? (uint32_t)e->len : 0u;
        if (!mem_write_u32_le(blob, &p, bl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
        if (bl > 0 && !mem_write_bytes(blob, &p, e ? e->data : NULL, bl)) { if (blob->data) avm_heap_free(blob->data); avm_heap_free(blob); return avm_alloc_fail_value(); }
    }

    blob->len = (int)p;
    AvmValue out;
    out.type = AVM_VAL_BYTES;
    out.as.b = blob;
    return out;
}

static int avm_parse_obc_from_bytes(AvmVM* owner, const AvmBytes* obc, AvmProgram* out) {
    if (!obc || !out) return 0;
    if (!obc->data || obc->len < 4) return 0;

    const uint8_t* data = obc->data;
    size_t len = (size_t)obc->len;

    // Always initialize output so callers can safely call cleanup on failure.
    out->code = NULL;
    out->code_len = 0;
    out->constants = NULL;
    out->const_count = 0;

    // Header: CD 0E
    if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) return 0;

    // Const count (u16)
    size_t pos = 2;
    if (pos + 2 > len) return 0;
    uint16_t n_consts = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
    pos += 2;

    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)n_consts);
    if (!consts && n_consts > 0) return 0;
    for (uint16_t i = 0; i < n_consts; i++) consts[i].type = AVM_VAL_NIL;

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(owner, &prev_owner);

    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) goto fail;
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
            continue;
        }
        if (type == 1) { // INT
            if (pos + 8 > len) goto fail;
            int64_t val = 0;
            for (int k = 0; k < 8; k++) {
                val |= (int64_t)data[pos++] << (k * 8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
            continue;
        }
        if (type == 2) { // BOOL (u8 0|1)
            if (pos + 1 > len) goto fail;
            uint8_t b = data[pos++];
            consts[i].type = AVM_VAL_BOOL;
            consts[i].as.i = b ? 1 : 0;
            continue;
        }
        if (type == 3) { // FLOAT (f64 bits as u64 little-endian)
            if (pos + 8 > len) goto fail;
            uint64_t bits = 0;
            for (int k = 0; k < 8; k++) bits |= (uint64_t)data[pos++] << (k * 8);
            double d = 0.0;
            memcpy(&d, &bits, sizeof(bits));
            consts[i].type = AVM_VAL_FLOAT;
            consts[i].as.f = d;
            continue;
        }
        if (type == 4) { // STRING
            if (pos + 2 > len) goto fail;
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            if (pos + slen > len) goto fail;
            char* s = (char*)avm_heap_malloc_k((size_t)slen + 1, AVM_ALLOC_KIND_STRING);
            if (!s) goto fail;
            if (slen > 0) memcpy(s, data + pos, slen);
            s[slen] = 0;
            pos += slen;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
            continue;
        }
        if (type == 8) { // BYTES (rolling): u32 len + raw bytes
            if (pos + 4 > len) goto fail;
            uint32_t blen = (uint32_t)data[pos] |
                ((uint32_t)data[pos + 1] << 8) |
                ((uint32_t)data[pos + 2] << 16) |
                ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (pos + blen > len) goto fail;
            AvmBytes* b = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_BYTES);
            if (!b) goto fail;
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)avm_heap_malloc_k((size_t)blen, AVM_ALLOC_KIND_BYTES);
                if (!b->data) { avm_heap_free(b); goto fail; }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
            continue;
        }
        goto fail;
    }

    if (pos > len) goto fail;
    out->code = (uint8_t*)(data + pos);
    out->code_len = len - pos;
    out->constants = consts;
    out->const_count = n_consts;
    avm_alloc_owner_pop(prev_owner);
    return 1;

fail:
    avm_alloc_owner_pop(prev_owner);
    if (consts) {
        for (uint16_t i = 0; i < n_consts; i++) {
            if (consts[i].type == AVM_VAL_STRING && consts[i].as.p) {
                avm_heap_free(consts[i].as.p);
            } else if (consts[i].type == AVM_VAL_BYTES && consts[i].as.b) {
                if (consts[i].as.b->data) avm_heap_free(consts[i].as.b->data);
                avm_heap_free(consts[i].as.b);
            }
            consts[i].type = AVM_VAL_NIL;
        }
        free(consts);
    }
    out->code = NULL;
    out->code_len = 0;
    out->constants = NULL;
    out->const_count = 0;
    return 0;
}

static int avm_clone_fs_allow_prefixes(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src) return 1;
    if (src->fs_allow_prefix_count <= 0 || !src->fs_allow_prefixes) return 1;

    int n = src->fs_allow_prefix_count;
    dst->fs_allow_prefix_count = 0;
    dst->fs_allow_prefixes = (char**)malloc(sizeof(char*) * (size_t)n);
    if (!dst->fs_allow_prefixes) return 0;
    for (int i = 0; i < n; i++) dst->fs_allow_prefixes[i] = NULL;

    for (int i = 0; i < n; i++) {
        const char* s = src->fs_allow_prefixes[i];
        if (!s) s = "";
        size_t sl = strlen(s);
        dst->fs_allow_prefixes[i] = (char*)malloc(sl + 1);
        if (!dst->fs_allow_prefixes[i]) {
            for (int j = 0; j < n; j++) { if (dst->fs_allow_prefixes[j]) free(dst->fs_allow_prefixes[j]); }
            free(dst->fs_allow_prefixes);
            dst->fs_allow_prefixes = NULL;
            dst->fs_allow_prefix_count = 0;
            return 0;
        }
        memcpy(dst->fs_allow_prefixes[i], s, sl);
        dst->fs_allow_prefixes[i][sl] = 0;
        dst->fs_allow_prefix_count++;
    }

    return 1;
}

static int avm_clone_fs_mounts(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src) return 1;

    // Clone read mounts
    if (src->fs_mounts_read_count > 0 && src->fs_mounts_read_virt && src->fs_mounts_read_host) {
        int n = src->fs_mounts_read_count;
        dst->fs_mounts_read_count = 0;
        dst->fs_mounts_read_virt = (char**)malloc(sizeof(char*) * (size_t)n);
        dst->fs_mounts_read_host = (char**)malloc(sizeof(char*) * (size_t)n);
        if (!dst->fs_mounts_read_virt || !dst->fs_mounts_read_host) {
            if (dst->fs_mounts_read_virt) free(dst->fs_mounts_read_virt);
            if (dst->fs_mounts_read_host) free(dst->fs_mounts_read_host);
            dst->fs_mounts_read_virt = NULL;
            dst->fs_mounts_read_host = NULL;
            dst->fs_mounts_read_count = 0;
            return 0;
        }
        for (int i = 0; i < n; i++) { dst->fs_mounts_read_virt[i] = NULL; dst->fs_mounts_read_host[i] = NULL; }
        for (int i = 0; i < n; i++) {
            const char* v = src->fs_mounts_read_virt[i] ? src->fs_mounts_read_virt[i] : "";
            const char* h = src->fs_mounts_read_host[i] ? src->fs_mounts_read_host[i] : "";
            size_t vl = strlen(v);
            size_t hl = strlen(h);
            dst->fs_mounts_read_virt[i] = (char*)malloc(vl + 1);
            dst->fs_mounts_read_host[i] = (char*)malloc(hl + 1);
            if (!dst->fs_mounts_read_virt[i] || !dst->fs_mounts_read_host[i]) {
                if (dst->fs_mounts_read_virt[i]) free(dst->fs_mounts_read_virt[i]);
                if (dst->fs_mounts_read_host[i]) free(dst->fs_mounts_read_host[i]);
                for (int j = 0; j < n; j++) {
                    if (dst->fs_mounts_read_virt[j]) free(dst->fs_mounts_read_virt[j]);
                    if (dst->fs_mounts_read_host[j]) free(dst->fs_mounts_read_host[j]);
                }
                free(dst->fs_mounts_read_virt);
                free(dst->fs_mounts_read_host);
                dst->fs_mounts_read_virt = NULL;
                dst->fs_mounts_read_host = NULL;
                dst->fs_mounts_read_count = 0;
                return 0;
            }
            memcpy(dst->fs_mounts_read_virt[i], v, vl); dst->fs_mounts_read_virt[i][vl] = 0;
            memcpy(dst->fs_mounts_read_host[i], h, hl); dst->fs_mounts_read_host[i][hl] = 0;
            dst->fs_mounts_read_count++;
        }
    }

    // Clone write mounts
    if (src->fs_mounts_write_count > 0 && src->fs_mounts_write_virt && src->fs_mounts_write_host) {
        int n = src->fs_mounts_write_count;
        dst->fs_mounts_write_count = 0;
        dst->fs_mounts_write_virt = (char**)malloc(sizeof(char*) * (size_t)n);
        dst->fs_mounts_write_host = (char**)malloc(sizeof(char*) * (size_t)n);
        if (!dst->fs_mounts_write_virt || !dst->fs_mounts_write_host) {
            if (dst->fs_mounts_write_virt) free(dst->fs_mounts_write_virt);
            if (dst->fs_mounts_write_host) free(dst->fs_mounts_write_host);
            dst->fs_mounts_write_virt = NULL;
            dst->fs_mounts_write_host = NULL;
            dst->fs_mounts_write_count = 0;
            return 0;
        }
        for (int i = 0; i < n; i++) { dst->fs_mounts_write_virt[i] = NULL; dst->fs_mounts_write_host[i] = NULL; }
        for (int i = 0; i < n; i++) {
            const char* v = src->fs_mounts_write_virt[i] ? src->fs_mounts_write_virt[i] : "";
            const char* h = src->fs_mounts_write_host[i] ? src->fs_mounts_write_host[i] : "";
            size_t vl = strlen(v);
            size_t hl = strlen(h);
            dst->fs_mounts_write_virt[i] = (char*)malloc(vl + 1);
            dst->fs_mounts_write_host[i] = (char*)malloc(hl + 1);
            if (!dst->fs_mounts_write_virt[i] || !dst->fs_mounts_write_host[i]) {
                if (dst->fs_mounts_write_virt[i]) free(dst->fs_mounts_write_virt[i]);
                if (dst->fs_mounts_write_host[i]) free(dst->fs_mounts_write_host[i]);
                for (int j = 0; j < n; j++) {
                    if (dst->fs_mounts_write_virt[j]) free(dst->fs_mounts_write_virt[j]);
                    if (dst->fs_mounts_write_host[j]) free(dst->fs_mounts_write_host[j]);
                }
                free(dst->fs_mounts_write_virt);
                free(dst->fs_mounts_write_host);
                dst->fs_mounts_write_virt = NULL;
                dst->fs_mounts_write_host = NULL;
                dst->fs_mounts_write_count = 0;
                return 0;
            }
            memcpy(dst->fs_mounts_write_virt[i], v, vl); dst->fs_mounts_write_virt[i][vl] = 0;
            memcpy(dst->fs_mounts_write_host[i], h, hl); dst->fs_mounts_write_host[i][hl] = 0;
            dst->fs_mounts_write_count++;
        }
    }

    return 1;
}

static char* avm_fs_map_path(const AvmVM* vm, const char* vpath, int is_write, int* matched_out) {
    if (matched_out) *matched_out = 0;
    if (!vm || !vpath) return NULL;
    if (vm->fs_backend_kind != 0) return NULL; // mapping is host-backend only

    const char* const* virt = is_write ? (const char* const*)vm->fs_mounts_write_virt : (const char* const*)vm->fs_mounts_read_virt;
    const char* const* host = is_write ? (const char* const*)vm->fs_mounts_write_host : (const char* const*)vm->fs_mounts_read_host;
    int n = is_write ? vm->fs_mounts_write_count : vm->fs_mounts_read_count;
    if (!virt || !host || n <= 0) return NULL;

    int best = -1;
    size_t best_len = 0;
    for (int i = 0; i < n; i++) {
        const char* vp = virt[i];
        if (!vp) continue;
        size_t vl = strlen(vp);
        if (vl == 0) continue;
        if (strncmp(vpath, vp, vl) == 0) {
            // Boundary check when virt_prefix does not end with '/':
            // Avoid accidental matches like 'v/mnt' matching 'v/mnt2'.
            int ok = 1;
            if (vl > 0 && vp[vl - 1] != '/') {
                char nextc = vpath[vl];
                if (nextc != 0 && nextc != '/') ok = 0;
            }
            if (ok) {
                if (vl > best_len) { best = i; best_len = vl; }
            }
        }
    }
    if (best < 0) {
        // Host-prefix fast path (parity with native runtime):
        // If the caller already passes a host path that starts with any enrolled host prefix,
        // allow it as-is. This keeps mounts as the enrollment mechanism even when higher-level
        // code pre-resolves paths.
        int best_h = -1;
        size_t best_hl = 0;
        for (int i = 0; i < n; i++) {
            const char* hp = host[i];
            if (!hp) continue;
            size_t hl = strlen(hp);
            if (hl == 0) continue;
            if (strncmp(vpath, hp, hl) == 0) {
                // Boundary check when host_prefix does not end with '/':
                // Avoid accidental matches like '/mnt' matching '/mnt2'.
                int ok = 1;
                if (hl > 0 && hp[hl - 1] != '/') {
                    char nextc = vpath[hl];
                    if (nextc != 0 && nextc != '/') ok = 0;
                }
                if (ok) {
                    if (hl > best_hl) { best_h = i; best_hl = hl; }
                }
            }
        }
        if (best_h < 0) return NULL;
        if (matched_out) *matched_out = 1;
        size_t pl = strlen(vpath);
        char* out = (char*)malloc(pl + 1);
        if (!out) return NULL;
        memcpy(out, vpath, pl);
        out[pl] = 0;
        return out;
    }
    if (matched_out) *matched_out = 1;

    const char* hp = host[best] ? host[best] : "";
    size_t hl = strlen(hp);
    const char* rest = vpath + best_len;
    size_t rl = strlen(rest);
    char* out = (char*)malloc(hl + rl + 1);
    if (!out) return NULL;
    if (hl) memcpy(out, hp, hl);
    if (rl) memcpy(out + hl, rest, rl);
    out[hl + rl] = 0;
    return out;
}

static const char* avm_fs_op_name(uint16_t op) {
    switch (op) {
        case 0: return "read_file";
        case 1: return "write_file";
        case 2: return "write_bytes";
        case 3: return "read_bytes";
        case 4: return "exists";
        case 5: return "readdir";
        default: return "fs_op";
    }
}

static void avm_format_path_short(char* out, size_t outn, const char* path) {
    if (!out || outn == 0) return;
    if (!path) {
        snprintf(out, outn, "<null>");
        return;
    }
    size_t n = strlen(path);
    if (n <= 160) {
        snprintf(out, outn, "'%s'", path);
        return;
    }
    // Keep a deterministic short prefix/suffix for diagnostics (avoid huge error strings).
    // Format: 'prefix...suffix'
    char pfx[81];
    char sfx[61];
    memcpy(pfx, path, 80);
    pfx[80] = 0;
    memcpy(sfx, path + (n - 60), 60);
    sfx[60] = 0;
    snprintf(out, outn, "'%s...%s'", pfx, sfx);
}

static AvmValue avm_err_fs_mount_denied(uint8_t domain, uint16_t op, const char* path, int is_write) {
    char pbuf[220];
    avm_format_path_short(pbuf, sizeof(pbuf), path);

    const char* opname = avm_fs_op_name(op);
    const char* rw = is_write ? "write" : "read";

    // Keep message concise but actionable. Mention both AVM_* and OREN_* env vars because
    // ./avm can be used as a runner for programs compiled from the same sources as native.
    char msg[600];
    snprintf(
        msg,
        sizeof(msg),
        "fs mount denied (%s/%s): path=%s; hint: set AVM_FS_MOUNTS[_READ|_WRITE] (or OREN_FS_MOUNTS[_READ|_WRITE])",
        opname,
        rw,
        pbuf
    );
    return avm_err_domop(AVM_ERR_PERM, msg, (int)domain, (int)op);
}

static int cmp_avm_value_string(const void* a, const void* b) {
    const AvmValue* va = (const AvmValue*)a;
    const AvmValue* vb = (const AvmValue*)b;
    const char* sa = (va && va->type == AVM_VAL_STRING && va->as.p) ? (const char*)va->as.p : "";
    const char* sb = (vb && vb->type == AVM_VAL_STRING && vb->as.p) ? (const char*)vb->as.p : "";
    return strcmp(sa, sb);
}

static AvmVfs* avm_vfs_get_or_create(AvmVM* vm) {
    if (!vm) return NULL;
    if (vm->vfs) return (AvmVfs*)vm->vfs;
    AvmVfs* v = (AvmVfs*)avm_heap_malloc_k(sizeof(AvmVfs), AVM_ALLOC_KIND_VFS);
    if (!v) return NULL;
    v->entries = NULL;
    v->count = 0;
    v->cap = 0;
    vm->vfs = v;
    return v;
}

static AvmVfsEntry* avm_vfs_find(AvmVfs* v, const char* path) {
    if (!v || !path) return NULL;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].path && strcmp(v->entries[i].path, path) == 0) return &v->entries[i];
    }
    return NULL;
}

static int avm_vfs_ensure_cap(AvmVfs* v, uint32_t need) {
    if (!v) return 0;
    if (need <= v->cap) return 1;
    uint32_t nc = v->cap ? v->cap : 16;
    while (nc < need) nc *= 2;
    AvmVfsEntry* ne = (AvmVfsEntry*)avm_heap_realloc_k(v->entries, sizeof(AvmVfsEntry) * (size_t)nc, AVM_ALLOC_KIND_VFS);
    if (!ne) return 0;
    // Initialize new slots to a safe state.
    for (uint32_t i = v->cap; i < nc; i++) {
        ne[i].path = NULL;
        ne[i].data = NULL;
        ne[i].len = 0;
    }
    v->entries = ne;
    v->cap = nc;
    return 1;
}

static int avm_vfs_put(AvmVM* vm, const char* path, const uint8_t* data, uint32_t len) {
    if (!vm || !path) return 0;
    AvmVfs* v = avm_vfs_get_or_create(vm);
    if (!v) return 0;

    AvmVfsEntry* e = avm_vfs_find(v, path);
    if (!e) {
        if (!avm_vfs_ensure_cap(v, v->count + 1)) return 0;
        e = &v->entries[v->count++];
        e->path = NULL;
        e->data = NULL;
        e->len = 0;

        size_t pl = strlen(path);
        e->path = (char*)avm_heap_malloc_k(pl + 1, AVM_ALLOC_KIND_VFS);
        if (!e->path) return 0;
        memcpy(e->path, path, pl);
        e->path[pl] = 0;
    } else {
        if (e->data) avm_heap_free(e->data);
        e->data = NULL;
        e->len = 0;
    }

    if (len > 0) {
        e->data = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_VFS);
        if (!e->data) return 0;
        memcpy(e->data, data, (size_t)len);
    }
    e->len = len;
    return 1;
}

static int avm_vfs_put_list(AvmVM* vm, const char* path, const AvmList* list) {
    if (!vm || !path) return 0;
    uint32_t len = 0;
    if (list && list->count > 0) len = (uint32_t)list->count;
    // Build a temporary buffer, then store it as file bytes.
    // This is bootstrap-simple and keeps VirtualFS data independent from list lifetime.
    uint8_t* buf = NULL;
    if (len > 0) {
        buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES);
        if (!buf) return 0;
        for (uint32_t i = 0; i < len; i++) {
            int64_t v = 0;
            if (list && list->items && (int)i < list->count) v = list->items[i].as.i;
            buf[i] = (uint8_t)(v & 0xFF);
        }
    }
    int ok = avm_vfs_put(vm, path, buf, len);
    if (buf) avm_heap_free(buf);
    return ok;
}

static int avm_vfs_clone(AvmVM* dst, AvmVM* src) {
    if (!dst) return 0;
    if (!src || !src->vfs) return 1;
    AvmVfs* sv = (AvmVfs*)src->vfs;
    if (!sv || sv->count == 0) return 1;

    for (uint32_t i = 0; i < sv->count; i++) {
        AvmVfsEntry* se = &sv->entries[i];
        const char* path = se->path ? se->path : "";
        const uint8_t* data = se->data;
        uint32_t len = se->len;
        if (!avm_vfs_put(dst, path, data, len)) return 0;
    }
    return 1;
}

// NOTE: legacy `oren_read_bytes` returns LIST<int>, not BYTES. VirtualFS matches that ABI.
static AvmValue avm_vfs_read_bytes_list_value(AvmVM* vm, const uint8_t* data, uint32_t len) {
    AvmValue res;
    res.type = AVM_VAL_NIL;

    AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!list) return avm_alloc_fail_value();
    list->count = (int)len;
    list->capacity = (int)len;
    list->all_int = 1;
    list->items = NULL;
    if (len > 0) {
        list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)len, AVM_ALLOC_KIND_LIST);
        if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
        for (uint32_t i = 0; i < len; i++) {
            list->items[i].type = AVM_VAL_INT;
            list->items[i].as.i = (int64_t)(unsigned char)(data ? data[i] : 0);
        }
    }
    res.type = AVM_VAL_LIST;
    res.as.l = list;
    return res;
}

static AvmValue avm_vfs_read_string_value(AvmVM* vm, const uint8_t* data, uint32_t len) {
    AvmValue res;
    res.type = AVM_VAL_NIL;
    char* s = (char*)avm_heap_malloc_k((size_t)len + 1, AVM_ALLOC_KIND_STRING);
    if (!s) return avm_alloc_fail_value();
    if (len > 0) memcpy(s, data, (size_t)len);
    s[len] = 0;
    res.type = AVM_VAL_STRING;
    res.as.p = s;
    return res;
}
