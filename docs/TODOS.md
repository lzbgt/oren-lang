# Active Tracker (Succinct)

**Last updated:** 2025-12-31

This repo is in rolling mode. This file tracks the **highest-priority active work** in execution order.

Rules for this tracker:

- Keep it **succinct and actionable** (aim: 10–20 items total).
- This is **not** a changelog; implemented feature status belongs in:
  - `docs/LANGUAGE_FEATURE_MATRIX.md`
  - `docs/LANGUAGE_STATUS_AND_GAPS.md`
  - dedicated design docs under `docs/`
- When an item is “done enough” (rolling), move details to `docs/TODOS_ARCHIVE.md` and keep this file focused on what’s next.

## P0 (Now)

1) **Tier‑1 native support parity (arm64 + x86_64; macOS/Linux/Windows)** (L)
   - Converge the native backends on one semantics set:
     - callables (function values), closures, varargs/spread, and deterministic failure modes (`OREN_DIAG` + stack traces)
     - **language concurrency**: `spawn`/`oren_join` must work on Windows (thread-based; no fork/pipe assumptions)
     - container ops (list/map/buf) with identical semantics across arch/OS
     - remove x86_64 bring-up hacks by linking the full native runtime module set where possible
       - **runtime injection is default-on** for x86_64 (same runtime source as arm64; expanded `// @include` tree)
         - escape hatch: `OREN_X64_NO_INJECT_RUNTIME=1` (debug / bring-up)
       - x86_64 backend re-runs global DCE after injection to keep cross-compilation time bounded (modern “unused stdlib removed” behavior)
       - next: replace remaining “bring-up-only” intrinsics with shared runtime helpers (goal: single semantics set, thin ABI emit layers)
   - Next (Tier‑1 correctness):
     - Windows x86_64: **done** — full env enumeration now uses `GetEnvironmentStringsA` (entry stub) + runtime conversion to a POSIX-style `envp` pointer array (no fixed allowlist).
       - Follow-up: **done** — env block is copied into runtime-owned memory during envp conversion, then freed via `FreeEnvironmentStringsA` (no intentional env-block leak; envp pointers remain stable).
     - Windows x86_64: **done** — TIME substrate now works without libc (`sys_nanosleep`, `sys_gettimeofday` via PE IAT shims); remote `tests/native/test_time_suite.oren` passes on Win11.
     - Windows x86_64: **done** — NET substrate now works without libc (WinSock + `select` wait backend + WSAStartup gated inside NET runtime); remote `tests/native/test_net_suite.oren` passes on Win11.
     - Windows x86_64: **rolling** — PROC spawn now has a Windows implementation via `CreateProcessA` (`sys_win_createprocess`), used by `oren_proc_spawn` when `g_target_os==3`.
       - Proof (Tier‑1 remote gate): `OREN_REMOTE_RUN=1 make test` runs `tests/fixtures/tier1_native_smoke_main.oren` on Win11+WSL2; the fixture now calls `oren_system("echo tier1 smoke proc ok")` and returns non‑zero on failure.
       - NOTE (concurrency): Windows Tier‑1 `spawn` is lowered to CreateThread and `oren_join(_timeout)` waits via `WaitForSingleObject` (see the Tier‑1 remote fixture `tests/fixtures/tier1_native_spawn_join_main.oren`). Still rolling: timeout cancellation uses `TerminateThread` today (needs a cooperative cancellation story later).
       - Next: extend beyond “spawn+wait” to a full PROC story on Windows: pid/kill/wait semantics (or define a cross‑OS `sys_spawn` CoreIR boundary).
     - POSIX `oren_system_timeout` robustness in minimal/container environments: **done** — runtime now performs deterministic shell discovery (supports `OREN_SYSTEM_SHELL` override) and returns `-2` (ENOENT) if no shell exists.
     - Windows x86_64 FS syscall surface parity (capsule-safe): **done** (rolling)
       - `sys_open` (CreateFileA), `sys_read/sys_write` (generic HANDLEs, not just stdio), `sys_close` (closesocket→CloseHandle fallback)
       - `sys_stat/sys_lstat/sys_fstat` now populate an **Oren-owned Stat ABI** (OrenStatV0) rather than mirroring host `struct stat` layouts.
       - `sys_unlink/sys_rmdir/sys_rename/sys_mkdir` (Win32 shims)
       - `sys_chmod` (currently a no-op on Windows; still enforces capsule FS write enrollment via prehook)
       - Stat ABI (done): `sys_stat/sys_lstat/sys_fstat` write OrenStatV0 into the caller buffer; callers/tests should allocate via `oren_stat_alloc()` (64B), not oversized host `struct stat` buffers.
     - Unify stack-safety call depth storage with the injected native runtime (remove the x86_64 data-blob-only guard once parity is proven).
     - Windows PE stack sizing: **done** — increased PE `SizeOfStackReserve` so deep recursion tests no longer need Windows skips (still a stopgap until heap-frame stackless recursion lands).
   - Post-injection DCE roots: **done** — global DCE now supports `@oren.keep` (explicit pin) and treats capsule syscall hooks (`native_capsule_sys_*`) as an internal ABI surface; runtime entry-stub/fixup helpers are pinned near their definitions.
   - Keep validation integration-first, and keep the remote x64 path as a hard gate:
     - `docs/REMOTE_X64_ENV.md` (Win11 + WSL2)
     - Keep tests OS-neutral where possible (e.g., avoid calling `oren_tcp_wait_kqueue` directly in cross-platform NET tests; prefer `oren_fd_wait_{readable,writable}`).
   - Tier‑1 correctness gap (x86_64 native): keep string compare semantics consistent with arm64:
     - **done**: `== != < <= > >=` in condition lowering treat tracked strings by content/lexicographic order (no pointer-compare regressions).

2) **Native value tagging (remove “key kind inference” fragility)** (L)
   - Goal: **maps do not require explicit key kind** in the language model; the runtime can safely decide based on tagged values.
   - Interim (done, keep): native runtime infers map key kind using tracking metadata (`oren_find_node(...).kind == STRING`), and native codegen ensures string literals / member keys are tracked via `oren_ensure_tracked`.
   - Harden runtime safety in the interim model: container ops must never dereference untracked values; prefer `oren_find_node` + `kind` guards before any `ptr_get(x+...)` on user-provided values.
   - Deliverable: a native value representation that can distinguish:
     - immediates (ints/bools/nil) vs pointers
     - string/list/map/buf payload kinds
   - References:
     - `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
     - `docs/DESIGN_CONTAINER_OPS.md`

3) **Backend architecture unification (CoreIR boundary)** (L)
   - Make one canonical CoreIR own semantics (eval order, short-circuit, varargs packing, closure ABI).
   - Backends become thin adapters (ABI + emit).
   - Rolling progress: extracted native stmt→ops lowering + expr validation to a shared module (`lib/compiler/native_ops_v0.oren`) to reduce backend drift and prep for deeper unification.
   - References:
     - `docs/BACKEND_ARCHITECTURE.md`
     - `docs/IR_AND_COMPILER_INTERNALS.md`

4) **Container ops as operations (no hot-path stdlib overhead)** (M)
   - Ensure `xs[i]`, `xs[i]=v`, `len`, `push` lower to intrinsics where appropriate.
   - Make map/list/buf iteration semantics deterministic across backends (add a unified iterator protocol so `for x in buf` works identically on arm64/x86_64 and across native/C/AVM).
   - Reference:
     - `docs/DESIGN_CONTAINER_OPS.md`
     - `docs/STDLIB_LAYERS.md`

5) **AVM in AVM + compiler-in-AVM (deterministic toolchain in a capsule)** (M)
   - Make `.oren → .obc` compilation runnable inside AVM with budgets and locked capability surfaces.
   - References:
     - `docs/AVM_MULTIVERSE.md`
     - `docs/AVM_SPEC_V1.md`
     - `docs/SELF_HOSTING.md`

6) **Stdlib distribution + module resolution (native + AVM)** (M)
   - One coherent story for end users:
     - `import ... "std:foo"` resolution
     - source vs precompiled stdlib bundles
     - AVM consuming the same stdlib without host-FS assumptions
   - References:
     - `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`
     - `docs/OBC_MODULE_LINKING.md`

7) **HPC/SIMD parity (arm64 NEON today; x86_64 SSE2/AVX next)** (M)
   - Keep determinism contract: scalar is authoritative; SIMD must be bit-identical for covered kernels.
   - Expand x86_64 SIMD coverage once x64 native reaches semantic parity.
   - References:
     - `docs/HPC_SERVER_PLAN.md`
     - `docs/AVM_NEON_MAPPING_PLAN.md`

8) **Tooling (modern compiler UX; self-hosting behind gates)** (M)
   - Keep Go bootstrap canonical until Oren-native tooling meets reliability/perf gates.
   - Track Oren-native tools as gated milestones: `fmt`, `test`, `pkg`, `lsp`.
   - References:
     - `docs/TEST_SYSTEM.md`
     - `docs/CLI_COMPLETION.md`
     - `docs/SELF_HOSTING.md`

9) **Tests & iteration speed (integration-first; backend/arch neutral by default)** (S)
   - Keep `make test` iteration-fast and deterministic.
   - Prefer a small number of high-signal integration suites + fixtures as living spec.
   - Keep tests hermetic: avoid relying on host shells or external utilities (prefer helper binaries built from Oren sources + explicit `oren_proc_spawn`).
   - Keep tests OS-neutral: avoid asserting platform `struct stat` layouts; prefer Oren-owned stable ABIs (e.g. OrenStatV0 via `oren_stat_alloc()`).
   - Make test tooling robust in minimal environments too: `oretest` now supports deterministic shell discovery and an override via `ORETEST_SHELL`.
   - Reference: `docs/TEST_SYSTEM.md`

## P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)
   - Formalize cert chain constraints and root pubkey distribution/rotation.
   - Keep private keys out of repo (`../oren-ca/`).
   - References:
     - `docs/APPSTORE_ROOTCA_AND_UPDATES.md`
     - `docs/CERT_CHAIN_FORMAT.md`

2) **Stackless recursion beyond TCO (heap call frames)** (L)
   - For non-tail recursion that cannot be optimized by TCO, provide a deterministic heap-frame model (AVM-like).
   - Reference: `docs/STACK_SAFETY.md`

3) **Native scheduler + netpoller (IO readiness → channels + select)** (L)
   - Keep `select` **channel-based** at the language surface; fd readiness integrates by producing channel events.
   - Bring native closer to AVM semantics:
     - mature channels beyond pipe-based bring-up
     - deterministic fairness rules where practical (round-robin cursor)
     - structured cancellation/timeouts
   - OS backends (planned):
     - macOS: kqueue/kevent + ulock parking
     - Linux: epoll (or io_uring later) + futex-like parking
     - Windows: IOCP for sockets (WinSock `select` is not sufficient for general async IO); unify with PROC/FS strategy
   - References:
     - `docs/CONCURRENCY_MODEL.md`
     - `docs/NATIVE_GMP_SCHEDULER.md`
     - `docs/ASYNC_IO_AND_SELECT.md`
