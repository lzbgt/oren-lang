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
   - If you add new files, you must `git add`/commit them before running the docker suite (otherwise the container won't see them).
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

1) **[lang][perf] SIMD surface + dispatch boundary (arm64 NEON first)**
   - DoD:
     - Define a stable intrinsic boundary (compiler-known names) for vector kernels
     - Add feature gating + scalar fallback (deterministic)
     - Expand `std/linalg` kernels safely (keep reference implementations)
   - Status:
     - **done (C backend):** NEON fast paths for typed-buffer kernels are gated by env (`OREN_ENABLE_SIMD=1`, `OREN_NO_SIMD=1`) and preserve scalar semantics.
     - **done (AVM):** `oren_buf_dot_i32` is wrap-safe (no signed overflow UB) and gains a NEON fast path behind `AVM_ENABLE_SIMD=1`.
     - **done (native runtime config):** `OREN_ENABLE_SIMD` is parsed once at startup and stored in native globals (future native NEON kernels can key off it).
     - **todo:** add native-backend NEON kernels (requires arm64 SIMD load/store + loop emission in the native codegen).

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- AVM snapshots v7: snapshot/restore now includes scheduler state (tasks + channels + queues) so spawned workloads can be paused/resumed.
- Bytecode backend: `oren_yield()` now returns canonical `nil` (stack-balanced as an expression), preventing verifier stack-height mismatches.
