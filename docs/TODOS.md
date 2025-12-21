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

10) **Tests must target public tool surfaces** `[maint]`
   - Avoid importing `lib/compiler/*` inside `.oren` tests (couples tests to compiler internals).
   - Prefer using `./oren` subcommands (`build`, `meta`, etc.) and checking outputs via `cmd/oretest` fixtures.

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[stdlib][perf] SIMD and numeric kernels (arm64 NEON first)**
   - Goal: keep scalar reference semantics, add NEON fast paths behind intrinsic boundaries.
   - DoD:
     - Keep deterministic rounding/order guarantees (increasing-k accumulation for matmul).
     - Expand NEON kernels beyond dot (e.g. axpy / small GEMM tiles) where safe.
     - Perf smoke stays “no thresholds”; correctness tests stay small and deterministic.
   - Status (rolling):
     - DONE: f32 reductions now have deterministic NEON paths in C runtime (`oren_buf_dot_f32*`, `oren_buf_reduce_sum_f32*`) matching AVM semantics.
     - DONE: f64 SIMD paths are working end-to-end (native backend + C backend):
       - `oren_buf_add_f64_into`, `oren_buf_mul_f64_into`, `oren_buf_dot_f64`, `oren_buf_reduce_sum_f64`
       - NOTE: native backend relies on correct opcode tables in `lib/compiler/arm64_core.oren` (fixed `insn_fadd_2d`, `insn_umov_x_d1`).
     - DONE: f64 view + matmul building blocks are now available and covered in the fast suite:
       - runtime: `oren_buf_dot_f64_slice`, `oren_buf_dot_f64_strided` (C + native runtime)
       - stdlib: `dot_f64_view`, `matmul_f64_buf` (dot-based; deterministic increasing-k semantics)
       - tests: `tests/modules/test_integration_suite.oren` asserts slice/strided dot + a small matmul result
     - DONE: native SIMD integration coverage lives in `tests/native/test_simd_suite.oren` (hash/bits checks; SIMD enabled/disabled runs).
     - NOTE: scalar-multiply “scale i32/f32” SIMD fast paths are intentionally **not** enabled in the native backend yet (prior attempt had correctness issues; removed to keep the repo green).
     - Implemented (code present, needs explicit C-backend coverage): additional NEON kernels in `lib/runtime_buf.c` (i32 axpy + scale/add/mul variants).
     - DONE: initial i32 GEMM microkernel boundary (1x4) is implemented and used by `std/linalg.matmul_i32_buf`:
       - runtime: `oren_buf_dot_i32_4_slice_into` (C runtime has a NEON path; native runtime scalar; AVM scalar)
       - stdlib: `matmul_i32_buf` uses 4-way dot dispatch when computing 4 columns
       - tests: `tests/modules/test_integration_suite.oren` includes a 1x4×4 identity matmul smoke to exercise the microkernel
     - DONE: packed-B path for i32 matmul is implemented (tile-major packed transpose for cache locality) and the 1×4 microkernel is used on packed tiles.
       - tests: `tests/modules/test_integration_suite.oren` includes a 1×64 × 64×64 identity smoke to force the packed path
     - DONE: additional i32 SIMD kernel surfaces are now covered in the fast suites:
       - module: `tests/modules/test_integration_suite.oren` covers `add/mul/scale/axpy` on i32 typed buffers
       - native: `tests/native/test_integration_suite.oren` covers `*_into` forms and `axpy` (`oren_buf_add_i32_into`, `oren_buf_mul_i32_into`, `oren_buf_scale_i32_into`, `oren_buf_axpy_i32_into`)
     - DONE: AVM parity: `oren_buf_axpy_{i32,f32}_{into,in_place}` are implemented as AVM natives and covered by `tests/avm/test_smoke_suite.oren`.
     - NEXT: add an f32 microkernel variant once FP strategy is stabilized; consider f64 after deciding error model vs bitwise determinism.

2) **[lang][arch] Type namespacing v1: `alias.Type` annotations work across modules**
   - Status: **done** (see archive for details).

3) **[lang][hpc] Scientific notation float literals (`1e-12`)**
   - Why: modern HPC/math code needs scientific notation for tolerances and constants; decimal expansions are noisy and error-prone.
   - DoD:
     - Lexer accepts `e/E` suffix with optional sign for float literals (both `1e3` and `1.5e-2`).
     - Invalid forms (`1e`, `1e+`) produce a deterministic lexer error.
     - Coverage in `tests/modules/test_integration_suite.oren` uses `1e-12` (and a couple of exact cases like `1e3`).
     - Spec updated in `docs/LANGUAGE_SPEC.md`.
   - Status: **done**.

4) **[stdlib][hpc] Math foundations for scientific/HPC code (no host libm)**
   - Goal: provide deterministic “libm-lite” primitives so HPC/ML libraries can be written in Oren.
   - DoD (rolling):
     - Provide correct, deterministic `sqrt(x)` + `powi(x,n)` and float classification helpers.
     - Provide deterministic `exp2/exp/log2/ln` so probabilistic/ML/HPC code can proceed without host libm.
     - Keep implementations portable across C/native/AVM (no platform libm calls).
     - Keep integration tests small and exact (avoid tolerance-based tests until an error model is documented).
   - Status (rolling):
     - DONE: `math.sqrt`, `math.powi`, `math.is_inf/is_finite/signbit/copysign` (covered in `tests/modules/test_integration_suite.oren`).
     - DONE: `math.exp2/exp/log2/ln` (range-reduced, fixed-iteration, no host libm; covered in `tests/modules/test_integration_suite.oren` with tight deterministic tolerances).
     - DONE: `math.sin/math.cos` (range-reduced, fixed polynomial; guarded for huge |x|; covered in `tests/modules/test_integration_suite.oren`).
     - DONE: `math.atan/math.atan2` (fdlibm-style range reduction + polynomial; covered in `tests/modules/test_integration_suite.oren`).
     - NEXT: improved trig range reduction (Payne–Hanek) so trig works for huge |x| without errors; property tests in `./oretest --full`.

5) **[lang][ux] `else if` chains (no extra braces)**
   - Why: modern ergonomics; avoids noisy `else { if ... }` indentation in real code.
   - DoD:
     - Parser accepts `else if <cond> { ... }` and lowers to existing `else { if ... }` AST form.
     - Coverage exists in `tests/modules/test_integration_suite.oren`.
     - Spec updated in `docs/LANGUAGE_SPEC.md`.
   - Status: **done**.

6) **[docs][ux] Draft + maintain a practical Language Manual**
   - Why: the spec is correct but not a beginner-friendly “how to write Oren”; we need a single narrative doc that matches reality.
   - DoD:
     - Manual exists and matches current rolling features (literals, else-if, match, lambdas, typed buffers, deterministic math).
     - Manual links to canonical specs/docs for details.
     - Keep it updated as features land; move large historical narrative to `docs/EVOLUTION_GUIDE.md`.
   - Status: **done** (`docs/LANGUAGE_MANUAL.md`).

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

1) **[boot][arch] Compiler-in-AVM v2: hash-addressed artifacts + governance hooks**
   - Goal: make `.obc` artifacts content-addressable and verifiable inside multiverse swarms.
   - DoD:
     - deterministic `.obc` hash IDs and module manifests
     - governance hooks for module load policies (capsule-style)
     - AVM can ingest `.oren` via VirtualFS and emit `.obc` without host FS effects

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Test runner: fast suite is now integration-first (added `tests/modules/test_integration_suite.oren` + merged native SIMD tests into `tests/native/test_simd_suite.oren`).
- Struct unification: `struct` values are map-shaped + mutable across backends (see archive entry).
- Cast lowering (HPC signal): `i64/u64` casts and `: i64` parameter annotations no longer inject `oren_trunc_int(...)` in provably-int paths (reduces dynamic checks in hot loops while preserving correctness for float→int truncation).
- Stdlib cleanup (HPC signal): removed redundant `i64(...)` wrappers from `std/linalg` and `std/math` where values are already int-only, keeping semantics unchanged.
- AVM snapshots v7: snapshot/restore now includes scheduler state (tasks + channels + queues) so spawned workloads can be paused/resumed.
- Bytecode backend: `oren_yield()` now returns canonical `nil` (stack-balanced as an expression), preventing verifier stack-height mismatches.
- Compiler-in-AVM v0 (host FS): self-hosted compiler builds to `.obc`, runs inside `./avm`, compiles a `.oren` fixture to `.obc`, and the result runs successfully.
  - Bytecode widening: added `CALL32`/`PUSH_FUNC32` (u32 addrs) and `LOAD/STORE_LOCAL16` (u16 locals) so the compiler `.obc` can exceed 64KB safely.
  - Import alias scoping: import aliases are now namespaced per-module in the linker so bytecode backends can resolve `alias.symbol` deterministically after merging modules.
  - Capability hardening: FS allow-prefix checks now normalize paths lexically (blocks `build/../...` traversal and allows `./tests/...` ergonomics).
- Native backend: arm64 NEON dot kernel is implemented and regression-tested under env-gated SIMD dispatch.
