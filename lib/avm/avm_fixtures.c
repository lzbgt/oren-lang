#include "avm_internal.h"

#include <string.h>

AvmVnetEntry* avm_vnet_find(AvmVM* vm, const char* url) {
    if (!vm || !vm->vnet || !url) return NULL;
    AvmVnet* v = (AvmVnet*)vm->vnet;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].url && strcmp(v->entries[i].url, url) == 0) return &v->entries[i];
    }
    return NULL;
}

AvmVprocEntry* avm_vproc_find(AvmVM* vm, const char* cmd) {
    if (!vm || !vm->vproc || !cmd) return NULL;
    AvmVproc* v = (AvmVproc*)vm->vproc;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].cmd && strcmp(v->entries[i].cmd, cmd) == 0) return &v->entries[i];
    }
    return NULL;
}

int avm_net_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !data) return 0;
    if (len < 12) return 0; // magic + count
    if (len > (size_t)INT32_MAX) return 0;

    AvmBytes in;
    in.data = (uint8_t*)data;
    in.len = (int)len;
    in.capacity = (int)len;

    uint32_t pos = 0;
    uint8_t magic[8];
    if (!mem_read_bytes(&in, &pos, magic, 8)) return 0;
    const uint8_t want[8] = {'A','V','M','N','E','T','0','1'};
    if (memcmp(magic, want, 8) != 0) return 0;

    uint32_t count = 0;
    if (!mem_read_u32_le(&in, &pos, &count)) return 0;
    if (count > 1000000u) return 0; // sanity cap (rolling)

    AvmVnet* v = (AvmVnet*)avm_heap_malloc_k(sizeof(AvmVnet), AVM_ALLOC_KIND_VNET);
    if (!v) return 0;
    v->entries = NULL;
    v->count = count;

    if (count > 0) {
        if (count > (uint32_t)(SIZE_MAX / sizeof(AvmVnetEntry))) return 0;
        v->entries = (AvmVnetEntry*)avm_heap_malloc_k(sizeof(AvmVnetEntry) * (size_t)count, AVM_ALLOC_KIND_VNET);
        if (!v->entries) return 0;
        for (uint32_t i = 0; i < count; i++) {
            v->entries[i].url = NULL;
            v->entries[i].body = NULL;
            v->entries[i].body_len = 0;
        }
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t url_len = 0;
        if (!mem_read_u32_le(&in, &pos, &url_len)) return 0;
        if ((uint64_t)pos + (uint64_t)url_len > (uint64_t)in.len) return 0;
        char* url = (char*)avm_heap_malloc_k((size_t)url_len + 1, AVM_ALLOC_KIND_VNET);
        if (!url) return 0;
        if (url_len > 0) memcpy(url, in.data + pos, url_len);
        url[url_len] = 0;
        pos += url_len;

        uint32_t body_len = 0;
        if (!mem_read_u32_le(&in, &pos, &body_len)) return 0;
        if ((uint64_t)pos + (uint64_t)body_len > (uint64_t)in.len) return 0;
        uint8_t* body = NULL;
        if (body_len > 0) {
            body = (uint8_t*)avm_heap_malloc_k((size_t)body_len, AVM_ALLOC_KIND_VNET);
            if (!body) return 0;
            memcpy(body, in.data + pos, body_len);
        }
        pos += body_len;

        v->entries[i].url = url;
        v->entries[i].body = body;
        v->entries[i].body_len = body_len;
    }

    vm->vnet = v;
    return 1;
}

int avm_proc_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len) {
    if (!vm || !data) return 0;
    if (len < 12) return 0; // magic + count
    if (len > (size_t)INT32_MAX) return 0;

    AvmBytes in;
    in.data = (uint8_t*)data;
    in.len = (int)len;
    in.capacity = (int)len;

    uint32_t pos = 0;
    uint8_t magic[8];
    if (!mem_read_bytes(&in, &pos, magic, 8)) return 0;
    const uint8_t want[8] = {'A','V','M','P','R','C','0','1'};
    if (memcmp(magic, want, 8) != 0) return 0;

    uint32_t count = 0;
    if (!mem_read_u32_le(&in, &pos, &count)) return 0;
    if (count > 1000000u) return 0; // sanity cap (rolling)

    AvmVproc* v = (AvmVproc*)avm_heap_malloc_k(sizeof(AvmVproc), AVM_ALLOC_KIND_VPROC);
    if (!v) return 0;
    v->entries = NULL;
    v->count = count;

    if (count > 0) {
        if (count > (uint32_t)(SIZE_MAX / sizeof(AvmVprocEntry))) return 0;
        v->entries = (AvmVprocEntry*)avm_heap_malloc_k(sizeof(AvmVprocEntry) * (size_t)count, AVM_ALLOC_KIND_VPROC);
        if (!v->entries) return 0;
        for (uint32_t i = 0; i < count; i++) {
            v->entries[i].cmd = NULL;
            v->entries[i].exit_code = 0;
        }
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t cmd_len = 0;
        if (!mem_read_u32_le(&in, &pos, &cmd_len)) return 0;
        if ((uint64_t)pos + (uint64_t)cmd_len > (uint64_t)in.len) return 0;
        char* cmd = (char*)avm_heap_malloc_k((size_t)cmd_len + 1, AVM_ALLOC_KIND_VPROC);
        if (!cmd) return 0;
        if (cmd_len > 0) memcpy(cmd, in.data + pos, cmd_len);
        cmd[cmd_len] = 0;
        pos += cmd_len;

        uint32_t exit_u32 = 0;
        if (!mem_read_u32_le(&in, &pos, &exit_u32)) return 0;
        int32_t exit_i32 = (int32_t)exit_u32;

        v->entries[i].cmd = cmd;
        v->entries[i].exit_code = exit_i32;
    }

    if (pos != (uint32_t)in.len) return 0;
    vm->vproc = v;
    return 1;
}

