# Production Readiness Review - 2026-04-08

## Scope

Reviewed the repo’s documented readiness posture and hardened the Go CLI surfaces in:

- `cmd/oren` (bootstrap compiler / REPL entrypoint)
- `cmd/oredoc` (metadata/OpenAPI export helper)
- `cmd/orensign` (signing/certificate helper)

These are the production-facing repo tools that scripts, release workflows, or operator
automation are most likely to invoke directly.

Primary source-of-truth docs inspected in this pass:

- `README.md`
- `docs/STATUS.md`
- `docs/BLEEDING_EDGE_TASKS.md`
- `docs/READINESS.md`
- `project-doc/repo_inspection_20260404.md`

## Facts confirmed from repo docs

- The repository still explicitly describes itself as rolling rather than production-stable.
- `docs/STATUS.md` still lists unresolved W5 blockers:
  - semantic/tagged-value convergence across backends
  - performance parity, especially `dot_product` / read-heavy hot loops
  - runtime robustness around GC/reuse/list-header integrity
  - Tier-1 breadth still rolling for x64 targets
  - essential language/runtime features still missing or planned
- Because those are repo-stated blockers, this pass does **not** claim Oren is now
  generally “production ready” in the LLVM/rustc/GCC/zig/go sense.

## Concrete production issues fixed in this pass

### 1. Wrong default target in bootstrap CLI

Before this change, `cmd/oren/main.go` hardcoded:

- `target := "macos"`

That meant the bootstrap `oren` CLI would default to a macOS target even on Linux or
Windows hosts unless callers always overrode it explicitly. That is a bad production
default and contradicts the README-style expectation that `oren build <file>` should
do the sensible host-local thing.

Fix:

- added `defaultTargetForHost(goos string)`
- `build` now defaults to `macos` / `linux` / `windows` based on the host OS

### 2. `run` command could fail via missing argument indexing

Before this change, `run` used `os.Args[2]` without first checking that the user
actually provided a source path.

Fix:

- added explicit usage validation for `oren run <file.oren>`
- missing file now returns exit code `2` with a usage message

### 3. Bootstrap CLI used `panic(...)` on ordinary user/environment failures

Before this change, ordinary failures such as:

- missing input file / include expansion failure
- C file write failure
- `python3-config` probe failures

could surface as panics instead of clean diagnostics.

Fix:

- refactored `main` into `runCommand(...)` for structured exit behavior
- replaced panic-based handling with explicit error messages and exit codes
- unknown commands now return non-zero instead of printing a message and falling through

### 4. REPL prompt ignored the provided writer

Before this change, `Start(...)` wrote the prompt with `fmt.Printf`, bypassing the
supplied output writer.

Fix:

- prompt now writes to the passed `io.Writer`

### 5. `oredoc` still used process-exit control flow and hardwired stdout

Before this change, `cmd/oredoc/main.go` mixed command parsing and `os.Exit(...)`
control flow, and `openapi` wrote directly to process stdout instead of the supplied
writer path. That made it harder to test, embed, or reuse in scripted tooling and
meant usage/unknown-command paths were not covered by normal unit tests.

Fix:

- added `runOredoc(...)` and `runOpenAPI(...)` structured runners
- added explicit root help / unknown-command / missing-argument exit handling
- made OpenAPI emission writer-aware instead of hardwiring `os.Stdout`
- added focused CLI tests for usage/errors and successful JSON/file export

### 6. `orensign` still used `flag.ExitOnError` + `must(...)` for ordinary failures

Before this change, `cmd/orensign/main.go` still used:

- `flag.ExitOnError`
- direct `os.Exit(...)`
- `must(err)` aborts for user mistakes and file/content problems

That is not production-grade behavior for a signing tool that should be predictable in
automation. It also left the signing and cert-issuance command surface effectively
untested.

Fix:

- added `runOrensign(...)` plus structured `runKeygen(...)`, `runIssueCert(...)`,
  `runSignOBC(...)`, and `runVerifyOBC(...)`
- converted command-line misuse into exit code `2` with explicit usage text
- converted operational failures into exit code `1` with contextual diagnostics
- added end-to-end regression tests for keygen/sign/verify and certificate issuance

## Tests added

Added bootstrap CLI regression coverage in `cmd/oren/main_test.go` for:

- host default target selection
- host default compiler selection on Windows
- build-arg parsing failures
- missing-file and usage diagnostics
- unknown-command non-zero exit behavior

Added `cmd/oredoc/main_test.go` coverage for:

- root usage/help/unknown-command handling
- missing `<meta.json>` diagnostics
- successful OpenAPI JSON export to stdout
- successful OpenAPI export to `-o <file>`

Added `cmd/orensign/main_test.go` coverage for:

- root usage/help/unknown-command handling
- missing required subcommand flags
- end-to-end `keygen -> sign-obc -> verify-obc`
- successful `issue-cert`
- rejection of conflicting `--allow-domains` / `--allow-domains-mask`

## Verification run in this pass

Successful:

- `go test ./cmd/oren`
- `go test ./cmd/oredoc`
- `go test ./cmd/orensign`
- `go test ./...`
- `make test`
- `./scripts/triage_native_quick_green_cache_flake.sh 5 ./oren`
  - passed 5/5
  - log: `build/logs/triage_green_cache_current_20260408.log`
- `go build -o build/tmp/oren_bootstrap_review ./cmd/oren`
- `build/tmp/oren_bootstrap_review run`
  - verified exit `2`
  - verified usage message in `build/logs/oren_bootstrap_run_usage_20260408.log`
- `build/tmp/oren_bootstrap_review build tests/fixtures/does_not_exist.oren`
  - verified exit `1`
  - verified friendly read error in `build/logs/oren_bootstrap_build_missing_20260408.log`
- `./oretest`
  - passed after rebuilding stage0 + stage1
  - log: `build/logs/oretest_review_post_patch_20260408.log`
- repo-wide test logs for the second CLI batch:
  - `build/logs/go_test_cmd_oredoc_20260408.log`
  - `build/logs/go_test_cmd_orensign_20260408.log`
  - `build/logs/go_test_all_cli_batch_20260408.log`
  - `build/logs/make_test_cli_batch_20260408.log`

## Runtime robustness follow-up (2026-04-08)

The repo docs still carried March-era stage1 green-cache flake notes, so this pass also
rechecked the current runtime robustness surface instead of assuming those flakes still
represented the present baseline.

Facts from current verification:

- the dedicated stage1 green-cache flake harness now passes 5/5 on current `master`
- the default quick-integration green-cache pass also remains clean on current `master`
- the important remaining gap was not a currently reproduced crash, but that the main
  W5 runtime robustness verifier did **not** include the guarded pre-world-lock
  green-cache path that the tracker still called out
- the first attempt to add that path exposed two verifier-side false-reds instead of a
  runtime crash:
  - `scripts/triage_stage2_quick_until_world_lock.sh` logged failed builds as `rc=0`
    because it captured `$?` from `if ! cmd; then ...`
  - the guarded pre-world-lock and stage2 quick-integration verifier paths were using
    undersized stage2 build budgets relative to current self-hosted debug compile cost
- direct measurement on current `master` showed
  `./oren_stage2 build tests/native/test_quick_integration_native.oren --backend native --platform arm64-macos --debug ...`
  taking about `2:24.28`, so the `240s` budget already used by `test-native-quick-stage2`
  is the right baseline for these guarded stage2 verifier paths on this host

Fix in this pass:

- `scripts/verify_runtime_robustness_w5.sh` now runs the guarded pre-world-lock
  green-cache quick-integration path by default
- `scripts/triage_stage2_quick_until_world_lock.sh` now preserves the actual build exit
  code in failure logs instead of collapsing build failures to `rc=0`
- `scripts/triage_native_quick_stage2_flake_debug.sh` now defaults to the same `240s`
  stage2 debug build headroom already proven by `test-native-quick-stage2`
- `make verify-runtime-robustness` now forwards dedicated env knobs for:
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_STAGE2_BUILD_TIMEOUT_SECS`

Verification for this follow-up:

- `make verify-green-preworld-guarded`
  - log: `build/logs/make_verify_green_preworld_guarded_20260408.log`
- `make verify-runtime-robustness`
  - log: `build/logs/make_verify_runtime_robustness_20260408.log`
  - detailed bundle log: `build/logs/runtime_robustness_w5_20260408_212845.log`
- `make test`
  - log: `build/logs/make_test_runtime_gate_20260408.log`

That change upgrades stage1 green-cache runtime robustness from a side-target / manual
triage path into part of the main W5 verification bundle.

## W5 perf follow-up in this pass

After the runtime-verifier work, the next concrete blocker was still arm64/native hot-loop
parity, especially canonical `dot_product`. I tested one specific loop-body hypothesis in
the compiler: replacing contiguous `ldr`/`ldr off` groups with arm64 post-index `ldp`
pair-loads on the canonical `fast_list_int_get_sum_while*` and single-pair
`fast_list_int_dot_while*` paths.

What held up:

- the experiment is now preserved as a default-off compiler knob instead of a hand edit:
  - `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1`
  - `OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1`
- there is now a dedicated reproducible probe:
  - `make perf-probe-arm64-fast-loop-pair-post`
- the remaining comma-splitting bug in the perf smoke/disasm/debug helpers was fixed, so
  comma-separated `OREN_BENCH_ENV_BUILD_OREN=A=1,B=2` now reaches those legs consistently
  instead of only the gate/steady runners

Measured result:

- paired rerun log: `build/logs/perf-probe-arm64-fast-loop-pair-post-20260408_215548_57748.log`
- shipped default:
  - `steady_array_sum ~2.4342x C`
  - `steady_dot_product ~2.7645x C`
  - `gate_array_sum ~2.0788x C`
  - `gate_dot_product ~2.5682x C`
  - disasm instruction counts: `52` (`array_sum`) / `70` (`dot_product`)
- enabled pair-post experiment:
  - `steady_array_sum ~2.3932x C`
  - `steady_dot_product ~3.1297x C`
  - `gate_array_sum ~2.1181x C`
  - `gate_dot_product ~2.6913x C`
  - disasm instruction counts: `47` / `60`

Conclusion:

- the instruction windows got materially shorter, but the measured hot-loop gates still
  regressed, especially canonical `dot_product`
- therefore the pair-post lowering stays disabled by default
- the new probe means future arm64 loop work can reuse this exact comparison without
  reopening source diffs or re-learning the comma-splitting failure mode

Perf tooling hardening follow-up:

- the remaining perf/build helper scripts that still hand-parsed
  `OREN_BENCH_ENV_BUILD_OREN` now share one parser in
  `scripts/perf_build_env_lib.sh`
- the last local `join_build_env` / `eval` wrapper path was removed, so
  comma-separated multi-var build envs now reach the direct-build helper probes through
  the same array-safe code path as the smoke/disasm runners
- targeted verification for this cleanup:
  - `make perf-probe-arm64-fast-loop-pair-post`
    - wrapper log: `build/logs/perf_probe_pair_post_env_helper_20260408.log`
    - summary: `build/logs/perf-probe-arm64-fast-loop-pair-post-20260408_221017_88781.log`
  - `make perf-probe-arm64-dot-vs-c-scalar-ceiling`
    - wrapper log: `build/logs/perf_probe_dot_scalar_ceiling_env_helper_20260408.log`
    - summary: `build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260408_221100_90602.log`
  - `make test`
    - log: `build/logs/make_test_perf_env_parser_20260408.log`

Prefix-zero containment follow-up:

- I tested another arm64 statement-level loop-body idea: a compile-time-zero fast path for the
  canonical `list<int>` `array_sum` / `dot_product` while-loops.
- I kept the experiment only as an explicit opt-in compiler knob:
  - `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1`
  - `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`
- There is still a failure-aware family probe:
  - `make perf-probe-arm64-fast-loop-prefix-zero`
  - Unlike the pair-post probe, it records wrapper and acceptance exit status per leg and only
    returns non-zero when the shipped default is broken.
- The get-sum leg is still a measured loss. The isolated rerun
  (`build/logs/perf-probe-arm64-dot-acceptance-20260409_003014_84317.summary.log`) landed at:
  - `steady_array_sum ~7.1203x C`
  - `gate_array_sum ~2.3250x C`
  - `disasm_array_sum_insns: 18`
- The dot leg is now correctness-clean after the April 9 register-plan fix that mirrors the proven
  direct-slot intrinsic register layout after list validation. Native smoke now passes with
  `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`
  (`build/logs/perf-smoke-native-fast-loops-20260409_003456_90383.log`).
- There is now a dedicated serialized dot-only probe:
  - `make perf-probe-arm64-fast-dot-prefix-zero`
  - It compares the shipped default against only
    `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` on
    `OREN_ARM64_DOT_ACCEPT_PROGRAMS=dot_product`.
- The generic and explicit prefix-zero wrappers now also keep raw steady/gate native medians and
  covariance from the acceptance bundles, because ratio-only A/Bs were masking C-baseline drift.
- Current dot-only rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-20260409_014027_88043.log`):
  - shipped default:
    - `steady_dot_product ~2.8260x C`
    - `steady_dot_product_native_median_s: 0.083484`
    - `gate_dot_product ~2.3626x C`
    - `gate_dot_product_native_median_s: 0.013869`
    - `disasm_dot_product_insns: 70`
  - enabled dot prefix-zero experiment:
    - `steady_dot_product ~2.9272x C`
    - `steady_dot_product_native_median_s: 0.080339`
    - `gate_dot_product ~2.6579x C`
    - `gate_dot_product_native_median_s: 0.014837`
    - `disasm_dot_product_insns: 23`
  - direct native deltas:
    - `steady_dot_product_native_median_delta_pct: -3.77%`
    - `gate_dot_product_native_median_delta_pct: +6.98%`
- There is now a matching explicit `list<int>` acceptance/probe surface:
  - `make perf-probe-arm64-list-int-acceptance`
  - `make perf-probe-arm64-fast-dot-prefix-zero-list-int`
- Current explicit `list<int>` rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-list-int-20260409_014050_89076.log`):
  - shipped default:
    - `steady_dot_product_int ~3.0871x C`
    - `steady_dot_product_int_native_median_s: 0.077758`
    - `gate_dot_product_int ~2.5017x C`
    - `gate_dot_product_int_native_median_s: 0.013945`
    - `disasm_dot_product_int_insns: 70`
  - enabled dot prefix-zero experiment:
    - `steady_dot_product_int ~2.9543x C`
    - `steady_dot_product_int_native_median_s: 0.087468`
    - `gate_dot_product_int ~2.6867x C`
    - `gate_dot_product_int_native_median_s: 0.015405`
    - `disasm_dot_product_int_insns: 23`
  - direct native deltas:
    - `steady_dot_product_int_native_median_delta_pct: +12.49%`
    - `gate_dot_product_int_native_median_delta_pct: +10.47%`
- Corrected conclusion: keep both prefix-zero branches disabled by default for now. The get-sum leg
  is still a clear negative result. The dot-only experiment no longer crashes, but the latest
  raw-median rerun no longer supports the older ratio-only “explicit win” reading: generic remains
  mixed and explicit `dot_product_int` regresses on both steady and whole-operation native medians.
- Follow-up specialization check (2026-04-09): I added
  `make perf-probe-arm64-fast-dot-prefix-zero-specialization` so the repo now has one artifact that
  compares generic auto-specialized `dot_product` against explicit `dot_product_int` on both the
  shipped default and `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`, while also preserving the
  compile-time specialization trace. Current rerun
  (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-specialization-20260409_011654_49934.log`) says
  the generic/explicit gap still stays small after restoring typed reserve on the parsed-bound fill
  loops:
  - default steady: generic `~1.3947x C`, specialized `~1.6008x C` (`~0.8713x` gap)
  - enabled steady: generic `~1.3992x C`, specialized `~1.5518x C` (`~0.9017x` gap)
  - default read-split long-per-rep: generic `~1.6788x C`, specialized `~1.7004x C` (`~0.9873x` gap)
  - enabled read-split long-per-rep: generic `~1.6392x C`, specialized `~1.5860x C` (`~1.0335x` gap)
  - compile trace now also confirms typed reserve + typed unchecked fill on the benchmark loops:
    generic `rewrite_init=2`, `list_int_reserve=2`, `list_int_push_unchecked=2`; specialized
    `rewrite_init=0`, `list_int_reserve=2`, `list_int_push_unchecked=2`
- Updated conclusion: the current blocker is no longer well-described as a broad “source-shape gap”.
  The explicit `list<int>` surface likes the salvaged dot path, the focused specialization probes
  keep the generic/explicit gap near parity, and the parsed-bound benchmark setup gap is now
  closed. The remaining blocker is back in the steady arm64 dot kernel and the missing vector path.
- Verification for the current salvage pass:
  - `env OREN_BENCH_ENV_BUILD_OREN='OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1' make perf-smoke-native-fast-loops`
    - wrapper log: `build/logs/make_perf_smoke_native_fast_loops_dot_prefix_zero_only_fix1_clean_20260409.log`
    - smoke summary: `build/logs/perf-smoke-native-fast-loops-20260409_003456_90383.log`
  - `make perf-probe-arm64-fast-dot-prefix-zero`
    - wrapper log: `build/logs/make_perf_probe_arm64_fast_dot_prefix_zero_20260409.log`
    - summary: `build/logs/perf-probe-arm64-fast-dot-prefix-zero-20260409_003819_95036.log`
  - `make perf-probe-arm64-fast-dot-prefix-zero-list-int`
    - wrapper log: `build/logs/make_perf_probe_arm64_fast_dot_prefix_zero_list_int_20260409.log`
    - summary: `build/logs/perf-probe-arm64-fast-dot-prefix-zero-list-int-20260409_004804_8889.log`

Shared `list<int> -> []i32` bridge follow-up:

- I then moved off the speculative arm64 loop-body edits and attacked the adjacent bridge that the
  tracker still had marked as a W5 blocker.
- Root cause on current `master`: shared `buffer.i32_pack_list_int(...)` was still building a fresh
  `[]i32` through an Oren-level element loop in `std:buffer`, so the explicit packed-bridge path
  paid per-element shared-language dispatch/check/store cost before it even reached the packed dot
  kernel.
- Fix in this pass:
  - added dedicated runtime helpers across all three backends:
    - native: `oren_i32_buf_pack_list_int(...)` / `_into(...)`
    - C runtime: same bridge surface with a fast raw-slot path when list locking is not needed
    - AVM: matching native ids + dispatch cases
  - rewired shared `buffer.i32_pack_list_int(...)` / `_into(...)` onto those helpers
  - tightened the native implementation again after the first correctness pass so the hot loop uses
    cursor increments plus direct little-endian byte stores instead of calling
    `oren_ptr_set_i32_le(...)` for every lane
  - added `_into` regression coverage on all three execution surfaces:
    - `tests/modules/test_linalg.oren`
    - `tests/native/qi/100_tests_basic.oren`
    - `tests/avm/test_std_buffer_views_portable.oren`

Measured result:

- `make perf-probe-list-int-dot-ceiling`
  - first runtime-backed rerun: `build/logs/perf-probe-list-int-dot-ceiling-20260408_231259_80069.log`
  - tightened native-loop rerun: `build/logs/perf-probe-list-int-dot-ceiling-20260408_231950_89006.log`
  - latest ranking on the tightened rerun:
    - canonical `dot_product_int`: `~1.2169x C`
    - direct-slot helper `dot_product_int_slot_direct`: `~1.1182x C`
    - packed bridge SIMD `dot_product_int_packed_bridge`: `~4.9387x C`
    - packed bridge scalar `dot_product_int_packed_bridge`: `~17.0948x C`
- `make perf-probe-list-int-packed-bridge-read-split`
  - first runtime-backed rerun: `build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_231504_82827.log`
  - tightened native-loop rerun: `build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log`
  - latest attribution on the tightened rerun:
    - canonical `dot_product_int`: `~1.3778x C` long-per-rep
    - packed bridge scalar `dot_product_int_packed_bridge`: `~13.5584x C` long-per-rep
    - packed bridge SIMD `dot_product_int_packed_bridge`: `~4.1480x C` long-per-rep
    - packed-SIMD repeated-work delta: `~0.4993x C`

Conclusion:

- the shared runtime-backed bridge is a real improvement; it cut the packed-SIMD path from the old
  hundreds-of-times-C regime down to single-digit multiples of C on the same fast-profile probe
- the repeated packed-SIMD kernel is no longer the main blocker
- the remaining blocker is one-shot bridge setup/materialization cost before the kernel runs
- the next high-leverage parity move is therefore not more packed dot-kernel tuning; it is
  eliminating, hoisting, caching, or otherwise reusing the `list<int> -> []i32` export work

Explicit packed-workspace reuse follow-up:

- I then tested the most conservative version of that next idea: do not invent an implicit cache,
  because the runtime still has no list-mutation epoch suitable for safe hidden reuse. Instead,
  expose a caller-managed workspace surface in shared stdlib and measure it directly.
- Fix in this pass:
  - added `linalg.dot_i32_list_int_packed_reuse(...)`
  - added `linalg.reduce_sum_i32_list_int_packed_reuse(...)`
  - both functions repack into caller-provided `[]i32` work buffers via
    `buffer.i32_pack_list_int_into(...)`
  - hidden packed-bridge benchmarks now support `OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1`
  - packed-bridge smoke now checks that reuse-work mode still returns the expected `205` / `710` /
    `6590` / `54380`
  - shared module tests now cover the new reuse entrypoints

Measured result:

- `make perf-probe-list-int-packed-bridge-read-split`
  - no-smoke rerun: `build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log`
  - current long-per-rep ranking:
    - canonical `dot_product_int`: `~1.2915x C`
    - fresh-pack SIMD (`OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_ENABLE_SIMD=1`): `~7.3906x C`
    - reuse-work SIMD (`OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1,OREN_ENABLE_SIMD=1`): `~7.2240x C`
    - pack-once SIMD (`OREN_ENABLE_SIMD=1`): `~4.4566x C`

Conclusion:

- explicit destination-buffer reuse is a valid shared API and it is correctness-clean
- but it only trims a small slice of the fresh-pack cost on the current probe
- therefore fresh allocation is not the dominant remaining bridge cost anymore
- the real remaining blocker is the repeated `list<int> -> []i32` materialization/copy itself
- that means the next parity move should not be “more workspace reuse”; it should be either
  hoisting/prepacking the bridge across repeated operations or eliminating the bridge entirely for
  the hot path

Direct-slot read-split follow-up:

- After the bridge/reuse work, the tracker still mixed steady-only helper numbers with read-split
  bridge numbers. That was no longer good enough to choose the next implementation move.
- Fix in this pass:
  - added `make perf-probe-list-int-slot-direct-read-split`
  - it warms the hidden direct-slot artifacts once and reruns canonical `array_sum_int` /
    `dot_product_int` against `array_sum_int_slot_direct` / `dot_product_int_slot_direct` on the
    same short/long read-split harness
  - the summary now calls out when the delta metric is unstable and should not drive tracker updates

Measured result:

- no-smoke rerun: `build/logs/perf-probe-list-int-slot-direct-read-split-20260408_235243_30345.log`
- current long-per-rep ranking on that split:
  - canonical `array_sum_int`: `~1.3410x C`
  - direct-slot `array_sum_int_slot_direct`: `~1.0383x C`
  - canonical `dot_product_int`: `~1.2680x C`
  - direct-slot `dot_product_int_slot_direct`: `~1.1637x C`
- the same rerun produced unstable delta-side evidence on `dot_product_int`
  (`canonical ~-0.0273x C`, `direct-slot ~7.6465x C`), so `long_per_rep` is the reliable number on
  this surface

Conclusion:

- the hidden direct-slot helper is now a better whole-operation ceiling than the shipped canonical
  loop on the same read-split workload
- the packed bridge remains the wrong place to spend the next turn
- the next highest-leverage implementation task is now clearer: move more of the canonical lowering
  toward the direct-slot path, while preserving the existing correctness/lowering guards

Whole-list helper follow-up (2026-04-09):

- I tried the narrowest safe version of that convergence idea on both arm64 and x64: if the
  canonical `array_sum_int` / `dot_product_int` loop starts from `i == 0`, `sum == 0`, and `n`
  matches the validated list lengths, the compiler can jump straight to
  `oren_list_int_reduce_sum_slots_unchecked(...)` / `oren_list_int_dot_slots_unchecked(...)`
  instead of staying in the existing canonical fast loop.
- Correctness and lowering shape were clean:
  - `make verify-native-list-int-fast-lowering`
  - log: `build/logs/verify_native_list_int_fast_lowering_20260409_000729_50400.log`
- But the production metric was wrong: serialized no-smoke read-split reruns showed the default-on
  shortcut made the shipped whole-operation path slower, not faster.
  - enabled summary: `build/logs/perf-probe-list-int-slot-direct-read-split-20260409_000912_53072.log`
  - disabled summary: `build/logs/perf-probe-list-int-slot-direct-read-split-20260409_000926_53704.log`
  - `array_sum_int`: `~1.3445x C` enabled vs `~1.1896x C` disabled
  - `dot_product_int`: `~1.4160x C` enabled vs `~1.3166x C` disabled
- Result:
  - `OREN_NATIVE_FAST_LIST_INT_GET_SUM_WHOLE_LIST_HELPER`
  - `OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER`
  remain in-tree only as opt-in experiments; they are not production defaults.

Started but not carried to completion in this pass:

- `make readiness-report-json`
  - reached `verify-native-quick-simd`
  - completed stage1 quick verification and stage2 build/quick-integration progress
  - run was stopped to keep this pass bounded after the CLI hardening had already been
    validated by `go test ./...`, rebuilt bootstrap-binary checks, and `./oretest`

## Remaining production blockers after this pass

From the repository’s own docs and tracker, the major blockers are still:

- backend semantic convergence
- native runtime robustness under GC/reuse stress
- sustained hot-loop parity, especially native `dot_product`
- Tier-1 completion for non-arm64-macOS targets
- feature-completeness gaps called out in `docs/LANGUAGE.md` / `docs/STATUS.md`

## Result of this pass

This pass makes the repo’s **Go operator/tooling surface** materially safer and more
production-like:

- correct host-aware defaults
- no crashy missing-arg path for `oren run`
- friendly diagnostics instead of panics / hard exits on common CLI failures
- deterministic non-zero exits for invalid invocation across `oren`, `oredoc`, and `orensign`
- actual regression coverage for metadata export and signing/cert workflows

That improves bring-up reliability, scripting safety, and operator UX, but it does not
erase the broader compiler/runtime maturity gaps that the project still documents as open.

## 2026-04-09 update

Additional production-readiness work after the CLI pass tightened the arm64 dot-kernel evidence and
landed one measured compiler-default improvement:

- new probe wrappers now preserve raw native medians/covariance for the arm64 exact-`madd` family,
  and explicit `dot_product_int` wrappers exist alongside the generic `dot_product` surface
- the full opt-in branch `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` is still mixed and stays
  non-default
- the older scalar-only promotion story is no longer current on the post-unroll2 tree; the current
  scalar-core matrix wrappers are the right decision surface now:
  - generic `dot_product` (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260409_033716_83363.log`):
    `SCALAR=1` improves both raw native medians (`0.147226s -> 0.140442s`, `-4.61%`;
    `0.016850s -> 0.016093s`, `-4.49%`)
  - explicit `dot_product_int`
    (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-list-int-20260409_033758_85506.log`):
    `SCALAR=1` improves steady materially (`0.150822s -> 0.137406s`, `-8.90%`) but still regresses
    whole-operation gate (`0.015208s -> 0.016123s`, `+6.02%`)
  - `CURSOR=0` and `CURSOR=0,SCALAR=1` stay similarly mixed once the explicit gate surface is
    included
- the new read-split decomposition wrappers now explain that mixed explicit result instead of
  leaving it as a black box:
  - generic rerun (`build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-20260409_035000_5744.log`):
    `CURSOR=0,SCALAR=1` improves every reported native component on this rerun
    (`short -3.49%`, `setup -3.27%`, `delta -5.72%`, `long_per_rep -4.47%`)
  - explicit rerun (`build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-20260409_035009_6305.log`):
    `SCALAR=1` improves short/setup (`-3.28%`, `-3.95%`) and is almost flat on repeated
    `long_per_rep` (`-0.11%`), but still worsens the `delta` estimate (`+4.22%`)
- the focused tie-breaker is now explicit whole-operation gate stability, not one more ad hoc rerun:
  - new wrapper:
    `make perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int`
  - latest order-balanced artifact:
    `build/logs/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-20260409_035611_14589.log`
  - it rotates the four scalar-core cases across four sweeps so each case occupies each run
    position once
  - current result: `SCALAR=1` wins absolute native gate median in `3/4` sweeps and by median
    `-1.31%`, but loses normalized `native/C` in `3/4` sweeps with median `+5.74%`
  - `CURSOR=0,SCALAR=1` is flatter on absolute native median (median `-0.52%`) but still loses
    normalized `native/C` (median `+2.32%`)
- reweight: keep scalar exact-`madd` opt-in on the shipped baseline for now, and keep cursor regs
  default-on until a future arm64 dot core change improves both generic and explicit whole-operation
  surfaces together on the matrix, read-split, and stability surfaces
- the shipped scalar default now has a deterministic structural guard:
  `make verify-native-arm64-dot-madd-scalar-default` and the integrated
  `make verify-native-list-int-fast-lowering` path both confirm the live arm64 default still emits
  `21` instructions with no scalar-tail `madd` on generic and explicit surfaces, while forcing
  `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` moves both to `20` instructions with
  `madd_count=1` (`build/logs/verify_arm64_dot_madd_scalar_default_20260409_033658_82605.log`)
- the arm64 acceptance summaries and exact-`madd` wrappers now raise explicit high-variance warning
  keys for noisy gate samples instead of relying on manual COV inspection of nested logs
- the arm64 dual-accum experiment was also corrected and remeasured:
  - the opt-in path no longer keeps its secondary accumulator in caller-saved `x17`; it now uses
    callee-saved `x22`, which removes a real inline-GC-safepoint correctness hazard
  - new generic and explicit wrappers exist:
    `make perf-probe-arm64-fast-dot-dual-accum` and
    `make perf-probe-arm64-fast-dot-dual-accum-list-int`
  - current generic rerun
    (`build/logs/perf-probe-arm64-fast-dot-dual-accum-20260409_024400_89920.log`) improved both
    raw native medians despite a `69 -> 70` disasm increase: steady `0.079878s -> 0.077758s`
    (`-2.65%`), gate `0.014427s -> 0.013903s` (`-3.63%`)
  - current explicit rerun
    (`build/logs/perf-probe-arm64-fast-dot-dual-accum-list-int-20260409_024524_92158.log`) stayed
    mixed: steady `0.077313s -> 0.080407s` (`+4.00%`), gate `0.016063s -> 0.015338s` (`-4.51%`),
    but the enabled gate sample warned as high variance
  - conclusion: the old April 4 repo note claiming dual-accum "regresses both surfaces" is stale,
    but the current evidence still does not justify promoting the path into the shipped default
- the arm64 unroll2 and cursor-reg surfaces were then reweighted on the actual post-CLI/current-tree
  baseline instead of the stale April 4 one:
  - generic and explicit wrappers now exist for both
    `make perf-probe-arm64-fast-dot-unroll2{,-list-int}` and
    `make perf-probe-arm64-fast-dot-single-pair-cursor-regs{,-list-int}`
  - the shipped arm64 dot baseline now keeps unroll2 off by default; real post-flip reruns
    (`build/logs/perf-probe-arm64-fast-dot-unroll2-20260409_030759_29018.log`,
    `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260409_030846_30731.log`) kept that
    20-instruction scalar loop ahead of `UNROLL2=1` on both raw medians
  - the scalar-tail `madd` structural guard was updated again after the default-off flip; latest
    verify log (`build/logs/verify_arm64_dot_madd_scalar_default_20260409_033658_82605.log`) now
    proves the shipped baseline at `21` instructions with `madd_count=0`, while `SCALAR=1` moves the
    same loops to `20` instructions with `madd_count=1`
  - the new scalar-core matrix wrappers replaced the older cursor-only interpretation:
    generic `dot_product` now likes both `SCALAR=1` and the combined cursor+scalar case, but
    explicit `dot_product_int` still regresses whole-operation gate on every non-baseline candidate.
    That keeps both cursor-reg disablement and scalar-`madd` promotion out of the shipped default.

This narrows one hot-loop gap without over-claiming broad arm64 parity. The broader production
blocker remains sustained native `dot_product` parity against vectorized C, not operator/tooling
reliability.

## 2026-04-09 Tier-1 tooling follow-up

The Tier-1 Linux/QEMU verification scripts also had a real operator-facing false red. The repo and
AGENTS documentation describe the persistent Ubuntu toolchain container by the stable name
`c7e5f7bd9f5c`, but several scripts treated `OREN_LINUX_DOCKER_ID` as if it had to be a literal
running container ID. That could fail even when the documented container name was correct and the
container was running under a different current ID.

Fix:

- added shared [scripts/linux_docker_lib.sh](/Users/zongbaolu/work/compiler-mini/scripts/linux_docker_lib.sh)
  to resolve `OREN_LINUX_DOCKER_ID` as a container name, full ID, or unambiguous ID prefix
- patched the Tier-1 Linux/QEMU callers:
  [setup_x64_linux_qemu_sysroot.sh](/Users/zongbaolu/work/compiler-mini/scripts/setup_x64_linux_qemu_sysroot.sh),
  [verify_x64_linux_qemu_smoke.sh](/Users/zongbaolu/work/compiler-mini/scripts/verify_x64_linux_qemu_smoke.sh),
  [verify_x64_linux_qemu_net_smoke.sh](/Users/zongbaolu/work/compiler-mini/scripts/verify_x64_linux_qemu_net_smoke.sh),
  [verify_x64_linux_qemu_tls_smoke.sh](/Users/zongbaolu/work/compiler-mini/scripts/verify_x64_linux_qemu_tls_smoke.sh),
  [verify_native_matrix.sh](/Users/zongbaolu/work/compiler-mini/scripts/verify_native_matrix.sh),
  and [verify_native_net_matrix.sh](/Users/zongbaolu/work/compiler-mini/scripts/verify_native_net_matrix.sh)
- patched [triage_native_slow_compile.sh](/Users/zongbaolu/work/compiler-mini/scripts/triage_native_slow_compile.sh)
  usage text so the operator contract matches the implementation

This does not claim Tier-1 x64 Linux is fully production-ready, but it removes a real verification
paper cut: the default documented container reference now resolves the way the repo says it should.
