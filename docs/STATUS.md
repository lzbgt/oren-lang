# Status + Tracker (Rolling)

**Last updated:** 2026-03-05

This document is intentionally lean: active tracker + feature matrix.
No archives. No stubs. When a task is done enough, summarize it and move on.

---

## How to use this tracker

- Start at P0 and take the first unfinished item.
- Tie work to a regression gate (benchmark or test).
- Update fixtures and this doc when behavior changes.
- High-level goals live in `docs/BLEEDING_EDGE_TASKS.md`.

---

## Maturity definition (rolling, measurable)

Oren is "mature" when all are reliably true on Tier-1 targets
(`arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`):

- Buildability: stage0 -> stage1 -> stage2 works with minimal setup.
- Semantic parity: native/C/bytecode behavior matches the fixtures.
- Performance budgets: hot loops and allocation are within target ratios vs C.
- Docs fidelity: docs match tests and the code that enforces them.
- Stdlib quality: NET/TLS/HTTP/WS loopback suites pass on Tier-1.

---

## Production readiness gap (rolling snapshot)

Oren is not yet at production parity with industrial compilers (LLVM/rustc/GCC/zig/go):

- **Semantic maturity**: tagged value model is still rolling in native; `oren_type_tag` is best‑effort for scalars and cross‑backend parity is still enforced via fixtures (see `docs/DESIGN.md`).
- **Performance parity**: native hot loops remain >2× C (see perf tracker baselines: `loop_sum` 3.35×, `dot_product` 2.62×; latest `alloc_churn` 5.54×, `alloc_drop` 1.58× on arm64, 2026-03-05).
- **Runtime robustness**: GC reuse and allocator paths are still experimental; list header corruption investigations are ongoing (tracked below).
- **Platform breadth**: Tier‑1 intent targets are arm64‑macOS, arm64‑linux, x64‑linux, x64‑windows; x64 targets are still in rolling bring‑up.
- **Tooling/ABI stability**: ABI/opcode stability is explicitly rolling; compatibility guarantees are not declared.
- **Feature set maturity**: essential modern features are still planned (see `docs/LANGUAGE.md`):
  `yield`/stackless coroutines, structured error model, visibility boundaries,
  first-class bytes + typed buffers; dynamic module loading and user-defined methods remain unimplemented.

Design intent is bleeding‑edge (determinism + capability gating + AVM), but execution maturity is still in the rolling phase.

---

## Production readiness scorecard (weighted, rolling snapshot)

Weighted categories map directly to the tracker items below; W5 dominates "how far"
Oren is from LLVM/rustc/GCC/zig/go parity today.

1) **W5 - Semantic parity (tagged values + fixtures)**
   - Native tagged values are still rolling; `oren_type_tag` is best‑effort for scalars.
   - Cross‑backend parity is enforced via fixtures, not a stabilized ABI.

2) **W5 - Performance parity (hot loops + alloc/GC)**
   - Baselines: `loop_sum` 3.35× C, `dot_product` 2.62× C; latest `alloc_churn` 5.54× C, `alloc_drop` 1.58× C (arm64, 2026-03-05).
   - Priority: hot loops remain above the 2× gate; alloc_drop and alloc_churn are within the 5×/8× gates.
   - Target gates: loops <= 2× C; alloc_churn <= 8× C; alloc_drop <= 5× C.

3) **W5 - Runtime robustness (GC reuse + allocator invariants)**
   - GC reuse paths are experimental; list header corruption investigations are ongoing.
   - Guardrails and traces exist, but correctness gates are not yet stable.
   - Fix: rtobj seed keys now include trace hash opts (alloc_req/list_hdr/list_reserve) so
     trace builds cannot reuse non-trace runtime objects under cache hits (2026-03-03).
   - Fix: free_nodes reuse now enforces canonical node headers (48 bytes + magic) and raw-node
     reuse is re-enabled with integrity guards to avoid invalid pointers (2026-03-03).
   - Repro (2026-02-26): `benchmarks/run_benchmarks.py` dot_product Oren C build panicked with
     `gc list header corrupt` (log: `build/logs/bench_build_oren_c_dot_product_20260226_145741.log`).
   - Fix: GC list header validation now accepts 16-byte aligned inline header sizes to avoid
     false corruption on small caps (2026-02-26).
   - Fix: list_reserve now attempts alloc-index recover + header re-track before panicking
     on non-list headers to reduce false positives under GC churn (2026-02-26).
  - New: free-list header dumps now emit list_hdr ring traces when validation fails, to
    correlate last header writes with corrupted free-list entries (2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now auto-enables free-list header dumps
    and list_hdr ring capture to reduce trace setup friction (2026-02-26).
   - Fix: host-thread green spawn/join now uses world-lock critical sections when enabled,
     preventing races in multi-worker world-lock mode (2026-02-26).
   - Fix: host metadata lookups (`oren_find_node`) now enter the world lock when workers
     are active, avoiding list/map metadata races during world-lock tests (2026-02-26).
   - Verified: dot_product Oren C benchmark build/run now completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_oren_c_20260226_155530.log`).
   - Verified: dot_product_int Oren C benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_oren_c_20260226_155726.log`).
   - Verified: dot_product_int Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_native_20260226_161550.log`).
   - Verified: dot_product Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_native_20260226_161555.log`).
   - New: list corruption checks now flag len/cap invariants and reserve-fail traces log header fields (2026-02-25).
   - New: green scheduler struct allocations now rebuild/force GC tracking before tagging kind=STRUCT,
     preventing args-list GC under `OREN_GREEN_POLL_CACHE=1` (2026-02-25).
   - New: map checks rebuild the alloc-index once on non-map detection to avoid false panics under GC churn (2026-02-26).
   - New: list len checks rebuild the alloc-index once on non-list detection to avoid false panics under GC churn (2026-02-26).
   - New: alloc-index recovery scans live allocs on map/list misses to reinsert missing nodes before panicking (2026-02-26).
   - New: list/map constructors re-track headers when alloc-index misses to prevent untracked containers under GC stress (2026-02-26).
   - New: map/list checks re-track headers on alloc-index misses when magic+cap look sane to reduce false panics (2026-02-26).
   - Fix: green spawn/entry now re-track args_list headers on alloc-index misses when magic+len/cap look sane to avoid false panics under GC churn (2026-03-04).
   - New: arm64/x64 `oren_list_len` intrinsics now fall back to magic+count on untracked headers
     to avoid false panics under GC stress (2026-02-26).
   - New: `oren_track_alloc_new` now de-duplicates existing alloc-index nodes to prevent duplicate
     tracking entries under reuse/GC churn (2026-02-26).
   - New: `make test-native-quick-gc-stress-stage2` runs quick integration with forced GC
     (`OREN_GC_ALLOC_THRESHOLD=20000`) and longer timeouts (2026-02-26).
   - New: `make verify-native-quick-gc` runs the standard native quick verify plus GC-stress
     quick integration to catch tracking regressions (2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX=1` now reports `dedup_hits` for alloc-index de-dup
     in `oren_track_alloc_new` (2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX_DEDUP_CAP=<n>` panics when dedup hits exceed `n`
     (trace-only guardrail, 2026-02-26).
   - New: list header/buffer alloc requests emit cap/bytes context when
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1` triggers (`[list_hdr_req]`, `[list_buf_req]`, 2026-02-26).
   - New: list growth/reserve now guards `cap > 1<<30` as corruption to avoid overflow
     and to fail fast on bad headers (2026-02-26).
   - New: GC mark now validates list/list_int headers and panics on corruption
     before scanning payloads (2026-02-26).
   - New: optional list header poisoning on GC free sets magic to `list_magic_poison`
     (`OREN_GC_POISON_LIST_HEADERS=1`); reuse precheck tolerates poison while GC mark
     remains strict to surface use-after-free (2026-02-26).
  - New: list header ring guard now logs `[list_hdr_ring_ptr_guard_last_corrupt]` when
    `g_trace_list_hdr_ring_ptr_guard_last` is not 0/1 to catch unexpected writes (2026-02-27).
  - New: `scripts/triage_native_quick_stage2_flake_debug.sh` + `make test-native-quick-stage2-flake-debug`
    run the stage2 quick integration loop with spawn ring + list header ring guardrails
    enabled for flake triage; timeouts can be overridden via
    `OREN_NATIVE_RUN_TIMEOUT_SECS` / `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS` /
    `OREN_NATIVE_BUILD_TIMEOUT_SECS` (2026-03-04).
  - New: `scripts/triage_native_quick_flake_debug.sh` + `make test-native-quick-flake-debug`
    provide the same guardrail triage for stage1 native quick integration (2026-03-04).
  - New: `make verify-backend-parity` runs all cross-backend parity smokes in one shot
    (boxed list, list<int>, tags, arith panics, index panics) (2026-03-04).
  - New: `scripts/verify_backend_parity_*.sh` accepts `OREN_BACKEND_PARITY_TRACE_ENV`
    to forward trace env vars into build/run steps for deeper corruption diagnosis
    (2026-03-04).
  - Trace: `OREN_BACKEND_PARITY_TRACE_ENV='OREN_TRACE_LIST_HDR_RING=1 OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1 OREN_TRACE_LIST_HDR_RING_CAP=4096 OREN_TRACE_LIST_CORRUPT=1'`
    allows `make verify-backend-parity` to complete cleanly on 2026-03-04 (log: `build/logs/verify_backend_parity_trace_20260304.log`).
  - Trace: stage2 native quick integration segfaulted during QI dbg sugar (rc=139);
    log: `build/logs/oren_stage2_native_quick_flake_20260304_161224_run1.log` (2026-03-04).
  - Trace: stage2 quick flake debug guardrail run (3 runs) completed cleanly under
    list header ring + spawn ring + list corruption tracing (log:
    `build/logs/triage_stage2_flake_debug_20260304_183646.log`, 2026-03-04).
  - Trace: stage2 quick flake debug run (5 runs) with list_hdr dup + gc_list_hdr_kind
    tracing completed cleanly (log:
    `build/logs/triage_stage2_flake_debug_dup_20260304_184142.log`, 2026-03-04).
  - Trace: stage1 quick flake debug run (5 runs) with list_hdr dup + gc_list_hdr_kind
    tracing completed cleanly (log:
    `build/logs/triage_stage1_flake_debug_dup_20260304_184754.log`, 2026-03-04).
  - Trace: stage1 quick flake (5 runs) with list corruption tracing and larger ring
    capacity completed cleanly (log:
    `build/logs/triage_stage1_flake_noguard_20260304_185130.log`, 2026-03-04).
  - Trace: stage1 quick flake (30 runs) with list corruption tracing (no guardrails)
    segfaulted at run 4 (rc=139); log:
    `build/logs/triage_stage1_flake_noguard_30_20260304_185445.log` (run log:
    `build/logs/oren_native_quick_flake_20260304_185547_run4.log`, 2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (20 runs) with list corruption
    tracing + free-list ring passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_trace_20260304_185657.log`, 2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + list header
    ring (cap 8192) and extended timeouts passed cleanly (log:
    `build/logs/triage_stage1_flake_ringonly_timeout_20260304_190448.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + green spawn
    ring only passed cleanly (log:
    `build/logs/triage_stage1_flake_spawn_ringonly_20260304_191042.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + list header
    ring dup guard (cap 8192) passed cleanly (log:
    `build/logs/triage_stage1_flake_list_ringdup_20260304_191425.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + free-list
    ring passed cleanly (log:
    `build/logs/triage_stage1_flake_freelist_ring_20260304_191805.log`,
    2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (5 runs) after args_list retrack
    passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_retrack_20260304_210139.log`,
    2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (20 runs) with jitter
    (`OREN_QI_JITTER_MAX_MS=50`) after args_list retrack passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_retrack_jitter_20260304_210806.log`,
    2026-03-04).
  - Trace: stage1 quick flake (50 runs) with jitter (`OREN_QI_JITTER_MAX_MS=50`) and
    auto rerun guardrails hit rc=143 at run 16; auto rerun with guardrails succeeded
    (log: `build/logs/triage_stage1_flake_autorun_jitter_20260304_195330.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_194557_run16.log`,
    guardrails log:
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
    `build/logs/triage_stage1_flake_jitter_notrace_20260304_195411.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_195754_run12.log`,
    2026-03-04).
  - Trace: stage1 quick flake with jitter + auto rerun guardrails (no list tracing on
    base run) segfaulted at run 7 (rc=139); auto rerun guardrails succeeded (log:
    `build/logs/triage_stage1_flake_jitter_autorun_notrace_20260304_195907.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_200108_run7.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_200108_run7_guardrails.log`,
    2026-03-04).
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
    `build/logs/triage_stage1_flake_jitter_autorun_greenfirst_20260304_202152.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_202353_run7.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_202353_run7_guardrails.log`,
    2026-03-04).
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
  - Fix: AVM truthiness now treats int zero as truthy to match Oren semantics
    (only `nil`/`false` are falsey) (2026-03-04).
  - New: `scripts/triage_arith_div0_c_build_flake.sh` + `make test-native-quick-arith-div0-flake`
    loop a C-backend build fixture (default `arith_div0.oren`, override with
    `OREN_TRACE_ARITH_SRC=...`) with list header ring guardrails to reproduce
    list_int header corruption (2026-03-04).
  - New: `scripts/verify_runtime_robustness_w5.sh` + `make verify-runtime-robustness`
    run the W5 runtime-robustness smoke (stage2 quick integration + C-backend build
    fixtures) with guardrail traces; optional `OREN_RUNTIME_ROBUSTNESS_TRACE_ENV` forwards
    trace env vars into child scripts for faster production-readiness triage. Make target
    knobs: `OREN_RUNTIME_ROBUSTNESS_RUNS`, `OREN_RUNTIME_ROBUSTNESS_COMPILER`,
    `OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS`, `OREN_RUNTIME_ROBUSTNESS_C_RUNS`,
    `OREN_RUNTIME_ROBUSTNESS_C_FIXTURES`, and `OREN_RUNTIME_ROBUSTNESS_TRACE_ENV` (2026-03-04).
  - New: `scripts/triage_native_quick_flake.sh` supports auto re-run with guardrails via
    `OREN_QI_AUTO_RERUN_GUARDRAILS=1`; override env with
    `OREN_QI_AUTO_RERUN_ENV='KEY=VAL ...'` to capture guardrail traces on flakes
    (2026-03-04).
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
   - Trace: global slot dump maps `idx=434` / `off=3472` to `g_trace_list_hdr_ring_ptr_guard_last`
     after rebuilding stage2 (`alloc_churn_build_globals_idx434_manual_20260227.log`, 2026-02-27).
   - Trace: precheck_guard9 (cached + no-cache) still shows bad-list roots with
     `root_slot_offset=3472` while `guard_last=1` and no guard-last-corrupt logs; suggests
     root-slot offset may not reflect g_storage (`alloc_churn_trace_precheck_guard9_20260227.log`,
     `alloc_churn_trace_precheck_guard9_nc_20260227.log`, 2026-02-27).
   - Trace: after bounding root-slot offsets to `boot_globals_storage` (512 bytes),
     precheck_guard10 now reports `root_slot_offset=-1` while bad-list roots persist,
     confirming the earlier 3472 offset was outside g_storage
     (`alloc_churn_trace_precheck_guard10_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_ROOT_SLOTS=1` shows `root_idx=35`, `list_len=409`, and the
     global-roots entry at `i=35` points to a slot pointer outside g_storage whose value
     equals the bad-list ptr, indicating the root list is pointing at a non-g_storage slot
     (`alloc_churn_trace_precheck_guard13_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_REGISTER_ROOT=1` shows early roots registered at
     `slot_off=-8` (g_storage slot) and `slot_off=528..560` (heap spill slots);
     `OREN_TRACE_GC_ROOT_MATCHES=1` shows three root slots (idx 35/117/182) whose
     slot values equal the bad-list ptr with `slot_off=2376..3552` (all outside the 512B
     boot globals range) (`alloc_churn_trace_precheck_guard15_nc_20260227.log`, 2026-02-27).
   - Trace: compile-time global slot mapping shows `slot_off=2376/2896/3584` correspond to
     `g_gc_reuse_bad_list_triggers`, `g_runtime_root_len`, and `g_trace_list_header`,
     suggesting global int slots are being overwritten by bad-list pointers
     (`alloc_churn_globals_trace_20260227_072238.log`, 2026-02-27).
   - Trace: pending root tags now flush once envp-derived tracing is enabled, showing
     runtime init’s `value_nil/false/true` registrations with `pending=1`
     (`alloc_churn_trace_precheck_guard22_nc_20260226.log`, 2026-02-26).
   - Tool: `OREN_TRACE_GC_REGISTER_ROOT` now tags known call sites; untagged entry-stub
     roots are skipped unless `OREN_TRACE_GC_REGISTER_ROOT_ALL=1` is set. New summary
     knob `OREN_TRACE_GC_ROOT_SLOT_SUMMARY=1` reports boot vs non-boot root slots
     (sample cap via `OREN_TRACE_GC_ROOT_SLOT_SUMMARY_CAP`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_GLOBAL_GUARD=1` logs when `g_gc_reuse_bad_list_triggers`,
     `g_runtime_root_len`, or `g_trace_list_header` hold pointer-like values to help
     pinpoint corruption timing (rolling, 2026-02-27).
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
  - Tool: `scripts/repro_bad_list_alloc_churn.sh` brute-forces alloc_churn configs until a
    `[gc_reuse_bad_list]` hit is found, printing ptr/node filters for follow-up tracing; it
    continues across crashes, logs non-zero exit statuses, and captures stderr in logs
    (set `EXTRA_TRACE=1` to include reuse summary + list-hdr kind/ok traces, 2026-02-27).
  - Tool: `tools/trace_list_hdr_correlate.py --log <log> --limit 5 --max 50` now surfaces
    `list_corrupt` and `gc_list_*_corrupt` events alongside free-list samples and attaches
    ring dumps when present to pinpoint last header writes (2026-03-05).
  - Tool: `tools/run_alloc_churn_hunt.sh [max_runs] [tag_base]` repeats alloc_churn traces
    until a corruption signature is observed (or a timeout/failure stops the run), using
    the trace harness logs under `build/logs/` (set `ALLOC_CHURN_HUNT_CORRELATE=0` to skip
    auto-correlation; tune via `ALLOC_CHURN_HUNT_CORRELATE_LIMIT/MAX`).
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

4) **W4 - Platform breadth (Tier‑1 intent targets)**
   - arm64 is most mature; x64 Linux/Windows are still in rolling bring‑up.

5) **W4 - Feature set completeness (essential modern features)**
   - Planned (not yet implemented): `yield`/stackless coroutines, structured error model,
     visibility boundaries, bytes + typed buffers
     (see `docs/LANGUAGE.md` "Planned (Essential Modern Language Features)").
   - Design spec: `docs/design/structured_error_model.md` (2026-03-05).
   - New: `std:result` smoke fixture wired into native quick integration
     (`tests/fixtures/tier1_native_result_smoke_main.oren`, 2026-03-05).
   - New: `std:list` structured helpers (`try_len`/`try_get`/`try_set`/`try_last`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - New: `std:buffer` slice helpers return `oren_err` on invalid input; covered by
     result smoke fixture (2026-03-05).
   - New: `std:encoding/base64.decode_bytes` error handling covered by result
     smoke fixture (2026-03-05).
   - New: `std:encoding/base64.encode_bytes` validates input and returns `oren_err`
     on invalid values; covered by result smoke fixture (2026-03-05).
   - New: `std:encoding/base64.decode_bytes_strict` rejects whitespace; covered by
     result smoke fixture (2026-03-05).
   - New: `std:crypto/pem.decode_blocks_strict` rejects whitespace inside base64
     payloads; covered by result smoke fixture (2026-03-05).
   - New: `std:strings` structured helpers (`try_len`/`try_char_at`/`try_slice`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - New: `std:bytes` structured helpers (`try_len`/`try_get_u8`/`try_set_u8`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - New: `std:bytes` hex helpers (`try_from_hex`/`try_to_hex`) validate inputs and
     return `oren_err` on invalid values; covered by result smoke fixture (2026-03-05).
   - New: `std:buffer` structured helpers (`try_len`/`try_load_u8`/`try_store_u8`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - Implemented (rolling): core `assert(cond, msg?)` statement and `oren test` runner for
     `test "name" { ... }` blocks (2026-03-04).
   - Implemented (rolling): call-site spread + user-defined varargs (incl. `print(xs...)`)
     covered by native quick integration + varargs fixtures (2026-03-04).
   - Not implemented: dynamic module loading; user-defined methods/inheritance (see `docs/LANGUAGE.md`).
   - Interim: `std:assert` helper module provides `assert`/`assert_eq` in the stdlib (2026-03-03).

6) **W3 - Tooling/ABI stability**
   - ABI/opcode stability is explicitly rolling; compatibility guarantees are not declared.
   - AVM build/parity gate integrity is tracked as a W4 blocker when broken (select case parsing + helper exports; 2026-02-25).

7) **W3 - Docs fidelity + regression gates**
   - Docs are grounded in fixtures/tests; gaps get surfaced via parity gates.

8) **W3 - Structural/SOLID debt**
   - Large source files remain a maintainability risk; measured (non-generated, non-web) >2000 lines:
     - None >2000 lines (2026-03-03).
   - Splits underway:
     - GC safepoint helpers moved out of `lib/compiler/arm64_native_stmt.oren` into
       `lib/compiler/arm64_native_gc.oren` (2026-02-25).
     - `lib/compiler/arm64_native_stmt.oren` split into focused loop/list/runtime modules:
       `lib/compiler/arm64_native_stmt_loops.oren`,
       `lib/compiler/arm64_native_stmt_loops_list.oren`,
       `lib/compiler/arm64_native_stmt_loops_list_emit.oren`,
       `lib/compiler/arm64_native_stmt_loops_base.oren`,
       `lib/compiler/arm64_native_stmt_runtime.oren` (all <2000 lines, 2026-02-25).
     - `lib/compiler/transpiler.oren` split into focused core/analysis/C-utils/lambda modules
       (all <2000 lines, 2026-02-25).
     - `lib/compiler/optimizer.oren` split into focused core/fold/DCE/list-int/list-reserve/TCO modules
       (all <2000 lines, 2026-02-25).
     - `lib/runtime_native/100_time_gc_alloc.oren` core split into scan/reuse, list_hdr, track, roots_gc
       modules (all <2000 lines, 2026-03-03).
     - `lib/runtime_native/170_lists.oren` split into core + api modules (all <2000 lines, 2026-03-03).
     - `lib/compiler/optimizer_loops.oren` split into `lib/compiler/optimizer_loops_list.oren` and
       `lib/compiler/optimizer_loops_arena.oren` (both <2000 lines, 2026-02-25).
     - `lib/compiler/arm64_native_program.oren` split into `lib/compiler/arm64_native_program/*`
       modules (all <2000 lines, 2026-03-03).
     - `lib/avm/main.c` split into CLI-focused modules (`avm_cli_util`, `avm_cli_verify`,
       `avm_cli_policy`, `avm_cli_fs`, `avm_cli_disasm`, `avm_cli_dump`)
       (all <2000 lines, 2026-02-25).
     - `lib/avm/avm_vm.c` split into focused VM modules (`avm_vm_core`,
       `avm_vm_sched`, `avm_vm_values`, `avm_vm_list_ops`)
       (all <2000 lines, 2026-02-25).
     - `lib/compiler/x64_native_program/060_emit_ops.oren` split into focused emit modules
       (`055_emit_ops_locals`, `056_emit_ops_match`, `057_emit_ops_while_emit`)
       (all <2000 lines, 2026-02-25).

---

## Regression gates (run first)

Local (fast):

- `make test`
- `make verify-native-quick`
- `make verify-backend-parity-boxed-list`
- `make verify-backend-parity-list-int`
- `make verify-backend-parity-tags`
- `make verify-backend-parity-arith-panics`
- `make verify-backend-parity-index-panics`
- `make verify-runtime-robustness`
- `./scripts/verify_x64_linux_qemu_smoke.sh`

Note: `make verify-backend-parity-tags` depends on AVM CLI/VM build; keep select-case parsing + helper visibility in sync with the split.

Remote verify scripts support `OREN_REMOTE_SCP_TIMEOUT_SECS` to bound scp hangs.

Tier-1 cross-arch (when touching native/runtime/net):

- `./scripts/verify_native_matrix.sh`
- `./scripts/verify_native_net_matrix.sh`
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
- `./scripts/verify_stage0_windows_bootstrap.sh`

Periodic perf gates (when touching performance-critical paths):

- `make benchmarks`
- `make bench-native-compile`

---

## Performance parity tracker (weighted, 2026-02-26 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026-02-26).
Weights reflect expected impact on C parity and breadth of affected code.

1) **W5 - Native integer hot-loop parity (loop_sum, dot_product)** (L)
   - Baseline (arm64 native, snapshot 2026-02-26): `loop_sum` 3.33× C, `dot_product` 2.57× C.
   - New run (arm64, 2026-03-05, runs=3, warmups=1):
     - loop_sum: C 0.067194s, native 0.225078s (3.35× C) (log: `build/logs/bench_run_perf_gate_20260305_021914.log`).
     - dot_product: C 0.005185s, native 0.013571s (2.62× C) (log: `build/logs/bench_run_perf_gate_20260305_021914.log`).
   - Expand inty propagation and arithmetic fast paths.
   - Split runtime init vs steady-state cost and quantify the init gap (see `benchmarks/RESULTS_LATEST.md` notes).
     - New: `OREN_BENCH_INIT_SPLIT=1` adds loop_sum init/steady estimation (see `benchmarks/README.md`).
     - New: capsule-only NET/PROC tables now allocate in `native_runtime_capsule_init` to reduce non-capsule runtime init cost; remeasure init/steady split (2026-02-25).
     - New: `OREN_TRACE_RUNTIME_INIT=1` prints native_runtime_init phase timings.
   - Init/steady split (loop_sum, arm64 macOS, 2026-03-05, n=20,000,000; reps=1 vs 10; 3 runs):
      - C: init 0.003130s, steady 0.064991s
      - Oren C: init 0.002705s, steady 0.059376s
      - Native: init 0.001412s, steady 0.225120s
   - Const-divisor `%` is now inlined for literal/const RHS (arm64 + x64).
   - New: native LCG fast loops use reciprocal-based fastmod when mod constants fit (arm64 + x64).
   - Boxed list dot/get-sum regression guard added to native QI (2026-02-19).
   - Fast-loop safepoints now reset GC tick after safepoint to avoid tick spills (arm64 list-sum, x64 LCG sum).
   - Native fast list-dot loops now use per-list cursors (when lists are unique per mul) to avoid per-iter index multiplies.
   - Native fast list get-sum loops now use per-list cursors (when lists are unique per load) to avoid per-iter index multiplies.
   - Int-only list literals now lower to `list<int>` even when non-empty and use unchecked pushes on native/OBC to preserve fast paths (rolling, 2026-02-20).
   - Safe list<int> get/len now rewrite to unchecked header paths (`oren_list_int_get_unchecked`, `oren_list_int_len_unchecked`) on native backends (rolling, 2026-02-24).
   - Arm64 fast list_int get-sum loops now accept `list_int_get_unchecked` calls to preserve the fast path after rewriting (rolling, 2026-02-24).
   - Arm64 list<int> get-sum + dot fast loops use inline safepoint ticks (register-based) while keeping the stack tick slot to avoid the offset regression (rolling, 2026-02-25).
   - Safepoint throttling for list<int> hot loops: arm64 list<int> sum/dot mask=4095; x64 list<int> sum/dot mask=1023.
   - X64 boxed-list fast loops (push/get-sum/dot) now throttle safepoints at mask=1023 to reduce hot-loop overhead (rolling, 2026-02-25).
   - Arm64 list<int> get-sum + dot fast loops now keep i/sum in registers across iterations to reduce stack traffic (rolling, 2026-02-26).
   - Arm64 boxed list get-sum + dot fast loops now keep i/sum in registers across iterations to reduce stack traffic (rolling, 2026-02-26).
   - Fix: arm64 boxed fast list dot loop now initializes X10 tick mask before inline safepoint ticks (2026-02-26).
   - LCG fast loop safepoint mask now 4095 on arm64 + x64 (rolling, 2026-02-26).
   - LCG fast loop unroll-by-2 on arm64 + x64 to reduce loop overhead (rolling, 2026-02-26).
   - New: `OREN_TRACE_ARM64_LOOP_STACK=1` logs loop stack/tick layout for arm64 loop emitters to debug tick slot offsets.
   - Trace (arm64 compile, 2026-02-26, `OREN_TRACE_ARM64_LOOP_STACK=1`):
     - loop_sum: `while_generic` tick_off=0 (stacks=160/176/224, slots=2, bytes=16).
     - dot_product: `fast_list_int_push_while` tick_off=0 (stack=208, slots=7, bytes=64);
       `fast_list_int_dot_while` tick_off=0 (stack=224, slots=8, bytes=64);
       `while_generic` tick_off=0 (stacks=224/240, slots=2, bytes=16).
   - Stage2 trace rebuilds with `OREN_TRACE_ARM64_LOOP_STACK=1` (2026-02-26) completed without GC list-header corruption.
   - New debug knob: `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` removes the tick stack slot for
     `fast_list_int_dot_while` to isolate the arm64 tick-offset regression (trace kind=`fast_list_int_dot_while_no_tick`).
   - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): `fast_list_int_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
   - New debug knob: `OREN_TRACE_ARM64_GC_TICK_OFF=1` logs negative tick offsets in arm64 GC throttled safepoints
     (set to `all` to log every tick_off).
   - New debug knob: `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` removes the tick stack slot for
     `fast_list_dot_while` (trace kind=`fast_list_dot_while_no_tick`).
   - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): dot_product still lowers via list<int> fast loops; no `fast_list_dot_while_no_tick`
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
   - New: `OREN_TRACE_ARM64_GC_TICK_OFF=1` now tags traces with `kind=<loop_kind>` when available to
     attribute negative tick offsets to a specific loop emitter (2026-03-03).
   - New: arm64 GC tick-off trace now includes the last loop stack snapshot (`last_kind`, `last_base`,
     `last_stack`, `last_slots`, `last_bytes`, `last_tick_off`) when tick_off is negative (2026-03-03).
   - TODO: root-cause the arm64 offset regression when removing the tick stack slot and safely eliminate the unused slot.
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

2) **W5 - Allocation/GC overhead reduction (alloc_churn, alloc_drop)** (L)
   - Baseline (arm64 native, 2026-02-26): `alloc_churn` 6.62× C, `alloc_drop` 1.28× C.
   - New run (arm64, 2026-03-04, runs=5, warmups=1; log: `build/logs/bench_alloc_churn_drop_20260304_235146.log`):
     - alloc_churn: C 0.002886s, native 0.015997s (5.54× C).
     - alloc_drop: C 0.002986s, native 0.004703s (1.58× C).
   - Bytecode note: `oren_gc_collect()` now lowers to a no-op in the bytecode backend so alloc_churn/alloc_drop OBC builds succeed (2026-03-04).
   - `alloc_churn` and `alloc_drop` are now within the 8×/5× gates on arm64.
   - Alloc-site trace (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, warmups=0):
     - `alloc_churn` median total=2 (list_int_header=1, list_int_buf=1, list_header=0, list_buf=0).
     - `alloc_drop` median total=108 (list_header=105, list_buf=3, list_int_header=0, list_int_buf=0).
   - Fix and enable reuse paths (`OREN_GC_REUSE_BLOCKS`) when correct.
   - Add allocation-site counters for `alloc_churn`/`alloc_drop` to pinpoint dominant allocations.
   - New: `OREN_TRACE_ALLOC_SITE=1` reports list/list_int header+buffer sites (ids 1..4; see `lib/runtime_native/170_lists.oren`).
   - New: `OREN_GC_REUSE_LISTS=1` allows reuse for list/list_int headers when `OREN_GC_REUSE_BLOCKS=1` (rolling guardrail).
     - Rolling safety: list reuse is disabled when `OREN_GC_AUTO=1` unless `OREN_GC_REUSE_LISTS_UNSAFE=1`.
   - New: `OREN_GC_REUSE_MAPS=1` / `OREN_GC_REUSE_STRUCTS=1` allow reuse for map/struct headers (rolling guardrail).
   - New: `OREN_GC_REUSE_ZERO=1` zero-fills reused blocks by default when reuse is enabled (set `OREN_GC_REUSE_ZERO=0` to disable).
   - New: `OREN_GC_REUSE_SCAN_CAP=<n>` limits the free-list scan length during reuse (0 = unbounded).
   - New: `OREN_TRACE_GC_REUSE=1` now reports `scan_steps`, `scan_cap_hits`, and `scan_steps_cap`
     to quantify free-list scan cost under a cap.
   - New: `OREN_GC_REUSE_BUCKETS=1` enables size-bucketed free lists (<=64/<=256/<=1024/>1024 bytes).
   - New: `OREN_TRACE_GC_REUSE_VERBOSE=1` logs capped reuse hits (cap via `OREN_TRACE_GC_REUSE_VERBOSE_CAP`).
   - New: `OREN_TRACE_GC_FREED_LISTS=1` records freed list pointers; `OREN_TRACE_GC_FREED_LISTS_CAP=<n>` controls ring size.
   - New: `OREN_TRACE_GC_STACK_RANGES=1` captures stack scan ranges per collection (cap via `OREN_TRACE_GC_STACK_RANGES_CAP`).
   - Verbose reuse logs now include `in_roots` plus `root_kind` (1=gc_pin, 2=runtime roots, 3=global roots) and `root_idx`, alongside `in_stack`.
   - Reuse guard now restores free-list nodes that are still referenced by roots/stack; `[gc_reuse]` includes `guard_live`.
   - List reuse guard validates header integrity and drops corrupt candidates; `[gc_reuse]` includes `guard_bad_list`.
    - Trace rejected list headers with `OREN_TRACE_GC_REUSE_BAD_LIST=1` (cap via `OREN_TRACE_GC_REUSE_BAD_LIST_CAP`).
    - Trace freed list headers with `OREN_TRACE_GC_FREE_LIST_HEADERS=1` (cap via `OREN_TRACE_GC_FREE_LIST_HEADERS_CAP`).
   - Trace list header writes with `OREN_TRACE_LIST_HEADER=1` (cap via `OREN_TRACE_LIST_HEADER_CAP`).
   - Trace list buffer allocations with `OREN_TRACE_LIST_BUF=1` (cap via `OREN_TRACE_LIST_BUF_CAP`).
   - Trace optimizer list reserve insertion with `OREN_TRACE_LIST_RESERVE=1`.
   - Trace implausible `track_alloc_new` sizes with `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1`
     (default min 1<<30; tunable via `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN`/`_CAP`).
   - New: `OREN_TRACE_LIST_GET_BAD=1` logs list-get diagnostics when `Indexing on non-container`
     or `Indexing on non-list` triggers (cap via `OREN_TRACE_LIST_GET_BAD_CAP`).
   - New: `OREN_TRACE_LIST_GET_BAD_SCAN=1` scans the alloc-index table for the offending
     pointer on `list_get_bad` (expensive; use only for targeted flake triage).
   - New: `OREN_TRACE_GREEN_RUNQ_ARGS=1` logs `g->fn_obj/args_list` metadata at green
     runq push/pop/steal to trace scheduler corruption (use sparingly).
   - New: `OREN_TRACE_GREEN_RUNQ_GUARD=1` asserts runq `g` magic + args_list list headers
     on spawn/enqueue/dequeue, panicking with details instead of bus errors (debug-only).
   - New: `OREN_TRACE_GREEN_ARGS_STAMP=1` snapshots spawn-time args_list headers and
     checks for drift at runq/entry (panics on mismatch; debug-only).
   - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD=1` validates cached poll `ts/s/p` pointers
     and runq_buf before deref (debug-only).
   - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD_EVERY=<n>` samples the poll-cache guard
     every N cached iterations (debug-only).
   - New: `OREN_TRACE_GREEN_LAST_OPS=1` captures a ring of recent green runq/entry
     operations and dumps on `oren_fail`/`oren_panic`/`oren_exit`
     (cap via `OREN_TRACE_GREEN_LAST_OPS_CAP`).
   - New: `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=<n>` dumps the last-op ring
     every N cached poll iterations (debug-only).
   - Trace: `alloc_churn` run with size tracing shows `size=160000` corresponds to a list_int
     buffer (`cap=20000`, bytes=160000), so the size log is expected
     (log: `build/logs/bench_run_alloc_churn_20260226_084444/oren_native/run_0.log`).
   - Trace: GC-stress quick integration with list reserve/corrupt tracing enabled emitted
     only alloc-index summaries (no list_reserve/list_corrupt events)
     (log: `build/logs/native_quick_gc_trace_20260226_084741.log`).
   - Trace native pre-track alloc requests with `OREN_TRACE_NATIVE_ALLOC_REQ=1`
     (emits `oren_trace_alloc_request` before `oren_track_alloc_new` on native backends).
   - New: `OREN_TRACE_NATIVE_LIST_HDR=1` enables arm64 + x64 fast‑path list header tracing (calls `oren_trace_list_header` on list/list_int push fast paths).
     - Arm64 fast list push while-loops now emit list header traces on the count update (rolling, 2026-02-25).
   - GC init now registers the main thread for stack scanning to avoid missing roots during auto-GC reuse tests.
   - New: `OREN_TRACE_GC_REUSE=1` prints reuse tries/hits/misses at GC sweep.
   - Historical GC reuse experiments (2026-02-20) showed list header corruption before reuse; detailed traces live under `build/logs/`.
    - List trace now re-checks env when envp/argv/argc change to avoid caching off before runtime init (rolling, 2026-02-25).
    - New alloc_churn trace (arm64, 2026-02-25, `OREN_TRACE_NATIVE_LIST_HDR=1` + `OREN_TRACE_LIST_HEADER=1`, cap=200):
      - `op=6` list_int_reserve to cap=128 (per list), followed by `op=7` list_int_push count update after the fast loop.
    - New alloc_churn free-list trace (arm64, 2026-02-25, `OREN_ARENA_AUTO_LOOP=0`, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`,
      `OREN_TRACE_LIST_HEADER=1`, `OREN_GC_ALLOC_THRESHOLD=1000`): list_int headers free with len/cap=128 and magic ok, but
      free-list `chunk` sizes are huge (~6.16e9) and `freed_bytes` spikes, suggesting tracking-node size corruption even when
      header fields look valid (log: `build/logs/alloc_churn_free_list_trace_20260225_200907.log`).
    - New alloc_churn free-list trace with list_hdr_ring (arm64, 2026-02-25, `OREN_TRACE_LIST_HDR_RING=1`):
      - list_hdr_ring shows `op=2/6/7` (new_list_int/reserve/push) with valid len/cap/magic before free, while
        `gc_free_list_node` reports huge `size` with intact node magic, reinforcing that the tracking-node size field is corrupt
        rather than the list header itself (log: `build/logs/alloc_churn_free_list_trace_20260225_202512.log`).
    - New alloc_churn track-size trace (arm64, 2026-02-25, `OREN_TRACE_LIST_TRACK_SIZE=1`):
      - list_int allocations are tracked with a huge `size` (~6.12e9) at `oren_track_alloc_new` time, before header fields
        are initialized (len/cap/magic = 0), which means the corruption is already present in the `size` argument passed
        into tracking (log: `build/logs/bench_run_alloc_churn_20260225_203557/oren_native/run_0.log`).
    - New: arm64 native `malloc_k` preserves size across kind-eval (compiler fix, 2026-02-25).
      - Follow-up alloc_churn trace with `OREN_TRACE_LIST_NEW_CAP=1` + `OREN_TRACE_LIST_TRACK_SIZE=1` shows no list allocations
        with size >= 1 MiB, suggesting the huge-size tracking corruption may be resolved (log: `build/logs/bench_run_alloc_churn_20260225_205122/oren_native/run_0.log`).
      - Follow-up GC free-list trace (arm64, `OREN_GC_AUTO=1`, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`, cap=40) shows list_int frees with
        `chunk=32` and no huge sizes (log: `build/logs/bench_run_alloc_churn_20260225_210209/oren_native/run_0.log`).
      - NOTE: a heavier trace run (GC auto + list header/native list traces) triggered `list_int_reserve on non-list` panic; needs triage
        to confirm whether the trace stack or GC path can still corrupt list metadata (log: `build/logs/bench_run_alloc_churn_20260225_205603/oren_native/run_0.log`).
      - New: same GC auto trace without `OREN_TRACE_NATIVE_LIST_HDR` completes and shows sane free-list chunks + list headers, suggesting the
        panic is tied to native list tracing (log: `build/logs/bench_run_alloc_churn_20260225_210329/oren_native/run_0.log`).
      - New: after spilling list ptr to stack around `oren_trace_list_header`, GC auto trace with `OREN_TRACE_NATIVE_LIST_HDR=1` completes
        cleanly with sane free-list chunks (log: `build/logs/bench_run_alloc_churn_20260225_210830/oren_native/run_0.log`).
    - New: alloc_drop with the same native trace knobs also completes cleanly and shows sane free-list chunks
        (log: `build/logs/bench_run_alloc_drop_20260225_211047/oren_native/run_0.log`).
    - Partial alloc_drop free-list trace (arm64, 2026-02-25, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`): list headers free with normal
      chunk sizes (32/64) and valid magic (log: `build/logs/alloc_drop_free_list_trace_20260225_200437.log`).
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
    - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING_RECENT=<n>` dumps the last `n` ring entries for a sampled
      free-list header to focus on the most recent writes (2026-03-05).
    - Trace: alloc_churn with ring-recent shows list_int size mismatches (`chunk=32`, `expect=1056`)
      alongside recent ring ops `6:8 -> 2:8`; correlation log helps pinpoint last header writes
      (logs: `build/logs/alloc_churn_trace_gc_ring_recent_20260305_014912.log`,
      `build/logs/alloc_churn_trace_gc_ring_recent_20260305_014912_corr.log`).
    - Fix: free-list size-mismatch logging now matches list header validation (accepts aligned
      inline sizes and adjacent external buffers) to reduce false positives in traces (2026-03-05).
   - Repro (2026-03-05): higher-pressure alloc_churn with GC poison + reuse + list_int
     (`OREN_BENCH_LIST_LEN=512`, `OREN_GC_ALLOC_THRESHOLD=5000`) hits
     `gc list_int header corrupt` (log:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_20260305_020406.log`).
   - Repro (2026-03-05): same env with `OREN_TRACE_GC_REUSE_BAD_LIST_CAP=4` triggers
     `gc_reuse_bad_list` and `gc list_int header corrupt`; ring dump shows only op=91
     entries (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap_20260305_023629_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap_20260305_023629_1_correlate2.log`).
   - Repro (2026-03-05): with fast list_int loop ring emission enabled, corruption still
     shows only op=91 entries (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap2_20260305_024825_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap2_20260305_024825_1_correlate.log`).
   - Repro (2026-03-05): with ring_pre enabled (and arena list ring emission), still only
     op=91 entries; arena off does not change (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre2_20260305_025533_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre2_20260305_025533_1_correlate.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre3_arenaoff_20260305_025745_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre3_arenaoff_20260305_025745_1_correlate.log`).
   - Repro (2026-03-05): enabling `OREN_TRACE_ALLOC_KIND_CHANGE` triggers an early segfault
     before any trace output (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_kindflip_20260305_025937_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_kindflip2_20260305_030010_1.log`).
   - Update (2026-03-05): fast_list_int_push_while now emits list_hdr ring entries on loop
     exit even without compile-time trace flags, so GC corruptions can be correlated from
     standard trace runs.
   - Update (2026-03-05): arena list/list_int allocations now emit list_hdr ring entries
     (op=1/2) so ring dumps include arena-backed list headers.
   - New: `OREN_TRACE_ALLOC_INDEX=1` now logs `[alloc_index_list_bad]` when list/list_int
     nodes are inserted with non-magic headers (excluding poison), to catch kind/ptr drift.
   - New: `OREN_TRACE_LIST_CTOR=1` logs `[list_ctor]` stages (`pre_init`, `post_init`, `post_track`)
     for list/list_int allocations; filter via `OREN_TRACE_LIST_CTOR_PTR` /
     `OREN_TRACE_LIST_CTOR_NODE` to line up ctor events with `[alloc_index_list_bad]`.
   - Repro (2026-03-05): gc_ring_poison_hi_alloc_index shows `[alloc_index_list_bad]` with
     magic=0 at alloc-index insert time, before `gc_reuse_bad_list` fires (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1_correlate.log`,
     `build/logs/alloc_churn_hunt_alloc_index_20260305_030652.log`).
   - Repro (2026-03-05): ctor-trace run shows `[alloc_index_list_bad]` preceding
     `[list_ctor] stage=pre_init` for the same ptr, so alloc-index insertion happens
     before list header init; magic=0 appears expected for fresh allocations
     (log: `build/logs/alloc_churn_trace_gc_ring_poison_hi_ctortrace_20260305_031847.log`).
   - Next: if corruption still shows only op=91 GC entries, consider adding per-iteration
     ring updates under a trace guard to capture in-loop header writes.
   - Update (2026-03-05): alloc-index now emits `[alloc_index_list_zeroed]` only when
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` and headers are still zeroed (magic/len/cap/buf all 0),
     reducing noise in `[alloc_index_list_bad]`.
   - Update (2026-03-05): alloc-index list trace lines now include `zeroed_count`/`bad_count`
     counters to track noise vs true corruption across runs.
   - Update (2026-03-05): GC summary now prints `[alloc_index_list_counts]` when
     `OREN_TRACE_ALLOC_INDEX=1` to report per-sweep zeroed/bad totals.
   - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX=1` +
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` (`OREN_BENCH_ITERS=2000`) reported `zeroed_count=2`
     and `bad_count=0` (log:
     `build/logs/alloc_churn_trace_alloc_index_counts_20260305_033136.log`).
   - Trace (2026-03-05): higher-pressure alloc_churn with GC reuse knobs +
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` reported
     `zeroed_count=256` and `bad_count=0` (log:
     `build/logs/alloc_churn_trace_alloc_index_counts_hi_20260305_033237.log`).
    - New: `OREN_BENCH_LIST_LEN=<n>` lets alloc_churn reduce per-list pushes during trace runs so
      list_hdr ring entries survive until GC sweep samples (2026-02-26).
    - New: runtime reserve trace `OREN_TRACE_LIST_RESERVE_RT=1` (cap via `OREN_TRACE_LIST_RESERVE_RT_CAP`) added; alloc_churn run
      now emits `[list_reserve]` + `[list_buf]` lines, confirming runtime reserve execution
      (log: `build/logs/alloc_churn_run_trace_20260226_013845.log`).
    - New: list_alloc + arena trace (arm64, 2026-02-26) shows list_int headers with `mode=2` (arena ctor) while
      `OREN_TRACE_ARENA=1` reports `allocs=0`, suggesting arena allocs are spilling to malloc or trace enable is late
      (log: `build/logs/alloc_churn_manual_run_list_alloc_arena_20260226_002922.log`).
    - New: `OREN_TRACE_ARENA_SPILL=1` reports arena spill reasons (depth=0, size<=0, cap, mmap failure) to explain
      `mode=2` list allocations with `allocs=0` in arena traces (rolling, 2026-02-26).
    - New: when built with `--backend native` (runtime cache disabled), alloc_churn shows arena allocs=3 with no spills,
      confirming arena is active and prior `allocs=0` was from a non-native build artifact
      (log: `build/logs/alloc_churn_manual_run_arena_spill_native_20260226_003939.log`).
    - New: `OREN_TRACE_NATIVE_LIST_RESERVE=1` emits a fast-loop reserve trace call to
      `oren_trace_list_reserve_fast(...)` so we can verify whether the native fast loop
      actually calls reserve at runtime (rolling, 2026-02-26).
    - New: list buffer trace (`OREN_TRACE_LIST_BUF=1`) now re-checks envp/argv/argc to avoid caching
      off before runtime init, mirroring list header trace behavior (rolling, 2026-02-26).
    - New: alloc_churn native run with `OREN_TRACE_NATIVE_LIST_RESERVE=1` + `OREN_TRACE_LIST_RESERVE_RT=1` shows
      list<int> reserve executes at runtime and allocates 1024-byte buffers via `_list_alloc_buf`
      (log: `build/logs/alloc_churn_manual_run_trace_reserve_fast2_20260226_004803.log`).
      - Follow-up reserve trace shows stage=1/2 pairs per list with no duplicate stage=1 per list
        (log: `build/logs/alloc_churn_run_trace_20260226_013845.log`), so the earlier redundant-reserve suspicion
        is cleared for this run.
    - New: alloc-site tracing now counts arena list buffers; alloc_churn native trace shows
      list_int_header=20000, list_int_buf=20000 (total=40000) under `OREN_BENCH_TRACE_ALLOC_SITE=1`
      (log: `build/logs/bench_alloc_churn_alloc_site_20260225_234114.log`).
    - New: `OREN_TRACE_LIST_RESERVE_BYTES=1` prints reserve allocation/copy totals at shutdown; alloc_churn
      reports list_int_alloc_bytes=20480000 with 20000 reserve calls and zero copy bytes
      (log: `build/logs/alloc_churn_run_reserve_bytes_20260226_020050.log`).
   - New: loop list reuse brings alloc_churn to ~6.62× C (arm64, 2026-02-26),
      within the 8× gate; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`
     (log: `benchmarks/results/alloc_churn_darwin_arm64_20260226_161846.md`).
    - New: loop list reuse keeps alloc_drop at ~1.28× C (arm64, 2026-02-26),
      within the 5× gate (log: `benchmarks/results/alloc_drop_darwin_arm64_20260226_161849.md`).
    - New: reuse escape smoke (`test_loop_list_reuse_escape_smoke`) added to native quick integration
      to guard against incorrect reuse when lists escape (2026-02-26).
    - Fix: loop list reuse now skips unsafe list uses (escape/alias), enabling default-on reuse while
      remaining correctness-safe under `test_loop_list_reuse_escape_smoke` (2026-02-26).
   - New: list-reserve/unchecked-push generalization now treats `oren_new_list(cap)`, `oren_list_new_cap(cap)`,
     `oren_arena_new_list(cap)`, and `oren_arena_new_list_auto(cap)` as list constructors and propagates list metadata across simple alias assignments,
     extending reserve/unchecked-push rewrites (rolling, 2026-02-24).
   - New: list<int> lowering now propagates safe-int context across nested blocks, so empty list literals
     that push ints derived from outer-scope loop indices lower to list<int> (rolling, 2026-02-25).
     - Verified: `alloc_churn` emit-c now uses `oren_new_list_int`, `oren_list_int_reserve`,
       `oren_list_int_push_fast`, and `oren_list_int_get_fast` (log: `build/logs/emit_c_alloc_churn_listint_20260225_035210.log`).
     - New: `OREN_TRACE_LIST_INT=1` logs list<int> lowering decisions (candidate/touch/unsafe/rewrite).
     - Safety: list<int> lowering now skips candidates assigned in nested control-flow blocks
       to avoid mixed list/list<int> rewrites (fixes arena auto-loop use-before-assign smoke; rolling, 2026-02-25).
   - New: loop list reuse hoists safe, non-escaping list allocations out of loops and replaces per-iter
     init with `*_clear_unchecked` calls; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`.
     - Reuse smoke: `test_arena_auto_loop_smoke` passes with reuse enabled on arm64 macOS (2026-02-25).
   - `alloc_churn` native was 46.65× C in the 2026-02-25 snapshot; reached 6.62× C on 2026-02-26,
     but regressed to 104.37× C in the 2026-03-04 snapshot.
   - Alloc-site trace (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, native-only):
     median total=20000, list_int_header=20000, list_header=0, list_buf=0, list_int_buf=0
     (log: `build/logs/bench_alloc_churn_alloc_site_20260225_234114.log`).
   - List alloc trace (arm64, 2026-02-25, `OREN_TRACE_LIST_ALLOC=1`, cap=20): list_int headers
     are allocated at size=32 (cap=0) in arena mode (mode=2), and no list buffer allocations
     were observed even with `OREN_TRACE_LIST_BUF=1` (log: `build/logs/bench_alloc_churn_list_alloc_buf_20260225_235415.log`).
   - Compiler trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1`): `alloc_churn` inserts
     `oren_list_int_reserve(xs, 128)` (log: `build/logs/bench_build_oren_native_alloc_churn_20260226_000335.log`).
   - Combined trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1` + `OREN_TRACE_LIST_ALLOC=1` + `OREN_TRACE_LIST_BUF=1`):
     runtime still shows list_int header allocations (size=32, mode=2) and no list_buf events; compile log did not emit
     list_reserve prints in this run (log: `build/logs/bench_alloc_churn_list_all_20260226_000614.log`).
   - Manual build trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1` + `OREN_TRACE_OPTIMIZER=1`, `--no-cache`):
     `alloc_churn` prints `list_int_reserve name=xs n=128` (log: `build/logs/bench_alloc_churn_manual_build_20260226_001017.log`).
   - Bench run with no-cache env (arm64, 2026-02-26, `OREN_TRACE_LIST_BUF=1` + `OREN_TRACE_LIST_RESERVE=1`):
     no list_buf events appeared and reserve trace did not surface in build logs (log: `build/logs/bench_alloc_churn_nocache_list_buf_20260226_001246.log`).
   - List literal sinking now handles `ExprStmt` if-forms, reducing `alloc_drop` list-header churn
     (alloc-site median list_header=105 in 2026-02-25 trace; latest `alloc_drop` native 1.28× C).
   - New: fast list/list_int push while-loops now accept constant upper bounds (arm64/x64/transpiler),
     and `alloc_drop` is now within target on the 2026-02-25 snapshot (rolling).
   - New: list/list_int reserve + unchecked push now try `native_arena_alloc_raw` for arena-backed buffers
     and fall back to `malloc_k` (cuts alloc-index tracking overhead on arena hot paths; rolling, 2026-02-20).
   - New: list/list_int set growth now uses arena-backed buffer allocation when list headers are arena-tracked,
     matching reserve/push behavior (rolling, 2026-02-24).
    - Reuse + list trace run (arm64, 2026-02-20, reuse+trace flags): still segfaults; reuse summary
      tries=7951 hits=54 misses=7900 hit_bytes=57472 guard_bad_list=105. List trace shows only `op=1/3/5`;
      free-list headers still report len/cap=128 with chunk=32 (same corruption pattern).
    - Free-list header dump now calls `native_list_debug_node` on invalid headers to capture node/alloc-index state (rolling, 2026-02-20).
    - Fresh reuse trace with list_debug (arm64, 2026-02-20): invalid free-list headers show
      `list_debug node_ptr=<ptr> size=32 kind=2 freed=0 next=<ptr>` with node_in_allocs=0 and node_in_free_blocks=0
      at dump time (node already unlinked, index still resolves).
    - Reordered alloc-index removal to run after free-list dumps so list_debug can resolve nodes (rolling, 2026-02-20).
    - Corruption reproduces even with reuse disabled: `OREN_GC_REUSE_BLOCKS=0` still shows free-list headers
      with len/cap=128 and list_debug node_ptr/next but node_in_allocs=0, node_in_free_blocks=0 (arm64, 2026-02-20).
    - New trace: `OREN_TRACE_LIST_CORRUPT=1` (cap via `OREN_TRACE_LIST_CORRUPT_CAP`) logs suspicious list headers
      during reserve/push_unchecked (invalid magic or buf), dumps list_debug state, and emits list_alloc/list_hdr
      ring matches when enabled (rolling, 2026-02-20). List_len/list_reserve and list_int panics now also dump ring matches.
   - New: list indexing (`xs[i]`) rebuilds alloc-index once on non-container detection before panicking
     to avoid false panics from stale index state (rolling, 2026-02-26).
   - List header reuse guard now treats chunk_size==32 as separate-buffer lists even if buf==list+32 (avoids false bad-list hits when allocator places buffers adjacent; rolling, 2026-02-20).
   - List header reuse guard now accepts external-buffer lists whose header allocation still includes stale inline storage (chunk_size > 32 with buf != list+32), avoiding false bad-list hits after growth (rolling, 2026-02-24).
   - List trace env checks now cache false after first lookup (`OREN_TRACE_LIST_HEADER`,
     `OREN_TRACE_LIST_HDR_RING`, `OREN_TRACE_LIST_CORRUPT`) to avoid per-op env scans (rolling, 2026-02-25).
     - Reuse guard enforces inline-buffer sizing: chunk==32+cap*8 when buf==list+32; out-of-line headers accept any chunk>=32 (rolling, 2026-02-24).
     - Prior strict header sizing guard (out-of-line required chunk==32) still segfaulted; guard_bad_list=276 (local run, 2026-02-20).
     - Reuse now rejects alloc-index mismatches for reused pointers (rolling, 2026-02-20).
     - Alloc-index guard run still segfaults; guard_bad_list=275 (local run, 2026-02-20).
     - `alloc_churn` runs when list reuse is guarded off (auto-GC) with reuse blocks only:
       tries=9989 hits≈4987 misses≈5005 hit_bytes≈5.11 MiB (local run, 2026-02-20).
     - `alloc_drop` (runs=1) 12.13s with GC reuse traces (local run, 2026-02-20).
   - Bench harness supports `OREN_BENCH_TRACE_ALLOC_SITE=1` (native) to capture alloc-site counts in benchmark stdout logs (forces warmups=0; dump happens at exit; use `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD` if you want GC-triggered dumps).
   - When trace alloc-site is enabled, benchmark result JSON records `alloc_site` counts + medians.
   - Bench harness supports `OREN_BENCH_TRACE_ARENA=1` (native) to capture arena alloc/spill counters; results JSON records `arena_trace` medians (optional cap via `OREN_BENCH_TRACE_ARENA_CAP_BYTES`).
   - Bench harness supports compile-time env overrides via `OREN_BENCH_ENV_BUILD` (all build steps) and
     `OREN_BENCH_ENV_BUILD_OREN` (Oren build steps only).
   - Bench harness supports `OREN_BENCH_SAVE_RUN_LOGS=1` (per-run stdout logs) and `OREN_BENCH_RUN_LOG_TEE=1` (tee to console) for trace-heavy runs like GC reuse.
   - Alloc-site snapshots from trace runs are stored under `build/logs/` (results files are pruned per policy).
   - New: arena list header allocations now bump alloc-site counters (native `native_arena_new_list(_int)`)
     so arena-backed list headers show up in `OREN_BENCH_TRACE_ALLOC_SITE` runs (rolling, 2026-02-25).
   - Trace alloc-site (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, warmups=0):
     - `alloc_churn` list_header=20000, list_buf=0.
     - `alloc_drop` list_header=1794, list_buf=6.
   - New: list-track now logs `track_alloc` events in `oren_track_alloc` when `OREN_TRACE_LIST_TRACK=1`
     (rolling, 2026-02-25). `alloc_churn` now emits `[list_track] arena_alloc` lines under auto arenas,
     confirming list headers are arena-backed in the default benchmark build.
   - New: `OREN_TRACE_ARENA=1` now reports per-iter arena counters (`iter_push/pop`, `iter_spills`,
     `iter_spill_bytes`) to diagnose per-iteration caps (rolling, 2026-02-25).
   - Trace list-track (arm64, 2026-02-25, `OREN_ARENA_AUTO_LOOP=0` runtime via bench env):
     `alloc_churn` emits `[list_track] index_put/alloc` lines (log:
     `build/logs/bench_run_alloc_churn_20260225_020630/oren_native/run_0.log`),
     confirming GC-tracked list headers when auto arenas are disabled at runtime.
   - Trace alloc_drop reuse (arm64, 2026-02-25, `OREN_BENCH_ITERS=2000`,
     `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=2000`, `OREN_GC_REUSE_BLOCKS=1`,
     `OREN_GC_REUSE_LISTS=1`, `OREN_GC_REUSE_LISTS_UNSAFE=1`):
     run completes; list_track emits `track_alloc` (mode=3), and GC reuse reports
     guard_bad_list=0 with scan_steps in the 2–4.6M range (log:
     `build/logs/bench_run_alloc_drop_20260225_021248/oren_native/run_0.log`).
   - Trace alloc_churn direct reuse (arm64, 2026-02-25, direct native run with
     `OREN_ARENA_AUTO_LOOP=0`, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=1`,
     `OREN_GC_REUSE_LISTS_UNSAFE=1`, `OREN_GC_REUSE_SCAN_CAP=5000`):
     hit `[gc_reuse_bad_list]` quickly (chunk=32 len/cap=128 buf=ptr+32 magic=1279870019)
     with a preceding `[gc_reuse_hit] kind=0` (log:
     `build/logs/alloc_churn_direct_reuse_cap_20260225_021657.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=65536`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.49s vs C 0.00307s (2114×);
     `alloc_drop` 0.2746s vs C 0.003064s (89.6×). This is worse than baseline; cap size
     likely too small for the current allocation profile (log:
     `build/logs/bench_iter_cap_20260225_030936.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=262144`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.50s vs C 0.003316s (1961×);
     `alloc_drop` 0.2745s vs C 0.003150s (87.1×). Still worse than baseline (log:
     `build/logs/bench_iter_cap_256k_20260225_031225.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=1048576`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.51s vs C 0.003024s (2153×);
     `alloc_drop` 0.2753s vs C 0.003061s (89.9×). Still worse than baseline (log:
     `build/logs/bench_iter_cap_1m_20260225_031326.log`).
   - Post list-trace cache (arm64, 2026-02-25, runs=3/warmups=1, native+C only):
     `alloc_churn` 0.311s vs C 0.006686s (46.6×); `alloc_drop` 0.194s vs C 0.008016s (24.3×)
     (log: `build/logs/bench_post_list_trace_cache_20260225_033359.log`).
   - Repeat post list-trace cache (arm64, 2026-02-25, runs=3/warmups=1, native+C only):
     `alloc_churn` 0.237s vs C 0.002871s (82.6×); `alloc_drop` 0.159s vs C 0.003137s (50.8×)
     (log: `build/logs/bench_post_list_trace_cache_repeat_20260225_033511.log`).
   - Post list-trace cache (arm64, 2026-02-25, runs=5/warmups=1, native+C only):
     `alloc_churn` 0.225s vs C 0.003204s (70.3×); `alloc_drop` 0.1568s vs C 0.003079s (50.9×)
     (log: `build/logs/bench_post_list_trace_cache_runs5_20260225_033625.log`).
   - Trace run (arm64, 2026-02-25, `OREN_TRACE_ARENA=1`, `OREN_ARENA_ITER_CAP_BYTES=262144`):
     alloc_churn run emitted 20,000 `[arena]` lines with `iter_spills=0` (cap not binding);
     benchmark aborted with output mismatch due to trace (log:
     `build/logs/bench_iter_cap_256k_trace_20260225_031951.log`,
     run log: `build/logs/bench_run_alloc_churn_20260225_031951/oren_native/run_0.log`).
   - Trace run (arm64, 2026-02-25, `OREN_TRACE_ARENA=1`, `OREN_ARENA_ITER_CAP_BYTES=262144`,
     `OREN_BENCH_OUTPUT_CHECK=0`): alloc_drop run emitted **no** `[arena]` lines, indicating
     the loop is not arena-wrapped (log:
     `build/logs/bench_iter_cap_256k_trace_drop_20260225_032316.log`,
     run log: `build/logs/bench_run_alloc_drop_20260225_032316/oren_native/run_0.log`).
   - Arena-loop trace (arm64, 2026-02-25, `OREN_TRACE_ARENA_LOOPS=1` compile):
     alloc_drop inner loop drops the list literal candidate as `unsafe_use` and
     ends with `skip=no_arena_alloc`, so the loop is not wrapped by arenas
     (log: `build/logs/alloc_drop_arena_loop_trace_20260225_032643.log`).
   - Repro across scan caps (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     scan_cap=1000/5000/20000 each shows `[gc_reuse_hit] kind=0` followed by
     `[gc_reuse_bad_list] chunk=32 len=128 cap=128 buf=ptr+32 magic=1279870019`
     (logs: `build/logs/alloc_churn_direct_reuse_cap1000_20260225_021833.log`,
     `build/logs/alloc_churn_direct_reuse_cap5000_20260225_021853.log`,
     `build/logs/alloc_churn_direct_reuse_cap20000_20260225_021913.log`).
   - New list-alloc ring correlation (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     `[gc_reuse_bad_list_site] ptr=... site=1 mode=1 size=32` confirms bad list headers
     come from GC list header allocations (site=1, mode=1). Log:
     `build/logs/alloc_churn_direct_reuse_list_alloc_ring_20260225_023407.log`.
   - List header ring shows `list_reserve` op with `buf=ptr+32` after growth on a header
     whose allocation chunk is still 32 bytes (adjacent external buffer). The GC reuse
     list-header guard now treats `buf==ptr+32 && chunk_size==32` as valid to avoid
     false bad-list hits (rolling, 2026-02-25).
   - Post-guard trace (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     no `[gc_reuse_bad_list]` lines; gc_reuse summary shows guard_bad_list=0
     (log: `build/logs/alloc_churn_direct_reuse_post_guard_20260225_025057.log`).
   - Higher-verbosity reuse trace (arm64, 2026-02-25, same env with verbose cap=50):
     still no `[gc_reuse_bad_list]`; reuse hits>1k, guard_bad_list=0
     (log: `build/logs/alloc_churn_direct_reuse_post_guard_verbose_20260225_025542.log`).
   - Trace alloc_churn reuse (arm64, 2026-02-25, same reuse env as above) ran >3 min
     and was terminated to keep iteration fast; no trace output captured.
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`, warmups=0):
     - `alloc_churn` panics: `list_reserve on non-list` after `[alloc_site] total=1536 list_header=768 list_buf=768`.
       New trace: stage=1 (node missing), magic matches, count/cap/buf=0, list_debug node=0,
       arena_depth=0 (no arena node or range) (local run log: `build/logs/bench_run_alloc_churn_20260220_132405/oren_native/run_0.log`).
   - New: `OREN_TRACE_LIST_TRACK=1` logs alloc-index insert/remove events for list/list_int headers
     (cap=1024; override with `OREN_TRACE_LIST_TRACK_CAP`, rolling, 2026-02-20).
   - New: `OREN_TRACE_TRACK_ALLOC_NEW=1` logs early `oren_track_alloc_new` events
     (cap via `OREN_TRACE_TRACK_ALLOC_NEW_CAP`, rolling, 2026-02-25).
   - New: `OREN_TRACE_LIST_ALLOC=1` logs list header allocations with alloc-site id and mode
     (1=GC, 2=arena); cap via `OREN_TRACE_LIST_ALLOC_CAP` (rolling, 2026-02-25).
     Ring buffer size for bad-list correlation via `OREN_TRACE_LIST_ALLOC_RING_CAP`
     (default 4096); `gc_reuse_bad_list` now emits a matching `[gc_reuse_bad_list_site]`
     line when the pointer is still in the ring (rolling, 2026-02-25).
   - New: `OREN_TRACE_LIST_HDR_RING=1` records list header mutations (new/reserve/push/set/clear ops,
     including list<int> variants)
     in a ring; `OREN_TRACE_LIST_HDR_RING_CAP` controls size (default 4096). When a
     `gc_reuse_bad_list` is reported, the ring is searched and matching `[list_hdr_ring]`
     entries are emitted (rolling, 2026-02-25).
   - New: `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1` prints alloc-index remove timing stats at GC sweep
     (rolling, 2026-02-20).
   - Trace list-track (arm64, 2026-02-25, `OREN_TRACE_LIST_TRACK=1`, cap=5): `alloc_churn` emits
     `[list_track] arena_alloc` lines, confirming list headers are arena-backed under auto loop arenas.
     Auto-loop rewrites now target `oren_arena_new_list_auto`/`oren_arena_new_list_int_auto`, which consult runtime
     `OREN_ARENA_AUTO_LOOP` to fall back to GC list headers for reuse debugging (explicit `@oren.arena` stays arena-only).
   - New: native GC safepoints now spill callee‑saved registers to the stack before calling
     `oren_gc_safepoint` (arm64: x19–x28; x64: rbx/rbp/rdi/rsi/r12–r15) so conservative stack scans
     see register‑held pointers (rolling, 2026-02-20).
   - New: explicit `oren_gc_safepoint()` calls now use the same spill wrapper in native codegen
     (arm64 + x64), not just loop‑injected safepoints (rolling, 2026-02-20).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`,
     `OREN_TRACE_LIST_TRACK=1`, runs=1): `alloc_churn` completes at 5.035s with list_header=1024, list_buf=1024
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`,
     `OREN_TRACE_LIST_TRACK=1`, `OREN_TRACE_LIST_TRACK_CAP=5000`, runs=1): `alloc_churn` 5.872s with list_header=1024, list_buf=1024
     `build/logs/bench_run_alloc_churn_20260220_134542/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_churn` 5.752s with list_header=1024, list_buf=1024
     `build/logs/bench_run_alloc_churn_20260220_135825/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, after safepoint spill wrapper for explicit calls, runs=1):
     list_track log has no `remove` lines: `build/logs/bench_run_alloc_churn_20260220_140537/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_drop` 0.609s with list_header=821, list_buf=2
     `build/logs/bench_run_alloc_drop_20260220_140749/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`, same env, runs=1):
     list_track log now shows many `remove` lines (see `build/logs/bench_run_alloc_drop_20260220_140954/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, runs=1): `alloc_drop` 18.034s with list_header=137, list_buf=0
     spikes to ~4.1µs, counts ≈550 per sweep (log: `build/logs/bench_run_alloc_drop_20260220_141623/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env but `OREN_GC_ALLOC_THRESHOLD=10000`, runs=1):
     alloc_index_remove counts ≈5700 per sweep with avg ~1–2µs and spikes to ~12–17µs
     (log: `build/logs/bench_run_alloc_drop_20260220_141832/oren_native/run_0.log`).
   - New: alloc-index cleanup during GC sweep now defers to a bulk rebuild when reuse blocks are enabled
     (avoids per-free remove probes; rolling, 2026-02-20).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX=1`, `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, runs=1):
     alloc_index_remove count=0; alloc_index rebuilds ~34–39µs
     (log: `build/logs/bench_run_alloc_drop_20260220_142335/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1):
     alloc_index_remove count=0; alloc_index rebuilds ~67–73µs
     (log: `build/logs/bench_run_alloc_churn_20260220_142427/oren_native/run_0.log`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, default GC threshold, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=32`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=8`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=4`, warmups=1):
   - Trace reuse (arm64, 2026-02-20, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, reuse blocks on,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 19.056s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 10.387s with gc_reuse
     scan_steps min=90, max=10.3M, avg=5.2M across 40 sweeps
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_BUCKETS=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 18.747s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 13.245s with gc_reuse
     scan_steps min=5.6k, max=19.7M, avg=9.9M across 40 sweeps
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_REUSE_SCAN_CAP=32`,
     `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_TRACE_GC_REUSE=1`, output check disabled):
     `alloc_drop` 6.812s with gc_reuse scan_steps min=369, max=36.6k, avg=35.1k; scan_steps_cap
     min=429, max=36.9k, avg=34.5k; scan_cap_hits min=12, max=1114, avg=1041 across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 7.687s with gc_reuse
     scan_steps min=375, max=65.5k, avg=62.1k; scan_steps_cap min=429, max=65.3k, avg=60.4k;
     scan_cap_hits min=12, max=1975, avg=1828 across 40 sweeps
   - New run (arm64, 2026-02-20, runs=5, warmups=1):
     `alloc_churn` 0.131s (48.57× C), `alloc_drop` 0.160s (56.17× C)
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` + `OREN_ARENA_PER_ITER=1`, native only):
     - `alloc_churn` 1620× C, `alloc_drop` 60.18× C (C baseline from `benchmarks/RESULTS_LATEST.md`; no improvement vs default).
     - `OREN_BENCH_TRACE_ARENA=1` emitted no `[arena]` lines for alloc_churn/alloc_drop (likely no arena push/pop in these benches).
   - New run (arm64, 2026-02-20, compile-time auto-loop via `OREN_BENCH_ENV_BUILD_OREN`, runs=1, warmups=0):
     - `alloc_churn` 5.17s (native only), arena trace shows per-iteration allocs=2, push=1, pop=1 (per-iter active; perf worse).
     - `arena_loop` trace still marks alloc_churn's outer loop as long-lived despite `n=20000`; investigate bound detection.
   - New: arena loop bound detection now compares identifier names by value (string equality) in optimizer loops,
     fixing const-int bound lookups that were previously missing when strings were not pointer-equal (rolling, 2026-02-20).
   - New: C backend defines arena push/pop/new_list fallbacks (GC allocs) so auto-loop builds don't fail (rolling, 2026-02-20).
   - New: arena auto-loop wrapping is now gated to the native backend via optimizer config to avoid injecting
     arena calls into C/bytecode builds (rolling, 2026-02-20).
   - New: arena auto-loop is enabled by default for native builds; auto rewrites target
     `oren_arena_new_list_auto` so `OREN_ARENA_AUTO_LOOP=0` at runtime forces GC list headers when debugging.
   - New: long-lived arena bound default lowered to 1024 iterations (override via `OREN_ARENA_LONG_LIVED_BOUND`).
   - New: safe loop-local lists now insert a pre-loop `list_reserve` when a constant push bound is detected
     (rolling, 2026-02-20).
   - New: list/list_int push paths allocate growth buffers from the arena when the list header is arena-tracked
     (rolling, 2026-02-20).
   - New: arena-loop trace now reports candidate rejection reasons (`unsafe_use`, `used_after_loop`,
     `assign_not_dominate`) plus `candidates=0` when no list allocs are seen (rolling, 2026-02-20).
   - New: list_reserve/list_int_reserve now allocate buffers from the arena when the list header is arena-tracked,
     avoiding GC buffer allocations for arena lists (rolling, 2026-02-20).
   - New: list validation now accepts arena-tracked nodes when `OREN_LIST_ASSUME_LIST=0`, so list_len/reserve/get/set/push
     do not treat arena lists as non-lists during safety checks (rolling, 2026-02-20).
   - New: list-literal sinking now recurses into nested blocks (loops/ifs/switch cases) so branch-local lists inside
     loops are elided when unused on false paths (rolling, 2026-02-20).
   - New: list-literal sinking now hoists contiguous side-effect-free temps used only by the list literal
     into the same branch (rolling, 2026-02-20).
   - New: side-effect-free allowlist includes `oren_int_to_string`, enabling branch-local sinking of temps
     that build strings for list literals (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, post recursive list-literal sinking, runs=5, warmups=1):
     - `alloc_churn` median 3.404s native; `alloc_drop` median 0.145s native
   - New trace (arm64, 2026-02-20, manual compile with `OREN_TRACE_ARENA_LOOPS=1`):
     - `alloc_churn`: outer loop wraps (`safe_vars=1`, `rewrite=1`); inner loop shows `candidates=0` then `skip=no_arena_alloc`.
     - `alloc_drop`: main loop drops list literal `l` as `unsafe_use` (escapes via `keep`), then `skip=no_arena_alloc`.
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace after backend gating, runs=1, warmups=0):
     - `alloc_churn` 0.361s native; arena trace allocs=40000, push=1, pop=1, epoch_reset=1.
     - `arena_loop` trace shows bound=20000, long_lived=0, per_iter=0; C/bytecode builds skip=backend.
   - New run (arm64, 2026-02-20, compile-time auto-loop, runs=5, warmups=0):
   - New: const-int bound detection now resolves simple identifier aliases (e.g., `limit = fallback`)
     but aborts if any intervening control-flow assigns to the bound (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace on alloc_drop, runs=1, warmups=0):
     - `alloc_drop` 0.171s native; arena_loop reports bound missing / skip=no_arena_alloc (no arena rewrites).
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace after alias-bound fix, runs=1, warmups=0):
     - `alloc_drop` 0.166s native; arena_loop now detects bound=10000 but still skip=no_arena_alloc.
   - New: optimizer sinks side-effect-free list literals into immediate `if` blocks when the list
     is only used in the true branch, avoiding allocations on the false path (rolling, 2026-02-20).
   - New: if a list is predeclared as nil/empty and only assigned a list literal in the true branch,
     the assignment is converted to a branch-local `var` (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, post list-literal sinking, runs=1, warmups=0):
     - `alloc_drop` 0.158s native (single run; compare to prior 0.166–0.171s).
   - New run (arm64, 2026-02-20, post list-literal sinking, runs=5, warmups=0):
   - New run (arm64, 2026-02-20, post list-literal assign scoping, runs=5, warmups=0):
   - New run (arm64, 2026-02-20, bench harness default, runs=5, warmups=1):
     - `alloc_churn` median 3.409s native; `alloc_drop` median 0.145s native
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.643s native; `alloc_drop` median 0.152s native
     - Note: this run set the flag at runtime only; compile-time auto-loop was not enabled.
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` via build env, runs=5, warmups=1):
     - `alloc_churn` median 3.526s native; `alloc_drop` median 0.147s native
   - New run (arm64, 2026-02-20, arena-backed reserve buffers + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 0.324s native; `alloc_drop` median 0.150s native
   - New run (arm64, 2026-02-20, recursive list-literal sinking + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.532s native; `alloc_drop` median 0.148s native
   - New run (arm64, 2026-02-20, temp+list-literal sinking, runs=5, warmups=1):
     - `alloc_churn` median 3.404s native; `alloc_drop` median 0.144s native
   - Design + implement loop‑local arenas for list/list_int (compiler escape analysis + arena tracking table).
   - Native runtime scaffolding: `oren_arena_push/pop` + `oren_arena_new_list(_int)` (compiler lowering pending).
   - Arena cap: `OREN_ARENA_CAP_BYTES` spills allocations back to GC when exceeded.
   - Compiler: `OREN_ARENA_AUTO_LOOP=1` wraps simple loops; it can rewrite **unconditional top‑level** loop‑local `oren_new_list(_int)` vars to arena allocs when usage is limited to safe list ops.
   - List literals inside eligible loops are rewritten to arena lists in auto mode (non‑empty literals expand to arena alloc + pushes).
   - Auto-loop rewriting requires the allocation to **dominate first use** in the loop body (use‑before‑assign skips).
   - Auto-loop wrapping now ignores `continue` inside nested loops (outer loop still eligible).
   - Auto-loop now inserts arena pop on `break`/`return`/`continue` in the same loop body.
     - `continue` is allowed for `while` and `for` loops (post executes outside the arena).
   - Auto-loop now keeps bounded loops truly loop-scoped (push before the loop, pop after); per-iteration
     push/pop is reserved for long-lived loops or `@oren.arena_iter`.
   - Auto-loop wrapping skips nested loops when an ancestor has explicit `@oren.arena` or `@oren.arena_iter`.
   - Auto-loop wrapping also skips descendants of `@oren.noarena` (explicit arenas still allowed).
   - `OREN_ARENA_PER_ITER=1` switches auto‑mode to per‑iteration push/pop for long‑lived loops.
   - `@oren.arena_iter` forces per‑iteration push/pop on a loop (even if auto mode is off).
   - Heuristic: loops without a simple literal upper bound default to per‑iteration mode;
     const‑int bounds (including prior locals assigned a literal) or `list_len` locals assigned before the loop
     are treated as bounded when not reassigned.
     - New: const‑int bounds (including prior locals assigned a literal) and `list_len` locals of
       list literals >= `OREN_ARENA_LONG_LIVED_BOUND` (default 1,000,000) are treated as long‑lived
       (per‑iteration).
   - Define long‑lived loop policy:
     - Prefer per‑iteration sub‑arenas when loop trip count is unbounded or long‑lived.
     - Values that escape an iteration allocate in GC/outer arenas (no arena aliasing).
     - Loop‑scoped arenas must enforce `OREN_ARENA_CAP_BYTES` and spill to GC beyond cap.
     - Add periodic epoch resets for long‑running loops to prevent unbounded growth.
   - Add arena‑lifetime counters (spills, epoch resets) to quantify long‑loop behavior.
   - `OREN_TRACE_ARENA=1` prints arena alloc/spill counters at arena epoch reset.
   - Arena tracking table now resets via epoch generation bump (avoids O(cap) clears per iteration).
   - Arena push/pop now checkpoint ptr/limit/base/bytes_used and use per‑depth tracking tables; nested arenas restore state and clear the popped table to prevent long‑lived loop growth.
   - Gate: native `alloc_churn` <= 8x C; native `alloc_drop` <= 5x C.

3) **W4 - List reserve + unchecked push** (M)
   - Baseline (arm64 native, 2026-02-26): `array_sum` 2.12× C, `multi_list_push_int` 3.36× C.
   - Extend bounds propagation for reserve/unchecked push.
   - Treat `oren_new_list(0)` as list-literal for reserve insertion (loop bound -> reserve).
   - Reserve insertion now descends into nested loops with outer list literals and adds list literal length to the reserve amount when known.
   - Native array literal lowering now calls `oren_new_list(n)` (pre-reserve capacity).
   - Native list-literal lowering now uses `oren_list_push_unchecked` for element pushes.
   - Native list/list_int push intrinsics now call unchecked push on the grow slow-path to avoid duplicate validation.
   - Loop reserve insertion does not rewrite push calls (keeps the intrinsic fast path); it only adds `*_reserve` pre-loop.
   - Rolling: empty list literals lower to list<int> only when the same block establishes
     an int element via `list_push`/`list_set` (cross‑block empties stay boxed; 2026-02-20).
   - Native fast list_int push loops now accept `list_int_push_unchecked` calls to preserve the fast path after list<int> lowering (rolling, 2026-02-20).
   - List<int> reserve insertion now accepts int-only list literals (including empty literals).
   - Gate: native `array_sum` and `multi_list_push_int` <= 2x C.

4) **W4 - Tagged value representation convergence** (L)
   - Canonical tagged layout across native/C/AVM.
   - Tag parity fixture now asserts numeric tag values across backends (`tests/fixtures/tag_parity_smoke.oren`).
   - Gate: fixtures pass; no backend-only semantics.

5) **W3 - SIMD/typed-buffer parity on native (x64 + arm64)** (M)
    - Baseline (arm64 native, 2026-02-26): `dot_product_int` 2.55× C.
    - SSE2 baseline on x64; scalar equivalence gated.
    - Wire list_int dot loops to SIMD kernels (or typed-buffer views) where safe.
    - arm64 native fast list_int dot loops unroll by 2 when lists are unique.
    - arm64 native fast list_int get-sum loops unroll by 2 when lists are unique.
    - x64 native fast list_int dot loops unroll by 2 when lists are unique (multi-mul supported).
    - x64 native fast list_int get-sum loops unroll by 2 when lists are unique.
    - Read-only list_int sum/dot loops now use higher safepoint masks on native (arm64=4095, x64=1023).
    - Gate: native `dot_product_int` <= 2x C.

6) **W3 - AVM allocation fast paths + typed buffers** (M)
   - Baseline (OBC, 2026-02-20): `alloc_churn` 61.78× C, `alloc_drop` 2.59× C.
   - Arena/slab alloc for short-lived lists/structs.
   - TMP freelist for `AVM_ALLOC_KIND_TMP` (env: `AVM_TMP_FREELIST=1`, cap via `AVM_TMP_FREELIST_BYTES`, block cap via `AVM_TMP_FREELIST_MAX_BLOCK_BYTES`).
   - List freelist for `AVM_ALLOC_KIND_LIST` + `AVM_ALLOC_KIND_LIST_INT` (env: `AVM_LIST_FREELIST=1`, cap via `AVM_LIST_FREELIST_BYTES`, block cap via `AVM_LIST_FREELIST_MAX_BLOCK_BYTES`).
   - Gate: OBC `alloc_churn` <= 10x C; AVM SIMD test suite passes.

7) **W3 - AVM unboxed list<int> payload + lowering** (M)
   - Baseline (OBC, 2026-02-26): `dot_product_int` 77.69× C, `array_sum_int` 66.36× C.
   - Baseline (native, 2026-02-26): `array_sum` 2.12× C, `dot_product` 2.57× C,
     `array_sum_int` 2.11× C, `multi_list_sum` 2.35× C.
   - Implement list<int> payload + OBC lowering.
   - Gate: list<int> fixtures + OBC perf parity for dot/sum loops.

---

## P0 (Now)

P0 focuses on the W5/W4 scorecard items. Structural/SOLID refactors remain P2
until perf + parity gates are within range. Reweight: runtime robustness + tagged
value convergence are W5 blockers; performance work must preserve correctness and
traceability.
Reweight: avoid trace-only changes unless they unblock a root-cause or a W5 gate.

1) **Perf parity W5: allocation/GC** (L, W5)
   - Execute item 2 in the performance tracker (alloc_churn + alloc_drop).
   - Include long‑lived loop arena policy (per‑iteration sub‑arenas + spill + epoch reset).
   - Design spec: `docs/design/arena_loop_policy.md` (loop arena policy + GC reuse safety).
   - New: per-iteration loops use `oren_arena_iter_push/pop` with optional cap via `OREN_ARENA_ITER_CAP_BYTES` (rolling).
   - Next: tune `OREN_ARENA_ITER_CAP_BYTES` (64 KiB / 256 KiB / 1 MiB all worsen alloc_churn/alloc_drop; likely need adaptive or different arena policy).
   - Update (2026-03-04): alloc_churn regression resolved by splitting loop-invariant list_int temps into
     an outer `if` and fast-path `while` so `fast_list_int_push_while` can match again; alloc_churn
     5.54× C, alloc_drop 1.58× C (arm64, runs=5; `benchmarks/results/alloc_churn_darwin_arm64_20260304_235146.md`).
   - Fix (2026-03-04): list_int safe-int dataflow now preserves local temps across nested blocks;
     alloc_churn compile trace shows list_push call sites include `v`/`v2` in safe keys
     (log: `build/logs/bench_build_oren_native_alloc_churn_20260304_232251.log`).
   - Fix: loop list reset now requires first-assign dominance in the loop body to avoid auto-arena on use-before-assign patterns
     (keeps `test_arena_auto_loop_use_before_assign_skip_smoke` stable).
   - Fold loop‑local arena prototype for list/list_int into this track; override annotations
     (`@oren.arena`, `@oren.arena_iter`, `@oren.noarena`) are already implemented.
   - Confirmed GC-path list tracking after disabling auto arenas (`OREN_ARENA_AUTO_LOOP=0` runtime via
     `oren_arena_new_list_auto`); no `malloc_k` list-track wiring needed unless future traces regress.
   - Separate arena vs GC allocations in perf diagnostics; `alloc_churn` defaults to arena-backed lists
     (use runtime `OREN_ARENA_AUTO_LOOP=0` or build-time env to force GC-tracked list headers when debugging reuse).
   - Gate: native `alloc_churn` <= 8x C; native `alloc_drop` <= 5x C.

2) **Perf parity W5: native hot loops** (L, W5)
   - Execute item 1 in the performance tracker (loop_sum + dot_product).
   - Init/steady split instrumentation is now available via `OREN_BENCH_INIT_SPLIT=1` (see `benchmarks/README.md`).
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

3) **Runtime robustness W5: GC reuse + list header integrity** (L, W5)
   - Root-cause list header corruption (alloc_churn/alloc_drop traces point to pre-reuse corruption).
  - Expand fast-path tracing on native emitters (arm64 + x64) to pin header writes (`OREN_TRACE_NATIVE_LIST_HDR=1`).
    - Done: arm64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-25).
    - Done: x64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-26).
    - Next: correlate list_hdr traces with free-list header dumps to find the first corrupt write.
    - Investigate list_int tracking-node size corruption (alloc_churn free-list traces show huge chunk sizes despite valid headers).
    - New: size-mismatch traces now dump `list_hdr_ring` (when ring capture is active) to
      show the last header writes for the mismatched pointer (2026-02-26).
    - Trace: alloc_churn ring capture + forced list_int still shows only `chunk=32` frees and
      no size mismatches (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring2.log`, 2026-02-26).
    - Trace: longer header ring capture (cap=2000, ring=256) still shows only `chunk=32` frees and
      no size mismatches (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring3.log`, 2026-02-26).
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
    - Trace: compile-time global slot mapping shows stale-root offsets `2376/2896/3584` align to
      `g_gc_reuse_bad_list_triggers`, `g_runtime_root_len`, and `g_trace_list_header`,
      indicating non-pointer globals are being overwritten by bad-list pointers
      (`alloc_churn_globals_trace_20260227_072238.log`, 2026-02-27).
    - Tool: `OREN_TRACE_GC_GLOBAL_GUARD=1` logs when those globals hold pointer-like values
      to narrow down corruption timing (rolling, 2026-02-27).
    - Tool: `OREN_GC_ROOTS_SKIP_RUNTIME_GLOBALS=1` (compile-time env) skips registering
      runtime globals as GC roots to test whether false roots from runtime counters
      are masking bad-list reuse (rolling, 2026-02-27).
    - Tool: `OREN_TRACE_GC_REGISTER_ROOT_NAMES=1` (compile-time env) emits per-root
      `[gc_root_name]` entries (name + slot pointer) during entry registration to map
      non-g_storage roots back to global names (rolling, 2026-02-27).
    - Trace: even with `OREN_GC_ROOTS_SKIP_RUNTIME_GLOBALS=1`, bad-list reuse still hits
      a stale root (root_idx=146, root_count=2) whose slot pointer lies outside g_storage
      (`root_slot_offset=-1`), so runtime globals are not the sole source of false roots
      (`alloc_churn_skiproots_badlist_len64_gc50_200_thr500_ring_20260227_072238.log`,
      2026-02-27).
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
    - Trace: reuse-enabled alloc_churn (blocks+lists unsafe) still shows only `chunk=32` frees
      and no size mismatches; reuse stats show large scan_steps in later windows
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse1.log`, 2026-02-26).
    - Trace: reuse + scan cap (`OREN_GC_REUSE_SCAN_CAP=4096`) still shows only `chunk=32` frees
      and no size mismatches; reuse stats show scan_cap_hits with reduced scan_steps
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_scan_cap.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=128` segfaulted, but still showed only
      `chunk=32` frees before the crash; reuse stats showed large scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_GC_REUSE_BUCKETS=1` + `OREN_BENCH_LIST_LEN=128` also
      segfaulted; still only `chunk=32` frees before the crash; reuse stats show large
      scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128_buckets.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` also segfaulted; still only
      `chunk=32` frees before the crash; reuse stats show large scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` with verbose reuse logging also
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
    - New: bad-list ring dumps now skip when `cap` is implausible (>=1,048,576) to reduce
      segfault risk when corrupted headers point into unmapped memory (2026-02-26).
    - Trace: with ring-dump guard enabled, summary-only run still segfaulted before bad-list logs
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap64_guard.log`, 2026-02-26).
    - Trace: lower-stress run (`GC_EVERY=200`, `ITERS=100`) completed cleanly but produced no
      bad-list or reuse summary output (run log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_100_gc200_cap64_guard.log`, 2026-02-26).
    - Trace: medium-stress run (`GC_EVERY=200`, `ITERS=500`) still segfaulted before bad-list logs;
      summary only (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_500_gc200_cap64_guard.log`, 2026-02-26).
    - Trace: `GC_EVERY=150`, `ITERS=300` still segfaulted before bad-list logs; summary only
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_guard.log`, 2026-02-26).
    - Trace: `GC_EVERY=175`, `ITERS=250` still segfaulted before bad-list logs; summary only
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_250_gc175_cap64_guard.log`, 2026-02-26).
    - New: added `OREN_TRACE_GC_REUSE_BAD_LIST_SAFE=1` to skip bad-list header derefs and
      ring dumps when tracing (2026-02-26).
    - Trace: safe mode + `GC_EVERY=150`, `ITERS=300` still segfaulted before bad-list logs;
      summary only (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_safe.log`, 2026-02-26).
    - New: `OREN_TRACE_GC_REUSE_PRECHECK=1` logs list reuse candidates before
      header validation (cap via `OREN_TRACE_GC_REUSE_PRECHECK_CAP`, default 64, 2026-02-26).
    - Trace: precheck run (`GC_EVERY=150`, `ITERS=300`) captured repeated bad-list events for the
      same node/ptr (len=3762810489372947252 cap=13366 buf=0 magic=0) and completed without
      a segfault (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_precheck.log`, 2026-02-26).
    - Trace: precheck + free-list put (`OREN_TRACE_GC_FREE_LIST_PUT=1`) shows the same ptr had
      a valid empty-list header at free time (len=0 cap=0 buf=0 magic=1279870019), but later
      reappeared as corrupted during reuse (len=3544957662233047860 cap=12342 buf=0 magic=0).
      This points to post-free overwrite / UAF of list header memory (log:
      `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_precheck_put.log`, 2026-02-26).
    - Trace: with freed-list tracking enabled (`OREN_TRACE_GC_FREED_LISTS=1`), no
      `[gc_freed_list_use]` was reported before the bad-list corruption, indicating the
      overwrite likely happens without a tracked alloc-index lookup (log:
      `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_freed.log`, 2026-02-26).
    - New: precheck now reports `freed_seen=1` when freed-list tracking is enabled; latest
      trace shows the corrupted reuse candidate was present in the freed list at precheck time
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_freed_seen.log`, 2026-02-26).
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
      status in trace harness to confirm log completeness.
  - Note: `make test` saw a one-off segfault in `test-native-quick-stage2`
    (log: `build/logs/make_test_20260226_172510.log`); rerun passed
    (log: `build/logs/make_test_native_quick_stage2_20260226_172724.log`). Track for flakes.
  - Note: `make test` hit another `test-native-quick-stage2` segfault (Error 139)
    on 2026-03-03 (log: `build/logs/make_test_20260303_214100.log`);
    rerun `scripts/run_native_quick_integration.sh ./oren_stage2` passed
    (log: `build/logs/repro_native_quick_stage2_20260303_214042.log`). Track for flakes.
  - New: `scripts/triage_native_quick_stage2_flake.sh` runs the stage2 quick integration
    repeatedly and captures per-run logs to help diagnose flaky segfaults; supports
    `ENV=VAL` passthrough args for tracing, logs git/uname metadata, and saves failure
    copies of the inner quick-integration log (2026-03-03).
  - Note: `make test` hit a `test-native-quick` segfault (Error 139) on 2026-03-03
    (log: `build/logs/make_test_20260303_215000.log`); rerun passed
    (log: `build/logs/make_test_20260303_215100.log`). Track for flakes.
  - Note: `make test` hit `test-native-quick` Error 1 on 2026-03-03 in the
    `OREN_GREEN_POLL_CACHE=1` sub-run (panic: "Indexing on non-container";
    log: `build/logs/make_test_20260303_221100.log`); rerun passed
    (log: `build/logs/make_test_20260303_221200.log`). Track for flakes.
  - Trace: stage1 flake harness with `OREN_GREEN_POLL_CACHE=1` timed out on run 1
    (rc=143; log: `build/logs/triage_stage1_quick_green_cache_20260303_221009.log`);
    rerun with `OREN_NATIVE_RUN_TIMEOUT_SECS=30` passed 5 runs
    (log: `build/logs/triage_stage1_quick_green_cache_timeout_20260303_221058.log`).
  - New: `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS` overrides the timeout for the
    `OREN_GREEN_POLL_CACHE=1` sub-run in `scripts/run_native_quick_integration.sh` (2026-03-03).
  - Trace: stage2 quick-integration flake harness ran 10 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage2_quick_20260303_214758.log`).
  - New: `scripts/triage_native_quick_flake.sh` runs the stage1 native quick integration
    in a loop and captures per-run logs for flake diagnosis; supports `ENV=VAL` passthrough
    args for tracing, logs git/uname metadata, and saves failure copies of the inner
    quick-integration log (2026-03-03).
  - Trace: stage1 quick-integration flake harness ran 5 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage1_quick_20260303_215453.log`).
   - New: `OREN_TRACE_ALLOC_INDEX_REBUILD_CAP=<n>` panics when rebuilds exceed `n` (trace-only guardrail)
     to catch runaway rebuild loops during corruption hunts (rolling, 2026-02-26).
   - Fix: native entry stubs now register all global slots as GC roots before top-level execution,
     preventing GC from collecting globals such as test lists (rolling, 2026-02-25).
   - Gate: no header corruption under alloc benches with reuse disabled; reuse paths stay guarded until verified.

4) **Tagged value convergence plan** (L, W5)
   - Define layout and staged migration.
   - Pin semantic invariants (truthiness, equality, type tests) and add cross‑backend fixtures.
   - Expand `tests/fixtures/tag_parity_smoke.oren` to cover truthiness (ints/floats), type‑strict equality (`==`/`!=`), mixed numeric + string comparisons (`< <= > >=`), cross‑type equality (string/int, bool/int), and mixed map key kinds (int vs string) (rolling, 2026-02-24).
   - New: tag parity now asserts list/list_int identity equality (`==`/`!=`) for alias vs distinct lists (rolling, 2026-02-26).
   - New: `make verify-backend-parity-arith-panics` enforces cross-backend panic parity for `div0`, `div_overflow`, `mod0`, `mod_overflow`, and `shift_oob` (shl/shr) (rolling, 2026-02-24).
   - Fix: native stringy inference no longer treats empty list literals as list<string> (prevents strcmp on list pointers; restores list equality semantics, 2026-02-26).
   - Backend mapping table (native/C/AVM) captured in `docs/DESIGN.md`.
   - Tag parity fixture now asserts `oren_type_name` across backends.
   - Parity gate: `tests/fixtures/tag_parity_smoke.oren` + `make verify-backend-parity-tags`.
   - Add compatibility shims so native/C/OBC can migrate without breaking Tier‑1.
   - Gate: fixtures across all backends.

5) **Cross-backend parity gates** (M, W4)
   - Expand fixtures where gaps remain; keep C/native/OBC output aligned.
   - New: `make verify-backend-parity-index-panics` enforces negative index assignment + list get out-of-bounds + non-container index get + unsupported map key get/set panics across backends (rolling, 2026-02-24).
   - Gate: parity scripts + `make test` remain green.

6) **Native scheduler / green-task integration** (L, W4)
   - Keep syscall-first constraints.
   - Note: `test_green_global_runq_fairness` returned -60 once during `make test` on 2026-02-26; rerun passed.
     Treat as a potential flake and keep an eye on fairness/timeout robustness.
   - Note: `make test` hit a segfault in `test-native-quick` with `OREN_GREEN_POLL_CACHE=1`
     (log: `build/logs/make_test_20260226_183026.log`); rerun `make test-native-quick` passed
     (log: `build/logs/make_test_native_quick_20260226_183115.log`). Track as a potential flake.
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_191243.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_191323.log`).
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_193526.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_193613.log`).
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_202338.log`);
     rerun `make test-native-quick` failed once (log: `build/logs/make_test_native_quick_20260226_202537.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_202606.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_213359.log`); rerun `make test-native-quick`
     failed once (log: `build/logs/make_test_native_quick_20260226_213622.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_213712.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_212743.log`); rerun `make test-native-quick`
     completed (log: `build/logs/make_test_native_quick_20260226_212955.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_215921.log`); rerun `make test-native-quick`
     segfaulted once (log: `build/logs/make_test_native_quick_20260226_220029.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_220102.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_221229.log`); rerun `make test-native-quick`
     passed (log: `build/logs/make_test_native_quick_20260226_221331.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_223629.log`); rerun `make test-native-quick`
     passed (log: `build/logs/make_test_native_quick_20260226_223727.log`). Track as a flake.
    - Gate: `make test` + Tier-1 matrix.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring-up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Deterministic AVM scheduler (budgeted)** (L, W3)
5) **Local agent UI polling/backoff** (S, W3)
   - Investigate repeated `/v1/tools` polling failures from `index-*.js`
     (fetch to `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?...`).
    Searched this repo (`rg "agent1/proxy"`, `rg "v1/tools"`): no references found; need the
    owning component path to proceed.
   - New: UI at `http://127.0.0.1:54514/` reports frequent failed fetches to
     `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?tools=host&yolo=1&host_policy=full&session_id=...`,
     suggesting aggressive polling + scheme/port mismatch (2026-02-26).
   - Update: located UI in the `agent` repo (`ui/src/App.tsx`, `ui/src/hooks/useUiSettings.ts`).
     Added loopback scheme inference (use window protocol when base has no scheme) and reduced
     tools query refetch pressure (staleTime + backoff). UI build ok
     (log: `/Users/zongbaolu/work/agent/build/logs/ui_build_20260226_211713.log`, 2026-02-26).

## P2 (Later)

1) **Allow non-macOS hosts for partial targets** (S, W2)
2) **Package manager / signed module workflow** (M, W2)
3) **Refactor oversized native emitters (>2000 lines)** (M, W2)
4) **Refactor `lib/runtime_native/100_time_gc_alloc.oren` (>2000 lines)** (M, W2)
5) **Refactor `lib/compiler/optimizer.oren` (>2000 lines)** (M, W2)
6) **Refactor `lib/compiler/compiler/040_build_pipeline/010_main.oren` (>2000 lines)** (M, W2)

---

## Feature matrix (rolling snapshot)

Status legend:

- Implemented: supported by stage1 compiler and used in current code.
- Rolling: supported but still evolving; must stay regression-tested.
- Planned: design intent; track in this file.

### Core language

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| Modules + `import` | Rolling | `lib/compiler/compiler/020_modules_linking.oren` | `tests/modules/`, `examples/module_app.oren` |
| FFI symbols (`ffi name`) | Rolling | `lib/compiler/*_macho.oren`, `lib/compiler/x64_native_program/072_ffi.oren` | `examples/ffi_test.oren`, `tests/native/ffi_windows_kernel32.oren` |
| `@cfg`, `@debug`/`@release`, `dbg`/`dprint` | Rolling | `lib/compiler/cfg_lowering.oren`, `lib/compiler/debug_sugar.oren` | `tests/native/cfg_os_select.oren`, `tests/native/test_quick_integration_native.oren` |
| Top-level statements + entry | Rolling | native stubs + bytecode tail | `tests/fixtures/tier1_native_no_main_top_level_only.oren` |
| Functions + lambdas | Rolling | `lib/runtime_native/120_first_class_fn.oren`, bytecode closures | `tests/avm/test_closure_fn_values.oren` |
| Generics + specialization | Rolling | compiler specialization passes | `tests/avm/test_generic_call_specialization.oren` |
| Traits + impl blocks | Rolling | compiler lowering passes | `tests/modules/test_trait_*.oren` |
| `match` + `enum` | Rolling | lowering to control flow | `tests/modules/test_match_enum.oren` |
| Diagnostics (`OREN_DIAG`) | Rolling | compiler + runtime | `tests/native/fixtures/diag_fail.oren` |

### Containers and strings

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| Lists (`[]`, `len`, `push`) | Rolling | intrinsics + lowering | `tests/native/fixtures/**` |
| Maps (`{}`, `m[k]`) | Rolling | runtime helpers + lowering | `tests/native/test_integration_suite.oren` |
| Deterministic map iteration | Rolling | runtime sorting | `tests/native/test_integration_suite.oren` |
| Typed buffers (`[]u8`, `[]i32`, `[]f64`, ...) | Rolling | `lib/std/buffer.oren`, `lib/runtime_native/typed_buffers/**` | `tests/avm/test_u8_buf_views.oren`, `tests/fixtures/tier1_native_smoke_main.oren` |
| Strings (`+`, `len`, `slice`) | Rolling | runtime helpers | `tests/fixtures/tier1_native_string_ops_main.oren` |

### Runtime + stdlib

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| TIME substrate (`oren_sleep_ms`, `oren_time_*`) | Rolling | `lib/runtime_native/100_time.oren` | `tests/native/test_time_suite.oren` |
| RNG substrate (`oren_getentropy`) | Rolling | `lib/runtime_native/102_entropy.oren` | `tests/native/test_quick_integration_native.oren` |
| NET substrate (TCP/UDP) | Rolling | `lib/runtime_native/240_tcp.oren`, `250_udp.oren` | `tests/native/test_net_suite.oren` |
| DNS v0 | Rolling | `lib/std/net/dns.oren` | `tests/native/test_dns_loopback.oren` |
| TLS v0 | Rolling | `lib/std/net/tls.oren` + OS providers | `tests/native/test_tls_loopback.oren` |
| HTTP/1.1 GET | Rolling | `lib/std/net/http.oren` | `tests/native/test_http_get_loopback.oren` |
| HTTP/2 framing + HPACK v0 | Rolling | `lib/std/net/http2.oren`, `lib/std/net/hpack.oren` | `tests/native/test_http2_preface_loopback.oren`, `tests/native/test_http2_headers_loopback.oren` |
| WebSocket v0 | Rolling | `lib/std/net/ws.oren` | `tests/native/test_ws_echo_loopback.oren` |
| Channels + select | Rolling | `lib/runtime_native/010_channels_*`, `lib/runtime_native/245_select.oren` | `tests/native/test_integration_suite.oren`, `tests/avm/test_smoke_suite.oren` |
| Spawn + join | Rolling | `lib/runtime_native/260_threads.oren` | `tests/native/test_integration_suite.oren` |
| Capsule model (capability gating) | Rolling | runtime + emit constraints | `tests/native/fixtures/capsule_*` |
| UI headless core | Rolling | `lib/std/ui/**` | `tests/avm/test_ui_*_v0.oren` |

### Backends + AVM

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| C backend | Rolling | `lib/compiler/transpiler.oren` | `make bootstrap`, `make test` |
| Native backend (arm64/x64) | Rolling | `lib/compiler/arm64_*`, `lib/compiler/x64_*` | Tier-1 fixtures under `tests/fixtures/` |
| Bytecode backend (OBC) | Rolling | `lib/compiler/codegen_bytecode/**` | `tests/avm/**` |
| Capability domains (CORE/FS/TIME/RNG/NET/PROC/ENV/AVM) | Rolling | `lib/avm/avm_native.inc` | `tests/avm/**` |
| VirtualFS/VirtualNET/VirtualPROC | Rolling | `lib/avm/main.c` | AVM fixtures under `tests/avm/` |
| `.obc` signature verification | Rolling | `lib/avm/avm_sig.c` | `cmd/orensign/main.go` |
| Nested universes (AVM in AVM) | Rolling (gated) | `lib/avm/avm_native.inc` | `tests/avm/**` |

### HPC / SIMD

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| SIMD toggle | Rolling | `lib/runtime_native/040_capsule_core.oren` | `tests/native/test_simd_suite.oren` |
| arm64 NEON intrinsics | Rolling | `lib/compiler/arm64_native_expr/**` | `tests/native/test_simd_suite.oren` |
| x64 SIMD baseline (SSE2) | Planned | x64 codegen + runtime kernels | Track in this file |
| AVM SIMD (NEON, gated) | Planned/Rolling | `lib/avm/avm_native.c` | Track in this file |
