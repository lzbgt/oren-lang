typedef enum {
    OREN_ALLOC_STRING = 1,
    OREN_ALLOC_LIST = 2,
    OREN_ALLOC_MAP = 3,
    OREN_ALLOC_STRUCT = 4,
    // Opaque raw bytes (no pointers). Used for typed buffer payloads and other HPC blobs.
    OREN_ALLOC_RAW = 5,
    // mmap-backed opaque raw bytes (returned to OS via munmap on free/GC sweep).
    OREN_ALLOC_RAW_MMAP = 6,
    OREN_ALLOC_GENERATOR = 7,
    OREN_ALLOC_GENERATOR_CONTEXT = 8
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
