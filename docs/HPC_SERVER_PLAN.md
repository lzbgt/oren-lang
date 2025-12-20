# Server-side HPC Requirements (Oren Roadmap Driver)

This document explains what “production-grade HPC on servers” requires from Oren.

Think: Eigen/BLAS-like workloads (matrix multiply, solvers, SIMD kernels), but running as a service:

- low latency + high throughput
- predictable memory and data layout
- controllable concurrency
- debuggable failures and deterministic tests

This is a **requirements + plan** doc; it is not a frozen spec.

## A) Mandatory language/compiler features (must-have)

### 1) Explicit numeric types (width tokens)

Required as first-class language tokens:

- integers: `u8 u16 u32 u64 u128`, `i8 i16 i32 i64 i128`
- floats: `f32 f64`
- `bool`

These must drive:

- ABI/layout lowering
- codegen semantics (esp. float narrowing)
- SIMD selection

### 2) Efficient casting (compiler-lowered)

Casting is one of the most frequent operations in HPC code.

Rules:

- casts must lower to deterministic rewrites/intrinsics (not user-level function calls)
- support both surfaces:
  - cast sugar: `u8(x)`
  - cast operator: `x as u8`

### 3) Contiguous typed buffers + views (slices/strides)

HPC requires:

- contiguous arrays (not hash/list of boxed values)
- views without copying (`ptr + len` / `ptr + len + stride`)
- fixed-size arrays for small vectors (`[N]T`)

In Oren terms (design direction):

- introduce a slice concept (`[]T`) and matrix views with stride
- make packed structs a “view over bytes” (already aligned with syscall-first parsing)

### 4) Generics + traits (compile-time) + optional runtime trait objects

Eigen-style libraries require **monomorphization**:

- generic algorithms over `T` (`dot<T>`, `axpy<T>`, `matmul<T>`)
- constraints: `T: Float` / `T: Scalar`

Runtime trait objects are optional and should not be in hot loops.

### 5) SIMD support (arm64 NEON first)

Server-side HPC on arm64 requires:

- SIMD vector types and/or intrinsics (NEON)
- feature gating and dispatch (scalar fallback + NEON fast path)
- deterministic rounding rules (especially around `f32`)

### 6) Concurrency (server runtime reality)

Production server HPC requires OS threads:

- N:M green threads can exist, but compute kernels must be able to saturate cores
- thread pools, work queues, and locks/atomics are mandatory substrate

## B) Immediate plan (rolling execution order)

This repo is rolling; priorities are driven by what blocks production libraries.

1) **Typecheck mode v0** (opt-in)
   - reject obviously invalid casts (`f32("x")`, `u8(1.0)`, etc.)
   - validate annotated function boundaries when argument/return is statically-known

2) **Typed buffers + views**
   - define a slice/view shape (ptr+len) and matrix stride view
   - keep it compatible with deterministic AVM goals (no hidden host effects)

3) **SIMD hook boundary + NEON kernels**
   - keep scalar reference kernels
   - add NEON kernels for dot/axpy where safe

4) **Allocator control for large numeric buffers**
   - aligned allocation, arena/mmap options, and “non-GC-scanned” memory region support

5) **Generics + monomorphization**
   - required for `std/linalg` to avoid duplicating for each scalar type

## C) Where the tracker lives

- The actionable prioritized tracker is: `docs/TODOS.md`
- Completed work is moved to: `docs/TODOS_ARCHIVE.md`

