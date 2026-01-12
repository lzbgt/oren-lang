# Active Tracker (Rolling)

**Last updated:** 2026-01-12

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

- `make test` (native quick integration smoke; fast default)
  - Includes “must fail” fixtures (e.g. `scalar == nil` hazards).
- `make verify-native-quick` (stage1 + stage2 native smoke)

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
		   - 2026-01-12: verified x64 native selfhost compile-only gate still passes after the runtime FS-helper refactor:
		     - `make verify-native-x64-selfhost-compile` (targets: x64-linux, x64-windows)
	   - 2026-01-12: `scripts/verify_native_x64_compile_only.sh` now pre-seeds native runtime ASTBIN + rtobj (core+full) before running tight per-build timeouts, so the “cold after runtime change” case stays bounded.
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
   - 2026-01-12: fixed the native runtime lock blocking primitive on Tier‑1:
     - `sys_ulock_wait/sys_ulock_wake` are now treated as a portable "wait-on-address" primitive:
       - Linux: `futex(FUTEX_WAIT_PRIVATE/FUTEX_WAKE_PRIVATE)`
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
   - 2026-01-13: `scripts/verify_windows_stage2_from_stage1.sh` passed (remote Win11; stage0→stage1→stage2, plus UI shim compile/link guard).
   - 2026-01-13: `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl` passed (remote WSL2; x64-linux compiler runs and compiles+executes a tiny native program).
   - 2026-01-12: `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` passed (remote Win11 + WSL2; stage2 compiler runs and compiles+runs a tiny native program on both).

7) **GUI: platform shims for Tier‑1 (RGBA blit v0)** (L)

   Keep `std:ui/*` as the portable retained-mode API; bring up thin platform shells.

   Docs:

   - `docs/GUI.md`, `docs/GUI_PLATFORM_SHIMS.md`
   - Optional Dear ImGui shell/overlay: `docs/GUI_IMGUI_SHELL.md` (devtools + bring-up accelerator, not the app UI API)
     - Upstream reference snapshots (verbatim) live under `project-doc/web/github.com/ocornut/imgui/` (do not rely on memory/folklore).
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

## Tier‑1 verification blockers (operational)

- Remote Win11/WSL2 access can intermittently fail via the default proxy hostname (`pc.work`).
  - Mitigation:
    - Use `--skip-remote` for quick local confidence and keep local x64 compile-only gates strong.
    - Fetch remote logs without copy/paste using `scripts/fetch_remote_file.sh` (see `docs/REMOTE_X64_ENV.md`).
    - Analyze large logs with `scripts/analyze_stage2_failure_log.sh` (bounded output).
    - If a fetched log is only a few lines and shows `x64 pe: failed to write ... examples\\...`:
      - it usually indicates an older compiler that did not normalize backslash paths early; re-run `scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` to confirm the current gate is green.
    - Note: `scripts/fetch_remote_file.sh --trace` is safe to use when debugging proxy/ssh issues (it now scans the full stage log for the `FETCH_OK:` marker instead of assuming it appears in the last few lines).
