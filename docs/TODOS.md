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
   - If the change touches the **compiler itself** (`oren.oren`, `lib/compiler/*`):
     - rebuild stage1 first: `make stage1`
     - then run: `./oretest --target macos`
   - If **docs-only** changes (only documentation files modified): tests are not required.
     - Allowed docs-only set: `docs/*`, `README.md`, `LICENSE`.

6) **Keep this file actionable** `[maint]`
   - Each item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list *short and top-down prioritized* (target ~10–20 items max); merge and archive aggressively.
   - Repo must build from a clean clone: ignore build outputs only (do not accidentally ignore source dirs like `cmd/oren/` or `cmd/oretest/`).
   - Test policy guard:
     - Default (fast) suite must stay **integration-first** and **small** (goal: ≤ ~3 module tests + ≤ ~8 AVM tests).
     - New fine-grained tests should go to `./oretest --full` unless they catch a regression that cannot be represented in an integration suite.

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

1) **[lang][quality] Typecheck mode v0: make `--typecheck` high-signal for HPC**
   - Goal: get production-grade errors early for typed code, without blocking rolling v0 code.
   - DoD:
     - Strengthen `./oren build --typecheck` to reject obviously invalid operations at annotated boundaries:
       - casts like `u8("x")`, `f32("x")`, `bool("x")` (unless explicit coercion is defined)
       - invalid `as` casts across categories (e.g. `bytes as i32` without a defined cast rule)
     - Ensure diagnostics are stable and point at user spans (not compiler-generated lowering).
     - Add/merge into the integration suite (no explosion of tiny tests).
   - Status:
     - **done:** numeric casts reject `string/bytes/list/map/buf` inputs when statically known.
     - **done:** `bool(...)` rejects `string/bytes/list/map` inputs when statically known (still allows numeric/bool/nil/unknown).
     - **done:** `as` casts are already desugared to cast calls and thus follow the same checks.

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation
   - Plan (split into tractable milestones):
     - v0: compiler runs in AVM (host FS backend) to validate the loop (**DONE**: `compiler_in_avm_smoke` fixture)
     - v1: compiler reads/writes via VirtualFS (no host effects), and can run inside a child universe deterministically
       - **done:** `avm.run_obc_bytes` supports `cfg["argv"]` (argv-as-data) and returns `vfs_snapshot` (AVMVFS01 bytes)
       - **done:** `./oretest --full` runs `compiler_in_avm_smoke` using a VirtualFS harness (no host FS in the nested compiler)
     - v2: swarm governance + hash-addressed `.obc` artifacts

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][perf] SIMD and numeric kernels (arm64 NEON first)**
   - Goal: keep scalar reference semantics, add NEON fast paths behind intrinsic boundaries.
   - DoD:
     - Keep deterministic rounding/order guarantees (increasing-k accumulation for matmul).
     - Expand NEON kernels beyond dot (e.g. axpy / small GEMM tiles) where safe.
     - Perf smoke stays “no thresholds”; correctness tests stay small and deterministic.

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Test runner: fast suite is now integration-first (added `tests/modules/test_integration_suite.oren` + merged native SIMD tests into `tests/native/test_simd_suite.oren`).
- Struct unification: `struct` values are map-shaped + mutable across backends (see archive entry).
- AVM snapshots v7: snapshot/restore now includes scheduler state (tasks + channels + queues) so spawned workloads can be paused/resumed.
- Bytecode backend: `oren_yield()` now returns canonical `nil` (stack-balanced as an expression), preventing verifier stack-height mismatches.
- Compiler-in-AVM v0 (host FS): self-hosted compiler builds to `.obc`, runs inside `./avm`, compiles a `.oren` fixture to `.obc`, and the result runs successfully.
  - Bytecode widening: added `CALL32`/`PUSH_FUNC32` (u32 addrs) and `LOAD/STORE_LOCAL16` (u16 locals) so the compiler `.obc` can exceed 64KB safely.
  - Import alias scoping: import aliases are now namespaced per-module in the linker so bytecode backends can resolve `alias.symbol` deterministically after merging modules.
  - Capability hardening: FS allow-prefix checks now normalize paths lexically (blocks `build/../...` traversal and allows `./tests/...` ergonomics).
- Native backend: arm64 NEON dot kernel is implemented and regression-tested under env-gated SIMD dispatch.
