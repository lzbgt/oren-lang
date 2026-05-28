#include "avm_embed.h"
#include "avm_cli_verify.h"
#include "avm_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AVM_EMBED_HANDLE_MAGIC UINT64_C(0x41564d454d424544)

struct AvmEmbedHandle {
    uint64_t magic;
    AvmVM* vm;
    int verify_strict;
    AvmEmbedProgram* owned_program;
    int argc;
    char** argv;
};

struct AvmEmbedProgram {
    uint8_t* obc_data;
    size_t obc_len;
    AvmProgram program;
    int loaded_into_vm;
};

static void avm_embed_set_message(AvmEmbedResult* result, const char* message) {
    if (!result) return;
    if (!message) message = "";
    snprintf(result->message, sizeof(result->message), "%s", message);
}

static int avm_embed_fail(AvmEmbedResult* result, int status, int avm_error_code, const char* message) {
    if (result) {
        avm_embed_result_clear(result);
        result->status = status;
        result->avm_error_code = avm_error_code;
        avm_embed_set_message(result, message);
    }
    return status;
}

void avm_embed_result_clear(AvmEmbedResult* result) {
    if (!result) return;
    memset(result, 0, sizeof(*result));
}

void avm_embed_config_default(AvmEmbedConfig* config) {
    if (!config) return;
    memset(config, 0, sizeof(*config));
    config->abi_version = AVM_EMBED_ABI_VERSION;
    config->struct_size = (uint32_t)sizeof(*config);
    config->deterministic = 1;
    config->verify_strict = 1;
    config->allowed_native_domains = (UINT64_C(1) << 0) |
        (UINT64_C(1) << 1) |
        (UINT64_C(1) << 4) |
        (UINT64_C(1) << 5) |
        (UINT64_C(1) << 6);
    config->gas_limit = 5000000ull;
    config->heap_limit_bytes = 32ull * 1024ull * 1024ull;
    config->io_limit_bytes = 1024ull * 1024ull;
    config->frame_limit = 1024u;
    config->task_quantum_steps = 1000u;
    config->fs_backend_kind = 1;
    config->proc_backend_kind = 1;
    config->net_backend_kind = 1;
}

static int avm_embed_valid_handle(AvmEmbedHandle* handle) {
    return handle && handle->magic == AVM_EMBED_HANDLE_MAGIC && handle->vm;
}

static void avm_embed_free_argv(AvmEmbedHandle* handle) {
    if (!handle) return;
    if (handle->argv) {
        for (int i = 0; i < handle->argc; i++) free(handle->argv[i]);
        free(handle->argv);
    }
    handle->argv = NULL;
    handle->argc = 0;
    if (handle->vm) {
        handle->vm->argv = NULL;
        handle->vm->argc = 0;
    }
}

static AvmVfs* avm_embed_vfs_get_or_create_vm(AvmVM* vm) {
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

static AvmVfsEntry* avm_embed_vfs_find_entry(AvmVfs* v, const char* path) {
    if (!v || !path) return NULL;
    for (uint32_t i = 0; i < v->count; i++) {
        if (v->entries[i].path && strcmp(v->entries[i].path, path) == 0) return &v->entries[i];
    }
    return NULL;
}

static int avm_embed_vfs_ensure_cap(AvmVfs* v, uint32_t need) {
    if (!v) return 0;
    if (need <= v->cap) return 1;
    uint32_t nc = v->cap ? v->cap : 16;
    while (nc < need) nc *= 2;
    AvmVfsEntry* ne = (AvmVfsEntry*)avm_heap_realloc_k(v->entries, sizeof(AvmVfsEntry) * (size_t)nc, AVM_ALLOC_KIND_VFS);
    if (!ne) return 0;
    for (uint32_t i = v->cap; i < nc; i++) {
        ne[i].path = NULL;
        ne[i].data = NULL;
        ne[i].len = 0;
    }
    v->entries = ne;
    v->cap = nc;
    return 1;
}

static AvmVnet* avm_embed_vnet_get_or_create_vm(AvmVM* vm) {
    if (!vm) return NULL;
    if (vm->vnet) return (AvmVnet*)vm->vnet;
    AvmVnet* v = (AvmVnet*)avm_heap_malloc_k(sizeof(AvmVnet), AVM_ALLOC_KIND_VNET);
    if (!v) return NULL;
    v->entries = NULL;
    v->count = 0;
    vm->vnet = v;
    return v;
}

static AvmVproc* avm_embed_vproc_get_or_create_vm(AvmVM* vm) {
    if (!vm) return NULL;
    if (vm->vproc) return (AvmVproc*)vm->vproc;
    AvmVproc* v = (AvmVproc*)avm_heap_malloc_k(sizeof(AvmVproc), AVM_ALLOC_KIND_VPROC);
    if (!v) return NULL;
    v->entries = NULL;
    v->count = 0;
    vm->vproc = v;
    return v;
}

static int avm_embed_write_u32_le(uint8_t* out, size_t cap, size_t* pos, uint32_t v) {
    if (!out || !pos || *pos > cap || cap - *pos < 4) return 0;
    out[(*pos)++] = (uint8_t)(v & 0xFFu);
    out[(*pos)++] = (uint8_t)((v >> 8) & 0xFFu);
    out[(*pos)++] = (uint8_t)((v >> 16) & 0xFFu);
    out[(*pos)++] = (uint8_t)((v >> 24) & 0xFFu);
    return 1;
}

static void avm_embed_apply_config(AvmVM* vm, const AvmEmbedConfig* config) {
    vm->deterministic = config->deterministic ? 1 : 0;
    vm->allowed_native_domains = config->allowed_native_domains;
    vm->gas_remaining = config->gas_limit;
    vm->heap_budget_bytes = config->heap_limit_bytes;
    vm->io_budget_bytes = config->io_limit_bytes;
    vm->frame_limit = config->frame_limit ? config->frame_limit : MAX_FRAMES;
    vm->task_quantum_steps = config->task_quantum_steps ? (int)config->task_quantum_steps : 1000;
    vm->fs_backend_kind = config->fs_backend_kind;
    vm->proc_backend_kind = config->proc_backend_kind;
    vm->net_backend_kind = config->net_backend_kind;
}

static void avm_embed_free_constants(AvmValue* consts, size_t n) {
    if (!consts) return;
    for (size_t i = 0; i < n; i++) {
        if (consts[i].type == AVM_VAL_STRING && consts[i].as.p) {
            free(consts[i].as.p);
        } else if (consts[i].type == AVM_VAL_BYTES && consts[i].as.b) {
            if (consts[i].as.b->data) free(consts[i].as.b->data);
            free(consts[i].as.b);
        }
        consts[i].type = AVM_VAL_NIL;
    }
    free(consts);
}

static int avm_embed_parse_obc_bytes(const uint8_t* data, size_t len, AvmProgram* out, char* err, size_t err_cap) {
    if (err && err_cap > 0) err[0] = 0;
    if (!data || !out) {
        if (err && err_cap > 0) snprintf(err, err_cap, "invalid OBC parse argument");
        return 0;
    }
    out->code = NULL;
    out->code_len = 0;
    out->constants = NULL;
    out->const_count = 0;

    if (len < 4 || data[0] != 0xCD || data[1] != 0x0E) {
        if (err && err_cap > 0) snprintf(err, err_cap, "invalid OBC magic");
        return 0;
    }

    size_t pos = 2;
    if (pos + 2 > len) {
        if (err && err_cap > 0) snprintf(err, err_cap, "invalid OBC constant pool");
        return 0;
    }
    uint16_t n_consts = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
    pos += 2;

    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)n_consts);
    if (!consts && n_consts > 0) {
        if (err && err_cap > 0) snprintf(err, err_cap, "out of memory parsing OBC constants");
        return 0;
    }
    for (uint16_t i = 0; i < n_consts; i++) consts[i].type = AVM_VAL_NIL;

    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) goto invalid_const_pool;
        uint8_t type = data[pos++];
        if (type == 0) {
            consts[i].type = AVM_VAL_NIL;
        } else if (type == 1) {
            if (pos + 8 > len) goto invalid_const_pool;
            int64_t val = 0;
            for (int k = 0; k < 8; k++) val |= (int64_t)data[pos++] << (k * 8);
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
        } else if (type == 2) {
            if (pos + 1 > len) goto invalid_const_pool;
            consts[i].type = AVM_VAL_BOOL;
            consts[i].as.i = data[pos++] ? 1 : 0;
        } else if (type == 3) {
            if (pos + 8 > len) goto invalid_const_pool;
            uint64_t bits = 0;
            for (int k = 0; k < 8; k++) bits |= (uint64_t)data[pos++] << (k * 8);
            double d = 0.0;
            memcpy(&d, &bits, sizeof(bits));
            consts[i].type = AVM_VAL_FLOAT;
            consts[i].as.f = d;
        } else if (type == 4) {
            if (pos + 2 > len) goto invalid_const_pool;
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            if (pos + slen > len) goto invalid_const_pool;
            char* s = (char*)malloc((size_t)slen + 1);
            if (!s) {
                if (err && err_cap > 0) snprintf(err, err_cap, "out of memory parsing OBC string constant");
                avm_embed_free_constants(consts, n_consts);
                return 0;
            }
            if (slen > 0) memcpy(s, data + pos, slen);
            s[slen] = 0;
            pos += slen;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
        } else if (type == 8) {
            if (pos + 4 > len) goto invalid_const_pool;
            uint32_t blen = (uint32_t)data[pos] |
                ((uint32_t)data[pos + 1] << 8) |
                ((uint32_t)data[pos + 2] << 16) |
                ((uint32_t)data[pos + 3] << 24);
            pos += 4;
            if (blen > (uint32_t)INT32_MAX || pos + blen > len) goto invalid_const_pool;
            AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
            if (!b) {
                if (err && err_cap > 0) snprintf(err, err_cap, "out of memory parsing OBC bytes constant");
                avm_embed_free_constants(consts, n_consts);
                return 0;
            }
            b->len = (int)blen;
            b->capacity = (int)blen;
            b->data = NULL;
            if (blen > 0) {
                b->data = (uint8_t*)malloc((size_t)blen);
                if (!b->data) {
                    free(b);
                    if (err && err_cap > 0) snprintf(err, err_cap, "out of memory parsing OBC bytes payload");
                    avm_embed_free_constants(consts, n_consts);
                    return 0;
                }
                memcpy(b->data, data + pos, blen);
            }
            pos += blen;
            consts[i].type = AVM_VAL_BYTES;
            consts[i].as.b = b;
        } else {
            goto invalid_const_pool;
        }
    }

    out->code = (uint8_t*)(data + pos);
    out->code_len = len - pos;
    out->constants = consts;
    out->const_count = n_consts;
    return 1;

invalid_const_pool:
    if (err && err_cap > 0) snprintf(err, err_cap, "invalid OBC constant pool");
    avm_embed_free_constants(consts, n_consts);
    return 0;
}

static void avm_embed_fill_from_vm(AvmVM* vm, AvmEmbedResult* result) {
    if (!result) return;
    avm_embed_result_clear(result);
    if (!vm) {
        result->status = AVM_EMBED_ERR_VM;
        result->avm_error_code = AVM_ERR_INTERNAL;
        avm_embed_set_message(result, "missing AVM VM");
        return;
    }

    result->exit_code = vm->exit_code;
    result->gas_executed = vm->gas_executed;
    result->heap_used_bytes = vm->heap_used_bytes;
    result->io_used_bytes = vm->io_used_bytes;

    if (avm_is_err_val(vm->last_error)) {
        AvmValue code = avm_map_get(vm->last_error.as.m, "code");
        AvmValue msg = avm_map_get(vm->last_error.as.m, "msg");
        result->status = AVM_EMBED_ERR_VM;
        result->avm_error_code = (code.type == AVM_VAL_INT) ? (int)code.as.i : AVM_ERR_INTERNAL;
        avm_embed_set_message(result, msg.type == AVM_VAL_STRING ? (const char*)msg.as.p : "AVM error");
        return;
    }

    result->status = AVM_EMBED_OK;
}

AvmEmbedHandle* avm_embed_open(const AvmEmbedConfig* config, AvmEmbedResult* result) {
    AvmEmbedConfig local;
    avm_embed_result_clear(result);
    if (!config) {
        avm_embed_config_default(&local);
        config = &local;
    } else if (config->abi_version != AVM_EMBED_ABI_VERSION || config->struct_size < sizeof(AvmEmbedConfig)) {
        if (result) {
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "unsupported AVM embed config ABI");
        }
        return NULL;
    }

    AvmEmbedHandle* handle = (AvmEmbedHandle*)calloc(1, sizeof(AvmEmbedHandle));
    if (!handle) {
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to allocate AVM embed handle");
        }
        return NULL;
    }

    handle->vm = avm_new();
    if (!handle->vm) {
        free(handle);
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to allocate AVM VM");
        }
        return NULL;
    }

    handle->magic = AVM_EMBED_HANDLE_MAGIC;
    handle->verify_strict = config->verify_strict ? 1 : 0;
    avm_embed_apply_config(handle->vm, config);
    avm_embed_fill_from_vm(handle->vm, result);
    return handle;
}

void avm_embed_close(AvmEmbedHandle* handle) {
    if (!handle) return;
    avm_embed_free_argv(handle);
    if (handle->magic == AVM_EMBED_HANDLE_MAGIC && handle->vm) {
        avm_free(handle->vm);
    }
    avm_embed_program_free(handle->owned_program);
    handle->magic = 0;
    handle->vm = NULL;
    free(handle);
}

AvmVM* avm_embed_vm(AvmEmbedHandle* handle) {
    return avm_embed_valid_handle(handle) ? handle->vm : NULL;
}

int avm_embed_set_argv(AvmEmbedHandle* handle, int argc, const char* const* argv, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || argc < 0 || (argc > 0 && !argv)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed argv argument");
    }

    char** next = NULL;
    if (argc > 0) {
        next = (char**)calloc((size_t)argc, sizeof(char*));
        if (!next) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate argv array");
        for (int i = 0; i < argc; i++) {
            const char* s = argv[i] ? argv[i] : "";
            size_t n = strlen(s);
            next[i] = (char*)malloc(n + 1);
            if (!next[i]) {
                for (int j = 0; j < argc; j++) free(next[j]);
                free(next);
                return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy argv string");
            }
            memcpy(next[i], s, n + 1);
        }
    }

    avm_embed_free_argv(handle);
    handle->argc = argc;
    handle->argv = next;
    handle->vm->argc = argc;
    handle->vm->argv = next;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_vfs_put(AvmEmbedHandle* handle, const char* path, const uint8_t* data, size_t len, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !path || (len > 0 && !data) || len > (size_t)UINT32_MAX) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VFS put argument");
    }

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(handle->vm, &prev_owner);
    handle->vm->fs_backend_kind = 1;
    AvmVfs* v = avm_embed_vfs_get_or_create_vm(handle->vm);
    if (!v) {
        avm_alloc_owner_pop(prev_owner);
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate AVM VFS");
    }

    AvmVfsEntry* e = avm_embed_vfs_find_entry(v, path);
    char* next_path = NULL;
    uint8_t* next_data = NULL;
    uint32_t next_len = (uint32_t)len;
    if (!e) {
        if (!avm_embed_vfs_ensure_cap(v, v->count + 1)) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to grow AVM VFS");
        }
        size_t path_len = strlen(path);
        next_path = (char*)avm_heap_malloc_k(path_len + 1, AVM_ALLOC_KIND_VFS);
        if (!next_path) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VFS path");
        }
        memcpy(next_path, path, path_len + 1);
    }
    if (len > 0) {
        next_data = (uint8_t*)avm_heap_malloc_k(len, AVM_ALLOC_KIND_VFS);
        if (!next_data) {
            if (next_path) avm_heap_free(next_path);
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VFS file bytes");
        }
        memcpy(next_data, data, len);
    }

    if (!e) {
        e = &v->entries[v->count++];
        e->path = next_path;
        e->data = NULL;
        e->len = 0;
    } else if (e->data) {
        avm_heap_free(e->data);
    }
    e->data = next_data;
    e->len = next_len;
    avm_alloc_owner_pop(prev_owner);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_vfs_get(AvmEmbedHandle* handle, const char* path, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result) {
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !path || !out_data || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VFS get argument");
    }
    AvmVfs* v = handle->vm->vfs ? (AvmVfs*)handle->vm->vfs : NULL;
    AvmVfsEntry* e = avm_embed_vfs_find_entry(v, path);
    if (!e) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "AVM VFS path not found");
    }
    uint8_t* copy = NULL;
    if (e->len > 0) {
        copy = (uint8_t*)malloc((size_t)e->len);
        if (!copy) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VFS file bytes");
        memcpy(copy, e->data, (size_t)e->len);
    }
    *out_data = copy;
    *out_len = (size_t)e->len;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_vfs_snapshot(AvmEmbedHandle* handle, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result) {
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !out_data || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VFS snapshot argument");
    }
    AvmVfs* v = handle->vm->vfs ? (AvmVfs*)handle->vm->vfs : NULL;
    uint32_t count = v ? v->count : 0;
    size_t total = 8u + 4u;
    for (uint32_t i = 0; i < count; i++) {
        AvmVfsEntry* e = &v->entries[i];
        size_t path_len = e->path ? strlen(e->path) : 0;
        if (path_len > (size_t)UINT32_MAX) {
            return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "VFS path too large for snapshot");
        }
        if (total > SIZE_MAX - 8u - path_len - (size_t)e->len) {
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "VFS snapshot too large");
        }
        total += 8u + path_len + (size_t)e->len;
    }

    uint8_t* buf = (uint8_t*)malloc(total ? total : 1u);
    if (!buf) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate VFS snapshot");
    size_t pos = 0;
    memcpy(buf + pos, "AVMVFS01", 8u);
    pos += 8u;
    if (!avm_embed_write_u32_le(buf, total, &pos, count)) {
        free(buf);
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to write VFS snapshot");
    }
    for (uint32_t i = 0; i < count; i++) {
        AvmVfsEntry* e = &v->entries[i];
        size_t path_len = e->path ? strlen(e->path) : 0;
        if (!avm_embed_write_u32_le(buf, total, &pos, (uint32_t)path_len)) {
            free(buf);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to write VFS snapshot path length");
        }
        if (path_len > 0) {
            memcpy(buf + pos, e->path, path_len);
            pos += path_len;
        }
        if (!avm_embed_write_u32_le(buf, total, &pos, e->len)) {
            free(buf);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to write VFS snapshot body length");
        }
        if (e->len > 0) {
            memcpy(buf + pos, e->data, (size_t)e->len);
            pos += (size_t)e->len;
        }
    }
    *out_data = buf;
    *out_len = total;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

void avm_embed_free_bytes(uint8_t* data) {
    free(data);
}

int avm_embed_vnet_put(AvmEmbedHandle* handle, const char* url, const uint8_t* body, size_t len, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !url || (len > 0 && !body) || len > (size_t)UINT32_MAX) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VNET put argument");
    }

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(handle->vm, &prev_owner);
    handle->vm->net_backend_kind = 1;
    AvmVnet* v = avm_embed_vnet_get_or_create_vm(handle->vm);
    if (!v) {
        avm_alloc_owner_pop(prev_owner);
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate AVM VNET");
    }

    AvmVnetEntry* e = avm_vnet_find(handle->vm, url);
    char* next_url = NULL;
    uint8_t* next_body = NULL;
    if (!e) {
        if (v->count == UINT32_MAX || (size_t)v->count + 1u > SIZE_MAX / sizeof(AvmVnetEntry)) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "AVM VNET fixture table too large");
        }
        size_t url_len = strlen(url);
        if (url_len > (size_t)UINT32_MAX) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "VNET URL too large");
        }
        next_url = (char*)avm_heap_malloc_k(url_len + 1, AVM_ALLOC_KIND_VNET);
        if (!next_url) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VNET URL");
        }
        memcpy(next_url, url, url_len + 1);
    }
    if (len > 0) {
        next_body = (uint8_t*)avm_heap_malloc_k(len, AVM_ALLOC_KIND_VNET);
        if (!next_body) {
            if (next_url) avm_heap_free(next_url);
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VNET body");
        }
        memcpy(next_body, body, len);
    }

    if (!e) {
        AvmVnetEntry* ne = (AvmVnetEntry*)avm_heap_realloc_k(v->entries, sizeof(AvmVnetEntry) * (size_t)(v->count + 1u), AVM_ALLOC_KIND_VNET);
        if (!ne) {
            if (next_url) avm_heap_free(next_url);
            if (next_body) avm_heap_free(next_body);
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to grow AVM VNET");
        }
        v->entries = ne;
        e = &v->entries[v->count++];
        e->url = next_url;
        e->body = NULL;
        e->body_len = 0;
    } else if (e->body) {
        avm_heap_free(e->body);
    }
    e->body = next_body;
    e->body_len = (uint32_t)len;
    avm_alloc_owner_pop(prev_owner);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_vproc_put(AvmEmbedHandle* handle, const char* command, int exit_code, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !command) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VPROC put argument");
    }

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(handle->vm, &prev_owner);
    handle->vm->proc_backend_kind = 1;
    AvmVproc* v = avm_embed_vproc_get_or_create_vm(handle->vm);
    if (!v) {
        avm_alloc_owner_pop(prev_owner);
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate AVM VPROC");
    }

    AvmVprocEntry* e = avm_vproc_find(handle->vm, command);
    char* next_cmd = NULL;
    if (!e) {
        if (v->count == UINT32_MAX || (size_t)v->count + 1u > SIZE_MAX / sizeof(AvmVprocEntry)) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "AVM VPROC fixture table too large");
        }
        size_t cmd_len = strlen(command);
        if (cmd_len > (size_t)UINT32_MAX) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "VPROC command too large");
        }
        next_cmd = (char*)avm_heap_malloc_k(cmd_len + 1, AVM_ALLOC_KIND_VPROC);
        if (!next_cmd) {
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy VPROC command");
        }
        memcpy(next_cmd, command, cmd_len + 1);
        AvmVprocEntry* ne = (AvmVprocEntry*)avm_heap_realloc_k(v->entries, sizeof(AvmVprocEntry) * (size_t)(v->count + 1u), AVM_ALLOC_KIND_VPROC);
        if (!ne) {
            avm_heap_free(next_cmd);
            avm_alloc_owner_pop(prev_owner);
            return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to grow AVM VPROC");
        }
        v->entries = ne;
        e = &v->entries[v->count++];
        e->cmd = next_cmd;
    }
    e->exit_code = (int32_t)exit_code;
    avm_alloc_owner_pop(prev_owner);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_vproc_set_default_exit(AvmEmbedHandle* handle, int exit_code, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed VPROC default argument");
    }
    handle->vm->proc_backend_kind = 1;
    handle->vm->proc_exit_code = exit_code;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_program_from_obc_bytes(const uint8_t* data, size_t len, int verify_strict, AvmEmbedProgram** out_program, AvmEmbedResult* result) {
    if (out_program) *out_program = NULL;
    avm_embed_result_clear(result);
    if (!data || len == 0 || !out_program) {
        if (result) {
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid OBC bytes argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }

    AvmEmbedProgram* program = (AvmEmbedProgram*)calloc(1, sizeof(AvmEmbedProgram));
    if (!program) {
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to allocate AVM embed program");
        }
        return AVM_EMBED_ERR_ALLOC;
    }
    program->obc_data = (uint8_t*)malloc(len);
    if (!program->obc_data) {
        free(program);
        if (result) {
            result->status = AVM_EMBED_ERR_ALLOC;
            result->avm_error_code = AVM_ERR_BUDGET;
            avm_embed_set_message(result, "failed to copy OBC bytes");
        }
        return AVM_EMBED_ERR_ALLOC;
    }
    memcpy(program->obc_data, data, len);
    program->obc_len = len;

    char err[256];
    if (!avm_embed_parse_obc_bytes(program->obc_data, program->obc_len, &program->program, err, sizeof(err))) {
        avm_embed_program_free(program);
        if (result) {
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, err[0] ? err : "failed to parse OBC bytes");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }

    VerifyResult vr = verify_program(&program->program, verify_strict ? 1 : 0);
    if (!vr.ok) {
        avm_embed_program_free(program);
        if (result) {
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, vr.msg);
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }

    *out_program = program;
    if (result) result->status = AVM_EMBED_OK;
    return AVM_EMBED_OK;
}

void avm_embed_program_free(AvmEmbedProgram* program) {
    if (!program) return;
    if (program->loaded_into_vm) {
        free(program->program.constants);
    } else {
        avm_embed_free_constants(program->program.constants, program->program.const_count);
    }
    free(program->obc_data);
    free(program);
}

AvmProgram* avm_embed_program_view(AvmEmbedProgram* program) {
    return program ? &program->program : NULL;
}

int avm_embed_load_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !program) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid AVM embed load argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    if (handle->owned_program) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "handle already owns loaded OBC bytes; open a new handle to load another program");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    avm_load(handle->vm, program);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_load_obc_bytes(AvmEmbedHandle* handle, const uint8_t* data, size_t len, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid AVM embed load argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    AvmEmbedProgram* program = NULL;
    int rc = avm_embed_program_from_obc_bytes(data, len, handle->verify_strict, &program, result);
    if (rc != AVM_EMBED_OK) return rc;
    handle->owned_program = program;
    program->loaded_into_vm = 1;
    avm_load(handle->vm, &program->program);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_run_loaded(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        if (result) {
            avm_embed_result_clear(result);
            result->status = AVM_EMBED_ERR_INVALID_ARG;
            result->avm_error_code = AVM_ERR_INVALID_ARG;
            avm_embed_set_message(result, "invalid AVM embed run argument");
        }
        return AVM_EMBED_ERR_INVALID_ARG;
    }
    avm_run(handle->vm);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : (avm_is_err_val(handle->vm->last_error) ? AVM_EMBED_ERR_VM : AVM_EMBED_OK);
}

int avm_embed_run_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result) {
    int rc = avm_embed_load_program(handle, program, result);
    if (rc != AVM_EMBED_OK) return rc;
    return avm_embed_run_loaded(handle, result);
}

int avm_embed_run_obc_bytes(AvmEmbedHandle* handle, const uint8_t* data, size_t len, AvmEmbedResult* result) {
    int rc = avm_embed_load_obc_bytes(handle, data, len, result);
    if (rc != AVM_EMBED_OK) return rc;
    return avm_embed_run_loaded(handle, result);
}
