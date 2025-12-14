#include "runtime.h"
#include <sys/stat.h>
#include <pthread.h>

OrenValue OREN_NIL;
OrenValue OREN_TRUE;
OrenValue OREN_FALSE;
static OrenList *OREN_ARG_LIST = NULL;

typedef enum {
    OREN_ALLOC_STRING = 1,
    OREN_ALLOC_LIST = 2,
    OREN_ALLOC_MAP = 3,
    OREN_ALLOC_STRUCT = 4
} OrenAllocKind;

typedef struct OrenAllocNode {
    void* ptr;
    OrenAllocKind kind;
    int freed;
    struct OrenAllocNode* next;
} OrenAllocNode;

static OrenAllocNode* g_allocs = NULL;
static pthread_mutex_t g_alloc_mutex = PTHREAD_MUTEX_INITIALIZER;
static OrenAllocNode* g_roots = NULL;
static pthread_mutex_t g_collection_mutex = PTHREAD_MUTEX_INITIALIZER;

static void lock_collections() { pthread_mutex_lock(&g_collection_mutex); }
static void unlock_collections() { pthread_mutex_unlock(&g_collection_mutex); }

void oren_register_root(OrenValue* slot) {
#ifdef OREN_NO_GC
    (void)slot;
    return;
#endif
    if (slot == NULL) return;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = (OrenAllocNode*)malloc(sizeof(OrenAllocNode));
    if (!n) {
        fprintf(stderr, "root registry failed\n");
        exit(1);
    }
    n->ptr = slot;
    n->kind = 0; // root marker
    n->freed = 0;
    n->next = g_roots;
    g_roots = n;
    pthread_mutex_unlock(&g_alloc_mutex);
}

void oren_unregister_root(OrenValue* slot) {
#ifdef OREN_NO_GC
    (void)slot;
    return;
#endif
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* prev = NULL;
    OrenAllocNode* cur = g_roots;
    while (cur) {
        if (cur->ptr == slot) {
            if (prev) prev->next = cur->next; else g_roots = cur->next;
            free(cur);
            break;
        }
        prev = cur;
        cur = cur->next;
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

static void oren_register_alloc(void* ptr, OrenAllocKind kind) {
    if (ptr == NULL) return;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = (OrenAllocNode*)malloc(sizeof(OrenAllocNode));
    if (!n) {
        fprintf(stderr, "alloc registry failed\n");
        exit(1);
    }
    n->ptr = ptr;
    n->kind = kind;
    n->freed = 0;
    n->next = g_allocs;
    g_allocs = n;
    pthread_mutex_unlock(&g_alloc_mutex);
}

static OrenAllocNode* oren_find_node(void* ptr) {
    OrenAllocNode* cur = g_allocs;
    while (cur) {
        if (cur->ptr == ptr) return cur;
        cur = cur->next;
    }
    return NULL;
}

static void oren_mark_value(OrenValue v) {
#ifdef OREN_NO_GC
    return;
#endif
    if (v.type == OREN_TYPE_STRING) {
        OrenAllocNode* n = oren_find_node(v.as.string_val);
        if (n && n->freed == 0) n->freed = -1;
        return;
    }
    if (v.type == OREN_TYPE_LIST) {
        OrenList* lst = v.as.list_val;
        if (!lst) return;
        OrenAllocNode* n = oren_find_node(lst);
        if (n && n->freed == 0) {
            n->freed = -1;
            for (int i = 0; i < lst->count; i++) {
                oren_mark_value(lst->items[i]);
            }
        }
        return;
    }
    if (v.type == OREN_TYPE_MAP) {
        OrenMap* mp = v.as.map_val;
        if (!mp) return;
        OrenAllocNode* n = oren_find_node(mp);
        if (n && n->freed == 0) {
            n->freed = -1;
            for (int i = 0; i < mp->count; i++) {
                oren_mark_value(mp->keys[i]);
                oren_mark_value(mp->values[i]);
            }
        }
        return;
    }
}

void oren_gc_collect() {
#ifdef OREN_NO_GC
    return;
#endif
    pthread_mutex_lock(&g_alloc_mutex);
    // Clear prior marks (-1 -> 0)
    OrenAllocNode* n = g_allocs;
    while (n) {
        if (n->freed == -1) n->freed = 0;
        n = n->next;
    }
    // Mark from roots
    OrenAllocNode* r = g_roots;
    while (r) {
        OrenValue* slot = (OrenValue*)r->ptr;
        if (slot) {
            oren_mark_value(*slot);
        }
        r = r->next;
    }
    // Sweep: free unmarked (freed==0) tracked allocations
    OrenAllocNode* prev = NULL;
    n = g_allocs;
    while (n) {
        int marked = (n->freed == -1);
        if (!marked && n->freed == 0) {
            if (n->kind == OREN_ALLOC_STRING) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_LIST) {
                OrenList* lst = (OrenList*)n->ptr;
                if (lst->items) free(lst->items);
                free(lst);
            } else if (n->kind == OREN_ALLOC_MAP) {
                OrenMap* mp = (OrenMap*)n->ptr;
                if (mp->keys) free(mp->keys);
                if (mp->values) free(mp->values);
                free(mp);
            } else {
                free(n->ptr);
            }
            OrenAllocNode* to_free = n;
            n = n->next;
            if (prev) prev->next = n; else g_allocs = n;
            free(to_free);
            continue;
        }
        n->freed = 0; // clear mark
        prev = n;
        n = n->next;
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}

static void oren_store_args(int argc, char **argv) {
    if (argc <= 0) return;
    OREN_ARG_LIST = malloc(sizeof(OrenList));
    oren_register_alloc(OREN_ARG_LIST, OREN_ALLOC_LIST);
    OREN_ARG_LIST->count = argc;
    OREN_ARG_LIST->capacity = argc;
    OREN_ARG_LIST->items = malloc(sizeof(OrenValue) * argc);
    for (int i = 0; i < argc; i++) {
        OREN_ARG_LIST->items[i] = oren_string(argv[i]);
    }
}

OrenValue oren_args() {
    if (OREN_ARG_LIST == NULL) {
        OrenValue empty;
        empty.type = OREN_TYPE_LIST;
        empty.as.list_val = malloc(sizeof(OrenList));
        oren_register_alloc(empty.as.list_val, OREN_ALLOC_LIST);
        empty.as.list_val->count = 0;
        empty.as.list_val->capacity = 0;
        empty.as.list_val->items = NULL;
        return empty;
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = OREN_ARG_LIST;
    return v;
}

void oren_init(int argc, char **argv) {
    OREN_NIL.type = OREN_TYPE_NIL;
    OREN_TRUE.type = OREN_TYPE_BOOL;
    OREN_TRUE.as.bool_val = 1;
    OREN_FALSE.type = OREN_TYPE_BOOL;
    OREN_FALSE.as.bool_val = 0;

    oren_store_args(argc, argv);

#ifdef OREN_ENABLE_PYTHON
    Py_Initialize();
    // Python manages its own argv; callers can set sys.argv from Oren if needed.
#endif
}

#ifdef OREN_ENABLE_PYTHON
static OrenValue oren_py_to_oren(PyObject* obj) {
    if (obj == Py_None) return OREN_NIL;
    if (PyBool_Check(obj)) return (obj == Py_True) ? OREN_TRUE : OREN_FALSE;
    if (PyLong_Check(obj)) return oren_int(PyLong_AsLongLong(obj));
    if (PyFloat_Check(obj)) return oren_float(PyFloat_AsDouble(obj));
    if (PyUnicode_Check(obj)) return oren_string(PyUnicode_AsUTF8(obj));

    // Wrap generic python object
    OrenValue v;
    v.type = OREN_TYPE_PY_OBJ;
    v.as.py_obj = obj;
    // IncRef? No, usually return new ref.
    return v;
}

static PyObject* oren_to_py(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_NIL: Py_RETURN_NONE;
        case OREN_TYPE_INT: return PyLong_FromLongLong(v.as.int_val);
        case OREN_TYPE_FLOAT: return PyFloat_FromDouble(v.as.float_val);
        case OREN_TYPE_BOOL: return PyBool_FromLong(v.as.bool_val);
        case OREN_TYPE_STRING: return PyUnicode_FromString(v.as.string_val);
        case OREN_TYPE_PY_OBJ:
            Py_INCREF(v.as.py_obj);
            return v.as.py_obj;
        case OREN_TYPE_LIST: {
            PyObject* list = PyList_New(v.as.list_val->count);
            for (int i = 0; i < v.as.list_val->count; i++) {
                 PyList_SetItem(list, i, oren_to_py(v.as.list_val->items[i]));
            }
            return list;
        }
        case OREN_TYPE_MAP: {
             PyObject* dict = PyDict_New();
             for (int i = 0; i < v.as.map_val->count; i++) {
                 PyDict_SetItem(dict, oren_to_py(v.as.map_val->keys[i]), oren_to_py(v.as.map_val->values[i]));
             }
             return dict;
        }
    }
    Py_RETURN_NONE;
}
#endif

OrenValue oren_int(long long v) {
    OrenValue val;
    val.type = OREN_TYPE_INT;
    val.as.int_val = v;
    return val;
}

OrenValue oren_float(double v) {
    OrenValue val;
    val.type = OREN_TYPE_FLOAT;
    val.as.float_val = v;
    return val;
}

OrenValue oren_string(const char* s) {
    OrenValue val;
    val.type = OREN_TYPE_STRING;
    val.as.string_val = strdup(s);
    oren_register_alloc(val.as.string_val, OREN_ALLOC_STRING);
    return val;
}

OrenValue oren_bool(int v) {
    return v ? OREN_TRUE : OREN_FALSE;
}

int oren_is_truthy(OrenValue v) {
    if (v.type == OREN_TYPE_NIL) return 0;
    if (v.type == OREN_TYPE_BOOL) return v.as.bool_val;
    return 1;
}

OrenValue oren_add(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val + b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val + b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val + b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val + (double)b.as.int_val);
    }
    // TODO: String concat
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
         // POC: simplistic concat
         char* new_s = malloc(strlen(a.as.string_val) + strlen(b.as.string_val) + 1);
         strcpy(new_s, a.as.string_val);
         strcat(new_s, b.as.string_val);
         OrenValue val;
         val.type = OREN_TYPE_STRING;
         val.as.string_val = new_s;
         return val;
    }
    printf("Runtime Error: Type mismatch in add\n");
    exit(1);
}

OrenValue oren_sub(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val - b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val - b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val - b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val - (double)b.as.int_val);
    }
    printf("Runtime Error: Type mismatch in sub\n");
    exit(1);
}

OrenValue oren_mul(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val * b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val * b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val * b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val * (double)b.as.int_val);
    }
    printf("Runtime Error: Type mismatch in mul\n");
    exit(1);
}

OrenValue oren_div(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_int(a.as.int_val / b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_float(a.as.float_val / b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_float((double)a.as.int_val / b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_float(a.as.float_val / (double)b.as.int_val);
    }
    printf("Runtime Error: Type mismatch in div\n");
    exit(1);
}

static uint64_t oren_u64(OrenValue v, const char *op) {
    if (v.type != OREN_TYPE_INT) {
        printf("Runtime Error: %s expects int\n", op);
        exit(1);
    }
    return (uint64_t)v.as.int_val;
}

OrenValue oren_band(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitand");
    uint64_t y = oren_u64(b, "bitand");
    return oren_int((long long)(x & y));
}

OrenValue oren_bor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitor");
    uint64_t y = oren_u64(b, "bitor");
    return oren_int((long long)(x | y));
}

OrenValue oren_bxor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitxor");
    uint64_t y = oren_u64(b, "bitxor");
    return oren_int((long long)(x ^ y));
}

OrenValue oren_shl(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "shl");
    uint64_t s = oren_u64(b, "shl");
    if (s >= 64) return oren_int(0);
    return oren_int((long long)(x << s));
}

OrenValue oren_shr(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "shr");
    uint64_t s = oren_u64(b, "shr");
    if (s >= 64) return oren_int(0);
    return oren_int((long long)(x >> s));
}

OrenValue oren_bnot(OrenValue v) {
    uint64_t x = oren_u64(v, "bnot");
    return oren_int((long long)(~x));
}

OrenValue oren_eq(OrenValue a, OrenValue b) {
    if (a.type != b.type) return OREN_FALSE;
    switch (a.type) {
        case OREN_TYPE_INT: return oren_bool(a.as.int_val == b.as.int_val);
        case OREN_TYPE_FLOAT: return oren_bool(a.as.float_val == b.as.float_val);
        case OREN_TYPE_BOOL: return oren_bool(a.as.bool_val == b.as.bool_val);
        case OREN_TYPE_STRING: return oren_bool(strcmp(a.as.string_val, b.as.string_val) == 0);
        case OREN_TYPE_NIL: return OREN_TRUE;
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            // Check identity or equality
            int res = PyObject_RichCompareBool(a.as.py_obj, b.as.py_obj, Py_EQ);
            if (res == -1) { PyErr_Clear(); return OREN_FALSE; }
            return oren_bool(res);
#else
            printf("Runtime Error: Python support is disabled\n");
            exit(1);
#endif
        }
        case OREN_TYPE_LIST:
            // Identity or deep equal? Identity for now
            return oren_bool(a.as.list_val == b.as.list_val);
        case OREN_TYPE_MAP:
            return oren_bool(a.as.map_val == b.as.map_val);
    }
    return OREN_FALSE;
}

#ifdef OREN_ENABLE_PYTHON
OrenValue oren_py_import(OrenValue name) {
    if (name.type != OREN_TYPE_STRING) {
        printf("Runtime Error: import expects string\n");
        exit(1);
    }
    PyObject* mod = PyImport_ImportModule(name.as.string_val);
    if (!mod) {
        PyErr_Print();
        printf("Runtime Error: Could not import python module %s\n", name.as.string_val);
        exit(1);
    }
    OrenValue v;
    v.type = OREN_TYPE_PY_OBJ;
    v.as.py_obj = mod;
    return v;
}
#else
OrenValue oren_py_import(OrenValue name) {
    (void)name;
    printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
    exit(1);
}
#endif

OrenValue oren_get_attr(OrenValue obj, const char* attr) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* val = PyObject_GetAttrString(obj.as.py_obj, attr);
        if (!val) {
            PyErr_Print();
            printf("Runtime Error: Python object has no attribute '%s'\n", attr);
            exit(1);
        }
        return oren_py_to_oren(val);
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
        exit(1);
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_map_get(obj, oren_string(attr));
    }
    printf("Runtime Error: get_attr only supported for Python objects and maps currently\n");
    exit(1);
}

OrenValue oren_set_attr(OrenValue obj, const char* attr, OrenValue value) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_val = oren_to_py(value);
        if (PyObject_SetAttrString(obj.as.py_obj, attr, py_val) != 0) {
            PyErr_Print();
            printf("Runtime Error: failed to set attribute '%s'\n", attr);
            exit(1);
        }
        Py_DECREF(py_val);
        return value;
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        (void)attr;
        (void)value;
        printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
        exit(1);
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_index_set(obj, oren_string(attr), value);
    }
    printf("Runtime Error: set_attr only supported for Python objects and maps currently\n");
    exit(1);
}

OrenValue oren_new_list(int count, ...) {
    va_list args;
    va_start(args, count);

    lock_collections();
    OrenList* list = malloc(sizeof(OrenList));
    oren_register_alloc(list, OREN_ALLOC_LIST);
    list->count = count;
    list->capacity = count;
    list->items = malloc(sizeof(OrenValue) * count);

    for (int i = 0; i < count; i++) {
        list->items[i] = va_arg(args, OrenValue);
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    unlock_collections();
    return v;
}

OrenValue oren_list_len(OrenValue list) {
    if (list.type != OREN_TYPE_LIST) {
        printf("Runtime Error: len on non-list\n");
        exit(1);
    }
    lock_collections();
    int c = list.as.list_val->count;
    unlock_collections();
    return oren_int(c);
}

OrenValue oren_list_push(OrenValue list, OrenValue value) {
    if (list.type != OREN_TYPE_LIST) {
        printf("Runtime Error: push on non-list\n");
        exit(1);
    }
    OrenList *l = list.as.list_val;
    lock_collections();
    if (l->count >= l->capacity) {
        int newCap = l->capacity == 0 ? 4 : l->capacity * 2;
        l->items = realloc(l->items, sizeof(OrenValue) * newCap);
        l->capacity = newCap;
    }
    l->items[l->count] = value;
    l->count += 1;
    unlock_collections();
    return list;
}

OrenValue oren_list_get(OrenValue list, OrenValue index) {
    if (list.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
             printf("Runtime Error: index must be integer\n");
             exit(1);
        }
        int idx = (int)index.as.int_val;
        if (idx < 0 || idx >= list.as.list_val->count) {
             printf("Runtime Error: index out of bounds (idx=%d, count=%d, cap=%d)\n", idx, list.as.list_val->count, list.as.list_val->capacity);
             exit(1);
        }
        lock_collections();
        OrenValue v = list.as.list_val->items[idx];
        unlock_collections();
        return v;
    }
    // Also support python list get item?
#ifdef OREN_ENABLE_PYTHON
    if (list.type == OREN_TYPE_PY_OBJ) {
         PyObject* item = PyObject_GetItem(list.as.py_obj, oren_to_py(index)); // This leaks the index py object reference
         if (!item) {
             PyErr_Print();
             exit(1);
         }
         return oren_py_to_oren(item);
    }
#else
    if (list.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
        exit(1);
    }
#endif

    // Support map access via []
    if (list.type == OREN_TYPE_MAP) {
        return oren_map_get(list, index);
    }

    printf("Runtime Error: index get on non-list/map\n");
    exit(1);
}

OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value) {
    if (container.type == OREN_TYPE_LIST) {
        if (index.type != OREN_TYPE_INT) {
            printf("Runtime Error: index must be integer\n");
            exit(1);
        }
        int idx = (int)index.as.int_val;
        if (idx < 0) {
            printf("Runtime Error: index out of bounds (idx=%d, count=%d, cap=%d)\n", idx, container.as.list_val->count, container.as.list_val->capacity);
            exit(1);
        }
        if (idx >= container.as.list_val->capacity) {
            int newCap = container.as.list_val->capacity == 0 ? (idx + 1) : container.as.list_val->capacity;
            while (newCap <= idx) { newCap *= 2; }
            container.as.list_val->items = realloc(container.as.list_val->items, sizeof(OrenValue) * newCap);
            container.as.list_val->capacity = newCap;
        }
        if (idx >= container.as.list_val->count) {
            // zero-fill new slots
            for (int i = container.as.list_val->count; i <= idx; i++) {
                container.as.list_val->items[i] = OREN_NIL;
            }
            container.as.list_val->count = idx + 1;
        }
        lock_collections();
        container.as.list_val->items[idx] = value;
        unlock_collections();
        return value;
    }

    if (container.type == OREN_TYPE_MAP) {
        OrenMap* map = container.as.map_val;
        lock_collections();
        for (int i = 0; i < map->count; i++) {
            if (oren_eq(map->keys[i], index).as.bool_val) {
                map->values[i] = value;
                unlock_collections();
                return value;
            }
        }
        if (map->count >= map->capacity) {
            int newCap = map->capacity == 0 ? 4 : map->capacity * 2;
            map->keys = realloc(map->keys, sizeof(OrenValue) * newCap);
            map->values = realloc(map->values, sizeof(OrenValue) * newCap);
            map->capacity = newCap;
        }
        map->keys[map->count] = index;
        map->values[map->count] = value;
        map->count += 1;
        unlock_collections();
        return value;
    }

#ifdef OREN_ENABLE_PYTHON
    if (container.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_index = oren_to_py(index);
        PyObject* py_value = oren_to_py(value);
        if (PyObject_SetItem(container.as.py_obj, py_index, py_value) != 0) {
            PyErr_Print();
            printf("Runtime Error: python setitem failed\n");
            exit(1);
        }
        Py_DECREF(py_index);
        Py_DECREF(py_value);
        return value;
    }
#else
    if (container.type == OREN_TYPE_PY_OBJ) {
        (void)index;
        (void)value;
        printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
        exit(1);
    }
#endif

    printf("Runtime Error: index set on non-list/map\n");
    exit(1);
}

OrenValue oren_new_map(int count, ...) {
    va_list args;
    va_start(args, count);

    lock_collections();
    OrenMap* map = malloc(sizeof(OrenMap));
    oren_register_alloc(map, OREN_ALLOC_MAP);
    map->count = count;
    map->capacity = count;
    map->keys = malloc(sizeof(OrenValue) * count);
    map->values = malloc(sizeof(OrenValue) * count);

    for (int i = 0; i < count; i++) {
        map->keys[i] = va_arg(args, OrenValue);
        map->values[i] = va_arg(args, OrenValue);
    }

    va_end(args);

    OrenValue v;
    v.type = OREN_TYPE_MAP;
    v.as.map_val = map;
    unlock_collections();
    return v;
}

OrenValue oren_map_get(OrenValue map, OrenValue key) {
    if (map.type != OREN_TYPE_MAP) return OREN_NIL;
    lock_collections();
    for (int i = 0; i < map.as.map_val->count; i++) {
        OrenValue k = map.as.map_val->keys[i];
        if (oren_eq(k, key).as.bool_val) {
            OrenValue v = map.as.map_val->values[i];
            unlock_collections();
            return v;
        }
    }
    unlock_collections();
    return OREN_NIL;
}

OrenValue oren_call_obj(OrenValue fn, int count, ...) {
    va_list args;
    va_start(args, count);

#ifdef OREN_ENABLE_PYTHON
    if (fn.type == OREN_TYPE_PY_OBJ) {
        if (!PyCallable_Check(fn.as.py_obj)) {
            printf("Runtime Error: Python object is not callable\n");
            exit(1);
        }
        PyObject* py_args = PyTuple_New(count);
        for (int i = 0; i < count; i++) {
            OrenValue arg = va_arg(args, OrenValue);
            PyTuple_SetItem(py_args, i, oren_to_py(arg)); // Steals ref
        }
        PyObject* result = PyObject_CallObject(fn.as.py_obj, py_args);
        Py_DECREF(py_args);
        if (!result) {
            PyErr_Print();
            exit(1);
        }
        va_end(args);
        return oren_py_to_oren(result);
    }
#else
    if (fn.type == OREN_TYPE_PY_OBJ) {
        (void)count;
        printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
        exit(1);
    }
#endif

    printf("Runtime Error: Calling non-callable object (only Python callables supported via generic call so far)\n");
    exit(1);
}

OrenValue oren_neq(OrenValue a, OrenValue b) {
    OrenValue eq = oren_eq(a, b);
    return eq.as.bool_val ? OREN_FALSE : OREN_TRUE;
}

OrenValue oren_lt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val < b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val < b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val < (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) < 0);
    }
    printf("Runtime Error: Type mismatch in lt\n");
    exit(1);
}

OrenValue oren_gt(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val > b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val > b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val > (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) > 0);
    }
    printf("Runtime Error: Type mismatch in gt\n");
    exit(1);
}

OrenValue oren_lte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val <= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val <= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val <= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) <= 0);
    }
    printf("Runtime Error: Type mismatch in lte\n");
    exit(1);
}

OrenValue oren_gte(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.int_val >= b.as.int_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool(a.as.float_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_FLOAT) {
        return oren_bool((double)a.as.int_val >= b.as.float_val);
    }
    if (a.type == OREN_TYPE_FLOAT && b.type == OREN_TYPE_INT) {
        return oren_bool(a.as.float_val >= (double)b.as.int_val);
    }
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
        return oren_bool(strcmp(a.as.string_val, b.as.string_val) >= 0);
    }
    printf("Runtime Error: Type mismatch in gte\n");
    exit(1);
}

void oren_print(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_INT: printf("%lld\n", v.as.int_val); break;
        case OREN_TYPE_FLOAT: printf("%f\n", v.as.float_val); break;
        case OREN_TYPE_BOOL: printf("%s\n", v.as.bool_val ? "true" : "false"); break;
        case OREN_TYPE_STRING: printf("%s\n", v.as.string_val); break;
        case OREN_TYPE_NIL: printf("nil\n"); break;
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            PyObject* str = PyObject_Str(v.as.py_obj);
            printf("%s\n", PyUnicode_AsUTF8(str));
            Py_DECREF(str);
            break;
#else
            printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
            exit(1);
#endif
        }
        case OREN_TYPE_LIST: {
            printf("[");
            for (int i = 0; i < v.as.list_val->count; i++) {
                // Recursive print? Using oren_print_multi style
                // Simplification for now
                // We cannot reuse oren_print directly because it prints newline
                // Let's just print type name for nested for POC or simplistic recurse
                if (i > 0) printf(", ");
                // Hack: call print logic without newline
                OrenValue val = v.as.list_val->items[i];
                 switch (val.type) {
                    case OREN_TYPE_INT: printf("%lld", val.as.int_val); break;
                    case OREN_TYPE_FLOAT: printf("%f", val.as.float_val); break;
                    case OREN_TYPE_BOOL: printf("%s", val.as.bool_val ? "true" : "false"); break;
                    case OREN_TYPE_STRING: printf("%s", val.as.string_val); break;
                    case OREN_TYPE_NIL: printf("nil"); break;
                    default: printf("..."); break;
                }
            }
            printf("]\n");
            break;
        }
        case OREN_TYPE_MAP: {
             printf("{");
             for (int i = 0; i < v.as.map_val->count; i++) {
                 if (i > 0) printf(", ");
                 // Simplified key print
                 OrenValue key = v.as.map_val->keys[i];
                 switch (key.type) {
                     case OREN_TYPE_STRING: printf("\"%s\"", key.as.string_val); break;
                     default: printf("..."); break;
                 }
                 printf(": ");
                 // Simplified value print (stub)
                 OrenValue val = v.as.map_val->values[i];
                 switch (val.type) {
                    case OREN_TYPE_INT: printf("%lld", val.as.int_val); break;
                    case OREN_TYPE_FLOAT: printf("%f", val.as.float_val); break;
                    case OREN_TYPE_BOOL: printf("%s", val.as.bool_val ? "true" : "false"); break;
                    case OREN_TYPE_STRING: printf("%s", val.as.string_val); break;
                    case OREN_TYPE_NIL: printf("nil"); break;
                    default: printf("..."); break;
                }
             }
             printf("}\n");
             break;
        }
    }
}

void oren_print_multi(int count, ...) {
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) {
        OrenValue v = va_arg(args, OrenValue);
        switch (v.type) {
            case OREN_TYPE_INT: printf("%lld", v.as.int_val); break;
            case OREN_TYPE_FLOAT: printf("%f", v.as.float_val); break;
            case OREN_TYPE_BOOL: printf("%s", v.as.bool_val ? "true" : "false"); break;
            case OREN_TYPE_STRING: printf("%s", v.as.string_val); break;
            case OREN_TYPE_NIL: printf("nil"); break;
            case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
                PyObject* str = PyObject_Str(v.as.py_obj);
                printf("%s", PyUnicode_AsUTF8(str));
                Py_DECREF(str);
                break;
#else
                printf("Runtime Error: Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)\n");
                exit(1);
#endif
            }
            case OREN_TYPE_LIST:
                // For now, call oren_print which handles list (but adds newline which is bad for multi-arg print without glue)
                // Let's just recurse logic or print marker for now to avoid complexity in this file edit
                printf("[...]");
                break;
            case OREN_TYPE_MAP:
                printf("{...}");
                break;
        }
        if (i < count - 1) printf(" ");
    }
    printf("\n");
    va_end(args);
}

OrenValue oren_string_len(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        printf("Runtime Error: string_len expects string\n");
        exit(1);
    }
    return oren_int((long long)strlen(s.as.string_val));
}

OrenValue oren_string_char_at(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        printf("Runtime Error: char_at expects (string, int)\n");
        exit(1);
    }
    long long idx = index.as.int_val;
    size_t len = strlen(s.as.string_val);
    if (idx < 0 || (size_t)idx >= len) {
        printf("Runtime Error: char_at index out of range\n");
        exit(1);
    }
    char buf[2];
    buf[0] = s.as.string_val[idx];
    buf[1] = '\0';
    return oren_string(buf);
}

OrenValue oren_char(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        printf("Runtime Error: char expects int\n");
        exit(1);
    }
    long long v = code.as.int_val;
    if (v < 0 || v > 255) {
        printf("Runtime Error: char code out of range\n");
        exit(1);
    }
    char buf[2];
    buf[0] = (char)v;
    buf[1] = '\0';
    return oren_string(buf);
}

OrenValue oren_read_file(OrenValue path) {
    if (path.type != OREN_TYPE_STRING) {
        printf("Runtime Error: read_file expects string path\n");
        exit(1);
    }
    FILE *f = fopen(path.as.string_val, "rb");
    if (!f) {
        printf("Runtime Error: cannot open file %s\n", path.as.string_val);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(size + 1);
    fread(buf, 1, size, f);
    buf[size] = '\0';
    fclose(f);
    return oren_string(buf);
}

OrenValue oren_write_file(OrenValue path, OrenValue content) {
    if (path.type != OREN_TYPE_STRING || content.type != OREN_TYPE_STRING) {
        printf("Runtime Error: write_file expects (string, string)\n");
        exit(1);
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        printf("Runtime Error: cannot open file for write %s\n", path.as.string_val);
        exit(1);
    }
    fwrite(content.as.string_val, 1, strlen(content.as.string_val), f);
    fclose(f);
    return OREN_NIL;
}

OrenValue oren_write_bytes(OrenValue path, OrenValue bytes) {
    if (path.type != OREN_TYPE_STRING || bytes.type != OREN_TYPE_LIST) {
        printf("Runtime Error: write_bytes expects (string, list)\n");
        exit(1);
    }
    FILE *f = fopen(path.as.string_val, "wb");
    if (!f) {
        printf("Runtime Error: cannot open file for write %s\n", path.as.string_val);
        exit(1);
    }
    for (int i = 0; i < bytes.as.list_val->count; i++) {
        OrenValue b = bytes.as.list_val->items[i];
        if (b.type != OREN_TYPE_INT) {
            printf("Runtime Error: write_bytes expects list of ints\n");
            exit(1);
        }
        long long v = b.as.int_val;
        if (v < 0 || v > 255) {
            printf("Runtime Error: write_bytes byte out of range\n");
            exit(1);
        }
        fputc((unsigned char)v, f);
    }
    fclose(f);
    return OREN_NIL;
}

OrenValue oren_bytes_from_string(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        printf("Runtime Error: bytes_from_string expects string\n");
        exit(1);
    }
    size_t n = strlen(s.as.string_val);
    OrenList* list = malloc(sizeof(OrenList));
    list->count = (int)n;
    list->capacity = (int)n;
    list->items = malloc(sizeof(OrenValue) * n);
    for (size_t i = 0; i < n; i++) {
        list->items[i] = oren_int((unsigned char)s.as.string_val[i]);
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = list;
    return v;
}

typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} OrenSha256Ctx;

static uint32_t oren_sha256_rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
static uint32_t oren_sha256_ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
static uint32_t oren_sha256_maj(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (x & z) ^ (y & z); }
static uint32_t oren_sha256_ep0(uint32_t x) { return oren_sha256_rotr(x, 2) ^ oren_sha256_rotr(x, 13) ^ oren_sha256_rotr(x, 22); }
static uint32_t oren_sha256_ep1(uint32_t x) { return oren_sha256_rotr(x, 6) ^ oren_sha256_rotr(x, 11) ^ oren_sha256_rotr(x, 25); }
static uint32_t oren_sha256_sig0(uint32_t x) { return oren_sha256_rotr(x, 7) ^ oren_sha256_rotr(x, 18) ^ (x >> 3); }
static uint32_t oren_sha256_sig1(uint32_t x) { return oren_sha256_rotr(x, 17) ^ oren_sha256_rotr(x, 19) ^ (x >> 10); }

static const uint32_t OREN_SHA256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void oren_sha256_transform(OrenSha256Ctx* ctx, const uint8_t data[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        int j = i * 4;
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) | ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
    }
    for (int i = 16; i < 64; i++) {
        m[i] = oren_sha256_sig1(m[i - 2]) + m[i - 7] + oren_sha256_sig0(m[i - 15]) + m[i - 16];
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + oren_sha256_ep1(e) + oren_sha256_ch(e, f, g) + OREN_SHA256_K[i] + m[i];
        uint32_t t2 = oren_sha256_ep0(a) + oren_sha256_maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void oren_sha256_init(OrenSha256Ctx* ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void oren_sha256_update(OrenSha256Ctx* ctx, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            oren_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void oren_sha256_final(OrenSha256Ctx* ctx, uint8_t out[32]) {
    uint32_t i = ctx->datalen;

    // Pad with a single 1 bit then zeros.
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        oren_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }

    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    oren_sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; i++) {
        out[i]      = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        out[i + 4]  = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        out[i + 8]  = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        out[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        out[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        out[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        out[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        out[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length) {
    if (bytes.type != OREN_TYPE_LIST || start.type != OREN_TYPE_INT || length.type != OREN_TYPE_INT) {
        printf("Runtime Error: sha256_range expects (list, int, int)\n");
        exit(1);
    }
    long long s = start.as.int_val;
    long long n = length.as.int_val;
    if (s < 0 || n < 0 || s + n > bytes.as.list_val->count) {
        printf("Runtime Error: sha256_range out of bounds\n");
        exit(1);
    }

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);

    for (long long i = 0; i < n; i++) {
        OrenValue b = bytes.as.list_val->items[(int)(s + i)];
        if (b.type != OREN_TYPE_INT) {
            printf("Runtime Error: sha256_range expects list of ints\n");
            exit(1);
        }
        long long v = b.as.int_val;
        if (v < 0 || v > 255) {
            printf("Runtime Error: sha256_range byte out of range\n");
            exit(1);
        }
        uint8_t byte = (uint8_t)v;
        oren_sha256_update(&ctx, &byte, 1);
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    OrenList* out = malloc(sizeof(OrenList));
    out->count = 32;
    out->capacity = 32;
    out->items = malloc(sizeof(OrenValue) * 32);
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}

OrenValue oren_chmod(OrenValue path, OrenValue mode) {
    if (path.type != OREN_TYPE_STRING || mode.type != OREN_TYPE_INT) {
        printf("Runtime Error: chmod expects (string, int)\n");
        exit(1);
    }
    if (chmod(path.as.string_val, (mode_t)mode.as.int_val) != 0) {
        printf("Runtime Error: chmod failed for %s\n", path.as.string_val);
        exit(1);
    }
    return OREN_NIL;
}

OrenValue oren_system(OrenValue cmd) {
    if (cmd.type != OREN_TYPE_STRING) {
        printf("Runtime Error: system expects string\n");
        exit(1);
    }
    int res = system(cmd.as.string_val);
    return oren_int((long long)res);
}

OrenValue oren_exit(OrenValue code) {
    if (code.type != OREN_TYPE_INT) {
        printf("Runtime Error: exit expects int\n");
        exit(1);
    }
    exit((int)code.as.int_val);
    return OREN_NIL;
}

OrenValue oren_int_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_INT) {
        printf("Runtime Error: int_to_string expects int\n");
        exit(1);
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%lld", v.as.int_val);
    return oren_string(buf);
}

OrenValue oren_float_to_string(OrenValue v) {
    if (v.type != OREN_TYPE_FLOAT) {
        printf("Runtime Error: float_to_string expects float\n");
        exit(1);
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%f", v.as.float_val);
    return oren_string(buf);
}

OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end) {
    if (s.type != OREN_TYPE_STRING || start.type != OREN_TYPE_INT || end.type != OREN_TYPE_INT) {
        printf("Runtime Error: string_slice type mismatch\n");
        exit(1);
    }
    char* str = s.as.string_val;
    long long len = strlen(str);
    long long i = start.as.int_val;
    long long j = end.as.int_val;
    if (i < 0) i = 0;
    if (j > len) j = len;
    if (i >= j) {
        return oren_string("");
    }
    long long n = j - i;
    char* sub = malloc(n + 1);
    strncpy(sub, str + i, n);
    sub[n] = '\0';
    
    OrenValue v;
    v.type = OREN_TYPE_STRING;
    v.as.string_val = sub;
    return v;
}

// getenv wrapper: returns string or NIL
OrenValue oren_env(OrenValue name) {
    if (name.type != OREN_TYPE_STRING || name.as.string_val == NULL) {
        return OREN_NIL;
    }
    const char* key = name.as.string_val;
    const char* val = getenv(key);
    if (val == NULL) {
        return OREN_NIL;
    }
    return oren_string(val);
}

// Recursive free for compound objects; skips primitives.
void oren_free(OrenValue v) {
    if (v.type == OREN_TYPE_STRING) {
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(v.as.string_val);
        if (n && !n->freed) {
            n->freed = 1;
            free(n->ptr);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_LIST) {
        OrenList* lst = v.as.list_val;
        if (lst == NULL) return;
        for (int i = 0; i < lst->count; i++) {
            oren_free(lst->items[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(lst);
        if (n && !n->freed) {
            n->freed = 1;
            if (lst->items) free(lst->items);
            free(lst);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
    if (v.type == OREN_TYPE_MAP) {
        OrenMap* mp = v.as.map_val;
        if (mp == NULL) return;
        for (int i = 0; i < mp->count; i++) {
            oren_free(mp->keys[i]);
            oren_free(mp->values[i]);
        }
        pthread_mutex_lock(&g_alloc_mutex);
        OrenAllocNode* n = oren_find_node(mp);
        if (n && !n->freed) {
            n->freed = 1;
            if (mp->keys) free(mp->keys);
            if (mp->values) free(mp->values);
            free(mp);
        }
        pthread_mutex_unlock(&g_alloc_mutex);
        return;
    }
}

void oren_shutdown() {
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = g_allocs;
    while (n != NULL) {
        OrenAllocNode* next = n->next;
        if (!n->freed) {
            if (n->kind == OREN_ALLOC_STRING) {
                free(n->ptr);
            } else if (n->kind == OREN_ALLOC_LIST) {
                OrenList* lst = (OrenList*)n->ptr;
                if (lst->items) free(lst->items);
                free(lst);
            } else if (n->kind == OREN_ALLOC_MAP) {
                OrenMap* mp = (OrenMap*)n->ptr;
                if (mp->keys) free(mp->keys);
                if (mp->values) free(mp->values);
                free(mp);
            } else if (n->kind == OREN_ALLOC_STRUCT) {
                free(n->ptr);
            } else {
                free(n->ptr);
            }
        }
        free(n);
        n = next;
    }
    g_allocs = NULL;
    // Clear registered roots to release bookkeeping nodes
    OrenAllocNode* r = g_roots;
    while (r != NULL) {
        OrenAllocNode* next_r = r->next;
        free(r);
        r = next_r;
    }
    g_roots = NULL;
    pthread_mutex_unlock(&g_alloc_mutex);
}

uint64_t oren_alloc_struct(size_t bytes) {
#ifdef OREN_NO_GC
    void* p = malloc(bytes);
#else
    void* p = malloc(bytes);
    oren_register_alloc(p, OREN_ALLOC_STRUCT);
#endif
    if (!p) {
        fprintf(stderr, "struct alloc failed\n");
        exit(1);
    }
    return (uint64_t)p;
}

void oren_free_struct(uint64_t ptr) {
#ifdef OREN_NO_GC
    free((void*)ptr);
    return;
#endif
    void* p = (void*)ptr;
    pthread_mutex_lock(&g_alloc_mutex);
    OrenAllocNode* n = oren_find_node(p);
    if (n && !n->freed) {
        n->freed = 1;
        free(p);
    }
    pthread_mutex_unlock(&g_alloc_mutex);
}
