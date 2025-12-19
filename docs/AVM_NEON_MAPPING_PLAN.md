# AVM NEON Mapping Plan (arm64, No-JIT-First)

This document defines how the current **typed-buffer kernel ABI** in the C AVM (scalar fallback) evolves into **NEON-accelerated** kernels on arm64 while preserving:

- determinism (consensus safety)
- snapshot/hash stability
- rolling ABI friendliness (we can add kernels, but stable kernels must not change semantics)

Scope: macOS arm64 first, but the plan is written to also apply to Linux arm64.

## 1) Goals

1) **Keep semantics stable**: NEON is an optimization, not a semantic change.
2) **No JIT required**: acceleration is in the interpreter/runtime (C code) using intrinsics.
3) **Determinism-first**: consensus mode must not become “depends on compiler flags”.
4) **Minimal surface**: small set of kernels that unlock most ML-ish workloads.

## 2) Kernel ABI nucleus (what we freeze)

The “ABI nucleus” is the set of kernels whose **names + argument order + return convention** are intended to become stable.

Rule: in-place kernels end with `_into` and always have:

- `dst` first
- inputs next
- scalar last (if any)
- return value is `dst` (for fluent `.oren` style, but still in-place)

Examples:

- `oren_buf_add_f32_into(dst, a, b) -> dst`
- `oren_buf_mul_f32_into(dst, a, b) -> dst`
- `oren_buf_scale_f32_into(dst, a, scalar) -> dst`

Scalar reductions are *not* `_into`:

- `oren_buf_dot_f32(a, b) -> float`
- `oren_buf_reduce_sum_f32(a) -> float`

## 3) Data layout and loads/stores (must not change)

- Typed buffers are byte arrays with canonical little-endian element encoding:
  - `i32/i64`: two’s complement little-endian
  - `f32/f64`: IEEE-754 bit pattern little-endian
- NEON paths must interpret memory the same way.

Practical requirement:

- Use `memcpy` loads/stores (or unaligned-safe intrinsics) so behavior does not depend on alignment.
- Do not reinterpret pointers into `float*` / `int32_t*` unless alignment is guaranteed and verified.

## 4) Determinism rules for NEON kernels

Determinism constraints (consensus safety) apply even when NEON is enabled:

1) **No fast-math** (`-fno-fast-math`).
2) **No FP contraction / no FMA drift** (`-ffp-contract=off` + TU pragmas).
3) **Fixed evaluation order** for reductions.

Important nuance:

- Elementwise ops (`add`, `mul`, `scale`) are naturally deterministic given IEEE-754 and fixed per-element order.
- Reductions (`dot`, `reduce_sum`) are sensitive to reassociation. Even if SIMD is used, the reduction order must be fixed.

## 5) Recommended NEON strategies per kernel

### 5.1 Elementwise kernels

These are safe to SIMD as “map” operations:

- `*_add_*_into`
- `*_mul_*_into`
- `*_scale_*_into`

Strategy:

- Process `N` elements in chunks of 4 (for f32) with `float32x4_t`.
- Use a scalar tail loop for `N % 4`.
- Writes must be exact element-by-element results (no reordering).

### 5.2 Reduction kernels (dot/sum)

These are more delicate.

Strategy for `f32` reductions:

- Compute per-lane partial sums in vector registers (`float32x4_t`).
- Reduce lanes in a **fixed, explicit order** (pairwise in a deterministic sequence).
- Accumulate into a `double` scalar accumulator (already the scalar fallback policy).
- Use a scalar tail loop for remaining elements.

This yields a deterministic order that is stable across compilers and platforms *as long as* fast-math and FP contraction are disabled.

## 6) Feature gating: runtime + build-time

Runtime:

- Add a VM/global flag like `AVM_ENABLE_SIMD=1` (default off until validated).
- Consensus mode (deterministic) can force SIMD on/off depending on policy, but it must be explicit and stable.

Build-time:

- Keep AVM built with determinism flags by default.
- Add optional `AVM_SIMD_CFLAGS` when we introduce NEON intrinsics.

## 7) Testing strategy (high signal)

1) Keep a scalar reference implementation (the current code).
2) Add a SIMD-enabled build mode and run the same test suite:
   - smoke suite covers elementwise and reduction kernels
   - state-hash / snapshot-resume tests ensure determinism invariants stay true
3) For float kernels:
   - use exactly representable test constants where possible (e.g. 1.5, 0.25)
   - ensure reductions are tested (dot + reduce_sum)

## 8) What we do next (repo tasks)

1) Freeze the ABI nucleus list in `docs/AVM_SPEC_V1.md` (names + arg order + return convention).
2) Implement NEON versions behind a build flag and runtime flag.
3) Validate:
   - macOS arm64 first
   - linux/arm64 in docker/qemu later

