# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode.

This file is the *single source of truth* for what to do next.

Priority model:

- **Order = priority.** The first unfinished item is the most urgent.
- We intentionally avoid fixed labels like “P0/P1”: the list is continuously reordered as reality changes.
- Completed items are moved to `docs/TODOS_ARCHIVE.md` to keep this file readable.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).
- Roadmap driver: production **server-side HPC** requirements (Eigen/BLAS-like workloads), see `docs/HPC_SERVER_PLAN.md`.

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims for the native backend** `[arch]`
   - **Native backend output** must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - The **C backend / C AVM** may use `libc` during bootstrap (like a normal C program), until the Oren-native runtime is complete.
   - Native runtime primitives must be implemented via `sys_*` + repo-owned ABI tables + `.oren` code (no host SDK dependence).

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - If code changes: run the canonical suite (preferred) `./oretest --target macos` (or `make test`).
   - If **docs-only** changes (only documentation files modified): tests are not required.
     - Allowed docs-only set: `docs/*`, `README.md`, `LICENSE`.

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

1) **[stdlib/tooling][ux] API docs via attributes (FastAPI-style ergonomics, OpenAPI export)**
   - DoD:
     - `oredoc openapi <meta.json>` emits a valid OpenAPI 3.1 document
     - no runtime dependency; purely compiler metadata → spec

2) **[stdlib][ux] `std/time` v0 (datetime-like, portable + deterministic surface)**
   - Goal:
     - Provide a modern time API usable for server-side apps and agentic tooling, while keeping
       deterministic execution possible in AVM mode.
   - DoD:
     - Add `lib/std/time.oren` with:
       - `Instant` + `Duration` (nanosecond precision, monotonic-safe arithmetic)
       - `now_unix_ns()` + `now_mono_raw()` plumbing (backend-specific; exposed via a stable stdlib API)
       - `sleep_ms(ms)` wrapper with clear semantics
       - `DateTime` UTC v0: epoch conversions + ISO-8601 parse/format (UTC-only v0; locale/tz later)
     - Add a module test covering parse/format roundtrip + monotonic non-decrease smoke

### B) AVM (evolves alongside language/compiler)

3) **[vm][safety] Record/Replay v1 for all effectful domains**
   - DoD:
     - record/replay for FS + NET + PROC + ENV + TIME + RNG
     - replay runs must not touch the host (even if the recorded run did)
     - replay logs are budgeted and portable (in-memory and file-backed)

4) **[vm][safety] Deterministic concurrency substrate (AVM tasks)**
   - DoD:
     - introduce `yield`/tasks with a deterministic scheduler mode (single-thread baseline)
     - define scheduling determinism (either deterministic policy or record/replay scheduling)
     - budgets propagate through task trees (structured concurrency)

5) **[vm][safety] Snapshot/restore format hardening + stability knobs**
   - DoD:
     - snapshot includes full VM state and validates on load
     - hash-friendly, chunkable layout (for swarm consensus + dedupe)
     - clear “rolling vs stable” policy for snapshots (separate from `.obc`)

6) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Casting: allow float→int cast sugar (`u8(1.9)`) via `oren_trunc_int`; allow `f32(16777217)` via numeric coercion; updated typecheck + tests; verified on macOS + Linux docker.
- Typed buffers + views: C backend runtime primitives in `lib/runtime_buf.c`, `std/buffer`, and an integration module test; fixed top-level var init ordering in the C backend; verified on macOS + Linux docker.
- `std/linalg` v0.2: added typed-buffer APIs + runtime AXPY intrinsics; arm64 NEON fast paths for i32 dot/reduce; fixed signed-overflow UB in i32 dot/reduce; verified on macOS + Linux docker.
- GC registry scaling: replaced linear `oren_find_node()` lookup with a pointer-indexed hash table and added a GC stress module test; verified on macOS + Linux docker.
