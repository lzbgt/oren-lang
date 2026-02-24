# Status + Tracker (Rolling)

**Last updated:** 2026-02-24

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
- **Performance parity**: native hot loops remain >2× C and allocation/GC is far from target (see perf tracker baselines: `loop_sum` 3.42×, `dot_product` 4.13×; `alloc_churn` 1463×, `alloc_drop` 62× on arm64).
- **Runtime robustness**: GC reuse and allocator paths are still experimental; list header corruption investigations are ongoing (tracked below).
- **Platform breadth**: Tier‑1 intent targets are arm64‑macOS, arm64‑linux, x64‑linux, x64‑windows; x64 targets are still in rolling bring‑up.
- **Tooling/ABI stability**: ABI/opcode stability is explicitly rolling; compatibility guarantees are not declared.

Design intent is bleeding‑edge (determinism + capability gating + AVM), but execution maturity is still in the rolling phase.

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
- `./scripts/verify_x64_linux_qemu_smoke.sh`

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

## Performance parity tracker (weighted, 2026-02-24 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026-02-24).
Weights reflect expected impact on C parity and breadth of affected code.

1) **W5 - Native integer hot-loop parity (loop_sum, dot_product)** (L)
   - Baseline (arm64 native, 2026-02-20): `loop_sum` 3.42× C, `dot_product` 4.13× C.
   - Expand inty propagation and arithmetic fast paths.
   - Split runtime init vs steady-state cost and quantify the init gap (see `benchmarks/RESULTS_LATEST.md` notes).
     - New: `OREN_BENCH_INIT_SPLIT=1` adds loop_sum init/steady estimation (see `benchmarks/README.md`).
     - New: `OREN_TRACE_RUNTIME_INIT=1` prints native_runtime_init phase timings.
     - Init/steady split (loop_sum, arm64 macOS, 2026-02-25, n=20,000,000; reps=1 vs 10; 3 runs):
       - C: init -0.0004s (noise), steady 0.0705s
       - Oren C: init 0.0034s, steady 0.0599s
       - Native: init 0.0177s, steady 0.2293s
       - OBC: init 0.0020s, steady 0.0934s
   - Const-divisor `%` is now inlined for literal/const RHS (arm64 + x64).
   - Boxed list dot/get-sum regression guard added to native QI (2026-02-19).
   - Fast-loop safepoints now reset GC tick after safepoint to avoid tick spills (arm64 list-sum, x64 LCG sum).
   - Native fast list-dot loops now use per-list cursors (when lists are unique per mul) to avoid per-iter index multiplies.
   - Native fast list get-sum loops now use per-list cursors (when lists are unique per load) to avoid per-iter index multiplies.
   - Int-only list literals now lower to `list<int>` even when non-empty and use unchecked pushes on native/OBC to preserve fast paths (rolling, 2026-02-20).
   - Safe list<int> get/len now rewrite to unchecked header paths (`oren_list_int_get_unchecked`, `oren_list_int_len_unchecked`) on native backends (rolling, 2026-02-24).
   - Arm64 fast list_int get-sum loops now accept `list_int_get_unchecked` calls to preserve the fast path after rewriting (rolling, 2026-02-24).
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

2) **W5 - Allocation/GC overhead reduction (alloc_churn, alloc_drop)** (L)
   - Baseline (arm64 native, 2026-02-24): `alloc_churn` 1463.70× C, `alloc_drop` 62.49× C.
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
    - New: `OREN_TRACE_NATIVE_LIST_HDR=1` enables arm64 fast‑path list header tracing (calls `oren_trace_list_header` on list/list_int push fast paths).
   - GC init now registers the main thread for stack scanning to avoid missing roots during auto-GC reuse tests.
   - New: `OREN_TRACE_GC_REUSE=1` prints reuse tries/hits/misses at GC sweep.
   - Reuse experiment (arm64, 2026-02-20, reuse flags enabled during native run):
     - `alloc_churn` 769.01× C, `alloc_drop` 1190.02× C (see `benchmarks/results/alloc_*_20260220_075738.md`).
   - Reuse trace (arm64, 2026-02-20, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=10000`, reuse flags enabled):
     - `alloc_churn` segfaults when list reuse is forced (`OREN_GC_REUSE_LISTS_UNSAFE=1`); last trace: tries=10001 hits=3 misses=10001 hit_bytes=5248.
     - Verbose reuse hits show alternating kind=0 and kind=2 (list header) 32-byte chunks before crash
       (captured in local bench run logs).
     - Freed-list tracing (`OREN_TRACE_GC_FREED_LISTS=1`) did not catch a reuse-after-free before crash.
     - Stack range tracing (`OREN_TRACE_GC_STACK_RANGES=1`) shows reuse-hit ptrs with in_stack=0.
     - Reuse live-guard (roots/stack) still segfaults; guard_live=0 in reuse summary (local run, 2026-02-20).
     - Root provenance tracing shows in_roots=0 (root_kind/root_idx=0) on reuse hits before crash (local run, 2026-02-20).
     - List reuse guard drops corrupt list headers (guard_bad_list>0) but segfault persists (local run, 2026-02-20).
     - Bad-list trace shows repeated header with chunk=32 but len/cap=128, buf=ptr+32, magic=1279870019 (local run, 2026-02-20).
     - Bad-list trace run hung (killed after ~14 min); summary showed guard_bad_list=291 (local run, 2026-02-20).
    - Free-list trace shows list frees already have len/cap=128 with chunk=32 and bad magic (same ptr+32 buf), so headers are corrupt before reuse (local run, 2026-02-20).
    - List header trace (`OREN_TRACE_LIST_HEADER=1`, cap=50) emitted no `[list_hdr]` lines during alloc_churn, suggesting the hot path bypasses list runtime helpers (local run, 2026-02-20).
    - List trace now re-checks env after runtime init (uses `native_envp_get_value_ptr` + refresh even if cached off); envp lookup falls back to argv when envp missing (rolling, 2026-02-24).
    - New alloc_churn trace (`OREN_TRACE_LIST_HEADER=1`, cap=20) shows `op=1` new_list, `op=3` reserve to cap=128, then `op=5` list_push_unchecked; no `op=4` fast-path list_push seen (local run, 2026-02-20).
   - New: list-reserve/unchecked-push generalization now treats `oren_new_list(cap)`, `oren_list_new_cap(cap)`,
     `oren_arena_new_list(cap)`, and `oren_arena_new_list_auto(cap)` as list constructors and propagates list metadata across simple alias assignments,
     extending reserve/unchecked-push rewrites (rolling, 2026-02-24).
   - New: fast list/list_int push while-loops now accept constant upper bounds (arm64/x64/transpiler),
     but `alloc_churn` remains far above target in the 2026-02-24 snapshot (rolling).
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
      during reserve/push_unchecked (invalid magic or buf) and dumps list_debug state (rolling, 2026-02-20).
   - List header reuse guard now treats chunk_size==32 as separate-buffer lists even if buf==list+32 (avoids false bad-list hits when allocator places buffers adjacent; rolling, 2026-02-20).
   - List header reuse guard now accepts external-buffer lists whose header allocation still includes stale inline storage (chunk_size > 32 with buf != list+32), avoiding false bad-list hits after growth (rolling, 2026-02-24).
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
   - Alloc-site snapshot (arm64, 2026-02-20): `alloc_churn` list_header=20k, list_buf=20k; `alloc_drop` list_header≈10011, list_buf≈31 (post list_int literal reserve).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, warmups=0):
     - `alloc_drop` list_header=10011, list_buf=31 (see `alloc_drop_darwin_arm64_20260220_130348.md`).
     - `alloc_churn` list_header=20000, list_buf=20000 (see `alloc_churn_darwin_arm64_20260220_130551.md`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, warmups=0):
     - `alloc_churn` list_header=5119, list_buf=5119 (see `alloc_churn_darwin_arm64_20260220_130727.md`).
     - `alloc_drop` list_header=1794, list_buf=6 (see `alloc_drop_darwin_arm64_20260220_130750.md`).
   - New: arena list header allocations now bump alloc-site counters (native `native_arena_new_list(_int)`)
     so arena-backed list headers show up in `OREN_BENCH_TRACE_ALLOC_SITE` runs (rolling, 2026-02-25).
   - Trace alloc-site (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, warmups=0):
     - `alloc_churn` list_header=20000, list_buf=0.
     - `alloc_drop` list_header=1794, list_buf=6.
   - New: list-track now logs `track_alloc` events in `oren_track_alloc` when `OREN_TRACE_LIST_TRACK=1`
     (rolling, 2026-02-25). `alloc_churn` now emits `[list_track] arena_alloc` lines under auto arenas,
     confirming list headers are arena-backed in the default benchmark build.
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
     (see `alloc_churn_darwin_arm64_20260220_134105.md`; list_track logs in `build/logs/bench_run_alloc_churn_20260220_133619/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`,
     `OREN_TRACE_LIST_TRACK=1`, `OREN_TRACE_LIST_TRACK_CAP=5000`, runs=1): `alloc_churn` 5.872s with list_header=1024, list_buf=1024
     (see `alloc_churn_darwin_arm64_20260220_134542.md`; list_track log has no `remove` lines:
     `build/logs/bench_run_alloc_churn_20260220_134542/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_churn` 5.752s with list_header=1024, list_buf=1024
     (see `alloc_churn_darwin_arm64_20260220_135825.md`; list_track log has no `remove` lines:
     `build/logs/bench_run_alloc_churn_20260220_135825/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, after safepoint spill wrapper for explicit calls, runs=1):
     `alloc_churn` 5.769s with list_header=1024, list_buf=1024 (see `alloc_churn_darwin_arm64_20260220_140537.md`;
     list_track log has no `remove` lines: `build/logs/bench_run_alloc_churn_20260220_140537/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_drop` 0.609s with list_header=821, list_buf=2
     (see `alloc_drop_darwin_arm64_20260220_140749.md`; list_track log has no `remove` lines:
     `build/logs/bench_run_alloc_drop_20260220_140749/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`, same env, runs=1):
     `alloc_drop` 75.897s with list_header=26, list_buf=0 (see `alloc_drop_darwin_arm64_20260220_140954.md`);
     list_track log now shows many `remove` lines (see `build/logs/bench_run_alloc_drop_20260220_140954/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, runs=1): `alloc_drop` 18.034s with list_header=137, list_buf=0
     (see `alloc_drop_darwin_arm64_20260220_141623.md`); alloc_index_remove averages ~0.6–0.9µs per call with
     spikes to ~4.1µs, counts ≈550 per sweep (log: `build/logs/bench_run_alloc_drop_20260220_141623/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env but `OREN_GC_ALLOC_THRESHOLD=10000`, runs=1):
     `alloc_drop` 15.729s with list_header=1423, list_buf=4 (see `alloc_drop_darwin_arm64_20260220_141832.md`);
     alloc_index_remove counts ≈5700 per sweep with avg ~1–2µs and spikes to ~12–17µs
     (log: `build/logs/bench_run_alloc_drop_20260220_141832/oren_native/run_0.log`).
   - New: alloc-index cleanup during GC sweep now defers to a bulk rebuild when reuse blocks are enabled
     (avoids per-free remove probes; rolling, 2026-02-20).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX=1`, `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, runs=1):
     `alloc_drop` 15.275s with list_header=1417, list_buf=4 (see `alloc_drop_darwin_arm64_20260220_142335.md`);
     alloc_index_remove count=0; alloc_index rebuilds ~34–39µs
     (log: `build/logs/bench_run_alloc_drop_20260220_142335/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1):
     `alloc_churn` 10.282s with list_header=4979, list_buf=4979 (see `alloc_churn_darwin_arm64_20260220_142427.md`);
     alloc_index_remove count=0; alloc_index rebuilds ~67–73µs
     (log: `build/logs/bench_run_alloc_churn_20260220_142427/oren_native/run_0.log`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, warmups=1):
     `alloc_drop` 3.412s (see `alloc_drop_darwin_arm64_20260220_142827.md`);
     `alloc_churn` 7.341s (see `alloc_churn_darwin_arm64_20260220_142844.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, default GC threshold, warmups=1):
     `alloc_drop` 3.192s (see `alloc_drop_darwin_arm64_20260220_143016.md`);
     `alloc_churn` 7.215s (see `alloc_churn_darwin_arm64_20260220_143032.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, `OREN_GC_REUSE_ZERO=0`, warmups=1):
     `alloc_drop` 3.216s (see `alloc_drop_darwin_arm64_20260220_143057.md`);
     `alloc_churn` 7.268s (see `alloc_churn_darwin_arm64_20260220_143113.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
     `alloc_drop` 3.207s (see `alloc_drop_darwin_arm64_20260220_143257.md`);
     `alloc_churn` 7.105s (see `alloc_churn_darwin_arm64_20260220_143312.md`).
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
     `alloc_drop` 0.178s (see `alloc_drop_darwin_arm64_20260220_143341.md`);
     `alloc_churn` 4.028s (see `alloc_churn_darwin_arm64_20260220_143351.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_ZERO=0`, warmups=1):
     `alloc_drop` 3.399s (see `alloc_drop_darwin_arm64_20260220_143539.md`);
     `alloc_churn` 7.156s (see `alloc_churn_darwin_arm64_20260220_143555.md`).
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_REUSE_ZERO=0`, warmups=1):
     `alloc_drop` 0.179s (see `alloc_drop_darwin_arm64_20260220_143620.md`);
     `alloc_churn` 4.025s (see `alloc_churn_darwin_arm64_20260220_143628.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=32`, warmups=1):
     `alloc_drop` 3.232s (see `alloc_drop_darwin_arm64_20260220_143913.md`);
     `alloc_churn` 7.262s (see `alloc_churn_darwin_arm64_20260220_143946.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=8`, warmups=1):
     `alloc_drop` 3.259s (see `alloc_drop_darwin_arm64_20260220_144118.md`);
     `alloc_churn` 7.225s (see `alloc_churn_darwin_arm64_20260220_144134.md`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=4`, warmups=1):
     `alloc_drop` 3.199s (see `alloc_drop_darwin_arm64_20260220_144306.md`);
     `alloc_churn` 7.275s (see `alloc_churn_darwin_arm64_20260220_144325.md`).
   - Trace reuse (arm64, 2026-02-20, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, reuse blocks on,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 19.056s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
     (see `alloc_drop_darwin_arm64_20260220_144740.md`; log: `build/logs/bench_run_alloc_drop_20260220_144740/oren_native/run_0.log`).
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 10.387s with gc_reuse
     scan_steps min=90, max=10.3M, avg=5.2M across 40 sweeps
     (see `alloc_churn_darwin_arm64_20260220_144835.md`; log: `build/logs/bench_run_alloc_churn_20260220_144835/oren_native/run_0.log`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_BUCKETS=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
     `alloc_drop` 3.189s (see `alloc_drop_darwin_arm64_20260220_145625.md`);
     `alloc_churn` 7.154s (see `alloc_churn_darwin_arm64_20260220_145710.md`).
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 18.747s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
     (see `alloc_drop_darwin_arm64_20260220_145851.md`; log: `build/logs/bench_run_alloc_drop_20260220_145851/oren_native/run_0.log`).
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 13.245s with gc_reuse
     scan_steps min=5.6k, max=19.7M, avg=9.9M across 40 sweeps
     (see `alloc_churn_darwin_arm64_20260220_145934.md`; log: `build/logs/bench_run_alloc_churn_20260220_145934/oren_native/run_0.log`).
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_REUSE_SCAN_CAP=32`,
     `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_TRACE_GC_REUSE=1`, output check disabled):
     `alloc_drop` 6.812s with gc_reuse scan_steps min=369, max=36.6k, avg=35.1k; scan_steps_cap
     min=429, max=36.9k, avg=34.5k; scan_cap_hits min=12, max=1114, avg=1041 across 72 sweeps
     (see `alloc_drop_darwin_arm64_20260220_150730.md`; log: `build/logs/bench_run_alloc_drop_20260220_150730/oren_native/run_0.log`).
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 7.687s with gc_reuse
     scan_steps min=375, max=65.5k, avg=62.1k; scan_steps_cap min=429, max=65.3k, avg=60.4k;
     scan_cap_hits min=12, max=1975, avg=1828 across 40 sweeps
     (see `alloc_churn_darwin_arm64_20260220_150745.md`; log: `build/logs/bench_run_alloc_churn_20260220_150745/oren_native/run_0.log`).
   - New run (arm64, 2026-02-20, runs=5, warmups=1):
     `alloc_churn` 0.131s (48.57× C), `alloc_drop` 0.160s (56.17× C)
     (see `alloc_churn_darwin_arm64_20260220_154700.md`, `alloc_drop_darwin_arm64_20260220_154657.md`).
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
       (see `alloc_churn_darwin_arm64_20260220_124216.md`, `alloc_drop_darwin_arm64_20260220_124239.md`).
   - New trace (arm64, 2026-02-20, manual compile with `OREN_TRACE_ARENA_LOOPS=1`):
     - `alloc_churn`: outer loop wraps (`safe_vars=1`, `rewrite=1`); inner loop shows `candidates=0` then `skip=no_arena_alloc`.
     - `alloc_drop`: main loop drops list literal `l` as `unsafe_use` (escapes via `keep`), then `skip=no_arena_alloc`.
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace after backend gating, runs=1, warmups=0):
     - `alloc_churn` 0.361s native; arena trace allocs=40000, push=1, pop=1, epoch_reset=1.
     - `arena_loop` trace shows bound=20000, long_lived=0, per_iter=0; C/bytecode builds skip=backend.
   - New run (arm64, 2026-02-20, compile-time auto-loop, runs=5, warmups=0):
     - `alloc_churn` median 0.340s native; mean 0.342s (see `alloc_churn_darwin_arm64_20260220_120618.md`).
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
     - `alloc_drop` median 0.156s native; mean 0.156s (see `alloc_drop_darwin_arm64_20260220_115810.md`).
   - New run (arm64, 2026-02-20, post list-literal assign scoping, runs=5, warmups=0):
     - `alloc_drop` median 0.155s native; mean 0.155s (see `alloc_drop_darwin_arm64_20260220_120356.md`).
   - New run (arm64, 2026-02-20, bench harness default, runs=5, warmups=1):
     - `alloc_churn` median 3.409s native; `alloc_drop` median 0.145s native
       (see `alloc_churn_darwin_arm64_20260220_121545.md`, `alloc_drop_darwin_arm64_20260220_121608.md`).
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.643s native; `alloc_drop` median 0.152s native
      (see `alloc_churn_darwin_arm64_20260220_122103.md`, `alloc_drop_darwin_arm64_20260220_122127.md`).
     - Note: this run set the flag at runtime only; compile-time auto-loop was not enabled.
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` via build env, runs=5, warmups=1):
     - `alloc_churn` median 3.526s native; `alloc_drop` median 0.147s native
       (see `alloc_churn_darwin_arm64_20260220_122307.md`, `alloc_drop_darwin_arm64_20260220_122330.md`).
   - New run (arm64, 2026-02-20, arena-backed reserve buffers + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 0.324s native; `alloc_drop` median 0.150s native
      (see `alloc_churn_darwin_arm64_20260220_123817.md`, `alloc_drop_darwin_arm64_20260220_123822.md`).
   - New run (arm64, 2026-02-20, recursive list-literal sinking + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.532s native; `alloc_drop` median 0.148s native
      (see `alloc_churn_darwin_arm64_20260220_124354.md`, `alloc_drop_darwin_arm64_20260220_124417.md`).
   - New run (arm64, 2026-02-20, temp+list-literal sinking, runs=5, warmups=1):
     - `alloc_churn` median 3.404s native; `alloc_drop` median 0.144s native
       (see `alloc_churn_darwin_arm64_20260220_130107.md`, `alloc_drop_darwin_arm64_20260220_130131.md`).
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
   - Baseline (arm64 native, 2026-02-20): `array_sum` 4.02× C, `multi_list_push_int` 3.15× C.
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
    - Baseline (arm64 native, 2026-02-20): `dot_product_int` 4.38× C.
    - SSE2 baseline on x64; scalar equivalence gated.
    - Wire list_int dot loops to SIMD kernels (or typed-buffer views) where safe.
    - arm64 native fast list_int dot loops unroll by 2 when lists are unique.
    - arm64 native fast list_int get-sum loops unroll by 2 when lists are unique.
    - x64 native fast list_int dot loops unroll by 2 when lists are unique (multi-mul supported).
    - x64 native fast list_int get-sum loops unroll by 2 when lists are unique.
    - Read-only list_int sum/dot loops now use a 1023 safepoint mask on native.
    - Gate: native `dot_product_int` <= 2x C.

6) **W3 - AVM allocation fast paths + typed buffers** (M)
   - Baseline (OBC, 2026-02-20): `alloc_churn` 61.78× C, `alloc_drop` 2.59× C.
   - Arena/slab alloc for short-lived lists/structs.
   - TMP freelist for `AVM_ALLOC_KIND_TMP` (env: `AVM_TMP_FREELIST=1`, cap via `AVM_TMP_FREELIST_BYTES`, block cap via `AVM_TMP_FREELIST_MAX_BLOCK_BYTES`).
   - List freelist for `AVM_ALLOC_KIND_LIST` + `AVM_ALLOC_KIND_LIST_INT` (env: `AVM_LIST_FREELIST=1`, cap via `AVM_LIST_FREELIST_BYTES`, block cap via `AVM_LIST_FREELIST_MAX_BLOCK_BYTES`).
   - Gate: OBC `alloc_churn` <= 10x C; AVM SIMD test suite passes.

7) **W3 - AVM unboxed list<int> payload + lowering** (M)
   - Baseline (OBC, 2026-02-20): `dot_product_int` 1.80× C, `array_sum_int` 1.15× C.
   - Implement list<int> payload + OBC lowering.
   - Gate: list<int> fixtures + OBC perf parity for dot/sum loops.

---

## P0 (Now)

1) **Perf parity W5: allocation/GC** (L, W5)
   - Execute item 2 in the performance tracker (alloc_churn + alloc_drop).
   - Include long‑lived loop arena policy (per‑iteration sub‑arenas + spill + epoch reset).
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

3) **Tagged value convergence plan** (L, W5)
   - Define layout and staged migration.
   - Pin semantic invariants (truthiness, equality, type tests) and add cross‑backend fixtures.
   - Expand `tests/fixtures/tag_parity_smoke.oren` to cover truthiness (ints/floats), type‑strict equality (`==`/`!=`), mixed numeric + string comparisons (`< <= > >=`), cross‑type equality (string/int, bool/int), and mixed map key kinds (int vs string) (rolling, 2026-02-24).
   - New: `make verify-backend-parity-arith-panics` enforces cross-backend panic parity for `div0`, `div_overflow`, `mod0`, `mod_overflow`, and `shift_oob` (shl/shr) (rolling, 2026-02-24).
   - Backend mapping table (native/C/AVM) captured in `docs/DESIGN.md`.
   - Tag parity fixture now asserts `oren_type_name` across backends.
   - Parity gate: `tests/fixtures/tag_parity_smoke.oren` + `make verify-backend-parity-tags`.
   - Add compatibility shims so native/C/OBC can migrate without breaking Tier‑1.
   - Gate: fixtures across all backends.

4) **Cross-backend parity gates** (M, W4)
   - Expand fixtures where gaps remain; keep C/native/OBC output aligned.
   - New: `make verify-backend-parity-index-panics` enforces negative index assignment + list get out-of-bounds + non-container index get + unsupported map key get/set panics across backends (rolling, 2026-02-24).
   - Gate: parity scripts + `make test` remain green.

5) **Native scheduler / green-task integration** (L, W4)
   - Keep syscall-first constraints.
   - Gate: `make test` + Tier-1 matrix.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring-up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Deterministic AVM scheduler (budgeted)** (L, W3)

## P2 (Later)

1) **Allow non-macOS hosts for partial targets** (S, W2)
2) **Package manager / signed module workflow** (M, W2)
3) **Refactor oversized native emitters (>2000 lines)** (M, W2)
4) **Refactor `lib/runtime_native/100_time_gc_alloc.oren` (>2000 lines)** (M, W2)
5) **Refactor `lib/compiler/optimizer.oren` (>2000 lines)** (M, W2)

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
