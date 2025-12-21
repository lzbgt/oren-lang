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

1) **[lang][perf] Native-backend arm64 NEON kernels: typed buffers (Eigen/BLAS driver)**
   - DoD:
     - Add native-backend NEON kernels for `i32_buf` / `f32_buf` hot loops with scalar fallback
     - Validate scalar vs SIMD equivalence under env toggles (`OREN_ENABLE_SIMD=1`, `OREN_NO_SIMD=1`)
     - Keep compiler intrinsics as the stable “dispatch boundary” (no libc, no SDK headers)
   - Status:
     - **done:** native `oren_buf_dot_i32` NEON fast path via intrinsic `simd_dot_i32_ptr(a_ptr,b_ptr,n)->i64` + scalar tail.
     - **next:** add native NEON for `i32_buf` add/mul into (in-place destination) and extend regression tests.
     - **next:** add native NEON for `f32_buf` add/mul/dot with deterministic semantics (likely f64 accumulation for dot).
     - **done:** native NEON for `i32_buf` add/mul into via intrinsics `simd_add_i32_ptr` / `simd_mul_i32_ptr` + scalar tail; validated by native test (`tests/native/test_simd_i32_buf_ops_native.oren`).
     - **done:** native NEON for `f32_buf` add/mul into via intrinsics `simd_add_f32_ptr` / `simd_mul_f32_ptr` + scalar tail; validated by native test (`tests/native/test_simd_f32_buf_ops_native.oren`).
     - **done:** native NEON for `f32_buf` dot via intrinsic `simd_dot_f32_ptr(a_ptr,b_ptr,n)->f64bits` (widen to f64 + scalar-ordered accumulate); validated by native test (`tests/native/test_simd_dot_f32_native.oren`).

2) **[lang][perf] Typed views: slice + stride (HPC + syscall-first parsing)**
   - DoD:
     - Define a minimal `slice`/`view` shape (`ptr + len`), then a `stride` matrix view (`ptr + rows + cols + stride`)
     - Keep views non-owning and bounds-checked; no host-endian dependence
     - Implement across backends (C/native/bytecode) as a stable surface
   - Status:
     - **done:** `std/buffer` slice views (`slice_new`, `slice_load/store_{u8,i32,f32}`) + matrix views (`mat_view_new`, `mat_load/store_{f32,i32}`)
     - **next:** add view helpers for `f64` and `i64` where needed (serde/CBOR + wide math)

3) **[lang][perf] Allocator control for large numeric buffers (no-GC-scanned region)**
   - DoD:
     - Expose an allocation mode for large typed-buffer payloads that avoids GC scanning (mmap/arena backing)
     - Ensure alignment guarantees (cacheline + NEON-friendly) remain a performance property (no semantic change)
     - Add stress tests for fragmentation + OOM behavior

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][perf] `std/linalg` v0.3: matmul baseline + kernel dispatch**
   - DoD:
     - Provide baseline `matmul_f32` / `matmul_i32` using typed buffers + views
     - Pluggable kernel dispatch (scalar vs NEON) via intrinsic boundary
     - Add correctness tests (small shapes) + perf smoke test (no hard perf thresholds)
   - Status:
     - **done:** baseline typed-buffer matmul (`matmul_f32_buf`, `matmul_i32_buf`, `matmul_i32_buf_wide`) + module tests (`tests/modules/test_linalg.oren`)
     - **next:** add kernel boundary for `matmul_f32_buf` inner loop (tile + optional NEON microkernel for `k`-loop)

2) **[stdlib][api] Serde annotations remain stable while language evolves**
   - DoD:
     - Keep attribute syntax short (`@pack`, `@json(...)`, `@yaml(...)`, `@cbor(...)`)
     - Ensure unknown attrs are deterministic (ignored unless explicitly consumed)
     - Add one integration test that roundtrips nested arrays/maps for JSON/YAML/CBOR

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- AVM snapshots v7: snapshot/restore now includes scheduler state (tasks + channels + queues) so spawned workloads can be paused/resumed.
- Bytecode backend: `oren_yield()` now returns canonical `nil` (stack-balanced as an expression), preventing verifier stack-height mismatches.
- Native backend: arm64 NEON dot kernel is implemented and regression-tested under env-gated SIMD dispatch.
