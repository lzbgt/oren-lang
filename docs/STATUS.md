# Status + Tracker (Rolling)

**Last updated:** 2026-02-20

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

## Regression gates (run first)

Local (fast):

- `make test`
- `make verify-native-quick`
- `make verify-backend-parity-boxed-list`
- `make verify-backend-parity-list-int`
- `make verify-backend-parity-tags`
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

## Performance parity tracker (weighted, 2026-02-20 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026-02-20).
Weights reflect expected impact on C parity and breadth of affected code.

1) **W5 - Native integer hot-loop parity (loop_sum, dot_product)** (L)
   - Baseline (arm64 native, 2026-02-20): `loop_sum` 3.42× C, `dot_product` 9.97× C.
   - Expand inty propagation and arithmetic fast paths.
   - Split runtime init vs steady-state cost and quantify the init gap (see `benchmarks/RESULTS_LATEST.md` notes).
   - Const-divisor `%` is now inlined for literal/const RHS (arm64 + x64).
   - Boxed list dot/get-sum regression guard added to native QI (2026-02-19).
   - Fast-loop safepoints now reset GC tick after safepoint to avoid tick spills (arm64 list-sum, x64 LCG sum).
   - Native fast list-dot loops now use per-list cursors (when lists are unique per mul) to avoid per-iter index multiplies.
   - Native fast list get-sum loops now use per-list cursors (when lists are unique per load) to avoid per-iter index multiplies.
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

2) **W5 - Allocation/GC overhead reduction (alloc_churn, alloc_drop)** (L)
   - Baseline (arm64 native, 2026-02-20): `alloc_churn` 21.05× C, `alloc_drop` 33.60× C.
   - Fix and enable reuse paths (`OREN_GC_REUSE_BLOCKS`) when correct.
   - Add allocation-site counters for `alloc_churn`/`alloc_drop` to pinpoint dominant allocations.
   - New: `OREN_TRACE_ALLOC_SITE=1` reports list/list_int header+buffer sites (ids 1..4; see `lib/runtime_native/170_lists.oren`).
   - New: `OREN_GC_REUSE_LISTS=1` allows reuse for list/list_int headers when `OREN_GC_REUSE_BLOCKS=1` (rolling guardrail).
     - Rolling safety: list reuse is disabled when `OREN_GC_AUTO=1` unless `OREN_GC_REUSE_LISTS_UNSAFE=1`.
   - New: `OREN_GC_REUSE_MAPS=1` / `OREN_GC_REUSE_STRUCTS=1` allow reuse for map/struct headers (rolling guardrail).
   - New: `OREN_GC_REUSE_ZERO=1` zero-fills reused blocks by default when reuse is enabled (set `OREN_GC_REUSE_ZERO=0` to disable).
   - New: `OREN_TRACE_GC_REUSE_VERBOSE=1` logs capped reuse hits (cap via `OREN_TRACE_GC_REUSE_VERBOSE_CAP`).
   - New: `OREN_TRACE_GC_FREED_LISTS=1` records freed list pointers; `OREN_TRACE_GC_FREED_LISTS_CAP=<n>` controls ring size.
   - New: `OREN_TRACE_GC_STACK_RANGES=1` captures stack scan ranges per collection (cap via `OREN_TRACE_GC_STACK_RANGES_CAP`).
   - Verbose reuse logs now include `in_roots` plus `root_kind` (1=gc_pin, 2=runtime roots, 3=global roots) and `root_idx`, alongside `in_stack`.
   - Reuse guard now restores free-list nodes that are still referenced by roots/stack; `[gc_reuse]` includes `guard_live`.
   - List reuse guard validates header integrity and drops corrupt candidates; `[gc_reuse]` includes `guard_bad_list`.
     - Trace rejected list headers with `OREN_TRACE_GC_REUSE_BAD_LIST=1` (cap via `OREN_TRACE_GC_REUSE_BAD_LIST_CAP`).
     - Trace freed list headers with `OREN_TRACE_GC_FREE_LIST_HEADERS=1` (cap via `OREN_TRACE_GC_FREE_LIST_HEADERS_CAP`).
     - Trace list header writes with `OREN_TRACE_LIST_HEADER=1` (cap via `OREN_TRACE_LIST_HEADER_CAP`).
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
     - Reuse guard now enforces strict header sizing: inline-buffer headers require chunk==32+cap*8; out-of-line headers require chunk==32 (rolling, 2026-02-20).
     - Strict header sizing guard still segfaults; guard_bad_list=276 (local run, 2026-02-20).
     - Reuse now rejects alloc-index mismatches for reused pointers (rolling, 2026-02-20).
     - Alloc-index guard run still segfaults; guard_bad_list=275 (local run, 2026-02-20).
     - `alloc_churn` runs when list reuse is guarded off (auto-GC) with reuse blocks only:
       tries=9989 hits≈4987 misses≈5005 hit_bytes≈5.11 MiB (see `benchmarks/results/alloc_churn_darwin_arm64_20260220_083057.md`).
     - `alloc_drop` (runs=1) 12.13s with GC reuse traces (see `benchmarks/results/alloc_drop_darwin_arm64_20260220_081737.md`).
   - Bench harness supports `OREN_BENCH_TRACE_ALLOC_SITE=1` (native) to capture alloc-site counts in benchmark stdout logs (forces warmups=0; dump happens at exit; use `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD` if you want GC-triggered dumps).
   - When trace alloc-site is enabled, benchmark result JSON records `alloc_site` counts + medians.
   - Bench harness supports `OREN_BENCH_TRACE_ARENA=1` (native) to capture arena alloc/spill counters; results JSON records `arena_trace` medians (optional cap via `OREN_BENCH_TRACE_ARENA_CAP_BYTES`).
   - Bench harness supports `OREN_BENCH_SAVE_RUN_LOGS=1` (per-run stdout logs) and `OREN_BENCH_RUN_LOG_TEE=1` (tee to console) for trace-heavy runs like GC reuse.
   - Alloc-site snapshot (arm64, 2026-02-20): `alloc_churn` list_header=20k, list_buf=20k; `alloc_drop` list_header≈10011, list_buf≈31 (post list_int literal reserve).
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` + `OREN_ARENA_PER_ITER=1`, OBC/OREN_C skipped):
     - `alloc_churn` 25.90× C, `alloc_drop` 38.26× C (see `benchmarks/RESULTS_LATEST.md`).
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1`, OBC/OREN_C skipped):
     - `alloc_churn` 24.82× C, `alloc_drop` 38.16× C (see `benchmarks/results/alloc_*_20260220_041633.md`).
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
     const‑int bounds, prior locals, or `list_len` locals assigned before the loop are treated as bounded when not reassigned.
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
   - Baseline (arm64 native, 2026-02-20): `array_sum` 5.12× C, `multi_list_push_int` 2.56× C.
   - Extend bounds propagation for reserve/unchecked push.
   - Treat `oren_new_list(0)` as list-literal for reserve insertion (loop bound -> reserve).
   - Reserve insertion now descends into nested loops with outer list literals and adds list literal length to the reserve amount when known.
   - Native array literal lowering now calls `oren_new_list(n)` (pre-reserve capacity).
   - Native list-literal lowering now uses `oren_list_push_unchecked` for element pushes.
   - Native list/list_int push intrinsics now call unchecked push on the grow slow-path to avoid duplicate validation.
   - Reserve insertion now rewrites safe loop-local list.push to `oren_list_push_unchecked` when the list is created from a literal/new_list(0) and not reassigned in the loop body.
   - List<int> loops now rewrite safe `list_int_push` to `oren_list_int_push_unchecked` when the pushed value is provably inty.
   - List<int> reserve insertion now accepts int-only list literals (including empty literals).
   - Gate: native `array_sum` and `multi_list_push_int` <= 2x C.

4) **W4 - Tagged value representation convergence** (L)
   - Canonical tagged layout across native/C/AVM.
   - Tag parity fixture now asserts numeric tag values across backends (`tests/fixtures/tag_parity_smoke.oren`).
   - Gate: fixtures pass; no backend-only semantics.

5) **W3 - SIMD/typed-buffer parity on native (x64 + arm64)** (M)
    - Baseline (arm64 native, 2026-02-20): `dot_product_int` 3.59× C.
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

1) **Perf parity W5: native hot loops** (L, W5)
   - Execute item 1 in the performance tracker (loop_sum + dot_product).
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

2) **Perf parity W5: allocation/GC** (L, W5)
   - Execute item 2 in the performance tracker (alloc_churn + alloc_drop).
   - Include long‑lived loop arena policy (per‑iteration sub‑arenas + spill + epoch reset).
   - Gate: native `alloc_churn` <= 8x C; native `alloc_drop` <= 5x C.

3) **Tagged value convergence plan** (L, W4)
   - Define layout and staged migration.
   - Pin semantic invariants (truthiness, equality, type tests) and add cross‑backend fixtures.
   - Backend mapping table (native/C/AVM) captured in `docs/DESIGN.md`.
   - Tag parity fixture now asserts `oren_type_name` across backends.
   - Parity gate: `tests/fixtures/tag_parity_smoke.oren` + `make verify-backend-parity-tags`.
   - Add compatibility shims so native/C/OBC can migrate without breaking Tier‑1.
   - Gate: fixtures across all backends.

4) **Native scheduler / green-task integration** (L, W4)
   - Keep syscall-first constraints.
   - Gate: `make test` + Tier-1 matrix.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring-up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Deterministic AVM scheduler (budgeted)** (L, W3)
5) **Loop‑local arena prototype for list/list_int** (L, W5)
   - Implemented: `@oren.arena` / `@oren.arena_iter` / `@oren.noarena` override auto loop wrapping.

## P2 (Later)

1) **Allow non-macOS hosts for partial targets** (S, W2)
2) **Package manager / signed module workflow** (M, W2)
3) **Refactor oversized native emitters (>2000 lines)** (M, W2)
4) **Refactor `lib/runtime_native/100_time_gc_alloc.oren` (>2000 lines)** (M, W2)

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
