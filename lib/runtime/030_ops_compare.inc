OrenValue oren_add(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        // Deterministic i64 wrap semantics (two's complement) without signed-overflow UB.
        uint64_t ua = 0, ub = 0, ur = 0;
        long long r = 0;
        memcpy(&ua, &a.as.int_val, sizeof(ua));
        memcpy(&ub, &b.as.int_val, sizeof(ub));
        ur = ua + ub;
        memcpy(&r, &ur, sizeof(r));
        return oren_int(r);
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
    if (a.type == OREN_TYPE_STRING && b.type == OREN_TYPE_STRING) {
         // Rolling: deterministic string concat.
         //
         // IMPORTANT: the result must be registered as a GC-tracked STRING allocation.
         // The compiler and tooling build many transient strings (e.g. lexing/printing);
         // failing to register here causes unbounded RSS growth (leak-by-bug).
         const char* as = a.as.string_val ? a.as.string_val : "";
         const char* bs = b.as.string_val ? b.as.string_val : "";
         size_t al = strlen(as);
         size_t bl = strlen(bs);
         size_t nl = al + bl;
         char* new_s = (char*)malloc(nl + 1);
         if (!new_s) {
             oren_panic("string concat: malloc failed");
             return OREN_NIL; // Should not be reached
         }
         if (al) memcpy(new_s, as, al);
         if (bl) memcpy(new_s + al, bs, bl);
         new_s[nl] = '\0';
         oren_register_alloc(new_s, OREN_ALLOC_STRING);
         OrenValue val;
         val.type = OREN_TYPE_STRING;
         val.as.string_val = new_s;
         return val;
    }
    if (getenv("OREN_TRACE_ADD_MISMATCH")) {
        fprintf(stderr, "[trace] add mismatch a.type=%d b.type=%d\n", a.type, b.type);
#if defined(__GNUC__) || defined(__clang__)
        // Useful for mapping back to a call-site during compiler bring-up.
        // MSVC does not support `__builtin_return_address`.
        void* ra0 = __builtin_return_address(0);
        fprintf(stderr, "[trace] add mismatch ra0=%p\n", ra0);
#endif
        if (a.type == OREN_TYPE_INT) fprintf(stderr, "[trace] a.int=%lld\n", (long long)a.as.int_val);
        if (b.type == OREN_TYPE_INT) fprintf(stderr, "[trace] b.int=%lld\n", (long long)b.as.int_val);
        if (a.type == OREN_TYPE_FLOAT) fprintf(stderr, "[trace] a.float=%f\n", a.as.float_val);
        if (b.type == OREN_TYPE_FLOAT) fprintf(stderr, "[trace] b.float=%f\n", b.as.float_val);
        if (a.type == OREN_TYPE_STRING) fprintf(stderr, "[trace] a.str=%.120s\n", a.as.string_val ? a.as.string_val : "<null>");
        if (b.type == OREN_TYPE_STRING) fprintf(stderr, "[trace] b.str=%.120s\n", b.as.string_val ? b.as.string_val : "<null>");
    }
    oren_panic("Type mismatch in add");
    return OREN_NIL;
}

OrenValue oren_sub(OrenValue a, OrenValue b) {
    if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        // Deterministic i64 wrap semantics (two's complement) without signed-overflow UB.
        uint64_t ua = 0, ub = 0, ur = 0;
        long long r = 0;
        memcpy(&ua, &a.as.int_val, sizeof(ua));
        memcpy(&ub, &b.as.int_val, sizeof(ub));
        ur = ua - ub;
        memcpy(&r, &ur, sizeof(r));
        return oren_int(r);
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
    if (getenv("OREN_TRACE_SUB_MISMATCH")) {
        fprintf(stderr, "[trace] sub mismatch a.type=%d b.type=%d\n", a.type, b.type);
    }
    oren_panic("Type mismatch in sub");
    return OREN_NIL;
}

OrenValue oren_mul(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        // Deterministic i64 wrap semantics (two's complement) without signed-overflow UB.
        uint64_t ua = 0, ub = 0, ur = 0;
        long long r = 0;
        memcpy(&ua, &a.as.int_val, sizeof(ua));
        memcpy(&ub, &b.as.int_val, sizeof(ub));
        ur = ua * ub;
        memcpy(&r, &ur, sizeof(r));
        return oren_int(r);
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
    oren_panic("Type mismatch in mul");
    return OREN_NIL;
}

OrenValue oren_div(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        // Deterministic error instead of host SIGFPE / UB.
        if (b.as.int_val == 0) {
            oren_panic("division by zero");
            return OREN_NIL;
        }
        // INT64_MIN / -1 overflows in two's complement.
        if (a.as.int_val == LLONG_MIN && b.as.int_val == -1) {
            oren_panic("division overflow (i64_min / -1)");
            return OREN_NIL;
        }
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
    oren_panic("Type mismatch in div");
    return OREN_NIL;
}

// --- TIME (C backend runtime) ---
//
// Note: this is a host-effectful backend; libc usage here is acceptable for bootstrap.
// AVM determinism is provided by the AVM TIME domain; native backend uses syscall-first TIME.

OrenValue oren_sleep_ns(OrenValue ns) {
    if (ns.type != OREN_TYPE_INT) {
        oren_panic("sleep_ns expects int");
        return OREN_NIL;
    }
    long long nsv = ns.as.int_val;
    if (nsv <= 0) return oren_int(0);

    // Avoid overflow in seconds conversion.
    long long sec = nsv / 1000000000LL;
    long long nsec = nsv % 1000000000LL;
    if (nsec < 0) nsec = 0;

    struct timespec ts;
    ts.tv_sec = (time_t)sec;
    ts.tv_nsec = (long)nsec;

    while (1) {
        int rc = nanosleep(&ts, &ts);
        if (rc == 0) return oren_int(0);
        if (errno == EINTR) continue;
        return oren_int(0 - (long long)errno);
    }
}

OrenValue oren_sleep_ms(OrenValue ms) {
    if (ms.type != OREN_TYPE_INT) {
        oren_panic("sleep_ms expects int");
        return OREN_NIL;
    }
    long long msv = ms.as.int_val;
    if (msv <= 0) return oren_int(0);
    // ms -> ns, detect overflow conservatively.
    if (msv > LLONG_MAX / 1000000LL) {
        return oren_int(0 - (long long)EINVAL);
    }
    return oren_sleep_ns(oren_int(msv * 1000000LL));
}

OrenValue oren_yield(void) {
#if defined(_WIN32)
    Sleep(0);
    return oren_int(0);
#elif defined(__linux__)
    int rc = sched_yield();
    if (rc == 0) return oren_int(0);
    return oren_int(0 - (long long)errno);
#else
    // Keep parity with the rolling native runtime surface on macOS/other POSIX hosts:
    // `yield` is currently a best-effort no-op when no stronger scheduler hook exists.
    return oren_int(0);
#endif
}

OrenValue oren_yield_stmt(void) {
    (void)oren_yield();
    return OREN_NIL;
}

static OrenValue oren_time_clock_ns(clockid_t clk) {
    struct timespec ts;
    if (clock_gettime(clk, &ts) != 0) {
        return oren_int(0);
    }
    long long sec = (long long)ts.tv_sec;
    long long nsec = (long long)ts.tv_nsec;
    return oren_int(sec * 1000000000LL + nsec);
}

OrenValue oren_time_unix_ns() {
    // Prefer clock_gettime; fall back to gettimeofday if unavailable.
#ifdef CLOCK_REALTIME
    return oren_time_clock_ns(CLOCK_REALTIME);
#else
    struct timeval tv;
    if (gettimeofday(&tv, NULL) != 0) return oren_int(0);
    return oren_int((long long)tv.tv_sec * 1000000000LL + (long long)tv.tv_usec * 1000LL);
#endif
}

OrenValue oren_time_mono_raw() {
#ifdef CLOCK_MONOTONIC
    return oren_time_clock_ns(CLOCK_MONOTONIC);
#else
    // Best-effort fallback: wall clock.
    return oren_time_unix_ns();
#endif
}

OrenValue oren_time_now_ns() {
    // Rolling alias for compatibility with the AVM TIME domain surface.
    return oren_time_unix_ns();
}

OrenValue oren_mod(OrenValue a, OrenValue b) {
     if (a.type == OREN_TYPE_INT && b.type == OREN_TYPE_INT) {
        // Deterministic error instead of host SIGFPE / UB.
        if (b.as.int_val == 0) {
            oren_panic("modulo by zero");
            return OREN_NIL;
        }
        // INT64_MIN % -1 is undefined in C because it implies INT64_MIN / -1 overflow.
        if (a.as.int_val == LLONG_MIN && b.as.int_val == -1) {
            oren_panic("modulo overflow (i64_min % -1)");
            return OREN_NIL;
        }
        return oren_int(a.as.int_val % b.as.int_val);
    }
    oren_panic("Type mismatch in mod");
    return OREN_NIL;
}

static uint64_t oren_u64(OrenValue v, const char *op) {
    if (v.type != OREN_TYPE_INT) {
        char buf[64];
        snprintf(buf, sizeof(buf), "%s expects int", op);
        oren_panic(buf);
        return 0ULL; // Should not be reached, but needed for compiler
    }
    return (uint64_t)v.as.int_val;
}

OrenValue oren_band(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitand");
    uint64_t y = oren_u64(b, "bitand");
    uint64_t ur = (x & y);
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_bor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitor");
    uint64_t y = oren_u64(b, "bitor");
    uint64_t ur = (x | y);
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_bxor(OrenValue a, OrenValue b) {
    uint64_t x = oren_u64(a, "bitxor");
    uint64_t y = oren_u64(b, "bitxor");
    uint64_t ur = (x ^ y);
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_shl(OrenValue a, OrenValue b) {
    if (a.type != OREN_TYPE_INT || b.type != OREN_TYPE_INT) {
        oren_panic("shl expects int");
        return OREN_NIL;
    }
    long long s = b.as.int_val;
    if (s < 0 || s >= 64) {
        oren_panic("shl shift count out of range (need 0..63)");
        return OREN_NIL;
    }
    uint64_t x = 0;
    memcpy(&x, &a.as.int_val, sizeof(x));
    uint64_t ur = x << (uint64_t)s;
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_shr(OrenValue a, OrenValue b) {
    if (a.type != OREN_TYPE_INT || b.type != OREN_TYPE_INT) {
        oren_panic("shr expects int");
        return OREN_NIL;
    }
    long long s = b.as.int_val;
    if (s < 0 || s >= 64) {
        oren_panic("shr shift count out of range (need 0..63)");
        return OREN_NIL;
    }
    uint64_t x = 0;
    memcpy(&x, &a.as.int_val, sizeof(x));
    uint64_t ur = x >> (uint64_t)s;
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_bnot(OrenValue v) {
    uint64_t x = oren_u64(v, "bnot");
    uint64_t ur = ~x;
    long long r = 0;
    memcpy(&r, &ur, sizeof(r));
    return oren_int(r);
}

OrenValue oren_eq(OrenValue a, OrenValue b) {
    if (a.type != b.type) return OREN_FALSE;
    switch (a.type) {
        case OREN_TYPE_INT: return oren_bool(a.as.int_val == b.as.int_val);
        case OREN_TYPE_FLOAT: return oren_bool(a.as.float_val == b.as.float_val);
        case OREN_TYPE_BOOL: return oren_bool(a.as.bool_val == b.as.bool_val);
        case OREN_TYPE_STRING: return oren_bool(strcmp(a.as.string_val, b.as.string_val) == 0);
        case OREN_TYPE_NIL: return OREN_TRUE;
        case OREN_TYPE_FUNC:
            return oren_bool(a.as.func_val.fn == b.as.func_val.fn && a.as.func_val.env == b.as.func_val.env);
        case OREN_TYPE_U8_BUF:
        case OREN_TYPE_I32_BUF:
        case OREN_TYPE_I64_BUF:
        case OREN_TYPE_F32_BUF:
        case OREN_TYPE_F64_BUF:
            return oren_bool(a.as.buf_val == b.as.buf_val);
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            // Check identity or equality
            int res = PyObject_RichCompareBool(a.as.py_obj, b.as.py_obj, Py_EQ);
            if (res == -1) { PyErr_Clear(); return OREN_FALSE; }
            return oren_bool(res);
#else
            oren_panic("Python support is disabled");
            return OREN_FALSE;
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
        oren_panic("import expects string");
        return OREN_NIL; // Should not be reached
    }
    PyObject* mod = PyImport_ImportModule(name.as.string_val);
    if (!mod) {
        PyErr_Print();
        char buf[256];
        snprintf(buf, sizeof(buf), "Could not import python module %s", name.as.string_val);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    OrenValue v;
    v.type = OREN_TYPE_PY_OBJ;
    v.as.py_obj = mod;
    return v;
}

OrenValue oren_py_release(OrenValue obj) {
    if (obj.type != OREN_TYPE_PY_OBJ) {
        oren_panic("py_release expects a Python object");
        return OREN_NIL;
    }
    if (obj.as.py_obj != NULL) {
        Py_DECREF(obj.as.py_obj);
    }
    return OREN_NIL;
}
#else
OrenValue oren_py_import(OrenValue name) {
    (void)name;
    oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_py_release(OrenValue obj) {
    (void)obj;
    oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
    return OREN_NIL; // Should not be reached
}
#endif

OrenValue oren_get_attr(OrenValue obj, const char* attr) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* val = PyObject_GetAttrString(obj.as.py_obj, attr);
        if (!val) {
            PyErr_Print();
            char buf[256];
            snprintf(buf, sizeof(buf), "Python object has no attribute '%s'", attr);
            oren_panic(buf);
            return OREN_NIL; // Should not be reached
        }
        return oren_py_to_oren(val);
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return OREN_NIL; // Should not be reached
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_map_get(obj, oren_string(attr));
    }
    oren_panic("get_attr only supported for Python objects and maps currently");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_set_attr(OrenValue obj, const char* attr, OrenValue value) {
#ifdef OREN_ENABLE_PYTHON
    if (obj.type == OREN_TYPE_PY_OBJ) {
        PyObject* py_val = oren_to_py(value);
        if (PyObject_SetAttrString(obj.as.py_obj, attr, py_val) != 0) {
            PyErr_Print();
            char buf[256];
            snprintf(buf, sizeof(buf), "failed to set attribute '%s'", attr);
            oren_panic(buf);
            return value; // Should not be reached, but needed for compiler
        }
        Py_DECREF(py_val);
        return value;
    }
#else
    if (obj.type == OREN_TYPE_PY_OBJ) {
        (void)attr;
        (void)value;
        oren_panic("Python support is disabled (rebuild with -DOREN_ENABLE_PYTHON)");
        return value; // Should not be reached
    }
#endif
    if (obj.type == OREN_TYPE_MAP) {
        return oren_index_set(obj, oren_string(attr), value);
    }
    oren_panic("set_attr only supported for Python objects and maps currently");
    return value; // Should not be reached
}
