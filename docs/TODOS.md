# Active Tracker (Rolling)

**Last updated:** 2026-01-16

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
  - x64-linux execution is currently validated via the Win11+WSL2 host (`docs/REMOTE_X64_ENV.md`)

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
				   - 2026-01-16: fixed a module-parse parallelism deadlock when stage2 `spawn` is cooperative green tasks (thread-mode but not truly concurrent):
				     - Root cause: the thread-mode join loop polled `oren_is_done(...)` and slept without driving the green scheduler, so spawned workers never ran (hangs x64 compile-only suite).
				     - Fix: detect cooperative spawn and join sequentially (each join drives the scheduler): `lib/compiler/compiler/020_modules_linking.oren` (`_ml_spawn_is_cooperative`).
				     - Guard: `make verify-native-x64-compile` (`scripts/verify_native_x64_compile_only.sh` sets `OREN_PARSE_FORK_PARALLEL=1`).
				   - 2026-01-16: hardened native debug-info parsing so diagnostics never crash debug builds (best-effort tables must not segfault):
				     - Runtime: `lib/runtime_native/110_mem_diag.oren` (`compute_program_pc_bounds`, `find_func_info`) now bails out on malformed lengths/pointers.
				     - Guard: `make test` (native quick integration is built with `--debug` and installs debug info at entry).
				   - 2026-01-14: fixed an arm64-macos native OS-thread bring-up crash that could be *masked or preserved* by stale rtobj cache entries:
				     - Symptom: `tests/native/test_darwin_os_thread_spawn_join.oren` crashes (SIGBUS) on stage2-native builds when runtime thread registration is enabled and rtobj cache hits.
				     - Root cause: native call-depth hooks recursed via an instrumented slow-path helper when multithreading flips `g_runtime_single_threaded` to 0; stale rtobj cache entries kept the buggy runtime machine code alive even after compiler fixes.
			     - Fix: ensure call-depth slow-path helpers are never instrumented + bump rtobj backend signatures (`arm64_v0_8`, `x64_v0_13`) to invalidate old cached runtime objects.
	   - 2026-01-12: began splitting the >2k-line x64 Linux syscall intrinsic emitter into smaller modules; moved the NET/epoll blocks into `lib/compiler/x64_native_program/046_emit_sys_intrinsics_linux_net.oren` so hot-path compilation of `_emit_intrinsic_sys_linux_x64` stays bounded.
	   - 2026-01-12: introduced an x64-focused compiler entry (`oren_x64.oren` → `lib/compiler/compiler_x64.oren`) that swaps arm64 native backends for small stubs, so x64 self-host builds do not spend time compiling arm64 code.
	     - Fact (arm64-macos host → x64-linux target, `--no-cache`): `./oren_stage2 build oren_x64.oren --backend native --platform x64-linux --no-debug`
       - total ~180s (`[build] summary total_ms=180390`)
       - link (parse+passes) ~103s (`link_ms=102635`)
       - x64 emit+link ~78s (`emit_ms=77747`)
     - This keeps `scripts/verify_native_x64_selfhost_compile_only.sh` under the default 240s timeout (it now defaults to `oren_x64.oren`; override via `OREN_SELFHOST_SRC=oren.oren`).

2) **Tier‑1 native parity: correctness across arch/OS** (L)

   Goal: “same program, same result” across Tier‑1, not “macOS only”.

   Parity surfaces:

   - value semantics (`nil/false/true` vs numeric), comparisons, list/map behavior
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

	   - 2026-01-12: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` passed (compiler runs on Win11 + WSL2 and compiles+runs a tiny native program on both).
		   - 2026-01-13: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` extended with a filesystem directory gate (`fs_dir_gate.oren`) and remains green:
		     - proves `oren_mkdir_p` handles the `-EEXIST` case correctly for directories
		     - proves `sys_stat` reports directory mode correctly on both WSL2 (x64-linux) and Win11 (x64-windows)
		   - 2026-01-13: `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` passed (remote Win11 + remote WSL2; stage1 + stage2).
		   - 2026-01-15: `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` passed (remote Win11 + remote WSL2; stage1 + stage2).
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
     - Verified end-to-end via `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` (stage1 + stage2; Win11 + WSL2).
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
	   - 2026-01-13: Tier‑1 native smoke now asserts the reflection v0 contract on real x64 hosts (Win11 + WSL2):
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
   - 2026-01-12: `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` passed (remote Win11 + WSL2; stage2 compiler runs and compiles+runs a tiny native program on both).

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

   Next steps (actionable, highest leverage first):

   - Stage N2 groundwork: syscall-first OS threads (no libpthread) on Tier‑1
     - macOS arm64: finish the syscall-first `bsdthread_register` story and keep it robust across modern dyld/libpthread:
       - keep installing runtime-owned threadstart stubs at process init (call `native_runtime_threading_init(...)` early)
       - keep `sys_bsdthread_create/terminate` wired to the shared runtime `oren_os_thread_spawn(...)` primitive (`lib/runtime_native/269_os_thread_m.oren`)
       - reduce/eliminate the pthread fallback by making syscall-first threadstart work even when the process is already registered by libpthread (kernel may return `-EINVAL` / already-registered; requires deeper ABI alignment work)
     - Linux x64/arm64: extend the syscall-first OS-thread substrate toward production:
       - add TLS story (`CLONE_SETTLS`) once runtime uses/needs a real thread pointer
       - unify the Linux `M` abstraction with Windows/Darwin (shared scheduler-facing shape)
       - keep join bounded: `tests/native/test_linux_os_thread_smoke.oren` uses a futex wait timeout and re-checks `ctid_ptr` after timeout (avoids false negatives if a wake is missed)
     - Windows x64: unify existing CreateThread-based `spawn` with the same scheduler-facing `M` abstraction (keep WaitForSingleObject join)
	   - 2026-01-15: introduced a minimal runtime-owned OS-thread ("M") abstraction (macOS + Linux + Windows) for future M:N work:
	     - Runtime: `lib/runtime_native/269_os_thread_m.oren`
	       - `oren_os_thread_spawn(start_addr, arg_ptr)`
	       - `oren_os_thread_join_timeout(handle, timeout_us)` (portable timeout `-60`)
	       - `oren_m_park_word_wait` / `oren_m_park_word_wake` (futex/WaitOnAddress token-based park/unpark)
	     - Guard: `tests/native/test_os_thread_park_unpark_smoke.oren` (macOS + Linux + Windows)
	     - Guard: `tests/native/test_os_thread_spawn_many_smoke.oren` (macOS + Linux + Windows; bounded join timeout)
		   - 2026-01-15 → 2026-01-16: Stage N2 groundwork: green-task scheduler can now run on background OS threads ("M") via `oren_green_start_workers(n)`.
		     - Runtime: `lib/runtime_native/263_green_tasks.oren`
		       - per-OS-thread scheduler state (scheduler ctx + current-G are no longer globals)
		       - Stage N2 groundwork: `P` struct + per-P runq/sleepq (single-P by default), plus a thread-local **current P** pointer
		       - scheduler now has a **global run queue** for cross-P injection / fairness (spawns from outside green context)
		       - per-P local runq is now a **GC-visible ring buffer / work-stealing deque** (head+tail+mask), with overflow to the global runq
		       - worker idle sleeps now park on the shared park word with a timeout (so new runnable work wakes it immediately); inserting sleepers wakes workers to re-evaluate the next deadline
		       - worker entry accepts an optional `P*` argument and claims `P.owner_tid` (rolling: hard fail if a P is accidentally shared across Ms)
		       - `_green_poll_until` enforces `P.owner_tid == sys_gettid()` in worker mode; `oren_green_start_workers` reserves each `P` with a negative sentinel and the worker claims its bound `P` to a positive tid before running the scheduler loop
		       - scheduler now uses a **dedicated scheduler lock** (wait-on-addr based) instead of the runtime global lock (reduces coupling to allocator/GC metadata)
		         - Invariant: requires `sys_gettid()` to be non-zero when workers are enabled (0 is reserved as the “unlocked” sentinel).
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join`)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_ctx_switch_alloc_integrity`) (worker-mode ctx-switch + scheduler stability)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_local_ptr_survives_yields`) (ctx-switch must preserve long-lived locals across yields)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_local_ptr_survives_yields`) (same contract under worker-mode scheduling)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_wake_while_sleepers`) (prevents “sleepers stall runnable work” regressions)
				     - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_global_runq_fairness`) (prevents global-runq starvation regressions)
				     - Rolling limitation: worker parallelism is clamped to 1 by default until the native allocator/GC are concurrency-correct; opt-in for experimentation only via `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`.
		   - Parking/unparking primitive for idle `M` (required to avoid spin):
		     - macOS: ulock-based park/wake for `P` (pairs with `sys_ulock_wait/sys_ulock_wake`)
		     - Linux: futex-based park/wake
		   - Stage N3 (next): make `P` real (toward true M:N)
		     - enforce “an `M` runs Oren code only while holding a `P`” (no shared-P execution)
		     - evolve the global runq into a fairness/overflow queue (it exists today as cross-P injection)
		     - implement real work stealing between `P` (today: a global-lock bring-up: “steal one before idle”, plus periodic global-runq polling for fairness)
		     - replace the current global lock in green scheduling with per-P queues + atomics (keep GC/STW correctness first)
				     - define and enforce a context-switch preservation contract (arm64 `oren_ctx_switch` + codegen):
				       - today, the scheduler re-fetches per-thread state (`ts`/`P`) each poll iteration for robustness; fix the root cause so we can rely on normal locals again
				       - 2026-01-16: arm64 native backend now addresses locals FP-relative (X29) instead of SP-relative:
				         - reduces long-lived-local aliasing hazards when SP moves for temporaries/ABI call frames
				         - compiler: `lib/compiler/arm64_core.oren`, `lib/compiler/arm64_native_stmt.oren`, `lib/compiler/arm64_native_expr/010_lowering_a.oren`
				         - verified: `make test`
				       - add a small regression that would have caught the earlier “P pointer becomes a small integer after ctx switch” failure mode
				       - concrete failure mode seen in worker-mode: `P` can collapse to a small integer (e.g. `2`) and crash in `_green_p_owner_tid`; keep the per-iteration re-fetch until the native backend reliably preserves/spills long-lived locals across call sites
				       - 2026-01-16: added a small compiler guard to reduce “dead code perturbs stack accounting” hazards:
				         - arm64 stmt codegen now stops emitting statements after a non-fallthrough terminator in a `Block`:
				           - direct `break`/`continue`/`return`
				           - `if { ... } else { ... }` where both branches terminate
				           - compiler: `lib/compiler/arm64_native_stmt.oren` (`native_compile_stmt` returns `false` for “no fallthrough”)
				         - status: this does **not** yet make `_green_poll_until` safe to cache `ts`/`P` across iterations; keep the re-fetch until a deeper backend/ctx-switch fix lands
					         - 2026-01-16: arm64 stmt codegen now also restores SP after condition evaluation in `if` / `while` / `for` headers (so branch entry SP matches codegen assumptions):
					           - compiler: `lib/compiler/arm64_native_stmt.oren` (`cond_delta` restore)
					         - known repro (rolling): attempts to add an env-gated cached mode (e.g. probing `OREN_GREEN_POLL_CACHE` via `native_envp_get_value_ptr(...)` and caching `ts`/`P` across iterations) still cause deterministic SIGSEGV (rc=139) in `make test-native-quick-stage2` / `make test`; keep the safe per-iteration re-fetch loop by default
				     - 2026-01-16: switched green sleeper deadlines to a monotonic clock source (avoid wall-clock jumps affecting wake behavior):
				       - Runtime: `lib/runtime_native/100_time.oren` (`oren_time_mono_ns`)
				       - Runtime: `lib/runtime_native/263_green_tasks.oren` (`_green_time_now_ns` + scheduler uses it for wake/deadlines)
				       - Compiler (Linux x64/arm64): `sys_gettimeofday(..., abs_ptr)` now fills abs_ptr with `clock_gettime(CLOCK_MONOTONIC)` in ns
				         (so `oren_time_mono_raw()` works on Linux too)
			     - 2026-01-16: added a bounded regression gate for worker-mode scheduling (many tasks must complete; no hangs):
			       - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_many_tasks_bounded`)
			     - Next: make `oren_time_mono_ns()` conversion exact on macOS/Windows (avoid wall-clock-based calibration):
			       - macOS: use `mach_timebase_info` (num/den) for mach_absolute_time -> ns
			       - Windows: use `QueryPerformanceFrequency` for QPC ticks -> ns
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

## Tier‑1 verification blockers (operational)

- Remote Win11/WSL2 access can intermittently fail via the default proxy hostname (`pc.work`).
  - Mitigation:
    - Use `--skip-remote` for quick local confidence and keep local x64 compile-only gates strong.
    - Fetch remote logs without copy/paste using `scripts/fetch_remote_file.sh` (see `docs/REMOTE_X64_ENV.md`).
    - Analyze large logs with `scripts/analyze_stage2_failure_log.sh` (bounded output).
    - If a fetched log is only a few lines and shows `x64 pe: failed to write ... examples\\...`:
      - it usually indicates an older compiler that did not normalize backslash paths early; re-run `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` to confirm the current gate is green.
    - Note: `scripts/fetch_remote_file.sh --trace` is safe to use when debugging proxy/ssh issues (it now scans the full stage log for the `FETCH_OK:` marker instead of assuming it appears in the last few lines).
