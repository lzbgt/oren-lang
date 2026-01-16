# Native Backend: G-M-P (Greenlet) Scheduler Design (Syscall-First, No libc/pthreads)

**Status:** Draft (design + staged plan)  
**Scope:** native backend runtime (AArch64), not AVM bytecode scheduling  
**Non-goals (for now):** JIT, cross-language ABI stability, “perfect” determinism under OS threads

This document defines how Oren’s **native backend** evolves from the early bootstrap `spawn`
(historically macOS/Linux: `fork + pipe`) into a production-grade **N:M** (a.k.a. **G-M-P**) greenlet
runtime **without relying on libc/pthreads shims**.

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

### Stage N0 (historical baseline): process-based `spawn` (fork+pipe) on POSIX

Historical bootstrap behavior (macOS/Linux native):

- `spawn` implemented as `fork + pipe` (process-based) to avoid relying on libpthread’s `bsdthread_*` APIs.

Current (rolling) behavior:

- `spawn` on macOS/Linux now **prefers in-process green tasks** (Stage N1) and falls back to fork+pipe
  when green tasks are disabled/unavailable.
  - Escape hatch: `OREN_NO_GREEN=1` forces fork+pipe for bring-up/debugging.

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

Status (fact, code):

- Green task runtime is implemented in `lib/runtime_native/263_green_tasks.oren`.
- `spawn` prefers green tasks on POSIX via `oren_green_spawn` (`lib/runtime_native/120_first_class_fn.oren`).
- Context switch intrinsics are defined as native backend intrinsics (`oren_ctx_init`, `oren_ctx_switch` in
  `lib/runtime_native/000_prelude_sys.oren`).

### Stage N2: N:M GMP (multiple OS threads, multiple Ps)

Goal:

- scale compute across cores while keeping `G` lightweight.

Key additions:

1) **Syscall-first OS thread creation**
   - Implement OS thread creation via kernel interfaces directly (no libpthread).
   - Keep the boundary narrow: a single `sys_thread_create(entry, arg, stack_top, ctid_ptr)` (Linux),
     or `sys_win_createthread(entry, arg)` (Windows), plus minimal TLS/registration.
   - macOS note (rolling): true syscall-first OS-thread creation requires the `bsdthread_*` syscall boundary
     (or another kernel-exposed thread API) and correct thread-local storage + threadstart stub installation.

Status (rolling groundwork):

- **Linux + Windows:** a runtime-owned OS-thread handle exists and is used by tests:
  - Runtime: `lib/runtime_native/269_os_thread_m.oren` (`oren_os_thread_spawn`, `oren_os_thread_join_timeout`, `oren_os_thread_destroy`)
  - Linux thread creation uses the syscall-first clone wrapper: `lib/runtime_native/266_linux_os_threads.oren` (`sys_thread_create`)
  - Parking uses wait-on-address: `lib/runtime_native/267_wait_on_addr.oren` (`oren_wait_on_addr`, `oren_wake_all_addr`)
  - Smokes:
    - `tests/native/test_os_thread_park_unpark_smoke.oren`
    - `tests/native/test_os_thread_spawn_many_smoke.oren`
- **macOS arm64:** syscall-first `bsdthread_register/create/terminate` lowering exists, and the native backend
  attempts to install runtime-owned threadstart stubs at process init (non-dylib builds):
  - Compiler emit + init call: `lib/compiler/arm64_native_program.oren`
  - Threadstart stubs + fallback implementation: `lib/runtime_native/264_darwin_os_threads.oren`
  - Runtime init helper: `lib/runtime_native/020_fork_runtime_init.oren` (`native_runtime_threading_init`)
  - Reality note (rolling): many macOS processes are already registered by dyld/libpthread, so the runtime
    uses a **pthread_create fallback** for `oren_os_thread_spawn` unless our runtime-owned registration succeeds.
    The long-term target remains syscall-first threads (no libpthread dependency).

- **Green-task scheduler worker mode (Stage N2 groundwork):** the Stage N1 green-task runtime now supports:
  - per-OS-thread scheduler state (scheduler context + current-G are no longer globals), including a thread-local **current P** pointer, and
  - optional background scheduler workers (`oren_green_start_workers(n)`) that drain:
    - their bound `P` local runq/sleepq (locality), and
    - a scheduler-level **global run queue** for cross-P injection / fairness (spawns from outside green context).
  - Worker sleeping behavior (rolling, but important for responsiveness):
    - when only sleepers exist, the worker parks on the shared park word with a timeout (so new runnable work wakes it immediately)
    - inserting new sleepers wakes workers so the “next wake” deadline is re-evaluated promptly
    - sleeper deadlines use a **monotonic** clock (`oren_time_mono_ns`) so wall-clock jumps do not break wake behavior:
      - Linux: fills `sys_gettimeofday(..., abs_ptr)` via `clock_gettime(CLOCK_MONOTONIC)` in ns
      - macOS: converts gettimeofday’s `mach_absolute_time` out-arg using `mach_timebase_info` (num/den)
      - Windows: converts QPC ticks using `QueryPerformanceFrequency`
  - Join behavior: when workers are enabled, `oren_green_join_timeout` waits on the green task's state word via the portable
    wait-on-address primitive (instead of driving the scheduler on the joining thread).
  - P ownership (rolling correctness guard): when workers are enabled, `_green_poll_until` enforces `P.owner_tid == sys_gettid()`.
    Worker bring-up reserves each `P` with a negative sentinel during `oren_green_start_workers`, then the worker claims its bound `P`
    to a positive tid before entering the scheduler loop (hard-fails on mismatches).
  - Runtime: `lib/runtime_native/263_green_tasks.oren`
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join`)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_wake_while_sleepers`) (prevents “sleepers stall runnable work” regressions)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_many_tasks_bounded`) (many short tasks must complete; no hangs)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_time_mono_ns_monotonic`) (`oren_time_mono_ns` must advance)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_ctx_switch_alloc_integrity`) (worker-mode ctx-switch must not corrupt scheduler locals / allocator state)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_local_ptr_survives_yields`) (ctx-switch must preserve long-lived locals across yields)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_local_ptr_survives_yields`) (same contract under worker-mode scheduling)
  - Rolling limitation (important): `_green_poll_until` currently re-fetches per-thread scheduler state (`ts`/`P`) each poll iteration for robustness.
    - Rationale: until native backend/local preservation invariants are fully tightened across ctx switches and syscalls, caching `ts`/`P` as long-lived locals
      can lead to crashes (non-canonical pointers later dereferenced via `ptr_get` / `ptr_get_byte`).
    - Repro (rolling, 2026-01-16): attempts to add an env-gated cached mode (e.g. probing an `OREN_GREEN_POLL_CACHE` env var via
      `native_envp_get_value_ptr(...)` and caching `ts`/`P` across iterations) caused deterministic SIGSEGV (rc=139) in `make test-native-quick-stage2` / `make test`,
      so the runtime keeps the safe re-fetch loop and does not ship a cache knob yet.
    - Recent mitigations that tightened stack/local invariants but did **not** make caching safe yet (2026-01-16):
      - arm64 stmt codegen restores SP after condition evaluation in `if` / `while` / `for` headers
      - arm64 stmt codegen uses chunked SP restores (`emit_add_sp_any`) for large deltas
      - arm64 `var` initializer stores via FP-relative addressing (reduces transient SP sensitivity)
    - Runtime: `lib/runtime_native/263_green_tasks.oren` (`_green_poll_until`)
  - Rolling limitation (important): worker parallelism is currently clamped to 1 by default, because the native allocator/GC
    are not concurrency-correct yet. Opt-in for experimentation only: `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`.

Correctness gotchas (fact; Tier‑1 regression-driven):

- **Linux clone trampoline must initialize “reserved registers” for the child OS thread.**
  - The native bump allocator state lives in reserved callee-saved registers:
    - arm64: `X28` = heap_ptr, `X27` = heap_limit
    - x64: `R15` = heap_ptr, `R14` = heap_limit
  - Linux `clone(2)` threads inherit the parent register contents; if the child keeps those heap registers,
    the parent and child can allocate from the same bump region and corrupt heap objects/metadata under worker-mode scheduling.
  - Fix (2026-01-16): the `sys_thread_create` child path now resets the heap registers to `0` before calling the start routine,
    forcing the first allocation in the new OS thread to take the slow path (mmap a fresh chunk) and seed per-thread bump state.

- **Process exit on Linux must use `exit_group(2)` once OS threads exist.**
  - `exit(2)` terminates only the calling thread; if background workers exist, `exit(0)` can leave the process alive and look “hung”.
  - Fix (2026-01-16): arm64 native lowering routes source-level `exit(...)` to `exit_group` via `sys_exit_group`;
    `sys_exit` remains “terminate this thread” and is used by thread trampolines.

2) **Parking/unparking**
   - When an `M` has no work, it must block efficiently without busy looping.
   - Implement via a syscall-level wait primitive (platform-specific):
     - macOS candidates include kernel wait/wake interfaces used by system runtimes.
     - Linux uses `futex`.
   - The exact primitive is an implementation detail, but “sleep until work” is mandatory for production.

Status (rolling groundwork):

- The portable wait-on-address layer exists and is verified:
  - `lib/runtime_native/267_wait_on_addr.oren`
  - `tests/native/test_ulock_timeout_portable.oren`
  - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_mismatch_is_success`) (locks in “wait while equal” semantics)
- The scheduler-oriented “park word” exists (token + wait-on-address) and is verified:
  - `lib/runtime_native/269_os_thread_m.oren` (`oren_m_park_word_wait`, `oren_m_park_word_wake`)
  - `tests/native/test_os_thread_park_unpark_smoke.oren`

3) **Run queues**
   - Each `P` has a local run queue for `G`.
   - There is a global queue for overflow and fairness.
   - Add work stealing between `P` (to balance load).
   - Requires atomics (already present: `atomic_add`, `atomic_cas`).

Rolling status (native runtime bring-up):

- The native green scheduler now models `P` local run queues as a **ring buffer** (monotonic head/tail + mask),
  with overflow to a scheduler-level **global run queue**. The local queue is treated as a **work-stealing deque**:
  - the owning `M` pops from the *tail* (LIFO locality), and
  - stealing `M` takes from the *head* (FIFO fairness).
  This keeps the shape aligned with an eventual atomics-based implementation while keeping the current bring-up lock model simple.

4) **Syscall blocking strategy**
   - Prefer non-blocking + event loop for IO-bound `G` (best scalability).
   - For truly blocking operations, detach the `G` from the `M` and let the `M` continue running other `G`.

5) **GC and stack scanning implications**
   - Oren’s current GC strategy must eventually become “stop-the-world at safepoints” or another well-defined scheme.
   - For N:M, you need:
     - a way to stop all `M` at safepoints, or
     - a conservative stack scanning strategy with coordination
   - This is a major reason to do N:1 first: it validates `G` stacks + yield points before introducing cross-thread coordination.

Status (rolling, fact):

- 2026-01-15: a minimal **stop-the-world at safepoints** protocol exists in the native runtime to make `oren_gc_collect()` safe when more than one OS thread exists:
  - Runtime impl: `lib/runtime_native/100_time.oren` (`native_gc_stw_begin/native_gc_stw_poll_and_park/native_gc_stw_end`)
  - Coordination words live in globals storage (wait-on-address): offsets `424/432/440` (see `lib/runtime_native/010_channels_globals_consts.oren`)
  - Guard: `tests/native/test_gc_stw_os_thread_collect.oren`
  - Limitation: cooperative only (threads must reach `oren_gc_safepoint()`); this is foundational plumbing for a future preemptive/stw design and for M:N.
- 2026-01-16: compiler backends now insert **throttled cooperative safepoints** into loop headers (every 256 iterations) so OS threads can reliably reach `oren_gc_safepoint()`:
  - C backend transpiler: `lib/compiler/transpiler.oren`
  - arm64 native backend: `lib/compiler/arm64_native_stmt.oren` (`native_emit_gc_safepoint_throttled`)
  - x64 native backend: `lib/compiler/x64_native_program/060_emit_ops.oren` (`_emit_gc_safepoint_throttled_x64`)
  - Limitation: this is still loop-based cooperative polling; long-running non-loop code still needs a bounded safepoint strategy, and there is no preemption yet.
- 2026-01-16: native call-depth hook now also performs a **throttled STW poll** (every 1024 function entries) in multi-OS-thread mode:
  - Runtime: `lib/runtime_native/105_call_depth.oren` (`native_call_depth_safepoint_poll_throttled`)
  - This complements loop-header polling for call-heavy non-loop paths (visitors/recursion), but is still cooperative (no preemption).

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
