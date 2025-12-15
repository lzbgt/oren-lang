# AVM Concurrency Model (Deterministic, Syscall-First-Aligned, Multiverse-Friendly)

**Status:** Draft (design guidance + priorities)  
**Last updated:** 2025-12-15  
**Scope:** AVM execution semantics (bytecode VM), not the native backend runtime

This document defines what “concurrency” should mean for **AVM** in the AI/agent era, especially given:

- AVM supports **nested universes** (AVM-in-AVM) (`docs/AVM_MULTIVERSE.md`)
- AVM targets restricted environments (iOS/Web/Edge) and must stay **no-JIT-first**
- Oren’s native runtime roadmap is **syscall-first** and avoids libc/pthreads (`docs/SYSCALL_FIRST_RUNTIME_PLAN.md`)

The key requirement is not raw throughput; it is **deterministic, governable concurrency** that composes with:

- capability gating and virtualization
- snapshot/restore and “agent mobility”
- record/replay auditing
- swarm consensus (`docs/AVM_SWARM_CONSENSUS.md`)

## 0) Non-negotiables

1) **Deterministic baseline**
   - AVM must have a single-thread deterministic execution mode that is stable enough for consensus.
2) **No host-thread nondeterminism in the core VM**
   - AVM must not depend on OS thread scheduling to define semantics.
3) **Blocking is always explicit and budgeted**
   - Any “wait” must be representable as a deterministic state transition (for snapshot/replay), and be subject to gas/time budgets.

## 1) Model: Cooperative, deterministic “tasks” (green threads)

AVM concurrency should be **cooperative** and **deterministic**:

- A VM instance contains N lightweight tasks (“fibers”, “coroutines”, “green threads”).
- At any point, exactly one task is “running” in the interpreter.
- Tasks yield only at explicit yield points:
  - `sleep_ms`
  - blocking channel operations
  - `await` on a syscall-like host op (VirtualFS/VirtualNET/VirtualPROC)
  - explicit `yield` (when syntax lands)

This is aligned with:

- **snapshot/restore**: the scheduler state and task stacks are data
- **nested universes**: each child universe can be modeled as a task that runs under a separate budget allocation
- **syscall-first thinking**: “blocking” means “park until an event”, not “spin”

### 1.1 Deterministic scheduler rule

Scheduler determinism rule (recommended v0):

- Maintain a FIFO ready queue of runnable task IDs.
- On yield/block, the current task is moved to:
  - ready queue tail (voluntary yield), or
  - a wait queue keyed by (channel/time/event)
- On wake, tasks are enqueued in deterministic order:
  - time events ordered by `(wake_time, task_id)`
  - channel wakeups ordered by `(channel_id, enqueue_order)`

This ensures:

- given the same program + inputs + virtual time + replay logs, scheduling is deterministic
- `TRACE_HASH` can validate schedule decisions without recording them separately

## 2) Syscall-first alignment: AVM “syscalls” are capability-scoped host services

The native runtime’s syscall-first plan (`sys_*`) is about **native backend** independence from libc.

For AVM, “syscall-first alignment” means something analogous:

- all effectful / potentially blocking operations are modeled as explicit **capability-scoped calls**
- such calls must be:
  - denyable (capabilities)
  - budgeted (gas/time/io/log)
  - virtualizable / replayable (Virtual* backends)

Conceptually:

> AVM concurrency is an event loop that multiplexes capability-scoped “syscalls”.

Examples:

- `FS.read_file` may be instantaneous in “real host mode”, but in VirtualFS it is a deterministic lookup.
- `NET.http_request` (future) should always be modeled as an async op with replay logs providing responses in deterministic mode.

## 3) Nested universes as concurrent tasks (multiverse scheduling)

Nested universes (domain `AVM`, run child `.obc`) should integrate with the scheduler as:

- **spawn child universe** → create a child task whose execution is the child VM run
- **join** → parent task blocks until the child finishes (or budget aborts)

Important design choice:

- Child universes should not share mutable memory with the parent.
- Parent/child communicate via explicit data:
  - returned `MAP` (exit_code, hashes, logs)
  - `BYTES` replay log blobs (already supported)

This keeps universes composable and governable.

## 4) No OS threads in AVM semantics (but parallelism is a host optimization)

AVM semantics should be defined as **single-threaded**.

Implementations may:

- run multiple AVM instances in parallel at the host layer (outside semantics)
- use SIMD kernels for pure compute domains

But:

- bytecode-visible concurrency semantics must remain deterministic.

This is crucial for:

- consensus verification
- reproducible agent debugging
- stable snapshot/resume behavior

## 5) What we need before true concurrency lands (prerequisites)

To add task scheduling without breaking determinism, AVM needs:

1) A deterministic trace stream and `TRACE_HASH` (agent debugging + schedule validation)
2) A stable “blocking primitive” model in the VM:
   - “blocked on channel”
   - “blocked until virtual time >= t”
   - “blocked on event id”
3) Snapshot/restore that includes scheduler state
4) Virtualized TIME and record/replay for effectful domains (already partially present)

## 6) Priorities (derived from repo TODOs)

Near-term “must-have” tasks to unlock deterministic concurrency:

- Implement deterministic `TRACE_HASH` and a canonical trace encoding (see `docs/TODOS.md` P1).
- Define the `TASK` domain surface (design first):
  - spawn task (pure)
  - join task (blocking)
  - channel ops + select (blocking)
- Extend snapshot/restore to include tasks + wait queues (once tasks exist).

