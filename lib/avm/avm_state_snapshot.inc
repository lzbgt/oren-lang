static int write_u8(FILE* f, uint8_t v);
static int write_u32_le(FILE* f, uint32_t v);
static int write_u64_le(FILE* f, uint64_t v);
static uint32_t read_u32_le(FILE* f, int* ok);
static uint64_t read_u64_le(FILE* f, int* ok);

static AvmValue snap_new_empty_map_value(void) {
    AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
    if (!map) return avm_alloc_fail_value();
    map->keys = NULL;
    map->values = NULL;
    map->count = 0;
    map->capacity = 0;
    AvmValue v;
    v.type = AVM_VAL_MAP;
    v.as.m = map;
    return v;
}

static int snap_write_str(FILE* f, const char* s) {
    if (!f) return 0;
    if (!s) {
        return write_u32_le(f, 0xFFFFFFFFu);
    }
    uint64_t n64 = (uint64_t)strlen(s);
    if (n64 > 0xFFFFFFFEu) return 0;
    uint32_t n = (uint32_t)n64;
    if (!write_u32_le(f, n)) return 0;
    if (n > 0) {
        if (fwrite(s, 1, n, f) != n) return 0;
    }
    return 1;
}

static char* snap_read_str(FILE* f, int* ok) {
    if (!ok) return NULL;
    uint32_t n = read_u32_le(f, ok);
    if (!*ok) return NULL;
    if (n == 0xFFFFFFFFu) return NULL;
    // sanity cap (rolling): prevent hostile snapshots from allocating absurd strings
    if (n > 64u * 1024u * 1024u) { *ok = 0; return NULL; }
    char* s = (char*)avm_heap_malloc_k((size_t)n + 1u, AVM_ALLOC_KIND_TMP);
    if (!s) { *ok = 0; return NULL; }
    if (n > 0) {
        if (fread(s, 1, n, f) != n) { *ok = 0; avm_heap_free(s); return NULL; }
    }
    s[n] = 0;
    return s;
}

static int snap_write_bytes(FILE* f, const uint8_t* data, uint32_t len) {
    if (!write_u32_le(f, len)) return 0;
    if (len > 0) {
        if (fwrite(data, 1, len, f) != len) return 0;
    }
    return 1;
}

static uint8_t* snap_read_bytes(FILE* f, uint32_t* out_len, int* ok) {
    if (!ok) return NULL;
    uint32_t n = read_u32_le(f, ok);
    if (!*ok) return NULL;
    if (out_len) *out_len = n;
    // sanity cap (rolling): 512MB
    if (n > 512u * 1024u * 1024u) { *ok = 0; return NULL; }
    if (n == 0) return NULL;
    uint8_t* buf = (uint8_t*)avm_heap_malloc_k((size_t)n, AVM_ALLOC_KIND_TMP);
    if (!buf) { *ok = 0; return NULL; }
    if (fread(buf, 1, n, f) != n) { *ok = 0; avm_heap_free(buf); return NULL; }
    return buf;
}

int avm_snapshot(AvmVM* vm, const char* path) {
    if (!vm || !vm->prog || !path) return 1;

    // Cooperative tasks/channels (rolling): AVMSNAP9 adds per-task cooperative-cancel state on top
    // of the AVMSNAP8 scheduler snapshot support for runtime task-group registries.

    ObjTable objs = {0};

    // Deterministic root traversal order:
    // - stack (0..sp-1)
    // - globals (0..MAX_GLOBALS-1)
    // - selected result + last_error (for pause/resume parity)
    for (int i = 0; i < vm->sp; i++) collect_value_objects(&objs, vm->stack[i]);
    for (int i = 0; i < MAX_GLOBALS; i++) collect_value_objects(&objs, vm->globals[i]);
    collect_value_objects(&objs, vm->result_value);
    collect_value_objects(&objs, vm->last_error);

    // Closure environments (rolling): required for pause/resume inside functions with captures.
    collect_value_objects(&objs, vm->env);
    for (int i = 0; i < vm->frame_count; i++) collect_value_objects(&objs, vm->frames[i].env);

    // Record/replay in-memory logs (rolling; AVMSNAP5+): needed for deterministic replay and nested universes.
    if (vm->record_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes; collect_value_objects(&objs, v); }
    if (vm->replay_log_bytes) { AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes; collect_value_objects(&objs, v); }

    // Cooperative tasks + channels (rolling; AVMSNAP8+):
    // Snapshot must include all values reachable from other tasks' stacks/envs and from channel queues.
    if (vm->sched) {
        AvmSched* s = (AvmSched*)vm->sched;
        if (s && s->init) {
            int cur = s->current_tid;
            // Tasks
            for (int ti = 0; ti < s->task_cap; ti++) {
                AvmTask* t = &s->tasks[ti];
                if (!t->used) continue;

                // Current task state may be newer in vm registers than in the stored task snapshot.
                if (ti == cur) {
                    collect_value_objects(&objs, vm->env);
                    for (int fi = 0; fi < vm->frame_count; fi++) collect_value_objects(&objs, vm->frames[fi].env);
                    for (int si = 0; si < vm->sp; si++) collect_value_objects(&objs, vm->stack[si]);
                } else {
                    collect_value_objects(&objs, t->env);
                    if (t->frames) {
                        int fc = t->frame_count;
                        if (fc < 0) fc = 0;
                        if (fc > (int)MAX_FRAMES) fc = (int)MAX_FRAMES;
                        for (int fi = 0; fi < fc; fi++) collect_value_objects(&objs, t->frames[fi].env);
                    }
                    if (t->stack) {
                        int sp = t->sp;
                        if (sp < 0) sp = 0;
                        if (sp > (int)AVM_STACK_SIZE) sp = (int)AVM_STACK_SIZE;
                        for (int si = 0; si < sp; si++) collect_value_objects(&objs, t->stack[si]);
                    }
                }

                collect_value_objects(&objs, t->wait_list);
                collect_value_objects(&objs, t->wake_value);
                collect_value_objects(&objs, t->ret);
                collect_value_objects(&objs, t->cancel_reason);
            }

            // Channels: only queued message values are part of the VM semantic heap graph.
            for (int ci = 0; ci < s->chan_cap; ci++) {
                AvmChan* ch = &s->chans[ci];
                if (!ch->used) continue;
                if (ch->q && ch->q_len > 0) {
                    int qn = ch->q_len;
                    if (qn < 0) qn = 0;
                    if (qn > 4096) qn = 4096;
                    for (int qi = 0; qi < qn; qi++) collect_value_objects(&objs, ch->q[qi]);
                }
            }
            collect_value_objects(&objs, s->task_groups);
        }
    }

    FILE* f = fopen(path, "wb");
    if (!f) {
        objtable_free(&objs);
        return 1;
    }

    // Magic (8 bytes)
    const uint8_t magic[8] = {'A','V','M','S','N','A','P','9'};
    if (fwrite(magic, 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }

    if (!write_u32_le(f, (uint32_t)objs.count)) { fclose(f); objtable_free(&objs); return 1; }

    // Object table, ids are 0..count-1 in insertion order (deterministic for a given state).
    for (uint32_t id = 0; id < objs.count; id++) {
        uint8_t t = objs.types[id];
        uint32_t aux = objs.aux[id];
        if (!write_u8(f, t)) { fclose(f); objtable_free(&objs); return 1; }
        if (!write_u32_le(f, aux)) { fclose(f); objtable_free(&objs); return 1; }

        if (t == 1) { // STRING
            if (aux > 0) {
                if (fwrite(objs.ptrs[id], 1, aux, f) != aux) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 2) { // LIST
            AvmList* list = (AvmList*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, list->items[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 10) { // LIST_INT
            AvmListInt* list = (AvmListInt*)objs.ptrs[id];
            if (!list || (uint32_t)list->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, avm_int(list->items[i]))) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_write_object_payload(f, &objs, t, aux, objs.ptrs[id])) { fclose(f); objtable_free(&objs); return 1; }
        } else if (t == 3) { // MAP
            AvmMap* map = (AvmMap*)objs.ptrs[id];
            if (!map || (uint32_t)map->count != aux) { fclose(f); objtable_free(&objs); return 1; }
            for (uint32_t i = 0; i < aux; i++) {
                if (!encode_value(f, &objs, map->keys[i])) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, map->values[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 4) { // BYTES
            AvmBytes* b = (AvmBytes*)objs.ptrs[id];
            if (!b || (uint32_t)b->len != aux) { fclose(f); objtable_free(&objs); return 1; }
            if (aux > 0) {
                if (fwrite(b->data, 1, aux, f) != aux) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else if (t == 5) { // FUNC
            AvmFunc* fn = (AvmFunc*)objs.ptrs[id];
            if (!fn || fn->addr != aux) { fclose(f); objtable_free(&objs); return 1; }
            if (!encode_value(f, &objs, fn->env)) { fclose(f); objtable_free(&objs); return 1; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) { // typed buffers
            AvmBuf* b = (AvmBuf*)objs.ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { fclose(f); objtable_free(&objs); return 1; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fwrite(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { fclose(f); objtable_free(&objs); return 1; }
            }
        } else {
            fclose(f);
            objtable_free(&objs);
            return 1;
        }
    }

    // VM state
    if (!write_u32_le(f, (uint32_t)vm->pc)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->sp)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->fp)) { fclose(f); objtable_free(&objs); return 1; }
    // Current closure environment (rolling; AVMSNAP4+)
    if (!encode_value(f, &objs, vm->env)) { fclose(f); objtable_free(&objs); return 1; }

    if (!write_u32_le(f, (uint32_t)vm->frame_count)) { fclose(f); objtable_free(&objs); return 1; }

    for (int i = 0; i < vm->frame_count; i++) {
        if (!write_u32_le(f, (uint32_t)vm->frames[i].return_pc)) { fclose(f); objtable_free(&objs); return 1; }
        if (!write_u32_le(f, (uint32_t)vm->frames[i].fp)) { fclose(f); objtable_free(&objs); return 1; }
        if (!encode_value(f, &objs, vm->frames[i].env)) { fclose(f); objtable_free(&objs); return 1; }
    }

    for (int i = 0; i < MAX_GLOBALS; i++) {
        if (!encode_value(f, &objs, vm->globals[i])) { fclose(f); objtable_free(&objs); return 1; }
    }
    for (int i = 0; i < vm->sp; i++) {
        if (!encode_value(f, &objs, vm->stack[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // Additional VM state (rolling): selected result + last_error
    if (!write_u8(f, (uint8_t)(vm->has_result_value ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!encode_value(f, &objs, vm->result_value)) { fclose(f); objtable_free(&objs); return 1; }
    if (!encode_value(f, &objs, vm->last_error)) { fclose(f); objtable_free(&objs); return 1; }

    // Deterministic TIME/RNG state (rolling; AVMSNAP3+)
    if (!write_u8(f, (uint8_t)(vm->deterministic ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_now_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_step_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->virtual_sleep_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->rng_state)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->gas_executed)) { fclose(f); objtable_free(&objs); return 1; }

    // Record/replay logs (rolling; AVMSNAP5+)
    if (!write_u8(f, (uint8_t)(vm->record_log_bytes ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (vm->record_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->record_log_bytes;
        if (!encode_value(f, &objs, v)) { fclose(f); objtable_free(&objs); return 1; }
    }
    if (!write_u8(f, (uint8_t)(vm->replay_log_bytes ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (vm->replay_log_bytes) {
        AvmValue v; v.type = AVM_VAL_BYTES; v.as.b = vm->replay_log_bytes;
        if (!encode_value(f, &objs, v)) { fclose(f); objtable_free(&objs); return 1; }
    }
    if (!write_u32_le(f, (uint32_t)vm->replay_log_pos)) { fclose(f); objtable_free(&objs); return 1; }

    // Budgets + counters (rolling; AVMSNAP5+): ensures pause/resume does not widen budgets by accident.
    if (!write_u64_le(f, vm->gas_remaining)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->deadline_ns)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->heap_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->heap_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->io_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->io_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->log_budget_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u64_le(f, vm->log_used_bytes)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u8(f, (uint8_t)(vm->cancelled ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }

    // VM configuration + virtual backends (rolling; AVMSNAP6+)
    if (!write_u64_le(f, vm->allowed_native_domains)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->fs_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->proc_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->net_backend_kind)) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->proc_exit_code)) { fclose(f); objtable_free(&objs); return 1; }

    // Additional VM configuration (rolling; AVMSNAP7+)
    if (!write_u8(f, (uint8_t)(vm->enable_simd ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
    if (!write_u32_le(f, (uint32_t)vm->task_quantum_steps)) { fclose(f); objtable_free(&objs); return 1; }

    // FS allow prefixes
    uint32_t apc = (vm->fs_allow_prefix_count > 0 && vm->fs_allow_prefixes) ? (uint32_t)vm->fs_allow_prefix_count : 0u;
    if (!write_u32_le(f, apc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < apc; i++) {
        if (!snap_write_str(f, vm->fs_allow_prefixes[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // FS mounts (read)
    uint32_t mrc = (vm->fs_mounts_read_count > 0 && vm->fs_mounts_read_virt && vm->fs_mounts_read_host) ? (uint32_t)vm->fs_mounts_read_count : 0u;
    if (!write_u32_le(f, mrc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < mrc; i++) {
        if (!snap_write_str(f, vm->fs_mounts_read_virt[i])) { fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_str(f, vm->fs_mounts_read_host[i])) { fclose(f); objtable_free(&objs); return 1; }
    }
    // FS mounts (write)
    uint32_t mwc = (vm->fs_mounts_write_count > 0 && vm->fs_mounts_write_virt && vm->fs_mounts_write_host) ? (uint32_t)vm->fs_mounts_write_count : 0u;
    if (!write_u32_le(f, mwc)) { fclose(f); objtable_free(&objs); return 1; }
    for (uint32_t i = 0; i < mwc; i++) {
        if (!snap_write_str(f, vm->fs_mounts_write_virt[i])) { fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_str(f, vm->fs_mounts_write_host[i])) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualFS snapshot (AVMVFS01)
    if (vm->vfs) {
        if (fwrite("AVMVFS01", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
        AvmVfs* v = (AvmVfs*)vm->vfs;
        uint32_t cnt = v ? v->count : 0u;
        if (!write_u32_le(f, cnt)) { fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            AvmVfsEntry* e = &v->entries[i];
            if (!snap_write_str(f, e ? e->path : "")) { fclose(f); objtable_free(&objs); return 1; }
            uint32_t bl = e ? e->len : 0u;
            if (!snap_write_bytes(f, e ? e->data : NULL, bl)) { fclose(f); objtable_free(&objs); return 1; }
        }
    } else {
        if (fwrite("AVMVFS00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualPROC fixtures snapshot (AVMPRC01 blob)
    if (vm->vproc) {
        AvmVproc* vp = (AvmVproc*)vm->vproc;
        uint32_t cnt = vp ? vp->count : 0u;
        // Build a fixture blob in memory then write it as length-prefixed bytes.
        AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
        if (!blob) { fclose(f); objtable_free(&objs); return 1; }
        blob->data = NULL; blob->len = 0; blob->capacity = 0;
        uint32_t p = 0;
        if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        const uint8_t magicp[8] = {'A','V','M','P','R','C','0','1'};
        if (!mem_write_bytes(blob, &p, magicp, 8)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!mem_write_u32_le(blob, &p, cnt)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            const char* cmd = vp->entries[i].cmd ? vp->entries[i].cmd : "";
            uint64_t cl64 = (uint64_t)strlen(cmd);
            if (cl64 > 0xFFFFFFFEu) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t cl = (uint32_t)cl64;
            if (!mem_write_u32_le(blob, &p, cl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, (const uint8_t*)cmd, cl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_u32_le(blob, &p, (uint32_t)vp->entries[i].exit_code)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        }
        blob->len = (int)p;
        if (fwrite("AVMPRC1B", 1, 8, f) != 8) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_bytes(f, blob->data, (uint32_t)blob->len)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (blob->data) avm_heap_free(blob->data);
        avm_heap_free(blob);
    } else {
        if (fwrite("AVMPRC0B", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // VirtualNET fixtures snapshot (AVMNET01 blob)
    if (vm->vnet) {
        AvmVnet* vn = (AvmVnet*)vm->vnet;
        uint32_t cnt = vn ? vn->count : 0u;
        AvmBytes* blob = (AvmBytes*)avm_heap_malloc_k(sizeof(AvmBytes), AVM_ALLOC_KIND_TMP);
        if (!blob) { fclose(f); objtable_free(&objs); return 1; }
        blob->data = NULL; blob->len = 0; blob->capacity = 0;
        uint32_t p = 0;
        if (!bytes_ensure_cap(blob, 12)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        const uint8_t magicn[8] = {'A','V','M','N','E','T','0','1'};
        if (!mem_write_bytes(blob, &p, magicn, 8)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!mem_write_u32_le(blob, &p, cnt)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        for (uint32_t i = 0; i < cnt; i++) {
            const char* url = vn->entries[i].url ? vn->entries[i].url : "";
            uint64_t ul64 = (uint64_t)strlen(url);
            if (ul64 > 0xFFFFFFFEu) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t ul = (uint32_t)ul64;
            if (!mem_write_u32_le(blob, &p, ul)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, (const uint8_t*)url, ul)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            uint32_t bl = vn->entries[i].body_len;
            if (!mem_write_u32_le(blob, &p, bl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
            if (!mem_write_bytes(blob, &p, vn->entries[i].body, bl)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        }
        blob->len = (int)p;
        if (fwrite("AVMNET1B", 1, 8, f) != 8) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (!snap_write_bytes(f, blob->data, (uint32_t)blob->len)) { avm_heap_free(blob); fclose(f); objtable_free(&objs); return 1; }
        if (blob->data) avm_heap_free(blob->data);
        avm_heap_free(blob);
    } else {
        if (fwrite("AVMNET0B", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    // Scheduler snapshot (rolling; AVMSNAP9+): tasks + channels + runtime task groups, plus
    // per-task cooperative-cancel state.
    //
    // Layout: tagged chunk appended at end so older readers can ignore (they won't accept AVMSNAP8 anyway).
    if (vm->sched) {
        AvmSched* s = (AvmSched*)vm->sched;
        if (!s || !s->init) {
            if (fwrite("AVMSCH00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
        } else {
            if (fwrite("AVMSCH01", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }

            // Header
            if (!write_u32_le(f, (uint32_t)s->current_tid)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->quantum_steps)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->task_cap)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->task_count)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->ready_len)) { fclose(f); objtable_free(&objs); return 1; }
            for (int i = 0; i < s->ready_len; i++) {
                int idx = s->ready_head + i;
                if (idx >= s->ready_cap) idx -= s->ready_cap;
                if (!write_u32_le(f, (uint32_t)s->ready[idx])) { fclose(f); objtable_free(&objs); return 1; }
            }
            if (!write_u32_le(f, (uint32_t)s->select_len)) { fclose(f); objtable_free(&objs); return 1; }
            for (int i = 0; i < s->select_len; i++) {
                if (!write_u32_le(f, (uint32_t)s->select_waiters[i])) { fclose(f); objtable_free(&objs); return 1; }
            }
            if (!write_u32_le(f, (uint32_t)s->chan_cap)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u32_le(f, (uint32_t)s->chan_count)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u64_le(f, (uint64_t)s->next_chan_id)) { fclose(f); objtable_free(&objs); return 1; }
            if (!write_u64_le(f, (uint64_t)s->next_task_group_id)) { fclose(f); objtable_free(&objs); return 1; }
            if (!encode_value(f, &objs, s->task_groups)) { fclose(f); objtable_free(&objs); return 1; }

            int cur = s->current_tid;

            // Tasks
            for (int ti = 0; ti < s->task_cap; ti++) {
                AvmTask* t = &s->tasks[ti];
                if (!write_u8(f, (uint8_t)(t->used ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!t->used) continue;

                if (!write_u8(f, (uint8_t)(t->done ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u8(f, (uint8_t)(t->blocked ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u8(f, (uint8_t)(t->cancel_requested ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_kind)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_id)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->wait_chan)) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->wait_list)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u64_le(f, t->join_deadline_ns)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u8(f, (uint8_t)(t->wake_pending ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->wake_value)) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->cancel_reason)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->slice_remaining)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)t->select_cursor)) { fclose(f); objtable_free(&objs); return 1; }

                // Task machine state: for the current task, prefer the live vm registers.
                int pc = t->pc;
                int sp = t->sp;
                int fp = t->fp;
                int fc = t->frame_count;
                AvmValue env = t->env;
                AvmValue* stack = t->stack;
                AvmFrame* frames = t->frames;
                if (ti == cur) {
                    pc = vm->pc;
                    sp = vm->sp;
                    fp = vm->fp;
                    fc = vm->frame_count;
                    env = vm->env;
                    stack = vm->stack;
                    frames = vm->frames;
                }
                if (sp < 0) sp = 0;
                if (sp > (int)AVM_STACK_SIZE) sp = (int)AVM_STACK_SIZE;
                if (fc < 0) fc = 0;
                if (fc > (int)MAX_FRAMES) fc = (int)MAX_FRAMES;

                if (!write_u32_le(f, (uint32_t)pc)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)sp)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)fp)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)fc)) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, env)) { fclose(f); objtable_free(&objs); return 1; }

                for (int fi = 0; fi < fc; fi++) {
                    int rpc = 0;
                    int fpp = 0;
                    AvmValue fenv = avm_nil();
                    if (frames) {
                        rpc = frames[fi].return_pc;
                        fpp = frames[fi].fp;
                        fenv = frames[fi].env;
                    }
                    if (!write_u32_le(f, (uint32_t)rpc)) { fclose(f); objtable_free(&objs); return 1; }
                    if (!write_u32_le(f, (uint32_t)fpp)) { fclose(f); objtable_free(&objs); return 1; }
                    if (!encode_value(f, &objs, fenv)) { fclose(f); objtable_free(&objs); return 1; }
                }

                for (int si = 0; si < sp; si++) {
                    AvmValue sv = avm_nil();
                    if (stack) sv = stack[si];
                    if (!encode_value(f, &objs, sv)) { fclose(f); objtable_free(&objs); return 1; }
                }

                if (!write_u8(f, (uint8_t)(t->has_ret ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!encode_value(f, &objs, t->ret)) { fclose(f); objtable_free(&objs); return 1; }
            }

            // Channels
            for (int ci = 0; ci < s->chan_cap; ci++) {
                AvmChan* ch = &s->chans[ci];
                if (!write_u8(f, (uint8_t)(ch->used ? 1 : 0))) { fclose(f); objtable_free(&objs); return 1; }
                if (!ch->used) continue;
                if (!write_u64_le(f, (uint64_t)ch->id)) { fclose(f); objtable_free(&objs); return 1; }
                if (!write_u32_le(f, (uint32_t)ch->recv_count)) { fclose(f); objtable_free(&objs); return 1; }
                for (int wi = 0; wi < ch->recv_count; wi++) {
                    if (!write_u32_le(f, (uint32_t)ch->recv_waiters[wi])) { fclose(f); objtable_free(&objs); return 1; }
                }
                if (!write_u32_le(f, (uint32_t)ch->q_len)) { fclose(f); objtable_free(&objs); return 1; }
                for (int qi = 0; qi < ch->q_len; qi++) {
                    if (!encode_value(f, &objs, ch->q[qi])) { fclose(f); objtable_free(&objs); return 1; }
                }
            }
        }
    } else {
        if (fwrite("AVMSCH00", 1, 8, f) != 8) { fclose(f); objtable_free(&objs); return 1; }
    }

    fclose(f);
    objtable_free(&objs);
    return 0;
}

int avm_restore(AvmVM* vm, const char* path) {
    if (!vm || !vm->prog || !path) return 1;

    FILE* f = fopen(path, "rb");
    if (!f) return 1;

    uint8_t magic[8];
    if (fread(magic, 1, 8, f) != 8) { fclose(f); return 1; }
    const uint8_t want2[8] = {'A','V','M','S','N','A','P','2'};
    const uint8_t want3[8] = {'A','V','M','S','N','A','P','3'};
    const uint8_t want4[8] = {'A','V','M','S','N','A','P','4'};
    const uint8_t want5[8] = {'A','V','M','S','N','A','P','5'};
    const uint8_t want6[8] = {'A','V','M','S','N','A','P','6'};
    const uint8_t want7[8] = {'A','V','M','S','N','A','P','7'};
    const uint8_t want8[8] = {'A','V','M','S','N','A','P','8'};
    const uint8_t want9[8] = {'A','V','M','S','N','A','P','9'};
    int snap_ver = 0;
    if (memcmp(magic, want2, 8) == 0) snap_ver = 2;
    if (memcmp(magic, want3, 8) == 0) snap_ver = 3;
    if (memcmp(magic, want4, 8) == 0) snap_ver = 4;
    if (memcmp(magic, want5, 8) == 0) snap_ver = 5;
    if (memcmp(magic, want6, 8) == 0) snap_ver = 6;
    if (memcmp(magic, want7, 8) == 0) snap_ver = 7;
    if (memcmp(magic, want8, 8) == 0) snap_ver = 8;
    if (memcmp(magic, want9, 8) == 0) snap_ver = 9;
    if (snap_ver == 0) { fclose(f); return 1; }

    int ok = 1;
    uint32_t obj_count = read_u32_le(f, &ok);
    if (!ok) { fclose(f); return 1; }
    if (obj_count > 1000000) { fclose(f); return 1; } // sanity cap

    uint8_t* obj_types = NULL;
    uint32_t* obj_aux = NULL;
    uint64_t* payload_off = NULL;
    void** obj_ptrs = NULL;

    obj_types = (uint8_t*)calloc(obj_count, 1);
    obj_aux = (uint32_t*)calloc(obj_count, sizeof(uint32_t));
    payload_off = (uint64_t*)calloc(obj_count, sizeof(uint64_t));
    obj_ptrs = (void**)calloc(obj_count, sizeof(void*));
    if (!obj_types || !obj_aux || !payload_off || !obj_ptrs) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 1: read headers, record payload offsets, skip payloads
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        if (fread(&t, 1, 1, f) != 1) { ok = 0; break; }
        uint32_t aux = read_u32_le(f, &ok);
        if (!ok) break;

        obj_types[id] = t;
        obj_aux[id] = aux;
        payload_off[id] = (uint64_t)ftell(f);

        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 10 || t == 11 || t == 12) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
        else { ok = 0; break; }

        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    if (!ok) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 2: allocate objects based on headers (so references can resolve)
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            char* s = (char*)malloc((size_t)aux + 1);
            if (!s) { ok = 0; break; }
            s[aux] = 0;
            obj_ptrs[id] = s;
        } else if (t == 2) {
            AvmList* list = (AvmList*)malloc(sizeof(AvmList));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->all_int = 1;
            list->items = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if (!list->items && aux > 0) { free(list); ok = 0; break; }
            obj_ptrs[id] = list;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)malloc(sizeof(AvmListInt));
            if (!list) { ok = 0; break; }
            list->count = (int)aux;
            list->capacity = (int)aux;
            list->items = NULL;
            if (aux > 0) {
                list->items = (int64_t*)malloc(sizeof(int64_t) * (size_t)aux);
                if (!list->items) { free(list); ok = 0; break; }
            }
            obj_ptrs[id] = list;
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_alloc_object(t, aux, &obj_ptrs[id])) { ok = 0; break; }
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
            if (!map) { ok = 0; break; }
            map->count = (int)aux;
            map->capacity = (int)aux;
            map->keys = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            map->values = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)aux);
            if ((!map->keys || !map->values) && aux > 0) {
                if (map->keys) free(map->keys);
                if (map->values) free(map->values);
                free(map);
                ok = 0;
                break;
            }
            obj_ptrs[id] = map;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) { ok = 0; break; }
            b->len = (int)aux;
            b->capacity = (int)aux;
            b->data = NULL;
            if (aux > 0) {
                b->data = (uint8_t*)malloc((size_t)aux);
                if (!b->data) { free(b); ok = 0; break; }
            }
            obj_ptrs[id] = b;
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)malloc(sizeof(AvmFunc));
            if (!fn) { ok = 0; break; }
            fn->addr = aux;
            fn->env.type = AVM_VAL_NIL;
            fn->env.as.i = 0;
            obj_ptrs[id] = fn;
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)malloc(sizeof(AvmBuf));
            if (!b) { ok = 0; break; }
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            b->len = aux;
            b->elem_size = elem;
            b->data = NULL;
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                b->data = (uint8_t*)malloc((size_t)bytes_len);
                if (!b->data) { free(b); ok = 0; break; }
            }
            obj_ptrs[id] = b;
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        fclose(f);
        for (uint32_t i = 0; i < obj_count; i++) if (obj_ptrs[i]) free(obj_ptrs[i]);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Pass 3: fill payloads
    for (uint32_t id = 0; id < obj_count; id++) {
        if (fseek(f, (long)payload_off[id], SEEK_SET) != 0) { ok = 0; break; }
        uint8_t t = obj_types[id];
        uint32_t aux = obj_aux[id];
        if (t == 1) {
            if (aux > 0) {
                if (fread(obj_ptrs[id], 1, aux, f) != aux) { ok = 0; break; }
            }
            ((char*)obj_ptrs[id])[aux] = 0;
        } else if (t == 2) {
            AvmList* list = (AvmList*)obj_ptrs[id];
            list->all_int = 1;
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &list->items[i])) { ok = 0; break; }
                if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
            }
            if (!ok) break;
        } else if (t == 10) {
            AvmListInt* list = (AvmListInt*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                AvmValue v;
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { ok = 0; break; }
                if (v.type != AVM_VAL_INT) { ok = 0; break; }
                list->items[i] = v.as.i;
            }
            if (!ok) break;
        } else if (avm_generator_object_type(t)) {
            if (!avm_generator_fill_object_file(f, obj_types, obj_ptrs, obj_count, t, aux, obj_ptrs[id])) { ok = 0; break; }
        } else if (t == 3) {
            AvmMap* map = (AvmMap*)obj_ptrs[id];
            for (uint32_t i = 0; i < aux; i++) {
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->keys[i])) { ok = 0; break; }
                if (!decode_value(f, obj_types, obj_ptrs, obj_count, &map->values[i])) { ok = 0; break; }
            }
            if (!ok) break;
        } else if (t == 4) {
            AvmBytes* b = (AvmBytes*)obj_ptrs[id];
            if (!b || (uint32_t)b->len != aux) { ok = 0; break; }
            if (aux > 0) {
                if (fread(b->data, 1, aux, f) != aux) { ok = 0; break; }
            }
        } else if (t == 5) {
            AvmFunc* fn = (AvmFunc*)obj_ptrs[id];
            if (!fn || fn->addr != aux) { ok = 0; break; }
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &fn->env)) { ok = 0; break; }
        } else if (t == 6 || t == 7 || t == 8 || t == 9) {
            AvmBuf* b = (AvmBuf*)obj_ptrs[id];
            uint32_t elem = (t == 6 || t == 8) ? 4u : 8u;
            if (!b || b->len != aux || b->elem_size != elem) { ok = 0; break; }
            uint64_t bytes_len = (uint64_t)aux * (uint64_t)elem;
            if (bytes_len > 0) {
                if (fread(b->data, 1, (size_t)bytes_len, f) != (size_t)bytes_len) { ok = 0; break; }
            }
        } else {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        fclose(f);
        free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
        return 1;
    }

    // Seek to VM state (end of object table). We are currently positioned at last payload end; compute by seeking:
    // easiest: after pass1 we left file position at end of object table; store it.
    // Instead, re-run pass1 cursor quickly here by seeking after magic+count.
    if (fseek(f, 8 + 4, SEEK_SET) != 0) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    for (uint32_t id = 0; id < obj_count; id++) {
        uint8_t t = 0;
        if (fread(&t, 1, 1, f) != 1) { ok = 0; break; }
        uint32_t aux = read_u32_le(f, &ok);
        if (!ok) break;
        uint64_t payload_len = 0;
        if (t == 1) payload_len = aux;
        else if (t == 2) payload_len = (uint64_t)aux * 9ull;
        else if (t == 3) payload_len = (uint64_t)aux * 2ull * 9ull;
        else if (t == 10 || t == 11 || t == 12) payload_len = (uint64_t)aux * 9ull;
        else if (t == 4) payload_len = aux;
        else if (t == 5) payload_len = 9ull;
        else if (t == 6 || t == 8) payload_len = (uint64_t)aux * 4ull;
        else if (t == 7 || t == 9) payload_len = (uint64_t)aux * 8ull;
        else { ok = 0; break; }
        if (fseek(f, (long)payload_len, SEEK_CUR) != 0) { ok = 0; break; }
    }
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    // Read VM state
    uint32_t pc = read_u32_le(f, &ok);
    uint32_t sp = read_u32_le(f, &ok);
    uint32_t fp = read_u32_le(f, &ok);

    // Current closure environment (rolling; AVMSNAP4+).
    if (snap_ver >= 4) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->env)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    } else {
        vm->env.type = AVM_VAL_NIL;
        vm->env.as.i = 0;
    }

    uint32_t frame_count = read_u32_le(f, &ok);
    if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (frame_count > MAX_FRAMES) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (sp > AVM_STACK_SIZE) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (pc > vm->prog->code_len) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    vm->pc = (int)pc;
    vm->sp = (int)sp;
    vm->fp = (int)fp;
    vm->frame_count = (int)frame_count;
    {
        uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
        if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
        if (frame_count > fl) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }

    for (uint32_t i = 0; i < frame_count; i++) {
        uint32_t rpc = read_u32_le(f, &ok);
        uint32_t fpp = read_u32_le(f, &ok);
        if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->frames[i].return_pc = (int)rpc;
        vm->frames[i].fp = (int)fpp;
        if (snap_ver >= 4) {
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->frames[i].env)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        } else {
            vm->frames[i].env.type = AVM_VAL_NIL;
            vm->frames[i].env.as.i = 0;
        }
    }

    for (int i = 0; i < MAX_GLOBALS; i++) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->globals[i])) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }
    for (uint32_t i = 0; i < sp; i++) {
        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->stack[i])) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    }

    // Additional VM state (rolling): selected result + last_error
    uint8_t has_res = 0;
    if (fread(&has_res, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    vm->has_result_value = (has_res != 0) ? 1 : 0;
    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->result_value)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &vm->last_error)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

    // Deterministic TIME/RNG state (rolling; AVMSNAP3+)
    if (snap_ver >= 3) {
        uint8_t det = 0;
        if (fread(&det, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->deterministic = (det != 0) ? 1 : 0;
        int ok2 = 1;
        vm->virtual_now_ns = read_u64_le(f, &ok2);
        vm->virtual_step_ns = read_u64_le(f, &ok2);
        vm->virtual_sleep_ns = read_u64_le(f, &ok2);
        vm->rng_state = read_u64_le(f, &ok2);
        vm->gas_executed = read_u64_le(f, &ok2);
        if (!ok2) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
    } else {
        // AVMSNAP2 did not capture deterministic state; reset rolling fields.
        vm->virtual_sleep_ns = 0;
        vm->gas_executed = 0;
    }

    // Record/replay logs + budgets (rolling; AVMSNAP5+)
    if (snap_ver >= 5) {
        uint8_t has_rec = 0;
        if (fread(&has_rec, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->record_log_bytes = NULL;
        if (has_rec) {
            AvmValue v = avm_nil();
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (v.type != AVM_VAL_BYTES || !v.as.b) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->record_log_bytes = v.as.b;
        }

        uint8_t has_rep = 0;
        if (fread(&has_rep, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->replay_log_bytes = NULL;
        if (has_rep) {
            AvmValue v = avm_nil();
            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &v)) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (v.type != AVM_VAL_BYTES || !v.as.b) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->replay_log_bytes = v.as.b;
        }

        uint32_t rpos = read_u32_le(f, &ok);
        if (!ok) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->replay_log_pos = rpos;

        int ok3 = 1;
        vm->gas_remaining = read_u64_le(f, &ok3);
        vm->deadline_ns = read_u64_le(f, &ok3);
        vm->heap_budget_bytes = read_u64_le(f, &ok3);
        vm->heap_used_bytes = read_u64_le(f, &ok3);
        vm->io_budget_bytes = read_u64_le(f, &ok3);
        vm->io_used_bytes = read_u64_le(f, &ok3);
        vm->log_budget_bytes = read_u64_le(f, &ok3);
        vm->log_used_bytes = read_u64_le(f, &ok3);
        if (!ok3) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        uint8_t cancelled = 0;
        if (fread(&cancelled, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->cancelled = cancelled ? 1 : 0;
    }

    // VM configuration + virtual backends (rolling; AVMSNAP6+)
    if (snap_ver >= 6) {
        int okc = 1;
        vm->allowed_native_domains = read_u64_le(f, &okc);
        uint32_t fs_kind = read_u32_le(f, &okc);
        uint32_t proc_kind = read_u32_le(f, &okc);
        uint32_t net_kind = read_u32_le(f, &okc);
        uint32_t proc_ec = read_u32_le(f, &okc);
        if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_backend_kind = (int)fs_kind;
        vm->proc_backend_kind = (int)proc_kind;
        vm->net_backend_kind = (int)net_kind;
        vm->proc_exit_code = (int)proc_ec;

        // Additional VM configuration (rolling; AVMSNAP7+)
        if (snap_ver >= 7) {
            uint8_t en_simd = 0;
            if (fread(&en_simd, 1, 1, f) != 1) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->enable_simd = (en_simd != 0) ? 1 : 0;
            uint32_t tq = read_u32_le(f, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            vm->task_quantum_steps = tq;
        }

        // FS allow prefixes
        uint32_t apc = read_u32_le(f, &okc);
        if (!okc || apc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_allow_prefix_count = 0;
        vm->fs_allow_prefixes = NULL;
        if (apc > 0) {
            vm->fs_allow_prefixes = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)apc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_allow_prefixes) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < apc; i++) vm->fs_allow_prefixes[i] = NULL;
            for (uint32_t i = 0; i < apc; i++) {
                char* s = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                vm->fs_allow_prefixes[i] = s ? s : (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP);
                if (!vm->fs_allow_prefixes[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!s) vm->fs_allow_prefixes[i][0] = 0;
            }
            vm->fs_allow_prefix_count = (int)apc;
        }

        // FS mounts (read)
        uint32_t mrc = read_u32_le(f, &okc);
        if (!okc || mrc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_mounts_read_count = 0;
        vm->fs_mounts_read_virt = NULL;
        vm->fs_mounts_read_host = NULL;
        if (mrc > 0) {
            vm->fs_mounts_read_virt = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mrc, AVM_ALLOC_KIND_TMP);
            vm->fs_mounts_read_host = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mrc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_mounts_read_virt || !vm->fs_mounts_read_host) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < mrc; i++) { vm->fs_mounts_read_virt[i] = NULL; vm->fs_mounts_read_host[i] = NULL; }
            for (uint32_t i = 0; i < mrc; i++) {
                vm->fs_mounts_read_virt[i] = snap_read_str(f, &okc);
                vm->fs_mounts_read_host[i] = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!vm->fs_mounts_read_virt[i]) { vm->fs_mounts_read_virt[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_read_virt[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_read_virt[i][0]=0; }
                if (!vm->fs_mounts_read_host[i]) { vm->fs_mounts_read_host[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_read_host[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_read_host[i][0]=0; }
            }
            vm->fs_mounts_read_count = (int)mrc;
        }

        // FS mounts (write)
        uint32_t mwc = read_u32_le(f, &okc);
        if (!okc || mwc > 100000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        vm->fs_mounts_write_count = 0;
        vm->fs_mounts_write_virt = NULL;
        vm->fs_mounts_write_host = NULL;
        if (mwc > 0) {
            vm->fs_mounts_write_virt = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mwc, AVM_ALLOC_KIND_TMP);
            vm->fs_mounts_write_host = (char**)avm_heap_malloc_k(sizeof(char*) * (size_t)mwc, AVM_ALLOC_KIND_TMP);
            if (!vm->fs_mounts_write_virt || !vm->fs_mounts_write_host) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            for (uint32_t i = 0; i < mwc; i++) { vm->fs_mounts_write_virt[i] = NULL; vm->fs_mounts_write_host[i] = NULL; }
            for (uint32_t i = 0; i < mwc; i++) {
                vm->fs_mounts_write_virt[i] = snap_read_str(f, &okc);
                vm->fs_mounts_write_host[i] = snap_read_str(f, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!vm->fs_mounts_write_virt[i]) { vm->fs_mounts_write_virt[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_write_virt[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_write_virt[i][0]=0; }
                if (!vm->fs_mounts_write_host[i]) { vm->fs_mounts_write_host[i] = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_TMP); if (!vm->fs_mounts_write_host[i]) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } vm->fs_mounts_write_host[i][0]=0; }
            }
            vm->fs_mounts_write_count = (int)mwc;
        }

        // VirtualFS blob
        char tag[8];
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMVFS01", 8) == 0) {
            uint32_t cnt = read_u32_le(f, &okc);
            if (!okc || cnt > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            AvmVfs* v = (AvmVfs*)avm_heap_malloc_k(sizeof(AvmVfs), AVM_ALLOC_KIND_VFS);
            if (!v) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            v->entries = NULL;
            v->count = cnt;
            v->cap = cnt;
            if (cnt > 0) {
                v->entries = (AvmVfsEntry*)avm_heap_malloc_k(sizeof(AvmVfsEntry) * (size_t)cnt, AVM_ALLOC_KIND_VFS);
                if (!v->entries) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                for (uint32_t i = 0; i < cnt; i++) { v->entries[i].path = NULL; v->entries[i].data = NULL; v->entries[i].len = 0; }
            }
            for (uint32_t i = 0; i < cnt; i++) {
                char* path = snap_read_str(f, &okc);
                uint32_t bl = 0;
                uint8_t* data = snap_read_bytes(f, &bl, &okc);
                if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (!path) { path = (char*)avm_heap_malloc_k(1, AVM_ALLOC_KIND_VFS); if (!path) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; } path[0] = 0; }
                uint8_t* body = NULL;
                if (bl > 0) {
                    body = (uint8_t*)avm_heap_malloc_k((size_t)bl, AVM_ALLOC_KIND_VFS);
                    if (!body) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    memcpy(body, data, bl);
                }
                if (data) avm_heap_free(data);
                v->entries[i].path = path;
                v->entries[i].data = body;
                v->entries[i].len = bl;
            }
            vm->vfs = v;
        } else if (memcmp(tag, "AVMVFS00", 8) == 0) {
            vm->vfs = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // VirtualPROC fixtures blob
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMPRC1B", 8) == 0) {
            uint32_t bl = 0;
            uint8_t* buf = snap_read_bytes(f, &bl, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (bl > 0 && buf) {
                (void)avm_proc_load_fixtures(vm, buf, (size_t)bl);
            }
            if (buf) avm_heap_free(buf);
        } else if (memcmp(tag, "AVMPRC0B", 8) == 0) {
            vm->vproc = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // VirtualNET fixtures blob
        if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
        if (memcmp(tag, "AVMNET1B", 8) == 0) {
            uint32_t bl = 0;
            uint8_t* buf = snap_read_bytes(f, &bl, &okc);
            if (!okc) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (bl > 0 && buf) {
                (void)avm_net_load_fixtures(vm, buf, (size_t)bl);
            }
            if (buf) avm_heap_free(buf);
        } else if (memcmp(tag, "AVMNET0B", 8) == 0) {
            vm->vnet = NULL;
        } else {
            fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
        }

        // Scheduler chunk (rolling; AVMSNAP7+; runtime task groups added in AVMSNAP8,
        // per-task cooperative cancel state added in AVMSNAP9)
        if (snap_ver >= 7) {
            if (fread(tag, 1, 8, f) != 8) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
            if (memcmp(tag, "AVMSCH00", 8) == 0) {
                vm->sched = NULL;
                vm->stack = vm->stack_base;
            } else if (memcmp(tag, "AVMSCH01", 8) == 0) {
                int oks = 1;
                uint32_t cur_tid = read_u32_le(f, &oks);
                uint32_t quantum_steps = read_u32_le(f, &oks);
                uint32_t task_cap = read_u32_le(f, &oks);
                uint32_t task_count = read_u32_le(f, &oks);
                uint32_t ready_len = read_u32_le(f, &oks);
                if (!oks) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (task_cap == 0 || task_cap > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (task_count > task_cap) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (ready_len > 1000000u) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

                uint32_t* ready = NULL;
                if (ready_len > 0) {
                    ready = (uint32_t*)calloc(ready_len, sizeof(uint32_t));
                    if (!ready) { fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    for (uint32_t i = 0; i < ready_len; i++) ready[i] = read_u32_le(f, &oks);
                    if (!oks) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                }

                uint32_t select_len = read_u32_le(f, &oks);
                if (!oks || select_len > 1000000u) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                uint32_t* select_waiters = NULL;
                if (select_len > 0) {
                    select_waiters = (uint32_t*)calloc(select_len, sizeof(uint32_t));
                    if (!select_waiters) { fclose(f); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                    for (uint32_t i = 0; i < select_len; i++) select_waiters[i] = read_u32_le(f, &oks);
                    if (!oks) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                }

                uint32_t chan_cap = read_u32_le(f, &oks);
                uint32_t chan_count = read_u32_le(f, &oks);
                uint64_t next_chan_id_u64 = read_u64_le(f, &oks);
                uint64_t next_task_group_id_u64 = 0;
                if (snap_ver >= 8) next_task_group_id_u64 = read_u64_le(f, &oks);
                if (!oks) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (chan_cap > 1000000u) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                if (chan_cap > 0 && chan_count > chan_cap) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }

                // Create scheduler
                AvmSched* s = (AvmSched*)calloc(1, sizeof(AvmSched));
                if (!s) { fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1; }
                s->init = 1;
                s->current_tid = (int)cur_tid;
                s->quantum_steps = (int)quantum_steps;
                s->task_cap = (int)task_cap;
                s->task_count = (int)task_count;
                s->ready = NULL;
                s->ready_len = (int)ready_len;
                s->ready_cap = (int)ready_len;
                s->ready_head = 0;
                s->select_waiters = NULL;
                s->select_len = (int)select_len;
                s->select_cap = (int)select_len;
                s->chan_cap = (int)chan_cap;
                s->chan_count = (int)chan_count;
                s->next_chan_id = (int64_t)next_chan_id_u64;
                s->next_task_group_id = (snap_ver >= 8) ? (int64_t)next_task_group_id_u64 : INT64_C(-900000000000000000);
                s->task_groups = avm_nil();

                s->tasks = (AvmTask*)calloc((size_t)s->task_cap, sizeof(AvmTask));
                if (!s->tasks) {
                    free(s);
                    fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                if (s->chan_cap > 0) {
                    s->chans = (AvmChan*)calloc((size_t)s->chan_cap, sizeof(AvmChan));
                    if (!s->chans) {
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                } else {
                    s->chans = NULL;
                }

                if (ready_len > 0) {
                    s->ready = (int*)calloc(ready_len, sizeof(int));
                    if (!s->ready) {
                        free(s->chans);
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    for (uint32_t i = 0; i < ready_len; i++) s->ready[i] = (int)ready[i];
                }
                if (select_len > 0) {
                    s->select_waiters = (int*)calloc(select_len, sizeof(int));
                    if (!s->select_waiters) {
                        if (s->ready) free(s->ready);
                        free(s->chans);
                        free(s->tasks);
                        free(s);
                        fclose(f); free(select_waiters); free(ready); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    for (uint32_t i = 0; i < select_len; i++) s->select_waiters[i] = (int)select_waiters[i];
                }
                free(select_waiters);
                free(ready);

                if (snap_ver >= 8) {
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &s->task_groups)) {
                        oks = 0;
                    }
                    if (!oks || s->task_groups.type != AVM_VAL_MAP || !s->task_groups.as.m) {
                        oks = 0;
                    }
                } else {
                    s->task_groups = snap_new_empty_map_value();
                    if (s->task_groups.type != AVM_VAL_MAP || !s->task_groups.as.m) {
                        oks = 0;
                    }
                }

                // Tasks
                for (int ti = 0; ti < s->task_cap; ti++) {
                    uint8_t used = 0;
                    if (fread(&used, 1, 1, f) != 1) { oks = 0; break; }
                    if (!used) {
                        s->tasks[ti].used = 0;
                        continue;
                    }
                    AvmTask* t = &s->tasks[ti];
                    memset(t, 0, sizeof(*t));
                    t->used = 1;
                    uint8_t done = 0, blocked = 0;
                    if (fread(&done, 1, 1, f) != 1) { oks = 0; break; }
                    if (fread(&blocked, 1, 1, f) != 1) { oks = 0; break; }
                    t->done = done ? 1 : 0;
                    t->blocked = blocked ? 1 : 0;
                    if (snap_ver >= 9) {
                        uint8_t cancel_requested = 0;
                        if (fread(&cancel_requested, 1, 1, f) != 1) { oks = 0; break; }
                        t->cancel_requested = cancel_requested ? 1 : 0;
                    } else {
                        t->cancel_requested = 0;
                    }
                    t->wait_kind = (int)read_u32_le(f, &oks);
                    t->wait_id = (int)read_u32_le(f, &oks);
                    t->wait_chan = (int)read_u32_le(f, &oks);
                    if (!oks) break;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->wait_list)) { oks = 0; break; }
                    t->join_deadline_ns = read_u64_le(f, &oks);
                    if (!oks) break;
                    uint8_t wakep = 0;
                    if (fread(&wakep, 1, 1, f) != 1) { oks = 0; break; }
                    t->wake_pending = wakep ? 1 : 0;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->wake_value)) { oks = 0; break; }
                    if (snap_ver >= 9) {
                        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->cancel_reason)) { oks = 0; break; }
                    } else {
                        t->cancel_reason = avm_nil();
                    }
                    t->slice_remaining = (int)read_u32_le(f, &oks);
                    t->select_cursor = (int)read_u32_le(f, &oks);
                    if (!oks) break;

                    t->pc = (int)read_u32_le(f, &oks);
                    t->sp = (int)read_u32_le(f, &oks);
                    t->fp = (int)read_u32_le(f, &oks);
                    t->frame_count = (int)read_u32_le(f, &oks);
                    if (!oks) break;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->env)) { oks = 0; break; }

                    if (t->sp < 0) t->sp = 0;
                    if (t->sp > (int)AVM_STACK_SIZE) t->sp = (int)AVM_STACK_SIZE;
                    if (t->frame_count < 0) t->frame_count = 0;
                    if (t->frame_count > (int)MAX_FRAMES) t->frame_count = (int)MAX_FRAMES;

                    // Allocate task stack + frames.
                    if (ti == 0) {
                        t->stack = vm->stack_base;
                    } else {
                        t->stack = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)AVM_STACK_SIZE);
                        if (!t->stack) { oks = 0; break; }
                    }
                    t->frames = (AvmFrame*)malloc(sizeof(AvmFrame) * (size_t)MAX_FRAMES);
                    if (!t->frames) { oks = 0; break; }
                    memset(t->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

                    for (int fi = 0; fi < t->frame_count; fi++) {
                        uint32_t rpc = read_u32_le(f, &oks);
                        uint32_t fpp = read_u32_le(f, &oks);
                        if (!oks) break;
                        t->frames[fi].return_pc = (int)rpc;
                        t->frames[fi].fp = (int)fpp;
                        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->frames[fi].env)) { oks = 0; break; }
                    }
                    if (!oks) break;

                    for (int si = 0; si < t->sp; si++) {
                        if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->stack[si])) { oks = 0; break; }
                    }
                    if (!oks) break;

                    uint8_t has_ret = 0;
                    if (fread(&has_ret, 1, 1, f) != 1) { oks = 0; break; }
                    t->has_ret = has_ret ? 1 : 0;
                    if (!decode_value(f, obj_types, obj_ptrs, obj_count, &t->ret)) { oks = 0; break; }
                }
                if (!oks) {
                    // Best-effort cleanup on parse failure.
                    if (s->tasks) {
                        for (int i = 0; i < s->task_cap; i++) {
                            if (!s->tasks[i].used) continue;
                            if (s->tasks[i].frames) free(s->tasks[i].frames);
                            if (i != 0 && s->tasks[i].stack) free(s->tasks[i].stack);
                        }
                    }
                    if (s->ready) free(s->ready);
                    if (s->select_waiters) free(s->select_waiters);
                    if (s->chans) free(s->chans);
                    if (s->tasks) free(s->tasks);
                    free(s);
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }

                // Channels
                for (int ci = 0; ci < s->chan_cap; ci++) {
                    uint8_t used = 0;
                    if (fread(&used, 1, 1, f) != 1) { oks = 0; break; }
                    if (!used) {
                        s->chans[ci].used = 0;
                        continue;
                    }
                    AvmChan* ch = &s->chans[ci];
                    memset(ch, 0, sizeof(*ch));
                    ch->used = 1;
                    ch->id = (int64_t)read_u64_le(f, &oks);
                    uint32_t recv_count = read_u32_le(f, &oks);
                    if (!oks || recv_count > 1000000u) { oks = 0; break; }
                    ch->recv_count = (int)recv_count;
                    ch->recv_cap = (int)recv_count;
                    ch->recv_waiters = NULL;
                    if (recv_count > 0) {
                        ch->recv_waiters = (int*)calloc(recv_count, sizeof(int));
                        if (!ch->recv_waiters) { oks = 0; break; }
                        for (uint32_t i = 0; i < recv_count; i++) ch->recv_waiters[i] = (int)read_u32_le(f, &oks);
                        if (!oks) break;
                    }
                    uint32_t q_len = read_u32_le(f, &oks);
                    if (!oks || q_len > 1000000u) { oks = 0; break; }
                    ch->q_len = (int)q_len;
                    ch->q_cap = (int)q_len;
                    ch->q = NULL;
                    if (q_len > 0) {
                        ch->q = (AvmValue*)calloc(q_len, sizeof(AvmValue));
                        if (!ch->q) { oks = 0; break; }
                        for (uint32_t i = 0; i < q_len; i++) {
                            if (!decode_value(f, obj_types, obj_ptrs, obj_count, &ch->q[i])) { oks = 0; break; }
                        }
                        if (!oks) break;
                    }
                }
                if (!oks) {
                    if (s->tasks) {
                        for (int i = 0; i < s->task_cap; i++) {
                            if (!s->tasks[i].used) continue;
                            if (s->tasks[i].frames) free(s->tasks[i].frames);
                            if (i != 0 && s->tasks[i].stack) free(s->tasks[i].stack);
                        }
                    }
                    if (s->chans) {
                        for (int i = 0; i < s->chan_cap; i++) {
                            if (!s->chans[i].used) continue;
                            if (s->chans[i].recv_waiters) free(s->chans[i].recv_waiters);
                            if (s->chans[i].q) free(s->chans[i].q);
                        }
                        free(s->chans);
                    }
                    if (s->ready) free(s->ready);
                    if (s->select_waiters) free(s->select_waiters);
                    if (s->tasks) free(s->tasks);
                    free(s);
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }

                // Attach scheduler and load current task state into VM.
                if (vm->sched) {
                    // Restore expects a fresh VM; be conservative.
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                // Best-effort sanity: ensure quantum is consistent with VM config.
                if (vm->task_quantum_steps > 0 && quantum_steps != 0 && vm->task_quantum_steps != quantum_steps) {
                    // If mismatch occurs, prefer snapshot scheduler quantum (semantics) and overwrite vm config.
                    vm->task_quantum_steps = quantum_steps;
                }
                vm->sched = s;

                int cur = s->current_tid;
                if (cur < 0 || cur >= s->task_cap || !s->tasks[cur].used) {
                    fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                }
                AvmTask* ct = &s->tasks[cur];
                vm->stack = ct->stack ? ct->stack : vm->stack_base;
                vm->pc = ct->pc;
                vm->sp = ct->sp;
                vm->fp = ct->fp;
                vm->frame_count = ct->frame_count;
                vm->env = ct->env;
                if (ct->frames) memcpy(vm->frames, ct->frames, sizeof(AvmFrame) * (size_t)MAX_FRAMES);
                else memset(vm->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

                if (ct->wake_pending) {
                    if (vm->sp < (int)AVM_STACK_SIZE) {
                        vm->stack[vm->sp++] = ct->wake_value;
                    } else {
                        fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
                    }
                    ct->wake_pending = 0;
                    ct->wake_value = avm_nil();
                }
            } else {
                fclose(f); free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs); return 1;
            }
        }
    }

    fclose(f);

    // NOTE: heap objects allocated here are intentionally leaked for now (consistent with bootstrap AVM design).
    free(obj_types); free(obj_aux); free(payload_off); free(obj_ptrs);
    return 0;
}
