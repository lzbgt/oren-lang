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
     - Add **optional C-AVM NEON kernels** (behind build+runtime flags) for the hottest typed-buffer ops:
       - `dot_f64_4` and `gemm_f64_4x4` first (bit-exact vs scalar; preserves strict k-order).
       - then extend to `gemm_f32_4x4` and `gemm_i32_4x4` (still determinism-safe; scalar fallback remains authoritative).
   - Current rolling note:
      - Matmul now avoids per-k-block dot calls when **not packed** (Bt is contiguous per column, so we do a single dot/dot_4 across full `n`).
      - Packed-B matmul now packs directly from B (skips materializing full Bt transpose).
      - `matmul_i32_buf_wide` now matches the same packed/non-packed strategy, but stores full i64 accumulators.
      - Added `oren_buf_gemm_f32_4x4_slice_into` (native_id=128): 4×4 dot microkernel boundary returning 16 f64 results, with C runtime + native runtime + AVM parity.
        - Native runtime now uses a **true single-pass** intrinsic `simd_gemm_f32_4x4_ptr` (bit-exact vs scalar reference).
      - Added `oren_buf_gemm_i32_4x4_slice_into` (native_id=129): 4×4 i32 GEMM boundary returning 16 i64 results, with C runtime + native runtime + AVM parity.
      - Added `oren_buf_dot_f64_4_slice_into` (native_id=130): 1×4 f64 dot microkernel boundary returning 4 f64 results, used by `matmul_f64_buf` packed/non-packed paths to reduce interpreter/native overhead.
        - Native runtime now uses a **true single-pass** intrinsic `simd_dot_f64_4_ptr` (bit-exact vs scalar reference; preserves strict k-order).
      - Added `oren_buf_gemm_f64_4x4_slice_into` (native_id=131): 4×4 f64 GEMM microkernel boundary returning 16 f64 results, with C runtime + native runtime + AVM parity.
        - Native runtime now uses a **true single-pass** intrinsic `simd_gemm_f64_4x4_ptr` (bit-exact vs scalar reference; preserves strict k-order).
        - C AVM now has an optional **NEON** fast path for `native_id=131` when `AVM_ENABLE_SIMD=1` (bit-exact; lane-ordered accumulation).
      - C AVM now has optional **NEON** fast paths (bit-exact; lane-ordered accumulation) for:
        - `native_id=130` (`oren_buf_dot_f64_4_slice_into`) when `AVM_ENABLE_SIMD=1`
        - `native_id=122` (`oren_buf_dot_i32_4_slice_into`) when `AVM_ENABLE_SIMD=1`
        - `native_id=128` (`oren_buf_gemm_f32_4x4_slice_into`) when `AVM_ENABLE_SIMD=1`
        - `native_id=129` (`oren_buf_gemm_i32_4x4_slice_into`) when `AVM_ENABLE_SIMD=1`
        - `matmul_f64_buf` now uses a 4-row/4-col block path (packed and non-packed) to reuse packed-B across 4 rows and reduce call overhead.
      - C AVM now has optional **NEON** fast paths (wrap-safe integer accumulation) for:
        - `native_id=88` (`oren_buf_dot_i32_into`) when `AVM_ENABLE_SIMD=1`
        - `native_id=89` (`oren_buf_reduce_sum_i32_into`) when `AVM_ENABLE_SIMD=1`
      - Tail columns are covered in both packed and non-packed 4-row paths (`p % 4 != 0`).
      - Added `linalg.matmul_f32_buf_into(out, a, b, m, n, p)` to enable allocation-free HPC loops (caller owns output buffer).
      - Added `linalg.matmul_i32_buf_into(out, a, b, m, n, p)` for the same allocation-free pattern in integer GEMM paths.
      - Added `linalg.matmul_f64_buf_into(out, a, b, m, n, p)` and `linalg.matmul_i32_buf_wide_into(out, a, b, m, n, p)` so long-running HPC loops can reuse output buffers (even when keeping full i64 accumulators).

2) **[stdlib][net] Native networking foundations**
   - DoD:
     - Minimal syscall-first TCP stack surface (connect/listen/accept/read/write) + select/poll abstraction (`kqueue` on macOS; `epoll` later).
     - Clear separation between VirtualNET (pure) and HostNET (capability-gated).
   - Current rolling note:
     - Added `std/net/tcp` module (`lib/std/net/tcp.oren`) exposing the syscall-first TCP substrate as a stable stdlib surface.
     - `std/net/http` now implements `http.get_text(url, timeout_ms)` on top of `std/net/tcp` (no hidden runtime-only helper).

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM v2: hash-addressed artifacts + governance hooks**
   - DoD:
     - `.obc` artifacts are content-addressed and verifiable (hash IDs + manifest).
     - Governance hooks exist for module load policies (capsule-style).
     - Still no host FS effects when running compiler in a child universe (VirtualFS only).
   - Current rolling note:
     - `oren build` / `oren meta` now support `--manifest` to emit `<out>.manifest.json` with a stable `sha256` record (use with `--deterministic` for content-addressed builds).
     - When `oren build --backend native --metadata` is used, `--manifest` also emits a manifest for the metadata sidecar (`<out>.meta.json.manifest.json`).
     - `./oretest` has integration fixtures that assert `--manifest` output exists (and includes `size_bytes`) for bytecode builds, `oren meta`, and native `--metadata` sidecars.
     - Manifests now include `size_bytes` (deterministic) to support artifact caching/GC.

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][serde] Serde adaptors: tighten v1 surfaces**
   - Goal: keep the current JSON/YAML/CBOR v1 useful for real apps without pulling in a heavy toolchain.
   - DoD:
     - JSON/YAML decode: comment tolerance stays deterministic (already supported); improve diagnostics on malformed inputs.
     - CBOR: keep canonical map ordering and RFC 8742 sequence support; add roundtrip fixtures for nested shapes.
     - Ensure serde-generated helpers cover nested arrays/maps and preserve deterministic ordering.
