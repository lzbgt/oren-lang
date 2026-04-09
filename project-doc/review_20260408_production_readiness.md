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
- the current remaining stage1 runtime suspicion is narrower than the broad quick harness:
  the intermittent green-cache `Indexing on non-container` retry has been tied to the
  `worker_green_local_ptr_survives_yields` region, so a focused reproducer is more useful than
  repeatedly rerunning the entire quick-integration fixture
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
  - `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM`
  - `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER`
  - `OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS`
  - `OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS`
  - `OREN_RUNTIME_ROBUSTNESS_STAGE2_BUILD_TIMEOUT_SECS`
- the bundled W5 runtime gate now prewarms host runtime astbin + debug rtobj seeds before the
  base quick-integration leg, and `make verify-native-quick-base-cold-seeded` proves the stage2
  base path can run with an empty active runtime cache via `phase=rtobj.seed_hit` instead of
  rebuilding from `rtobj.miss.build.start`

Additional runtime-robustness follow-up on 2026-04-09:

- added `tests/native/test_quick_integration_green_local_ptr_focus.oren`, which preserves the
  late-green prelude through `test_green_global_runq_fairness()` and then loops only
  `test_green_ctx_switch_alloc_integrity`, `test_green_local_ptr_survives_yields`,
  `test_green_workers_ctx_switch_alloc_integrity`, and
  `test_green_workers_local_ptr_survives_yields`
- added `scripts/triage_native_quick_green_local_ptr_flake.sh` plus the operator targets
  `make verify-native-quick-green-local-ptr-guarded` and
  `make test-native-quick-green-local-ptr-flake`
- the focused wrapper keeps strict no-retry semantics and enables `OREN_TRACE_LIST_GET_BAD=1`
  along with the existing runq / entry-args guards by default
- `scripts/verify_runtime_robustness_w5.sh` now includes this focused stage1 guard surface by
  default via `OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS`

Further refinement on 2026-04-09:

- split the focused local-ptr surface into explicit `plain` and `workers` halves via
  `scripts/triage_native_quick_green_local_ptr_plain_flake.sh` and
  `scripts/triage_native_quick_green_local_ptr_workers_flake.sh`
- added `scripts/verify_native_quick_green_local_ptr_modes.sh`, which runs those two halves
  sequentially with strict no-retry semantics; the operator entrypoint is
  `make test-native-quick-green-local-ptr-split-flake`
- that stricter split surface already reproduced a current-tree failure:
  `rc=138` in the `plain` half on run 3/3 while still in the
  `test_green_global_runq_fairness()` prelude
  (`build/logs/verify_native_quick_green_local_ptr_modes_20260409_065008.log`,
  `build/logs/oren_native_quick_flake_20260409_065015_run3_err.log`)
- because the split surface is already acting as a high-signal triage reproducer, the stable
  bundled guard targets continue to use the earlier blended local-ptr wrapper for now; the next
  runtime-robustness root-cause pass should start from the new split plain/workers scripts
- the active fairness crash on the prior tree turned out to be a worker-mode serialization hole,
  not just “one-arg scheduler volatility”: the green world-lock only engaged for
  `g_green_worker_count > 1`, which left the current `host + 1 worker` fairness reproducer
  unsynchronized. The runtime now enables the world lock by default for any worker-mode run unless
  the caller explicitly opts into `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`, and the host/poll paths
  now honor that at `1` worker too
- the sharp mixed fairness slice now has a harness-free direct reproducer at
  `scripts/triage_native_quick_green_fairness_onearg_h8_s1_direct_flake.sh`
  (`make test-native-quick-green-fairness-onearg-direct-flake`), which builds the focused fairness
  binary once and reruns the current `full` / `one_arg` / `notopology` / `hogs=8` / `shorts=1`
  slice directly
- after the single-worker world-lock fix, the old sharp `h8/s1` fairness crash no longer
  reproduces on the current tree. The new direct target passed 10/10
  (`build/logs/make_test_native_quick_green_fairness_onearg_direct_flake_20260409.log`), the
  one-arg count sweep passed every configured case including the earlier `hogs=8, shorts=1`
  failure slice
  (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_after_world_lock_fix_20260409.log`),
  and the full fairness mode matrix passed all seven slices 3/3
  (`build/logs/make_test_native_quick_green_fairness_modes_after_world_lock_fix_20260409.log`)
- that means the current tree no longer has an active fairness repro on the focused stage1
  surfaces. Fairness should remain triage-only until it has broader soak, but the old `h8/s1`
  failure is no longer the highest-signal blocker
- the wider runtime bundle and the repo-wide suite also stayed green on the same tree:
  `make verify-runtime-robustness` passed
  (`build/logs/make_verify_runtime_robustness_after_single_worker_world_lock_fix_20260409.log`,
  `build/logs/runtime_robustness_w5_20260409_090337.log`), and `make test` passed
  (`build/logs/make_test_single_worker_world_lock_fix_20260409.log`)
- added the dedicated fairness isolator `tests/native/test_quick_integration_green_fairness_focus.oren`,
  the strict wrapper `scripts/triage_native_quick_green_fairness_flake.sh`, and the matrix runner
  `scripts/verify_native_quick_green_fairness_modes.sh`
  (`make test-native-quick-green-fairness-flake`,
  `make test-native-quick-green-fairness-modes-flake`)
- fact from the new matrix on current `master`: the runtime crash is narrower than the earlier
  local-ptr story implied. `full + topology` passed 3/3, but `full` without topology failed
  immediately on run 1/3 with `rc=138`
  (`build/logs/verify_native_quick_green_fairness_modes_20260409.log`,
  `build/logs/oren_native_quick_flake_20260409_071639_run1_err.log`)
- the leaf fairness bodies `short_only` and `hogs_only` both passed 3/3
  (`build/logs/triage_native_quick_green_fairness_short_only_notopology_20260409.log`,
  `build/logs/triage_native_quick_green_fairness_hogs_only_notopology_20260409.log`)
- that means topology contamination is not required, and neither spawn shape fails by itself on
  this tree; the active root-cause surface is the mixed hog+short fairness interaction
- `lib/runtime_native/263_green/040_green_workers.oren` now GC-roots both `fn_obj` and
  `args_list` across the host-side world-lock / `_green_spawn_alloc_g(...)` path in
  `oren_green_spawn(...)` and `oren_green_debug_spawn_call_list_to_p(...)`
- after that root-lifetime fix, the fairness split no longer stays pinned to one short-arg shape.
  An earlier rerun shifted the `full` / no-topology / `zero_arg` slice from the old immediate
  `rc=138` crash to a strict green-cache retry (`rc=137` under `OREN_QI_FAIL_ON_RETRY=1`) on run
  2/3
  (`build/logs/triage_native_quick_green_fairness_full_notopology_zeroarg_postroot_20260409_075401.log`,
  `build/logs/oren_native_quick_flake_20260409_075404_run2_inner.log`), while the matching
  `one_arg` slice passed 3/3 then
  (`build/logs/triage_native_quick_green_fairness_full_notopology_onearg_postroot_20260409_075401.log`)
- on the latest rerun from the same tree, the split flipped again: the zero-arg mixed slice passed
  3/3 with zero retries
  (`build/logs/make_test_native_quick_green_fairness_zeroarg_flake_20260409.log`,
  `build/logs/oren_native_quick_green_fairness_full_notopology_zeroarg.log`), while the matching
  one-arg mixed slice failed immediately on run 1/3 with `rc=138`
  (`build/logs/make_test_native_quick_green_fairness_onearg_flake_20260409.log`,
  `build/logs/oren_native_quick_flake_20260409_080425_run1_err.log`)
- because of that, fairness remains triage-only. Keep the stable bundled gate on
  `make verify-runtime-robustness` and use
  `make test-native-quick-green-fairness-zeroarg-flake`,
  `make test-native-quick-green-fairness-onearg-flake`,
  `make test-native-quick-green-fairness-onearg-modes-flake`, and
  `make test-native-quick-green-fairness-modes-flake` as the active root-cause entrypoints.
- the latest one-arg leaf control proves the remaining crash still needs the mixed fairness
  interaction: `short_only` / `one_arg` passed 3/3
  (`build/logs/triage_native_quick_green_fairness_short_only_onearg_20260409.log`), while the
  mixed `full` / `one_arg` slice also failed with topology enabled
  (`build/logs/triage_native_quick_green_fairness_full_topology_onearg_20260409.log`)
- the fairness matrix wrappers now continue through every configured slice and print per-case
  PASS/FAIL summaries instead of exiting on the first failing case, so the full split signal is
  preserved in one triage run
- the first rerun of the dedicated one-arg matrix
  (`make test-native-quick-green-fairness-onearg-modes-flake`) came back green across the leaf
  control plus both mixed one-arg variants
  (`build/logs/make_test_native_quick_green_fairness_onearg_modes_flake_20260409.log`)
- treat that as more evidence of volatility rather than closure; the serial one-arg matrix is
  still the right entrypoint because it preserves all one-arg case outcomes together even when a
  single rerun does not reproduce the crash
- the new one-arg count sweep
  (`make test-native-quick-green-fairness-onearg-count-sweep-flake`) sharpened the mixed one-arg
  story further: `short_only` / `one_arg` / `shorts=40`, mixed `hogs=1, shorts=1`,
  mixed `hogs=1, shorts=8`, mixed `hogs=8, shorts=8`, and mixed `hogs=8, shorts=40`
  all passed in the same serial run, while mixed `hogs=8, shorts=1` failed with `rc=138`
  on run 2/3 (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_flake_20260409.log`,
  `build/logs/oren_native_quick_flake_20260409_084111_run2_err.log`)
- that reweights the active fairness repro again: it is not simply “more one-arg short tasks”
  and not just “full mixed one-arg”; the sharpest current slice is high hog pressure with very
  few one-arg short tasks
- the local-ptr fixture now has explicit `OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY` /
  `OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS` knobs, and the strict local-ptr wrappers now default
  fairness off plus `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=720`
- after fairness extraction, the mixed `both` local-ptr slice still reproduced a current-tree
  failure (`rc=139` on run 3/3 in
  `build/logs/oren_native_quick_flake_20260409_072245_run3_err.log`), while the serial split
  plain/workers surface passed with the widened timeout
  (`build/logs/make_test_native_quick_green_local_ptr_split_after_timeout_widen_20260409.log`,
  `build/logs/verify_native_quick_green_local_ptr_modes_20260409_072744.log`)
- because of that, the guard surface is now intentionally split: the blended
  `make test-native-quick-green-local-ptr-flake` remains a mixed-mode triage entrypoint, while
  `make verify-native-quick-green-local-ptr-guarded` and the local-ptr section of
  `make verify-runtime-robustness` use the stable split plain/workers path
- on the current tree after the single-worker world-lock fix, that older blended local-ptr
  failure no longer reproduces. The harness-based mixed `both` wrapper passed 3/3
  (`build/logs/make_test_native_quick_green_local_ptr_flake_after_single_worker_world_lock_fix_20260409.log`)
  and then a longer 10/10 no-retry soak
  (`build/logs/triage_native_quick_green_local_ptr_flake_10run_after_single_worker_world_lock_fix_20260409.log`)
- added a harness-free direct mixed-mode local-ptr reproducer
  `scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh`
  (`make test-native-quick-green-local-ptr-direct-flake`), which builds the focused fixture once
  and reruns the current `both` / topology-on / fairness-off slice directly
- guard policy is updated accordingly: `make verify-native-quick-green-local-ptr-guarded` and the
  local-ptr portion of `make verify-runtime-robustness` now use the stronger direct mixed-mode
  surface; the split plain/workers wrappers remain explicit triage tools, and the harness-based
  blended wrapper remains available when the broader quick-integration path itself needs rechecking

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

Additional runtime follow-up on 2026-04-09:

- `scripts/run_native_quick_integration.sh` now runs the entire post-phase follow-on smoke block
  through checked build/run helpers instead of mixing guarded phase logic with unguarded late
  smokes
- timeout-like follow-on smoke exits now get per-smoke reruns via
  `OREN_QI_FOLLOWON_SMOKE_RETRIES` (default `1`)
- the inner quick-integration log now carries explicit `ok:` markers for the late smokes and a
  final `native quick integration follow-on OK` stamp
- this closes the remaining late `test-native-quick` `Error 143` blind spot where the inner log
  could stop after `Build successful: ...loop_list_reuse_escape_smoke` without identifying the
  last completed smoke

Verification for this follow-up:

- direct `./scripts/run_native_quick_integration.sh ./oren`
  - log: `build/logs/native_quick_followon_guard_20260409.log`
- `make test`
  - log: `build/logs/make_test_native_quick_followon_guard_20260409.log`
  - note: the verification run still exercised the existing stage1 base-run timeout retry once
    (`WARN: timeout (rc=143). Retrying with 720s.` in
    `build/logs/oren_native_quick_integration.log`), but it stayed green and the new follow-on
    markers proved the late-smoke block completed.

Additional runtime follow-up later on 2026-04-09:

- `scripts/run_native_quick_integration.sh` now also accepts `OREN_QI_STOP_AFTER_BASE=1`
- the stage1 base-only path now stamps `native quick integration base phase OK` plus
  `skip_reason=OREN_QI_STOP_AFTER_BASE=1` into the inner log
- the new wrapper `scripts/triage_native_quick_base_flake.sh` feeds that base-only path through
  the existing flake harness with `OREN_QI_TRACE=1`, giving a cheap per-test-progress reproducer
  for the remaining stage1 base-run timeout/retry path
- `make verify-native-quick-base-guarded` is now the dedicated 3-pass gate for that surface
- `scripts/verify_runtime_robustness_w5.sh` now also runs that base-only stage1 surface by
  default, so the main W5 runtime-robustness bundle finally covers both active stage1 quick
  guard paths instead of leaving the base-only timeout/retry path as a side target
- the latest full `make test` on that tree reached `native quick integration follow-on OK`
  without reproducing the older stage1 base-run timeout retry
- the same latest full run still logged a green-cache retry after `Indexing on non-container`
  in `__oren_fnwrap_worker_green_local_ptr_survives_yields`, so focused stage1 wrappers should
  fail on hidden retries instead of silently passing
- the clean sequential rerun of that stricter green-cache reproducer later on the same day passed
  3/3 with `retry_*_count=0`, so the issue remains intermittent rather than a stable current repro
- the final full-suite rerun on the same tree also reached `native quick integration follow-on OK`
  with `retry_*_count=0` in the inner quick log (`build/logs/make_test_retry_summary_20260409.log`)

Verification for this follow-up:

- direct base-only run:
  - `build/logs/native_quick_base_only_direct_20260409.log`
- focused 3-pass base-only gate:
  - `build/logs/make_verify_native_quick_base_guarded_20260409.log`
  - inner traced run log: `build/logs/oren_native_quick_base_only.log`
- bundled W5 runtime-robustness gate:
  - `build/logs/make_verify_runtime_robustness_base_bundle_20260409.log`
  - detailed bundle log: `build/logs/runtime_robustness_w5_20260409_054902.log`
- full-suite verification on the same tree:
  - `build/logs/make_test_runtime_base_bundle_20260409.log`
  - inner quick logs: `build/logs/oren_native_quick_base_only.log`,
    `build/logs/oren_native_quick_integration.log`
- focused no-retry stage1 gates:
  - `make verify-native-quick-base-guarded`
  - `make test-native-quick-green-cache-flake`
  - latest clean strict green-cache log: `build/logs/make_test_native_quick_green_cache_flake_strict_20260409.log`

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

Get-sum-specific follow-up (2026-04-09):

- the old family probe was still the wrong shipping surface for the explicit get-sum leg, so I
  added:
  - `make perf-probe-arm64-fast-get-sum-pair-post-list-int`
  - `make perf-probe-arm64-fast-get-sum-pair-post-decision`
- the new decision probe
  (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`)
  isolates `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1` on the shared `array_sum_int`
  acceptance bundle plus same-tree exact `perf-probe-list-int-c-ceiling` reruns
- result:
  - local acceptance wrapper strongly preferred enabled
    - `enabled_steady_array_sum_int_native_median_delta_pct: -26.20%`
    - `enabled_gate_array_sum_int_native_median_delta_pct: -53.71%`
  - exact whole-operation surface still preferred shipped default
    - `default_array_ratio_median: ~2.3604x`
    - `enabled_array_ratio_median: ~2.4015x`
    - `array_default_wins: 3/5`
  - exact `dot_product_int` also stayed slightly better on default
    - `default_dot_ratio_median: ~1.8539x`
    - `enabled_dot_ratio_median: ~1.8578x`
- corrected conclusion:
  - keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST` opt-in only
  - the acceptance wrapper is useful as a local sanity surface, but not as the shipping
    ranking surface for this branch

Fill-share follow-up (2026-04-09):

- the next unresolved question after the rejected get-sum micro-branches was whether the remaining
  `array_sum_int` cost on the shipped unroll2-on tree was still mostly the repeated read loop or if
  list build/fill had become material again
- I added:
  - hidden fill-only benchmark pair:
    - `benchmarks/fill_list_int/fill_list_int.oren`
    - `benchmarks/fill_list_int/fill_list_int.c`
  - new decision surface:
    - `make perf-probe-list-int-fill-share-decision`
- current artifact:
  - `build/logs/perf-probe-list-int-fill-share-decision-20260409_181428_58993.log`
- current measured result:
  - fill-only Oren `list<int>`: `per_rep_s ~0.005037`
  - fill-only slot64 C vector: `per_rep_s ~0.001044`
  - fill-only slot64 C scalar: `per_rep_s ~0.001462`
  - exact `array_sum_int` breakdown on the same tree:
    - Oren setup estimate: `~0.008520s`
    - Oren steady per-rep: `~0.000490s`
    - slot64 C vector steady per-rep: `~0.000194s`
  - derived:
    - `oren_fill_list_int / c_fill_slot64_vector ~4.8260x`
    - `oren_fill_list_int / oren_array_sum_setup_est ~0.5912x`
    - `oren_fill_list_int / oren_array_sum_steady_per_rep ~10.2796x`
- corrected reweighting:
  - the repeated read loop is still above the slot64 C vector ceiling
  - but the list build/fill side is materially larger in absolute time than the current shipped
    steady read kernel, so the next optimization class should move back toward list
    allocation/push lifetime/setup rather than more get-sum-local loop-body branches

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
- But the production metric was wrong: the refreshed post-unroll2 decision probe
  (`build/logs/perf-probe-arm64-whole-list-get-sum-helper-decision-20260409_173112_97220.log`)
  makes the current-tree split explicit.
  - exact `array_sum_int`: shipped default `~1.9974x` vs helper-enabled `~13.6272x`
    (`exact_array_winner: default`, helper/default `~6.8225x`)
  - exact `dot_product_int`: shipped default `~1.7628x` vs helper-enabled `~1.8728x`
  - small read-split hidden helper ceiling remains context only:
    `slot_direct_array_long_per_rep ~1.0113x`,
    `slot_direct_vs_canonical_array_long_per_rep ~0.7866x`
- Result:
  - `OREN_NATIVE_FAST_LIST_INT_GET_SUM_WHOLE_LIST_HELPER`
  - `OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER`
  remain in-tree only as opt-in experiments; they are not production defaults.

Shared slot-direct stdlib follow-up (2026-04-09):

- The repo already had direct-slot runtime helpers plus hidden benchmark-only entrypoints, but that
  was still a tooling gap: there was no shared/public stdlib surface for “use the direct-slot path
  when safe, otherwise stay correct”.
- Fix in this pass:
  - added `linalg.reduce_sum_i64_list_int_slots(...)`
  - added `linalg.dot_i64_list_int_slots(...)`
  - on C/native/AVM, those entrypoints now use `oren_is_list_int(...)` and the direct-slot helper
    surface when the runtime can prove an all-int list
  - otherwise they fall back to a portable scalar list walk so generic list callers stay correct on
    bytecode too
  - widened `tests/fixtures/list_int_dot_sum_smoke.oren` so `make verify-backend-parity-list-int`
    exercises the new public slot-direct surface instead of only the older manual list loops
- Adjacent verifier fix:
  - all backend parity scripts now default `OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS=120` instead of
    `20`, aligning them with the repo-wide build watchdog and avoiding false `124` exits when a
    parity run queues behind the shared compiler-build lock or a cold stage2 rebuild
- Measured slot-surface follow-up:
  - the helper smoke/prebuild surface now also covers hidden public-slot benchmarks
    `array_sum_int_slot_public` / `dot_product_int_slot_public`
  - `make verify-native-slot-direct` inherits that widened native smoke, so the public surface is
    covered alongside the raw helper contracts
  - added `make perf-probe-list-int-slot-surface-read-split` to compare the shipped canonical
    loops, the hidden helper ceiling, and the new public `std:linalg` slot wrappers on the same
    short/long harness
  - latest no-smoke artifact:
    `build/logs/perf-probe-list-int-slot-surface-read-split-20260409_044605_90580.log`
  - whole-operation long-per-rep summary:
    - `array_sum_int`: canonical `~1.3454× C`, hidden helper `~1.0479× C`, public wrapper
      `~1.2686× C`
    - `dot_product_int`: canonical `~1.4701× C`, hidden helper `~1.1698× C`, public wrapper
      `~1.2188× C`
  - interpretation:
    - the public slot wrapper is materially better than the shipped canonical path on both
      benchmarks
    - it still trails the raw helper ceiling, but only narrowly on `dot_product_int`
    - split deltas are still noisy here, so tracker updates should keep using `long_per_rep`
    - the next direct-slot follow-up should be wrapper/boundary-overhead reduction or more direct
      lowering against the public slot surface, not more packed-bridge work
- Public-slot fast-path collapse follow-up:
  - the first public wrapper pass still paid extra high-level overhead even when the input was
    already a proven `list<int>`:
    - `dot.reduce_sum_i64_list_int_slots(...)` front-loaded `list.len(...)` before checking
      `oren_is_list_int(...)`
    - `dot.dot_i64_list_int_slots(...)` front-loaded generic `_vec2_len(...)`
    - `std:linalg.reduce_sum_i64_list_int_slots(...)` / `dot_i64_list_int_slots(...)` also bounced
      through an extra module wrapper before reaching the raw helper
  - fix in this pass:
    - `std:linalg/dot` now checks `oren_is_list_int(...)` first and only does the generic scalar
      fallback work when the fast path does not apply
    - the top-level `std:linalg` facade now jumps straight to the raw helper on proven `list<int>`
      inputs, while preserving typed length-mismatch semantics as errors via `list.int_len(...)`
    - tests now explicitly cover typed-list mismatch on the public slot surface
  - new steady ranking surface:
    - `make perf-probe-list-int-dot-ceiling` now includes the public-slot benchmarks
      `array_sum_int_slot_public` / `dot_product_int_slot_public`
    - latest artifact:
      `build/logs/perf-probe-list-int-dot-ceiling-20260409_050407_19366.log`
    - ranking on that run:
      - `dot_product_int`: canonical `~1.3657× C`, hidden helper `~1.0803× C`, public slot
        `~1.1062× C`
      - `array_sum_int`: canonical `~1.3992× C`, hidden helper `~0.9836× C`, public slot
        `~1.2014× C`
	- read-split caution:
	  - the smoke-on rerun
	    `build/logs/perf-probe-list-int-slot-surface-read-split-20260409_050248_17126.log`
	  and the no-smoke rerun
	    `build/logs/perf-probe-list-int-slot-surface-read-split-20260409_051528_36514.log`
	  disagree on public-vs-helper ordering, so the split surface is still too noisy to use as the
	  primary ranking signal
	  - use the steady ceiling probe above for the current public-slot ordering, and keep the
	    read-split probe as a sanity/regression check only
	- Checked-helper contract + unchecked-len follow-up:
	  - the previous pass still had one backend mismatch hidden under the public-slot work: AVM
	    returned structured `invalid_arg` errors from the checked raw slot helpers, while the native
	    runtime bundle still panicked on the same bad inputs
	  - fix in this pass:
	    - native checked raw helpers now return structured `invalid_arg` errors, matching AVM/C
	      behavior
	    - `make verify-native-slot-direct` now checks both the checked-helper error contract and the
	      unchecked-helper panic contract
	    - the public `std:linalg` fast path keeps the cheaper unchecked raw helper once
	      `oren_is_list_int(...)` has already proven the input, but now uses
	      `oren_list_int_len_unchecked(...)` for the typed mismatch guard instead of paying
	      `list.int_len(...)` again
	  - latest steady ranking surface:
	    - `build/logs/perf-probe-list-int-dot-ceiling-20260409_113946_99659.log`
	    - `dot_product_int`: canonical `~1.3221× C`, hidden helper `~1.0920× C`, public slot
	      `~1.2079× C`
	    - `array_sum_int`: canonical `~1.4110× C`, hidden helper `~1.0019× C`, public slot
	      `~1.0800× C`
		  - interpretation:
		    - the public slot surface remains behind the hidden helper ceiling, but the residual gap is
		      still materially smaller than the older tracker state on both steady benchmarks
		    - this is still a wrapper/helper convergence problem, not a reason to reopen packed-bridge
		      work
		    - internal `oren_list_int_*_slots_try_fast(...)` helpers now exist across C/native/AVM for
		      future lowering experiments, but a direct public reroute through that helper surface
		      regressed badly on the same steady probe
		      (`build/logs/perf-probe-list-int-dot-ceiling-20260409_113108_86448.log`:
		      public-slot `dot_product_int` `~3.2619× C`, public-slot `array_sum_int` `~2.1178× C`), so
		      that route remains internal-only
			    - later the same day, the arm64 compiler-side list fast-loop validation was converged onto
			      the same `native_alloc_index_get` lookup x64 already uses instead of the older
			      `oren_find_node` path in `lib/compiler/arm64_native_stmt_loops_list_emit.oren`
			    - that convergence stayed correctness-clean and two serialized steady reruns both improved
			      the shipped canonical path versus the earlier snapshot:
			      - `build/logs/perf-probe-list-int-dot-ceiling-20260409_115936_33151.log`
			        canonical `array_sum_int` `~1.2173× C`, canonical `dot_product_int` `~1.3071× C`
			      - `build/logs/perf-probe-list-int-dot-ceiling-20260409_120228_38413.log`
			        canonical `array_sum_int` `~1.2781× C`, canonical `dot_product_int` `~1.2155× C`
			    - the direct-slot/public ordering still flipped between those light reruns, so this was a
			      real canonical-baseline win but still not a stable new helper/public ranking
			    - the stronger follow-up is now
			      `make perf-probe-list-int-dot-ceiling-stability`
			      (`build/logs/perf-probe-list-int-dot-ceiling-stability-20260409_123207_90132.log`),
			      which rotates baseline / direct-slot / public-slot / packed-scalar / packed-SIMD across
			      five sweeps (`runs=3`, `warmups=1`, `n=20000`, `reps=4`)
			    - on that order-balanced surface:
			      - `array_sum_rank_counts`: canonical `2/5`, direct-slot `2/5`, public-slot `1/5`
			      - `dot_product_rank_counts`: canonical `3/5`, public-slot `2/5`, direct-slot `0/5`
			      - median `array_sum_int`: canonical `~1.1887× C`, direct-slot `~1.2329× C`,
			        public-slot `~1.2729× C`
			      - median `dot_product_int`: canonical `~1.2177× C`, public-slot `~1.2231× C`,
			        direct-slot `~1.3097× C`
				    - that is the new production-quality ranking fact on current arm64 `master`: the shipped
				      canonical path is now the best repeated whole-operation median on both benchmarks,
				      public-slot remains close enough to win some `dot_product_int` sweeps, and the hidden
				      direct-slot helper is no longer a stable whole-operation winner
						    - the new broader host-C ceiling follow-up is now
						      `make perf-probe-list-int-c-ceiling`
						      (`build/logs/perf-probe-list-int-c-ceiling-20260409_132256_79494.log`), which widens the
						      earlier dot-only slot-ABI ceiling across both canonical benchmarks by comparing packed32
						      C, slot64 C, and shipped Oren native whole-operation binaries under one workload
						    - on that surface:
						      - `array_sum_int`: packed32 C vector `~0.000136s`, slot64 C vector `~0.000246s`,
						        slot64 C scalar `~0.000774s`, Oren canonical `~0.001327s`
						      - `dot_product_int`: packed32 C vector `~0.000264s`, slot64 C vector `~0.000736s`,
						        slot64 C scalar `~0.000804s`, Oren canonical `~0.001360s`
						      - decisive ratios:
						        - `array_slot64_vector / array_packed32_vector`: `~1.8165×`
						        - `oren_array_sum_int / array_slot64_vector`: `~5.3848×`
						        - `dot_slot64_vector / dot_packed32_vector`: `~2.7825×`
						        - `oren_dot_product_int / dot_slot64_vector`: `~1.8485×`
						    - the new explicit get-sum single-list cursor-reg follow-up
						      (`build/logs/perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int-20260409_130055_41301.log`)
						      is worth keeping but deliberately narrow: default steady native median improved from
						      disabled `0.134232s` to `0.133314s`, the disabled gate leg warned as high variance, and
						      both legs kept the same 16-instruction traced loop
						    - the new explicit push single-list cursor follow-up
						      (`build/logs/perf-probe-arm64-fast-push-single-list-cursor-list-int-20260409_132214_76347.log`)
						      is also worth keeping: default steady native median improved from disabled `0.136291s`
						      to `0.131530s`, gate native improved from disabled `0.010571s` to `0.010084s`, and both
						      legs kept the same 16-instruction traced loop
						    - the new setup-vs-steady attribution probe
						      (`build/logs/perf-probe-list-int-array-sum-c-breakdown-20260409_143718_76549.log`)
						      closes the remaining “maybe setup dominates” question on the exact `array_sum_int`
						      workload as far as this current surface can support: the short-run setup estimate
						      is still noisy, but the steady per-rep gap remains the stronger fact (`~0.001311s`
						      for Oren canonical vs `~0.000204s` for slot64 C vector, or `~6.4228×`)
							    - the new explicit get-sum tick-mask sweep
							      (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-list-int-20260409_143632_74801.log`)
							      is why `OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK` still ships at `4095`: explicit
							      `16383` and `65535` improved steady native medians on that sample, but the gate view
							      stayed too noisy to trust as a production default (`c_cov=0.6421` at shipped `4095`,
							      `0.2631` at `16383`, `0.1270` at `65535`)
							    - the explicit get-sum unroll2 follow-up
							      (`make perf-probe-arm64-fast-get-sum-unroll2-list-int`) is no longer a
							      default-off dead branch: the earlier crashy candidate was root-caused in
							      `lib/compiler/arm64_native_stmt_loops_list_emit.oren`, where the experimental
							      unrolled bodies were clobbering reserved heap registers `X27` / `X28`
							    - those loop-body value temps now use caller-saved `X12` / `X13`, and
							      `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2` now ships on by default for
							      single-read-list shapes while staying overrideable for A/B and emergency disable
							    - the promoted exact whole-operation rerun
							      (`build/logs/perf-probe-list-int-c-ceiling-20260409_163202_21950.log`) now keeps
							      `oren_array_sum_int / array_slot64_vector ~2.3939×` and
							      `oren_dot_product_int / dot_slot64_vector ~1.8678×`
								    - the broad integrated gates that previously rejected the candidate now pass in
								      `build/logs/make_test_get_sum_unroll2_promote_20260409.log`,
								      `build/logs/make_verify_runtime_robustness_get_sum_unroll2_promote_20260409.log`,
								      and `build/logs/runtime_robustness_w5_20260409_163313.log`
								    - the new combined decision probe
								      (`build/logs/perf-probe-arm64-fast-get-sum-unroll2-decision-20260409_170812_66742.log`)
								      now records the same-tree disagreement instead of leaving it implicit:
								      acceptance steady still preferred disabled (`-4.79%`), acceptance gate slightly
								      preferred default (`+0.78%`), but exact whole-operation `array_sum_int`
								      preferred the shipped default in all three sweeps (`~2.3793×` vs disabled
								      `~5.3859×`, `array_default_wins: 3/3`)
								    - exact `dot_product_int` stayed mixed in that same probe (`default ~1.8343×`,
								      disabled `~1.8138×`, disabled wins `2/3`), which is consistent with this knob
									      being a get-sum / `array_sum_int` decision rather than a general dot-path win
									    - so exact whole-operation ceiling plus integrated green lanes remain the shipped
									      decision surface for this path, not the local acceptance micro-probe by itself
									    - the next explicit get-sum follow-up now closes another tempting but wrong branch:
									      `build/logs/perf-probe-arm64-fast-get-sum-dual-accum-decision-20260409_174904_22327.log`
									      compares the shipped default against
									      `OREN_ARM64_FAST_LIST_INT_GET_SUM_DUAL_ACCUM=1` and shows the same kind of surface
									      split even more sharply. The local acceptance wrapper preferred the enabled branch
									      (`steady -19.53%`, `gate -52.65%`), but the widened same-tree exact whole-operation
									      reruns still preferred the shipped default in `4/5` sweeps
									      (`default median ~2.2506×`, enabled median `~2.2797×`). So the dual-accum path is
									      now factually downgraded to opt-in experiment only, not a production candidate.
								    - reweight accordingly: the get-sum tick-mask probe
							      is worth keeping but is still not the missing slot64-vector parity fix
						    - that is the stronger whole-operation blocker split on current arm64 `master`: the
						      helper/public-slot routing question is no longer the main issue, and the new get-sum
						      and push cursor cleanups are not the missing whole-operation `array_sum_int` fix.
						      The setup-vs-steady split now says the same thing more directly: the repeated get-sum
						      kernel still dominates the remaining gap.
						      `array_sum_int` still leaves a large gap to a competitive slot64 host-C vector path,
						      while `dot_product_int` still sits materially above even the slot64 host-C ceiling
						      inside the current 64-bit slot ABI.
			- Probe UX follow-up:
	  - related list-int probe scripts now honor the repo-wide `OREN_PERF_SMOKE_LIST_INT=0` knob as a
	    fallback instead of requiring only per-script smoke env vars, which removes a real measurement
	    consistency footgun during no-smoke reruns

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
