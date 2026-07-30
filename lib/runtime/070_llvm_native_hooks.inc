typedef struct OrenLlvmString {
    int64_t len;
    char* data;
    int64_t owner_kind;
} OrenLlvmString;

static int64_t g_llvm_runtime_alloc_calls = 0;
static int64_t g_llvm_runtime_registered_strings = 0;

void* oren_llvm_runtime_alloc_bytes(int64_t byte_count, int64_t alloc_kind) {
    if (byte_count < 0) {
        oren_panic("llvm runtime alloc: negative byte count");
        return NULL;
    }

    size_t n = (size_t)byte_count;
    void* p = malloc(n == 0 ? 1u : n);
    if (!p) {
        oren_panic("llvm runtime alloc failed");
        return NULL;
    }
    memset(p, 0, n == 0 ? 1u : n);

#ifndef OREN_NO_GC
    if (alloc_kind == 1) {
        oren_register_alloc(p, OREN_ALLOC_STRING);
    } else {
        // LLVM string descriptors are opaque runtime structs, not raw payload blocks.
        oren_register_alloc(p, OREN_ALLOC_STRUCT);
    }
#endif
    g_llvm_runtime_alloc_calls++;
    return p;
}

void oren_llvm_runtime_register_string(int64_t desc_handle, char* data, int64_t len) {
    if (desc_handle == 0 || data == NULL || len < 0) {
        oren_panic("llvm runtime string register: invalid allocation");
        return;
    }

    OrenLlvmString* desc = (OrenLlvmString*)(uintptr_t)desc_handle;
    if (desc->len != len || desc->data != data || desc->owner_kind != 1) {
        oren_panic("llvm runtime string register: descriptor metadata mismatch");
        return;
    }
    g_llvm_runtime_registered_strings++;
}

int64_t oren_llvm_runtime_alloc_calls(void) {
    return g_llvm_runtime_alloc_calls;
}

int64_t oren_llvm_runtime_registered_strings(void) {
    return g_llvm_runtime_registered_strings;
}
