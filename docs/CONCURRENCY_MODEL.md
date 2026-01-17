# Oren Concurrency & IPC Model (Rolling)

This doc describes:

- what exists today (facts, grounded in code), and
- what the intended direction is (design, tracked in `docs/TODOS.md`).

Oren is rolling; compatibility is not the priority. Accuracy is.

**Last updated:** 2026-01-17

## 1) Core primitives (current reality)

### 1. `spawn` + `join` (today: platform-specific substrate)

`spawn` exists in the language surface today, but it is **not yet** a unified “lightweight task” abstraction.

Current native backend behavior (rolling, fact):

- **macOS/Linux (POSIX v0 → Stage N1):** `spawn` prefers **in-process green tasks** (**N:1**, one OS thread).
  - This is shared-address-space concurrency (required groundwork for any coherent GC/locks story).
  - Escape hatch: set `OREN_NO_GREEN=1` to force the legacy **fork + pipe** fallback.
  - Fork+pipe semantics (fallback):
    - the child computes the return value, writes 8 bytes to the pipe, and exits
    - the parent joins by reading those 8 bytes and reaping the child
- **Windows x64 Tier‑1:** `spawn` is implemented as **CreateThread** (OS threads) via the native runtime helper (`oren_spawn_call_list`).
  - The join handle wraps a runtime-owned OS-thread handle (backed by a Win32 HANDLE) and a result pointer (see `lib/runtime_native/260_threads.oren`, `lib/runtime_native/269_os_thread_m.oren`).

Additional substrate (not wired into `spawn` yet):

- **Linux syscall-first OS threads:** a minimal clone(2) wrapper + CLONE_CHILD_CLEARTID join exists as Stage N2 groundwork
  (see `lib/runtime_native/266_linux_os_threads.oren`). This will be used by the upcoming N:M scheduler, not by v0 `spawn`.
- **Green-task background workers (Stage N2 groundwork):** the green scheduler can optionally run on background OS threads via:
  - `oren_green_start_workers(n)` (runtime: `lib/runtime_native/263_green_tasks.oren`)
  - This is not a full GMP/netpoller yet (no true async IO), but it is the “M” substrate needed to move beyond N:1.
  - Guardrail (rolling): `oren_green_start_workers` must be called from a host thread (not while executing a green task), otherwise it returns `-1`.
  - Rolling Stage N3 plumbing: `P` count is now configurable before workers start:
    - `oren_green_set_p_count(n)` grows scheduler `P` objects (no shrink; rejected once workers started).
    - `oren_green_p_count()` reports the current `P` count.
    - `oren_green_bind_p(p_id)` re-binds the current OS thread to a specific `P` (bring-up/testing; rejected in-green and once workers started).
    - `oren_green_current_p_id()` reports the current thread’s bound `P` id (diagnostic/fixtures).
    - Low-level host-thread scheduler drive hooks (bring-up/tests; rejected once workers started):
      - `oren_green_poll_until(deadline_ns)` drives the scheduler until idle or deadline.
      - `oren_green_poll_steps(n)` drives at most `n` context switches (used for deterministic fixtures).

### 1.2 Wait-on-address (`sys_ulock_wait/sys_ulock_wake`) (portable lock/park substrate)

The native runtime treats `sys_ulock_wait` / `sys_ulock_wake` as a *portable* “wait on memory address” primitive.

Facts (rolling, verified by tests):

- **macOS:** lowers to the ulock syscalls (`ulock_wait` / `ulock_wake`).
- **Linux:** lowers to `futex(FUTEX_WAIT_PRIVATE/FUTEX_WAKE_PRIVATE)`.
  - Timeout behavior is normalized to Oren’s portable `-60` timeout code (Darwin ETIMEDOUT),
    even though Linux futex uses `-ETIMEDOUT` (`-110`) as the raw errno.
- **Windows:** lowers to `WaitOnAddress` / `WakeByAddressAll` (KERNELBASE import).
- **Oren-level semantics (portable API):** `oren_wait_on_addr(addr, expected, timeout_us)` is “wait while equal”.
  - If `*addr != expected`, it returns `0` immediately (no blocking).
  - If the underlying primitive reports a value mismatch/spurious wake (e.g. Linux futex `-EAGAIN`), it is normalized to `0`
    because callers are structured as “check → wait → retry”.
  - Green-task nuance (rolling, 2026-01-17): when called from inside a green task, the runtime must not kernel-block the scheduler OS thread
    in the wait-on-address primitive (either forever or with bounded timeout).
    - Current implementation: parks the current `G` on a scheduler-owned “word wait” list and wakes it via `oren_wake_all_addr(addr)`
      (wake-driven; no polling; timeouts return portable `-60`).
    - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_in_green_does_not_block_scheduler`)
    - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_timeout_in_green_does_not_block_scheduler`)

Why this matters:

- This is the basic building block for:
  - parking/unparking idle scheduler threads (`M`), and
  - non-busy-wait locks in a libc-free runtime.

Source of truth / guards:

- Runtime wrapper (portable API): `lib/runtime_native/267_wait_on_addr.oren` (`oren_wait_on_addr`, `oren_wake_all_addr`)
- OS-thread (M) substrate uses the wait-on-address primitive for parking (no busy spin):
  - `lib/runtime_native/269_os_thread_m.oren` (`oren_m_park_word_wait`, `oren_m_park_word_wake`, `oren_os_thread_spawn`, `oren_os_thread_join_timeout`)
- Portable timeout smoke: `tests/native/test_ulock_timeout_portable.oren` (expects `-60`, skips `-38`/ENOSYS)
- Linux timeout normalization smoke: `tests/native/test_ulock_timeout_linux.oren` (skips on non-Linux; asserts `-110` normalizes to `-60`)
- OS-thread substrate smokes:
  - `tests/native/test_os_thread_park_unpark_smoke.oren` (macOS/Linux/Windows; park/unpark + bounded join)
  - `tests/native/test_os_thread_spawn_many_smoke.oren` (macOS/Linux/Windows; spawn/join-many bounded stress)
- Tier-1 lock handshake: `tests/fixtures/tier1_native_spawn_join_main.oren`
  - Quick integration regression: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_mismatch_is_success`)

Implementation guardrails (native backend contributors):

- The native runtime “rtobj” cache stores compiled machine code for the injected runtime. If native codegen changes (ABI layout,
  syscall lowering, instruction encoding), bump the backend signature in `lib/compiler/native_runtime_obj_cache.oren` or you can
  accidentally keep old runtime machine code alive on cache hits.
- Linux/aarch64 syscall ABI nuance: raw `clone(2)` argument order is `clone(flags, stack, ptid, tls, ctid)` (TLS and ctid are swapped
  vs x64 conventions). `sys_thread_create` lowering must follow that when using `CLONE_*TID` flags.

Implications:

- There is no **production-grade** GMP/netpoller (true async IO + channels/select across Tier‑1) in native yet.
  - However, macOS/Linux already have an early green-task scheduler + netpoll integration for pipe/socket readiness (rolling; see `docs/NATIVE_GMP_SCHEDULER.md`).
  - Windows has a correctness-first in-memory channel implementation so `oren_select` works for channels even without IOCP (see `docs/ASYNC_IO_AND_SELECT.md`).
  - Windows also has a rolling v0 socket netpoll path (WinSock `select()` over a small watched set) so green-task `oren_fd_wait_*` can be scheduler-driven, but IOCP is still the intended long-term implementation.
- A “mutex” cannot coordinate across `spawn` on POSIX v0, because forked processes do not share the address space.

Source of truth:

- POSIX fork+pipe join handle: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`
- Windows CreateThread path: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`

### 1.1 `oren_yield()` (rolling: green-yield when available; OS yield otherwise)

`oren_yield()` is the best-effort “yield” surface used by both:

- the Stage N1 green-task runtime (as a cooperative scheduler yield), and
- non-green paths (as a best-effort OS yield hint).

Current behavior (native runtime, rolling):

- If green tasks are enabled: `oren_yield()` routes to `oren_green_yield()` (scheduler yield).
- Otherwise:
  - **Linux:** calls `sched_yield(2)` via syscall-first `sys_sched_yield()`.
  - **Windows:** calls `Sleep(0)` via `sys_sched_yield()` shim.
  - **macOS:** currently a best-effort `sys_sched_yield()` (no-op on older bring-up paths).

Source of truth:

- `lib/runtime_native/262_yield.oren`
- Linux syscall numbers are repo-owned in `docs/refs/linux_*` and wired via `lib/compiler/*_abi_linux.oren`.

### 2. Channels + `oren_select` (today: data-driven, backend-shared)

Channels exist today, but their implementation is currently a bring-up substrate:

- Native channels are platform-dependent today (rolling):
  - **macOS/Linux:** pipe pairs `[rfd, wfd]` (`oren_new_channel()` returns a list)
  - **Windows:** in-memory channels (a GC-tracked struct; `oren_new_channel()` returns a pointer)
- AVM has proper channels as VM objects.
- `oren_select_recv` / `oren_select` exist as **functions** (not syntax) and have a shared encoding across AVM and native.

Source of truth:

- Native: `lib/runtime_native/010_channels_globals_consts.oren`, `lib/runtime_native/011_channels_mem.oren`, `lib/runtime_native/245_select.oren`
- AVM: `lib/avm/avm_vm.c` opcodes `SELECT_RECV` / `SELECT`
- Docs: `docs/ASYNC_IO_AND_SELECT.md`

### 3. Atomics (native)

Atomics exist as native intrinsics and are the right “foundation layer” for future shared-memory concurrency:

- `atomic_add`
- `atomic_cas`

These are necessary (but not sufficient) for:

- a real native thread scheduler
- mutex/condvar/channel implementations that do not require host libc

## 2) Synchronization primitives (what is *not* true yet)

The following are *design goals* but are not implemented today as stable primitives:

- “green threads” / coroutines
- a portable, shared-memory `mutex`/`lock` that works across macOS/Linux/Windows without libc
- structured concurrency (`task_group`, cancellation propagation)
- pub/sub or multicast channels
- data-parallel iterators (`par_map`, `par_reduce`)

## 3) Roadmap (high-level)

Implementation plan is tracked in `docs/TODOS.md` and the deeper design docs:

- `docs/NATIVE_GMP_SCHEDULER.md`
- `docs/ASYNC_IO_AND_SELECT.md`
- `docs/AVM_CONCURRENCY.md`

## 4) AVM notes

For AVM execution (interpreter-only environments), concurrency primitives must:

- support cancellation/timeouts (to stop work when a better plan exists)
- be compatible with snapshot/restore (pause and resume tasks)
- be compatible with capability gating (NET/PROC may be disabled)

See:

- `docs/AVM_SPEC_V1.md`
- `docs/AGENTIC_REQUIREMENTS.md`
