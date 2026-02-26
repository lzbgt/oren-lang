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
- Reweight: essential language feature completeness is promoted to W4 (see `docs/LANGUAGE.md` planned features).
- Reweight: rtobj cache hash must reflect trace codegen flags (alloc_req/list_hdr/list_reserve) to keep runtime tracing
  consistent under cache hits; treat as a W5 runtime robustness gate.
- Reweight: avoid trace-only changes unless they unblock a root-cause or a W5 gate; prioritize fixes that move
  semantic parity, runtime robustness, or perf parity metrics.

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-02-26): `alloc_churn` 6.62× C, `alloc_drop` 1.28× C.
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
    `[list_hdr]` traces with `[gc_free_list]` samples to spot the last header writes.
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
   - Next: audit native codegen for size/arg clobbers when new regressions appear.
   - Expand fast-path tracing in native emitters to pinpoint header writes.
   - New: x64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-26).
   - Gate: no header corruption under `alloc_churn`/`alloc_drop` with reuse disabled; reuse remains guarded.

3) **W5 perf parity: hot loops (loop_sum, dot_product)**
   - Close native gap vs C and keep cross-backend semantics aligned.
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
   - Note: `make test` hit a segfault in `test-native-quick` with `OREN_GREEN_POLL_CACHE=1`
     (log: `build/logs/make_test_20260226_183026.log`); rerun `make test-native-quick` passed
     (log: `build/logs/make_test_native_quick_20260226_183115.log`). Track as a potential flake.
   - Gate: deterministic fixtures + Tier-1 matrix.

7) **SIMD + typed-buffer kernels for list<int> hot paths**
   - Baseline (arm64 native, 2026-02-26): `dot_product_int` 2.55× C.
   - arm64 NEON + x64 SSE2 baseline; keep scalar equivalence.
   - Gate: `dot_product_int` native <= 2x C.

8) **AVM unboxed list<int> payload + lowering**
   - Improve OBC parity for dot/sum loops.
   - Gate: list<int> fixtures + OBC perf parity.

9) **W4 feature set completeness (essential modern features)**
   - Implement across backends (C/native/OBC): `yield`/stackless coroutines, built-in `assert`/`test`,
     structured error model, visibility boundaries, bytes + typed buffers, variadic ergonomics.
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
   - Fix AVM build breaks that block `make verify-backend-parity-tags` (select case parsing + helper visibility + headers).
   - Investigate repeated `/v1/tools` polling failures from `index-*.js`
     (fetch to `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?...`).
     New: UI at `http://127.0.0.1:54514/` reports frequent failed fetches to
     `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?tools=host&yolo=1&host_policy=full&session_id=...`,
     suggesting aggressive polling + scheme/port mismatch (2026-02-26).
   - Gate: `make test`, `make benchmarks`, and snapshot updates are deterministic.

---

When a task is completed or re-scoped, update `docs/STATUS.md` and the relevant
fixtures/tests to keep the rolling truth accurate.
