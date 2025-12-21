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

1) **[lang][perf] Allocator control for large numeric buffers (no-GC-scanned region)**
   - DoD:
     - Expose an allocation mode for large typed-buffer payloads that avoids GC scanning (mmap/arena backing)
     - Ensure alignment guarantees (cacheline + NEON-friendly) remain a performance property (no semantic change)
     - Add stress tests for fragmentation + OOM behavior
   - Status:
     - **done:** env-configurable raw mmap threshold (C + native) via `OREN_RAW_MMAP_THRESHOLD` (0 disables)
     - **done:** env-configurable typed-buffer alignment via `OREN_BUF_ALIGN=8|16|32|64` (default 64)
     - **done:** optional typed-buffer force-mmap via `OREN_BUF_FORCE_MMAP=1` (native)
     - **done:** `cmd/oretest` sanitizes these env vars to keep tests stable across user shells
     - **done:** stress/integration test `tests/modules/test_buffer_alloc_stress.oren` (fragmentation-style churn + explicit GC; covers RAW + RAW_MMAP)
     - **next:** add a deterministic “OOM/too-large” failure test only if we can catch/report allocation failure without crashing the whole process

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation
   - Plan (split into tractable milestones):
     - v0: compiler runs in AVM (host FS backend) to validate the loop (**DONE**: `compiler_in_avm_smoke` fixture)
     - v1: compiler reads/writes via VirtualFS (no host effects), and can run inside a child universe deterministically
     - v2: swarm governance + hash-addressed `.obc` artifacts

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][perf] `std/linalg` v0.3: matmul baseline + kernel dispatch**
   - DoD:
     - Provide baseline `matmul_f32` / `matmul_i32` using typed buffers + views
     - Pluggable kernel dispatch (scalar vs NEON) via intrinsic boundary
     - Add correctness tests (small shapes) + perf smoke test (no hard perf thresholds)
   - Status:
     - **done:** baseline typed-buffer matmul (`matmul_f32_buf`, `matmul_i32_buf`, `matmul_i32_buf_wide`) + module tests (`tests/modules/test_linalg.oren`)
     - **done:** initial kernel dispatch: matmul uses `B` transpose + `oren_buf_dot_*_slice` so native backend can hit NEON dot kernels without a full GEMM microkernel.
     - **done:** cache-aware scalar dispatch: matmul transposes `B` once and computes 4 columns at a time (j-block), reusing `A[i,k]` across columns while preserving per-output k-order determinism.
     - **done:** deterministic k-block tiling (KB=64) layered under the same per-output k-order semantics
     - **next:** optional packed-B tiles for larger matrices (still preserve per-output k-order determinism)
     - **done:** `dot_strided` primitive exists (`oren_buf_dot_*_strided`) for columnar access without transpose (still scalar today).

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Struct unification: `struct` values are map-shaped + mutable across backends (see archive entry).
- AVM snapshots v7: snapshot/restore now includes scheduler state (tasks + channels + queues) so spawned workloads can be paused/resumed.
- Bytecode backend: `oren_yield()` now returns canonical `nil` (stack-balanced as an expression), preventing verifier stack-height mismatches.
- Compiler-in-AVM v0 (host FS): self-hosted compiler builds to `.obc`, runs inside `./avm`, compiles a `.oren` fixture to `.obc`, and the result runs successfully.
  - Bytecode widening: added `CALL32`/`PUSH_FUNC32` (u32 addrs) and `LOAD/STORE_LOCAL16` (u16 locals) so the compiler `.obc` can exceed 64KB safely.
  - Import alias scoping: import aliases are now namespaced per-module in the linker so bytecode backends can resolve `alias.symbol` deterministically after merging modules.
  - Capability hardening: FS allow-prefix checks now normalize paths lexically (blocks `build/../...` traversal and allows `./tests/...` ergonomics).
- Native backend: arm64 NEON dot kernel is implemented and regression-tested under env-gated SIMD dispatch.
