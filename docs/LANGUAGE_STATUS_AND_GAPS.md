# Language Status & Gaps (Rolling, Production Roadmap)

Oren is intentionally in **rolling mode**: rapid evolution is allowed, and backward
compatibility is not required unless explicitly stated.

This document is a *fact-first* snapshot of:

1) what exists today (with references to tests/fixtures),
2) what is missing for “modern production language” maturity,
3) the prioritized gap list (feeds `docs/TODOS.md`).

It is not meant to be aspirational prose; it is a checklist tied to code and tests.

## North Star (Production Definition)

“Production-ready Oren” means:

1) **Language**: a modern, expressive surface with stable semantics, strong diagnostics, and a coherent standard library story.
2) **Compiler**: one front-end with a shared, semantics-owning CoreIR, emitting 3 backends consistently:
   - C backend (portable bootstrap + constrained targets),
   - native backend (Tier‑1: arm64 + x86_64; macOS + Linux + Windows),
   - bytecode backend (`.obc`) for AVM.
3) **AVM**: a deterministic, budgeted execution environment where:
   - `.obc` runs under capability gating,
   - multiverse (AVM-in-AVM) can safely compose universes,
   - **compiler-in-AVM** is supported (compile `.oren → .obc` inside the sandbox).
   - plugin-style tooling can be modeled as **child universes** (OBC-first; iOS-safe; no-JIT-first).

This doc answers: “what’s real today?” and “what’s missing to reach that definition?”

Related plugin/nesting model notes:

- `docs/AVM_DESIGN.md#avm-plugins-nesting-obc-first-ios-safe-rolling`

## Implemented Today (Evidence-Backed)

### Core language surface

- **Functions + lambdas as values**
  - Runtime plumbing: `lib/runtime_native/120_first_class_fn.oren`
- **Generics + specialization**
  - Compile-time guardrails: `tests/native/fixtures/generic_unspecialized_call.oren`
  - AVM specialization coverage: `tests/avm/test_generic_call_specialization.oren`
- **Traits + impl blocks**
  - Qualified calls: `tests/modules/test_trait_qualified_calls.oren`
  - Failure modes: `tests/native/fixtures/trait_impl_ambiguous_method.oren`,
    `tests/native/fixtures/trait_impl_duplicate.oren`,
    `tests/native/fixtures/trait_impl_split_blocks.oren`

### Diagnostics / determinism contracts

- **Machine-readable diagnostics (`OREN_DIAG`)**
  - Runtime fail header: `tests/native/fixtures/diag_fail.oren`
  - Compile-time ABI layout errors: `tests/native/fixtures/abi_layout_error.oren`
- **Deterministic invalid arithmetic behavior**
  - div-by-zero / overflow / shift-oob are exercised by the curated runner
    via native/C diagnostics fixtures (see `tests/native/fixtures/arith_*.oren`).

### Attribute system / ABI tools

- **Attributes + strict mode**
  - `tests/native/fixtures/strict_attrs_ok.oren` / `strict_attrs_bad.oren`
  - See also `docs/ATTRIBUTES.md`
- **Conditional compilation (`@cfg`, `@debug`/`@release`, `debug { ... }`/`release { ... }`)**
  - Statement-level filtering + debug/release gating is exercised by:
    - `tests/native/cfg_os_select.oren`
    - `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)
- **Debug print sugar (`dbg(...)`, `dprint(...)`)**
  - Statement form: `dbg(...)` expands to `@debug print(...)` with a file/line prefix (compiled out in release).
  - Statement form: `dprint(...)` expands to `@debug print(...)` with no prefix.
  - Expression form (single-arg): `dbg(expr)` / `dprint(expr)` return `expr` and print only in debug builds.
  - Evidence: `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`)
- **ABI layout query intrinsics**
  - `tests/native/fixtures/abi_layout_error.oren`

### Capability / capsule model

- **Capsules (capability-restricted native execution)**
  - `tests/native/fixtures/capsule_ok.oren`
  - `tests/native/fixtures/capsule_bad_syscall.oren`
  - `tests/native/fixtures/capsule_bad_fs.oren`
  - `tests/native/fixtures/capsule_ok_fs_allow.oren`
  - Higher-level syscall-edge fixtures live under `tests/native/fixtures/capsule_runtime_*`

### Backend reality (today)

- **3 backends**
  - C backend (portable via host toolchain)
  - bytecode backend + AVM (`.obc`)
  - native backend (arm64 mature; x86_64 rolling bring-up)
- **Tier‑1 intent for x86_64**
  - Local build existence + format checks are validated by the curated runner.
  - Real-hardware x86_64 run validation is opt-in (Win11, WSL2 optional): `docs/REMOTE_X64_ENV.md`
    - Rolling note (2026-02-13): the current remote host has Win11 online, but WSL2 is not installed/enabled yet.
    - Tier‑1 TIME substrate (Linux+Windows): `tests/native/test_time_suite.oren` (expects `oren_sleep_ms` + wall/mono time to work without libc)
    - Tier‑1 RNG substrate (Linux+Windows): `tests/native/test_quick_integration_native.oren` asserts `oren_getentropy` works (and Tier‑1 WebSocket uses it for client key + masking).
    - Tier‑1 parity fixture (closures + varargs): `tests/fixtures/tier1_native_lambda_varargs_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh --targets x64-win-tier1` / `x64-wsl-tier1` with `--tier1-src ...`)
    - Tier‑1 parity fixture (map dynamic key-kind on empty maps): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets; see `docs/REMOTE_X64_ENV.md`)
    - Tier‑1 parity fixture (map get via dynamic key; nil-key miss semantics): `tests/fixtures/tier1_native_map_get_dynamic_key_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets)
    - Tier‑1 parity fixture (string ops: `+` / `len` / `slice`): `tests/fixtures/tier1_native_string_ops_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets)
    - Tier‑1 parity fixture (float literals + `+ - * /` + casts `f32/i64`): `tests/fixtures/tier1_native_float_ops_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets)
    - Tier‑1 parity fixture (process args / `oren_args()` across Linux+Windows): `tests/fixtures/tier1_native_args_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets)

### Concurrency primitives (runtime-level; rolling)

- **Channels + select in AVM**
  - Deterministic VM opcodes: `SELECT_RECV` / `SELECT` in `lib/avm/avm_vm.c`
  - Evidence: `tests/avm/test_smoke_suite.oren` (channels + select cases)
- **Channels + select in native runtime (rolling)**
  - Channels:
    - macOS/Linux: pipe-based channels: `lib/runtime_native/010_channels_globals_consts.oren`
    - Windows: in-memory channels: `lib/runtime_native/011_channels_mem.oren`
  - Select over channels: `lib/runtime_native/245_select.oren` (POSIX: kqueue/epoll; Windows: mem-channel select)
  - Evidence: `tests/native/test_integration_suite.oren` (`test_select_primitives`)

### Networking + crypto (stdlib; rolling)

- **TCP/UDP + HTTP + WebSocket loopback suites**
  - Evidence: `tests/native/test_net_suite.oren`, `tests/native/test_http_get_loopback.oren`, `tests/native/test_ws_echo_loopback.oren`
  - Tier‑1 reality: these are included in the remote x86_64 net verification gate (`scripts/verify_native_net_matrix.sh`).
- **TLS/HTTPS/WSS loopback on macOS + Linux + Windows**
  - Evidence: `tests/native/test_tls_loopback.oren`, `tests/native/test_https_get_loopback.oren`, `tests/native/test_wss_echo_loopback.oren`
  - Tier‑1 gate: `scripts/verify_native_net_matrix.sh` runs these fixtures on Win11 (WSL2 optional) + local macOS + linux/arm64 container.
- **HTTP/2 bring-up (framing-only; ALPN `h2`)**
  - Scope today: connection preface + frame header encoding/decoding + minimal control frames (SETTINGS/ACK, PING/ACK) + SETTINGS payload codec + HPACK encode/decode v0.
  - Stdlib: `lib/std/net/http2.oren`
  - Minimal client facade: `lib/std/net/http2_client.oren` (handshake + single-stream request/response; exercised by the loopback fixture)
  - HPACK core: `lib/std/net/hpack.oren` (RFC 7541 static+dynamic tables; Huffman encode/decode; header block encode/decode)
  - Evidence: `tests/native/test_http2_preface_loopback.oren` (preface + SETTINGS/ACK + PING/ACK over TLS)
  - HPACK smoke: `tests/native/test_hpack_smoke.oren` (RFC 7541 Appendix C.2 + C.4.1; includes Huffman decode)
  - HPACK encoder regression: `tests/native/test_hpack_encode_rfc_c41.oren` (reproduces RFC 7541 Appendix C.4.1 exact bytes)
  - HTTP/2 request/response loopback: `tests/native/test_http2_headers_loopback.oren` (HEADERS + CONTINUATION + DATA over TLS; single stream; includes SETTINGS payload + SETTINGS/ACK)
  - Tier‑1 gate: `scripts/verify_native_net_matrix.sh` runs the loopback fixture on macOS + Linux + Windows (stage1 + stage2).
- **PEM decode helpers (crypto plumbing)**
  - Evidence: `tests/native/test_pem_decode_smoke.oren` (imports `std:crypto/pem`)

### UI core (headless; rolling)

- **Deterministic UI tree/layout/render/raster core (no OS windows)**
  - Modules: `lib/std/ui/{core,layout,style,render,raster,commands,ppm}.oren`
  - Evidence (AVM): `tests/avm/test_ui_*_v0.oren` fixtures (layout, render, raster, ppm, commands.validate)
  - Evidence (native quick smoke): `tests/native/test_quick_integration_native.oren` (`test_ui_headless`)

## What’s Still Missing for Production Maturity (Gap List)

This section is intentionally phrased as “missing or not yet proved by tests”, because
production maturity requires both implementation *and* regression coverage.

### P0: Semantic parity and safety invariants

- **Stack safety parity across backends**
  - AVM has `--call-depth-max`.
  - C backend has `OREN_CALL_DEPTH_MAX` env (`0` disables the deterministic guard).
  - Native backend supports `oren build --call-depth-max <n>` (compile-time default) and `OREN_CALL_DEPTH_MAX` (runtime override, including x64 entry stubs; `0` disables).
  - Design: `docs/STACK_SAFETY.md`
- **Remove native map “key kind” heuristics**
  - Any heuristic that guesses key types (e.g. based on numeric range) is a semantics risk.
  - Direction: a tagged value model or explicit key typing at IR level.
  - Rolling status:
    - Native backends (arm64 + x64): “magic numeric range” key typing is removed from compiler lowering/codegen decisions; when key kind is not inferable statically, native codegen can perform a runtime dispatch via tracking metadata (`oren_find_node(key).kind == STRING` → string key; else treat as int key). The native runtime still keeps a small-int fast path (`key < 4096`) to avoid allocation-list scans; this is a bring-up optimization, not a semantics rule. Tagged values remain the full fix.
    - x64 native now also propagates `recv_kind` on `Index` so codegen can avoid dynamic LIST/MAP dispatch when the receiver kind is known (still validates runtime magic; remaining unknown cases need a principled representation)
    - Tier‑1 x86_64 evidence (empty map + dynamic string key): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 Tier‑1 gate; see `docs/REMOTE_X64_ENV.md`)
- **Varargs/spread parity (all backends + indirect calls)**
  - Varargs must be “boring and correct”: same semantics everywhere, including closures.
  - Rolling status: x64 native supports `fn (x, ...rest) { ... }` lambdas; see Tier‑1 parity fixture above.

- **Tier‑1 OS/arch parity: native backends must converge**
  - Targets (Tier‑1 intent): macOS + Linux + Windows, on arm64 + x86_64.
  - Production readiness requires more than “it links”:
    - stable entry semantics (`__top_level__` + `main`),
    - deterministic panic/diagnostic contracts (`OREN_DIAG`),
    - consistent container fast-path semantics (no backend-only behavior),
    - capsule gating parity for syscall surfaces.
    - Rolling evidence (x86_64 Windows):
      - TIME substrate is now proved by `tests/native/test_time_suite.oren` on Win11 (sleep + gettimeofday shims).
      - RNG substrate is now proved by `tests/native/test_quick_integration_native.oren` (asserts `oren_getentropy` works).
      - NET substrate is now regression-gated by `scripts/verify_native_net_matrix.sh`:
        - Loopback-only TCP/UDP + HTTP GET + WebSocket echo are covered on Win11 (WSL2 optional) via `tests/native/test_net_suite.oren`, `tests/native/test_http_get_loopback.oren`, `tests/native/test_ws_echo_loopback.oren` (see `docs/REMOTE_X64_ENV.md`).
        - TLS/HTTPS/WSS are now proved on Win11 (WSL2 optional) + macOS + Linux via `scripts/verify_native_net_matrix.sh` (fixtures: `tests/native/test_tls_loopback.oren`, `tests/native/test_https_get_loopback.oren`, `tests/native/test_wss_echo_loopback.oren`).
    - FFI substrate (Tier‑1 Windows, rolling):
      - `ffi name` is implemented via lazy `LoadLibraryA`/`GetProcAddress` stubs in the x64 backend.
      - Evidence: `tests/native/ffi_windows_kernel32.oren` (remote Win11 gate via `scripts/verify_native_matrix.sh --targets x64-win`).
    - PROC substrate (Tier‑1 Windows): rolling but now regression-gated:
      - POSIX fork/exec/wait4 do not exist, so the runtime uses `CreateProcessA` via `sys_win_createprocess` for `oren_proc_spawn`/`oren_system`.
      - Proof gate: `scripts/verify_native_matrix.sh --targets x64-win-tier1` runs `tests/fixtures/tier1_native_smoke_main.oren` on Win11 (WSL2 optional); the fixture calls `oren_system("echo tier1 smoke proc ok")` and returns non‑zero on failure.
      - Note (concurrency): Windows Tier‑1 `spawn` now prefers in-process green tasks (N:1), same as POSIX; host-thread `oren_join(_timeout)` drives the green scheduler (Tier‑1 remote fixture: `tests/fixtures/tier1_native_spawn_join_main.oren`).
        - Escape hatch: `OREN_NO_GREEN=1` falls back to a runtime-owned OS-thread spawn; join waits via `WaitForSingleObject` and timeout handling uses a best-effort detach (avoids `TerminateThread`).
    - Self-host compiler on x86_64 (rolling):
      - Local emit sanity (compile-only): `make verify-native-x64-compile` (builds stage1+stage2 and emits x64-linux + x64-windows artifacts).
      - Native Windows bootstrap gate (stage0 -> stage1 -> stage2, then compile+run a tiny exe): `scripts/verify_windows_stage2_from_stage1.sh` (`make verify-stage2-win`).
      - Remote run gate: `scripts/verify_selfhost_x64_compiler.sh` builds x64 compiler binaries and runs them on Win11 (WSL2 optional) to compile+run a tiny native program.
    - Track: `docs/TODOS.md` (P0.1–P0.3), `docs/BACKEND_ARCHITECTURE.md#native-backend-overview`.

  - **Async IO + scheduler integration (planned)**
    - Today, NET fd waits are runtime helpers that block OS threads (`lib/runtime_native/240_tcp.oren`).
    - The production direction is a native scheduler + netpoller so IO readiness can feed channels and `select`.
    - Track: `docs/TODOS.md` (P1.3), `docs/ASYNC_IO_AND_SELECT.md`.

### P1: Tooling quality (modern compiler UX)

- **Modern CLI ergonomics (mostly done; polish remains)**
  - The Stage1 compiler (`./oren`) already uses a structured subcommand model backed by `std:argparse`:
    - `oren build|emit-c|meta|dump|scan|completion`
    - `oren --help` and `oren <cmd> --help`
    - machine-readable help: `oren --help=json`
    - completion scripts: `oren completion bash|zsh` (see `docs/CLI_COMPLETION.md`)
  - Remaining “production polish” gaps:
    - consistent exit codes for all parse/validation errors
    - env/flag precedence is now standardized:
      - defaults come from the CLI spec (and may be sourced from env via `std:argparse` option bindings)
      - CLI argv always wins over env
      - machine-readable help (`--help=json`) exposes `env` for each option (when applicable)
    - optional `--json` structured output for build results (artifact list + hashes) beyond `--manifest`

- **Production CLI ergonomics: “click-like” subcommands**
  - The repo already has subcommands + completion, but production UX needs:
    - consistent error formatting (human + machine),
    - stable exit codes for parse/analyze/codegen/link phases,
    - a consistent “flag precedence” contract (env vs CLI vs defaults),
    - help output suitable for IDEs and wrappers.
  - Track: `docs/TODOS.md` (P0.8).

### P1: Stdlib maturity

- **Stdlib should track current grammar**
  - Avoid legacy syntax drift: if/else forms, match forms, for-in syntax, etc.
  - The repo enforces audits via Makefile + direct test programs; expand as grammar stabilizes.

### P2: Distribution and “production runtime” story

- **Stdlib resolution/distribution**
  - “User friendly imports” vs embedding vs precompiled `.obc` bundles needs a single
    coherent model that works for both native and AVM.
  - Related docs: `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`, `docs/OBC_MODULE_LINKING.md`

- **Packages + registry + reproducible builds**
  - For production, the language needs a coherent “package → build artifact” story:
    - module naming / resolution,
    - lockfiles, hashes, deterministic builds,
    - support for precompiled `.obc` libraries (OBX exports/relocs) in AVM.
  - Track: `docs/OBC_MODULE_LINKING.md`, `docs/TOOLCHAIN_SELF_HOSTING.md`, `docs/TODOS.md` (P1.2, P1.4).

- **Trust / signing / update channels for multiverse**
  - Multiverse implies “code moves between universes”; production needs a root-of-trust:
    - signed `.obc` artifacts, cert chains, key rotation,
    - developer identity / org delegation model,
    - update and patch workflows that do not break determinism.
  - Track: `docs/APPSTORE_ROOTCA_AND_UPDATES.md`, `docs/CERT_CHAIN_FORMAT.md`, `docs/TODOS.md` (P1.1).

## How to Use This Doc

- When a new feature lands, add a **test/fixture reference** here (it becomes living spec).
- When an incompatibility is introduced, record it as a **rolling limitation** and link the
  TODO item that will remove it.
