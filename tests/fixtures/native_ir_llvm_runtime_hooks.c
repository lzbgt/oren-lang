#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct OrenLlvmString {
    int64_t len;
    char* data;
    int64_t owner_kind;
} OrenLlvmString;

static int64_t g_llvm_runtime_alloc_calls = 0;
static int64_t g_llvm_runtime_registered_strings = 0;

void* oren_llvm_runtime_alloc_bytes(int64_t byte_count, int64_t alloc_kind) {
    (void)alloc_kind;
    if (byte_count < 0) {
        fprintf(stderr, "oren_llvm_runtime_alloc_bytes: negative byte count\n");
        abort();
    }
    size_t n = (size_t)byte_count;
    void* p = malloc(n == 0 ? 1u : n);
    if (!p) {
        fprintf(stderr, "oren_llvm_runtime_alloc_bytes: malloc failed\n");
        abort();
    }
    memset(p, 0, n == 0 ? 1u : n);
    g_llvm_runtime_alloc_calls++;
    return p;
}

void oren_llvm_runtime_register_string(int64_t desc_handle, char* data, int64_t len) {
    if (desc_handle == 0 || data == NULL || len < 0) {
        fprintf(stderr, "oren_llvm_runtime_register_string: invalid string allocation\n");
        abort();
    }
    OrenLlvmString* desc = (OrenLlvmString*)(uintptr_t)desc_handle;
    if (desc->len != len || desc->data != data || desc->owner_kind != 1) {
        fprintf(stderr, "oren_llvm_runtime_register_string: descriptor metadata mismatch\n");
        abort();
    }
    g_llvm_runtime_registered_strings++;
}

int64_t oren_llvm_runtime_alloc_calls(void) {
    return g_llvm_runtime_alloc_calls;
}

int64_t oren_llvm_runtime_registered_strings(void) {
    return g_llvm_runtime_registered_strings;
}
