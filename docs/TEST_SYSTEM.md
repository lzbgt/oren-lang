# Test & Build System (Rolling, Syscall-First)

This repo is intentionally in **rolling ABI** mode. The development constraint is:

- iteration must be **fast**
- tests must **never hang forever**
- failures must be **actionable** (logs, minimal noise)
- the toolchain must evolve toward **Oren-native tooling** (build/test), without forcing a big-bang rewrite.

This document explains the current state and the planned evolution.

## Current State (Today)

### 1) `make test` (shell runner, curated)

`make test` is a curated, timeout-protected suite intended for fast iteration:

- compiles and runs a curated list of **native backend** tests
- compiles and runs curated **C backend module** tests (module system coverage)
- compiles `.oren` → `.obc`, then runs curated **AVM** tests via `./avm`
- captures per-test logs under `build/logs/`
- prints **only summaries** on success; prints **details only on failures**

It requires `timeout` (Linux) or `gtimeout` (macOS coreutils).

### 2) `./oren test` (repo runner inside the compiler)

`./oren test` is the first step toward Oren-native tooling:

- same “curated + timeout + failure-only logs” philosophy
- implemented in `lib/compiler/compiler.oren`
- does not depend on Makefile semantics

Today it still shells out for filesystem ops (`mkdir`, `rm`, `cat`) and timeouts, because:

- the compiler itself should not grow “host FS syscalls” as a dependency prematurely
- we want correctness and iteration safety first

## Design Goals (What We’re Optimizing For)

1) **No hangs**: every build/run step has a wall-time timeout.
2) **Deterministic, replayable AVM**: AVM tests must be safe under snapshot/resume and record/replay.
3) **Syscall-first runtime**: native backend runtime is designed to be independent of libc shims (the syscall substrate is the long-term stable base).
4) **Minimal rewrite pressure**: migrate tooling incrementally.
5) **Composable tooling**: “compiler as a library” is a target state (for both Oren tools and AVM universes).

## Near-Term Roadmap (Incremental, No Big Rewrite)

### Phase A — Makefile becomes a thin wrapper

Goal: Makefile stays as a convenience entrypoint, but the canonical runner becomes `./oren test`.

Deliverables:

- `make test` calls `./oren test` (or stays in sync with it)
- `./oren test` gains parity with the curated Makefile behaviors (special AVM cases, feature guards)

### Phase B — Oren-native test manifest + structured output

Goal: remove most shell logic while keeping the same safety properties.

Deliverables:

- test manifests declared in `.oren` (or a small `tests/manifest.oren`)
- structured output:
  - summary `X/Y`
  - `failed:` list
  - stable log paths
- optional `--json` output for agentic tooling

### Phase C — Oren-native build/test language surface

Goal: a first-class Oren “tooling DSL” so the project does not depend on Make in production workflows.

Possible design:

- `oren test` evaluates a `tests/` manifest as Oren code (not shell)
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

