# Syscall-First Native Runtime Plan (No C Shims)

**Status:** Active plan (documented for later reference)  
**Last updated:** 2025-12-17  
**Repo:** `compiler-mini` (Oren)

## 0. Summary (What We Are Doing)

We will evolve the **native backend runtime** to be **syscall-first** and **independent of libc/pthreads/malloc** for core runtime services, **without taking a temporary “C shim dylib” route**.

The plan avoids future “rip-and-replace” by:

- Establishing a stable **internal OS boundary** (`sys_*`) used by the native runtime.
- Implementing **OS-specific syscall layers** for **macOS (Darwin/arm64)** and **Linux (arm64)** in parallel.
- Building higher-level primitives (allocator, locks, threads, channels) **on top of** the syscall layer.
- Migrating existing runtime code incrementally behind stable APIs, with continuous tests.

This is aligned with the “correct architecture first” constraint: **no temporary C shims** that would later be rewritten out.

## 1. Current Reality (As of 2025-12-16)

- Native backend injects `lib/runtime_native.oren` into programs.
- The native backend treats `sys_*` calls as **compiler intrinsics** and emits syscalls inline (Darwin arm64 on macOS; Linux arm64 is separate work).
  - The `sys_*` functions remain as stubs in source so programs typecheck, but native code does not call those stubs.
- `oren_system()` is now syscall-first on macOS: `fork + execve("/bin/sh", ...) + wait4`.
- ENV is syscall-free (no libc): the entry stub captures `envp` and stores it in the runtime globals, and `oren_getenv(key)` scans the initial `envp` block (bounded; never hangs).
- TIME is now syscall-first (no libc): `sys_nanosleep(ns)` is implemented as a native-backend intrinsic:
  - macOS: sleeps via `kqueue + kevent(timeout)`
  - Linux: sleeps via `__NR_nanosleep`

- FS is now progressively syscall-first with capsule enforcement at the raw `sys_*` boundary (no bypass):
  - `sys_open`, `sys_unlink`, `sys_rename`, `sys_mkdir`, `sys_access`, `sys_rmdir`, `sys_stat`, `sys_lstat`, `sys_fstat`, `sys_getdirentries64`
  - **macOS arm64 note:** `sys_stat` uses `stat64` (338). The legacy `stat` syscall number (188) can return success but not populate the expected 64-bit fields in our usage; the curated test suite locks this down.
- `spawn`/`oren_join` on macOS is currently implemented as **fork + pipe** (process-based) for v0 correctness.
  - This avoids the Darwin `bsdthread_register/bsdthread_create` ABI surface until a robust syscall-first thread design is implemented.
- Darwin fork ABI nuance is now accounted for:
  - kernel returns `X0=child_pid` in both parent/child and `X1=0(parent)/1(child)`
  - the runtime-facing `sys_fork()` intrinsic returns POSIX semantics (`0` in child).

## 2. Decisions (Hard Constraints)

### D1: No “C shim dylib” path

We will not introduce a “pthread/malloc shim” as an intermediate step, to avoid a predictable future rewrite.

### D2: Syscall-first OS boundary

All OS interactions in the native runtime must go through a small, explicit `sys_*` interface. No direct calls to:

- libc allocation (malloc/free)
- pthread mutex/cond
- stdio FILE APIs

### D3: Implement macOS + Linux in parallel

We target both:

- **macOS arm64** (primary dev machine)
- **Linux arm64** (verified via QEMU host: `blu@qemu-blu.localc`)

### D4: ABI can be refactored for best architecture/efficiency

We accept internal ABI refactors (within the Oren runtime/compiler repo) as needed for correctness and performance.
Public language syntax should remain stable where possible; internal runtime ABI can evolve.

## 3. Design Goals / Non-Goals

### Goals

- **Correctness**: no UB from opaque C ABI objects (e.g. `pthread_mutex_t`) because we won’t use them.
- **Portability**: same runtime semantics across macOS/Linux where possible.
- **Efficiency**: blocking primitives must be parking-based (futex/ulock), not spinning.
- **Composability**: primitives should support channels + future coroutine scheduler.
- **Testability**: every layer has direct tests; Linux tests runnable under QEMU.

### Non-goals (for the initial milestones)

- A perfect “no dynamic loader dependencies” story on macOS (Darwin has platform constraints).
- Full precise GC with stack maps (planned later).
- Full Linux dynamic linking/FFI (separate roadmap track).

## 4. The Architecture (Layers)

### Layer L0: Compiler + codegen (unchanged externally)

- Codegen continues to call stable runtime entry points like `oren_*`.
- Native backend continues to inject `lib/runtime_native.oren` (but it can be refactored internally).

### Layer L1: Runtime services (`oren_*`)

Examples:

- heap allocation API (`oren_alloc_*`)
- thread management (`oren_spawn`, `oren_join`)
- channels, atomics, time
- file I/O helpers (`oren_read_bytes`, `oren_write_bytes`)

**Rule:** `oren_*` must be OS-agnostic and must not call libc/pthread.

### Layer L2: OS boundary (`sys_*`)

This is the only layer allowed to touch OS ABI.

**Rule:** all OS-specific differences live here.

### Layer L3: OS implementations (per target)

- Linux arm64: syscall ABI, futex, clone, mmap, openat/read/write/close, nanosleep
- macOS arm64: Darwin/Mach primitives (e.g., ulock-style parking) and Darwin syscalls as applicable

## 5. The `sys_*` Interface (Proposed)

This list is intentionally small and “kernel-shaped”. Naming can change, but the roles should not.

### Files / IO

- `sys_open(path_ptr, flags, mode) -> fd_or_neg_errno`
- `sys_close(fd) -> 0_or_neg_errno`
- `sys_read(fd, buf_ptr, len) -> nread_or_neg_errno`
- `sys_write(fd, buf_ptr, len) -> nwritten_or_neg_errno`

For minimalism we can implement `sys_openat` only (Linux) and wrap.

### Memory

- `sys_mmap(addr, len, prot, flags, fd, off) -> ptr_or_neg_errno`
- `sys_munmap(ptr, len) -> 0_or_neg_errno`
- (optional) `sys_mprotect(ptr, len, prot)`

### Threads

- `sys_thread_create(entry_ptr, arg_ptr) -> handle_or_neg_errno`
- `sys_thread_join(handle) -> ret_or_neg_errno`
- `sys_thread_self() -> tid_token`

### Parking (blocking primitive base)

- `sys_park(addr_ptr, expected, timeout_ns) -> 0_or_neg_errno`
- `sys_wake(addr_ptr, count) -> nwoken_or_neg_errno`

Linux implementation maps to `futex(FUTEX_WAIT/FUTEX_WAKE)`.
macOS implementation maps to `ulock_wait/ulock_wake` (or equivalent Darwin primitive).

### Time

- `sys_nanosleep(ns) -> 0_or_neg_errno`
- `sys_gettimeofday(tv_ptr, tz_ptr, abs_ptr) -> 0_or_neg_errno`
  - macOS: syscall provides a 3rd out-param `mach_absolute_time` (usable as monotonic raw time).
  - Linux: syscall has no abs out-param; pass `abs_ptr=0`.

## 6. Milestones (ABCDE as Deliverables on This Architecture)

### A) Byte-accurate I/O (binary-safe)

Add runtime API:

- `oren_read_bytes(path) -> list<int 0..255>`

This is required for:

- `.obc` bytecode loading
- any binary formats

**Correctness requirement:** embedded `0x00` bytes must roundtrip.

### B) Syscall layer implemented (macOS + Linux)

Replace stubs in `sys_*` with working OS implementations.

### C) Blocking primitives (no busy-spin)

Implement mutex/cond-like behavior on top of `sys_park/sys_wake`.

### D) Coroutines / scheduler readiness

Once blocking exists, we can build:

- channels with proper blocking semantics
- future M:N scheduler primitives

(Coroutine semantics can still be compiler-driven; the runtime must support parking/wakeup.)

### E) GC + threads hardening

Ensure:

- threads are registered/scanned correctly
- safepoints do not hang
- stress tests pass on both macOS and Linux

## 7. Testing & Verification

### Local (macOS)

- Use `make test` as the baseline continuous suite.
- Add targeted tests for each new primitive:
  - binary I/O test that includes `0x00`
  - channel blocking test (no spin)
  - spawn/join stress

### Linux under QEMU (trusted host)

Linux arm64 validation host:

- SSH: `blu@qemu-blu.localc`

Baseline approach:

1) Build the stage1 compiler (`./oren`) on macOS (already works).
2) Run Linux-native backend builds/tests on the QEMU host:
   - `./oren build ... --backend native --target linux ...`
3) Execute resulting ELF binaries on QEMU host.

We should maintain:

- a small script (optional) to run the native Linux test subset remotely
- a stable “smoke list” of tests that exercise syscalls + allocator + futex

## 8. Risk Register (Known Hard Parts)

- **macOS syscall surface**: Darwin is less straightforward than Linux. We must pick stable primitives (e.g., ulock) and keep the `sys_*` layer thin.
- **Thread join**: without pthreads, joining needs a design (shared state + park/wake).
- **Allocator correctness**: mmap-based allocator must integrate with GC tracking/marking.
- **GC + multi-thread**: stop-the-world coordination must not deadlock and must avoid scanning invalid stacks.

## 9. Acceptance Criteria (“Independent”)

We consider the native runtime “independent” when:

- Native backend output does not import:
  - `pthread_*`
  - `malloc/free`
  - libc stdio file APIs
- Core runtime behavior (threads, locks, I/O, allocation, channels) is implemented via:
  - `sys_*` kernel-shaped primitives
  - pure runtime code in `.oren`
- `make test` passes on macOS and the Linux syscall-dependent tests pass on QEMU host.
