# Active Tracker (Succinct)

**Last updated:** 2026-01-03

This repo is in rolling mode. This file tracks the **highest-priority active work** in execution order.
Recent completions live in `docs/TODOS_ARCHIVE.md` (keep this list “what’s next”, not a changelog).

Rules for this tracker:

- Keep it **succinct and actionable** (aim: 10–20 items total).
- This is **not** a changelog; implemented feature status belongs in:
  - `docs/LANGUAGE_FEATURE_MATRIX.md`
  - `docs/LANGUAGE_STATUS_AND_GAPS.md`
  - dedicated design docs under `docs/`
- When an item is “done enough” (rolling), move details to `docs/TODOS_ARCHIVE.md` and keep this file focused on what’s next.

## P0 (Now)

0) **Toolchain resource bounds (self-hosting + tests)** (L)
   - Keep these paths reliable and bounded:
     - `make verify-native-quick` (stage1 + stage2 native smoke)
     - `make test-native-all` (native suite; stage1)
     - `make verify` (stage1 → stage2 self-hosting gate)
	   - Avoid O(n²) string/collection patterns in compiler-side tooling (include expansion, C backend transpiler, whole-program lowering passes).
	   - Recently completed: pooled embedded string literals + one-time startup registration (`oren_init_static_cstr0_table`) to remove per-use tracking overhead in compiler workloads (details in `docs/TODOS_ARCHIVE.md`).
	   - Hard gate (non-negotiable for rolling):
	     - Stage2/Stage3 self-host compiler build must stay **< 3 minutes** wall time on the primary dev host.
     - RSS should stay **< 300 MB** for the compilation process.
	   - High-leverage path (avoid “parameter tuning”):
	     - deterministic parallel compilation pipeline (module graph scheduling + cache hits)
	     - eliminate global/shared mutable state that prevents safe parallelism (or centralize it behind explicit concurrency primitives)
	     - reduce compiler heap churn by moving hot internal data away from pointer-heavy `map/list` graphs:
	       - prefer typed buffers (`u8_buf`) + compact encodings for AST/IR/module artifacts (e.g. `astbin` / CBOR-like) when crossing worker boundaries or caching
	       - keep the in-process “fast path” zero-copy where possible (shared-memory attach instead of returning large graphs through `join`)

1) **Tier‑1 native support parity (arm64 + x86_64; macOS/Linux/Windows)** (L)
   - Keep native semantics aligned across platforms:
     - callables/closures/varargs + deterministic failure modes (`OREN_DIAG` + stack traces)
     - container ops (list/map/buf) with identical semantics across arch/OS
     - concurrency primitives on Windows (no fork/pipe assumptions): `spawn`, `oren_join(_timeout)`, and a path to cooperative cancellation
   - Remaining gaps (active):
     - **Stage2-native (arm64-macos) self-hosting via `--backend native` is still unstable** (as of 2026-01-03).
       - Repro: `./oren build oren.oren --backend native --platform arm64-macos --no-cache --no-debug -o build/selfhost_manual/oren_stage2_native && codesign -s - --force build/selfhost_manual/oren_stage2_native`
       - Minimal compare: compile+run `tests/native/test_quick_integration_native.oren` using `./scripts/run_native_quick_integration.sh ./build/selfhost_manual/oren_stage2_native`
     - POSIX: replace fork-based `spawn` substrate with real OS threads + shared-memory synchronization:
       - mutex/condvar + parking/unparking primitives (`ulock` on macOS; futex-like on Linux; Win32 already exists)
       - a GC/safepoint model that remains correct once true threads exist (no “mutex works but GC breaks”)
     - Windows: complete a coherent PROC story (pid/kill/wait semantics or define a cross-OS `sys_spawn` boundary).
       - Current blocker: `oren_system(_timeout)` on `x64-windows` fails in the remote gate (`sys_win_createprocess` returns `-998` / `GetLastError()==998` = `ERROR_NOACCESS`).
         - Tier‑1 fixture currently *soft-skips* the failure on Windows to keep the remote gate usable; remove this skip once CreateProcess wiring is correct.
	     - x86_64: finish deleting bring-up-only code paths (keep runtime injection mandatory; converge remaining fast paths on the same safety contract).
	     - (performance) stage2-native runtime bundle cost remains high; keep iterating toward:
	       - default: hashed runtime AST cache under `build/cache/native_runtime_astbin/` (disable via `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0`)
	       - `OREN_NATIVE_RUNTIME_EXPANDED=...` troubleshooting fast-path (skip include expansion)
	       - `OREN_NATIVE_RUNTIME_ASTBIN=...` troubleshooting fast-path (force a specific astbin file)
	       - Current measured hotspot (arm64-macos, `tests/native/test_quick_integration_native.oren`, stage2-native compiler):
	         - runtime astbin decode is still multi-second (~7.4s decode for the runtime bundle on 2026-01-03 with `OREN_TRACE_RUNTIME_BUNDLE=1 OREN_TRACE_ASTBIN=1`), despite recent wins from inlining `oren_buf_load_u8_unchecked` in native emit.
	         - next high-leverage direction: avoid compiling the full injected runtime on every build (cache a platform+opts-specific compiled runtime blob and link/merge it), so “compile one file” doesn’t pay the full runtime cost.
	       - (capsule) ensure `native_capsule_sys_*` hooks are emitted + kept only when `--capsule` is enabled (non-capsule builds should not pay this cost)

2) **Determinism + replay (native + AVM)** (L)
   - MANTIS requires deterministic replay and traceability (`mantis.md` “Observability & reproducibility”).
   - AVM has deterministic TIME/RNG + record/replay fixtures today; native needs an equivalent “deterministic mode” story:
     - record/replay boundary for effectful ops (FS/NET/PROC/ENV/TIME/RNG)
     - deterministic scheduling option (ties into structured concurrency)
   - Reference goal doc: `OREN_MANTIS_STDLIB_GOALS.md`

3) **Native value tagging (remove “key kind inference” fragility)** (L)
   - Goal: **maps do not require explicit key kind** in the language model; the runtime can safely decide based on tagged values.
   - Keep tightening interim safety rules:
     - container ops must never dereference untracked values
     - key-kind inference must not rely on numeric-range heuristics
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
   - Keep `make test` (native quick smoke) iteration-fast and deterministic.
   - Prefer a small number of high-signal integration suites + fixtures as living spec.
   - Keep tests hermetic: avoid relying on host shells or external utilities (prefer helper binaries built from Oren sources + explicit `oren_proc_spawn`).
   - Keep tests OS-neutral: avoid asserting platform `struct stat` layouts; prefer Oren-owned stable ABIs (e.g. OrenStatV0 via `oren_stat_alloc()`).
   - Make test tooling robust in minimal environments too: avoid relying on host shells/utilities in test programs.
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
   - Already exists (today, in code/tests): `oren_select` / `oren_select_recv` runtime APIs (native + AVM), plus fd readiness waits (`oren_fd_wait_{readable,writable}` etc).
     - Not done yet: language-level `select { ... }` syntax, and a native green-thread scheduler/netpoller that wakes channels instead of blocking the whole process/thread.
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
