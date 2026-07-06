// Deadline-backed scheduler waits: join timeouts and task cancel-wait opcodes.
// This scan is O(tasks) and runs periodically (amortized). Keep it cheap.
if (sched && ((steps & 255ull) == 0)) {
    uint64_t now = avm_vm_now_ns(vm);
    for (int i = 0; i < sched->task_cap; i++) {
        AvmTask* t = &sched->tasks[i];
        if (!t->used || !t->blocked) continue;
        if (t->wait_kind != 4 && t->wait_kind != 6) continue;
        if (t->join_deadline_ns == 0) continue;
        if (now >= t->join_deadline_ns) {
            if (t->wait_kind == 4) {
                t->blocked = 0;
                t->wait_kind = 0;
                t->join_deadline_ns = 0;
                t->wake_pending = 1;
                t->wake_value = avm_int(-60); // ETIMEDOUT (BSD)
                (void)sched_ready_push(sched, i);
            } else if (t->wait_kind == 6) {
                int target_tid = t->wait_id;
                AvmValue reason = t->wait_list;
                AvmValue rv = avm_task_stop_result("detached", avm_int(-60), reason, avm_nil());
                if (target_tid >= 0 && target_tid < sched->task_cap && sched->tasks[target_tid].used) {
                    AvmTask* target = &sched->tasks[target_tid];
                    if (target->done) {
                        rv = avm_task_stop_result("joined", target->has_ret ? target->ret : avm_nil(), reason, avm_nil());
                    } else {
                        target->detached = 1;
                    }
                }
                avm_task_wake_with_value(sched, i, rv);
            }
        }
    }
}
