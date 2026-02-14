#ifndef OREN_H
#define OREN_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>

// Python embedding is optional. Enable it by compiling with `-DOREN_ENABLE_PYTHON`
// and linking against libpython (e.g. via `python3-config --cflags --embed --ldflags`).
#ifdef OREN_ENABLE_PYTHON
#include <Python.h>
#else
typedef struct PyObject PyObject;
#endif

typedef enum {
    OREN_TYPE_NIL,
    OREN_TYPE_INT,
    OREN_TYPE_FLOAT,
    OREN_TYPE_BOOL,
    OREN_TYPE_STRING,
    OREN_TYPE_PY_OBJ,
    OREN_TYPE_LIST,
    OREN_TYPE_MAP,
    OREN_TYPE_FUNC,
    // Typed numeric buffers (rolling; required for HPC + SIMD kernels).
    // Backends must treat payload as little-endian bytes for determinism.
    OREN_TYPE_U8_BUF,
    OREN_TYPE_I32_BUF,
    OREN_TYPE_I64_BUF,
    OREN_TYPE_F32_BUF,
    OREN_TYPE_F64_BUF
} OrenType;

// Stable error codes (rolling ABI; subject to refinement, but keep numbers stable once used).
// Convention: 0 == "no error"; non-zero indicates failure.
#define OREN_ERR_PERM 1
#define OREN_ERR_NOT_FOUND 2
#define OREN_ERR_IO 3
#define OREN_ERR_INVALID_ARG 4
#define OREN_ERR_TIMEOUT 5
#define OREN_ERR_CANCELLED 6
#define OREN_ERR_NOT_IMPLEMENTED 7
#define OREN_ERR_INTERNAL 8
#define OREN_ERR_BUDGET 9

struct OrenList;
struct OrenMap;
struct OrenBuf;

typedef struct OrenValue OrenValue;

// First-class function values (C backend):
// - A uniform call ABI so functions can be stored in OrenValue and invoked via oren_call_obj.
// - `env` is reserved for closures; v0 uses env=NULL.
typedef OrenValue (*OrenFn)(void* env, int argc, OrenValue* argv);
typedef struct {
    OrenFn fn;
    void* env;
} OrenFunc;

struct OrenValue {
    OrenType type;
    union {
        long long int_val;
        double float_val;
        int bool_val;
        char* string_val;
        PyObject* py_obj;
        struct OrenList* list_val;
        struct OrenMap* map_val;
        OrenFunc func_val;
        struct OrenBuf* buf_val;
    } as;
};

typedef struct OrenList {
    OrenValue* items;
    int count;
    int capacity;
} OrenList;

typedef struct OrenMap {
    // Deterministic ordered map: keys kept sorted, linear storage.
    OrenValue* keys;
    OrenValue* values;
    int count;
    int capacity;
} OrenMap;

typedef struct OrenBuf {
    uint8_t* data;
    uint32_t len;       // element count
    uint32_t elem_size; // 4 for i32/f32, 8 for i64/f64
} OrenBuf;

	// GC / roots
	void oren_register_root(OrenValue* slot);
	void oren_unregister_root(OrenValue* slot);
	void oren_gc_collect();
	void oren_gc_safepoint();
	// Pin a value in the current thread state so GC can always find it (even if the caller
	// keeps it only in registers under -O2). Returns the previous pinned value.
	OrenValue oren_gc_pin(OrenValue v);
	// Precise per-thread root stack (fast, rolling):
	// - Designed for generated C code to keep locals/temporaries alive without relying on
	//   conservative stack/register scanning (which is fragile under -O2 and threads).
	// - Roots are thread-local and GC scans them during stop-the-world marking.
	//
	// Typical pattern:
	//   size_t mark = oren_roots_mark();
	//   OrenValue tmp = ...; oren_roots_push(&tmp);
	//   ...
	//   oren_roots_reset(mark);
size_t oren_roots_mark(void);
void oren_roots_push(OrenValue* slot);
// Root an rvalue / temporary by value (does not require taking the address of a local).
// This avoids forcing large numbers of temporaries onto the C stack (important for the
// self-hosted compiler, which otherwise can blow the OS thread stack under -O2).
void oren_roots_push_value(OrenValue v);
void oren_roots_reset(size_t mark);

	extern OrenValue OREN_NIL;
	extern OrenValue OREN_TRUE;
	extern OrenValue OREN_FALSE;

void oren_init(int argc, char **argv);
OrenValue oren_args();

// Run a program's main body in a fresh OS thread with a larger stack.
//
// Motivation (rolling):
// - Self-hosted compiler workloads are deeply recursive and can overflow the default host stack,
//   especially on Windows where the main thread stack is often ~1 MiB by default.
// - Stage0 bootstrap emits C that calls this helper from `main(...)` so the generated C backend
//   binaries are robust across Tier‑1 hosts.
//
// Env:
// - OREN_MAIN_STACK_SIZE: decimal bytes (default: 64 MiB, min: 1 MiB)
int oren_run_main_threaded(int argc, char **argv, int (*body)(int, char **));

// Threads (C backend only for now)
typedef OrenValue (*OrenFn0)(void);
OrenValue oren_spawn0(OrenFn0 fn);
// Spawn a thread that calls a callable `fn` with arguments from a list.
// This is the preferred API for supporting first-class functions and closures.
OrenValue oren_spawn_call_list(OrenValue fn, OrenValue args_list);
OrenValue oren_join(OrenValue thread);
// Join with a wall-time timeout in milliseconds.
// - timeout_ms < 0: wait forever (equivalent to oren_join)
// - timeout_ms >= 0: wait up to timeout; on timeout returns INT(-60) (BSD ETIMEDOUT)
//   and detaches the thread so it can clean up without blocking the caller.
OrenValue oren_join_timeout(OrenValue thread, OrenValue timeout_ms);
OrenValue oren_detach(OrenValue thread);
OrenValue oren_is_done(OrenValue thread);
OrenValue oren_join_all();

OrenValue oren_func(OrenFn fn, void* env);
// Create a closure by capturing values into an environment (capture-by-value).
// The environment is stored as a GC-managed list; the returned function value
// keeps it alive via GC marking of `OREN_TYPE_FUNC`.
OrenValue oren_closure(OrenFn fn, int capture_count, ...);
// Like `oren_closure`, but captures are passed as an array to avoid varargs/struct ABI issues.
OrenValue oren_closure_from_array(OrenFn fn, int capture_count, const OrenValue* captures);

OrenValue oren_int(long long v);
OrenValue oren_float(double v);
OrenValue oren_string(const char* s);
// Construct a string backed by a constant NUL-terminated C string.
// This avoids heap allocation and GC tracking and is intended for literals and other process-lifetime strings.
OrenValue oren_string_const(const char* s);

// Join a list<string> into one string with a single allocation.
// Used by compiler tooling (include expansion) to avoid O(n^2) string churn.
OrenValue oren_string_join(OrenValue parts);
OrenValue oren_bool(int v);

int oren_is_truthy(OrenValue v);

OrenValue oren_add(OrenValue a, OrenValue b);
OrenValue oren_sub(OrenValue a, OrenValue b);
OrenValue oren_mul(OrenValue a, OrenValue b);
OrenValue oren_div(OrenValue a, OrenValue b);
OrenValue oren_mod(OrenValue a, OrenValue b);

OrenValue oren_band(OrenValue a, OrenValue b);
OrenValue oren_bor(OrenValue a, OrenValue b);
OrenValue oren_bxor(OrenValue a, OrenValue b);
OrenValue oren_shl(OrenValue a, OrenValue b);
OrenValue oren_shr(OrenValue a, OrenValue b);
OrenValue oren_bnot(OrenValue v);

OrenValue oren_eq(OrenValue a, OrenValue b);
OrenValue oren_neq(OrenValue a, OrenValue b);
OrenValue oren_lt(OrenValue a, OrenValue b);
OrenValue oren_gt(OrenValue a, OrenValue b);
OrenValue oren_lte(OrenValue a, OrenValue b);
OrenValue oren_gte(OrenValue a, OrenValue b);

OrenValue oren_get_attr(OrenValue obj, const char* attr);
OrenValue oren_set_attr(OrenValue obj, const char* attr, OrenValue value);

// Python Interop
OrenValue oren_py_import(OrenValue name);
OrenValue oren_py_release(OrenValue obj);
OrenValue oren_py_call(OrenValue obj, int count, ...); // Specific call?
// Actually, generic call support is better
OrenValue oren_call_obj(OrenValue fn, int count, ...);
// Non-varargs forms (useful for spawn/callback paths).
OrenValue oren_call_obj_argv(OrenValue fn, int argc, OrenValue* argv);
OrenValue oren_call_obj_list(OrenValue fn, OrenValue args_list);
OrenValue oren_call_obj_spread(OrenValue fn, OrenValue fixed_args, OrenValue spread_list);

OrenValue oren_new_list(int count, ...);
// Build a list from an array of OrenValue items (no varargs/struct ABI issues).
// Intended for C transpilers to lower list literals safely and efficiently.
OrenValue oren_new_list_from_array(int count, const OrenValue* items);
OrenValue oren_list_len(OrenValue list);
OrenValue oren_list_push(OrenValue list, OrenValue value);
// Unsafe/fast-path (tooling/internal): assumes `list` is a valid list object.
// Returns `nil` (matches `oren_list_push`).
OrenValue oren_list_push_unchecked(OrenValue list, OrenValue value);
OrenValue oren_list_get(OrenValue list, OrenValue index);
OrenValue oren_list_set(OrenValue list, OrenValue index, OrenValue value);
OrenValue oren_iter_next(OrenValue container, OrenValue idx, OrenValue out_pair);
// Map entry iterator (key+value). Returns ok:int (1/0) and writes into out_pair[0..1].
OrenValue oren_iter_next_entry(OrenValue map, OrenValue idx, OrenValue out_pair);
OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value);
// Safe type predicates (must not panic on wrong type).
OrenValue oren_is_list(OrenValue v);
OrenValue oren_is_map(OrenValue v);
OrenValue oren_is_string(OrenValue v);
// Typed buffer predicates (must not panic on wrong type).
OrenValue oren_is_buf(OrenValue v);
OrenValue oren_is_u8_buf(OrenValue v);
// Debug/interop helper: return the runtime type tag (matches OrenType enum values).
OrenValue oren_type_tag(OrenValue v);
// Debug/interop helper: return a stable type name string for the runtime type tag.
// Intended for logging and basic reflection in user code (e.g. varargs dispatch).
OrenValue oren_type_name(OrenValue v);

OrenValue oren_new_map(int count, ...);
// Build a map from an array of key/value pairs:
//   kv_pairs[0]=k0, kv_pairs[1]=v0, kv_pairs[2]=k1, kv_pairs[3]=v1, ...
// This avoids passing OrenValue structs through varargs (undefined behavior).
OrenValue oren_new_map_from_pairs(int count, const OrenValue* kv_pairs);
OrenValue oren_map_get(OrenValue map, OrenValue key);
OrenValue oren_map_get_int(OrenValue map, OrenValue key);
OrenValue oren_map_get_str(OrenValue map, OrenValue key);
OrenValue oren_map_set(OrenValue map, OrenValue key, OrenValue value);
OrenValue oren_map_set_int(OrenValue map, OrenValue key, OrenValue value);
OrenValue oren_map_set_str(OrenValue map, OrenValue key, OrenValue value);
	// Unsafe/fast-path (tooling/internal): assumes `map` is a valid map and the key kind is correct.
	OrenValue oren_map_set_int_unchecked(OrenValue map, OrenValue key, OrenValue value);
	OrenValue oren_map_set_str_unchecked(OrenValue map, OrenValue key, OrenValue value);
	// Unsafe builder fast-path (tooling/internal):
	// Append a new entry without doing a duplicate-key search.
	// Intended for astbin decode when the map capacity is preallocated and the input has no duplicates.
	//
	// Return value matches `oren_map_set_*`: returns `value`.
	OrenValue oren_map_push_entry_int_unchecked(OrenValue map, OrenValue key, OrenValue value);
	OrenValue oren_map_push_entry_str_unchecked(OrenValue map, OrenValue key, OrenValue value);
	// Finalize a map after bulk pushes (native backend may build a hash index).
	// `want_entries` is the expected entry count (best-effort hint).
	// Returns `map`.
	OrenValue oren_map_build_finalize_unchecked(OrenValue map, OrenValue want_entries);
	OrenValue oren_map_len(OrenValue map);

// Allocate an empty list with reserved capacity `cap`.
// This is a tooling/perf helper used by compiler internals (e.g. astbin decode) to avoid
// O(n) growth reallocations. Semantics: list length starts at 0.
OrenValue oren_list_new_cap(OrenValue cap);
// Allocate an empty map with reserved capacity `cap`.
// Semantics: map length starts at 0.
OrenValue oren_map_new_cap(OrenValue cap);

OrenValue oren_string_len(OrenValue s);
OrenValue oren_string_char_at(OrenValue s, OrenValue index);
// Fast path for tooling (compiler/lexer): like `oren_string_char_at`, but assumes
// the caller has already bounds-checked `index` against a known string length.
// This avoids an O(n) `strlen` per character, which is catastrophic for lexing.
OrenValue oren_string_char_at_unchecked(OrenValue s, OrenValue index);
// Fast path for tooling: return the raw byte value at `index` (0..255) without bounds checks.
// Caller must ensure `index` is within the string's known length.
OrenValue oren_string_byte_at_unchecked(OrenValue s, OrenValue index);
// Return the unsigned byte value at `index` (0..255).
// Rolling v0 note: the language currently treats strings as C-strings (bytes until NUL),
// so this is a byte-oriented helper used by the compiler lexer and AVM tests.
OrenValue oren_string_char_code_at(OrenValue s, OrenValue index);
// Build a string from a slice of a byte container (list<int 0..255> or u8_buf).
// Used by the compiler's parallel module pipeline to decode astbin without per-byte boxing.
OrenValue oren_string_from_bytes_slice(OrenValue bytes, OrenValue start, OrenValue len);
// Build a u8_buf from a slice of a byte container (list<int 0..255> or u8_buf).
// Used by compiler tooling to decode astbin efficiently (memcpy on u8_buf inputs).
OrenValue oren_u8_buf_from_bytes_slice(OrenValue bytes, OrenValue start, OrenValue len);
OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end);
// Like `oren_string_slice`, but assumes the caller already validated bounds against a known length.
// This avoids repeated O(n) `strlen` scans in compiler hot paths (e.g., runtime include expansion).
OrenValue oren_string_slice_unchecked(OrenValue s, OrenValue start, OrenValue end);
// Best-effort symbol resolver for debug tooling. Native emitters provide real symbol mapping in
// debug builds; C backend uses a minimal stub.
OrenValue oren_resolve_symbol(OrenValue addr);
OrenValue oren_char(OrenValue code);
OrenValue oren_int_to_string(OrenValue v);
OrenValue oren_float_to_string(OrenValue v);
OrenValue oren_string_to_float_bits(OrenValue s);
// Round a float value to IEEE-754 float32 precision and return it as a float (f64 container).
// Used by the compiler as the semantic core of `f32` annotations.
OrenValue oren_f32_round(OrenValue v);
// Bitcast helpers (unsafe, rolling):
// - interpret float bits as integer bits and vice versa (no numeric conversion).
OrenValue oren_f32_to_u32_bits(OrenValue v);
OrenValue oren_u32_bits_to_f32(OrenValue v);
OrenValue oren_f64_to_u64_bits(OrenValue v);
OrenValue oren_u64_bits_to_f64(OrenValue v);
// Normalize a value to a boolean using numeric (int/float) semantics rather than generic truthiness.
// Used by the compiler as the semantic core of `bool` annotations.
OrenValue oren_bool_norm(OrenValue v);
// Truncate a numeric value to an int using deterministic semantics:
// - int   -> identity
// - float -> truncate toward zero (like C cast), error on NaN/overflow
// Used by the compiler for float->int cast sugar lowering (e.g. `u8(1.9)`).
OrenValue oren_trunc_int(OrenValue v);

// --- typed numeric buffers (C backend) ---
OrenValue oren_u8_buf_new(OrenValue len);
OrenValue oren_i32_buf_new(OrenValue len);
OrenValue oren_i64_buf_new(OrenValue len);
OrenValue oren_f32_buf_new(OrenValue len);
OrenValue oren_f64_buf_new(OrenValue len);

OrenValue oren_buf_len(OrenValue buf);
// Diagnostic helper: return true if the buffer payload is tracked as RAW bytes.
// Useful for ensuring buffer payloads are unscanned and not treated as pointer-containing memory.
OrenValue oren_buf_payload_is_raw(OrenValue buf);
// Diagnostic helper: return true if the buffer payload was mmap-allocated (and can be returned to OS).
OrenValue oren_buf_payload_is_mmap(OrenValue buf);

	// Debug/diagnostic helper (C backend): returns (uintptr_t)buf->data % mod.
	// Does not expose the full pointer value, but enables alignment assertions in tests.
	OrenValue oren_buf_data_mod(OrenValue buf, OrenValue mod);
		// Unsafe/fast-path (tooling/internal): return (uintptr_t)buf->data as an int.
		// Intended for native+tooling hot paths that need raw byte access without per-byte calls.
		// Caller must treat this as an internal pointer value (not stable ABI).
		OrenValue oren_buf_data_ptr_unchecked(OrenValue buf);

	// --- unsafe pointer primitives (tooling/internal) ---
	//
	// These are exposed to generated C code as first-class function values (OrenValue type FUNC),
	// so the C backend can use the uniform-call ABI (`oren_call_obj_*`) without special-casing.
	//
	// Contract:
	// - pointers are passed as OREN_TYPE_INT containing a (uintptr_t) address
	// - these are intentionally unsafe and may crash on invalid pointers
	extern OrenValue ptr_get;
	extern OrenValue ptr_set;
	extern OrenValue ptr_get_byte;
	extern OrenValue ptr_set_byte;

		OrenValue oren_buf_load_u8(OrenValue buf, OrenValue idx);
		// Unsafe/fast-path (tooling/internal): load a byte from a u8_buf without bounds/type checks.
		// Intended for compiler hot paths like astbin decode after a single upfront validation.
		OrenValue oren_buf_load_u8_unchecked(OrenValue buf, OrenValue idx);
	OrenValue oren_buf_store_u8(OrenValue buf, OrenValue idx, OrenValue v);
OrenValue oren_buf_load_i32(OrenValue buf, OrenValue idx);
OrenValue oren_buf_store_i32(OrenValue buf, OrenValue idx, OrenValue v);
OrenValue oren_buf_load_i64(OrenValue buf, OrenValue idx);
OrenValue oren_buf_store_i64(OrenValue buf, OrenValue idx, OrenValue v);
OrenValue oren_buf_load_f32(OrenValue buf, OrenValue idx);
OrenValue oren_buf_store_f32(OrenValue buf, OrenValue idx, OrenValue v);
OrenValue oren_buf_load_f64(OrenValue buf, OrenValue idx);
OrenValue oren_buf_store_f64(OrenValue buf, OrenValue idx, OrenValue v);

OrenValue oren_buf_fill_u8(OrenValue buf, OrenValue v);
OrenValue oren_buf_fill_i32(OrenValue buf, OrenValue v);
OrenValue oren_buf_fill_i64(OrenValue buf, OrenValue v);
OrenValue oren_buf_fill_f32(OrenValue buf, OrenValue v);
OrenValue oren_buf_fill_f64(OrenValue buf, OrenValue v);

	OrenValue oren_buf_add_i32(OrenValue a, OrenValue b);
	OrenValue oren_buf_add_f32(OrenValue a, OrenValue b);
	OrenValue oren_buf_add_i64(OrenValue a, OrenValue b);
	OrenValue oren_buf_add_f64(OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_i32(OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_f32(OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_f64(OrenValue a, OrenValue b);
// Dot over contiguous slices (no allocation).
// Semantics match `oren_buf_dot_*` but allow specifying offsets + length explicitly.
OrenValue oren_buf_dot_i32_slice(OrenValue a, OrenValue a_off, OrenValue b, OrenValue b_off, OrenValue n);
OrenValue oren_buf_dot_f32_slice(OrenValue a, OrenValue a_off, OrenValue b, OrenValue b_off, OrenValue n);
OrenValue oren_buf_dot_f64_slice(OrenValue a, OrenValue a_off, OrenValue b, OrenValue b_off, OrenValue n);
// Dot over strided slices (no allocation):
// - element i in a: a[a_off + i * a_stride]
// - element i in b: b[b_off + i * b_stride]
OrenValue oren_buf_dot_i32_strided(OrenValue a, OrenValue a_off, OrenValue a_stride, OrenValue b, OrenValue b_off, OrenValue b_stride, OrenValue n);
OrenValue oren_buf_dot_f32_strided(OrenValue a, OrenValue a_off, OrenValue a_stride, OrenValue b, OrenValue b_off, OrenValue b_stride, OrenValue n);
OrenValue oren_buf_dot_f64_strided(OrenValue a, OrenValue a_off, OrenValue a_stride, OrenValue b, OrenValue b_off, OrenValue b_stride, OrenValue n);

// 1x4 i32 dot microkernel: compute four dot products that share the same `a` slice.
//
// Writes 4 i64 results into `out` (an i64 typed buffer) starting at `out_off`:
//   out[out_off + j] = dot_i32(a[a_off..a_off+n), b[bj_off..bj_off+n))  for j=0..3
//
// Semantics:
// - integer multiplication uses i64, accumulation is modulo 2^64 then reinterpreted as signed i64
// - deterministic for all backends; NEON paths are allowed because wrap addition is associative
OrenValue oren_buf_dot_i32_4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

// 1x4 f32 dot microkernel: compute four dot products that share the same `a` slice.
//
// Writes 4 f64 results into `out` (an f64 typed buffer) starting at `out_off`:
//   out[out_off + j] = dot_f32(a[a_off..a_off+n), b[bj_off..bj_off+n))  for j=0..3
//
// Semantics:
// - each element is widened to f64 and multiplied in f64
// - accumulation is done in a fixed increasing-k order (deterministic)
// - SIMD paths must preserve this ordering (no reassociation / FMA contraction)
OrenValue oren_buf_dot_f32_4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

// 1x4 f64 dot microkernel: compute four dot products that share the same `a` slice.
//
// Writes 4 f64 results into `out` (an f64 typed buffer) starting at `out_off`:
//   out[out_off + j] = dot_f64(a[a_off..a_off+n), b[bj_off..bj_off+n))  for j=0..3
//
// Semantics:
// - multiplication is done in f64
// - accumulation is done in a fixed increasing-k order (deterministic)
// - SIMD paths must preserve this ordering (no reassociation / FMA contraction)
OrenValue oren_buf_dot_f64_4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

// 4x4 f64 GEMM microkernel: compute a 4x4 block of dot-products in one pass.
//
// Writes 16 f64 results into `out` (an f64 typed buffer) starting at `out_off`,
// in row-major order:
//   out[out_off + (r*4 + c)] = dot_f64(a[a_r_off..a_r_off+n), b[b_c_off..b_c_off+n))
// for r,c in 0..3.
//
// Semantics / determinism contract (v0):
// - multiplication is done in f64
// - accumulation is done in a fixed increasing-k order (deterministic)
// - SIMD paths must preserve this ordering (no reassociation / FMA contraction)
OrenValue oren_buf_gemm_f64_4x4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a0_off, OrenValue a1_off, OrenValue a2_off, OrenValue a3_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

// 4x4 i32 GEMM microkernel: compute a 4x4 block of dot products in one pass.
//
// Writes 16 i64 results into `out` (an i64 typed buffer) starting at `out_off`,
// in row-major order:
//   out[out_off + (r*4 + c)] = dot_i32(a[a_r_off..a_r_off+n), b[b_c_off..b_c_off+n))
// for r,c in 0..3.
//
// Semantics:
// - integer multiplication uses i64, accumulation is modulo 2^64 then reinterpreted as signed i64
// - deterministic for all backends; NEON paths are allowed because wrap addition is associative
OrenValue oren_buf_gemm_i32_4x4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a0_off, OrenValue a1_off, OrenValue a2_off, OrenValue a3_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

// 4x4 f32 GEMM microkernel: compute a 4x4 block of dot products in one pass.
//
// Writes 16 f64 results into `out` (an f64 typed buffer) starting at `out_off`,
// in row-major order:
//   out[out_off + (r*4 + c)] = dot_f32(a[a_r_off..a_r_off+n), b[b_c_off..b_c_off+n))
// for r,c in 0..3.
//
// Semantics:
// - each element is widened to f64 and multiplied in f64
// - accumulation is done in a fixed increasing-k order (deterministic)
// - SIMD paths must preserve this ordering (no reassociation / FMA contraction)
OrenValue oren_buf_gemm_f32_4x4_slice_into(
    OrenValue out, OrenValue out_off,
    OrenValue a, OrenValue a0_off, OrenValue a1_off, OrenValue a2_off, OrenValue a3_off,
    OrenValue b, OrenValue b0_off, OrenValue b1_off, OrenValue b2_off, OrenValue b3_off,
    OrenValue n);

	OrenValue oren_buf_add_i32_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_add_f32_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_add_i64_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_add_f64_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_i32(OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_f32(OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_i64(OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_f64(OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_i32_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_f32_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_i64_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_mul_f64_into(OrenValue dst, OrenValue a, OrenValue b);
	OrenValue oren_buf_scale_i32_into(OrenValue dst, OrenValue a, OrenValue scalar);
	OrenValue oren_buf_scale_f32(OrenValue buf, OrenValue scalar);
	OrenValue oren_buf_scale_f32_into(OrenValue dst, OrenValue a, OrenValue scalar);

	OrenValue oren_buf_reduce_sum_i32(OrenValue buf);
	OrenValue oren_buf_reduce_sum_f32(OrenValue buf);
	OrenValue oren_buf_reduce_sum_f64(OrenValue buf);
	OrenValue oren_buf_dot_i32_into(OrenValue out, OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_f32_into(OrenValue out, OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_f64_into(OrenValue out, OrenValue a, OrenValue b);
	OrenValue oren_buf_reduce_sum_i32_into(OrenValue out, OrenValue a);
	OrenValue oren_buf_reduce_sum_f32_into(OrenValue out, OrenValue a);
	OrenValue oren_buf_reduce_sum_f64_into(OrenValue out, OrenValue a);

	// AXPY: y := alpha*x + y (in-place) and dst := alpha*x + y (into).
	//
	// Determinism contract (v0):
	// - f32 ops round `alpha` to float32 boundary, then do per-element mul+add in float32.
	// - implementations must not change per-element rounding (avoid FMA contraction).
	OrenValue oren_buf_axpy_f32_into(OrenValue dst, OrenValue alpha, OrenValue x, OrenValue y);
	OrenValue oren_buf_axpy_f32_in_place(OrenValue alpha, OrenValue x, OrenValue y);
	OrenValue oren_buf_axpy_i32_into(OrenValue dst, OrenValue alpha, OrenValue x, OrenValue y);
	OrenValue oren_buf_axpy_i32_in_place(OrenValue alpha, OrenValue x, OrenValue y);

	OrenValue oren_read_file(OrenValue path);
OrenValue oren_write_file(OrenValue path, OrenValue content);
OrenValue oren_write_bytes(OrenValue path, OrenValue bytes);
OrenValue oren_read_bytes(OrenValue path);
	// Read a file into a typed byte buffer (u8_buf) with one allocation.
	// This avoids boxing each byte as an int (which can explode memory for large artifacts).
	OrenValue oren_read_u8_buf(OrenValue path);
	// Fast file metadata query for build tooling.
	//
	// Returns a list<int> of length 2: [size_bytes, mtime_ns].
	// On error returns the structured error map (same convention as other `oren_*` helpers).
	OrenValue oren_file_stat_size_mtime_ns(OrenValue path);
	OrenValue oren_bytes_from_string(OrenValue s);
// Build a string from list<int 0..255> (inverse of bytes_from_string).
OrenValue oren_string_from_bytes(OrenValue bytes);

// --- TIME (C backend runtime) ---
//
// Convention:
// - sleep returns 0 on success, or -errno on failure
// - time returns nanoseconds in an int (best-effort)
OrenValue oren_sleep_ms(OrenValue ms);
OrenValue oren_sleep_ns(OrenValue ns);
OrenValue oren_time_now_ns();
OrenValue oren_time_unix_ns();
OrenValue oren_time_mono_raw();
// Fill `len` bytes at `ptr` with OS entropy. Returns 0 on success, or -errno.
OrenValue oren_getentropy(OrenValue ptr, OrenValue len);
// Byte-level reads/writes (list<int 0..255>) helpers.
OrenValue oren_bytes_get_u8(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_set_u8(OrenValue bytes, OrenValue index, OrenValue value);
// Endian-aware reads from list<int 0..255> (network parsing helpers).
OrenValue oren_bytes_get_u16_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_u16_le(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i16_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i16_le(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_u32_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_u32_le(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i32_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i32_le(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_u64_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_u64_le(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i64_be(OrenValue bytes, OrenValue index);
OrenValue oren_bytes_get_i64_le(OrenValue bytes, OrenValue index);
// Endian-aware writes to list<int 0..255> (network serialization helpers).
OrenValue oren_bytes_set_u16_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_u16_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i16_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i16_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_u32_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_u32_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i32_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i32_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_u64_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_u64_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i64_be(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_bytes_set_i64_le(OrenValue bytes, OrenValue index, OrenValue value);
OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length);
// Compute SHA-256 of a string's bytes (excluding the NUL terminator).
// Returns a list<int 0..255> of length 32 (digest bytes).
OrenValue oren_sha256_string(OrenValue s);
OrenValue oren_env(OrenValue name);
OrenValue oren_net_get(OrenValue url);

// Raw pointer allocation (C backend / FFI helpers).
// Returns an integer address (fits in i64 on supported platforms).
OrenValue oren_ptr_alloc(OrenValue bytes);
OrenValue oren_ptr_free(OrenValue ptr);

// Pointer byte-order helpers (portable across native + C backends).
OrenValue oren_ptr_get_u8(OrenValue p);
OrenValue oren_ptr_set_u8(OrenValue p, OrenValue v);
OrenValue oren_ptr_get_u16_be(OrenValue p);
OrenValue oren_ptr_get_u16_le(OrenValue p);
OrenValue oren_ptr_get_i16_be(OrenValue p);
OrenValue oren_ptr_get_i16_le(OrenValue p);
OrenValue oren_ptr_set_u16_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_u16_le(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i16_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i16_le(OrenValue p, OrenValue v);
OrenValue oren_ptr_get_u32_be(OrenValue p);
OrenValue oren_ptr_get_u32_le(OrenValue p);
OrenValue oren_ptr_get_i32_be(OrenValue p);
OrenValue oren_ptr_get_i32_le(OrenValue p);
OrenValue oren_ptr_set_u32_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_u32_le(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i32_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i32_le(OrenValue p, OrenValue v);
OrenValue oren_ptr_get_u64_be(OrenValue p);
OrenValue oren_ptr_get_u64_le(OrenValue p);
OrenValue oren_ptr_get_i64_be(OrenValue p);
OrenValue oren_ptr_get_i64_le(OrenValue p);
OrenValue oren_ptr_set_u64_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_u64_le(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i64_be(OrenValue p, OrenValue v);
OrenValue oren_ptr_set_i64_le(OrenValue p, OrenValue v);

// Structured errors (currently represented as a map: {"__err": true, "code": int, "msg": string})
OrenValue oren_err(OrenValue code, OrenValue msg);
OrenValue oren_is_err(OrenValue v);
OrenValue oren_err_code(OrenValue v);
OrenValue oren_err_msg(OrenValue v);

// Result selection (rolling): allows a program/library to publish an explicit “result value”
// for consensus hashing / tooling. Backends are expected to treat this as optional.
OrenValue oren_set_result(OrenValue v);
OrenValue oren_get_result();
void oren_free(OrenValue v);
uint64_t oren_alloc_struct(size_t bytes);
void oren_free_struct(uint64_t ptr);
// Allocate an opaque/raw byte region.
// - Payload contains no OrenValue pointers (unscanned by the GC; safe for HPC buffers).
// - `align` must be a power of two, and >= sizeof(void*). Use 64 for SIMD-friendly kernels.
uint64_t oren_alloc_raw_aligned(size_t bytes, size_t align);
void oren_free_raw(uint64_t ptr);
OrenValue oren_system(OrenValue cmd);
OrenValue oren_exit(OrenValue code);
OrenValue oren_chmod(OrenValue path, OrenValue mode);
OrenValue oren_rename(OrenValue from, OrenValue to);
// Recursive directory creation.
//
// Return convention (syscall-like):
// - 0 on success
// - negative errno on failure
//
// This is used by compiler tooling and other bootstrap paths that must work
// without shelling out to `mkdir -p` (especially on Windows).
OrenValue oren_mkdir_p(OrenValue path);
// Existence predicates (filesystem).
//
// Return convention:
// - returns a bool value (`true`/`false`)
// - never returns an error map
//
// These helpers are intentionally small so stage1 tooling can avoid shell probes like:
//   - POSIX: `test -f ...`
//   - Windows: `if exist ...`
OrenValue oren_exists(OrenValue path);
OrenValue oren_is_file(OrenValue path);
OrenValue oren_unlink(OrenValue path);
OrenValue oren_rmdir(OrenValue path);
// Recursive delete (rm -rf semantics).
//
// Return convention (syscall-like):
// - 0 on success (including when the path does not exist)
// - negative errno on failure
OrenValue oren_rm_rf(OrenValue path);

void oren_print(OrenValue v);
void oren_print_multi(int count, ...);
void oren_print_fmt(OrenValue fmt, int count, ...);
void oren_print_list(OrenValue args_list);
void oren_print_spread(OrenValue fixed_args, OrenValue spread_list);
void oren_print_fmt_list(OrenValue fmt, OrenValue args_list);
void oren_print_fmt_spread(OrenValue fmt, OrenValue fixed_args, OrenValue spread_list);
void oren_shutdown();
void oren_panic(const char* msg);
// Stack safety (rolling): deterministic recursion guard for C backend binaries.
// Oren source lowering may call these on function entry/exit.
void oren_call_depth_enter();
void oren_call_depth_exit();
OrenValue oren_fail(OrenValue code, OrenValue msg);

#endif
