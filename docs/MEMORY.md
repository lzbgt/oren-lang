# Memory Model

**Last updated:** 2026-01-16

Oren’s native backend is **syscall-first** and **libc-free**. Memory management is designed so long-running programs do not grow memory unboundedly (no “leak by design”), while still supporting a deterministic/manual lane.

This doc is rolling: it records what the code does today and the constraints that fall out of that.

## Modes
- **Auto-managed (default)**: allocations are tracked and reclaimed via a conservative mark/sweep collector (`native_gc_collect()`).
- **Deterministic/Manual**: set `--no-gc` / `OREN_NO_GC=1` to disable GC scanning/collection. You still can explicitly release memory via `free(ptr)` (returns blocks to the reuse pool). This is the intended path for targets where pauses aren’t acceptable.

## What is managed
- In the native backend, heap allocations are performed by the compiler’s intrinsic `malloc(...)`, implemented directly on top of OS syscalls (not `libc malloc`).
- Runtime objects (strings/lists/maps/structs/function-closures) are tracked by the native runtime so GC can traverse container graphs and reuse freed blocks.
- **Runtime metadata** (globals storage, thread-list nodes, root-list nodes) is allocated with `malloc_raw(...)` so it is not subject to GC (prevents GC from reclaiming internal runtime bookkeeping).

Rolling detail (native GC correctness):

- Struct allocations tagged as kind=STRUCT are scanned **conservatively**:
  - every 8-byte slot in the allocation payload is treated as a potential pointer and marked if it refers to a tracked allocation
  - there is no type descriptor yet, so this is correctness-first (it can visit many non-pointers, but they fast-skip via alloc-index miss)
- The mark phase honors the mark bit to avoid infinite recursion on cyclic container graphs.

## Roots & collection
- The collector is cooperative: call `native_gc_collect()` at safe points to reclaim unreachable tracked allocations.
- Roots are for “stable address” slots used by the runtime/compiler; user code should not normally need to manipulate roots directly in v0.
- Result selection (`oren_set_result`) pins the selected value as a GC root in native, mirroring the C backend “tooling surface” contract.

## Disabling GC
- Builds can disable GC scanning by defining `OREN_NO_GC` (or passing `--no-gc` to the CLI). Stack scanning and mark/sweep become no-ops.
- Manual reclamation still works: `free(ptr)` removes the allocation from the tracked set and returns it to the reuse pool (so long-running programs can stay bounded even with GC disabled).

## Thread Safety
### C backend

- List/map operations in the C runtime take a coarse mutex, so concurrent reads/writes across threads are serialized.

### Native backend (important nuance)

Today, the native backend supports a **shared-address-space** concurrency substrate on POSIX via
**green tasks** (single OS thread, cooperative scheduling):

- Default (rolling): `spawn` on macOS/Linux prefers **in-process green tasks** (shared heap, no `fork`).
  - Escape hatch: set `OREN_NO_GREEN=1` to force the legacy **fork+pipe** path.
- In green-task mode, all tasks share one heap in one process:
  - this avoids the “locks don’t synchronize after fork” trap
  - it is required groundwork for a real OS-thread scheduler and a thread-safe GC story

Important remaining nuance:

- Green tasks today are **N:1** (one OS thread), so they do not introduce parallel data races yet.
- The runtime is still evolving toward **true OS threads** + **M:N scheduling**; once multiple OS threads
  exist, GC, allocator metadata, and shared runtime structures must be made concurrency-correct.

Rolling status (fact):

- macOS now has a **syscall-first OS-thread substrate** (bsdthread_register + bsdthread_create/terminate) as groundwork for Stage N2,
  but it is **not** the default `spawn` path yet (language `spawn` still defaults to green tasks unless explicitly overridden).
  - Darwin substrate: `lib/runtime_native/264_darwin_os_threads.oren`
  - Shared scheduler-facing OS-thread (“M”) abstraction: `lib/runtime_native/269_os_thread_m.oren`
- Linux now has a **syscall-first OS-thread substrate** (clone wrapper + futex join) as groundwork for Stage N2,
  but it is **not** the default `spawn` path yet (language `spawn` still defaults to green tasks unless explicitly overridden).
  - Linux clone(2) substrate: `lib/runtime_native/266_linux_os_threads.oren`
  - Shared scheduler-facing OS-thread (“M”) abstraction: `lib/runtime_native/269_os_thread_m.oren`
- 2026-01-15: the native runtime gained a minimal **stop-the-world GC safepoint protocol** so manual collection is no longer “single-thread only”:
  - Collector: `oren_gc_collect()` requests STW, runs `native_gc_collect()`, then releases.
  - Mutators: `oren_gc_safepoint()` checks the STW state and **parks** the OS thread when requested.
  - GC stack scanning uses the thread node’s `saved_sp` field to scan parked threads safely.
  - Current-thread stack selection for **OS threads** uses `sys_gettid()` identity (not an SP/top heuristic), avoiding adjacent-stack misidentification crashes.
  - Guard: `tests/native/test_gc_stw_os_thread_collect.oren` (object reachable only from parked thread’s stack must survive).
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_os_thread_join_waiter`) (STW GC must not deadlock while another OS thread is blocked in `oren_os_thread_join_timeout(..., timeout_us=0)`).
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_wait_for_exited_os_threads_win`) (Windows: exited OS threads must be marked DEAD on exit so STW does not wait for them).
  - Rolling constraint: any runtime path that can block in a kernel wait must either be bounded or poll `oren_gc_safepoint()` periodically, otherwise STW can deadlock.

Practical consequence:

- As soon as true OS threads are introduced, runtime bookkeeping allocations that were “safe enough” under single-threaded execution
  must be made thread-safe (or moved to syscall-first allocations). For example, the native thread registration list node is allocated
  via `mmap` so it does not depend on any allocator-internal locks that are not yet OS-thread safe.

This is one reason OS-thread + scheduler work (and a coherent thread-safe GC model) is considered P0 for scaling compilation and agentic workloads.

## Limitations & next steps
- Native backend participates in the same *tracked-heap + mark/sweep* approach as the C backend:
  - allocations are registered in a tracking list
  - collection is conservative (stack scan + optional registered roots)
  - collection is explicit today (`native_gc_collect()`), and higher-level safepoints can be added later
- The deterministic/manual lane is available on native too:
  - compile with `--no-gc` to make GC scanning/collection a no-op by default
  - runtime override: `OREN_NO_GC=1` disables scanning/collection (useful for production rollouts)
- Collection locking is coarse today; per-object locking or lock-free structures plus a concurrency-compatible GC/safepoint story are still needed.
- The collector is stop-the-world and can be invoked manually today; in multi-threaded programs it currently relies on **cooperative safepoints**
  (threads must reach `oren_gc_safepoint()` in bounded time). Automatic triggers exist in limited form and still default to single-OS-thread mode.
