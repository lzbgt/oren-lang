# Bleeding-Edge Goals + Derived Tasks

**Last updated:** 2026-03-04

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
- New: alloc_churn back within the 8× gate at 5.54× C (arm64, 2026-03-04).
- Reweight: runtime robustness + tagged-value convergence are now explicit W5 blockers; perf work must preserve correctness.
- Reweight: regression gate integrity (AVM build + parity tags) is promoted to W4 because it blocks W5 progress when broken.
- Reweight: essential language feature completeness is promoted to W4 (see `docs/LANGUAGE.md` planned features).
- Done: rtobj cache hash now reflects trace codegen flags end-to-end (alloc_req/list_hdr/list_reserve),
  including rtobj seed selection, keeping runtime tracing consistent under cache hits.
- Reweight: avoid trace-only changes unless they unblock a root-cause or a W5 gate; prioritize fixes that move
  semantic parity, runtime robustness, or perf parity metrics.

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-03-04): `alloc_churn` 5.54× C, `alloc_drop` 1.58× C.
   - New run (arm64, 2026-03-04, runs=5, warmups=1; log: `build/logs/bench_alloc_churn_drop_20260304_235146.log`):
     - alloc_churn: C 0.002886s, native 0.015997s (5.54× C).
     - alloc_drop: C 0.002986s, native 0.004703s (1.58× C).
   - Bytecode note: `oren_gc_collect()` now lowers to a no-op in the bytecode backend so alloc_churn/alloc_drop OBC builds succeed (2026-03-04).
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
   - New: loop list reuse cuts alloc_churn to ~6.62× C (arm64, 2026-02-26),
     within the 8× gate; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`
     (log: `benchmarks/results/alloc_churn_darwin_arm64_20260226_161846.md`).
   - New: loop list reuse keeps alloc_drop at ~1.28× C (arm64, 2026-02-26),
     within the 5× gate (log: `benchmarks/results/alloc_drop_darwin_arm64_20260226_161849.md`).
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
   - Done: free-node reuse now enforces canonical node headers (48 bytes + magic) and raw-node
     reuse is re-enabled with integrity guards for `malloc_raw` paths (`native_try_reuse_node`).
   - Fix: green spawn/entry now re-track args_list headers on alloc-index misses when magic+len/cap look sane (2026-03-04).
   - Repro (2026-03-04): `make verify-backend-parity` failed while building
     `tests/native/fixtures/arith_div0.oren` (C backend) with
     `gc list_int header corrupt` (log: `build/logs/arith_div0_c_build.log`).
   - Trace: `arith_div0` C-backend build flake harness (5 runs) completed cleanly
     with list header ring guardrails (logs:
     `build/logs/arith_div0_c_build_flake_20260304_152304_run1.log`,
     `build/logs/arith_div0_c_build_flake_20260304_152305_run5.log`).
   - Trace: `arith_div_overflow` C-backend build flake harness (10 runs) completed
     cleanly under list header ring guardrails (logs:
     `build/logs/arith_div_overflow_c_build_flake_20260304_152630_run1.log`,
     `build/logs/arith_div_overflow_c_build_flake_20260304_152632_run10.log`).
   - Trace: stage1 quick flake with list corruption tracing (no guardrails) segfaulted
     at run 4 (log: `build/logs/triage_stage1_flake_noguard_30_20260304_185445.log`,
     run log: `build/logs/oren_native_quick_flake_20260304_185547_run4.log`, 2026-03-04).
   - Trace: stage1 quick flake debug guardrail run (20 runs) with list corruption
     tracing + free-list ring passed cleanly (log:
     `build/logs/triage_stage1_flake_debug_trace_20260304_185657.log`, 2026-03-04).
   - Trace: stage1 quick flake with list corruption tracing + list header ring (cap 8192)
     and extended timeouts passed cleanly (log:
     `build/logs/triage_stage1_flake_ringonly_timeout_20260304_190448.log`, 2026-03-04).
   - Trace: stage1 quick flake with list corruption tracing + green spawn ring only
     passed cleanly (log:
     `build/logs/triage_stage1_flake_spawn_ringonly_20260304_191042.log`, 2026-03-04).
   - Trace: stage1 quick flake with list corruption tracing + list header ring dup guard
     (cap 8192) passed cleanly (log:
     `build/logs/triage_stage1_flake_list_ringdup_20260304_191425.log`, 2026-03-04).
   - Trace: stage1 quick flake with list corruption tracing + free-list ring passed
     cleanly (log:
     `build/logs/triage_stage1_flake_freelist_ring_20260304_191805.log`, 2026-03-04).
   - Trace: stage1 quick flake debug guardrail run (5 runs) after args_list retrack
     passed cleanly (log:
     `build/logs/triage_stage1_flake_debug_retrack_20260304_210139.log`, 2026-03-04).
   - Trace: stage1 quick flake debug guardrail run (20 runs) with jitter
     (`OREN_QI_JITTER_MAX_MS=50`) after args_list retrack passed cleanly (log:
     `build/logs/triage_stage1_flake_debug_retrack_jitter_20260304_210806.log`,
     2026-03-04).
   - Trace: stage1 quick flake with jitter (`OREN_QI_JITTER_MAX_MS=50`) and auto rerun
     guardrails hit rc=143 at run 16; auto rerun guardrails succeeded (log:
     `build/logs/triage_stage1_flake_autorun_jitter_20260304_195330.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_194557_run16.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_194557_run16_guardrails.log`,
     2026-03-04).
   - Trace: quick integration green-cache-only run with jitter
     (`OREN_QI_ONLY_GREEN_CACHE=1`, `OREN_QI_JITTER_MAX_MS=50`) completed cleanly
     (log: `build/logs/quick_integration_green_only_jitter_20260304_195118.log`,
     2026-03-04).
   - Trace: quick integration base-only run with jitter
     (`OREN_QI_SKIP_GREEN_CACHE=1`, `OREN_QI_JITTER_MAX_MS=50`) completed cleanly
     (log: `build/logs/quick_integration_base_only_jitter_20260304_195240.log`,
     2026-03-04).
   - Trace: stage1 quick flake with jitter only (`OREN_QI_JITTER_MAX_MS=50`, no list
     tracing) failed at run 12 with `assert_eq` in `test_select_in_green_workers`
     during green-cache phase (got -5, expected 777), rc=50 (log:
     `build/logs/triage_stage1_flake_jitter_notrace_20260304_195411.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_195754_run12.log`, 2026-03-04).
   - Trace: stage1 quick flake with jitter + auto rerun guardrails (no list tracing on
     base run) segfaulted at run 7 (rc=139); auto rerun guardrails succeeded (log:
     `build/logs/triage_stage1_flake_jitter_autorun_notrace_20260304_195907.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_200108_run7.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_200108_run7_guardrails.log`, 2026-03-04).
   - Trace: quick integration with green-cache first + 3 repeats and jitter
     (`OREN_QI_GREEN_CACHE_FIRST=1`, `OREN_QI_GREEN_CACHE_RUNS=3`,
     `OREN_QI_JITTER_MAX_MS=50`) completed cleanly (log:
     `build/logs/quick_integration_green_first_repeat_20260304_200604.log`,
     2026-03-04).
   - Trace: quick integration with green-cache first + 20 repeats and jitter
     (`OREN_QI_GREEN_CACHE_FIRST=1`, `OREN_QI_GREEN_CACHE_RUNS=20`,
     `OREN_QI_JITTER_MAX_MS=50`) completed cleanly (log:
     `build/logs/quick_integration_green_first_repeat20_20260304_200743.log`,
     2026-03-04).
   - Trace: stage1 quick flake with jitter + auto rerun guardrails failed at run 31
     with rc=143; auto rerun guardrails succeeded (log:
     `build/logs/triage_stage1_flake_jitter_autorun_20260304_200926.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_201937_run31.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_201937_run31_guardrails.log`,
     2026-03-04).
   - Trace: stage1 quick flake with jitter + auto rerun guardrails + green-cache-first
     hit `Indexing on non-container` in `__oren_fnwrap_worker_green_local_ptr_survives_yields`
     at run 7 (rc=1); auto rerun guardrails succeeded (log:
     `build/logs/triage_stage1_flake_jitter_autorun_greenfirst_20260304_202152.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_202353_run7.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_202353_run7_guardrails.log`, 2026-03-04).
   - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
     rerun guardrails hit rc=143 at run 27; auto rerun guardrails succeeded (log:
     `build/logs/triage_stage1_flake_greenonly_autorun_20260304_202536.log`, run log:
     `build/logs/oren_native_quick_flake_20260304_203350_run27.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_203350_run27_guardrails.log`,
     2026-03-04).
   - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
     rerun guardrails + green-cache repeats (10) hit rc=143 at run 8; guardrail rerun
     segfaulted (rc=139) (log:
     `build/logs/triage_stage1_flake_greenonly_autorun_repeat10_20260304_203557.log`,
     run log: `build/logs/oren_native_quick_flake_20260304_203927_run8.log`, guardrails log:
     `build/logs/oren_native_quick_flake_20260304_203927_run8_guardrails.log`,
     2026-03-04).
   - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
     rerun guardrails + green-cache repeats (10) hit rc=143 at run 27; guardrail rerun
     segfaulted with `green_spawn_alloc args_list untracked` in the ring dump
     (log: `build/logs/triage_stage1_flake_greenonly_autorun_repeat10_20260304_203557.log`,
     run log: `build/logs/oren_native_quick_flake_20260304_203350_run27.log`,
     guardrails log:
     `build/logs/oren_native_quick_flake_20260304_203350_run27_guardrails.log`,
     2026-03-04).
   - Repro (2026-02-26): `benchmarks/run_benchmarks.py` dot_product Oren C build panicked with
     `gc list header corrupt` (log: `build/logs/bench_build_oren_c_dot_product_20260226_145741.log`).
   - Fix: GC list header validation now accepts 16-byte aligned inline header sizes to avoid
     false corruption on small caps (2026-02-26).
   - Fix: list_reserve now attempts alloc-index recover + header re-track before panicking
     on non-list headers to reduce false positives under GC churn (2026-02-26).
   - New: free-list header dumps now include list_hdr ring traces when validation fails, to
     correlate the last header writes with corrupted free-list entries (2026-02-26).
   - Fix: host-thread green spawn/join now uses world-lock critical sections when enabled,
     preventing races in multi-worker world-lock mode (2026-02-26).
  - Fix: host metadata lookups (`oren_find_node`) now enter the world lock when workers
    are active, avoiding list/map metadata races during world-lock tests (2026-02-26).
  - New: optional list header poisoning on GC free sets magic to `list_magic_poison`
    (`OREN_GC_POISON_LIST_HEADERS=1`); reuse precheck tolerates poison while GC mark
    remains strict to surface UAF (2026-02-26).
  - Trace: poison+reuse+GC sweep run (`OREN_GC_POISON_LIST_HEADERS=1`,
    `OREN_TRACE_GC_SWEEP=1`, `OREN_TRACE_LIST_CORRUPT=1`) segfaulted quickly; first
    sweep/reuse summary emitted before crash (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_sweep.log`, 2026-02-26).
  - Trace: poison+GC sweep with list reuse disabled (blocks reuse on) still segfaulted
    (log: `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_sweep.log`, 2026-02-26).
  - Trace: poison+GC sweep with reuse blocks disabled completes cleanly (log:
    `build/logs/alloc_churn_trace_poison_noreuse_len64_gc50_200_sweep.log`, 2026-02-26).
  - New: reuse scan now drops nodes with bad `native_node_magic` and can trace via
    `OREN_TRACE_GC_REUSE_NODE_MAGIC=1` (rolling, 2026-02-26).
  - Trace: poison+reuse (list reuse off) with node-magic tracing completed cleanly; no
    bad-node-magic hits (`guard_bad_magic=0`) in summaries (log:
    `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_magic.log`, 2026-02-26).
  - Trace: repeat poison+reuse (list reuse off) with node-magic tracing also completed cleanly;
    still no bad-node-magic hits (log:
    `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_magic2.log`, 2026-02-26).
  - Trace: poison+reuse (list reuse on) with node-magic tracing segfaulted after a second sweep;
    reuse summaries show `guard_bad_magic=0` but `guard_bad_list=6` before crash (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_magic.log`, 2026-02-26).
  - Trace: poison+reuse with bad-list safe tracing timed out with repeated bad-list hits on a
    single list header (ptr `4341780128`, kind=2, cap=0); `freed_seen=0` in precheck and
    `guard_bad_list` incremented (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist.log`, 2026-02-26).
  - New: bad-list safe trace now prints header + node fields (len/cap/buf/magic + node kind/size)
    to reduce follow-up repros (rolling, 2026-02-26).
  - New: first bad-list safe print now triggers `native_list_debug_node` for alloc-index
    context (one-shot, rolling, 2026-02-26).
  - New: `native_list_debug_node` now reports membership in free-block bucket lists
    (64/256/1024/other) to disambiguate reuse corruption (rolling, 2026-02-26).
  - New: reuse scan can optionally detect nodes still present in allocs
    (`OREN_TRACE_GC_REUSE_ALLOC_NODE=1`) and counts `guard_alloc_node` in summaries (rolling, 2026-02-26).
  - New: reuse scan can detect alloc-index duplicate nodes via
    `OREN_TRACE_GC_REUSE_ALLOC_INDEX_DUP=1` and counts `guard_alloc_index_dup` (rolling, 2026-02-26).
  - New: bad-list summary now reports `guard_bad_magic`, `guard_alloc_node`, and
    `guard_alloc_index_dup` to avoid missing guard signals in trace logs (rolling, 2026-02-26).
  - Trace: poison+reuse with alloc-node/alloc-index-dup tracing still hits bad-list while
    `guard_bad_magic/guard_alloc_node/guard_alloc_index_dup` remain 0; no
    `[gc_reuse_alloc_*]` prints observed (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_allocnode_dup2.log`, 2026-02-26).
  - Trace: ring-all bad-list run (`OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1`) still shows
    `guard_bad_magic/guard_alloc_node/guard_alloc_index_dup=0` while emitting
    `list_hdr_ring idx=...` entries (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall.log`, 2026-02-26).
  - New: ring-all dumps now filter to the bad-list pointer (one-shot) via
    `native_list_header_ring_filter_set`, reducing noise in ring-all logs (rolling, 2026-02-26).
  - New: ring-all filter emits `[list_hdr_ring_filter_miss]` when no ring entries match
    the filtered pointer, signaling missing ring capture (rolling, 2026-02-26).
  - Trace: ring-all filter run (miss warning enabled) still finds a matching ring entry;
    no `[list_hdr_ring_filter_miss]` emitted (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter_miss.log`, 2026-02-26).
  - New: bad-list dumps can emit the most recent list header ops for that pointer via
    `OREN_TRACE_GC_REUSE_BAD_LIST_RING_RECENT=<n>` and `[list_hdr_ring_recent]` (rolling, 2026-02-26).
  - New: `OREN_TRACE_GC_REUSE_BAD_LIST_KIND_FLIP=1` only emits recent-op dumps when
    `node_kind` changes across bad-list hits (rolling, 2026-02-26).
  - New: `gc_reuse_summary_at_bad_list` now reports `kind_flip` when the kind-flip
    gate is active (rolling, 2026-02-26).
  - Trace: kind-flip run still emits recent-op entries (no suppression observed; node_kind
    still changes in this run) (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip.log`, 2026-02-26).
  - Trace: kind-flip summary shows `kind_flip=0`; only the first bad-list dump emits
    recent-op entries (duplicates within the dump reflect ring state, not repeated dumps)
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip2.log`, 2026-02-27).
  - Trace: ring-cap 512 run still shows `op=1` entries for the bad list pointer with the
    same recent-op sequence (`1:2`) despite larger ring history (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringcap512.log`, 2026-02-27;
    correlate:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringcap512_correlate.log`, 2026-02-27).
  - Trace: correlator delta output shows no per-hit deltas for kind-flip2 (single bad-list
    sample in correlate output) (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip2_correlate.log`, 2026-02-27).
  - Trace: multihit run (iters=500) still shows identical recent-op sequence (`1:2`);
    correlator emits a `list_hdr_ring_recent_delta` header with no deltas
    (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_multihit_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_multihit_20260227_correlate.log`,
    2026-02-27).
  - Trace: multihit run (iters=1000, ring_recent=64) still shows identical recent-op sequence (`1:2`);
    correlator emits a `list_hdr_ring_recent_delta` header with no deltas
    (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_multihit_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_multihit_20260227_correlate.log`,
    2026-02-27).
  - Trace: multihit run (iters=1000, ring_recent=128, ringcap=512) still shows identical recent-op
    sequence (`1:2`); correlator emits a `list_hdr_ring_recent_delta` header with no deltas
    (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_ringcap512_recent128_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_ringcap512_recent128_20260227_correlate.log`,
    2026-02-27).
  - Trace: pre-bad-list ring snapshot (`OREN_TRACE_GC_REUSE_BAD_LIST_RING_PRE=64`) emits
    `[list_hdr_ring_pre]` before the first bad-list print; sequence remains `1:2`
    (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_20260227_correlate.log`,
    2026-02-27).
  - Trace: pre-bad-list ring snapshot (`OREN_TRACE_GC_REUSE_BAD_LIST_RING_PRE=128`,
    `OREN_TRACE_GC_REUSE_BAD_LIST_RING_RECENT=128`) still shows the same `1:2` sequence
    (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_pre128_recent128_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_pre128_recent128_20260227_correlate.log`,
    2026-02-27).
  - Trace: pre-bad-list dump-all (filtered) still shows only `op=1 kind=2` entries for
    the bad pointer; no earlier ops appear (logs:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_dumpall_20260227.log`,
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_dumpall_20260227_correlate.log`,
    2026-02-27).
  - Tool: bad-list dumps now log `[list_hdr_ring_state]` (head/cap/delta) per trigger
    to confirm whether the ring advances between bad-list events (rolling, 2026-02-27).
  - Trace: ring state shows head did not advance between bad-list events
    (`head=357`, `delta=0`) in the 500-iter ringstate run (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringstate_20260227.log`, 2026-02-27).
  - Trace: ring-put watch (pre=64) emitted no `[list_hdr_ring_put]` lines, suggesting
    no list header trace ops for the bad pointer after the pre dump (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringput_20260227.log`, 2026-02-27).
  - Tool: GC list header poison + bad-list dumps now emit ring ops (`op=90` for poison,
    `op=91` for bad-list) via `native_list_header_ring_put_gc`; ring op filter now
    accepts these codes to surface them in dumps (rolling, 2026-02-27).
  - Tool: first list-header poison can optionally trigger a one-shot ring-all dump
    (gated by `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1`) to confirm `op=90` visibility
    in ring logs (rolling, 2026-02-27).
  - Trace: ringgc run (poison+reuse, ring ops enabled) segfaulted before emitting any
    output; run log is empty (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringgc_20260226.log`, 2026-02-27).
  - Trace: ring-all run with reduced iters emits `[gc_free_list]` + `[list_hdr_ring]`
    output and a `gc_reuse_summary` before segfault; no bad-list triggers observed
    in that log (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_100_ringall_20260227.log`, 2026-02-27).
  - Trace: ring-all run after enabling op=90/91 in ring filter shows `op=90` entries
    for poisoned list headers (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_100_ringall3_20260227.log`, 2026-02-27).
  - Trace: ringbad run (iters=300) still shows `op=90` poison entries but no
    `gc_reuse_bad_list` events before segfault (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_300_ringbad_20260227.log`, 2026-02-27).
  - Trace: precheck+ringbad run re-triggers `gc_reuse_bad_list`; ring pre/recent
    entries now show `op=91` dumps with corrupted header fields and `op=90` poison
    right before the bad-list detection (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_ringbad_20260227.log`, 2026-02-27).
  - Trace: precheck+idx run logs `gc_reuse_bad_list_idx` showing alloc-index presence
    on the first bad-list hit (idx_node set) and missing index on the second hit,
    while node kind/size flips from `1/32` to `0/48` (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idx_20260227.log`, 2026-02-27).
  - Trace: precheck+idxflip run confirms alloc-index flip detection via
    `gc_reuse_bad_list_idx_flip` for the same pointer across successive bad-list hits
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idxflip_20260227.log`,
    2026-02-27).
  - Trace: precheck+rebuild run emitted `gc_reuse_bad_list_idx_flip` but no
    `gc_reuse_bad_list_rebuild` entries (no alloc-index rebuild observed after the bad-list),
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_rebuild_20260227.log`,
    2026-02-27).
  - Trace: precheck+idxremove run hit `gc_reuse_bad_list_idx_flip` but no
    `gc_reuse_bad_list_index` events (no alloc-index tombstone/remove/insert/replace logged);
    run terminated with SIGTERM after ~189s (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idxremove_20260226.log`,
    2026-02-26).
  - Trace: precheck+scan run shows `gc_reuse_bad_list_index_scan found=0` after the second
    bad-list hit (alloc-index entry not present by full-table scan; `hash_idx=818 cap=2048`);
    run timed out at 120s (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_scan_20260226.log`,
    2026-02-26).
  - Trace: precheck+scan2 run shows `gc_reuse_bad_list_index_scan found_node=1` at `node_idx=818`
    with `node_ptr=0` (alloc-index slot still points at the old node, but the node’s ptr
    field was cleared). `found=0` for the original ptr; run timed out at 120s (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_scan2_20260226.log`,
    2026-02-26).
  - Trace: precheck+fix run (after removing bad-list ptr from alloc-index) still shows
    `gc_reuse_bad_list_index_scan found=0` on the second hit (no remaining node slot observed);
    run timed out at 120s (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_fix_20260226.log`,
    2026-02-26).
  - Trace: precheck+putbad run emitted no `[gc_free_list_put_bad_hdr]` lines before
    the bad-list hit (suggests list header is still valid when pushed to free list);
    scan still shows `found=0` after second hit. Run timed out at 120s (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_putbad_20260226.log`,
    2026-02-26).
  - Trace: precheck+state run shows the bad-list ptr transitions from `allocs=1` on first hit
    to `allocs=0` and `in_roots=1 (root_kind=3)` on second hit, with no free-list residency
    (`free_total=0`), implying a stale root keeps the corrupted header alive after it leaves
    allocs (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_state_20260226.log`,
    2026-02-26).
  - Trace: precheck+state5 run logs root slot details for the stale root:
    `root_slot_offset=3456` (`root_slot_index=432`) with `root_slot_val` equal to the bad ptr
    and `root_count=3` (duplicate roots). Confirms the root slot lives inside `g_storage`
    at offset 3456 (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_state5_20260226.log`,
    2026-02-26).
  - Trace: compile-time global slot dump (`OREN_TRACE_GLOBAL_SLOTS=1`,
    `OREN_TRACE_GLOBAL_SLOT_OFF=3456`) maps the stale root slot to
    `g_trace_list_hdr_ring_dup_seen_head` (alloc_churn build, 2026-02-26).
  - Tool: list header ring ptr guard (`OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1`) logs if the
    ring buffer pointer or dup-seen buffer pointer equals `g_storage` (one-shot, 2026-02-26).
  - Tool: list header ring ptr guard now also checks `g_trace_list_hdr_ring_dup_seen_head` and
    logs `[list_hdr_ring_dup_seen_head_ptr]` if it looks like a tracked alloc/free pointer
    (one-shot, 2026-02-27).
  - Trace: precheck+guard run (ptr guard enabled) still hits bad-list; stale root now reports
    `root_slot_offset=3464` (`root_slot_index=433`) and no `[list_hdr_ring_ptr_guard]` lines
    were emitted; run timed out at 120s (log:
    `build/logs/alloc_churn_trace_precheck_guard_20260226.log`, 2026-02-26).
  - Trace: precheck+guard2 run (ptr guard enabled) still hits bad-list; stale root remains
    `root_slot_offset=3464` (`root_slot_index=433`) and no guard lines emitted; run timed out
    at 120s (log:
    `build/logs/alloc_churn_trace_precheck_guard2_20260227.log`, 2026-02-27).
  - Trace: compile-time global slot dump after rebuilding stage2 maps slot 3464/index 433 to
    `g_trace_list_hdr_ring_ptr_guard` (log:
    `build/logs/global_slots_idx433_after_stage2.log`, 2026-02-27).
  - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_corrupt]` if the guard slot value
    exceeds 1 and looks like a tracked alloc/free pointer (one-shot, 2026-02-27).
  - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_set]` whenever the guard slot changes,
    capturing the new value + reason (env_enable/corrupt/g_storage/dup_seen_head_ptr) and
    the current op/list/kind (one-shot, 2026-02-27).
  - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_changed]` if the guard slot changes
    outside the helper (detects unexpected writes; one-shot per change, 2026-02-27).
  - Tool: GC reuse precheck now polls the ptr-guard via `list_hdr_ring_guard_poll` (op=92)
    when `OREN_TRACE_GC_REUSE_PRECHECK=1`, so unexpected writes are detected even if no
    list header ring puts occur (2026-02-27).
  - Tool: root lookup now polls the ptr-guard via `list_hdr_ring_guard_poll` (op=93)
    in `native_gc_root_find`, widening coverage beyond reuse precheck (2026-02-27).
  - Tool: bad-list ptr state log now includes `guard` + `guard_last` to confirm whether
    `g_trace_list_hdr_ring_ptr_guard` changed when stale roots are reported (2026-02-27).
  - Trace: precheck+guard4 run shows a single `[list_hdr_ring_ptr_guard_set]` (env_enable)
    and no subsequent guard flips before timeout (log:
    `build/logs/alloc_churn_trace_precheck_guard4_20260227.log`, 2026-02-27).
  - Trace: precheck+guard5 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
    (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
    `build/logs/alloc_churn_trace_precheck_guard5_20260227.log`, 2026-02-27).
  - Trace: precheck+guard6 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
    (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
    `build/logs/alloc_churn_trace_precheck_guard6_20260227.log`, 2026-02-27).
  - Trace: precheck+guard7 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
    (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
    `build/logs/alloc_churn_trace_precheck_guard7_20260227.log`, 2026-02-27).
  - Tool: reuse scan can optionally log `[gc_reuse_list_hdr]` for list headers encountered
    during reuse (`OREN_TRACE_GC_REUSE_LIST_HDR=<n>`) to check if list header fields
    are already corrupted before reuse validation (rolling, 2026-02-27).
  - Trace: list-hdr reuse scan run with `OREN_TRACE_GC_REUSE_LIST_HDR=8` segfaulted
    quickly and emitted no `[gc_reuse_list_hdr]` lines (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_listhdr_20260227.log`, 2026-02-27).
  - Tool: list header validation now optionally logs `[gc_list_hdr_ok]` before
    `native_gc_list_header_ok_impl` returns (`OREN_TRACE_GC_LIST_HDR_OK=<n>`)
    to capture raw header fields even if validation fails (rolling, 2026-02-27).
  - Tool: `scripts/repro_bad_list_alloc_churn.sh` brute-forces alloc_churn configs until a
    `[gc_reuse_bad_list]` hit is found, printing ptr/node filters for follow-up tracing; it
    continues across crashes, logs non-zero exit statuses, and captures stderr in logs
    (set `EXTRA_TRACE=1` to include reuse summary + list-hdr kind/ok traces, 2026-02-27).
  - Trace: list header ok trace emitted entries (e.g., `kind=8` and `kind=2`)
    before a segfault (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_hdr_ok_20260227.log`, 2026-02-27).
  - Tool: list header kind tracing now logs `[gc_list_hdr_kind]` at reuse + mark call sites
    (`OREN_TRACE_GC_LIST_HDR_KIND=<n>`) to capture the kind/ptr source before validation
    (rolling, 2026-02-27).
  - Trace: `[gc_list_hdr_kind]` emitted `src=mark_list_int` with `kind=8` (list_int_kind)
    before segfault (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_hdr_kind_20260227.log`,
    2026-02-27).
  - Tool: allocation kind change tracing logs `[alloc_kind_change]` when a tracked node’s
    kind changes during `oren_track_alloc*` (`OREN_TRACE_ALLOC_KIND_CHANGE=<n>`, optional
    filters: `OREN_TRACE_ALLOC_KIND_CHANGE_PTR`/`..._NODE`), including initial list/list_int
    retags from `kind=0`, to catch unexpected retagging (rolling, 2026-02-27).
  - Trace: alloc-kind-change run emitted no `[alloc_kind_change]` lines before segfault
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_kindchange_20260227.log`,
    2026-02-27).
  - Trace: alloc-kind-change re-run (cap=32) segfaulted before emitting any output; run log
    is empty (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_kindchange2_20260226.log`,
    2026-02-27).
  - Trace: ring-recent run logs `[list_hdr_ring_recent]` entries for the bad list pointer
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent.log`, 2026-02-26).
  - Trace: correlator output now includes `[list_hdr_ring_recent]` blocks for the bad list
    pointer (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent_correlate.log`, 2026-02-26).
  - Trace: ring-recent (n=16) run still reports repeated `op=1` entries for the bad list pointer;
    correlator sequence remains `1:2` (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent16.log`, 2026-02-26;
    correlate:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent16_correlate.log`, 2026-02-26).
  - New: `OREN_TRACE_LIST_HDR_RING_DUP=1` logs `[list_hdr_ring_dup]` when the ring buffer
    already contains the same list pointer; per-pointer suppression uses
    `OREN_TRACE_LIST_HDR_RING_DUP_SEEN_CAP` (default 64) to avoid repeat logs
    (log cap via `OREN_TRACE_LIST_HDR_RING_DUP_CAP`, 2026-02-26).
  - Trace: ring-dup run emits repeated `[list_hdr_ring_dup]` hits for list_int headers
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringdup.log`, 2026-02-26).
  - Trace: ring-dup suppression run logs one dup per list pointer (distinct list_int headers)
    under `OREN_TRACE_LIST_HDR_RING_DUP_SEEN_CAP` (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringdup_once.log`, 2026-02-26).
  - Trace: ring-all filter run emits a single `list_hdr_ring idx=...` line for the bad pointer
    (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter.log`, 2026-02-26).
  - Tool: `tools/trace_list_hdr_correlate.py` now includes `[list_hdr_ring]` entries when
    correlating `gc_free_list` samples (rolling, 2026-02-26).
  - Tool: correlator accepts ring-all `idx=` entries to match `list_hdr_ring` dumps
    when `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1` is set (rolling, 2026-02-26).
  - Tool: correlator now ingests `[list_hdr_ring_recent]` and emits recent-op blocks
    for bad-list pointers, including a summarized op sequence and per-hit deltas
    across successive bad-list events (rolling, 2026-02-26).
  - Tool: correlator now captures recent-op deltas keyed off `gc_reuse_bad_list`
    (via subsequent `list_hdr_ring_recent` lines) and annotates delta sources
    to handle logs with sparse `gc_free_list` samples (rolling, 2026-02-27).
  - Tool: correlator parses `[list_hdr_ring_pre]` entries to keep pre-bad-list
    snapshots alongside recent-op sequences (rolling, 2026-02-27).
  - Trace: correlate output for the alloc-node/dup run now captures the ring entry alongside
    the `gc_free_list` sample (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_allocnode_dup2_correlate.log`, 2026-02-26).
  - Trace: ring-all correlate output captures the matching ring entry for the
    free-list sample (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_correlate.log`, 2026-02-26).
  - Trace: ring-all filter correlate output captures only the filtered ring entry
    (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter_correlate.log`, 2026-02-26).
  - Trace: follow-up bad-list safe run shows corrupted header fields (`len=4122543214814507828`,
    `cap=13879`, `buf=0`, `magic=0`) while precheck still reports `freed_seen=0`; node_kind
    flips (1 -> 0) and node_size (32 -> 48) between prints for the same node (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist2.log`, 2026-02-26).
  - Trace: one-shot `native_list_debug_node` now shows the bad-list node is still in allocs
    (`node_in_allocs=1`) and not in free blocks (`node_in_free_blocks=0`) while the header
    fields are corrupt; node_kind flips 1 -> 0 with node_size 32 -> 48 (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist3.log`, 2026-02-26).
  - Trace: bucket scans confirm the bad-list node is not in any reuse free-block bucket
    (`node_in_free_blocks_64/256/1024/other=0`) while still present in allocs (log:
    `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist4.log`, 2026-02-26).
  - Verified: dot_product Oren C benchmark build/run now completes without list-header corruption
    after aligned-header fix (log: `build/logs/bench_dot_product_oren_c_20260226_155530.log`).
   - Verified: dot_product_int Oren C benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_oren_c_20260226_155726.log`).
   - Verified: dot_product_int Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_native_20260226_161550.log`).
   - Verified: dot_product Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_native_20260226_161555.log`).
   - New: list_int allocations show huge `size` at `oren_track_alloc_new` time (before header init), so track the
     corruption back to size propagation (possible 32-bit -> 64-bit zero-extend gap or bad `cap` propagation).
   - New: arm64 native `malloc_k` now preserves size across kind-eval; re-run free-list traces to confirm the
     huge-size tracking corruption is gone before re-enabling reuse.
   - New: GC auto + heavy list tracing can trigger `list_int_reserve on non-list` panic; triage whether this is a
     trace-only artifact or a real metadata corruption under GC.
   - New: GC auto trace with `OREN_TRACE_NATIVE_LIST_HDR=1` completes cleanly after spilling list ptr to stack in
     the trace hook; keep this guard.
   - New: `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1` logs implausible `track_alloc_new` sizes
     (default min 1<<30; tunable via `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN`/`_CAP`) to catch size corruption early.
   - Trace: alloc_churn run with `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN=65536` emitted
     `[track_alloc_new_size] ... size=160000 kind=0` and caused benchmark stdout mismatch
     (log: `build/logs/bench_alloc_churn_track_alloc_size_min64k_20260226_045645.log`).
   - Trace: new list alloc request tracing confirms `size=160000` is a list_int buffer
     (`cap=20000`, bytes=160000) in alloc_churn, so the size log is expected
     (log: `build/logs/bench_run_alloc_churn_20260226_084444/oren_native/run_0.log`).
   - Trace: alloc_churn native-only run with `OREN_TRACE_NATIVE_ALLOC_REQ=1` +
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN=32768` (stdout check disabled) logged
     `size=160000 kind=0` in each native run log
     (`build/logs/bench_run_alloc_churn_20260226_050943/oren_native/run_*.log`).
   - Trace: pre-track tag `[alloc_req]` did not appear in the native run logs above
     (only `[track_alloc_new_size]` emitted), so the pre-track hook may not be firing
     for runtime allocations yet (investigate compiler/runtime bundle flag propagation).
   - Fix: pin `oren_track_alloc_new` + `oren_trace_alloc_request` with `@oren.keep` so DCE does not drop
     fixup-only runtime helpers on non-rtobj builds (2026-02-26).
   - Fix: rtobj runtime hash now salts trace codegen flags (`OREN_TRACE_NATIVE_ALLOC_REQ`,
     `OREN_TRACE_NATIVE_LIST_HDR`, `OREN_TRACE_NATIVE_LIST_RESERVE`) so cached runtime objects rebuild
     with pre-track tracing enabled (2026-02-26).
   - Trace: loop_sum native run with `OREN_TRACE_NATIVE_ALLOC_REQ=1` +
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1` (min=1 cap=10) shows `[alloc_req]` under rtobj cache hits,
     confirming the trace hook fires with the salted rtobj hash
     (log: `build/logs/bench_run_loop_sum_20260226_053253/oren_native/run_0.log`).
   - Trace: alloc_churn native run with `OREN_TRACE_NATIVE_ALLOC_REQ=1` +
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN=32768` failed with `list_int_reserve on non-list` panic
     (log: `build/logs/bench_run_alloc_churn_20260226_053122/oren_native/run_0.log`); keep tracking
     the reserve-on-non-list corruption path (2026-02-26).
   - Trace: alloc_churn with `OREN_BENCH_GC_EVERY=1000` + `OREN_TRACE_GC_SWEEP=1` (and `OREN_ARENA_AUTO_LOOP=0`)
     shows GC sweeps but `freed_kinds` list/list_int=0, so free-list header dumps never fire; likely
     list headers remain live under conservative scan (log: `build/logs/alloc_churn_native_gc_sweep_20260226_163932.log`).
   - New: `alloc_churn` trace knobs `OREN_BENCH_CLEAR_LIST=1` + `OREN_BENCH_SMALL_INTS=1` clear per-iter list roots
     and reduce conservative false roots so GC frees can surface list headers during corruption hunts (2026-02-26).
   - Trace: alloc_churn with `OREN_BENCH_CLEAR_LIST=1` + `OREN_BENCH_SMALL_INTS=1` +
     `OREN_TRACE_GC_FREE_LIST_HEADERS=1` now shows list header frees with `len/cap=128` and `chunk=32`,
     confirming GC can free list headers once conservative roots are reduced
     (log: `build/logs/alloc_churn_trace_hdr_ring_20260226_164630.log`).
   - New: `OREN_BENCH_FORCE_LIST_INT=1` forces alloc_churn to use list<int> ops so GC traces can
     surface list_int header frees directly (2026-02-26).
   - Trace: alloc_churn with `FORCE_LIST_INT=1` + `CLEAR_LIST=1` + `SMALL_INTS=1` now shows
     free-list dumps for list_int headers (kind=8, len/cap=128), alongside list (kind=2)
     headers, confirming list_int frees are visible under GC traces
     (log: `build/logs/alloc_churn_trace_list_int_20260226_165002.log`).
   - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` dumps list_hdr ring samples at free-list dump time
     (tunable via `_EVERY`/`_CAP`) to correlate recent list header writes with freed headers (2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1` dumps the full ring snapshot (bounded by ring size)
    for free-list samples when pointer filtering misses (2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now auto-enables free-list header dumps +
    list_hdr ring capture (no separate `OREN_TRACE_LIST_HDR_RING` needed, 2026-02-26).
  - Trace: alloc_churn with `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now emits `[list_hdr_ring]`
    samples alongside `[gc_free_list]` without extra ring flags
    (log: `build/logs/alloc_churn_trace_gc_ring_20260226_172250.log`).
  - Tool: `tools/trace_list_hdr_correlate.py --log <log> --limit 5 --max 50` correlates
    `[list_hdr]` and `[list_hdr_ring]` traces with `[gc_free_list]` samples to spot the last header writes.
  - Tool: `tools/run_alloc_churn_trace.sh [tag]` builds + runs alloc_churn and records
    OREN/AVM env + logs for reproducible trace runs. Use `ALLOC_CHURN_RUN_TIMEOUT_SECS`
    to bound long-running traces.
  - Trace: alloc_churn with GC reuse + `OREN_TRACE_ALLOC_INDEX=1` + free-list header tracing
    appeared to loop on alloc-index rebuild logs and was killed
    (log: `build/logs/alloc_churn_trace_repro_reuse_20260226e.log`).
  - New: free-list header dumps now emit `[gc_free_list_size_mismatch]` when list/list_int
    headers have a non-32 tracked size to catch tracking-node size corruption (2026-02-26).
  - New: size-mismatch traces now dump `list_hdr_ring` (when ring capture is active) to
    show the last header writes for the mismatched pointer (2026-02-26).
  - Trace: alloc_churn with `OREN_TRACE_GC_FREE_LIST_HEADERS=1` (cap=200) now shows
    only `chunk=32` list/list_int header frees; large chunk sizes from earlier traces
    did not reproduce (log: `build/logs/alloc_churn_trace_gc_hdrsize_20260226_173253.log`).
  - Trace: alloc_churn with header ring capture + forced list_int + GC every 1000
    still shows only `chunk=32` frees and no size mismatches
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring2.log`, 2026-02-26).
  - Trace: longer header ring capture (cap=2000, ring=256) still shows only `chunk=32`
    frees and no size mismatches
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring3.log`, 2026-02-26).
  - Trace: reuse-enabled alloc_churn (blocks+lists unsafe) still shows only `chunk=32`
    frees and no size mismatches; reuse stats show large scan_steps in later windows
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse1.log`, 2026-02-26).
  - Trace: reuse + scan cap (`OREN_GC_REUSE_SCAN_CAP=4096`) still shows only `chunk=32` frees
    and no size mismatches; reuse stats show scan_cap_hits with reduced scan_steps
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_scan_cap.log`, 2026-02-26).
  - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=128` crashed (segfault) but still showed
    only `chunk=32` frees before the crash; reuse stats showed large scan_steps with cap hits
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128.log`, 2026-02-26).
  - Trace: reuse + scan cap + `OREN_GC_REUSE_BUCKETS=1` + `OREN_BENCH_LIST_LEN=128`
    also segfaulted; still only `chunk=32` frees before the crash; reuse stats show large
    scan_steps with cap hits
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128_buckets.log`, 2026-02-26).
  - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` also segfaulted; still only
    `chunk=32` frees before the crash; reuse stats show large scan_steps with cap hits
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64.log`, 2026-02-26).
  - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` with verbose reuse logging still
    segfaulted; captured `[gc_reuse_hit]` lines for small/medium chunks before crash
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_verbose.log`, 2026-02-26).
  - Trace: no-reuse + `OREN_BENCH_LIST_LEN=64` completes cleanly; still only `chunk=32`
    frees and no size mismatches
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_noreuse_len64.log`, 2026-02-26).
  - Trace: reuse + bad-list tracing hit `[gc_reuse_bad_list]` with corrupt header fields
    (len=4 cap=5 buf=6 magic=7) and timed out; indicates reuse guardrail catches corrupted
    list headers under reuse stress
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist.log`, 2026-02-26).
  - New: bad-list guardrail now force-enables list_hdr_ring so reuse corruption dumps
    can capture the last header writes even when ring tracing was not otherwise enabled.
  - New: bad-list guardrail now dumps full list_hdr_ring snapshot to avoid missing pointer
    correlation when ring sampling is sparse.
  - Trace: bad-list run with full ring dump still did not show any list_hdr_ring entries
    for the corrupted pointer, suggesting the bad header was never recorded in the ring
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist_ring2.log`, 2026-02-26).
  - Trace: bad-list logs now include tracking-node fields; observed node_freed=1 with valid
    node_magic and kind=8 when corruption is detected, suggesting the tracked node is
    already marked freed at reuse time
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist_node.log`, 2026-02-26).
  - Trace: block-reuse only (lists disabled) still segfaulted under `OREN_BENCH_LIST_LEN=64`;
    no bad-list events were emitted, suggesting the crash is not limited to list reuse
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_blocks_only.log`, 2026-02-26).
  - Trace: no-reuse `OREN_BENCH_LIST_LEN=64` still completes cleanly after guardrail
    changes; only `chunk=32` frees observed
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_noreuse_len64_postguard.log`, 2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_PUT=1` logs nodes as they enter free lists (cap via
    `OREN_TRACE_GC_FREE_LIST_PUT_CAP`).
  - New: `OREN_TRACE_GC_FREE_LIST_TAKE=1` logs nodes as they are removed from free lists
    (cap via `OREN_TRACE_GC_FREE_LIST_TAKE_CAP`).
  - Trace: free-list put logs show list/list_int nodes inserted with freed=1 and intact
    magic/len/cap; bad-list events still show corrupted header fields
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freeput.log`, 2026-02-26).
  - Trace: even with `OREN_TRACE_GC_FREE_LIST_PUT_CAP=2000`, the bad ptr did not appear
    in any free-list put logs before `[gc_reuse_bad_list]`, suggesting it enters reuse
    without a visible free-list insertion in the current trace window
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freeput2.log`, 2026-02-26).
  - Trace: free-list take logging captured a single put/take pair (freed flipped to 0
    on take); no bad-list events observed before timeout
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake.log`, 2026-02-26).
  - Trace: free-list take logging with cap=2000 again emitted only a single put/take pair
    (two-line log) and no bad-list events before timeout
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake2.log`, 2026-02-26).
  - Trace: `OREN_BENCH_LIST_LEN=128` with free-list take logging (timeout 120s) still
    emitted only a single put/take pair and no bad-list events before timeout
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128_freetake.log`, 2026-02-26).
  - Trace: free-list take logging with line-buffered output still emitted only a single
    put/take pair; run_status=124 (timeout) recorded in env log
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake3.log`, 2026-02-26).
  - Trace: lowering GC interval to `OREN_BENCH_GC_EVERY=100` still emitted only a single
    put/take pair; run_status=124 (timeout) recorded in env log
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake4_gc100.log`, 2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_TAKE_COUNT=1` prints total/by_ptr/reuse take counts at shutdown
    to distinguish sparse activity from log truncation (2026-02-26).
  - New: `OREN_BENCH_ITERS=<n>` overrides alloc_churn iteration count (default 20000) to
    shorten trace runs when heavy GC logging is enabled (2026-02-26).
  - Trace: small-iteration run with `OREN_BENCH_ITERS=50`, `OREN_BENCH_LIST_LEN=8`,
    `OREN_BENCH_GC_EVERY=10`, `OREN_GC_REUSE_SCAN_CAP=128` emitted
    `[gc_free_list_take_count] ... reuse=6` plus repeated bad-list entries, confirming
    reuse hits occur even when per-take logs are sparse
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len8_takecount_50_cap128.log`, 2026-02-26).
  - Trace: `OREN_BENCH_ITERS=200`, `OREN_BENCH_LIST_LEN=64`, `OREN_BENCH_GC_EVERY=50`,
    `OREN_GC_REUSE_SCAN_CAP=128` still reports `[gc_free_list_take_count] ... reuse=6`
    with repeated bad-list entries (run_status=124 timeout), indicating reuse hits
    even without per-take logging
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_takecount_200_cap128.log`, 2026-02-26).
  - New: `OREN_TRACE_GC_REUSE_SUMMARY=1` prints a per-GC summary line that includes
    reuse stats plus free-list take counters (and auto-enables reuse tracing),
    to correlate bad-list bursts with reuse/take activity; summary now includes
    `bad_list_prints` (2026-02-26).
  - Trace: per-GC summary run (`OREN_BENCH_ITERS=200`, `OREN_BENCH_LIST_LEN=64`,
    `OREN_BENCH_GC_EVERY=50`, `OREN_GC_REUSE_SCAN_CAP=128`) logged
    `[gc_reuse_summary] tries=363 hits=0 ... take_total=0` while still emitting
    repeated bad-list entries, indicating bad-list triggers can occur without reuse hits
    in this short run (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128.log`, 2026-02-26).
  - Trace: summary with `bad_list_prints` still showed `bad_list_prints=0` even though
    `[gc_reuse_bad_list]` lines followed in the log, implying bad-list prints can occur
    after the summary window (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128b.log`, 2026-02-26).
  - Trace: longer summary run (`OREN_BENCH_ITERS=500`, `OREN_BENCH_GC_EVERY=10`) still
    logged a single summary line with `bad_list_prints=0` followed by repeated bad-list
    entries, suggesting summary timing does not capture subsequent bad-list prints
    in short timeouts (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_500_gc10.log`, 2026-02-26).
  - Trace: 180s timeout run (`OREN_BENCH_ITERS=1000`, `OREN_BENCH_GC_EVERY=10`) still
    logged one summary line with `bad_list_prints=0` followed by bad-list prints
    counting down 10→1, reinforcing the gap between summary and later bad-list logs
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_1000_gc10_t180.log`, 2026-02-26).
  - New: `gc_reuse_summary` now reports `bad_list_triggers` (counter incremented before
    cap check) alongside `bad_list_prints`, to detect bad-list triggers that occur after
    the summary window (2026-02-26).
  - New: bad-list dumps now emit `[gc_reuse_summary_at_bad_list]` snapshots when
    `OREN_TRACE_GC_REUSE_SUMMARY=1`, capturing reuse/take counters at the moment a
    bad-list is detected (2026-02-26).
  - Trace: summary-at-bad-list run segfaulted before emitting any bad-list logs
    (run_status=139), so no `[gc_reuse_summary_at_bad_list]` lines captured yet
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128e.log`, 2026-02-26).
  - Trace: lower scan cap (`OREN_GC_REUSE_SCAN_CAP=64`, bad-list cap=3) still
    segfaulted before emitting bad-list logs; summary only
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap64.log`, 2026-02-26).
  - Trace: with `bad_list_triggers` enabled, summary still showed `bad_list_triggers=0`
    while bad-list prints followed (now with `len=0 cap=1 buf=2 magic=3` in the corrupted
    header fields), so the summary window continues to miss later bad-list events
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128d.log`, 2026-02-26).
  - Trace: even with `bad_list_triggers` reported, summary still showed
    `bad_list_triggers=0` while bad-list prints counted down 10→1, indicating triggers
    can occur after the summary snapshot (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128d.log`, 2026-02-26).
  - New: bad-list logs now include `prints=<n>` so each `[gc_reuse_bad_list]` line can be
    correlated directly with the running bad-list counter (2026-02-26).
  - Trace: bad-list log `prints=<n>` counts down as expected (5→1) in
    `gc_hdr_mismatch_reuse_len64_summary_200_cap128c`, confirming the counter tracks
    each bad-list print even when the summary line shows `bad_list_prints=0`
    (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128c.log`, 2026-02-26).
  - New: alloc_churn trace harness now records run_status/run_timed_out/run_elapsed_sec
    and line-buffer command in the env log for timeout diagnostics (2026-02-26).
  - Next: determine why free-list take traces remain sparse under reuse (single put/take
    pair per 120s run); consider forcing line-buffered logging or recording timeout/exit
    status in the trace harness to confirm log completeness.
  - Trace: alloc_churn with `OREN_ARENA_AUTO_LOOP=0` + free-list ring tracing (cap=200)
    still shows only `chunk=32` list/list_int header frees; large chunk sizes remain
    unreproduced under arena-off GC stress
    (log: `build/logs/alloc_churn_trace_gc_arenaoff_20260226_173516.log`).
  - Trace: longer arena-off run (`OREN_TRACE_GC_FREE_LIST_HEADERS_CAP=2000`) still shows
    no size mismatches or non-32 chunks
    (log: `build/logs/alloc_churn_trace_gc_arenaoff_long_20260226_174106.log`).
  - New: `OREN_TRACE_ALLOC_INDEX=1` now emits `[alloc_index_size]` for list/list_int nodes
    when tracked size exceeds 1 GiB to catch alloc-index size corruption; expected size
    accounts for inline buffers when `buf == list+32` (2026-02-26).
  - New: free-list insertion now emits `[free_blocks_size]` when a block size is >= 1 GiB
    (or negative), including list header fields for list/list_int nodes (2026-02-26).
   - New: `OREN_BENCH_LIST_LEN=<n>` lets alloc_churn reduce per-list pushes during trace runs so
     list_hdr ring entries survive until GC sweep samples (2026-02-26).
   - Trace: alloc_churn native baseline now completes after the alloc-index rebuild fallback
     (log: `build/logs/bench_run_alloc_churn_20260226_054752/oren_native/run_0.log`); earlier panic
     logs remain as reference (e.g., `bench_run_alloc_churn_20260226_053425`).
   - Trace: when forcing `OREN_NATIVE_RESOLVE_SYMBOL=1` during the earlier panic, stacks still
     resolved as `???` (log: `build/logs/bench_run_alloc_churn_20260226_053529/oren_native/run_0.log`);
     resolve-symbol likely needs ASLR slide awareness or debug‑info embedding if we need it again.
   - New: `OREN_TRACE_LIST_RESERVE_FAIL=1` prints list/node metadata when `list_int_reserve` fails
     (stage + list ptr + node kind + list magic) to debug the non-list corruption path (2026-02-26).
   - New: reserve-fail tracing now includes list header fields (len/cap/buf/magic), and
     list corruption checks flag len>cap/negative or cap==0 with nonzero len/buf (2026-02-25).
   - Fix: list/list_int reserve now rebuilds the alloc index once on non-list detection before panicking,
     to recover from stale alloc-index state during green-task churn (rolling, 2026-02-26).
   - Fix: green scheduler struct allocations now rebuild/force GC tracking before tagging kind=STRUCT,
     preventing args-list GC under `OREN_GREEN_POLL_CACHE=1` (2026-02-25).
   - Fix: map checks now rebuild the alloc-index once on non-map detection to avoid false panics
     under GC churn (rolling, 2026-02-26).
   - Fix: list len checks now rebuild the alloc-index once on non-list detection to reduce
     false panics when the index is stale under GC churn (rolling, 2026-02-26).
   - Fix: alloc-index recovery now scans live allocs on map/list misses to reinsert
     missing nodes before panicking (rolling, 2026-02-26).
   - Fix: list/map constructors now re-track headers when alloc-index misses, preventing
     untracked container headers under GC stress (rolling, 2026-02-26).
   - Fix: map/list check paths now re-track headers on alloc-index misses when magic+cap look sane,
     reducing false panics during GC stress (rolling, 2026-02-26).
   - Fix: arm64/x64 `oren_list_len` intrinsics now fall back to magic+count on untracked headers
     to avoid false panics under GC stress (rolling, 2026-02-26).
   - Fix: `oren_track_alloc_new` now de-duplicates existing alloc-index nodes to avoid duplicate
     tracking entries under reuse/GC churn (rolling, 2026-02-26).
   - New: `make test-native-quick-gc-stress-stage2` runs quick integration with forced GC
     (`OREN_GC_ALLOC_THRESHOLD=20000`) and longer timeouts (rolling, 2026-02-26).
   - New: `make verify-native-quick-gc` runs the standard native quick verify plus GC-stress
     quick integration to catch tracking regressions (rolling, 2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX=1` now reports alloc-index rebuild stats
     (`[alloc_index] rebuild allocs=... static=... dt_ms=... dedup_hits=...`) to quantify how often
     the fallback path runs under green-task churn (2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX_DEDUP_CAP=<n>` panics when dedup hits exceed `n`
     (trace-only guardrail, 2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX_REBUILD_CAP=<n>` panics when rebuilds exceed `n` (trace-only guardrail)
     to catch runaway rebuild loops during corruption hunts (rolling, 2026-02-26).
   - Trace: alloc_churn native run with `OREN_TRACE_ALLOC_INDEX=1` emitted a single
     `[alloc_index] rebuild allocs=0 static=0 dt_ms=0` line (log:
     `build/logs/bench_run_alloc_churn_20260226_055407/oren_native/run_0.log`), suggesting
     no rebuild pressure in this baseline after the fallback fix (2026-02-26).
   - Trace: quick integration run with `OREN_TRACE_ALLOC_INDEX=1` emitted two rebuild events
     (summary shows `rebuilds=2`, `rebuild_ns=114000`, `rebuild_allocs=0`, `rebuild_static=0`;
     log: `build/logs/oren_stage2_native_quick_integration.log`), indicating early-runtime
     rebuilds but no tracked allocs in the table (2026-02-26).
   - New: `OREN_TRACE_NATIVE_ALLOC_REQ=1` emits a native-side pre-track trace
     (`oren_trace_alloc_request`) before `oren_track_alloc_new` to catch size corruption at the call site.
   - New: list header/buffer alloc request trace logs size+cap before tracking when
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1` triggers (2026-02-26).
   - New: list growth/reserve now guards `cap > 1<<30` to catch corrupted headers before
     overflow/alloc (2026-02-26).
   - New: GC mark now validates list/list_int headers and panics on corruption before
     scanning payloads (2026-02-26).
   - Trace: GC-stress quick integration with list-reserve-fail + corrupt tracing enabled
     saw no list_reserve/list_corrupt events; alloc-index rebuilds remained zero
     (log: `build/logs/native_quick_gc_trace_20260226_084741.log`).
   - New: guard poll now logs `[list_hdr_ring_ptr_guard_last_corrupt]` when
     `g_trace_list_hdr_ring_ptr_guard_last` is not 0/1 to catch unexpected writes (2026-02-27).
   - Trace: global slots dump maps `idx=434` / `off=3472` to
     `g_trace_list_hdr_ring_ptr_guard_last` after rebuilding stage2
     (log: `build/logs/alloc_churn_build_globals_idx434_manual_20260227.log`).
   - Trace: precheck_guard9 (cached build) still shows `root_slot_offset=3472` with
     `guard_last=1` and no guard-last-corrupt logs (log:
     `build/logs/alloc_churn_trace_precheck_guard9_20260227.log`).
   - Trace: precheck_guard9 (no-cache build) still shows `root_slot_offset=3472` with
     `guard_last=1` and no guard-last-corrupt logs (log:
     `build/logs/alloc_churn_trace_precheck_guard9_nc_20260227.log`).
   - Trace: after bounding root-slot offsets to the 512-byte boot globals storage,
     precheck_guard10 reports `root_slot_offset=-1` while bad-list roots persist (log:
     `build/logs/alloc_churn_trace_precheck_guard10_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_ROOT_SLOTS=1` shows `root_idx=35`, `list_len=409`, and the
     global-roots entry at `i=35` points to a slot pointer outside g_storage whose value
     equals the bad-list ptr (log:
     `build/logs/alloc_churn_trace_precheck_guard13_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_REGISTER_ROOT=1` shows early roots registered at
     `slot_off=-8` (g_storage slot) and `slot_off=528..560` (heap spill slots);
     `OREN_TRACE_GC_ROOT_MATCHES=1` shows three root slots (idx 35/117/182) whose
     slot values equal the bad-list ptr with `slot_off=2376..3552` (log:
     `build/logs/alloc_churn_trace_precheck_guard15_nc_20260227.log`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_REGISTER_ROOT` now tags known call sites; untagged entry-stub
     roots are skipped unless `OREN_TRACE_GC_REGISTER_ROOT_ALL=1` is set. New summary
     knob `OREN_TRACE_GC_ROOT_SLOT_SUMMARY=1` reports boot vs non-boot root slots
     (sample cap via `OREN_TRACE_GC_ROOT_SLOT_SUMMARY_CAP`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_REGISTER_ROOT_ALL=1` logs entry-stub roots with tag=nil
     (`tag_id` equals the value-nil pointer) and slots spanning `slot_off=0..3872`;
     tagged call sites did not appear yet (log:
     `build/logs/alloc_churn_trace_precheck_guard16_nc_20260226d.log`, 2026-02-26).
   - Trace: pending root tags now flush once envp-derived tracing is enabled, showing
     runtime init’s `value_nil/false/true` registrations with `pending=1` (log:
     `build/logs/alloc_churn_trace_precheck_guard22_nc_20260226.log`, 2026-02-26).
   - Next: audit native codegen for size/arg clobbers when new regressions appear.
   - Expand fast-path tracing in native emitters to pinpoint header writes.
   - New: x64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-26).
   - Gate: no header corruption under `alloc_churn`/`alloc_drop` with reuse disabled; reuse remains guarded.

3) **W5 perf parity: hot loops (loop_sum, dot_product)**
   - Close native gap vs C and keep cross-backend semantics aligned.
   - New run (arm64, 2026-03-04, runs=5, warmups=1):
     - loop_sum: C 0.066739s, native 0.237463s (3.56× C) (log: `build/logs/bench_run_perf_gate_20260304_213121.log`).
     - dot_product: C 0.005035s, native 0.013433s (2.67× C) (log: `build/logs/bench_run_perf_gate_20260304_213121.log`).
    - New: loop_sum init/steady split instrumentation via `OREN_BENCH_INIT_SPLIT=1`.
      - Latest split (2026-02-26, n=20,000,000): native steady ~0.224922s vs C ~0.067377s (≈3.34× steady-state).
    - New: defer capsule-only NET/PROC tables to `native_runtime_capsule_init` to reduce non-capsule runtime init cost; remeasure init/steady split (2026-02-25).
    - Measured: native init 0.003006s, steady 0.223682s (arm64 macOS, 2026-02-26).
    - New: native LCG fast loops use reciprocal fastmod when mod constants fit (arm64 + x64).
    - New: dot_product native at 2.57× C (arm64 macOS, 2026-02-26).
    - New: arm64 list<int> get-sum + dot loops keep i/sum in registers across iterations (2026-02-26).
    - New: arm64 boxed list get-sum + dot loops keep i/sum in registers across iterations (2026-02-26).
    - Fix: arm64 boxed fast list dot loop now initializes X10 tick mask before inline safepoint ticks (2026-02-26).
    - New: LCG fast loop safepoint mask raised to 4095 on arm64 + x64 (2026-02-26).
    - New: LCG fast loop unroll-by-2 on arm64 + x64 to reduce loop overhead (2026-02-26).
    - New: `OREN_TRACE_ARM64_LOOP_STACK=1` logs loop stack/tick layout for arm64 emitters to debug tick slot offsets.
    - Trace (arm64 compile, 2026-02-26, `OREN_TRACE_ARM64_LOOP_STACK=1`): loop_sum + dot_product emitters report tick_off=0 across
      `while_generic` and list<int> fast loops (push/dot), with stack bases matching current stack size.
    - Stage2 trace rebuilds with `OREN_TRACE_ARM64_LOOP_STACK=1` (2026-02-26) completed without GC list-header corruption.
    - New debug knob: `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` removes the tick slot for `fast_list_int_dot_while` to
      isolate arm64 tick-offset regressions (trace kind=`fast_list_int_dot_while_no_tick`).
    - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` +
      `OREN_TRACE_ARM64_LOOP_STACK=1`): `fast_list_int_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
    - New debug knob: `OREN_TRACE_ARM64_GC_TICK_OFF=1` logs negative tick offsets in arm64 GC throttled safepoints
      (set to `all` to log every tick_off).
    - New debug knob: `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` removes the tick slot for `fast_list_dot_while`
      (trace kind=`fast_list_dot_while_no_tick`).
    - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` +
      `OREN_TRACE_ARM64_LOOP_STACK=1`): dot_product still uses list<int> fast loops; no `fast_list_dot_while_no_tick`
      emitted (trace shows `fast_list_int_dot_while` tick_off=0, slots=8, bytes=64, stack/base=224).
    - Trace (arm64 stage2 compile, 2026-02-26, `build/tmp/boxed_dot.oren`,
      `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_LOOP_STACK=1`):
      `fast_list_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
   - Trace (arm64 stage2 compile, 2026-02-26, `build/tmp/boxed_dot.oren`,
     `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     tick_off=0 at throttled safepoints (base/stack 160, 240; mask=1023), no negative offsets observed.
   - Trace (arm64 stage2 compile, 2026-03-03, `build/tmp/boxed_dot.oren`,
     `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): tick_off=0 at throttled safepoints (base/stack 160, 240);
     no negative offsets observed (log: `build/logs/arm64_tick_off_trace_20260303_212831.log`).
   - Trace (arm64 stage2 compile, 2026-03-03, `benchmarks/dot_product/dot_product.oren`,
     `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): tick_off=0 at throttled safepoints (base/stack 224, 240);
     no negative offsets observed (log: `build/logs/arm64_tick_off_trace_intdot_20260303_212850.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `OREN_TRACE_ARM64_GC_TICK_OFF=1`):
     no `[arm64_gc_tick_off]` entries emitted; log only shows rtobj/astbin seed updates
     (log: `build/logs/arm64_tick_off_stage2_20260303_213032.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     no `[arm64_gc_tick_off]` entries emitted; log only shows rtobj/astbin seed updates
     (log: `build/logs/arm64_tick_off_stage2_all_20260303_213150.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `make -B stage2` + `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     many `tick_off=0` entries (all `while_generic`), no negative offsets observed
     (log: `build/logs/arm64_tick_off_stage2_all_forced_20260303_213450.log`).
   - New debug knob: `OREN_TRACE_ARM64_STACK_RESTORE=1` logs stack restore deltas when the
     compiler repairs mismatched stack accounting on arm64 loop emission (2026-03-03).
   - New: arm64 GC tick-off traces now include last stack-restore context (`last_restore_*`)
     when tick_off is negative to correlate stack repairs with offset regressions (2026-03-03).
    - Reduce GC safepoint overhead in alloc-free hot loops (inline tick + higher masks where safe).
    - New: x64 boxed-list fast loops (push/get-sum/dot) now throttle safepoints at mask=1023; re-check perf gates.
    - Gate: `loop_sum` + `dot_product` native <= 2x C on Tier-1.
    - New: `OREN_TRACE_GC_REGISTER_ROOT_NAMES=1` (compile-time env) emits per-root
      `[gc_root_name]` lines; bad-list root_idx=256 mapped to `g_gc_reuse_bad_list_last_ptr`
      (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_083852.log`).
    - Trace: after skipping only `g_gc_reuse_bad_list_last_ptr`, bad-list root_idx=280 mapped
      to `g_find_cache_ptr0`, indicating `oren_find_node` MRU cache slots were still rooted
      (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_084819.log`).
    - Fix: global root registration now skips `g_gc_reuse_bad_list_last_ptr` and
      `g_find_cache_ptr{0,1}`/`g_find_cache_node{0,1}`; repro now reports `in_roots=0`
      for bad-list pointers (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_085139.log`).
    - Trace: ring pre/recent dump around bad-list shows `op=90` (list_header_poison) then
      `op=91` (bad-list dump) for the same list pointer, with prior ops `1/5` showing normal growth;
      bad-list pointer is not in roots (`in_roots=0`) and `list_debug` still reports `node_in_allocs=1`,
      suggesting a freed header is still tracked as live (log:
      `build/logs/alloc_churn_rootnames_badlist_ringpre_20260227_085849.log`, 2026-02-27).
    - Tool: `OREN_TRACE_GC_FREED_LIVE=1` reports when a freed list header pointer still appears
      in the allocs list (cap via `OREN_TRACE_GC_FREED_LIVE_CAP`, 2026-02-27).
    - Tool: `OREN_TRACE_GC_ALLOCS_LIST_HDR=1` logs when list headers are inserted into the
      allocs list (cap via `OREN_TRACE_GC_ALLOCS_LIST_HDR_CAP`, 2026-02-27).
    - Tool: `OREN_TRACE_LIST_HDR_REINIT=1` logs list header reinitialization after
      allocation/reuse (cap via `OREN_TRACE_LIST_HDR_REINIT_CAP`, filters via
      `OREN_TRACE_LIST_HDR_REINIT_PTR`/`OREN_TRACE_LIST_HDR_REINIT_NODE`, 2026-02-27).
    - Tool: `OREN_TRACE_GC_LIST_HDR_POISON_NODE=1` logs the allocs-list node and alloc-index
      state when a list header is poisoned during sweep (cap via `OREN_TRACE_GC_LIST_HDR_POISON_NODE_CAP`, 2026-02-27).
    - Trace: poison-node logs show `node_in_allocs=0`, `allocs_count=0`, and `idx_node` matching
      the sweep node at poison time; later `reuse_take` reactivates the same node before the
      bad-list event, pointing to corruption after reuse rather than a stale allocs entry
      (`build/logs/alloc_churn_poison_node_20260227_092907.log`, 2026-02-27).
    - Trace: `OREN_TRACE_LIST_HDR_REINIT=1` now logs reinit events when alloc-index nodes are
      present; latest alloc_churn run shows only `new_list` entries with `prev_magic=0` and
      `freed_seen=0` (no bad-list event to correlate yet)
      (`build/logs/alloc_churn_list_hdr_reinit_node2_cap200_20260227_094121.log`, 2026-02-27).
    - Trace: bad-list pointer shows `gc_allocs_list_hdr` entries for both `track_alloc_new`
      and later `reuse_take` on the same ptr/node, confirming it was freed and reactivated
      from the free-list before corruption (log:
      `build/logs/alloc_churn_allocs_list_hdr_bigcap_20260227_091142.log`, 2026-02-27).

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
  - Note: `make test` hit a segfault in `test-native-quick` with `OREN_GREEN_POLL_CACHE=1`
    (log: `build/logs/make_test_20260226_183026.log`); rerun `make test-native-quick` passed
    (log: `build/logs/make_test_native_quick_20260226_183115.log`). Track as a potential flake.
  - New: `scripts/triage_native_quick_stage2_flake.sh` runs stage2 quick integration in a loop
    and captures per-run logs for flake diagnosis; supports `ENV=VAL` passthrough args
    for tracing, logs git/uname metadata, and saves failure copies of the inner
    quick-integration log (2026-03-03).
  - Note: `make test` hit `test-native-quick` Error 139 on 2026-03-03
    (log: `build/logs/make_test_20260303_215000.log`); rerun passed
    (log: `build/logs/make_test_20260303_215100.log`). Track as a potential flake.
  - Note: `make test` hit `test-native-quick` Error 1 on 2026-03-03 in the
    `OREN_GREEN_POLL_CACHE=1` sub-run (panic: "Indexing on non-container";
    logs: `build/logs/make_test_20260303_221100.log`,
    `build/logs/make_test_20260303_223310.log` + inner
    `build/logs/oren_stage2_native_quick_integration.log`); rerun passed
    (log: `build/logs/make_test_20260303_221200.log`). Track as a potential flake.
  - New: `OREN_TRACE_LIST_GET_BAD=1` emits list-get diagnostics when "Indexing on non-container"
    triggers; use this for the `OREN_GREEN_POLL_CACHE=1` flake (cap via `OREN_TRACE_LIST_GET_BAD_CAP`).
  - Trace: stage1 flake harness with `OREN_GREEN_POLL_CACHE=1` timed out on run 1
    (rc=143; log: `build/logs/triage_stage1_quick_green_cache_20260303_221009.log`);
    rerun with `OREN_NATIVE_RUN_TIMEOUT_SECS=30` passed 5 runs
    (log: `build/logs/triage_stage1_quick_green_cache_timeout_20260303_221058.log`).
  - New: `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS` overrides the timeout for the
    `OREN_GREEN_POLL_CACHE=1` sub-run in `scripts/run_native_quick_integration.sh` (2026-03-03).
  - New: `OREN_QI_TRACE_GREEN_LIST=1` logs list metadata before `oren_list_get` inside
    `worker_green_alloc_yield_integrity` to diagnose green poll cache list corruption (2026-03-03).
  - New: `OREN_TRACE_GREEN_ENTRY_ARGS=1` logs `args_list` metadata at `__oren_green_entry`
    to catch corrupted spawn args before `oren_call_obj_list` (2026-03-03).
  - New: `OREN_TRACE_LIST_GET_BAD_SCAN=1` dumps alloc-index probe info for
    `list_get_bad` pointers (use sparingly; expensive).
  - New: `OREN_TRACE_GREEN_RUNQ_ARGS=1` logs `g->fn_obj/args_list` metadata at
    runq push/pop/steal to catch corruption between enqueue/dequeue (2026-03-03).
  - New: `OREN_TRACE_GREEN_RUNQ_GUARD=1` validates runq `g` + args_list headers on
    spawn/enqueue/dequeue and panics with details before a bus error (debug-only).
  - New: `OREN_TRACE_GREEN_ARGS_STAMP=1` snapshots spawn-time args_list headers and
    checks for drift at runq/entry (panics on mismatch; debug-only).
  - Trace: stage2 flake harness with `OREN_TRACE_LIST_GET_BAD=1` timed out on run 2
    (rc=143; log: `build/logs/native_quick_stage2_flake_20260303_224014_run2.log` +
    inner `build/logs/native_quick_stage2_flake_20260303_224014_run2_inner.log`).
  - Trace: stage2 flake harness rerun with `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=30` passed
    10 runs and emitted no `list_get_bad` lines (log: `build/logs/native_quick_stage2_flake_20260303_224533_run10.log`).
  - Trace: attempted 50-run stage2 harness with `OREN_TRACE_LIST_GET_BAD=1` +
    `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=30`; manually stopped after 18 runs
    (log: `build/logs/native_quick_stage2_flake_20260303_225644_run18.log`); no
    `list_get_bad` lines observed in completed runs.
  - Trace: stage2 harness with `OREN_QI_TRACE_GREEN_LIST=1` +
    `OREN_TRACE_LIST_GET_BAD=1` failed on run 9 (rc=1). `list_get_bad` fired
    with `node=0` before `worker_green_local_ptr_survives_yields` invoked;
    `__args` matched `args_list` pointer 4381103232 in the panic trace
    (log: `build/logs/native_quick_stage2_flake_20260303_230643_run9_inner.log`).
  - Trace: stage2 harness with `OREN_QI_TRACE_GREEN_LIST=1` +
    `OREN_TRACE_LIST_GET_BAD=1` + `OREN_TRACE_GREEN_ENTRY_ARGS=1` segfaulted
    on run 1 (rc=139) after logging `green_entry_args` with list kind=2/magic ok
    (log: `build/logs/native_quick_stage2_flake_20260303_231403_run1_inner.log`).
  - Trace: stage2 harness with `OREN_QI_TRACE_GREEN_LIST=1` +
    `OREN_TRACE_LIST_GET_BAD=1` + `OREN_TRACE_LIST_GET_BAD_SCAN=1` +
    `OREN_TRACE_GREEN_ENTRY_ARGS=1` segfaulted on run 3 (rc=139); no
    `list_get_bad` fired before crash, and entry args still showed list kind=2/magic ok
    (log: `build/logs/native_quick_stage2_flake_20260303_232159_run3_inner.log`).
  - Trace: stage2 harness with `OREN_QI_TRACE_GREEN_LIST=1` +
    `OREN_TRACE_LIST_GET_BAD=1` + `OREN_TRACE_LIST_GET_BAD_SCAN=1` +
    `OREN_TRACE_GREEN_ENTRY_ARGS=1` + `OREN_TRACE_GREEN_RUNQ_ARGS=1` hit a
    bus error on run 1 (rc=138); runq/entry logs show args_list kind=2/magic ok
    immediately before the crash (log: `build/logs/native_quick_stage2_flake_20260303_233056_run1_inner.log`).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_RUNQ_GUARD=1` still hit a bus error
    on run 1 (rc=138) before the guard printed; runq/entry logs still show kind=2/magic ok
    (log: `build/logs/native_quick_stage2_flake_20260303_233935_run1_inner.log`).
  - Trace: stage2 harness after adding spawn/enqueue guards still hit a bus error
    on run 1 (rc=138); guard did not emit before crash, runq/entry logs show kind=2/magic ok
    (log: `build/logs/native_quick_stage2_flake_20260303_235157_run1_inner.log`).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_ARGS_STAMP=1` +
    `OREN_TRACE_GREEN_RUNQ_GUARD=1` hit a bus error on run 7 (rc=138);
    no `green_args_stamp` output before crash (logs:
    `build/logs/native_quick_stage2_flake_20260304_000820_run7_inner.log`,
    `build/logs/triage_stage2_quick_args_stamp_20260304_000507.log`).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_ARGS_STAMP=1` +
    `OREN_TRACE_GREEN_RUNQ_GUARD=1` + `OREN_TRACE_GREEN_ENTRY_ARGS=1` +
    `OREN_TRACE_GREEN_RUNQ_ARGS=1` hit a bus error on run 1 (rc=138);
    runq/entry logs show args_list kind=2/magic ok with no `green_args_stamp`
    output before crash (logs:
    `build/logs/native_quick_stage2_flake_20260304_001002_run1_inner.log`,
    `build/logs/triage_stage2_quick_args_stamp_entry_20260304_001002.log`).
  - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD=1` validates cached poll `ts/s/p` pointers
    and runq_buf before deref (debug-only).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_POLL_CACHE_GUARD=1` +
    `OREN_TRACE_GREEN_RUNQ_ARGS=1` + `OREN_TRACE_GREEN_ENTRY_ARGS=1` timed out on run 1
    (rc=143) before producing inner logs (log:
    `build/logs/triage_stage2_quick_poll_cache_guard_20260304_001353.log`).
  - Trace: reruns with higher run timeouts (guard only) still timed out on run 1
    with empty inner logs (logs:
    `build/logs/triage_stage2_quick_poll_cache_guard_timeout_20260304_001446.log`,
    `build/logs/triage_stage2_quick_poll_cache_guard_only_20260304_001530.log`,
    `build/logs/triage_stage2_quick_poll_cache_guard_only2_20260304_001620.log`).
  - Trace: manual `run_native_quick_integration.sh` with guard and 60s timeouts
    also hit rc=143 before producing inner logs (log:
    `build/logs/native_quick_poll_cache_guard_manual_20260304_001735.log`).
  - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD_EVERY=<n>` samples guard checks every
    N cached poll iterations (debug-only).
  - Trace: stage2 harness with guard sampling (`EVERY=32`) still timed out on run 1
    with empty inner logs (log:
    `build/logs/triage_stage2_quick_poll_cache_guard_every32_20260304_002436.log`).
  - New: `OREN_TRACE_GREEN_LAST_OPS=1` captures a small ring of recent green runq/entry
    ops and dumps on `oren_fail`/`oren_panic`/`oren_exit` (cap via
    `OREN_TRACE_GREEN_LAST_OPS_CAP`).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_LAST_OPS=1` timed out on run 1
    before producing inner logs; no last-op dump (rc=143; log:
    `build/logs/triage_stage2_quick_last_ops_20260304_003205.log`).
  - Trace: no-timeout `run_native_quick_integration.sh` with `OREN_TRACE_GREEN_LAST_OPS=1`
    produced last-op entries (push_local/steal_one) before `native quick integration OK`
    (log: `build/logs/native_quick_last_ops_dump_20260304_004424.log`).
  - New: `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=<n>` dumps the last-op ring every
    N cached poll iterations (debug-only).
  - Trace: stage2 harness with `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=1000` still
    timed out on run 1 with empty inner logs (log:
    `build/logs/triage_stage2_quick_last_ops_every_20260304_004939.log`).
  - Trace: no-timeout quick integration with `OREN_TRACE_GREEN_LAST_OPS=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=500` emitted periodic last-op dumps
    (pop_global/entry/push_local/steal_one) and completed (log:
    `build/logs/native_quick_last_ops_every_no_timeout_20260304_005446.log`).
  - Trace: no-timeout quick integration with outer watchdog (180s) +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=500` emitted periodic last-op dumps
    and completed (log:
    `build/logs/native_quick_last_ops_every_outer_watch_20260304_005730.log`).
  - Trace: stage2 harness (3 runs) with `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=200`
    completed; inner logs include periodic last-op dumps (logs:
    `build/logs/triage_stage2_quick_last_ops_every200_20260304_005940.log`,
    `build/logs/native_quick_stage2_flake_20260304_005940_run1_inner.log`).
  - Trace: stage2 harness (10 runs, no timeouts) with
    `OREN_TRACE_GREEN_LAST_OPS=1` + `OREN_TRACE_GREEN_LAST_OPS_CAP=128` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=200` +
    `OREN_NATIVE_BUILD_TIMEOUT_SECS=0` + `OREN_NATIVE_RUN_TIMEOUT_SECS=0` +
    `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=0` hit a hang on run 4; outer
    watchdog (300s) terminated the harness after `test_green_two_workers_world_lock_smoke`
    started (logs: `build/logs/triage_stage2_quick_last_ops_every200_10run_20260304_010244.log`,
    `build/logs/native_quick_stage2_flake_20260304_010429_run4.log`, inner log
    `build/logs/oren_stage2_native_quick_integration.log` stops at
    `== green two workers world-lock smoke ==`).
  - Next: isolate `test_green_two_workers_world_lock_smoke` hangs by running the smoke
    standalone with last-op dumps enabled and a watchdog that preserves the inner log.
  - New: `scripts/triage_green_two_workers_world_lock_smoke.sh` loops the world-lock
    smoke with env passthrough and a watchdog (`OREN_WORLD_LOCK_SMOKE_TIMEOUT_SECS`).
  - Trace: standalone `test_green_two_workers_world_lock_smoke` (3 runs, watchdog 120s)
    with `OREN_TRACE_GREEN_LAST_OPS=1` + `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=200`
    completed cleanly (log:
    `build/logs/green_two_workers_world_lock_smoke_stage2_trace_20260304_010842.log`).
  - Trace: `scripts/triage_green_two_workers_world_lock_smoke.sh` (3 runs) completed
    cleanly with last-op dumps (summary log:
    `build/logs/triage_green_two_workers_world_lock_smoke_20260304_011231.log`).
  - Trace: dense world-lock smoke triage (5 runs, watchdog 300s) with
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_green_two_workers_world_lock_smoke_dense_20260304_011459.log`).
  - New: `scripts/triage_stage2_quick_until_world_lock.sh` runs native quick integration
    plus the smokes leading up to `test_green_two_workers_world_lock_smoke` to isolate
    order-sensitive hangs.
  - New: quick flake triage scripts capture the in-flight inner log on SIGTERM/SIGINT
    (writes `*_interrupt.log` alongside the per-run log) for hang forensics.
  - New: `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` prints progress markers inside
    `test_green_two_workers_world_lock_smoke` and dumps `oren_green_last_ops_dump()`
    at key milestones (and every 10 joins) to localize hangs.
  - New: `OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1` + `OREN_TRACE_GREEN_ENTRY_ARGS_SCAN=1`
    guard `__oren_green_entry` against invalid `args_list` (panic + alloc-index scan)
    when debugging entry-args corruption.
  - Trace: stage2 quick-until-world-lock harness (1 run) with last-op dumps completed
    cleanly (log: `build/logs/native_quick_until_world_lock_20260304_011816_run1.log`).
  - Trace: stage2 quick-until-world-lock harness (5 runs, 30s timeouts) completed
    cleanly with last-op dumps (summary log:
    `build/logs/triage_stage2_quick_until_world_lock_5run_20260304_011957.log`).
  - Trace: stage2 quick-until-world-lock harness (5 runs, poll cache enabled) completed
    cleanly with last-op dumps (summary log:
    `build/logs/triage_stage2_quick_until_world_lock_poll_cache_5run_20260304_012514.log`).
  - Trace: stage2 quick-until-world-lock harness with
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_until_world_lock_trace_20260304_012946.log`).
  - Trace: stage2 quick-until-world-lock harness with
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_until_world_lock_trace2_20260304_013258.log`).
  - Trace: stage2 quick-until-world-lock harness (10 runs) with
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_until_world_lock_trace10_20260304_013405.log`).
  - New: quick-until-world-lock harness captures the in-flight inner log on
    SIGTERM/SIGINT (writes `native_quick_until_world_lock_*_interrupt.log`).
  - Trace: stage2 full quick-integration harness (5 runs) with
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_full_trace_20260304_013754.log`).
  - Trace: stage2 full quick-integration harness (10 runs) with
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_full_trace10_20260304_014204.log`).
  - Trace: stage2 full quick-integration harness (5 runs) with
    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_full_poll_cache_trace_20260304_014906.log`).
  - Trace: stage2 full quick-integration harness (10 runs) with
    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` completed cleanly (summary log:
    `build/logs/triage_stage2_quick_full_poll_cache_trace10_20260304_015814.log`).
  - Trace: stage2 full quick-integration harness (20 runs) with
    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` failed on run 14 with
    `Runtime Panic: Indexing on non-container` in
    `__oren_fnwrap_worker_green_alloc_yield_integrity` (logs:
    `build/logs/triage_stage2_quick_full_poll_cache_trace20_20260304_020532.log`,
    `build/logs/native_quick_stage2_flake_20260304_021330_run14_inner.log`).
  - Next: repro the run-14 panic with `OREN_TRACE_GREEN_ENTRY_ARGS=1` and
    `OREN_QI_TRACE_GREEN_LIST=1` to capture args/list metadata at the failing entry.
  - Trace: stage2 full quick-integration harness (20 runs) with
    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` +
    `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50` +
    `OREN_TRACE_GREEN_ENTRY_ARGS=1` + `OREN_QI_TRACE_GREEN_LIST=1` crashed on run 1
    (rc=139; no panic output) after `== green two workers world-lock smoke ==` with no
    world-lock trace markers; inner log includes entry-args + list traces
    (logs: `build/logs/triage_stage2_quick_full_poll_cache_trace20_entry_args_20260304_021500.log`,
    `build/logs/native_quick_stage2_flake_20260304_021500_run1_inner.log`).
  - Next: run world-lock smoke alone with `OREN_TRACE_GREEN_ENTRY_ARGS=1` +
    `OREN_QI_TRACE_GREEN_LIST=1` + `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` to see if
    the segfault reproduces outside the full harness.
  - Trace: standalone world-lock smoke (3 runs) with
    `OREN_TRACE_GREEN_ENTRY_ARGS=1` + `OREN_QI_TRACE_GREEN_LIST=1` +
    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1` + `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50`
    + `OREN_GREEN_POLL_CACHE=1` completed cleanly (summary log:
    `build/logs/triage_green_world_lock_entry_args_20260304_021633.log`).
  - Trace: stage2 full quick-integration harness (5 runs) with
    `OREN_TRACE_LIST_GET_BAD=1` + `OREN_TRACE_LIST_GET_BAD_SCAN=1` plus entry-args/list
    tracing crashed on run 2 (rc=139) during native quick integration; inner log shows
    `trace: green_entry_args ... node=0` followed by a segfault in
    `run_native_quick_integration.sh` (logs:
    `build/logs/triage_stage2_quick_full_poll_cache_trace5_listgetbad_20260304_021923.log`,
    `build/logs/native_quick_stage2_flake_20260304_022003_run2_inner.log`).
  - Trace: stage2 full quick-integration harness (5 runs) with entry-args guard + scan
    (`OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1`, `OREN_TRACE_GREEN_ENTRY_ARGS_SCAN=1`) plus
    list-get-bad tracing crashed on run 1 (rc=139) during native quick integration; inner
    log still shows `trace: green_entry_args ... node=0` but no guard emit before the
    segfault (logs:
    `build/logs/triage_stage2_quick_full_poll_cache_guard_entry_20260304_022731.log`,
    `build/logs/native_quick_stage2_flake_20260304_022731_run1_inner.log`).
  - Trace: stage2 full quick-integration harness (5 runs, guard before trace) still
    segfaulted on run 1 (rc=139) during native quick integration with guard+scan enabled;
    inner log shows `trace: green_entry_args ...` lines but no guard panic before the crash
    (logs: `build/logs/triage_stage2_quick_full_guard_reorder_5run_20260304_023602.log`,
    `build/logs/native_quick_stage2_flake_20260304_023602_run1_inner.log`).
  - New: `OREN_TRACE_GREEN_ENTRY_ARGS_GUARD_LIGHT=1` logs args_list + fn without alloc-index
    access to avoid guard crashes before panic (rolling, 2026-03-04).
  - Trace: stage2 flake harness (1 run) with guard-light + list trace +
    `OREN_GREEN_POLL_CACHE=1` + world-lock tracing completed with extended timeouts;
    guard-light emits throughout the run (logs:
    `build/logs/native_quick_stage2_flake_20260304_024138_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_024138_run1_inner.log`).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    guard-light + entry-args/list tracing segfaulted (rc=139) during native quick
    integration, confirming the crash can happen before the world-lock smoke (logs:
    `build/logs/native_quick_until_world_lock_20260304_024843_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_024843_run1_inner.log`).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    guard-light + list tracing but **no** entry-args trace completed cleanly
    (logs: `build/logs/native_quick_until_world_lock_20260304_025148_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_025148_run1_inner.log`).
  - New: `OREN_TRACE_GREEN_ENTRY_ARGS_LIGHT=1` enables entry-args tracing without
    alloc-index access (lightweight trace-only mode; rolling, 2026-03-04).
  - New: `OREN_TRACE_GREEN_ENTRY_ARGS_LIGHT_STRIDE=<n>` samples entry-args light
    tracing every Nth entry (rolling, 2026-03-04).
  - New: entry-args guard logs include `g` state + args stamp when `node=0` is
    detected (rolling, 2026-03-04).
  - New: `OREN_TRACE_GREEN_ARGS_STAMP=1` now logs args-stamp set events with
    header fields (rolling, 2026-03-04).
  - New: `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=<n>` samples args-stamp set logs
    every Nth stamp (rolling, 2026-03-04).
  - New: runq guard now dumps `g` state + args stamp when `args_list` is
    untracked (`node=0`) (rolling, 2026-03-04).
  - New: spawn alloc logs args_list header/node when args-stamp tracing enabled
    (rolling, 2026-03-04).
  - New: `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=<n>` samples spawn-alloc header
    logging every Nth spawn when args-stamp tracing is enabled (rolling, 2026-03-04).
  - New: spawn alloc now panics immediately if args_list is untracked when
    args-stamp tracing is enabled (rolling, 2026-03-04).
  - New: `oren_green_spawn` logs incoming args_list header when args-stamp
    tracing is enabled (rolling, 2026-03-04).
  - New: `oren_green_spawn` logs args_list header again after world-lock enter
    when args-stamp tracing is enabled (rolling, 2026-03-04).
  - New: `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` enables spawn-alloc args_list
    untracked guard independent of args-stamp tracing (rolling, 2026-03-04).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    entry-args light trace + guard-light + list tracing hit `Indexing on non-container`
    during the poll-cache run (no segfault); `list_trace_dump` shows `node=0` just
    before the panic (logs: `build/logs/native_quick_until_world_lock_20260304_025406_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_025406_run1_inner.log`).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    entry-args light trace + guard-light and list tracing disabled (`OREN_QI_TRACE_GREEN_LIST=0`)
    completed cleanly (logs: `build/logs/native_quick_until_world_lock_20260304_025817_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_025817_run1_inner.log`).
  - New: `OREN_QI_TRACE_GREEN_LIST_LIGHT=1` emits list trace labels/indices without
    calling `oren_type_tag`/`oren_type_name` or list predicates (rolling, 2026-03-04).
  - New: `OREN_QI_TRACE_GREEN_LIST_LIGHT_STRIDE=<n>` samples list trace light output
    every N indices (rolling, 2026-03-04).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    entry-args light + guard-light + list trace light segfaulted (rc=139) during
    native quick integration (logs:
    `build/logs/native_quick_until_world_lock_20260304_030124_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_030124_run1_inner.log`).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    list trace light enabled but entry-args tracing disabled completed cleanly
    (logs: `build/logs/native_quick_until_world_lock_20260304_030625_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_030625_run1_inner.log`).
  - Trace: quick-until-world-lock run with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1`,
    entry-args light + guard-light + list trace light with stride=8 completed cleanly
    (logs: `build/logs/native_quick_until_world_lock_20260304_030837_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_030837_run1_inner.log`).
  - Trace: stage2 flake harness (5 runs) with entry-args light + guard-light +
    list trace light stride=8 segfaulted on run 1 during native quick integration
    (logs: `build/logs/native_quick_stage2_flake_20260304_031123_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_031123_run1_inner.log`).
  - Trace: stage2 flake harness (5 runs) with entry-args light + guard-light and
    list tracing disabled (`OREN_QI_TRACE_GREEN_LIST=0`) still failed on run 3 with
    `Indexing on non-container`; `list_trace_dump` shows node=0 at `oren_list_get`
    (logs: `build/logs/native_quick_stage2_flake_20260304_031436_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_031436_run3_inner.log`).
  - Trace: quick-until-world-lock run with list corrupt tracing enabled
    (`OREN_TRACE_LIST_CORRUPT=1`, cap=4) completed cleanly with list/entry traces off
    (logs: `build/logs/native_quick_until_world_lock_20260304_031616_run1.log`,
    `build/logs/native_quick_until_world_lock_20260304_031616_run1_inner.log`).
  - Trace: stage2 flake harness (5 runs) with list corrupt tracing enabled
    (`OREN_TRACE_LIST_CORRUPT=1`, cap=8) still failed on run 5 during the poll-cache
    run with `Indexing on non-container` and `list_trace_dump` node=0 at
    `__oren_fnwrap_worker_green_alloc_yield_integrity` (logs:
    `build/logs/native_quick_stage2_flake_20260304_032019_run5.log`,
    `build/logs/native_quick_stage2_flake_20260304_032019_run5_inner.log`).
  - Trace: stage2 flake harness (3 runs) with list header guard enabled
    (`OREN_QI_TRACE_GREEN_LIST_GUARD=1`) and list/entry traces off completed cleanly
    (logs: `build/logs/native_quick_stage2_flake_20260304_032233_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_032344_run3.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    `OREN_GREEN_POLL_CACHE=1` completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_033208_run10.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled **and**
    entry-args light tracing re-enabled segfaulted on run 1 during native quick
    integration (logs: `build/logs/native_quick_stage2_flake_20260304_033409_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_033409_run1_inner.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard off) segfaulted on run 3
    during native quick integration (logs:
    `build/logs/native_quick_stage2_flake_20260304_033702_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_033702_run3_inner.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard off) segfaulted on run 2
    during native quick integration (logs:
    `build/logs/native_quick_stage2_flake_20260304_034443_run2.log`,
    `build/logs/native_quick_stage2_flake_20260304_034443_run2_inner.log`).
  - Trace: stage2 flake harness (20 runs target) with list header guard enabled
    and entry-args/list traces off timed out on run 10 (rc=143) during the
    poll-cache run; inner log stops after the poll-cache header without panic
    (logs: `build/logs/native_quick_stage2_flake_20260304_035219_run10.log`,
    `build/logs/native_quick_stage2_flake_20260304_035219_run10_inner.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args/list traces off completed cleanly after raising
    `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=60` (log:
    `build/logs/native_quick_stage2_flake_20260304_035944_run10.log`).
  - Trace: stage2 flake harness (20 runs) with list header guard enabled and
    entry-args/list traces off completed cleanly with
    `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=60` (log:
    `build/logs/native_quick_stage2_flake_20260304_041252_run20.log`).
  - Trace: stage2 flake harness (5 runs) with list header guard enabled plus
    post-`oren_list_get` pointer guard completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_034111_run5.log`).
  - Trace: stage2 flake harness (5 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard off, stride=32) completed
    cleanly (log: `build/logs/native_quick_stage2_flake_20260304_041850_run5.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard off, stride=32) timed out
    on run 3 (rc=143) during the poll-cache run; inner log stops after the
    poll-cache header (logs: `build/logs/native_quick_stage2_flake_20260304_122903_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_122903_run3_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_122903_run3_err.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard off, stride=32) failed on
    run 2 after raising `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=90` with
    `OREN_DIAG` fail code 797 in
    `test_gc_stw_wakes_netpoll_blocked_threads` during native quick integration
    (logs: `build/logs/native_quick_stage2_flake_20260304_123235_run2.log`,
    `build/logs/native_quick_stage2_flake_20260304_123235_run2_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_123235_run2_err.log`).
  - Trace: stage2 flake harness (5 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard on, stride=32) completed
    cleanly (log: `build/logs/native_quick_stage2_flake_20260304_123621_run5.log`).
  - Trace: stage2 flake harness (10 runs) with list header guard enabled and
    entry-args light tracing (guard-light on, guard on, stride=32) failed on
    run 1 with `Indexing on non-container`; `list_trace_dump` shows `node=0`
    in `oren_list_get` (logs: `build/logs/native_quick_stage2_flake_20260304_123756_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_123756_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_123756_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list header guard enabled plus
    list-light tracing (stride=8) and entry-args guard/light (stride=32)
    completed cleanly (log: `build/logs/native_quick_stage2_flake_20260304_123932_run1.log`).
  - Trace: stage2 flake harness (5 runs) with list header guard enabled plus
    list-light tracing (stride=8) and entry-args guard/light (stride=32) failed
    on run 1 with `Indexing on non-container`; `list_trace_dump` shows `node=0`
    in `oren_list_get` (logs: `build/logs/native_quick_stage2_flake_20260304_124116_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_124116_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_124116_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list header guard enabled plus
    list-light tracing (stride=1) and entry-args guard/light (stride=32)
    completed cleanly (log: `build/logs/native_quick_stage2_flake_20260304_124245_run1.log`).
  - Trace: stage2 flake harness (5 runs) with list header guard enabled plus
    list-light tracing (stride=1) and entry-args guard/light (stride=32)
    segfaulted on run 2 during native quick integration (logs:
    `build/logs/native_quick_stage2_flake_20260304_124453_run2.log`,
    `build/logs/native_quick_stage2_flake_20260304_124453_run2_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_124453_run2_err.log`).
  - Trace: stage2 flake harness (1 run) with list header guard enabled plus
    list-light tracing (stride=1) and entry-args guard on (entry-args light off)
    segfaulted during native quick integration before list-light output emitted
    (logs: `build/logs/native_quick_stage2_flake_20260304_124631_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_124631_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_124631_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list-light disabled and entry-args
    guard on (entry-args light off) failed with `Indexing on non-container`;
    `list_trace_dump` shows `node=0` for args list in
    `__oren_fnwrap_worker_green_alloc_yield_integrity` (logs:
    `build/logs/native_quick_stage2_flake_20260304_124803_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_124803_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_124803_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list guard/light disabled and
    entry-args guard on (entry-args light off) segfaulted during native quick
    integration (logs: `build/logs/native_quick_stage2_flake_20260304_124943_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_124943_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_124943_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled and entry-args
    guard on (guard-light off, entry-args light off) hit `green entry args_list
    not tracked` (guard `node=0`), then also logged `Indexing on non-container`
    with `list_trace_dump` showing `node=0` (logs:
    `build/logs/native_quick_stage2_flake_20260304_125154_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_125154_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_125154_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled and entry-args
    guard on (guard-light off, entry-args light off) timed out on run 1 (rc=143);
    inner log was empty (logs:
    `build/logs/native_quick_stage2_flake_20260304_125415_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_125415_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_125415_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled and entry-args
    guard on (guard-light off, entry-args light off) hit `green entry args_list
    not tracked` with `node=0`; guard dump shows `g` magic/state and empty args
    stamp (logs: `build/logs/native_quick_stage2_flake_20260304_125629_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_125629_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_125629_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_125823_run1.log`).
  - Trace: stage2 flake harness (5 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` failed on run 2 with `green runq guard:
    args_list untracked` during `spawn_alloc`/`entry` (logs:
    `build/logs/native_quick_stage2_flake_20260304_130219_run2.log`,
    `build/logs/native_quick_stage2_flake_20260304_130219_run2_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_130219_run2_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` timed out on run 1 (rc=143); inner log was
    empty (logs:
    `build/logs/native_quick_stage2_flake_20260304_130411_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_130411_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_130411_run1_err.log`).
  - Trace: stage2 flake harness (5 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` failed on run 1 with `green runq guard:
    args_list untracked`; runq dump shows `spawn_alloc` g has empty stamp while
    an `entry` g stamp is populated (logs:
    `build/logs/native_quick_stage2_flake_20260304_130610_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_130610_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_130610_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` completed cleanly with spawn-alloc header
    logging enabled (log: `build/logs/native_quick_stage2_flake_20260304_130842_run1.log`).
  - Trace: stage2 flake harness (5 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` ended on run 1 with rc=137 while emitting
    only spawn-alloc/entry traces (no guard panics captured) (logs:
    `build/logs/native_quick_stage2_flake_20260304_131131_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_131131_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_131131_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=15` (log:
    `build/logs/native_quick_stage2_flake_20260304_131338_run1.log`).
  - Trace: stage2 flake harness (3 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=15` (log:
    `build/logs/native_quick_stage2_flake_20260304_131635_run3.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=8` completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_131909_run1.log`).
  - Trace: stage2 flake harness (3 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=16`, and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=8`
    failed on run 1 with `green runq guard: args_list untracked`; spawn_alloc stamp
    was empty while entry stamp populated (logs:
    `build/logs/native_quick_stage2_flake_20260304_133143_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_133143_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_133143_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=64`, and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=64`
    failed with `green spawn_alloc: args_list untracked` before stamping; a subsequent
    entry guard also saw `args_list` node=0 (logs:
    `build/logs/native_quick_stage2_flake_20260304_133447_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_133447_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_133447_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=64`, and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=64`
    failed with `green spawn_alloc: args_list untracked` while `oren_green_spawn`
    logs show tracked args_list headers up to the failure (logs:
    `build/logs/native_quick_stage2_flake_20260304_133732_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_133732_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_133732_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=64`, and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=64`
    completed cleanly with post-world-lock spawn header logging enabled (log:
    `build/logs/native_quick_stage2_flake_20260304_134013_run1.log`).
  - Trace: stage2 flake harness (3 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    `OREN_TRACE_GREEN_ARGS_STAMP_STRIDE=64`, and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=64`
    ended on run 1 with rc=137; pre/post world-lock spawn logs show args_list
    still tracked up to the end of the inner log (logs:
    `build/logs/native_quick_stage2_flake_20260304_134319_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_134319_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_134319_run1_err.log`).
  - Trace: stage2 flake harness (3 runs) with entry-args tracing disabled and
    args-stamp/spawn logging sampled at stride=128 ended on run 3 with rc=138
    (bus error) after spawn logs (logs:
    `build/logs/native_quick_stage2_flake_20260304_134703_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_134703_run3_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_134703_run3_err.log`).
  - Trace: stage2 flake harness (1 run) with tracing off and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` timed out on run 1 (rc=143); inner
    log was empty (logs:
    `build/logs/native_quick_stage2_flake_20260304_134941_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_134941_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_134941_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with tracing off and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=15` (log:
    `build/logs/native_quick_stage2_flake_20260304_135238_run1.log`).
  - Trace: stage2 flake harness (3 runs) with tracing off and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=15` (log:
    `build/logs/native_quick_stage2_flake_20260304_135650_run3.log`).
  - Trace: stage2 flake harness (3 runs) with tracing off and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=30` (log:
    `build/logs/native_quick_stage2_flake_20260304_140000_run3.log`).
  - Trace: stage2 flake harness (5 runs) with tracing off and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` completed cleanly with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=30` (log:
    `build/logs/native_quick_stage2_flake_20260304_140741_run5.log`).
  - Trace: stage2 flake harness (3 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=256) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_141133_run3.log`).
  - Trace: stage2 flake harness (5 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=256) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` ended on run 5 with rc=139
    (segmentation fault) after spawn traces (logs:
    `build/logs/native_quick_stage2_flake_20260304_141628_run5.log`,
    `build/logs/native_quick_stage2_flake_20260304_141628_run5_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_141628_run5_err.log`).
  - Trace: stage2 flake harness (5 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=256) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` ended on run 4 with rc=1 and
    `green spawn_alloc: args_list untracked` panic (followed by
    `Indexing on non-container`) after spawn traces (logs:
    `build/logs/native_quick_stage2_flake_20260304_142117_run4.log`,
    `build/logs/native_quick_stage2_flake_20260304_142117_run4_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_142117_run4_err.log`).
  - Trace: stage2 flake harness (5 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=256) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=0` ended on run 1 with rc=138 (bus error)
    after spawn traces (logs:
    `build/logs/native_quick_stage2_flake_20260304_142341_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_142341_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_142341_run1_err.log`).
  - Trace: stage2 flake harness (5 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=1024) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` ended on run 1 with rc=139
    (segmentation fault) after spawn traces (logs:
    `build/logs/native_quick_stage2_flake_20260304_142726_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_142726_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_142726_run1_err.log`).
  - New: `OREN_TRACE_GREEN_SPAWN_RING=1` enables a small spawn ring buffer in
    `oren_green_spawn`/`_green_spawn_alloc_g` (cap via
    `OREN_TRACE_GREEN_SPAWN_RING_CAP`, default 128) and dumps recent entries on
    spawn-alloc guard panics.
  - Trace: stage2 flake harness (1 run) with spawn ring enabled
    (`OREN_TRACE_GREEN_SPAWN_RING=1`, cap=64), guard on, and other tracing off
    timed out (rc=143) (logs:
    `build/logs/native_quick_stage2_flake_20260304_143243_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_143243_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_143243_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with spawn ring enabled (cap=64),
    guard on, and longer timeouts (60s) completed cleanly (logs:
    `build/logs/native_quick_stage2_flake_20260304_143450_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_143450_run1_inner.log`).
  - Trace: stage2 flake harness (3 runs) with spawn ring enabled (cap=64),
    guard on, and longer timeouts (60s) completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_143647_run1.log`).
  - Trace: stage2 flake harness (5 runs) with spawn ring enabled (cap=64),
    guard on, and longer timeouts (60s) timed out on run 3 (rc=143) (logs:
    `build/logs/native_quick_stage2_flake_20260304_144207_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_144207_run3_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_144207_run3_err.log`).
  - Trace: stage2 flake harness (1 run) with spawn ring (cap=64) plus list
    header ring + ptr guard (`OREN_TRACE_LIST_HDR_RING=1`,
    `OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1`, cap=2048) completed cleanly (logs:
    `build/logs/native_quick_stage2_flake_20260304_144424_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_144424_run1_inner.log`).
  - Trace: stage2 flake harness (3 runs) with spawn ring (cap=64) plus list
    header ring + ptr guard (cap=2048) completed cleanly (logs:
    `build/logs/native_quick_stage2_flake_20260304_144738_run3.log`,
    `build/logs/native_quick_stage2_flake_20260304_144738_run3_inner.log`).
  - Trace: stage2 flake harness (5 runs) with spawn ring (cap=64) plus list
    header ring + ptr guard (cap=2048) completed cleanly (log:
    `build/logs/native_quick_stage2_flake_20260304_145137_run4.log`).
  - Trace: stage2 flake harness (10 runs) with spawn ring (cap=64) plus list
    header ring + ptr guard (cap=2048) timed out on run 1 (rc=143) (logs:
    `build/logs/native_quick_stage2_flake_20260304_145424_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_145424_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_145424_run1_err.log`).
  - Trace: stage2 flake harness (1 run) with spawn ring + list header ring
    ptr guard + dup detection (`OREN_TRACE_LIST_HDR_RING_DUP=1`, cap=128)
    completed cleanly (logs:
    `build/logs/native_quick_stage2_flake_20260304_145635_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_145635_run1_inner.log`).
  - Trace: stage2 flake harness (3 runs) with spawn ring + list header ring
    ptr guard + dup detection (cap=128) completed cleanly (logs:
    `build/logs/native_quick_stage2_flake_20260304_145826_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_145826_run1_inner.log`).
  - Trace: stage2 flake harness (3 runs) with tracing mostly off but
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (stride=128) and
    `OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1` ended on run 1 with rc=138 (bus error)
    after spawn logs (logs:
    `build/logs/native_quick_stage2_flake_20260304_140213_run1.log`,
    `build/logs/native_quick_stage2_flake_20260304_140213_run1_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_140213_run1_err.log`).
  - Trace: stage2 flake harness (5 runs) with list tracing disabled, entry-args
    guard on (guard-light off, entry-args light off), `OREN_TRACE_GREEN_ARGS_STAMP=1`,
    and `OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=8` ended on run 2 with rc=137 while
    emitting only spawn-alloc/entry traces (no guard panics captured) (logs:
    `build/logs/native_quick_stage2_flake_20260304_132306_run2.log`,
    `build/logs/native_quick_stage2_flake_20260304_132306_run2_inner.log`,
    `build/logs/native_quick_stage2_flake_20260304_132306_run2_err.log`).
  - Trace: stage2 flake harness (5 runs) with trace knobs off
    (`OREN_TRACE_GREEN_ENTRY_ARGS=0`, `OREN_TRACE_GREEN_ARGS_STAMP=0`, list tracing off)
    completed cleanly (log: `build/logs/native_quick_stage2_flake_20260304_132732_run5.log`).
  - New: `OREN_QI_STOP_BEFORE_WORLD_LOCK=1` skips the world-lock smoke in
    `triage_stage2_quick_until_world_lock.sh`.
  - Trace: skip-before-world-lock run completed cleanly (log:
    `build/logs/native_quick_until_world_lock_20260304_012236_run1.log`).
  - Note: `make test` hit `test-native-quick-stage2` Error 139 on 2026-03-03
    (log: `build/logs/make_test_20260303_233334.log`); rerun passed
    (log: `build/logs/make_test_20260303_233544.log`).
  - Trace: stage2 quick-integration flake harness ran 10 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage2_quick_20260303_214758.log`).
  - New: `scripts/triage_native_quick_flake.sh` runs stage1 native quick integration in a loop
    and captures per-run logs for flake diagnosis; supports `ENV=VAL` passthrough args
    for tracing, logs git/uname metadata, and saves failure copies of the inner
    quick-integration log (2026-03-03).
  - New: `scripts/triage_native_quick_flake.sh` can auto re-run flakes with guardrails via
    `OREN_QI_AUTO_RERUN_GUARDRAILS=1`; override env with
    `OREN_QI_AUTO_RERUN_ENV='KEY=VAL ...'` for guardrail capture (2026-03-04).
  - New: `scripts/triage_native_quick_flake.sh` supports per-run jitter via
    `OREN_QI_JITTER_MAX_MS=<n>` to vary scheduling when chasing timing-sensitive flakes
    (2026-03-04).
  - New: `scripts/run_native_quick_integration.sh` supports phase controls via
    `OREN_QI_SKIP_BASE_RUN=1`, `OREN_QI_SKIP_GREEN_CACHE=1`,
    `OREN_QI_STOP_AFTER_GREEN_CACHE=1`, or `OREN_QI_ONLY_GREEN_CACHE=1` to isolate
    quick-integration timeouts (2026-03-04).
  - New: `scripts/run_native_quick_integration.sh` supports `OREN_QI_GREEN_CACHE_FIRST=1`
    to run the green-cache phase before the base run and `OREN_QI_GREEN_CACHE_RUNS=<n>`
    to repeat the green-cache phase (2026-03-04).
  - New: green spawn alloc guard now dumps raw args_list header + list debug traces
    when the args_list is untracked, before panicking (2026-03-04).
  - Trace: stage1 quick-integration flake harness ran 5 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage1_quick_20260303_215453.log`).
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_191243.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_191323.log`).
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_193526.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_193613.log`).
   - Gate: deterministic fixtures + Tier-1 matrix.

7) **SIMD + typed-buffer kernels for list<int> hot paths**
   - Baseline (arm64 native, 2026-02-26): `dot_product_int` 2.55× C.
   - arm64 NEON + x64 SSE2 baseline; keep scalar equivalence.
   - Gate: `dot_product_int` native <= 2x C.

8) **AVM unboxed list<int> payload + lowering**
   - Improve OBC parity for dot/sum loops.
   - Gate: list<int> fixtures + OBC perf parity.

9) **W4 feature set completeness (essential modern features)**
   - Implement across backends (C/native/OBC): `yield`/stackless coroutines, structured error model,
     visibility boundaries, bytes + typed buffers.
   - Implemented (rolling): core `assert(cond, msg?)` statement + `oren test` runner.
   - Implemented (rolling): call-site spread + user-defined varargs (incl. `print(xs...)`).
   - Design spec: `docs/design/structured_error_model.md` (2026-03-05).
   - Not implemented yet: dynamic module loading; user-defined methods/inheritance (track when design lands).
   - Gate: feature fixtures across backends + updated `docs/LANGUAGE.md`/`docs/STATUS.md`.

10) **W3 structural/SOLID refactors (large files)**
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

11) **Tooling reliability and reproducibility**
   - Keep build/test/bench workflows stable and fast.
   - Done: enable `--python` embedding flags for stage0 MSVC builds (bootstrap/windows parity).
   - Fix AVM build breaks that block `make verify-backend-parity-tags` (select case parsing + helper visibility + headers).
   - Investigate repeated `/v1/tools` polling failures from `index-*.js`
     (fetch to `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?...`).
     Repo search (`rg "agent1/proxy"`, `rg "v1/tools"`) found no references here; need the
     owning component path to proceed.
     New: UI at `http://127.0.0.1:54514/` reports frequent failed fetches to
     `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?tools=host&yolo=1&host_policy=full&session_id=...`,
     suggesting aggressive polling + scheme/port mismatch (2026-02-26).
     Update: UI lives in the `agent` repo; added loopback scheme inference + tools query backoff
     (staleTime/refetch suppression). Build ok
     (log: `/Users/zongbaolu/work/agent/build/logs/ui_build_20260226_211713.log`, 2026-02-26).
   - Gate: `make test`, `make benchmarks`, and snapshot updates are deterministic.

---

When a task is completed or re-scoped, update `docs/STATUS.md` and the relevant
fixtures/tests to keep the rolling truth accurate.
