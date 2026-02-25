#include "avm_vm_sched.h"

#include <stdlib.h>
#include <string.h>

static void task_load_into_vm(AvmVM* vm, AvmTask* t);
static AvmValue make_pair_list(AvmVM* vm, AvmValue a, AvmValue b);
static AvmSched* avm_sched_ensure(AvmVM* vm);
static int chan_recv_waiter_pop(AvmChan* ch, int* out_tid);
static int chan_queue_push(AvmChan* ch, AvmValue v);

AvmSched* avm_sched_get(AvmVM* vm) {
    return vm ? (AvmSched*)vm->sched : NULL;
}

AvmSched* avm_sched_lazy_ensure(AvmVM* vm, AvmSched* sched) {
    if (sched && sched->init) return sched;
    sched = avm_sched_ensure(vm);
    if (!sched) return NULL;
    sched->current_tid = 0;
    // Sync main task state now that scheduler exists.
    task_save_from_vm(vm, &sched->tasks[0]);
    return sched;
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

int sched_ready_push(AvmSched* s, int tid) {
    if (!s) return 0;
    if (tid < 0) return 0;
    if (s->ready_len + 1 > s->ready_cap) {
        int new_cap = s->ready_cap ? s->ready_cap * 2 : 16;
        int* n = (int*)malloc(sizeof(int) * (size_t)new_cap);
        if (!n) return 0;
        for (int i = 0; i < s->ready_len; i++) {
            int idx = s->ready_head + i;
            if (idx >= s->ready_cap) idx -= s->ready_cap;
            n[i] = s->ready[idx];
        }
        if (s->ready) free(s->ready);
        s->ready = n;
        s->ready_cap = new_cap;
        s->ready_head = 0;
    }
    if (s->ready_cap <= 0) return 0;
    int tail = s->ready_head + s->ready_len;
    if (tail >= s->ready_cap) tail -= s->ready_cap;
    s->ready[tail] = tid;
    s->ready_len++;
    return 1;
}

int sched_ready_pop(AvmSched* s, int* out_tid) {
    if (!s || s->ready_len <= 0) return 0;
    int tid = s->ready[s->ready_head];
    s->ready_head++;
    if (s->ready_head >= s->ready_cap) s->ready_head = 0;
    s->ready_len--;
    if (s->ready_len == 0) s->ready_head = 0;
    if (out_tid) *out_tid = tid;
    return 1;
}

int sched_select_waiter_add(AvmSched* s, int tid) {
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

void task_save_from_vm(AvmVM* vm, AvmTask* t) {
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
    list->all_int = (a.type == AVM_VAL_INT && b.type == AVM_VAL_INT);
    list->items = (AvmValue*)avm_heap_malloc_k(sizeof(AvmValue) * 2u, AVM_ALLOC_KIND_LIST);
    if (!list->items) { avm_heap_free(list); return avm_alloc_fail_value(); }
    list->items[0] = a;
    list->items[1] = b;
    AvmValue v; v.type = AVM_VAL_LIST; v.as.l = list;
    return v;
}

uint64_t avm_vm_now_ns(AvmVM* vm) {
    if (!vm) return 0;
    if (vm->deterministic) {
        // Deterministic monotonic clock derived from semantic work and explicit sleep.
        return vm->virtual_now_ns + vm->virtual_sleep_ns + vm->gas_executed * vm->virtual_step_ns;
    }
    return avm_now_ns();
}

void sched_switch(AvmVM* vm, AvmSched* s, int next_tid) {
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
    s->ready_head = 0;
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

int sched_new_task(AvmVM* vm, AvmSched* s, AvmValue fn, AvmValue args_list) {
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
    t->wait_id = 0;
    t->wait_chan = 0;
    t->wait_list = avm_nil();
    t->join_deadline_ns = 0;
    t->wake_pending = 0;
    t->wake_value = avm_nil();
    t->slice_remaining = s->quantum_steps;
    t->select_cursor = 0;
    t->stack = (AvmValue*)malloc(sizeof(AvmValue) * AVM_STACK_SIZE);
    if (!t->stack) { t->used = 0; return -1; }
    t->frames = (AvmFrame*)malloc(sizeof(AvmFrame) * (size_t)MAX_FRAMES);
    if (!t->frames) { free(t->stack); t->stack = NULL; t->used = 0; return -1; }
    memset(t->frames, 0, sizeof(AvmFrame) * (size_t)MAX_FRAMES);

    // Seed new task state (stack/pc/frames).
    t->pc = fn.as.fn->addr;
    t->sp = 0;
    t->fp = 0;
    t->frame_count = 0;
    t->env = fn.as.fn->env;
    // Push args list (CALL_INDIRECT_SPREAD semantics for now).
    t->stack[t->sp++] = args_list;

    if (tid >= s->task_count) s->task_count = tid + 1;
    (void)sched_ready_push(s, tid);
    return tid;
}

AvmChan* sched_chan_get(AvmSched* s, int64_t hid) {
    if (!s || hid <= 0) return NULL;
    for (int i = 0; i < s->chan_cap; i++) {
        AvmChan* ch = &s->chans[i];
        if (!ch->used) continue;
        if (ch->id == hid) return ch;
    }
    return NULL;
}

int sched_chan_new(AvmSched* s) {
    if (!s) return -1;
    int idx = -1;
    for (int i = 0; i < s->chan_cap; i++) {
        if (!s->chans[i].used) { idx = i; break; }
    }
    if (idx < 0) {
        int new_cap = s->chan_cap * 2;
        AvmChan* nc = (AvmChan*)realloc(s->chans, sizeof(AvmChan) * (size_t)new_cap);
        if (!nc) return -1;
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

int chan_recv_waiter_push(AvmChan* ch, int tid) {
    if (!ch) return 0;
    if (ch->recv_count + 1 > ch->recv_cap) {
        int new_cap = ch->recv_cap ? ch->recv_cap * 2 : 8;
        int* n = (int*)realloc(ch->recv_waiters, sizeof(int) * (size_t)new_cap);
        if (!n) return 0;
        ch->recv_waiters = n;
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
    if (ch->q_len + 1 > ch->q_cap) {
        int new_cap = ch->q_cap ? ch->q_cap * 2 : 8;
        if (new_cap > 4096) return 0; // cap to avoid runaway in rolling mode
        AvmValue* n = (AvmValue*)realloc(ch->q, sizeof(AvmValue) * (size_t)new_cap);
        if (!n) return 0;
        ch->q = n;
        ch->q_cap = new_cap;
    }
    ch->q[ch->q_len++] = v;
    return 1;
}

int chan_can_send(AvmChan* ch) {
    if (!ch) return 0;
    if (ch->q_len < 4096) return 1;
    // If queue is full, but a waiter exists, send can still complete.
    if (ch->recv_count > 0) return 1;
    return 0;
}

int chan_send_value(AvmSched* s, AvmChan* ch, AvmValue v) {
    if (!s || !ch) return 0;
    int recv_tid = -1;
    if (chan_recv_waiter_pop(ch, &recv_tid)) {
        if (recv_tid >= 0 && recv_tid < s->task_cap && s->tasks[recv_tid].used) {
            AvmTask* t = &s->tasks[recv_tid];
            t->blocked = 0;
            t->wait_kind = 0;
            t->wait_chan = 0;
            t->wake_pending = 1;
            t->wake_value = v;
            (void)sched_ready_push(s, recv_tid);
            return 1;
        }
    }
    return chan_queue_push(ch, v);
}

int chan_queue_pop(AvmChan* ch, AvmValue* out) {
    if (!ch || ch->q_len <= 0) return 0;
    AvmValue v = ch->q[0];
    for (int i = 1; i < ch->q_len; i++) ch->q[i - 1] = ch->q[i];
    ch->q_len--;
    if (out) *out = v;
    return 1;
}

void sched_try_wake_select_waiters(AvmVM* vm, AvmSched* s) {
    if (!vm || !s || s->select_len <= 0) return;
    int i = 0;
    while (i < s->select_len) {
        int tid = s->select_waiters[i];
        if (tid < 0 || tid >= s->task_cap || !s->tasks[tid].used) {
            // remove invalid
            for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
            s->select_len--;
            continue;
        }
        AvmTask* t = &s->tasks[tid];
        if (!t->blocked || (t->wait_kind != 3 && t->wait_kind != 5)) {
            for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
            s->select_len--;
            continue;
        }

        AvmValue list = t->wait_list;
        if (list.type != AVM_VAL_LIST || !list.as.l) {
            for (int j = i + 1; j < s->select_len; j++) s->select_waiters[j - 1] = s->select_waiters[j];
            s->select_len--;
            continue;
        }

        int cnt = list.as.l->count;
        int start = t->select_cursor % (cnt > 0 ? cnt : 1);
        int woke = 0;
        for (int step = 0; step < cnt; step++) {
            int k = (start + step) % cnt;
            AvmValue casev = list.as.l->items[k];
            if (casev.type != AVM_VAL_LIST || !casev.as.l || casev.as.l->count < 2) continue;
            AvmValue kindv = casev.as.l->items[0];
            AvmValue chv = casev.as.l->items[1];
            if (kindv.type != AVM_VAL_INT || chv.type != AVM_VAL_INT) continue;
            int kind = (int)kindv.as.i;
            int64_t chid = chv.as.i;
            AvmValue sendv = avm_nil();
            if (kind == 1) {
                if (casev.as.l->count < 3) continue;
                sendv = casev.as.l->items[2];
            }
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

void avm_sched_free(AvmVM* vm) {
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
