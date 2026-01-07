# Active Tracker (Succinct)

**Last updated:** 2026-01-07

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
		   - Recent completions are tracked in `docs/TODOS_ARCHIVE.md` (keep this list focused on what’s next).
		   - New (2026-01-06): x86_64 cross-target self-host compiler builds are now bounded (no multi-minute stalls in single backend helper functions); details in `docs/TODOS_ARCHIVE.md`.
		   - Remaining (active): rtobj-miss (cold) path is still too slow in stage2-native due to runtime bundle decode + runtime decl compilation; keep pushing toward **< 10s** cold “compile one file” when caches are empty (see `docs/TODOS_ARCHIVE.md` for current measurements + profiling knobs; current is ~`15s` on arm64-macos stage2 for `examples/hello.oren` in `./scripts/bench_native_compile_one_file.sh --no-debug` run-1 (isolated rtobj dir; seed disabled)).
		     - New (2026-01-05): introduced a smaller “core” native runtime entry (`lib/runtime_native_core.oren`) selectable via `OREN_NATIVE_RUNTIME_PROFILE=core` so cold rtobj misses can be bounded for typical programs without removing the full runtime surface (default remains `lib/runtime_native.oren`).
		       - Seed support: `scripts/build_runtime_astbin_seed.sh` now seeds full+core+capsule runtime astbins; `scripts/build_rtobj_seed.sh` supports `--runtime-profile` (or env `OREN_NATIVE_RUNTIME_PROFILE`) without pruning other profiles' seeds.
		       - Fixed (2026-01-06): build cache key now hashes the effective injected native runtime entry (full vs core), so switching `OREN_NATIVE_RUNTIME_PROFILE` cannot reuse cached artifacts built with a different runtime (details in `docs/TODOS_ARCHIVE.md`).
			     - Recent (2026-01-04): x86_64 cross-target cold miss is still expensive when the rtobj seed is disabled, but it is materially improved by:
				       - eliminating per-instruction allocations in the x64 encoder (`lib/compiler/x64_core.oren`)
				       - keeping capsule enforcement implementation out of the non-capsule runtime rtobj (`lib/runtime_native/035_capsule_stubs.oren`)
				       - simplifying runtime decl hotspots to reduce stage2-native decl compile work (`oren_iter_next`, `oren_bytes_from_string_ptr`, `oren_int_to_string`), plus using `iadd`/shifts in byte loops to avoid slow generic `+`/`*` lowering (details in `docs/TODOS_ARCHIVE.md`)
						       - Recent (2026-01-05): x64 intrinsic temp spill slots are now addressed via compiler-internal `IntrTmp{idx}` nodes + a per-function base-offset reservation (`ctx["intr_tmp_base_off"]`), eliminating `$tmp_intrN` identifier strings and per-function locals-map inserts in stage2-native rtobj builds.
						       - Fixed (2026-01-06): x64 intrinsic-temp spill allocator now reserves slot 0 (1-based indices) to avoid stage2-native `nil==0` collisions that could silently skip call/arg lowering (e.g. “print disappears” / missing string literals); regression gate added to `scripts/verify_native_x64_compile_only.sh` (details in `docs/TODOS_ARCHIVE.md`).
					       - Recent (2026-01-04): native runtime `oren_string_from_bytes` restored a fast list-backed-buffer copy path (keeps lexer/tooling bounded); u8_buf continues to use the slice helper fast memcpy path.
					       - Note (regression prevention): compiler-side helpers must remain portable across stage1 (C runtime) and stage2 (native runtime); avoid using `ptr_*` byte loads on “string” values unless explicitly guarded.
					       - Next: continue shrinking the rtobj decl bucket by refactoring remaining large native-runtime helpers (recent top decls include `oren_string_from_bytes` and `oren_net_get`; prefer direct buffer access and `iadd`/shift arithmetic in loops).
				       - stage2 `--platform x64-linux` true miss (isolated rtobj dir; `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0`, astbin seed enabled): rtobj `total_ms` ~`17–18s` (`parse_ms` ~`1.8s`, `decls_ms` ~`14.0s`), with `OREN_TRACE_X64_RT_OBJ_SUMMARY=1`.
				       - same build with rtobj seed enabled (empty cache dir; seed-hit): ~`5.3s` total (see `make rtobj-seed-x64`).
		     - Capsule note (resolved): stage2-native “cold parse” of `lib/runtime_native_capsule.oren` can be tens of seconds if the runtime astbin cache is empty; this is now mitigated by the runtime-astbin seed (`make astbin-seed`, `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR`) so cold capsule builds can stay under the default 10s timeout in typical dev setups.
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

1) **Tier‑1 native support parity (arm64-macos + arm64-linux + x64-linux + x64-windows)** (L)
		   - Keep native semantics aligned across platforms:
	     - callables/closures/varargs + deterministic failure modes (`OREN_DIAG` + stack traces)
	     - container ops (list/map/buf) with identical semantics across arch/OS
	     - concurrency primitives on Windows (no fork/pipe assumptions): `spawn`, `oren_join(_timeout)`, and a path to cooperative cancellation
			   - Fixed (2026-01-07): x86_64 self-host compiler run gate (Win11 + WSL2) now passes; keep this as a hard regression gate:
				     - `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` (details in `docs/TODOS_ARCHIVE.md`)
				       - Also proves host auto-detection (remote runs omit `--platform` and rely on runtime host detection / `OREN_PLATFORM` fallback).
			   - Fixed (2026-01-07): stage0 (Go bootstrap) can build stage1 on **x64-windows** using VS2022 `cl.exe`, and the resulting stage1 binary can run on Windows (stack-safe entrypoint).
			     - Regression gate: `./scripts/verify_stage0_windows_bootstrap.sh` (details in `docs/TODOS_ARCHIVE.md`).
					     - Remaining gaps (active):
					     - NET stdlib maturity (production direction):
					       - Current: `lib/std/net/http.oren` supports HTTP/1.1 GET over TCP (Content-Length + chunked; IP-only; no TLS/DNS/keep-alive pooling yet).
						       - Fixed (2026-01-07): Tier‑1 NET loopback is now regression-gated across `arm64-macos` + `arm64-linux` + `x64-windows` + `x64-linux` (stage1 + stage2) via `./scripts/verify_native_net_matrix.sh`.
						       - Fixed (2026-01-07): WebSocket v0 (ws:// handshake + masked text frames + loopback echo) implemented and added to the Tier‑1 NET matrix (`tests/native/test_ws_echo_loopback.oren`).
						       - Fixed (2026-01-07): Win11 WS echo loopback flake eliminated by hardening NET read/write against spurious readiness timeouts (optimistic `recv`/`send` first; retry until deadline instead of returning `ETIMEDOUT` immediately).
						       - Next: structured HTTP client/server surface (headers map + status + streaming body), then production WebSocket:
						         - Fixed (2026-01-07): ping/pong/close frames are handled in `ws.recv_text` (auto-pong + ignore pongs), and `ws.send_ping_{client,server}` exists.
						         - Fixed (2026-01-07): client key + masking are no longer constant (best-effort time-seeded xorshift32).
						         - Remaining: define a portable OS entropy/RNG surface (avoid “toy RNG” for protocol masking/keys) and plumb it through NET/stdlib.
						         - fragmentation + binary frames + streaming recv API
						         - then HTTP/2 framing on top of the TCP substrate (then TLS + DNS layers).
			     - Fixed (2026-01-04): **arm64-macos stage2 is now bootstrapped via the native backend by default** (`make stage2`).
			       - Fallback (bring-up): `make stage2 OREN_STAGE2_BACKEND=c`.
			    - Native FFI / dynamic linking parity (rolling):
			      - Current reality:
			        - **macOS (Mach‑O):** `ffi` works via dyld binding opcodes + `--link` dylibs.
			        - **Windows x64 (PE):** `ffi` works via lazy `LoadLibraryA`/`GetProcAddress` stubs; `--link` supplies DLL search names/paths (kernel32 searched by default).
			        - **Linux (ELF):** dynamic linking is not implemented yet; calling an `ffi` symbol panics (FFI not functional yet).
			      - Regression gates (current):
			        - Remote Win11: `scripts/verify_native_matrix.sh --targets x64-win` runs `tests/native/ffi_windows_kernel32.oren` (stage1 + stage2).
			        - Local sanity: `make verify-native-x64-compile` compiles Windows FFI examples (including `--link msvcrt.dll` propagation checks).
			        - Linux bring-up contract: `scripts/verify_native_matrix.sh --targets arm64-linux` (and `x64-wsl`) runs `tests/native/ffi_linux_unresolved_panics.oren` and asserts:
			          - the program fails with `ffi unresolved:` (until ELF dynamic linking is implemented), and
			          - the debug stack trace includes `oren_panic` (runtime frame symbolization under rtobj cache mode).
			      - Deliverable (remaining): Linux ELF `DT_NEEDED` + PLT/GOT relocations (or an explicit dynamic-loader strategy) so `ffi` becomes real on `x64-linux` and `arm64-linux`.
			      - Then un-skip the native FFI example path in `make examples-test` on Linux.
			    - Shared library output parity (native `--lib`/`--shared`):
			      - arm64 Mach‑O supports `--lib` today (`.dylib` + headers/metadata).
			      - Remaining: implement x86_64 ELF `.so` and x86_64 Windows `.dll` emission, including export tables and metadata/header generation hooks.
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
		       - Fixed (2026-01-06): arm64 debug stack traces now symbolize runtime frames under rtobj cache mode (no more `???` for helpers like `oren_panic`).
		         - Runtime-object cache meta now persists runtime debug function ranges, and the arm64 compiler merges them into the final embedded debug-info table at rtobj apply time.
		         - Linux/arm64 unresolved-import stubs are also added to the debug-info table so `ffi` panics show the failing symbol frame.
		         - Regression gate: linux/arm64 container step in `scripts/verify_native_matrix.sh` asserts both `ffi unresolved:` and `oren_panic` are present in output.
		       - Fixed (2026-01-04): arm64 varargs wrappers no longer self-recurse in native codegen.
		         - Added a `cur_fn_name` context so call lowering can skip varargs “callable-object” lowering inside `__oren_fnwrap_*`.
		         - Result: `tests/fixtures/tier1_native_smoke_main.oren` runs successfully on `arm64-macos` native backend in debug mode.
		       - Fixed (2026-01-07): x86_64 stage2 varargs+spread calls no longer recurse inside `__oren_fnwrap_*` (Win11 Tier‑1 “call depth exceeded” abort).
		         - Fnwrap synthesis now marks the internal call as already-packed via `__oren_varargs_packed`.
		         - The x64 call emitter skips varargs packing when that marker is present (pack exactly once).
		       - Fixed (2026-01-04): x86_64-linux Tier‑1 spawn/join now runs successfully under remote WSL2 (stage1 + stage2).
		         - Root cause: stale cached runtime machine code (rtobj cache) could preserve a buggy historical x64 `sys_pipe` lowering that clobbered the syscall rc while widening fds.
		         - Fix: bumped `RUNTIME_OBJ_BACKEND_SIG_X64` to invalidate cached runtime objects and restored strict runtime checks (`sys_pipe(...) != 0` fails) so regressions are caught immediately.
		         - Perf fix (2026-01-04): x64 rtobj build no longer synthesizes `__oren_fnwrap_*` wrappers for **all** runtime functions.
		           - Now matches arm64’s `fnwrap_needed` strategy (only synthesize wrappers actually used as function values), reducing “compile one file” cold miss on x64 targets (debug) from ~5.4s → ~2.5s in local benchmarks.
		         - Also hardened `scripts/verify_native_matrix.sh` to propagate remote exit codes and assert Tier‑1 output markers (prevents silent early-exit false positives).
		         - Details: `docs/TODOS_ARCHIVE.md`.
		       - Fixed (2026-01-06): x86_64-linux WSL2 native runtime could hang in `oren_select` send cases due to Linux `epoll_event` ABI differences across arch (x86_64 packed vs arm64 aligned); native runtime now probes the active layout once at `native_runtime_init` and uses `OREN_EPOLL_EVENT_*` offsets for select + NET epoll waits (details in `docs/TODOS_ARCHIVE.md`).
		       - Fixed (2026-01-07): x86_64-linux native early-init no longer stack-overflows in alloc-index compare recursion (details in `docs/TODOS_ARCHIVE.md`).
		       - Fixed (2026-01-07): `for x in view` now iterates typed-buffer views (slice/stride/matrix list protocol) instead of iterating view metadata lists.
		         - Implemented in `oren_iter_next(...)` view detection and element loads.
		         - Regression gate: native quick integration test now covers view iteration.
		       - Hardening (2026-01-07): `scripts/verify_native_matrix.sh` retries remote `scp` uploads to avoid flaky proxy connection resets (`OREN_REMOTE_SCP_RETRIES`, default `3`).
						     - x86_64: finish deleting bring-up-only code paths (keep runtime injection mandatory; converge remaining fast paths on the same safety contract).
						       - Fixed (2026-01-04): x64 no longer eagerly synthesizes `__oren_fnwrap_*` for every named user function.
						         - Now uses `fnwrap_needed` to synthesize/compile fnwraps only when a function is used as a value (also works for runtime functions, including rtobj mode).
						         - Bumped x64 rtobj backend sig to invalidate cached runtime objects after wrapper emission strategy changes.
					     - (performance) stage2-native runtime bundle cost remains high; keep iterating toward:
			       - default: hashed runtime AST cache under `build/cache/native_runtime_astbin/` (disable via `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0`)
			       - default (Tier‑1 throughput): cached compiled runtime object under `build/cache/native_runtime_obj/` (disable via `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`)
				       - optional (fast first-run): rtobj “seed” dir under `build/cache/native_runtime_obj_seed/` (override via `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=...`, disable with `0`); generate with `make rtobj-seed` (host) and `make rtobj-seed-x64` (cross `x64-linux`/`x64-windows`)
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
