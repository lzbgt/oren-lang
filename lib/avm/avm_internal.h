#ifndef AVM_INTERNAL_H
#define AVM_INTERNAL_H

#include "avm.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>

// Error codes (must match the C runtime's rolling conventions in lib/runtime.h)
#define AVM_ERR_PERM 1
#define AVM_ERR_NOT_FOUND 2
#define AVM_ERR_IO 3
#define AVM_ERR_INVALID_ARG 4
#define AVM_ERR_TIMEOUT 5
#define AVM_ERR_CANCELLED 6
#define AVM_ERR_NOT_IMPLEMENTED 7
#define AVM_ERR_INTERNAL 8
#define AVM_ERR_BUDGET 9

enum {
    AVM_ALLOC_KIND_UNKNOWN = 0,
    AVM_ALLOC_KIND_STRING = 1,
    AVM_ALLOC_KIND_BYTES = 2,
    AVM_ALLOC_KIND_LIST = 3,
    AVM_ALLOC_KIND_MAP = 4,
    AVM_ALLOC_KIND_VFS = 5,
    AVM_ALLOC_KIND_VPROC = 6,
    AVM_ALLOC_KIND_VNET = 7,
    AVM_ALLOC_KIND_TMP = 8,
    AVM_ALLOC_KIND_FUNC = 9,
    AVM_ALLOC_KIND_BUF = 10
};

static inline AvmValue avm_int(int64_t i) {
    AvmValue v;
    v.type = AVM_VAL_INT;
    v.as.i = i;
    return v;
}

static inline AvmValue avm_bool(int b) {
    AvmValue v;
    v.type = AVM_VAL_BOOL;
    v.as.i = b ? 1 : 0;
    return v;
}

static inline AvmValue avm_nil(void) {
    AvmValue v;
    v.type = AVM_VAL_NIL;
    v.as.i = 0;
    return v;
}

// --- VM control ---
void avm_abort(AvmVM* vm, AvmValue err);

// --- Cooperative scheduler (internal) ---
// Returns 1 if the scheduler is either disabled or in a "trivial" state that is safe to snapshot:
// - only main task exists
// - no channels exist
// - no ready/select wait queues are populated
int avm_sched_is_trivial(AvmVM* vm);

// --- Allocation (heap budgeting + leak-free teardown) ---
void avm_alloc_owner_push(AvmVM* vm, AvmVM** prev);
void avm_alloc_owner_pop(AvmVM* prev);
void avm_alloc_unbudgeted_push(int* prev);
void avm_alloc_unbudgeted_pop(int prev);

void* avm_heap_malloc_k(size_t size, uint8_t kind);
void* avm_heap_realloc_k(void* p, size_t new_size, uint8_t kind);
void avm_heap_free(void* p);

AvmValue avm_alloc_fail_value(void);
void avm_release_unreachable_allocs(AvmVM* vm);

// --- Budgets ---
int avm_io_charge(AvmVM* vm, uint64_t bytes, int domain, int op);
int avm_log_charge(AvmVM* vm, uint64_t bytes, int domain, int op);
int avm_log_can_fit(AvmVM* vm, uint64_t bytes);

// --- Host time + entropy (non-deterministic mode) ---
uint64_t avm_now_ns(void);
uint64_t prng_next_u64(uint64_t* state);
uint64_t host_random_u64(void);

// --- Container helpers (maps are key-ordered for determinism) ---
int avm_map_get_bool(AvmMap* map, const char* key);
AvmValue avm_map_get(AvmMap* map, const char* key);
int avm_map_key_supported(AvmValue k);
int avm_map_find_index(AvmMap* map, AvmValue key, int* found);
int avm_map_set_sorted(AvmMap* map, AvmValue key, AvmValue val);
int avm_list_ensure_cap(AvmList* list, int need);

// --- BYTES utils (in-memory record/replay + trace bytes) ---
int bytes_ensure_cap(AvmBytes* b, int need);
int mem_write_u8(AvmBytes* b, uint32_t* pos, uint8_t v);
int mem_write_u16_le(AvmBytes* b, uint32_t* pos, uint16_t v);
int mem_write_u32_le(AvmBytes* b, uint32_t* pos, uint32_t v);
int mem_write_u64_le(AvmBytes* b, uint32_t* pos, uint64_t v);
int mem_write_bytes(AvmBytes* b, uint32_t* pos, const uint8_t* data, uint32_t len);
int mem_read_u8(const AvmBytes* b, uint32_t* pos, uint8_t* out);
int mem_read_u16_le(const AvmBytes* b, uint32_t* pos, uint16_t* out);
int mem_read_u32_le(const AvmBytes* b, uint32_t* pos, uint32_t* out);
int mem_read_u64_le(const AvmBytes* b, uint32_t* pos, uint64_t* out);
int mem_read_bytes(const AvmBytes* b, uint32_t* pos, uint8_t* out, uint32_t len);

// --- Values / errors ---
int avm_err_from_errno(int err);
AvmValue avm_string(const char* s);
AvmValue avm_bytes_new(int len);
int hex_nibble(char c);
char* my_strdup(const char* s);

AvmValue avm_err(int code, const char* msg);
AvmValue avm_err_domop(int code, const char* msg, int domain, int op);
int avm_is_err_val(AvmValue v);

// --- Trace (best-effort; must not affect semantics) ---
int trace_emit_step(AvmVM* vm, int op_pc, uint8_t op);
int trace_emit_native2(AvmVM* vm, int op_pc, uint8_t domain, uint16_t op, uint8_t nargs);
int trace_emit_abort(AvmVM* vm, int op_pc, uint16_t err_code);
int trace_emit_alloc_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t size, uint32_t charged);
int trace_emit_free_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t size, uint32_t charged);
int trace_emit_realloc_bytes(AvmVM* vm, uint32_t pc, uint32_t alloc_id, uint8_t kind, uint32_t old_size, uint32_t new_size, uint32_t old_charged, uint32_t new_charged);

// --- Opcode semantics helpers ---
const char* avm_op_name(uint8_t op);
uint32_t avm_gas_cost(uint8_t op);

// --- Native capability dispatcher (CALL_NATIVE2) ---
AvmValue avm_call_native2(AvmVM* vm, uint8_t domain, uint16_t op, AvmValue* args, int nargs);

// --- Virtual backends fixtures helpers (used by NET/PROC domains) ---
typedef struct {
    char* url;
    uint8_t* body;
    uint32_t body_len;
} AvmVnetEntry;
typedef struct {
    AvmVnetEntry* entries;
    uint32_t count;
} AvmVnet;
AvmVnetEntry* avm_vnet_find(AvmVM* vm, const char* url);
int avm_net_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len);

typedef struct {
    char* cmd;
    int32_t exit_code;
} AvmVprocEntry;
typedef struct {
    AvmVprocEntry* entries;
    uint32_t count;
} AvmVproc;
AvmVprocEntry* avm_vproc_find(AvmVM* vm, const char* cmd);
int avm_proc_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len);

// --- VirtualFS backing store (in-memory filesystem) ---
// Stored under `AvmVM.vfs` when fs_backend_kind==1.
typedef struct {
    char* path;
    uint8_t* data;
    uint32_t len;
} AvmVfsEntry;

typedef struct {
    AvmVfsEntry* entries;
    uint32_t count;
    uint32_t cap;
} AvmVfs;

// --- Heap release from snapshot module (internal wrapper) ---
void avm_release_heap_all(AvmVM* vm);

// --- Record/replay helpers (used by native domains + snapshot code) ---
int rr_write_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret);
AvmValue rr_replay_entry(AvmVM* vm, FILE* f, uint8_t domain, uint16_t op, AvmValue* args, int nargs);
int rr_write_entry_mem(AvmVM* vm, AvmBytes* out, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs, AvmValue ret);
AvmValue rr_replay_entry_mem(AvmVM* vm, const AvmBytes* in, uint32_t* pos, uint8_t domain, uint16_t op, AvmValue* args, int nargs);
int avm_path_allowed(AvmVM* vm, const char* path);

#endif
