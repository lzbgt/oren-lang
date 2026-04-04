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
