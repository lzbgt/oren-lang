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
- Updated [README.md](/Users/zongbaolu/work/compiler-mini/README.md) and [docs/README.md](/Users/zongbaolu/work/compiler-mini/docs/README.md) so the quick-start docs match the actual repo entrypoints.

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
