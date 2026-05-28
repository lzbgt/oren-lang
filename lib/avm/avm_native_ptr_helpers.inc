#define AVM_PTR_HANDLE_BASE ((int64_t)1099511627776LL) /* 1 << 40 */
#define AVM_PTR_HANDLE_STRIDE ((int64_t)4294967296LL)  /* 1 << 32 */

static int64_t avm_ptr_handle_encode(int id, int64_t off) {
    return AVM_PTR_HANDLE_BASE + ((int64_t)id * AVM_PTR_HANDLE_STRIDE) + off;
}

static int avm_ptr_register(AvmVM* vm, AvmType type, void* owner, uint8_t* data, int64_t len, int readonly, int64_t* out) {
    if (!vm || !owner || len < 0 || !out) return 0;
    for (int i = 0; i < vm->ptr_handle_count; i++) {
        AvmPtrHandle* h = &vm->ptr_handles[i];
        if (h->owner == owner && h->data == data && h->type == type) {
            *out = avm_ptr_handle_encode(i + 1, 0);
            return 1;
        }
    }
    if (vm->ptr_handle_count >= AVM_PTR_HANDLE_MAX) return 0;
    int idx = vm->ptr_handle_count++;
    vm->ptr_handles[idx].type = type;
    vm->ptr_handles[idx].owner = owner;
    vm->ptr_handles[idx].data = data;
    vm->ptr_handles[idx].len = len;
    vm->ptr_handles[idx].readonly = readonly;
    *out = avm_ptr_handle_encode(idx + 1, 0);
    return 1;
}

static int avm_ptr_base_from_value(AvmVM* vm, AvmValue v, int64_t* out) {
    if (!out) return 0;
    if (v.type == AVM_VAL_INT) {
        *out = v.as.i;
        return 1;
    }
    if (v.type == AVM_VAL_STRING && v.as.p) {
        char* s = (char*)v.as.p;
        return avm_ptr_register(vm, v.type, s, (uint8_t*)s, (int64_t)strlen(s), 1, out);
    }
    if (v.type == AVM_VAL_BYTES && v.as.b) {
        AvmBytes* b = v.as.b;
        return avm_ptr_register(vm, v.type, b, b->data, (int64_t)b->len, 0, out);
    }
    if ((v.type == AVM_VAL_I32_BUF || v.type == AVM_VAL_I64_BUF || v.type == AVM_VAL_F32_BUF || v.type == AVM_VAL_F64_BUF) && v.as.buf) {
        AvmBuf* b = v.as.buf;
        int64_t nbytes = (int64_t)b->len * (int64_t)b->elem_size;
        return avm_ptr_register(vm, v.type, b, b->data, nbytes, 0, out);
    }
    return 0;
}

static int avm_ptr_decode(AvmVM* vm, AvmValue v, AvmPtrHandle** out_h, int64_t* out_off) {
    int64_t raw = 0;
    if (!avm_ptr_base_from_value(vm, v, &raw)) return 0;
    if (raw < AVM_PTR_HANDLE_BASE) return 0;
    int64_t rel = raw - AVM_PTR_HANDLE_BASE;
    int id = (int)(rel / AVM_PTR_HANDLE_STRIDE);
    int64_t off = rel - ((int64_t)id * AVM_PTR_HANDLE_STRIDE);
    if (id <= 0 || id > vm->ptr_handle_count) return 0;
    AvmPtrHandle* h = &vm->ptr_handles[id - 1];
    if (!h->data && h->len > 0) return 0;
    *out_h = h;
    *out_off = off;
    return 1;
}

static AvmValue avm_ptr_get_byte_value(AvmVM* vm, AvmValue pval) {
    AvmPtrHandle* h = NULL;
    int64_t off = 0;
    if (!avm_ptr_decode(vm, pval, &h, &off)) return avm_err(AVM_ERR_INVALID_ARG, "ptr_get_byte expects VM pointer handle");
    if (off < 0 || off >= h->len) return avm_err(AVM_ERR_INVALID_ARG, "ptr_get_byte: out of bounds");
    return avm_int((int64_t)h->data[off]);
}

static AvmValue avm_ptr_set_byte_value(AvmVM* vm, AvmValue pval, AvmValue vval) {
    AvmPtrHandle* h = NULL;
    int64_t off = 0;
    if (vval.type != AVM_VAL_INT) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte expects int value");
    if (!avm_ptr_decode(vm, pval, &h, &off)) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte expects VM pointer handle");
    if (h->readonly) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte: read-only pointer");
    if (off < 0 || off >= h->len) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte: out of bounds");
    int64_t v = vval.as.i;
    if (v < 0 || v > 255) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set_byte: byte out of range");
    h->data[off] = (uint8_t)v;
    return avm_nil();
}

static AvmValue avm_ptr_get_u64_value(AvmVM* vm, AvmValue pval) {
    AvmPtrHandle* h = NULL;
    int64_t off = 0;
    if (!avm_ptr_decode(vm, pval, &h, &off)) return avm_err(AVM_ERR_INVALID_ARG, "ptr_get expects VM pointer handle");
    if (off < 0 || off + 8 > h->len) return avm_err(AVM_ERR_INVALID_ARG, "ptr_get: out of bounds");
    uint64_t u = 0;
    for (int i = 0; i < 8; i++) u |= ((uint64_t)h->data[off + i]) << (8 * i);
    return avm_int((int64_t)u);
}

static AvmValue avm_ptr_set_u64_value(AvmVM* vm, AvmValue pval, AvmValue vval) {
    AvmPtrHandle* h = NULL;
    int64_t off = 0;
    if (vval.type != AVM_VAL_INT) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set expects int value");
    if (!avm_ptr_decode(vm, pval, &h, &off)) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set expects VM pointer handle");
    if (h->readonly) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set: read-only pointer");
    if (off < 0 || off + 8 > h->len) return avm_err(AVM_ERR_INVALID_ARG, "ptr_set: out of bounds");
    uint64_t u = (uint64_t)vval.as.i;
    for (int i = 0; i < 8; i++) h->data[off + i] = (uint8_t)((u >> (8 * i)) & 255u);
    return avm_nil();
}
