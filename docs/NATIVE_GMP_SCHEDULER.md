# Native Backend: G-M-P (Greenlet) Scheduler Design (Syscall-First, No libc/pthreads)

**Status:** Draft (design + staged plan)  
**Scope:** native backend runtime (AArch64), not AVM bytecode scheduling  
**Non-goals (for now):** JIT, cross-language ABI stability, “perfect” determinism under OS threads

This document defines how Oren’s **native backend** can evolve from today’s bootstrap `spawn` (macOS: `fork + pipe`) into a production-grade **N:M** (a.k.a. **G-M-P**) greenlet runtime **without relying on libc/pthreads shims**.

Related:

- `docs/SYSCALL_FIRST_RUNTIME_PLAN.md` (syscall-first runtime boundary)
- `docs/CONCURRENCY_MODEL.md` (language-level concurrency surface)
- `docs/AVM_CONCURRENCY.md` (deterministic concurrency inside AVM; different goal)

## 0) Terminology

We use the Go-style naming because it maps cleanly to the target architecture:

- **G** (“greenlet” / “goroutine”): a lightweight task that runs Oren code.
- **M** (“machine”): an OS thread that executes code on a CPU core.
- **P** (“processor”): a scheduler context holding run queues, timers, and local caches. At any instant, an `M` runs code *only while holding a `P`*.

Target end state:

- Many `G` run on fewer `M` (N:M).
- `P` count (often) equals the number of OS threads allowed to run Oren code concurrently (similar to `GOMAXPROCS`).

## 1) Non-negotiables (syscall-first and “no shims”)

1) **No libc / no libpthread dependency in the core runtime**
   - The runtime may call kernel syscalls directly.
   - The runtime must not link against libc/pthreads to “get threads”.

2) **Blocking must not block the entire runtime**
   - A single blocked operation (NET/PROC/FS) must not stall all runnable `G`.
   - For the N:1 phase, this implies “event-loop style” non-blocking syscalls.
   - For N:M, it implies “park the `G`” and let the `M` run other work.

3) **Rolling ABI friendly**
   - Data structures and calling conventions can evolve (repo is rolling ABI).
   - But we must avoid a “do shims now, rewrite later” trap: build the correct syscall-first shape early.

## 2) Why AVM and native concurrency are different problems

AVM concurrency (`docs/AVM_CONCURRENCY.md`) is about:

- determinism (consensus/replay)
- snapshot/restore of scheduler state as data
- capability-governed effects (VirtualFS/VirtualNET/VirtualPROC)

Native backend concurrency is about:

- production throughput and real OS integration (real sockets, real processes)
- efficient multiplexing (kevent/kqueue on macOS; epoll on Linux)
- low overhead tasks (millions of `G`), with OS threads used as an execution resource

So:

- **AVM:** single-thread semantics first, deterministic scheduler.
- **Native:** N:1 greenlets first (event loop), then N:M once syscall-first threads are in place.

## 3) Staged plan (no huge rewrite)

### Stage N0 (today): `spawn` is process-based on macOS

Current bootstrap behavior (macOS native):

- `spawn` implemented as `fork + pipe` (process-based) to avoid relying on libpthread’s `bsdthread_*` APIs.

Pros:

- correct, syscall-first, debuggable
- avoids “thread init” complexity early

Cons:

- heavy (process cost)
- not a greenlet model
- not suitable for large-scale concurrency

### Stage N1: N:1 cooperative greenlets (single OS thread)

Goal:

- Introduce **real lightweight concurrency** without needing OS thread creation yet.

Core idea:

- One OS thread runs an event loop and a cooperative scheduler.
- Each `G` yields explicitly at safe points.

Requirements:

1) **A context switch primitive**
   - Implemented as a tiny AArch64 assembly routine (no libc):
     - save callee-saved registers + SP + return address into a `Context`
     - restore from another `Context`
   - Exposed to Oren as an intrinsic (e.g. `oren_ctx_switch(old, new)`).

2) **Per-greenlet stack**
   - Allocate stacks from the runtime allocator (eventually with guard pages).
   - Store stack pointer + entry function pointer in `G`.

3) **Yield points**
   - Minimal: `yield()` builtin (or `oren_yield()` runtime call) that enqueues current `G` and switches to scheduler.
   - Also: `sleep_ms`, channel ops, and capability-scoped “syscalls” become yield points.

4) **Non-blocking OS integration**
   - On macOS, `kqueue/kevent` is the syscall-first friendly multiplexer.
   - NET reads/writes use non-blocking sockets + kevent timeouts.
   - PROC waits can use `wait4` with polling/timeouts (or a signal + kevent integration later).

This stage gives:

- a true coroutine runtime
- cancellable/timeout-capable IO (essential for agent systems)
- minimal architectural debt (the `G`/scheduler model remains the same in N:M)

### Stage N2: N:M GMP (multiple OS threads, multiple Ps)

Goal:

- scale compute across cores while keeping `G` lightweight.

Key additions:

1) **Syscall-first OS thread creation**
   - Implement OS thread creation via kernel interfaces directly (no libpthread).
   - macOS note: this requires the `bsdthread_*` syscall boundary (or another kernel-exposed thread API) and correct thread-local storage setup.
   - Keep the boundary narrow: a single `sys_thread_create(entry, arg)` + `sys_thread_self()` + minimal TLS init.

2) **Parking/unparking**
   - When an `M` has no work, it must block efficiently without busy looping.
   - Implement via a syscall-level wait primitive (platform-specific):
     - macOS candidates include kernel wait/wake interfaces used by system runtimes.
     - Linux uses `futex`.
   - The exact primitive is an implementation detail, but “sleep until work” is mandatory for production.

3) **Run queues**
   - Each `P` has a local run queue for `G`.
   - There is a global queue for overflow and fairness.
   - Add work stealing between `P` (to balance load).
   - Requires atomics (already present: `atomic_add`, `atomic_cas`).

4) **Syscall blocking strategy**
   - Prefer non-blocking + event loop for IO-bound `G` (best scalability).
   - For truly blocking operations, detach the `G` from the `M` and let the `M` continue running other `G`.

5) **GC and stack scanning implications**
   - Oren’s current GC strategy must eventually become “stop-the-world at safepoints” or another well-defined scheme.
   - For N:M, you need:
     - a way to stop all `M` at safepoints, or
     - a conservative stack scanning strategy with coordination
   - This is a major reason to do N:1 first: it validates `G` stacks + yield points before introducing cross-thread coordination.

## 4) Minimal language surface to support this

To avoid a spec rewrite while still enabling modern concurrency:

- Keep `spawn f(args...)` as the surface syntax, but redefine its semantics over time:
  - v0 (today): `spawn` is process-based (macOS bootstrap)
  - N:1: `spawn` creates a `G`
  - N:M: `spawn` creates a `G` scheduled over `M` threads

Add (recommended) explicit primitives:

- `yield()` (or `yield expr` later if it becomes an expression-level feature)
- `sleep_ms(ms)` (already exists; must be cancellable/timeout-safe)
- channels (`chan`, `send`, `recv`, `select`) for structured concurrency

## 5) Deliverables checklist (engineering milestones)

N:1 (must land before N:M to avoid massive debugging complexity):

- `Context` struct + `oren_ctx_switch` intrinsic (AArch64)
- `G` struct (stack, context, status, id)
- scheduler loop in runtime (ready queue + timers)
- `yield()` intrinsic and at least one regression test that proves it yields
- non-blocking `sleep_ms` integration (scheduler timer)

N:M (after N:1 is stable):

- syscall-first `sys_thread_create` on macOS arm64
- `P` struct + per-P run queue
- `M` worker loop + parking/unparking
- work stealing
- GC coordination plan (even if “stop the world” at first)

## 6) Relationship to AVM “multiverse”

Native GMP enables “real world” libraries and services written in `.oren`.

AVM multiverse enables:

- deterministic simulation of agents
- policy scanning and governance
- portable snapshots

Both are mandatory long-term, but they solve different operational tiers.

