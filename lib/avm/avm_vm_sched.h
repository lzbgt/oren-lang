#ifndef AVM_VM_SCHED_H
#define AVM_VM_SCHED_H

#include "avm_internal.h"

AvmSched* avm_sched_get(AvmVM* vm);
AvmSched* avm_sched_lazy_ensure(AvmVM* vm, AvmSched* sched);
void avm_sched_free(AvmVM* vm);
AvmValue make_pair_list(AvmVM* vm, AvmValue a, AvmValue b);

int sched_ready_push(AvmSched* s, int tid);
int sched_ready_pop(AvmSched* s, int* out_tid);
int sched_select_waiter_add(AvmSched* s, int tid);
void task_save_from_vm(AvmVM* vm, AvmTask* t);
int sched_new_task(AvmVM* vm, AvmSched* s, AvmValue fn, AvmValue args_list);

AvmChan* sched_chan_get(AvmSched* s, int64_t hid);
int sched_chan_new(AvmSched* s);
int chan_recv_waiter_push(AvmChan* ch, int tid);
int chan_queue_pop(AvmChan* ch, AvmValue* out);
int chan_can_send(AvmChan* ch);
int chan_send_value(AvmSched* s, AvmChan* ch, AvmValue v);

void sched_switch(AvmVM* vm, AvmSched* s, int next_tid);
uint64_t avm_vm_now_ns(AvmVM* vm);
uint64_t avm_deadline_after_ms(AvmVM* vm, int64_t ms);
int avm_clamp_wait_ms_to_int(int64_t ms);
void avm_add_virtual_sleep_ms(AvmVM* vm, int64_t ms);
void avm_task_clear_wait_state(AvmTask* task);
void avm_task_wake_with_value(AvmSched* sched, int waiter_tid, AvmValue value);
void avm_task_wake_join_waiters(AvmSched* sched, int target_tid, AvmValue ret);
AvmValue avm_task_cancel_wait_result_or_transition(AvmVM* vm, AvmSched* sched, int waiter_tid, int target_tid, int64_t wait_ms, AvmValue reason, int* transitioned);
void sched_try_wake_select_waiters(AvmVM* vm, AvmSched* s);
AvmValue avm_task_current_handle(AvmVM* vm);
AvmValue avm_task_request_cancel(AvmVM* vm, AvmValue handle, AvmValue reason);
AvmValue avm_task_is_cancel_requested(AvmVM* vm, AvmValue handle);
AvmValue avm_task_cancel_reason(AvmVM* vm, AvmValue handle);
AvmValue avm_task_cancel_now(AvmVM* vm, AvmValue handle, AvmValue reason);
AvmValue avm_task_stop_result(const char* status, AvmValue result, AvmValue reason, AvmValue detach_result);
AvmValue avm_task_cancel_wait(void);
AvmValue avm_task_cancel_after_wait(void);
AvmValue avm_task_stop_capabilities(void);
AvmValue avm_task_group_new(AvmVM* vm);
int avm_task_group_is_handle(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_add(AvmVM* vm, AvmValue group, AvmValue handle);
AvmValue avm_task_group_count(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_members(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_member_kinds(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_member_snapshot(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_snapshot(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_take_snapshot(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_default_policy(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_set_default_policy(AvmVM* vm, AvmValue group, AvmValue policy);
AvmValue avm_task_group_clear(AvmVM* vm, AvmValue group);
AvmValue avm_task_group_spawn_call_list(AvmVM* vm, AvmValue group, AvmValue fn, AvmValue args_list);

#endif
