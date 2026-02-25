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

Priority weights (rolling, refreshed after x64 emit ops split):
- W5 items remain the top leverage path to production parity (perf + semantic + runtime robustness).
- W4/W3 follow; W3 large-file refactors are currently complete.

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-02-25): `alloc_churn` 46.65× C, `alloc_drop` 1.44× C.
   - New: latest snapshot shows a large alloc_churn regression; root-cause before re-enabling reuse paths.
   - Trace: alloc_churn alloc-site median counts show list_int_header=20000 and list_buf/list_int_buf=0 (native-only trace, 2026-02-25).
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
   - New: GC auto trace with `OREN_TRACE_NATIVE_LIST_HDR=1` completes cleanly after spilling list ptr to stack in
     the trace hook; keep this guard.
   - Instrument `malloc_k`/arena callers to log size+cap before tracking when `size` is implausible, and audit
     native codegen for size/arg clobbers when new regressions appear.
   - Expand fast-path tracing in native emitters to pinpoint header writes.
   - Gate: no header corruption under `alloc_churn`/`alloc_drop` with reuse disabled; reuse remains guarded.

3) **W5 perf parity: hot loops (loop_sum, dot_product)**
   - Close native gap vs C and keep cross-backend semantics aligned.
   - New: loop_sum init/steady split instrumentation via `OREN_BENCH_INIT_SPLIT=1`.
   - Reduce GC safepoint overhead in alloc-free hot loops (inline tick + higher masks where safe).
   - New: x64 boxed-list fast loops (push/get-sum/dot) now throttle safepoints at mask=1023; re-check perf gates.
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

9) **W3 structural/SOLID refactors (large files)**
   - Split high-churn, 2000+ line modules into focused units with clear boundaries.
   - Started: GC safepoint helpers moved to `lib/compiler/arm64_native_gc.oren`.
   - Done: `lib/compiler/arm64_native_stmt.oren` split into loop/list/runtime modules (<2000 lines each).
   - Done: `lib/compiler/transpiler.oren` split into core/analysis/C-utils/lambda modules (<2000 lines each).
   - Done: `lib/compiler/optimizer_loops.oren` split into list/arena modules (<2000 lines each).
   - Done: `lib/compiler/optimizer.oren` split into core/fold/DCE/list-int/list-reserve/TCO modules (<2000 lines each).
   - Done: `lib/runtime_native/100_time_gc_alloc.oren` split into trace/index/core modules (<2000 lines each).
   - Done: `lib/avm/main.c` split into CLI-focused modules
     (`avm_cli_util`, `avm_cli_verify`, `avm_cli_policy`, `avm_cli_fs`,
     `avm_cli_disasm`, `avm_cli_dump`) (<2000 lines each, 2026-02-25).
   - Done: `lib/avm/avm_vm.c` split into focused VM modules (`avm_vm_core`,
     `avm_vm_sched`, `avm_vm_values`, `avm_vm_list_ops`) (<2000 lines each, 2026-02-25).
   - Done: `lib/compiler/x64_native_program/060_emit_ops.oren` split into focused emit modules
     (`055_emit_ops_locals`, `056_emit_ops_match`, `057_emit_ops_while_emit`)
     (<2000 lines each, 2026-02-25).
   - Next targets: none (current non-generated sources are <2000 lines).

10) **Tooling reliability and reproducibility**
   - Keep build/test/bench workflows stable and fast.
   - Gate: `make test`, `make benchmarks`, and snapshot updates are deterministic.

---

When a task is completed or re-scoped, update `docs/STATUS.md` and the relevant
fixtures/tests to keep the rolling truth accurate.
