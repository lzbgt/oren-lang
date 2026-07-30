typedef struct OrenLlvmString {
    int64_t len;
    char* data;
    int64_t owner_kind;
} OrenLlvmString;

typedef struct OrenLlvmList {
    int64_t len;
    int64_t* data;
    int64_t owner_kind;
    int64_t capacity;
} OrenLlvmList;

typedef struct OrenLlvmBytes {
    int64_t len;
    uint8_t* data;
    int64_t owner_kind;
} OrenLlvmBytes;

typedef struct OrenLlvmMap {
    int64_t len;
    int64_t* keys;
    int64_t* values;
    int64_t* key_kinds;
    int64_t owner_kind;
    int64_t capacity;
} OrenLlvmMap;

typedef struct OrenLlvmRootMark {
    size_t string_depth;
    size_t list_depth;
    size_t bytes_depth;
    size_t map_depth;
} OrenLlvmRootMark;

static int64_t g_llvm_runtime_alloc_calls = 0;
static int64_t g_llvm_runtime_registered_strings = 0;
static int64_t g_llvm_runtime_registered_lists = 0;
static int64_t g_llvm_runtime_registered_bytes = 0;
static int64_t g_llvm_runtime_registered_maps = 0;
static int64_t g_llvm_runtime_root_pushes = 0;
static int64_t g_llvm_runtime_safepoint_collections = 0;
static OrenLlvmString** g_llvm_runtime_string_roots = NULL;
static size_t g_llvm_runtime_string_roots_len = 0;
static size_t g_llvm_runtime_string_roots_cap = 0;
static OrenLlvmList** g_llvm_runtime_list_roots = NULL;
static size_t g_llvm_runtime_list_roots_len = 0;
static size_t g_llvm_runtime_list_roots_cap = 0;
static OrenLlvmBytes** g_llvm_runtime_bytes_roots = NULL;
static size_t g_llvm_runtime_bytes_roots_len = 0;
static size_t g_llvm_runtime_bytes_roots_cap = 0;
static OrenLlvmMap** g_llvm_runtime_map_roots = NULL;
static size_t g_llvm_runtime_map_roots_len = 0;
static size_t g_llvm_runtime_map_roots_cap = 0;
static OrenLlvmRootMark* g_llvm_runtime_root_marks = NULL;
static size_t g_llvm_runtime_root_marks_len = 0;
static size_t g_llvm_runtime_root_marks_cap = 0;

static int oren_llvm_runtime_force_gc_cached(void) {
    static int cached = -1;
    if (cached >= 0) return cached;
    const char* env = getenv("OREN_LLVM_FORCE_GC_AT_SAFEPOINT");
    cached = (env != NULL && env[0] != '\0' && strcmp(env, "0") != 0) ? 1 : 0;
    return cached;
}

static OrenAllocNode* oren_llvm_runtime_find_any_node_locked(void* ptr) {
    OrenThreadState* st = oren_thread_state();
    if (st) {
        OrenAllocNode* cur = st->local_allocs;
        while (cur) {
            if (cur->ptr == ptr) return cur;
            cur = cur->next;
        }
    }
    return oren_find_node(ptr);
}

static int oren_llvm_runtime_node_is_live_kind_locked(void* ptr, OrenAllocKind kind, int allow_marked) {
    OrenAllocNode* n = oren_llvm_runtime_find_any_node_locked(ptr);
    if (!n || n->kind != kind) return 0;
    if (n->freed == 0) return 1;
    return allow_marked && n->freed == -1;
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
                if (desc->owner_kind == 1 &&
                    desc->data != NULL &&
                    desc->len >= 0 &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRING, 0)) {
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
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRING, 0)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_list_desc_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenThreadState* st = oren_thread_state();
    if (st) {
        OrenAllocNode* cur = st->local_allocs;
        while (cur) {
            if (cur->ptr == (void*)(uintptr_t)desc_handle &&
                cur->freed == 0 &&
                cur->kind == OREN_ALLOC_STRUCT) {
                OrenLlvmList* desc = (OrenLlvmList*)(uintptr_t)desc_handle;
                if (desc->owner_kind == 1 &&
                    desc->data != NULL &&
                    desc->len >= 0 &&
                    desc->capacity >= desc->len &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRUCT, 0)) {
                    return cur;
                }
                return NULL;
            }
            cur = cur->next;
        }
    }
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || n->freed != 0 || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmList* desc = (OrenLlvmList*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        desc->capacity < desc->len ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRUCT, 0)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_bytes_desc_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenThreadState* st = oren_thread_state();
    if (st) {
        OrenAllocNode* cur = st->local_allocs;
        while (cur) {
            if (cur->ptr == (void*)(uintptr_t)desc_handle &&
                cur->freed == 0 &&
                cur->kind == OREN_ALLOC_STRUCT) {
                OrenLlvmBytes* desc = (OrenLlvmBytes*)(uintptr_t)desc_handle;
                if (desc->owner_kind == 1 &&
                    desc->data != NULL &&
                    desc->len >= 0 &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_RAW, 0)) {
                    return cur;
                }
                return NULL;
            }
            cur = cur->next;
        }
    }
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || n->freed != 0 || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmBytes* desc = (OrenLlvmBytes*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_RAW, 0)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_map_desc_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenThreadState* st = oren_thread_state();
    if (st) {
        OrenAllocNode* cur = st->local_allocs;
        while (cur) {
            if (cur->ptr == (void*)(uintptr_t)desc_handle &&
                cur->freed == 0 &&
                cur->kind == OREN_ALLOC_STRUCT) {
                OrenLlvmMap* desc = (OrenLlvmMap*)(uintptr_t)desc_handle;
                if (desc->owner_kind == 1 &&
                    desc->keys != NULL &&
                    desc->values != NULL &&
                    desc->key_kinds != NULL &&
                    desc->len >= 0 &&
                    desc->capacity >= desc->len &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->keys, OREN_ALLOC_STRUCT, 0) &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->values, OREN_ALLOC_STRUCT, 0) &&
                    oren_llvm_runtime_node_is_live_kind_locked(desc->key_kinds, OREN_ALLOC_STRUCT, 0)) {
                    return cur;
                }
                return NULL;
            }
            cur = cur->next;
        }
    }
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || n->freed != 0 || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmMap* desc = (OrenLlvmMap*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->keys == NULL ||
        desc->values == NULL ||
        desc->key_kinds == NULL ||
        desc->len < 0 ||
        desc->capacity < desc->len ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->keys, OREN_ALLOC_STRUCT, 0) ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->values, OREN_ALLOC_STRUCT, 0) ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->key_kinds, OREN_ALLOC_STRUCT, 0)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_string_desc_for_mark_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || (n->freed != 0 && n->freed != -1) || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmString* desc = (OrenLlvmString*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRING, 1)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_list_desc_for_mark_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || (n->freed != 0 && n->freed != -1) || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmList* desc = (OrenLlvmList*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        desc->capacity < desc->len ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_STRUCT, 1)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_bytes_desc_for_mark_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || (n->freed != 0 && n->freed != -1) || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmBytes* desc = (OrenLlvmBytes*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->data == NULL ||
        desc->len < 0 ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->data, OREN_ALLOC_RAW, 1)) return NULL;
    return n;
}

static OrenAllocNode* oren_llvm_runtime_find_map_desc_for_mark_locked(int64_t desc_handle) {
    if (desc_handle == 0) return NULL;
    OrenAllocNode* n = oren_find_node((void*)(uintptr_t)desc_handle);
    if (!n || (n->freed != 0 && n->freed != -1) || n->kind != OREN_ALLOC_STRUCT) return NULL;
    OrenLlvmMap* desc = (OrenLlvmMap*)(uintptr_t)desc_handle;
    if (desc->owner_kind != 1 ||
        desc->keys == NULL ||
        desc->values == NULL ||
        desc->key_kinds == NULL ||
        desc->len < 0 ||
        desc->capacity < desc->len ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->keys, OREN_ALLOC_STRUCT, 1) ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->values, OREN_ALLOC_STRUCT, 1) ||
        !oren_llvm_runtime_node_is_live_kind_locked(desc->key_kinds, OREN_ALLOC_STRUCT, 1)) return NULL;
    return n;
}

static void oren_llvm_runtime_mark_string_desc_locked(OrenLlvmString* desc) {
    if (!desc) return;
    OrenAllocNode* dn = oren_llvm_runtime_find_string_desc_for_mark_locked((int64_t)(uintptr_t)desc);
    if (!dn) return;
    if (dn->freed == 0) {
        dn->freed = -1;
    }
    if (desc->data) {
        OrenAllocNode* bn = oren_find_node(desc->data);
        if (bn && bn->freed == 0 && bn->kind == OREN_ALLOC_STRING) {
            bn->freed = -1;
        }
    }
}

static void oren_llvm_runtime_mark_bytes_desc_locked(OrenLlvmBytes* desc);
static void oren_llvm_runtime_mark_map_desc_rec_locked(OrenLlvmMap* desc, int depth);

static void oren_llvm_runtime_mark_list_desc_rec_locked(OrenLlvmList* desc, int depth) {
    if (!desc || depth <= 0) return;
    OrenAllocNode* dn = oren_llvm_runtime_find_list_desc_for_mark_locked((int64_t)(uintptr_t)desc);
    if (!dn) return;
    if (dn->freed == 0) {
        dn->freed = -1;
    }
    if (!desc->data) return;
    OrenAllocNode* bn = oren_find_node(desc->data);
    if (bn && bn->freed == 0 && bn->kind == OREN_ALLOC_STRUCT) {
        bn->freed = -1;
    }
    for (int64_t j = 0; j < desc->len; j++) {
        int64_t item = desc->data[j];
        OrenAllocNode* sn = oren_llvm_runtime_find_string_desc_for_mark_locked(item);
        if (sn) {
            oren_llvm_runtime_mark_string_desc_locked((OrenLlvmString*)sn->ptr);
            continue;
        }
        OrenAllocNode* ln = oren_llvm_runtime_find_list_desc_for_mark_locked(item);
        if (ln) {
            oren_llvm_runtime_mark_list_desc_rec_locked((OrenLlvmList*)ln->ptr, depth - 1);
            continue;
        }
        OrenAllocNode* bn = oren_llvm_runtime_find_bytes_desc_for_mark_locked(item);
        if (bn) {
            oren_llvm_runtime_mark_bytes_desc_locked((OrenLlvmBytes*)bn->ptr);
            continue;
        }
        OrenAllocNode* mn = oren_llvm_runtime_find_map_desc_for_mark_locked(item);
        if (mn) {
            oren_llvm_runtime_mark_map_desc_rec_locked((OrenLlvmMap*)mn->ptr, depth - 1);
        }
    }
}

static void oren_llvm_runtime_mark_list_desc_locked(OrenLlvmList* desc) {
    oren_llvm_runtime_mark_list_desc_rec_locked(desc, 64);
}

static void oren_llvm_runtime_mark_bytes_desc_locked(OrenLlvmBytes* desc) {
    if (!desc) return;
    OrenAllocNode* dn = oren_llvm_runtime_find_bytes_desc_for_mark_locked((int64_t)(uintptr_t)desc);
    if (!dn) return;
    if (dn->freed == 0) {
        dn->freed = -1;
    }
    if (desc->data) {
        OrenAllocNode* bn = oren_find_node(desc->data);
        if (bn && bn->freed == 0 && bn->kind == OREN_ALLOC_RAW) {
            bn->freed = -1;
        }
    }
}

static void oren_llvm_runtime_mark_descriptor_handle_locked(int64_t item, int depth) {
    if (depth <= 0) return;
    OrenAllocNode* sn = oren_llvm_runtime_find_string_desc_for_mark_locked(item);
    if (sn) {
        oren_llvm_runtime_mark_string_desc_locked((OrenLlvmString*)sn->ptr);
        return;
    }
    OrenAllocNode* ln = oren_llvm_runtime_find_list_desc_for_mark_locked(item);
    if (ln) {
        oren_llvm_runtime_mark_list_desc_rec_locked((OrenLlvmList*)ln->ptr, depth - 1);
        return;
    }
    OrenAllocNode* bn = oren_llvm_runtime_find_bytes_desc_for_mark_locked(item);
    if (bn) {
        oren_llvm_runtime_mark_bytes_desc_locked((OrenLlvmBytes*)bn->ptr);
        return;
    }
    OrenAllocNode* mn = oren_llvm_runtime_find_map_desc_for_mark_locked(item);
    if (mn) {
        oren_llvm_runtime_mark_map_desc_rec_locked((OrenLlvmMap*)mn->ptr, depth - 1);
    }
}

static void oren_llvm_runtime_mark_map_desc_rec_locked(OrenLlvmMap* desc, int depth) {
    if (!desc || depth <= 0) return;
    OrenAllocNode* dn = oren_llvm_runtime_find_map_desc_for_mark_locked((int64_t)(uintptr_t)desc);
    if (!dn) return;
    if (dn->freed == 0) {
        dn->freed = -1;
    }
    if (desc->keys) {
        OrenAllocNode* kn = oren_find_node(desc->keys);
        if (kn && kn->freed == 0 && kn->kind == OREN_ALLOC_STRUCT) {
            kn->freed = -1;
        }
    }
    if (desc->values) {
        OrenAllocNode* vn = oren_find_node(desc->values);
        if (vn && vn->freed == 0 && vn->kind == OREN_ALLOC_STRUCT) {
            vn->freed = -1;
        }
    }
    if (desc->key_kinds) {
        OrenAllocNode* kn = oren_find_node(desc->key_kinds);
        if (kn && kn->freed == 0 && kn->kind == OREN_ALLOC_STRUCT) {
            kn->freed = -1;
        }
    }
    for (int64_t j = 0; j < desc->len; j++) {
        if (desc->key_kinds[j] != 0) {
            oren_llvm_runtime_mark_descriptor_handle_locked(desc->keys[j], depth);
        }
        oren_llvm_runtime_mark_descriptor_handle_locked(desc->values[j], depth);
    }
}

static void oren_llvm_runtime_mark_map_desc_locked(OrenLlvmMap* desc) {
    oren_llvm_runtime_mark_map_desc_rec_locked(desc, 64);
}

int64_t oren_llvm_runtime_roots_mark(void) {
    pthread_mutex_lock(&g_alloc_mutex);
    if (g_llvm_runtime_root_marks_len == g_llvm_runtime_root_marks_cap) {
        size_t next_cap = g_llvm_runtime_root_marks_cap == 0 ? 16u : g_llvm_runtime_root_marks_cap * 2u;
        OrenLlvmRootMark* next_marks = (OrenLlvmRootMark*)realloc(
            g_llvm_runtime_root_marks,
            next_cap * sizeof(OrenLlvmRootMark)
        );
        if (!next_marks) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime roots: mark grow failed");
            return 0;
        }
        g_llvm_runtime_root_marks = next_marks;
        g_llvm_runtime_root_marks_cap = next_cap;
    }
    if (g_llvm_runtime_root_marks_len >= (size_t)INT64_MAX) {
        pthread_mutex_unlock(&g_alloc_mutex);
        oren_panic("llvm runtime roots: mark overflow");
        return 0;
    }
    size_t mark_index = g_llvm_runtime_root_marks_len++;
    g_llvm_runtime_root_marks[mark_index].string_depth = g_llvm_runtime_string_roots_len;
    g_llvm_runtime_root_marks[mark_index].list_depth = g_llvm_runtime_list_roots_len;
    g_llvm_runtime_root_marks[mark_index].bytes_depth = g_llvm_runtime_bytes_roots_len;
    g_llvm_runtime_root_marks[mark_index].map_depth = g_llvm_runtime_map_roots_len;
    pthread_mutex_unlock(&g_alloc_mutex);
    return (int64_t)(mark_index + 1u);
}

void oren_llvm_runtime_roots_push_string(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_llvm_runtime_find_string_desc_locked(desc_handle);
    if (!n) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (g_llvm_runtime_string_roots_len == g_llvm_runtime_string_roots_cap) {
        size_t next_cap = g_llvm_runtime_string_roots_cap == 0 ? 16u : g_llvm_runtime_string_roots_cap * 2u;
        OrenLlvmString** next_roots = (OrenLlvmString**)realloc(
            g_llvm_runtime_string_roots,
            next_cap * sizeof(OrenLlvmString*)
        );
        if (!next_roots) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime roots: grow failed");
            return;
        }
        g_llvm_runtime_string_roots = next_roots;
        g_llvm_runtime_string_roots_cap = next_cap;
    }
    g_llvm_runtime_string_roots[g_llvm_runtime_string_roots_len++] = (OrenLlvmString*)n->ptr;
    g_llvm_runtime_root_pushes++;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_roots_push_list(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_llvm_runtime_find_list_desc_locked(desc_handle);
    if (!n) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (g_llvm_runtime_list_roots_len == g_llvm_runtime_list_roots_cap) {
        size_t next_cap = g_llvm_runtime_list_roots_cap == 0 ? 16u : g_llvm_runtime_list_roots_cap * 2u;
        OrenLlvmList** next_roots = (OrenLlvmList**)realloc(
            g_llvm_runtime_list_roots,
            next_cap * sizeof(OrenLlvmList*)
        );
        if (!next_roots) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime list roots: grow failed");
            return;
        }
        g_llvm_runtime_list_roots = next_roots;
        g_llvm_runtime_list_roots_cap = next_cap;
    }
    g_llvm_runtime_list_roots[g_llvm_runtime_list_roots_len++] = (OrenLlvmList*)n->ptr;
    g_llvm_runtime_root_pushes++;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_roots_push_bytes(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_llvm_runtime_find_bytes_desc_locked(desc_handle);
    if (!n) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (g_llvm_runtime_bytes_roots_len == g_llvm_runtime_bytes_roots_cap) {
        size_t next_cap = g_llvm_runtime_bytes_roots_cap == 0 ? 16u : g_llvm_runtime_bytes_roots_cap * 2u;
        OrenLlvmBytes** next_roots = (OrenLlvmBytes**)realloc(
            g_llvm_runtime_bytes_roots,
            next_cap * sizeof(OrenLlvmBytes*)
        );
        if (!next_roots) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime bytes roots: grow failed");
            return;
        }
        g_llvm_runtime_bytes_roots = next_roots;
        g_llvm_runtime_bytes_roots_cap = next_cap;
    }
    g_llvm_runtime_bytes_roots[g_llvm_runtime_bytes_roots_len++] = (OrenLlvmBytes*)n->ptr;
    g_llvm_runtime_root_pushes++;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_roots_push_map(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_llvm_runtime_find_map_desc_locked(desc_handle);
    if (!n) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (g_llvm_runtime_map_roots_len == g_llvm_runtime_map_roots_cap) {
        size_t next_cap = g_llvm_runtime_map_roots_cap == 0 ? 16u : g_llvm_runtime_map_roots_cap * 2u;
        OrenLlvmMap** next_roots = (OrenLlvmMap**)realloc(
            g_llvm_runtime_map_roots,
            next_cap * sizeof(OrenLlvmMap*)
        );
        if (!next_roots) {
            pthread_mutex_unlock(&g_alloc_mutex);
            oren_panic("llvm runtime map roots: grow failed");
            return;
        }
        g_llvm_runtime_map_roots = next_roots;
        g_llvm_runtime_map_roots_cap = next_cap;
    }
    g_llvm_runtime_map_roots[g_llvm_runtime_map_roots_len++] = (OrenLlvmMap*)n->ptr;
    g_llvm_runtime_root_pushes++;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_roots_reset(int64_t mark) {
    pthread_mutex_lock(&g_alloc_mutex);
    if (mark <= 0 || (size_t)mark > g_llvm_runtime_root_marks_len) {
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    size_t mark_index = (size_t)mark - 1u;
    OrenLlvmRootMark snap = g_llvm_runtime_root_marks[mark_index];
    if (snap.string_depth < g_llvm_runtime_string_roots_len) {
        g_llvm_runtime_string_roots_len = snap.string_depth;
    }
    if (snap.list_depth < g_llvm_runtime_list_roots_len) {
        g_llvm_runtime_list_roots_len = snap.list_depth;
    }
    if (snap.bytes_depth < g_llvm_runtime_bytes_roots_len) {
        g_llvm_runtime_bytes_roots_len = snap.bytes_depth;
    }
    if (snap.map_depth < g_llvm_runtime_map_roots_len) {
        g_llvm_runtime_map_roots_len = snap.map_depth;
    }
    g_llvm_runtime_root_marks_len = mark_index;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_llvm_runtime_safepoint_poll(void) {
    if (!oren_llvm_runtime_force_gc_cached()) return;
    g_llvm_runtime_safepoint_collections++;
    oren_gc_collect();
}

static void oren_llvm_runtime_mark_roots(void) {
#ifndef OREN_NO_GC
    for (size_t i = 0; i < g_llvm_runtime_string_roots_len; i++) {
        oren_llvm_runtime_mark_string_desc_locked(g_llvm_runtime_string_roots[i]);
    }
    for (size_t i = 0; i < g_llvm_runtime_list_roots_len; i++) {
        oren_llvm_runtime_mark_list_desc_locked(g_llvm_runtime_list_roots[i]);
    }
    for (size_t i = 0; i < g_llvm_runtime_bytes_roots_len; i++) {
        oren_llvm_runtime_mark_bytes_desc_locked(g_llvm_runtime_bytes_roots[i]);
    }
    for (size_t i = 0; i < g_llvm_runtime_map_roots_len; i++) {
        oren_llvm_runtime_mark_map_desc_locked(g_llvm_runtime_map_roots[i]);
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
    } else if (alloc_kind == 5) {
        oren_register_alloc(p, OREN_ALLOC_RAW);
    } else {
        // LLVM descriptors and list payload arrays are opaque runtime structs.
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
    if (desc->len != len || desc->data != data || desc->owner_kind != 1 || desc->capacity < len) {
        oren_panic("llvm runtime list register: descriptor metadata mismatch");
        return;
    }
    g_llvm_runtime_registered_lists++;
}

void oren_llvm_runtime_register_bytes(int64_t desc_handle, uint8_t* data, int64_t len) {
    if (desc_handle == 0 || data == NULL || len < 0) {
        oren_panic("llvm runtime bytes register: invalid allocation");
        return;
    }

    OrenLlvmBytes* desc = (OrenLlvmBytes*)(uintptr_t)desc_handle;
    if (desc->len != len || desc->data != data || desc->owner_kind != 1) {
        oren_panic("llvm runtime bytes register: descriptor metadata mismatch");
        return;
    }
    g_llvm_runtime_registered_bytes++;
}

void oren_llvm_runtime_register_map(
    int64_t desc_handle,
    int64_t* keys,
    int64_t* values,
    int64_t* key_kinds,
    int64_t len,
    int64_t capacity
) {
    if (desc_handle == 0 || keys == NULL || values == NULL || key_kinds == NULL || len < 0 || capacity < len) {
        oren_panic("llvm runtime map register: invalid allocation");
        return;
    }

    OrenLlvmMap* desc = (OrenLlvmMap*)(uintptr_t)desc_handle;
    if (desc->len != len || desc->keys != keys || desc->values != values ||
        desc->key_kinds != key_kinds || desc->owner_kind != 1 || desc->capacity != capacity) {
        oren_panic("llvm runtime map register: descriptor metadata mismatch");
        return;
    }
    g_llvm_runtime_registered_maps++;
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

int64_t oren_llvm_runtime_registered_bytes(void) {
    return g_llvm_runtime_registered_bytes;
}

int64_t oren_llvm_runtime_registered_maps(void) {
    return g_llvm_runtime_registered_maps;
}

int64_t oren_llvm_runtime_is_live_string(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t live = oren_llvm_runtime_find_string_desc_locked(desc_handle) ? 1 : 0;
    pthread_mutex_unlock(&g_alloc_mutex);
    return live;
}

int64_t oren_llvm_runtime_is_live_list(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t live = oren_llvm_runtime_find_list_desc_locked(desc_handle) ? 1 : 0;
    pthread_mutex_unlock(&g_alloc_mutex);
    return live;
}

int64_t oren_llvm_runtime_is_live_bytes(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t live = oren_llvm_runtime_find_bytes_desc_locked(desc_handle) ? 1 : 0;
    pthread_mutex_unlock(&g_alloc_mutex);
    return live;
}

int64_t oren_llvm_runtime_is_live_map(int64_t desc_handle) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t live = oren_llvm_runtime_find_map_desc_locked(desc_handle) ? 1 : 0;
    pthread_mutex_unlock(&g_alloc_mutex);
    return live;
}

int64_t oren_llvm_runtime_root_depth(void) {
    pthread_mutex_lock(&g_alloc_mutex);
    int64_t n = (int64_t)(
        g_llvm_runtime_string_roots_len +
        g_llvm_runtime_list_roots_len +
        g_llvm_runtime_bytes_roots_len +
        g_llvm_runtime_map_roots_len
    );
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
