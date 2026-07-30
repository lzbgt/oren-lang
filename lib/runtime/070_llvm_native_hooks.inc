typedef struct OrenLlvmString {
    int64_t len;
    char* data;
    int64_t owner_kind;
} OrenLlvmString;

typedef struct OrenLlvmList {
    int64_t len;
    int64_t* data;
    int64_t owner_kind;
} OrenLlvmList;

static int64_t g_llvm_runtime_alloc_calls = 0;
static int64_t g_llvm_runtime_registered_strings = 0;
static int64_t g_llvm_runtime_registered_lists = 0;
static int64_t g_llvm_runtime_root_pushes = 0;
static int64_t g_llvm_runtime_safepoint_collections = 0;
static OrenLlvmString** g_llvm_runtime_roots = NULL;
static size_t g_llvm_runtime_roots_len = 0;
static size_t g_llvm_runtime_roots_cap = 0;

static int oren_llvm_runtime_force_gc_cached(void) {
    static int cached = -1;
    if (cached >= 0) return cached;
    const char* env = getenv("OREN_LLVM_FORCE_GC_AT_SAFEPOINT");
    cached = (env != NULL && env[0] != '\0' && strcmp(env, "0") != 0) ? 1 : 0;
    return cached;
}

static OrenAllocNode* oren_llvm_runtime_find_string_desc_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenThreadState* st = oren_thread_state();
    if (st) {
        OrenAllocNode* cur = st->local_allocs;
        while (cur) {
            if (cur->ptr == (void*)(uintptr_t)desc_handle &&
                cur->freed == 0 &&
                cur->kind == OREN_ALLOC_STRUCT) {
                OrenLlvmString* desc = (OrenLlvmString*)(uintptr_t)desc_handle;
                if (desc->owner_kind == 1 && desc->data != NULL && desc->len >= 0) {
                    return cur;
                }
                return NULL;
            }
            cur = cur->next;
        }
    }
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || n->freed != 0 || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmString* desc = (OrenLlvmString*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 || desc->data == NULL || desc->len < 0) return NULL;
    return n;
}

int64_t oren_llvm_runtime_roots_mark(void) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t mark = (int64_t)g_llvm_runtime_roots_len;
    pthread_mutex_unlock(&g_alloc_mutex);
    return mark;
}

void oren_llvm_runtime_roots_push_string(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_llvm_runtime_find_string_desc_locked(desc_handle);
    if (!n) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (g_llvm_runtime_roots_len == g_llvm_runtime_roots_cap) {
        size_t next_cap = g_llvm_runtime_roots_cap == 0 ? 16u : g_llvm_runtime_roots_cap * 2u;
        OrenLlvmString** next_roots = (OrenLlvmString**)realloc(g_llvm_runtime_roots, next_cap * sizeof(OrenLlvmString*));
        if (!next_roots) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime roots: grow failed");
            return;
        }
        g_llvm_runtime_roots = next_roots;
        g_llvm_runtime_roots_cap = next_cap;
    }
    g_llvm_runtime_roots[g_llvm_runtime_roots_len++] = (OrenLlvmString*)n->ptr;
    g_llvm_runtime_root_pushes++;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_roots_reset(int64_t mark) {
    pthread_mutex_lock(&g_alloc_mutex);
    if (mark < 0) mark = 0;
    size_t m = (size_t)mark;
    if (m < g_llvm_runtime_roots_len) {
        g_llvm_runtime_roots_len = m;
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_safepoint_poll(void) {
    if (!oren_llvm_runtime_force_gc_cached()) return;
    g_llvm_runtime_safepoint_collections++;
    oren_gc_collect();
}

static void oren_llvm_runtime_mark_roots(void) {
#ifndef OREN_NO_GC
    for (size_t i = 0; i < g_llvm_runtime_roots_len; i++) {
        OrenLlvmString* desc = g_llvm_runtime_roots[i];
        if (!desc) continue;
        OrenAllocNode* dn = oren_find_node(desc);
        if (dn && dn->freed == 0 && dn->kind == OREN_ALLOC_STRUCT) {
            dn->freed = -1;
        }
        if (desc->data) {
            OrenAllocNode* bn = oren_find_node(desc->data);
            if (bn && bn->freed == 0 && bn->kind == OREN_ALLOC_STRING) {
                bn->freed = -1;
            }
        }
    }
#endif
}

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

void oren_llvm_runtime_register_list(int64_t desc_handle, int64_t* data, int64_t len) {
    if (desc_handle == 0 || data == NULL || len < 0) {
        oren_panic("llvm runtime list register: invalid allocation");
        return;
    }

    OrenLlvmList* desc = (OrenLlvmList*)(uintptr_t)desc_handle;
    if (desc->len != len || desc->data != data || desc->owner_kind != 1) {
        oren_panic("llvm runtime list register: descriptor metadata mismatch");
        return;
    }
    g_llvm_runtime_registered_lists++;
}

int64_t oren_llvm_runtime_alloc_calls(void) {
    return g_llvm_runtime_alloc_calls;
}

int64_t oren_llvm_runtime_registered_strings(void) {
    return g_llvm_runtime_registered_strings;
}

int64_t oren_llvm_runtime_registered_lists(void) {
    return g_llvm_runtime_registered_lists;
}

int64_t oren_llvm_runtime_root_depth(void) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t n = (int64_t)g_llvm_runtime_roots_len;
    pthread_mutex_unlock(&g_alloc_mutex);
    return n;
}

int64_t oren_llvm_runtime_root_pushes(void) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t n = g_llvm_runtime_root_pushes;
    pthread_mutex_unlock(&g_alloc_mutex);
    return n;
}

int64_t oren_llvm_runtime_safepoint_collections(void) {
    return g_llvm_runtime_safepoint_collections;
}
