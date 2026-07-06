// --- Cooperative Tasks (rolling, AVM v1 direction) ---
//
// Minimal VM-internal cooperative concurrency model for bytecode `spawn`/`join`,
// channels, and select. Design constraints: single-threaded, deterministic, no
// host syscalls.

static AvmValue avm_err_map_key_unsupported_at(AvmVM* vm, AvmValue key, const char* op) {
    char msg[160];
    snprintf(msg, sizeof(msg), "%s map key type not supported (need nil/bool/int/string): type=%d pc=%d",
        op ? op : "map", (int)key.type, vm ? vm->pc : -1);
    return avm_err(AVM_ERR_INVALID_ARG, msg);
}

// Tasks share heap/globals; blocking ops yield to runnable tasks. This remains a
// rolling foundation for AVM v1 scheduling rules such as gas/time slicing and
// deterministic select fairness.

enum {
    AVM_OP_SPAWN_CALL_LIST = 0x45,  // stack: [... fn args_list] -> [... handle_int]
    AVM_OP_JOIN            = 0x46,  // stack: [... handle_int] -> [... ret]
    AVM_OP_CHAN_NEW        = 0x47,  // stack: [...] -> [... chan_int]
    AVM_OP_CHAN_SEND       = 0x48,  // stack: [... ch val] -> [... ok_int]
    AVM_OP_CHAN_RECV       = 0x49,  // stack: [... ch] -> [... val] (blocks if empty)
    AVM_OP_SELECT_RECV     = 0x4A,  // stack: [... list<ch>] -> [... [idx,val]] (blocks if none ready)
    AVM_OP_YIELD           = 0x4B   // stack: [...] -> [...] (yield to another runnable task)
    ,AVM_OP_JOIN_TIMEOUT   = 0x4C   // stack: [... handle timeout_ms] -> [... ret_or_timeout]
    ,AVM_OP_SELECT         = 0x4D   // stack: [... list<case>] -> [... [idx,payload]] (recv or send)
    ,AVM_OP_DETACH         = 0x62   // stack: [... handle_int] -> [...]
    ,AVM_OP_TASK_CANCEL_AFTER_WAIT = 0x63 // stack: [... handle delay_ms wait_ms reason] -> [... stop_result|err]
    ,AVM_OP_TASK_CANCEL_WAIT = 0x64       // stack: [... handle wait_ms reason] -> [... stop_result|err]
};

static int select_case_parse(AvmValue v, int* out_kind, int64_t* out_chid, AvmValue* out_sendv) {
    if (!out_kind || !out_chid || !out_sendv) return 0;
    if (v.type != AVM_VAL_LIST || !v.as.l) return 0;
    AvmList* lst = v.as.l;
    if (lst->count < 2) return 0;
    AvmValue kindv = lst->items[0];
    AvmValue chidv = lst->items[1];
    if (kindv.type != AVM_VAL_INT || chidv.type != AVM_VAL_INT) return 0;
    int kind = (int)kindv.as.i;
    if (kind == 0) { // recv: [0, ch]
        *out_kind = 0;
        *out_chid = chidv.as.i;
        *out_sendv = avm_nil();
        return 1;
    }
    if (kind == 1) { // send: [1, ch, val]
        if (lst->count < 3) return 0;
        *out_kind = 1;
        *out_chid = chidv.as.i;
        *out_sendv = lst->items[2];
        return 1;
    }
    return 0;
}

static int avm_value_equal_depth(AvmValue a, AvmValue b, int depth) {
    (void)depth;
    if (a.type != b.type) return 0;
    if (a.type == AVM_VAL_NIL) return 1;
    if (a.type == AVM_VAL_INT || a.type == AVM_VAL_BOOL) return a.as.i == b.as.i;
    if (a.type == AVM_VAL_FLOAT) return a.as.f == b.as.f;
    if (a.type == AVM_VAL_STRING) return strcmp((char*)a.as.p, (char*)b.as.p) == 0;
    if (a.type == AVM_VAL_BYTES) return a.as.b == b.as.b;
    if (a.type == AVM_VAL_I32_BUF || a.type == AVM_VAL_I64_BUF ||
        a.type == AVM_VAL_F32_BUF || a.type == AVM_VAL_F64_BUF) return a.as.buf == b.as.buf;
    if (a.type == AVM_VAL_GENERATOR) return a.as.gen == b.as.gen;
    if (a.type == AVM_VAL_GENERATOR_CONTEXT) return a.as.gctx == b.as.gctx;
    if (a.type == AVM_VAL_LIST_INT) return a.as.li == b.as.li;
    if (a.type == AVM_VAL_LIST) return a.as.l == b.as.l;
    if (a.type == AVM_VAL_MAP) return a.as.m == b.as.m;
    return a.as.p == b.as.p;
}

static int avm_list_like_count(AvmValue v, int* out_count) {
    if (v.type == AVM_VAL_LIST && v.as.l) {
        *out_count = v.as.l->count;
        return v.as.l->count >= 0 && (v.as.l->count == 0 || v.as.l->items);
    }
    if (v.type == AVM_VAL_LIST_INT && v.as.li) {
        *out_count = v.as.li->count;
        return v.as.li->count >= 0 && (v.as.li->count == 0 || v.as.li->items);
    }
    return 0;
}

static AvmValue avm_list_like_item(AvmValue v, int idx) {
    if (v.type == AVM_VAL_LIST) return v.as.l->items[idx];
    return avm_int(v.as.li->items[idx]);
}

static AvmValue avm_concat_list_values(AvmValue a, AvmValue b) {
    int ac = 0;
    int bc = 0;
    if (!avm_list_like_count(a, &ac) || !avm_list_like_count(b, &bc) || ac > INT_MAX - bc) {
        return avm_err(AVM_ERR_INVALID_ARG, "list concat expects valid lists");
    }
    int total = ac + bc;
    AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!list) return avm_alloc_fail_value();
    list->count = total;
    list->capacity = total;
    list->all_int = 1;
    list->items = NULL;
    if (total > 0) {
        list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)total, AVM_ALLOC_KIND_LIST);
        if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
        for (int i = 0; i < ac; i++) {
            list->items[i] = avm_list_like_item(a, i);
            if (list->all_int && list->items[i].type != AVM_VAL_INT) list->all_int = 0;
        }
        for (int i = 0; i < bc; i++) {
            list->items[ac + i] = avm_list_like_item(b, i);
            if (list->all_int && list->items[ac + i].type != AVM_VAL_INT) list->all_int = 0;
        }
    }
    AvmValue r;
    r.type = AVM_VAL_LIST;
    r.as.l = list;
    return r;
}

static AvmValue avm_func_new(AvmVM* vm, uint32_t addr, AvmValue env) {
    (void)vm;
    AvmFunc* fn = (AvmFunc*)avm_heap_malloc_k(sizeof(AvmFunc), AVM_ALLOC_KIND_FUNC);
    if (!fn) return avm_alloc_fail_value();
    fn->addr = addr;
    fn->env = env;
    AvmValue v;
    v.type = AVM_VAL_FUNC;
    v.as.fn = fn;
    return v;
}
