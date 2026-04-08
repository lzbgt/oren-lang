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
- The first implementation was not correctness-safe: with the fast path active, native benchmark
  smoke still produced the expected `array_sum` outputs (`205`, `710`), but `dot_product 10 3`
  crashed before returning `6590`.
- I kept the experiment only as an explicit opt-in compiler knob:
  - `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1`
  - `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`
- There is now a dedicated failure-aware probe:
  - `make perf-probe-arm64-fast-loop-prefix-zero`
  - Unlike the pair-post probe, it records wrapper and acceptance exit status per leg and only
    returns non-zero when the shipped default is broken.
- Current rerun (`build/logs/perf-probe-arm64-fast-loop-prefix-zero-20260408_224002_36344.log`):
  - shipped default:
    - `steady_array_sum ~2.1470x C`
    - `steady_dot_product ~2.9221x C`
    - `gate_array_sum ~1.9392x C`
    - `gate_dot_product ~2.7083x C`
    - disasm instruction counts: `52` / `70`
    - `debug_exit_code: 0`
  - enabled prefix-zero experiment:
    - `wrapper_exit_code: 2`
    - `exit_status: 2`
    - `failed_step: perf-smoke-native-fast-loops`
- Underlying failure log: `build/logs/perf-smoke-native-fast-loops-20260408_224013_36955.log`
  confirms the crash happens on native `dot_product 10 3` after `array_sum` already passed.
- Verification for the containment pass:
  - `make perf-smoke-native-fast-loops`
    - wrapper log: `build/logs/perf_smoke_native_fast_loops_prefix_zero_default_20260408.log`
    - smoke summary: `build/logs/perf-smoke-native-fast-loops-20260408_223942_35777.log`
  - `make perf-probe-arm64-fast-loop-prefix-zero`
    - wrapper log: `build/logs/make_perf_probe_arm64_fast_loop_prefix_zero_20260408_safe.log`
    - summary: `build/logs/perf-probe-arm64-fast-loop-prefix-zero-20260408_224002_36344.log`
  - `make test`
    - log: `build/logs/make_test_prefix_zero_containment_20260408.log`

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
