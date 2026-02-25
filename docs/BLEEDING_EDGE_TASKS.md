# Bleeding-Edge Goals + Derived Tasks

**Last updated:** 2026-02-26

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
- New: alloc_churn is back within the 8× gate after default-on loop list reuse; keep monitoring for regressions.
- Reweight: runtime robustness + tagged-value convergence are now explicit W5 blockers; perf work must preserve correctness.
- Reweight: regression gate integrity (AVM build + parity tags) is promoted to W4 because it blocks W5 progress when broken.

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-02-26): `alloc_churn` 6.28× C, `alloc_drop` 2.36× C.
   - New: latest snapshot keeps alloc_churn within the 8× gate; reuse is default-on with escape/alias guardrails.
   - Trace: alloc_churn alloc-site median counts show list_int_header=20000 and list_buf/list_int_buf=0 (native-only trace, 2026-02-25).
   - Trace: list_alloc shows list_int headers sized at 32 bytes (cap=0, arena mode) with no list_buf events even when enabled; investigate reserve/fast-path behavior (2026-02-25).
   - Trace: optimizer inserts `oren_list_int_reserve(xs, 128)` for alloc_churn (`OREN_TRACE_LIST_RESERVE=1`, 2026-02-26).
   - Trace: combined runtime trace still shows only list_int header allocs (size=32, mode=2) and no list_buf events; reserve trace did not appear in that build log (2026-02-26).
   - Trace: manual no-cache build confirms `list_int_reserve(xs, 128)` insertion for alloc_churn (`bench_alloc_churn_manual_build_20260226_001017.log`).
   - Trace: bench run with no-cache env still shows no list_buf events and no reserve trace in build logs (2026-02-26).
   - Trace: list_alloc + arena trace (arm64, 2026-02-26) shows list_int headers with `mode=2` (arena ctor) but
     `OREN_TRACE_ARENA=1` reports `allocs=0`, suggesting arena allocs are spilling to malloc or trace enable is late
     (log: `build/logs/alloc_churn_manual_run_list_alloc_arena_20260226_002922.log`).
   - New: `OREN_TRACE_ARENA_SPILL=1` reports spill reasons (depth=0, size<=0, cap, mmap failure) to explain
     `mode=2` list allocations with `allocs=0` (rolling, 2026-02-26).
   - Trace: native build (runtime cache disabled) shows arena allocs=3, no spills; prior `allocs=0` was from
     a non-native build artifact (log: `build/logs/alloc_churn_manual_run_arena_spill_native_20260226_003939.log`).
   - New: `OREN_TRACE_NATIVE_LIST_RESERVE=1` inserts a fast-loop trace call to verify runtime reserve execution
     (rolling, 2026-02-26).
   - New: list buffer trace now re-checks envp/argv/argc to avoid caching off before runtime init
     (rolling, 2026-02-26).
   - Trace: alloc_churn native run with fast-loop reserve tracing shows list<int> reserve executes
     and allocates 1024-byte buffers via `_list_alloc_buf` (log: `build/logs/alloc_churn_manual_run_trace_reserve_fast2_20260226_004803.log`).
   - Trace: runtime reserve trace `OREN_TRACE_LIST_RESERVE_RT=1` shows stage=1/2 pairs per list and
     `[list_buf]` allocations; no duplicate stage=1 per list (log: `build/logs/alloc_churn_run_trace_20260226_013845.log`).
     The earlier “redundant reserve call” suspicion is cleared for this run; keep watching in future traces.
   - New: alloc-site tracing now counts arena list buffers; alloc_churn shows list_int_buf=20000 and
     list_int_header=20000 (total=40000) in native runs with `OREN_BENCH_TRACE_ALLOC_SITE=1`
     (log: `build/logs/bench_alloc_churn_alloc_site_20260225_234114.log`).
   - New: `OREN_TRACE_LIST_RESERVE_BYTES=1` reports reserve allocation/copy totals at shutdown:
     alloc_churn shows list_int_alloc_bytes=20480000 with 20000 reserve calls and zero copy bytes
     (log: `build/logs/alloc_churn_run_reserve_bytes_20260226_020050.log`).
   - New: loop list reuse cuts alloc_churn to ~6.28× C (arm64, 2026-02-26),
     within the 8× gate; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`
     (log: `benchmarks/results/alloc_churn_darwin_arm64_20260226_023800.md`).
   - New: loop list reuse keeps alloc_drop at ~2.36× C (arm64, 2026-02-26),
     within the 5× gate (log: `benchmarks/results/alloc_drop_darwin_arm64_20260226_023803.md`).
   - New: reuse escape smoke (`test_loop_list_reuse_escape_smoke`) added to native quick integration
     to catch incorrect reuse when lists escape (2026-02-26).
   - Fix: loop list reuse now skips unsafe list uses (escape/alias), enabling default-on reuse
     while remaining correctness-safe under `test_loop_list_reuse_escape_smoke` (2026-02-26).
   - Fix: loop list reset now requires first-assign dominance in the loop body, avoiding auto-arena
     on use-before-assign patterns (`test_arena_auto_loop_use_before_assign_skip_smoke`, 2026-02-26).
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
   - New: x64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-26).
   - Gate: no header corruption under `alloc_churn`/`alloc_drop` with reuse disabled; reuse remains guarded.

3) **W5 perf parity: hot loops (loop_sum, dot_product)**
   - Close native gap vs C and keep cross-backend semantics aligned.
    - New: loop_sum init/steady split instrumentation via `OREN_BENCH_INIT_SPLIT=1`.
      - Latest split (2026-02-26, n=20,000,000): native steady ~0.224922s vs C ~0.067377s (≈3.34× steady-state).
    - New: defer capsule-only NET/PROC tables to `native_runtime_capsule_init` to reduce non-capsule runtime init cost; remeasure init/steady split (2026-02-25).
    - Measured: native init 0.002592s, steady 0.223975s (arm64 macOS, 2026-02-26).
   - Reduce GC safepoint overhead in alloc-free hot loops (inline tick + higher masks where safe).
   - New: x64 boxed-list fast loops (push/get-sum/dot) now throttle safepoints at mask=1023; re-check perf gates.
   - Gate: `loop_sum` + `dot_product` native <= 2x C on Tier-1.

4) **W5 tagged value convergence plan (native/C/AVM)**
   - One canonical model + staged migration.
   - Fix: native stringy inference no longer treats empty list literals as list<string> (avoids strcmp on list pointers; restores list equality semantics, 2026-02-26).
   - Gate: fixtures across all backends.

5) **Cross-backend parity gates**
   - Expand fixtures where gaps remain; keep C/native/OBC output aligned.
   - Arithmetic panic parity now covers `div0`, `div_overflow`, `mod0`, `mod_overflow`, and `shift_oob` (shl/shr).
   - Index panic parity covers negative list index assignment + list get out-of-bounds + non-container index get + unsupported map key get/set.
   - Gate: parity scripts + `make test` remain green.

6) **Deterministic schedulers (native + AVM)**
   - Budgeted execution and GC-safe scheduling.
   - New: `test_green_global_runq_fairness` returned -60 once during `make test` on 2026-02-26; rerun passed.
     Treat as a potential flake and investigate fairness/timeout robustness before tightening gates.
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
   - Fix AVM build breaks that block `make verify-backend-parity-tags` (select case parsing + helper visibility + headers).
   - Gate: `make test`, `make benchmarks`, and snapshot updates are deterministic.

---

When a task is completed or re-scoped, update `docs/STATUS.md` and the relevant
fixtures/tests to keep the rolling truth accurate.
