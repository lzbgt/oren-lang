# Repo Inspection Notes - 2026-04-04

## Scope

Inspected the repo structure, top-level docs, Makefile verification targets, and the fast readiness/doc tooling.

## Facts established from code + docs

- The repo is still explicitly in rolling mode. `docs/STATUS.md` and `docs/LANGUAGE.md` both state that several planned features are not implemented yet, including:
  - stackless coroutines / `yield`
  - structured error model
  - visibility boundaries
  - first-class bytes + typed buffers as a fully mature language surface
  - dynamic module loading
  - user-defined methods
  - production-grade native GMP/netpoller across Tier-1
  - compiler-in-AVM
- The repo-local project instructions in [AGENTS.md](/Users/zongbaolu/work/compiler-mini/AGENTS.md) standardize on `./oretest` as the default fast path, but the repository did not ship that entrypoint before this change.
- Git history confirms this was real drift, not guesswork:
  - `oretest` existed as a dedicated Go runner under `cmd/oretest/`.
  - It was removed in commit `e1f6922ab11613607abb14a4f8349c55f0e4c510` on 2026-01-03.
  - The repo-local instructions continued to reference `./oretest` after that removal.
- The current quick verification surface in [Makefile](/Users/zongbaolu/work/compiler-mini/Makefile) is centered on:
  - `make test` -> `verify-native-quick`
  - `make verify-native-quick-gc`
  - `make verify-backend-parity`
  - `make test-avm`
  - `make verify-readiness-pipeline`
  - `make test-native-all`

## Changes made in this pass

- Added a repo-root `./oretest` wrapper so the documented/expected fast path actually exists.
- Wired `./oretest` to existing high-signal verification targets instead of inventing new test logic.
- Added support for:
  - `--jobs` / `OREN_TEST_JOBS`
  - `--native-jobs` / `OREN_TEST_NATIVE_JOBS`
  - `--fixture-jobs` / `OREN_TEST_FIXTURE_JOBS`
- Follow-up adjustment after checking the deleted Go runner:
  - historical `oretest` default was a smaller fast suite, not the modern `make test` bundle
  - the restored wrapper now defaults to `make test-native-quick`
  - stage2/capsule/optimizer moved behind explicit `--selfhost`
  - `--full` now includes that selfhost bundle plus the wider optional suites
- Follow-up adjustment after checking the top-level Makefile target:
  - `make test` had drifted to `verify-native-quick`, which made the documented fast path take about 333s on this host
  - `make test` now maps back to the fast stage1 quick smoke (`test-native-quick`)
  - `make test-selfhost` now names the heavier stage2/capsule/optimizer bundle explicitly
- Updated [README.md](/Users/zongbaolu/work/compiler-mini/README.md) and [docs/README.md](/Users/zongbaolu/work/compiler-mini/docs/README.md) so the quick-start docs match the actual repo entrypoints.
- Follow-up native hot-loop pass (2026-04-04):
  - traced the direct-slot `list<int>` probe boundary against the real benchmark artifacts instead of assuming the old helper-path measurements still held
  - confirmed the packed `list<int> -> []i32` bridge is still the wrong direction for current 64-bit slot payloads
  - added native call-site intrinsics for `oren_list_int_reduce_sum_slots_unchecked` and `oren_list_int_dot_slots_unchecked` on both arm64 and x64, so those hidden raw-slot probes now inline their loops instead of paying the old generic helper-path cost
  - kept semantics explicit:
    - reduce-sum unchecked: `nil -> 0`
    - dot unchecked: both `nil -> 0`; one `nil` or length mismatch panics with `list_int_dot_slots_unchecked: length mismatch`
  - verified the new code path with:
    - `make -j1 oren_stage2`
    - `./scripts/verify_native_list_int_fast_lowering.sh`
    - `make test`
    - forced direct-slot perf rerun via `OREN_PERF_PREBUILD_FORCE=1 ./scripts/run_perf_probe_list_int_slot_direct.sh`
  - measured result from `build/logs/perf-probe-list-int-slot-direct-20260404_200234.log`:
    - canonical steady baseline on the same sweep: `array_sum_int` ~2.3090× C, `dot_product_int` ~2.9950× C
    - hidden direct-slot probe after the new call-site intrinsics: `array_sum_int_slot_direct` ~15.1069× C, `dot_product_int_slot_direct` ~5.1760× C
  - conclusion: the new call-site lowering materially reduced the pathological dot-product direct-slot gap, but the unchecked helper-backed probe still trails the canonical fast loops and should remain a probe/targeted intrinsic surface rather than the default general lowering
- Follow-up slot-direct contract pass (2026-04-04):
  - extended the existing slot-direct verify surface instead of adding a disconnected one-off check
  - `make verify-native-slot-direct` now also builds `tests/fixtures/list_int_slot_direct_contracts.oren`
    and checks:
    - unchecked nil behavior stays zero-returning for reduce-sum and `(nil, nil)` dot
    - unchecked dot mismatch cases still panic with `list_int_dot_slots_unchecked: length mismatch`
  - also promoted the same unchecked-nil assertions into:
    - [tests/fixtures/tier1_native_result_smoke_main.oren](/Users/zongbaolu/work/compiler-mini/tests/fixtures/tier1_native_result_smoke_main.oren)
    - [tests/native/qi/100_tests_basic.oren](/Users/zongbaolu/work/compiler-mini/tests/native/qi/100_tests_basic.oren)
  - this closes the main correctness blind spot left by the earlier call-site intrinsic change: the new native lowering path now has explicit edge-contract coverage, not just benchmark-output coverage
- Follow-up perf snapshot refresh (2026-04-04):
  - reran the canonical perf gates directly instead of relying on stale tracker text:
    - `make perf-gate-native`
    - `make perf-gate-list-int`
    - `make perf-gate-list-int-steady`
  - refreshed the benchmark snapshot and tracker docs to the measured April results:
    - canonical hot-loop gate: `loop_sum` 1.09× C, `dot_product` 2.82× C
    - allocation gate: `alloc_churn` 5.42× C, `alloc_drop` 1.76× C
    - focused one-shot `list<int>` gate: `array_sum_int` 2.07× C, `dot_product_int` 2.59× C, `multi_list_push_int` 2.24× C
    - focused steady `list<int>` gate: `array_sum_int` ~2.43× C, `dot_product_int` ~2.78× C
  - conclusion from the refreshed numbers:
    - the formal remaining perf blocker is still canonical arm64 `dot_product` above the <=2× gate
    - the focused `dot_product_int` steady tracker is better than the older ~3.09× reading, but it still points at the same read-heavy dot loop as the next high-leverage target
- Follow-up canonical lowering guard pass (2026-04-04):
  - verified directly that the canonical W5 benchmark sources already auto-specialize onto the fast
    `list<int>` path on the local arm64 and x64 backends:
    - `benchmarks/array_sum/array_sum.oren`
    - `benchmarks/dot_product/dot_product.oren`
  - extended `make verify-native-list-int-fast-lowering` so those canonical benchmark shapes are now
    covered by the automated lowering guard, not just the explicit `array_sum_int` /
    `dot_product_int` benchmark variants
  - this removes a lingering ambiguity in the perf tracker: if canonical `dot_product` remains slow,
    it is because the existing fast `list<int>` dot loop still needs work, not because the benchmark
    silently fell off the intended lowering path
- Follow-up arm64 tick-mask tuning pass (2026-04-04):
  - added compiler-env tick-mask parsing in the shared arm64 GC helper so the native fast-loop
    emitters can be tuned without source edits:
    - `OREN_ARM64_FAST_LIST_{GET_SUM,DOT,PUSH}_TICK_MASK`
    - `OREN_ARM64_FAST_LIST_INT_{GET_SUM,DOT,PUSH}_TICK_MASK`
    - `OREN_ARM64_FAST_LCG_SUM_TICK_MASK`
  - those overrides accept decimal `0..65535`; invalid input falls back to the emitter default
  - fixed a real emitter inconsistency found during that pass: arm64 `fast_list_int_push_while`
    previously called the inline safepoint helper without initializing X10 on loop entry
  - added a reproducible probe target:
    - `make perf-probe-arm64-fast-loop-tick-masks`
  - verified the code path with:
    - `./scripts/verify_native_list_int_fast_lowering.sh`
    - `make test`
    - `make perf-probe-arm64-fast-loop-tick-masks`
  - measured result from `build/logs/perf-probe-arm64-fast-loop-tick-masks-20260404_205632.log`:
    - baseline: `array_sum` ~2.2145x C, `dot_product` ~2.9293x C
    - `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383`: effectively unchanged (`array_sum` ~2.2145x C, `dot_product` ~2.9293x C)
    - `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=65535`: modest directional improvement (`array_sum` ~2.0713x C, `dot_product` ~2.8584x C)
  - conclusion: keep the shipped arm64 `list<int>` dot tick mask at `4095` for now; the new tuning
    surface is useful for measurement, but the observed win is too small to treat as a settled
    production default change yet
- Follow-up canonical native split pass (2026-04-04):
  - aligned the benchmark surfaces first instead of trusting a mixed-workload split:
    - `benchmarks/array_sum/array_sum.oren`
    - `benchmarks/dot_product/dot_product.oren`
    - `benchmarks/array_sum/array_sum.c`
    - `benchmarks/dot_product/dot_product.c`
    now all accept the same optional `n` + `reps` CLI args
  - added a dedicated runner:
    - `make perf-gate-native-read-split`
  - this runner reuses the existing canonical benchmark sources and reports `reps=1` vs `reps=10`
    so the split compares the same workload across C/native rather than a repeated native loop
    against a fixed C baseline
  - verified with:
    - `make perf-gate-native-read-split`
    - `make test`
  - measured result from `build/logs/perf-gate-native-read-split-20260404_210513.log`:
    - `array_sum`: native/C long-per-rep ~1.4403x, delta estimate ~0.9590x
    - `dot_product`: native/C long-per-rep ~2.5894x, delta estimate ~2.4758x
  - conclusion: the remaining canonical `dot_product` blocker is still in the steady read/multiply
    loop body, not in the one-time list fill/setup half; `array_sum` steady read is already much
    closer to parity
- Follow-up canonical native smoke + steady pass (2026-04-04):
  - added a direct native correctness gate for the same canonical benchmark binaries:
    - `make perf-smoke-native-fast-loops`
  - added a dedicated direct steady-state runner:
    - `make perf-gate-native-steady`
  - while verifying that batch, found and fixed a real tooling bug in the newly added probe/smoke
    scripts: second-resolution timestamps could collide when multiple runs started in the same
    second, so the new scripts now suffix log names with `$$`
  - verified with:
    - `make perf-smoke-native-fast-loops`
    - `make perf-gate-native-steady`
    - `make test`
  - measured result from `build/logs/perf-gate-native-steady-20260404_211102_35559.log`:
    - `array_sum`: native/C steady ~2.3967x
    - `dot_product`: native/C steady ~3.1027x
  - conclusion: the earlier split runner was useful to localize the problem to the steady body, but
    the new steady runner is the right tracker surface. On the canonical arm64 path, `dot_product`
    is still materially above target even after fill/setup noise is removed

## Production-level reality after this pass

This repo is still not factually "all planned features implemented" or "production level" across the full language/runtime surface. The authoritative blockers remain the ones already documented in [docs/STATUS.md](/Users/zongbaolu/work/compiler-mini/docs/STATUS.md), especially:

- semantic parity convergence
- runtime robustness under GC/reuse/concurrency stress
- full Tier-1 platform maturity
- production-grade async/native GMP
- planned language features that are still marked unimplemented

## Recommended next work

- Keep `./oretest` as the standard local gate and extend it only when the underlying `make` targets are stable enough to compose.
- Continue treating `docs/STATUS.md` as the production-readiness source of truth instead of overstating maturity in user-facing docs.
- If the goal is "production level" in the stricter sense, the next work should target one W4/W5 blocker from `docs/STATUS.md` and close it with code + fixtures + readiness updates, not broad marketing/documentation changes.
- After the native hot-loop and perf-refresh follow-ups above, the next high-leverage item is narrower than before: reduce the remaining canonical arm64 `dot_product` gap toward the existing <=2x gate, while continuing to use the focused `dot_product_int` steady runner as the more local diagnostic view and without routing general `list<int>` loops through the helper probe path.
- The new arm64 tick-mask probe can stay as the first sanity check for future dot-loop work, but the
  April 4 data says safepoint cadence alone is not enough to close the remaining canonical gap.
- The new canonical split runner now makes the next optimization target clearer too: for arm64
  `dot_product`, attack the steady dot core first and treat fill/setup work as secondary.
- The new canonical native smoke should be the first correctness check before any further arm64
  dot-core experiment, because it exercises the exact benchmark binaries rather than only the
  generalized list-int lowering guard.
