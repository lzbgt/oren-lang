# Bleeding-Edge Goals + Derived Tasks

**Last updated:** 2026-02-25

This doc captures the bleeding-edge feature goals (user/client + architect/designer)
and turns them into concrete task buckets. It is intentionally short and
kept in sync with `docs/STATUS.md`.

---

## As a user/client, bleeding-edge features I want

- Deterministic execution with capability-gated effects (FS/NET/PROC/ENV/TIME/RNG) across backends.
- Performance parity with C on hot loops and allocation-heavy workloads.
- Cross-backend semantic parity (C/native/OBC) with clear fixtures and regression gates.
- Portable bytecode (AVM) that runs deterministically and supports sandboxed execution.
- Tooling reliability: fast incremental builds, stable CLI, reproducible outputs.

## As a system architect/designer, bleeding-edge features I want

- Converged tagged-value representation across native/C/AVM (one model, staged migration).
- Deterministic scheduler (native + AVM) with explicit budgets and safe GC interaction.
- Allocation/GC fast paths with reuse that preserve correctness under concurrency.
- SIMD + typed-buffer kernels (arm64 + x64) wired into list<int> hot loops.
- AVM unboxed list<int> payload + lowering for dot/sum parity.

---

## Derived tasks to work on (linked to `docs/STATUS.md`)

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-02-25): `alloc_churn` 7.23× C, `alloc_drop` 2.32× C.
   - Next: keep `alloc_drop` within target while auditing other alloc/GC workloads for regressions.
   - Gate: `alloc_churn` native <= 8x C; `alloc_drop` native <= 5x C.

2) **W5 runtime robustness: GC reuse + list header integrity**
   - Root-cause list header corruption before enabling reuse paths.
   - New: list_int allocations show huge `size` at `oren_track_alloc_new` time (before header init), so track the
     corruption back to size propagation (possible 32-bit -> 64-bit zero-extend gap or bad `cap` propagation).
   - New: arm64 native `malloc_k` now preserves size across kind-eval; re-run free-list traces to confirm the
     huge-size tracking corruption is gone before re-enabling reuse.
   - New: GC auto + heavy list tracing can trigger `list_int_reserve on non-list` panic; triage whether this is a
     trace-only artifact or a real metadata corruption under GC.
   - Instrument `malloc_k`/arena callers to log size+cap before tracking when `size` is implausible, and audit
     native codegen for size/arg clobbers when new regressions appear.
   - Expand fast-path tracing in native emitters to pinpoint header writes.
   - Gate: no header corruption under `alloc_churn`/`alloc_drop` with reuse disabled; reuse remains guarded.

3) **W5 perf parity: hot loops (loop_sum, dot_product)**
   - Close native gap vs C and keep cross-backend semantics aligned.
   - New: loop_sum init/steady split instrumentation via `OREN_BENCH_INIT_SPLIT=1`.
   - Reduce GC safepoint overhead in alloc-free hot loops (inline tick + higher masks where safe).
   - Gate: `loop_sum` + `dot_product` native <= 2x C on Tier-1.

4) **W5 tagged value convergence plan (native/C/AVM)**
   - One canonical model + staged migration.
   - Gate: fixtures across all backends.

5) **Cross-backend parity gates**
   - Expand fixtures where gaps remain; keep C/native/OBC output aligned.
   - Arithmetic panic parity now covers `div0`, `div_overflow`, `mod0`, `mod_overflow`, and `shift_oob` (shl/shr).
   - Index panic parity covers negative list index assignment + list get out-of-bounds + non-container index get + unsupported map key get/set.
   - Gate: parity scripts + `make test` remain green.

6) **Deterministic schedulers (native + AVM)**
   - Budgeted execution and GC-safe scheduling.
   - Gate: deterministic fixtures + Tier-1 matrix.

7) **SIMD + typed-buffer kernels for list<int> hot paths**
   - arm64 NEON + x64 SSE2 baseline; keep scalar equivalence.
   - Gate: `dot_product_int` native <= 2x C.

8) **AVM unboxed list<int> payload + lowering**
   - Improve OBC parity for dot/sum loops.
   - Gate: list<int> fixtures + OBC perf parity.

9) **Tooling reliability and reproducibility**
   - Keep build/test/bench workflows stable and fast.
   - Gate: `make test`, `make benchmarks`, and snapshot updates are deterministic.

---

When a task is completed or re-scoped, update `docs/STATUS.md` and the relevant
fixtures/tests to keep the rolling truth accurate.
