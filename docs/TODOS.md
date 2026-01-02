# Active Tracker (Succinct)

**Last updated:** 2026-01-02

This repo is in rolling mode. This file tracks the **highest-priority active work** in execution order.

Rules for this tracker:

- Keep it **succinct and actionable** (aim: 10–20 items total).
- This is **not** a changelog; implemented feature status belongs in:
  - `docs/LANGUAGE_FEATURE_MATRIX.md`
  - `docs/LANGUAGE_STATUS_AND_GAPS.md`
  - dedicated design docs under `docs/`
- When an item is “done enough” (rolling), move details to `docs/TODOS_ARCHIVE.md` and keep this file focused on what’s next.

## P0 (Now)

0) **Toolchain resource bounds (self-hosting + tests)** (L)
   - MANTIS is a forcing function for “production-level” maturity, but the compiler/test runner must also be stable enough to iterate quickly.
   - Keep these paths reliable and bounded:
     - `make verify` (stage1 → stage2 self-hosting gate)
     - `make test` (curated suite)
     - `./oretest --matrix tier1` (host + linux/arm64 docker + remote x64 gate when available)
   - Avoid O(n²) string/collection patterns in compiler-side tooling (include expansion, C backend transpiler, whole-program lowering passes).
   - Hard gate (non-negotiable for rolling):
     - Stage2/Stage3 self-host compiler build must stay **< 3 minutes** wall time on the primary dev host.
     - RSS should stay **< 300 MB** for the compilation process.
   - High-leverage path (avoid “parameter tuning”):
     - deterministic parallel compilation pipeline (module graph scheduling + cache hits)
     - eliminate global/shared mutable state that prevents safe parallelism (or centralize it behind explicit concurrency primitives)

1) **Tier‑1 native support parity (arm64 + x86_64; macOS/Linux/Windows)** (L)
   - Keep native semantics aligned across platforms:
     - callables/closures/varargs + deterministic failure modes (`OREN_DIAG` + stack traces)
     - container ops (list/map/buf) with identical semantics across arch/OS
     - concurrency primitives on Windows (no fork/pipe assumptions): `spawn`, `oren_join(_timeout)`, and a path to cooperative cancellation
   - Remaining gaps (active):
     - POSIX: replace fork-based `spawn` substrate with real OS threads + shared-memory synchronization:
       - mutex/condvar + parking/unparking primitives (`ulock` on macOS; futex-like on Linux; Win32 already exists)
       - a GC/safepoint model that remains correct once true threads exist (no “mutex works but GC breaks”)
     - Windows: complete a coherent PROC story (pid/kill/wait semantics or define a cross-OS `sys_spawn` boundary).
       - Current blocker: `oren_system(_timeout)` on `x64-windows` fails in the remote gate (`sys_win_createprocess` returns `-998` / `GetLastError()==998` = `ERROR_NOACCESS`).
         - Tier‑1 fixture currently *soft-skips* the failure on Windows to keep the remote gate usable; remove this skip once CreateProcess wiring is correct.
     - x86_64: finish deleting bring-up-only code paths (keep runtime injection mandatory; converge remaining fast paths on the same safety contract).
   - **done (rolling, 2026-01-02):**
     - fix POSIX `spawn`/`join` handle correctness by using byte-accurate pointer offsets (`iadd(...)`) instead of `+` in runtime metadata structs (prevents fork+pipe returning corrupted results on Linux)
     - add native `oren_set_result` / `oren_get_result` surface and pin result values as GC roots (parity with C backend + AVM job orchestration)
   - References:
     - `docs/REMOTE_X64_ENV.md`
     - `docs/TEST_SYSTEM.md`
     - `docs/LANGUAGE_FEATURE_MATRIX.md`

2) **Determinism + replay (native + AVM)** (L)
   - MANTIS requires deterministic replay and traceability (`mantis.md` “Observability & reproducibility”).
   - AVM has deterministic TIME/RNG + record/replay fixtures today; native needs an equivalent “deterministic mode” story:
     - record/replay boundary for effectful ops (FS/NET/PROC/ENV/TIME/RNG)
     - deterministic scheduling option (ties into structured concurrency)
   - Reference goal doc: `OREN_MANTIS_STDLIB_GOALS.md`

3) **Native value tagging (remove “key kind inference” fragility)** (L)
   - Goal: **maps do not require explicit key kind** in the language model; the runtime can safely decide based on tagged values.
   - Interim (done, keep): native runtime infers map key kind using tracking metadata (`oren_find_node(...).kind == STRING`), and native codegen ensures string literals / member keys are tracked via `oren_ensure_tracked`.
   - Harden runtime safety in the interim model: container ops must never dereference untracked values; prefer `oren_find_node` + `kind` guards before any `ptr_get(x+...)` on user-provided values.
     - **done (rolling):** arm64 + x86_64 Index get/set dispatch now checks tracked node kind (LIST/MAP) before touching container headers (no untracked `*(x+24)` probes).
   - **done (rolling):** removed native-runtime numeric-range string-key heuristic (`k < 4096`); string-key validation now relies on tracked-allocation metadata only.
   - **done (rolling):** compiler lowering learns kind hints from `oren_track_alloc(x, ..., kind)` / `oren_ensure_tracked(x, kind)` statement calls (e.g. kind=1 => `string`), improving key-kind inference for dynamic string keys.
   - **done (rolling):** Tier‑1 fixtures cover dynamic string keys + a large integer key (`50000`) for map set/get determinism guards.
   - **done (rolling):** arm64 + x86_64 native index get/set fallbacks now delegate unknown map key kinds to the shared runtime helpers `oren_map_get` / `oren_map_set` (reduces backend drift while value tagging is in flight).
   - Deliverable: a native value representation that can distinguish:
     - immediates (ints/bools/nil) vs pointers
     - string/list/map/buf payload kinds
   - References:
     - `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
     - `docs/DESIGN_CONTAINER_OPS.md`

4) **Backend architecture unification (CoreIR boundary)** (L)
   - Make one canonical CoreIR own semantics (eval order, short-circuit, varargs packing, closure ABI).
   - Backends become thin adapters (ABI + emit).
   - Rolling progress: extracted native stmt→ops lowering + expr validation to a shared module (`lib/compiler/native_ops_v0.oren`) to reduce backend drift and prep for deeper unification.
   - References:
     - `docs/BACKEND_ARCHITECTURE.md`
     - `docs/IR_AND_COMPILER_INTERNALS.md`

5) **Container ops as operations (no hot-path stdlib overhead)** (M)
   - Ensure `xs[i]`, `xs[i]=v`, `len`, `push` lower to intrinsics where appropriate.
   - Make map/list/buf iteration semantics deterministic across backends (add a unified iterator protocol so `for x in buf` works identically on arm64/x86_64 and across native/C/AVM).
   - Reference:
     - `docs/DESIGN_CONTAINER_OPS.md`
     - `docs/STDLIB_LAYERS.md`

6) **AVM in AVM + compiler-in-AVM (deterministic toolchain in a capsule)** (M)
   - Make `.oren → .obc` compilation runnable inside AVM with budgets and locked capability surfaces.
	   - References:
	     - `docs/AVM_MULTIVERSE.md`
	     - `docs/AVM_SPEC_V1.md`
	     - `docs/SELF_HOSTING.md`
	   - **done (rolling, 2026-01-02):** native backend bridge for `oren_avm_run_obc_bytes(child_obc_bytes, cfg)` (runs `./avm` + returns record log bytes + hashes; `avm` run JSON now includes selected result for orchestration).

7) **Stdlib distribution + module resolution (native + AVM)** (M)
   - One coherent story for end users:
     - `import ... "std:foo"` resolution
     - source vs precompiled stdlib bundles
     - AVM consuming the same stdlib without host-FS assumptions
   - References:
     - `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`
     - `docs/OBC_MODULE_LINKING.md`

8) **HPC/SIMD parity (arm64 NEON today; x86_64 SSE2/AVX next)** (M)
   - Keep determinism contract: scalar is authoritative; SIMD must be bit-identical for covered kernels.
   - Expand x86_64 SIMD coverage once x64 native reaches semantic parity.
   - References:
     - `docs/HPC_SERVER_PLAN.md`
     - `docs/AVM_NEON_MAPPING_PLAN.md`

9) **Tooling (modern compiler UX; self-hosting behind gates)** (M)
   - Keep Go bootstrap canonical until Oren-native tooling meets reliability/perf gates.
   - Track Oren-native tools as gated milestones: `fmt`, `test`, `pkg`, `lsp`.
   - References:
     - `docs/TEST_SYSTEM.md`
     - `docs/CLI_COMPLETION.md`
     - `docs/SELF_HOSTING.md`

10) **Tests & iteration speed (integration-first; backend/arch neutral by default)** (S)
   - Keep `make test` iteration-fast and deterministic.
   - **done (rolling):** build-cache dependency scan is no longer O(n^2) and no longer parses full ASTs just to find `import` edges; it now uses a lexer token scan + a persistent scan cache under the selected `--cache-dir`/`OREN_CACHE_DIR` to reduce repeated work on large graphs.
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
