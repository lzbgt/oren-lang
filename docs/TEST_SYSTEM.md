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

It requires `timeout` (Linux) or `gtimeout` (macOS coreutils).

Legacy behavior (broader Makefile-driven lists) is preserved as:

- `make test-legacy`
  - note: `test-legacy` is now a **compatibility alias** for `./oretest --full` (broader curated coverage, still parallel).
  - the historical shell-heavy runner is kept only for reference as `make test-legacy-old` (and may be removed once confidence is high).

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
