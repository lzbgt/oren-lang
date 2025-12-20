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
    // Basic linear scan map for POC, or hash table.
    // Let's use simple linear scan of key-value pairs for simplicity in C
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

extern OrenValue OREN_NIL;
extern OrenValue OREN_TRUE;
extern OrenValue OREN_FALSE;

void oren_init(int argc, char **argv);
OrenValue oren_args();

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

OrenValue oren_int(long long v);
OrenValue oren_float(double v);
OrenValue oren_string(const char* s);
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
OrenValue oren_py_call(OrenValue obj, int count, ...); // Specific call?
// Actually, generic call support is better
OrenValue oren_call_obj(OrenValue fn, int count, ...);
// Non-varargs forms (useful for spawn/callback paths).
OrenValue oren_call_obj_argv(OrenValue fn, int argc, OrenValue* argv);
OrenValue oren_call_obj_list(OrenValue fn, OrenValue args_list);
OrenValue oren_call_obj_spread(OrenValue fn, OrenValue fixed_args, OrenValue spread_list);

OrenValue oren_new_list(int count, ...);
OrenValue oren_list_len(OrenValue list);
OrenValue oren_list_push(OrenValue list, OrenValue value);
OrenValue oren_list_get(OrenValue list, OrenValue index);
OrenValue oren_list_set(OrenValue list, OrenValue index, OrenValue value);
OrenValue oren_iter_next(OrenValue container, OrenValue idx);
OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value);

OrenValue oren_new_map(int count, ...);
OrenValue oren_map_get(OrenValue map, OrenValue key);
OrenValue oren_map_len(OrenValue map);

OrenValue oren_string_len(OrenValue s);
OrenValue oren_string_char_at(OrenValue s, OrenValue index);
OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end);
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

// Debug/diagnostic helper (C backend): returns (uintptr_t)buf->data % mod.
// Does not expose the full pointer value, but enables alignment assertions in tests.
OrenValue oren_buf_data_mod(OrenValue buf, OrenValue mod);

OrenValue oren_buf_load_u8(OrenValue buf, OrenValue idx);
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
OrenValue oren_buf_dot_i32(OrenValue a, OrenValue b);
OrenValue oren_buf_dot_f32(OrenValue a, OrenValue b);

OrenValue oren_buf_add_i32_into(OrenValue dst, OrenValue a, OrenValue b);
OrenValue oren_buf_add_f32_into(OrenValue dst, OrenValue a, OrenValue b);
OrenValue oren_buf_mul_i32(OrenValue a, OrenValue b);
OrenValue oren_buf_mul_f32(OrenValue a, OrenValue b);
OrenValue oren_buf_mul_i32_into(OrenValue dst, OrenValue a, OrenValue b);
OrenValue oren_buf_mul_f32_into(OrenValue dst, OrenValue a, OrenValue b);
OrenValue oren_buf_scale_i32_into(OrenValue dst, OrenValue a, OrenValue scalar);
OrenValue oren_buf_scale_f32(OrenValue buf, OrenValue scalar);
OrenValue oren_buf_scale_f32_into(OrenValue dst, OrenValue a, OrenValue scalar);

	OrenValue oren_buf_reduce_sum_i32(OrenValue buf);
	OrenValue oren_buf_reduce_sum_f32(OrenValue buf);
	OrenValue oren_buf_dot_i32_into(OrenValue out, OrenValue a, OrenValue b);
	OrenValue oren_buf_dot_f32_into(OrenValue out, OrenValue a, OrenValue b);
	OrenValue oren_buf_reduce_sum_i32_into(OrenValue out, OrenValue a);
	OrenValue oren_buf_reduce_sum_f32_into(OrenValue out, OrenValue a);

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

void oren_print(OrenValue v);
void oren_print_multi(int count, ...);
void oren_print_fmt(OrenValue fmt, int count, ...);
void oren_print_list(OrenValue args_list);
void oren_print_spread(OrenValue fixed_args, OrenValue spread_list);
void oren_print_fmt_list(OrenValue fmt, OrenValue args_list);
void oren_print_fmt_spread(OrenValue fmt, OrenValue fixed_args, OrenValue spread_list);
void oren_shutdown();
void oren_panic(const char* msg);
OrenValue oren_fail(OrenValue code, OrenValue msg);

#endif
