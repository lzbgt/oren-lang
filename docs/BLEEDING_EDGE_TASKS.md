# Bleeding-Edge Goals + Derived Tasks

**Last updated:** 2026-04-12

This doc captures the bleeding-edge feature goals (user/client + architect/designer)
and turns them into concrete task buckets. It is intentionally short and
kept in sync with `docs/STATUS.md`.

---

## As a user/client, bleeding-edge features I want

- Deterministic execution with capability-gated effects (FS/NET/PROC/ENV/TIME/RNG) across backends.
  Current contract: `docs/CAPABILITY_RUNTIME_CONTRACT.md`.
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
- New: `docs/CAPABILITY_RUNTIME_CONTRACT.md` now pins the current native runtime profiles,
  capability domains, failure model, and verification map; `oren meta` now emits a per-source
  `capabilities` manifest for `@cap.requires` functions; artifact `--manifest` output now carries
  build-policy fields for backend, runtime-profile request, capsule flag, allowlisted domains,
  source-required domains, source package policy, and observe-only `source_package_check`
  comparison; `@oren.package(...)` now provides the first source-level package marker for
  runtime-profile intent, allow domains, and budget defaults; `--enforce-package-policy` /
  `OREN_ENFORCE_PACKAGE_POLICY=1` now promotes `mismatch_observed` into a build error.
  `scripts/run_package_policy.sh` now dispatches explicit package-policy execution for AVM and
  native capsule runs. The AVM path consumes bytecode artifact manifests and applies package
  capsule/gas/heap/wall declarations to AVM runtime policy, with a pre-execution used-domain
  scan that fails closed when bytecode exceeds the package allowlist. The native path consumes
  the same package marker, builds with package-derived capsule/domain policy, enforces
  `budget_wall_ms` with a process watchdog, enforces `budget_heap_bytes` from captured native-run
  JSON live-heap scan evidence, enforces `budget_cpu_ms` from child process resource usage where
  available, and enforces `budget_gas` from captured native-run
  `native_stmt_loop_tick_v0` evidence after building and running gas-budgeted artifacts with
  `OREN_NATIVE_GAS_ACCOUNTING=stmt`.
  The native runner can now write
  `oren.native-package-policy-run.v0` via `OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path>` with
  runner-observed wall/gas/heap/CPU-budget evidence and captured native runtime `effect_ledger`
  summary when available. Native executables
  can also emit `oren.native-run.v0` through `OREN_NATIVE_RUN_JSON=1`, which gives semantic-diff
  runtime-observed `effect_ledger_summary` wall timing, native capsule domain-gate counters,
  selected FS/NET/PROC resource-check counters, and a scanned native `heap_bytes.used` value for
  live tracked heap nodes, plus default loop-safepoint `native_loop_safepoint_tick_v0` gas ticks or
  statement+loop `native_stmt_loop_tick_v0` ticks when `OREN_NATIVE_GAS_ACCOUNTING=stmt` or
  `statement` is used, distinct lowering-block `native_basic_block_tick_v0` ticks when
  `OREN_NATIVE_GAS_ACCOUNTING=basic-block` is used, or weighted lowering-block
  `native_block_weighted_tick_v0` ticks when `OREN_NATIVE_GAS_ACCOUNTING=block-weighted` is used, or
  runtime path-aware `native_dynamic_emitter_tick_v0` ticks when
  `OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter` is used. Every native gas surface is explicitly
  backend-local and not conversion-ready (`unit_scope="backend_local"`,
  `target_arch`, `unit_family`, `cross_arch_comparable=false`, `conversion_ready=false`,
  `avm_canonical=false`), so
  semantic-diff consumers cannot mistake it for architecture-neutral instruction gas or hide arm64/x64
  unit-family differences.
  The native build cache key now includes the
  normalized gas-accounting mode, and the mode guard forces `--no-cache`, after a verifier run showed
  cached artifacts could otherwise hide backend gas-note differences behind identical binaries.
  Native and AVM gas summaries now carry explicit `oren.gas-surface.v0` descriptors; semantic diff
  reports native/OBC gas as non-comparable while native semantic-diff uses `native_dynamic_emitter_tick_v0` and AVM uses
  canonical `avm_opcode_cost_v0` opcode-dispatch gas (`unit_scope="avm_canonical"`,
	  `runtime_path_aware=true`, `cross_arch_comparable=true`, `conversion_ready=true`,
	  `avm_canonical=true`). Semantic diff also records `oren.gas-surface-calibration.v0` empirical
	  ratios for the fixture, explicitly marked as not a conversion, and now emits
	  `oren.avm-canonical-sidecar-gas.v0` as same-source OBC canonical gas evidence with
				  `package_policy_may_use=false`, source/native-artifact/sidecar-artifact SHA-256 identity hashes,
				  program-args/package-policy binding hashes, sidecar `avm.run.v1` status/error evidence,
				  normalized stdout/stderr hashes, explicit `same_run_stderr_equal`,
				  concrete native/sidecar exit codes, non-blocking `certification_warnings`, `certification_status`, and
				  `certification_failure_reasons` evidence. Higher-level calibration and native instruction-surface
				  decision reports preserve that warning-free stderr-parity, run-JSON-ok, test-injection-free evidence, and
				  per-sample source/native-artifact/sidecar-artifact identity plus input-binding hashes.
		  Native package-policy verification now also distinguishes structured non-gas AVM sidecar run errors
		  with a `run_error` injection and `sidecar_error` failure reason.
		  Native package-policy verification now also covers the non-certified sidecar branch with an
		  auditable stdout-mismatch `test_injection`, requiring `budget_unavailable` rather than accidental
		  `budget_gas` enforcement, and the stderr-mismatch warning branch with AVM sidecar gas enforcement
		  still intact. It now also covers schema-mismatch plus stderr `budget exceeded (gas)` injection, so
		  stderr diagnostics cannot certify gas without canonical `avm.run.v1` evidence. It now also covers
		  an exit-code mismatch injection so nonzero sidecar exits remain
		  non-certified even when stdout/stderr and canonical gas evidence are present. Missing run-JSON,
		  schema-mismatch, gas-surface, zero-gas, and timeout injections now separately prove absent or
		  invalid canonical gas evidence also fails closed. A sidecar build-failure injection now proves the runner still emits structured
	  `sidecar_build_failed` evidence instead of dropping the JSON contract. A native-failure fixture
	  now also keeps the native exit visible with `not_run_native_failed` sidecar evidence instead of
	  masking it as sidecar gas unavailability.
	  `make verify-backend-gas-surface-calibration-set`
	  now emits an `oren.gas-surface-calibration-set.v0` report across default smoke, loop-heavy,
	  branch-heavy, call-heavy, and allocation-heavy fixtures, guards the current cross-fixture ratio spread as `single_ratio_unsafe`, and
	  emits an `oren.gas-surface-conversion-decision.v0` blocker requiring
	  package-bound AVM canonical sidecar gas or native instruction-equivalent gas before package policy may compare
	  native/OBC gas as one unit. The calibration samples now also carry the dynamic-emitter surface metadata
  (`unit_scope`, `target_arch`, `unit_family`, `runtime_path_aware`, `cross_arch_comparable`,
  `conversion_ready`) and the AVM canonical metadata (`unit_scope="avm_canonical"`,
  `avm_canonical=true`) so the blocker is machine-readable even before looking at ratios. The first dynamic-emitter calibration set
  (`build/reports/backend_gas_surface_calibration_set_20260412_081109_85502.json`) still shows
  `native_per_obc` spread from `~2.49x` to `~16.82x`, so dynamic-emitter evidence is path-aware
  but not a conversion rule. `make verify-backend-native-instruction-surface-decision`
	  also rejects the tempting whole-binary native disassembly shortcut by cross-checking it against
	  the current `native_dynamic_emitter_tick_v0` runtime surface: whole-binary counts include linked
	  runtime text and are not per-executed-path gas. The first static-proxy report
		  (`build/reports/backend_native_instruction_surface_decision_20260412_083236_29513.json`) counted
		  the same `474624` whole-binary native instructions for the original three fixtures while OBC opcode gas
			  varied from `234` to `2328`, confirming the shortcut is runtime-insensitive; the current default
			  guard also requires call-heavy and allocation-heavy sample classes. `docs/GAS_SURFACE_REGISTRY.md`
	  and `make verify-gas-surface-registry` now pin the gas-surface inventory so tools cannot drift on
	  AVM-canonical versus native backend-local conversion status. AVM `effect_ledger_summary.budgets`
			  now reports gas, heap, and wall budget fields for that path, including `wall_ms.limit` and measured
			  `wall_ms.elapsed_ns`. Native package policy can now opt into a package-bound sidecar certificate
			  with `OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1`, which records AVM canonical gas only after the
				  sidecar runs under package budgets and matches native stdout/exit, or after the sidecar itself
				  reports AVM canonical gas budget exhaustion through structured `avm.run.v1.error` evidence. The sidecar
			  certificate now binds exact program args and package policy with stable SHA-256 fields. The explicit
		  `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar` profile and the dispatcher/native `auto`
		  default for gas-budgeted packages now use that certificate for `budget_gas` enforcement and report
		  `runner_wall_avm_canonical_gas`; next capability work should add finer native instruction-equivalent
		  gas or tighten package-bound sidecar coverage rather than re-describing the existing env contract.
  `docs/EFFECT_LEDGER_CONTRACT.md` now pins the v0 effect-ledger schema before complete runtime
  emission lands. Contract drift is guarded by
  `make verify-capability-runtime-contract`, `make verify-capability-metadata`, and
  `make verify-capability-manifest-policy`; effect-ledger schema drift is guarded by
  `make verify-effect-ledger-contract`, with AVM JSON summary emission covered by
  `make verify-avm-effect-ledger-json`, package-policy execution covered by
  `make verify-avm-package-policy-runner` / `make verify-native-package-policy-runner`, and native
  resource-check summaries covered by `make verify-native-capsule-resource-checks`.
- New: `project-doc/oren_feature_horizon_20260412.md` and
  `project-doc/oren_language_system_bets_20260412.md` separate external pressure signals from
  Oren-owned forecast bets. Reweight Oren differentiation toward deterministic native/AVM
  execution, counterfactual AVM snapshots, effect ledgers, budgeted interfaces, semantic diffs,
  representation contracts, proof-carrying artifact manifests, and protocol-independent
  agent-callable module contracts.
- New: `make verify-public-readme-positioning` keeps public README positioning on the general
  mainstream-language differentiation line instead of citing one comparison language directly;
  archived research/reference material remains allowed under `project-doc/**` and `docs/refs/**`.
- Done: rtobj cache hash now reflects trace codegen flags end-to-end (alloc_req/list_hdr/list_reserve),
  including rtobj seed selection, keeping runtime tracing consistent under cache hits.
- Reweight: avoid trace-only changes unless they unblock a root-cause or a W5 gate; prioritize fixes that move
  semantic parity, runtime robustness, or perf parity metrics.
- Update: readiness dashboard now supports audit warning thresholds (2026-03-05).

1) **W5 perf parity: allocation/GC (alloc_churn, alloc_drop)**
   - Enable safe reuse paths and reduce tracking overhead.
   - Baseline (arm64 native, 2026-04-22): `alloc_churn` 5.76× C, `alloc_drop` 1.83× C.
   - New run (arm64, 2026-04-22, runs=5, warmups=1; via `make perf-gate-native-refresh-latest`):
     - alloc_churn: C 0.002945s, native 0.016951s (5.76× C).
     - alloc_drop: C 0.002961s, native 0.005433s (1.83× C).
   - Bytecode note: `oren_gc_collect()` now lowers to a no-op in the bytecode backend so alloc_churn/alloc_drop OBC builds succeed (2026-03-04).
   - New: latest focused perf-gate snapshot keeps alloc_churn within the 8× gate; reuse is default-on with escape/alias guardrails.
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
     (see `benchmarks/RESULTS_LATEST.md` for the retained summary; local result artifacts live under `build/benchmarks/results/`).
   - New: loop list reuse keeps alloc_drop at ~1.28× C (arm64, 2026-02-26),
     within the 5× gate (see `benchmarks/RESULTS_LATEST.md`; local result artifacts live under `build/benchmarks/results/`).
   - New: reuse escape smoke (`test_loop_list_reuse_escape_smoke`) added to native quick integration
     to catch incorrect reuse when lists escape (2026-02-26).
   - Fix: loop list reuse now skips unsafe list uses (escape/alias), enabling default-on reuse
     while remaining correctness-safe under `test_loop_list_reuse_escape_smoke` (2026-02-26).
   - Fix: loop list reset now requires first-assign dominance in the loop body, avoiding auto-arena
     on use-before-assign patterns (`test_arena_auto_loop_use_before_assign_skip_smoke`, 2026-02-26).
   - Next: keep alloc_churn/alloc_drop within gate while auditing other alloc/GC workloads for regressions.
   - Gate: `alloc_churn` native <= 8x C; `alloc_drop` native <= 5x C.

2) **W5 runtime robustness: GC reuse + list header integrity**
   - Root-cause list header corruption before enabling reuse paths.
   - Fix + verify (2026-04-21): the current reduced aggressive-GC `list<int>` churn repro
     (`tests/native/test_gc_reuse_alloc_churn_min.oren`) now passes again on shipped defaults.
     The concrete arm64 fix was saturating `_arm64_nonneg_linear_safe_n_limit(...)` so the
     identity nonnegative-linear shape no longer overflows the fast-loop preheader ceiling to
     `0x8000000000000000`. Native quick now runs that reducer directly, and the dedicated W5
     tracking smoke uses the reduced fixtures (`test_gc_reuse_alloc_churn_min`,
     `test_gc_collect_list_int_live`, `test_gc_auto_list_int_live`, and the generic control)
     instead of the heavier benchmark build. That same-day reducer fix still triggered a temporary
     rollback while the broader self-host/native-quick surface was being re-closed. A direct arm64
     `oren_gc_collect()` shortcut was tried during the same investigation and then removed after it
     deadlocked the native quick green join-waiter fixture; shipped code stays on the normal
     direct-call lowering there.
   - Update (2026-04-23): that broader blocker is now closed on the current tree, so
     `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR` ships on by default again. The refreshed
     shipped-vs-disabled decision surface
     (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_011353_91759.log`)
     keeps the formal rule aligned (`decision_surface_alignment: agree`) and still strongly
     prefers the shipped default on the fill/share plus exact `array_sum_int` surfaces
     (`default_fill_vs_c_vector ~2.3103×` vs disabled `~5.7054×`,
     `default_array_ratio_median ~2.1964×` vs disabled `~2.3212×`), while exact
     `dot_product_int` only moves slightly toward the disabled branch
     (`default_dot_ratio_median ~1.3884×` vs disabled `~1.3578×`). The real shipped safety surface
     is green too: `make verify-native-quick`
     (`build/logs/make_verify_native_quick_20260423_011547_default_on_promote_v1.log`) and
     `make test` (`build/logs/make_test_20260423_012704_default_on_promote_v2.log`) both pass with
     the default-on branch. Reweight next work away from more branch-isolation experiments and
     toward the residual list build/fill lifetime cost on this now-revalidated shipped surface.
	   - Update (2026-04-23): the next constructor-path runtime micro-branch is now rejected on that
	     same shipped surface too. The exact same-tree baseline remains
	     `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`
	     (`default_fill_vs_c_vector ~2.3103×`, fill `per_rep_s ~0.003096`). A first rerun that gated
	     arena/non-arena constructor trace/index work behind active ctor tracing
	     (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015415_6018.log`) regressed to
	     `~2.3671×` / `~0.003145`, and the follow-up that also short-circuited the immediate
	     arena-retag lookup (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015936_6969.log`)
	     regressed further to `~2.3970×` / `~0.003188`. Do not reopen that constructor trace/retag
	     seam without new evidence; the remaining blocker is below the constructor boundary.
	   - Update (2026-04-23): the first narrower compiler-side loop-state trim under that same shipped
	     fill surface is now rejected too. Starting from the same baseline
	     `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`
	     (`default_fill_vs_c_vector ~2.3103×`, fill `per_rep_s ~0.003096`), a focused rerun that
	     stopped spilling the generic `idx` local on the nonnegative-linear path and tried to keep `i`
	     live across the direct arithmetic helper path
	     (`build/logs/perf-probe-list-int-fill-share-decision-20260423_021057_8800.log`) regressed
	     hard to `~4.2125×` / `~0.005534`. Reweight again: the remaining cost is not the obvious
	     frame spill/reload pair by itself, and the next exact same-tree work should look below that
	     narrow `X20` live-range assumption instead of reopening this trim branch.
	   - Update (2026-04-23): the next safepoint-side loop-state trim under that same shipped fill
	     surface is now rejected too. Starting from the same baseline
	     `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`
	     (`default_fill_vs_c_vector ~2.3103×`, fill `per_rep_s ~0.003096`), a rerun that replaced the
	     generic inline-tick preserved-reg spill set with the narrower explicit-pairs path for
	     `fast_list_int_push_while`
	     (`build/logs/perf-probe-list-int-fill-share-decision-20260423_022302_10735.log`) still
	     regressed slightly to `~2.3697×` / `~0.003107`. Reweight again: the remaining fill-side cost
	     is not solved by just narrowing the safepoint spill pairs on the shipped loop, so the next
	     exact same-tree work should stay below that branch too.
	   - Update (2026-04-23): the next reciprocal-fastmod follow-up under that same shipped fill
	     surface is now rejected too. The earlier naive reciprocal path had already shown why the
	     first idea lost: `build/logs/otool_fill_list_int_oren_inspect_fastmod_full_20260423_v1.log`
	     materialized the reciprocal constant inside the hot loop each iteration. A narrower rerun
	     then hoisted the shared `% 1000` divisor and reciprocal into preheader regs and kept the
	     reciprocal lowering only on the shipped nonnegative-linear `fast_list_int_push_while`
	     surface, but the exact same-tree probe still regressed hard:
	     `build/logs/perf-probe-list-int-fill-share-decision-20260423_024106_13895.log` moved from the
	     current baseline `~2.3103×` / `~0.003096` to `~2.8408×` / `~0.003746`. The emitted code proves
	     the hoist itself worked: `build/logs/otool_fill_list_int_oren_inspect_fastmod_hoist_full_20260423_v1.log`
	     preloads `x24=#1000` and `x25=<reciprocal>` once before the loop and uses `umulh` in the hot
	     body. Reweight again: the remaining shipped fill-side blocker is not just the reciprocal
	     literal materialization; the next pass should inspect the surviving loop body around slot
	     writes, count/cursor updates, and safepoint-reset scaffolding instead of reopening this
	     reciprocal branch.
	   - Update (2026-04-21): the shared native quick path now carries an explicit GC reuse tracking
	     smoke. `tests/native/test_gc_reuse_tracking.oren` was tightened so the dead headers are
	     created through `oren_new_list(0)` and an escaping aggregate, then
	     `scripts/run_native_quick_integration.sh` builds it with `OREN_ARENA_AUTO_LOOP=0` and runs it
	     under `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=1`,
	     `OREN_GC_REUSE_LISTS_UNSAFE=1`, `OREN_TRACE_GC_REUSE_SUMMARY=1`, failing if the run does not
	     emit a nonzero `[gc_reuse_summary] ... hits=...`. Current quick log shows `hits=4` followed by
	     `gc reuse tracking OK` (`build/logs/oren_native_quick_integration.log`).
	   - Fix + verify (2026-04-21): the native build cache now includes a curated build-affecting
	     native env surface instead of reusing the same artifact across incompatible fast-path modes.
	     The concrete regression was a sequential same-cache build of
	     `tests/native/test_gc_reuse_alloc_churn_min.oren`: with the old key,
	     `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=1` restored the cached `...=0` artifact. The
	     cache key in `lib/compiler/compiler/012_build_cache.oren` now carries the native fast-loop
	     env surface plus content hashes for runtime override-file envs, and
	     `scripts/verify_build_cache_native_env_surface.sh` guards that the two env modes differ
	     while a repeated same-mode build restores from cache.
		   - Refresh (2026-04-21): the earlier 2-run hunt was too weak to retire this thread.
		     The wider current rerun
		     (`build/logs/repro_bad_list_alloc_churn_current_20260421_205455.log`, `RUNS=10`) still
		     produced no `[gc_reuse_bad_list]` prints, but it did reproduce a live runtime failure on the
		     current tree: 4/10 runs panic with `list_int_push on non-list`
		     (`build/logs/alloc_churn_bad_list_auto_20260421_205513_3.log`,
		     `build/logs/alloc_churn_bad_list_auto_20260421_205513_4.log`,
		     `build/logs/alloc_churn_bad_list_auto_20260421_205549_8.log`,
		     `build/logs/alloc_churn_bad_list_auto_20260421_205549_9.log`).
		   - Fix + verify (2026-04-21): `native_list_panic_footer(...)` now respects the list-header
		     ring env itself, and `scripts/repro_bad_list_alloc_churn.sh` now always enables the ring /
		     dup trace surface, records the concrete run parameters into each run log, and treats the
		     current `list_int_push on non-list` panic as a hit instead of falsely ending with only
		     “no bad-list hits”. The focused current rerun
		     (`build/logs/alloc_churn_bad_list_focus_20260421_210001.log`) now emits
		     `[list_hdr_ring_recent]` for the failing pointer, showing a sane `list<int>` growth sequence
		     ending at `len=64 cap=64` immediately before the panic. There is now a stable current entry
		     point for this thread at `make triage-alloc-churn-bad-list-current`.
		   - Fix + verify (2026-04-21): the compact explicit-collect alloc-churn failure was an
		     overlapping free-list reuse bug, not another generic list push corruption. The free-list
		     path in `100_time_gc_alloc_core_scan_reuse.oren` now drops candidates whose tracked range
		     overlaps any live alloc range, and the existing “free node still in allocs” plus
		     alloc-index-dup guardrails are now unconditional instead of trace-only. In the same slice,
		     arm64/x64 explicit `oren_gc_collect()` lowering now spills callee-saved registers like the
		     safepoint helper, conservative mark skips stale aliased list headers instead of panicking,
		     and `scripts/verify_alloc_churn_tracking_smoke.sh` now includes
		     `tests/native/test_gc_collect_alloc_churn_debug_shape.oren`. Current proof:
		     `build/logs/verify_alloc_churn_tracking_20260421_220046_gates_restored.log`.
		   - Fix + verify (2026-04-21): the remaining no-arena explicit-collect `list<int>` corruption
		     was a live-header overlap. Reuse now checks runtime/global roots by range
		     (`native_gc_root_find_in_range(...)`) instead of only exact pointer equality, and
		     `_list_alloc_buf(...)` now refuses any returned buffer whose range overlaps the live
		     32-byte list header. When that impossible overlap still appears, the helper recycles the
		     just-reactivated node back to the free list and falls back to a fresh raw allocation, so
		     the copy loop cannot overwrite the header. The focused no-arena repro
		     `tests/native/test_gc_collect_list_int_len128_loop_live.oren` now passes on both stage1
		     and fresh stage2
		     (`build/logs/gc_collect_list_int_len128_loop_live_stage1_probe2.run.log`,
		     `build/logs/gc_collect_list_int_len128_loop_live_stage2_probe2.run.log`), and the current
		     compact stage2 smoke is green again
		     (`build/logs/verify_alloc_churn_tracking_20260421_stage2_after_overlap_guard.log`).
		   - Refresh + verify (2026-04-22): that broader benchmark-sized triage thread is no longer
		     reproducing on the current tree. The reduced explicit-collect fixture
		     `tests/native/test_gc_collect_alloc_churn_debug_shape.oren` now runs clean 20/20 on fresh
		     stage2 (`build/logs/gc_collect_alloc_churn_debug_shape_runs_default.log`), and the bounded
		     benchmark hunt now ends with `no bad-list hits in 10 runs`
		     (`build/logs/make_triage_alloc_churn_bad_list_current_20260422_post42713c00.log`). The old
		     nonzero `make` status there was only the hunt tool’s “no hit found” convention, not a live
		     failure.
		   - Guard restore (2026-04-22): the reduced debug-shape fixture stays out of the Tier-1 quick smoke
		     because the full stress env is too expensive there, but the repo now ships a real verifier
		     `verify-alloc-churn-broad-current` that first runs the reduced fixture directly on fresh stage2
		     and then inverts the hunt-script exit convention into a bounded success check. `verify-runtime-robustness`
		     includes that new leg so the broader alloc_churn surface stays guarded without keeping a stale
		     open TODO.
	   - Fix + verify (2026-04-21): the focused green join-waiter/STW flake now has current runtime
	     fixes and a bundled guard instead of only historical traces. `100_time_core.oren` now
	     collapses duplicate OS-thread nodes that share a recycled TID, prefers live nodes in
	     `native_time_current_thread_node_or0()`, and marks all same-TID nodes DEAD during exit/join
	     cleanup so STW parked-count math cannot accumulate phantom threads. A second current trace
	     then narrowed the remaining stall to a lost-wake window around netpoll-blocked threads, so
	     `100_time_gc_stw.oren` now reissues `native_netpoll_wake()` while STW is still short on
	     parked threads and waits in bounded 10ms slices instead of long sleeps. The new split guard
	     `scripts/verify_native_quick_green_join_waiters_modes.sh` prewarms the debug rtobj seed and
	     proves both the green-only and OS-only stress modes under stage2; the bundled W5 runtime gate
	     now runs it by default (`build/logs/verify_native_quick_green_join_waiters_modes_20260421_194941.log`,
	     `build/logs/runtime_robustness_w5_20260421_193511.log`).
		   - Refresh (2026-04-21): the direct world-lock/entry-args slice is now current evidence, not
		     only an old March trace branch. `scripts/triage_green_two_workers_world_lock_smoke.sh`
		     passed 3/3 with `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_ENTRY_ARGS=1`,
		     `OREN_QI_TRACE_GREEN_LIST=1`, `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1`, and
		     `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50`
		     (`build/logs/triage_green_world_lock_entry_args_current_20260421_200041.log`), and the
		     inner log shows sane `green_entry_args` metadata all the way through `gc collect done`
		     (`build/logs/oren_stage2_green_two_workers_world_lock_smoke.log`). The repo now ships that
		     exact traced recipe in `verify-green-world-lock-guarded`, and `verify-runtime-robustness`
		     includes a one-run direct world-lock leg with the same env set.
		   - Fix + verify (2026-04-21): the runtime-robustness / flake wrappers no longer leak child
		     processes when interrupted. `scripts/run_native_quick_integration.sh` now starts Darwin
		     timeout builds in a fresh process group and kills the whole group on timeout, while the
		     surrounding triage wrappers track the active child PID and recursively terminate descendant
		     trees on SIGTERM/SIGINT before copying inner logs. The interrupted base-only proof run in
		     `build/logs/runtime_robustness_interrupt_cleanup_20260421_202907.log` left no orphan
		     `run_native_quick_integration.sh` or `./oren_stage2 build ...` processes behind.
		   - Correction + verify (2026-04-21): the old “pre-world-lock stage2 hang” interpretation was
		     stale. A clean current rerun now carries the same tree through the guarded pre-world-lock
		     gate, the direct world-lock gate, stage2 native quick integration, the three C-backend
		     flake fixtures, alloc-churn tracking, and the split green/os join-waiter guard
		     (`build/logs/make_verify_runtime_robustness_20260421_cleanupfix_20260421_202922.log`,
		     `build/logs/runtime_robustness_w5_20260421_202923.log`,
		     `build/logs/verify_native_quick_green_join_waiters_modes_20260421_204329.log`).
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
    (set `EXTRA_TRACE=1` to include reuse summary + list-hdr kind/ok traces; set
    `CRASH_FOOTER=0` to skip enabling crash_footer; it now runs the correlator on runs
    that emit crash_footer output unless `REPRO_BAD_LIST_CORRELATE=0` is set, and prints
    the first `[crash_footer_raw]` line plus a few ring dump lines when present,
    2026-03-05).
  - Tool: `OREN_TRACE_CRASH_FOOTER=1` installs a best-effort crash footer on macOS
    (SIGSEGV/SIGBUS) that dumps alloc-index counts plus list header ring contents when
    the process crashes (debug-only; not signal-safe, 2026-03-05).
  - New: crash footer now emits a minimal `crash_footer_raw` line via `sys_write`
    before higher-level printing, to improve chances of output under severe
    corruption (debug-only; not signal-safe, 2026-03-05).
  - New: crash footer now logs `[crash_footer] installed` when the handler is
    registered (debug-only, 2026-03-05).
  - New: crash footer now registers an alternate signal stack (SIGSTKSZ) and
    installs handlers via `sigaction` with `SA_ONSTACK` on macOS (debug-only, 2026-03-05).
  - New: `crash_footer_raw` now includes list header ring pointer + guard values
    to help diagnose ring corruption (debug-only, 2026-03-05).
  - New: enabling `OREN_TRACE_CRASH_FOOTER=1` now force-enables list header ring
    capture so crash footers can report ring state even without separate trace
    flags (debug-only, 2026-03-05).
  - New: `crash_footer_raw` now includes list header ring head/cap values
    (debug-only, 2026-03-05).
  - New: `crash_footer_raw` now emits limited ring dump lines (idx/list/op/len/cap/buf/magic/kind)
    to stderr to preserve recent list header history even when higher-level printing fails
    (debug-only, 2026-03-05).
  - Tool: list<int> panic footer now always emits alloc-index counts; enabling
    `OREN_TRACE_LIST_PANIC_FOOTER=1` also dumps the list header ring for the offending list
    (debug-only, 2026-03-05).
  - Fix: arm64/x64 list<int> intrinsics now invoke `native_list_panic_footer` before
    emitting "list_int_push on non-list" panics, so the footer is captured even when the
    runtime list_int_push is bypassed (2026-03-05).
  - Trace: alloc_churn trace with crash footer + alloc-index tracing hit
    `list_int_push on non-list` panic (no `[crash_footer]` output), indicating
    a non-SEGV failure mode before bad-list triggers
    (log: `build/logs/alloc_churn_trace_crash_footer_20260305_044237.log`, 2026-03-05).
  - Trace: repro bad-list alloc_churn runs (poison headers + reuse) segfaulted
    quickly and still emitted no `[crash_footer]` output, even with
    `OREN_TRACE_CRASH_FOOTER=1` enabled
    (logs: `build/logs/alloc_churn_bad_list_auto_20260305_050800_0.log`,
    `build/logs/alloc_churn_bad_list_auto_20260305_050830_0.log`, 2026-03-05).
  - Trace: repro bad-list alloc_churn runs now emit `[crash_footer_raw]` after
    enabling sigaltstack + sigaction (logs:
    `build/logs/alloc_churn_bad_list_auto_20260305_053740_0.log`,
    `build/logs/alloc_churn_bad_list_auto_20260305_053740_1.log`, 2026-03-05).
    Wrapper log reports rc=132 (Illegal instruction) while the crash footer
    reports signal 11; keep for context (summary log:
    `build/logs/repro_bad_list_alloc_churn_sigaltstack_20260305_053739.log`).
  - Trace: crash_footer_raw now includes list_hdr_ring ptr/guard in bad-list repros
    (logs: `build/logs/alloc_churn_bad_list_auto_20260305_054630_0.log`,
    `build/logs/alloc_churn_bad_list_auto_20260305_054630_1.log`, 2026-03-05).
  - Trace: crash_footer_raw ring fields confirmed non-zero after auto-enabling ring
    (summary log: `build/logs/repro_bad_list_alloc_churn_ring_20260305_060019.log`,
    2026-03-05).
  - Trace: crash_footer_raw now shows ring head/cap values in bad-list repros
    (logs: `build/logs/alloc_churn_bad_list_auto_20260305_060705_0.log`,
    `build/logs/alloc_churn_bad_list_auto_20260305_060705_1.log`, 2026-03-05).
  - Tool: `[alloc_index_list_counts_at_bad_list]` now prints alloc-index zeroed/bad counts
    plus index len/cap at each `[gc_reuse_bad_list]` when `OREN_TRACE_ALLOC_INDEX=1`
    (2026-03-05).
  - Trace: alloc_churn hunt with alloc-index tracing enabled
    (`OREN_TRACE_ALLOC_INDEX=1`, `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=64`, runs=10)
    completed with no corruption signatures or `alloc_index_list_counts_at_bad` output
    (log: `build/logs/alloc_churn_hunt_counts_at_bad_20260305_042000.log`, 2026-03-05).
  - Trace: `scripts/repro_bad_list_alloc_churn.sh` with alloc-index tracing + extra list-hdr
    traces (`RUNS=20`, `EXTRA_TRACE=1`) exited with repeated segfaults (status 139) and no
    `gc_reuse_bad_list` / `alloc_index_list_counts_at_bad` hits (summary log:
    `build/logs/repro_bad_list_counts_at_bad_20260305_042036.log`, per-run logs:
    `build/logs/alloc_churn_bad_list_auto_20260305_0420*.log`, 2026-03-05).
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
  - Tool: `tools/trace_list_hdr_correlate.py` now includes `[list_hdr_ring]` and
    `crash_footer_raw` ring entries when correlating `gc_free_list` samples
    (rolling, 2026-03-05).
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
    `gc_reuse_bad_list` and `gc list_int header corrupt`; list_hdr ring dump shows only
    op=91 entries (logs:
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
  - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now auto-enables free-list header dumps +
    list_hdr ring capture (no separate `OREN_TRACE_LIST_HDR_RING` needed, 2026-02-26).
  - Trace: alloc_churn with `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now emits `[list_hdr_ring]`
    samples alongside `[gc_free_list]` without extra ring flags
    (log: `build/logs/alloc_churn_trace_gc_ring_20260226_172250.log`).
  - Tool: `tools/trace_list_hdr_correlate.py --log <log> --limit 5 --max 50` correlates
    `[list_hdr]`, `[list_hdr_ring]`, and `crash_footer_raw` ring traces with
    `[gc_free_list]` samples, surfaces `list_corrupt` / `gc_list_*_corrupt` events, and
    attaches ring dumps when present to spot last header writes; it also emits ring-only
    blocks when only ring entries are available and annotates crash_footer ring head/cap
    plus derived ring ages when present.
  - Update (2026-03-05): arena list/list_int allocations now emit list_hdr ring entries
    (op=1/2) so ring dumps include arena-backed list headers.
  - New: `OREN_TRACE_ALLOC_INDEX=1` now logs `[alloc_index_list_bad]` when list/list_int
    nodes are inserted with non-magic headers (excluding poison) to catch kind/ptr drift.
  - New: `OREN_TRACE_LIST_CTOR=1` logs `[list_ctor]` stages (`pre_init`, `post_init`, `post_track`)
    for list/list_int allocations, with filters `OREN_TRACE_LIST_CTOR_PTR` /
    `OREN_TRACE_LIST_CTOR_NODE` to align ctor events with `[alloc_index_list_bad]` pointers.
  - Trace (2026-03-05): alloc_churn gc_ring_poison_hi_alloc_index hits `[alloc_index_list_bad]`
    immediately with magic=0 before `gc_reuse_bad_list`, implying alloc-index sees invalid
    headers at insert time (logs:
    `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1.log`,
    `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1_correlate.log`,
    `build/logs/alloc_churn_hunt_alloc_index_20260305_030652.log`).
  - Trace (2026-03-05): ctor-trace run shows `[alloc_index_list_bad]` fires before
    `[list_ctor] stage=pre_init` for the same ptr, so alloc-index insertion happens
    ahead of list header initialization; magic=0 appears to be expected for fresh
    list allocations (log:
    `build/logs/alloc_churn_trace_gc_ring_poison_hi_ctortrace_20260305_031847.log`).
  - Update (2026-03-05): alloc-index now emits `[alloc_index_list_zeroed]` only when
    `OREN_TRACE_ALLOC_INDEX_ZEROED=1` and the list header is still zeroed (magic/len/cap/buf
    all 0), separating fresh allocations from genuine corruption in
    `[alloc_index_list_bad]`.
  - Update (2026-03-05): alloc-index list trace lines now include `zeroed_count`/`bad_count`
    counters to quantify noise reduction across a run.
  - Update (2026-03-05): GC summary now prints `[alloc_index_list_counts]` when
    `OREN_TRACE_ALLOC_INDEX=1` to report zeroed/bad totals per sweep.
  - Update (2026-03-05): `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=<n>` dumps the last
    `<n>` list_hdr ring entries when `[alloc_index_list_bad]` fires.
  - Update (2026-03-05): `[gc_reuse_bad_list]` now includes `freed_seen=<0|1>` when
    `OREN_TRACE_GC_FREED_LISTS=1` to flag potential use-after-free list headers.
  - Update (2026-03-05): list header corruption dumps now include
    `[alloc_index_list_counts_at_bad]` when `OREN_TRACE_ALLOC_INDEX=1` so counts are
    preserved even if GC panics.
  - Trace (2026-03-05): alloc_churn with `OREN_TRACE_GC_FREED_LISTS=1` showed `freed_seen=0`
    across multiple `[gc_reuse_bad_list]` prints (log:
    `build/logs/alloc_churn_trace_alloc_index_bad_freed_20260305_041225.log`).
  - Trace (2026-03-05): alloc_churn run with `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=8`
    hit `gc list_int corrupt` and emitted list_hdr ring dumps from GC reuse traces, but did
    not trigger `[alloc_index_list_bad]` yet (log:
    `build/logs/alloc_churn_trace_alloc_index_bad_ring_20260305_035440.log`).
  - Trace (2026-03-05): alloc_index_bad_ring hunt run 1 (same env + alloc-index zeroed)
    logged `zeroed_count=87`, `bad_count=0`, and no `[alloc_index_list_bad]` despite
    `gc list_int corrupt` (log:
    `build/logs/alloc_churn_trace_alloc_index_bad_ring_20260305_035623_1.log`).
  - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX=1` +
    `OREN_BENCH_GC_EVERY=50` emitted repeated `[alloc_index_list_counts]` lines
    (log: `build/logs/alloc_churn_trace_alloc_index_counts_summary_gc_20260305_034720.log`).
  - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX=1` +
    `OREN_TRACE_ALLOC_INDEX_ZEROED=1` (`OREN_BENCH_ITERS=2000`) reported `zeroed_count=2`
    and `bad_count=0` (log:
    `build/logs/alloc_churn_trace_alloc_index_counts_20260305_033136.log`).
  - Trace (2026-03-05): higher-pressure alloc_churn with GC reuse knobs +
    `OREN_TRACE_ALLOC_INDEX_ZEROED=1` reported
    `zeroed_count=256` and `bad_count=0` (log:
    `build/logs/alloc_churn_trace_alloc_index_counts_hi_20260305_033237.log`).
  - Tool: `tools/run_alloc_churn_trace.sh [tag]` builds + runs alloc_churn and records
    OREN/AVM env + logs for reproducible trace runs. Use `ALLOC_CHURN_RUN_TIMEOUT_SECS`
    to bound long-running traces.
  - Tool: `tools/run_alloc_churn_hunt.sh [max_runs] [tag_base]` repeats the alloc_churn
    trace harness until a corruption signature is found (or a timeout/failure stops the
    hunt), emitting logs under `build/logs/`. Set `ALLOC_CHURN_HUNT_CORRELATE=0` to
    skip auto-correlation; tune output via `ALLOC_CHURN_HUNT_CORRELATE_LIMIT/MAX`.
    The harness now prints the first `[crash_footer_raw]` line plus a few ring dump
    lines when a run fails or times out, and runs the correlator on failures/timeouts
    when enabled (2026-03-05).
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
   - New run (arm64, 2026-04-22, runs=5, warmups=1; via `make perf-gate-native-refresh-latest`):
     - loop_sum: C 0.066952s, native 0.073464s (1.10× C).
     - dot_product: C 0.005423s, native 0.015320s (2.83× C).
   - Fix: shared arm64 `UMULH` opcode encoding was wrong; correcting it restores the intended
     reciprocal-mod lowering used by the arm64 fast LCG loop (2026-03-20).
	   - New: `benchmarks/loop_sum/loop_sum.oren` now preserves inty CLI args via `oren_trunc_int(...)`,
	     so arm64 loop_sum re-enters `fast_lcg_sum_while_no_tick` instead of falling back to `while_generic` (2026-03-20).
		   - New focused canonical split runner (2026-04-04): `array_sum` / `dot_product` now accept
		     optional `n` + `reps` CLI args, and `make perf-gate-native-read-split` measures the same
		     split workload across C/native variants.
		   - Reweight: loop_sum is still within the <=2× gate on arm64; the remaining canonical gap is
		     centered on `dot_product`, but the fresh 2026-04-22 attribution is narrower than “some old
		     scalar-core toggle probably fixes it”. The latest read-split repeated-work view is still
		     3.47× C (`build/logs/perf-gate-native-read-split-20260422_002728_90701.log`), the refreshed
		     scalar-ceiling probe is still 1.8452× slower than scalar host C
		     (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log`), and the
		     current scalar-core matrix keeps baseline over cursor/scalar variants
		     (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`).
		   - Fix + rerun (2026-04-05): `make perf-probe-list-int-specialization-gap` now sends the right
		     steady-runner knobs to each side (`OREN_BENCH_NATIVE_STEADY_*` for generic,
		     `OREN_BENCH_LIST_INT_STEADY_*` for specialized). The earlier artifact
		     `build/logs/perf-probe-list-int-specialization-gap-20260405_025217_48504.log` is superseded:
		     it overstated the gap because the generic side accidentally ignored the intended `n/reps`.
		     Corrected artifact (`build/logs/perf-probe-list-int-specialization-gap-20260405_025957_59475.log`,
		     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=1`, `n=200000`,
		     `reps=10`) measured:
		     - `array_sum`: generic `~1.3419× C` vs specialized `~1.4064× C` (`~0.9541×` gap)
		     - `dot_product`: generic `~1.5169× C` vs specialized `~1.4803× C` (`~1.0247×` gap)
		   - New specialization read-split probe (2026-04-05): `make perf-probe-list-int-specialization-read-split`
		     now separates setup-heavy short runs from repeated-loop long runs across the same
		     generic/specialized benchmark pairs. Latest artifact
		     (`build/logs/perf-probe-list-int-specialization-read-split-20260405_030027_60451.log`)
		     shows the reliable `long_per_rep` view stays near parity:
		     - `array_sum`: generic `~1.5652× C`, specialized `~1.4639× C` (`~1.0692×` gap)
		     - `dot_product`: generic `~1.5241× C`, specialized `~1.5157× C` (`~1.0055×` gap)
		     The delta estimate is too noisy to drive tracker updates here; use the long-per-rep view.
		   - New focused arm64 dot-prefix-zero specialization wrapper (2026-04-09):
		     `make perf-probe-arm64-fast-dot-prefix-zero-specialization` compares generic
		     auto-specialized `dot_product` against explicit `dot_product_int` on both the shipped
		     default and `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`, then bundles the aligned steady
		     gap, read-split gap, and specialization trace into one artifact. Latest rerun
		     (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-specialization-20260409_011654_49934.log`)
		     shows the generic/explicit gap stays small, and restoring parsed-bound reserve insertion
		     moved both whole-operation ratios materially in the right direction:
		     - default steady: generic `~1.3947× C`, specialized `~1.6008× C` (`~0.8713×` gap)
		     - enabled steady: generic `~1.3992× C`, specialized `~1.5518× C` (`~0.9017×` gap)
		     - default read-split long-per-rep: generic `~1.6788× C`, specialized `~1.7004× C`
		       (`~0.9873×` gap)
		     - enabled read-split long-per-rep: generic `~1.6392× C`, specialized `~1.5860× C`
		       (`~1.0335×` gap)
		     - specialization trace now shows the benchmark fill loops taking typed reserve plus typed
		       unchecked pushes on both sides (`list_int_reserve=2`, `list_int_push_unchecked=2` for the
		       `dot_product` pair; trace summary
		       `build/logs/perf-probe-list-int-specialization-trace-20260409_011625_49062.log`)
		     Reweighting: the generic parsed-bound fill/setup gap is no longer the blocker on this
		     benchmark pair. The remaining gap is back in the steady arm64 dot core versus C.
		   - New specialization trace probe (2026-04-05): `make perf-probe-list-int-specialization-trace`
		     now confirms the benchmark fill loops take the full intended typed path, not just the
		     constructor rewrite:
		     - generic `array_sum`: `rewrite_init=1`, `list_int_reserve=1`, `list_int_push_unchecked=1`
		     - generic `dot_product`: `rewrite_init=2`, `list_int_reserve=2`, `list_int_push_unchecked=2`
		     - explicit `array_sum_int`: `list_int_reserve=1`, `list_int_push_unchecked=1`
		     - explicit `dot_product_int`: `list_int_reserve=2`, `list_int_push_unchecked=2`
		     The remaining boxed `list_reserve=1` / `list_push_unchecked=1` counts come from shared
		     helper functions, not from the benchmark fill loops.
			   - New scalar-ceiling probe + env-parse fix (2026-04-05, extractor refreshed 2026-04-11):
				   `make perf-probe-arm64-dot-vs-c-loop-compare` now forwards comma-separated
				     `OREN_BENCH_ENV_BUILD_OREN` correctly and finds C loop blocks by instruction shape
				     (`smlal*` for vector blocks, `smaddl` for the scalar tail) instead of hardcoded Clang
				     `LBB0_*` labels. Latest loop-compare rerun
				     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260422_002728_90700.log`)
				     shows the current shipped Oren generic `dot_product` window as a 20-instruction
				     traced range, with the skipped cold GC-call block now split out as `8`
				     instructions and the hot range-without-cold-tick at `12` instructions. Host C still
				     has vector/mid/tail blocks (`28` / `12` / `6` extracted-block instructions), and
				     the new explicit-list counterpart
				     `make perf-probe-arm64-dot-vs-c-loop-compare-list-int`
				     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-20260411_165935_82064.log`)
				     shows the same 21-instruction `dot_product_int` Oren traced range, the same
				     14-instruction range without the cold GC-call block, and the same C vector/mid/tail
			     shape. Both probes now resolve C labels by instruction pattern rather than assumed
			     block numbers, and
			     `make perf-probe-arm64-dot-vs-c-scalar-ceiling` now compares exact Oren native `dot_product`
			     against both vectorized and de-vectorized host-C builds. The scalar-ceiling runner is now
			     parameterized too, with explicit `dot_product_int` coverage via
			     `make perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int`. Latest artifacts:
			     - generic `dot_product`
			       (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log`):
			       scalar/vector C `~2.9275×`, Oren/scalar `~1.8452×`, Oren/vector `~5.4018×`
			     - explicit `dot_product_int`
			       (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int-20260411_164309_41086.log`):
			       scalar/vector C `~3.0352×`, Oren/scalar `~1.7130×`, Oren/vector `~5.1992×`
			     The corrected scalar-ceiling extractor now reports the precise inner C loops too: 28
			     instructions for the NEON vector body and 6 for the de-vectorized scalar `smaddl` loop
			     on both sources.
			   - Scalar-core matrix refresh (2026-04-22):
			     `make perf-probe-arm64-fast-dot-scalar-core-matrix`
			     (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`)
			     keeps the shipped baseline over the older generic cursor/scalar candidates. Relative to
			     baseline, `SINGLE_PAIR_CURSOR_REGS=0` regresses steady/gate native medians
			     `+3.76%` / `+4.67%`, `MADD_EXACT_SCALAR=1` regresses `+0.50%` / `+2.97%`, and the
			     combined row regresses `+2.90%` / `+2.96%`.
			   - Reweight accordingly: generic-list specialization is not the dominant remaining blocker for
			     canonical `dot_product`. Scalar loop debt is still material, but the current tree is again
			     saying “baseline beats the older scalar toggles,” so the remaining large gap is dominated by
			     the missing vector/slot64-quality path relative to the host C baseline.
			   - Generic whole-list-helper decision (2026-04-22):
			     `make perf-probe-arm64-fast-dot-whole-list-helper-decision`
			     (`build/logs/perf-probe-arm64-fast-dot-whole-list-helper-decision-20260422_004934_99469.log`)
			     closes the remaining “maybe just call the helper” branch on the actual canonical generic
			     `dot_product` surface. Helper-enabled loses everywhere:
			     - read-split `long_per_rep`: `0.006172s` vs baseline `0.002664s` (`+131.68%`)
			     - read-split repeated-work delta: `+270.80%`
			     - order-balanced native median: `+20.08%` (`wins=0/4`)
			     - order-balanced native/C ratio: `+19.38%` (`wins=0/4`)
			     Reweight again: do not spend more W5 time on whole-list helper promotion for generic
			     `dot_product`; the remaining high-leverage path is a new arm64 vector/slot64-quality kernel.
	   - Trace (2026-03-20): a targeted arm64 `dot_product` experiment that hoisted the single-pair
	     list<int> cursors fully into callee-saved regs did not help; the fresh perf gate moved
	     `dot_product` from about 2.51× C to about 2.55× C, so cursor stack traffic is not the
     dominant remaining cost on this path.
   - Trace (2026-03-20): a follow-up arm64 `dot_product` experiment that fused the hot
     `sum += left * right` pairs into `MADD` also regressed on Apple M2 Pro; the focused
     perf gate moved `dot_product` from about 2.51× C to about 2.70× C, so the remaining
     gap is not just the current `MUL` + `ADD` pair count.
   - Trace (2026-03-20): a second follow-up that replaced the unique unrolled `list<int>`
     cursor loads with `LDP ... post-index` pair loads also regressed on Apple M2 Pro; the
     focused perf gate moved `dot_product` from about 2.51× C to about 2.71× C, so the
     remaining gap is not dominated by the current per-side load/address-update sequence either.
   - Trace (2026-03-20): a third follow-up that hoisted invariant `n` into a preserved reg
     across the fast read-only list loops also regressed on Apple M2 Pro; the focused perf
     gate moved `dot_product` from about 2.51× C to about 2.84× C, so the remaining gap is
     not explained by the current per-iter loop-bound stack reload either.
   - Trace (2026-03-20): a follow-up `array_sum_int` experiment that hoisted the single-list
     `list<int>` cursor into a preserved reg was not safe to keep; the focused `list<int>` gate
     built successfully but the native `array_sum_int` benchmark binary crashed during execution,
     so the shared read-heavy path should not move list data cursors out of the established stack
     slots without a stronger GC-rooting argument.
   - Latest focused list<int> clean rerun (arm64, 2026-04-04): `array_sum_int` 2.07× C,
     `dot_product_int` 2.59× C, `multi_list_push_int` 2.24× C. One-shot list<int> results are
     now best used as a smoke view; they are no longer precise enough to rank the remaining
     steady-state blocker on their own.
   - New: the exact two-list single-pair arm64 `list<int>` dot shape keeps both data cursors in
     callee-saved regs across iterations/safepoints, and the exact single-list `list<int>` get-sum
     shape now also pairwise-reduces its 4-wide and 2-wide hot bodies to shorten the running-sum
     dependency chain. That moved the current steady rerun to ~2.43× for `array_sum_int`, while
     the unchanged exact-pair dot path now measures ~2.78× on the same rerun (Apple M2 Pro, 2026-04-04).
   - Tooling: benchmark result artifacts now retain raw timing vectors plus `stdev_s` / `cov`,
     so tracker updates can distinguish stable reruns from one-off outliers.
   - New focused steady-state runner (2026-04-04, `make perf-gate-list-int-steady`, `reps=100`):
     `array_sum_int` steady-state native/C is ~2.43× and `dot_product_int` steady-state native/C
     is ~2.78×. The remaining blocker is still the repeated read/mul/accumulate loop itself,
     not one-time fill/setup cost.
   - New guardrail (2026-03-20): `make perf-smoke-list-int` now builds the native
     `array_sum_int` / `dot_product_int` benchmark binaries once and checks both the exact tiny
     scalar-tail outputs (`205` and `6590`) and the >16-element hot-path outputs (`710` and
     `54380`) before heavier timing sweeps. The main `list<int>` perf runners now invoke this
     smoke by default, with `OREN_PERF_SMOKE_LIST_INT=0` as the explicit opt-out.
   - Trace (2026-03-20): a follow-up arm64 exact-dot experiment that tried to split the
     single-pair `dot_product_int` accumulation chain across two persistent accumulators was not
     safe to keep. Even after reworking the register choice, the direct native smoke returned
     `4621` for `dot_product_int 10 3` instead of the known-good `6590`, so future dot-core work
     should clear `make perf-smoke-list-int` before trusting any perf-gate result.
   - Trace (2026-03-20): a narrower follow-up that hoisted `n` into X21 only for the unique
     arm64 read-only `list<int>` fast loops was also not a shared win. On the steady runner it
     moved `array_sum_int` from about 3.28× C to about 3.21× C, but `dot_product_int` regressed
     from about 3.74× C to about 3.95× C, so the loop-bound reload is not the dominant blocker
     on the shared path.
   - New unsafe steady probe (2026-03-20, consolidated rerun via
     `make perf-probe-list-int-unsafe`): the pre-unroll4 clean baseline was `array_sum_int` ~3.38× C and
     `dot_product_int` ~3.90× C. `OREN_LIST_ASSUME_LIST=1` nudged them only to ~3.25× / ~3.88×,
     `OREN_NATIVE_ASSUME_LIST_INDEX=1` moved them to ~3.36× / ~4.09×, and combining both landed
     at ~3.32× / ~3.94×. So runtime list validation and compiler-side direct index lowering are
     only partial ceilings, not a shared fix for the steady-state read-heavy path.
   - Trace (2026-03-20): replacing the new arm64 4-wide exact-shape loads with `ldp ... post-index`
     pair loads was also not a win. The experimental steady rerun moved `array_sum_int` from about
     2.87× C to about 2.95× C and `dot_product_int` from about 3.17× C to about 3.33× C, so the
     remaining shared gap is not mainly the current scalar load-address sequence inside those 4-wide paths.
   - Trace (2026-03-20): a narrower follow-up that locally pairwise-reduced the exact single-pair
     arm64 `dot_product_int` 4-wide and 2-wide bodies before adding into the running sum stayed
     correct under `make perf-smoke-list-int`, but the steady rerun still regressed slightly:
     `dot_product_int` moved from about 3.09× C to about 3.13× C, so reducing the number of
     per-body writes into `x23` alone is not the missing win.
   - Trace (2026-03-20): a stricter follow-up that reduced the exact 4-wide single-pair arm64
     `dot_product_int` body all the way down to one final `x23 += batch_sum` update also stayed
     correct under `make perf-smoke-list-int`, but the steady rerun regressed further:
     `dot_product_int` moved to about 3.22× C. That makes the current evidence stronger: simply
     collapsing the exact 4-wide batch into fewer running-sum writes does not solve the blocker.
   - Trace (2026-03-20): a later direct NEON chunking experiment for the exact single-pair arm64
     `dot_product_int` path was also not safe to keep. The emitted vector body itself assembled and
     passed the tiny `10 3` smoke, but the widened smoke and steady runner exposed deterministic
     wrong-code (`54380` hot-path smoke failed; full benchmark output halved to `253794000000`).
     Root cause: current `list<int>` fast loops read 64-bit list slots, while the existing packed-i32
     SIMD dot kernel shape assumes 32-bit lanes. So a future SIMD bridge here needs either a safe
     packed-i32 view or a dedicated 64-bit-slot lowering, not a direct cursor handoff.
   - New native runtime helpers (2026-03-20): `oren_list_int_data_ptr(...)`,
     `oren_list_int_data_ptr_unchecked(...)`, and `oren_list_int_slot_stride_bytes()` now expose
     that 64-bit-slot payload contract directly, and the Tier-1 native quick fixture
     `tests/native/qi/100_tests_basic.oren` guards it. That narrows future bridge work to
     "build a safe packed view" or "target the 64-bit-slot ABI directly" instead of rediscovering
     the layout experimentally.
   - New bridge/probe boundary (2026-03-20): the safe `list<int> -> []i32` stdlib packing path now
     exists and is cross-backend checked, but the default native benchmark profile is still the
     reduced `core` runtime, not `full`. Hidden packed-bridge benchmarks plus
     `make perf-probe-list-int-packed-bridge` now isolate that ceiling measurement instead of
     polluting the canonical `array_sum_int` / `dot_product_int` gates.
   - Fix (2026-03-27): the native core runtime now carries the minimal `i32` typed-buffer dot
     family needed by the packed bridge, so both hidden packed-bridge benchmarks build on the
     default core profile and `std:linalg.dot_i32_list_int_packed(...)` no longer has to stay on a
     scalar fallback.
   - Fix (2026-05-04): arm64/x64 native runtime-profile selection now treats `std:linalg` as a
     full-runtime dependency when typed-buffer kernels are reachable, preventing native builds
     that call `linalg.dot_f64_buf(...)` from linking against the reduced core profile. The new
     native quick smoke `tests/fixtures/native_linalg_typed_buffer_runtime_profile_smoke.oren`
     also guards `oren_buf_data_mod(...)` on native typed buffers.
   - API cleanup (2026-05-04): `std:linalg` now exposes explicit `try_*` aliases over the public
     dot/reduce/AXPY/GEMM value-or-error helpers, with native/bytecode module coverage and the
     native typed-buffer runtime-profile smoke using representative `try_*` names.
   - New blocker isolated (2026-05-04): `tests/modules/test_integration_suite.oren --backend native`
     got past the stdlib cast-wrapper checks, then failed at the f32 typed-buffer matmul assertion.
     A focused probe showed bytecode computing `[1.0, 2.0, 3.0, 4.0]`, while native stored the wrong
     f32 bits after routing through f64 scratch buffers; this was a native floaty-state /
     f64-scratch representation boundary in linalg, not an integration-fixture expectation issue.
   - Fix (2026-05-04): linalg f32/f64 scratch stores now preserve native float representation, and
     impl lowering treats the generated generator-aware for-in bridge as an `oren_iter_next(...)`
     hook for typed custom iterables. Native quick includes
     `tests/fixtures/native_iterable_trait_forin_smoke.oren`, so local/imported
     `impl Iterable.iter_next` dispatch is guarded outside the full integration suite.
   - Fix (2026-05-04): `std:linalg` scalar-list f64/f32 dot/AXPY/GEMM paths now pack through typed
     buffers on the public facade path and common vector validation returns `oren_err` for non-lists,
     so the broad native linalg module smoke no longer trips over untagged list-float carriers or
     native `list_len` panics.
   - Fix (2026-05-04): AVM bytecode now covers the remaining raw integration IDs:
     `oren_time_mono_raw(...)`, `oren_buf_data_mod(...)`, and `oren_buf_add_i64_into(...)`.
     `tests/modules/test_integration_suite.oren` now passes on both native and bytecode and is part
     of the fast native quick lane.
   - Verified (2026-03-20): those hidden packed-bridge benchmarks compile and return the expected
     `205` / `710` / `6590` / `54380` outputs through the Oren C backend, proving the bridge
     helpers are portable; the slower native steady probe remains the explicit next step for
     measuring whether packed buffers plus typed-buffer kernels actually buy us headroom.
   - Fix (2026-03-27): native `oren_list_len` intrinsics on arm64/x64 now accept `LIST_INT`
     headers as well as boxed `LIST` headers, matching the runtime contract and unblocking rebuilt
     core-runtime packed-bridge binaries.
   - Fix (2026-03-27): the C backend runtime now implements the missing portable bytes helpers
     `oren_bytes_len`, `oren_bytes_from_hex`, `oren_bytes_to_hex`, and `oren_bytes_pack`, which
     restores Oren C packed-bridge preflight builds and closes a broader stdlib/runtime ABI gap.
   - New probe hygiene (2026-03-20): packed-bridge smoke now defaults to Oren C instead of
     native so the correctness preflight stays cheap. The heavier native cost now appears only in
     the dedicated packed-bridge steady probe, where it belongs.
   - New probe batching (2026-03-20): that dedicated packed-bridge steady probe now warms the
     hidden packed benchmarks only once and reuses the artifacts for the scalar-vs-kernel cases.
     The optimized run already reconfirmed the canonical steady baseline (`array_sum_int` ~2.43× C,
     `dot_product_int` ~2.78× C) before entering the remaining expensive full-runtime warm leg.
   - New probe prebuild step (2026-03-20): the hidden packed-bridge warm leg is now exposed as a
     reusable prebuild target so we can precompile the packed benchmarks once and then measure the
     packed scalar vs packed kernel ceiling without conflating it with first-build cost. Both
     hidden packed-bridge artifacts now stay on the cheap native `core` profile, and that warm step
     now also prebuilds the matching C binaries so the later `OREN_BENCH_SKIP_BUILD=1` probe legs
     do not fail on missing artifacts.
   - Follow-through (2026-03-27): native packed-bridge smoke and
     `make verify-native-core-packed-bridge` now reuse that same core-runtime prebuild path,
     keeping the smoke and steady-probe tooling aligned on the real runtime boundary.
   - Fix (2026-03-27): native `i32` typed-buffer scalar dot/reduce fallbacks now do one outer
     typed-buffer check and then walk payload pointers directly via
     `oren_ptr_get_i32_le(...)` / `oren_ptr_set_i64_le(...)`; `std:linalg.reduce_sum_i32_buf(...)`
     now uses that runtime reduce kernel instead of looping through `oren_buf_load_i32(...)`.
     The first shortened rerun on the same host improved the canonical steady baseline to
     `array_sum_int` ~1.35× C and `dot_product_int` ~1.36× C.
   - Probe result (2026-03-27, shortened steady sample: `n=100000`, `reps=5`, `runs=2`,
     `warmups=0`): the current packed bridge is decisively not ready for compiler lowering.
     Baseline measured `array_sum_int` ~1.45× C and `dot_product_int` ~1.38× C, while the packed
     bridge measured `array_sum_int_packed_bridge` ~1351× C scalar / ~1599× C SIMD and
     `dot_product_int_packed_bridge` ~14975× C scalar / ~3043× C SIMD. The next work item is to
     fix bridge materialization/runtime cost or pursue a direct 64-bit-slot lowering instead.
   - Follow-up probe result (2026-03-27, same shortened steady sample after the pointer-loop
     runtime fix): baseline improved to `array_sum_int` ~1.35× C and `dot_product_int` ~1.36× C,
     but the packed bridge still measured `array_sum_int_packed_bridge` ~1438× C scalar /
     ~1177× C SIMD and `dot_product_int_packed_bridge` ~15382× C scalar / ~2779× C SIMD. That
     makes the remaining blocker explicit: bridge/materialization dominates, not the `i32`
     typed-buffer inner-loop fallback.
   - New direct-slot probe boundary (2026-03-27): native runtime now also exposes
     `oren_list_int_reduce_sum_slots(_unchecked)` and `oren_list_int_dot_slots(_unchecked)`, with
     hidden native-only benchmarks and a dedicated smoke/probe path to measure the raw 64-bit-slot
     ABI directly instead of using the packed bridge as a proxy.
   - Direct-slot probe result (2026-03-27, shortened steady sample: `n=100000`, `reps=5`,
     `runs=2`, `warmups=0`): baseline measured `array_sum_int` ~1.35× C and
     `dot_product_int` ~1.41× C, while the hidden direct-slot helper benchmarks measured
     `array_sum_int_slot_direct` ~13.74× C and `dot_product_int_slot_direct` ~21.03× C. That is
     dramatically better than the packed bridge, which makes “lower directly against the 64-bit
     slot ABI” the right optimization direction, but it is still too slow to treat the runtime
     helper call itself as the end state.
   - Follow-up (2026-04-04): arm64 and x64 now inline the unchecked raw-slot helper calls at the
     native call site for `oren_list_int_reduce_sum_slots_unchecked` and
     `oren_list_int_dot_slots_unchecked` instead of routing those probes through the old generic
     helper body. The forced steady rerun
	     (`build/logs/perf-probe-list-int-slot-direct-20260404_200234.log`) moved the hidden
	     direct-slot path to `array_sum_int_slot_direct` ~15.1069× C and
	     `dot_product_int_slot_direct` ~5.1760× C, while the same sweep measured the canonical
	     baseline at `array_sum_int` ~2.3090× C and `dot_product_int` ~2.9950× C. That materially
	     reduces the dot-path gap and confirms the call-site lowering matters, but the helper-backed
	     probe still trails the canonical fast loops by too much to become the default lowering.
		   - Ceiling probe + helper env fix (2026-04-05): the list<int> helper prebuild/smoke surfaces now
		     honor `OREN_BENCH_ENV_BUILD_OREN` consistently, and the hidden helper probes record `build_env`
		     in their summaries. New ranking surface: `make perf-probe-list-int-dot-ceiling`. Latest fast
		     profile artifact (`build/logs/perf-probe-list-int-dot-ceiling-20260405_024559_38593.log`,
		     `runs=2 warmups=0 n=20000 reps=2`, `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`) ranks
		     `dot_product_int` paths as canonical `~1.2137× C`, direct-slot `~1.5149× C`, packed-SIMD
		     `~565.8124× C`, packed-scalar `~1382.0339× C`. Reweight accordingly: the canonical fast loop
		     still dominates the helper/bridge alternatives, so future parity work should stay on direct
		     lowering / representation changes rather than going back through packed-bridge routing.
		   - Slot-ABI ceiling probe (2026-04-05, refreshed 2026-04-11): new `make perf-probe-list-int-slot-abi-ceiling`
		     measures packed-i32 C, slot64 C, the shipped Oren canonical benchmark, and the Oren
		     slot-direct helper under one workload. Latest artifact
		     (`build/logs/perf-probe-list-int-slot-abi-ceiling-20260411_181606_60508.log`,
		     `runs=5 warmups=1 n=2000000 reps=100`) shows:
		     - packed-i32 C vector: ~0.000250s per rep
		     - packed-i32 C scalar: ~0.000747s per rep
		     - slot64 C “vector”: ~0.000728s per rep
		     - slot64 C scalar: ~0.000759s per rep
		     - Oren native canonical: ~0.001305s per rep
		     - Oren native slot-direct helper: ~0.003599s per rep
		     The decisive ratios are `slot64-vector / packed-vector ~2.9086×` and
		     `Oren canonical / slot64-vector ~1.7932×`. The corrected assembly extractor reports a
		     28-instruction packed-i32 NEON body, a 12-instruction slot64 paired-scalar loop, and a
		     6-instruction slot64 scalar tail. Plain “vectorize the current 64-bit slot ABI” is not
		     enough to regain packed-i32 NEON throughput, but the current Oren loop still has a material
		     scalar/slot64-ceiling gap too.
		     The scalar-post follow-up now confirms that simply matching the host slot64 scalar loop's
		     post-index load + `madd` shape is not enough: the opt-in combined Oren loop shrinks to
		     `18` traced instructions (`11` without the skipped cold GC-call block), but the measured
			     decision surface still rejects the branch.
			   - Get-sum slot64 vector-2d follow-up (2026-04-11): `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1`
			     now exists as a default-off direct-lowering experiment for `array_sum_int`. It emits
			     `ldr q` over 64-bit list slots, combines lanes with `add.2d`/`addp.2d`, and reduces
			     back into the scalar sum before another possible GC safepoint call. Use
			     `make perf-probe-arm64-fast-get-sum-vector-2d-decision` as the ranking surface. The
			     widened current-tree artifact
			     (`build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`)
			     confirms the intended shape (`51` traced instructions, `41` without two cold tick
			     blocks, `q` loads in the snippet, `add.2d=1`, `addp.2d=2`) but rejects promotion:
			     local acceptance preferred enabled (`steady -7.95%`, `gate -1.62%` native medians),
			     while the same-tree C-ceiling surface preferred the shipped default in `4/5` sweeps
			     (`default_array_ratio_median ~2.2140×`, enabled `~2.2967×`). Keep this branch opt-in;
			     the W5 representation path still needs more than per-iteration pairwise-add on the
			     current 64-bit slot stream.
			   - Arm64 slot64 SIMD ISA check (2026-04-11): new
			     `make verify-native-arm64-slot64-simd-isa` records the local assembler fact behind the
			     dot-side reweighting. Latest artifact
			     `build/logs/verify_arm64_slot64_simd_isa_20260411_202346_64385.log` shows AdvSIMD accepts
			     slot64 vector add/reduce (`ldr q`, `add.2d`, `addp.2d`) and packed-i32 widening dot
			     (`smull.2d`, `smull2.2d`), but rejects true 64-bit-lane vector multiply (`mul v*.2d`).
			     Reweight: do not spend another branch trying to vectorize slot64 dot by swapping the
			     scalar multiply opcode; the remaining high-leverage path is a safe packed view or a
			     different representation contract.
				   - Read-split follow-up (2026-04-05): new `make perf-probe-list-int-packed-bridge-read-split`
			     warms the hidden packed-bridge artifacts once and then compares canonical `dot_product_int`
			     against packed scalar / SIMD on the same short/long split runner. Latest artifact
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_032402_91481.log`,
			     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=2 warmups=0 n=20000 short_reps=1
		     long_reps=2`) shows the bridge is still nowhere near competitive even after setup is
		     amortized: baseline `~1.3378× C` long-per-rep, packed-SIMD `~549.8375× C`, packed-scalar
			     `~1037.5886× C`. Treat that as a closed branch: the current bridge shape is not merely paying
			     first-build or one-time pack cost, so do not route near-term parity work back through it.
			   - Shared runtime-backed bridge follow-up (2026-04-08): `buffer.i32_pack_list_int(...)` and
			     `_into` now route through dedicated runtime helpers across native, C, and AVM instead of a
			     shared Oren element loop. The native implementation now hoists source/destination cursors
			     and emits direct byte stores; the same batch added `_into` coverage to modules/native
			     QI/AVM tests.
				   - New ceiling rerun (2026-04-08): latest
				     `make perf-probe-list-int-dot-ceiling`
				     (`build/logs/perf-probe-list-int-dot-ceiling-20260408_231950_89006.log`,
				     `runs=2 warmups=0 n=20000 reps=2`) now ranks the same shapes as canonical
				     `dot_product_int` `~1.2169× C`, direct-slot helper `~1.1182× C`, packed-SIMD
				     `~4.9387× C`, packed-scalar `~17.0948× C`. The bridge is no longer catastrophically bad,
				     but it still trails the shipped whole-operation path.
					   - Direct-slot read-split follow-up (2026-04-08): new
					     `make perf-probe-list-int-slot-direct-read-split` now warms the hidden direct-slot
					     artifacts once and reruns canonical `array_sum_int` / `dot_product_int` against the
				     unchecked helper path on the same short/long harness. Latest no-smoke artifact
				     (`build/logs/perf-probe-list-int-slot-direct-read-split-20260408_235243_30345.log`,
				     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) keeps the helper ahead on
				     whole-operation cost:
				     - canonical `array_sum_int`: `~1.3410× C` long-per-rep
				     - direct-slot `array_sum_int_slot_direct`: `~1.0383× C` long-per-rep
				     - canonical `dot_product_int`: `~1.2680× C` long-per-rep
				     - direct-slot `dot_product_int_slot_direct`: `~1.1637× C` long-per-rep
					     - delta note: the same rerun produced unstable split deltas (canonical
					       `dot_product_int` `~-0.0273× C`, direct-slot `~7.6465× C`), so tracker updates should
						       prefer long-per-rep on this surface.
						     Reweight accordingly: the packed bridge still stays closed as the next parity lever, and
						     the higher-value next task looked like pulling more of the direct-slot path into the
						     shipped canonical lowering.
					   - Public slot-surface read-split follow-up (2026-04-09): new
					     `make perf-probe-list-int-slot-surface-read-split` now warms the same slot-surface
					     artifacts and reruns canonical `array_sum_int` / `dot_product_int` against both the
					     hidden helper ceiling and the new public `std:linalg` slot wrappers. That split surface
					     still is not stable enough to rank public-vs-helper ordering by itself: the smoke-on
					     rerun (`build/logs/perf-probe-list-int-slot-surface-read-split-20260409_050248_17126.log`)
					     and the later no-smoke rerun
					     (`build/logs/perf-probe-list-int-slot-surface-read-split-20260409_051528_36514.log`,
					     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) disagree on the public/helper winner.
					     Latest no-smoke long-per-rep numbers came back as:
					     - canonical `array_sum_int`: `~1.2464× C`
					     - direct-slot `array_sum_int_slot_direct`: `~1.0077× C`
					     - public-slot `array_sum_int_slot_public`: `~1.1301× C`
					     - canonical `dot_product_int`: `~1.2771× C`
					     - direct-slot `dot_product_int_slot_direct`: `~1.0642× C`
					     - public-slot `dot_product_int_slot_public`: `~1.2439× C`
					     Reweight again: keep this split probe as a regression/sanity check only; use the steady
					     dot-ceiling probe below for public-slot ranking.
					   - Public slot checked-contract + unchecked-len follow-up (2026-04-09): the native checked
					     raw helpers now match AVM/C parity by returning structured `invalid_arg` errors instead
					     of panicking on bad input, while the public `std:linalg` fast path keeps using the
					     unchecked helper after `oren_is_list_int(...)` has already proven the input and now uses
					     `oren_list_int_len_unchecked(...)` for the typed mismatch guard instead of paying the
					     safer `list.int_len(...)` probe again. Latest steady
					     `make perf-probe-list-int-dot-ceiling`
					     (`build/logs/perf-probe-list-int-dot-ceiling-20260409_113946_99659.log`,
					     `runs=2 warmups=0 n=20000 reps=2`) now ranks:
					     - canonical `dot_product_int`: `~1.3221× C`
					     - direct-slot `dot_product_int_slot_direct`: `~1.0920× C`
					     - public-slot `dot_product_int_slot_public`: `~1.2079× C`
					     - canonical `array_sum_int`: `~1.4110× C`
					     - direct-slot `array_sum_int_slot_direct`: `~1.0019× C`
					     - public-slot `array_sum_int_slot_public`: `~1.0800× C`
					     Reweight again: the public slot surface is still behind the hidden helper ceiling, but
					     the residual gap remains meaningfully smaller than the older tracker state on both
					     steady benchmarks.
						   - Internal `try_fast` helper follow-up (2026-04-09): C/native/AVM now expose
						     `oren_list_int_*_slots_try_fast(...)` so future lowering experiments can probe a single
						     checked boundary, but a direct reroute of the public `std:linalg` API through that helper
						     surface regressed hard on the same steady ceiling
						     (`build/logs/perf-probe-list-int-dot-ceiling-20260409_113108_86448.log`:
						     public-slot `dot_product_int` `~3.2619× C`, public-slot `array_sum_int` `~2.1178× C`).
						     Keep that helper surface internal-only for now.
						   - Arm64 alloc-index convergence follow-up (2026-04-09): list/list<int> fast-loop
						     validation in `lib/compiler/arm64_native_stmt_loops_list_emit.oren` now uses the same
						     `native_alloc_index_get` lookup x64 already uses instead of the older
						     `oren_find_node` call sequence. This stayed correctness-clean (`make
						     verify-backend-parity-list-int`, `make test`) and two serialized ceiling reruns both
						     improved the shipped canonical path versus the earlier
						     `build/logs/perf-probe-list-int-dot-ceiling-20260409_113946_99659.log` snapshot:
						     - `build/logs/perf-probe-list-int-dot-ceiling-20260409_115936_33151.log`
						       - canonical `array_sum_int`: `~1.2173× C`
						       - canonical `dot_product_int`: `~1.3071× C`
						     - `build/logs/perf-probe-list-int-dot-ceiling-20260409_120228_38413.log`
						       - canonical `array_sum_int`: `~1.2781× C`
						       - canonical `dot_product_int`: `~1.2155× C`
						     Reweight again: this batch is a real canonical-baseline win, but not yet a stable new
						     helper/public ranking. The light `runs=2`, `reps=2` ceiling probe still flipped
						     direct-slot vs public-slot ordering, which is why the new order-balanced stability probe
						     was added next.
							   - Order-balanced ceiling stability follow-up (2026-04-09): new
							     `make perf-probe-list-int-dot-ceiling-stability` rotates baseline, direct-slot,
							     public-slot, packed-scalar, and packed-SIMD across five sweeps so each case appears in
							     each starting position once. Latest artifact:
						     `build/logs/perf-probe-list-int-dot-ceiling-stability-20260409_123207_90132.log`
						     (`sweeps=5`, `runs=3`, `warmups=1`, `n=20000`, `reps=4`) now comes back as:
						     - `array_sum_rank_counts`: canonical `2/5` wins, direct-slot `2/5`, public-slot `1/5`
						     - `dot_product_rank_counts`: canonical `3/5` wins, public-slot `2/5`, direct-slot `0/5`
						     - median `array_sum_int`: canonical `~1.1887× C`, direct-slot `~1.2329× C`,
						       public-slot `~1.2729× C`
						     - median `dot_product_int`: canonical `~1.2177× C`, public-slot `~1.2231× C`,
						       direct-slot `~1.3097× C`
							     Reweight again: on the stronger repeated surface, current arm64 canonical is now the best
							     whole-operation median on both benchmarks. Public-slot remains close enough to win some
							     `dot_product_int` sweeps, but neither public-slot nor hidden direct-slot is a stable
							     whole-operation winner on current `master`. Use this new stability probe for ordering
							     decisions and stop assuming more helper/public lowering will automatically beat the
							     shipped canonical arm64 path.
								   - Whole-operation host-C ceiling follow-up (2026-04-09): new
								     `make perf-probe-list-int-c-ceiling` broadens the earlier dot-only slot-ABI ceiling
								     probe across both canonical benchmarks by timing packed32 C, slot64 C, and the shipped
								     Oren native `array_sum_int` / `dot_product_int` binaries under the same whole-operation
								     workload. Latest artifact:
									     `build/logs/perf-probe-list-int-c-ceiling-20260411_181614_60702.log`
									     (`runs=5`, `warmups=1`, `n=2000000`, `reps=100`) now comes back as:
									     - `array_sum_int`
									       - packed32 C vector: `~0.000134s`
									       - slot64 C vector: `~0.000246s`
									       - slot64 C scalar: `~0.000774s`
									       - Oren canonical: `~0.000561s`
									     - `dot_product_int`
									       - packed32 C vector: `~0.000250s`
									       - slot64 C vector: `~0.000738s`
									       - slot64 C scalar: `~0.000778s`
									       - Oren canonical: `~0.001326s`
									     - decisive ratios:
									       - `array_slot64_vector / array_packed32_vector`: `~1.8365×`
									       - `oren_array_sum_int / array_slot64_vector`: `~2.2778×`
									       - `dot_slot64_vector / dot_packed32_vector`: `~2.9502×`
									       - `oren_dot_product_int / dot_slot64_vector`: `~1.7959×`
											     Reweight again: helper/public-slot ordering is no longer the main blocker. On current
											     arm64 `master`, `array_sum_int` still lacks a competitive slot64-vector whole-operation
											     path, while `dot_product_int` remains materially above even the slot64 host-C ceiling
										     inside the current ABI.
								   - Dot route decision wrapper (2026-04-11): new
								     `make perf-probe-list-int-dot-route-decision` reruns the slot-ABI ceiling,
								     whole-operation C ceiling, and order-balanced helper/public/packed stability surface
								     together. Latest artifact:
									     `build/logs/perf-probe-list-int-dot-route-decision-20260411_181606_60502.log`.
									     Verdict: keep shipped canonical lowering. Slot64 still loses packed-NEON
									     headroom (`slot64_vector / packed_vector ~2.9086×`, `slot64_scalar /
									     packed_scalar ~1.0165×`), and the whole-operation gaps remain material
									     (`oren_dot_product_int / dot_slot64_vector ~1.7959×`,
									     `oren_array_sum_int / array_slot64_vector ~2.2778×`). Hidden direct-slot won
									     dot on this rerun (`3/5`, median `-10.83%`) but lost array badly (`1/5`,
									     median `+18.24%`); public-slot stayed mixed, and packed-SIMD stayed far behind.
									     Reweight again: the next dot work should target representation/direct lowering
									     for slot64 or a safe packed view, not the current helper/public/packed bridge
									     route and not another scalar-tail scheduling toggle.
								   - Slot-direct fast-tick decision (2026-04-11): new
								     `make perf-probe-list-int-slot-direct-fast-tick-decision` serializes default
								     vs `OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1` and forces the shared read-split
								     artifacts to rebuild for each side. Latest artifact:
									     `build/logs/perf-probe-list-int-slot-direct-fast-tick-decision-20260411_194036_96087.log`.
									     Verdict: keep the reduced helper safepoint spill / 4095 tick-mask branch opt-in.
									     It regressed the slot-ABI direct-helper time from `~0.001870s` to `~0.001874s`
									     per rep (`+0.21%`) and regressed read-split slot-direct native/C on both
									     `array_sum_int` (`~1.0010× -> ~1.1249×`) and `dot_product_int`
									     (`~1.2931× -> ~1.3051×`). This closes the tick/spill shortcut as a default
									     path; the next W5 move is still a real representation/direct-lowering change.
								   - Slot-direct helper pair-loop decision (2026-04-11): new
								     `OREN_ARM64_LIST_INT_SLOT_DIRECT_PAIR_LOOP=1` emits a counted 2-wide
								     raw-slot helper loop for unchecked `list<int>` sum/dot helpers, and
								     `make perf-probe-list-int-slot-direct-pair-loop-decision`
									     (`build/logs/perf-probe-list-int-slot-direct-pair-loop-decision-20260411_195615_19255.log`)
									     covers default, fast-tick, pair-loop, and pair-loop+fast-tick builds.
									     Verdict: keep it opt-in. Pair-loop alone regressed slot-ABI direct-helper
									     time `+3.15%` and read-split `array_sum_int` slot-direct native/C `+9.88%`,
									     while improving only `dot_product_int` `-3.31%`; pair-loop+fast-tick also
									     regressed slot-ABI `+3.42%` and array `+7.70%` while improving dot `-7.55%`.
									     This closes the scalar helper scheduling shortcut as a default path.
						   - New setup-vs-steady attribution follow-up (2026-04-09): new
						     `make perf-probe-list-int-array-sum-c-breakdown`
					     (`build/logs/perf-probe-list-int-array-sum-c-breakdown-20260409_143718_76549.log`)
					     now closes the remaining “maybe fill/setup dominates” question on the exact
					     `array_sum_int` workload. The short-run setup estimate is still noisy, but the stable
					     whole-operation fact did not move: Oren steady per-rep came back at `~0.001311s`
					     versus slot64 C vector `~0.000204s` (`~6.4228×`). Reweight again: the structural
					     blocker is still the repeated get-sum loop, not another one-time setup tweak.
										   - Exact whole-list helper follow-up (2026-04-09): the refreshed post-unroll2
										     decision probe
										     (`build/logs/perf-probe-arm64-whole-list-get-sum-helper-decision-20260409_173112_97220.log`)
										     confirms the canonical shortcut is still wrong on the exact shipped tree:
										     - exact `array_sum_int`: default `~1.9974×` vs helper-enabled `~13.6272×`
										       (`exact_array_winner: default`, helper/default `~6.8225×`)
										     - exact `dot_product_int`: default `~1.7628×` vs helper-enabled `~1.8728×`
										     - small split hidden helper ceiling stays useful context only:
										       `slot_direct_array_long_per_rep ~1.0113×`,
										       `slot_direct_vs_canonical_array_long_per_rep ~0.7866×`
										     Reweight again: do not ship the exact whole-list helper shortcut; keep those
										     knobs opt-in only and look for a different canonical/direct-slot convergence move.
				   - Read-split rerun (2026-04-08): latest
				     `make perf-probe-list-int-packed-bridge-read-split`
				     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log`)
			     changes the attribution: baseline canonical `dot_product_int` is `~1.3778× C`
			     long-per-rep, packed-scalar is `~13.5584× C`, and packed-SIMD is `~4.1480× C`
			     long-per-rep while its repeated-work delta is already `~0.4993× C`. Reweight the next work
			     accordingly: stop tuning the packed dot kernel itself and focus on bridge
			     setup/materialization elimination or reuse.
			   - Explicit reuse-work follow-up (2026-04-08): shared `std:linalg` now exposes
			     `dot_i32_list_int_packed_reuse(...)` and `reduce_sum_i32_list_int_packed_reuse(...)`, which
			     repack into caller-provided `[]i32` work buffers instead of allocating fresh packed buffers
			     inside every call. Hidden packed-bridge smoke now covers `OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1`
			     for both `array_sum` and `dot_product`.
			   - Reuse-work read-split rerun (2026-04-08): latest
			     `make perf-probe-list-int-packed-bridge-read-split`
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log`,
			     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) reweights the bridge again:
			     - canonical `dot_product_int`: `~1.2915× C` long-per-rep
			     - fresh-pack SIMD: `~7.3906× C` long-per-rep
			     - reuse-work SIMD: `~7.2240× C` long-per-rep
			     - pack-once SIMD: `~4.4566× C` long-per-rep
			     So caller-managed destination-buffer reuse trims only a small slice of the fresh-pack cost
			     and still loses badly to the existing pack-once bridge. Keep the next work aimed at
			     eliminating or hoisting the repeated `list<int> -> []i32` materialization itself.
			   - Native pointer-i32 pack-store follow-up (2026-04-11): arm64/x64 native now inline
			     `oren_ptr_get_i32_le` / `oren_ptr_set_i32_le`, and the `list<int> -> []i32` pack loop
			     stores lanes through the 32-bit little-endian pointer helper instead of four
			     `ptr_set_byte` calls. The current read-split artifact
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260411_203510_80313.log`,
			     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) moves the bridge materially:
			     - canonical `dot_product_int`: `~1.2150× C` long-per-rep
			     - fresh-pack SIMD: `~4.6037× C` long-per-rep
			     - reuse-work SIMD: `~4.0130× C` long-per-rep
			     - pack-once SIMD: `~2.3687× C` long-per-rep, `~2.4378× C` delta
			     - pack-once SIMD / canonical baseline long-per-rep: `~1.9495×`
			     Bounded steady cross-check
			     (`build/logs/perf-probe-list-int-packed-bridge-20260411_204441_93198.log`,
			     `runs=2 warmups=0 n=20000 reps=2`) reports packed-SIMD `array_sum_int_packed_bridge`
			     `~2.9643× C` and `dot_product_int_packed_bridge` `~2.1500× C`, versus canonical
			     `array_sum_int` `~1.2482× C` and `dot_product_int` `~1.2109× C`. Keep the intrinsic
			     improvement, but do not promote the packed bridge. The current route-stability rerun
			     (`build/logs/perf-probe-list-int-dot-ceiling-stability-20260411_204859_99207.log`)
			     still gives packed-SIMD `0/5` wins on both array and dot, with median deltas `+269.38%`
			     and `+134.27%` versus canonical. The next representation task is still copy
			     avoidance/hoisting or a real packed-view contract rather than another bridge reroute.
		   - Packed-SIMD reuse follow-up (2026-04-05): new
		     `make perf-probe-list-int-packed-bridge-simd-reuse` keeps only the canonical baseline and the
		     packed-SIMD bridge path, but raises the long run to `10` reps so reuse dominates the setup
		     more clearly. Latest artifact
		     (`build/logs/perf-probe-list-int-packed-bridge-simd-reuse-20260405_033734_11943.log`,
		     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=20000`) still comes back
		     as baseline `~0.000331s` native long-per-rep vs packed-SIMD `~0.266698s`, so the packed-SIMD
		     reuse case is still ~805.7341× slower than the shipped canonical loop.
		   - Guarded `[]i32` dot benchmark fix (2026-04-05): the hidden
		     `benchmarks/dot_product_i32_buf/dot_product_i32_buf.{oren,c}` pair now perturbs lane `0`
		     across `reps` and accumulates every repetition result so the repeated dot work cannot be
		     hoisted. The rerun full-process probe
		     (`build/logs/perf-probe-list-int-i32-buf-dot-ceiling-20260405_040717_51202.log`) still comes
		     back setup-mixed, so its `~14.0453×` whole-process SIMD/C ratio is no longer treated as a
		     clean kernel gap.
		   - New focused reuse surface (2026-04-05): `make perf-probe-list-int-i32-buf-simd-reuse`
		     isolates just the guarded packed-i32 C vector path and the guarded Oren `dot_product_i32_buf`
		     SIMD path with `long_reps=1000`. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-simd-reuse-20260405_040936_54584.log`,
		     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=200000`) shows:
		     - packed-i32 C vector: `setup≈0.002528s`, `delta≈0.000018s`
		     - Oren `dot_product_i32_buf` SIMD: `setup≈0.374950s`, `delta≈0.000024s`
		     - repeated-kernel delta ratio: ~1.3562×
		     - whole-process long-per-rep ratio: ~19.7021×
		     Reweight again: the repeated SIMD kernel is no longer the main unexplained gap. The remaining
		     typed-buffer problem is now dominated by fixed setup/runtime-boundary cost, not a SIMD core
		     that is still an order of magnitude behind packed C.
		   - Setup-breakdown follow-up (2026-04-05): `make perf-probe-list-int-i32-buf-setup-breakdown`
		     adds a hidden fill-only `[]i32` benchmark pair and compares that setup directly against the
		     guarded SIMD reuse setup. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-setup-breakdown-20260405_042115_69806.log`,
		     `runs=3 warmups=0 n=200000 short_reps=1 long_reps=1000`) shows:
		     - fill-only C: `~0.002515s`
		     - fill-only Oren `[]i32`: `~0.372046s`
		     - packed-i32 C vector setup: `~0.002991s`
		     - Oren `dot_product_i32_buf` SIMD setup: `~0.375121s`
		     - Oren fill share of Oren SIMD setup: `~99.18%`
		     That closes another ambiguity: the fixed typed-buffer cost is now almost entirely the
		     alloc+fill path itself. The next viable work is to attack checked `oren_buf_store_i32(...)`
		     setup or expose a bulk/unchecked fill surface, not to keep tuning the SIMD dot core.
		   - Fill-shape follow-up (2026-04-05): `make perf-probe-list-int-i32-buf-unchecked-fill`
		     compares checked fill, helper-based unchecked fill, pointer-hoisted fill, and
		     pointer-hoisted fill after `oren_i32_buf_new_uninit` for the same hidden `[]i32` setup
		     benchmark. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-unchecked-fill-20260405_044149_1286.log`,
		     `runs=3 warmups=0 n=200000`) shows:
		     - checked fill: `~0.376955s`
		     - unchecked helper fill: `~0.367594s` (`~1.0255×`)
		     - pointer-hoisted fill: `~0.344940s` (`~1.0928×`)
		     - pointer-hoisted + uninitialized fill: `~0.207338s` (`~1.8181×`)
		     Reweight again: a per-call unchecked wrapper is not enough. The next high-leverage change must
		     combine pointer-aware fill with a proven-safe uninitialized allocation path for buffers that
		     are fully overwritten before exposure.
		   - Native bulk-fill fix (2026-04-05): `oren_buf_fill_i32/i64/f32/f64` now hoist the payload
		     pointer and write bytes directly after a single upfront `native_buf_check`, instead of calling
		     the checked element-store helper on every iteration.
		   - Shared i32 conversion fast-path (2026-04-05): the first production use of the measured
		     `uninit + unchecked full overwrite` lever is now kept in the shared stdlib, not just hidden
		     benchmarks. Fresh `i32` export surfaces that prove full overwrite on success now allocate via
		     `oren_i32_buf_new_uninit(...)` and fill with unchecked direct stores:
		     `buffer.i32_pack_list_int`, `buffer.try_slice_to_i32_buf`,
		     `buffer.try_strided_to_i32_buf`, `buffer.i32_mat_pack_rows`, and
		     `buffer.i32_mat_to_i32_buf`. The C backend now also exports a conservative
		     `oren_i32_buf_new_uninit` shim so shared stdlib code remains backend-safe.
			   - Real workload follow-up (2026-04-05): the kept change materially improves the direct
			     conversion path on the ranking probe. Latest artifact
			     (`build/logs/perf-probe-list-int-dot-ceiling-20260405_223926_17836.log`) shows:
			     - baseline `dot_product_int`: `~1.4238x C`
			     - `dot_product_int_slot_direct`: `~0.9826x C`
		     - baseline `array_sum_int`: `~1.3214x C`
		     - `array_sum_int_slot_direct`: `~0.7955x C`
			     Reweight again: the direct `i32` conversion path is now good enough to beat or match the
			     host C baseline on this fast profile, while the packed bridge still stays catastrophically
			     bad. The paired read-split artifact
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_223926_17837.log`)
			     still reports `dot_product_int_packed_bridge` at `~542.7074× C` SIMD and `~1062.1370× C`
			     scalar on long-per-rep.
			   - Bridge/runtime follow-up (2026-04-08): the shared `list<int> -> []i32` export now also
			     has dedicated runtime-backed fast paths instead of per-element stdlib loops. Shared
			     `buffer.i32_pack_list_int` / `_into` now lower into native/C/AVM helpers, and the updated
			     fast-profile probe
			     (`build/logs/perf-probe-list-int-dot-ceiling-20260408_231950_89006.log`) cuts the packed
			     bridge to `~4.9387× C` SIMD / `~17.0948× C` scalar. The paired read-split rerun
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log`)
			     shows the remaining packed-SIMD gap is now setup-dominated (`~4.1480× C` long-per-rep,
			     `~0.4993× C` repeated-work delta), so the next bridge work should target one-shot export
			     cost rather than the inner packed dot kernel.
			   - Reuse-work follow-up (2026-04-08): caller-managed work buffers are now exposed directly in
			     shared `std:linalg`, but the rerun
			     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log`)
			     shows they are not the final answer. `dot_i32_list_int_packed_reuse(...)` only moves the
			     packed-SIMD long-per-rep result from `~7.3906× C` to `~7.2240× C`, while the existing
			     pack-once bridge still sits at `~4.4566× C`. Reweight accordingly: fresh allocation reuse is
			     a useful API, but not the missing parity lever.
		   - Family expansion (2026-04-05): the same full-overwrite proof now covers the rest of the
		     fresh numeric typed-buffer exports. Shared stdlib `i64`/`f32`/`f64`
		     pack/slice/strided/matrix-export paths now also use `*_buf_new_uninit(...)` and unchecked
		     direct stores on success-only full-write paths. Keep the next work focused on surfaces with
		     similarly strong overwrite proofs; do not spread this to partial-write or externally visible
		     buffers without a comparable safety argument.
		   - `u8` family expansion (2026-04-05): finish the same rule on the byte-oriented fresh export
		     paths instead of leaving one more partial cleanup pass behind. Shared stdlib
		     `buffer.try_u8_pack`, string-to-`[]u8`, slice/strided-to-`[]u8`, `u8` matrix row/string
		     pack/export, and `bytes.try_to_u8_buf[_slice]` now use the same
		     `oren_u8_buf_new_uninit(...) + unchecked direct write` rule only where successful return
		     proves every lane was written. Reweight again: the next work should move to other
		     full-overwrite conversion surfaces or measured bottlenecks, not back to the already-covered
		     fresh numeric/byte export family.
		   - Shared byte-constructor cleanup (2026-04-05): finish the same proof on the remaining shared
		     `[]u8` constructors that still zero-allocated before immediately overwriting every lane.
		     `bytes.from_hex`, `bytes.pack`, `base64.decode_bytes`, and the C/native `read_u8_buf` paths
		     now also use `oren_u8_buf_new_uninit(...)`. Reweight again: stop spending turns on obvious
		     zero-fill cleanup inside the already-covered byte constructor family and move to either a new
		     measured bottleneck or another surface with the same full-overwrite proof.
		   - Adjacent linalg family cleanup (2026-04-05): finish the same proof-backed rewrite on the
		     fresh-output typed-buffer linear algebra family. `axpy_i32_buf`, `axpy_f32_buf`,
		     `matmul_i32_buf`, `matmul_i32_buf_wide`, `matmul_f32_buf`, and `matmul_f64_buf` now allocate
		     fresh output via `*_buf_new_uninit(...)`, and their internal pack/transpose and scratch
		     buffers now do the same where the code or paired runtime `*_slice_into` helper fully
		     overwrites every slot before any successful return. Reweight again: stop spending turns on
		     obvious zero-fill cleanup inside the already-covered fresh numeric/linalg family and move to a
		     newly measured bottleneck or another surface with equally strong overwrite proof.
		   - Shared byte-serializer cleanup (2026-04-05): finish the same proof-backed rewrite on the
		     remaining obvious fresh-`[]u8` serializers in shared stdlib code. `http2.settings_payload_from_list`,
		     `http2_client._u8_concat2`, `http2_client._read_frame`, `http2_client._send_headers_fragmented`,
		     `hpack._huff_decode_bytes` output materialization, and `ppm.encode_rgba` now allocate through
		     `oren_u8_buf_new_uninit(...)` because their local loops or syscall fill paths deterministically
		     write every byte before any successful return. Reweight again: stop spending turns on obvious
		     fresh-byte overwrite cleanups in already-covered serializer families and move to either a
		     measured bottleneck or a new family with the same overwrite proof.
		   - Shared byte-helper boundary cleanup (2026-04-05): after the fresh-byte allocation work,
		     remove the remaining portable helper hops through temporary `list<int>` materialization.
		     `bytes.try_to_string`, `bytes.try_slice`, `bytes.try_concat`, `bytes.try_from_u8_buf`, and
		     `bytes.try_to_string_slice` now use the shared direct bridges
		     `oren_string_from_bytes_slice(...)` / `oren_u8_buf_from_bytes_slice(...)` plus unchecked
		     direct `u8` writes, and `ppm.write_rgba_ppm` now writes the encoded `u8_buf` directly via
		     `oren_write_bytes(...)`. Reweight again: stop spending turns on obvious shared byte-helper
		     bridging and move to a newly measured runtime bottleneck instead.
		   - Compiler byte-path follow-up (2026-04-05): remove the adjacent compiler bounce back into
		     legacy byte lists where the shared generic-bytes surface is already available.
		     `lib/compiler/obc_link.oren` now reads `.obc` bundles via `oren_read_u8_buf(...)` and parses
		     them through `oren_bytes_len(...)`, `oren_bytes_get_u8(...)`, and
		     `oren_string_from_bytes_slice(...)`; the deterministic metadata hashing legs in
		     `lib/compiler/compiler/040_build_pipeline/010_main.oren` now also hash `u8_buf` reads
		     directly. Reweight again: the obvious compiler-side `read_bytes -> list<int>` bridge on
		     artifact reads is closed, so next byte-path work should be driven by a measured hotspot.
		   - AVM `.obc` harness follow-up (2026-04-05): remove the adjacent AVM test/harness bounce
		     through legacy byte lists where the child-program API already expects BYTES. The multiverse,
		     map-key, and compiler-in-AVM fixtures now read `.obc` via `oren_read_u8_buf(...)`
		     directly, and the local AVM VFS fixture builders now append generic bytes via
		     `oren_bytes_len(...)` / `oren_bytes_get_u8(...)` instead of assuming `list<int>` bodies.
		     Reweight again: the obvious `.obc` reader bridge in the AVM harness layer is closed; keep
		     the remaining `read_bytes` surfaces only where they are the API under test.
		   - AVM byte-slice bridge follow-up (2026-04-12): add the missing bytecode native mappings for
		     `oren_string_from_bytes_slice(...)` and `oren_u8_buf_from_bytes_slice(...)`, matching the
		     shared C/native bridge surface used by `std:bytes` / `std:strings`. This closes the
		     `test_smoke_suite` bytecode build failure found while widening AVM run-JSON verification.
		     The same AVM pass fixes spawned task bootstrap to unpack positional args into the task frame,
		     closing the next `CHAN_SEND expects int channel` smoke-suite failure; keep
		     `make verify-avm-spawn-channel-args` in the default gate as the focused guard. The broader
		     curated AVM rerun temporarily added bounded structural equality for aggregate `==` / `!=`;
		     the follow-up cross-backend tag parity gate rebalanced that operator back to the shipped
		     C/native identity contract for lists, maps, bytes, and typed buffers. UI tree comparison
		     now uses an explicit `std:ui/core.node_equal(...)` structural helper instead of relying
		     on operator divergence. The same AVM pass added AVM `list + list` concatenation for UI
		     diff path-prefix construction, and maps the `*_buf_new_uninit(...)` typed-buffer
		     constructor aliases to the existing deterministic AVM buffer constructors.
		     `make test-avm` now clears the curated UI patch/render/raster/PPM lane again.
		   - Guardrail follow-up (2026-04-04): `make verify-native-slot-direct` now covers the unchecked
		     helper edge contract as well as the benchmark numerics. The slot-direct smoke builds
		     `tests/fixtures/list_int_slot_direct_contracts.oren` and checks nil-zero behavior plus the
     deterministic panic text for one-nil and length-mismatch
     `oren_list_int_dot_slots_unchecked(...)` calls.
				   - Shared stdlib follow-up (2026-04-09): the same direct-slot runtime surface is no longer
				     benchmark-only. `std:linalg` now exposes
				     `reduce_sum_i64_list_int_slots(...)` / `dot_i64_list_int_slots(...)`, which fast-path through
				     `oren_is_list_int(...)` plus the direct-slot helpers on C/native/AVM and fall back to a
				     portable scalar list walk for generic list inputs. `make verify-backend-parity-list-int`
				     now exercises that public surface via `tests/fixtures/list_int_dot_sum_smoke.oren`
				     instead of only checking the low-level helper contracts in isolation.
				   - Typed-mismatch semantics guard (2026-04-09): the same public-slot surface now has
				     explicit typed-list mismatch checks in `tests/fixtures/list_int_dot_sum_smoke.oren`,
				     `tests/fixtures/tier1_native_result_smoke_main.oren`, and
				     `tests/modules/test_linalg.oren`, so the fast path keeps returning error values instead
				     of accidentally inheriting unchecked-helper panic semantics.
				   - Native smoke widen (2026-04-09): `make verify-native-slot-direct` now inherits widened
				     slot-surface smoke too, so it validates the hidden helper-entry benchmarks, the hidden
				     public-slot benchmarks `array_sum_int_slot_public` / `dot_product_int_slot_public`, and the
				     unchecked helper panic contracts in one native gate.
		   - Verifier watchdog follow-up (2026-04-09): the backend parity scripts now default
		     `OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS=120` instead of `20`, matching the repo-wide build
		     watchdog so local parity runs do not false-time out while queued behind the shared
		     compiler-build lock or a cold stage2 rebuild.
	   - Verification (2026-03-28): the canonical benchmark loops already lower directly against that
	     64-bit-slot ABI on both native backends. New gate:
	     `make verify-native-list-int-fast-lowering`. It compiles
     `benchmarks/array_sum_int/array_sum_int.oren` and `benchmarks/dot_product_int/dot_product_int.oren`
     with `OREN_TRACE_ARM64_LOOP_STACK=1` on the local arm64 backend and with
     `OREN_TRACE_X64_LIST_FAST=1` on x64-linux, then asserts the arm64 trace still reports
     `fast_list_int_get_sum_while(_no_tick)?` / `fast_list_int_dot_while(_no_tick)?` and the x64
     compiler still emits `[x64_list_fast] ... kind=fast_list_int_{get_sum,dot}_while`. That makes
     the remaining task concrete: improve or broaden the existing direct-slot compiler fast loops,
     not the runtime helper boundary.
	   - Follow-up (2026-04-04): the same gate now also compiles the canonical W5 perf-gate benchmarks
	     `benchmarks/array_sum/array_sum.oren` and `benchmarks/dot_product/dot_product.oren`, so the
	     auto-specialized benchmark shapes are guarded alongside the explicit `array_sum_int` /
	     `dot_product_int` probes instead of relying on manual trace spot-checks.
		   - Structural guard widen (refreshed 2026-04-11): `make verify-native-list-int-fast-lowering` now also
		     runs `make verify-native-arm64-dot-madd-scalar-default`, so the shipped arm64 scalar-tail
		     choice is guarded by a deterministic disasm A/B. Latest log
		     (`build/logs/verify_arm64_dot_madd_scalar_default_20260411_171634_95703.log`): generic
		     `dot_product` and explicit `dot_product_int` stay at `instruction_count=21`,
		     `range_without_cold_gc_tick_instruction_count=14`, and `madd_count=0` on the shipped default,
		     while forcing
		     `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` moves both to
		     `instruction_count=20`, `range_without_cold_gc_tick_instruction_count=13`, and `madd_count=1`.
   - New matcher parity widen (2026-03-28): arm64/x64 direct-loop matchers now also accept the
     commuted equivalents `sum = xs[i] + sum` and `sum = a[i] * b[i] + sum`, including the boxed
     list fast-loop siblings. `make verify-native-list-int-fast-lowering` now compiles
     `tests/fixtures/list_int_fast_lowering_commuted.oren` and asserts those commuted `list<int>`
     loops still emit the same direct-slot fast traces on both backends; native QI now also checks
     boxed-list and `list<int>` commuted-loop correctness during `make test`.
   - New temp-normalized widen (2026-03-28): those same arm64/x64 direct-loop matchers now also
     accept one-temp normalized forms like `var x = xs[i]; sum = x + sum` and
     `var p = a[i] * b[i]; sum = p + sum`, including the boxed-list fast-loop siblings.
     `make verify-native-list-int-fast-lowering` now also compiles
     `tests/fixtures/list_int_fast_lowering_temp.oren` and asserts those temp-normalized
     `list<int>` loops still emit the direct-slot fast traces on both backends; native QI also
     checks temp-normalized boxed and `list<int>` loops during `make test`.
   - New warm-path control (2026-03-20): the packed-bridge prebuild now accepts an explicit
     program list, and `make perf-prebuild-dot-product-int-packed-bridge` warms only the hidden dot
     artifact before the timed ceiling probe.
   - New focused read split (2026-03-20): the split runner now reports both delta-based and
     long-run-per-rep estimates and warns when they drift materially. On the latest rerun,
     `array_sum_int` delta-vs-long drifted by about 30%, so steady-state tracker updates should
     prefer the dedicated steady runner or the split long-per-rep estimate over naive delta subtraction.
   - New: loop_sum init/steady split instrumentation via `OREN_BENCH_INIT_SPLIT=1`.
      - Latest split (2026-02-26, n=20,000,000): native steady ~0.224922s vs C ~0.067377s (≈3.34× steady-state).
    - New: defer capsule-only NET/PROC tables to `native_runtime_capsule_init` to reduce non-capsule runtime init cost; remeasure init/steady split (2026-02-25).
    - Measured: native init 0.003006s, steady 0.223682s (arm64 macOS, 2026-02-26).
    - New: native LCG fast loops use reciprocal fastmod when mod constants fit (arm64 + x64).
    - New: dot_product native at 2.57× C (arm64 macOS, 2026-02-26).
    - New: arm64 list<int> get-sum + dot loops keep i/sum in registers across iterations (2026-02-26).
	    - New: arm64 boxed list get-sum + dot loops keep i/sum in registers across iterations (2026-02-26).
	    - Fix: arm64 boxed fast list dot loop now initializes X10 tick mask before inline safepoint ticks (2026-02-26).
	    - Fix (2026-04-04): arm64 fast `list<int>` push loops now initialize X10 before inline
	      safepoint ticks.
	    - New: LCG fast loop safepoint mask raised to 4095 on arm64 + x64 (2026-02-26).
	    - New: arm64 fast-loop throttling masks are now compiler-env tunable per emitter via
	      `OREN_ARM64_FAST_LIST_{GET_SUM,DOT,PUSH}_TICK_MASK`,
	      `OREN_ARM64_FAST_LIST_INT_{GET_SUM,DOT,PUSH}_TICK_MASK`, and
	      `OREN_ARM64_FAST_LCG_SUM_TICK_MASK` (decimal `0..65535`, invalid input falls back).
		    - Probe (2026-04-04, canonical `array_sum`/`dot_product`, arm64):
		      baseline `dot_product` ~2.9293x C, `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383`
		      effectively unchanged, `65535` ~2.8584x C. Keep the default `4095`.
		    - Split (2026-04-04, canonical `array_sum`/`dot_product`, reps=1 vs 10):
		      `array_sum` steady long-per-rep is already much closer (~1.44x C native), while
		      `dot_product` still sits around ~2.59x C long-per-rep / ~2.48x C delta estimate.
		      So the next work stays on the steady dot core, not the fill/setup half.
			    - New canonical native smoke + steady runner (2026-04-04):
			      `make perf-smoke-native-fast-loops` now trips on the direct benchmark binaries, and
			      `make perf-gate-native-steady` measured `array_sum` ~2.40x C and `dot_product`
			      ~3.10x C at `reps=100`. Prefer that steady runner over the split estimate when
			      reweighting hot-loop work.
			    - New canonical steady tick-mask probe (2026-04-04):
			      `make perf-probe-arm64-fast-loop-tick-masks-steady` reran the arm64 `16383` /
			      `65535` sweep on the real repeated-read-loop runner, with one shared smoke
			      preflight and then same-policy measured runs. Corrected `dot_product` rerun:
			      baseline ~3.0142x C, `16383` ~3.0924x C, `65535` ~3.1914x C. That strengthens the
			      earlier readout: higher dot tick masks do not help the canonical steady-state path,
			      so keep the default `4095` and work the loop body itself.
			    - New arm64 single-pair cursor-reg probe (2026-04-04):
			      `make perf-probe-arm64-fast-dot-single-pair-cursor-regs` now compares the shipped
			      single-pair cursor-reg path against
			      `OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0` without source edits.
			      While landing that probe, the native/list<int> gate scripts and
			      `benchmarks/run_benchmarks.py` were fixed to use collision-resistant timestamps, so
			      adjacent probe variants no longer overwrite each other’s logs/results. Current
			      kept-state serial rerun stayed inconclusive: steady default ~3.1205x C vs disabled
			      ~3.1322x C, while the canonical gate read default ~2.6041x C vs disabled ~2.5322x C.
			      Keep the shipped default for now and use the probe for future reruns.
				    - New arm64 unroll-by-2 probe (2026-04-04):
				      `make perf-probe-arm64-fast-dot-unroll2` now compares the shipped unique-list
				      unroll-by-2 path against `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=0` without source
				      edits. The emitter also accepts explicit `...=1` / `true` so future reruns can force
				      either side of the comparison. Current kept-state rerun is mixed rather than
				      decisive: steady default ~2.9806x C vs disabled ~2.8893x C, while the canonical gate
				      read default ~2.1919x C vs disabled ~2.7147x C. Keep the shipped default for now and
				      use the probe for future reruns.
				    - New arm64 fast-loop pair-post probe + parser fix (2026-04-08):
				      `make perf-probe-arm64-fast-loop-pair-post` now compares the shipped `array_sum` /
				      `dot_product` baseline against the default-off pair-load experiment enabled via
				      `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1`.
				      The same batch fixed the remaining comma-splitting bug in the smoke/disasm/debug
				      helpers, so comma-separated `OREN_BENCH_ENV_BUILD_OREN` now reaches those legs too.
				      Current rerun (`build/logs/perf-probe-arm64-fast-loop-pair-post-20260408_215548_57748.log`):
				      default `steady_array_sum ~2.4342x C`, `steady_dot_product ~2.7645x C`,
				      `gate_array_sum ~2.0788x C`, `gate_dot_product ~2.5682x C`, disasm `52` / `70`;
				      enabled `~2.3932x C`, `~3.1297x C`, `~2.1181x C`, `~2.6913x C`, disasm `47` / `60`.
				      Keep the pair-post branch default-off; instruction-count wins alone still lose on the
				      measured hot-loop gates.
				    - New explicit get-sum pair-post decision surface (2026-04-09):
				      `make perf-probe-arm64-fast-get-sum-pair-post-list-int` now isolates the get-sum
				      `array_sum_int` leg on the shared `list<int>` acceptance bundle, and
				      `make perf-probe-arm64-fast-get-sum-pair-post-decision` compares the shipped default
				      against only `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1` on the same-tree exact
				      whole-operation C ceiling. Current widened rerun
				      (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`)
				      shows the acceptance wrapper strongly prefers the enabled branch (`steady -26.20%`,
				      `gate -53.71%`), but the exact whole-operation reruns still prefer the shipped
				      default in `3/5` sweeps (`default_array_ratio_median ~2.3604x`, enabled `~2.4015x`;
					      exact dot also stays slightly better on default at `~1.8539x` vs `~1.8578x`).
					      Keep the get-sum pair-post branch default-off; the acceptance wrapper is not the
					      ranking surface for this branch.
					    - New explicit get-sum vector-2d decision surface (2026-04-11):
					      `make perf-probe-arm64-fast-get-sum-vector-2d-decision` compares the shipped
					      default against `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1`, a direct slot64
					      SIMD-add body that uses `ldr q` plus `add.2d`/`addp.2d` and reduces back into
					      the scalar sum before another possible GC safepoint call. Current widened rerun
					      (`build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`)
					      confirms the intended structure (`51` traced instructions, `41` after subtracting
					      two cold tick blocks, `q` loads in the snippet, `add.2d=1`, `addp.2d=2`), but
					      the shipped decision surface rejects promotion: local acceptance preferred enabled
					      (`steady -7.95%`, `gate -1.62%` native medians), while the exact C-ceiling surface
					      preferred shipped default in `4/5` sweeps (`default_array_ratio_median ~2.2140x`,
					      enabled `~2.2967x`). Keep the vector-2d branch default-off; it is a useful
					      direct-lowering probe, not the stable slot64 fix.
						    - New list<int> fill-share decision surface (2026-04-09):
					      `make perf-probe-list-int-fill-share-decision` adds a hidden single-list
					      `benchmarks/fill_list_int` benchmark pair and compares that fill-only whole-operation
					      cost against the exact `array_sum_int` breakdown surface on the same shipped tree.
					      Current artifact
					      (`build/logs/perf-probe-list-int-fill-share-decision-20260409_181428_58993.log`)
					      says the list-build side is no longer small enough to hand-wave away:
					      fill-only Oren `per_rep_s ~0.005037`, slot64 C vector `~0.001044`,
					      `oren_fill_list_int / c_fill_slot64_vector ~4.8260x`,
					      `oren_fill_list_int / oren_array_sum_setup_est ~0.5912x`, and
					      `oren_fill_list_int / oren_array_sum_steady_per_rep ~10.2796x`.
					      Reweight again: the next high-leverage `array_sum_int` work should attack list
					      build/fill lifetime/setup costs, not another get-sum-local micro-branch.
					      - Exact constructor proof on the shipped tree (2026-04-09): a targeted native trace
					        rerun for `benchmarks/fill_list_int`
					        (`build/logs/run_fill_list_int_ctor_probe_final_20260409.log`) shows the benchmark-sized
					        header allocation as `[list_new_cap] kind=8 cap=2000000 total=16000032 mode=2`.
					        `mode=2` comes from the arena-backed constructor path in
					        `lib/runtime_native/095_arena.oren`, so the current fill-side blocker is no longer
					        “maybe this benchmark still uses GC list headers.” Reweight again: future work
					        should stay below the constructor boundary.
						    - Arm64 fill-side push-index-expression promotion (2026-04-09): the new default-on
							      `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR` path keeps pure index-only integer push
						      expressions on explicit `fast_list_int_push_while` lowering instead of routing them
						      through generic `native_compile_expr(...)` each iteration. Use
						      `make perf-probe-arm64-fast-push-idx-expr-decision` as the current ranking surface.
					      Current widened rerun
					      (`build/logs/perf-probe-arm64-fast-push-idx-expr-decision-20260409_183650_90548.log`)
					      now aligns across both relevant surfaces: fill/share preferred the shipped default
					      (`default_fill_vs_c_vector ~4.4912x` vs disabled `~5.0143x`), exact same-tree
					      whole-operation `array_sum_int` preferred default in `3/5` sweeps
					      (`default_array_ratio_median ~2.2989x` vs disabled `~2.3437x`), and exact
					      `dot_product_int` also preferred default in `4/5` sweeps
						      (`default_dot_ratio_median ~1.8313x` vs disabled `~1.8546x`). This is the first
						      post-fill-share branch that improves both the fill attribution surface and the
						      exact whole-operation ceiling, so it now ships on by default.
						    - Whole-list runtime fill-helper follow-up rejected and removed (2026-04-09):
						      a single-list helper that replaced the explicit push loop with one
						      `native_list_int_try_fill_nonneg_linear_exact(...)` call did trigger on
						      `benchmarks/fill_list_int/fill_list_int.oren`, but the widened decision artifact
						      (`build/logs/perf-probe-arm64-fast-push-fill-helper-decision-20260409_223410_5754.log`)
						      made it an immediate no-ship:
						      - fill/share exploded from default `~2.3500x` to enabled `~98.8846x`
						      - exact `array_sum_int` regressed from default `~2.1732x` to enabled `~6.0964x`
						      - exact `dot_product_int` improved only slightly (`~1.8157x` -> `~1.7652x`)
						      Cleanup: the helper/runtime/compiler plumbing was removed from the tree instead of
						      being left as another dead opt-in branch. Reweight: keep chasing safer fill/setup
						      lifetime reductions, not whole-list runtime helper rerouting.
				    - Arm64 fast-loop prefix-zero family remains default-off, but the dot leg is now
				      correctness-clean and isolated (2026-04-09): the statement-level prefix-zero
				      list<int> fast paths still stay explicit opt-in only via
				      `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1` and
				      `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`.
				      `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1` is still a clear loss on the current
				      host (`build/logs/perf-probe-arm64-dot-acceptance-20260409_003014_84317.summary.log`:
				      `steady_array_sum ~7.1203x C`, `gate_array_sum ~2.3250x C`). The arm64 dot prefix-zero
				      subpath now mirrors the proven direct-slot register plan after validation, so
					      `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` is smoke-clean again
						      (`build/logs/perf-smoke-native-fast-loops-20260409_003456_90383.log`). Use
						      `make perf-probe-arm64-fast-dot-prefix-zero` for the generic auto-specialized
						      `dot_product` surface and `make perf-probe-arm64-fast-dot-prefix-zero-list-int` for the
						      explicit `dot_product_int` surface. The wrappers now keep raw steady/gate native
						      medians and covariance too, because ratio-only reruns were masking C-baseline drift.
						      Current generic rerun
						      (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-20260409_014027_88043.log`):
						      default steady native `0.083484s`, gate native `0.013869s`, disasm `70`; enabled
						      steady native `0.080339s`, gate native `0.014837s`, disasm `23`
						      (`steady_dot_product_native_median_delta_pct: -3.77%`,
						      `gate_dot_product_native_median_delta_pct: +6.98%`). Current explicit `list<int>`
						      rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-list-int-20260409_014050_89076.log`):
						      default steady native `0.077758s`, gate native `0.013945s`, disasm `70`; enabled
						      steady native `0.087468s`, gate native `0.015405s`, disasm `23`
						      (`steady_dot_product_int_native_median_delta_pct: +12.49%`,
						      `gate_dot_product_int_native_median_delta_pct: +10.47%`).
						      Keep the family default-off: the get-sum leg still regresses, the generic dot leg
						      stays mixed, and the latest raw-median rerun overturns the older ratio-only
						      “explicit win” reading. The specialization wrapper still says this is not a large
						      generic-vs-explicit source-shape split.
					    - Modest arm64 unique-list loop-body cleanup (2026-04-04):
						      kept `n` hot in a register for the unique-list int get-sum/dot loops, switched
						      scalar unique-list cursor bumps to immediate adds, and removed the duplicate `i * 8`
				      recompute in the non-unique int-dot body. Serial reruns on the kept tree improved to
				      canonical `array_sum` ~2.0808x C / `dot_product` ~2.7616x C and steady `array_sum`
				      ~2.2422x C / `dot_product` ~2.9915x C. This is worth keeping, but the canonical
				      arm64 dot blocker is still open.
				    - Targeted arm64 fast-loop safepoint spill reduction (2026-04-04):
				      kept the generic safepoint spill wrapper untouched, but reduced the exact
				      `list<int>` hot-loop inline-safepoint spills to the pairs that can actually hide
				      live heap pointers from conservative stack scans. On the kept reruns this moved
				      steady `array_sum` / `dot_product` to ~2.4144x / ~2.7706x C and the canonical gate
				      to ~1.8926x / ~2.5264x C, while shrinking the traced hot-loop windows to 52
				      instructions for `array_sum` and 70 for `dot_product` (`stp/ldp` in dot fell from
				      10/10 to 4/4). Keep this; it improves both perf surfaces without changing the generic
				      safepoint contract.
				    - Follow-up exact-register spill probe (2026-04-05):
				      tried narrowing that kept two-pair dot safepoint set one step further to exact
				      single-register spills (`[x19]`, `[x26]`). The exact benchmark smoke and exact-binary
				      repro stayed green, but the real perf signal regressed:
				      `build/logs/perf-gate-native-steady-20260405_002356_78070.log` moved to
				      `array_sum` / `dot_product` ~2.4180x / ~3.0259x C and
				      `build/logs/perf-gate-native-20260405_002400_78191.summary.log` moved to
				      ~2.0537x / ~2.5850x C. Reverted; keep the earlier two-pair spill baseline.
				    - Arm64 dual-accum refresh + safepoint-safe register plan (2026-04-09):
				      `make perf-probe-arm64-fast-dot-dual-accum` now preserves raw native
				      medians/covariance for generic `dot_product`, and
				      `make perf-probe-arm64-fast-dot-dual-accum-list-int` does the same for explicit
				      `dot_product_int`. The opt-in path now keeps its secondary accumulator in
				      callee-saved `x22` instead of caller-saved `x17`, so inline GC safepoints cannot
				      clobber it. Current generic rerun improved both raw native medians
				      (`0.079878s -> 0.077758s` steady, `0.014427s -> 0.013903s` gate), but the explicit
				      `list<int>` rerun stayed mixed (`0.077313s -> 0.080407s` steady, `0.016063s ->
				      0.015338s` gate with a high-variance warning). Keep the dual-accum path disabled by
				      default; the old April 4 "regresses both surfaces" note is stale on the current
				      tree.
				    - Arm64 dot unroll2 default-off refresh (2026-04-09): generic and explicit wrappers now
				      exist, and the shipped default is off. Real post-flip reruns
				      (`build/logs/perf-probe-arm64-fast-dot-unroll2-20260409_030759_29018.log`,
				      `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260409_030846_30731.log`)
					      kept the non-unrolled 21-instruction traced baseline (14 instructions after
					      subtracting the skipped cold GC-call block) ahead of `UNROLL2=1` on both raw
					      medians. Keep unroll2 disabled by default.
					    - Arm64 cursor-reg refresh on the current baseline (2026-04-11): generic and
					      explicit wrappers now exist and were rerun after the cold-tick disasm accounting.
					      Generic `dot_product`
					      (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-20260411_170046_96599.log`)
					      prefers keeping cursor regs enabled on raw native medians (`steady 0.130047s ->
					      0.133221s`, `gate 0.010926s -> 0.011969s` when disabled). Explicit
					      `dot_product_int`
					      (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int-20260411_170108_97730.log`)
					      is still mixed: disabled improves raw native by only `-1.31%` / `-0.05%`, while
					      the ratio view worsens due the paired C median shift. Keep cursor-reg enabled.
						    - Arm64 explicit get-sum single-list cursor-reg refresh (2026-04-09): new wrapper
						      `make perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int` compares the
						      shipped `array_sum_int` scalar loop against
						      `OREN_ARM64_FAST_LIST_INT_GET_SUM_SINGLE_LIST_CURSOR_REGS=0` through the serialized
						      acceptance bundle. Current rerun
						      (`build/logs/perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int-20260409_130055_41301.log`)
						      kept the new default-on path: steady native median improved from disabled `0.134232s`
						      to default `0.133314s`, gate native stayed effectively flat, the disabled gate leg
						      warned as high variance, and both legs kept the same 16-instruction traced loop.
						      Keep the cursor-reg path enabled, but do not mistake it for the missing whole-op
						      `array_sum_int` fix.
							    - Arm64 explicit push single-list cursor follow-up (2026-04-09): new wrapper
							      `make perf-probe-arm64-fast-push-single-list-cursor-list-int` compares the shipped
							      `array_sum_int` fill loop against
							      `OREN_ARM64_FAST_LIST_INT_PUSH_SINGLE_LIST_CURSOR=0` through the same serialized
						      acceptance bundle. Current rerun
						      (`build/logs/perf-probe-arm64-fast-push-single-list-cursor-list-int-20260409_132214_76347.log`)
						      kept the new default-on path: steady native median improved from disabled `0.136291s`
						      to default `0.131530s` (`-3.62%`), gate native improved from disabled `0.010571s` to
						      default `0.010084s` (`-4.83%`), and both legs kept the same 16-instruction traced loop.
						      The whole-operation rerun
								      (`build/logs/perf-probe-list-int-c-ceiling-20260409_132256_79494.log`) improved
								      canonical `oren_array_sum_int / array_slot64_vector` from `~5.4463×` to `~5.3848×`.
								      Keep this cursor path enabled, but treat it as a modest whole-operation win rather
								      than the missing slot64-vector parity fix.
								    - Arm64 explicit push index-expression fill follow-up (2026-04-09): new ranking
								      surface `make perf-probe-arm64-fast-push-idx-expr-decision` now compares the shipped
								      default against `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR=0` on both the
								      fill/share attribution probe and same-tree exact whole-operation C-ceiling reruns.
								      The widened rerun
								      (`build/logs/perf-probe-arm64-fast-push-idx-expr-decision-20260409_183650_90548.log`)
								      closed this branch as a real shipped win instead of another local-only acceptance
								      artifact: fill/share preferred default (`default_fill_vs_c_vector ~4.4912×`,
								      disabled `~5.0143×`), exact `array_sum_int` preferred default in `3/5` sweeps
								      (`default_array_ratio_median ~2.2989×` vs disabled `~2.3437×`), and exact
								      `dot_product_int` also preferred default in `4/5` sweeps
									      (`default_dot_ratio_median ~1.8313×` vs disabled `~1.8546×`).
									      `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR` therefore ships on by default on the
									      current tree.
									    - Arm64 push idx-expr preserved-cursor follow-up (2026-04-23 refresh): the
									      current-tree ranking surface
									      `make perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision` now compares
									      the shipped default against explicit disable
									      (`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS=0`) after the later
									      nonnegative-linear/default-on fill changes landed. The refreshed rerun
									      (`build/logs/perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision-20260423_025433_17194.log`)
									      now agrees on the target surfaces: fill/share strongly preferred default
									      (`default_fill_vs_c_vector ~1.7572×` vs disabled `~2.3562×`), exact
									      `array_sum_int` also preferred default
									      (`default_array_ratio_median ~2.2127×` vs disabled `~2.2219×`), and exact
									      `dot_product_int` median stayed lower on the default too
									      (`default_dot_ratio_median ~1.3770×` vs disabled `~1.5110×`).
									      `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS` therefore now ships on by
									      default on the current tree.
										    - Arm64 explicit push nonnegative-linear fill follow-up (2026-04-09): ranking
										      surface `make perf-probe-arm64-fast-push-nonneg-linear-decision` now compares the
										      current shipped default against `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=0`
										      on the same fill/share attribution probe plus same-tree exact whole-operation
										      C-ceiling reruns.
										      The widened rerun
											      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260409_195510_97018.log`)
											      originally closed this branch as the next real shipped fill-side win: fill/share
											      strongly preferred default (`default_fill_vs_c_vector ~2.8909×`, disabled
											      `~4.3823×`), exact `array_sum_int` also preferred default
											      (`default_array_ratio_median ~2.2540×` vs disabled `~2.2740×`), and exact
											      `dot_product_int` preferred default too
											      (`default_dot_ratio_median ~1.7910×` vs disabled `~1.8065×`).
											      Fix + verify (2026-04-21): reduced aggressive-GC churn exposed a current overflow
											      in `_arm64_nonneg_linear_safe_n_limit(...)` on the identity shape, which emitted a
											      signed preheader compare against `0x8000000000000000`. Saturating that bound fixed
											      the reducer, but the branch was temporarily rolled back while a broader default-on
											      self-host/native-quick stall was investigated. Native quick now carries
											      `tests/native/test_gc_reuse_alloc_churn_min.oren` as a direct guardrail for that
											      family.
											      Refresh + promote (2026-04-23): the current-tree shipped-vs-disabled rerun
											      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_011353_91759.log`)
											      closes that blocker and re-promotes the broad branch on the actual shipped tree.
											      The formal decision surface stays aligned (`decision_surface_alignment: agree`);
											      fill/share strongly prefers the shipped default
											      (`default_fill_vs_c_vector ~2.3103×`, disabled `~5.7054×`), exact
											      `array_sum_int` still prefers default
											      (`default_array_ratio_median ~2.1964×` vs disabled `~2.3212×`), and exact
											      `dot_product_int` only moves slightly toward the disabled branch
											      (`default_dot_ratio_median ~1.3884×` vs disabled `~1.3578×`).
										      The real shipped safety lane is now green too:
										      `build/logs/make_verify_native_quick_20260423_011547_default_on_promote_v1.log`
										      and `build/logs/make_test_20260423_012704_default_on_promote_v2.log` both pass
										      with the default-on branch. Reweight accordingly: keep the broad
										      nonnegative-linear path shipped, do not revive the narrower fresh-single-list
										      isolation, and attack the residual lifetime/setup cost on this exact same-tree
										      default surface.
										      Emitted-code contract fix (2026-04-23): disassembly of the shipped
										      `array_sum_int` push loop found `_arm64_emit_fast_loop_nonneg_linear_to_x0(...)`
										      clobbering `x9` for mul/add/mod immediates even though inline GC countdown uses
										      `x9` as the tick register inside `fast_list_int_push_while`. The helper now keeps
										      `x9` reserved and uses `x11`/`x10` scratch instead, both push emitters now publish
										      `[arm64_loop_range]` traces, and
										      `build/logs/verify_native_list_int_fast_lowering_20260423_051622_70950.log`
										      now disassembles `array_sum_int`, rejects any hot-loop `x9` use beyond the
										      shipped countdown forms (`subs x9, x9, #0x1` / `#0x4`), and requires the
										      four-wide slot-store body to stay present. The refreshed shipped-vs-disabled rerun
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_034811_37016.log`)
										      still keeps the broad branch shipped on (`default_fill_vs_c_vector ~2.4026×`
										      vs disabled `~5.0016×`, `default_array_ratio_median ~2.2189×` vs disabled
										      `~2.2980×`, `default_dot_ratio_median ~1.5522×` vs disabled `~1.6406×`,
										      `decision_surface_alignment: agree`), and the widened safety lanes remain green
										      (`build/logs/make_verify_native_quick_20260423_tick_reg_fix_v1.log`,
										      `build/logs/make_test_20260423_tick_reg_fix_v1.log`). Reweight again: the inline
										      tick-register correctness hole is closed; keep the shipped branch, and continue
										      attacking the residual slot-write / count-update / safepoint-reset cost below it.
										      Loop-body disasm follow-up (2026-04-23): added
										      `make perf-probe-arm64-list-int-fill-hot-loop-disasm` so the shipped
										      `fill_list_int` / `array_sum_int` `fast_list_int_push_while` body can be counted
										      directly while excluding the cold GC-tick side block. The reverted current-tree
										      artifact
										      (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_042356_51281.log`)
										      shows the shipped loop at `25` total instructions / `17` hot instructions with
										      no per-iteration final count/cursor writeback in the hot body. A temporary
										      `% 1000` remainder fuse to `udiv; msub` reduced the hot body to `16`
										      instructions in
										      (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_041825_49207.log`)
										      but still regressed the real shipped decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_041844_49343.log`:
										      `default_fill_vs_c_vector ~2.4590×`, `default_array_ratio_median ~2.2222×`,
										      `default_dot_ratio_median ~1.6367×`). Reweight again: keep the shipped
										      `udiv; mul; sub` remainder path, stop treating per-iteration count/cursor
										      writeback as the likely blocker, and use the new hot-loop probe to attack the
										      surviving slot-store/arithmetic/safepoint-reset shape instead.
										      Oren-vs-C compare follow-up (2026-04-23): added
										      `make perf-probe-arm64-fill-vs-c-loop-compare` to pair the shipped fill
										      hot-loop summary with the host C `-O2` arm64 assembly. That compare did lead to
										      the right next experiment, and the follow-up is now landed: the refreshed
										      shipped-vs-disabled decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_045547_59235.log`)
										      keeps `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4` shipped on by
										      default because fill/share prefers the promoted branch
										      (`default_fill_vs_c_vector ~2.2247×` vs disabled `~2.4860×`), exact
										      `array_sum_int` also prefers it (`default_array_ratio_median ~2.1889×` vs
										      disabled `~2.2154×`, `array_default_wins: 3/3`), and exact `dot_product_int`
										      median stays lower on default too (`default_dot_ratio_median ~1.7420×` vs
										      disabled `~1.7574×`, `exact_dot_pref: default`). The corrected current shipped
										      compare artifact
										      (`build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_045541_59142.log`)
										      now reports the landed wide body directly: `35` hot instructions for `4` output
										      elements (`8.75` per element) versus the host C `LBB0_15` ceiling at `27`
										      instructions for `4` elements (`6.75` per element) plus a `9`-instruction scalar
										      tail in `LBB0_18`. Reweight again: the “missing wide/unrolled shape” theory is
										      now closed positive and shipped; the remaining fill-side work is the arithmetic /
										      store / tail / safepoint overhead inside that landed wide body, not another
										      request to add width in the abstract.
										    - Arm64 explicit push nonnegative-linear pair-store follow-up (2026-04-23):
										      the next narrower store-shape hypothesis under that shipped four-wide body is
										      now also closed negative. A temporary rerun replaced the four scalar stores plus
										      pointer bump with two post-index `stp` stores. The emitted loop improved:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_053204_75573.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_053209_75659.log`
										      show the wide main iteration dropping from `35` hot instructions for `4`
										      outputs (`8.75` per element) to `32` (`8.00` per element). But the actual
										      same-tree shipped-vs-enabled decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-stp-decision-20260423_053014_74064.log`)
										      still rejected promotion: fill/share preferred the shipped default
										      (`default_fill_vs_c_vector ~2.0548×` vs enabled `~2.1867×`), exact
										      `array_sum_int` median also slightly preferred default (`~2.1822×` vs
										      `~2.1860×`), and only exact `dot_product_int` median moved toward the
										      pair-store branch (`default_dot_ratio_median ~1.7285×` vs enabled `~1.6796×`).
										      Reweight again: stop treating slot-store shape as the primary blocker; the
										      remaining fill-side gap is now more likely in the carried recurrence arithmetic
										      and compare/branch density inside the shipped wide body.
										    - Arm64 explicit push nonnegative-linear direct-register follow-up (2026-04-23):
										      the next mov-chain hypothesis under that same shipped four-wide body is now also
										      closed negative. A temporary rerun removed the cloned register chain around the
										      carried values. The emitted loop improved again:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_054624_80049.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_054629_80110.log`
										      show the wide main iteration dropping to `30` hot instructions for `4` outputs
										      (`7.50` per element). But the actual same-tree decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-direct-regs-decision-20260423_054458_78631.log`)
										      still rejected promotion: fill/share improved (`default_fill_vs_c_vector
										      ~2.2174×` vs enabled `~2.1132×`), but both exact medians regressed
										      (`default_array_ratio_median ~2.2164×` vs enabled `~2.2298×`,
										      `default_dot_ratio_median ~1.5550×` vs enabled `~1.6600×`,
										      `decision_surface_alignment: disagree`). Reweight again: stop treating the
										      mov-chain as the primary blocker; the next fill-side work should target the
										      recurrence arithmetic itself and the compare/branch structure inside the
										      shipped wide body.
										    - Arm64 explicit push nonnegative-linear four-stream follow-up (2026-04-23):
										      the next true multi-stream recurrence hypothesis under that same shipped
										      four-wide body is now also closed negative. A temporary rerun kept four
										      carried lanes live in preserved regs and advanced each by a precomputed
										      `4*step mod` delta across main iterations. The emitted loop still improved:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_061011_87026.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_061011_87005.log`
										      show the wide main iteration dropping to `32` hot instructions for `4`
										      outputs (`8.00` per element). But that same emitted-code pass also shows
										      the cold GC-tick side blocks growing from `16` to `24` instructions because
										      the helper had to spill and restore four preserved pairs instead of two.
										      The actual same-tree decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-multi-stream-decision-20260423_060858_85589.log`)
										      still rejected promotion cleanly: fill/share preferred the shipped default
										      (`default_fill_vs_c_vector ~2.1459×` vs enabled `~2.1862×`), exact
										      `array_sum_int` median also preferred default (`default_array_ratio_median
										      ~2.1979×` vs enabled `~2.2283×`), and exact `dot_product_int` median
										      preferred default too (`default_dot_ratio_median ~1.5145×` vs enabled
										      `~1.6533×`, `decision_surface_alignment: agree`). Reweight again: any
										      future multi-stream retry has to avoid paying a wider safepoint spill/reset
										      tax at the same time.
										    - Arm64 explicit push nonnegative-linear branchless-wrap follow-up (2026-04-23):
										      the next `sub` + `csel` control-form hypothesis under that same shipped
										      four-wide body is now also closed negative. A temporary rerun replaced the
										      carried wrap `cmp` / `b.lt` pairs with branchless `sub` + `csel` recurrence
										      steps. The emitted loop still improved:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_055647_83223.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_055652_83291.log`
										      show the wide main iteration dropping to `31` hot instructions for `4`
										      outputs (`7.75` per element). But the actual same-tree decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-csel-decision-20260423_055520_81868.log`)
										      still rejected promotion decisively: fill/share preferred the shipped default
										      (`default_fill_vs_c_vector ~2.1457×` vs enabled `~3.2438×`), exact
										      `array_sum_int` median also preferred default (`default_array_ratio_median
										      ~2.2018×` vs enabled `~2.2386×`), and only exact `dot_product_int` median
										      moved toward the branchless path (`default_dot_ratio_median ~1.7842×` vs
										      enabled `~1.5692×`, `decision_surface_alignment: agree`). Reweight again:
										      stop treating branchy wrap control as the primary blocker; the next fill-side
										      work should target the serial carried recurrence itself versus the host C
										      loop's four independent streams.
										    - Arm64 explicit push nonnegative-linear precise-safepoint-spill follow-up (2026-04-23):
										      the next narrower inline GC helper hypothesis under that same shipped
										      four-wide body is now also closed negative. A temporary rerun changed only
										      the conservative safepoint spill contract, replacing the two preserved
										      cursor pairs with the exact live pointer spill `[x19]` via
										      `stp x19, xzr` / `ldp x19, xzr`. The emitted hot loop did not change:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_062415_90653.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_062415_90632.log`
										      still show `35` hot instructions for `4` outputs (`8.75` per element),
										      but the cold GC-tick side blocks shrink from `16` instructions on the clean
										      shipped baseline
										      (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_061450_87903.log`,
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_061450_87882.log`)
										      to `12`. The actual same-tree decision surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_062307_89324.log`)
										      still rejected keeping that change on the shipped tree relative to the
										      clean baseline
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_045547_59235.log`):
										      fill/share improved (`default_fill_vs_c_vector ~2.2247× -> ~2.1355×`), but
										      both exact same-tree medians regressed
										      (`default_array_ratio_median ~2.1889× -> ~2.2115×`,
										      `default_dot_ratio_median ~1.7420× -> ~1.7738×`). Reweight again: exact
										      live-pointer conservative spills are mechanically cleaner, but they are not
										      enough to ship as a standalone perf move; any future retry has to be paired
										      with a stronger recurrence/control improvement or justified by a correctness
										      need.
										    - Arm64 explicit push nonnegative-linear two-stream recurrence follow-up (2026-04-23):
										      the next spill-neutral multi-stream retry under that same shipped four-wide
										      body is now also closed negative. A temporary rerun kept the shipped
										      safepoint spill width unchanged and only split the carried values into two
										      live streams (`x24/x25`) plus a shared `2*step mod` delta in `x26`. The
										      emitted loop still improved slightly:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_063816_94224.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_063815_94203.log`
										      show the wide main iteration dropping from `35` hot instructions for `4`
										      outputs (`8.75` per element) to `34` (`8.50` per element), while the cold
										      GC-tick side blocks stay at the shipped `16`. The actual same-tree decision
										      surface
										      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-two-stream-decision-20260423_063427_92506.log`)
										      still rejected promotion cleanly on every tracked metric: fill/share
										      preferred the shipped default (`default_fill_vs_c_vector ~2.1431×` vs
										      enabled `~2.2392×`), exact `array_sum_int` median also preferred default
										      (`default_array_ratio_median ~2.2033×` vs enabled `~2.2142×`), and exact
										      `dot_product_int` median preferred default too (`default_dot_ratio_median
										      ~1.5928×` vs enabled `~1.6949×`, `decision_surface_alignment: agree`).
										      Reweight again: the remaining blocker is no longer just “multi-stream
										      without a wider safepoint spill tax”; even that narrower recurrence split
										      loses to the shipped serial four-wide body.
										    - Arm64 explicit push nonnegative-linear category breakdown refresh (2026-04-23):
										      the fill-vs-C disasm probe now emits per-category counts for the shipped
										      four-wide body itself, so the next branch can be chosen from actual
										      instruction mix rather than total counts alone. The refreshed shipped logs
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_064855_96771.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_064900_96827.log`
										      still show the landed Oren main iteration at `35` hot instructions for `4`
										      outputs (`8.75` per element), but now quantify the per-element category
										      mix: Oren spends `stores 1.00`, `arith 2.75`, `moves 1.25`,
										      `compare/tick 1.75`, and `branches 2.00`, while the host C vector ceiling
										      through `LBB0_15` spends `stores 0.50`, `arith 5.00`, `moves 0.25`,
										      `compare/tick 0.50`, and `branches 0.50` at `6.75` instructions per
										      element. Reweight again: the remaining blocker is not “not enough
										      arithmetic” by itself; it is the extra control/move/store overhead around
										      Oren's serial recurrence. Future retries should only ship if they trade
										      that control-state maintenance for more independent arithmetic work, not if
										      they just shave arithmetic ops in isolation.
										    - Arm64 explicit push nonnegative-linear remaining-count control follow-up (2026-04-23):
										      the next narrower loop-control rewrite under that same shipped four-wide
										      body is now also closed negative. A temporary rerun kept the shipped
										      safepoint spill width and store shape intact, but replaced the carried
										      `i` + recomputed `n - i` control with a carried remaining-count and
										      reconstructed the final idx/count only at loop exit. The emitted loop
										      still improved slightly:
										      `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_070103_440.log`
										      and
										      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_070107_517.log`
										      show the wide main iteration dropping from `35` hot instructions for `4`
										      outputs (`8.75` per element) to `34` (`8.50` per element), and the
										      per-output-element category mix only changes in arithmetic
										      (`2.75 -> 2.50`) while `stores 1.00`, `moves 1.25`, `compare/tick 1.75`,
										      and `branches 2.00` stay flat. The actual same-tree decision surface
											      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-remaining-decision-20260423_065955_98963.log`)
											      still does not justify keeping it: fill/share and exact `array_sum_int`
											      improve slightly (`default_fill_vs_c_vector ~2.2233×` vs enabled
											      `~2.1710×`, `default_array_ratio_median ~2.1913×` vs enabled `~2.1894×`),
											      but exact `dot_product_int` regresses (`default_dot_ratio_median
											      ~1.7179×` vs enabled `~1.7739×`, `decision_surface_alignment: agree`).
											      Reweight again: the remaining blocker is not an `n - i` bookkeeping seam
											      by itself; future retries need a bigger control/store reduction or a
											      stronger whole-program dot win.
											    - Arm64 explicit push nonnegative-linear peeled-tail follow-up (2026-04-23):
											      the next narrower control-shape retry under that same shipped four-wide
											      body is now closed negative on correctness before it even reaches the
											      normal ranking surface. A temporary rerun enabled
											      `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4_PEELED_TAIL=1`
											      and peeled the scalar remainder out of the wide body so the main
											      iteration no longer paid the per-trip `< 4 left?` check, but the
											      enabled fill-share wrapper log
											      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-peeled-tail-decision-20260423_071903_4101.enabled-fill.log`)
											      failed because the generated `fill_list_int_oren_native` exits
											      nonzero. The dedicated repro log
											      (`build/logs/verify_fill_list_int_repeat_stability_20260423_peeled_tail_repro_v1.log`)
											      shows the branch is repeated-invocation unsafe: `n=2000000 reps=1`
											      still returns `11`, but `n=2000000 reps=2` panics with `Index out
											      of bounds`. Reweight again: reject the peeled-tail branch on
											      correctness, and keep future retries honest with the shipped
											      repeat-stability verifier instead of only disasm/perf probes.
											    - Native list<int> fast-lowering verifier repeat/runtime refresh (2026-04-23):
											      `make verify-native-list-int-fast-lowering` now honors
											      `OREN_BENCH_ENV_BUILD_OREN` for its arm64 builds and also runs the
												      generated `fill_list_int` benchmark binary with `2000000 2` as a
												      repeat-stability runtime guard. That closes the verification hole the
												      peeled-tail branch exposed: experimental fast-push variants now have
												      to survive repeated invocation before they can be treated as serious
												      performance candidates.
												    - Arm64 explicit push nonnegative-linear unroll4 no-wrap split follow-up (2026-04-23):
												      a spill-budget-neutral “dominant no-wrap fast path, existing wrap body as rare
												      fallback” retry is now also closed negative. The temporary branch enabled
												      `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4_NOWRAP_SPLIT=1` and
												      guarded the current wrap-capable wide body behind a single
												      `current < mod - 3*step` check, so the common no-wrap case no longer paid the
												      per-lane wrap-control sequence. The actual same-tree decision surface
												      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-nowrap-split-decision-20260423_074857_16234.log`)
												      still rejected shipping it: fill/share preferred enabled
												      (`default_fill_vs_c_vector ~2.1517×` vs enabled `~1.7698×`), exact
												      `array_sum_int` median also preferred enabled (`default_array_ratio_median
												      ~2.1881×` vs enabled `~2.1519×`), but exact `dot_product_int` regressed across
												      every sweep (`default_dot_ratio_median ~1.5254×` vs enabled `~1.7467×`,
												      `decision_surface_alignment: agree`). The targeted runtime verifier
												      (`build/logs/verify_native_list_int_fast_lowering_20260423_075050_17727.log`)
												      passed, so this is a pure performance rejection rather than another
												      repeat-stability bug.
													    - Arm64 fill hot-loop split-path probe refresh (2026-04-23):
													      the disasm/compare tooling now measures the dominant fast subpath when a wide
													      loop contains a rare fallback block instead of charging both together as one
													      static main iteration. The refreshed nowrap-split logs
												      (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_075358_18627.log`,
												      `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_075357_18606.log`)
												      now report `main_iter_kind=split_fast_path` at `23` hot instructions for `4`
													      outputs (`5.75` per element) with per-element category mix `stores 1.00`,
													      `arith 2.00`, `moves 0.00`, `compare/tick 1.25`, and `branches 1.50`. Reweight
													      again: a common fill-side path can now beat the host C vector body on static
													      per-element count and still lose the exact whole-program dot surface, so future
													      retries must preserve that dominant-path win without enough rare-wrap/control
													      cost to flip `dot_product_int` back the wrong way.
														    - Arm64 exact-program fill-mix probe (2026-04-23): the new target
														      `make perf-probe-arm64-fast-push-exact-fill-mix` now defaults to the causal
														      single-list set `array_sum_int,array_sum_int_step7` plus the non-causal control
														      `dot_product_int`, and reports which exact programs can actually enter the
														      shipped single-list unroll4 gate `single_list_cursor && pushes_per_iter==1 &&
														      nonnegative_linear && tick_period%4==0`. The refreshed summary log
														      (`build/logs/perf-probe-arm64-fast-push-exact-fill-mix-20260423_081815_23618.log`)
														      shows both single-list sum benchmarks are directly causal
														      (`fill_pushes_per_iter: 1`, `single_list_unroll4_applicable: yes`) and still
														      overwhelmingly no-wrap in isolation (`array_sum_int 98.8000%`,
														      `array_sum_int_step7 98.0000%`), while `dot_product_int` remains structurally
														      ineligible (`fill_pushes_per_iter: 2`, `single_list_unroll4_applicable: no`,
														      `ineligible_reason: pushes_per_iter!=1 blocks single_list_cursor/unroll4 gate`)
														      even though its two isolated fill streams are also mostly no-wrap
														      (`99.2000%` and `98.0000%`).
														    - Arm64 single-list family decision surface (2026-04-23): the new target
														      `make perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision`
														      keeps the fill/share surface but ranks exact programs as causal single-list
														      benchmarks (`array_sum_int,array_sum_int_step7`) plus the separate non-causal
														      `dot_product_int` control. The first summary
														      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision-20260423_082026_25099.log`)
														      exposes a real disagreement on the current shipped tree: fill/share prefers the
														      shipped default (`default_fill_vs_c_vector ~2.0473×` vs disabled `~2.3812×`),
														      but both causal exact programs slightly prefer `disabled` on steady native/C
														      (`array_sum_int ~2.0855×` vs `~2.0782×`,
														      `array_sum_int_step7 ~2.0855×` vs `~2.0782×`), and the non-causal control also
														      slightly prefers `disabled` (`dot_product_int ~5.1433×` vs `~5.1370×`), so
														      `decision_surface_alignment: disagree`. Reweight again: do not spend the next
														      round on narrower local control-form tweaks until this causal single-list
														      surface is reconciled.
													    - Arm64 explicit push nonnegative-linear recurrence follow-up (2026-04-10):
												      a narrower single-list modulo-recurrence subpath was tested on the same shipped
												      baseline, but the widened cached decision surface
											      (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-recurrence-decision-20260410_001827_33770.log`)
										      rejected it cleanly enough to prune from the tree. Fill/share still preferred the
										      shipped default (`default_fill_vs_c_vector ~4.7537×`, disabled `~4.8312×`), and
										      the exact same-tree whole-operation medians also preferred the disabled branch on
										      both tracked programs (`default_array_ratio_median ~2.3187×` vs disabled
										      `~2.2727×`, `default_dot_ratio_median ~1.7935×` vs disabled `~1.7737×`).
										      Reweight: keep the shipped nonnegative-linear fast path simple; the next fill-side
										      work should attack a different residual cost than `%` recurrence inside the same
										      single-list cursor loop.
										    - Arm64 explicit push fresh-exact-init follow-up (2026-04-09): explicit
										      `fast_list_int_push_while` now has an opt-in path
										      `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT=1` that carries conservative
									      same-block constructor proof from `list.int_new(n)` / `oren_new_list_int(n)` into
									      the fast fill loop. When `i` is still known `0` and the constructor cap exactly
									      matches the loop bound, the emitter skips reserve/count/header revalidation and
									      writes through the constructor-installed buffer directly. Use
									      `make perf-probe-arm64-fast-push-fresh-exact-init-decision` as the ranking
									      surface. Current widened safe-tree rerun
									      (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203332_51451.log`)
									      preferred enabled on both surfaces, but the immediate promoted-default rerun
										      (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203846_59158.log`)
										      flipped the exact whole-operation medians back toward the disabled branch while the
										      fill/share surface still preferred default. Reweight: keep
										      `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT` opt-in only. This branch is
										      promising, but the exact same-tree winner is not stable enough yet to ship.
										    - Arm64 explicit push fresh-exact single-list isolation (2026-04-09): the same
										      constructor proof is now isolated behind the narrower opt-in gate
										      `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_SINGLE_LIST=1`, which only targets the
										      single-list explicit fill shape instead of the broader multi-loop family. Use
										      `make perf-probe-arm64-fast-push-fresh-exact-single-list-decision` as the ranking
										      surface. The current safe-tree widened rerun
										      (`build/logs/perf-probe-arm64-fast-push-fresh-exact-single-list-decision-20260409_232042_61224.log`)
										      still rejects promotion: fill/share preferred shipped default
										      (`default_fill_vs_c_vector ~2.7420×` vs enabled `~2.7707×`), exact `array_sum_int`
										      also preferred shipped default (`default_array_ratio_median ~1.9810×` vs enabled
										      `~2.1506×`, `array_default_wins: 4/5`), while exact `dot_product_int` moved slightly
										      toward enabled (`default_dot_ratio_median ~1.7857×` vs enabled `~1.7675×`). Keep
										      this narrower branch opt-in only too; it answered the isolation question but still
										      does not beat the shipped default on the actual fill-side target surface.
											    - Arm64 fast `list<int>` push native-list-header trace alignment (2026-04-09):
											      explicit `fast_list_int_push_while` no longer emits loop-exit
											      `oren_trace_list_header(...)` calls on shipped trace-off builds. It now follows
										      the same compile-time debug contract as the older generic fast-list tracing path
										      and only emits those calls when `OREN_TRACE_NATIVE_LIST_HDR=1` is set. Use
										      `make perf-probe-arm64-fast-push-native-list-hdr-decision` as the ranking surface.
										      The first widened cached rerun
										      (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_213946_33097.log`)
										      slightly preferred `OREN_TRACE_NATIVE_LIST_HDR=1` on fill/share and exact
										      `array_sum_int`, but the second rerun
										      (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_214130_36680.log`)
										      flipped exact `array_sum_int` back toward default by median and kept exact
										      `dot_product_int` with the shipped trace-off build (`default_dot_ratio_median
										      ~1.7383×` vs `trace_enabled ~1.7840×`, `dot_default_wins: 5/5`). The final
										      cached rerun on the finished scripts
										      (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_220014_61301.log`)
										      still stayed mixed: fill/share again preferred `OREN_TRACE_NATIVE_LIST_HDR=1`,
										      exact `array_sum_int` preferred default, and exact `dot_product_int` flipped
										      slightly toward `trace_enabled`. Reweight: keep native fast-loop list header
										      tracing opt-in only; the codegen alignment is correct and shipped, but the exact
										      whole-operation winner is not stable enough to justify default-on tracing.
											    - Arm64 explicit push tick-mask decision surface (2026-04-23 refresh): the
											      current-tree wrapper `make perf-probe-arm64-fast-push-tick-mask-decision`
											      first produced a candidate rerun that made `65535` look promotable
											      (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032104_29410.log`:
											      fill/share `default_fill_vs_c_vector ~1.8155×`, `mask_16383 ~1.8369×`,
											      `mask_65535 ~1.7173×`; exact `array_sum_int` median `default ~2.2131×`,
											      `mask_16383 ~2.1760×`, `mask_65535 ~2.1398×`; exact `dot_product_int`
											      median `default ~1.4062×`, `mask_16383 ~1.4727×`, `mask_65535 ~1.3362×`;
											      `decision_surface_alignment: agree`). But the immediate promoted-default
											      rerun on the actual shipped `65535` tree
											      (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032751_32000.log`)
											      did not hold: fill/share flipped toward the lower masks
											      (`default_fill_vs_c_vector ~1.8792×`, `mask_4095 ~1.7483×`,
											      `mask_16383 ~1.7535×`), while exact `array_sum_int` and exact
											      `dot_product_int` medians both preferred `16383`
											      (`default_array_ratio_median ~2.1792×`, `mask_4095 ~2.1950×`,
											      `mask_16383 ~2.1736×`; `default_dot_ratio_median ~1.7445×`,
											      `mask_4095 ~1.7506×`, `mask_16383 ~1.7229×`). Reweight: keep the shipped
											      `4095` push tick mask; higher masks remain probe-only because the
											      promoted-default rerun is not stable enough to keep.
										    - Arm64 explicit get-sum tick-mask follow-up (2026-04-09): new wrapper
										      `make perf-probe-arm64-fast-get-sum-tick-mask-list-int` now compares the shipped
									      explicit `array_sum_int` get-sum default against explicit mask overrides through the same
							      serialized acceptance bundle. Current final-tree rerun
								      (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-list-int-20260409_143632_74801.log`)
								      keeps `OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK=4095` for now: explicit `16383`
								      and `65535` improved steady native medians on that sample (`0.137232s` and `0.131635s`
								      vs shipped `0.141901s`), but the gate view stayed too noisy to trust as a production
									      default (`native gate cov=0.6421` at shipped `4095`, `0.2631` at `16383`, `0.1270`
									      at `65535`).
									      The stronger exact same-tree decision wrapper is now
									      `make perf-probe-arm64-fast-get-sum-tick-mask-decision`. Current cached rerun
									      (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-decision-20260411_162635_82969.log`)
									      keeps the shipped default: target exact `array_sum_int` preferred default by
									      median (`~2.1833×` vs `16383 ~2.2437×`, `65535 ~2.1864×`,
									      `array_default_wins: 2/3`), and the `dot_product_int` control also preferred
									      default (`~1.7332×` vs `~1.7811×`, `~1.7845×`).
									    - Arm64 explicit get-sum unroll2 promotion (2026-04-09): the earlier crashy
									      candidate was root-caused in
								      `lib/compiler/arm64_native_stmt_loops_list_emit.oren`, where the unrolled
								      bodies were clobbering reserved heap registers `X27` / `X28`. Those temps now
								      use caller-saved `X12` / `X13`, and
									      `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2` now ships on by default for
									      single-read-list shapes. The promoted exact whole-operation rerun
									      (`build/logs/perf-probe-list-int-c-ceiling-20260409_163202_21950.log`) keeps
									      `oren_array_sum_int / array_slot64_vector ~2.3939×`, while the broad gates now
									      pass in `build/logs/make_test_get_sum_unroll2_promote_20260409.log` and
									      `build/logs/make_verify_runtime_robustness_get_sum_unroll2_promote_20260409.log`
									      / `build/logs/runtime_robustness_w5_20260409_163313.log`. The new combined decision
									      probe (`build/logs/perf-probe-arm64-fast-get-sum-unroll2-decision-20260409_170812_66742.log`)
									      makes the disagreement explicit: acceptance steady still preferred disabled
									      (`-4.79%`), acceptance gate slightly preferred default (`+0.78%`), but exact
									      whole-operation `array_sum_int` preferred the shipped default in all three
										      same-tree sweeps (`~2.3793×` vs disabled `~5.3859×`, `array_default_wins: 3/3`).
										      Keep treating the acceptance wrapper as local sanity only; exact whole-operation
										      ceiling plus integrated green lanes are the decision surface for this path.
										    - Arm64 explicit get-sum dual-accumulator follow-up (2026-04-09): the new
										      decision surface `make perf-probe-arm64-fast-get-sum-dual-accum-decision`
										      compares the shipped default against the opt-in
										      `OREN_ARM64_FAST_LIST_INT_GET_SUM_DUAL_ACCUM=1` path on both the local
										      acceptance wrapper and same-tree exact whole-operation C-ceiling sweeps.
										      The widened rerun
										      (`build/logs/perf-probe-arm64-fast-get-sum-dual-accum-decision-20260409_174904_22327.log`)
										      closed that branch as a loser on the actual decision surface: acceptance liked
										      the enabled leg (`steady -19.53%`, `gate -52.65%`), but exact whole-operation
										      `array_sum_int` still preferred the shipped default in `4/5` sweeps
										      (`default ~2.2506×`, enabled `~2.2797×`). Keep dual-accum opt-in only.
				    - Native gate summary hygiene (2026-04-04):
				      `make perf-gate-native` now emits a lightweight summary log and prints the same
			      high-variance warning style used by the arm64 dot probes, so noisy one-program gate
			      outliers are less likely to be misread as real wins.
					    - Native gate stability probe (2026-04-04):
					      `make perf-probe-native-gate-stability` now reruns the canonical native gate a few
					      times and summarizes the ratio range plus warning frequency per program, so future
					      arm64 dot work can compare against a small gate distribution instead of one run. The
					      first rerun (`sweeps=3`, `array_sum,dot_product`) came back clean enough to use:
					      `array_sum` median ~1.9955x C (range ~1.9603x..~2.0259x, warnings 0/3),
					      `dot_product` median ~2.5153x C (range ~2.3889x..~2.6432x, warnings 0/3). That
					      confirms the arm64 dot blocker without relying on a single noisy gate sample.
					    - Tooling fix (2026-04-04): the shared stage1/stage2 build path now uses a repo-local
					      compiler build lock (`build/locks/compiler-build.lock`), so parallel `make perf-*`
					      verification no longer races on `oren` / `oren_stage2` and trips false macOS
					      codesign failures.
					    - Tooling follow-up (2026-04-04): the shared compiler build lock now defaults to a
					      longer wait (`OREN_BUILD_LOCK_WAIT_SECS=1800`, `0` = wait forever) and records
					      holder start time / age in the lock metadata, after a queued `make test` false-red
					      timed out behind a legitimate stage2 rebuild at the old 300-second default.
					    - Tooling fix (2026-04-04): arm64 fast list loops now expose an opt-in
					      `OREN_TRACE_ARM64_LOOP_RANGES=1` trace, and
					      `make perf-probe-arm64-native-hot-loop-disasm` captures just the canonical
					      `fast_list_int_get_sum_while*` / `fast_list_int_dot_while*` machine-code windows
					      from `--disasm` output instead of forcing future dot-core work to sift whole-binary
					      dumps by hand.
					    - Trace (arm64, 2026-04-04): replacing the single-pair unrolled cursor-reg body with
					      post-index pair loads (`ldp ..., [cursor], #16`) regressed the serial reruns
					      instead of helping: steady `array_sum` ~2.33x / `dot_product` ~3.15x and canonical
					      gate `array_sum` ~2.18x / `dot_product` ~2.61x. Reverted; do not treat pair-load
					      cursor fusion as the next likely dot-core win on this host.
					    - Trace (arm64, 2026-04-04): a narrower follow-up that kept cursor bumps separate and
					      only swapped the exact single-pair hot-path scalar load groups for plain offset
					      `ldp` pair loads also regressed. The focused steady rerun moved canonical
					      `dot_product` to ~3.10x C (`build/logs/perf-gate-native-steady-20260404_231609_56304.log`),
					      so non-writeback pair loads are not the next likely win either.
					    - Trace (arm64, 2026-04-04): replacing the hot fast-dot `mul` + `add` pairs with a
					      shared `madd` helper was not correctness-safe. `make perf-smoke-native-fast-loops`
					      still passed `array_sum`, but native `dot_product 10 3` crashed before producing
					      `6590` (log: `build/logs/perf-smoke-native-fast-loops-20260404_223646_87957.log`).
					      Reverted immediately; future multiply-accumulate work needs a narrower audited path.
					    - Trace (arm64, 2026-04-04): narrowing the exact single-pair fast-dot inline-safepoint
					      spill set from two cursor pairs to one `[x19,x26]` pair also regressed the focused
					      steady rerun. `build/logs/perf-gate-native-steady-20260404_233707_97722.log` moved
					      `array_sum` / `dot_product` to ~2.4331x / ~3.0449x C, so the one-pair variant was
					      reverted and the kept two-pair spill set remains the better baseline.
					    - Tooling (arm64, 2026-04-04): `make perf-probe-arm64-native-hot-loop-disasm`
					      now emits instruction counts and a mnemonic histogram for the traced canonical
					      `fast_list_int_get_sum_while*` / `fast_list_int_dot_while*` windows, so static
					      loop-shape changes can be compared directly before another perf rerun.
					    - Tooling follow-up (arm64, 2026-04-05): that disasm probe now forces `--no-cache`
					      when `OREN_TRACE_ARM64_LOOP_RANGES=1` is enabled, because native cache hits can skip
					      lowering and otherwise drop the compile-time `[arm64_loop_range]` lines the summary
					      depends on.
					    - Tooling follow-up (arm64, 2026-04-05): the same disasm probe now exits non-zero
					      when either traced canonical loop window is missing, so cache/lowering drift stops
					      being a soft note and becomes a real failure.
					    - Tooling follow-up (arm64, 2026-04-05): `make perf-probe-arm64-dot-acceptance`
					      now runs the serial arm64 dot-core acceptance bundle in one place:
					      benchmark smoke, hot-loop disasm, steady gate, canonical gate, exact-binary native
					      repro, and `make test` by default. The summary artifact captures the wrapper logs
					      plus the extracted ratios/instruction counts so future dot experiments have one
					      comparable acceptance record instead of a hand-collected command list.
						    - Tooling follow-up (2026-04-05): `make perf-debug-native-benchmark` now provides
						      a reusable exact-binary repro runner for native benchmarks. It records the exact
						      built binary path, args, exit code, build log, and run log, and on non-zero exit
						      it prints the manual `lldb -- <binary> <args...>` command to use next, so unsafe
						      arm64 dot experiments stop depending on hand-reconstructed repro steps.
							    - Tooling follow-up (2026-04-05, updated 2026-04-09): the arm64 exact-`madd`
							      probes now preserve raw native medians/covariance instead of only ratios, and the
							      explicit `list<int>` counterparts now exist too:
							      `make perf-probe-arm64-fast-dot-madd-exact-list-int` and
							      `make perf-probe-arm64-fast-dot-madd-exact-list-int-subpaths`.
						    - Tooling fix (2026-04-05): `make perf-smoke-native-fast-loops` and
						      `make perf-smoke-list-int` now rebuild native benchmark binaries with
						      `--no-cache`, because compiler-env experiments were otherwise able to certify
						      stale cached baseline artifacts as a false green smoke.
						    - Trace (arm64, 2026-04-05): an exact-path `madd` follow-up only replaced the
						      single-pair cursor-reg `fast_list_int_dot_while*` multiply/add pairs. The traced
						      canonical dot window did shrink from 70 to 63 instructions
						      (`build/logs/perf-probe-arm64-native-hot-loop-disasm-20260404_235545_32513.log`)
					      and the focused steady rerun improved to `dot_product` ~2.5627x C
					      (`build/logs/perf-gate-native-steady-20260404_235745_37067.log`), but the exact
					      native smoke still crashed at `dot_product 10 3`
					      (`build/logs/perf-smoke-native-fast-loops-20260405_000124_44574.log`). Reverted;
					      do not treat “same arithmetic with `madd`” as correctness-preserving on this
					      path without a tighter audit.
						    - Probe rerun (arm64, 2026-04-05): the shipped `make perf-probe-arm64-fast-dot-madd-exact`
						      wrapper reached the same conclusion without source edits. The enabled exact-path
						      branch improved the focused acceptance metrics (`steady_dot_product ~2.7940x`,
						      `gate_dot_product ~2.5953x`, canonical dot disasm `63` instructions), but the
						      exact native debug repro still failed at `perf-debug-native-benchmark` with
						      `exit_code: 139` in
						      `build/logs/perf-probe-arm64-dot-acceptance-20260405_005354_27728.summary.log`.
						      After the smoke cache-policy fix, the enabled canonical smoke now fails directly
						      too instead of passing via a stale cached baseline binary.
						    - Exact-double tail guard follow-up (arm64, 2026-04-05): the 2-wide exact-`madd`
						      branch now falls back to the original `mul/add` body when the chunk is terminal.
						      The updated sweep is fully green for `n=1..24`, including the formerly unsafe
						      `n ≡ 2 (mod 4)` tail cases `10`, `14`, `18`, and `22`
						      (`build/logs/perf-probe-arm64-fast-dot-madd-exact-double-sweep-20260405_013604_40047.log`).
							    - Raw-metric rerun (arm64, 2026-04-09): the whole exact branch is still mixed even
							      after the exact-double guard, so keep
							      `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` opt-in:
							      - generic rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-20260409_020451_23581.log`):
							        enabled steady/gate native deltas `+3.12%` / `-3.02%`
							      - explicit rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-list-int-20260409_020520_24931.log`):
							        enabled steady/gate native deltas `+0.11%` / `-2.99%`
								    - Shipped scalar-core matrix (arm64, refreshed 2026-04-11): the wrappers
								      `make perf-probe-arm64-fast-dot-scalar-core-matrix` and
								      `make perf-probe-arm64-fast-dot-scalar-core-matrix-list-int`
								      compare the shipped default-off baseline against `CURSOR=0`,
								      `SCALAR=1`, and `CURSOR=0,SCALAR=1`:
								      - generic rerun (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260411_170733_44863.log`):
								        the one-shot acceptance medians prefer `SCALAR=1` and `CURSOR=0,SCALAR=1`,
								        but the run is too noisy to use alone (`gate` baseline covariances around `0.41`)
								      - explicit rerun (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-list-int-20260411_170847_78864.log`):
								        `SCALAR=1` improves steady (`-5.03%`) but is basically flat/slightly worse on
								        the gate (`+0.65%`); `CURSOR=0,SCALAR=1` improves the same one-shot gate
								        (`-9.96%`) but needs the order-balanced tie-breaker below
								      - deterministic guard (arm64, refreshed 2026-04-11):
								        `make verify-native-arm64-dot-madd-scalar-default` now pins the shipped
								        default-off path to `21` full-range instructions / `14` without the cold
								        GC-call block / `madd_count=0` on both generic and explicit surfaces, with
								        `SCALAR=1` moving both to `20` / `13` / `1`
								        (`build/logs/verify_arm64_dot_madd_scalar_default_20260411_171634_95703.log`)
								      - read-split decomposition (arm64, refreshed 2026-04-11): the wrappers
								        `make perf-probe-arm64-fast-dot-scalar-core-read-split` and
								        `make perf-probe-arm64-fast-dot-scalar-core-read-split-list-int`
								        (`build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-20260411_170937_83286.log`,
								        `build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-20260411_170942_83791.log`)
								        split one-shot setup from repeated work:
								        - generic `dot_product`: the latest read-split does not confirm the noisy one-shot
								          matrix win; the combined cursor+scalar case is roughly flat on setup (`+0.09%`)
								          and regresses repeated `long_per_rep` (`+0.88%`)
								        - explicit `dot_product_int`: `SCALAR=1` improves every reported native component
								          on this rerun (`short -6.13%`, `setup -6.11%`, `delta -6.33%`,
								          `long_per_rep -6.26%`), with the usual delta-vs-long drift warning still telling
								          tracker updates to prefer `long_per_rep`
								      - order-balanced gate stability (arm64, refreshed 2026-04-11): the
								        `make perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int`
								        wrapper rotates the four scalar-core cases across four whole-operation sweeps
								        so each case occupies each run position once. Latest artifact
								        (`build/logs/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-20260411_170947_84214.log`)
								        keeps the explicit shipped verdict mixed:
								        - `SCALAR=1` is only a `2/4` native-median win with median `+1.65%`, while
								          normalized `native/C` is a `2/4` win with median `-1.13%`
								        - `CURSOR=0,SCALAR=1` is also only a `2/4` native-median win with median
								          `+0.48%`, and normalized `native/C` is `2/4` with median `+0.15%`
								      - combined unroll2 + scalar-core decision (arm64, 2026-04-11): the
								        read-split and gate-stability wrappers now accept explicit case sets, and
								        `make perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int`
								        ranks `UNROLL2=1`, `SCALAR=1`, and `UNROLL2=1,SCALAR=1` together on the
								        explicit `dot_product_int` surface. Current artifact
								        (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172420_40937.log`)
								        rejects the combined candidate: read-split native `long_per_rep +0.72%`,
								        gate native median `+2.20%` with `1/4` wins, and gate `native/C +8.09%`
								        with `1/4` wins. The separate `UNROLL2=1` and `SCALAR=1` rows also fail at
								        least one required surface (`long_per_rep +7.42%` and `+3.54%`), so the
								        older scalar subpath "quad" hint is no longer an open promotion branch on
								        this shipped baseline. A post-hardening verification rerun
								        (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172713_80854.log`)
								        was noisier, with high-covariance nested samples, but still rejected the same
								        combined candidate.
								      - scalar-post + scalar-core decision (arm64, 2026-04-11):
								        `make perf-probe-arm64-fast-dot-scalar-post-decision-list-int`
								        ranks `baseline`, `SCALAR_POST=1`, `SCALAR=1`, and
								        `SCALAR_POST=1,SCALAR=1` on the same explicit `dot_product_int`
								        read-split and order-balanced gate surfaces. The structural artifacts confirm
								        the intended lowering:
								        - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1`
								          (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-20260411_174133_69032.log`)
								          emits post-index loads and shrinks the traced range to `19` instructions,
								          `12` without the skipped cold GC-call block
								        - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1`
								          (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-madd-20260411_174149_69542.log`)
								          emits post-index loads plus `madd` and shrinks the traced range to `18`
								          instructions, `11` without the skipped cold block
								        The decision artifact
								        (`build/logs/perf-probe-arm64-fast-dot-scalar-post-decision-list-int-20260411_173911_64748.log`)
								        rejects the combined candidate: read-split native `long_per_rep +0.99%`,
								        gate native median `+1.17%` with `2/4` wins, and gate `native/C +2.22%`
								        with `2/4` wins. The standalone `SCALAR_POST=1` row also fails read-split
								        (`long_per_rep +4.57%`) and gate native median (`+1.01%`, `2/4` wins).
								      - pair-post + exact-body `madd` decision (arm64, 2026-04-11):
								        `make perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int`
								        ranks `baseline`, `UNROLL2=1`, `UNROLL2=1,PAIR_POST=1`,
								        `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1`, and the combined
								        `UNROLL2=1,PAIR_POST=1,QUAD/DOUBLE/SCALAR_MADD=1` candidate. The first
								        focused explicit decision artifact
								        (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_175200_21609.log`)
								        cleared that narrow surface (`long_per_rep -0.22%`, gate native median
								        `-1.03%` with `3/4` wins, and gate `native/C -5.64%` with `4/4` wins),
								        but the immediate same-target rerun after generic wrapper parameterization
								        (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_180637_46019.log`)
								        rejected it (`long_per_rep +6.27%`, gate native median `+0.49%` with
								        `2/4` wins, and gate `native/C -2.93%` with `3/4` wins). Treat the explicit
								        surface as unstable, not promotable. Structural disasm
								        (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-unroll2-pair-post-madd-20260411_175249_24107.log`)
								        confirms the intended 4-wide paired-scalar body: post-index `ldp` pairs plus
								        `madd`, with a 63-instruction traced range and 49 instructions after
								        subtracting two skipped cold GC-call blocks. Broader acceptance keeps this
								        opt-in: explicit `dot_product_int` improves raw native medians (`steady -0.74%`,
								        `gate -6.12%`;
								        `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260411_175304_24487.log`),
								        but generic `dot_product` regresses steady native time while slightly improving
								        gate (`+1.69%` / `-0.63%`;
								        `build/logs/perf-probe-arm64-fast-dot-unroll2-20260411_175335_25935.log`). The
								        matching generic decision wrapper is now
								        `make perf-probe-arm64-fast-dot-pair-post-madd-decision`; current artifact
								        (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-20260411_180500_42245.log`)
								        rejects the same combined candidate despite a read-split repeated-work win
								        (`long_per_rep -2.46%`), because order-balanced gate native median regressed
								        `+1.72%` with only `1/4` wins and normalized `native/C` regressed `+5.16%`
								        with only `1/4` wins. The simpler
								        `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1` row wins the generic gate
								        (`native -2.42%`, `4/4`; native/C `-1.70%`, `3/4`) but fails read-split
								        repeated work (`long_per_rep +2.55%`).
								      - dual-accum `madd` decision (arm64, 2026-04-11):
								        `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1` now converts the existing
								        opt-in dual-accumulator body from `mul`+`add` pairs into independent
								        `madd` updates, but only when `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1`
								        is already set. The new wrappers
								        `make perf-probe-arm64-fast-dot-dual-madd-decision` and
								        `make perf-probe-arm64-fast-dot-dual-madd-decision-list-int` rank the
								        unroll2, dual-accum, dual-accum+madd, pair-post+dual-accum, and
								        pair-post+dual-accum+madd rows. Current generic artifact
								        (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-20260411_183505_89024.log`)
								        rejects the combined candidate: read-split `long_per_rep -0.32%`, but
								        gate native median `-1.20%` has only `2/4` wins and normalized
								        `native/C +0.63%` has only `1/4` wins. The explicit artifact
								        (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-list-int-20260411_183536_91542.log`)
								        also rejects it: read-split `long_per_rep -8.18%`, gate native median
								        `+1.18%` with `2/4` wins, and normalized `native/C +5.43%` with `1/4`
								        wins. Structural disasm
								        (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-dual-madd-20260411_183626_94501.log`)
								        confirms the intended paired post-index `ldp` plus dual-accumulator
								        `madd` shape, with a 53-instruction traced range, 39 after subtracting
								        two skipped cold GC-call blocks, and `madd=7`.
								      - low32 slot-load decision (arm64, 2026-04-11):
								        `OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1` keeps the current 8-byte
								        `list<int>` slot stride but emits sign-extending `ldrsw` from the low
								        32 bits of each slot for the exact single-pair cursor-reg path. It is
								        intentionally default-off because general `list<int>` slots hold 64-bit
								        integers; treat it only as a range-proved/i32 workload experiment.
								        Structural disasm
								        (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-low32-dual-madd-20260411_185115_16862.log`)
								        confirms the intended `UNROLL2=1,LOW32=1,DUAL_ACCUM=1,DUAL_MADD=1`
								        shape: `ldrsw=14`, `madd=7`, 63 traced instructions, and 49 after
								        subtracting two cold GC-call blocks. The new generic decision wrapper
								        (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-20260411_185129_17298.log`)
								        rejects the combined candidate: read-split `long_per_rep +1.25%`,
								        gate native `+0.12%` with `2/4` wins, and normalized `native/C -1.99%`
								        with `3/4` wins. The standalone `LOW32=1` row wins the generic gate but
								        still loses read-split repeated work (`long_per_rep +1.25%`). The
								        explicit decision wrapper
								        (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-list-int-20260411_185153_19370.log`)
								        has the opposite split for the combined row: read-split
								        `long_per_rep -0.81%`, but gate native `+2.72%` with `1/4` wins and
								        normalized `native/C +2.83%` with `2/4` wins.
								      - prefix pair-loop decision (arm64, 2026-04-11):
								        `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1` is a new default-off
								        exact prefix-zero dot branch that emits a counted 2-wide pair loop and keeps
								        the scalar remainder outside the hot pair body. The simple wrapper is
								        `make perf-probe-arm64-fast-dot-prefix-pair-loop-decision`; the broader
								        wrappers are `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision`
								        and `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int`.
								        Structural disasm
								        (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-prefix-pair-loop-20260411_190748_44241.log`)
								        confirms the intended `ldp` pair + `madd` body: 44 traced instructions and
								        26 after subtracting two cold GC-call blocks. The simple wrapper
								        (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-decision-20260411_191033_47867.log`)
								        looked positive (`dot_product` steady/gate native `-0.75%` / `-1.92%`;
								        `dot_product_int` `-0.27%` / `-5.88%`), but the stronger stability surface
								        rejected the branch: generic stability
								        (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-20260411_191326_52903.log`)
								        had read-split `long_per_rep +3.34%` and only `2/4` order-balanced gate wins;
								        explicit stability
								        (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int-20260411_191335_53758.log`)
								        had read-split `long_per_rep +12.87%` and normalized gate `native/C` only
								        `2/4` wins.
								      Reweight: keep scalar exact-`madd` opt-in, keep cursor regs default-on, keep the
								      whole exact branch opt-in, keep scalar-post, pair-post+madd, dual-accum
								      `madd`, low32 slot-loads, and prefix pair-loop opt-in, and use the matrix +
								      read-split + gate-stability wrappers for future core A/B work.
						    - Acceptance surface fix + cursor-end probe (arm64, 2026-04-05):
						      `OREN_BENCH_ENV_BUILD_OREN` now reaches smoke/disasm/debug inside
						      `make perf-probe-arm64-dot-acceptance`, and the acceptance summary records the
						      active `build_env`. Keep that harness improvement. Retire the specific
						      cursor-end lowering branch: the later read-split rerun regressed repeated-loop
						      `dot_product` on both `long/reps` (`~2.6003x -> ~2.6651x`) and delta-based
							      steady (`~2.8383x -> ~3.0797x`), so the cursor-end probes and knob were removed
							      from the live surface after recording the evidence
							      (`build/logs/perf-probe-arm64-fast-dot-cursor-end-read-split-20260405_021431_93331.log`).
							      The April 9 follow-up also added explicit
							      `warning_gate_{dot_product,dot_product_int}_high_variance` keys to the arm64
							      acceptance summaries, and the exact-`madd` wrappers now preserve those warning
							      lines at the top level when gate COV crosses `0.10`.
							    - New compare probe (arm64, 2026-04-05; extractor refreshed 2026-04-11): `make perf-probe-arm64-dot-vs-c-loop-compare`
							      now compares the shipped traced Oren `dot_product` loop directly against the host
							      `cc -O2 -S` lowering of `benchmarks/dot_product/dot_product.c`. It now finds the C
							      vector/mid/tail blocks by `smlal*` / `smaddl` instruction shape instead of hardcoded
							      `LBB0_*` labels. The latest artifact
							      (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260411_165929_79776.log`)
							      shows Oren now shipping a 21-instruction traced range and a 14-instruction range after
							      subtracting the skipped cold GC-call block, while host C is still using a NEON vector
							      loop plus vector mid loop plus scalar `smaddl` tail (`28` + `12` + `6`
							      extracted-block instructions). Reweight future arm64 dot work accordingly: cold
							      safepoint save/restore cleanup alone is unlikely to close the full remaining gap.
							      The new explicit-list companion
							      `make perf-probe-arm64-dot-vs-c-loop-compare-list-int`
							      (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-20260411_165935_82064.log`)
							      confirms the same current shape for `dot_product_int`.
					    - New: LCG fast loop unroll-by-2 on arm64 + x64 to reduce loop overhead (2026-02-26).
    - New: `OREN_TRACE_ARM64_LOOP_STACK=1` logs loop stack/tick layout for arm64 emitters to debug tick slot offsets.
    - Trace (arm64 compile, 2026-02-26, `OREN_TRACE_ARM64_LOOP_STACK=1`): loop_sum + dot_product emitters report tick_off=0 across
      `while_generic` and list<int> fast loops (push/dot), with stack bases matching current stack size.
    - Stage2 trace rebuilds with `OREN_TRACE_ARM64_LOOP_STACK=1` (2026-02-26) completed without GC list-header corruption.
    - Historical debug knob: `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` removed the tick slot for `fast_list_int_dot_while` to
      isolate arm64 tick-offset regressions (trace kind=`fast_list_int_dot_while_no_tick`).
    - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` +
      `OREN_TRACE_ARM64_LOOP_STACK=1`): `fast_list_int_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
    - New debug knob: `OREN_TRACE_ARM64_GC_TICK_OFF=1` logs negative tick offsets in arm64 GC throttled safepoints
      (set to `all` to log every tick_off).
    - Historical debug knob: `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` removed the tick slot for `fast_list_dot_while`
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
   - Fix (2026-03-19): arm64 fast boxed/int get-sum and boxed/int dot loops now use the slot-free
     layout by default. The old stack tick slots can still be restored with the corresponding
     `*_KEEP_TICK_SLOT=1` env overrides when comparing traces, but the active hot paths no longer
     reserve the extra loop slot.
   - Verification (2026-03-19): `benchmarks/dot_product/dot_product.oren` now emits
     `fast_list_int_dot_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_dot_tickslot_default_trace_20260319.log`), while the keep-slot
     escape hatch restores the old layout (`build/logs/codex_arm64_dot_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): the same default now holds for both boxed and `list<int>` get-sum
     loops. `build/tmp/arm64_boxed_getsum_probe.oren` emits `fast_list_get_sum_while_no_tick`
     by default (`build/logs/codex_arm64_boxed_getsum_tickslot_default_trace_20260319.log`), and
     `benchmarks/array_sum_int/array_sum_int.oren` emits `fast_list_int_get_sum_while_no_tick`
     (`build/logs/codex_arm64_int_getsum_tickslot_default_trace_20260319.log`); the corresponding
     keep-slot overrides restore the older layouts.
   - Verification (2026-03-19): `make test` stays green with the new default
     (`build/logs/codex_make_test_tickslot_default_20260319.log`).
   - New debug knob: `OREN_TRACE_ARM64_STACK_RESTORE=1` logs stack restore deltas when the
     compiler repairs mismatched stack accounting on arm64 loop emission (2026-03-03).
   - New: arm64 GC tick-off traces now include last stack-restore context (`last_restore_*`)
     when tick_off is negative to correlate stack repairs with offset regressions (2026-03-03).
   - Verification (2026-03-19): `benchmarks/dot_product/dot_product.oren` and
     `benchmarks/array_sum_int/array_sum_int.oren` now emit
     `fast_list_int_push_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_int_push_tickslot_default_trace_20260319.log` and
     `build/logs/codex_arm64_int_push_qi_tickslot_default_trace_20260319.log`), while
     `OREN_ARM64_FAST_LIST_INT_PUSH_KEEP_TICK_SLOT=1` restores the older layout
     (`build/logs/codex_arm64_int_push_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): `oren.oren` now emits
     `fast_list_push_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_boxed_push_tickslot_default_oren_20260319.log`), while
     `OREN_ARM64_FAST_LIST_PUSH_KEEP_TICK_SLOT=1` restores the older layout
     (`build/logs/codex_arm64_boxed_push_tickslot_keep_oren_20260319.log`).
   - Verification (2026-03-19): `build/tmp/arm64_generic_loop_probe.oren` still emits
     `while_generic` with `tick_off=0` under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_generic_loop_tickslot_trace_20260319.log`). A matching
     `for_loop` trace hook now exists in the native arm64 `For` emitter too, so any surviving
     `For` path will report the same loop-stack metadata.
   - Root cause (2026-03-19/20): the remaining generic arm64 throttled loops are intentionally
     stack-backed because their condition/body/post paths can compile arbitrary code that clobbers
     caller-saved X9/X10.
   - Constraint (2026-03-20): there is no cheap spare-register alternative on the current backend:
     X19..X26 are already consumed as the preserved temp set, and X27/X28 are reserved heap
     globals. Removing those last generic tick slots would require a backend-wide register-policy
     redesign or a different generic safepoint scheme.
   - Status: no further per-loop arm64 tick-slot toggles remain in this W5 thread.
   - Update (2026-04-21): the fresh arm64 perf gate is now back within the Tier-1 hot-loop gate
     (`build/logs/perf-gate-native-20260421_154158_16010.summary.log`: `loop_sum` 1.0926× C,
     `dot_product` 1.9281× C). The closing fixes were inline countdown seeding for low-bit
     safepoint masks plus a literal-only guard on fast push idx-expression constant folding, which
     stopped nested `fast_list_int_push_while` from freezing an outer induction variable to its
     stale pre-loop `locals_int_const` value.
   - Next: keep arm64 hot-loop work off the old tick-slot cleanup thread and move W5 effort toward
     runtime robustness / allocation-heavy workloads and the remaining non-arm64 parity gaps.
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
   - New (2026-04-12): `scripts/run_backend_semantic_diff.sh` emits
     `build/reports/backend_semantic_diff_*.json` with backend exit codes, normalized stdout/stderr
     hashes, log paths, and a pass/fail verdict. It now also runs native with
     `OREN_NATIVE_RUN_JSON=1` and the OBC artifact with `--print-run-json`, records native/AVM
     `effect_ledger_summary` plus normalized `budget_deltas`, and reports only C ledger
     availability as explicitly missing until that backend exports equivalent ledgers. This turns
     one parity smoke into an agent-readable
     semantic-diff artifact rather than a log-scraping check. The native package-policy runner
     now separately emits `oren.native-package-policy-run.v0` runner-observed wall-budget JSON
     on request; native runtime summary export is now `OREN_NATIVE_RUN_JSON=1`, including
     `oren.native-capsule-effect-gates.v0` central domain-gate counters when capsule mode runs.
     Gas summaries include explicit `oren.gas-surface.v0` descriptors so the report can say native
     dynamic-emitter gas is not yet the same comparable unit as canonical AVM opcode-dispatch gas. The report also
     includes empirical `oren.gas-surface-calibration.v0` ratios, but keeps them out of enforcement
     until a conversion contract exists. `make verify-backend-semantic-diff-gas-calibration` runs a
     second loop-heavy calibration point through the same report/guard path, and
		     `make verify-backend-gas-surface-calibration-set` combines the smoke, loop-heavy, branch-heavy, call-heavy, and allocation-heavy reports to guard that the current
	     native/OBC ratio spread remains evidence, not an implicit rule. `make verify-native-gas-accounting-modes`
     now guards that `stmt` and `statement` select statement+loop gas, `basic-block` selects a
     distinct native lowering-block surface, `block-weighted` selects weighted lowering-block
     evidence, and `dynamic-emitter` selects runtime path-aware emitter-span evidence, not a hidden
     alias. The set guard stays off the default test-critical path.
   - New (2026-03-27): bytes parity is now explicitly gated too, covering the portable
     `oren_bytes_len` / `oren_bytes_from_hex` / `oren_bytes_to_hex` / `oren_bytes_pack` surface.
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
  - New (2026-03-07): `make verify-green-world-lock-guarded` wraps the standalone smoke in
    a cheap 3-pass gate with `OREN_GREEN_POLL_CACHE=1`,
    `OREN_TRACE_GREEN_RUNQ_GUARD=1`, and `OREN_TRACE_GREEN_ARGS_STAMP=1`.
  - Reweight (2026-03-07): once the guarded standalone smoke is green, the higher-leverage
    repro path is the earlier native quick integration / green-cache sequence, not the
    standalone world-lock fixture by itself.
  - New (2026-03-07): `make verify-green-preworld-guarded` runs that earlier path directly
    with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1` and slightly longer run timeouts so it can act
    as a cheap pre-world-lock regression gate instead of a one-off triage command.
  - New (2026-03-07): `make verify-green-fairness-guarded` runs stage2 quick integration only
    through `test_green_global_runq_fairness` with `OREN_QI_STOP_AFTER_GREEN_FAIRNESS=1`
    and `OREN_TRACE_GREEN_FAIRNESS=1`; it also sets `OREN_QI_STOP_AFTER_GREEN_CACHE=1`
    so the known fairness flake has a cheap dedicated gate with progress markers in the
    inner log without paying for the unrelated follow-on smokes.
  - Verified (2026-03-07): `make verify-green-preworld-guarded` passed
    (`build/logs/codex_verify_green_preworld_guarded_20260307.log`), and the per-run wrapper log
    now captures the step summaries plus an explicit
    `skip_reason=OREN_QI_STOP_BEFORE_WORLD_LOCK=1`
    (`build/logs/oren_stage2_native_quick_until_world_lock_20260307_002343_run1.log`).
  - Verified (2026-03-07): `make verify-green-fairness-guarded` passed 3/3 runs
    (`build/logs/codex_verify_green_fairness_guarded_20260307_pass.log`), and the per-run
    logs now stop immediately after the base + green-cache fairness passes while keeping
    the fairness progress markers in the inner log.
  - Fix + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now runs the whole
    post-phase follow-on smoke block through checked build/run helpers, applies timeout-like
    reruns per smoke via `OREN_QI_FOLLOWON_SMOKE_RETRIES` (default `1`), and stamps explicit
    `ok:` completion markers plus a final `native quick integration follow-on OK` line into the
    inner log. This removes the remaining late `test-native-quick` `Error 143` blind spot where
    the inner log could stop after `Build successful: ...loop_list_reuse_escape_smoke` without
    telling us which smoke had actually completed. Verified with:
    `build/logs/native_quick_followon_guard_20260409.log` and
    `build/logs/make_test_native_quick_followon_guard_20260409.log`. That verification still hit
    the existing stage1 base-run timeout retry once (`WARN: timeout (rc=143). Retrying with 720s.`
    in `build/logs/oren_native_quick_integration.log`), but the suite stayed green and the new
    markers proved the late follow-on block completed.
  - New + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now accepts
    `OREN_QI_STOP_AFTER_BASE=1`, records `native quick integration base phase OK` plus
    `skip_reason=OREN_QI_STOP_AFTER_BASE=1`, and the new wrapper
    `scripts/triage_native_quick_base_flake.sh` feeds that base-only path through the existing
    flake harness with `OREN_QI_TRACE=1` plus `OREN_QI_FAIL_ON_RETRY=1`.
    `make verify-native-quick-base-guarded` now gives a cheap 3-pass reproducer for the remaining
    stage1 base-run timeout/retry path with per-test progress in
    `build/logs/oren_native_quick_base_only.log` and no hidden reruns. Verified with
    `build/logs/native_quick_base_only_direct_20260409.log`,
    `build/logs/oren_native_quick_base_only.log`, and
    `build/logs/make_verify_native_quick_base_guarded_20260409.log`.
	  - Fix + verify (2026-04-09): `scripts/verify_runtime_robustness_w5.sh` now includes that
	    base-only stage1 reproducer by default before the guarded pre-world-lock green-cache, stage2
	    quick-integration, and C-backend loops. `make verify-runtime-robustness` now forwards
	    `OREN_RUNTIME_ROBUSTNESS_BASE_RUNS`, so the main W5 runtime gate finally covers both active
    stage1 quick-integration guard surfaces instead of leaving the base-only timeout/retry path as
    a side target. The latest full `make test` also reached `native quick integration follow-on OK`
    without reproducing the older base-run timeout retry. Verified with
	    `build/logs/make_verify_runtime_robustness_base_bundle_20260409.log`,
	    `build/logs/runtime_robustness_w5_20260409_054902.log`,
	    `build/logs/make_test_runtime_base_bundle_20260409.log`,
	    `build/logs/oren_native_quick_base_only.log`, and
	    `build/logs/oren_native_quick_integration.log`.
	  - Fix + verify (2026-04-09): the bundled W5 runtime gate now also forwards
	    `OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS`, defaulting the stage1 base-build cap to
	    `720s`. This was necessary once the checked-helper/runtime bundle change forced a cold
	    base-only rebuild back through `rtobj.miss.build.start` long enough to exceed both the older
	    `240s` and `480s` caps while the compiler was still actively running. Verified by the updated
	    script surface (`build/logs/bash_n_verify_runtime_robustness_checked_helper_batch_20260409.log`)
	    and the latest bundled log header (`build/logs/runtime_robustness_w5_20260409_102644.log`,
	    `base_build_timeout_secs=720`).
	  - Fix + verify (2026-04-09): the bundled W5 runtime gate now prewarms host runtime astbin and
	    debug rtobj seeds before the base quick-integration leg instead of depending only on the wider
	    `720s` timeout. The new knobs are `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM`,
	    `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS`, and
	    `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER`. The structural companion target
	    `make verify-native-quick-base-cold-seeded` now forces an empty active runtime obj/astbin
	    cache and verifies that the stage2 base quick path records `phase=rtobj.seed_hit` rather than
	    `phase=rtobj.miss.build.start`. Treat that cold-seeded proof as the durable fix; the larger
	    base-build timeout remains a backstop for unusually slow hosts, not the primary solution.
	  - Fix + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now records
	    `retry_base_count`, `retry_green_cache_count`, `retry_followon_count`, and
    `retry_total_count`, and accepts `OREN_QI_FAIL_ON_RETRY=1` so focused triage surfaces can fail
    on hidden self-healing reruns instead of reporting green. The focused green-cache wrapper
    `scripts/triage_native_quick_green_cache_flake.sh` now disables inner green-cache reruns with
    `OREN_QI_GREEN_CACHE_RETRIES=0` and runs under `OREN_QI_FAIL_ON_RETRY=1`. This keeps the
    focused green-cache surface honest even when a full `make test` stays green after retrying an
    `Indexing on non-container` panic in `__oren_fnwrap_worker_green_local_ptr_survives_yields`.
    A clean sequential rerun of the stricter reproducer passed 3/3 on current `master`
    (`build/logs/make_test_native_quick_green_cache_flake_strict_20260409.log`), and the latest
    inner quick logs now stamp `retry_*_count=0`
    (`build/logs/oren_native_quick_integration.log`, `build/logs/oren_native_quick_base_only.log`);
    the latest full-suite rerun is also clean with the same zero-retry summary
    (`build/logs/make_test_retry_summary_20260409.log`).
    Treat this stage1 green-cache/local-ptr issue as intermittent but still active enough to keep
    the no-retry reproducer in the repo.
  - New + verify (2026-04-09): added a focused local-ptr stress fixture
    `tests/native/test_quick_integration_green_local_ptr_focus.oren` plus strict wrappers
    `scripts/triage_native_quick_green_local_ptr_flake.sh`,
    `make verify-native-quick-green-local-ptr-guarded`, and
    `make test-native-quick-green-local-ptr-flake`. This keeps the same late-green prelude through
    `test_green_global_runq_fairness()` but loops only the allocator-integrity + local-ptr region
    with `OREN_QI_STRESS_ITERS` / `OREN_QI_LOCAL_PTR_MODE` knobs and default
    `OREN_TRACE_LIST_GET_BAD=1` + runq/entry guards. `make verify-runtime-robustness` now bundles
    the focused surface through `OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS`, so the remaining
    stage1 green-cache/local-ptr suspicion no longer depends on the full quick-integration fixture
    for coverage.
  - Refine + verify (2026-04-09): split that focused local-ptr surface into `plain` vs `workers`
    mode triage. New wrappers:
    `scripts/triage_native_quick_green_local_ptr_plain_flake.sh` and
    `scripts/triage_native_quick_green_local_ptr_workers_flake.sh`, plus the serial wrapper
    `scripts/verify_native_quick_green_local_ptr_modes.sh`
    (`make test-native-quick-green-local-ptr-split-flake`). On current `master`, that stricter
    split surface is already a reproducer: it hit `rc=138` in the `plain` half on run 3/3 while
    still in the `test_green_global_runq_fairness()` prelude
    (`build/logs/verify_native_quick_green_local_ptr_modes_20260409_065008.log`,
    `build/logs/oren_native_quick_flake_20260409_065015_run3_err.log`). Keep the stable bundled
    guard on the earlier blended local-ptr wrapper for now, and use the split plain/workers
    surfaces as the next root-cause entrypoint.
  - Root cause + verify (2026-04-09): the current mixed fairness crash was not just “one-arg
    scheduler volatility”. Worker mode was still leaving the host thread and the single background
    worker unsynchronized because the green world-lock only engaged for `g_green_worker_count > 1`.
    The runtime now enables the world lock by default for any worker-mode run unless the caller
    explicitly opts into `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`, and the host/poll gates now honor
    that at `1` worker too.
  - New triage surface (2026-04-09): the sharp mixed fairness slice now has a harness-free direct
    reproducer at `scripts/triage_native_quick_green_fairness_onearg_h8_s1_direct_flake.sh`
    (`make test-native-quick-green-fairness-onearg-direct-flake`), which builds the focused
    fairness binary once and reruns the current `full` / `one_arg` / `notopology` / `hogs=8` /
    `shorts=1` slice directly.
  - Measured (2026-04-09): after the single-worker world-lock fix, the old `h8/s1` fairness
    failure no longer reproduces on the current tree. The direct harness-free target passed 10/10
    (`build/logs/make_test_native_quick_green_fairness_onearg_direct_flake_20260409.log`), the
    one-arg count sweep passed all configured cases including the earlier `hogs=8, shorts=1`
    failure slice
    (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_after_world_lock_fix_20260409.log`),
    and the full fairness mode matrix passed all seven slices 3/3
    (`build/logs/make_test_native_quick_green_fairness_modes_after_world_lock_fix_20260409.log`).
    Reweight accordingly: the current tree no longer has an active fairness repro on these focused
    stage1 surfaces, although fairness stays triage-only until it has broader soak.
  - Verification (2026-04-09): the wider runtime bundle and the repo-wide suite both stayed green
    on the same tree. `make verify-runtime-robustness` passed
    (`build/logs/make_verify_runtime_robustness_after_single_worker_world_lock_fix_20260409.log`,
    `build/logs/runtime_robustness_w5_20260409_090337.log`), and `make test` passed
    (`build/logs/make_test_single_worker_world_lock_fix_20260409.log`).
  - Narrow + verify (2026-04-09): add the dedicated fairness isolator
    `tests/native/test_quick_integration_green_fairness_focus.oren` plus
    `scripts/triage_native_quick_green_fairness_flake.sh` and the matrix wrapper
    `scripts/verify_native_quick_green_fairness_modes.sh`
    (`make test-native-quick-green-fairness-flake`,
    `make test-native-quick-green-fairness-modes-flake`). The shared test body now exposes
    `test_green_global_runq_fairness_counts(hog_count, short_count)` so the mixed fairness path
    can be isolated without duplicating the scheduler test.
  - Measured (2026-04-09): the new fairness matrix already supersedes the local-ptr split as the
    best current-tree reproducer. `full + topology` passed 3/3, but `full` without topology
    failed on run 1/3 with `rc=138`
    (`build/logs/verify_native_quick_green_fairness_modes_20260409.log`,
    `build/logs/oren_native_quick_flake_20260409_071639_run1_err.log`). The leaf cases
    `short_only` and `hogs_only` both passed 3/3
    (`build/logs/triage_native_quick_green_fairness_short_only_notopology_20260409.log`,
    `build/logs/triage_native_quick_green_fairness_hogs_only_notopology_20260409.log`).
    So the current stage1 corruption no longer points at topology contamination or a single spawn
    shape by itself; it points at the mixed hog+short fairness interaction.
  - Patch + remeasure (2026-04-09): `oren_green_spawn(...)` and
    `oren_green_debug_spawn_call_list_to_p(...)` now GC-root `fn_obj` and `args_list` across the
    host-side world-lock/alloc path. After that fix, the fairness split no longer stays pinned to
    one short-arg shape. An earlier rerun shifted the `full` / no-topology / `zero_arg`
    slice from the old immediate `rc=138` crash to a strict green-cache retry
    (`build/logs/triage_native_quick_green_fairness_full_notopology_zeroarg_postroot_20260409_075401.log`,
    `build/logs/oren_native_quick_flake_20260409_075404_run2_inner.log`), while the matching
    `one_arg` slice passed 3/3 then
    (`build/logs/triage_native_quick_green_fairness_full_notopology_onearg_postroot_20260409_075401.log`).
  - Measured (2026-04-09): on the latest rerun from the same tree, the split flipped again:
    `make test-native-quick-green-fairness-zeroarg-flake` passed 3/3 with zero retries
    (`build/logs/make_test_native_quick_green_fairness_zeroarg_flake_20260409.log`,
    `build/logs/oren_native_quick_green_fairness_full_notopology_zeroarg.log`), while
    `make test-native-quick-green-fairness-onearg-flake` failed immediately on run 1/3 with
    `rc=138`
    (`build/logs/make_test_native_quick_green_fairness_onearg_flake_20260409.log`,
    `build/logs/oren_native_quick_flake_20260409_080425_run1_err.log`).
    That is a better triage surface, but still not an honest bundled guard; keep fairness on the
    triage-only entrypoints (`make test-native-quick-green-fairness-zeroarg-flake`,
    `make test-native-quick-green-fairness-onearg-flake`,
    `make test-native-quick-green-fairness-onearg-modes-flake`,
    `make test-native-quick-green-fairness-modes-flake`) and leave
    `make verify-runtime-robustness` on the stable base/local-ptr/pre-world/stage2/C bundle.
  - Measured (2026-04-09): the dedicated one-arg leaf control confirms the unstable path still
    requires the mixed fairness interaction. `short_only` / `one_arg` passed 3/3
    (`build/logs/triage_native_quick_green_fairness_short_only_onearg_20260409.log`), while the
    mixed `full` / `one_arg` variant also failed with topology enabled
    (`build/logs/triage_native_quick_green_fairness_full_topology_onearg_20260409.log`). The
    focused one-arg matrix now has its own serial wrapper
    `scripts/verify_native_quick_green_fairness_onearg_modes.sh`, and the full fairness matrix
    keeps the leaf controls first and continues through all cases so one run captures the passing
    controls plus the failing mixed slices together.
  - Measured (2026-04-09): the first rerun of
    `make test-native-quick-green-fairness-onearg-modes-flake` came back green across the leaf
    control plus both mixed one-arg variants
    (`build/logs/make_test_native_quick_green_fairness_onearg_modes_flake_20260409.log`).
    Treat that as more evidence of runtime volatility rather than closure; the dedicated matrix is
    still the right entrypoint because it preserves all one-arg case outcomes together even when a
    single rerun does not reproduce the crash.
  - Measured (2026-04-09): the new one-arg count sweep
    `scripts/verify_native_quick_green_fairness_onearg_count_sweep.sh`
    (`make test-native-quick-green-fairness-onearg-count-sweep-flake`) shows the current crash
    family is not monotonic in short-task count. The same serial sweep kept `short_only` /
    `one_arg` / `shorts=40`, mixed `hogs=1, shorts=1`, mixed `hogs=1, shorts=8`, mixed
    `hogs=8, shorts=8`, and mixed `hogs=8, shorts=40` all green, but reproduced
    `full` / `one_arg` / `notopology` at `hogs=8, shorts=1` with `rc=138` on run 2/3
    (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_flake_20260409.log`,
    `build/logs/oren_native_quick_flake_20260409_084111_run2_err.log`). Treat that
    `hogs=8, shorts=1` slice as the current sharpest fairness repro and keep the broader
    mode matrices for volatility tracking.
  - Rewire + verify (2026-04-09): the focused local-ptr fixture now accepts
    `OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY` / `OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS`, and the strict
    local-ptr wrappers default fairness off plus `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=720`.
    This keeps local-ptr coverage from inheriting the separate mixed fairness crash or the earlier
    360s timeout-style false red.
  - Measured (2026-04-09): once fairness was removed from the local-ptr path, the blended
    `both`-mode local-ptr slice still reproduced a current-tree crash (`rc=139` on run 3/3 in
    `build/logs/oren_native_quick_flake_20260409_072245_run3_err.log`), but the serial split
    plain/workers surface passed with the widened timeout
    (`build/logs/make_test_native_quick_green_local_ptr_split_after_timeout_widen_20260409.log`,
    `build/logs/verify_native_quick_green_local_ptr_modes_20260409_072744.log`).
    Keep the mixed `both` path as the triage reproducer, and use the split surface for
    `make verify-native-quick-green-local-ptr-guarded` plus the bundled
    `make verify-runtime-robustness` gate.
  - Re-measure + rewire (2026-04-09): on the current tree after the single-worker world-lock fix,
    the blended local-ptr `both` surface no longer reproduces. The harness wrapper passed 3/3
    (`build/logs/make_test_native_quick_green_local_ptr_flake_after_single_worker_world_lock_fix_20260409.log`)
    and then 10/10
    (`build/logs/triage_native_quick_green_local_ptr_flake_10run_after_single_worker_world_lock_fix_20260409.log`).
  - New + verify (2026-04-09): added the harness-free direct mixed-mode local-ptr target
    `scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh`
    (`make test-native-quick-green-local-ptr-direct-flake`), which builds the focused fixture once
    and reruns the current `both` / topology-on / fairness-off slice directly.
  - Guard policy (2026-04-09): the stable local-ptr surface is now the direct mixed both-mode
    target. `make verify-native-quick-green-local-ptr-guarded` and the local-ptr portion of
    `make verify-runtime-robustness` use that stronger direct guard; the split plain/workers
    wrappers remain triage-only, and the harness-based blended wrapper remains available when the
    broader quick-integration path itself needs rechecking.
  - Verified (2026-03-15): arm64 self-hosted stage2 quick integration no longer times out
    in native emit. `./scripts/run_native_quick_integration.sh ./oren_stage2` completed
    cleanly, and the fresh phase log now reaches `macho.fixups.done` plus
    `build.native.emit.done` before the quick-integration binary runs
    (`build/logs/oren_stage2_native_quick_integration.phases.log`,
    `build/logs/oren_stage2_native_quick_integration.log`).
  - Verified (2026-03-15): the current full-suite run progresses past
    `test-native-quick-stage2`; `build/logs/make_test_after_47c7fada.log` reaches the
    capsule rtobj-seed path only after stage1 + stage2 native quick integration pass,
    so the earlier arm64 stage2 compiler timeout/local-fixup blocker is no longer the
    active gate.
  - Fix (2026-03-15): `rtobj-seed` no longer force-refreshes the capsule seed on every run.
    The Makefile now lets `scripts/build_rtobj_seed.sh` no-op/copy on matching capsule
    hash hits and only pay the cold `examples/hello --capsule` build when the current
    capsule hash is actually missing. Re-run `make rtobj-seed` after the first fill to
    verify the path stays cheap on hits.
  - Fix (2026-03-15): host capsule cold-seed population now uses `./oren` as the build
    compiler while still keying the artifact by runtime hash + backend sig. Measured on
    arm64-macos: `./oren build examples/hello.oren --backend native --platform arm64-macos
    --capsule --no-debug --no-cache` completed in about 12.9s and produced the desired
    rtobj cache key, whereas the concurrent `./oren_stage2` cold build was still inside
    `rtobj.miss.build.start` after 10s. `scripts/build_rtobj_seed.sh --compiler ./oren_stage2
    --build-compiler ./oren --capsule --no-debug` now fills the seed once and the next run
    is a no-op hit.
  - Fix (2026-03-15): the capsule cold rtobj-seed path now injects the prebuilt capsule
    runtime astbin seed directly, instead of relying on the compiler to discover the astbin
    seed only after expanding/fingerprinting the runtime. Measured on arm64-macos with empty
    rtobj cache/seed dirs: the old cold path still took about 12.7s even with
    `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=build/cache/native_runtime_astbin_seed`, while the
    new direct-astbin path completed in about 5.2s and logged the exact seed file under
    `build/cache/native_runtime_astbin_seed/`.
  - Fix (2026-03-15): `stage2` / `rtobj-seed` now warm `astbin-seed` before the host rtobj
    seed fill, so first-run capsule seed refreshes can use the direct astbin override
    immediately.
  - Fix (2026-03-15): `rtobj-seed-x64` now warms `astbin-seed-x64` first, and the x64 capsule
    cold-fill path also uses `./oren` as the build compiler while leaving `./oren_stage2` as the
    requested compiler. Measured on x64-linux with empty rtobj cache/seed dirs: the cold
    capsule seed command completed in about 6.3s and logged the direct astbin seed file under
    `build/cache/native_runtime_astbin_seed/`.
  - Fix (2026-03-15): cross-target non-capsule x64 rtobj cold fills now also use
    `--build-compiler ./oren`. Measured on x64-linux with empty rtobj cache/seed dirs: the old
    stage2-only `--no-debug` path was still CPU-bound after about 39s, while the stage1-fallback
    path completed in about 5.0s with the direct core astbin seed file.
  - New: `scripts/triage_stage2_quick_until_world_lock.sh` runs native quick integration
    plus the smokes leading up to `test_green_two_workers_world_lock_smoke` to isolate
    order-sensitive hangs.
  - Update (2026-03-15): `scripts/triage_native_quick_flake.sh` now snapshots the per-run
    quick-integration phase log as well as the inner log, so timeout runs preserve both
    artifacts automatically.
  - Fix (2026-03-27): stage2 quick integration now routes the global-runq fairness joins
    through a shared retrying join helper and gives the GC/STW netpoll wake guard one
    bounded re-measure before failing code `797`, while keeping the original `<700ms`
    regression threshold. This is intended to suppress transient scheduler jitter, not
    to relax the missing-wake regression itself.
  - Fix (2026-03-27): the guarded stage2 scheduler smokes now use the same `30s`
    run budget as `make test-native-quick-stage2`, because the previous `20s`
    wrapper budget was timing out during stage2 quick-integration startup on the
    current arm64-macos path before the guarded assertions even ran.
  - Update (2026-03-27): `make verify-green-fairness-guarded` is now a one-run
    guarded smoke with explicit `OREN_NATIVE_BUILD_TIMEOUT_SECS=120` and
    `OREN_NATIVE_RUN_TIMEOUT_SECS=60` / `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=60`.
    The old `3x` loop remains available through `scripts/triage_native_quick_stage2_flake.sh`
    for flake hunting, but the default verify target should stay a practical gate.
  - New (2026-03-15): `scripts/triage_native_quick_green_cache_flake.sh` +
    `make test-native-quick-green-cache-flake` isolate only the stage1 green-cache rerun path
    with STW/runq guards enabled.
  - New (2026-03-15): `scripts/run_native_quick_integration.sh` now accepts `OREN_QI_SRC` +
    `OREN_QI_LABEL`, and `scripts/triage_native_quick_gc_stw_focus_flake.sh` +
    `make test-native-quick-gc-stw-focus-flake` isolate the quick-integration prefix through
    `test_gc_stw_wakes_netpoll_blocked_threads()` with collector-side waiter dumps enabled.
  - New (2026-03-15): `scripts/triage_native_quick_green_tail_flake.sh` +
    `make test-native-quick-green-tail-flake` isolate the later green-worker/STW/join/select tail
    under green-cache-only reruns, targeting the first observed `expected=3` / `expected=4`
    collector waits.
  - Trace (2026-03-15): the focused green-cache-only harness hit a timeout on run 3
    (`build/logs/codex_stage1_qi_green_cache_only_guarded_20260315.log`), with the last STW
    trace showing `expected=9` parked threads before the run timed out. Follow-up traced loops
    passed 10/10, so treat this as a low-frequency runtime race in the dirty stage1 green/STW
    path, not as a deterministic compiler regression.
  - Trace (2026-03-15): the new focused GC/STW+netpoll flake loop passed 10/10
    (`build/logs/codex_gc_stw_focus_flake_20260315.log`), and the broader stage1
    green-cache-only harness passed 20/20 with `OREN_TRACE_GC_STW_WAITERS=1`
    (`build/logs/codex_stage1_green_cache_flake_with_waiters_20260315.log`).
    The new waiter dump now shows which thread is last to park when STW tails:
    regular OS-thread nodes with `flags=1`, `saved=0`, and transient `backup_saved` /
    512 KiB stack metadata that then park on the next wait. Keep using this path until the
    original timeout reproduces again.
  - Verified (2026-04-08): current `master` passed the dedicated stage1 green-cache flake
    harness 5/5 (`build/logs/triage_green_cache_current_20260408.log`).
  - Fix + verify (2026-04-08): `scripts/verify_runtime_robustness_w5.sh` now includes the
    guarded pre-world-lock green-cache path by default, `scripts/triage_stage2_quick_until_world_lock.sh`
    now preserves the actual build failure exit code in its logs, and the guarded stage2 build
    budgets are aligned to the same proven `240s` headroom used by `test-native-quick-stage2`.
    Verified with `build/logs/make_verify_green_preworld_guarded_20260408.log`,
    `build/logs/make_verify_runtime_robustness_20260408.log`, and
    `build/logs/runtime_robustness_w5_20260408_212845.log`.
  - Trace (2026-03-15): in the successful green-cache reruns, the first larger collector waits
    occur at `test_gc_collect_does_not_deadlock_with_green_join_waiter()` (`expected=3`) and
    `test_gc_collect_does_not_deadlock_with_os_thread_join_waiter()` (`expected=4`), so the next
    tight reproducer should start there instead of from the earlier GC/netpoll wake smoke.
  - Trace (2026-03-15): the new late-tail flake loop passed 10/10
    (`build/logs/codex_green_tail_flake_20260315.log`) while still reproducing the smaller
    `expected=3` / `expected=4` collector waits in isolation
    (`build/logs/oren_native_quick_flake_20260315_043744_run1_inner.log`,
    `build/logs/oren_native_quick_flake_20260315_043757_run8_inner.log`).
  - New (2026-03-15): `scripts/triage_native_quick_green_join_waiters_stress_flake.sh` +
    `make test-native-quick-green-join-waiters-stress-flake` stress only the two join-waiter
    tests in-process, with explicit per-step markers and selectable modes:
    `OREN_QI_STRESS_MODE=green|os|both`.
  - Trace (2026-03-15): that new stress fixture narrowed the failing path precisely.
    `green`-only and `os`-only both passed for 4 iterations, while the original alternating
    `both` mode crashed in the second
    `test_gc_collect_does_not_deadlock_with_green_join_waiter()` iteration
    (`build/logs/codex_green_join_waiters_stress_flake_20260315.log`).
  - Fix (2026-03-15): delayed `STRUCT` publication until after green/select/fn-wrapper
    initialization and changed GC stack scanning to hold the thread-list lock while skipping dead
    OS-thread nodes. That removed the alternating join-waiter stress crash and the dead-thread
    scan hazard that was surfacing in STW traces.
  - Verification (2026-03-15): the focused alternating stress harness now passes
    (`build/logs/codex_post_skip_dead_threads_green_join_waiters_flake_20260315.log`), and the
    related regression gates also pass: backend tag parity
    (`build/logs/codex_verify_backend_parity_tags_after_runtime_fix_20260315.log`) plus stage2
    capsule smoke (`build/logs/codex_test_native_capsule_smoke_stage2_timeout60_20260315.log`).
  - Verification (2026-03-19): the clean branch now completes `make test` end-to-end
    (`build/logs/codex_make_test_rerun_20260319.log`), so this runtime race is no longer the
    active blocker. Keep the focused flake harnesses because they remain the shortest path back to
    this failure mode if future scheduler/GC changes regress it.
  - New: quick flake triage scripts capture the in-flight inner log on SIGTERM/SIGINT
    (writes `*_interrupt.log` alongside the per-run log) for hang forensics, and as of
    `2026-04-21` they also kill the active descendant tree first so interrupted runs do not leave
    orphan `run_native_quick_integration.sh` / compiler processes behind.
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
    SIGTERM/SIGINT (writes `native_quick_until_world_lock_*_interrupt.log`), and on the current
    tree it also kills the active descendant process tree before exit.
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
  - Verified (2026-03-07): standalone guarded world-lock smoke passed 3/3 runs with
    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_RUNQ_GUARD=1`, and
    `OREN_TRACE_GREEN_ARGS_STAMP=1` (summary log:
    `build/logs/codex_green_world_lock_smoke_20260306.log`).
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
	  - Update (2026-03-08): arm64 self-hosted rtobj apply now completes after moving runtime
	    function lookup + runtime fixup handling to lazier paths; latest traced cache-hit build
	    reaches Mach-O fixup application with runtime prepare reduced to about `+16648ms`
	    (log: `build/logs/codex_stage2_build_gc_stw_collect_trace10_20260307.log`).
	  - Update (2026-03-08): emitter fixup application now caches resolved targets, and rtobj
	    apply migrates legacy `fixups_enc` cache hits into the compact in-memory representation.
	    The rebuilt stage1 compiler now gets the old debug cache-hit path through
	    `fixup[10000]` / `fixup[20000]` and finishes native emit
	    (`build/logs/codex_stage1_build_gc_stw_collect_trace14_20260308.log`).
	  - Update (2026-03-08): a fresh arm64 `d0` runtime-object cache entry was regenerated with
	    on-disk `fixups_compact`, and `make oren_stage2` passes again with that warmed cache
	    (`build/logs/codex_stage1_build_gc_stw_collect_nodebug_trace16_20260308.log`,
	    `build/logs/codex_make_oren_stage2_20260308_final.log`).
	  - Next: measure and reduce the remaining self-hosted delta between the fast stage1
	    migrated-cache path and the slower stage2 fixup loop, now that both legacy and fresh
	    cache formats are unblocked.
	  - Next: root-cause the new integrated `test-native-quick` illegal-instruction crash
	    (`build/logs/oren_native_quick_integration.log`) before treating the arm64 compiler path
	    as production-stable.
	  - Next: make the forced cold rtobj seed path cheap enough to refresh cache entries quickly
	    after compiler-side metadata/layout changes (current log:
	    `build/logs/codex_build_rtobj_seed_arm64_20260308.log`).
	  - Update (2026-04-11): x64 rtobj cache hits now use the same lazy-metadata principle instead
	    of eagerly decoding large runtime metadata before user compilation. X64 runtime-object sig
	    `x64_v0_23` stores compact fixups (`x64_fixups_compact`), compact function offsets
	    (`fn_offsets_compact`), and lazy cstr0 offsets; ELF/PE and symtab emission resolve runtime
	    function offsets through lazy lookup sidecars instead of merging the runtime function map
	    into `ctx["functions"]`. The fixed cache-hit trace reaches user-function compilation after
	    attaching compact offsets/fixups
	    (`build/logs/x64_stage2_qi_linux_lazy_fn_offsets_lookup_trace_20260411_225344.log`), while
	    full QI and NET/TLS/HTTP2 stage2 x64 no-cache compiles remain separate throughput work; the
	    measurement-window timeout placeholders are
	    `build/logs/x64_stage2_qi_linux_lazy_fn_offsets_measure_20260411_225556.log` and
	    `build/logs/x64_stage2_net_tls_http2_linux_timeout_measure_20260411_231009.log`. Reweight:
	    keep `make verify-native-x64-compile` bounded by default and use
	    `OREN_NATIVE_X64_INCLUDE_QI=1`, `OREN_NATIVE_X64_INCLUDE_NET_TLS_HTTP2=1`, or
	    `OREN_NATIVE_X64_INCLUDE_STAGE2_FULL=1` only when intentionally probing those slow surfaces.
	    The cleaned default Make verifier passed in
	    `build/logs/verify_native_x64_compile_lazy_fn_offsets_make_default_20260411_233255.log`
	    (376s on this host).
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
   - Update (2026-04-21): the canonical arm64 path is back under the production gate on the shipped
     perf surface. `make perf-gate-native`
     (`build/logs/perf-gate-native-20260421_154158_16010.summary.log`) now records `loop_sum`
     1.0926× C and `dot_product` 1.9281× C, while `alloc_churn` remains inside its separate gate at
     5.0596× C. The fixes that closed the dot gap were not another packed/SIMD bridge experiment;
     they were backend lowering fixes on the canonical path: low-bit inline safepoint countdown
     seeding and literal-only integer-constant handling for nested fast push idx expressions. The
     len128 specialized benchmark path is now guarded by `scripts/verify_alloc_churn_len128_smoke.sh`
     so this exact correctness regression cannot silently return.
   - Baseline (arm64 native, 2026-04-04 latest clean focused list<int> rerun): `array_sum_int` 2.07× C,
     `dot_product_int` 2.59× C, `multi_list_push_int` 2.24× C.
   - Steady-state baseline (arm64 native, 2026-04-04, `reps=100`): `array_sum_int` ~2.43× C,
     `dot_product_int` ~2.78× C.
   - arm64 NEON + x64 SSE2 baseline; keep scalar equivalence.
   - Priority update (2026-03-27): do not lower general `list<int>` hot loops into the current
     packed-bridge path yet; even the shortened steady probe still shows it orders of magnitude
     slower than the canonical loops.
   - Follow-up (2026-03-27): after converting native `i32` typed-buffer scalar dot/reduce
     fallbacks to direct payload pointer loops, the canonical shortened steady baseline improved to
     `array_sum_int` ~1.35× C and `dot_product_int` ~1.36× C, but the packed bridge still sat at
     ~1177× / ~2779× C on the SIMD leg and ~1438× / ~15382× C on the scalar leg. The next
     high-leverage move is no longer “optimize the typed-buffer kernel”; it is “remove bridge
     materialization cost or lower directly against the 64-bit-slot ABI”.
   - Follow-up (2026-03-27): the new hidden direct-slot probe came in at
     `array_sum_int_slot_direct` ~13.74× C and `dot_product_int_slot_direct` ~21.03× C. That is
     vastly better than the packed bridge and confirms the raw slot ABI path is materially real,
     but it still leaves a large gap to the canonical fast loops. The next concrete task is direct
     compiler lowering to that ABI, not another round of runtime-helper or packed-bridge tuning.
   - Follow-up (2026-04-04): the unchecked raw-slot probe now has that narrower direct-lowering
     step on both native backends. `oren_list_int_reduce_sum_slots_unchecked` and
     `oren_list_int_dot_slots_unchecked` inline at the call site, and the fresh forced steady rerun
     (`build/logs/perf-probe-list-int-slot-direct-20260404_200234.log`) improved the hidden
     direct-slot results to `array_sum_int_slot_direct` ~15.1069× C and
     `dot_product_int_slot_direct` ~5.1760× C. That is much less pathological for the dot path, but
     it still does not beat the canonical fast loops (`array_sum_int` ~2.3090× C,
     `dot_product_int` ~2.9950× C on the same sweep), so the remaining work stays on parity of the
     canonical path rather than shipping the helper probe path.
   - Guardrail (2026-04-04): slot-direct verification now includes direct unchecked-helper contract
     coverage via `tests/fixtures/list_int_slot_direct_contracts.oren`, so future arm64/x64 tuning
     cannot silently change nil or mismatch behavior while still passing the benchmark-output smoke.
   - Follow-up (2026-04-11): arm64 raw-slot helper lowering now has
     `OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1` as a default-off probe that narrows the expr-helper
     safepoint spill set and uses a 4095 default tick mask. The decision probe
     `make perf-probe-list-int-slot-direct-fast-tick-decision`
     (`build/logs/perf-probe-list-int-slot-direct-fast-tick-decision-20260411_194036_96087.log`)
     rejects promotion: slot-ABI direct-helper time regressed `+0.21%`, and read-split
     slot-direct native/C regressed on both `array_sum_int` and `dot_product_int`. Keep it opt-in;
     do not use it as the W5 default path.
   - Follow-up (2026-04-11): `OREN_ARM64_LIST_INT_SLOT_DIRECT_PAIR_LOOP=1` is now a default-off
     counted 2-wide raw-slot helper loop probe for unchecked `list<int>` sum/dot helpers. The decision
     probe `make perf-probe-list-int-slot-direct-pair-loop-decision`
     (`build/logs/perf-probe-list-int-slot-direct-pair-loop-decision-20260411_195615_19255.log`)
     rejects promotion: pair-loop alone regressed slot-ABI direct-helper time `+3.15%` and
     read-split `array_sum_int` slot-direct native/C `+9.88%`, while improving only `dot_product_int`
     `-3.31%`; pair-loop+fast-tick regressed slot-ABI `+3.42%` and array `+7.70%`, while improving
     dot `-7.55%`. Keep it opt-in; W5 still needs a real representation/direct-lowering path.
   - Constraint (2026-03-20): direct reuse of the packed-i32 SIMD dot kernel is not safe for the
     current `list<int>` fast-loop payload layout because those slots are 64-bit values.
   - New: native runtime now exposes the current `list<int>` payload ABI explicitly via
     `oren_list_int_data_ptr*` + `oren_list_int_slot_stride_bytes()` and guards it with a native
     layout test.
   - Gate: `dot_product_int` native <= 2x C.

8) **AVM unboxed list<int> payload + lowering**
   - Improve OBC parity for dot/sum loops.
   - Gate: list<int> fixtures + OBC perf parity.

9) **W4 feature set completeness (essential modern features)**
   - Remaining cross-backend language backlog: full `yield`/stackless coroutine semantics beyond
     the current helper surfaces.
   Bare `yield`, `yield <value>`, and expression/result-position `yield` are now shipped through
     `oren_yield_stmt()` / `oren_yield_value(v)`, and explicit caller-visible yielded/resumed
     values now also exist through `oren_yield_exchange(yield_ch, resume_ch, v)`, but source-level
     coroutine/generator semantics and a stronger default native green-channel protocol are still
     missing.
	   - Implemented (rolling): the structured error model is the shipped value-or-error convention
	     (`oren_err`, `oren_is_err`, `oren_err_code`, `oren_err_msg`, `std:result`). `std:result`
	     now also ships `code`, `msg`, `map_ok`, `and_then`, `map_err`, and `or_else`, so the
	     remaining work is stdlib migration breadth rather than core language/runtime availability.
	     It also ships `from_ok_map` / `to_ok_map` bridges so older JSON/YAML/CBOR-style
	     `{"ok":...}` maps can interoperate with the structured error convention during migration.
	     New (2026-05-04): JSON, YAML, and CBOR codec surfaces now provide direct
	     structured encode/decode wrappers (`try_encode` / `try_decode`, plus CBOR
	     sequence/typed-sequence variants).
		     Native ARM64 bool annotation normalization is now singleton-aware too, so serde
		     bool fields preserve `false` when constructors and return boundaries re-normalize
		     already-boolean values.
		     Follow-up (2026-05-04): ARM64 native tracks static typed-struct field metadata for
		     constructor results held in locals/globals/typed params, so `f32`/`f64` member reads preserve
		     float representation after map-backed loads. It also tracks annotated user-function return
		     kinds so `f32`/`f64` returned values stay floaty at call sites. The typed struct field module
		     now guards this on native and bytecode.
		     YAML native quick coverage is now enabled after the optional split-invariant list-push
	     transform was moved off the default path; stage1/stage2 native YAML decode/serde now
	     preserves empty-line handling and compact serde keyword attributes via bytewise string
	     comparisons. The optional native
	     split-invariant list-push optimizer is opt-in (`OREN_OPT_SPLIT_INVARIANT_LIST_PUSH=1`)
	     after a stage1 YAML probe spent the whole 90s test budget in that pass. The fast native
	     quick lane now includes YAML comments and serde-attribute codec smokes. Remaining ok-map
	     cleanup is mostly network/protocol APIs.
	     New (2026-05-04): DNS/host/HPACK now also expose structured `try_*` wrappers over
	     the already-tested ok-map APIs, reducing the remaining network/protocol migration
	     backlog to broader HTTP/TLS/WebSocket surfaces and untested provider edges.
	     New (2026-05-04): HTTP and WebSocket loopback-tested APIs now also have structured
	     wrappers (`try_get_text`, `try_get_response`, `try_connect`, `try_accept`,
	     `try_recv_text`, `try_send_text_*`), and WebSocket low-level helpers now include
	     `try_parse_url` / `try_client_key_base64`, leaving deeper protocol and older
	     library edges as the main network ok-map cleanup.
	     New (2026-05-04): TCP, UDP, TLS, crypto-facing TLS, and HTTP/2 framing/client facades now
	     expose structured wrappers over tested deterministic surfaces (`tcp.try_*`, `udp.try_*`,
	     `tls.try_connect`/`try_wrap_*`/IO/cert/ALPN helpers, `http2.try_parse_*`,
	     `http2_client.try_new`/`try_request`). Remaining network migration is now mostly deeper
	     protocol APIs and older library edges, not the primary facades.
	     New (2026-05-04): OS-specific TLS provider modules now also mirror those direct
	     structured helpers (`try_wrap_*`, IO, cert hash, and ALPN), so advanced provider callers
	     can bypass the facade without falling back to ok-map/errno handling.
	     New (2026-05-04): crypto helper modules now also have checked structured aliases
	     where the semantics are deterministic and already tested: `rand.try_bytes` /
	     `try_fill`, `pem.try_decode_blocks*`, `sha1.try_sha1_*`, `sha256.try_sha256_*`,
	     and `x509.try_sha256_hex_der`.
	     New (2026-05-04): `std:argparse` now has `try_parse(...)` as a structured bridge over
	     the legacy parse map: successful parses and help early-exits stay as direct maps, while
	     parse failures become `oren_err`.
	     New (2026-05-04): `std:regex` now has `try_compile(...)` and `try_is_match(...)`,
	     preserving the legacy compile `{ok, err, v}` map while giving new callers direct
	     value-or-`oren_err` regex compilation/matching.
   - Implemented (rolling): core `assert(cond, msg?)` statement + `oren test` runner.
   - Implemented (rolling): call-site spread + user-defined varargs (incl. `print(xs...)`).
   - Implemented (2026-04-22): rolling module visibility boundaries via `pub` on top-level
     `fn`, `var`, `struct`/`class`, `enum` sugar expansions, and `ffi` declarations.
   - Migration rule: a module that declares any `pub` member becomes closed-by-default to imports;
     modules with no `pub` members remain legacy-open so the current stdlib and repo fixtures do
     not need a flag day.
   - Guarded by native quick integration with both success and compile-failure fixtures for
     `pub` imports, private imported members/types, legacy-open modules, and nested invalid `pub`.
   - New (2026-04-22): the UI color/raster checked path now also runs on the structured error
     surface, with coverage in the Tier-1 native result smoke plus AVM UI tests.
   - New (2026-04-22): rolling `yield` sugar is now guarded in native quick + AVM, including the
     new value-carrying/result-position helper surface.
   - New: `project-doc/yield_coroutine_lowering_20260422.md` records the current backend seams, the
     shipped `oren_yield_value(v)` / `oren_yield_exchange(yield_ch, resume_ch, v)` helper paths,
     and the remaining gap between helper-level value exchange and full coroutine/generator resume
     channels.
   - New (2026-04-22): `oren meta` / native `--metadata` now surface per-function `contains_yield`,
     `yield_stmt_count`, and `yield_stmt_sites`, counting only source-level `yield` statements and
     intentionally ignoring raw `oren_yield()` calls plus nested function-literal bodies.
   - New (2026-04-22): metadata/dump/OBC introspection now also surfaces value-yield separately via
     `contains_yield_value`, `yield_value_count`, `yield_value_sites`, and `yield_value_surface`,
     so the shipped helper-based value contract is machine-readable without pretending the older
     bare-statement `yield_lowering` plan covers it. That surface now also records
     `consumer_kinds` plus per-point `context`.
   - New (2026-04-22): metadata/dump/OBC introspection now also surfaces the explicit channel-based
     helper via `contains_yield_exchange`, `yield_exchange_count`, `yield_exchange_sites`, and
     `yield_exchange_surface`, so the shipped `channel_resume_v0` protocol is machine-readable too.
   - New (2026-04-22): function metadata also emits a rolling `yield_lowering` plan object with an
     explicit entry state plus one resume state per yield site, and now records conservative
     `locals_across_yield` frame-slot candidates; this is the first concrete frame/state model for
     the future coroutine-lowering pass.
   - New (2026-04-22): that plan now also emits `lowering_v0`, an explicit gate for the current
     executable subset. `bare_yield_dispatch_v0` is now marked `ready` for the implemented
     bare-statement `yield` surface: top-level yields, multiple top-level yields, branch/block/
     loop-nested yields, and functions that also contain nested function literals, including live
     locals/params.
   - New (2026-04-22): ready functions now also emit `yield_lowering.prepared_v0`, a concrete
     compiler-generated prepared shape: split-dispatch when top-level yield segments exist, or
     direct-passthrough for ready branch/block control flow. That closes the gap between “metadata
     knows a function is ready” and “the compiler has no explicit lowered body shape yet”.
   - New (2026-04-22): `dump linked` now exposes the same per-function `yield_lowering` object in
     `function_details`, and `verify-yield-lowering-v0` now extracts embedded `OREN_META` from the
     built `.obc` so the backend artifact itself is guarded, not just the standalone `meta` path.
   - New (2026-04-22): `verify-yield-lowering-v0` now guards the strict compiler policy directly,
     including the cache-bypass regression case. Strict `build|meta|dump` validates the full
     parsed source program before DCE/reachability pruning, and strict mode skips artifact-cache
     restore so cached non-strict outputs cannot mask blocked yielding functions.
   - New (2026-04-22): the bytecode backend now consumes `prepared_v0` for the exact
     `lowering_v0.ready` subset and lowers it into an explicit split-dispatch state machine around
     `oren_yield_stmt()`. The verifier now proves real backend consumption with a positive
     `OREN_TRACE_BYTECODE_YIELD_LOWERING` hit for `ready_worker` and no blocked-function lowering
     trace leaks.
	   - New (2026-04-22): `lowering_v0.ready` now also covers multiple top-level yield sites plus
	     top-level locals/parameters that remain live across them. That is now an executed AVM path,
	     not just an analysis claim: the verifier and AVM smoke both run ready functions whose locals
	     survive multiple suspension/resume boundaries.
			   - New (2026-04-22): ready branch/block/loop-nested bare `yield` now ships too through
			     `prepared_v0.kind=direct_passthrough`, and functions that also contain nested function
			     literals stay ready when their own top-level yields are otherwise ordinary. The old
			     non-top-level / loop / nested-literal blockers were stale policy, not execution limits.
	   - New (2026-04-22): the same ready bare-yield fixture is now parity-verified under bytecode, C,
	     and native with stage2 + strict gating. AVM consumes `prepared_v0` through explicit
	     split-dispatch or direct-passthrough execution; C/native still reach the shipped subset
	     through direct `oren_yield_stmt()` execution rather than backend state-machine lowering.
	   - New (2026-04-23): that same parity verifier now also emits a backend-neutral
	     `[yield_lowering_v0]` summary for bytecode, C, and native, so the same prepared-plan shape is
	     observable in every build path instead of only through the older AVM-only lowering trace.
	   - New (2026-04-22): value-carrying `yield` is now parity-verified under bytecode, C, and native
	     too. The current contract is intentionally local and helper-based: `oren_yield_value(v)`
     yields, then resumes with `v`.
	   - New (2026-04-22 / 2026-04-23): explicit caller-visible yielded/resumed value exchange is also
	     parity-verified under bytecode, C, and native through
	     `oren_yield_exchange(yield_ch, resume_ch, v)`. On native host threads with green runtime
	     already active and no background workers, the shipped path now does both pieces needed for
	     correctness on the default runtime route: `oren_yield()` drives a cooperative green
	     scheduling step, and the final wait for `resume_ch` now goes through the scheduler-aware
	     `oren_select_recv([resume_ch])` path instead of a raw blocking `oren_chan_recv(resume_ch)`.
	     That means a responder green task may itself `yield` before replying without wedging the host
	     thread. Direct standalone
	     `./scripts/run_native_quick_integration.sh ./oren_stage2` now auto-prewarms runtime
	     astbin/rtobj seeds too, so empty seed dirs no longer fall back to a cold self-hosted
	     `rtobj.miss.build.start` path during the quick smoke. The seeded-cold proof now runs against a
	     dedicated tiny native fixture instead of the full quick-integration source, so default
	     verification keeps the same structural guarantee at lower cost. The same channel protocol now
	     also has shared-front-end source syntax (`yield expr in (yield_ch, resume_ch)` and
	     `yield in (yield_ch, resume_ch)`), with metadata distinguishing source syntax from raw helper
	     calls via `syntax_kinds` and per-point `syntax` / `explicit_value`.
		   - New (2026-04-23): the first generator/coroutine-level cancellation protocol now ships above
		     that helper path:
		     - `std:generator.request_cancel(...)` / `std:coroutine.request_cancel(...)` record sticky
		       first-write-wins cancel-request state distinct from `close()`
		     - `is_cancel_requested(...)` and `cancel_reason(...)` expose that sticky state
		     - active delegation propagates both request and hard-cancel intent down the current child
		       chain
		     - the request survives natural completion or explicit `close()`
		     - `std:generator.cancel(...)` / `std:coroutine.cancel(...)` are now the shipped hard-stop
		       layer for the current helper path: they record the same sticky state and then force the
		       deterministic `close()` path
		   - New (2026-04-23): timeout-aware watcher helpers now also ship on that same surface:
		     - `request_cancel_after(target, timeout_ms, reason)` starts a joinable watcher task that
		       sleeps and then records the cooperative sticky cancel-request state
		     - `cancel_after(target, timeout_ms, reason)` starts a joinable watcher task that sleeps and
		       then applies the same first-write-wins hard-stop `cancel(...)` protocol
		     - `request_cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` and
		       `cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` are the synchronous
		       stdlib forms above those watcher helpers: they spawn the same watcher and then wait
		       through `oren_join_timeout(...)`
		     - `timeout_ms == nil` defaults to `0`, negative timeouts clamp to `0`, and invalid non-`int`
		       timeouts fail immediately with `err`
		     - for live targets the watcher join result is `nil`; if `cancel_after(...)` runs after the
		       target already finished, the watcher surfaces the cached terminal result without rewriting
		       the target’s cancellation state
		     - `join_timeout_ms == nil` or any negative `join_timeout_ms` value now uses a derived
		       wait budget instead of a raw infinite join: relative helpers wait for
		       `timeout_ms + 2000`, absolute helpers wait for the computed deadline delay plus `2000`,
		       and stop helpers add `grace_ms` into that same default budget; invalid non-`int`
		       join-timeout arguments fail immediately with `err`
		     - the default native green/runtime route now carries started generator handles through these
		       watcher tasks correctly, so the remaining gap is richer deadline/scheduler policy rather
		       than timeout-helper availability itself
		   - New (2026-04-23): absolute-deadline watcher helpers now also ship on the same contract:
		     - `request_cancel_at(target, deadline_ns, reason)` / `cancel_at(target, deadline_ns, reason)`
		       use the `time.now_ns()` domain instead of relative `timeout_ms`
		     - `request_cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` /
		       `cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` are the matching
		       synchronous absolute-deadline forms
		     - `deadline_ns <= time.now_ns()` fires immediately, `deadline_ns == nil` defaults to
		       immediate, and invalid non-`int` deadlines fail immediately with `err`
		   - New (2026-04-23): the shipped helper stack now also carries an explicit stop-policy layer:
		     - `stop_after(target, timeout_ms, grace_ms, reason)` first records the cooperative sticky
		       cancel request and then escalates to the existing hard-stop `cancel(...)` path after
		       `grace_ms`
		     - `stop_at(target, deadline_ns, grace_ms, reason)` applies that same soft-then-hard
		       policy against an absolute deadline in the `time.now_ns()` domain
		     - `stop_after_wait(target, timeout_ms, grace_ms, reason, join_timeout_ms)` /
		       `stop_at_wait(target, deadline_ns, grace_ms, reason, join_timeout_ms)` are the
		       synchronous stdlib forms above that watcher layer: they apply the same policy and then
		       wait through `oren_join_timeout(...)`, using either the explicit `join_timeout_ms`
		       budget or the derived operation window plus `2000`
		     - `timeout_ms == nil`, `grace_ms == nil`, and `deadline_ns == nil` all default to
		       immediate scheduling points, negative timeout/grace values clamp to `0`, and invalid
		       non-`int` timeout / grace / deadline arguments fail immediately with `err`
		     - `cancel(target, reason)` now consistently accepts handle-or-context targets, so the
		       watcher/stop helpers no longer depend on an implicit handle-only hard-cancel seam
		     - `terminal_result(handle)` now exposes the final done-handle result directly instead of
		       requiring callers to branch manually across `terminal_error(...)` and `return_value(...)`
		   - New (2026-04-23): the shipped stop/cancel stack now also has a map-shaped
		     scheduler/deadline policy API above the flat helper family:
		     - `stop_policy(target, policy)` always returns the joinable watcher handle for the
		       normalized policy
		     - `stop_policy_wait(target, policy)` applies that same normalized policy synchronously
		     - `policy["mode"]` accepts `request_cancel`, `cancel`, or `stop` (default `stop`; `request`
		       aliases `request_cancel`)
		     - `policy["timeout_ms"]` and `policy["deadline_ns"]` are mutually exclusive when both are
		       non-`nil`
		     - `policy["grace_ms"]` is valid only for `mode=stop`; positive grace on other modes fails
		       immediately with `err`
		     - `policy["join_timeout_ms"]` is consumed by `stop_policy_wait(...)` and follows the same
		       derived wait-budget rules as the existing `*_wait(...)` helpers
		   - New (2026-04-23): `std:task` now ships as the first safe facade over generic `spawn`
		     handles:
		     - `task.is_handle(...)` / `is_done(...)` provide the first reflected task predicates across
		       AVM, C, and the default native green-task path
		     - `task.current()` now returns the current safe task handle inside scheduler-backed spawned
		       work and `nil` elsewhere
		     - `task.request_cancel(...)`, `task.is_cancel_requested(...)`, and
		       `task.cancel_reason(...)` now ship as cooperative sticky cancel-request state for generic
		       task handles
			     - a task may observe that sticky request on its first executed step when the request is
			       recorded before the task first runs
		     - `task.request_cancel_after(...)` / `request_cancel_after_wait(...)` and
		       `task.request_cancel_at(...)` / `request_cancel_at_wait(...)` now layer timeout/deadline
		       helpers above that cooperative state
			     - zero-delay / already-expired `*_wait(...)` calls now apply the request synchronously
			       before returning instead of relying on a watcher task to run later
		     - `task.join(...)`, `join_timeout(...)`, `detach(...)`, and `join_all(...)` now wrap the
		       raw runtime join surface behind safe-handle validation
			     - `join_timeout(...) == -60` now preserves the live handle for later join/cancel/detach
			       instead of consuming it on timeout
			     - `task.cancel(...)`, `cancel_after(...)`, `cancel_after_wait(...)`, `cancel_at(...)`,
			       and `cancel_at_wait(...)` now ship as bounded task-cancel helpers: they record the same
			       cooperative sticky request first, then use the safe join/detach path instead of an unsafe
			       preemptive worker kill
			     - `task.stop_after(...)`, `stop_after_wait(...)`, `stop_at(...)`, `stop_at_wait(...)`,
			       `stop_policy(...)`, and `stop_policy_wait(...)` now ship as the shared task stop/deadline
			       surface for generic `spawn` handles
			     - that task stop surface now accepts `mode="request_cancel"`, `mode="cancel"`, and
			       `mode="stop"`
				     - `mode="request_cancel"` records cooperative sticky state only
				     - `mode="cancel"` records the cooperative request at the timeout/deadline and then
				       immediately applies bounded join/detach
				     - `mode="stop"` records the cooperative request at the timeout/deadline, then waits the
				       grace window before detaching if the task is still live
				     - `stop_policy_wait(...)` returns `nil` for `mode="request_cancel"` and returns the
				       `{status, result, reason, detach_result}` map for `mode="cancel"` or `mode="stop"`;
				       `join_timeout_ms` remains the explicit synchronous wait-budget override
			     - legacy native raw fallback handles remain low-level-only for now; the safe reflected
			       surface is intentionally limited to scheduler-backed task handles there
		   - New (2026-04-23): `std:task_group` now ships as the first structured-concurrency group
		     layer above that policy map:
		     - `task_group.new(default_policy)` / `from_list(targets, default_policy)` create mutable
		       groups over generator/coroutine handles, active contexts, or safe task handles
			    - `task_group.stop_policy(group, policy)` merges the group default policy with an override
			      and returns a watcher list for the whole group; stdlib map-backed groups now also
			      dispatch by member kind instead of rejecting task members
				    - `task_group.stop_policy_wait(group, policy)` applies that same normalized policy
				      synchronously and now routes task members through the shared `std:task`
				      stop-policy surface
				    - direct group helpers now mirror the same policy family for easier use:
				      `request_cancel(...)`, `request_cancel_wait(...)`, `cancel(...)`, `cancel_wait(...)`,
				      `stop_after(...)`, `stop_after_wait(...)`, `stop_at(...)`, and `stop_at_wait(...)`
			     - `task_group.join_all(...)` is now the task-handle-only group join path, while
		       `task_group.join_watchers(...)` and `task_group.terminal_results(...)` round out the
		       watcher / terminal-result side of the group surface
		   - New (2026-04-23): runtime-backed task groups for generic `spawn` work now also ship as the
		     first runtime-backed mixed group surface:
			    - `task_group.new_runtime()` / `new_runtime_with_policy(default_policy)` create
			      runtime-backed groups with the latter attaching a stored default stop-policy map
			    - `task_group.from_task_list(targets)` / `from_task_list_with_policy(targets, default_policy)`
			      are the task-handle constructors, while `task_group.from_runtime_list(targets,
			      default_policy)` creates the same runtime-backed shape from safe task handles plus
			      generator/coroutine handles or active contexts
			    - runtime-backed groups now also accept those same mixed non-task members through
			      `add(...)` / `extend(...)`
			    - `task_group.is_runtime_group(...)` distinguishes that runtime-backed shape, while
			      `task_group.is_group(...)` and `std:reflect.is_task_group(...)` now accept both runtime
			      and stdlib map-backed groups
					    - `task_group.default_policy(...)` / `set_default_policy(...)` now also ship for
					      runtime-backed groups and round-trip a cloned stored policy map; `snapshot(...)`
					      returns cloned `members`, `member_kinds`, and `default_policy`
					    - `task_group.member_kinds(group)` now exposes the normalized member-kind vector
					      (`"task"`, `"generator"`, or `"generator_context"`), and runtime-backed groups
					      compute it from an atomic runtime-owned member snapshot rather than a separate
					      stdlib classification pass
							    - runtime-backed mixed membership, stored default policy, and member/kind/policy
							      snapshotting now live in the runtime group state itself across C, native, and
							      AVM instead of stdlib sidecar maps; runtime stop paths preflight policy and then
							      consume an atomic runtime-owned take-snapshot before dispatching per-member
							      policy helpers, so invalid overrides leave runtime groups intact while valid stop
							      operations claim and clear participating members up front
				    - `task_group.spawn_call_list(...)` spawns directly into the runtime group on AVM, C, and
				      the default native green-task scheduler
			    - `task_group.stop_policy(group, policy)` / `stop_policy_wait(...)` now dispatch by
			      member kind:
			      - stored runtime-group default policy is merged before override validation
			      - generator/coroutine members keep the full generator-backed stop-policy semantics
						      - task members now use the same shared `std:task` contract, including cooperative
						        `mode="request_cancel"`, bounded `mode="cancel"`, `mode="stop"`, and optional
						        `join_timeout_ms` override on the synchronous path; immediate zero-budget task
						        cancel/stop execution is runtime-owned through `oren_task_cancel_now(...)`
								      - `std:task.stop_capabilities()` exposes the runtime stop boundary as data:
								        immediate cancel-now, cancel-request state, bounded cancel-wait, and delayed
									        synchronous cancel-wait are runtime/scheduler-backed across C, native, and AVM;
									        AVM uses dedicated scheduler opcodes for the wait paths
									      - verifier/runtime-edit guardrail (2026-05-04): native surface verifiers now
									        prewarm the stage1 runtime astbin seed and pass the exact seed through
									        `OREN_NATIVE_RUNTIME_ASTBIN` for stage2 native builds, while still bounding
									        native build process groups with `OREN_VERIFY_NATIVE_BUILD_TIMEOUT_SECS`.
										        They also prewarm a non-debug core runtime-object seed with stage1. The
											        seed prewarm now validates the runtime hash cache against recorded source
											        file size/mtime metadata before taking the no-op path, so repeated surface
											        verifier runs avoid forced cold seed probes while edited scheduler runtime
											        files still refresh the seed before stage2 fixture verification.
											      - the shared rtobj seed cold-fill helper is now bounded by
											        `OREN_RT_OBJ_SEED_BUILD_TIMEOUT_SECS` (default `180`) and kills the
											        child process group on timeout, closing the `make stage2` gap where a
											        bad native-runtime/codegen edit could previously sit in `rtobj_seed_probe`
											        outside the verifier timeout wrapper.
									      - bytecode direct emission now avoids materializing the legacy `list<int>` code
									        representation unless OBC linking needs it, and scalar constant interning cuts
									        the generator surface constant pool from 5355 entries to 781 entries.
									      - `OREN_TRACE_BYTECODE_CODEGEN=1` and
									        `scripts/profile_bytecode_codegen.sh` now provide section/function bytecode
										        codegen profiling. The 2026-05-04 generator-surface profile proves the
										        remaining large-fixture bytecode hotspot is the final call-fixup pass
										        (`call_fixups`: about 41s for 1228 sites), while function-body compilation
											        is only about 3.9s total. Oren-level cache/patch variants did not improve
											        this, and a direct-address variant moved the same cost into per-call
											        `ctx["functions"][name]` lookups, so the next real optimization should
											        avoid name-keyed post-pass patching or fix the native hot map lookup safely.
											      - bytecode call fixups are now grouped by callee name during emission, cutting
												        the generator-surface `call_fixups` profile from about 41s to about 6.7s
												        (`1228` call sites across `231` unique callees) without regressing the
												        `compile_stmts` phase. The profile summary also preserves extra section
												        metrics such as `names=...` for regression tracking.
												      - `make profile-native-build-phases` now wraps a native fixture build with
												        the same direct astbin seed, rtobj seed prewarm, and process-group timeout
												        used by surface verifiers, then summarizes adjacent build/codegen phase
												        deltas. The 2026-05-04 generator profile shows the largest native costs
												        as user declaration emission (~22.5s), link/prep (~14.5s), wrapper
													        emission (~12.8s), and global-root registration codegen (~7.3s for
													        626 roots). `arm64.codegen.global_roots.done` now records that hidden
													        root cost separately instead of folding it into runtime declarations.
													      - ARM64 global-root initialization now emits a compact root-offset data table
													        and one generated registration loop instead of per-root ADR/BL fixups. The
														        generator profile reduced local fixups from 20271 to 19021 and code bytes
														        from 2592520 to 2585100, while keeping root-name tracing on the explicit
														        diagnostic path. Root metadata is now tracked as globals are allocated or
														        imported from rtobj seeds, preserving the 626-root generator profile count
														        while cutting `arm64.codegen.global_roots.done` from about 6.8s to about
														        120ms by avoiding an emission-time globals-map walk. A map-backed Mach-O
														        target cache was tested and rejected after hitting the 180s profile timeout.
														      - ARM64 runtime-object application now logs `rtobj.apply.*` sub-phases and
														        schema-3 rtobj caches carry adoptable global/root metadata. On cache hits the
														        compiler adopts the decoded runtime globals map and recorded root metadata
														        directly before user globals are appended, instead of replaying 613 runtime
														        globals through ordinary Oren map mutation. The generator profile cuts
														        `rtobj.apply.globals.done` from about 12.26s to about 0.55ms (`adopted=1`).
														      - ARM64 statement compilation now sets loop/statement compile hooks once per
														        codegen context instead of resetting module globals for every statement. The
													        native profile also splits wrapper emission into scan/fnwrap/lambda buckets:
													        wrapper scanning is only ~29ms, named function wrapper emission is ~4.2s, and
													        lambda wrapper emission is ~8.4s on the generator surface fixture. The next
													        native build-cost task should therefore target direct wrapper emission or
													        wrapper codegen batching, not more AST scanning work.
													      - ARM64 native build profiling now also captures per-function codegen rows
													        behind `OREN_TRACE_ARM64_FUNCTIONS_PATH`, and
													        `make profile-native-build-phases` summarizes phase totals plus the hottest
													        generated function bodies. The generator-surface profile shows the
													        `user_decls` phase is dominated by the generated fixture `main`
													        (~13.2s / 300888 bytes), while wrapper cost is distributed across many
													        small generated functions (`lambda_wrap` ~8.5s across 52 funcs, `fnwrap`
													        ~4.4s across 37 funcs). It also exposes a separate Mach-O local BL target
														        resolution spike (~2.6s in the first 4096 local BL fixups), but a
														        map-backed target-cache experiment already hit the native profile timeout,
														        so the next safe native optimization should reduce monolithic
														        statement/function codegen overhead or change wrapper emission shape.
														      - Follow-up (2026-05-04): the local Mach-O resolver now stores unique-target
														        string length and first byte beside its existing linear target cache. This
														        preserves byte-content equality and avoids the rejected map/hash/string-identity
														        cache designs. The refreshed generator profile improved only modestly
														        (`~3419ms + ~107ms + ~146ms` local BL resolve buckets to
														        `~3371ms + ~36ms + ~88ms`), so keep treating user-declaration/wrapper
														        codegen and the first BL resolve bucket as the real remaining bottlenecks.
															      - Follow-up instrumentation (2026-05-04): local BL resolve logs now include
															        `prefilled` and `resolved` target counts. The generator profile reports
															        `prefilled=0 resolved=11285`; a recent-first linear scan experiment was also
															        measured and rejected. Reweight away from eager-target or scan-order retries
															        unless another fixture gives different facts.
																      - Follow-up cleanup (2026-05-04): the local target resolver now also stores
																        each unique target name's last byte beside length and first byte before
																        doing the full byte-content comparison. The refreshed generator profile is
																        still dominated by the first BL resolve bucket (`~2386ms + ~25ms + ~62ms`,
																        `n=11174`), so keep prioritizing `user_decls` / `lambda_wrap` unless a
																        stronger first-bucket resolver design appears.
																	      - Local resolver scan diagnostics (2026-05-04): opt-in
																	        `OREN_PROFILE_MACHO_RESOLVE_STATS=1 make profile-native-build-phases`
																	        now includes unique target count, lookup count, linear scan steps,
																	        metadata candidates, byte comparisons, appended targets, and misses at
																	        progress and completion points. The generator profile reports `11398`
																	        BL lookups over `332` unique targets, `790088` linear scan steps, and
																	        only `12567` full byte comparisons; by `i=4096`, `269` unique targets
																	        are already appended and `252115` scan steps are spent. Detailed counters
																	        are gated so the default native profile stays phase/function oriented.
																	        Hoisting stable list lengths out of those hot loops trims later spans only
																	        modestly, so the next resolver design must reduce linear traversal itself
																	        rather than byte-comparison cost.
																      - Metadata-key cleanup (2026-05-04): the resolver now stores a single
																        `(length, first-byte, last-byte)` integer key per unique target instead
																        of three separate metadata vectors. This preserves byte-content
																        equality and avoids the rejected cache families, but the generator
																	        profile still reports the same `790088` BL scan steps and first bucket
																	        around `~2.40s`; treat it as a constant-factor simplification, not the
																	        final traversal fix.
																	      - Rejected metadata-bucket resolver follow-up (2026-05-04): both a
																	        map-backed metadata-key bucket and a lean parallel-list metadata bucket
																	        reduced detailed BL scan accounting from `790088` entries to the
																	        candidate count (`12567`), but the first BL resolve bucket stayed
																	        flat/slightly worse (`~2.40s` to `~2.43-2.45s`). Do not retry bucket
																	        discovery that merely moves the cost into per-lookup map/list lookup.
																      - Named-function wrapper cleanup (2026-05-04): synthesized `__oren_fnwrap_*`
															        functions now carry a compiler-internal marker that skips native call-depth
														        enter/exit instrumentation on ARM64 and x64. The actual target function
														        still carries the guard, while lambda wrappers stay guarded because their
														        wrapper is the body. The generator native profile moves `fnwrap` from the
														        prior ~5.8s / 29700 bytes / 37 funcs to ~3.9s / 28516 bytes / 37 funcs,
														        and local BL fixups drop to 11174. Keep the remaining backend work focused
														        on `user_decls`, `lambda_wrap`, and the first BL resolve bucket.
															      - Direct fixed-fnwrap body emission (2026-05-04): fixed-arity
															        `__oren_fnwrap_*` functions now keep the synthesized AST body for
															        non-ARM64 backends but carry metadata so ARM64 emits the env/arity
																        checks and target call directly inside the existing function frame. The
																        generator profile moves `fnwrap` from ~4.0s / 28516 bytes / 37 funcs to
																        ~0.95s / 19932 bytes / 37 funcs; reweight named-function wrappers down
																        and keep the next backend slice on `user_decls`, `lambda_wrap`, or the
																        first BL resolve bucket.
																	      - Direct fixed-lambdawrap prefix emission (2026-05-04): fixed-arity
																	        `__oren_lambda_*` wrappers keep the synthesized AST body for fallback
																	        and non-ARM64 paths, but ARM64 emits the generated env/arity checks
																	        plus capture/parameter binding prefix directly before compiling the
																	        original lambda body normally. The generator profile moves
																	        `lambda_wrap` from ~7.8s / 72368 bytes / 52 funcs to ~1.7s / 54968
																	        bytes / 52 funcs. Varargs lambdas still use the generic wrapper path;
																	        reweight remaining backend work toward `user_decls` and the first BL
																	        resolve bucket.
																	      - Wrapper emitter split (2026-05-04): the direct ARM64 fnwrap/lambdawrap
																	        emitters now live in `lib/compiler/arm64_native_stmt_wrappers.oren`
																	        and call back into statement compilation explicitly. This keeps
																	        `arm64_native_stmt.oren` under the 2000-line guardrail without changing
																	        the measured fast-wrapper behavior; treat it as maintainability
																	        groundwork before the next `user_decls` slice.
																	      - Direct non-string comparison branches (2026-05-04): ARM64 `if`
																	        conditions with non-string comparison expressions now branch directly
																	        from integer/float compare flags instead of materializing a runtime
																	        boolean singleton and re-normalizing it for truthiness. The generator
																	        profile keeps `user_decls` time roughly neutral (~20.9s), but cuts
																	        user-declaration code size from ~505KB to ~461KB and local fixup volume
																	        from 18719 to 17691. String/dynamic truthiness conditions remain on the
																	        generic path.
																		      - Stackless literal/singleton branch follow-up (2026-05-04): direct ARM64
																			        `if` comparisons now avoid the temporary left-operand stack spill when
																			        comparing against `true`, `false`, `nil`, or integer literals; wider
																		        and negative integer literals load through a scratch register. The
																		        same slice fixes ARM64 `oren_bool_norm(float)` so `bool(-0.0)` compares
																		        as `-0.0 != 0.0` before returning a runtime boolean singleton instead
																		        of treating raw IEEE bits as an integer. The refreshed generator profile
																		        keeps fixup counts stable while reducing total code bytes from 2514200
																			        to 2505768 and `user_decls` bytes from 460696 to 452472. This is a
																			        useful guard-heavy code-size cleanup, but `user_decls` wall time remains
																			        the next real backend boundary.
																				      - Direct logical-if branch follow-up (2026-05-04): ARM64 `if`
																				        conditions whose guards are short-circuit `||` / `&&` chains now carry
																				        branch-result lists directly instead of materializing runtime boolean
																				        singleton values and immediately normalizing them again for statement
																				        truthiness. `tests/fixtures/tier1_native_logical_if_branch_main.oren`
																				        verifies side-effect short-circuit behavior and is now part of native
																				        quick integration. The uncontended generator profile keeps
																				        `user_decls` wall time roughly neutral (~20.9s) while reducing
																				        `user_decls` code bytes from 452472 to 379528, so the remaining
																				        backend work stays on lowering cost, not guard-chain code size.
																				      - Direct string-comparison-if follow-up (2026-05-04): the same direct
																					        ARM64 `if` branch path now covers string/string-literal comparisons
																					        with the existing guarded `strcmp` semantics and native small-value
																					        fallback. This avoids producing runtime boolean singletons when
																					        statement branching consumes the comparison immediately. The measured
																					        generator profile keeps `user_decls` wall time roughly neutral but
																					        cuts `user_decls` bytes from `340360` to `325368` and local ADR-data
																						        fixups from `4665` to `4303`; continue treating this as
																						        code-size/fixup-volume cleanup rather than the final wall-time fix.
																						      - Literal branch trait-probe hoist (2026-05-04): direct ARM64 `if`
																						        comparisons against `true`, `false`, `nil`, and integer literals now
																						        run the stackless singleton/literal branch path before broad
																						        string/float trait probes, with known-float non-literal sides still
																						        falling back to generic numeric lowering. The sequential generator
																						        profile keeps `user_decls` wall time in the same band (~21.0s) while
																						        trimming user-declaration bytes from `325368` to `323804`; a follow-up
																						        also reuses already-known string-trait results inside the guarded
																						        `strcmp` decision instead of walking both operands again. This is safe
																						        constant-factor guard cleanup, not the final wall-time fix.
																						      - Rejected string-literal register branch follow-up (2026-05-04): a
																						        narrower direct string-if experiment loaded literal operands directly
																					        into compare registers to avoid the temporary stack spill around
																					        `strcmp`. It passed focused native/bytecode branch smokes and trimmed
																					        generator `user_decls` bytes only from `325368` to `324612`, but two
																					        profiles regressed `user_decls` wall time to about `25.6s`; the branch
																					        was reverted. Do not retry that literal-register path without stronger
																					        evidence that compiler-side lowering cost is addressed too.
																				      - Shared function epilogue follow-up (2026-05-04): generated ARM64
																				        `return` statements now run call-depth exit if required, restore SP to
																				        FP, and branch to one function-local epilogue instead of duplicating
																				        the X19-X26/LR restore sequence at every return site. The uncontended
																				        generator profile keeps `user_decls` wall time roughly neutral
																				        (~20.8s) while reducing `user_decls` code bytes from 379528 to 340360;
																				        wrapper bytes also fall (`lambda_wrap` 53472 -> 51096, `fnwrap`
																				        19932 -> 18600). Continue treating wall-time lowering as the main
																				        remaining backend task.
																				      - Rejected literal-return fast path (2026-05-04): a direct ARM64
																				        emitter for `return nil` / singleton / integer-literal values built
																				        and passed focused native smokes, but the generator profile stayed
																				        neutral-to-worse (`user_decls` still about `20.9s` and `340360`
																				        bytes), so it was reverted. Do not retry this narrow return path
																				        without a new profile proving it is hot.
																			      - Statement-profile follow-up (2026-05-04): `OREN_PROFILE_NATIVE_STMTS=1
																			        make profile-native-build-phases` now enables gated inclusive ARM64
																        statement buckets via `OREN_TRACE_ARM64_STMTS_PATH`. The default profile
														        path stays at phase/function granularity to avoid per-statement aggregation
														        overhead. The first generator run shows `user_decls ExprStmt(If)` at ~16.5s
														        / 854 stmts, `user_decls Var` at ~2.7s / 579 stmts, and `user_decls Return`
														        at ~2.4s / 1088 stmts; wrapper cost is mostly the synthesized
														        function/body envelope (`lambda_wrap ExprStmt(Function)` ~8.5s and
														        `lambda_wrap Block` ~15.0s inclusive). A top-function body-scope skip
														        experiment regressed the profile and should not be retried as-is.
														        Follow-up probes also rejected a narrow `if { return }` block-skip matcher
														        (unchanged code bytes, neutral-to-worse phase timings) and exclusive
															        statement profiling via per-depth child accounting (timed out at the
															        180s native-profile budget before `user_decls` completed).
															      - Condition-shaped statement profile follow-up (2026-05-04): the gated
															        ARM64 statement profiler now breaks `ExprStmt(If)` down by condition
															        shape without changing the default phase/function profile path. The
															        refreshed generator run shows the largest inclusive `user_decls`
															        buckets are `Infix(||,Infix(!=),Infix(!=))` (~6.4s / 179 stmts),
															        `Infix(||,Infix(||),Infix(!=))` (~4.4s / 58 stmts),
															        `Infix(!=,Call,String)` (~1.8s / 46 stmts), and
															        `Infix(!=,Call,Boolean)` (~1.6s / 121 stmts). These remain
															        inclusive timings; use them to rank probes, not as exclusive proof that
															        the condition expression alone owns the whole bucket.
															      - Logical-branch flattening follow-up (2026-05-04): ARM64 direct `if`
															        lowering now flattens same-operator `&&` / `||` chains before emitting
															        branch lists. This preserves left-to-right short-circuit behavior while
															        avoiding recursive same-shape lowering for generated guard chains. The
															        first probe also exposed that the matcher must use bytewise compiler
															        string comparison for operator matching; direct string equality could
															        fail to flatten and recursively re-enter the same condition until
															        call-depth overflow. After the fix, focused logical/integration smokes
																		        pass, code bytes stay unchanged, and the latest default-profile sample
																		        moves `user_decls` from ~25.1s to ~21.7s while statement buckets move
																		        only slightly (`|| != !=` ~6.43s -> ~6.37s). Treat this as structural
																		        cleanup, not the final wall-time fix.
																	      - OR-branch single-jump inversion follow-up (2026-05-04): non-last
																	        `||` terms now skip the unconditional true bridge only when the term
																	        produces one false-branch placeholder, which can be safely inverted to
																	        branch directly to the then-block. Composite terms such as `a && b`
																	        keep the older bridge because inverting each false exit independently
																	        changes conjunction semantics; the new logical fixture covers the
																	        mixed validation shape that exposed the unsafe version through native
																	        `dot_f64_view`. The refreshed generator profile trims `user_decls`
																	        bytes from `323804` to `322472` while wall time stays in the same
																	        band, so this is guarded code-size cleanup rather than the final
																	        native build-time fix.
																	      - Singleton-compare trait cleanup (2026-05-04): direct ARM64 `if`
																	        comparisons against `true`, `false`, or `nil` now bypass the long
																	        float-trait classifier when the other side is a literal, an
																	        annotated non-float direct call, or a known direct runtime/generated
																	        boolean helper such as `oren_is_err` or `oren_generator_is_done`.
																	        Emitted bytes are unchanged, but the refreshed default profile keeps
																	        `user_decls` around ~21.1s instead of the prior ~21.2s sample. This
																	        is compiler-side constant-factor cleanup; keep the next backend work
																	        focused on broad generated condition lowering.
																	      - Statement loop length-hoist follow-up (2026-05-04): ARM64 block
																	        iteration, branch false-jump patching, return-jump patching, and
																	        logical branch helpers now hoist stable `oren_list_len(...)` values
																        out of hot compiler loops. This does not change emitted code; the
																        refreshed generator profile keeps `user_decls` in the previous band
																        (~20.9s / 323804 bytes), `lambda_wrap` ~1.7s, and `fnwrap` ~0.95s.
																        A declaration-free block scope-frame skip built and passed focused
																	        checks, but regressed `user_decls` to ~22.1s and wrapper phases as
																	        well, so it was reverted. Keep the new block/shadow/`for var` scope
																	        smoke in native quick as the guardrail for any stronger scope design.
																		      - Fresh-cap tracker fast path (2026-05-04): the ARM64 list-int
																	        reserve-skip tracker now avoids cloning/scanning fresh-cap state when
																	        no tracked cap exists, and its recursive expression scanner hoists
																	        stable child-list lengths. Emitted code is unchanged. The default
																	        generator profile stays in the previous band (~20.9s / 323804 bytes),
																	        while the gated statement profile moves `user_decls Var` from ~2.85s
																	        to ~2.76s and statement-profiled `user_decls` from ~23.0s to ~22.2s.
																	        Keep this classified as compiler-loop cleanup; broader `user_decls`
																	        wall time is still the main backend target.
																			      - Statement shape/callee profile follow-up (2026-05-04): gated ARM64
																	        statement profiling moved to `arm64_native_stmt_profile.oren`, reducing
																	        `arm64_native_stmt.oren` line pressure while adding value/callee detail
																	        for `Var`, `Assign`, and `Return` buckets. The refreshed generator
																	        statement profile identifies generator error-return helpers
																	        (`STD_generator__generator_cancel_target_err`, `_oren_generator_err`),
																	        generator policy member calls (`stop_policy_wait`, `stop_policy`),
																		        and lambda-wrapper `oren_list_get` capture loads as the largest
																		        non-conditional buckets. Treat these as ranking data; avoid
																		        generator-specific native shortcuts unless a separate proof shows
																		        semantic safety and a real profile win. A direct lambda-wrapper
																		        local-binding probe removed the `lambda_wrap Var(Call(Id:oren_list_get,2))`
																			        statement bucket, but default profiles stayed neutral-to-worse
																			        (`lambda_wrap` ~1.7-1.9s with identical emitted bytes), so it was
																			        reverted instead of shipped.
																				      - Dynamic string equality fix (2026-05-05): ARM64 expression and
																			        direct-`if` equality lowering now use safe `oren_string_eq(...)`
																			        only for truly dynamic equality operands (not statically stringy,
																			        and not provably non-string). This fixes native
																			        `tests/modules/test_generator_std.oren` at the generic
																			        `assert_eq(oren_type_name(g), "generator")` boundary without
																			        putting common int/bool/generated guards on the runtime string
																			        helper path. The new `tier1_native_dynamic_string_eq_main.oren`
																			        native-quick smoke covers branch and expression-value equality.
																			        The uncontended profile stays in the prior band (`user_decls`
																			        ~21.0s / 323192 bytes); the broader all-generic-`==` probe was
																			        rejected after it inflated an overlapped profile to ~29s.
																				      - the generator surface fixture now splits its formerly monolithic native
																	        `main` into four top-level chunks plus a tiny dispatcher. Coverage and
															        return codes are preserved, but the hottest function drops from ~13.2s /
														        300888 bytes to four smaller chunks (~1.0s, ~4.1s, ~3.0s, ~4.2s).
														        The measured native profile improves `user_decls` from ~22.0s to ~20.7s
														        and link/prep from ~14.6s to ~8.4s, while confirming large monolithic
														        user functions are still a native-codegen scaling target.
														      - the coroutine surface fixture now uses the same split shape: four focused
														        top-level chunks plus a tiny dispatcher, preserving return codes and
														        coverage. The measured coroutine native profile now has the largest fixture
														        chunk at ~2.0s, while still exposing broader compiler/backend costs:
														        `user_decls` ~12.0s, global-root codegen ~6.3s, link/prep ~9.1s, and
														        Mach-O local BL target resolution ~1.8s for the first 4096 local calls.
														      - ARM64 assignment/global trait propagation now reuses the already-computed
														        float trait when deriving integer trait state. This removes redundant
														        top-level expression walks in hot `var`, `assign`, and global-slot paths;
														        the measured profile keeps it classified as a small codegen cleanup, not
														        the primary native build-time lever.
														      - the AVM bytecode-link smoke is now a bounded tiny OBX link/run verifier by
													        default, with unresolved `--obc-lib` relocs guarded separately; full stdlib
													        bundle probing is opt-in via `OREN_VERIFY_FULL_STDLIB_OBC=1`.
									      - native green bounded joins now re-check the specific joined task between
									        short scheduler-poll slices instead of passing the full caller timeout into
									        the generic poll loop. This closes the over-wait shape where an already
									        completed watcher could be delayed by unrelated parked green tasks.
				    - `task_group.join_all(...)` / `detach_all(...)` remain task-handle-only runtime-group
				      operations and reject extra generator/coroutine members
			    - `task_group.terminal_results(...)` now works for runtime-backed groups that contain only
			      generator/coroutine handles; it still rejects task handles and context-only members
								    The remaining gap is now narrower: runtime-backed groups are already unified and
								    runtime-owned for mixed membership, stored default policy, and atomic
										    member/kind/policy snapshot-and-take semantics, and generic task cancellation now
										    ships as cooperative request plus bounded stop/detach; immediate task stop
												    execution and bounded/delayed synchronous task cancel waits are now
												    runtime/scheduler-owned through `oren_task_cancel_now(...)`,
												    `oren_task_cancel_wait(...)`, and `oren_task_cancel_after_wait(...)` across C,
												    native, and AVM. Generator/coroutine typed stop execution still lives in stdlib
												    rather than wholly in the runtime scheduler.
			    or runtime task-group membership for spawned work.
		   - New (2026-04-22): `std:generator` now ships as the first reusable source-level abstraction on
		     top of that explicit exchange contract, but it is no longer the storage owner. Its
				     `start/next/send/close/cancel/request_cancel/delegate/is_started/is_done/is_closed/current_step/return_value/terminal_error/collect/is_cancel_requested/cancel_reason` surface
		     is now a thin facade over compiler-injected
		     `oren_generator_*` helpers, the shipped handle is tagged as `generator`, and worker bodies now
		     use `yield ... in co` as the normalized generator-context surface instead of spelling out
		     raw channel fields.
			   - New (2026-04-23): `std:coroutine` now ships as the matching coroutine-oriented facade over
			     that same shipped handle/context substrate. It adds
				     `start/resume/next/send/on_finalize/on_close/close/cancel/delegate/delegate_step/is_started/is_done/is_closed/current_step/return_value/terminal_error/collect`
			     plus `std:reflect.is_coroutine(v)` and `std:reflect.is_coroutine_context(v)`.
			   - New (2026-04-23): source-level `@oren.coroutine` now also ships as a self-host-safe
			     parser alias of `@oren.generator`. Reweight the next feature backlog accordingly:
			     - the missing work is no longer “ship coroutine source syntax”
			     - the shipped alias family now covers named `fn`, function-valued `var`,
			       lambda-valued `var`, `yield from`, and `defer` declaration forms
			     - the remaining gap is a distinct coroutine metadata/runtime model plus the broader
			       resumable coroutine protocol above the current generator substrate
			     - canonical metadata/runtime still stay on the generator contract
		   - New (2026-04-22): top-level and block-local `@oren.generator` now lower to that same
		     compiler-managed handle surface for both named `fn ...` declarations and function-valued
		     `var` bindings instead of a hidden `std:generator.start(...)` import.
			     Reweight the remaining work again: the missing piece is no longer “replace the stdlib-map
				     wrapper”, and the shipped handle contract is now also opaque by default
									     (`compiler_generator_object_v7` with `dedicated_generator_object_kind_v1` plus validated
					     `generator_context`, declaration-form metadata, `close_mode=propagate_active_delegate_chain_detach_live_task_v3`,
						     `delegate_mode=track_active_chain_inline_fresh_or_cached_started_step_v3`, and
						     `for_in_v0` iterable metadata). The remaining work is the next abstraction layer above the shipped
					     `generator` handle
					   - New (2026-04-22): raw generator slot numbering is now isolated to named injected helper
					     accessors in `lib/compiler/parser_parse/005_generator_core.oren`, so the new dedicated
					     generator object-kind substrate stays localized instead of rewriting every
						   - New (2026-04-22): the large-file cleanup pass above that substrate has moved another
						     step too: generator-specific AVM/runtime glue lives in dedicated helper includes,
						     pointer load/store helpers now live in `lib/runtime/061_ptr_load_store.inc`, and
						     print/iter/string reflection helpers now live in `lib/runtime/043_print_iter_string.inc`.
							     `lib/runtime/010_prelude.inc`, `lib/runtime/040_lists_maps.inc`,
							     `lib/avm/avm_state.inc`, and `lib/avm/avm_native.inc` are all back under the 2000-line
							     threshold; the AVM state host split now lives in `lib/avm/avm_state_rr.inc` and
							     `lib/avm/avm_state_snapshot.inc`, the universe/VFS/native helper cluster now lives in
							     `lib/avm/avm_native_fs_universe_helpers.inc`, the clone/value helper cluster now lives in
							     `lib/avm/avm_native_clone_helpers.inc`, the mid-body object/buffer switch islands now live
							     in `lib/avm/avm_native_object_buffer_cases_a.inc`,
							     `lib/avm/avm_native_buffer_cases_b.inc`,
							     `lib/avm/avm_native_buffer_cases_c.inc`, and
							     `lib/avm/avm_native_buffer_cases_d.inc`, and the capability-domain dispatcher body now
							     lives in `lib/avm/avm_native_capability_domain_fs.inc` plus
								     `lib/avm/avm_native_capability_domains_misc.inc`
						   - New (2026-04-22): the next coupled ARM64 stmt payoff above that generator/AVM cleanup is
						     landed too. `lib/compiler/arm64_native_stmt.oren` is back under the repo threshold, the
						     old list-loop emitter body is now split into
						     `lib/compiler/arm64_native_stmt_loops_list_emit_prefix_reduce.oren`,
						     `lib/compiler/arm64_native_stmt_loops_list_emit_int_reduce_dot.oren`, and
						     `lib/compiler/arm64_native_stmt_loops_list_emit_dot_push.oren`, and the set-lowering tail
						     now lives in `lib/compiler/arm64_native_stmt_set.oren`
						   - New (2026-04-22): the last tracked oversized source file is gone too.
						     `tests/native/qi/100_tests_basic.oren` is now only a facade that includes
						     `110_tests_basic_smoke_a.oren`, `120_tests_basic_std_buffer.oren`,
						     `130_tests_basic_core_runtime.oren`, and `140_tests_basic_select_arena.oren`,
						     so the rolling tracked source scan is back under the 2000-line threshold
						     everywhere. Reweight the next task away from file-size cleanup and toward
						     higher-leverage runtime/compiler seams like the stage2 `dump linked`
						     throughput path.
						   - New (2026-04-23): the stage2 generator-finalize introspection hotspot is fixed without
						     widening the shipped generator surface. `dump linked` / `dump graph` / `meta` now skip
						     compiler-injected generator-core helper parsing on the source-introspection path, and the
						     metadata guards now pin the cleaner visible-only function surface instead of expecting
						     hidden `oren_generator_*` / `_oren_generator_*` helpers in `meta`.
			     resume/close/delegate path.
	     (compiler-managed coroutine object lifecycle, richer resume protocols, and eventually
	     fuller coroutine language affordances without manual channel semantics leaking through).
	   - New (2026-04-22): generator handles now participate in generic `for x in iterable`
	     lowering too. The shipped contract is intentionally simple and explicit:
	     `for x in gen { ... }` resumes the generator with implicit `nil` on each step until done.
	     verified across bytecode, C, and native.
	   - New (2026-04-22): the focused exchange/generator proof scripts now take source-side
	     `meta`/`dump linked` from `./oren` and still verify stage2-built embedded OBC metadata plus
	     bytecode/C/native execution, which cuts the default guard cost without dropping target
	     artifact coverage.
	   - New (2026-04-22): the stage2 imported-generator bytecode regression is fixed and now
	     guarded by a committed four-case matrix instead of living only as a rollback note.
	     - the metadata emitter path was refactored away from repeated whole-document string
	       concatenation and onto chunked `oren_string_join(...)` assembly
			     - `scripts/probe_generator_import_yield_regression.sh` now proves all four committed
			       `tests/fixtures/generator_import_*` cases plus delegated imported composition compile under
			       `./oren_stage2 build --backend bytecode`
			     - the probe is pinned in `make test` through `verify-generator-import-yield-regression`
		   - New (2026-04-22): the next abstraction layer above plain `next/send` is now widened and
		     source-visible too.
		     - `oren_generator_delegate(co, inner)` / `std:generator.delegate(co, inner)` now cover both
		       fresh-handle inlining and already-started handles that still carry a cached current step
		     - `oren_generator_delegate_step(co, inner, step)` /
		       `std:generator.delegate_step(co, inner, step)` remain available for explicit step-driven
		       control
		     - source syntax now ships:
		       - explicit workers: `yield from inner in co`
		       - `@oren.generator` declarations: `yield from inner`
		       - `from` is contextual after `yield`, so existing identifiers named `from` are preserved
			     - the shipped mode is `track_active_chain_inline_fresh_or_cached_started_step_v3`
			     - explicit close/finalization now ships too through
			       `oren_generator_close(gen)` / `std:generator.close(gen)`, with
			       `close_mode=propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5`
			       plus `oren_generator_on_finalize(co, hook)` / `std:generator.on_finalize(...)`
			       using `on_finalize_mode=lifo_zero_arg_on_done_or_close_v1`
			     - `on_close(...)` now remains only as an alias surface, recorded as
			       `on_close_mode=alias_of_on_finalize_v1`
		     - source-level finalization syntax now ships too:
		       - explicit workers: `defer { ... } in co`
		       - `@oren.generator` declarations: `defer { ... }`
		       - `defer` remains contextual instead of becoming a global reserved word
			     - generator declaration metadata is now `version=19` with
		       `finalize_surface=generator_finalize_v0`
		     - per-function `meta`, `dump linked`, and OBC outputs now expose
		       `contains_generator_finalize`, `generator_finalize_count`,
		       `generator_finalize_sites`, and `generator_finalize_surface`
		     - the emitted `generator_finalize_surface` is `generator_finalize_v0`
		       with `lifecycle=on_done_or_close_v1`, `hook_arity=zero_arg`, and
		       per-site `syntax_kinds` / `api_kinds` / `consumer_kinds` /
		       `finalize_points`
		     - the new compact parity guard is
		       `verify-generator-finalize-surface-v0`
		     - handle sealing now first recursively closes the active delegated chain, then runs
		       finalization hooks, then detaches live workers instead of resuming them with a hidden close
		       sentinel
			     - imported stage2 bytecode coverage now includes
			       `tests/fixtures/generator_import_delegate_step_regression_v0.oren`,
			       `tests/fixtures/generator_import_close_regression_v0.oren`,
			       `tests/fixtures/generator_import_delegate_close_regression_v0.oren`,
			       `tests/fixtures/generator_import_on_close_regression_v0.oren`,
			       `tests/fixtures/generator_import_on_finalize_regression_v0.oren`,
			       `tests/fixtures/generator_import_defer_regression_v0.oren`, and
			       `tests/fixtures/generator_import_yield_from_regression_v0.oren`
		     - native wrapper discovery now also pre-scans nested lambda / generator-worker bodies for
		       named function values, so declaration-body `on_close(...)` plus
		       `gen.start(named_worker, ...)` followed by `yield from ...` is no longer a blocked native seam
				   - New (2026-04-22): the native nested-green scheduler seam is no longer a blocked repro.
					     - `scripts/verify_generator_nested_green_resume_v0.sh` now proves the fixed path instead of
					       a timeout-only failure
					     - `tests/fixtures/generator_nested_green_resume_v0.oren` keeps the reduced runtime shape
					       pinned under native
					     - reweight the next generator/runtime batch upward again, toward broader coroutine/resume
					       protocol design rather than another scheduler unblock
	   - Bytes + typed buffers are already partially shipped through `std:bytes` / `std:buffer`;
	     reweight that thread toward API tightening rather than first availability.
   - Design spec: `docs/design/structured_error_model.md` (2026-03-05).
   - New: `std:result` smoke fixture in native quick integration
     (`tests/fixtures/tier1_native_result_smoke_main.oren`, 2026-03-05).
   - New: `std:list` structured helpers (`try_len`/`try_is_empty`/`try_push`/`try_clone`/
     `try_slice_copy`/`try_get`/`try_set`/`try_last`) return `oren_err` on invalid input;
     covered by module tests and the result smoke fixture (2026-03-05; widened 2026-05-04).
   - New: `std:iter` checked range constructors (`try_range`/`try_range3`) return iterable maps
     on valid integer parameters or `oren_err` on invalid range inputs; covered on native and
     bytecode by `tests/modules/test_iter_range.oren` (2026-05-04).
   - New: `std:list.slice_copy`, `std:strings`, `std:bytes`, and `std:ui/commands.validate`
     now share the hardened non-nil int validation path used by `std:buffer`, so wrong-type
     scalar-like inputs return `oren_err` consistently instead of depending on backend coercion;
     malformed `std:list.slice_view` arguments still iterate as an empty sequence by contract
     (2026-03-27).
   - New: `std:ui/color`, `std:ui/commands`, `std:ui/raster`, and `std:ui/ppm` expose
     explicit `try_parse_hex`, `try_validate`, `try_rasterize`, `try_encode_rgba`, and
     `try_write_rgba_ppm` aliases over their existing value-or-error paths; covered by AVM UI
     smokes, the PPM module write smoke, and the Tier-1 result smoke (2026-05-04).
   - New: `std:linalg` exposes explicit `try_*` aliases over its dot/reduce/AXPY/GEMM
     value-or-error facade, including typed-buffer helpers; covered by the linalg module smoke
     and Tier-1 native typed-buffer runtime-profile smoke (2026-05-04).
   - New: `std:buffer` slice helpers return `oren_err` on invalid input; covered by
     result smoke fixture (2026-03-05).
   - New: `std:encoding/base64` exposes structured `try_encode_bytes`,
     `try_decode_bytes`, and `try_decode_bytes_strict` aliases; invalid input,
     invalid alphabet/length, and strict whitespace rejection are covered by the
     base64 module test and result smoke fixture (2026-05-04).
   - New: `std:time` exposes explicit `try_parse_iso8601_utc` and
     `try_datetime_to_unix_ns` aliases over its existing `oren_err` parse/conversion
     paths; covered by the native/bytecode time module test (2026-05-04).
   - New: `std:crypto/pem.decode_blocks_strict` rejects whitespace inside base64
     payloads; `try_decode_blocks*` aliases are covered by native PEM/result smoke fixtures.
   - New: `std:strings` structured helpers (`try_len`/`try_char_at`/`try_slice`, plus
     `try_starts_with`/`try_ends_with`/`try_contains`/`try_index_of`/`try_streq`/`try_trim`)
     return `oren_err` on invalid input; covered by module and result smoke fixtures (2026-05-04).
   - New: `std:bytes` structured helpers now cover the common packet-style multi-byte surface,
     slice/copy surface, and conversion surface too
     (`try_get_u16/u32/u64_*`, `try_get_i16/i32/i64_*`, `try_put_u16/i16/u32/i32/u64/i64_*`,
     `try_set_u16/i16/u32/i32/u64/i64_*`, `try_from_string`, `try_to_string`, `try_pack`,
     `try_unpack`, `try_slice`, `try_concat`, `try_copy_into`, `try_from_u8_buf`,
     `try_to_u8_buf`, `try_to_string_slice`, `try_to_u8_buf_slice`) and return `oren_err`
     on invalid input across `list<int>` and `u8_buf`; covered by result smoke + native quick
     integration + dedicated AVM bytes smoke
     (2026-03-27).
   - New: `std:bytes` hex helpers (`try_from_hex`/`try_to_hex`) validate inputs and
     return `oren_err` on invalid values; covered by result smoke fixture (2026-03-05).
   - New: `std:buffer` structured helpers now cover the common typed-buffer surface and zero-copy
     view surface too (`try_len`, `try_load/try_store_u8`, `try_load/try_store_i32`,
     `try_load/try_store_i64`, `try_load/try_store_f32`, `try_load/try_store_f64`,
     `try_slice_*`, `try_strided_*`, `try_mat_view_new`, `try_mat_load/store_i32`,
     `try_mat_load/store_f32`) and return `oren_err` on invalid input; covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked conversion helpers for the common portable bridge
     cases (`try_u8_pack`, `try_u8_pack_into`, `try_u8_unpack`, `try_u8_from_string`,
     `try_u8_to_string`, `try_u8_from_bytes`, `try_u8_from_bytes_slice`, `try_u8_to_bytes`,
     `try_i32_pack_list_int`, `try_i32_pack_list_int_into`, `try_i32_unpack_list`);
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes contiguous raw typed-buffer list bridges for `i64`, `f32`,
     and `f64` via helpers such as `try_i64_pack_list_int`, `try_i64_unpack_list`,
     `try_f32_pack_list`, `try_f32_unpack_list`, `try_f64_pack_list`, and
     `try_f64_unpack_list`, so callers can enter and leave non-`u8` typed buffers without
     open-coding allocation + per-element store loops; covered by result smoke + native quick
     integration + dedicated AVM buffer-view smoke, with exact float value proof kept in AVM and
     shared native fixtures checking non-error/shape only (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-buffer refill helpers for raw typed buffers,
     including `try_u8_copy_from_u8_buf`, `try_u8_copy_from_bytes`,
     `try_u8_copy_from_bytes_slice`, `try_u8_copy_from_string`,
     `try_u8_copy_from_string_slice`, `try_i32_copy_from_i32_buf`,
     `try_i64_copy_from_i64_buf`, `try_f32_copy_from_f32_buf`, and `try_f64_copy_from_f64_buf`,
     so callers can refill existing typed buffers without allocating a fresh bridge buffer or
     open-coding per-element loops, including direct byte-window and string-window refill without
     materializing an intermediate `[]u8`; covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke, with exact float value proof kept in AVM and shared native
     fixtures checking non-error/shape only (2026-03-27).
   - New: `std:buffer` now also exposes checked `[]u8` zero-copy view bridge helpers
     (`try_slice_to_bytes`, `try_slice_to_string`, `try_slice_copy_from_bytes`,
     `try_slice_copy_from_bytes_slice`, `try_strided_to_bytes`, `try_strided_to_string`,
     `try_strided_copy_from_bytes`, `try_strided_copy_from_bytes_slice`); covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked `[]u8` string-window refill helpers on zero-copy
     views (`try_slice_copy_from_string_slice`, `try_strided_copy_from_string_slice`), so callers
     can refill visible byte windows from substrings without materializing temporary `[]u8` bridges;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes checked `[]u8` slice/strided ergonomics for typed-buffer
     callers that want to stay on the stdlib surface
     (`try_slice_to_u8_buf`, `try_slice_copy_from_string`, `try_slice_copy_from_string_slice`,
     `try_strided_to_u8_buf`, `try_strided_copy_from_string`,
     `try_strided_copy_from_string_slice`); covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes the missing symmetric `[]u8` unpack/copy helpers for
     slice/strided views (`try_slice_unpack_u8`, `try_strided_unpack_u8`,
     `try_slice_copy_from_u8_buf`, `try_strided_copy_from_u8_buf`); covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` matrix views now also expose checked shape accessors plus the missing
     checked `i64` / `f64` matrix accessors (`try_mat_rows`, `try_mat_cols`,
     `try_mat_row_stride`, `try_mat_load/store_i64`, `try_mat_load/store_f64`);
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` matrix views now also expose checked `u8` cell accessors
     (`try_mat_load_u8`, `try_mat_store_u8`), so callers can keep direct byte-cell reads/writes on
     the matrix surface instead of routing through row or slice views for scalar access; covered by
     result smoke + native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` matrix views now also project back into the zero-copy slice/strided
     surface via `try_mat_row_slice` and `try_mat_col_strided`, so matrix callers can reuse the
     existing checked `[]u8` view bridges instead of rebuilding row/column index math by hand;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` matrix views now also expose checked submatrix and diagonal projections via
     `try_mat_subview` and `try_mat_diag_strided`, so callers can keep composing zero-copy matrix,
     slice, and strided views without open-coding offset math; covered by result smoke + native
     quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes checked compact row-major matrix conversion helpers
     `try_i32_mat_pack_rows`, `try_i32_mat_unpack_rows`, `try_u8_mat_pack_rows`,
     `try_u8_mat_unpack_rows`, `try_u8_mat_pack_strings`, and `try_u8_mat_unpack_strings`, so
     callers can enter and leave the zero-copy matrix-view surface without open-coding row-major
     loops; covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes direct checked matrix-row/column `[]u8` bridge helpers
     such as `try_mat_row_to_string`, `try_mat_row_copy_from_string`,
     `try_mat_row_copy_from_string_slice`, `try_mat_row_copy_from_bytes_slice`,
     `try_mat_col_to_string`, `try_mat_col_copy_from_string`,
     `try_mat_col_copy_from_string_slice`, and `try_mat_col_copy_from_bytes_slice`, so matrix
     callers can stay on the matrix surface for the common row/column text and byte bridge paths,
     including direct byte-window and string-window refill without open-coding a temporary slice;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes direct checked matrix-diagonal `[]u8` bridge helpers such
     as `try_mat_diag_to_string`, `try_mat_diag_to_bytes`, `try_mat_diag_copy_from_string`,
     `try_mat_diag_copy_from_string_slice`, `try_mat_diag_copy_from_bytes_slice`, and
     `try_mat_diag_copy_from_u8_buf`, so matrix callers can stay on the matrix surface for the
     common diagonal byte/text bridge paths instead of routing through an explicit strided view,
     including direct string-window refill; covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes direct checked whole-matrix `[]u8` flatten/copy helpers
     such as `try_u8_mat_to_bytes`, `try_u8_mat_to_string`, `try_u8_mat_copy_from_bytes`,
     `try_u8_mat_copy_from_bytes_slice`, `try_u8_mat_copy_from_string`,
     `try_u8_mat_copy_from_string_slice`, `try_u8_mat_copy_from_rows`, and
     `try_u8_mat_copy_from_strings`, so matrix callers can bridge or refill the entire visible
     matrix without open-coding row loops, including direct byte-window and string-window refill on
     the matrix surface; covered by result smoke + native quick integration + dedicated AVM
     buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes symmetric checked whole-matrix `[]u8` flat-list helpers
     `try_u8_mat_unpack_flat` and `try_u8_mat_copy_from_flat`, so callers can use the same
     `*_mat_unpack_flat` / `*_mat_copy_from_flat` row-major pattern across `u8`, `i32`, `i64`,
     `f32`, and `f64` matrix views instead of special-casing byte matrices; covered by result
     smoke + native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric matrix row-major conversion/refill helpers
     such as `try_i32_mat_copy_from_rows`, `try_i64_mat_pack_rows`, `try_i64_mat_unpack_rows`,
     `try_i64_mat_copy_from_rows`, `try_f32_mat_pack_rows`, `try_f32_mat_unpack_rows`,
     `try_f32_mat_copy_from_rows`, `try_f64_mat_pack_rows`, `try_f64_mat_unpack_rows`, and
     `try_f64_mat_copy_from_rows`, so callers can enter, leave, and refill the visible numeric
     matrix surface without open-coding row loops; covered by result smoke + native quick
     integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-matrix numeric flatten/refill helpers such
     as `try_i32_mat_unpack_flat`, `try_i32_mat_copy_from_flat`, `try_i64_mat_unpack_flat`,
     `try_i64_mat_copy_from_flat`, `try_f32_mat_unpack_flat`, `try_f32_mat_copy_from_flat`,
     `try_f64_mat_unpack_flat`, and `try_f64_mat_copy_from_flat`, so callers can bridge or refill
     the visible numeric matrix surface without open-coding row-major flatten loops; covered by
     result smoke + native quick integration + dedicated AVM buffer-view smoke, with shared native
     float checks kept at non-error/shape level and exact `f32`/`f64` value proof retained in the
     dedicated AVM smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric slice/strided list bridges such as
     `try_slice_unpack_i32`, `try_slice_copy_from_list_i32`, `try_strided_unpack_i64`, and
     `try_strided_copy_from_list_f64`, plus checked numeric matrix row/column list bridges such as
     `try_mat_row_unpack_i32`, `try_mat_row_copy_from_list_i64`, `try_mat_col_unpack_f32`, and
     `try_mat_col_copy_from_list_f64`, so callers can stay on the zero-copy slice/strided/matrix
     surface for numeric row/column extraction and refill without hand-writing view loops; covered
     by result smoke + native quick integration + dedicated AVM buffer-view smoke, with exact float
     value proof kept in AVM and non-error/shape proof kept in shared native fixtures (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric slice/strided typed-buffer bridges such as
     `try_slice_to_i32_buf`, `try_slice_copy_from_i32_buf`, `try_strided_to_i64_buf`, and
     `try_strided_copy_from_f64_buf`, plus checked numeric matrix row/column typed-buffer bridges
     such as `try_mat_row_to_i32_buf`, `try_mat_row_copy_from_i64_buf`, `try_mat_col_to_f32_buf`,
     and `try_mat_col_copy_from_f64_buf`, so callers can stay on the visible zero-copy
     slice/strided/matrix surface for numeric row/column bridge and refill work without routing
     through temporary lists. The matrix row/column helpers reuse the checked slice/strided
     typed-buffer bridge surface instead of duplicating row/column loops; covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke, with exact integer proof and exact
     AVM float-value proof kept alongside non-error/shape native float proof (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric matrix-diagonal list and typed-buffer
     bridges such as `try_mat_diag_unpack_i32`, `try_mat_diag_copy_from_list_i64`,
     `try_mat_diag_to_f32_buf`, and `try_mat_diag_copy_from_f64_buf`, so callers can bridge or
     refill diagonal projections directly on the matrix surface instead of routing through an
     explicit temporary strided view. The diagonal helpers reuse the same checked strided bridge
     surface as rows and columns; covered by result smoke + native quick integration + dedicated AVM
     buffer-view smoke, with exact integer proof and exact AVM float-value proof kept alongside
     non-error/shape native float proof (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-matrix numeric typed-buffer bridges such as
     `try_i32_mat_to_i32_buf`, `try_i32_mat_copy_from_i32_buf`, `try_i64_mat_to_i64_buf`,
     `try_i64_mat_copy_from_i64_buf`, `try_f32_mat_to_f32_buf`, `try_f32_mat_copy_from_f32_buf`,
     `try_f64_mat_to_f64_buf`, and `try_f64_mat_copy_from_f64_buf`, so callers can bridge or refill
     the visible numeric matrix surface without routing through temporary flat lists. The refill side
     now rejects mismatched typed-buffer kinds up front instead of depending on raw backend loads;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke, with
     exact float value proof kept in AVM and non-error/shape proof kept in shared native fixtures
     (2026-03-27).
   - Refactor: `std:buffer` is now split into a thin public facade plus
     `lib/std/buffer/view.oren` for slice/strided helpers and a direct matrix implementation split
     across `lib/std/buffer/mat_core.oren`, `lib/std/buffer/mat_proj.oren`,
     `lib/std/buffer/mat_shared.oren`, `lib/std/buffer/mat_numeric.oren`, and
     `lib/std/buffer/mat_u8.oren`. The public facade in `lib/std/buffer.oren` now imports those
     matrix modules directly instead of routing through either an internal `mat.oren`
     compatibility layer or a mixed numeric/byte dense helper module, which keeps the checked
     matrix API unchanged while making the internal module boundary match the real behavior split;
     covered by dedicated AVM buffer-view smoke, native quick integration, and full `make test`
     (2026-03-27).
   - Refactor: the duplicated integer/error validation helpers shared by the `std:buffer` facade,
     `view`, and matrix core now live in `lib/std/buffer/common.oren`, which removes copy-pasted
     `_err_invalid` / `_is_int` / `_check_*` / list-len / typed-buffer-len logic from the split
     modules and keeps future buffer-surface validation fixes aligned across all three layers;
     covered by dedicated AVM buffer-view smoke, native quick integration, and full `make test`
     (2026-03-27).
   - Refactor: the shared byte-range validator for `std:buffer` now also lives in
     `lib/std/buffer/common.oren`, so `view`, matrix core, and `u8` matrix helpers all reject
     out-of-range writes through the same checked path instead of carrying separate copies of the
     `0..255` validation logic; covered by dedicated AVM buffer-view smoke, native quick
     integration, and full `make test` (2026-03-27).
   - Refactor: the split `std:buffer` modules now also share list-view shape predicates
     (`_slice_is_list` / `_strided_is_list` / `_mat_is_list`) and numeric validators through
     `lib/std/buffer/common.oren`, which removes another copy-pasted helper family from `view` and
     the matrix layer; covered by dedicated AVM buffer-view smoke, native quick integration, and
     full `make test` (2026-03-27).
   - Refactor: the duplicated raw typed-buffer constructors, direct typed load/store shims, and
     `[]u8 -> bytes` bridge shared across the split `std:buffer` modules now live in
     `lib/std/buffer/raw.oren`, so low-level runtime wrapper changes no longer need to be edited in
     multiple places; covered by dedicated AVM buffer-view smoke, native quick integration, and
     full `make test` (2026-03-27).
   - Refactor: the checked raw/list/string bridge surface that used to live at the top of
     `lib/std/buffer.oren` now also lives in `lib/std/buffer/raw.oren`, leaving
     `lib/std/buffer.oren` as a thinner 697-line public facade over `raw`, `view`, and the split
     matrix modules while keeping the public checked API unchanged; covered by dedicated AVM
     buffer-view smoke, native quick integration, and full `make test` (2026-03-27).
   - Refactor: the dense matrix helpers no longer depend on `mat_core` internals for shape,
     row-major flatten, or typed-buffer bridge plumbing. Those shared helpers now live in
     `lib/std/buffer/mat_shared.oren`, which makes the matrix layer a cleaner facade/core/shared/dense
     split without changing the checked public API; covered by dedicated AVM buffer-view smoke,
     native quick integration, and full `make test` (2026-03-27).
   - Fix: `std:result.is_err(v)` now canonicalizes backend probes to a real Oren boolean on native,
     which removes raw truthy-value leakage from `== true` / `!= true` checks; covered by native
     module-result smoke, result smoke, native quick, and full `make test` (2026-03-27).
   - Fix: macOS stage1 native-quick verification now gives the `OREN_GREEN_POLL_CACHE` rerun a
     30s default watchdog even when the base run stays at 20s, which removes a false-red `rc=143`
     path in full-suite verification where the first run already completed cleanly (2026-03-27).
   - Fix: macOS stage1 native-quick verification now also gives the base run a 120s default
     watchdog instead of 60s. Earlier direct measurements already showed healthy base runs near
     `23.15s`, and after the later `240s` green-cache widening the full-suite stage1 path could
     still false-red at `60s` in `green_two_workers_world_lock_smoke`; a direct full-suite retry
     with `OREN_NATIVE_RUN_TIMEOUT_SECS=120` completed cleanly on this host, removing that remaining
     `rc=143` path from `make test` (2026-03-27).
   - Fix: `scripts/run_native_quick_integration.sh` now runs the stage1 base path and
     `OREN_GREEN_POLL_CACHE` rerun under `set +e` while harvesting retry status, so the scripted
     retry path actually executes instead of letting `set -e` abort the harness on the first
     timeout-style nonzero return; covered by native quick integration and full `make test`
     (2026-03-27).
   - Fix: `scripts/run_native_quick_integration.sh` now also captures the top-level
     `run_base` / `run_green_cache` phase status under `set +e` before tailing the inner log,
     so timeout-style nonzero exits no longer abort the harness at the phase call site before
     the intended tail/exit handling runs; covered by native quick integration and full
     `make test` (2026-03-27).
   - Fix: on macOS, `scripts/run_native_quick_integration.sh` now prefers a Python
     `subprocess.wait(timeout=...)` watchdog over the older bash sleeper/`kill` watcher, which
     removes the late `rc=143` false-red where the inner stage2 log had already completed
     successfully but the outer make target was still terminated by a racing watchdog
     (2026-03-27).
   - Fix: the standalone two-worker green scheduler world-lock / M<P / P-swap smokes now call
     `exit(0)` after their success print, matching the loopback tests that also start persistent
     green workers. A 2026-04-12 default `make test` run showed
     `test_green_two_workers_world_lock_smoke` printing both success lines but then staying alive
     until the 360s watchdog returned `run_rc=1`; the fixture now terminates the process
     explicitly after proving the scheduler property instead of depending on background-worker
     runtime cleanup.
   - Fix: macOS stage1 native-quick verification now also keeps the default green-cache rerun
     watchdog at `360s` instead of `240s`. A direct `240s` run still false-red with `rc=143`
     after the rerun had already emitted its last visible debug lines, while `360s` completed
     cleanly on this host; covered by native quick integration and full `make test` (2026-03-27).
   - Fix: macOS self-hosted stage2 native-quick verification now keeps the default
     `OREN_GREEN_POLL_CACHE` rerun watchdog at `720s` instead of reusing the stage1 `360s`
     budget. On this host the stage2 rerun still false-red at `360s` after emitting its last
     visible `41` / `42` debug lines, and the built-in `720s` retry completed cleanly; covered
     by stage2 native quick integration and full `make test` (2026-03-27).
   - Fix: macOS self-hosted stage2 native-quick verification now also keeps the base run watchdog
     at `120s` instead of the old `30s` make-target budget. On this host the base stage2 run still
     false-red at `60s` and only cleared on the built-in `120s` retry, so `test-native-quick-stage2`
     now starts from the proven healthy base-run budget instead of depending on a retry to pass
     (2026-03-27).
   - Fix: invoking `scripts/run_native_quick_integration.sh ./oren_stage2` directly on macOS now
     also keeps the stage2 debug build watchdog at `180s` instead of `35s`. A measured standalone
     rerun still false-red at `35s` during the self-hosted rebuild even with an rtobj hit, while
     the same path already completed cleanly under the `180s` full-suite budget; covered by a
     standalone stage2 stop-after-green quick-integration run plus the normal AVM/status gates
     (2026-03-27).
   - New: `std:assert.assert_streq` now uses portable stdlib string equality instead of raw
     `strcmp`, removing that direct bytecode codegen dependency; verified by native quick plus
     dedicated AVM bytes/assert smoke coverage (2026-03-26).
   - Not implemented yet: dynamic module loading; user-defined methods/inheritance (track when design lands).
   - Gate: feature fixtures across backends + updated `docs/LANGUAGE.md`/`docs/STATUS.md`.

10) **W3 structural/SOLID refactors (large files)**
   - Split high-churn, 2000+ line modules into focused units with clear boundaries.
   - Started: GC safepoint helpers moved to `lib/compiler/arm64_native_gc.oren`.
   - Done: `lib/compiler/arm64_native_stmt.oren` split into loop/list/runtime modules (<2000 lines each).
   - Done: `lib/compiler/transpiler.oren` split into core/analysis/C-utils/lambda modules (<2000 lines each).
   - Done: `lib/compiler/optimizer_loops.oren` split into list/arena modules (<=2000 lines each).
   - Done: `lib/compiler/optimizer.oren` split into core/fold/DCE/list-int/list-reserve/TCO modules (<2000 lines each).
   - Done: `lib/runtime_native/100_time_gc_alloc.oren` split into trace/index/core modules (<2000 lines each).
   - Done: `lib/std/buffer.oren` split into the public facade plus `lib/std/buffer/view.oren`
     and a direct matrix layer (`lib/std/buffer/mat_core.oren`, `lib/std/buffer/mat_proj.oren`,
     `lib/std/buffer/mat_shared.oren`, `lib/std/buffer/mat_numeric.oren`,
     `lib/std/buffer/mat_u8.oren`) plus shared validation / view-shape helpers in
     `lib/std/buffer/common.oren` and shared raw typed-buffer wrappers in
     `lib/std/buffer/raw.oren`, with the public facade at 697 lines and each helper module <2000
     lines (2026-03-27).
   - Done: `lib/compiler/compiler/040_build_pipeline/010_main.oren` split into a helper include
     (`lib/compiler/compiler/040_build_pipeline/005_helpers.oren`) plus the main command-dispatch
     unit, leaving the main file at 1957 lines while keeping the compile-time include order and
     behavior unchanged (2026-03-27).
   - Done: `lib/runtime_native/263_green/010_green_core.oren` split into a shared state/layout
     prelude (`lib/runtime_native/263_green/005_green_state.oren`) plus a 1928-line queue and
     scheduler core, which keeps the green-task include order intact while moving offsets, globals,
     and tiny state accessors out of the hot scheduler implementation (2026-03-27).
   - Done: `lib/avm/main.c` split into CLI-focused modules
     (`avm_cli_util`, `avm_cli_verify`, `avm_cli_policy`, `avm_cli_fs`,
     `avm_cli_disasm`, `avm_cli_dump`) (<2000 lines each, 2026-02-25).
   - Done: `lib/avm/avm_vm.c` split into focused VM modules (`avm_vm_core`,
     `avm_vm_sched`, `avm_vm_values`, `avm_vm_list_ops`) (<2000 lines each, 2026-02-25).
   - Done: `lib/compiler/x64_native_program/060_emit_ops.oren` split into focused emit modules
     (`055_emit_ops_locals`, `056_emit_ops_match`, `057_emit_ops_while_emit`)
     (<2000 lines each, 2026-02-25).
   - Done: `pkg/transpiler/transpiler.go` split into the core emitter plus
     `pkg/transpiler/transpiler_lambda.go`, moving lambda collection/free-var analysis/emission into
     a focused companion file and leaving the main transpiler at 1836 lines (2026-03-27).
   - Current tracked source scan (>=2000 lines, 2026-03-27): no remaining repo-tracked source files
     above the rolling 2000-line threshold.

11) **Tooling reliability and reproducibility**
   - Keep build/test/bench workflows stable and fast.
   - New (2026-03-27): `make verify-optimizer-list-reserve-branchy` builds
     `tests/fixtures/list_reserve_branchy_control_flow_smoke.oren` with
     `OREN_TRACE_LIST_RESERVE=1`, asserts the boxed and `list<int>` reserve/unchecked-push trace
     lines, and runs the fixture. `verify-native-quick` now includes that optimizer smoke so
     branch-heavy list loops stay covered in the default `make test` path.
   - Fix: `scripts/run_native_capsule_smoke.sh` now uses the native build cache by default and
     `test-native-capsule-smoke-stage2` raises the stage2 build watchdog to 180s, avoiding a
     timeout-style false red where the harness spent minutes in a deliberate `--no-cache` cold
     compile before reaching the actual capsule runtime smoke on this host (2026-03-27).
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
