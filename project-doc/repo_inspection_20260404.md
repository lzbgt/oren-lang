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
- Specialization-gap probe correction + follow-ups (2026-04-05):
  - fixed `make perf-probe-list-int-specialization-gap` so the generic side uses
    `OREN_BENCH_NATIVE_STEADY_*` instead of mistakenly reusing the `list<int>` steady vars
  - corrected steady artifact: `build/logs/perf-probe-list-int-specialization-gap-20260405_025957_59475.log`
    (`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=1`, `n=200000`, `reps=10`)
    - `array_sum`: generic `~1.3419× C`, specialized `~1.4064× C`, gap `~0.9541×`
    - `dot_product`: generic `~1.5169× C`, specialized `~1.4803× C`, gap `~1.0247×`
  - new read-split artifact: `build/logs/perf-probe-list-int-specialization-read-split-20260405_030027_60451.log`
    - reliable `long_per_rep` view stays near parity:
      - `array_sum`: generic `~1.5652× C`, specialized `~1.4639× C`, gap `~1.0692×`
      - `dot_product`: generic `~1.5241× C`, specialized `~1.5157× C`, gap `~1.0055×`
    - the delta estimate is noisy on the specialized side and already warns to prefer `long_per_rep`
  - new trace artifact: `build/logs/perf-probe-list-int-specialization-trace-20260405_025957_59477.log`
    - generic `array_sum`: `list_int rewrite init name=xs`
    - generic `dot_product`: `list_int rewrite init name=a` and `name=b`
    - explicit `array_sum_int` / `dot_product_int`: already begin as `oren_new_list_int` candidates
  - conclusion: the old “generic benchmark shape is the main blocker” attribution was a probe bug.
    The generic sources are already being rewritten into the intended `list<int>` form, and the
    aligned steady/read-split probes put generic and explicit `list.int_*` near parity. The next
    work should move back to the steady-state hot path versus the C/NEON baseline.
- Scalar-ceiling follow-up (2026-04-05):
  - fixed a helper bug in `make perf-probe-arm64-dot-vs-c-loop-compare` so comma-separated
    `OREN_BENCH_ENV_BUILD_OREN` values now reach the traced Oren build correctly
  - added `make perf-probe-arm64-dot-vs-c-scalar-ceiling` to time the exact Oren native
    `dot_product` benchmark binary against both vectorized and de-vectorized host-C builds of the
    same source
  - latest artifact: `build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260405_030703_69836.log`
    - vectorized C per-rep: `~0.000264s`
    - scalar C per-rep: `~0.000743s`
    - Oren native per-rep: `~0.000781s`
    - scalar/vector ratio: `~2.8153×`
    - Oren/scalar ratio: `~1.0517×`
    - Oren/vector ratio: `~2.9609×`
  - conclusion: the remaining arm64 `dot_product` gap is overwhelmingly the missing NEON/vector
    path. Oren is already within about 5% of scalar C on the same host/source/workload, so more
    scalar micro-tuning is unlikely to buy another ~3×.
- Follow-up helper ceiling probe (2026-04-05):
  - closed the remaining helper-path tooling mismatch:
    - `build_perf_artifacts_list_int_packed_bridge.sh`
    - `build_perf_artifacts_list_int_slot_direct.sh`
    - `make perf-smoke-list-int-packed-bridge`
    - `make perf-smoke-list-int-slot-direct`
    all now honor `OREN_BENCH_ENV_BUILD_OREN`, and the hidden packed-bridge / slot-direct steady
    probe summaries now record the active `build_env`
  - added `make perf-probe-list-int-dot-ceiling` as one fast ranking surface for the current
    `list<int>` dot alternatives
  - latest artifact: `build/logs/perf-probe-list-int-dot-ceiling-20260405_024559_38593.log`
    (`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=2 warmups=0 n=20000 reps=2`)
	- canonical `dot_product_int`: ~1.2137× C
	- direct-slot helper `dot_product_int_slot_direct`: ~1.5149× C
	- packed-bridge SIMD `dot_product_int_packed_bridge`: ~565.8124× C
	- packed-bridge scalar `dot_product_int_packed_bridge`: ~1382.0339× C
  - conclusion: the current helper/bridge detours are not close to the shipped fast loop, so the
    next productive parity work should stay on compiler fast-loop lowering and/or representation
    changes, not on repackaging list data through the existing packed bridge
- Packed-bridge read-split attribution follow-up (2026-04-05):
  - added `make perf-probe-list-int-packed-bridge-read-split`
  - latest artifact: `build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_032402_91481.log`
    (`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`)
    - baseline canonical `dot_product_int`: ~1.3378× C long-per-rep
    - packed-bridge SIMD `dot_product_int_packed_bridge`: ~549.8375× C long-per-rep
    - packed-bridge scalar `dot_product_int_packed_bridge`: ~1037.5886× C long-per-rep
  - conclusion: even after an explicit warm step and a short/long split that isolates repeated
    reads, the current packed bridge remains hundreds of times slower than the direct lowering; it
    is not just paying a one-time setup penalty
- Slot-ABI ceiling follow-up (2026-04-05):
  - added `make perf-probe-list-int-slot-abi-ceiling`
  - latest artifact: `build/logs/perf-probe-list-int-slot-abi-ceiling-20260405_033149_3497.log`
    (`runs=5 warmups=1 n=2000000 reps=100`)
    - packed-i32 C vector: ~0.000252s per rep
    - packed-i32 C scalar: ~0.000731s per rep
    - slot64 C “vector”: ~0.000725s per rep
    - slot64 C scalar: ~0.000741s per rep
    - Oren native canonical: ~0.000762s per rep
    - Oren native slot-direct helper: ~0.003228s per rep
  - conclusion: the current 64-bit slot ABI itself largely erases the host compiler’s
    auto-vectorization gain; packed-i32 C stays ~2.87× faster than slot64 C, and the shipped Oren
    canonical loop is already within ~5% of that slot64 host-C ceiling
- Packed-SIMD reuse follow-up (2026-04-05):
  - added `make perf-probe-list-int-packed-bridge-simd-reuse`
  - latest artifact: `build/logs/perf-probe-list-int-packed-bridge-simd-reuse-20260405_033734_11943.log`
    (`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=20000 short_reps=1 long_reps=10`)
    - baseline canonical `dot_product_int`: ~0.000331s native long-per-rep
    - packed-SIMD `dot_product_int_packed_bridge`: ~0.266698s native long-per-rep
  - conclusion: even the strongly amortized packed-SIMD reuse case is still ~805.7× slower than the
    shipped canonical loop; the packed bridge is not a viable near-term parity path
- Guarded `[]i32` dot benchmark + focused reuse follow-up (2026-04-05):
  - updated hidden benchmark pair `benchmarks/dot_product_i32_buf/dot_product_i32_buf.{oren,c}` so
    lane `0` is perturbed across `reps` and every repetition result is accumulated, preventing the
    repeated dot from being trivially hoisted
  - reran `make perf-probe-list-int-i32-buf-dot-ceiling`
  - latest full-process artifact: `build/logs/perf-probe-list-int-i32-buf-dot-ceiling-20260405_040717_51202.log`
    (`runs=3 warmups=0 n=20000 reps=20`)
    - packed-i32 C vector: ~0.000145s per rep
    - Oren `dot_product_i32_buf` SIMD: ~0.002043s per rep
    - warning emitted: probe is setup-mixed
  - added `make perf-probe-list-int-i32-buf-simd-reuse`
  - latest focused artifact: `build/logs/perf-probe-list-int-i32-buf-simd-reuse-20260405_040936_54584.log`
    (`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=200000 short_reps=1 long_reps=1000`)
    - packed-i32 C vector: `setup≈0.002528s`, `delta≈0.000018s`
    - Oren `dot_product_i32_buf` SIMD: `setup≈0.374950s`, `delta≈0.000024s`
    - repeated-kernel delta ratio: ~1.3562x
    - whole-process long-per-rep ratio: ~19.7021x
  - corrected conclusion: the repeated SIMD kernel is much closer to packed-i32 C than the previous
    full-process ceiling implied; the dominant remaining cost is fixed typed-buffer setup / runtime
    boundary overhead, not a SIMD dot core that is still ~14x behind
- Typed-buffer setup breakdown follow-up (2026-04-05):
  - added hidden fill-only benchmark pair:
    - `benchmarks/fill_i32_buf/fill_i32_buf.oren`
    - `benchmarks/fill_i32_buf/fill_i32_buf.c`
  - added `make perf-probe-list-int-i32-buf-setup-breakdown`
  - latest artifact: `build/logs/perf-probe-list-int-i32-buf-setup-breakdown-20260405_042115_69806.log`
    (`runs=3 warmups=0 n=200000 short_reps=1 long_reps=1000`)
    - fill-only C: ~0.002515s
    - fill-only Oren `[]i32`: ~0.372046s
    - packed-i32 C vector setup: ~0.002991s
    - Oren `dot_product_i32_buf` SIMD setup: ~0.375121s
    - Oren fill share of Oren SIMD setup: ~99.18%
    - Oren residual setup beyond fill: ~0.003075s
  - corrected conclusion: the fixed typed-buffer wall-time gap is now almost entirely the
    allocation + checked per-element fill phase. The repeated SIMD kernel is not the main blocker,
    and neither is a large hidden post-fill runtime-call boundary.
- Fill-shape follow-up (2026-04-05):
  - added hidden helper-based unchecked fill benchmark:
    - `benchmarks/fill_i32_buf_unchecked/fill_i32_buf_unchecked.oren`
  - added hidden pointer-hoisted fill benchmark:
    - `benchmarks/fill_i32_buf_ptr/fill_i32_buf_ptr.oren`
  - added hidden pointer-hoisted + uninitialized fill benchmark:
    - `benchmarks/fill_i32_buf_ptr_uninit/fill_i32_buf_ptr_uninit.oren`
  - added `make perf-probe-list-int-i32-buf-unchecked-fill`
  - latest artifact: `build/logs/perf-probe-list-int-i32-buf-unchecked-fill-20260405_044149_1286.log`
    (`runs=3 warmups=0 n=200000`)
    - checked fill: ~0.376955s
    - unchecked helper fill: ~0.367594s
    - pointer-hoisted fill: ~0.344940s
    - pointer-hoisted + uninitialized fill: ~0.207338s
    - unchecked helper speedup: ~1.0255x
    - pointer-hoisted speedup: ~1.0928x
    - pointer-hoisted + uninitialized speedup: ~1.8181x
  - corrected conclusion: removing only the per-call checked helper is a small win, pointer hoisting
    is better, and skipping the eager zero-fill before a proven full overwrite is the first large
    reduction on the typed-buffer setup path
  - production follow-up kept in the same batch: native `oren_buf_fill_i32/i64/f32/f64` now hoist
    `native_buf_data_ptr(buf)` and write bytes directly instead of re-entering the checked
    element-store helper on every iteration
  - follow-up production use (2026-04-05):
    - shared fresh-`i32` conversion surfaces now use the same measured lever where safety is provable:
      `buffer.i32_pack_list_int`, `buffer.try_slice_to_i32_buf`,
      `buffer.try_strided_to_i32_buf`, `buffer.i32_mat_pack_rows`, and
      `buffer.i32_mat_to_i32_buf` now allocate via `oren_i32_buf_new_uninit(...)` and fill via
      unchecked direct stores only when the fresh buffer is fully overwritten before successful return
    - the C backend now exports a conservative `oren_i32_buf_new_uninit` shim so these shared stdlib
      paths remain link-safe even though only the native backend gets the uninitialized-allocation win
  - latest direct-path ranking artifact:
    - `build/logs/perf-probe-list-int-dot-ceiling-20260405_223926_17836.log`
    - baseline `dot_product_int`: ~1.4238x C
    - `dot_product_int_slot_direct`: ~0.9826x C
    - baseline `array_sum_int`: ~1.3214x C
    - `array_sum_int_slot_direct`: ~0.7955x C
    - conclusion: the measured full-overwrite fast path materially improves the direct `i32`
      conversion surface and reaches near-parity or better than the host C baseline on this fast
      ranking profile
  - paired packed-bridge read-split artifact remains decisively negative:
    - `build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_223926_17837.log`
    - baseline `dot_product_int`: ~1.5762x C long-per-rep
    - packed bridge SIMD: ~542.7074x C long-per-rep
    - packed bridge scalar: ~1062.1370x C long-per-rep
    - conclusion: keep the direct-path fast surface; the packed bridge is still closed
	  - same-batch family expansion:
	    - extended the same success-only full-overwrite fast path from `i32` to the analogous fresh
	      numeric typed-buffer export surfaces for `i64`, `f32`, and `f64`
	    - updated shared stdlib pack/slice/strided/matrix-export helpers to use
	      `*_buf_new_uninit(...)` plus unchecked direct stores only where every lane is written before
	      successful return
	    - added conservative C-runtime shims for `oren_i64_buf_new_uninit`,
	      `oren_f32_buf_new_uninit`, and `oren_f64_buf_new_uninit` so shared stdlib code remains
	      backend-safe even though only native gets the uninitialized-allocation win
	  - same-rule `u8` follow-up:
	    - extended the same success-only full-overwrite fast path to the fresh `[]u8` export family in
	      shared stdlib: `buffer.try_u8_pack`, string-to-`[]u8`, slice/strided-to-`[]u8`, `u8` matrix
	      row/string pack/export, and `bytes.try_to_u8_buf[_slice]`
	    - removed the extra intermediate-list path from slice/strided-to-`[]u8` export and routed
	      bytes-to-buffer copies through the shared `oren_u8_buf_from_bytes_slice(...)` primitive
	    - added conservative C-runtime `oren_u8_buf_new_uninit` coverage so the same shared stdlib
	      code stays link-safe on `oren_c` while native gets the uninitialized-allocation win
	  - adjacent byte-constructor cleanup:
	    - extended the same full-overwrite allocation rule to the adjacent shared/runtime byte
	      constructors that also deterministically overwrite every output lane before return:
	      `bytes.from_hex`, `bytes.pack`, `base64.decode_bytes`, and both C/native `read_u8_buf`
	    - kept this as a scope/safety cleanup only; no separate perf artifact was added for this pass
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
- Follow-up canonical steady tick-mask probe (2026-04-04):
  - promoted the manual steady-state safepoint-mask check into a reusable target:
    - `make perf-probe-arm64-fast-loop-tick-masks-steady`
  - this reuses `make perf-gate-native-steady`, so it measures the same repeated-read-loop surface
    now used by the tracker rather than the earlier single-rep gate
  - while verifying the first draft, found and fixed a real comparison bug in the new script:
    baseline inherited the smoke preflight while the masked runs forced
    `OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0`; the landed version now runs one shared preflight and
    then measures all three cases with the same no-smoke setting
  - verified with:
    - `make perf-probe-arm64-fast-loop-tick-masks-steady`
    - `make test`
  - measured result from `build/logs/perf-probe-arm64-fast-loop-tick-masks-steady-20260404_211810_49064.log`:
    - baseline: `dot_product` ~3.0142x C
    - `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383`: slight regression (`dot_product` ~3.0924x C)
    - `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=65535`: larger regression (`dot_product` ~3.1914x C)
  - conclusion: on the canonical steady runner, increasing the arm64 dot safepoint mask does not
    help and in this corrected same-policy rerun it regresses; keep the shipped
    `fast_list_int_dot_while` tick mask at `4095` and keep pushing on the loop body itself
- Follow-up arm64 single-pair cursor-reg probe + benchmark timestamp fix (2026-04-04):
  - promoted the current-source recheck of the `fast_list_int_dot_while` single-pair cursor-reg
    path into a reusable target:
    - `make perf-probe-arm64-fast-dot-single-pair-cursor-regs`
  - kept the shipped cursor-reg path enabled by default, but made it probeable without source edits:
    - `OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0`
  - while landing that probe, fixed a real tooling issue found by the first back-to-back runs:
    - `scripts/run_perf_gate_native.sh`
    - `scripts/run_perf_gate_list_int.sh`
    - `scripts/run_perf_gate_list_int_read_split.sh`
    - `scripts/run_perf_gate_list_int_steady.sh`
    - `benchmarks/run_benchmarks.py`
    now all use collision-resistant timestamps, so adjacent probe variants do not overwrite
    each other’s gate logs or benchmark result artifacts
  - follow-up cleanup in the same measurement theme (2026-04-04):
    - `scripts/build_perf_artifacts_list_int_packed_bridge.sh`
    - `scripts/build_perf_artifacts_list_int_slot_direct.sh`
    - `scripts/run_perf_probe_list_int_packed_bridge.sh`
    - `scripts/run_perf_probe_list_int_slot_direct.sh`
    - `scripts/run_perf_probe_list_int_unsafe.sh`
    - `scripts/run_perf_smoke_list_int.sh`
    - `scripts/run_perf_smoke_list_int_packed_bridge.sh`
    - `scripts/run_perf_smoke_list_int_slot_direct.sh`
    - `scripts/verify_native_list_int_fast_lowering.sh`
    now also suffix log timestamps with `$$`, so the whole active list-int perf/probe/smoke surface
    is collision-safe under back-to-back runs
  - verified with:
    - `env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 make perf-probe-arm64-fast-dot-single-pair-cursor-regs`
    - `make test`
  - measured kept-state serial result from `build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-20260404_214038_91205.log`:
    - steady default: `dot_product` ~3.1205x C
    - steady disabled: `dot_product` ~3.1322x C
    - canonical gate default: `dot_product` ~2.6041x C
    - canonical gate disabled: `dot_product` ~2.5322x C
  - conclusion: on the current host the signal is too close and too noisy to justify a shipped
    default flip. Keep the cursor-reg path enabled for now, but use the new probe instead of
    ad-hoc source edits when rerunning this question
- Follow-up arm64 dot unroll-by-2 probe (2026-04-04):
  - promoted the current-source arm64 `fast_list_int_dot_while` unroll-by-2 recheck into a
    reusable target:
    - `make perf-probe-arm64-fast-dot-unroll2`
  - kept the shipped unique-list unroll-by-2 path enabled by default, but made the comparison
    source-free via:
    - `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=0`
  - widened the knob so future reruns can force either side without source edits:
    - `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1`
    - `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=true`
  - verified with:
    - `env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 make perf-probe-arm64-fast-dot-unroll2`
  - final kept-state rerun from `build/logs/perf-probe-arm64-fast-dot-unroll2-20260404_215653_19700.log`:
    - steady default: `dot_product` ~2.9806x C
    - steady disabled: `dot_product` ~2.8893x C
    - canonical gate default: `dot_product` ~2.1919x C
    - canonical gate disabled: `dot_product` ~2.7147x C
  - conclusion: current host signal is mixed rather than decisively better in one direction, so
    the shipped unroll-by-2 default stays enabled for now; use the new probe for future reruns
- Follow-up arm64 unique-list loop-body cleanup (2026-04-04):
  - tightened the arm64 int list hot loops without changing semantics:
    - keep `n` hot in a register on the unique-list `fast_list_int_get_sum_while` path
    - keep `n` hot in a register on the unique-list `fast_list_int_dot_while` path
    - use immediate `+8` cursor bumps on the scalar unique-list int get-sum/dot paths
    - remove the duplicate `i * 8` recompute from the non-unique int-dot body
  - verified with:
    - `make perf-smoke-native-fast-loops`
    - `env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 OREN_BENCH_PROGRAMS=array_sum,dot_product make perf-gate-native-steady`
    - `env OREN_BENCH_PROGRAMS=array_sum,dot_product make perf-gate-native`
    - `make test`
  - serial kept-state reruns:
    - steady summary `build/logs/perf-gate-native-steady-20260404_220430_32496.log`
      - `array_sum` ~2.2422x C
      - `dot_product` ~2.9915x C
    - canonical gate:
      - `build/benchmarks/results/array_sum_darwin_arm64_20260404_220447_355740.md`
        - `array_sum` ~2.0808x C
      - `build/benchmarks/results/dot_product_darwin_arm64_20260404_220447_627069.md`
        - `dot_product` ~2.7616x C
  - conclusion: this cleanup is worth keeping because it is low-risk and directionally positive,
    but it does not close the canonical arm64 `dot_product <= 2x C` blocker
- Follow-up arm64 dot dual-accum probe + variance guard (2026-04-04):
  - added a source-free probe for the single-pair cursor-reg dot specialization:
    - `make perf-probe-arm64-fast-dot-dual-accum`
    - `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1`
  - kept the shipped default conservative:
    - dual-accum path disabled by default
  - hardened the arm64 dot probe family while landing it:
    - `scripts/run_perf_probe_arm64_fast_dot_single_pair_cursor_regs.sh`
    - `scripts/run_perf_probe_arm64_fast_dot_unroll2.sh`
    - `scripts/run_perf_probe_arm64_fast_dot_dual_accum.sh`
    now parse benchmark `cov` and print a warning when the canonical one-program gate is too noisy
    (`cov >= 0.10`) to support a strong comparison
  - verified with:
    - `env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 make perf-probe-arm64-fast-dot-dual-accum`
    - `make test`
  - final clean rerun from `build/logs/perf-probe-arm64-fast-dot-dual-accum-20260404_221723_55004.log`:
    - steady default: `dot_product` ~2.8895x C
    - steady enabled: `dot_product` ~3.0684x C
    - canonical gate default: `dot_product` ~2.6129x C
    - canonical gate enabled: `dot_product` ~2.7629x C
  - conclusion: on the current host, dual accumulators make the single-pair arm64 dot path worse on
    both tracker surfaces, so keep the path disabled and keep the probe for future reruns
- Follow-up native gate summary hygiene (2026-04-04):
  - the more general issue exposed by the arm64 dot experiments was that `make perf-gate-native`
    still emitted only the raw benchmark log, while the narrower steady/probe flows already
    surfaced variance explicitly
  - fixed by teaching `scripts/run_perf_gate_native.sh` to emit a lightweight summary log beside
    the raw log:
    - `build/logs/perf-gate-native-*.summary.log`
  - the summary now prints per-program medians/ratios and warns when a one-program gate is too
    noisy to support a strong conclusion:
    - warning threshold: `cov >= 0.10`
  - this reduces the chance that future arm64 dot work overfits a single noisy canonical-gate
    outlier before the steady runner agrees
- Follow-up native gate stability probe (2026-04-04):
  - the next measurement gap after the summary warning was repeatability: one clean warning still
    does not tell you how often the canonical gate stays noisy or how wide the ratio spread is
  - added a reusable runner:
    - `make perf-probe-native-gate-stability`
  - it reruns `make perf-gate-native` a few times (default `OREN_NATIVE_GATE_STABILITY_SWEEPS=3`)
    and summarizes:
    - ratio median/min/max per program
    - warning frequency per program
  - this gives the arm64 dot thread a small gate-distribution view without having to hand-run the
    canonical gate several times and diff logs manually
  - first rerun from `build/logs/perf-probe-native-gate-stability-20260404_222343_66111.log`
    (`sweeps=3`, programs=`array_sum,dot_product`) was clean enough to trust:
    - `array_sum`: median ~1.9955x C, range ~1.9603x..~2.0259x, warnings 0/3
    - `dot_product`: median ~2.5153x C, range ~2.3889x..~2.6432x, warnings 0/3
  - conclusion: on this host the canonical gate is stable enough to confirm the blocker itself;
    arm64 `dot_product` remains clearly above the `<=2x C` target even when the gate stops warning
  - follow-up tooling fix (2026-04-04): concurrent `make perf-*` verification could rebuild
    `oren` / `oren_stage2` at the same time and trip a false macOS codesign
    `No such file or directory` failure
  - fix landed in the shared build path:
    - new helper `scripts/with_build_lock.sh`
    - stage1/stage2 Makefile recipes now queue on `build/locks/compiler-build.lock`
  - practical outcome: the perf targets still run independently after the compiler is ready, but
    the shared compiler rebuild is now serialized across parallel make invocations
  - follow-up tooling fix (2026-04-04): arm64 fast list loops now expose an opt-in
    `OREN_TRACE_ARM64_LOOP_RANGES=1` trace, and a new probe target
    `make perf-probe-arm64-native-hot-loop-disasm` builds canonical `array_sum` / `dot_product`
    with `--disasm` and extracts the traced fast-loop windows into a compact summary log
  - follow-up tooling fix (2026-04-05): that disasm probe now also forces `--no-cache`, because
    the summary depends on compile-time `[arm64_loop_range]` prints and native cache hits can
    otherwise leave the script with only raw disassembly text
  - follow-up tooling fix (2026-04-05): the disasm probe now exits non-zero when the traced
    canonical loop windows are missing, so the arm64 summary cannot silently degrade into a
    cache-hit/missed-lowering artifact
  - follow-up arm64 emitter experiment (2026-04-04): replaced the single-pair unrolled cursor-reg
    body with post-index pair loads (`ldp ..., [cursor], #16`) so the hot path could fuse adjacent
    loads with cursor bumps
    - serial reruns after reverting the parallel build race:
      - `build/logs/perf-gate-native-steady-20260404_222957_76222.log`
        - `array_sum` ~2.3254x C
        - `dot_product` ~3.1510x C
      - `build/logs/perf-gate-native-20260404_223004_76548.summary.log`
        - `array_sum` ~2.1785x C
        - `dot_product` ~2.6135x C
    - conclusion: this pair-load/cursor-fusion idea regressed the current host versus the last kept
      baseline, so it was reverted and should not be treated as the next likely win
  - follow-up arm64 emitter experiment (2026-04-04): replaced the hot `mul` + `add` accumulation
    pairs in fast dot loops with a new `madd` helper
    - verification failed at the correctness smoke before perf measurement:
      - `build/logs/perf-smoke-native-fast-loops-20260404_223646_87957.log`
      - `array_sum` still returned `205` / `710`, but native `dot_product 10 3` crashed before
        producing `6590`
    - conclusion: the current `madd` substitution was not safe to keep; it was reverted
      immediately, and future multiply-accumulate work should start from a lower-risk isolated path
      or a disassembly-level audit instead of broad emitter replacement

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
- The new arm64 hot-loop disasm probe is now more useful than the first draft: it captures the
  exact traced `fast_list_int_get_sum_while*` / `fast_list_int_dot_while*` windows and emits
  per-window instruction counts plus mnemonic histograms, which is enough to compare static loop
  shape before trusting another focused rerun.
- I tried one narrower follow-up after the earlier failed post-index pair-load experiment: keep
  cursor updates separate, but replace the single-pair hot-path scalar load groups with plain
  offset `ldp` pair loads. That reduced the traced dot window from 328 bytes to 304 bytes, but
  the focused steady rerun still regressed to about `3.10x C`, so the static load count alone is
  not the dominant blocker and that path should stay reverted.
- The next arm64 dot follow-up did produce a keep: the inline safepoint path was spilling far more
  callee-saved regs than the exact hot loops needed for GC visibility. Narrowing the exact
  `list<int>` fast-loop spill set cut the traced canonical windows to 52 instructions for
  `array_sum` and 70 for `dot_product` (with dot safepoint `stp/ldp` dropping from 10/10 to 4/4),
  while the kept reruns improved to steady `array_sum` / `dot_product` ~`2.4144x` / `2.7706x` C
  and canonical gate `array_sum` / `dot_product` ~`1.8926x` / `2.5264x` C.
- I also tried a narrower exact-path multiply/accumulate follow-up after that keep: replace only
  the single-pair cursor-reg `fast_list_int_dot_while*` `mul`+`add` pairs with verified `madd`
  encodings. The traced canonical dot window shrank again, from 70 instructions to 63, and the
  focused steady rerun improved to `dot_product` ~`2.5627x C`
  (`build/logs/perf-gate-native-steady-20260404_235745_37067.log`), but the exact benchmark smoke
  was still not safe: `build/logs/perf-smoke-native-fast-loops-20260405_000124_44574.log` died at
  native `dot_product 10 3` before producing `6590`. I reverted it immediately. The April 5 fact
  is that a nicer-looking disassembly is still not enough unless the exact benchmark smoke clears.
- To keep the next unsafe arm64 dot experiment from falling back to hand-reconstructed repro steps
  again, I also added `make perf-debug-native-benchmark`, a reusable exact-binary repro runner for
  native benchmarks. It records the exact built binary path, args, exit code, build log, and run log
  in one summary artifact, and on non-zero exit it prints the manual `lldb -- <binary> <args...>`
  command to use next.
- Follow-up tooling batch (2026-04-05): there is now also a dedicated
  `make perf-probe-arm64-fast-dot-madd-exact` wrapper. It compares the shipped arm64 dot baseline
  against `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` using the same serial acceptance bundle
  (`smoke`, traced disasm, steady gate, canonical gate, exact-binary repro, optional `make test`),
  so future exact-path `madd` reruns no longer need a hand-applied source diff just to get a full
  verdict artifact. The acceptance harness now also emits a partial summary on failure, which means
  the exact-path branch can preserve the `failed_step` and completed metrics even when the exact
  native repro dies mid-bundle.
- The first shipped rerun of that wrapper on April 5 keeps the same factual verdict as the earlier
  hand-edited experiment. Enabling `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` still dies in the
  exact native repro with `debug_exit_code: 139`, even though the partial acceptance summary
  (`build/logs/perf-probe-arm64-dot-acceptance-20260405_005354_27728.summary.log`) shows better
  focused metrics and the smaller 63-instruction canonical dot window.
- Follow-up probe batch (2026-04-05): there is now also
  `make perf-probe-arm64-fast-dot-madd-exact-subpaths`, which forces the global exact-path knob
  off and re-enables only one of the `quad`, `double`, or `scalar` `madd` substitutions at a time.
  After the exact-double tail guard landed, the current host now shows all three subpaths as
  correctness-clean, but still not as default-worthy wins. Latest rerun:
  baseline `steady_dot_product ~2.9142x`, `gate_dot_product ~2.6790x`, disasm `70`;
  `quad` `~2.9752x`, `~2.4771x`, disasm `66`;
  `double` `~3.0132x`, `~2.6670x`, disasm `82`;
  `scalar` `~2.9798x`, `~2.4631x`, disasm `69`
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-subpaths-20260405_013631_40642.log`).
- Another follow-up probe on April 5 tightened the exact-double story further: the updated
  `make perf-probe-arm64-fast-dot-madd-exact-double-sweep` runner is now green for every sampled
  `n=1..24`, including the formerly unsafe `n ≡ 2 (mod 4)` tail cases `10`, `14`, `18`, and `22`
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-double-sweep-20260405_013604_40047.log`).
  That confirms the remaining terminal exact-double case is now falling back safely.
- With that guard in place, the whole default-off exact-path branch is also correctness-clean again:
  `make perf-probe-arm64-fast-dot-madd-exact` no longer fails the exact native repro, but it still
  does not beat the shipped default overall. Latest rerun:
  baseline `steady_dot_product ~3.1670x`, `gate_dot_product ~2.7194x`, disasm `70` versus enabled
  `~2.9446x`, `~2.7220x`, disasm `77`
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-20260405_013731_43460.log`).
- Another April 5 follow-up fixed a tooling mismatch in the arm64 acceptance surface itself:
  `OREN_BENCH_ENV_BUILD_OREN` now reaches smoke, traced disasm, and exact native debug, not just
  the gate runners, and the acceptance summary records the active `build_env`. That harness fix
  stays, but the specific cursor-end lowering branch has now been retired. The later read-split
  rerun regressed repeated-loop `dot_product` on both `native/C long-per-rep`
  (`~2.6003x -> ~2.6651x`) and `native/C delta` (`~2.8383x -> ~3.0797x`), so the cursor-end knob
  and its dedicated probe scripts were removed from the live perf surface after recording the final
  evidence (`build/logs/perf-probe-arm64-fast-dot-cursor-end-read-split-20260405_021431_93331.log`).
  The same build-env contract now also reaches the direct-build exact-double helpers:
  `make perf-probe-arm64-fast-dot-madd-exact-double-sweep` and
  `make perf-probe-arm64-fast-dot-double-exit-snippet` both honor
  `OREN_BENCH_ENV_BUILD_OREN` and record the active `build_env` in their summaries.
- To make the next code change cheaper to audit, there is now also
  `make perf-probe-arm64-fast-dot-double-exit-snippet`, which rebuilds the baseline and
  exact-double variants with traced `--disasm` and extracts only the 2-wide hot block from the
  canonical `fast_list_int_dot_while_no_tick` window. That replaces another round of full-log
  grepping with one focused artifact for the exit-after-double path.
- Another follow-up compare probe (2026-04-05) now makes the baseline target itself less hand-wavy:
  `make perf-probe-arm64-dot-vs-c-loop-compare` pairs the traced Oren `fast_list_int_dot_while*`
  window with the host `cc -O2 -S` lowering of `benchmarks/dot_product/dot_product.c`.
  - latest artifact: `build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260405_022928_14265.log`
  - kept Oren path: 70-instruction scalar loop
  - host C path: 57-instruction NEON vector loop (`ldp q*`, `smlal.2d`, `smlal2.2d`),
    22-instruction vector mid loop, 6-instruction scalar `smaddl` tail
  - conclusion: the remaining arm64 `dot_product` gap is not just “our scalar loop is still a bit
    too long”; the host C reference is already vectorized on this machine, so further scalar
    cleanups should be treated as partial moves unless they change the execution model more
    fundamentally
- That rerun also exposed a smoke-tooling hole: the canonical and `list<int>` native smoke scripts
  were rebuilding benchmark binaries without `--no-cache`, so compiler-env experiments could pass
  against a stale cached baseline artifact while the exact no-cache debug repro crashed. Those two
  active smoke surfaces now rebuild with `--no-cache`, so environment-toggled compiler experiments
  stop reading as correctness-clean just because the smoke never recompiled the binary.
- Follow-up tooling batch (2026-04-05): there is now also a serial acceptance bundle for the arm64
  canonical dot-core thread: `make perf-probe-arm64-dot-acceptance`. It runs the exact benchmark
  smoke, the traced hot-loop disasm probe, the steady native gate, the canonical native gate, the
  exact-binary native repro, and `make test` in one sequence, then emits a single summary artifact
  with the wrapper logs plus the extracted current ratios and instruction counts.
- I tried one narrower follow-up on top of that keep: spill only the two exact cursor regs
  (`[x19,x26]`) at the single-pair dot inline safepoint instead of the kept two-pair set. That
  stayed correctness-clean in the smoke, but `build/logs/perf-gate-native-steady-20260404_233707_97722.log`
  regressed to `array_sum` / `dot_product` ~`2.4331x` / `3.0449x` C, so the one-pair variant was
  reverted immediately.
- I also tried a more exact April 5 follow-up after that: keep the same logical cursor-only idea,
  but spill those registers as exact single-register stack entries (`[x19]`, `[x26]`) instead of
  forcing them through pair-shaped spill helpers. That remained correctness-clean on the exact
  benchmark smoke and direct native repro
  (`build/logs/perf-smoke-native-fast-loops-20260405_002352_77964.log`,
  `build/logs/perf-debug-native-benchmark-dot_product-20260405_002400_78334.log`), but it still
  regressed both tracker surfaces to steady `array_sum` / `dot_product` ~`2.4180x` / `3.0259x` C
  and canonical gate ~`2.0537x` / `2.5850x` C. That variant was reverted too; the current best
  kept baseline is still the earlier two-pair spill reduction.
- The April 4 build-lock fix also needed a follow-up after the perf thread got cleaner: the
  original 300-second default wait was still short enough for a queued `make test` to false-fail
  behind a legitimate stage2 holder (`build/logs/turn_verify_make_test_gc_single_pair_20260404.log`).
  The lock now defaults to `OREN_BUILD_LOCK_WAIT_SECS=1800`, treats `0` as wait-forever, and records
  holder start time / age in `build/locks/compiler-build.lock/meta` so future queue stalls are easier
  to diagnose from logs alone.
