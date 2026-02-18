# Active Tracker (Rolling)

**Last updated:** 2026-02-18

This repo is in rolling mode. This file tracks the **highest-leverage work remaining** to evolve Oren
into a modern, efficient, production-ready language and toolchain, while keeping iteration fast.

Long-form history and detailed “what we fixed last week” write-ups live in:

- `docs/TODOS_ARCHIVE.md`

## How to use this tracker

- Start at **P0 (Now)** and take the first unfinished item that blocks Tier‑1 parity/perf.
- Keep this file **short and actionable**:
  - “What is the next deliverable?”
  - “What is the regression gate?”
  - “Where is the design doc / implementation?”
- When a task is “done enough” (rolling):
  - move the deep narrative to `docs/TODOS_ARCHIVE.md`
  - keep only a short status note + the gate here

Legend:

- Priority: **P0 (Now)** > **P1 (Soon)**
- Size tags: **(S/M/L)** = expected scope (not difficulty)
- Tier‑1 targets intent: `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`
  - x64-linux execution is validated via WSL2 when available; current remote host is Win11-only (`docs/REMOTE_X64_ENV.md`)

## “Maturity” definition (rolling, measurable)

Oren is “maturing” when the following are reliably true:

- **Buildability:** stage0→stage1→stage2 works on each Tier‑1 host OS/arch with minimal manual setup.
- **Native parity:** native backend semantics match across Tier‑1 (not “macOS only works”).
- **Performance budgets:** “compile one file” stays bounded (hit + cold miss).
- **Docs fidelity:** manuals/spec match real behavior (fixtures are the living spec).
- **Stdlib quality:** NET/TLS/HTTP/WS are correct and bounded under loopback tests, and crypto is layered
  under `std:crypto/*` (not trapped as NET-only helpers).

## Regression gates (run first when touching compiler/runtime)

Local (fast):

- `make test` (fast native smoke; stage1 + stage2 quick integration + capsule)
  - Includes “must fail” fixtures (e.g. `scalar == nil` hazards, reserved `__oren_type`).
- `make verify-native-quick` (alias of `make test`; stage1 + stage2 + capsule)
- `./scripts/verify_x64_linux_qemu_smoke.sh` (x64-linux execution under QEMU in the persistent Linux container)
  - Runs the native quick integration binary both normally and with `OREN_GREEN_POLL_CACHE=1` (catches cached-scheduler-local hazards on x86_64).
    - Cached-mode runs set `OREN_TEST_SLOW=1` to scale a small set of join timeouts for qemu (keeps the gate bounded but non-flaky).

Tier‑1 cross-arch (execution on real hosts):

- `./scripts/verify_native_matrix.sh` (native quick across local + container + remote x64)
  - `--skip-remote` is allowed when remote Win11/WSL2 is unreachable (explicitly skips).
- `./scripts/verify_native_net_matrix.sh` (TCP/UDP/DNS/HTTP/HTTPS/WS/WSS/TLS + HTTP/2/HPACK loopback; stage1 + stage2; all Tier‑1)
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` (compiler runs on x64 hosts and compiles+runs a tiny native program)
- `./scripts/verify_stage0_windows_bootstrap.sh` (stage0→stage1 via MSVC on Win11; stage1 builds+runs a tiny native program)

Local x64 (compile-only confidence, even if remote is down):

- `make verify-native-x64-compile` (stage1 + stage2 emit x64-linux + x64-windows)
- `make verify-native-x64-selfhost-compile` (stage2 compiles the compiler program for x64-linux + x64-windows; compile-only but higher-signal)
  - Default source: `oren_x64.oren` (x64-focused; avoids compiling arm64 native backends into x64 artifacts)
  - Override: `OREN_SELFHOST_SRC=oren.oren make verify-native-x64-selfhost-compile`

References:

- Perf playbook: `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`
- Remote x64 workflow: `docs/REMOTE_X64_ENV.md`
- Language docs baseline: `docs/LANGUAGE_MANUAL.md`, `docs/LANGUAGE_SPEC.md`, `docs/LANGUAGE_FEATURE_MATRIX.md`, `docs/LANGUAGE_STATUS_AND_GAPS.md`
  - Last sync (fact): 2026-01-11
- 2026-02-13: `@cfg` supports statement-level filtering, `debug`/`release` selectors, and the `@debug`/`@release` shorthand (see `docs/ATTRIBUTES.md`).

## P0 (Now)

Rolling priority override (2026-01-16): **Native scheduler / GMP greenlet M:N groundwork** is the current focus area (see item 9).

1) **Keep native backend bounded + predictable (perf + stability)** (L)

   Budgets (primary dev host; rolling hard expectations):

   - stage2-native “compile one file” **rtobj hit** (non-capsule): **< 4s**
   - stage2-native “compile one file” **cold** (empty caches): target **< 10s**
   - stage2 self-host compiler build: **< 3 minutes**

   Gates:

   - `make test`
   - `./scripts/verify_native_net_matrix.sh` (large-graph compile + run)

	   High-leverage direction:

	   - shrink the injected runtime surface compiled on cold misses (rtobj layering / reachability)
	   - keep rtobj seed tooling aligned with the compiler’s default runtime-profile heuristic (`auto` ⇒ core unless `std:net/*`); seed `full` explicitly for NET/TLS-heavy bring-up
	   - keep module parsing parallelism safe by default (fork-mode parallel parse without huge logs)
		   - reduce compiler dependency on shell commands for filesystem ops in core tooling where possible:
		     - Goal: make “compiler-in-capsule” and minimal environments more reliable (especially on Windows hosts where POSIX shims vary).
		     - Direction: provide a small syscall-first filesystem helper surface usable by both native and C backend runtimes (avoid `oren_system("mkdir -p ...")` for core operations).
		     - Keep it bounded: implement only what the compiler needs (mkdir -p, rm -f, rm -rf, exists, rename).

		   Status (fact):

				   - 2026-01-12: eliminated compiler dependency on shell `mkdir` for core tooling by adding `oren_mkdir_p`:
			     - C backend runtime: `lib/runtime/050_io_misc.inc` (`oren_mkdir_p` returns 0 / -errno)
			     - native runtime: `lib/runtime_native/230_binary_io.oren` (`oren_mkdir_p` implemented via `sys_mkdir` + `sys_stat` dir check)
			     - compiler tooling: `ensure_dir(...)` now calls `oren_mkdir_p` (no `oren_system("mkdir ...")`)
			   - 2026-01-13: fixed a Windows correctness edge-case in native `oren_mkdir_p` (`-EEXIST` on existing directory):
			     - Root cause: in x64-windows bring-up, calling `_oren_is_dir(path) -> bool` could return a spurious `false` even when `sys_stat` reports a directory.
			     - Fix: `oren_mkdir_p` now inlines `sys_stat` + mode check for the `-EEXIST` path (avoids relying on `_oren_is_dir` in the compiler/tooling hot path).
			     - Verified: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` (includes the Windows backslash-path compile+run gate).
			   - 2026-01-12: removed compiler dependency on shell `rm` / Windows `del` for core tooling:
			     - C backend runtime: `oren_unlink`, `oren_rmdir`, `oren_rm_rf` (0 / -errno; `rm -rf` ignores missing path)
			     - native runtime: `oren_unlink`, `oren_rmdir`, `oren_rm_rf` (implemented via `sys_unlink/sys_rmdir/sys_lstat` + `oren_readdir`)
			     - compiler tooling: no `oren_system("rm ...")` / `oren_system("del ...")` under `lib/compiler/compiler/*`
			   - 2026-01-12: removed compiler dependency on shell `test -f` / `if exist` probes for `file_exists(...)`:
			     - runtime: `oren_is_file(path)` (C + native) so stage1 tooling can check existence without shelling out
			   - 2026-01-13: added a hard guardrail to keep the compiler/runtime free of `rg`/ripgrep dependencies:
				     - `scripts/guard_no_external_rg_dependency.sh` scans `lib/**/*.oren` and fails if it finds any `oren_system(... rg ...)`-style shell-outs.
				     - Wired into default `make test` (native quick integration smoke).
			   - 2026-01-12: verified x64 native selfhost compile-only gate still passes after the runtime FS-helper refactor:
			     - `make verify-native-x64-selfhost-compile` (targets: x64-linux, x64-windows)
				   - 2026-01-12: `scripts/verify_native_x64_compile_only.sh` now pre-seeds native runtime ASTBIN + rtobj (core+full) before running tight per-build timeouts, so the “cold after runtime change” case stays bounded.
				   - 2026-02-14: hardened rtobj meta loading against corruption:
				     - Added a small `meta.check` sidecar (magic/version/len/fingerprint) and atomic writes, so corrupted or partial `meta.astbin` files become cache misses instead of fatal astbin decode exits.
				     - Seed bundles now copy `meta.check` alongside meta/code/data; missing/invalid check files are treated as misses (old caches rebuild on first use).
				   - 2026-02-14: fixed Python interop leaks (C runtime, `OREN_ENABLE_PYTHON`):
				     - `oren_list_get` now decref’s the temporary `py_index` created by `oren_to_py(index)` for `PyObject_GetItem`.
				     - `oren_to_py` map conversion now decref’s temporary key/value objects after `PyDict_SetItem` (which does not steal refs).
				     - `oren_py_to_oren` now consumes new refs for value conversions (DECREFs after copying), preventing leaks for `get_attr`/call results that return non-`PY_OBJ` values.
				   - 2026-02-14: added `py_release(obj)` for manual Python refcount drops (reduces long‑lived `py_obj` leaks):
				     - Runtime: `lib/runtime/030_ops_compare.inc` (`oren_py_release`)
				     - Compiler: `lib/compiler/transpiler.oren` builtin lowering
				     - Docs: `docs/LANGUAGE_SPEC.md`, `docs/SELF_HOSTING.md`, `docs/LANGUAGE_MANUAL.md`
				   - 2026-02-14: added a cross‑backend local perf benchmark harness:
				     - `benchmarks/loop_sum` (C vs Oren C backend vs Oren native vs OBC/AVM)
				     - Runner: `benchmarks/run_benchmarks.py`
				     - M2 Pro baseline (arm64‑macOS, 20M iters): C 0.069s, Oren C 1.231s (~17.7×), Oren native 2.430s (~35.0×), OBC 6.152s (~88.5×)
				     - Result artifact: `benchmarks/results/loop_sum_m2_20260214_114953.md`
				   - 2026-02-14: arm64 native inlines constant RHS modulo (nonzero, not -1) to avoid `oren_mod` call in hot loops:
				     - `benchmarks/loop_sum` (M2 Pro, 20M iters): C 0.0808s, Oren C 1.2187s (~15.1×), Oren native 2.4080s (~29.8×), OBC 6.2733s (~77.6×)
				     - Result artifact: `benchmarks/results/loop_sum_m2_20260214_115726.md`
				   - 2026-02-14: x64 native inlines constant RHS modulo (nonzero, not -1) to avoid `oren_mod` call in hot loops (no x64 bench captured yet).
					   - 2026-02-14: benchmark harness can capture per-run RSS (`OREN_BENCH_RSS=1`):
					     - Result artifact: `benchmarks/results/loop_sum_m2_20260214_120502.md`
					   - 2026-02-14: added `alloc_churn` allocation churn benchmark (GC/leak surface):
					     - M2 Pro baseline (runs=3, warmup=1, `OREN_GC_AUTO=1`): C 0.0042s, Oren C 0.1146s, Oren native 0.6410s, OBC 0.4070s
					     - RSS medians (bytes): C 1.29MB, Oren C 68.6MB, Oren native 54.0MB, OBC 61.4MB
					     - Result artifact: `benchmarks/results/alloc_churn_m2_20260214_121359.md`
					   - 2026-02-14: alloc_churn with lower GC threshold (`OREN_GC_ALLOC_THRESHOLD=200000`) did not reduce RSS (but increased runtime):
					     - Result artifact: `benchmarks/results/alloc_churn_m2_20260214_121632.md`
					   - 2026-02-14: loop_sum refresh (M2 Pro, 20M iters): C 0.0673s, Oren C 1.2218s (~18.1×), Oren native 2.2507s (~33.5×), OBC 6.0740s (~90.3×)
					     - Result artifact: `benchmarks/results/loop_sum_m2_20260214_133422.md`
					   - 2026-02-14: loop_sum refresh (M2 Pro, 20M iters; host-tagged runner): C 0.0694s, Oren C 1.2289s (~17.7×), Oren native 0.3880s (~5.6×), OBC 6.0913s (~87.8×)
					     - Result artifact: `benchmarks/results/loop_sum_darwin_arm64_20260214_143629.md`
						   - 2026-02-14: alloc_churn refresh (M2 Pro, runs=5, warmup=1): C 0.00275s, Oren C 0.1182s, Oren native 1.2805s, OBC 0.4110s
						     - Result artifact: `benchmarks/results/alloc_churn_m2_20260214_133613.md`
						   - 2026-02-14: loop_sum refresh (M2 Pro, runs=5, warmup=1): C 0.0659s, Oren C 1.1754s (~17.8×), Oren native 0.4205s (~6.4×), OBC 5.7436s (~87.2×)
						     - Result artifact: `benchmarks/results/loop_sum_darwin_arm64_20260214_165701.md`
						   - 2026-02-14: alloc_churn refresh (M2 Pro, runs=5, warmup=1): C 0.00289s, Oren C 0.1078s, Oren native 0.5712s, OBC 0.3880s
						     - Result artifact: `benchmarks/results/alloc_churn_darwin_arm64_20260214_165758.md`
					   - 2026-02-14: native '+' int fast-path (arm64) using inty propagation:
					     - Avoids `oren_add` when both operands are known integer-like (keeps runtime helper for strings/unknown).
					     - Compiler: `lib/compiler/arm64_native_expr/010_lowering_a.oren` + inty tracking in `arm64_native_stmt.oren`
					     - Bench (loop_sum, M2 Pro, 20M iters): C 0.0713s, Oren C 1.2655s (~17.7×), Oren native 2.1598s (~30.3×), OBC 6.0519s (~84.8×)
					     - Result artifact: `benchmarks/results/loop_sum_m2_20260214_134458.md`
					   - 2026-02-14: native '+' int fast-path (x64) using inty propagation:
					     - Avoids `oren_add` when both operands are known integer-like; keeps runtime helper for strings/unknown.
					     - Compiler: `lib/compiler/x64_native_program/046_emit_string_helpers.oren` + inty tracking in `060_emit_ops.oren`
					     - Benchmark pending (capture x64 loop_sum baseline on Tier‑1 Linux/Win).
					     - 2026-02-14: remote Win11 host (`pc2.work`) could not pull from GitHub (connection reset/timeouts); need alternate sync or retry before capturing x64 results.
					   - 2026-02-14: native free-block reuse now exists but is **gated** behind `OREN_GC_REUSE_BLOCKS=1` (default off pending GC correctness hardening):
				     - Runtime: `lib/runtime_native/100_time_gc_alloc.oren`
				     - Compiler: `lib/compiler/arm64_native_expr/090_tail.oren`, `lib/compiler/x64_native_program/040_emit_expr.oren`
				     - alloc_churn RSS on macOS remained at the high-water mark (bump allocator retains OS pages):
				       - Result artifact: `benchmarks/results/alloc_churn_m2_20260214_122357.md`
				     - Guard: enabling reuse currently trips `list_len on non-list` in native quick integration (select path); keep gated until GC/alloc invariants are hardened.
				   - 2026-02-14: allocator hardening for native runtime metadata:
				     - Raw tracking nodes now come from a dedicated raw arena (`sys_mmap_private_anon`) instead of the GC heap (`lib/runtime_native/015_raw_alloc.oren`).
				     - Tracking nodes now carry a magic word and are validated during alloc-index lookups/rebuilds (`lib/runtime_native/100_time_gc_alloc.oren`).
				     - Reuse-on now gets past map tracking but still fails quick integration with `list_len on non-list` (select path) — keep gated.
				       - 2026-02-14: reuse diagnostics + guardrails added:
				         - Reuse-mode alloc-index cleanup + cache clear on free/GC (guarded by `OREN_GC_REUSE_BLOCKS`).
				         - Reuse-mode alloc-index miss recovery in `oren_find_node` (linear scan on miss).
				         - `oren_track_alloc` now de-stales kind=0 in reuse mode and removes hit nodes from free list.
				         - `native_list_len_panic` emits list header diagnostics; arm64 list_len intrinsic routes failures through it.
				       - 2026-02-14: select GC rooting hardening:
				         - `oren_select` now allocates `chans`/`vals` arrays with `malloc_k(..., kind=STRUCT)` so GC conservatively scans channel/value pointers.
				         - `oren_select` pins `cases`/`chans`/`vals` via `oren_gc_pin` to keep them visible across safepoints.
				         - `_select_wait_in_green_netpoll_v2` pins `wait_roots` + `chans` + `vals` for netpoll tokens.
				         - `_select_wait_windows_mem_channels` now uses `malloc_k(..., kind=STRUCT)` for chans/vals and pins `cases`/`chans`/`vals`.
				         - Added native runtime root-slot array (`native_gc_root_push/pop`) and hooked it into GC root marking.
				         - `oren_select`/green netpoll/windows mem-select now push cases/chans/vals/wait_roots into root slots to avoid register-only root loss.
				       - 2026-02-14: native `oren_gc_pin` fixed to match C backend semantics:
				         - No longer registers a root slot (which incorrectly dereferenced the pinned object).
				         - GC now marks the pinned value directly during the root phase.
				       - Still failing (reuse-on): list magic overwritten with list pointer in `oren_select` (`test_quick_integration_native`):
				         - Status after root-slot + pinning hardening: still reproduces under `OREN_GC_REUSE_BLOCKS=1` (list magic == list ptr).
				         - trace: list is tracked (kind=2) but header magic is clobbered; likely a remaining GC root/stack spill issue or alloc-index duplication.
				         - Next steps: verify GC pin consumers (compiler/serde/renamer), audit select + netpoll pointer roots, and validate stack/register spill discipline at safepoints.
					   - 2026-01-16: fixed a module-parse parallelism deadlock when stage2 `spawn` is cooperative green tasks (thread-mode but not truly concurrent):
				     - Root cause: the thread-mode join loop polled `oren_is_done(...)` and slept without driving the green scheduler, so spawned workers never ran (hangs x64 compile-only suite).
				     - Fix: detect cooperative spawn and join sequentially (each join drives the scheduler): `lib/compiler/compiler/020_modules_linking.oren` (`_ml_spawn_is_cooperative`).
				     - Guard: `make verify-native-x64-compile` (`scripts/verify_native_x64_compile_only.sh` sets `OREN_PARSE_FORK_PARALLEL=1`).
					   - 2026-01-16: hardened native debug-info parsing so diagnostics never crash debug builds (best-effort tables must not segfault):
					     - Runtime: `lib/runtime_native/110_mem_diag.oren` (`compute_program_pc_bounds`, `find_func_info`) now bails out on malformed lengths/pointers.
					     - Guard: `make test` (native quick integration is built with `--debug` and installs debug info at entry).
					   - 2026-01-16: fixed a deterministic x64-linux execution crash under qemu (`make verify-x64-linux-qemu`) in the TIME monotonic path:
					     - Symptom: `tests/native/test_time_mono_raw.oren` (and native quick integration) segfaults immediately after `clock_gettime(CLOCK_MONOTONIC, ...)` returns 0.
					     - Root cause: Linux/x86_64 `sys_gettimeofday(tv, tz, abs_ptr)` lowering used a 16B `timespec` scratch where the kernel's `+8` write overlapped the spilled `abs_ptr` slot, clobbering it with `tv_nsec` and causing `*abs_ptr = ns` to dereference a small integer.
					     - Fix: use a safe adjacent-slot layout for the `timespec` scratch (pass the deeper slot as the base pointer so the kernel's `+8` write lands in the shallower slot), and bump x64 rtobj backend signature to invalidate stale runtime objects (`x64_v0_14`).
					     - Guard: `make verify-x64-linux-qemu` (stage1 + stage2), plus minimal repro `tests/native/test_time_mono_raw.oren`.
					   - 2026-01-14: fixed an arm64-macos native OS-thread bring-up crash that could be *masked or preserved* by stale rtobj cache entries:
				     - Symptom: `tests/native/test_darwin_os_thread_spawn_join.oren` crashes (SIGBUS) on stage2-native builds when runtime thread registration is enabled and rtobj cache hits.
				     - Root cause: native call-depth hooks recursed via an instrumented slow-path helper when multithreading flips `g_runtime_single_threaded` to 0; stale rtobj cache entries kept the buggy runtime machine code alive even after compiler fixes.
			     - Fix: ensure call-depth slow-path helpers are never instrumented + bump rtobj backend signatures (`arm64_v0_8`, `x64_v0_13` at the time; x64 is now `x64_v0_14`) to invalidate old cached runtime objects.
	   - 2026-01-12: began splitting the >2k-line x64 Linux syscall intrinsic emitter into smaller modules; moved the NET/epoll blocks into `lib/compiler/x64_native_program/046_emit_sys_intrinsics_linux_net.oren` so hot-path compilation of `_emit_intrinsic_sys_linux_x64` stays bounded.
	   - 2026-01-12: introduced an x64-focused compiler entry (`oren_x64.oren` → `lib/compiler/compiler_x64.oren`) that swaps arm64 native backends for small stubs, so x64 self-host builds do not spend time compiling arm64 code.
	     - Fact (arm64-macos host → x64-linux target, `--no-cache`): `./oren_stage2 build oren_x64.oren --backend native --platform x64-linux --no-debug`
       - total ~180s (`[build] summary total_ms=180390`)
       - link (parse+passes) ~103s (`link_ms=102635`)
       - x64 emit+link ~78s (`emit_ms=77747`)
     - This keeps `scripts/verify_native_x64_selfhost_compile_only.sh` under the default 240s timeout (it now defaults to `oren_x64.oren`; override via `OREN_SELFHOST_SRC=oren.oren`).

   Perf gaps from latest M2 benchmarks (2026-02-14, host-tagged results):

   - (P0/M) **Native alloc_churn is still slower than OBC and far behind Oren C**
     - Latest (runs=5): native 0.571s vs OBC 0.388s vs Oren C 0.108s (`benchmarks/results/alloc_churn_darwin_arm64_20260214_165758.md`).
     - Target: native ≤0.20s on M2 for alloc_churn without increasing RSS.
     - Likely work: harden free-block reuse (`OREN_GC_REUSE_BLOCKS=1`), reduce per-alloc tracking overhead, add a bump allocator for short-lived struct-heavy loops, verify GC root coverage at safepoints.
   - (P0/S) **alloc_drop native is catastrophic (drop-path bottleneck)**
     - Latest (50k iters): native 120.6s vs C 0.0087s vs Oren C 0.0407s (`benchmarks/results/alloc_drop_darwin_arm64_20260217_230447.md`).
     - Target: native ≤0.50s on M2 with stable RSS.
     - Likely work: profile drop/GC sweep path, reduce per-drop tracking churn, verify free-list reuse + fast-path for short-lived drops.
   - (P1/M) **Loop_sum native still ~6.4× C**
     - Latest: native 0.4253s vs C 0.0665s (`benchmarks/results/loop_sum_darwin_arm64_20260218_104800.md`).
       - Oren C: 1.1811s; OBC/AVM: 5.8217s (same run).
     - Target: native ≤0.25s (≤4× C) while keeping correctness gates.
  - (P1/M) **Array_sum list access is still ~34× C (native) / ~44× C (Oren C)**
    - Latest: native 0.1435s vs C 0.00418s (`benchmarks/results/array_sum_darwin_arm64_20260218_133631.md`).
      - Oren C: 0.1855s; OBC/AVM: 0.6295s (same run).
    - Target: native ≤0.03s (≤8× C) via faster list element access + fewer boxed int ops.
  - (P0/M) **Dot_product shows heavy list+multiply overhead**
    - Latest (M2 Pro, runs=5): C 0.00493s, Oren C 0.319s (~64.7×), Oren native 0.2196s (~44.5×), OBC 0.9027s (~183×).
      - Result: `benchmarks/results/dot_product_darwin_arm64_20260218_175058.md`
    - Target: native ≤0.03s (≤6× C) via bounds-check hoisting + tighter int multiply path.
   - (P1/M) **Capture x64-windows benchmark baselines (pc2.work)**
     - Blockers observed (2026-02-14):
       - No `oren_stage2.exe` in `G:\work\compiler-mini-git` (bench harness fails to compile Oren variants).
       - `avm.exe` build fails on MinGW: `sys/mman.h` + `clock_gettime` missing; `tools/gen_avm_root_pubkeys_inc.sh` requires MSYS `cat`.
       - 2026-02-17: macOS-built `oren_stage2.exe` exits immediately with `0xC00000FD` (stack overflow) on Win11 (`--version`); PE header stack reserve is 64MB/commit 64KB, so this is likely a recursion/entry bug (not a small stack).
     - Actions:
       - Cross-compile `oren_stage2.exe` for x64-windows on macOS and sync to pc2.work.
      - Triage the x64-windows stack-overflow path (call-depth instrumentation, runtime init, or entry stub) before re-running baselines.
        - 2026-02-17: compiler now skips inserting call-depth hooks when `call_depth_max==0`; try `--call-depth-max 0` to test if hooks are the overflow trigger.
        - 2026-02-17: `oren_stage2_cd0.exe` (built with `--call-depth-max 0`) runs `--version` on Win11 with `EXITCODE=0` (no stack overflow); baseline likely blocked by call-depth hook recursion/entry path.
        - 2026-02-17: `oren_stage2_cd0.exe build examples/hello.oren ... -o build\\tmp\\hello_cd0.exe` returns `EXITCODE=0` but emits no output and produces no file (log empty) — likely argv/envp or stdout handling bug in x64-windows runtime/entry stub.
        - 2026-02-17: entry trace still dies after `ENTRY: register_thread ok` (no `ENTRY: top_level call`).
          - `ENTRY` write helper now reserves its own 0x30 shadow/stack scratch, but stack overflow persists.
          - RSP drift check (r12 vs rsp) after `oren_register_thread` passes.
          - Next: isolate whether the post-register `WriteFile` call itself triggers overflow; try skipping the
            "register_thread ok" print or exiting immediately after register_thread in a trace build.
        - 2026-02-17: rebuilt stage2 and re-ran entry traces with post-register prints suppressed:
          - Trace with `OREN_ENTRY_EXIT_AFTER_REGISTER_THREAD=1` exits with code 241 (so `oren_register_thread` returns).
          - Trace with `OREN_TRACE_X64_ENTRY_AFTER_REG=0` still stack-overflows after `gc_mode ok`,
            implying the crash is in the `__top_level__` call path (or immediately after `oren_register_thread`),
            not in the post-register `WriteFile` trace.
        - 2026-02-18: `OREN_ENTRY_SKIP_TOP_LEVEL=1` (with post-register prints suppressed) avoids stack overflow,
          but exit code is still abnormal (`EXITCODE=291307520` on Win11); add a deterministic exit code when `main`
          is skipped and isolate the `main` path.
        - 2026-02-18: added `OREN_ENTRY_SKIP_MAIN=1` (and default `eax=0` when main is skipped) to bisect:
          - trace reaches `ENTRY: top_level call` and then stack-overflows (`EXITCODE=-1073741571`), so the
            overflow is inside `__top_level__` (or immediately after its call), not in `main`.
        - 2026-02-18: added compile-time top-level slicing (`OREN_TOP_LEVEL_FROM/TO`, `OREN_TRACE_TOP_LEVEL_SLICE`):
          - total synthesized top-level stmts: 242.
          - slice 0:121 still overflows; slice 0:60 OK; slice 60:90 OK; slice 90:121 overflows.
          - slice 90:105 overflows; slice 105:121 OK.
          - => offending initializer is in stmt index range [90,105).
          - Next: dump/top-level-stmt list with indices (or bisect 90:97 vs 97:105) and fix the specific initializer.
        - 2026-02-18: added `OREN_TRACE_TOP_LEVEL_LIST=1` and identified indices 94-100 as `lib/compiler/token.oren`
          char constants + debug flags; switched CH_* to string literals in `lib/compiler/token.oren` and
          `lib/compiler/transpiler.oren` to avoid top-level `oren_char` init.
          - After change: slice 0:121 OK, slices 94:97/97:101 OK, but slice 121:242 still overflows.
          - slice 121:181 OK; slice 181:242 overflows (`EXITCODE=-1073741571`).
          - Next: dump indices 181-242 from top-level list and bisect 181:211 vs 211:242.
        - 2026-02-18: root-cause fixed for Win11 `--version` stack overflow:
          - `std:argparse` `_normalize_key` now uses byte-at + slice-unchecked (avoids single-byte cache init).
          - single-byte string cache now allocates via raw arena and registers pointers in the cstr0 set
            (no GC-root registration during early init).
          - Verified: `oren_stage2_argparse_dbg7.exe --version` runs on pc2.work and prints version.
        - 2026-02-18: x64-windows stage2 now reaches runtime bundle parse, but parsing still crashes:
          - `oren_stage2_cd0.exe build lib\\runtime_native\\011_channels_mem.oren --backend c` exits early on Win11 with trace stopping around stmt index ~20 (offset helper functions).
          - Same crash reproduces during native runtime bundle parse (after `parse_program start`), likely a parser/lexer/GC issue on Win11.
          - Next: add lexer-level tracing on Windows or temporarily disable parser-side GC to confirm; consider prebuilt astbin seeding as a stopgap for benchmarks.
        - 2026-02-18: added GC-root pinning for module linking + safe-mode lexer path, but Win11 parse still crashes:
          - `LINK_GC_ROOT` pins module discovery/parse worklists; `parse_import` pins name/path; lexer safe mode uses `OREN_LEX_SAFE` or `OS=Windows_NT`.
          - With `OREN_TRACE_PARSE_PROGRESS=1` on `examples/hello.oren`, crash still occurs after stmt_i=1 (second import).
          - With `OREN_TRACE_LEX_STEP=1`, crash later while lexing `lib/std/list.oren` around `fn clone` (pos ~575).
          - Next: add GC pins for lexer/parser locals or temporarily disable GC during parse; capture a minimal repro to validate string lifetime on Win11.
        - 2026-02-18: minimal Win11 lexer repro isolated to long line comments (native backend):
          - `build\\tmp\\comment_only_40.oren` OK; `comment_only_45.oren` stack-overflows (`EXITCODE=-1073741571`).
          - Repro file content: `// ` + 45×`a` + `\\n` (no code required).
          - Fixture: `tests/fixtures/windows/lexer_comment_repro.oren`.
          - Still crashes with `OREN_NO_GC=1` and `OREN_LEX_SAFE=0`.
          - `OREN_TRACE_DUMP=1` or `OREN_TRACE_LEX_STEP=1` avoids the crash (heisenbug).
          - Next: audit native string-compare path + map key compare recursion; consider a byte-only lexer (no map lookups in hot loops) or a Windows-only fast comment skip that avoids `l["ch"]` string compares entirely.
        - 2026-02-18: hardened `strcmp` pointer checks (avoid `==` on raw pointers) but Win11 comment repro still overflows.
        - 2026-02-18: latest trace shows crash during module discovery (even earlier):
          - With `OREN_TRACE_PASSES=1` + parse tracing, Win11 exits after `discover_module: lib/std/list.oren` (list has no imports).
          - Next: instrument `_ml_scan_imports_in_src` + `discover_module` to pinpoint the fault; consider Windows-only fallback to parser-based import scanning if the fast scanner is corrupting memory.
       - Decide if AVM should be Windows-capable (add win32 time/mmap shims) or allow `OREN_BENCH_SKIP_OBC=1` (bench runner now supports this).

2) **Tier‑1 native parity: correctness across arch/OS** (L)

   Goal: “same program, same result” across Tier‑1, not “macOS only”.

   Parity surfaces:

   - value semantics (`nil/false/true` vs numeric), comparisons, list/map behavior
   - (P0/S) **STW GC saved_sp stability**: investigate why `stw_saved_sp` zeros out on macOS (stack-size fallback masks it now).
     - Gate: `tests/native/test_gc_stw_os_thread_collect.oren` passes on all Tier‑1 without relying on stack-size fallback.
     - Follow-up: capture stack size for Linux/Windows OS threads (store in thread node) so fallback is valid cross‑platform.
   - eliminate legacy “nil==0” / 0-sentinel assumptions (0 is a valid int and is truthy; `nil/false/true` are runtime singletons)
     - Fixed: x64 ModRM disp8 emission no longer uses a “disp8+1” encoding (see `lib/compiler/x64_core.oren`); `disp8=0` is now a real byte value with `nil` meaning “absent”.
     - Fixed: `std:net/dns.default_resolver` no longer treats missing `OREN_DNS_SERVER` as “present” under native singleton-`nil` semantics (checks `env_ip != nil && env_ip != 0 && env_ip != ""`); Tier‑1 Win11 fixture `tests/fixtures/windows_dns_default_resolver_smoke.oren` now passes.
     - Fixed: mixed `\\` vs `/` in default output paths is eliminated by normalizing `path` and `out_path` via `_path_to_posix_sep(...)` in the build pipeline.
       - Guarded by `make test` path-separator smokes (backslash input + backslash `-o` output).
       - If you still see `.../examples\\myapp` in a log, you are almost certainly running an older `oren_stage2.exe` on the remote host; see `docs/REMOTE_X64_ENV.md`.
   - FFI ABI correctness (sign/zero extension, void return, ptr-sized returns)
   - NET/TLS end-to-end behavior (timeouts, buffering, determinism knobs)

   Gates:

   - `./scripts/verify_native_matrix.sh`
   - `./scripts/verify_native_net_matrix.sh`
   - `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`

   Status (fact):

	   - 2026-01-12: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` passed (compiler runs on Win11 (WSL2 optional) and compiles+runs a tiny native program on both).
		   - 2026-01-13: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` extended with a filesystem directory gate (`fs_dir_gate.oren`) and remains green:
		     - proves `oren_mkdir_p` handles the `-EEXIST` case correctly for directories
		     - proves `sys_stat` reports directory mode correctly on both WSL2 (x64-linux) and Win11 (x64-windows)
		   - 2026-01-13: `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` passed (remote Win11 + remote WSL2; stage1 + stage2).
	   - 2026-01-15: `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` passed (remote Win11 + remote WSL2; stage1 + stage2).
	   - 2026-02-13: `pc2.work` Win11 host is online, but WSL2 is not installed/enabled yet; `x64-wsl-tier1` is blocked until WSL is enabled (use x64-win only for now).
   - 2026-01-12: fixed the native runtime lock blocking primitive on Tier‑1:
     - `sys_ulock_wait/sys_ulock_wake` are now treated as a portable "wait-on-address" primitive:
       - Linux: `futex(FUTEX_WAIT_PRIVATE/FUTEX_WAKE_PRIVATE)`
         - Timeout code is normalized to portable `-60` (Darwin ETIMEDOUT), even though Linux futex uses `-ETIMEDOUT` (`-110`).
       - Windows: `WaitOnAddress/WakeByAddressAll` imported from `KERNELBASE.dll` (kernel32 import can fail with `STATUS_ENTRYPOINT_NOT_FOUND` on Win11).
     - Added a direct ulock handshake to `tests/fixtures/tier1_native_spawn_join_main.oren` (remote x64 gate).
     - Verified end-to-end with `./scripts/verify_stage0_windows_bootstrap.sh` and `./scripts/verify_windows_stage2_from_stage1.sh`.
   - 2026-01-12: fixed `oren_intern_cstr` cache behavior under the native runtime on x86_64:
     - Root cause: `native_value_is_nil(...)` returns `true/false` **singletons**, not numeric `0/1`, so comparing it to `0` breaks cache-hit detection.
     - `oren_intern_cstr` now treats map misses as `nil` and checks `native_value_is_nil(cached) != true` before returning cached values.
     - Tier‑1 fixture now uses `false` (not numeric `0`) for the boolean short-circuit guard (`false && boom()`), matching the language spec (`0` is truthy).
     - Verified end-to-end via `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` (stage1 + stage2; Win11 (WSL2 optional)).
   - 2026-01-12: hardened Tier‑1 remote gate on Windows:
     - `scripts/verify_native_matrix.sh` now enforces Tier‑1 markers on Win11 too (not just WSL2).
     - Prevents “silent early exit still returns 0” false positives (Tier‑1 must print `tier1 spawn join ok` and `tier1 proc ok`).
   - 2026-01-12: added a Tier‑1 truthiness guardrail:
     - `tests/fixtures/tier1_native_smoke_main.oren` now asserts that numeric `0` is truthy, and only `nil`/`false` are falsey.
     - Prevents regressions where a fixture (or stdlib) accidentally assumes “0 is false” and masks real bugs.

3) **Native value representation + reflection-first type system** (L)

   Problem: the native value model is not fully tagged; “dynamic” flows historically produced hazards.

   Deliverables (design → implementation):

   - finish the tagged-value plan: `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
   - stabilize reflection APIs: `docs/REFLECTION_V1.md`
   - define how varargs elements carry type info so userland (fmt/ffi/serde) is robust
   - audit “optional string/env” checks across stdlib/compiler: avoid `v != 0` presence tests (under singleton-`nil`, `nil != 0` is true); standardize on `v != nil && v != 0 && v != ""` or a helper
   - nil-vs-scalar parity: either land tagged values (preferred) or keep evolving the nil-compare guard so it catches common “dynamic config value used as scalar later” patterns (e.g. `cfg["timeout_ms"]` followed by `x + 1`) without over-flagging intentional nil-coalescing idioms in core code

   Gate:

   - `make test` (nil-compare guard is always-on; diagnostics tagged `nil-compare guard:`)

	   Status (fact):

	   - 2026-01-12: added `lib/std/reflect.oren` (minimal reflection wrappers + stable tag constants) and wired it into the native quick integration smoke.
	   - 2026-01-12: expanded the native quick integration reflection+varargs gate (`tests/native/test_quick_integration_native.oren`) to cover `bool` + `func`, and to be forward-compatible with eventual float tagging (`int` vs `float` best-effort today).
	   - 2026-01-12: fixed x64 native “function values” parity so `reflect.tag(add)` is stable under stage2:
		     - x64 now materializes first-class function values via `oren_func(code_ptr, env_ptr)` (tracked kind=6), matching arm64.
		     - rtobj (cached injected runtime) path now marks `ctx["runtime_injected"]=true`, so Tier‑1 lowering paths are consistently selected.
		     - Guarded by `./scripts/verify_native_matrix.sh --targets x64-win,x64-wsl` (stage1 + stage2).
	   - 2026-01-13: Tier‑1 native smoke now asserts the reflection v0 contract on real x64 hosts (Win11, WSL2 optional):
	     - `tests/fixtures/tier1_native_smoke_main.oren` checks `reflect.tag/name` for `nil/bool/int/string/func/list/map/u8_buf`
	     - also checks that struct values expose a stable name via `__oren_type` (even though structs remain map-shaped in v0)
	     - and checks that identical string literals are deduplicated in the cstr0 pool (pointer identity stable; literals are not GC-tracked)
	   - 2026-01-13: added a compile-fail fixture to lock the reserved `__oren_type` struct key contract:
	     - `tests/fixtures/typecheck_bad_reserved_struct_field_oren_type.oren` must fail to parse/typecheck
	     - enforced by `scripts/run_native_quick_integration.sh` (so it runs under `make test` / Tier‑1 quick smokes)
	   - 2026-01-13: reduced log noise for the reserved `__oren_type` diagnostic:
	     - parser now error-recovers to the closing `}` for this case, avoiding cascading “no prefix parse fn” errors.
	   - 2026-01-12: nil-compare guard now treats arithmetic-with-numeric-literal as scalar evidence (covers index reads + locals/params) (fixtures: `tests/fixtures/nil_guard_bad_late_arith_literal_nil_compare.oren`, `tests/fixtures/nil_guard_bad_param_arith_literal_nil_compare.oren`).

4) **Stdlib NET/TLS/HTTP/WS maturity (not toy protocols)** (L)

   Goal: a production-grade loopback-verified stack:

   - TCP/UDP correctness + bounded timeouts
   - TLS providers per OS (working today) + clearer trust/verify story
   - HTTP/1.1: structured response + streaming body
   - WebSocket: fragmentation + binary frames + streaming recv API
   - HTTP/2: flow control + multi-stream mux + GOAWAY/RST_STREAM basics

   Gate:

   - `./scripts/verify_native_net_matrix.sh`

   Doc roots:

   - `docs/NET_TLS.md`, `docs/NET_HTTP2.md`, `docs/NET_WEBSOCKET.md`

   Status (fact):

	   - 2026-01-12: `./scripts/verify_native_net_matrix.sh --targets all` passed (stage1 + stage2; local + linux/arm64 container + remote Win11 + remote WSL2)
	     - Covers TCP/UDP + DNS + HTTP/1.1 + WS, plus TLS/HTTPS/WSS and HTTP/2 (preface + HPACK + headers loopback).
	   - 2026-01-13: `./scripts/verify_native_net_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` passed (remote Win11 + remote WSL2; stage1 + stage2).

5) **Crypto library layering (separate from NET)** (M)

   Goal: `std:crypto/*` becomes the stable home for:

   - PEM/DER parsing helpers, X.509 helpers, TLS facade/core layering

   Next steps:

   - split TLS into a crypto core (`std:crypto/tls_*`) + net integration (`std:net/tls`)
   - define CA/trust story per provider (Windows SChannel / macOS SecureTransport / Linux OpenSSL)

6) **Windows host developer experience (“make works” under MSYS2/Git Bash)** (M)

   Goal: `make stage1`, `make stage2`, `make test` work on native Windows hosts with VS2022 installed.

   Gate:

   - `./scripts/verify_stage0_windows_bootstrap.sh`
   - `./scripts/verify_windows_stage2_from_stage1.sh`

   Status (fact):

	   - 2026-01-12: `make verify-stage0-win` passed (remote Win11, stage0→stage1 via MSVC `cl.exe`)
	   - 2026-01-12: `make verify-stage2-win` passed (remote Win11, stage0→stage1→stage2 native + C-backend smoke using default `--cc`)
	     - Follow-up guard: `scripts/verify_windows_stage2_from_stage1.sh` also compiles `examples/ui_hello.oren` and builds the Win32 OrenUI shim DLL via `scripts/win_msvc_cmd.cmd` (no GUI run; compile/link guard only).
	     - 2026-01-12: `scripts/verify_windows_stage2_from_stage1.sh` now also proves the C backend works with **default `--cc`** on Windows (auto-picks MSVC `cl.exe`; does not require a Unix-like `cc`).
	   - 2026-01-13: `make stage2 OREN_STAGE2_BACKEND=c` is now robust on Windows hosts by default:
	     - Makefile defaults `OREN_STAGE2_CC=cl.exe` when using the stage2 C-backend bootstrap path (override via `OREN_STAGE2_CC=...`).
		   - 2026-01-13: fixed an MSVC-only C parser hazard where a `// ... \` comment line-continuation broke stage0→stage1 bootstrap:
		     - Root cause: `lib/runtime/050_io_misc.inc` had a comment `// UNC prefix: \\server\share\` ending in a backslash; MSVC treats `\\\n` as a line continuation even in `//` comments (C4010), corrupting subsequent C tokens.
	     - Fix: comment no longer ends with `\`.
	     - Guardrail (2026-01-13): `scripts/guard_no_msvc_comment_line_continuation.sh` is wired into `make test` to prevent recurrence.
	   - 2026-01-13: `scripts/verify_windows_stage2_from_stage1.sh` passed (remote Win11; stage0→stage1→stage2):
	     - Now also asserts default output path is created and runnable when the source path is provided with backslashes (`examples\\myapp.oren` → `build\\targets\\x64-windows\\native\\myapp.exe`).
   - 2026-01-13: `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl` passed (remote WSL2; x64-linux compiler runs and compiles+executes a tiny native program).
   - 2026-01-12: `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` passed (remote Win11 (WSL2 optional); stage2 compiler runs and compiles+runs a tiny native program on both).

7) **GUI: platform shims for Tier‑1 (RGBA blit v0)** (L)

   Keep `std:ui/*` as the portable retained-mode API; bring up thin platform shells.

   Docs:

	   - `docs/GUI.md`, `docs/GUI_PLATFORM_SHIMS.md`
	   - Optional Dear ImGui shell/overlay: `docs/GUI_IMGUI_SHELL.md` (devtools + bring-up accelerator, not the app UI API)
	     - Upstream reference snapshots (verbatim) live under `project-doc/web/github.com/ocornut/imgui/` (do not rely on memory/folklore).
	     - Latest snapshot (fact): `project-doc/web/github.com/ocornut/imgui/20260113/`
	   - Historical pointer: `ui-idea.md` (redirect to the above; avoids stale references)

   Next steps (actionable):

   - finalize `native/orenui/orenui.h` v0 ABI (window + poll_event + present_rgba)
     - Status: `orenui_poll_event` exists on macOS/Windows/Linux shims (v0 events: close + resize + basic input)
   - implement `native/orenui/win32/*` (Win32 + GDI/DIBSection blit) + keep a bounded headful smoke script green
     - Status: `native/orenui/win32/orenui_win32.c` implements v0 window + RGBA blit + poll_event (close/resize + basic input)
     - Added: `scripts/verify_ui_smoke_windows.sh` (`make verify-ui-smoke-windows`)
       - Uses `scripts/win_msvc_cmd.cmd` so it does not require a VS Developer Prompt.
   - implement `native/orenui/x11/*` (X11 + XPutImage blit) + keep a bounded headful smoke script green
     - Status: `native/orenui/x11/orenui_x11.c` implements v0 window + RGBA blit + poll_event (close/resize + basic input)
     - Added: `scripts/verify_ui_smoke_linux.sh` (`make verify-ui-smoke-linux`)
   - keep `examples/ui_hello.oren` portable across shims
     - Status: `examples/ui_hello.oren` uses `std:ui/host` (no per-OS FFI blocks in the example)
     - Next: stabilize key/text input semantics (unified key codes, UTF‑8 text, IME/compose strategy) above the platform raw events.
     - Next: add clipboard + DPI scale plumbing to the shim ABI (still v0-friendly; required for real apps).

8) **FFI ergonomics + ABI surface completion** (M)

   Goal: real-world Win32/libc/OpenSSL bindings are not painful.

   Status (fact):

   - 2026-01-12: added `ffi("lib") { ... }` sugar (lowers to portable `@ffi.link("lib")`), guarded by `scripts/verify_native_x64_compile_only.sh` via `tests/native/ffi_group_link_sugar.oren`.
   - 2026-01-13: `ffi { ... }` now allows multiline items without commas/semicolons (implicit separators between `@attr`/`ident` items), guarded by `scripts/verify_native_x64_compile_only.sh` via `tests/native/ffi_group_multiline_items.oren`.
   - 2026-01-13: accepted `@ffi.ret("ptr")` / `@ffi.ret("usize")` as ABI metadata for pointer-sized returns (Tier‑1 is 64-bit today), guarded by `scripts/verify_native_x64_compile_only.sh` via `tests/native/ffi_ret_ptr_usize.oren`.
   - 2026-01-12: added `@ffi.libc` as a portable “system libc” alias (maps to the correct library name per target OS), so simple libc bindings do not need per‑OS `@cfg` blocks.
     - Guard: `scripts/verify_native_x64_compile_only.sh` via `tests/native/ffi_libc_portable.oren` (stage1 + stage2, x64-linux + x64-windows).

   Next:

   - improve the “import many functions from one library” ergonomics without hiding ABI details:
     - keep `ffi("lib") { ... }` as the canonical grouping form
     - consider a small optional helper for the common “same dll, same calling convention, mostly ptr/usize” cases
   - add a clearer `size_t` story to the manual/spec (when to use `usize`, and how to express ptr-sized ABI returns)
   - consider “quoted external symbol” syntax only if we encounter real APIs that are not identifier-compatible

9) **Native scheduler + netpoller (true async IO + channels/select)** (L)

   Rationale: Oren needs a correct, production-grade concurrency story (green tasks / M:N scheduling)
   before the stdlib NET stack can be fully non-blocking and before `select`/async I/O can be robust.

   Status (fact):

   - 2026-01-12: added `oren_yield()` (best-effort OS yield hint today) backed by syscall-first `sys_sched_yield()`.
     - Linux: `sched_yield(2)` via `linux_sys_sched_yield` lowering in native backends.
     - Windows: `Sleep(0)` via `sys_sched_yield` shim in the x64 native backend.
     - Source of truth: `lib/runtime_native/262_yield.oren`, `docs/CONCURRENCY_MODEL.md`.
   - 2026-01-14: Stage N1 green tasks (N:1) landed and are now the default `spawn` path on macOS/Linux.
     - Runtime: `lib/runtime_native/263_green_tasks.oren` (cooperative scheduler + per-G stack + `sleep` integration).
     - Surface: `spawn f(args...)` routes to `oren_green_spawn(...)` unless `OREN_NO_GREEN=1` is set (fallback is legacy POSIX fork+pipe).
     - Motivation: shared heap/GC/locks in one address space is required before true OS-thread + M:N work can be correct.
   - 2026-01-14: fixed Tier‑1 x64 compile-only NET/TLS/HTTP2 suite breakage caused by numeric `== nil` patterns in `std:net/*`.
     - Rationale: the nil-compare guard is always-on; stdlib must not model “optional int” by comparing numeric scalars to `nil`.
     - Fix: replace numeric `x == nil` checks with `oren_type_tag(x) == 0` defaults in `lib/std/net/*`.
     - Guard: `make verify-native-x64-compile` (stage1 + stage2 emit x64-linux + x64-windows).
   - 2026-01-15: Linux syscall-first OS-thread substrate (clone wrapper + futex join) landed.
     - Compiler: add `sys_thread_create(start_addr, arg_ptr, stack_top, ctid_ptr)` intrinsic lowered to clone(2) with a safe child trampoline
       (child never returns to the caller stack frame).
     - Compiler (arm64-linux): fix Linux futex “wake all” constant emission in `sys_ulock_wake` lowering.
       - Bug: emitted an *undefined* MOVK encoding by passing `shift_idx=16` instead of `shift_idx=1` (ARM64 MOVK shift field is `hw` in {0,1,2,3}).
       - Symptom: `tests/native/test_os_thread_park_unpark_smoke.oren` crashes with SIGILL on linux/arm64.
       - Fix: use `insn_movk(..., 1)` and bump the rtobj backend sig to invalidate stale cached runtime objects.
       - Compiler (x64-linux): fix stack alignment masking in the clone trampoline: `insn_and_r64_imm32` takes an unsigned u32 immediate,
       so the “align down to 16” mask must be `0xFFFFFFF0` (`4294967280`), not `-16` (otherwise child_stack can collapse to 0).
     - Compiler: extend `sys_clone(flags, stack, ptid, ctid, tls)` to the full 5-arg Linux syscall ABI (required for CLONE_*TID).
     - Compiler (arm64-linux): Linux/aarch64 syscall ABI nuance: raw `clone(2)` arg order is `clone(flags, stack, ptid, tls, ctid)`,
       so lowering must pass TLS in X3 and ctid in X4 (different from x64 ordering).
     - Runtime: `lib/runtime_native/266_linux_os_threads.oren` (spawn/join substrate for Stage N2; not wired into language `spawn` yet).
     - Runtime/compiler: `sys_ulock_wait` Linux lowering supports `timeout_us` by passing a relative futex timespec, and normalizes `-ETIMEDOUT` (`-110`) to portable `-60`.
     - Runtime: added a small portable wrapper for the wait-on-address primitive:
       - `lib/runtime_native/267_wait_on_addr.oren` (`oren_wait_on_addr`, `oren_wake_all_addr`)
       - avoids repeating op codes in hot runtime paths and keeps the runtime bundle free of non-zero global initializers
       - semantics: “wait while equal”; if `*addr != expected` (or the kernel reports a mismatch like Linux futex `-EAGAIN`), treat as a spurious wake and return `0`
     - Guards:
       - `tests/native/test_linux_os_thread_smoke.oren` (OS-thread create/join; skips on non-Linux)
       - `tests/native/test_ulock_timeout_linux.oren` (timeout code normalization; skips on non-Linux)
       - `tests/native/test_ulock_timeout_portable.oren` (portable `-60` timeout code; skips if ENOSYS)
       - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_mismatch_is_success`) (prevents park/wait loops from failing on value mismatch)
	   - 2026-01-15: fixed macOS syscall-first OS-thread bring-up when `bsdthread_register` returns `0` on success (feature bits may be 0).
	     - Root cause: runtime treated “success” as `rv > 0` and would fall back to pthread (stubbed in syscall-first builds), causing `oren_os_thread_spawn` to fail.
	     - Fix: treat `rv >= 0` as success and allow the syscall-first `bsdthread_create` path to be used by the shared `oren_os_thread_*` abstraction.
	     - Guards:
	       - `tests/native/test_os_thread_park_unpark_smoke.oren` (arm64-macos + linux + windows)
		   - 2026-01-16: x64 native backend now inserts throttled `oren_gc_safepoint()` polling in `while`/`for` loop headers (every 256 iterations), matching arm64 + C transpiler.
		     - Required for the STW “park at safepoint” protocol to be viable on x64-linux/x64-windows Tier‑1 targets.
		     - Compiler: `lib/compiler/x64_native_program/060_emit_ops.oren` (`_emit_gc_safepoint_throttled_x64`)
				   - 2026-02-14: re-enabled cached poll mode under worker scheduling with P-epoch refresh:
				     - Cached path now tracks per-thread P epoch and refreshes cached `P` bindings across ownership transitions.
				     - Worker-mode cached poll is exercised by `test_green_workers_many_tasks_bounded` when `OREN_GREEN_POLL_CACHE=1` is set.
				     - Runtime: `lib/runtime_native/263_green/020_green_poll.oren`
				   - 2026-02-14: cached green poll auto-disables once workers start (rolling safety):
				     - Prevents stale cached scheduler locals from hanging OS-thread GC join tests under `OREN_GREEN_POLL_CACHE=1`.
				     - Runtime: `lib/runtime_native/263_green/010_green_core.oren` (`_green_poll_cache`)

			   Next steps (actionable, highest leverage first):

					   - Performance (P0): close the Oren native gap on `benchmarks/loop_sum` (M2 baseline ~30.3× C).
					     - Focus on: unboxed int arithmetic + modulo fast paths, loop‑header lowering overhead, and constant‑mod strength reduction.
					     - Guard: keep `benchmarks/loop_sum` results in `benchmarks/results/` and re-run after changes.
					   - Performance (P0): bring Oren C backend loop_sum under 10× C on M2 (currently ~17.7×).
					     - Focus on: avoid OrenValue boxing in tight loops, reduce helper call overhead, and enable constant‑folded modulo where safe.
					   - Performance (P0): capture x64 loop_sum baseline (after constant‑mod inline) on the Linux/Win Tier‑1 path to confirm x64 impact.
					   - Performance (P1): port inty propagation + '+' fast-path to x64 native (needs stringy/inty tracking or another safe guard).
					   - Reliability (P0): investigate reported memory leaks by adding a minimal leak repro + RSS sampling to the benchmark harness, then triage GC/runtime roots.
					     - 2026-02-17: added `benchmarks/alloc_drop` (C/Oren/AVM) with `OREN_BENCH_ITERS` override to make leak/RSS repros deterministic.
					     - 2026-02-17: baseline `alloc_drop` (darwin/arm64, iters=10000, runs=3, `OREN_GC_AUTO=1` for Oren):
					       - C: 0.0056s, RSS ~1.3MB
					       - Oren C: 0.0078s, RSS ~4.7MB
					       - Oren native: 0.339s, RSS ~7.7MB
					       - OBC: 0.0118s, RSS ~9.4MB
   - 2026-02-17: `alloc_drop` (darwin/arm64, iters=20000, runs=1, `OREN_GC_AUTO=1`, OBC skipped):
     - C: 0.0077s, RSS ~1.3MB
     - Oren C: 0.0190s, RSS ~9.9MB
   - 2026-02-18: `alloc_drop` (darwin/arm64, iters=10000, runs=1, `OREN_BENCH_RSS=1`):
     - C: 0.0057s, RSS ~1.3MB
     - Oren C: 0.0073s, RSS ~4.7MB
     - Oren native: 0.2817s, RSS ~7.7MB
     - OBC: 0.0120s, RSS ~9.3MB (`benchmarks/results/alloc_drop_darwin_arm64_20260218_133744.md`)
					       - Oren native: 0.734s, RSS ~13.5MB
					     - 2026-02-17: `alloc_drop` (darwin/arm64, iters=50000, runs=1, `OREN_GC_AUTO=1`, OBC skipped):
					       - C: 0.0087s, RSS ~1.3MB
					       - Oren C: 0.0407s, RSS ~24.8MB
					       - Oren native: 120.6s, RSS ~15.9MB (severe perf regression at higher churn)
					     - Next: increase `OREN_BENCH_ITERS` (50k/200k) and confirm RSS remains bounded under auto-GC; if growth persists, trace roots in native GC/reuse.
					   - Reliability (P0): alloc_churn RSS is still high under `OREN_GC_AUTO=1`; re-run with `OREN_BENCH_RSS=1` on the refreshed baseline and confirm auto-GC triggers.
			   - Windows: upgrade the socket netpoller from select-v0 to IOCP (scalable readiness + true wake; removes `FD_SETSIZE=64` per-call limit and avoids batching).
		       - Design doc: `docs/WINDOWS_IOCP_NETPOLL.md`
		       - Primary reference snapshots (verbatim): `project-doc/web/learn.microsoft.com/iocp/20260117/`
			       - Rolling plumbing landed (2026-01-17):
			         - IOCP syscall/intrinsic + PE import plumbing is present for x64-windows (CreateIoCompletionPort/GetQueuedCompletionStatusEx/PostQueuedCompletionStatus/CancelIoEx).
			         - WinSock overlapped syscall plumbing is present for x64-windows (WSARecv/WSASend) to support completion-based NET ops (treats `WSA_IO_PENDING` as success).
				       - Deliverable v1 (DONE, 2026-01-17): IOCP poll core + wake (still opt-in):
			         - Runtime: `lib/runtime_native/246_netpoll.oren`
			           - `native_netpoll_init_once` creates an IOCP when `OREN_NETPOLL_WIN_IOCP=1`
			           - `native_netpoll_wake()` uses `PostQueuedCompletionStatus` (no loopback dependency)
			           - `native_netpoll_poll_many_scratch` uses `GetQueuedCompletionStatusEx` (allocation-free)
			         - Rolling limitation (updated 2026-02-13): readiness bridge exists but is **gated** behind `OREN_NETPOLL_WIN_IOCP_READY=1`.
			           - Default path (`OREN_NETPOLL_WIN_IOCP=1` only) uses select‑v0 for socket readiness.
		       - Gate (added, 2026-01-17): Windows-only fixture proving a blocked IOCP poll is broken by `native_netpoll_wake()` (no loopback):
		         - Fixture: `tests/fixtures/windows_iocp_wake_smoke.oren` (run with `OREN_NETPOLL_WIN_IOCP=1` and `OREN_NETPOLL_WIN_IOCP_READY=1`)
	         - Wired into: `scripts/verify_native_matrix.sh --targets x64-win-tier1` (remote Win11)
		       - 2026-02-13: IOCP poll core now returns per-operation OVERLAPPED tokens when present (enables readiness/overlapped ops):
         - Runtime: `lib/runtime_native/246_netpoll.oren` (IOCP poll token selection uses `ov!=0` before completion key)
         - Runtime: IOCP wait-node layout (OVERLAPPED + netpoll metadata + bytes slot) and scheduler recognition of IOCP wait tokens.
         - Runtime: scheduler idle/blocking netpoll path also recognizes IOCP wait tokens (no drop on blocking polls).
         - Fixture: `tests/fixtures/windows_iocp_wake_smoke.oren` (posts completion with `ov!=0`, asserts token return, bytes capture)
		       - 2026-02-14: Win11 Tier‑1 matrix now runs green-worker fixtures with `OREN_GREEN_POLL_CACHE=1` to validate cached poll in worker mode.
		       - 2026-02-14: `./scripts/verify_native_matrix.sh --targets x64-win-tier1` passes on pc2.work (IOCP wake + green-worker cached poll fixtures OK).
				   - Windows: extend the wait-list mechanism beyond channels:
				     - 2026-02-13: fd waits (`oren_fd_wait_*`) can park Gs on IOCP wait nodes when IOCP readiness is explicitly enabled (`OREN_NETPOLL_WIN_IOCP_READY=1`).
			   - Follow-up: keep validating cached poll mode under worker scheduling on Tier‑1 (x64-win/x64-linux) before considering a default-on change.
			     - Rolling issue: IOCP readiness remains unreliable on Win11 (UDP `WSAEFAULT`, TCP header timeouts); default path uses select‑v0.
			     - Next: unify “wait node” metadata so channels + IO readiness share the same scheduler integration surface
			     - 2026-02-13: added shared wait-node init/reset helpers and used them in select/netpoll paths:
			       - Runtime: `lib/runtime_native/246_netpoll.oren` (`native_netpoll_wait_init`, `native_netpoll_wait_reset`)
			       - Runtime: `lib/runtime_native/245_select.oren` (select wait nodes now use the shared helpers)
			     - 2026-02-14: IOCP fd waits now use the shared IOCP wait-node init helper:
			       - Runtime: `lib/runtime_native/240_tcp.oren` (`oren_fd_wait_readable` / `oren_fd_wait_writable`)
		   - Cross-platform: evolve the scheduler-owned “word wait” wait-list so in-green waits never kernel-block the scheduler OS thread.
		     - DONE (2026-01-17): `oren_wait_on_addr` inside a green task is wake-driven via the scheduler-owned “word wait” list:
		       - `timeout_us==0` (“forever”): parks `G` on a scheduler list; wakes via `oren_wake_all_addr`.
		         - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_in_green_does_not_block_scheduler`)
		       - `timeout_us>0` (bounded): parks on the same list with a deadline; returns portable timeout `-60`.
		         - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_timeout_in_green_does_not_block_scheduler`)

	   - Stage N2 groundwork: syscall-first OS threads (no libpthread) on Tier‑1
     - macOS arm64: finish the syscall-first `bsdthread_register` story and keep it robust across modern dyld/libpthread:
       - keep installing runtime-owned threadstart stubs at process init (call `native_runtime_threading_init(...)` early)
       - keep `sys_bsdthread_create/terminate` wired to the shared runtime `oren_os_thread_spawn(...)` primitive (`lib/runtime_native/269_os_thread_m.oren`)
       - reduce/eliminate the pthread fallback by making syscall-first threadstart work even when the process is already registered by libpthread (kernel may return `-EINVAL` / already-registered; requires deeper ABI alignment work)
     - Linux x64/arm64: extend the syscall-first OS-thread substrate toward production:
       - add TLS story (`CLONE_SETTLS`) once runtime uses/needs a real thread pointer
       - unify the Linux `M` abstraction with Windows/Darwin (shared scheduler-facing shape)
       - keep join bounded: `tests/native/test_linux_os_thread_smoke.oren` uses a futex wait timeout and re-checks `ctid_ptr` after timeout (avoids false negatives if a wake is missed)
		     - DONE (2026-01-17): Windows x64: language `spawn` now prefers green tasks (N:1) like POSIX; OS-thread fallback when `OREN_NO_GREEN=1` routes through `oren_os_thread_spawn` (M abstraction).
		       - Gate (added, 2026-01-17): remote Win11 Tier‑1 now also runs with `OREN_NO_GREEN=1` to keep the OS-thread `spawn` fallback from rotting (join timeout + STW-safe detach behavior).
		       - Gate (added, 2026-01-17): remote WSL2 Tier‑1 now also runs with `OREN_NO_GREEN=1` to keep the POSIX fork+pipe fallback from rotting.
		   - 2026-01-15: introduced a minimal runtime-owned OS-thread ("M") abstraction (macOS + Linux + Windows) for future M:N work:
		     - Runtime: `lib/runtime_native/269_os_thread_m.oren`
		       - `oren_os_thread_spawn(start_addr, arg_ptr)`
		       - `oren_os_thread_join_timeout(handle, timeout_us)` (portable timeout `-60`)
		       - `oren_m_park_word_wait` / `oren_m_park_word_wake` (futex/WaitOnAddress token-based park/unpark)
		     - Guard: `tests/native/test_os_thread_park_unpark_smoke.oren` (macOS + Linux + Windows)
		     - Guard: `tests/native/test_os_thread_spawn_many_smoke.oren` (macOS + Linux + Windows; bounded join timeout)
	   - 2026-01-16: fixed Tier‑1 Windows bring-up regressions in the OS-thread substrate and TIME monotonic path:
		       - Root cause: `native_call1(addr, arg0)` was incorrectly short-circuited as a generic `native_*` call on x64,
		         executing the prelude stub body (returns 0) instead of doing an indirect call; this broke `oren_os_thread_spawn`
		         on Windows and made STW GC join-waiter tests hang/flake.
		       - Fix: keep `native_call1` routed through the x64 intrinsic emitter (ABI-aware arg-register mapping), and bump the
		         x64 rtobj backend signature (`x64_v0_17`) to invalidate stale cached runtime objects.
		       - Fix: treat `sys_qpc_frequency` as a syscall intrinsic and write the QueryPerformanceFrequency result directly to
			         `*freq_ptr` (avoid fixed stack scratch slots).
		         - Verified: `./scripts/verify_native_matrix.sh --targets x64-win --trace` (stage1 + stage2) on remote Win11.
		   - 2026-01-17: keep cross-target x64 builds robust when the injected runtime contains Windows-only branches guarded by `g_target_os`:
		     - x64 non-Windows syscall lowering now treats `sys_qpc_frequency` as `-ENOSYS` (instead of a hard compile-time error).
		     - Verified: `make verify-x64-linux-qemu` (stage1 + stage2).
		   - 2026-01-17: green-task safety: `oren_wait_on_addr` inside green tasks must not block the scheduler OS thread:
		     - Runtime: `lib/runtime_native/267_wait_on_addr.oren` + `lib/runtime_native/263_green/*.oren`
		       - parks the current `G` on a scheduler-owned “word wait” list (wake-driven; no polling)
		       - woken via `oren_wake_all_addr(addr)` (hooks into green wake best-effort)
		       - bounded timeouts use scheduler deadlines and return portable `-60`
		       - scheduler lock acquire uses a no-alloc “in-green” probe to avoid recursion with the runtime global lock wake path
		     - Guards:
		       - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_in_green_does_not_block_scheduler`)
		       - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_timeout_in_green_does_not_block_scheduler`)
		   - 2026-01-17: STW GC + netpoll integration (worker-mode efficiency without GC deadlocks):
		     - Runtime STW begin/end now call `native_netpoll_wake()` so OS threads blocked in kevent/epoll/select are broken out immediately and can park at safepoints.
		     - Green worker-mode idle netpoll waits can block up to 1s when the backend has a working wake mechanism; otherwise they fall back to a short bound (Windows capsule/no-wake correctness-first).
		     - Windows select-v0 netpoll: watch-table updates now wake a blocked poller when the wake socket exists, so longer select timeouts are possible without missing new registrations.
		     - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_stw_wakes_netpoll_blocked_threads`)
		     - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_stw_os_thread_collect_scans_parked_stack`)
		   - 2026-01-16: Windows channel/select groundwork (portable in-memory channels):
	     - Runtime: `lib/runtime_native/011_channels_mem.oren` (GC-tracked ring-buffer channels + wait-on-addr)
	     - Runtime: `lib/runtime_native/245_select.oren` (Windows: `oren_select` / `oren_select_recv` over mem-channels)
	     - Tests: enable select primitives on Windows:
	       - `tests/native/test_quick_integration_native.oren` (`test_select` no longer skips Windows)
	       - `tests/native/test_integration_suite.oren` (`test_select_primitives` no longer skips Windows)
		     - Notes:
		       - Pipe-fd readiness is still POSIX-only; Windows has a rolling select-v0 socket netpoller, but IOCP is still needed for a production-grade netpoller (scalability + wake).
			       - In-green `oren_select` / channel ops on Windows are **green-safe** and **non-polling**:
			         - green tasks park on per-channel wait lists and on the shared global select sequence word via `oren_wait_on_addr`
			         - send/recv wakes parked Gs by bumping the global seq word (no 1ms polling loop; enables idle-worker parking)
			         - select waiters are rooted by the scheduler-owned word-wait list (so parked `G`s remain GC-reachable even if callers drop handles)
			         - per-channel mem-channel locks (`_chan_mem_lock`) use the same green-aware `oren_wait_on_addr` path under contention (no `oren_green_sleep_ns` polling)
			         - Guards (Windows-enabled): `tests/native/test_quick_integration_native.oren`
			           - `test_select_in_green_workers`, `test_select_multi_case_in_green_workers`, `test_select_idle_does_not_spin_cpu`
				   - 2026-01-16: Windows socket netpoll v0 (readiness waits are green-safe):
				     - Runtime: `lib/runtime_native/246_netpoll.oren` (WinSock `select()`; `FD_SETSIZE=64` per-call; watch table batched beyond 64; best-effort wake socket when loopback is allowed)
				     - Runtime: `lib/runtime_native/263_green_tasks.oren` (scheduler drains tokens and wakes parked Gs)
				     - Runtime: `lib/runtime_native/240_tcp.oren` (`oren_fd_wait_*` call into netpoll when in-green)
				     - Guard: `tests/native/test_net_suite.oren` (`test_fd_wait_socket_readable_in_green_workers`)
				     - Rolling safety: watch-table lock contention is green-safe (never kernel-blocks the scheduler OS thread):
				       - Runtime: `lib/runtime_native/246_netpoll.oren` (`_netpoll_watch_lock_acquire` uses `oren_wait_on_addr`)
				   - 2026-01-15 → 2026-01-16: Stage N2 groundwork: green-task scheduler can now run on background OS threads ("M") via `oren_green_start_workers(n)`.
			     - Runtime: `lib/runtime_native/263_green_tasks.oren`
			       - per-OS-thread scheduler state (scheduler ctx + current-G are no longer globals)
			       - Stage N2 groundwork: `P` struct + per-P runq/sleepq (single-P by default), plus a thread-local **current P** pointer
			       - scheduler now has a **global run queue** for cross-P injection / fairness (spawns from outside green context)
		       - per-P local runq is now a **GC-visible ring buffer / work-stealing deque** (head+tail+mask), with overflow to the global runq
			       - Stage N3 plumbing: `P` topology is now configurable (before workers start) and sleepers are woken across all Ps:
			         - `oren_green_set_p_count(n)` grows scheduler Ps (no shrink; rejected once workers started)
			         - `oren_green_p_count()` reports the current P count
			         - `oren_green_bind_p(p_id)` binds the current OS thread to a specific P (bring-up/testing; rejected in-green and once workers started)
			         - `oren_green_current_p_id()` reports the current OS thread’s bound P id
			         - `oren_green_acquire_p(p_id)` / `oren_green_release_p()` allow host-thread P ownership bring-up (rejected in-green and once workers started)
			         - scheduler wake/next-deadline logic scans sleepers across all Ps (future-proof for `M < P`)
			       - worker idle sleeps now park on the shared park word with a timeout (so new runnable work wakes it immediately); inserting sleepers wakes workers to re-evaluate the next deadline
			       - worker entry accepts an optional `P*` argument and claims `P.owner_tid` (rolling: hard fail if a P is accidentally shared across Ms)
			       - `_green_poll_until` enforces `P.owner_tid == sys_gettid()` in worker mode; `oren_green_start_workers` reserves each worker `P` with a negative sentinel and the worker claims its bound `P` to a positive tid before running the scheduler loop
			         - Rolling safety: `oren_green_start_workers` rejects if any `P.owner_tid != 0` on entry (prevents subtle “worker aborts because P was already claimed” failures)
			         - Stage N3 evolution: `oren_green_start_workers(n)` reserves only the first `n` Ps; extra Ps must remain free (`owner_tid==0`) for future `M < P` operation.
			       - scheduler now uses a **dedicated scheduler lock** (wait-on-addr based) instead of the runtime global lock (reduces coupling to allocator/GC metadata)
			         - Invariant: requires `sys_gettid()` to be non-zero when workers are enabled (0 is reserved as the “unlocked” sentinel).
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join`)
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_bind_p_rejects_in_green`) (topology mutation must be host-thread only)
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_acquire_p_rejects_in_green`) (P ownership mutation must be host-thread only)
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_p_acquire_release_blocks_start_workers`) (start_workers must fail early if any P is already claimed by a host thread)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_release_acquire_p_when_parked`) (worker releases P while parked/blocked and re-acquires to run)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_start_workers_does_not_reserve_extra_ps`) (start_workers(1) must not reserve P1/P2; required for M<P)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_green_worker_idle`) (STW GC must not deadlock when a worker is parked or blocked in netpoll)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_green_join_waiter`) (STW GC must not deadlock while an OS thread is blocked in `join(..., -1)` under worker-mode green scheduling)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_os_thread_join_waiter`) (STW GC must not deadlock while an OS thread is blocked in `oren_os_thread_join_timeout(..., timeout_us=0)`)
						     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_p_count_api`) (P topology API; no shrink; reject after workers)
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_multi_p_single_thread_poll_steal`) (single-thread multi-P steal + cross-P wake without unsafe parallel workers)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_ctx_switch_alloc_integrity`) (worker-mode ctx-switch + scheduler stability)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_local_ptr_survives_yields`) (ctx-switch must preserve long-lived locals across yields)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_local_ptr_survives_yields`) (same contract under worker-mode scheduling)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_wake_while_sleepers`) (prevents “sleepers stall runnable work” regressions)
					     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_global_runq_fairness`) (prevents global-runq starvation regressions)
					     - Guard: `tests/native/test_green_two_workers_world_lock_smoke.oren` (safe multi-worker via world lock; allocator/GC not parallel yet)
					     - Rolling limitation: worker parallelism is clamped to 1 by default until the native allocator/GC are concurrency-correct; opt-in for experimentation only via `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`.
		   - Parking/unparking primitive for idle `M` (required to avoid spin):
		     - macOS: ulock-based park/wake for `P` (pairs with `sys_ulock_wait/sys_ulock_wake`)
		     - Linux: futex-based park/wake
			   - Stage N3 (next): make `P` real (toward true M:N)
				     - enforce “an `M` runs Oren code only while holding a `P`” (no shared-P execution)
				     - DONE (initial, under scheduler lock): idle-`P` pool + acquire/release plumbing (so `owner_tid==0` Ps are tracked explicitly, not via full P-list scans)
				       - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_idle_p_pool_acquire_any`)
				       - Progress (2026-01-16): worker idle/blocked paths now clear the thread-local P binding while parked, and on wake attempt to acquire **any** idle P before running Oren code (still under scheduler lock).
				       - Progress (2026-01-16): `oren_green_start_workers` now publishes worker-mode state before spawning threads and exposes a worker-ready counter (debug) to stabilize fixtures.
				       - Progress (2026-01-16): idle-P pool is now FIFO (fair) and has a multi-worker guard that proves `P2` can be acquired under `M<P` in world-lock mode:
				         - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` (wired into native quick integration runner; deterministic P swap + P2 acquisition)
				         - NOTE (required): in worker mode, `_green_poll_until` must not auto-bind `P0` when a worker intentionally clears its thread-local P binding; P acquisition must happen via the idle-P pool for M<P/fairness.
					       - DONE (2026-01-16): deterministic combined regression (2 workers, 3 Ps) that proves:
					         - worker1 acquires P0, worker0 acquires P1, and later worker0 acquires P2 (true `M<P` behavior under world-lock)
					         - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren`
					         - Implementation: per-worker park/wake slots + worker-tid table + test-only idle-P requeue + test-only spawn-to-P injection (keeps fixture deterministic).
					       - 2026-01-17: hardened multi-worker green scheduler fixtures so they run across Tier‑1 (including Windows) without relying on language `spawn` semantics:
					         - `tests/native/test_green_two_workers_world_lock_smoke.oren` now spawns work via `oren_green_spawn(...)` (so it covers Windows too).
					         - `tests/native/test_green_two_workers_p_swap_smoke.oren` and `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` now assert ownership by observing `P.owner_tid` (via `oren_green_debug_p_owner_tid`) with monotonic-time spin waits (avoids flakes from coarse sleep timers and from global “last acquire” debug markers being overwritten).
					         - `tests/native/test_green_two_workers_m_less_p_smoke.oren` now uses a durable “seen P ids” bitmask (`oren_green_debug_p_acquire_seen_mask`) to detect that `P2` was acquired (not a fragile “last acquire wins” check).
					         - 2026-01-17: fixed Tier‑1 Linux (WSL2) `join_timeout` contract under green-task `spawn` by making TIME sleep green-aware:
					           - Root cause: `spawn` is green-task-based on Linux; `oren_sleep_ms` previously blocked the scheduler OS thread in `sys_nanosleep`, so `oren_join_timeout` could not time out while the task “slept”.
					           - Fix: `oren_sleep_ns` now routes to `oren_green_sleep_ns` when called from inside a green task (`lib/runtime_native/100_time_core.oren`).
					           - Verified: `make test` (arm64-macos) + `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1 --trace` (remote Win11 + remote WSL2; stage1+stage2).
					         - 2026-01-17: Tier‑1 matrix now also runs the green-worker fixture set by default (when using the default Tier‑1 source):
					           - Implemented in: `scripts/verify_native_matrix.sh` (`x64-win-tier1`, `x64-wsl-tier1`).
						       - DONE (2026-01-16): documented the fixture-only `oren_green_debug_*` surface in one place (what is “test-only ABI” vs stable runtime ABI):
						         - Doc: `docs/NATIVE_GMP_SCHEDULER.md` (“Test-only debug API: `oren_green_debug_*`”)
				     - DONE (2026-01-17): single-thread multi-`P` steal + cross-`P` wake fixture exists (no unsafe parallel workers):
				       - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_multi_p_single_thread_poll_steal`)
				     - evolve the global runq into a fairness/overflow queue (it exists today as cross-P injection)
				     - implement real work stealing between `P` (today: a global-lock bring-up: “steal one before idle”, plus periodic global-runq polling for fairness)
		     - replace the current global lock in green scheduling with per-P queues + atomics (keep GC/STW correctness first)
				     - define and enforce a context-switch preservation contract (native `oren_ctx_switch` + codegen):
				       - today, the scheduler re-fetches per-thread state (`ts`/`P`) each poll iteration for robustness; fix the root cause so we can rely on normal locals again
				       - 2026-01-16: arm64 native backend now addresses locals FP-relative (X29) instead of SP-relative:
				         - reduces long-lived-local aliasing hazards when SP moves for temporaries/ABI call frames
				         - compiler: `lib/compiler/arm64_core.oren`, `lib/compiler/arm64_native_stmt.oren`, `lib/compiler/arm64_native_expr/010_lowering_a.oren`
				         - verified: `make test`
				       - 2026-01-16: native backends upgraded `oren_ctx_switch` to preserve a fuller machine state (fixes “locals corrupted across yield” failure modes):
				         - arm64: saves/restores `x0..x26` + `x29/x30` + `SP/PC` and `Q0..Q31`, while skipping the heap bump regs (`X27/X28`)
				         - x64: saves/restores GPRs + `RSP/RIP` and `XMM0..XMM15`, while skipping the heap bump regs (`R14/R15`)
				         - runtime: green context blobs now allocate one page (`green_ctx_bytes() == 4096`) to keep mmap/munmap semantics unambiguous and leave headroom
					       - 2026-01-17: regression guard for cached poll locals (would have caught “P pointer becomes a small integer after ctx switch”):
					         - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_poll_cache_does_not_corrupt_p_ptr`) (runs only when `OREN_GREEN_POLL_CACHE=1`)
				       - concrete failure mode seen in worker-mode: `P` can collapse to a small integer (e.g. `2`) and crash in `_green_p_owner_tid`; keep the per-iteration re-fetch until cached mode is proven safe under a dedicated guard
				       - 2026-01-16: added a small compiler guard to reduce “dead code perturbs stack accounting” hazards:
				         - arm64 stmt codegen now stops emitting statements after a non-fallthrough terminator in a `Block`:
				           - direct `break`/`continue`/`return`
				           - `if { ... } else { ... }` where both branches terminate
				           - compiler: `lib/compiler/arm64_native_stmt.oren` (`native_compile_stmt` returns `false` for “no fallthrough”)
				         - status: default `_green_poll_until` still re-fetches `ts`/`P` each iteration; an env-gated cached mode now exists and is regression-guarded (keep cached mode opt-in until we decide to flip the default)
						       - 2026-01-16: arm64 stmt codegen now also restores SP after condition evaluation in `if` / `while` / `for` headers (so branch entry SP matches codegen assumptions):
						         - compiler: `lib/compiler/arm64_native_stmt.oren` (`cond_delta` restore)
							       - 2026-01-16: regression guard: native quick integration now also runs with `OREN_GREEN_POLL_CACHE=1` (so cached scheduling locals must remain stable across yields)
							       - 2026-01-16: fixed an arm64 native codegen correctness bug where some expression statements could “pop too much stack” (delta < 0) and cause later locals to overlap earlier locals.
							         - Fix: statement-level stack restore now handles both delta>0 and delta<0 (`_arm64_restore_stack_to`).
							         - Compiler: `lib/compiler/arm64_native_stmt.oren`
							         - Guard: `make test` + `tests/native/test_quick_integration_native.oren` (`test_select_idle_does_not_spin_cpu`)
							       - 2026-01-16: fixed a worker-mode join/cleanup race that could flake as SIGSEGV (rc=139), especially under `OREN_GREEN_POLL_CACHE=1` stress:
							         - Root cause: joiners waiting on the `G.state` word can wake via ulock/futex mismatch and observe DONE before an explicit wake,
							           then call `_green_cleanup_g(g)` and `munmap` the green stack while the task is still executing on it.
						         - Fix: introduce an internal EXITING state so tasks switch back to the scheduler before DONE is published; scheduler finalizes DONE and wakes joiners.
						         - Runtime: `lib/runtime_native/263_green_tasks.oren` (`__oren_green_entry`, `_green_poll_until_budget`)
					     - 2026-01-16: switched green sleeper deadlines to a monotonic clock source (avoid wall-clock jumps affecting wake behavior):
					       - Runtime: `lib/runtime_native/100_time.oren` (`oren_time_mono_ns`)
					       - Runtime: `lib/runtime_native/263_green_tasks.oren` (`_green_time_now_ns` + scheduler uses it for wake/deadlines)
					       - Compiler (Linux x64/arm64): `sys_gettimeofday(..., abs_ptr)` now fills abs_ptr with `clock_gettime(CLOCK_MONOTONIC)` in ns
					         (so `oren_time_mono_raw()` works on Linux too)
					         - 2026-01-16: fix x64-linux lowering bug where the `timespec` scratch overlapped the spilled `abs_ptr` slot (clobbered with `tv_nsec` and could crash).
					           - Guard: `make verify-x64-linux-qemu` (stage1 + stage2), plus `tests/native/test_time_mono_raw.oren`.
				   - 2026-01-16: added a bounded regression gate for worker-mode scheduling (many tasks must complete; no hangs):
				       - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_many_tasks_bounded`)
							     - 2026-01-16: made native waits green-aware so they never block the scheduler OS thread when called from a green task:
							       - Runtime: `lib/runtime_native/246_netpoll.oren` (POSIX netpoller: kqueue/epoll + wake pipe)
							       - Runtime: `lib/runtime_native/263_green_tasks.oren` (scheduler drains netpoll tokens and can idle in kevent/epoll)
							       - Runtime: `lib/runtime_native/240_tcp.oren` (`oren_fd_wait_*`: parks the G on netpoll instead of poll+sleep)
								       - Runtime: `lib/runtime_native/245_select.oren` (`oren_select` / `oren_select_recv`: in-green uses **netpoll v2** case tokens; preserves deterministic selection without per-wake probe polling)
								       - Guards:
								         - `tests/native/test_net_suite.oren` (`test_fd_wait_readable_in_green_workers`)
								         - `tests/native/test_quick_integration_native.oren` (`test_select_in_green_workers`, `test_select_multi_case_in_green_workers`)
								       - 2026-01-16: `oren_select` now rejects duplicate case fds (`-EINVAL`) to keep behavior deterministic across the legacy per-call select path and netpoll v2.
								       - 2026-01-16: regression guard added: `tests/native/test_quick_integration_native.oren` (`test_select_idle_does_not_spin_cpu`) (bounds scheduler idle-loop iterations while a select blocks).
								       - Runtime: `lib/runtime_native/246_netpoll.oren` (`native_netpoll_poll_many_scratch` preserves full ready-sets; scheduler does not drop additional ready tokens)
								       - Follow-ups (still valuable):
								         - add a perf/behavior regression: “select blocks indefinitely with near-zero CPU while other green tasks keep running” (now guarded in quick integration via idle-iteration bound; CPU-time API measurement still TODO)
								     - 2026-01-16: strengthened multi-P work-stealing regression:
								       - Runtime: stealing now chooses the most-loaded victim P (under the scheduler lock) and records debug counters.
								       - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_multi_p_single_thread_poll_steal`) now asserts `steal_count > 0` and last victim is P2.
						     - 2026-01-16: fixed loopback NET fixtures that spawn in-process servers on POSIX:
						       - Problem: `spawn` prefers green tasks, but some fixtures ran a blocking client call on the main thread, starving the server green task (timeout).
						       - Fix: enable green worker mode up front in the spawned-server fixtures (unless `OREN_NO_GREEN` disables green tasks).
						       - Guards: `make verify-x64-linux-qemu-net` (covers `tests/native/test_dns_loopback.oren`, `tests/native/test_http_get_loopback.oren`, `tests/native/test_ws_echo_loopback.oren`)
						     - 2026-02-13: x64-windows TLS fixtures crashed when TLS ran on a green stack (access violation):
						       - Affects: `https_loopback`, `wss_loopback`, `http2_*` loopback tests on Win11 when green tasks were enabled.
						       - Probe: `OREN_GREEN_STACK_KB` up to 16384 (16 MiB) still crashed (`EXIT=-1073741819`), so this was not a small-stack overflow.
						       - 2026-02-14: adjusted x64 green stack entry alignment so `rsp+8` is 16-byte aligned (ctx_switch resumes via `ret`);
						         added a green-stack alignment regression (`test_green_sp_alignment_x64`).
						       - 2026-02-14: Windows TLS loopback fixtures now default to **green tasks** on Win11.
						         - Fallback: set `OREN_TLS_USE_OS_THREAD=1` to force OS-thread spawn.
						         - Verified: `./scripts/verify_native_net_matrix.sh --targets x64-win` (pc2.work, green default; TLS/HTTPS/WSS/HTTP2 all OK).
					     - 2026-01-16: made `oren_time_mono_ns()` conversion exact on macOS/Windows (no wall-clock calibration):
					       - macOS: uses `mach_timebase_info` (num/den) to convert gettimeofday’s `mach_absolute_time` out-arg to ns.
					       - Windows: uses `QueryPerformanceFrequency` for QPC ticks -> ns (backend exposes `sys_qpc_frequency`).
			     - 2026-01-16: fixed a Linux arm64 worker-mode green scheduler corruption + hang:
			       - Symptom (arm64-linux, Ubuntu container): `test_quick_integration_native.oren` panicked in `worker_green_alloc_yield_integrity` (`list_push on non-list`) and the binary could hang under worker threads.
			       - Root causes:
			         - Linux `sys_thread_create` clone trampoline did not reinitialize the native bump allocator registers in the child OS thread, so the child could inherit parent heap state and corrupt allocations under worker-mode scheduling.
			         - arm64 `exit(...)` intrinsic routed to `sys_exit` (thread-only), so after starting background workers `exit(0)` could leave the process alive and appear “hung”.
			       - Fix:
			         - reset heap regs in the clone child path (arm64: X27/X28; x64: R14/R15) before calling the thread entry function
			         - route arm64 `exit(...)` to Linux `exit_group(2)` via a new `sys_exit_group` syscall-lowering hook
			       - Guards: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join` + `test_green_global_runq_fairness` + `test_green_ctx_switch_alloc_integrity`) now run to completion on `arm64-linux`.
	     - Optional dev-only smoke (skipped by default): `tests/native/test_green_workers_multi_p_experimental.oren`
		   - 2026-01-15: GC + safepoint groundwork for N:M (stop-the-world first, correct before fast)
		     - Implemented a minimal STW protocol so `oren_gc_collect()` is safe once >1 OS thread exists:
		       - Runtime: `lib/runtime_native/100_time.oren` (`native_gc_stw_begin/native_gc_stw_poll_and_park/native_gc_stw_end`)
		       - Globals storage (wait-on-address words): `424/432/440` (see `lib/runtime_native/010_channels_globals_consts.oren`)
		     - Guard: `tests/native/test_gc_stw_os_thread_collect.oren`
		     - Remaining (still required before real N:M):
		       - extend safepoints beyond loop headers (bounded time for long-running non-loop code paths); there is no preemption yet
		       - define the "GC safe" calling convention wrt registers vs stack (roots must be discoverable at safepoints)
		       - evolve toward per-P allocation caches + a concurrency-correct allocator/metadata model (or keep STW around allocations initially)
			     - 2026-01-16: extended bounded safepoint reachability beyond loops by piggybacking on native call-depth hooks:
			       - Runtime: `lib/runtime_native/105_call_depth.oren` (`native_call_depth_safepoint_poll_throttled`)
			       - Behavior: in multi-OS-thread mode, every ~1024 function entries polls STW state and parks if requested.
			       - Motivation: call-heavy non-loop code paths (visitors/recursion) should not starve a stop-the-world request indefinitely.
				   - 2026-01-16: fixed an STW deadlock hazard after OS threads exit:
				       - Problem: thread nodes are mmap-backed metadata; without an explicit “dead” marker, STW could wait forever on threads that have already exited.
				       - Fix: OS-thread start stubs now mark their thread node as DEAD on exit, and STW counts only live (non-DEAD) OS-thread nodes when waiting.
				       - Runtime: `lib/runtime_native/100_time_core.oren` (`native_time_mark_thread_dead_current`), `lib/runtime_native/100_time_gc_stw.oren` (`native_gc_stw_expected_parked_count`)
				       - Guards: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_green_join_waiter`, `test_gc_collect_does_not_deadlock_with_os_thread_join_waiter`)
					       - 2026-01-16: ensured Windows OS-thread paths mark OS-thread nodes DEAD on thread exit (prevents STW regressions after many short-lived threads):
					         - Runtime: `lib/runtime_native/269_os_thread_m.oren` (`__oren_os_thread_entry_raw`), `lib/runtime_native/120_first_class_fn.oren` (`__oren_win_spawn_thread_entry` for `OREN_NO_GREEN=1` fallback)
					         - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_wait_for_exited_os_threads_win`) (bounded; fails with timeout instead of hanging)
					       - 2026-01-16: routed x64-windows language `spawn` lowering through the native runtime helper (`oren_spawn_call_list`) so the runtime owns CreateThread plumbing:
					         - Compiler: `lib/compiler/x64_native_program/044_emit_call_expr.oren` (`_emit_spawn_expr_v0`)
					         - Runtime: `lib/runtime_native/120_first_class_fn.oren` (`_oren_spawn_call_list_windows_thread`)
					         - Thread substrate: Windows now routes the thread create through the shared OS-thread ("M") abstraction:
					           - Runtime: `lib/runtime_native/269_os_thread_m.oren` (`oren_os_thread_spawn`, `oren_os_thread_destroy`)
					         - Motivation: keep OS-specific details out of codegen (reduces per-backend divergence; simplifies future N:M unification).
					       - 2026-01-16: made Windows `oren_join_timeout(timeout_ms>0)` STW-safe (polls `oren_gc_safepoint()` while waiting):
					         - Runtime: `lib/runtime_native/260_threads.oren` (`oren_join_timeout_win`)
					       - 2026-01-17: made POSIX fork+pipe join + syscall-first proc waits STW-safe (no infinite kernel blocks on host threads):
					         - Runtime: `lib/runtime_native/260_threads.oren`
					           - POSIX `oren_join/oren_join_timeout` uses `oren_is_done` + `wait4(WNOHANG)` under `oren_gc_safepoint()` (blocking joins are poll-based, timeout joins enforce timeout semantics without kernel-blocking).
					           - `oren_proc_spawn(timeout_ms<0)` is now poll-based (`wait4(WNOHANG)` + sleep) so STW collectors cannot deadlock on a forever wait.
				     - 2026-01-16: fixed a native GC correctness gap: STRUCT allocations are now conservatively scanned, and the mark phase is cycle-safe:
				       - Problem: many runtime subsystems tag allocations as kind=STRUCT “so GC can scan fields”, but the mark phase previously did not traverse kind=STRUCT.
				       - Fix: `oren_mark_value` now scans 8-byte slots for kind=STRUCT, and honors the mark bit to avoid infinite recursion on cyclic graphs.
				       - Runtime: `lib/runtime_native/100_time_gc_alloc.oren` (`oren_mark_value`)

		   References:

   - `docs/CONCURRENCY_MODEL.md`
   - `docs/NATIVE_GMP_SCHEDULER.md`
   - `docs/ASYNC_IO_AND_SELECT.md`

## P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)

   References:

   - `docs/APPSTORE_ROOTCA_AND_UPDATES.md`
   - `docs/CERT_CHAIN_FORMAT.md`

2) **Stackless recursion beyond TCO (heap call frames)** (L)

   Reference:

	   - `docs/STACK_SAFETY.md`

3) **Compiler-in-AVM + plugin packaging (iOS-safe, OBC-first)** (M)

   Goal:

   - ship `libavm` + `oren.obc` + a stdlib strategy so:
     - “source → `.obc`” can run inside a sandbox universe (VirtualFS, deterministic TIME/RNG, budgets)
     - untrusted tools/plugins can run as child universes (“Matrix sandbox”) without host FS/PROC/NET

   References:

   - `docs/AVM_MULTIVERSE.md` (compiler-in-AVM section)
   - `docs/OBC_MODULE_LINKING.md` (OBX v0 for compile-time linking)
   - `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` (stdlib distribution models)
   - `docs/AVM_PLUGINS_AND_NESTING.md` (plugin model A vs B; tracker split)

	   Status (fact):

	   - 2026-01-16: added a practical local smoke + build helper for OBC-first workflows:
	     - Build stdlib bundle `.obc` (OBX exports): `scripts/build_avm_plugins.sh` → `build/plugins/stdlib_bundle.obc`
	       - Default root: `lib/std/stdlib_avm.oren` (override via `OREN_STDLIB_BUNDLE_ROOT=...`)
	     - Verify OBX linking + AVM execution end-to-end: `scripts/verify_avm_bytecode_link_smoke.sh`
	       (builds `tests/fixtures/avm_obc_link_smoke.oren` with `--stdlib-mode obc` and runs it via `./avm`)
		  - 2026-01-16: fixed OBX linking correctness for `--stdlib-mode obc`:
		    - Linker now strips a trailing `HALT` from non-final modules during concatenation (prevents early termination of the pc=0 skip chain).
		    - OBX exports now encode **0-based** code addresses (compiler internals store 1-based addresses; exports must decode to `enc-1`).
		    - Added AVM core natives required by the minimal stdlib bundle: `oren_type_tag`, `oren_map_get_str`, `oren_map_set_str`.
		    - Guard: `scripts/verify_avm_bytecode_link_smoke.sh`

4) **Ergonomic debug logging helpers (compile‑out in release)** (S)

   Goal:

   - Provide a `dbg(...)`/`dprint(...)`-style helper that:
     - is **zero-cost** in release builds (compiled out)
     - captures file/line by default (compiler-supplied or metadata-based)
     - keeps the surface deterministic and capsule-safe
   - Keep `@debug`/`@release` as the low-level primitive (already implemented).

   References:

   - `docs/ATTRIBUTES.md` (conditional compilation + shorthand)

   Status (fact):

   - 2026-02-13: implemented `dbg(...)` statement sugar (expands to `@debug print(...)` with file/line prefix)
     - Pass: `lib/compiler/debug_sugar.oren`
     - Evidence: `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)
   - 2026-02-13: implemented `dprint(...)` statement sugar (expands to `@debug print(...)` with no prefix)
     - Pass: `lib/compiler/debug_sugar.oren`
     - Evidence: `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)
   - 2026-02-13: added `debug { ... }` / `release { ... }` block sugar (parses to `@debug` / `@release`)
     - Parser: `lib/compiler/parser_parse/000_prelude.oren`
     - Evidence: `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)
   - 2026-02-14: added single‑arg expression sugar for `dbg(expr)` / `dprint(expr)` (returns value; prints only in debug builds)
     - Pass: `lib/compiler/debug_sugar.oren`
     - Evidence: `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)

5) **Split oversized quick integration fixture (maintenance)** (S)

   Goal:

   - Keep `tests/native/test_quick_integration_native.oren` under ~2k LOC by extracting
     self-contained groups into include aggregators (or small helper modules) without changing semantics.
   - Preserve the single-entry smoke semantics while making it easier to add/remove high-signal checks.

   Rationale:

   - The fixture is now >2k LOC and touches many surfaces; refactoring into logical chunks will reduce
     maintenance risk while keeping the Tier‑1 gate signal.

   Status (fact):

   - 2026-02-13: split `tests/native/test_quick_integration_native.oren` into include segments:
     - `tests/native/qi/000_prelude.oren`
     - `tests/native/qi/100_tests_basic.oren`
     - `tests/native/qi/200_tests_wait_gc.oren`
     - `tests/native/qi/300_tests_green.oren`
     - `tests/native/qi/400_main.oren`

6) **Split oversized compiler build pipeline file (maintenance)** (S)

   Status (fact):

   - 2026-02-13: split `lib/compiler/compiler/040_build_pipeline.oren` into include segments:
     - `lib/compiler/compiler/040_build_pipeline/000_prelude.oren`
     - `lib/compiler/compiler/040_build_pipeline/010_main.oren`
     - `lib/compiler/compiler/040_build_pipeline/090_selftest.oren`

7) **Split oversized module linking file (maintenance)** (S)

   Status (fact):

   - 2026-02-13: split `lib/compiler/compiler/020_modules_linking.oren` into include segments:
     - `lib/compiler/compiler/020_modules_linking/000_prelude.oren`
     - `lib/compiler/compiler/020_modules_linking/010_parse.oren`
     - `lib/compiler/compiler/020_modules_linking/020_pipeline.oren`
     - `lib/compiler/compiler/020_modules_linking/090_tail.oren`

8) **Split oversized x64 syscall intrinsics file (maintenance)** (S)

   Status (fact):

   - 2026-02-13: split `lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren` into include segments:
     - `lib/compiler/x64_native_program/046_emit_sys_intrinsics/000_prelude.oren`
     - `lib/compiler/x64_native_program/046_emit_sys_intrinsics/090_tail.oren`

9) **Split oversized x64 program entry file (maintenance)** (S)

   Status (fact):

   - 2026-02-13: split `lib/compiler/x64_native_program/090_program_entry.oren` into include segments:
     - `lib/compiler/x64_native_program/090_program_entry/000_prelude.oren`
     - `lib/compiler/x64_native_program/090_program_entry/010_part_a.oren`
     - `lib/compiler/x64_native_program/090_program_entry/020_part_b.oren`
     - `lib/compiler/x64_native_program/090_program_entry/090_tail.oren`

## Tier‑1 verification blockers (operational)

- Remote Win11/WSL2 access can intermittently fail via the default proxy hostname (`pc.work`).
  - Mitigation:
    - Use `--skip-remote` for quick local confidence and keep local x64 compile-only gates strong.
    - Fetch remote logs without copy/paste using `scripts/fetch_remote_file.sh` (see `docs/REMOTE_X64_ENV.md`).
    - Analyze large logs with `scripts/analyze_stage2_failure_log.sh` (bounded output).
    - If a fetched log is only a few lines and shows `x64 pe: failed to write ... examples\\...`:
      - it usually indicates an older compiler that did not normalize backslash paths early; re-run `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` to confirm the current gate is green.
    - Note: `scripts/fetch_remote_file.sh --trace` is safe to use when debugging proxy/ssh issues (it now scans the full stage log for the `FETCH_OK:` marker instead of assuming it appears in the last few lines).

- The native runtime-object cache can preserve stale machine code across compiler/backend changes (even when runtime source hashes are unchanged).
  - Mitigation:
    - When touching x64/arm64 codegen or syscall intrinsic lowering, bump the relevant backend signature(s) in `lib/compiler/native_runtime_obj_cache.oren`.
    - If you need a quick one-off confirmation without bumping signatures: build with `--no-cache` / env `OREN_NO_CACHE=1`.
    - Optional: refresh cross-target seeds for faster first-run confidence: `make rtobj-seed-x64`.
