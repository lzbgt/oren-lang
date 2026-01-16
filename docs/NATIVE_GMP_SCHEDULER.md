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
   - Implemented as **native backend intrinsics** (inlined at call sites; no external asm objects or libc):
     - `oren_ctx_init(ctx_ptr, sp, pc)` initializes a context blob for first entry
     - `oren_ctx_switch(old_ctx, new_ctx)` saves CPU state into `old_ctx` and resumes `new_ctx`
   - Preservation contract (rolling, required for green scheduling correctness):
     - Save/restore all non-reserved GPRs + `SP` + resume `PC`.
     - Save/restore SIMD regs too (arm64: `Q0..Q31`, x64: `XMM0..XMM15`).
     - Do **not** save/restore the native bump allocator registers (arm64: `X27/X28`, x64: `R14/R15`), because allocator state must be shared per OS thread.

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
- 2026-01-16: native `oren_select` / `oren_select_recv` are green-aware and do not block the scheduler OS thread:
  - Green path uses the shared scheduler netpoller directly (**netpoll v2**): per-case tokens mark a full ready-set so deterministic cursor selection does not require per-wake probe polling.
  - Runtime: `lib/runtime_native/245_select.oren` (green `oren_select` waits on netpoll v2; non-green still uses a per-call kqueue/epoll wait)
  - Runtime: `lib/runtime_native/246_netpoll.oren`
    - POSIX: kqueue/epoll + wake pipe; allocation-free `native_netpoll_poll_many_scratch`
    - Windows (rolling v0): WinSock `select()` (`FD_SETSIZE=64` per call) with a watch table that can exceed 64 (polled in batches).
      - Wake: best-effort loopback UDP wake socket in non-capsule builds; in capsule builds it is only created if loopback endpoints are explicitly allowed.
      - IOCP is still the intended long-term implementation (scalability + true wake + future HANDLE story).
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (scheduler drains netpoll tokens and marks G/wait nodes ready)
  - Runtime: `lib/runtime_native/240_tcp.oren` (`oren_fd_wait_*` park the G and rely on the scheduler netpoller instead of poll+sleep)
  - Escape hatch (rolling): `OREN_NO_NETPOLL=1` disables netpoll bring-up for debugging (in-green select returns ENOSYS; avoids busy loops).
  - Guards:
    - `tests/native/test_quick_integration_native.oren` (`test_select_in_green_workers`, `test_select_multi_case_in_green_workers`)
    - `tests/native/test_net_suite.oren` (`test_fd_wait_socket_readable_in_green_workers`)

- 2026-01-16: scheduler netpoll waiting is allocation-free in steady-state:
  - the green scheduler uses a per-OS-thread scratch region for `native_netpoll_poll_many_scratch(...)` so worker idle waits do not allocate and do not drop additional ready tokens
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (per-thread scratch in `green_t`)

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
  - Scheduler topology (rolling; Stage N3 plumbing):
    - `P` count is now a real runtime parameter:
      - `oren_green_set_p_count(n)` grows the number of `P` objects before workers start (no shrink; returns `-1` once workers started).
      - `oren_green_p_count()` reports the current `P` count.
      - `oren_green_bind_p(p_id)` binds the current OS thread to a specific `P` (bring-up/testing; rejected in-green and once workers started).
      - `oren_green_current_p_id()` reports the current OS thread’s bound `P` id.
      - Host-thread ownership helpers (bring-up/testing; rejected in-green and once workers started):
        - `oren_green_acquire_p(p_id)` binds the OS thread to `p_id` and sets `P.owner_tid = sys_gettid()`
        - `oren_green_release_p()` releases the currently bound `P` and clears the thread binding
      - low-level scheduler drive hooks (host-thread only; bring-up/tests):
        - `oren_green_poll_until(deadline_ns)` drives until idle or deadline (monotonic ns).
        - `oren_green_poll_steps(n)` drives at most `n` context switches (used to seed multi-P queues deterministically).
    - The scheduler wakes sleepers **across all Ps**, not just the current thread’s bound `P`.
      - This is future-proofing for `M < P` and for global timeout-driven services (netpoller/timers) without requiring every `P` to be actively driven.
  - Worker sleeping behavior (rolling, but important for responsiveness):
    - when only sleepers exist, the worker parks on the shared park word with a timeout (so new runnable work wakes it immediately)
    - inserting new sleepers wakes workers so the “next wake” deadline is re-evaluated promptly
    - sleeper deadlines use a **monotonic** clock (`oren_time_mono_ns`) so wall-clock jumps do not break wake behavior:
      - Linux: fills `sys_gettimeofday(..., abs_ptr)` via `clock_gettime(CLOCK_MONOTONIC)` in ns
        - x64-linux note (fixed 2026-01-16): ensure the `timespec` scratch used by `clock_gettime` does not overlap the spilled `abs_ptr`
          (otherwise `abs_ptr` can be clobbered with `tv_nsec` and cause deterministic SIGSEGV under qemu and on real hosts).
          - Gate: `make verify-x64-linux-qemu`
      - macOS: converts gettimeofday’s `mach_absolute_time` out-arg using `mach_timebase_info` (num/den)
      - Windows: converts QPC ticks using `QueryPerformanceFrequency`
  - Join behavior: when workers are enabled, `oren_green_join_timeout` waits on the green task's state word via the portable
    wait-on-address primitive (instead of driving the scheduler on the joining thread).
  - P ownership (rolling correctness guard): when workers are enabled, `_green_poll_until` enforces `P.owner_tid == sys_gettid()`.
    Worker bring-up reserves each worker `P` with a negative sentinel during `oren_green_start_workers`, then the worker claims its bound `P`
    to a positive tid before entering the scheduler loop (hard-fails on mismatches).
    - Rolling safety: `oren_green_start_workers` rejects if any `P.owner_tid != 0` on entry (prevents subtle “worker aborts because P was already claimed” failures).
    - Stage N3 evolution: a worker may temporarily set `P.owner_tid = 0` while blocked (park/kevent/epoll), then re-acquire before running Oren code.
    - Stage N3 evolution: `oren_green_start_workers(n)` reserves only the first `n` Ps; extra Ps must remain free (`owner_tid==0`) for future `M < P` operation.
    - Stage N3 evolution: an explicit **idle-P pool** now exists (under the scheduler lock) so “owner_tid==0” Ps can be acquired/released without rescanning the full P list.
      - Test-only host hook: `oren_green_acquire_any_p()` (pre-workers only) for M<P bring-up and fixtures.
      - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_idle_p_pool_acquire_any`)
    - Stage N3 evolution (toward real `M < P`): workers now clear their **thread-local P binding** while parked/blocked, and on wake attempt to
      acquire **any** idle P before running Oren code (still under the scheduler lock; world-lock may further serialize execution).
      - Implementation note (important): in worker mode, `_green_poll_until` must **not** auto-rebind `P0` when the thread-local binding is cleared; it must acquire from the idle-P pool to enable `M < P` and fairness.
    - Stage N3 evolution (determinism): idle-P pool now uses a **FIFO queue** so idle Ps are acquired fairly (prevents “P2 starves forever” during M<P bring-up).
      - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` (2 workers, 3 Ps, world-lock; deterministic P swap + P2 acquisition)
	    - Stage N3 evolution (determinism): worker parking now uses **per-worker wake slots** so fixtures can wake a specific worker deterministically (instead of relying on wake-all ordering).
	      - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` (same fixture; also covers P swap deterministically)
	    - Stage N3 evolution (STW safety): worker idle waits must be bounded and/or include `oren_gc_safepoint()` polling so `oren_gc_collect()` cannot deadlock while a worker is parked (includes park-word and netpoll waits).
	    - Stage N3 evolution (STW safety): host-thread joiners must also remain safepoint-friendly in worker mode:
	      - `oren_green_join_timeout(..., timeout_ms<0)` now avoids infinite kernel sleeps and polls `oren_gc_safepoint()` while waiting.
	      - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_green_join_waiter`)

### Test-only debug API: `oren_green_debug_*` (rolling)

The native green runtime intentionally exposes a small **test/fixture-only** surface (via `@oren.keep`) under the `oren_green_debug_*` namespace.

This exists to keep Tier‑1 scheduler regressions **deterministic** (no probabilistic wake ordering) while the scheduler is still evolving.

Hard rule (rolling): these functions are **not stable ABI**. They may change/remove without compatibility promises.

**Availability / safety**

- These helpers are intended for `tests/native/*.oren` and for developer debugging only.
- Do not use them in stdlib or “user-facing” examples.
- Many helpers are meaningful only in worker mode (`oren_green_start_workers`) or only on the host thread (not in-green).
- Return codes follow the runtime convention: `0` success; negative values are “-errno style” (example: `-16` = busy); some helpers return `-1` for “unsupported/invalid”.

**Determinism helpers (fixtures)**

- `oren_green_debug_wake_worker(worker_id)` / `oren_green_debug_clear_worker_wake(worker_id)`:
  - posts (or clears) a wake token for a specific worker’s park word.
  - enables “wake worker0 only” / “wake worker1 only” style fixtures.
- `oren_green_debug_worker_tid(worker_id)`:
  - best-effort: returns the OS tid for a specific worker (indexed by the worker’s reserved `P` id).
- `oren_green_debug_idle_p_requeue(p_id)`:
  - moves an **idle** `P` to the tail of the idle‑P FIFO, to deterministically control which `P` is acquired next.
  - returns `-16` if the `P` is not idle (`owner_tid != 0`).
- `oren_green_debug_spawn_call_list_to_p(p_id, fn_obj, args_list)`:
  - allocates a runnable task and enqueues it into a specific `P`’s local runq (does not auto-wake workers).
  - used by deterministic multi-worker fixtures (P swap, `M < P` acquisition).

**Observability helpers**

- `oren_green_debug_p_owner_tid(p_id)` observes `P.owner_tid` (0=idle, negative=reserved sentinel, positive=tid).
- `oren_green_debug_worker_count()` and `oren_green_debug_workers_ready_count()` help stabilize bring-up sequencing.
- The remaining counter helpers (`oren_green_debug_idle_iters`, `*_steal_*`, `*_p_acquire_*`, `oren_green_debug_reset`) exist for lightweight regression assertions.
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (split modules: `lib/runtime_native/263_green/*.oren`)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join`)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_start_workers_does_not_reserve_extra_ps`) (includes worker-ready counter check)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_wake_while_sleepers`) (prevents “sleepers stall runnable work” regressions)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_many_tasks_bounded`) (many short tasks must complete; no hangs)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_time_mono_ns_monotonic`) (`oren_time_mono_ns` must advance)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_ctx_switch_alloc_integrity`) (worker-mode ctx-switch must not corrupt scheduler locals / allocator state)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_local_ptr_survives_yields`) (ctx-switch must preserve long-lived locals across yields)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_local_ptr_survives_yields`) (same contract under worker-mode scheduling)
- Rolling limitation (important): `_green_poll_until` defaults to the conservative mode (re-fetch per-thread scheduler state `ts`/`P` each poll iteration).
  - Cached mode exists but is opt-in only (env `OREN_GREEN_POLL_CACHE=1` / `oren_green_set_poll_cache_mode(1)`).
  - Rationale: until native backend/local preservation invariants are fully tightened across ctx switches and syscalls, caching `ts`/`P` as long-lived locals
    can surface backend bugs as corrupted pointers later dereferenced via `ptr_get` / `ptr_get_byte`.
  - Fixed flake (2026-01-16): `OREN_GREEN_POLL_CACHE=1` could SIGSEGV (rc=139) due to a join/cleanup race where a joining thread could observe DONE
    (via ulock/futex mismatch wakeups) and `munmap` the green stack while the task was still executing on it.
    - Fix: introduce an internal EXITING state so tasks switch back to the scheduler before DONE is published and joiners are woken.
    - Runtime: `lib/runtime_native/263_green_tasks.oren` (`__oren_green_entry`, `_green_poll_until_budget`)
  - Rolling limitation (important): worker parallelism is currently clamped to 1 by default, because the native allocator/GC
  are not concurrency-correct yet. Opt-in for experimentation only: `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`.
  - Safer experimentation mode (rolling): enable a world-lock so `oren_green_start_workers(n>1)` can run while still enforcing
    “only one OS thread executes Oren code at a time”:
    - runtime knob: `oren_green_set_world_lock_mode(1)` (must be called before workers start)
    - env knob (alternative): `OREN_GREEN_WORKERS_WORLD_LOCK=1`
    - guard: `tests/native/test_green_two_workers_world_lock_smoke.oren`
    - Implementation note (fact, rolling): the world lock is held in `_green_poll_until_budget` across the scheduler loop + one green task execution,
      and is released before blocking waits (kevent/epoll, park-word wait, nanosleep) so other workers can still drive netpoll/timers while this worker blocks.
      - Lock ordering invariant: scheduler lock (`_green_lock_*`) is acquired before the world lock to avoid deadlocks.

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
- `Context` blob + `oren_ctx_switch` intrinsic (x86_64)
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
