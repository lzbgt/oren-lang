# AVM VM Split

**Date:** 2026-02-25

## Goals

- Reduce `lib/avm/avm_vm.c` below the 2000-line threshold by splitting into focused VM modules.
- Preserve runtime semantics and bytecode behavior (no opcode changes).
- Keep internal interfaces tight and explicit (minimal cross-file coupling).

## Non-goals

- Changing AVM opcode semantics or scheduler behavior.
- Altering public `avm.h` API or snapshot format.
- Performance optimizations beyond structural refactor.

## Constraints

- Maintain deterministic scheduler invariants (single-threaded, no host syscalls).
- Keep `avm_run()` as the central dispatcher with a stable signature.
- Ensure `avm_internal.h` remains the single shared source for internal types.

## Proposed module map

- `lib/avm/avm_vm.c`:
  - `avm_run()` and opcode dispatch; minimal local helpers only.

- `lib/avm/avm_vm_sched.[ch]`:
  - Scheduler/task/channel helpers (`avm_sched_is_trivial`, task save/load,
    ready/select queues, channel send/recv, select wakeups, scheduler teardown).

- `lib/avm/avm_vm_core.c`:
  - VM lifecycle (`avm_new`, `avm_free`, `avm_load`, `avm_abort`),
    and opcode metadata helpers (`avm_op_name`, `avm_gas_cost`).

- `lib/avm/avm_vm_values.[ch]`:
  - Value helpers (truthiness, comparisons, numeric helpers) as inlines in the header,
    plus short type names + list<int> constructor helpers in the `.c`.

- `lib/avm/avm_vm_list_ops.[ch]`:
  - Heavy list/list_int opcode helpers (`LIST_DOT`, `LIST_PUSH*_INT_LOOP`),
    keeping the large loops out of `avm_vm.c`.

## Validation

- `make test` (fast Tier-1 smoke)
