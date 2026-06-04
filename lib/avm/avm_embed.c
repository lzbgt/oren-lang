#include "avm_embed.h"
#include "avm_cli_verify.h"
#include "avm_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>

#define AVM_EMBED_HANDLE_MAGIC UINT64_C(0x41564d454d424544)

struct AvmEmbedHandle {
    uint64_t magic;
    AvmVM* vm;
    int verify_strict;
    AvmEmbedProgram* owned_program;
    int argc;
    char** argv;
    atomic_int run_in_progress;
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
        (UINT64_C(1) << 2) |
        (UINT64_C(1) << 4) |
        (UINT64_C(1) << 5) |
        (UINT64_C(1) << 6) |
        (UINT64_C(1) << 9) |
        (UINT64_C(1) << 10) |
        (UINT64_C(1) << 11);
    config->gas_limit = 5000000ull;
    config->heap_limit_bytes = 32ull * 1024ull * 1024ull;
    config->io_limit_bytes = 1024ull * 1024ull;
    config->frame_limit = 1024u;
    config->task_quantum_steps = 1000u;
    config->fs_backend_kind = 1;
    config->proc_backend_kind = 1;
    config->net_backend_kind = 1;
}

void avm_embed_config_interactive_default(AvmEmbedConfig* config) {
    avm_embed_config_default(config);
    if (!config) return;
    // Interactive host apps need wall-clock TIME effects. Keep virtual FS/PROC/NET
    // defaults so app mode does not silently gain host filesystem/network/process access.
    config->deterministic = 0;
}

static int avm_embed_valid_handle(AvmEmbedHandle* handle) {
    return handle && handle->magic == AVM_EMBED_HANDLE_MAGIC && handle->vm;
}

static int avm_embed_enter_run(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed run argument");
    }
    int expected = 0;
    if (!atomic_compare_exchange_strong(&handle->run_in_progress, &expected, 1)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_BUSY, AVM_ERR_INVALID_ARG, "AVM embed handle is already running");
    }
    return AVM_EMBED_OK;
}

static void avm_embed_leave_run(AvmEmbedHandle* handle) {
    if (handle) atomic_store(&handle->run_in_progress, 0);
}

static void avm_embed_output_clear_vm(AvmVM* vm) {
    if (!vm) return;
    vm->stdout_capture_len = 0;
    if (vm->stdout_capture) vm->stdout_capture[0] = 0;
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

static char* avm_embed_strdup_heap(const char* s) {
    if (!s) return NULL;
    size_t n = strlen(s);
    char* out = (char*)malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, s, n + 1);
    return out;
}

static int avm_embed_fs_mount_append(char*** virt_arr,
                                     char*** host_arr,
                                     int* count,
                                     const char* virtual_prefix,
                                     const char* host_prefix) {
    if (!virt_arr || !host_arr || !count || !virtual_prefix || !host_prefix) return 0;
    if (*count < 0) return 0;
    size_t next_count = (size_t)*count + 1u;
    if (next_count > (size_t)INT32_MAX) return 0;
    char* virt_copy = avm_embed_strdup_heap(virtual_prefix);
    char* host_copy = avm_embed_strdup_heap(host_prefix);
    if (!virt_copy || !host_copy) {
        free(virt_copy);
        free(host_copy);
        return 0;
    }
    char** next_virt = (char**)realloc(*virt_arr, sizeof(char*) * next_count);
    if (!next_virt) {
        free(virt_copy);
        free(host_copy);
        return 0;
    }
    *virt_arr = next_virt;
    char** next_host = (char**)realloc(*host_arr, sizeof(char*) * next_count);
    if (!next_host) {
        free(virt_copy);
        free(host_copy);
        return 0;
    }
    *host_arr = next_host;
    (*virt_arr)[*count] = virt_copy;
    (*host_arr)[*count] = host_copy;
    *count = (int)next_count;
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

static uint32_t avm_embed_read_u32_le_raw(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
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
    handle->vm->stdout_capture_enabled = 1;
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

int avm_embed_set_output_capture(AvmEmbedHandle* handle, int enabled, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed output capture argument");
    }
    handle->vm->stdout_capture_enabled = enabled ? 1 : 0;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_output_info(AvmEmbedHandle* handle, size_t* out_len, AvmEmbedResult* result) {
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed output info argument");
    }
    *out_len = handle->vm->stdout_capture_len;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_output_get(AvmEmbedHandle* handle, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result) {
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !out_data || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed output get argument");
    }
    size_t len = handle->vm->stdout_capture_len;
    uint8_t* copy = (uint8_t*)malloc(len ? len : 1u);
    if (!copy) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy AVM output bytes");
    if (len > 0 && handle->vm->stdout_capture) memcpy(copy, handle->vm->stdout_capture, len);
    *out_data = copy;
    *out_len = len;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_output_clear(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed output clear argument");
    }
    avm_embed_output_clear_vm(handle->vm);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_set_gfx_frame_callback(AvmEmbedHandle* handle, AvmGfxFrameFn frame_fn, void* user_data, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX frame callback argument");
    }
    handle->vm->gfx_frame_fn = frame_fn;
    handle->vm->gfx_frame_user_data = user_data;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_gfx_frame_info(AvmEmbedHandle* handle, size_t* out_len, uint32_t* out_sequence, AvmEmbedResult* result) {
    if (out_len) *out_len = 0;
    if (out_sequence) *out_sequence = 0;
    if (!avm_embed_valid_handle(handle) || !out_len || !out_sequence) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX frame info argument");
    }
    if (handle->vm->gfx_frame_data && handle->vm->gfx_frame_len > 0) {
        *out_len = handle->vm->gfx_frame_len;
        *out_sequence = handle->vm->gfx_frame_sequence;
    }
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_gfx_frame_get(AvmEmbedHandle* handle, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result) {
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !out_data || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX frame get argument");
    }
    size_t len = handle->vm->gfx_frame_len;
    if (len == 0 || !handle->vm->gfx_frame_data) {
        return avm_embed_fail(result, AVM_EMBED_ERR_VM, AVM_ERR_NOT_FOUND, "GFX frame mailbox is empty");
    }
    uint8_t* copy = (uint8_t*)malloc(len);
    if (!copy) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy AVM GFX frame bytes");
    memcpy(copy, handle->vm->gfx_frame_data, len);
    *out_data = copy;
    *out_len = len;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_gfx_frame_clear(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX frame clear argument");
    }
    if (handle->vm->gfx_frame_data) {
        free(handle->vm->gfx_frame_data);
        handle->vm->gfx_frame_data = NULL;
    }
    handle->vm->gfx_frame_len = 0;
    handle->vm->gfx_frame_sequence = 0;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_gfx_input_put(AvmEmbedHandle* handle, const uint8_t* event_data, size_t event_len, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !event_data || event_len == 0 || event_len > (size_t)UINT32_MAX) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX input put argument");
    }
    char gfx_err[160];
    if (!avm_gfx_validate_event(event_data, event_len, gfx_err, sizeof(gfx_err))) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, gfx_err);
    }

    AvmGfxInputQueue* q = (AvmGfxInputQueue*)handle->vm->gfx_input_queue;
    if (!q) {
        q = (AvmGfxInputQueue*)calloc(1, sizeof(AvmGfxInputQueue));
        if (!q) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate AVM GFX input queue");
        handle->vm->gfx_input_queue = q;
    }
    if ((event_data[8] == 18u || event_data[8] == 96u) && q->count > 0 && q->entries) {
        uint32_t motion_source = event_data[8] == 96u ? avm_embed_read_u32_le_raw(event_data + 12) : 0u;
        uint32_t dst = 0;
        for (uint32_t src = 0; src < q->count; src++) {
            AvmGfxInputEntry entry = q->entries[src];
            int replace = entry.len >= 12u && entry.data && entry.data[8] == event_data[8];
            if (replace && event_data[8] == 96u) {
                replace = entry.len >= 16u && avm_embed_read_u32_le_raw(entry.data + 12) == motion_source;
            }
            if (replace) {
                free(entry.data);
                continue;
            }
            if (dst != src) q->entries[dst] = entry;
            dst++;
        }
        for (uint32_t i = dst; i < q->count; i++) {
            q->entries[i].data = NULL;
            q->entries[i].len = 0;
        }
        q->count = dst;
    }
    if (q->count >= 1024u) {
        return avm_embed_fail(result, AVM_EMBED_ERR_VM, AVM_ERR_BUDGET, "AVM GFX input queue is full");
    }
    if (q->count >= q->cap) {
        uint32_t next_cap = q->cap ? q->cap * 2u : 8u;
        if (next_cap < q->count + 1u) next_cap = q->count + 1u;
        AvmGfxInputEntry* next = (AvmGfxInputEntry*)realloc(q->entries, sizeof(AvmGfxInputEntry) * (size_t)next_cap);
        if (!next) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to grow AVM GFX input queue");
        for (uint32_t i = q->cap; i < next_cap; i++) {
            next[i].data = NULL;
            next[i].len = 0;
        }
        q->entries = next;
        q->cap = next_cap;
    }
    uint8_t* copy = (uint8_t*)malloc(event_len);
    if (!copy) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy AVM GFX input event");
    memcpy(copy, event_data, event_len);
    q->entries[q->count].data = copy;
    q->entries[q->count].len = (uint32_t)event_len;
    q->count++;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_gfx_screen_set(AvmEmbedHandle* handle,
                             uint32_t screen_id,
                             uint32_t width,
                             uint32_t height,
                             uint32_t scale_milli,
                             uint32_t drawable_width,
                             uint32_t drawable_height,
                             uint32_t target_hz_milli,
                             uint32_t flags,
                             AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || width == 0 || height == 0 || scale_milli == 0) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed GFX screen state");
    }
    handle->vm->gfx_screen_available = 1;
    handle->vm->gfx_screen_id = screen_id;
    handle->vm->gfx_screen_width = width;
    handle->vm->gfx_screen_height = height;
    handle->vm->gfx_screen_scale_milli = scale_milli;
    handle->vm->gfx_screen_drawable_width = drawable_width;
    handle->vm->gfx_screen_drawable_height = drawable_height;
    handle->vm->gfx_screen_target_hz_milli = target_hz_milli;
    handle->vm->gfx_screen_flags = flags;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

static char* avm_embed_strdup_limit(const char* s, size_t limit) {
    if (!s) s = "";
    size_t n = strlen(s);
    if (n > limit) return NULL;
    char* out = (char*)malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, s, n + 1);
    return out;
}

int avm_embed_event_put(AvmEmbedHandle* handle, const char* kind, const char* action, const char* detail, uint32_t flags, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !kind || !action || kind[0] == '\0' || action[0] == '\0') {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM host event put argument");
    }
    if ((strcmp(kind, "fs") != 0 && strcmp(kind, "package") != 0) || strlen(kind) > 32 || strlen(action) > 64 || (detail && strlen(detail) > 4096)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM host event kind/action/detail");
    }
    AvmHostEventQueue* q = (AvmHostEventQueue*)handle->vm->host_event_queue;
    if (!q) {
        q = (AvmHostEventQueue*)calloc(1, sizeof(AvmHostEventQueue));
        if (!q) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to allocate AVM host event queue");
        handle->vm->host_event_queue = q;
    }
    if (q->count >= 1024u) {
        return avm_embed_fail(result, AVM_EMBED_ERR_VM, AVM_ERR_BUDGET, "AVM host event queue is full");
    }
    if (q->count >= q->cap) {
        uint32_t next_cap = q->cap ? q->cap * 2u : 8u;
        if (next_cap < q->count + 1u) next_cap = q->count + 1u;
        AvmHostEventEntry* next = (AvmHostEventEntry*)realloc(q->entries, sizeof(AvmHostEventEntry) * (size_t)next_cap);
        if (!next) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to grow AVM host event queue");
        for (uint32_t i = q->cap; i < next_cap; i++) memset(&next[i], 0, sizeof(next[i]));
        q->entries = next;
        q->cap = next_cap;
    }
    char* kind_copy = avm_embed_strdup_limit(kind, 32);
    char* action_copy = avm_embed_strdup_limit(action, 64);
    char* detail_copy = avm_embed_strdup_limit(detail ? detail : "", 4096);
    if (!kind_copy || !action_copy || !detail_copy) {
        free(kind_copy);
        free(action_copy);
        free(detail_copy);
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy AVM host event");
    }
    uint32_t seq = handle->vm->host_event_sequence + 1u;
    if (seq == 0) seq = 1u;
    handle->vm->host_event_sequence = seq;
    AvmHostEventEntry* entry = &q->entries[q->count++];
    entry->kind = kind_copy;
    entry->action = action_copy;
    entry->detail = detail_copy;
    entry->flags = flags;
    entry->sequence = seq;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_permission_request_info(AvmEmbedHandle* handle, size_t* out_len, uint32_t* out_sequence, AvmEmbedResult* result) {
    if (out_len) *out_len = 0;
    if (out_sequence) *out_sequence = 0;
    if (!avm_embed_valid_handle(handle) || !out_len || !out_sequence) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed permission request info argument");
    }
    if (handle->vm->permission_request_data && handle->vm->permission_request_len > 0) {
        *out_len = handle->vm->permission_request_len;
        *out_sequence = handle->vm->permission_request_sequence;
    }
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_permission_request_get(AvmEmbedHandle* handle, uint8_t** out_data, size_t* out_len, AvmEmbedResult* result) {
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (!avm_embed_valid_handle(handle) || !out_data || !out_len) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed permission request get argument");
    }
    size_t len = handle->vm->permission_request_len;
    if (len == 0 || !handle->vm->permission_request_data) {
        return avm_embed_fail(result, AVM_EMBED_ERR_VM, AVM_ERR_NOT_FOUND, "permission request mailbox is empty");
    }
    uint8_t* copy = (uint8_t*)malloc(len);
    if (!copy) return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to copy AVM permission request bytes");
    memcpy(copy, handle->vm->permission_request_data, len);
    *out_data = copy;
    *out_len = len;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_permission_request_clear(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed permission request clear argument");
    }
    if (handle->vm->permission_request_data) {
        free(handle->vm->permission_request_data);
        handle->vm->permission_request_data = NULL;
    }
    handle->vm->permission_request_len = 0;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_fs_mount_read(AvmEmbedHandle* handle, const char* virtual_prefix, const char* host_prefix, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !virtual_prefix || !host_prefix ||
        virtual_prefix[0] == 0 || host_prefix[0] == 0) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed FS read mount argument");
    }
    if (!avm_embed_fs_mount_append(&handle->vm->fs_mounts_read_virt,
                                   &handle->vm->fs_mounts_read_host,
                                   &handle->vm->fs_mounts_read_count,
                                   virtual_prefix,
                                   host_prefix)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to add AVM FS read mount");
    }
    handle->vm->fs_backend_kind = 0;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_fs_mount_write(AvmEmbedHandle* handle, const char* virtual_prefix, const char* host_prefix, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle) || !virtual_prefix || !host_prefix ||
        virtual_prefix[0] == 0 || host_prefix[0] == 0) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed FS write mount argument");
    }
    if (!avm_embed_fs_mount_append(&handle->vm->fs_mounts_write_virt,
                                   &handle->vm->fs_mounts_write_host,
                                   &handle->vm->fs_mounts_write_count,
                                   virtual_prefix,
                                   host_prefix)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_ALLOC, AVM_ERR_BUDGET, "failed to add AVM FS write mount");
    }
    handle->vm->fs_backend_kind = 0;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_fs_mount(AvmEmbedHandle* handle, const char* virtual_prefix, const char* host_prefix, AvmEmbedResult* result) {
    AvmEmbedResult local;
    AvmEmbedResult* r = result ? result : &local;
    if (avm_embed_fs_mount_read(handle, virtual_prefix, host_prefix, r) != AVM_EMBED_OK) return r->status;
    if (avm_embed_fs_mount_write(handle, virtual_prefix, host_prefix, r) != AVM_EMBED_OK) return r->status;
    return r->status;
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

int avm_embed_set_net_fetch_callback(AvmEmbedHandle* handle, AvmNetFetchFn fetch_fn, void* user_data, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed NET callback handle");
    }
    handle->vm->net_fetch_fn = fetch_fn;
    handle->vm->net_fetch_user_data = user_data;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_set_net_session_callbacks(AvmEmbedHandle* handle, AvmNetSessionOpenFn open_fn, AvmNetSessionWriteFn write_fn, AvmNetSessionReadFn read_fn, AvmNetSessionPollFn poll_fn, AvmNetSessionSelectFn select_fn, AvmNetSessionAcceptFn accept_fn, AvmNetSessionCloseFn close_fn, void* user_data, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed NET session callback handle");
    }
    handle->vm->net_session_open_fn = open_fn;
    handle->vm->net_session_write_fn = write_fn;
    handle->vm->net_session_read_fn = read_fn;
    handle->vm->net_session_poll_fn = poll_fn;
    handle->vm->net_session_select_fn = select_fn;
    handle->vm->net_session_accept_fn = accept_fn;
    handle->vm->net_session_close_fn = close_fn;
    handle->vm->net_session_user_data = user_data;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_set_net_resolve_callback(AvmEmbedHandle* handle, AvmNetResolveFn resolve_fn, void* user_data, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed NET resolve callback handle");
    }
    handle->vm->net_resolve_fn = resolve_fn;
    handle->vm->net_resolve_user_data = user_data;
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

int avm_embed_cancel(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed cancel argument");
    }
    handle->vm->cancelled = 1;
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

int avm_embed_clear_cancel(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (!avm_embed_valid_handle(handle)) {
        return avm_embed_fail(result, AVM_EMBED_ERR_INVALID_ARG, AVM_ERR_INVALID_ARG, "invalid AVM embed clear-cancel argument");
    }
    handle->vm->cancelled = 0;
    handle->vm->last_error = avm_nil();
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : AVM_EMBED_OK;
}

static int avm_embed_run_loaded_unchecked(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    if (handle->vm->stdout_capture_enabled) avm_embed_output_clear_vm(handle->vm);
    avm_run(handle->vm);
    avm_embed_fill_from_vm(handle->vm, result);
    return result ? result->status : (avm_is_err_val(handle->vm->last_error) ? AVM_EMBED_ERR_VM : AVM_EMBED_OK);
}

int avm_embed_run_loaded(AvmEmbedHandle* handle, AvmEmbedResult* result) {
    int guard_rc = avm_embed_enter_run(handle, result);
    if (guard_rc != AVM_EMBED_OK) return guard_rc;
    int rc = avm_embed_run_loaded_unchecked(handle, result);
    avm_embed_leave_run(handle);
    return rc;
}

int avm_embed_run_program(AvmEmbedHandle* handle, AvmProgram* program, AvmEmbedResult* result) {
    int guard_rc = avm_embed_enter_run(handle, result);
    if (guard_rc != AVM_EMBED_OK) return guard_rc;
    int rc = avm_embed_load_program(handle, program, result);
    if (rc == AVM_EMBED_OK) rc = avm_embed_run_loaded_unchecked(handle, result);
    avm_embed_leave_run(handle);
    return rc;
}

int avm_embed_run_obc_bytes(AvmEmbedHandle* handle, const uint8_t* data, size_t len, AvmEmbedResult* result) {
    int guard_rc = avm_embed_enter_run(handle, result);
    if (guard_rc != AVM_EMBED_OK) return guard_rc;
    int rc = avm_embed_load_obc_bytes(handle, data, len, result);
    if (rc == AVM_EMBED_OK) rc = avm_embed_run_loaded_unchecked(handle, result);
    avm_embed_leave_run(handle);
    return rc;
}
