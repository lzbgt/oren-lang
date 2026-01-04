# Active Tracker (Succinct)

**Last updated:** 2026-01-04

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
	   - Recently completed: bounded build timing summaries via `OREN_TRACE_BUILD_SUMMARY=1` / `OREN_TRACE_BUILD_SLOW_MS=<n>` so “>10s builds” are diagnosable without huge logs (details in `docs/TODOS_ARCHIVE.md`).
	   - Recently completed: pooled embedded string literals + one-time startup registration (`oren_init_static_cstr0_table`) to remove per-use tracking overhead in compiler workloads (details in `docs/TODOS_ARCHIVE.md`).
	   - Recently completed: arm64-linux native binaries no longer segfault at startup:
	     - early runtime raw allocations now use `native_malloc_raw_or_mmap` (mmap fallback) instead of trusting `malloc_raw` unconditionally
	     - arm64 native allocator lowering now rejects suspicious mmap results `< 4096` (fail-fast) to avoid treating small integers as pointers (details in `docs/TODOS_ARCHIVE.md`).
	   - Recently completed: shared compiler growable-bytes builder extracted to `lib/compiler/bytes_builder.oren` to reduce arm64/x64 backend drift (details in `docs/TODOS_ARCHIVE.md`).
	   - Recently completed: native `oren_read_u8_buf` now returns structured errors on missing files (no hard-exit), fixing stage2-native runtime-object cache cold misses (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: GC pin/result no longer roots static string literals (classification-only nodes), reducing root churn in compiler/tooling runs (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: runtime bundle astbin caches now carry a “pruned for target OS” marker so pruned caches can skip redundant `g_target_os` pruning (and stale pruned caches can be rewritten once); astbin v2 encoder pre-sizes the string pool index map for large programs to keep cache writes bounded (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: fixed a capsule-build segfault where a stale pruned runtime astbin cache could preserve pruned-away runtime guard checks; pruning now records a cache generation marker and pruned cache suffix bumped to `_pruned3.astbin`, plus `make verify-native-quick` includes a capsule smoke (`scripts/run_native_capsule_smoke.sh`) (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: added a runtime-astbin “seed” mechanism so stage2-native can avoid very slow cold parsing of `lib/runtime_native_capsule.oren`:
		     - compiler tries `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR` on astbin cache miss and copies the seed into the active cache dir
		     - `make astbin-seed` (also run best-effort by `make stage2`) generates/refreshes the seed using stage1 `./oren` (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: runtime-object cache load is now hardened with a cheap sentinel integrity check so corrupted/stale rtobj meta becomes a miss+rebuild (instead of a stage1 panic in x64 codegen) (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: x64 PE/ELF fixup patching now uses a fast `bytes_set_u32_le` raw-store path, keeping `scripts/verify_native_x64_compile_only.sh` stage2 `x64-windows` under the default 10s timeout (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: native `sys_stat/sys_lstat/sys_fstat` now populate OrenStatV0 `{a,m,c}time_ns` on macOS/Linux (arm64+x86_64), and the build scan cache is now stat-aware (`scan_cache_v3.txt`) to avoid re-reading unchanged sources during build-cache key computation (details in `docs/TODOS_ARCHIVE.md`).
		   - Recently completed: native stage2 build-cache key computation is now bounded (no more multi-second “cache key compute” stalls):
		     - rolling builds use a cheap stat-based compiler signature (avoid hashing the full `./oren_stage2` binary every run)
		     - scan cache persistence happens after injected-runtime hashing (so the runtime include-closure is not re-walked each build)
		     - scan cache serialization now uses a `u8_buf` builder (no O(n²) string concatenation) (details in `docs/TODOS_ARCHIVE.md`).
		   - Remaining (active): rtobj-miss (cold) path is still too slow in stage2-native due to runtime bundle decode + runtime decl compilation; keep pushing toward **< 10s** cold “compile one file” when caches are empty (see `docs/TODOS_ARCHIVE.md` for current measurements + profiling knobs; current is ~`15s` on arm64-macos stage2 for `examples/hello.oren` in `./scripts/bench_native_compile_one_file.sh --no-debug` run-1 (isolated rtobj dir; seed disabled)).
		     - Capsule note (active): if the runtime astbin cache for `lib/runtime_native_capsule.oren` is missing, stage2-native may spend ~`20s+` just parsing the expanded capsule runtime once to regenerate `*_pruned3.astbin` (bounded but too slow for “first capsule build” UX). Consider seeding capsule runtime astbin/rtobj (or reducing capsule runtime surface) so cold `--capsule` builds stay under the default 10s per-build timeout.
		     - Current miss breakdown (arm64-macos; stage2; `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1`, seed disabled):
		       - runtime astbin decode/parse: ~`2.1s` total (astbin v2 decode ~`1.3s`)
		       - runtime decl compile: ~`7.0s`
		       - finalize: ~`1.4s`
		       - rtobj meta encode (astbin v2): ~`1.1s`
		       - rtobj build+apply total: ~`12.8–13.0s` (overall compile-one-file miss: ~`15.2–15.3s`)
		     - Decl bucket drill-down (arm64-macos; stage2; `OREN_TRACE_ARM64_RT_OBJ_TOP_DECLS=1`):
		       - The decl bucket is mostly real per-decl compilation work (sum of decl compile times ~= decls_ms).
		       - Current “top decls” include (approx): `_oren_map_set_kind_unchecked` (~`839ms`), `native_capsule_proc_match_token` (~`386ms`), `oren_avm_run_obc_bytes` (~`224ms`), `native_capsule_fs_mount_resolve` (~`221ms`), `oren_sha256_range` (~`143ms`).
		       - High-leverage direction: reduce what the compiler needs to inject/compile (tooling/runtime layering or a DCE/reachability model for rtobj), so cold rtobj builds don’t compile large AVM/HPC/capsule surfaces unnecessarily.
		     - Recent (2026-01-04): default `lib/runtime_native.oren` no longer includes the syscall-hook-only capsule modules (`050_capsule_fs_hooks`, `070_capsule_net_hooks`), reducing runtime decl count (rtobj `decls_n`) in non-capsule builds; capsule builds use `lib/runtime_native_capsule.oren`.
				   - Hard gate (non-negotiable for rolling):
				     - Stage2/Stage3 self-host compiler build must stay **< 3 minutes** wall time on the primary dev host.
			     - Stage2 native backend “compile one file” (cache hit; non-capsule) should stay **< 4s** wall time on the primary dev host; regressions indicate a fundamental hot-path flaw to investigate.
			     - Debug builds used by Tier‑1 fixtures must stay **< 10s** per `oren build ... --backend native --debug` step (default script timeout).
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
	     - Fixed (2026-01-04): **arm64-macos stage2 is now bootstrapped via the native backend by default** (`make stage2`).
	       - Fallback (bring-up): `make stage2 OREN_STAGE2_BACKEND=c`.
	     - POSIX: replace fork-based `spawn` substrate with real OS threads + shared-memory synchronization:
	       - mutex/condvar + parking/unparking primitives (`ulock` on macOS; futex-like on Linux; Win32 already exists)
	       - a GC/safepoint model that remains correct once true threads exist (no “mutex works but GC breaks”)
     - Windows: complete a coherent PROC story (pid/kill/wait semantics or define a cross-OS `sys_spawn` boundary).
       - Fixed (2026-01-04): `oren_system(_timeout)` now works on `x64-windows` (CreateProcessA path).
         - Tier‑1 fixture no longer soft-skips Windows.
         - Native quick integration now includes a Windows-only `oren_system_timeout(...)` smoke to prevent regressions.
         - Runtime object cache key now includes a backend signature so codegen changes invalidate cached runtime machine code.
       - Fixed (2026-01-04): x86_64 stack traces now resolve symbols under rtobj cache mode (no “???” on Win11 Tier‑1).
         - x64 compiler emits an embedded debug-info table and entry stub calls `oren_set_debug_info(...)`.
         - Runtime `stack_trace()` now uses `oren_resolve_symbol(pc)` (debug-info first; fallback to best-effort intrinsic).
         - Tier‑1 smoke asserts `oren_resolve_symbol(lr) != "???"`.
	       - Fixed (2026-01-04): arm64 varargs wrappers no longer self-recurse in native codegen.
	         - Added a `cur_fn_name` context so call lowering can skip varargs “callable-object” lowering inside `__oren_fnwrap_*`.
	         - Result: `tests/fixtures/tier1_native_smoke_main.oren` runs successfully on `arm64-macos` native backend in debug mode.
	       - Fixed (2026-01-04): x86_64-linux Tier‑1 spawn/join now runs successfully under remote WSL2 (stage1 + stage2).
	         - Root cause: stale cached runtime machine code (rtobj cache) could preserve a buggy historical x64 `sys_pipe` lowering that clobbered the syscall rc while widening fds.
	         - Fix: bumped `RUNTIME_OBJ_BACKEND_SIG_X64` to invalidate cached runtime objects and restored strict runtime checks (`sys_pipe(...) != 0` fails) so regressions are caught immediately.
	         - Perf fix (2026-01-04): x64 rtobj build no longer synthesizes `__oren_fnwrap_*` wrappers for **all** runtime functions.
	           - Now matches arm64’s `fnwrap_needed` strategy (only synthesize wrappers actually used as function values), reducing “compile one file” cold miss on x64 targets (debug) from ~5.4s → ~2.5s in local benchmarks.
	         - Also hardened `scripts/verify_native_matrix.sh` to propagate remote exit codes and assert Tier‑1 output markers (prevents silent early-exit false positives).
	         - Details: `docs/TODOS_ARCHIVE.md`.
				     - x86_64: finish deleting bring-up-only code paths (keep runtime injection mandatory; converge remaining fast paths on the same safety contract).
				       - Fixed (2026-01-04): x64 no longer eagerly synthesizes `__oren_fnwrap_*` for every named user function.
				         - Now uses `fnwrap_needed` to synthesize/compile fnwraps only when a function is used as a value (also works for runtime functions, including rtobj mode).
				         - Bumped x64 rtobj backend sig to invalidate cached runtime objects after wrapper emission strategy changes.
					     - (performance) stage2-native runtime bundle cost remains high; keep iterating toward:
			       - default: hashed runtime AST cache under `build/cache/native_runtime_astbin/` (disable via `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0`)
			       - default (Tier‑1 throughput): cached compiled runtime object under `build/cache/native_runtime_obj/` (disable via `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`)
			       - optional (fast first-run): rtobj “seed” dir under `build/cache/native_runtime_obj_seed/` (override via `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=...`, disable with `0`); generate with `make rtobj-seed`
			       - `OREN_NATIVE_RUNTIME_EXPANDED=...` troubleshooting fast-path (skip include expansion)
			       - `OREN_NATIVE_RUNTIME_ASTBIN=...` troubleshooting fast-path (force a specific astbin file)
			       - Status (rolling, 2026-01-03):
			         - Implemented: arm64 + x86_64 native backend runtime object cache (default-on for non-capsule builds; works for debug and non-debug) so “compile one file” can skip recompiling `lib/runtime_native.oren` on cache hit.
			         - Implemented: runtime object cache schema v2 (fast runtime fingerprint for cache selection; avoids expensive SHA-256 on the expanded runtime in stage2-native hot paths).
			         - Remaining: integrate capsule safely; consider persisting runtime debug line mapping (optional), and decide how to keep binaries small (DCE/prune strategy) without reintroducing per-build runtime compilation.
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
		   - Cross-arch: `./scripts/verify_native_matrix.sh` has opt-in Tier‑1 fixture targets (`x64-win-tier1`, `x64-wsl-tier1`) in addition to the fast quick-integration matrix.
		   - Perf regression playbook (native backend): `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`
		   - Lightweight tripwire (rtobj hit): `make perf-guard-native-hit` (or `./scripts/perf_guard_native_compile_one_file_hit.sh`)
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

4) **Portable core + reflective types + value repr refactor** (L)
   - Goal (rolling, allowed to break compatibility): make Oren’s internal “unsafe core” small, fast, and portable, and make types first-class with reflection as a primary design constraint.
   - Deliverables (design → implementation):
     - define a portable core runtime layer for unsafe primitives:
       - string buf / array buf (contiguous, amortized growth, explicit capacity)
       - IO ops surface (file + fd + basic NET) with explicit error codes
     - make types first-class and reflective:
       - stable “type object” representation
       - reflective APIs for field layout / method tables / generic instantiations (as designed)
     - redesign the native value representation (reduce “64-byte OrenValue” storage inefficiency):
       - unify with the native tagged-value plan and remove key-kind inference fragility as a side-effect
   - References:
     - `docs/TYPE_SYSTEM_PLAN.md`
     - `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
     - `docs/STDLIB_LAYERS.md`
