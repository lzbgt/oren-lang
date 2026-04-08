# Production Readiness Review - 2026-04-08

## Scope

Reviewed the repo’s documented readiness posture and hardened the Go bootstrap CLI
surface in `cmd/oren`, which is still the first executable users and build scripts
depend on for stage0/stage1 bring-up.

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

## Tests added

Added bootstrap CLI regression coverage in `cmd/oren/main_test.go` for:

- host default target selection
- host default compiler selection on Windows
- build-arg parsing failures
- missing-file and usage diagnostics
- unknown-command non-zero exit behavior

## Verification run in this pass

Successful:

- `go test ./cmd/oren`
- `go test ./...`
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

This pass makes the **bootstrap CLI** materially safer and more production-like:

- correct host-aware defaults
- no crashy missing-arg path for `run`
- friendly diagnostics instead of panics on common failures
- non-zero exits for invalid invocation

That improves bring-up reliability, scripting safety, and operator UX, but it does not
erase the broader compiler/runtime maturity gaps that the project still documents as open.
