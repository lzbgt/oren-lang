static void print_value_no_newline(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_INT: printf("%lld", v.as.int_val); break;
        case OREN_TYPE_FLOAT: printf("%f", v.as.float_val); break;
        case OREN_TYPE_BOOL: printf("%s", v.as.bool_val ? "true" : "false"); break;
        case OREN_TYPE_STRING: printf("%s", v.as.string_val); break;
        case OREN_TYPE_NIL: printf("nil"); break;
        case OREN_TYPE_FUNC: printf("<func %p>", (void*)v.as.func_val.fn); break;
        case OREN_TYPE_U8_BUF:
            printf("<u8_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_I32_BUF:
            printf("<i32_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_I64_BUF:
            printf("<i64_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_F32_BUF:
            printf("<f32_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_F64_BUF:
            printf("<f64_buf len=%u>", v.as.buf_val ? v.as.buf_val->len : 0u);
            break;
        case OREN_TYPE_GENERATOR:
        case OREN_TYPE_GENERATOR_CONTEXT:
            if (oren_generator_print_internal(v)) break;
            break;
        case OREN_TYPE_PY_OBJ: {
#ifdef OREN_ENABLE_PYTHON
            PyObject* str = PyObject_Str(v.as.py_obj);
            printf("%s", PyUnicode_AsUTF8(str));
            Py_DECREF(str);
            break;
#else
            oren_panic("Python support is disabled");
#endif
        }
        case OREN_TYPE_LIST: {
            printf("[");
            for (int i = 0; i < v.as.list_val->count; i++) {
                if (i > 0) printf(", ");
                print_value_no_newline(v.as.list_val->items[i]);
            }
            printf("]");
            break;
        }
        case OREN_TYPE_MAP: {
             printf("{");
             for (int i = 0; i < v.as.map_val->count; i++) {
                 if (i > 0) printf(", ");
                 print_value_no_newline(v.as.map_val->keys[i]);
                 printf(": ");
                 print_value_no_newline(v.as.map_val->values[i]);
             }
             printf("}");
             break;
        }
    }
}

void oren_print(OrenValue v) {
    print_value_no_newline(v);
    printf("\n");
}

void oren_print_multi(int count, ...) {
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) {
        OrenValue v = va_arg(args, OrenValue);
        print_value_no_newline(v);
        if (i < count - 1) printf(" ");
    }
    printf("\n");
    va_end(args);
}

void oren_print_fmt(OrenValue fmt_val, int count, ...) {
    if (fmt_val.type != OREN_TYPE_STRING) {
        oren_panic("print format must be string");
        return;
    }
    const char* fmt = fmt_val.as.string_val;
    va_list args;
    va_start(args, count);

    int arg_idx = 0;
    int len = strlen(fmt);
    int i = 0;
    while (i < len) {
        if (fmt[i] == '{' && i + 1 < len && fmt[i+1] == '}') {
            if (arg_idx < count) {
                OrenValue v = va_arg(args, OrenValue);
                print_value_no_newline(v);
                arg_idx++;
            } else {
                printf("{}");
            }
            i += 2;
        } else {
            putchar(fmt[i]);
            i++;
        }
    }
    printf("\n");
    va_end(args);
}

void oren_print_list(OrenValue args_list) {
    if (args_list.type == OREN_TYPE_NIL) {
        printf("\n");
        return;
    }
    if (args_list.type != OREN_TYPE_LIST) {
        oren_panic("print_list expects list");
        return;
    }
    OrenList* l = args_list.as.list_val;
    if (!l || l->count <= 0) {
        printf("\n");
        return;
    }
    for (int i = 0; i < l->count; i++) {
        print_value_no_newline(l->items[i]);
        if (i < l->count - 1) printf(" ");
    }
    printf("\n");
}

void oren_print_fmt_list(OrenValue fmt_val, OrenValue args_list) {
    if (fmt_val.type != OREN_TYPE_STRING) {
        oren_panic("print format must be string");
        return;
    }
    if (args_list.type != OREN_TYPE_LIST && args_list.type != OREN_TYPE_NIL) {
        oren_panic("print_fmt_list expects args list");
        return;
    }
    OrenList* l = (args_list.type == OREN_TYPE_LIST) ? args_list.as.list_val : NULL;
    int count = l ? l->count : 0;
    const char* fmt = fmt_val.as.string_val;

    int arg_idx = 0;
    int len = (int)strlen(fmt);
    int i = 0;
    while (i < len) {
        if (fmt[i] == '{' && i + 1 < len && fmt[i + 1] == '}') {
            if (arg_idx < count) {
                print_value_no_newline(l->items[arg_idx]);
                arg_idx++;
            } else {
                printf("{}");
            }
            i += 2;
        } else {
            putchar(fmt[i]);
            i++;
        }
    }
    printf("\n");
}

static void print_build_args(OrenValue* out_list, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = oren_new_list(0);
    if (fixed_args.type != OREN_TYPE_NIL) {
        if (fixed_args.type != OREN_TYPE_LIST) {
            oren_panic("spread fixed args must be list");
            *out_list = OREN_NIL;
            return;
        }
        OrenList* f = fixed_args.as.list_val;
        for (int i = 0; i < f->count; i++) {
            oren_list_push(args, f->items[i]);
        }
    }
    if (spread_list.type != OREN_TYPE_NIL) {
        if (spread_list.type != OREN_TYPE_LIST) {
            oren_panic("spread list must be list");
            *out_list = OREN_NIL;
            return;
        }
        OrenList* s = spread_list.as.list_val;
        for (int i = 0; i < s->count; i++) {
            oren_list_push(args, s->items[i]);
        }
    }
    *out_list = args;
}

void oren_print_spread(OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return;
    oren_print_list(args);
}

void oren_print_fmt_spread(OrenValue fmt, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return;
    oren_print_fmt_list(fmt, args);
}

OrenValue oren_call_obj_spread(OrenValue fn, OrenValue fixed_args, OrenValue spread_list) {
    OrenValue args = OREN_NIL;
    print_build_args(&args, fixed_args, spread_list);
    if (args.type == OREN_TYPE_NIL) return OREN_NIL;
    return oren_call_obj_list(fn, args);
}

// Iterator hook for `for x in <container>` sugar.
// Contract:
//   oren_iter_next(container, idx:int, out_pair:list|nil) -> [ok:int, value]
// Where ok is 1 when a value exists, 0 when iteration is complete.
//
// v0 iteration rules:
// - list: yields elements (idx 0..len-1)
// - map: yields keys in deterministic key order (idx 0..count-1)
// - string: yields byte codepoints (unsigned 0..255), stops at NUL terminator
static OrenValue iter_fill_pair(OrenValue out_pair, OrenValue okv, OrenValue val) {
    if (out_pair.type == OREN_TYPE_LIST && out_pair.as.list_val) {
        OrenList* l = out_pair.as.list_val;
        if (l->capacity >= 2 && l->items) {
            if (l->count < 2) l->count = 2;
            l->items[0] = okv;
            l->items[1] = val;
            return out_pair;
        }
    }
    return oren_new_list_from_array(2, (OrenValue[]){okv, val});
}

OrenValue oren_iter_next(OrenValue container, OrenValue idx, OrenValue out_pair) {
    if (idx.type != OREN_TYPE_INT) {
        oren_panic("iter_next expects (container, int idx, list|nil out_pair)");
        return OREN_NIL; // Should not be reached
    }

    long long i = idx.as.int_val;
    if (i < 0) {
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    // Typed buffer "view" lists (rolling, HPC):
    // - slice view:   [buf, off, len]
    // - strided view: [buf, off, len, stride]
    //
    // These are represented as normal lists for portability, but `for x in view`
    // should iterate the underlying buffer elements, not the metadata fields.
    if (container.type == OREN_TYPE_LIST && container.as.list_val) {
        OrenList* l = container.as.list_val;
        if (l->count == 3 || l->count == 4) {
            OrenValue b = l->items[0];
            if (b.type == OREN_TYPE_U8_BUF || b.type == OREN_TYPE_I32_BUF || b.type == OREN_TYPE_I64_BUF ||
                b.type == OREN_TYPE_F32_BUF || b.type == OREN_TYPE_F64_BUF) {
                OrenValue offv = l->items[1];
                OrenValue lenv = l->items[2];
                OrenValue stridev = (l->count == 4) ? l->items[3] : oren_int(1);
                if (offv.type != OREN_TYPE_INT || lenv.type != OREN_TYPE_INT || stridev.type != OREN_TYPE_INT) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                long long off = offv.as.int_val;
                long long n = lenv.as.int_val;
                long long stride = stridev.as.int_val;
                if (off < 0 || n < 0 || stride <= 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                if (i < n) {
                    long long elem_idx = off + i * stride;
                    OrenValue v = OREN_NIL;
                    OrenValue idxv = oren_int(elem_idx);
                    if (b.type == OREN_TYPE_U8_BUF) v = oren_buf_load_u8(b, idxv);
                    else if (b.type == OREN_TYPE_I32_BUF) v = oren_buf_load_i32(b, idxv);
                    else if (b.type == OREN_TYPE_I64_BUF) v = oren_buf_load_i64(b, idxv);
                    else if (b.type == OREN_TYPE_F32_BUF) v = oren_buf_load_f32(b, idxv);
                    else v = oren_buf_load_f64(b, idxv);
                    if (oren_is_err(v).as.bool_val) {
                        oren_panic("iter_next: buffer view load failed");
                        return OREN_NIL;
                    }
                    return iter_fill_pair(out_pair, oren_int(1), v);
                }
                return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
            }
        }
    }

    if (container.type == OREN_TYPE_LIST) {
        OrenList* l = container.as.list_val;
        if (i < l->count) {
            return iter_fill_pair(out_pair, oren_int(1), l->items[(int)i]);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_MAP) {
        // "Iterable map" protocol (rolling): allow maps to represent stream-like iterables.
        //
        // This is used by std/iter.oren's `range(...)` helpers:
        //   {"__iter":"range","start":0,"end":N,"step":1}
        //
        // Note: normal maps still iterate keys deterministically.
        OrenValue it = oren_map_get(container, oren_string_const("__iter"));
        if (it.type == OREN_TYPE_STRING && it.as.string_val && strcmp(it.as.string_val, "range") == 0) {
            OrenValue startv = oren_map_get(container, oren_string_const("start"));
            OrenValue endv = oren_map_get(container, oren_string_const("end"));
            OrenValue stepv = oren_map_get(container, oren_string_const("step"));
            // If the iterable map is malformed, treat it as an empty sequence (deterministic,
            // avoids crashing in production).
            if (startv.type == OREN_TYPE_INT && endv.type == OREN_TYPE_INT && stepv.type == OREN_TYPE_INT) {
                long long start = startv.as.int_val;
                long long end = endv.as.int_val;
                long long step = stepv.as.int_val;
                if (step == 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                long long v = start + (long long)i * step;
                if ((step > 0 && v < end) || (step < 0 && v > end)) {
                    return iter_fill_pair(out_pair, oren_int(1), oren_int(v));
                }
            }
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        if (it.type == OREN_TYPE_STRING && it.as.string_val && strcmp(it.as.string_val, "list_slice") == 0) {
            // Iterable map protocol (rolling): list slice view.
            //
            // Produced by std:list.slice_view(xs, off, n):
            //   {"__iter":"list_slice","base":xs,"off":off,"len":n}
            //
            // If malformed, treat as empty iteration (deterministic, avoids crashes).
            OrenValue basev = oren_map_get(container, oren_string_const("base"));
            OrenValue offv = oren_map_get(container, oren_string_const("off"));
            OrenValue lenv = oren_map_get(container, oren_string_const("len"));
            if (basev.type == OREN_TYPE_LIST && basev.as.list_val && offv.type == OREN_TYPE_INT && lenv.type == OREN_TYPE_INT) {
                long long off = offv.as.int_val;
                long long n = lenv.as.int_val;
                if (off < 0 || n < 0) {
                    return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
                }
                OrenList* l = basev.as.list_val;
                if (off <= l->count) {
                    long long max_n = (long long)l->count - off;
                    if (n <= max_n && i < n) {
                        long long elem_idx = off + i;
                        if (elem_idx >= 0 && elem_idx < (long long)l->count) {
                            return iter_fill_pair(out_pair, oren_int(1), l->items[(int)elem_idx]);
                        }
                    }
                }
            }
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        OrenMap* m = container.as.map_val;
        if (i < m->count) {
            return iter_fill_pair(out_pair, oren_int(1), m->keys[(int)i]);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    if (container.type == OREN_TYPE_STRING) {
        const unsigned char* s = (const unsigned char*)container.as.string_val;
        if (!s) {
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        unsigned char ch = s[i];
        if (ch == 0) {
            return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
        }
        return iter_fill_pair(out_pair, oren_int(1), oren_int((long long)ch));
    }

    // Typed numeric buffers (C backend).
    if (container.type == OREN_TYPE_U8_BUF || container.type == OREN_TYPE_I32_BUF || container.type == OREN_TYPE_I64_BUF ||
        container.type == OREN_TYPE_F32_BUF || container.type == OREN_TYPE_F64_BUF) {
        OrenBuf* b = container.as.buf_val;
        if (!b) { return iter_fill_pair(out_pair, oren_int(0), OREN_NIL); }
        if (i < (long long)b->len) {
            OrenValue v = OREN_NIL;
            OrenValue idxv = oren_int(i);
            if (container.type == OREN_TYPE_U8_BUF) v = oren_buf_load_u8(container, idxv);
            else if (container.type == OREN_TYPE_I32_BUF) v = oren_buf_load_i32(container, idxv);
            else if (container.type == OREN_TYPE_I64_BUF) v = oren_buf_load_i64(container, idxv);
            else if (container.type == OREN_TYPE_F32_BUF) v = oren_buf_load_f32(container, idxv);
            else v = oren_buf_load_f64(container, idxv);
            // `oren_buf_load_*` can return an Err map only if the buffer is corrupted
            // or index checks diverge; treat this as a hard failure (bug).
            if (oren_is_err(v).as.bool_val) {
                oren_panic("iter_next: buffer load failed");
                return OREN_NIL;
            }
            return iter_fill_pair(out_pair, oren_int(1), v);
        }
        return iter_fill_pair(out_pair, oren_int(0), OREN_NIL);
    }

    oren_panic("iter_next: unsupported container type (need list/map/string/buf)");
    return OREN_NIL; // Should not be reached
}

OrenValue oren_iter_next_entry(OrenValue map, OrenValue idx, OrenValue out_pair) {
    // Map-only entry iteration: fill out_pair[0]=key out_pair[1]=value.
    if (idx.type != OREN_TYPE_INT) {
        oren_panic("iter_next_entry expects (map, int idx, list out_pair)");
        return OREN_NIL;
    }
    if (out_pair.type != OREN_TYPE_LIST || !out_pair.as.list_val) {
        oren_panic("iter_next_entry expects out_pair list");
        return OREN_NIL;
    }
    if (map.type != OREN_TYPE_MAP || !map.as.map_val) {
        return oren_int(0);
    }
    long long i = idx.as.int_val;
    if (i < 0) return oren_int(0);
    OrenMap* m = map.as.map_val;
    if (i >= m->count) return oren_int(0);
    OrenList* l = out_pair.as.list_val;
    if (l->capacity < 2) {
        // Expand out_pair to at least 2.
        lock_collections();
        oren_list_grow(l, 2);
        unlock_collections();
    }
    if (l->count < 2) l->count = 2;
    l->items[0] = m->keys[(int)i];
    l->items[1] = m->values[(int)i];
    return oren_int(1);
}

OrenValue oren_string_len(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("string_len expects string");
        return OREN_NIL; // Should not be reached
    }
    return oren_int((long long)strlen(s.as.string_val));
}

OrenValue oren_string_eq(OrenValue a, OrenValue b) {
    if (a.type != OREN_TYPE_STRING || b.type != OREN_TYPE_STRING) return OREN_FALSE;
    if (!a.as.string_val || !b.as.string_val) return OREN_FALSE;
    return oren_bool(strcmp(a.as.string_val, b.as.string_val) == 0);
}

OrenValue oren_is_string(OrenValue v) {
    return oren_bool(v.type == OREN_TYPE_STRING);
}

OrenValue oren_is_buf(OrenValue v) {
    return oren_bool(
        v.type == OREN_TYPE_U8_BUF ||
        v.type == OREN_TYPE_I32_BUF ||
        v.type == OREN_TYPE_I64_BUF ||
        v.type == OREN_TYPE_F32_BUF ||
        v.type == OREN_TYPE_F64_BUF
    );
}

OrenValue oren_is_u8_buf(OrenValue v) {
    return oren_bool(v.type == OREN_TYPE_U8_BUF);
}

OrenValue oren_type_tag(OrenValue v) {
    return oren_int((long long)v.type);
}

OrenValue oren_type_name(OrenValue v) {
    switch (v.type) {
        case OREN_TYPE_NIL: return oren_string_const("nil");
        case OREN_TYPE_INT: return oren_string_const("int");
        case OREN_TYPE_FLOAT: return oren_string_const("float");
        case OREN_TYPE_BOOL: return oren_string_const("bool");
        case OREN_TYPE_STRING: return oren_string_const("string");
        case OREN_TYPE_PY_OBJ: return oren_string_const("py_obj");
        case OREN_TYPE_LIST: return oren_string_const("list");
        case OREN_TYPE_MAP: {
            // Rolling reflection v0: type constructor values are map-shaped and tagged with:
            //   {"__oren_type":"User", ...}
            OrenValue tn = oren_map_get_str(v, oren_string_const("__oren_type"));
            if (tn.type == OREN_TYPE_STRING) return tn;
            return oren_string_const("map");
        }
        case OREN_TYPE_FUNC: return oren_string_const("func");
        case OREN_TYPE_U8_BUF: return oren_string_const("u8_buf");
        case OREN_TYPE_I32_BUF: return oren_string_const("i32_buf");
        case OREN_TYPE_I64_BUF: return oren_string_const("i64_buf");
        case OREN_TYPE_F32_BUF: return oren_string_const("f32_buf");
        case OREN_TYPE_F64_BUF: return oren_string_const("f64_buf");
        case OREN_TYPE_GENERATOR:
        case OREN_TYPE_GENERATOR_CONTEXT:
            return oren_generator_type_name_internal(v);
        default: return oren_string_const("unknown");
    }
}

static pthread_once_t g_single_byte_strings_once = PTHREAD_ONCE_INIT;
static char g_single_byte_strings[256][2];

static void init_single_byte_strings(void) {
    for (int i = 0; i < 256; i++) {
        g_single_byte_strings[i][0] = (char)i;
        g_single_byte_strings[i][1] = '\0';
    }
}

static inline OrenValue oren_string_from_single_byte(unsigned char b) {
    pthread_once(&g_single_byte_strings_once, init_single_byte_strings);
    return oren_string_const(g_single_byte_strings[b]);
}

OrenValue oren_string_char_at(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("char_at expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    size_t len = strlen(s.as.string_val);
    if (idx < 0 || (size_t)idx >= len) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char_at index out of range (idx=%lld, len=%zu)", idx, len);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    return oren_string_from_single_byte((unsigned char)s.as.string_val[idx]);
}

OrenValue oren_string_char_at_unchecked(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("char_at_unchecked expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    if (idx < 0) {
        oren_panic("char_at_unchecked index out of range");
        return OREN_NIL; // Should not be reached
    }
    // Caller guarantees idx is within the string's known length.
    // Avoid `strlen` here: lexing is otherwise O(n^2).
    return oren_string_from_single_byte((unsigned char)s.as.string_val[(size_t)idx]);
}

OrenValue oren_string_byte_at_unchecked(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("string_byte_at_unchecked expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    if (idx < 0) {
        oren_panic("string_byte_at_unchecked index out of range");
        return OREN_NIL; // Should not be reached
    }
    // Caller guarantees idx is within the string's known length.
    return oren_int((long long)(unsigned char)s.as.string_val[(size_t)idx]);
}

OrenValue oren_string_char_code_at(OrenValue s, OrenValue index) {
    if (s.type != OREN_TYPE_STRING || index.type != OREN_TYPE_INT) {
        oren_panic("char_code_at expects (string, int)");
        return OREN_NIL; // Should not be reached
    }
    long long idx = index.as.int_val;
    size_t len = strlen(s.as.string_val);
    if (idx < 0 || (size_t)idx >= len) {
        char buf[128];
        snprintf(buf, sizeof(buf), "char_code_at index out of range (idx=%lld, len=%zu)", idx, len);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }
    return oren_int((long long)(unsigned char)s.as.string_val[(size_t)idx]);
}

OrenValue oren_resolve_symbol(OrenValue addr) {
    // C backend fallback: native emitters may generate a real symbol resolver in debug mode,
    // but C runtime builds do not have access to that symbol table. Keep this stub so
    // compiler tooling can call `oren_resolve_symbol(...)` portably.
    (void)addr;
    return oren_string("???");
}
