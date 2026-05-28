#ifndef AVM_H
#define AVM_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#include "sha256.h"

#define MAX_GLOBALS 1024
#define MAX_FRAMES 65536
#define AVM_STACK_SIZE 16777216
#define AVM_FREELIST_BUCKETS 16
#define AVM_GENERATOR_HANDLE_SLOTS 16
#define AVM_GENERATOR_CONTEXT_SLOTS 4
#define AVM_PTR_HANDLE_MAX 4096

typedef enum {
    AVM_VAL_NIL = 0,
    AVM_VAL_INT = 1,
    AVM_VAL_FLOAT = 2,
    AVM_VAL_BOOL = 3,
    AVM_VAL_STRING = 4,
    AVM_VAL_LIST = 5,
    AVM_VAL_LIST_INT = 6,
    AVM_VAL_MAP = 7,
    AVM_VAL_BYTES = 8,
    // First-class function value (closure): code address + captured environment value.
    // Rolling ABI: representation may evolve; semantics must remain deterministic.
    AVM_VAL_FUNC = 9,
    // Typed numeric buffers (rolling; required for ML-ish workloads + SIMD kernels).
    AVM_VAL_I32_BUF = 10,
    AVM_VAL_I64_BUF = 11,
    AVM_VAL_F32_BUF = 12,
    AVM_VAL_F64_BUF = 13,
    AVM_VAL_GENERATOR = 14,
    AVM_VAL_GENERATOR_CONTEXT = 15
} AvmType;

struct AvmList;
struct AvmListInt;
struct AvmMap;
struct AvmBytes;
struct AvmFunc;
struct AvmBuf;
struct AvmGeneratorHandle;
struct AvmGeneratorContext;

typedef struct {
    AvmType type;
    union {
        int64_t i;
        double f;
        void* p;
        struct AvmList* l;
        struct AvmListInt* li;
        struct AvmMap* m;
        struct AvmBytes* b;
        struct AvmFunc* fn;
        struct AvmBuf* buf;
        struct AvmGeneratorHandle* gen;
        struct AvmGeneratorContext* gctx;
    } as;
} AvmValue;

typedef struct AvmFunc {
    // Code address inside AvmProgram->code (rolling: currently u16 addresses in opcodes).
    uint32_t addr;
    // Captured environment (rolling):
    // - nil for non-closures / no captures
    // - LIST for capture-by-value env layouts (capture order is compiler-defined but deterministic)
    AvmValue env;
} AvmFunc;

typedef struct AvmList {
    AvmValue* items;
    int count;
    int capacity;
    int all_int;
} AvmList;

typedef struct AvmListInt {
    int64_t* items;
    int count;
    int capacity;
} AvmListInt;

typedef struct AvmMap {
    AvmValue* keys;
    AvmValue* values;
    int count;
    int capacity;
} AvmMap;

typedef struct AvmBytes {
    uint8_t* data;
    int len;
    int capacity;
} AvmBytes;

typedef struct AvmBuf {
    uint8_t* data;
    uint32_t len;       // element count
    uint32_t elem_size; // 4 for i32/f32, 8 for i64/f64
} AvmBuf;

typedef struct AvmPtrHandle {
    AvmType type;
    void* owner;
    uint8_t* data;
    int64_t len;
    int readonly;
} AvmPtrHandle;

typedef struct AvmGeneratorHandle {
    uint64_t magic;
    AvmValue slots[AVM_GENERATOR_HANDLE_SLOTS];
} AvmGeneratorHandle;

typedef struct AvmGeneratorContext {
    uint64_t magic;
    AvmValue slots[AVM_GENERATOR_CONTEXT_SLOTS];
} AvmGeneratorContext;

typedef struct {
    uint8_t* code;
    size_t code_len;
    AvmValue* constants;
    size_t const_count;
} AvmProgram;

typedef struct {
    uint64_t strings_count;
    uint64_t strings_bytes;
    uint64_t bytes_count;
    uint64_t bytes_bytes;
    uint64_t lists_count;
    uint64_t list_elems;
    uint64_t maps_count;
    uint64_t map_entries;
    uint64_t approx_total_bytes;
} AvmHeapStats;

typedef struct {
    int return_pc;
    int fp;
    // Saved environment (closures): restore vm->env on return.
    AvmValue env;
} AvmFrame;

typedef struct {
    // NOTE: `stack` may be swapped when cooperative tasks are enabled.
    // Always free `stack_base` (the original allocation) in teardown.
    AvmValue* stack_base;
    AvmValue* stack;
    int sp; 
    int pc;
    int running;
    AvmProgram* prog;
    int prog_constants_heap_owned;
    
    AvmValue globals[MAX_GLOBALS];
    AvmFrame frames[MAX_FRAMES];
    int frame_count;
    // Call stack depth limit (rolling; deterministic safety):
    // - must be <= MAX_FRAMES (fixed storage in AvmVM)
    // - 0 means "use MAX_FRAMES"
    // Configurable via CLI/env and child-universe config.
    uint32_t frame_limit;
    int fp; 
    // Current call environment for closures (restored via AvmFrame.env on return).
    AvmValue env;

    // Capability model (rolling/unstable): bitmask of allowed native domains.
    // If zero, treat as "allow all" for now.
    uint64_t allowed_native_domains;

    // FS allow-list (rolling): if empty, allow all. If non-empty, path must start with one of these prefixes.
    char** fs_allow_prefixes;
    int fs_allow_prefix_count;

    // FS mount mappings (rolling): optional virtual->host prefix mapping for the host FS backend.
    // These are intended to keep bytecode paths stable/deterministic while allowing explicit enrollment
    // into a host-backed filesystem (similar to the native runtime mounts).
    //
    // If mounts are configured for an operation type (read or write), host FS calls must match a mount.
    // If no mount matches, the operation is denied (AVM_ERR_PERM).
    char** fs_mounts_read_virt;
    char** fs_mounts_read_host;
    int fs_mounts_read_count;
    char** fs_mounts_write_virt;
    char** fs_mounts_write_host;
    int fs_mounts_write_count;
    // FS backend mode (rolling):
    // - 0: host filesystem (subject to capability + allow-prefixes + record/replay)
    // - 1: in-memory VirtualFS (no host filesystem effects; still record/replay-capable)
    int fs_backend_kind;
    // Internal: VirtualFS backing store (owned by VM heap; freed on teardown via leak-free teardown).
    void* vfs;

    // PROC backend mode (rolling):
    // - 0: host subprocess (system()) (subject to capability + record/replay)
    // - 1: VirtualPROC fixtures (no host subprocess; deterministic stub/fixture responses)
    int proc_backend_kind;
    // Internal: VirtualPROC fixtures table (owned by VM heap; freed on teardown via leak-free teardown).
    void* vproc;
    // VirtualPROC default configuration: return code for oren_system(cmd) when no fixture matches.
    int proc_exit_code;

    // NET backend mode (rolling):
    // - 0: host network (not implemented yet in bootstrap; should remain denied-by-default)
    // - 1: VirtualNET fixtures (no host network; deterministic responses)
    int net_backend_kind;
    // Internal: VirtualNET fixtures table (owned by VM heap; freed on teardown via leak-free teardown).
    void* vnet;

    // Execution budgets (rolling): 0 means "no limit".
    uint64_t gas_remaining;
    uint64_t deadline_ns;
    int cancelled;

    // Heap memory budget (rolling): counts heap allocations for AVM value objects and buffers
    // (strings/lists/maps/bytes, including record/replay buffers). 0 means "no limit".
    uint64_t heap_budget_bytes;
    uint64_t heap_used_bytes;
    void* heap_allocs_head; // internal: outstanding heap allocations (for leak-free teardown)
    // TMP freelist (rolling): best-effort reuse for short-lived allocations.
    int tmp_freelist_enabled;
    void* tmp_freelist_buckets[AVM_FREELIST_BUCKETS];
    uint64_t tmp_freelist_bytes;
    uint64_t tmp_freelist_cap_bytes;
    uint64_t tmp_freelist_max_block_bytes;
    uint64_t tmp_freelist_hits;
    uint64_t tmp_freelist_misses;
    uint64_t tmp_freelist_evictions;
    int list_freelist_enabled;
    void* list_freelist_buckets[AVM_FREELIST_BUCKETS];
    uint64_t list_freelist_bytes;
    uint64_t list_freelist_cap_bytes;
    uint64_t list_freelist_max_block_bytes;
    uint64_t list_freelist_hits;
    uint64_t list_freelist_misses;
    uint64_t list_freelist_evictions;

    // I/O budget (rolling): counts bytes read/written via host effect domains (FS first).
    // 0 means "no limit".
    uint64_t io_budget_bytes;
    uint64_t io_used_bytes;

    // Record/replay log budget (rolling): counts bytes appended to record logs (both file-based and in-memory).
    // This is separate from IO budget because logs are "determinism data" and may be used as capsules.
    // 0 means "no limit".
    uint64_t log_budget_bytes;
    uint64_t log_used_bytes;

    // Abort / error reporting (rolling): on budget/capability violations, last_error is set.
    AvmValue last_error;
    int exit_code;

    // Result selection (rolling): consensus jobs should set an explicit result value.
    // If has_result_value==0, the result is treated as nil.
    int has_result_value;
    AvmValue result_value;

    // Deterministic record/replay (rolling): used to virtualize effectful host calls (FS first).
    // - If replay_log is set, effectful calls are replayed from the log (no host effects).
    // - If record_log is set, effectful calls are executed normally and appended to the log.
    // - If both are NULL, normal behavior.
    FILE* record_log;
    FILE* replay_log;

    // In-memory record/replay logs (rolling):
    // - record_log_bytes: when set, record effectful calls into a BYTES buffer (no filesystem needed).
    // - replay_log_bytes: when set, replay effectful calls from a BYTES buffer.
    // These are intended to enable "AVM in AVM" (nested universes) where logs must be data, not host files.
    AvmBytes* record_log_bytes;
    AvmBytes* replay_log_bytes;
    uint32_t replay_log_pos;

    // Deterministic mode (rolling): for nested universes, eliminate reliance on host wall-time and entropy.
    // When deterministic==1:
    // - TIME domain uses a virtual monotonic clock (virtual_now_ns), advanced deterministically.
    // - RNG domain uses a deterministic PRNG (rng_state).
    int deterministic;
    uint64_t virtual_now_ns;
    // virtual_step_ns: time per executed semantic step (gas unit) in deterministic mode.
    // In deterministic mode, TIME.now_ns is derived from:
    //   virtual_now_ns + virtual_sleep_ns + gas_executed * virtual_step_ns
    uint64_t virtual_step_ns;
    uint64_t virtual_sleep_ns;
    uint64_t rng_state;
    // gas_executed is a semantic execution counter used for deterministic TIME.
    // Today (bootstrap), it increments by the semantic `gas_cost(op)` per executed opcode dispatch (currently 1 for all ops).
    uint64_t gas_executed;

    // SIMD acceleration (rolling, off by default):
    // - enable_simd is a runtime opt-in (env/CLI), because SIMD must be validated against determinism invariants.
    // - SIMD is an optimization only; semantics must match scalar fallback.
    int enable_simd;

    // Cooperative task scheduling quantum (rolling): number of semantic steps a task may run
    // before yielding to another runnable task (if any). This affects determinism and must be
    // included in job hashing when consensus mode is used.
    uint32_t task_quantum_steps;

    // Allocation id counter (rolling): used only for diagnostics/profiling output surfaces.
    // This must not affect program semantics; it is not included in state/result hashes.
    uint32_t alloc_next_id;

    // Cooperative pause (rolling): stop execution after N interpreter steps (not an error).
    // Used to support snapshot/resume workflows.
    uint64_t pause_after_steps;
    int paused;

    // Debug/trace (rolling): best-effort execution tracing for debugging and agent diagnostics.
    // When trace_enabled==1, the interpreter prints executed opcodes to trace_out up to trace_limit (0 => unlimited).
    int trace_enabled;
    uint64_t trace_limit;
    FILE* trace_out;

    // Deterministic trace hashing (rolling): a canonical encoding of executed steps hashed via SHA-256.
    // This is used for agentic diffing and swarm validation; it must not depend on host timing.
    int trace_hash_enabled;
    uint64_t trace_hash_limit; // 0 => unlimited
    int trace_hash_started;
    AvmSha256Ctx trace_hash_ctx;
    uint8_t trace_hash_out[32];
    int trace_hash_finalized;

    // Deterministic trace as data (rolling): canonical encoding of executed steps stored in BYTES.
    // This supports agentic diffing and nested universes without relying on stderr logs.
    int trace_bytes_enabled;
    uint64_t trace_bytes_limit;  // 0 => unlimited (limit by executed steps)
    uint64_t trace_budget_bytes; // 0 => unlimited
    uint64_t trace_used_bytes;
    AvmBytes* trace_bytes;
    // trace_bytes_truncated==1 means trace bytes capture stopped early due to budget or allocation failure.
    // This must never affect program semantics; trace capture is best-effort.
    int trace_bytes_truncated;

    // Debug/breakpoints (rolling): if any breakpoints are set, VM pauses before executing an instruction at that pc.
    int* break_pcs;
    int break_pc_count;

    // VM-local pointer handles for bytecode compiler/tooling internals.
    // These are deterministic handles, not host addresses.
    AvmPtrHandle ptr_handles[AVM_PTR_HANDLE_MAX];
    int ptr_handle_count;

    // Cooperative tasks + channels (rolling, v1 direction):
    // - Opaque internal scheduler state allocated by avm_vm.c
    // - NULL means "disabled / not initialized"
    void* sched;
    
    int argc;
    char** argv;
} AvmVM;

// Legacy native ID mapping (rolling/compat):
// The bytecode backend historically used CALL_NATIVE(id, nargs) where `id` is a flat native table index.
// AVM is moving to CALL_NATIVE2(domain, op, nargs), where domain/op are policy-controlled.
//
// To prevent legacy CALL_NATIVE or CORE domain (0) from bypassing capability policies, AVM maps
// known effectful legacy IDs into their capability domains.
//
// Mapping policy (bootstrap, rolling):
// - FS: legacy {0,1,17,18} -> domain 1 ops {0..3}
// - PROC: legacy {2} -> domain 5 op {0}
// - EXIT: legacy {5} -> domain 6 op {0}
// - ENV: legacy {4} -> domain 7 op {0}
// - Otherwise: domain 0 (CORE), op = legacy id
static inline void avm_legacy_native_to_domop(uint16_t legacy_id, uint8_t* domain_out, uint16_t* op_out) {
    uint8_t domain = 0;
    uint16_t op = legacy_id;

    if (legacy_id == 0) { domain = 1; op = 0; }   // FS.read_file
    if (legacy_id == 1) { domain = 1; op = 1; }   // FS.write_file
    if (legacy_id == 17) { domain = 1; op = 2; }  // FS.write_bytes
    if (legacy_id == 18) { domain = 1; op = 3; }  // FS.read_bytes

    if (legacy_id == 2) { domain = 5; op = 0; }   // PROC.system
    if (legacy_id == 5) { domain = 6; op = 0; }   // EXIT.exit

    if (legacy_id == 4) { domain = 7; op = 0; }   // ENV.env

    if (domain_out) *domain_out = domain;
    if (op_out) *op_out = op;
}

AvmVM* avm_new();
void avm_free(AvmVM* vm);
void avm_load(AvmVM* vm, AvmProgram* prog);
void avm_run(AvmVM* vm);

// VirtualNET fixtures (rolling):
// Load fixtures in AVMNET01 format:
//   magic[8]="AVMNET01"
//   u32_le count
//   repeated count times:
//     u32_le url_len, url bytes
//     u32_le body_len, body bytes
// Returns 1 on success; 0 on parse/alloc failure.
int avm_net_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len);
int avm_proc_load_fixtures(AvmVM* vm, const uint8_t* data, size_t len);

// Snapshot/restore (rolling; file format subject to change while repo is rolling).
// Snapshot does NOT include program code; restore expects vm->prog already loaded.
int avm_snapshot(AvmVM* vm, const char* path);
int avm_restore(AvmVM* vm, const char* path);

// Deterministic state hash (rolling): hashes heap + globals + stack + control state.
int avm_state_hash(AvmVM* vm, uint8_t out[32]);

// Deterministic result hash (rolling): hashes exit_code plus (ok -> selected result, err -> last_error).
int avm_result_hash(AvmVM* vm, uint8_t out[32]);

// Deterministic trace hash (rolling): hashes the canonical trace stream of executed steps (opt-in).
int avm_trace_hash(AvmVM* vm, uint8_t out[32]);

// Deterministic trace bytes (rolling): returns the canonical trace stream as a BYTES buffer (vm-owned).
// Requires trace_bytes_enabled to have been set before/during avm_run.
AvmBytes* avm_trace_bytes(AvmVM* vm);

// Heap stats (rolling): best-effort measurement of reachable heap objects from VM roots + constant pool.
int avm_heap_stats(AvmVM* vm, AvmHeapStats* out);

#endif
