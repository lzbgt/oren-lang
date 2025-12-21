#include "avm_internal.h"

#include <stdlib.h>
#include <string.h>

// --- Deterministic integer semantics (AVM v1 direction) ---
//
// C signed overflow is undefined behavior, which is unacceptable for AVM determinism.
// Define all int arithmetic in terms of 64-bit two's-complement wraparound.
//
// We do this by operating on *bit patterns* as uint64 and bit-casting back to int64.
// (Casting uint64->int64 when out-of-range is implementation-defined; memcpy is not.)
static inline uint64_t avm_u64_bits_i64(int64_t x) {
    uint64_t u = 0;
    memcpy(&u, &x, sizeof(u));
    return u;
}

static inline int64_t avm_i64_from_u64_bits(uint64_t u) {
    int64_t x = 0;
    memcpy(&x, &u, sizeof(x));
    return x;
}

static inline int64_t avm_i64_add_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) + avm_u64_bits_i64(b));
}

static inline int64_t avm_i64_sub_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) - avm_u64_bits_i64(b));
}

static inline int64_t avm_i64_mul_wrap(int64_t a, int64_t b) {
    return avm_i64_from_u64_bits(avm_u64_bits_i64(a) * avm_u64_bits_i64(b));
}

static inline int avm_i64_is_min(int64_t x) {
    // Compile-time-safe i64 min without relying on implementation-defined casts.
    // -(2^63) == (-9223372036854775807 - 1)
    return x == ((int64_t)-9223372036854775807LL - 1LL);
}

// --- Cooperative Tasks (rolling, AVM v1 direction) ---
//
// This implements a minimal, VM-internal cooperative concurrency model to support:
// - Oren `spawn f(...)` / `oren_join(handle)` in the bytecode backend
// - VM-internal channels: `oren_new_channel`, `oren_chan_send`, `oren_chan_recv`
// - `oren_select_recv([ch1, ch2, ...])`
//
// Design constraints:
// - single-threaded, deterministic, no host syscalls
// - shared heap + globals between tasks (like greenlets within one VM)
// - blocking ops (`join`, `chan_recv`, `select_recv`) yield to other runnable tasks
//
// This is intentionally minimal and rolling: it is a foundation for later AVM v1
// scheduling rules (gas/time slicing, deterministic select fairness, etc.).

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
};

static void avm_sched_free(AvmVM* vm);

static AvmSched* avm_sched_get(AvmVM* vm) {
    return vm ? (AvmSched*)vm->sched : NULL;
}

int avm_sched_is_trivial(AvmVM* vm) {
    AvmSched* s = avm_sched_get(vm);
    if (!s) return 1;

    // If any channels exist, snapshot must capture channel queues + waiter lists; not supported yet.
    if (s->chan_count != 0) return 0;

    // If any ready/select queues exist, snapshot would need to capture scheduler queues; not supported yet.
    if (s->ready_len != 0) return 0;
    if (s->select_len != 0) return 0;

    // Only task 0 is allowed to exist.
    if (s->task_count > 1) return 0;

    // Even if task_count==1, ensure no extra used tasks exist in expanded arrays.
    for (int i = 1; i < s->task_cap; i++) {
        if (s->tasks && s->tasks[i].used) return 0;
    }

    // Main task must not be blocked on scheduler primitives.
    if (s->tasks && s->tasks[0].blocked) return 0;
    if (s->tasks && s->tasks[0].wait_kind != 0) return 0;

    return 1;
}

static int sched_ready_push(AvmSched* s, int tid) {
    if (!s) return 0;
    if (tid < 0) return 0;
    if (s->ready_len + 1 > s->ready_cap) {
        int new_cap = s->ready_cap ? s->ready_cap * 2 : 16;
        int* n = (int*)realloc(s->ready, sizeof(int) * (size_t)new_cap);
        if (!n) return 0;
        s->ready = n;
        s->ready_cap = new_cap;
    }
    s->ready[s->ready_len++] = tid;
    return 1;
}

static int sched_ready_pop(AvmSched* s, int* out_tid) {
    if (!s || s->ready_len <= 0) return 0;
    int tid = s->ready[0];
    for (int i = 1; i < s->ready_len; i++) s->ready[i - 1] = s->ready[i];
    s->ready_len--;
    if (out_tid) *out_tid = tid;
    return 1;
}

static int sched_select_waiter_add(AvmSched* s, int tid) {
    if (!s) return 0;
    if (s->select_len + 1 > s->select_cap) {
        int new_cap = s->select_cap ? s->select_cap * 2 : 16;
        int* n = (int*)realloc(s->select_waiters, sizeof(int) * (size_t)new_cap);
        if (!n) return 0;
        s->select_waiters = n;
        s->select_cap = new_cap;
    }
    s->select_waiters[s->select_len++] = tid;
    return 1;
}

static void task_save_from_vm(AvmVM* vm, AvmTask* t) {
    if (!vm || !t) return;
    t->pc = vm->pc;
    t->sp = vm->sp;
    t->fp = vm->fp;
    t->frame_count = vm->frame_count;
    t->env = vm->env;
    if (t->frames) memcpy(t->frames, vm->frames, sizeof(AvmFrame) * (size_t)MAX_FRAMES);
}

static void task_load_into_vm(AvmVM* vm, AvmTask* t) {
    if (!vm || !t) return;
    vm->stack = t->stack;
    vm->pc = t->pc;
    vm->sp = t->sp;
    vm->fp = t->fp;
    vm->frame_count = t->frame_count;
    vm->env = t->env;
    if (t->frames) memcpy(vm->frames, t->frames, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

    if (t->wake_pending) {
        if (vm->sp < (int)AVM_STACK_SIZE) {
            vm->stack[vm->sp++] = t->wake_value;
        } else {
            avm_abort(vm, avm_err(AVM_ERR_BUDGET, "stack overflow on task wake"));
        }
        t->wake_pending = 0;
        t->wake_value = avm_nil();
    }
}

static AvmValue make_pair_list(AvmVM* vm, AvmValue a, AvmValue b) {
    AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
    if (!list) return avm_alloc_fail_value();
    list->count = 2;
    list->capacity = 2;
    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 2u, AVM_ALLOC_KIND_LIST);
    if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
    list->items[0] = a;
    list->items[1] = b;
    AvmValue v; v.type = AVM_VAL_LIST; v.as.l = list;
    return v;
}

static uint64_t avm_vm_now_ns(AvmVM* vm) {
    if (!vm) return 0;
    if (vm->deterministic) {
        // Deterministic monotonic clock derived from semantic work and explicit sleep.
        return vm->virtual_now_ns + vm->virtual_sleep_ns + vm->gas_executed * vm->virtual_step_ns;
    }
    return avm_now_ns();
}

static void sched_switch(AvmVM* vm, AvmSched* s, int next_tid) {
    if (!vm || !s) return;
    int cur = s->current_tid;
    if (cur >= 0 && cur < s->task_cap && s->tasks[cur].used) {
        task_save_from_vm(vm, &s->tasks[cur]);
    }
    s->current_tid = next_tid;
    if (next_tid >= 0 && next_tid < s->task_cap && s->tasks[next_tid].used) {
        task_load_into_vm(vm, &s->tasks[next_tid]);
    }
}

static AvmSched* avm_sched_ensure(AvmVM* vm) {
    if (!vm) return NULL;
    AvmSched* s = (AvmSched*)vm->sched;
    if (s && s->init) return s;

    s = (AvmSched*)calloc(1, sizeof(AvmSched));
    if (!s) return NULL;
    s->init = 1;
    s->current_tid = 0;
    s->quantum_steps = (vm && vm->task_quantum_steps > 0) ? (int)vm->task_quantum_steps : 1000;
    s->task_cap = 8;
    s->tasks = (AvmTask*)calloc((size_t)s->task_cap, sizeof(AvmTask));
    if (!s->tasks) { free(s); return NULL; }
    s->ready = NULL;
    s->ready_len = 0;
    s->ready_cap = 0;
    s->select_waiters = NULL;
    s->select_len = 0;
    s->select_cap = 0;
    s->chan_cap = 8;
    s->chans = (AvmChan*)calloc((size_t)s->chan_cap, sizeof(AvmChan));
    if (!s->chans) { free(s->tasks); free(s); return NULL; }
    s->next_chan_id = 1;

    // Main task (tid 0) uses the VM's original stack allocation.
    s->tasks[0].used = 1;
    s->tasks[0].done = 0;
    s->tasks[0].blocked = 0;
    s->tasks[0].stack = vm->stack_base;
    s->tasks[0].slice_remaining = s->quantum_steps;
    s->tasks[0].select_cursor = 0;
    s->tasks[0].frames = (AvmFrame*)malloc(sizeof(AvmFrame) * (size_t)MAX_FRAMES);
    if (!s->tasks[0].frames) {
        free(s->chans);
        free(s->tasks);
        free(s);
        return NULL;
    }
    memset(s->tasks[0].frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);
    s->task_count = 1;

    vm->sched = s;
    return s;
}

static int sched_new_task(AvmVM* vm, AvmSched* s, AvmValue fn, AvmValue args_list) {
    if (!vm || !s) return -1;
    if (fn.type != AVM_VAL_FUNC || !fn.as.fn) return -1;
    if (args_list.type != AVM_VAL_LIST || !args_list.as.l) return -1;

    // Find a free tid slot.
    int tid = -1;
    for (int i = 0; i < s->task_cap; i++) {
        if (!s->tasks[i].used) { tid = i; break; }
    }
    if (tid < 0) {
        int new_cap = s->task_cap * 2;
        AvmTask* nt = (AvmTask*)realloc(s->tasks, sizeof(AvmTask) * (size_t)new_cap);
        if (!nt) return -1;
        memset(nt + s->task_cap, 0, sizeof(AvmTask) * (size_t)(new_cap - s->task_cap));
        s->tasks = nt;
        tid = s->task_cap;
        s->task_cap = new_cap;
    }

    AvmTask* t = &s->tasks[tid];
    memset(t, 0, sizeof(*t));
    t->used = 1;
    t->done = 0;
    t->blocked = 0;
    t->wait_kind = 0;
    t->wake_pending = 0;
    t->wake_value = avm_nil();
    t->slice_remaining = s->quantum_steps;
    t->select_cursor = 0;

    t->stack = (AvmValue*)malloc(sizeof(AvmValue) * (size_t)AVM_STACK_SIZE);
    if (!t->stack) { memset(t, 0, sizeof(*t)); return -1; }
    t->frames = (AvmFrame*)malloc(sizeof(AvmFrame) * (size_t)MAX_FRAMES);
    if (!t->frames) { free(t->stack); memset(t, 0, sizeof(*t)); return -1; }
    memset(t->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

    AvmList* al = args_list.as.l;
    if (al->count < 0 || al->count > (int)AVM_STACK_SIZE) {
        free(t->frames);
        free(t->stack);
        memset(t, 0, sizeof(*t));
        return -1;
    }
    // Seed initial arg stack (callee expects args at fp=0).
    for (int i = 0; i < al->count; i++) {
        t->stack[i] = al->items[i];
    }
    t->sp = al->count;
    t->fp = 0;
    t->frame_count = 0;
    t->pc = (int)fn.as.fn->addr;
    t->env = fn.as.fn->env;

    if (tid >= s->task_count) s->task_count = tid + 1;
    (void)sched_ready_push(s, tid);
    return tid;
}

static AvmChan* sched_chan_get(AvmSched* s, int64_t hid) {
    if (!s) return NULL;
    if (hid <= 0) return NULL;
    for (int i = 0; i < s->chan_cap; i++) {
        if (s->chans[i].used && s->chans[i].id == hid) return &s->chans[i];
    }
    return NULL;
}

static int sched_chan_new(AvmSched* s) {
    if (!s) return 0;
    int idx = -1;
    for (int i = 0; i < s->chan_cap; i++) {
        if (!s->chans[i].used) { idx = i; break; }
    }
    if (idx < 0) {
        int new_cap = s->chan_cap * 2;
        AvmChan* nc = (AvmChan*)realloc(s->chans, sizeof(AvmChan) * (size_t)new_cap);
        if (!nc) return 0;
        memset(nc + s->chan_cap, 0, sizeof(AvmChan) * (size_t)(new_cap - s->chan_cap));
        s->chans = nc;
        idx = s->chan_cap;
        s->chan_cap = new_cap;
    }
    AvmChan* ch = &s->chans[idx];
    memset(ch, 0, sizeof(*ch));
    ch->used = 1;
    ch->id = s->next_chan_id++;
    ch->recv_waiters = NULL;
    ch->recv_count = 0;
    ch->recv_cap = 0;
    ch->q = NULL;
    ch->q_len = 0;
    ch->q_cap = 0;
    if (idx >= s->chan_count) s->chan_count = idx + 1;
    return (int)ch->id;
}

static int chan_recv_waiter_push(AvmChan* ch, int tid) {
    if (!ch) return 0;
    if (ch->recv_count + 1 > ch->recv_cap) {
        int new_cap = ch->recv_cap ? ch->recv_cap * 2 : 8;
        int* nw = (int*)realloc(ch->recv_waiters, sizeof(int) * (size_t)new_cap);
        if (!nw) return 0;
        ch->recv_waiters = nw;
        ch->recv_cap = new_cap;
    }
    ch->recv_waiters[ch->recv_count++] = tid;
    return 1;
}

static int chan_recv_waiter_pop(AvmChan* ch, int* out_tid) {
    if (!ch || ch->recv_count <= 0) return 0;
    int tid = ch->recv_waiters[0];
    for (int i = 1; i < ch->recv_count; i++) ch->recv_waiters[i - 1] = ch->recv_waiters[i];
    ch->recv_count--;
    if (out_tid) *out_tid = tid;
    return 1;
}

static int chan_queue_push(AvmChan* ch, AvmValue v) {
    if (!ch) return 0;
    // Best-effort runaway guard (rolling): avoid unbounded queue growth.
    if (ch->q_len > 4096) return 0;
    if (ch->q_len + 1 > ch->q_cap) {
        int new_cap = ch->q_cap ? ch->q_cap * 2 : 8;
        AvmValue* nq = (AvmValue*)realloc(ch->q, sizeof(AvmValue) * (size_t)new_cap);
        if (!nq) return 0;
        ch->q = nq;
        ch->q_cap = new_cap;
    }
    ch->q[ch->q_len++] = v;
    return 1;
}

static int chan_can_send(AvmChan* ch) {
    if (!ch) return 0;
    // Ready if there is a receiver waiting (rendezvous) or if we can enqueue without exceeding the runaway guard.
    if (ch->recv_count > 0) return 1;
    if (ch->q_len >= 4096) return 0;
    return 1;
}

static int chan_send_value(AvmSched* s, AvmChan* ch, AvmValue v) {
    if (!s || !ch) return 0;
    int recv_tid = -1;
    if (chan_recv_waiter_pop(ch, &recv_tid)) {
        if (recv_tid >= 0 && recv_tid < s->task_cap && s->tasks[recv_tid].used) {
            AvmTask* rt = &s->tasks[recv_tid];
            rt->blocked = 0;
            rt->wait_kind = 0;
            rt->wake_pending = 1;
            rt->wake_value = v;
            (void)sched_ready_push(s, recv_tid);
            return 1;
        }
    }
    return chan_queue_push(ch, v);
}

static int chan_queue_pop(AvmChan* ch, AvmValue* out) {
    if (!ch || ch->q_len <= 0) return 0;
    AvmValue v = ch->q[0];
    for (int i = 1; i < ch->q_len; i++) ch->q[i - 1] = ch->q[i];
    ch->q_len--;
    if (out) *out = v;
    return 1;
}

static int select_case_parse(AvmValue casev, int* out_kind, int64_t* out_ch, AvmValue* out_send_val) {
    // Rolling encoding for select cases (as data):
    // - recv case: [0, ch]
    // - send case: [1, ch, val]
    //
    // Back-compat: if casev is INT, treat as recv channel handle.
    if (out_kind) *out_kind = -1;
    if (out_ch) *out_ch = 0;
    if (out_send_val) *out_send_val = avm_nil();

    if (casev.type == AVM_VAL_INT) {
        if (out_kind) *out_kind = 0;
        if (out_ch) *out_ch = casev.as.i;
        return 1;
    }
    if (casev.type != AVM_VAL_LIST || !casev.as.l) return 0;
    AvmList* l = casev.as.l;
    if (l->count < 2) return 0;
    AvmValue k = l->items[0];
    AvmValue ch = l->items[1];
    if (k.type != AVM_VAL_INT || ch.type != AVM_VAL_INT) return 0;
    int kind = (int)k.as.i;
    if (kind == 0) {
        if (l->count != 2) return 0;
        if (out_kind) *out_kind = 0;
        if (out_ch) *out_ch = ch.as.i;
        return 1;
    }
    if (kind == 1) {
        if (l->count != 3) return 0;
        if (out_kind) *out_kind = 1;
        if (out_ch) *out_ch = ch.as.i;
        if (out_send_val) *out_send_val = l->items[2];
        return 1;
    }
    return 0;
}

static void sched_try_wake_select_waiters(AvmVM* vm, AvmSched* s) {
    if (!vm || !s || s->select_len <= 0) return;

    int i = 0;
    while (i < s->select_len) {
        int tid = s->select_waiters[i];
        if (tid < 0 || tid >= s->task_cap || !s->tasks[tid].used) {
            // Drop invalid waiter.
            for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
            s->select_len--;
            continue;
        }
        AvmTask* t = &s->tasks[tid];
        if (!t->blocked || t->wait_kind != 3 || t->wait_list.type != AVM_VAL_LIST || !t->wait_list.as.l) {
            for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
            s->select_len--;
            continue;
        }

        AvmList* lst = t->wait_list.as.l;
        int woke = 0;
        int cnt = lst->count;
        if (cnt <= 0) cnt = 0;
        int start = 0;
        if (cnt > 0) {
            start = t->select_cursor % cnt;
            if (start < 0) start = 0;
        }
        for (int off = 0; off < cnt; off++) {
            int k = (start + off) % cnt;
            int kind = -1;
            int64_t chid = 0;
            AvmValue sendv = avm_nil();
            if (!select_case_parse(lst->items[k], &kind, &chid, &sendv)) continue;
            AvmChan* ch = sched_chan_get(s, chid);
            if (!ch) continue;

            if (kind == 0) { // recv
                AvmValue msg;
                if (chan_queue_pop(ch, &msg)) {
                    AvmValue pair = make_pair_list(vm, avm_int((int64_t)k), msg);
                    if (avm_is_err_val(pair)) { avm_abort(vm, pair); return; }
                    t->blocked = 0;
                    t->wait_kind = 0;
                    t->wait_list = avm_nil();
                    t->wake_pending = 1;
                    t->wake_value = pair;
                    if (cnt > 0) t->select_cursor = (k + 1) % cnt;
                    (void)sched_ready_push(s, tid);
                    // Remove from select_waiters.
                    for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
                    s->select_len--;
                    woke = 1;
                    break;
                }
            } else if (kind == 1) { // send
                if (!chan_can_send(ch)) continue;
                if (!chan_send_value(s, ch, sendv)) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "channel queue overflow"));
                    return;
                }
                // payload: ok=1 (rolling)
                AvmValue pair = make_pair_list(vm, avm_int((int64_t)k), avm_int(1));
                if (avm_is_err_val(pair)) { avm_abort(vm, pair); return; }
                t->blocked = 0;
                t->wait_kind = 0;
                t->wait_list = avm_nil();
                t->wake_pending = 1;
                t->wake_value = pair;
                if (cnt > 0) t->select_cursor = (k + 1) % cnt;
                (void)sched_ready_push(s, tid);
                for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
                s->select_len--;
                woke = 1;
                break;
            }
        }
        if (!woke) {
            i++;
        }
    }
}

const char* avm_op_name(uint8_t op) {
    switch (op) {
        case 0x00: return "NOP";
        case 0x01: return "HALT";
        case 0x02: return "PUSH_CONST";
        case 0x03: return "POP";
        case 0x04: return "LOAD_LOCAL";
        case 0x05: return "STORE_LOCAL";
        case 0x06: return "LOAD_GLOBAL";
        case 0x07: return "STORE_GLOBAL";
        case 0x10: return "ADD";
        case 0x11: return "SUB";
        case 0x1D: return "MUL";
        case 0x1E: return "DIV";
        case 0x1F: return "MOD";
        case 0x12: return "LT";
        case 0x13: return "EQ";
        case 0x14: return "NEQ";
        case 0x15: return "GT";
        case 0x16: return "LE";
        case 0x17: return "GE";
        case 0x18: return "AND";
        case 0x19: return "OR";
        case 0x1A: return "XOR";
        case 0x1B: return "SHL";
        case 0x1C: return "SHR";
        case 0x20: return "PRINT";
        case 0x21: return "PRINT_LIST";
        case 0x30: return "JMP";
        case 0x31: return "JMP_IF";
        case 0x38: return "CALL";
        case 0x39: return "RET";
        case 0x3A: return "CALL_NATIVE";
        case 0x3B: return "CALL_NATIVE2";
        case 0x3C: return "PUSH_FUNC";
        case 0x3D: return "CALL_INDIRECT";
        case 0x3E: return "MAKE_CLOSURE";
        case 0x3F: return "LOAD_ENV";
        case 0x40: return "NEW_LIST";
        case 0x41: return "NEW_MAP";
        case 0x42: return "GET_INDEX";
        case 0x43: return "SET_INDEX";
        case 0x44: return "CALL_INDIRECT_SPREAD";
        case 0x45: return "SPAWN_CALL_LIST";
        case 0x46: return "JOIN";
        case 0x47: return "CHAN_NEW";
        case 0x48: return "CHAN_SEND";
        case 0x49: return "CHAN_RECV";
        case 0x4A: return "SELECT_RECV";
        case 0x4B: return "YIELD";
        case 0x4C: return "JOIN_TIMEOUT";
        case 0x4D: return "SELECT";
        default: return "OP?";
    }
}

static void avm_print_value_no_nl(AvmValue v) {
    if (v.type == AVM_VAL_INT) printf("%lld", (long long)v.as.i);
    else if (v.type == AVM_VAL_FLOAT) printf("%f", v.as.f);
    else if (v.type == AVM_VAL_STRING) printf("%s", (char*)v.as.p);
    else if (v.type == AVM_VAL_BOOL) printf("%s", v.as.i ? "true" : "false");
    else if (v.type == AVM_VAL_NIL) printf("nil");
    else if (v.type == AVM_VAL_LIST) printf("<list>");
    else if (v.type == AVM_VAL_MAP) printf("<map>");
    else if (v.type == AVM_VAL_FUNC) printf("<func>");
    else if (v.type == AVM_VAL_I32_BUF) printf("<i32_buf>");
    else if (v.type == AVM_VAL_I64_BUF) printf("<i64_buf>");
    else if (v.type == AVM_VAL_F32_BUF) printf("<f32_buf>");
    else if (v.type == AVM_VAL_F64_BUF) printf("<f64_buf>");
    else printf("<?>");
}

uint32_t avm_gas_cost(uint8_t op) {
    (void)op;
    // Bootstrap rule: every opcode costs 1 gas.
    return 1u;
}

void avm_abort(AvmVM* vm, AvmValue err) {
    vm->last_error = err;
    vm->exit_code = 1;
    vm->running = 0;
}

AvmVM* avm_new() {
    AvmVM* vm = (AvmVM*)malloc(sizeof(AvmVM));
    vm->stack_base = (AvmValue*)malloc(sizeof(AvmValue) * AVM_STACK_SIZE);
    vm->stack = vm->stack_base;
    vm->sp = 0;
    vm->pc = 0;
    vm->running = 0;
    vm->prog = NULL;
    vm->fp = 0;
    vm->env = avm_nil();
    vm->frame_count = 0;
    vm->frame_limit = MAX_FRAMES;
    vm->allowed_native_domains = 0;
    vm->fs_allow_prefixes = NULL;
    vm->fs_allow_prefix_count = 0;
    vm->fs_mounts_read_virt = NULL;
    vm->fs_mounts_read_host = NULL;
    vm->fs_mounts_read_count = 0;
    vm->fs_mounts_write_virt = NULL;
    vm->fs_mounts_write_host = NULL;
    vm->fs_mounts_write_count = 0;
    vm->fs_backend_kind = 0;
    vm->vfs = NULL;
    vm->proc_backend_kind = 0;
    vm->vproc = NULL;
    vm->proc_exit_code = 0;
    vm->net_backend_kind = 0;
    vm->vnet = NULL;
    vm->gas_remaining = 0;
    vm->deadline_ns = 0;
    vm->cancelled = 0;
    vm->heap_budget_bytes = 0;
    vm->heap_used_bytes = 0;
    vm->heap_allocs_head = NULL;
    vm->io_budget_bytes = 0;
    vm->io_used_bytes = 0;
    vm->log_budget_bytes = 0;
    vm->log_used_bytes = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->exit_code = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    vm->record_log = NULL;
    vm->replay_log = NULL;
    vm->record_log_bytes = NULL;
    vm->replay_log_bytes = NULL;
    vm->replay_log_pos = 0;
    vm->deterministic = 0;
    vm->virtual_now_ns = 0;
    vm->virtual_step_ns = 1000ull; // 1us per executed instruction step (default; override with AVM_TIME_STEP_NS)
    vm->virtual_sleep_ns = 0;
    vm->rng_state = 0x123456789abcdef0ull;
    vm->gas_executed = 0;
    vm->task_quantum_steps = 1000;
    vm->alloc_next_id = 1;
    vm->pause_after_steps = 0;
    vm->paused = 0;
    vm->trace_enabled = 0;
    vm->trace_limit = 0;
    vm->trace_out = NULL;
    vm->trace_hash_enabled = 0;
    vm->trace_hash_limit = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_bytes_enabled = 0;
    vm->trace_bytes_limit = 0;
    vm->trace_budget_bytes = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
    vm->break_pcs = NULL;
    vm->break_pc_count = 0;
    vm->sched = NULL;
    for (int i = 0; i < MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (!vm) return;

    // Close any open replay/record files (CLI can also close; best-effort here).
    if (vm->record_log) fclose(vm->record_log);
    if (vm->replay_log) fclose(vm->replay_log);

    // Best-effort: release heap objects reachable from VM roots (including const pool objects).
    avm_release_heap_all(vm);
    // Release any remaining unreachable heap allocations (leak-free teardown).
    avm_release_unreachable_allocs(vm);

    // Leak guard (must never fire): after teardown, no heap allocations should remain.
    // This is failure-only (no output on success) and intentionally fatal so leak
    // regressions cannot slip by silently during rolling development.
    if (vm->heap_allocs_head != NULL || vm->heap_used_bytes != 0) {
        fprintf(stderr, "AVM LEAK: heap_allocs_head=%p heap_used_bytes=%llu\n",
            vm->heap_allocs_head, (unsigned long long)vm->heap_used_bytes);
        abort();
    }

    // Tear down cooperative scheduler (tasks/channels) if it was initialized.
    // (Owned by this module; does not participate in the heap budget accounting.)
    if (vm->sched) avm_sched_free(vm);

    if (vm->stack_base) free(vm->stack_base);
    if (vm->break_pcs) free(vm->break_pcs);
    if (vm->fs_allow_prefixes) {
        for (int i = 0; i < vm->fs_allow_prefix_count; i++) {
            if (vm->fs_allow_prefixes[i]) free(vm->fs_allow_prefixes[i]);
        }
        free(vm->fs_allow_prefixes);
    }
    if (vm->fs_mounts_read_virt || vm->fs_mounts_read_host) {
        for (int i = 0; i < vm->fs_mounts_read_count; i++) {
            if (vm->fs_mounts_read_virt && vm->fs_mounts_read_virt[i]) free(vm->fs_mounts_read_virt[i]);
            if (vm->fs_mounts_read_host && vm->fs_mounts_read_host[i]) free(vm->fs_mounts_read_host[i]);
        }
        if (vm->fs_mounts_read_virt) free(vm->fs_mounts_read_virt);
        if (vm->fs_mounts_read_host) free(vm->fs_mounts_read_host);
    }
    if (vm->fs_mounts_write_virt || vm->fs_mounts_write_host) {
        for (int i = 0; i < vm->fs_mounts_write_count; i++) {
            if (vm->fs_mounts_write_virt && vm->fs_mounts_write_virt[i]) free(vm->fs_mounts_write_virt[i]);
            if (vm->fs_mounts_write_host && vm->fs_mounts_write_host[i]) free(vm->fs_mounts_write_host[i]);
        }
        if (vm->fs_mounts_write_virt) free(vm->fs_mounts_write_virt);
        if (vm->fs_mounts_write_host) free(vm->fs_mounts_write_host);
    }
    free(vm);
}

void avm_load(AvmVM* vm, AvmProgram* prog) {
    vm->prog = prog;
    vm->pc = 0;
    vm->sp = 0;
    vm->fp = 0;
    vm->env = avm_nil();
    vm->frame_count = 0;
    vm->stack = vm->stack_base;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value = avm_nil();
    vm->last_error = avm_nil();
    vm->exit_code = 0;
    vm->virtual_sleep_ns = 0;
    vm->gas_executed = 0;
    vm->trace_hash_started = 0;
    vm->trace_hash_finalized = 0;
    vm->trace_used_bytes = 0;
    vm->trace_bytes = NULL;
    vm->trace_bytes_truncated = 0;
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

void avm_run(AvmVM* vm) {
    if (!vm || !vm->prog) return;

    AvmVM* prev_owner = NULL;
    avm_alloc_owner_push(vm, &prev_owner);

    AvmSched* sched = avm_sched_ensure(vm);
    if (!sched) {
        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "out of memory (scheduler init)"));
        avm_alloc_owner_pop(prev_owner);
        return;
    }
    sched->current_tid = 0;
    // Ensure the main task state is in sync before any potential yields/switches.
    task_save_from_vm(vm, &sched->tasks[0]);

    vm->running = 1;
    vm->exit_code = 0;
    vm->last_error.type = AVM_VAL_NIL;
    vm->paused = 0;
    vm->has_result_value = 0;
    vm->result_value.type = AVM_VAL_NIL;
    uint8_t* code = vm->prog->code;
    uint64_t steps = 0;

    while (vm->running && vm->pc < vm->prog->code_len) {
        steps++;
        if (vm->break_pc_count > 0 && vm->break_pcs) {
            for (int bi = 0; bi < vm->break_pc_count; bi++) {
                if (vm->pc == vm->break_pcs[bi]) {
                    vm->paused = 1;
                    vm->exit_code = 2; // paused (non-error)
                    vm->running = 0;
                    break;
                }
            }
            if (!vm->running) break;
        }
        if (vm->pause_after_steps > 0) {
            vm->pause_after_steps--;
            if (vm->pause_after_steps == 0) {
                vm->paused = 1;
                vm->exit_code = 2; // paused (non-error)
                vm->running = 0;
                break;
            }
        }
        if (vm->cancelled) {
            avm_abort(vm, avm_err(AVM_ERR_CANCELLED, "cancelled"));
            break;
        }
        if (vm->deadline_ns > 0 && ((steps & 1023ull) == 0)) {
            uint64_t now = avm_now_ns();
            if (now != 0 && now > vm->deadline_ns) {
                avm_abort(vm, avm_err(AVM_ERR_TIMEOUT, "deadline exceeded"));
                break;
            }
        }

        int op_pc = vm->pc;
        uint8_t op = code[vm->pc];
        uint32_t cost = avm_gas_cost(op);
        if (cost == 0) cost = 1u;

        // Charge gas budget using the semantic cost model.
        if (vm->gas_remaining > 0) {
            if (vm->gas_remaining < (uint64_t)cost) {
                avm_abort(vm, avm_err(AVM_ERR_BUDGET, "budget exceeded (gas)"));
                break;
            }
            vm->gas_remaining -= (uint64_t)cost;
            if (vm->gas_remaining == 0) {
                avm_abort(vm, avm_err(AVM_ERR_BUDGET, "budget exceeded (gas)"));
                break;
            }
        }

        // Semantic execution counter for deterministic TIME (bootstrap: 1 gas per opcode dispatch).
        vm->gas_executed += (uint64_t)cost;
        vm->pc++;

        // Tracing is best-effort and must never affect program semantics.
        (void)trace_emit_step(vm, op_pc, op);
        if (vm->trace_enabled && (!vm->trace_limit || vm->gas_executed <= vm->trace_limit)) {
            FILE* out = vm->trace_out ? vm->trace_out : stderr;
            fprintf(out, "TRACE pc=%d op=0x%02x %s sp=%d fp=%d depth=%d gas=%llu\n",
                op_pc,
                (unsigned)op,
                avm_op_name(op),
                vm->sp,
                vm->fp,
                vm->frame_count,
                (unsigned long long)vm->gas_executed);
        }

        switch (op) {
            case 0x00: // NOP
                break;
            case 0x01: // HALT
                // HALT ends the current task. Task 0 halts the VM; other tasks complete normally.
                if (sched && sched->current_tid != 0) {
                    int tid = sched->current_tid;
                    AvmTask* t = &sched->tasks[tid];
                    t->done = 1;
                    t->blocked = 0;
                    t->wait_kind = 0;
                    t->has_ret = 1;
                    t->ret = (vm->sp > 0) ? vm->stack[vm->sp - 1] : avm_nil();
                    task_save_from_vm(vm, t);

                    // Wake join waiters (simple scan; rolling).
                    for (int wi = 0; wi < sched->task_cap; wi++) {
                        AvmTask* w = &sched->tasks[wi];
                        if (!w->used || !w->blocked) continue;
                        if ((w->wait_kind == 1 || w->wait_kind == 4) && w->wait_id == tid) {
                            w->blocked = 0;
                            w->wait_kind = 0;
                            w->join_deadline_ns = 0;
                            w->wake_pending = 1;
                            w->wake_value = t->ret;
                            (void)sched_ready_push(sched, wi);
                        }
                    }

                    // Switch to next runnable task.
                    int next = -1;
                    if (sched_ready_pop(sched, &next)) {
                        sched_switch(vm, sched, next);
                        continue;
                    }
                    // No runnable tasks: if main task is still running, resume it; else stop.
                    sched_switch(vm, sched, 0);
                    continue;
                }
                vm->running = 0;
                break;
            case 0x02: { // PUSH_CONST u16
                if (vm->pc + 2 > vm->prog->code_len) { vm->running = 0; break; }
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < vm->prog->const_count) {
                    vm->stack[vm->sp++] = vm->prog->constants[idx];
                }
                break;
            }
            case 0x03: // POP
                if (vm->sp > 0) vm->sp--;
                break;
            case 0x04: { // LOAD_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->sp++] = vm->stack[vm->fp + idx];
                break;
            }
            case 0x05: { // STORE_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->fp + idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x06: { // LOAD_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->stack[vm->sp++] = vm->globals[idx];
                break;
            }
            case 0x07: { // STORE_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->globals[idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x10: { // ADD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_add_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i + b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f + (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) {
                        const char* sa = a.as.p ? (const char*)a.as.p : "";
                        const char* sb = b.as.p ? (const char*)b.as.p : "";
                        size_t la = strlen(sa);
                        size_t lb = strlen(sb);
                        char* s = (char*)avm_heap_malloc_k(la + lb + 1, AVM_ALLOC_KIND_STRING);
                        if (!s) { AvmValue e = avm_alloc_fail_value(); avm_abort(vm, e); vm->stack[vm->sp++] = e; break; }
                        memcpy(s, sa, la);
                        memcpy(s + la, sb, lb);
                        s[la + lb] = 0;
                        AvmValue r; r.type = AVM_VAL_STRING; r.as.p = s; vm->stack[vm->sp++] = r;
                    } else {
                        // Rolling behavior: type mismatch yields nil (avoid host crash).
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x11: { // SUB
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_sub_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f - b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i - b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f - (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1D: { // MUL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_int(avm_i64_mul_wrap(a.as.i, b.as.i));
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i * b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f * (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1E: { // DIV
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        if (b.as.i == 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "division by zero"));
                            break;
                        }
                        // INT64_MIN / -1 overflows in two's complement; define as an error.
                        if (avm_i64_is_min(a.as.i) && b.as.i == -1) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "division overflow (i64_min / -1)"));
                            break;
                        }
                        vm->stack[vm->sp++] = avm_int(a.as.i / b.as.i);
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f / b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = (double)a.as.i / b.as.f; vm->stack[vm->sp++] = r;
                    } else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) {
                        AvmValue r; r.type = AVM_VAL_FLOAT; r.as.f = a.as.f / (double)b.as.i; vm->stack[vm->sp++] = r;
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x1F: { // MOD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) {
                        if (b.as.i == 0) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo by zero"));
                            break;
                        }
                        // INT64_MIN % -1 is invalid because it implies INT64_MIN / -1 overflow.
                        if (avm_i64_is_min(a.as.i) && b.as.i == -1) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "modulo overflow (i64_min % -1)"));
                            break;
                        }
                        vm->stack[vm->sp++] = avm_int(a.as.i % b.as.i);
                    } else {
                        vm->stack[vm->sp++] = avm_nil();
                    }
                }
                break;
            }
            case 0x12: { // LT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i < b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f < b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i < b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f < (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) < 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x13: { // EQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    int eq = 0;
                    if (a.type == b.type) {
                        if (a.type == AVM_VAL_NIL) eq = 1;
                        else if (a.type == AVM_VAL_INT || a.type == AVM_VAL_BOOL) eq = (a.as.i == b.as.i);
                        else if (a.type == AVM_VAL_FLOAT) eq = (a.as.f == b.as.f);
                        else if (a.type == AVM_VAL_STRING) eq = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                        else eq = (a.as.p == b.as.p);
                    }
                    vm->stack[vm->sp++] = avm_bool(eq);
                }
                break;
            }
            case 0x14: { // NEQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    int eq = 0;
                    if (a.type == b.type) {
                        if (a.type == AVM_VAL_NIL) eq = 1;
                        else if (a.type == AVM_VAL_INT || a.type == AVM_VAL_BOOL) eq = (a.as.i == b.as.i);
                        else if (a.type == AVM_VAL_FLOAT) eq = (a.as.f == b.as.f);
                        else if (a.type == AVM_VAL_STRING) eq = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                        else eq = (a.as.p == b.as.p);
                    }
                    vm->stack[vm->sp++] = avm_bool(!eq);
                }
                break;
            }
            case 0x15: { // GT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i > b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f > b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i > b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f > (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) > 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x16: { // LE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i <= b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f <= b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i <= b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f <= (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) <= 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x17: { // GE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.i >= b.as.i);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool(a.as.f >= b.as.f);
                    else if (a.type == AVM_VAL_INT && b.type == AVM_VAL_FLOAT) vm->stack[vm->sp++] = avm_bool((double)a.as.i >= b.as.f);
                    else if (a.type == AVM_VAL_FLOAT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_bool(a.as.f >= (double)b.as.i);
                    else if (a.type == AVM_VAL_STRING && b.type == AVM_VAL_STRING) vm->stack[vm->sp++] = avm_bool(strcmp((char*)a.as.p, (char*)b.as.p) >= 0);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x18: { // AND
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i & b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x19: { // OR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i | b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x1A: { // XOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT) vm->stack[vm->sp++] = avm_int(a.as.i ^ b.as.i);
                    else vm->stack[vm->sp++] = avm_nil();
                }
                break;
            }
            case 0x1B: { // SHL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type != AVM_VAL_INT || b.type != AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (b.as.i < 0 || b.as.i >= 64) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SHL shift count out of range (need 0..63)"));
                        break;
                    }
                    uint64_t ua = avm_u64_bits_i64(a.as.i);
                    uint64_t ur = ua << (uint64_t)b.as.i;
                    vm->stack[vm->sp++] = avm_int(avm_i64_from_u64_bits(ur));
                }
                break;
            }
            case 0x1C: { // SHR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    if (a.type != AVM_VAL_INT || b.type != AVM_VAL_INT) {
                        vm->stack[vm->sp++] = avm_nil();
                        break;
                    }
                    if (b.as.i < 0 || b.as.i >= 64) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SHR shift count out of range (need 0..63)"));
                        break;
                    }
                    uint64_t ua = avm_u64_bits_i64(a.as.i);
                    uint64_t ur = ua >> (uint64_t)b.as.i;
                    vm->stack[vm->sp++] = avm_int(avm_i64_from_u64_bits(ur));
                }
                break;
            }
            case 0x20: { // PRINT
                if (vm->sp > 0) {
                    AvmValue v = vm->stack[--vm->sp];
                    avm_print_value_no_nl(v);
                    printf("\n");
                }
                break;
            }
            case 0x21: { // PRINT_LIST
                if (vm->sp <= 0) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on PRINT_LIST"));
                    break;
                }
                AvmValue lst = vm->stack[--vm->sp];
                if (lst.type == AVM_VAL_NIL) {
                    printf("\n");
                    break;
                }
                if (lst.type != AVM_VAL_LIST || !lst.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "PRINT_LIST expects list"));
                    break;
                }
                AvmList* l = lst.as.l;
                for (int i = 0; i < l->count; i++) {
                    avm_print_value_no_nl(l->items[i]);
                    if (i < l->count - 1) printf(" ");
                }
                printf("\n");
                break;
            }
            case 0x30: { // JMP i16
                int16_t off = 0;
                off |= (int16_t)code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                vm->pc = (int)(vm->pc + off);
                break;
            }
            case 0x31: { // JMP_IF i16
                int16_t off = 0;
                off |= (int16_t)code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                AvmValue cond = vm->stack[--vm->sp];
                int truthy = 0;
                if (cond.type == AVM_VAL_BOOL) truthy = cond.as.i != 0;
                else if (cond.type == AVM_VAL_INT) truthy = cond.as.i != 0;
                else if (cond.type == AVM_VAL_NIL) truthy = 0;
                else truthy = 1;
                if (truthy) vm->pc = (int)(vm->pc + off);
                break;
            }
            case 0x38: { // CALL u16 u8
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                uint8_t argc = code[vm->pc++];
                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - argc;
                vm->env = avm_nil();
                vm->pc = addr;
                break;
            }
            case 0x39: { // RET
                // Function return convention (production/rolling):
                // - Callee leaves a single return value on the stack.
                // - RET pops that value, discards the entire callee frame (args+locals+temps),
                //   then pushes the return value for the caller.
                //
                // This matches the verifier model: CALL pops nargs and pushes 1.
                if (vm->sp <= 0) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on RET"));
                    break;
                }
                AvmValue ret = vm->stack[--vm->sp];
                int callee_fp = vm->fp;

                vm->frame_count--;
                if (vm->frame_count < 0) {
                    // Returning from top-level:
                    // - task 0: halt the VM (existing behavior)
                    // - other tasks: mark task done and yield to scheduler
                    if (sched && sched->current_tid != 0) {
                        int tid = sched->current_tid;
                        AvmTask* t = &sched->tasks[tid];
                        t->done = 1;
                        t->blocked = 0;
                        t->wait_kind = 0;
                        t->has_ret = 1;
                        t->ret = ret;
                        // Preserve a minimal stack with the return value.
                        vm->sp = 0;
                        vm->stack[vm->sp++] = ret;
                        task_save_from_vm(vm, t);

                        // Wake join waiters.
                        for (int wi = 0; wi < sched->task_cap; wi++) {
                            AvmTask* w = &sched->tasks[wi];
                            if (!w->used || !w->blocked) continue;
                            if ((w->wait_kind == 1 || w->wait_kind == 4) && w->wait_id == tid) {
                                w->blocked = 0;
                                w->wait_kind = 0;
                                w->join_deadline_ns = 0;
                                w->wake_pending = 1;
                                w->wake_value = ret;
                                (void)sched_ready_push(sched, wi);
                            }
                        }

                        int next = -1;
                        if (sched_ready_pop(sched, &next)) {
                            sched_switch(vm, sched, next);
                            continue;
                        }
                        // No runnable tasks: resume main.
                        sched_switch(vm, sched, 0);
                        continue;
                    }

                    vm->sp = 0;
                    vm->stack[vm->sp++] = ret;
                    vm->running = 0;
                    break;
                }

                // Discard callee frame contents and present return value to caller.
                vm->sp = callee_fp;
                vm->stack[vm->sp++] = ret;

                vm->pc = vm->frames[vm->frame_count].return_pc;
                vm->fp = vm->frames[vm->frame_count].fp;
                vm->env = vm->frames[vm->frame_count].env;
                break;
            }
            case 0x3C: { // PUSH_FUNC u16
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                AvmValue fv = avm_func_new(vm, (uint32_t)addr, avm_nil());
                if (avm_is_err_val(fv)) { avm_abort(vm, fv); break; }
                vm->stack[vm->sp++] = fv;
                break;
            }
            case 0x3D: { // CALL_INDIRECT u8
                uint8_t argc = code[vm->pc++];
                if (vm->sp < (int)argc + 1) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CALL_INDIRECT"));
                    break;
                }
                int fn_idx = vm->sp - (int)argc - 1;
                AvmValue fv = vm->stack[fn_idx];
                if (fv.type != AVM_VAL_FUNC || !fv.as.fn) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT expects function value"));
                    break;
                }
                uint32_t addr = fv.as.fn->addr;
                AvmValue callee_env = fv.as.fn->env;

                // Remove fn value from the stack by shifting args down over it.
                for (int i = fn_idx; i < vm->sp - 1; i++) {
                    vm->stack[i] = vm->stack[i + 1];
                }
                vm->sp -= 1;

                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - (int)argc;
                vm->env = callee_env;
                vm->pc = (int)addr;
                break;
            }
            case 0x44: { // CALL_INDIRECT_SPREAD u8_fixed
                uint8_t fixed = code[vm->pc++];
                if (vm->sp < (int)fixed + 2) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CALL_INDIRECT_SPREAD"));
                    break;
                }
                int fn_idx = vm->sp - (int)fixed - 2;
                AvmValue fv = vm->stack[fn_idx];
                if (fv.type != AVM_VAL_FUNC || !fv.as.fn) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD expects function value"));
                    break;
                }
                AvmValue spread = vm->stack[vm->sp - 1];
                if (spread.type != AVM_VAL_LIST || !spread.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD expects list as spread arg"));
                    break;
                }
                uint32_t addr = fv.as.fn->addr;
                AvmValue callee_env = fv.as.fn->env;

                AvmList* sl = spread.as.l;
                if ((int)fixed + sl->count > 255) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CALL_INDIRECT_SPREAD argc too large"));
                    break;
                }

                // Pop spread list value.
                vm->sp -= 1;

                // Remove fn value by shifting fixed args down over it.
                for (int i = fn_idx; i < vm->sp - 1; i++) {
                    vm->stack[i] = vm->stack[i + 1];
                }
                vm->sp -= 1;

                // Append spread items to stack as additional args.
                if (vm->sp + sl->count > (int)AVM_STACK_SIZE) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "stack overflow on CALL_INDIRECT_SPREAD"));
                    break;
                }
                for (int i = 0; i < sl->count; i++) {
                    vm->stack[vm->sp++] = sl->items[i];
                }

                uint8_t argc = (uint8_t)((int)fixed + sl->count);
                uint32_t fl = vm->frame_limit ? vm->frame_limit : (uint32_t)MAX_FRAMES;
                if (fl > (uint32_t)MAX_FRAMES) fl = (uint32_t)MAX_FRAMES;
                if (vm->frame_count >= (int)fl) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "call stack overflow (depth limit)"));
                    break;
                }
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frames[vm->frame_count].env = vm->env;
                vm->frame_count++;
                vm->fp = vm->sp - (int)argc;
                vm->env = callee_env;
                vm->pc = (int)addr;
                break;
            }
            case AVM_OP_SPAWN_CALL_LIST: { // SPAWN_CALL_LIST
                // stack: [... fn args_list] -> [... handle_int]
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SPAWN_CALL_LIST")); break; }
                AvmValue args_list = vm->stack[--vm->sp];
                AvmValue fnv = vm->stack[--vm->sp];
                int tid = sched_new_task(vm, sched, fnv, args_list);
                if (tid < 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "spawn failed")); break; }
                // Public handle is tid+1 so 0 can represent nil/invalid.
                vm->stack[vm->sp++] = avm_int((int64_t)(tid + 1));
                break;
            }
            case AVM_OP_JOIN: { // JOIN
                // stack: [... handle] -> [... ret] (blocks if not done)
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on JOIN")); break; }
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN expects int handle")); break; }
                int tid = (int)hv.as.i - 1;
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN invalid handle"));
                    break;
                }
                if (tid == sched->current_tid) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN self")); break; }
                AvmTask* tgt = &sched->tasks[tid];
                if (tgt->done) {
                    vm->stack[vm->sp++] = tgt->has_ret ? tgt->ret : avm_nil();
                    break;
                }

                // Block current task until target completes.
                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 1;
                ct->wait_id = tid;
                ct->join_deadline_ns = 0;
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_JOIN_TIMEOUT: { // JOIN_TIMEOUT
                // stack: [... handle timeout_ms] -> [... ret_or_timeout]
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on JOIN_TIMEOUT")); break; }
                AvmValue tv = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT || tv.type != AVM_VAL_INT) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT expects (int handle, int timeout_ms)"));
                    break;
                }
                int tid = (int)hv.as.i - 1;
                int64_t timeout_ms = tv.as.i;
                if (tid < 0 || tid >= sched->task_cap || !sched->tasks[tid].used) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT invalid handle"));
                    break;
                }
                if (tid == sched->current_tid) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "JOIN_TIMEOUT self")); break; }

                AvmTask* tgt = &sched->tasks[tid];
                if (tgt->done) {
                    vm->stack[vm->sp++] = tgt->has_ret ? tgt->ret : avm_nil();
                    break;
                }

                if (timeout_ms < 0) {
                    // Equivalent to JOIN (block).
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 1;
                    ct->wait_id = tid;
                    ct->join_deadline_ns = 0;
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

                if (timeout_ms == 0) {
                    // Fast-path: non-blocking join probe.
                    vm->stack[vm->sp++] = avm_int(-60); // ETIMEDOUT (BSD)
                    break;
                }

                // If there are no runnable tasks besides us, joining can never make progress; treat as timeout.
                if (sched->ready_len <= 0) {
                    vm->stack[vm->sp++] = avm_int(-60); // ETIMEDOUT (BSD)
                    break;
                }

                // Block current task with an absolute deadline in deterministic virtual time.
                uint64_t now = avm_vm_now_ns(vm);
                uint64_t dl = now + (uint64_t)timeout_ms * 1000000ull;

                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 4; // join_timeout
                ct->wait_id = tid;
                ct->join_deadline_ns = dl;
                ct->wake_pending = 0;
                ct->wake_value = avm_nil();
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    // No runnable tasks => immediate timeout (must not hang).
                    ct->blocked = 0;
                    ct->wait_kind = 0;
                    ct->join_deadline_ns = 0;
                    vm->stack[vm->sp++] = avm_int(-60);
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_CHAN_NEW: { // CHAN_NEW
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                int hid = sched_chan_new(sched);
                if (hid <= 0) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "CHAN_NEW failed")); break; }
                vm->stack[vm->sp++] = avm_int((int64_t)hid);
                break;
            }
            case AVM_OP_CHAN_SEND: { // CHAN_SEND
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 2) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CHAN_SEND")); break; }
                AvmValue val = vm->stack[--vm->sp];
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_SEND expects int channel")); break; }
                AvmChan* ch = sched_chan_get(sched, hv.as.i);
                if (!ch) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_SEND invalid channel")); break; }

                if (!chan_send_value(sched, ch, val)) {
                    avm_abort(vm, avm_err(AVM_ERR_BUDGET, "channel queue overflow"));
                    break;
                }

                // A send can make a previously-blocked select waiter runnable.
                sched_try_wake_select_waiters(vm, sched);
                if (vm->last_error.type != AVM_VAL_NIL) break;

                vm->stack[vm->sp++] = avm_int(1);
                break;
            }
            case AVM_OP_CHAN_RECV: { // CHAN_RECV
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on CHAN_RECV")); break; }
                AvmValue hv = vm->stack[--vm->sp];
                if (hv.type != AVM_VAL_INT) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_RECV expects int channel")); break; }
                AvmChan* ch = sched_chan_get(sched, hv.as.i);
                if (!ch) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "CHAN_RECV invalid channel")); break; }

                AvmValue msg;
                if (chan_queue_pop(ch, &msg)) {
                    vm->stack[vm->sp++] = msg;
                    break;
                }

                // Block current task on this channel.
                int cur = sched->current_tid;
                AvmTask* ct = &sched->tasks[cur];
                ct->blocked = 1;
                ct->wait_kind = 2;
                ct->wait_chan = (int)hv.as.i;
                (void)chan_recv_waiter_push(ch, cur);
                task_save_from_vm(vm, ct);

                int next = -1;
                if (!sched_ready_pop(sched, &next)) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                    break;
                }
                sched_switch(vm, sched, next);
                continue;
            }
            case AVM_OP_SELECT_RECV: { // SELECT_RECV
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SELECT_RECV")); break; }
                AvmValue lv = vm->stack[--vm->sp];
                if (lv.type != AVM_VAL_LIST || !lv.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SELECT_RECV expects list")); break; }

                AvmList* lst = lv.as.l;
                int cnt = lst->count;
                int cur = sched->current_tid;
                int start = 0;
                if (cnt > 0) {
                    start = sched->tasks[cur].select_cursor % cnt;
                    if (start < 0) start = 0;
                }
                for (int off = 0; off < cnt; off++) {
                    int i = (start + off) % cnt;
                    AvmValue hv = lst->items[i];
                    if (hv.type != AVM_VAL_INT) continue;
                    AvmChan* ch = sched_chan_get(sched, hv.as.i);
                    if (!ch) continue;
                    AvmValue msg;
                    if (chan_queue_pop(ch, &msg)) {
                        AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), msg);
                        if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                        if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                        vm->stack[vm->sp++] = pair;
                        goto select_done;
                    }
                }

                // Block current task, registering as a select waiter.
                {
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 3;
                    ct->wait_list = lv;
                    (void)sched_select_waiter_add(sched, cur);
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

select_done:
                break;
            }
            case AVM_OP_SELECT: { // SELECT
                if (!sched) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "scheduler missing")); break; }
                if (vm->sp < 1) { avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on SELECT")); break; }
                AvmValue lv = vm->stack[--vm->sp];
                if (lv.type != AVM_VAL_LIST || !lv.as.l) { avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "SELECT expects list")); break; }

                AvmList* lst = lv.as.l;
                int cnt = lst->count;
                int cur = sched->current_tid;
                int start = 0;
                if (cnt > 0) {
                    start = sched->tasks[cur].select_cursor % cnt;
                    if (start < 0) start = 0;
                }
                for (int off = 0; off < cnt; off++) {
                    int i = (start + off) % cnt;
                    int kind = -1;
                    int64_t chid = 0;
                    AvmValue sendv = avm_nil();
                    if (!select_case_parse(lst->items[i], &kind, &chid, &sendv)) continue;
                    AvmChan* ch = sched_chan_get(sched, chid);
                    if (!ch) continue;

                    if (kind == 0) { // recv
                        AvmValue msg;
                        if (chan_queue_pop(ch, &msg)) {
                            AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), msg);
                            if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                            if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                            vm->stack[vm->sp++] = pair;
                            goto select2_done;
                        }
                    } else if (kind == 1) { // send
                        if (!chan_can_send(ch)) continue;
                        if (!chan_send_value(sched, ch, sendv)) { avm_abort(vm, avm_err(AVM_ERR_BUDGET, "channel queue overflow")); break; }
                        AvmValue pair = make_pair_list(vm, avm_int((int64_t)i), avm_int(1));
                        if (avm_is_err_val(pair)) { avm_abort(vm, pair); break; }
                        if (cnt > 0) sched->tasks[cur].select_cursor = (i + 1) % cnt;
                        vm->stack[vm->sp++] = pair;
                        goto select2_done;
                    }
                }

                // Block current task, registering as a select waiter.
                {
                    int cur = sched->current_tid;
                    AvmTask* ct = &sched->tasks[cur];
                    ct->blocked = 1;
                    ct->wait_kind = 3;
                    ct->wait_list = lv;
                    (void)sched_select_waiter_add(sched, cur);
                    task_save_from_vm(vm, ct);

                    int next = -1;
                    if (!sched_ready_pop(sched, &next)) {
                        avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "deadlock (no runnable tasks)"));
                        break;
                    }
                    sched_switch(vm, sched, next);
                    continue;
                }

select2_done:
                // Sending via SELECT can also wake other blocked select waiters.
                sched_try_wake_select_waiters(vm, sched);
                break;
            }
            case AVM_OP_YIELD: { // YIELD
                if (!sched) break;
                int cur = sched->current_tid;
                // If no other runnable tasks, yield is a no-op.
                if (sched->ready_len <= 0) break;
                AvmTask* ct = &sched->tasks[cur];
                task_save_from_vm(vm, ct);
                (void)sched_ready_push(sched, cur);
                int next = -1;
                if (sched_ready_pop(sched, &next)) {
                    sched_switch(vm, sched, next);
                    continue;
                }
                break;
            }
            case 0x3E: { // MAKE_CLOSURE u8
                uint8_t ncap = code[vm->pc++];
                if (vm->sp < (int)ncap + 1) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow on MAKE_CLOSURE"));
                    break;
                }
                AvmValue base = vm->stack[vm->sp - 1];
                if (base.type != AVM_VAL_FUNC || !base.as.fn) {
                    avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "MAKE_CLOSURE expects function value"));
                    break;
                }

                AvmList* env_list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!env_list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                env_list->count = (int)ncap;
                env_list->capacity = (int)ncap;
                env_list->items = NULL;
                if (ncap > 0) {
                    env_list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)ncap, AVM_ALLOC_KIND_LIST);
                    if (!env_list->items) { avm_heap_free(env_list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    // Capture values are below the base function on the stack:
                    //   [... cap0 cap1 ... cap(n-1) base_fn]
                    int start = vm->sp - 1 - (int)ncap;
                    for (int i = 0; i < (int)ncap; i++) {
                        env_list->items[i] = vm->stack[start + i];
                    }
                }

                AvmValue envv;
                envv.type = AVM_VAL_LIST;
                envv.as.l = env_list;
                AvmValue clo = avm_func_new(vm, base.as.fn->addr, envv);
                if (avm_is_err_val(clo)) { avm_abort(vm, clo); break; }

                vm->sp -= (int)ncap + 1;
                vm->stack[vm->sp++] = clo;
                break;
            }
            case 0x3F: { // LOAD_ENV u8
                uint8_t idx = code[vm->pc++];
                if (vm->env.type != AVM_VAL_LIST || !vm->env.as.l) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_ENV with nil env"));
                    break;
                }
                AvmList* env_list = vm->env.as.l;
                if ((int)idx >= env_list->count) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "LOAD_ENV out of range"));
                    break;
                }
                vm->stack[vm->sp++] = env_list->items[(int)idx];
                break;
            }
            case 0x3A: { // CALL_NATIVE u16 u8 (legacy mapping)
                uint16_t id = code[vm->pc++];
                id |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                uint8_t domain = 0;
                uint16_t op2 = 0;
                avm_legacy_native_to_domop(id, &domain, &op2);
                AvmValue* args = (nargs > 0) ? &vm->stack[vm->sp - nargs] : NULL;
                (void)trace_emit_native2(vm, op_pc, domain, op2, nargs);
                AvmValue res = avm_call_native2(vm, domain, op2, args, nargs);
                vm->sp -= nargs;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x3B: { // CALL_NATIVE2 u8 u16 u8
                uint8_t domain = code[vm->pc++];
                uint16_t op2 = code[vm->pc++];
                op2 |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                AvmValue* args = (nargs > 0) ? &vm->stack[vm->sp - nargs] : NULL;
                (void)trace_emit_native2(vm, op_pc, domain, op2, nargs);
                AvmValue res = avm_call_native2(vm, domain, op2, args, nargs);
                vm->sp -= nargs;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x40: { // NEW_LIST u16
                uint16_t len = code[vm->pc++];
                len |= (uint16_t)code[vm->pc++] << 8;
                if (vm->sp < (int)len) {
                    avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "stack underflow"));
                    break;
                }
                AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList), AVM_ALLOC_KIND_LIST);
                if (!list) { avm_abort(vm, avm_alloc_fail_value()); break; }
                list->count = (int)len;
                list->capacity = (int)len;
                list->items = NULL;
                if (len > 0) {
                    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)list->capacity, AVM_ALLOC_KIND_LIST);
                    if (!list->items) { avm_heap_free(list); avm_abort(vm, avm_alloc_fail_value()); break; }
                    // NEW_LIST consumes `len` values from the stack, preserving push order:
                    // the last pushed value becomes the last element in the list.
                    for (int i = (int)len - 1; i >= 0; i--) {
                        list->items[i] = vm->stack[--vm->sp];
                    }
                }
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x41: { // NEW_MAP u16
                uint16_t pairs = code[vm->pc++];
                pairs |= (uint16_t)code[vm->pc++] << 8;
                AvmMap* map = (AvmMap*)avm_heap_malloc_k(sizeof(AvmMap), AVM_ALLOC_KIND_MAP);
                if (!map) { avm_abort(vm, avm_alloc_fail_value()); break; }
                map->count = 0;
                map->capacity = (pairs > 0) ? pairs * 2 : 8;
                map->keys = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                map->values = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * (size_t)map->capacity, AVM_ALLOC_KIND_MAP);
                if (!map->keys || !map->values) {
                    if (map->keys) avm_heap_free(map->keys);
                    if (map->values) avm_heap_free(map->values);
                    avm_heap_free(map);
                    avm_abort(vm, avm_alloc_fail_value());
                    break;
                }
                for (uint16_t i = 0; i < pairs; i++) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    if (!avm_map_key_supported(key)) {
                        avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                        break;
                    }
                    if (!avm_map_set_sorted(map, key, val)) {
                        avm_abort(vm, avm_alloc_fail_value());
                        break;
                    }
                }
                AvmValue res;
                res.type = AVM_VAL_MAP;
                res.as.m = map;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x42: { // GET_INDEX
                if (vm->sp >= 2) {
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    AvmValue res = avm_nil();

                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            res = obj.as.l->items[i];
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                            break;
                        }
                        int found = 0;
                        int idx = avm_map_find_index(obj.as.m, key, &found);
                        if (found) {
                            res = obj.as.m->values[idx];
                        }
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x43: { // SET_INDEX
                if (vm->sp >= 3) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];

                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            obj.as.l->items[i] = val;
                        } else if (i == obj.as.l->count) {
                            if (!avm_list_ensure_cap(obj.as.l, obj.as.l->count + 1)) {
                                avm_abort(vm, avm_alloc_fail_value());
                                break;
                            }
                            obj.as.l->items[obj.as.l->count++] = val;
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        if (!avm_map_key_supported(key)) {
                            avm_abort(vm, avm_err(AVM_ERR_INVALID_ARG, "map key type not supported (need nil/bool/int/string)"));
                            break;
                        }
                        if (!avm_map_set_sorted(obj.as.m, key, val)) {
                            avm_abort(vm, avm_alloc_fail_value());
                            break;
                        }
                    }
                }
                break;
            }
            default:
                avm_abort(vm, avm_err(AVM_ERR_INTERNAL, "unknown opcode"));
                break;
        }

        // Deterministic time-sliced scheduling (gas quantum):
        // If there is another runnable task, decrement current slice and yield when it reaches 0.
        if (sched && sched->ready_len > 0) {
            int cur = sched->current_tid;
            if (cur >= 0 && cur < sched->task_cap && sched->tasks[cur].used && !sched->tasks[cur].done && !sched->tasks[cur].blocked) {
                AvmTask* ct = &sched->tasks[cur];
                ct->slice_remaining--;
                if (ct->slice_remaining <= 0) {
                    ct->slice_remaining = sched->quantum_steps;
                    task_save_from_vm(vm, ct);
                    (void)sched_ready_push(sched, cur);
                    int next = -1;
                    if (sched_ready_pop(sched, &next)) {
                        sched_switch(vm, sched, next);
                        continue;
                    }
                }
            }
        }

        // JOIN_TIMEOUT deadlines: if any join-timeout waiters are blocked and expired, wake them with ETIMEDOUT.
        // This scan is O(tasks) and runs periodically (amortized). Keep it cheap.
        if (sched && ((steps & 255ull) == 0)) {
            uint64_t now = avm_vm_now_ns(vm);
            for (int i = 0; i < sched->task_cap; i++) {
                AvmTask* t = &sched->tasks[i];
                if (!t->used || !t->blocked) continue;
                if (t->wait_kind != 4) continue; // join_timeout
                if (t->join_deadline_ns == 0) continue;
                if (now >= t->join_deadline_ns) {
                    t->blocked = 0;
                    t->wait_kind = 0;
                    t->join_deadline_ns = 0;
                    t->wake_pending = 1;
                    t->wake_value = avm_int(-60); // ETIMEDOUT (BSD)
                    (void)sched_ready_push(sched, i);
                }
            }
        }
    }

    if (vm->trace_hash_enabled && vm->trace_hash_started && !vm->trace_hash_finalized) {
        avm_sha256_final(&vm->trace_hash_ctx, vm->trace_hash_out);
        vm->trace_hash_finalized = 1;
    }

    avm_alloc_owner_pop(prev_owner);
}

static void avm_sched_free(AvmVM* vm) {
    if (!vm || !vm->sched) return;
    AvmSched* s = (AvmSched*)vm->sched;

    if (s->tasks) {
        for (int i = 0; i < s->task_cap; i++) {
            AvmTask* t = &s->tasks[i];
            if (!t->used) continue;
            if (t->frames) free(t->frames);
            // Task 0 stack is vm->stack_base (owned by VM).
            if (i != 0 && t->stack) free(t->stack);
            t->frames = NULL;
            t->stack = NULL;
            t->used = 0;
        }
        free(s->tasks);
    }
    if (s->ready) free(s->ready);
    if (s->select_waiters) free(s->select_waiters);

    if (s->chans) {
        for (int i = 0; i < s->chan_cap; i++) {
            AvmChan* ch = &s->chans[i];
            if (!ch->used) continue;
            if (ch->recv_waiters) free(ch->recv_waiters);
            if (ch->q) free(ch->q);
            ch->recv_waiters = NULL;
            ch->q = NULL;
            ch->used = 0;
        }
        free(s->chans);
    }

    free(s);
    vm->sched = NULL;
    vm->stack = vm->stack_base;
}
