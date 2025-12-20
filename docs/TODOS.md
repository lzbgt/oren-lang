# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode.

This file is the *single source of truth* for what to do next.

Priority model:

- **Order = priority.** The first unfinished item is the most urgent.
- We intentionally avoid fixed labels like “P0/P1”: the list is continuously reordered as reality changes.
- Completed items are moved to `docs/TODOS_ARCHIVE.md` to keep this file readable.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims / no libc dependency** `[arch]`
   - Native backend output must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - Runtime must be implemented via `sys_*` primitives + `.oren` code.

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - If code changes: run the canonical suite (preferred) `./oretest --target macos` (or `make test`).
   - If **docs-only** changes (only `docs/*` modified): tests are not required.

6) **Keep this file actionable** `[maint]`
   - Each item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list *short and top-down prioritized* (target ~10–20 items max); merge and archive aggressively.
   - Repo must build from a clean clone: ignore build outputs only (do not accidentally ignore source dirs like `cmd/oren/` or `cmd/oretest/`).

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.
   - Do not wipe the container workspace by default; incremental builds must be possible (use an explicit clean flag when required).
   - Prefer syncing **tracked sources only** (git index) into `/work/repo` so host-built binaries never pollute the container workspace.
   - Forward feature flags via env (e.g. `OREN_TEST_FULL=1`) so Linux matches macOS runner behavior.
   - Remove stale build outputs (`oren`, `oretest`, `avm`) before running `make` to avoid timestamp skew from tar sync.

8) **Never generate `*.oren.c` next to sources** `[maint]`
   - `./oren_bootstrap build path/to/file.oren` writes `file.oren.c` next to sources; Make may then treat the source as a build target via implicit C rules.
   - Avoid running bootstrap builds on in-tree modules/tests/tools; prefer `./oren build ... -o build/...` or the curated runners (`make test`, `./oretest`).
   - If you *did* create `*.oren.c` artifacts, delete them before running `make test` (keep `oren.oren.c` only).

9) ** Refactor in rolling **
  - when a file is over 2000 lines, refacotor to be SOLID principles applied modules

10) **Tests must target public tool surfaces** `[maint]`
   - Avoid importing `lib/compiler/*` inside `.oren` tests (couples tests to compiler internals).
   - Prefer using `./oren` subcommands (`build`, `meta`, etc.) and checking outputs via `cmd/oretest` fixtures.

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[lang][safety] Troubleshooting & diagnostics (compiler + native runtime)**
   - DoD:
     - parse/compile errors include `file:line:col` when source spans are available
     - native backend must never “print and continue” on codegen errors; it must fail compilation with actionable messages
     - runtime panics/fails include function names and keep the stable `OREN_DIAG ...` one-liner (AI-friendly)
     - provide stable *tool surfaces* for debugging (no ad-hoc debug prints):
       - `oren dump tokens <file.oren> [-o out.json]` (token stream with spans)
       - `oren dump linked <file.oren> [-o out.json]` (linked/program summary)
       - `OREN_TRACE_PASSES=1` traces major compiler passes (for AI-friendly “what phase broke”)

2) **[lang][perf] Native backend optimizer baseline (no huge rewrite)**
   - DoD:
     - define a minimal IR boundary (or reuse current representation) that enables at least:
       - constant folding for numeric ops
       - dead-code elimination for unused locals/temporaries
       - peephole cleanup for redundant moves/loads
     - add a small microbenchmark `.oren` program in `examples/` + measure before/after in `docs/`
   - Status:
     - implemented a conservative AST/link-time optimizer pass: constant folding (small ints), peepholes, and trivial top-level DCE
     - added `examples/bench_opt_native.oren` as a baseline microbenchmark
     - fixed a native SIGILL regression found while enabling the optimizer: negative integer literals must not emit `MOVZ` with a negative imm16

3) **[lang][safety] “Production panic” diagnostics: spans + stable backtrace mapping**
   - DoD:
     - panics/errors include function + source span where available
     - metadata provides enough PC→span mapping for AVM traces and native panics (rolling schema OK)
     - oretest enforces machine-readable one-line `OREN_DIAG ...` + stable fields
   - Status:
     - native debug stack traces now print `file:line:col` for frames when built with `--debug` (via extended debug info table)

4) **[lang][arch] Module graph + reproducible builds (compiler surface)**
   - DoD:
     - stable module dependency graph export (JSON) for a build target
     - deterministic build ordering and deterministic artifact hashes in “deterministic mode”
   - Status:
     - module dependency graph export is available via `oren dump graph <file.oren>` (JSON, deterministic ordering)
     - `oren build --deterministic` emits stable `OREN_ARTIFACT ... sha256=...` hashes (oretest enforces bytecode reproducibility)
     - deterministic mode also hashes metadata sidecars (`--metadata` / `oren meta --deterministic`) as `kind=meta`
     - oretest also enforces deterministic `kind=meta` hashes
     - oretest covers both `oren meta` and `oren build --backend native --metadata` paths

5) **[lang][ux] Oren-native test runner direction (reduce Makefile coupling)**
   - DoD:
     - define minimal `.oren`-level test runner spec (output format, filters, JSON output)
     - keep `cmd/oretest` as orchestration for now, but document staged migration path

### B) AVM (evolves alongside language/compiler)

6) **[vm][safety] Record/Replay v1 for all effectful domains**
   - DoD:
     - record/replay for FS + NET + PROC + ENV + TIME + RNG
     - replay runs must not touch the host (even if the recorded run did)
     - replay logs are budgeted and portable (in-memory and file-backed)

7) **[vm][safety] Deterministic concurrency substrate (AVM tasks)**
   - DoD:
     - introduce `yield`/tasks with a deterministic scheduler mode (single-thread baseline)
     - define scheduling determinism (either deterministic policy or record/replay scheduling)
     - budgets propagate through task trees (structured concurrency)

8) **[vm][safety] Snapshot/restore format hardening + stability knobs**
   - DoD:
     - snapshot includes full VM state and validates on load
     - hash-friendly, chunkable layout (for swarm consensus + dedupe)
     - clear “rolling vs stable” policy for snapshots (separate from `.obc`)

9) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

10) **[stdlib][ux] API docs via attributes (FastAPI-style ergonomics, OpenAPI export)**
   - DoD:
     - `oredoc openapi <meta.json>` emits a valid OpenAPI 3.1 document
     - no runtime dependency; purely compiler metadata → spec

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Tooling: `oren dump tokens|linked <file.oren>` emits deterministic JSON for troubleshooting.
- Pass tracing: `OREN_TRACE_PASSES=1` prints major compiler phases during linking/compilation.
- Native debug traces: `--debug` builds now print `file:line:col` in stack traces (from debug info table), making panics AI-diagnosable without lldb.
- Tooling: `oren dump graph <file.oren>` exports a deterministic module dependency graph (JSON).
- Deterministic builds: `oren build --deterministic` emits stable `OREN_ARTIFACT ... sha256=...` hashes; oretest enforces bytecode reproducibility.
- Compiler diagnostics: lexer tokens now carry byte spans + file info; parse errors render `file:line:col`; native backend codegen errors fail the build with actionable locations.
- Runtime diagnostics: panics/fails emit a stable one-line `OREN_DIAG kind=... code=... msg=...` (AI-friendly; no lldb/otool needed).
- Attribute ergonomics: alias canonicalization (`@pack` → `@oren.packed`, `@abi` → `@oren.abi`, `@json.*` → `@serde.*`) keeps user code terse but metadata canonical.
- Verification loop: `oretest` is parallel + timeout-safe by default, and Linux/arm64 docker runner reuses a persistent container for fast smoke tests.
