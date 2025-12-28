# Test & Build System (Rolling, Syscall-First)

This repo is intentionally in **rolling ABI** mode. The development constraint is:

- iteration must be **fast**
- tests must **never hang forever**
- failures must be **actionable** (logs, minimal noise)
- the toolchain must evolve toward **Oren-native tooling** (build/test), without forcing a big-bang rewrite.

This document explains the current state and the planned evolution.

## Current State (Today)

### 1) `make test` (curated, timeout-protected)

`make test` is a curated, timeout-protected suite intended for fast iteration:

- runs the canonical curated runner: `./oretest --target macos`
- captures per-test logs under `build/logs/`
- prints **only summaries** on success; prints **details only on failures**
- runs tests/fixtures in parallel by default (bounded); tune with:
  - `OREN_TEST_JOBS` (`./oretest --jobs`)
  - `OREN_TEST_FIXTURE_JOBS` (`./oretest --fixture-jobs`)
  - `OREN_TEST_NATIVE_JOBS` (`./oretest --native-jobs`)
- build throughput note:
  - `./oretest` shells out to `./oren build ...` many times; `oren build` has a default-enabled build cache to keep repeated runs fast
  - default cache location is `./build/cache` (repo-local)
  - you can isolate cache state per run by setting `OREN_CACHE_DIR=...` or disable caching via `OREN_NO_CACHE=1`
  - `.obc` is an AVM artifact and is intended to be platform-neutral; `oren build --backend bytecode` uses an AVM ABI profile (`target=avm`, `arch=avm64`) to keep bytecode semantics stable across hosts
  - artifact layout note:
    - `oren build` has a repo-local default output layout under `build/targets/...`
    - `./oretest` passes explicit `-o ...` paths for fixtures/tests (so logs and cleanup lists stay stable), but those outputs now also follow the `build/targets/...` layout for the main suites:
      - native: `build/targets/<arch>-<os>/native/<test>`
      - c: `build/targets/<arch>-<os>/c/<test>`
      - bytecode: `build/targets/avm/bytecode/<test>.obc`
- quick bottleneck discovery:
  - `OREN_TEST_PROFILE=1 make test` (or `./oretest --profile`) prints the slowest tests (per-test elapsed time)
- SIMD validation note:
  - native SIMD is treated as an **optimization only** (scalar semantics are authoritative)
  - the native SIMD suite (`tests/native/test_simd_suite.oren`) is executed **twice**:
    - scalar baseline: `OREN_NO_SIMD=1` (expects `SIMD_ENABLED=0`)
    - SIMD run: `OREN_ENABLE_SIMD=1` (expects `SIMD_ENABLED=1`) and compares stable outputs to scalar
  - today, `./oretest` only performs the SIMD-on comparison when the *runner host* is `arm64` (NEON); x86_64 SIMD parity will expand this gate once SSE/AVX backends land
  - logs:
    - scalar: `build/logs/native_test_simd_suite.log`
    - SIMD: `build/logs/native_test_simd_suite_simd.log`
- rolling split (speed vs coverage):
  - default fast suite skips expensive fixture families (signing / OpenAPI export)
  - enable when needed:
    - `OREN_TEST_SIGNING=1 make test` (requires `./orensign`)
    - `OREN_TEST_OREDOC=1 make test` (requires `./oredoc`)
  - `make test-legacy` / `./oretest --full` implies those families (broader coverage)

It benefits from `timeout` (Linux) or `gtimeout` (macOS coreutils) as an outer failsafe, but it is not required for correctness.

Rolling update:

- `timeout`/`gtimeout` is **recommended** as an outer failsafe (Makefile uses it when present).
- `./oretest` also implements internal process-group timeouts and will warn (not fail) if `timeout` is missing.

Legacy behavior (broader Makefile-driven lists) is preserved as:

- `make test-legacy`
  - note: `test-legacy` is now a **compatibility alias** for `./oretest --full` (broader curated coverage, still parallel).
- the historical shell-heavy Makefile runner has been removed (rolling); use git history if you need to recover it.

### 2) `./oretest` (repo runner, outside the compiler)

`./oretest` is a repo-local test runner (currently written in Go):

- same “curated + timeout + failure-only logs” philosophy
- enforces SOLID by keeping repo test orchestration **out of** `lib/compiler/*.oren`
- shells out to:
  - `./oren` (self-hosted compiler binary) for compilation
  - `./avm` (C VM) for running `.obc` tests

This arrangement intentionally keeps “compiler as a library” as a future goal, without
forcing repo tooling concerns into the compiler sources today.

Rolling guidance:

- Prefer **integration-first fixtures** that exercise multiple language features at once.
- Keep Tier‑1 x86_64 validation small:
  - one local “builds exist” smoke that checks ELF+PE outputs
  - one opt-in remote-run smoke on real Win11+WSL2 (see `docs/REMOTE_X64_ENV.md`)
  - grow this set only when a regression escapes the integration suite.

## Design Goals (What We’re Optimizing For)

1) **No hangs**: every build/run step has a wall-time timeout.
2) **Deterministic, replayable AVM**: AVM tests must be safe under snapshot/resume and record/replay.
3) **Syscall-first runtime**: native backend runtime is designed to be independent of libc shims (the syscall substrate is the long-term stable base).
4) **Minimal rewrite pressure**: migrate tooling incrementally.
5) **Composable tooling**: “compiler as a library” is a target state (for both Oren tools and AVM universes).

## Near-Term Roadmap (Incremental, No Big Rewrite)

### Phase A — Makefile becomes a thin wrapper (now)

Goal: Makefile stays as a convenience entrypoint, but the canonical runner is `./oretest`.

Deliverables:

- `make test` calls `./oretest` (kept in sync)
- curated lists stay **short** and **integration-first**
- module tests run in parallel; AVM tests become parallel-safe by isolating per-test workdirs

### Phase B — Oren-native test manifest + structured output (later)

Goal: remove most shell logic while keeping the same safety properties.

Deliverables:

- test manifests declared in `.oren` (or a small `tests/manifest.oren`) **outside the compiler**
- structured output:
  - summary `X/Y`
  - `failed:` list
  - stable log paths
- optional `--json` output for agentic tooling

#### Proposed v0 spec (manifest + CLI)

This is the minimum bar for an Oren-native runner to replace most Makefile glue *without*
becoming a compiler-internal concern.

**Manifest file**

- Location: `tests/manifest.oren`
- The manifest is a normal `.oren` module that returns a list of test entries.
- Each entry is a plain map (stable keys, no reflection required):

  - `name`: string (stable identifier; used for filtering and log paths)
  - `kind`: string enum: `native|module|avm|fixture`
  - `path`: string (repo-relative source path)
  - `tags`: list[string] (e.g. `["fast","stdlib","serde"]`)
  - `timeout_ms`: int (wall clock; defaults by kind if omitted)

**Runner CLI**

- `oretest --list` prints stable test IDs (one per line).
- `oretest --filter <glob>` runs only tests whose `name` or `path` matches.
- `oretest --tag <tag>` runs only tests containing that tag (can repeat).
- `oretest --jobs <N>` controls parallelism (default: `min(num_cpu, 32)`).
- `oretest --json` emits a machine-readable JSON line per test result:
  - `{ "name": "...", "kind": "...", "path": "...", "ok": true|false, "ms": 123, "log": "build/logs/..." }`

**Text output contract**

Keep human output small and stable (agent-friendly):

- success: `X/Y <kind> tests passed`
- failure summary: `failed:` then indented list of test IDs + log file paths
- failure details: only show the tail of log by default; full log stays in `build/logs/`

### Phase C — Oren-native build/test language surface

Goal: a first-class Oren “tooling DSL” so the project does not depend on Make in production workflows.

Possible design:

- a future Oren-native successor to `./oretest` evaluates a `tests/` manifest as Oren code (not shell)
- a tiny “tooling runtime” provides:
  - process spawning with timeouts (PROC substrate)
  - structured logs
  - path utilities
  - host capability enrollment (explicit)

## Relationship to AVM & Multiverse

Long-term, parts of the build/test system can run inside AVM universes for:

- deterministic compilation capsules (“compile inside a capability-restricted universe”)
- replayable debugging (“replay the compiler run by hash”)

This is **not required** for the next milestones. The immediate goal is:

- syscall-first native backend correctness
- Oren-native tooling ergonomics
- deterministic AVM core primitives (snapshot/resume/record-replay)
