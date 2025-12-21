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
  - when a file is over 3000 lines, refacotor to be SOLID principles applied modules
  - every 20 turns, fix the parity btw code implemented and docuemnents under docs/
  - every 10 turns, favor to prune this document of DONE tasks to TODOS_ARCHIVE.md, keep the todo list succint, if later tasks can be well deduced and tracked with context.

10) **Tests must target public tool surfaces** `[maint]`
   - Avoid importing `lib/compiler/*` inside `.oren` tests (couples tests to compiler internals).
   - Prefer using `./oren` subcommands (`build`, `meta`, etc.) and checking outputs via `cmd/oretest` fixtures.

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[stdlib][perf] SIMD + GEMM kernels (arm64 NEON first)**
   - Goal: keep scalar semantics; add NEON behind stable intrinsic/runtime boundaries.
   - DoD:
     - A f32/i32 matmul path that scales beyond “dot per element” while preserving deterministic k-order semantics.
     - C runtime + native runtime + AVM parity for any new kernel boundary.
     - A small correctness-only integration test (no perf thresholds) in the fast suite.
   - Next milestone (suggested):
     - Add a small **tile GEMM microkernel** (e.g. 4×4 or 2×4) for f32 and wire it into `lib/std/linalg.oren` packed path.
   - Current rolling note:
      - Matmul now avoids per-k-block dot calls when **not packed** (Bt is contiguous per column, so we do a single dot/dot_4 across full `n`).
      - Packed-B matmul now packs directly from B (skips materializing full Bt transpose).
      - `matmul_i32_buf_wide` now matches the same packed/non-packed strategy, but stores full i64 accumulators.
      - Added `oren_buf_gemm_f32_4x4_slice_into` (native_id=128): 4×4 dot microkernel boundary returning 16 f64 results, with C runtime + native runtime + AVM parity.
        - Native runtime SIMD path currently composes 4× `simd_dot_f32_4_ptr` (bit-exact, deterministic).
        - Native runtime now uses a **true single-pass** intrinsic `simd_gemm_f32_4x4_ptr`:
          - loads/widens each B column once per k-block and reuses across 4 rows
          - still widens to f64 and accumulates in deterministic increasing-k order (bit-exact vs scalar reference)
        - `lib/std/linalg.oren` packed matmul uses this boundary for 4-row blocks.

2) **[lang][hpc] Explicit numeric casts + fixed-width types (HPC/FFI-grade)**
   - DoD:
     - `u8/i32/u64/f32/f64` are first-class tokens in the language (not attribute hacks).
     - Float→int cast semantics: truncate toward zero (C-like), with explicit `round/floor/ceil` helpers as separate ops.
     - Cast lowering avoids runtime helper calls in provably-int-only paths.
   - Current rolling note:
      - Cast sugar (`u8(x)`, `i32(x)`, `f32(x)`, endian spellings) is lowered by `type_ann_lowering.oren` into deterministic bit ops.
      - Integer-only cast sites now skip the `oren_trunc_int(...)` helper when the expression is provably-int (reduces overhead in tight loops).

3) **[lang][meta] Attribute system v1 (serde + docs tooling)**
   - DoD:
     - Syntax is short and ergonomic (prefer `@pack`, `@serde(...)`, `@json(...)` without `@oren.` prefixes).
     - Unknown user-defined attributes are preserved deterministically in meta output.
     - A stable “meta emission” tool path exists (no ad-hoc print_meta stubs).

4) **[stdlib][net] Native networking foundations**
   - DoD:
     - Minimal syscall-first TCP stack surface (connect/listen/accept/read/write) + select/poll abstraction (`kqueue` on macOS; `epoll` later).
     - Clear separation between VirtualNET (pure) and HostNET (capability-gated).

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM v2: hash-addressed artifacts + governance hooks**
   - DoD:
     - `.obc` artifacts are content-addressed and verifiable (hash IDs + manifest).
     - Governance hooks exist for module load policies (capsule-style).
     - Still no host FS effects when running compiler in a child universe (VirtualFS only).

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][serde] YAML + CBOR adaptors**
   - DoD:
     - YAML supports comments (`#`) and is strict-but-friendly for config use.
     - CBOR supports arrays/maps and a streaming API suitable for large payloads.
     - Both integrate with the attribute/serde v1 plan (Task A4).
