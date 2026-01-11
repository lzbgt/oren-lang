# Active Tracker (Rolling)

**Last updated:** 2026-01-11

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
- `make verify-native-x64-selfhost-compile` (stage2 compiles `oren.oren` for x64-linux + x64-windows; compile-only but higher-signal)

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

3) **Native value representation + reflection-first type system** (L)

   Problem: the native value model is not fully tagged; “dynamic” flows historically produced hazards.

   Deliverables (design → implementation):

   - finish the tagged-value plan: `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
   - stabilize reflection APIs: `docs/REFLECTION_V1.md`
   - define how varargs elements carry type info so userland (fmt/ffi/serde) is robust
   - audit “optional string/env” checks across stdlib/compiler: avoid `v != 0` presence tests (under singleton-`nil`, `nil != 0` is true); standardize on `v != nil && v != 0 && v != ""` or a helper
   - nil-vs-scalar parity: either land tagged values (preferred) or make the nil-compare guard flow-aware enough to catch `x + 1` patterns without flagging intentional nil-coalescing in core code

   Gate:

   - `make test` (nil-compare guard is always-on; diagnostics tagged `nil-compare guard:`)

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

   - 2026-01-12: `./scripts/verify_native_net_matrix.sh --targets x64-win,x64-wsl` passed (stage1 + stage2)

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

7) **GUI: platform shims for Tier‑1 (RGBA blit v0)** (L)

	   Keep `std:ui/*` as the portable retained-mode API; bring up thin platform shells.

	   Docs:

	   - `docs/GUI.md`, `docs/GUI_PLATFORM_SHIMS.md`
	   - Optional Dear ImGui shell/overlay: `docs/GUI_IMGUI_SHELL.md` (devtools + bring-up accelerator, not the app UI API)

	   Next steps (actionable):

	   - finalize `native/orenui/orenui.h` v0 ABI (window + poll_event + present_rgba)
	   - implement `native/orenui/win32/*` (Win32 + GDI/DIBSection blit) + keep a bounded headful smoke script green
	     - Started: `native/orenui/win32/orenui_win32.c` (skeleton; expects a GUI session)
	     - Added: `scripts/verify_ui_smoke_windows.sh` (`make verify-ui-smoke-windows`)
	   - implement `native/orenui/x11/*` (X11 + XPutImage blit) + keep a bounded headful smoke script green
	     - Started: `native/orenui/x11/orenui_x11.c` (skeleton; requires X11)
	     - Added: `scripts/verify_ui_smoke_linux.sh` (`make verify-ui-smoke-linux`)
	   - keep `examples/ui_hello.oren` portable across shims (today: macOS + Windows via `@cfg(os=...)`)

8) **FFI ergonomics + ABI surface completion** (M)

   Goal: real-world Win32/libc/OpenSSL bindings are not painful.

   Next:

   - add ptr-sized / `usize` return kinds and a stable story for `size_t`
   - consider “quoted external symbol” syntax only if we encounter real APIs that are not identifier-compatible

## P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)

   References:

   - `docs/APPSTORE_ROOTCA_AND_UPDATES.md`
   - `docs/CERT_CHAIN_FORMAT.md`

2) **Stackless recursion beyond TCO (heap call frames)** (L)

   Reference:

   - `docs/STACK_SAFETY.md`

3) **Native scheduler + netpoller (true async IO + channels/select)** (L)

   References:

   - `docs/CONCURRENCY_MODEL.md`
   - `docs/NATIVE_GMP_SCHEDULER.md`
   - `docs/ASYNC_IO_AND_SELECT.md`

## Tier‑1 verification blockers (operational)

- Remote Win11/WSL2 access can intermittently fail via the default proxy hostname (`pc.work`).
  - Mitigation:
    - Use `--skip-remote` for quick local confidence and keep local x64 compile-only gates strong.
    - Fetch remote logs without copy/paste using `scripts/fetch_remote_file.sh` (see `docs/REMOTE_X64_ENV.md`).
    - Analyze large logs with `scripts/analyze_stage2_failure_log.sh` (bounded output).
