# Core System Plans: Type System, Syscall-First Runtime, and HPC

**Status:** Rolling (consolidated plans)
**Last updated:** 2026-02-19

This document merges and replaces the prior plan docs:

- `docs/TYPE_SYSTEM_PLAN.md`
- `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`
- `docs/HPC_SERVER_PLAN.md`

It keeps the highest-leverage requirements and phased execution notes in one coherent place.

---

## 1) Type System Plan (Rolling -> Production)

This is design guidance, not a frozen spec.

Oren today is semantically typed at runtime (tagged values), but it lacks a production-grade static
layer needed for:

- syscall-first servers (no accidental allocations or conversions)
- HPC + SIMD-friendly code (explicit widths, predictable layout)
- FFI and packet parsing (endianness and packed views)
- future self-hosting (compiler and AVM in `.oren`)

The strategy is gradual typing: keep v0 running while enabling incremental compile-time checks.

### Non-negotiables (constraints)

1) Rolling ABI / rolling language until v1 stabilizes.
2) Syscall-first native runtime (no libc shims).
3) Deterministic semantics (especially AVM and replay).
4) Casting must be cheap (compiler-lowered rewrites or intrinsics, not user calls).

### Current state (v0 reality)

- Runtime values are tagged: `nil`, `bool`, `int`, `float`, heap/object, etc.
- Many operations are dynamically typed and error on mismatch.

Type annotations exist today:

- locals: `var x: u8 = ...`
- fields: `struct H { len: u16be }`
- fn params/returns: `fn f(x: u8): u8 { ... }`

In v0 these annotations lower to boundary normalization (wrap/truncate for ints, deterministic
rounding for `f32`), giving cross-backend meaning without full static typing.

Cast sugar today:

- `u8(x)`, `i32(x)`, `f32(x)`, `bool(x)`, endian spellings like `u16be(x)`
- Lowered into deterministic casts or intrinsics (`oren_f32_round`, `oren_bool_norm`, `oren_trunc_int`)
- Native backend can inline these (no call overhead)

`oren_trunc_int(x)` semantics (v0, deterministic):

- `int` input: identity
- `float` input: truncate toward zero, then clamp special values
  - `NaN` -> `0`
  - `+inf`/overflow -> `INT64_MAX`
  - `-inf`/overflow -> `INT64_MIN`

### Target model: static when you want it

We support both:

1) Compile-time polymorphism (monomorphized generics)
2) Runtime polymorphism (trait/protocol objects)

Compile-time is for performance; runtime is for heterogeneous containers and tooling.

#### Primitive width types are language tokens

Core tokens:

- signed: `i8 i16 i32 i64 i128 isize`
- unsigned: `u8 u16 u32 u64 u128 usize`
- floats: `f32 f64`
- `bool`, `nil`, `string`, `bytes`

Endianness is a type-level wrapper, not a separate primitive kind:

- `u16be`, `u16le`, etc. are surface spellings that desugar to view/parse rules.

#### Packed structs are views (zero-copy)

For packet parsing and syscall-first networking:

- `@pack struct Header { ... }` defines a layout view
- accessors read/write from `bytes` or `ptr` without allocations

#### Traits/protocols: compile-time + runtime

We want primitives to implement traits (Eq, Ord, Hash, Add, BitAnd, ...).

Plan:

- compiler-provided blanket impls for builtins (e.g., `impl<T: Int> Add for T` as a builtin rule)
- later, full surface-level blanket impls once generics exist

Runtime trait objects (`dyn Trait`) remain optional and out of hot loops.

### Roadmap (phases)

Phase A: typed boundaries (v0 -> v0.5)

- finalize cast sugar set + semantics
- add a cast operator: `expr as u16` (desugars to builtin cast)
- emit stable type-kind metadata for annotated nodes

Phase B: gradual type checker (v0.5)

- add `oren build --typecheck` (or default later)
- validate annotated boundaries and function signatures
- treat as lint-first while rolling

Phase C: full static types + generics (v1 direction)

- type inference with explicit width tokens
- generics + constraints (traits/protocols)
- monomorphization for performance
- explicit trait objects for runtime polymorphism

### Casting rules (production intent)

- integer narrowing uses wrap/truncate unless a checked cast is used
- float narrowing `f64 -> f32` is deterministic rounding to IEEE-754 float32, then widening
- endian casts are view/parse conversions, not arithmetic casts

No separate strict-mode toggle: semantics are strict and deterministic by default.

---

## 2) Syscall-First Native Runtime Plan (No C Shims)

### Summary

We will evolve the native runtime to be syscall-first and independent of libc/pthreads/malloc
for core runtime services, without a temporary C shim path. The plan avoids future rewrite by:

- keeping a stable internal OS boundary (`sys_*`)
- implementing OS-specific syscall layers for macOS arm64 and Linux arm64 in parallel
- building higher-level primitives (allocator, locks, threads, channels) on top
- migrating runtime code incrementally behind stable APIs

### Current reality (2026-01-12 snapshot)

- Native backend injects `lib/runtime_native.oren` (non-capsule) or `lib/runtime_native_capsule.oren`.
- `sys_*` calls are compiler intrinsics; native code emits syscalls inline.
- `oren_system()` is syscall-first on macOS (fork + execve + wait4).
- ENV is syscall-free: entry stub captures `envp`, `oren_getenv(key)` scans it.
- TIME is syscall-first: `sys_nanosleep(ns)` uses kqueue+kevent on macOS, `__NR_nanosleep` on Linux.
- Parking primitive exists on Tier-1:
  - macOS: ulock syscalls
  - Linux: futex wait/wake
  - Windows x64: WaitOnAddress/WakeByAddressAll from KERNELBASE.dll
- FS is progressively syscall-first with capsule enforcement at `sys_*` boundary:
  - `sys_open`, `sys_unlink`, `sys_rename`, `sys_mkdir`, `sys_access`, `sys_rmdir`,
    `sys_stat`, `sys_lstat`, `sys_fstat`, `sys_getdirentries64`
- `spawn`/`oren_join` on macOS uses fork + pipe for v0 correctness.
- Darwin fork ABI nuance handled: kernel returns X0 child_pid and X1=0/1; `sys_fork()` returns POSIX semantics.

### Hard constraints

1) No temporary C shim dylib path.
2) All OS interaction goes through `sys_*` boundary.
3) Implement macOS and Linux in parallel.
4) Internal ABI can be refactored for correctness/perf (rolling mode).

### Architecture layers

- L0: compiler + codegen (calls `oren_*` runtime APIs)
- L1: runtime services (`oren_*`) - OS agnostic
- L2: OS boundary (`sys_*`) - raw kernel-shaped operations
- L3: OS implementations (per target)

### Proposed `sys_*` interface (kernel-shaped)

Files / IO:

- `sys_open(path_ptr, flags, mode) -> fd_or_neg_errno`
- `sys_close(fd) -> 0_or_neg_errno`
- `sys_read(fd, buf_ptr, len) -> nread_or_neg_errno`
- `sys_write(fd, buf_ptr, len) -> nwritten_or_neg_errno`

Memory:

- `sys_mmap(addr, len, prot, flags, fd, off) -> ptr_or_neg_errno`
- `sys_munmap(ptr, len) -> 0_or_neg_errno`
- (optional) `sys_mprotect(ptr, len, prot)`

Threads:

- `sys_thread_create(entry_ptr, arg_ptr) -> handle_or_neg_errno`
- `sys_thread_join(handle) -> ret_or_neg_errno`
- `sys_thread_self() -> tid_token`

Parking (blocking primitive):

- `sys_park(addr_ptr, expected, timeout_ns) -> 0_or_neg_errno`
- `sys_wake(addr_ptr, count) -> nwoken_or_neg_errno`

Time:

- `sys_nanosleep(ns) -> 0_or_neg_errno`
- `sys_gettimeofday(tv_ptr, tz_ptr, abs_ptr) -> 0_or_neg_errno`

Fcntl helpers:

- `sys_fcntl(fd, cmd, arg) -> rc_or_neg_errno` (raw)
- `sys_fcntl_getfl(fd) -> oren_flags_or_neg_errno` (portable)
- `sys_fcntl_setfl(fd, oren_flags) -> rc_or_neg_errno` (portable)

### Milestones

A) Byte-accurate I/O (binary-safe)

- `oren_read_bytes(path) -> list<int 0..255>` must roundtrip embedded `0x00`

B) Syscall layer implemented (macOS + Linux)

C) Blocking primitives (no busy-spin)

D) Coroutine/scheduler readiness (channels + proper blocking)

E) GC + threads hardening (safepoints, stop-the-world, stress tests)

### Testing and verification

Local:

- `make test` baseline suite
- targeted tests for each primitive (binary I/O, channel blocking, spawn/join)

Linux arm64 under QEMU:

- build on macOS and execute ELF on QEMU host
- maintain a small smoke list for syscalls + allocator + futex

### Risks

- macOS syscall surface complexity
- thread join design without pthreads
- allocator correctness with GC tracking
- stop-the-world coordination across threads

### Acceptance criteria

Native runtime is independent when:

- native output does not import `pthread_*`, `malloc/free`, or libc stdio APIs
- core runtime behavior is built on `sys_*` and pure `.oren` code
- `make test` passes on macOS and Linux syscall-dependent tests pass under QEMU

---

## 3) HPC / Server Requirements (Roadmap Driver)

Production-grade HPC on servers needs:

- low latency + high throughput
- predictable memory and layout
- controllable concurrency
- deterministic tests and debuggable failures

### Mandatory language/compiler features

1) Explicit numeric types (width tokens)

- `u8 u16 u32 u64 u128`, `i8 i16 i32 i64 i128`, `f32 f64`, `bool`
- drive ABI/layout lowering, codegen semantics, SIMD selection

2) Efficient casting (compiler-lowered)

- cast sugar: `u8(x)`
- cast operator: `x as u8`

3) Contiguous typed buffers and views

- contiguous arrays (not boxed lists)
- zero-copy views (`ptr + len`, stride)
- fixed-size arrays for small vectors (`[N]T`)

4) Generics + traits (compile-time)

- monomorphized algorithms (`dot<T>`, `axpy<T>`, `matmul<T>`)
- constraints (`T: Float`, `T: Scalar`)

5) SIMD support (Tier-1)

- arm64 NEON (128-bit)
- x86_64 SSE2 baseline, AVX2 optional when determinism allows
- deterministic rounding and fixed reduction order

6) Concurrency (server runtime)

- OS threads for saturation
- thread pools, work queues, locks/atomics as substrate

### Immediate plan (rolling order)

1) Typecheck mode v0 (opt-in): reject invalid casts, validate typed boundaries
2) Typed buffers + views (ptr+len, stride views) aligned with deterministic AVM goals
3) SIMD hook boundary + NEON kernels with scalar fallback
4) Allocator control for large numeric buffers (aligned, arena/mmap, non-GC-scanned regions)
5) Generics + monomorphization for `std/linalg`

### Tracker

- Active priorities: `docs/TODOS.md`
- Completed work: `docs/TODOS_ARCHIVE.md`
