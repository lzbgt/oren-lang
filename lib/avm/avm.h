#ifndef AVM_H
#define AVM_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#define MAX_GLOBALS 256
#define MAX_FRAMES 65536
#define AVM_STACK_SIZE 16777216

typedef enum {
    AVM_VAL_NIL = 0,
    AVM_VAL_INT = 1,
    AVM_VAL_FLOAT = 2,
    AVM_VAL_BOOL = 3,
    AVM_VAL_STRING = 4,
    AVM_VAL_LIST = 5,
    AVM_VAL_MAP = 6,
    AVM_VAL_BYTES = 7
} AvmType;

struct AvmList;
struct AvmMap;
struct AvmBytes;

typedef struct {
    AvmType type;
    union {
        int64_t i;
        double f;
        void* p;
        struct AvmList* l;
        struct AvmMap* m;
        struct AvmBytes* b;
    } as;
} AvmValue;

typedef struct AvmList {
    AvmValue* items;
    int count;
    int capacity;
} AvmList;

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
} AvmFrame;

typedef struct {
    AvmValue* stack;
    int sp; 
    int pc;
    int running;
    AvmProgram* prog;
    
    AvmValue globals[MAX_GLOBALS];
    AvmFrame frames[MAX_FRAMES];
    int frame_count;
    int fp; 

    // Capability model (rolling/unstable): bitmask of allowed native domains.
    // If zero, treat as "allow all" for now.
    uint64_t allowed_native_domains;

    // FS allow-list (rolling): if empty, allow all. If non-empty, path must start with one of these prefixes.
    char** fs_allow_prefixes;
    int fs_allow_prefix_count;

    // Execution budgets (rolling): 0 means "no limit".
    uint64_t gas_remaining;
    uint64_t deadline_ns;
    int cancelled;

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
    // Today (bootstrap), it increments by 1 per executed opcode dispatch.
    uint64_t gas_executed;

    // Cooperative pause (rolling): stop execution after N interpreter steps (not an error).
    // Used to support snapshot/resume workflows.
    uint64_t pause_after_steps;
    int paused;

    // Debug/trace (rolling): best-effort execution tracing for debugging and agent diagnostics.
    // When trace_enabled==1, the interpreter prints executed opcodes to trace_out up to trace_limit (0 => unlimited).
    int trace_enabled;
    uint64_t trace_limit;
    FILE* trace_out;

    // Debug/breakpoints (rolling): if any breakpoints are set, VM pauses before executing an instruction at that pc.
    int* break_pcs;
    int break_pc_count;
    
    int argc;
    char** argv;
} AvmVM;

AvmVM* avm_new();
void avm_free(AvmVM* vm);
void avm_load(AvmVM* vm, AvmProgram* prog);
void avm_run(AvmVM* vm);

// Snapshot/restore (rolling; file format subject to change while repo is rolling).
// Snapshot does NOT include program code; restore expects vm->prog already loaded.
int avm_snapshot(AvmVM* vm, const char* path);
int avm_restore(AvmVM* vm, const char* path);

// Deterministic state hash (rolling): hashes heap + globals + stack + control state.
int avm_state_hash(AvmVM* vm, uint8_t out[32]);

// Deterministic result hash (rolling): hashes exit_code plus (ok -> selected result, err -> last_error).
int avm_result_hash(AvmVM* vm, uint8_t out[32]);

// Heap stats (rolling): best-effort measurement of reachable heap objects from VM roots + constant pool.
int avm_heap_stats(AvmVM* vm, AvmHeapStats* out);

#endif
