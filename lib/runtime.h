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
    OREN_TYPE_MAP
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

typedef struct {
    OrenType type;
    union {
        long long int_val;
        double float_val;
        int bool_val;
        char* string_val;
        PyObject* py_obj;
        struct OrenList* list_val;
        struct OrenMap* map_val;
    } as;
} OrenValue;

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
OrenValue oren_join(OrenValue thread);
OrenValue oren_detach(OrenValue thread);
OrenValue oren_is_done(OrenValue thread);
OrenValue oren_join_all();

OrenValue oren_int(long long v);
OrenValue oren_float(double v);
OrenValue oren_string(const char* s);
OrenValue oren_bool(int v);

int oren_is_truthy(OrenValue v);

OrenValue oren_add(OrenValue a, OrenValue b);
OrenValue oren_sub(OrenValue a, OrenValue b);
OrenValue oren_mul(OrenValue a, OrenValue b);
OrenValue oren_div(OrenValue a, OrenValue b);

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

OrenValue oren_new_list(int count, ...);
OrenValue oren_list_len(OrenValue list);
OrenValue oren_list_push(OrenValue list, OrenValue value);
OrenValue oren_list_get(OrenValue list, OrenValue index);
OrenValue oren_iter_next(OrenValue container, OrenValue idx);
OrenValue oren_index_set(OrenValue container, OrenValue index, OrenValue value);

OrenValue oren_new_map(int count, ...);
OrenValue oren_map_get(OrenValue map, OrenValue key);

OrenValue oren_string_len(OrenValue s);
OrenValue oren_string_char_at(OrenValue s, OrenValue index);
OrenValue oren_string_slice(OrenValue s, OrenValue start, OrenValue end);
OrenValue oren_char(OrenValue code);
OrenValue oren_int_to_string(OrenValue v);
OrenValue oren_float_to_string(OrenValue v);
OrenValue oren_string_to_float_bits(OrenValue s);

OrenValue oren_read_file(OrenValue path);
OrenValue oren_write_file(OrenValue path, OrenValue content);
OrenValue oren_write_bytes(OrenValue path, OrenValue bytes);
OrenValue oren_read_bytes(OrenValue path);
OrenValue oren_bytes_from_string(OrenValue s);
OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length);
OrenValue oren_env(OrenValue name);
OrenValue oren_net_get(OrenValue url);

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
OrenValue oren_system(OrenValue cmd);
OrenValue oren_exit(OrenValue code);
OrenValue oren_chmod(OrenValue path, OrenValue mode);

void oren_print(OrenValue v);
void oren_print_multi(int count, ...);
void oren_print_fmt(OrenValue fmt, int count, ...);
void oren_shutdown();
void oren_panic(const char* msg);

#endif
