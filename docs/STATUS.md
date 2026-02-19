# Status + Tracker (Rolling)

**Last updated:** 2026-02-19

This file merges the former status/roadmap and active tracker into a single canonical doc to reduce split attention.

## Active Tracker (Rolling)

This file tracks the **highest‑leverage work** to make Oren mature and performance‑competitive with C
across the C, native, and OBC/AVM backends. Keep it short and action‑oriented.

## How to use this tracker

- Start at **P0 (Now)** and take the first unfinished item that blocks Tier‑1 parity/perf.
- Keep tasks tied to a **regression gate** (benchmark or test) so work stays measurable.
- If a task is “done enough” in rolling mode, summarize the result and move on (don’t archive here).

Legend:

- Priority: **P0 (Now)** > **P1 (Soon)** > **P2 (Later)**
- Weight: **W5 (highest impact)** → **W1 (lowest impact)**
- Size: **(S/M/L)** = expected scope

## Maturity definition (rolling, measurable)

Oren is “mature” when all are reliably true on Tier‑1 targets (`arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`):

- **Buildability:** stage0→stage1→stage2 works with minimal manual setup.
- **Semantic parity:** native/C/bytecode behavior matches the language spec (fixtures prove it).
- **Performance budgets:** hot‑loop and allocation benchmarks are within target ratios vs C.
- **Docs fidelity:** manuals/spec/status reflect real behavior (fixtures are the living spec).
- **Stdlib quality:** NET/TLS/HTTP/WS are correct and bounded under loopback tests.

## Regression gates (run first when touching compiler/runtime)

Local (fast):

- `make test`
- `make verify-native-quick`
- `./scripts/verify_x64_linux_qemu_smoke.sh`

Tier‑1 cross‑arch:

- `./scripts/verify_native_matrix.sh` (use `--skip-remote` if remote is down)
- `./scripts/verify_native_net_matrix.sh`
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
- `./scripts/verify_stage0_windows_bootstrap.sh`

## Performance parity tracker (weighted, 2026‑02‑19 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026‑02‑19).
Weights reflect expected impact on C parity + breadth of affected code.

1) **W5 — Native integer hot‑loop parity (loop_sum, dot_product)** (L)
   - Expand `inty` propagation + arithmetic fast paths to avoid runtime helpers in tight loops.
   - Ensure native fastmod handles constant RHS and known‑literal mod vars.
   - Gate: native `loop_sum` and `dot_product` ≤ 2× C on arm64 + x64.

2) **W5 — Allocation/GC overhead reduction (alloc_churn/alloc_drop)** (L)
   - Fix and enable reuse paths (`OREN_GC_REUSE_BLOCKS`) when correct.
   - Reduce per‑alloc metadata overhead; add slabs for hot small objects.
   - Gate: native `alloc_churn` ≤ 8× C; native `alloc_drop` ≤ 5× C; Oren C `alloc_churn` ≤ 5× C.

3) **W4 — List reserve + fast push** (M)
   - Current reserve insertion covers safe int bounds (literals, propagated ints, `oren_*_len` calls, +/−/* arithmetic). Next: widen to richer computed bounds (e.g., min/clamp) and `<=` loop patterns.
   - Route compiler‑proven lists to unchecked push when safe.
   - Gate: native `array_sum` and `multi_list_push_int` ≤ 2× C.

4) **W4 — Tagged value representation convergence (native/C/AVM)** (L)
   - Converge on a canonical tagged representation (no heuristic tagging).
   - This unlocks faster comparisons + removes many fallback paths.
   - Gate: no semantic regressions in `make test` + cross‑backend fixtures.

5) **W3 — SIMD/typed‑buffer parity on native (x64 + arm64)** (M)
   - Ensure list<int>/typed buffers lower to SIMD kernels.
   - Bring up x64 SIMD baseline (SSE2) with scalar‑equivalence gates.
   - Gate: native `dot_product_int` ≤ 2× C.

6) **W3 — AVM allocation fast paths + typed buffers** (M)
   - Arena/slab alloc for short‑lived lists/structs.
   - Ensure typed buffers + vector ops are available without JIT.
   - Gate: OBC `alloc_churn` ≤ 10× C; AVM SIMD test suite passes.

7) **W3 — AVM unboxed list<int> payload + opcode lowering** (M)
   - Implement list<int> payload + compiler lowering for OBC (see collections design).
   - Gate: `list_int` fixtures + OBC perf parity for dot/sum loops.

## P0 (Now)

1) **Native scheduler / GMP M:N groundwork** (L, W4)
   - Keep syscall‑first, no‑libc/pthreads constraints.
   - Ensure green scheduling correctness across sleep/IO waits.
   - Gate: `make test` + `verify_native_matrix.sh` (all Tier‑1).

2) **Perf parity W5 items** (L, W5)
   - Execute items 1–2 in the weighted tracker above.

3) **Tagged value convergence plan** (L, W4)
   - Define the canonical tagged layout + staged migration plan.
   - Gate: fixtures + backends converge without heuristic fallbacks.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring‑up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Tooling reliability: SSH/scp timeouts in verify scripts** (S, W2)

## P2 (Later)

1) **Allow non‑macOS hosts for partial targets** (S, W2)
2) **Package manager / signed module workflow** (M, W2)

## Status and Roadmap (Rolling)

This document consolidates status snapshots, feature matrices, and roadmap planning to reduce drift.

## Language Status & Gaps (Rolling, Production Roadmap)

Oren is intentionally in **rolling mode**: rapid evolution is allowed, and backward
compatibility is not required unless explicitly stated.

This document is a *fact-first* snapshot of:

1) what exists today (with references to tests/fixtures),
2) what is missing for “modern production language” maturity,
3) the prioritized gap list (feeds the Active Tracker (above)).

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

- `docs/AVM.md#avm-plugins-nesting-obc-first-ios-safe-rolling`

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
  - See also `docs/LANGUAGE.md`
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
  - Real-hardware x86_64 run validation is opt-in (Win11, WSL2 optional): `docs/TOOLCHAIN_PLATFORMS.md`
    - Rolling note (2026-02-13): the current remote host has Win11 online, but WSL2 is not installed/enabled yet.
    - Tier‑1 TIME substrate (Linux+Windows): `tests/native/test_time_suite.oren` (expects `oren_sleep_ms` + wall/mono time to work without libc)
    - Tier‑1 RNG substrate (Linux+Windows): `tests/native/test_quick_integration_native.oren` asserts `oren_getentropy` works (and Tier‑1 WebSocket uses it for client key + masking).
    - Tier‑1 parity fixture (closures + varargs): `tests/fixtures/tier1_native_lambda_varargs_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh --targets x64-win-tier1` / `x64-wsl-tier1` with `--tier1-src ...`)
    - Tier‑1 parity fixture (map dynamic key-kind on empty maps): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 gate via `scripts/verify_native_matrix.sh` Tier‑1 targets; see `docs/TOOLCHAIN_PLATFORMS.md`)
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
  - Design: `docs/LANGUAGE.md`
- **Remove native map “key kind” heuristics**
  - Any heuristic that guesses key types (e.g. based on numeric range) is a semantics risk.
  - Direction: a tagged value model or explicit key typing at IR level.
  - Rolling status:
    - Native backends (arm64 + x64): “magic numeric range” key typing is removed from compiler lowering/codegen decisions; when key kind is not inferable statically, native codegen can perform a runtime dispatch via tracking metadata (`oren_find_node(key).kind == STRING` → string key; else treat as int key). The native runtime still keeps a small-int fast path (`key < 4096`) to avoid allocation-list scans; this is a bring-up optimization, not a semantics rule. Tagged values remain the full fix.
    - x64 native now also propagates `recv_kind` on `Index` so codegen can avoid dynamic LIST/MAP dispatch when the receiver kind is known (still validates runtime magic; remaining unknown cases need a principled representation)
    - Tier‑1 x86_64 evidence (empty map + dynamic string key): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 Tier‑1 gate; see `docs/TOOLCHAIN_PLATFORMS.md`)
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
        - Loopback-only TCP/UDP + HTTP GET + WebSocket echo are covered on Win11 (WSL2 optional) via `tests/native/test_net_suite.oren`, `tests/native/test_http_get_loopback.oren`, `tests/native/test_ws_echo_loopback.oren` (see `docs/TOOLCHAIN_PLATFORMS.md`).
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
    - Track: `docs/STATUS.md` (P0.1–P0.3), `docs/COMPILER_BACKENDS.md#native-backend-overview`.

  - **Async IO + scheduler integration (planned)**
    - Today, NET fd waits are runtime helpers that block OS threads (`lib/runtime_native/240_tcp.oren`).
    - The production direction is a native scheduler + netpoller so IO readiness can feed channels and `select`.
    - Track: `docs/STATUS.md` (P1.3), `docs/RUNTIME.md`.

### P1: Tooling quality (modern compiler UX)

- **Modern CLI ergonomics (mostly done; polish remains)**
  - The Stage1 compiler (`./oren`) already uses a structured subcommand model backed by `std:argparse`:
    - `oren build|emit-c|meta|dump|scan|completion`
    - `oren --help` and `oren <cmd> --help`
    - machine-readable help: `oren --help=json`
    - completion scripts: `oren completion bash|zsh` (see `docs/TOOLCHAIN_PLATFORMS.md`)
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
  - Track: `docs/STATUS.md` (P0.8).

### P1: Stdlib maturity

- **Stdlib should track current grammar**
  - Avoid legacy syntax drift: if/else forms, match forms, for-in syntax, etc.
  - The repo enforces audits via Makefile + direct test programs; expand as grammar stabilizes.

### P2: Distribution and “production runtime” story

- **Stdlib resolution/distribution**
  - “User friendly imports” vs embedding vs precompiled `.obc` bundles needs a single
    coherent model that works for both native and AVM.
  - Related docs: `docs/RUNTIME.md`, `docs/AVM.md`

- **Packages + registry + reproducible builds**
  - For production, the language needs a coherent “package → build artifact” story:
    - module naming / resolution,
    - lockfiles, hashes, deterministic builds,
    - support for precompiled `.obc` libraries (OBX exports/relocs) in AVM.
  - Track: `docs/AVM.md`, `docs/TOOLCHAIN_PLATFORMS.md`, `docs/STATUS.md` (P1.2, P1.4).

- **Trust / signing / update channels for multiverse**
  - Multiverse implies “code moves between universes”; production needs a root-of-trust:
    - signed `.obc` artifacts, cert chains, key rotation,
    - developer identity / org delegation model,
    - update and patch workflows that do not break determinism.
  - Track: `docs/AVM.md`, `docs/AVM.md`, `docs/STATUS.md` (P1.1).

## How to Use This Doc

- When a new feature lands, add a **test/fixture reference** here (it becomes living spec).
- When an incompatibility is introduced, record it as a **rolling limitation** and link the
  TODO item that will remove it.

## Oren Language Feature Matrix (Rolling, AI-Friendly)

**Last updated:** 2026-02-13  

This document is a **quick index** for AI agents and maintainers:

- what a feature is,
- whether it is **Implemented / Rolling / Planned**,
- where the implementation lives (compiler/runtime),
- where the behavior is validated (fixtures/examples).

It complements:

- `docs/LANGUAGE.md` (how to write Oren today),
- `docs/LANGUAGE.md` (grammar + semantics),
- `docs/STATUS.md` (production gaps, evidence-backed).

Status legend:

- **Implemented**: supported by the Stage1 compiler and used in current code.
- **Rolling**: supported, but semantics/ABI may still evolve (must stay regression-tested).
- **Planned**: design intent; track via `docs/STATUS.md`.

Remote x86_64 evidence:

- “remote x86_64 Tier‑1 gate” means the fixture is validated on real x86_64 hardware (Win11, WSL2 optional)
  via `scripts/verify_native_matrix.sh` (see `docs/TOOLCHAIN_PLATFORMS.md`).

## Core language

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Modules + `import` | Rolling | Parser: `lib/compiler/parser_parse/**`; Linking: `lib/compiler/compiler/020_modules_linking.oren` | Examples: `examples/module_app.oren`; Tests: `tests/modules/` |
| FFI symbols (`ffi name`) | Rolling (native: macOS+Windows; linux x64+arm64 requires a link dep via `--link` or `@ffi.link`; linux w/out link dep panics-on-call) | Parser surface: `lib/compiler/parser_parse/**`; Native emit: arm64 Mach‑O stubs (`lib/compiler/arm64_macho.oren`), x64 Windows lazy stubs (`lib/compiler/x64_native_program/072_ffi.oren` + `lib/compiler/x64_pe.oren`); Linux dynamic ELF (`lib/compiler/x64_elf.oren`, `lib/compiler/arm64_elf.oren`) + `dlsym`-based resolver (`lib/compiler/x64_native_program/072_ffi.oren`, `lib/compiler/arm64_elf.oren`) | Examples: `examples/ffi_test.oren` (uses `@cfg` + `@ffi.link`/`@ffi.dll` so it runs under `make examples-test`); Windows smoke: `tests/native/ffi_windows_kernel32.oren` (direct `ffi`); Stdlib wrapper evidence: Windows `lib/std/ffi/kernel32.oren`, `lib/std/ffi/iphlpapi.oren`, `lib/std/ffi/secur32.oren`, `lib/std/ffi/crypt32.oren` + `tests/native/test_std_ffi_kernel32_smoke.oren`; Linux `lib/std/ffi/libdl.oren` (used by `std:net/tls_linux_openssl` for OpenSSL lazy load); Linux OK contract (link dep via attr): `tests/native/ffi_linux_strlen_ok.oren` (arm64-linux docker + x64-linux remote WSL2 via `scripts/verify_native_matrix.sh` (stage1 + stage2)); Linux panic contract (arm64 + x64 w/out link dep): `tests/native/ffi_linux_unresolved_panics.oren` |
| Conditional compilation (`@cfg(...)`, `@debug`/`@release`, `debug { ... }`/`release { ... }`, `dbg(...)`/`dprint(...)` statement + single‑arg expression forms) | Rolling | Attr normalization: `lib/compiler/parser_core.oren`; Pass: `lib/compiler/cfg_lowering.oren` (filters declarations + block statements; wired in `lib/compiler/compiler/020_modules_linking.oren`) + `lib/compiler/debug_sugar.oren` | Fixtures: `tests/native/cfg_os_select.oren` (compiled by `scripts/verify_native_x64_compile_only.sh` for x64-linux + x64-windows; stage1 + stage2), debug/release selector + shorthand + debug print sugar + debug/release block via `tests/native/test_quick_integration_native.oren` (`test_cfg_debug_release`) |
| Top-level statements + entry | Rolling | Native entry stubs: `lib/compiler/arm64_*`, `lib/compiler/x64_*`; Bytecode entry: `lib/compiler/codegen_bytecode/030_tail.oren`; C entry: `lib/compiler/transpiler.oren` | Tier‑1 x86_64 remote fixture (no `fn main`): `tests/fixtures/tier1_native_no_main_top_level_only.oren` (remote x86_64 Tier‑1 gate) |
| Top-level globals (`var` at module scope) | Rolling | x86_64 native stores globals as 8-byte slots in the appended data blob and runs non-constant initializers in a synthesized `__top_level__` (`lib/compiler/x64_native_program/090_program_entry.oren`, loads: `lib/compiler/x64_native_program/040_emit_expr.oren`, stores: `lib/compiler/x64_native_program/060_emit_ops.oren`) | Tier‑1 x86_64 remote fixture: `tests/fixtures/tier1_native_globals_top_level_main.oren` (remote x86_64 Tier‑1 gate) |
| Program termination (`exit`) | Rolling | x86_64 native lowers `exit(...)` to `sys_exit` (`lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren`); other backends may still treat `main` return as advisory | Prefer `exit(code)` for portability; Tier‑1 x86_64 evidence: `tests/fixtures/tier1_native_globals_top_level_main.oren` (remote x86_64 Tier‑1 gate) |
| `print(...)` statement | Rolling | Surface: statement-form `print(...)` call; native lowering routes through runtime helpers for capsule-safe output and parity: x86_64 statement analysis lowers to `oren_print*` (`lib/compiler/x64_native_program/020_cond_analyze.oren`); runtime implementation: `lib/runtime_native/130_printing.oren` | Tier‑1 x86_64 remote fixture (non-literal arg): `tests/fixtures/tier1_native_smoke_main.oren` (remote x86_64 Tier‑1 gate) |
| `fn` + named functions | Implemented | Parser + lowering + all backends | Everywhere; compile pipeline: `lib/compiler/compiler/040_build_pipeline.oren` |
| Function values + lambdas | Rolling | C backend: `lib/compiler/transpiler.oren` (closures + wrappers); Native runtime: `lib/runtime_native/120_first_class_fn.oren`; Bytecode: `lib/compiler/codegen_bytecode/**` | AVM: `tests/avm/test_closure_fn_values.oren` |
| Varargs (`...rest`) + spread calls | Rolling | Parser marks `is_varargs`; Tier‑1 native uses the uniform callable ABI (`fn_obj` + `args_list`): x86_64 lowers spread via `oren_call_obj_spread` and varargs named calls via `__oren_fnwrap_*` wrappers (`lib/compiler/x64_native_program/044_emit_call_expr.oren`, runtime helper: `lib/runtime_native/130_printing.oren`) | Tier‑1 closure parity: `tests/fixtures/tier1_native_lambda_varargs_main.oren` (remote x86_64 Tier‑1 gate) |
| Control flow: `if/else`, `while`, `for`, `switch/case` | Implemented/Rolling | Parser + lowering; `for x in ...` is sugar in lowering | Example: `examples/hello.oren`; Tests: `tests/native/` + `tests/avm/test_switch.oren` |
| `match` | Rolling | Parser contextual keyword + lowering into deterministic control flow | Tests: `tests/modules/test_match_enum.oren` |
| `enum` | Rolling | Lowered as tagged-map constructors | Tests: `tests/modules/test_match_enum.oren`; Spec: `docs/LANGUAGE.md` “enum/match” section |

## Types and “static-first” constructs

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Type annotations (syntax) | Rolling | Parser supports `: type_name`; lowering uses hints | Manual/spec: type annotation sections |
| Traits + impl blocks (static-first) | Rolling | Parser: `lib/compiler/parser_parse/**`; Lowering: impl rewrite passes under `lib/compiler/**` | Tests: `tests/modules/test_trait_*.oren` |
| `dyn` / runtime trait objects | Planned | Design docs (static-first + opt-in runtime polymorphism) | Track: `docs/STATUS.md` |
| Floats (`f64` container) + casts (`f32/f64/i64/u64/bool`) + comparisons + **bit-casts** (`u32↔f32`, `u64↔f64`) | Rolling | Front-end cast lowering: `lib/compiler/type_ann_lowering.oren`; Bytecode: `lib/compiler/codegen_bytecode/**`; C runtime helpers: `lib/runtime/050_io_misc.inc`; Native: arm64 `lib/compiler/arm64_native_expr/**`, x86_64 `lib/compiler/x64_native_program/047_emit_float_intrinsics.oren` + `lib/compiler/x64_native_program/050_emit_cmp_labels.oren` + `lib/compiler/x64_native_program/040_emit_expr.oren` (bit-cast intrinsics) | Tier‑1 x86_64 fixture: `tests/fixtures/tier1_native_float_ops_main.oren` (remote x86_64 Tier‑1 gate); SIMD suite exercises float kernels: `tests/native/test_simd_suite.oren` |

## Containers and performance

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| List literal `[]` and indexing `xs[i]` | Rolling | Shared lowering + backend intrinsics; C uses runtime helpers | Tests: `tests/native/fixtures/**`; Docs: `docs/RUNTIME.md` |
| List `push/len` as operations (no wrapper overhead) | Rolling | Lowering: `lib/compiler/impl_lowering.oren`; Intrinsics: `oren_list_len`, `oren_list_push` (returns `nil`) | Track: `docs/STATUS.md` (P0.4); Internals: `docs/COMPILER_BACKENDS.md` |
| `slice_view` / `clone` / `slice_copy` | Rolling | Stdlib: `lib/std/list.oren` (`clone`, `slice_copy`, `slice_view`) | Manual: `docs/LANGUAGE.md` (List helpers); Track: `docs/STATUS.md` (P0.4) |
| Map literal `{}` and indexing `m[k]` / `m[k]=v` | Rolling | Parser + lowering; C/AVM: dynamic keys; Native: key-kind must be deterministic | Tests: `tests/native/test_integration_suite.oren`; Manual: `docs/LANGUAGE.md` “Maps” |
| Map dynamic string keys on empty maps (Tier‑1 x86_64) | Rolling | x64 native uses tracked-allocation metadata for key-kind inference; no syntax heuristics | Tier‑1 remote fixture: `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 Tier‑1 gate) |
| Map get with dynamic string key (Tier‑1 x86_64) | Rolling | x64 native map lookup must infer key kind from value metadata and perform string compare when needed | Tier‑1 remote fixture: `tests/fixtures/tier1_native_map_get_dynamic_key_main.oren` (remote x86_64 Tier‑1 gate) |
| Deterministic map iteration | Rolling | C runtime keeps keys sorted; native runtime sorts lazily on demand; x86_64 native runs with **full native runtime injection** (Tier‑1 mandatory) | Tests: `tests/native/test_integration_suite.oren` (map iteration); Tier‑1 x86_64: `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote x86_64 Tier‑1 gate); Runtime: `lib/runtime_native/160_iteration.oren`, `lib/runtime_native/130_printing.oren` |
| Typed map ops (`oren_map_get_str/int`, `oren_map_set_str/int`) | Rolling | Native runtime: `lib/runtime_native/130_printing.oren`; C runtime: `lib/runtime/040_lists_maps.inc`; Native lowering selects typed ops when key kind is known | Used by stdlib codecs: `lib/std/json.oren`, `lib/std/yaml.oren`, `lib/std/cbor.oren` |
| Typed buffers `[]i32`, `[]f64`, ... | Rolling | Stdlib: `lib/std/buffer.oren` + runtime helpers | Docs: `docs/STATUS.md` |
| Typed buffers `[]u8` in AVM (bytes-backed) + buffer views | Rolling | AVM core natives: `lib/avm/avm_native.inc` (`oren_u8_buf_new`, `oren_buf_*_u8`, `oren_iter_next` view handling); Bytecode lowering: `lib/compiler/codegen_bytecode/010_codegen_a.oren` | AVM test: `tests/avm/test_u8_buf_views.oren` |
| Typed buffers Tier‑1 native smoke (x86_64 Linux/Windows) | Rolling | Native runtime: `lib/runtime_native/typed_buffers/**`; x64 native: typed-buffer ops are **runtime-defined** (same source bundle as arm64) and lowered via generic runtime calls from `lib/compiler/x64_native_program/040_emit_expr.oren` (no x64-only typed-buffer intrinsics). | Tier‑1 remote fixture: `tests/fixtures/tier1_native_smoke_main.oren` (includes typed buffer checks) (remote x86_64 Tier‑1 gate) |
| `for x in buf` + buffer views (`[buf,off,len]`, `[buf,off,len,stride]`) on Tier‑1 x86_64 | Rolling | Iterator semantics are defined in the injected native runtime (`lib/runtime_native/160_iteration.oren`); x64 native lowers iteration via the runtime (no x64-only `oren_iter_next` bring-up intrinsic). | Tier‑1 remote fixture: `tests/fixtures/tier1_native_smoke_main.oren` (includes buf + view iteration checks) (remote x86_64 Tier‑1 gate) |
| Strings: concat (`+`), `len`, `slice` (Tier‑1 x86_64) | Rolling | C backend: string `+` via `oren_add` (`lib/runtime/030_ops_compare.inc`), plus `oren_string_len`/`oren_string_slice`; Native backend: `string_concat`/`oren_string_len`/`oren_string_slice`/`oren_string_eq` (`lib/runtime_native/150_strings.oren`, `lib/runtime_native/160_iteration.oren`); x64 native routes string semantics through the injected runtime (helper emitters live under `lib/compiler/x64_native_program/**`). | Tier‑1 remote fixture: `tests/fixtures/tier1_native_string_ops_main.oren` (and `tests/fixtures/tier1_native_smoke_main.oren`) (remote x86_64 Tier‑1 gate) |

## Runtime model (determinism, safety, AVM)

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Deterministic diagnostics (`OREN_DIAG`) | Rolling | Runtime + emit points (native/C) | Fixtures: `tests/native/fixtures/diag_fail.oren` |
| Runtime reflection helpers (`oren_type_tag`, `oren_type_name`) | Rolling (native+C; AVM planned) | C runtime: `lib/runtime/040_lists_maps.inc`; Native runtime: `lib/runtime_native/130_printing.oren` | Native quick integration: `tests/native/test_quick_integration_native.oren` (`test_type_tag_varargs`) |
| Native stack traces (`stack_trace`, `resolve_symbol`) on Tier‑1 x86_64 | Rolling | Runtime: `lib/runtime_native/000_prelude_sys.oren` (`stack_trace`); x64 native: `resolve_symbol` intrinsic over the embedded symtab (`lib/compiler/x64_native_program/043_emit_stack_intrinsics.oren`, reserved by `lib/compiler/x64_native_program/010_data_io.oren` `_data_reserve_symtab`) | Tier‑1 remote fixture: `tests/fixtures/tier1_native_stacktrace_main.oren` (remote x86_64 Tier‑1 gate) |
| Stack safety (call depth guard) | Rolling | AVM flag; C env; native guards | Docs: `docs/LANGUAGE.md`; fixtures: `tests/native/fixtures/call_depth_overflow.oren` |
| Tail-call optimization | Rolling (subset) | Lowering/codegen passes | Docs: `docs/LANGUAGE.md` |
| Native runtime injection (`lib/runtime_native.oren` expanded includes) | Rolling | Shared include expander: `lib/compiler/native_runtime_inject.oren`; arm64 native injects by default: `lib/compiler/arm64_native_program.oren`; x86_64 native injects by default: `lib/compiler/x64_native_program/090_program_entry.oren` (capsule builds use `lib/runtime_native_capsule.oren`; DCE keeps `@oren.keep` functions and treats `native_capsule_sys_*` as an internal ABI surface so fixup-only symbols are not dropped) | Tier‑1 x86_64 gate: `scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1` |
| Process args (`oren_args()`) on Tier‑1 native | Rolling | Runtime globals: `lib/runtime_native/020_fork_runtime_init.oren` (`native_runtime_set_args`); consumer: `lib/runtime_native/210_args.oren`; x86_64 entry stubs populate argc/argv (Linux: SysV entry stack; Windows: synthesized from `GetCommandLineW` + `CommandLineToArgvW` + UTF‑8 conversion) in `lib/compiler/x64_native_program/090_program_entry.oren` | Tier‑1 remote fixture: `tests/fixtures/tier1_native_args_main.oren` (remote x86_64 Tier‑1 gate) |
| TIME substrate (`oren_sleep_ms`, `oren_time_unix_ns`, `oren_time_mono_raw`) on Tier‑1 native | Rolling | Runtime: `lib/runtime_native/100_time.oren`; x86_64 syscall lowering: Linux `lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren`, Windows `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren` + PE IAT: `lib/compiler/x64_pe.oren` | Suites: `tests/native/test_time_suite.oren`; remote Win11 validation path: `docs/TOOLCHAIN_PLATFORMS.md` |
| RNG substrate (OS entropy: `oren_getentropy`) + `std:crypto/rand` | Rolling | Native runtime: `lib/runtime_native/102_entropy.oren` (`@cap.requires(domain="RNG")`); C runtime: `lib/runtime/025_entropy.inc`; Stdlib wrapper: `lib/std/crypto/rand.oren` | Native quick integration asserts `oren_getentropy` works: `tests/native/test_quick_integration_native.oren`. WebSocket uses it for `Sec-WebSocket-Key` + masking: `lib/std/net/ws.oren` (exercised by `tests/native/test_ws_echo_loopback.oren`, Tier‑1 NET gate: `scripts/verify_native_net_matrix.sh`). |
| NET substrate (TCP/UDP + fd wait) on Tier‑1 native | Rolling | Runtime: `lib/runtime_native/240_tcp.oren`, `lib/runtime_native/250_udp.oren` (includes `oren_udp_recvfrom_into_with_addr` for src sockaddr capture); x86_64 syscall lowering: Linux `lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren`; Windows `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net.oren` + PE IAT: `lib/compiler/x64_pe.oren` | Suite: `tests/native/test_net_suite.oren`; Tier‑1 cross‑arch gate: `scripts/verify_native_net_matrix.sh` (see `docs/TOOLCHAIN_PLATFORMS.md`) |
| DNS v0 stdlib (UDP A query; explicit server + best-effort system default resolver) | Rolling | Stdlib: `lib/std/net/dns.oren` (built on `std:net/udp`, OS entropy via `std:crypto/rand` for txid); default resolver selection reads `OREN_DNS_SERVER` when set, else: POSIX parses `/etc/resolv.conf` (IPv4 only), Windows uses iphlpapi `GetNetworkParams` (IPv4 only); no TCP fallback, no AAAA yet | Loopback regression: `tests/native/test_dns_loopback.oren`; Tier‑1 cross‑arch gate: `scripts/verify_native_net_matrix.sh` |
| TLS v0 stdlib (secure stream wrapper; PKCS#12 server; client opts for pinning) | Rolling (macOS/Linux/Windows) | Primary implementation: `lib/std/net/tls.oren`; providers: macOS `lib/std/net/tls_macos_securetransport.oren` (Security.framework), Linux `lib/std/net/tls_linux_openssl.oren` (OpenSSL), Windows `lib/std/net/tls_windows_schannel.oren` (Schannel/SSPI). Convenience facade: `lib/std/crypto/tls.oren` (alias-layer over `std:net/tls` while the TLS crypto-core split is implemented). Surface: `tls.connect`, `tls.wrap_client`, `tls.wrap_server_pkcs12`, `tls.read_into`, `tls.write_from`, `tls.close`, `tls.peer_cert_sha256_hex`, `tls.negotiated_alpn`. See `docs/RUNTIME.md`. | Loopback regression: `tests/native/test_tls_loopback.oren`; HTTPS/WSS use the same TLS substrate: `tests/native/test_https_get_loopback.oren`, `tests/native/test_wss_echo_loopback.oren` |
| HTTP/1.1 GET stdlib (`http://` + `https://` when TLS available; Content-Length + chunked; IPv4 + hostname via DNS A) | Rolling | Stdlib: `lib/std/net/http.oren` (built on `std:net/tcp`); hostname support via explicit resolver injection (`http.get_text_resolver` / `http.get_response_resolver`) or system `dns.default_resolver`; structured response API returns `{status, headers, body}`; `https://` support is enabled via `std:net/tls` on macOS/Linux/Windows (see `docs/RUNTIME.md`). | Loopback regression: `tests/native/test_http_get_loopback.oren` (hostname + status/header assertions) and `tests/native/test_https_get_loopback.oren` (TLS/HTTPS loopback); Tier‑1 cross‑arch gate: `scripts/verify_native_net_matrix.sh` |
| HTTP/2 (framing core + ALPN `h2`; HPACK/streams planned) | Rolling (framing + HPACK encode/decode v0) | Framing core: `lib/std/net/http2.oren` (preface + frame header encode/decode + SETTINGS payload codec). Loopback framing smoke: `tests/native/test_http2_preface_loopback.oren` (preface + SETTINGS/ACK + PING/ACK). HPACK core: `lib/std/net/hpack.oren` (static+dynamic tables, Huffman encode/decode, header block encode/decode). Minimal client facade: `lib/std/net/http2_client.oren` (handshake + single-stream request/response on top of TLS+framing+HPACK). HTTP/2 request/response loopback: `tests/native/test_http2_headers_loopback.oren` (client uses `std:net/http2_client`; server uses `std:net/http2` primitives; covers HEADERS + CONTINUATION + DATA over TLS; includes SETTINGS payload + SETTINGS/ACK). Stream muxing is still planned and tracked in `docs/STATUS.md`. | Tier‑1 cross‑arch gate: `scripts/verify_native_net_matrix.sh` runs the HTTP/2 fixtures (stage1 + stage2; macOS+Linux+Win11 (WSL2 optional)). |
| WebSocket v0 stdlib (`ws://` + `wss://` when TLS available; masked text frames; ping/pong; hostname via DNS A) | Rolling | Stdlib: `lib/std/net/ws.oren` (built on `std:net/tcp`, `std:crypto/sha1`, `std:encoding/base64`, `std:crypto/rand`); hostname support via explicit resolver injection (`ws.connect_resolver`) or POSIX `dns.default_resolver`; `wss://` support is enabled via `std:net/tls` on macOS/Linux/Windows (see `docs/RUNTIME.md`). | Loopback regression: `tests/native/test_ws_echo_loopback.oren` (ws://, includes hostname path + ping/pong) and `tests/native/test_wss_echo_loopback.oren` (wss:// loopback); Tier‑1 cross‑arch gate: `scripts/verify_native_net_matrix.sh` |
| PROC substrate (`oren_proc_spawn`, `oren_system`) on Tier‑1 native | Rolling | Runtime: `lib/runtime_native/260_threads.oren`; POSIX: `fork/execve/wait4`; Windows: `sys_win_createprocess` lowered by `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_proc.oren` + PE IAT: `lib/compiler/x64_pe.oren` | POSIX coverage: native integration suite exercises `oren_system_timeout` (`tests/native/test_integration_suite.oren`). Windows proof (Tier‑1 remote gate): `scripts/verify_native_matrix.sh --targets x64-win-tier1` runs `tests/fixtures/tier1_native_smoke_main.oren` on Win11 (WSL2 optional) (fixture calls `oren_system("echo tier1 smoke proc ok")`). |
| `spawn` + `oren_join(_timeout)` on Tier‑1 native | Rolling | Runtime join: `lib/runtime_native/260_threads.oren`; Spawn: `oren_spawn_call_list` in `lib/runtime_native/120_first_class_fn.oren` prefers green tasks (N:1) and falls back when `OREN_NO_GREEN=1` (POSIX: fork+pipe; Windows: runtime-owned OS thread). x86_64 spawn lowering routes through the runtime helper (`lib/compiler/x64_native_program/044_emit_call_expr.oren`). | Native suites: `tests/native/test_integration_suite.oren` (`test_spawn_join_timeout`, `test_spawn_join_timeout_probe_zero`) + `tests/native/test_smoke_suite.oren` (spawn/join). Tier‑1 x86_64 remote fixture: `tests/fixtures/tier1_native_spawn_join_main.oren` (remote x86_64 Tier‑1 gate). |
| Atomics (`atomic_add`, `atomic_cas`) | Rolling | ARM64: `lib/compiler/arm64_native_expr/**` (LL/SC lowering); x86_64: `lib/compiler/x64_native_program/040_emit_expr.oren` (LOCK XADD / CMPXCHG) | Native tests: `tests/native/test_atomics.oren`; Tier‑1 x86_64 fixture: `tests/fixtures/tier1_native_atomics_main.oren` (remote x86_64 Tier‑1 gate) |
| Channels (`oren_new_channel`, `oren_chan_send`, `oren_chan_recv`) | Rolling | AVM: opcodes in `lib/avm/avm_vm.c` + lowering in `lib/compiler/codegen_bytecode/010_codegen_a.oren`; Native: macOS/Linux pipe channels (`lib/runtime_native/010_channels_globals_consts.oren`), Windows mem channels (`lib/runtime_native/011_channels_mem.oren`) | Native evidence: `tests/native/test_integration_suite.oren` (`test_select_primitives`), plus basic channel smoke: `tests/native/test_channel.oren`. AVM evidence: `tests/avm/test_smoke_suite.oren` |
| Select (`oren_select_recv`, `oren_select`) | Rolling (AVM + native) | AVM: `SELECT_RECV`/`SELECT` opcodes (`lib/avm/avm_vm.c`); Native: POSIX kqueue/epoll select over pipe channels + Windows select over mem channels (`lib/runtime_native/245_select.oren`) | Native evidence: `tests/native/test_integration_suite.oren` (`test_select_primitives`). AVM evidence: `tests/avm/test_smoke_suite.oren` |
| Capsule model (native capability gating) | Rolling | Native runtime + syscall emit constraints | Fixtures: `tests/native/fixtures/capsule_*` |
| AVM execution of `.obc` | Rolling | Runtime: `lib/avm/**`; codegen: `lib/compiler/codegen_bytecode/**` | Examples: `examples/avm_*`; Tests: `tests/avm/**` |
| Capability domains (CORE/FS/TIME/RNG/NET/PROC/EXIT/ENV/AVM) | Rolling | `.obc` verifier + dispatch: `lib/avm/avm_native.inc`, `lib/avm/main.c` | Spec: `docs/AVM.md` (domains vs backends); fixtures cover capsule constraints |
| VirtualFS backend (`vfs`) for deterministic simulation | Rolling | Backend selection + fixtures: `lib/avm/main.c`; VFS ops + snapshot codec: `lib/avm/avm_native.inc` | Spec: `docs/AVM.md` (VirtualFS / `AVMVFS01`) |
| VirtualPROC backend (`vproc`) for deterministic subprocess stubs | Rolling | Backend selection + fixtures: `lib/avm/main.c` | Spec: `docs/AVM.md` (`AVM_PROC_BACKEND=vproc`, `AVM_PROC_FIXTURES_HEX=...`) |
| VirtualNET backend (`vnet`) for deterministic network stubs | Rolling | Backend selection + fixtures: `lib/avm/main.c` | Spec: `docs/AVM.md` (`AVM_NET_BACKEND=vnet`, `AVM_NET_FIXTURES_HEX=...`) |
| `.obc` signature verification (`--require-sig`) | Rolling | Sig verifier: `lib/avm/avm_sig.c` | Spec: `docs/AVM.md`; tools: `cmd/orensign/main.go` |
| Delegated signing via embedded cert chain (`OREN_CERTS`) | Rolling | Cert parser: `lib/avm/avm_cert.c`; chain verify: `lib/avm/avm_sig.c` | Docs: `docs/AVM.md` |
| Strict verification mode (`--verify-strict`) | Rolling | CLI + verifier gating: `lib/avm/main.c` | Spec: `docs/AVM.md` (strict verification); help: `lib/avm/avm_help.inc` |
| Nested universes (“AVM in AVM” / multiverse host service) | Rolling (gated) | AVM domain dispatch: `lib/avm/avm_native.inc` (Domain 8: AVM) | Docs: `docs/AVM.md#avm-in-avm-multiverse-design-nested-virtual-universes` (model + constraints) |
| Swarm / consensus outcome hashing | Rolling (in progress) | Job hash + result selection: `lib/avm/avm_state.inc`, `lib/avm/avm.h` | Docs: `docs/AVM.md#avm-swarm-consensus-agent-mobility-design-validation` |
| Compiler-in-AVM | Planned | Bytecode compiler + AVM host interface constraints | Track: `docs/STATUS.md` (P0.10), `docs/TOOLCHAIN_PLATFORMS.md` |

## HPC / SIMD (Tier‑1 HPC: arm64 NEON now, x86_64 SSE/AVX next)

| Feature | Status | Where (impl) | Evidence / notes |
|---|---|---|---|
| Typed buffers (`[]i32`, `[]f32`, `[]f64`, …) | Rolling | Stdlib/runtime surfaces under `lib/std/buffer.oren` + `lib/runtime_native/typed_buffers/**` | Manual: `docs/LANGUAGE.md` (Typed buffers section) |
| Native SIMD toggle | Rolling | Native runtime parses `OREN_ENABLE_SIMD` / `OREN_NO_SIMD`: `lib/runtime_native/040_capsule_core.oren` | Exercise via `tests/native/test_simd_suite.oren` (run once with `OREN_NO_SIMD=1`, then with `OREN_ENABLE_SIMD=1`, and compare stable outputs) |
| SIMD determinism contract (scalar is authoritative) | Rolling | Runtime dispatch chooses scalar vs SIMD; tests enforce equivalence | Determinism guard: SIMD must remain bit-identical to scalar for covered kernels; reduction order is fixed (no reassociation). Primary suite: `tests/native/test_simd_suite.oren` |
| SIMD intrinsics (arm64 NEON) | Rolling (arm64 macOS/Linux); Planned (x86_64) | Native arm64 codegen lowers `simd_*` intrinsics: `lib/compiler/arm64_native_expr/**` | Spec lists the intrinsic family: `docs/LANGUAGE.md` (“Native Backend Intrinsics”) |
| SIMD-backed typed-buffer kernels (dot/axpy/gemm/etc.) | Rolling (arm64 macOS/Linux); Planned (x86_64) | Runtime dispatch in `lib/runtime_native/typed_buffers/**` + arm64 intrinsic lowering; scalar fallbacks exist for all `simd_*_ptr` entrypoints in `lib/runtime_native/typed_buffers/005_simd_scalar_fallback.oren` | Opt-in via `OREN_ENABLE_SIMD=1` (or disable with `OREN_NO_SIMD=1`). Must remain deterministic. |
| x86_64 SIMD plan (SSE2 baseline, AVX2 optional) | Planned | x64 native codegen + runtime kernel implementations | Track under `docs/STATUS.md` (HPC item) until we have an x86_64 SIMD parity suite (scalar vs SIMD) and stable feature detection for Linux+Windows |
| AVM SIMD (NEON) | Planned / Rolling (gated) | Build/runtime gating exists (`AVM_ENABLE_SIMD=1`, arm64 NEON): `lib/avm/avm_native.c`, `lib/avm/main.c` | Design constraints: `docs/AVM.md#avm-neon-mapping-plan-arm64-no-jit-first` (determinism-first); not treated as mature until fully covered by AVM tests |
| HPC roadmap (math/linalg + perf harness) | Rolling (in progress) | Design docs: `docs/STATUS.md`, typed-buffer + linalg layers | Tracker: `docs/STATUS.md` (P1.3) |

## Tooling / ecosystem

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| `oren` CLI subcommands + completion | Rolling | CLI: `lib/compiler/compiler/000_prelude.oren`; completion docs | Docs: `docs/TOOLCHAIN_PLATFORMS.md` |
| Package registry (`oren-packages`) integration | Planned | Module resolution + lockfiles + reproducible builds | Track: `docs/STATUS.md` |

## Core System Plans: Type System, Syscall-First Runtime, and HPC

**Status:** Rolling (consolidated plans)
**Last updated:** 2026-02-19

This section consolidates the prior plan docs into one place to reduce drift and keep the highest‑leverage requirements together.

---

## 1) Type System Plan (Rolling -> Production)

This is design guidance, not a frozen spec.

Oren today is semantically typed at runtime (tagged values), but it lacks a production-grade static
layer needed for:

- syscall-first servers (no accidental allocations or conversions)
- HPC + SIMD-friendly code (explicit widths, predictable layout)
- FFI and packet parsing (endianness and packed views)
- future self-hosting (compiler and AVM in `.oren`)

The strategy is gradual typing: keep v0 running while enabling incremental compile-time checks.

### Non-negotiables (constraints)

1) Rolling ABI / rolling language until v1 stabilizes.
2) Syscall-first native runtime (no libc shims).
3) Deterministic semantics (especially AVM and replay).
4) Casting must be cheap (compiler-lowered rewrites or intrinsics, not user calls).

### Current state (v0 reality)

- Runtime values are tagged: `nil`, `bool`, `int`, `float`, heap/object, etc.
- Many operations are dynamically typed and error on mismatch.

Type annotations exist today:

- locals: `var x: u8 = ...`
- fields: `struct H { len: u16be }`
- fn params/returns: `fn f(x: u8): u8 { ... }`

In v0 these annotations lower to boundary normalization (wrap/truncate for ints, deterministic
rounding for `f32`), giving cross-backend meaning without full static typing.

Cast sugar today:

- `u8(x)`, `i32(x)`, `f32(x)`, `bool(x)`, endian spellings like `u16be(x)`
- Lowered into deterministic casts or intrinsics (`oren_f32_round`, `oren_bool_norm`, `oren_trunc_int`)
- Native backend can inline these (no call overhead)

`oren_trunc_int(x)` semantics (v0, deterministic):

- `int` input: identity
- `float` input: truncate toward zero, then clamp special values
  - `NaN` -> `0`
  - `+inf`/overflow -> `INT64_MAX`
  - `-inf`/overflow -> `INT64_MIN`

### Target model: static when you want it

We support both:

1) Compile-time polymorphism (monomorphized generics)
2) Runtime polymorphism (trait/protocol objects)

Compile-time is for performance; runtime is for heterogeneous containers and tooling.

#### Primitive width types are language tokens

Core tokens:

- signed: `i8 i16 i32 i64 i128 isize`
- unsigned: `u8 u16 u32 u64 u128 usize`
- floats: `f32 f64`
- `bool`, `nil`, `string`, `bytes`

Endianness is a type-level wrapper, not a separate primitive kind:

- `u16be`, `u16le`, etc. are surface spellings that desugar to view/parse rules.

#### Packed structs are views (zero-copy)

For packet parsing and syscall-first networking:

- `@pack struct Header { ... }` defines a layout view
- accessors read/write from `bytes` or `ptr` without allocations

#### Traits/protocols: compile-time + runtime

We want primitives to implement traits (Eq, Ord, Hash, Add, BitAnd, ...).

Plan:

- compiler-provided blanket impls for builtins (e.g., `impl<T: Int> Add for T` as a builtin rule)
- later, full surface-level blanket impls once generics exist

Runtime trait objects (`dyn Trait`) remain optional and out of hot loops.

### Roadmap (phases)

Phase A: typed boundaries (v0 -> v0.5)

- finalize cast sugar set + semantics
- add a cast operator: `expr as u16` (desugars to builtin cast)
- emit stable type-kind metadata for annotated nodes

Phase B: gradual type checker (v0.5)

- add `oren build --typecheck` (or default later)
- validate annotated boundaries and function signatures
- treat as lint-first while rolling

Phase C: full static types + generics (v1 direction)

- type inference with explicit width tokens
- generics + constraints (traits/protocols)
- monomorphization for performance
- explicit trait objects for runtime polymorphism

### Casting rules (production intent)

- integer narrowing uses wrap/truncate unless a checked cast is used
- float narrowing `f64 -> f32` is deterministic rounding to IEEE-754 float32, then widening
- endian casts are view/parse conversions, not arithmetic casts

No separate strict-mode toggle: semantics are strict and deterministic by default.

---

## 2) Syscall-First Native Runtime Plan (No C Shims)

### Summary

We will evolve the native runtime to be syscall-first and independent of libc/pthreads/malloc
for core runtime services, without a temporary C shim path. The plan avoids future rewrite by:

- keeping a stable internal OS boundary (`sys_*`)
- implementing OS-specific syscall layers for macOS arm64 and Linux arm64 in parallel
- building higher-level primitives (allocator, locks, threads, channels) on top
- migrating runtime code incrementally behind stable APIs

### Current reality (2026-01-12 snapshot)

- Native backend injects `lib/runtime_native.oren` (non-capsule) or `lib/runtime_native_capsule.oren`.
- `sys_*` calls are compiler intrinsics; native code emits syscalls inline.
- `oren_system()` is syscall-first on macOS (fork + execve + wait4).
- ENV is syscall-free: entry stub captures `envp`, `oren_getenv(key)` scans it.
- TIME is syscall-first: `sys_nanosleep(ns)` uses kqueue+kevent on macOS, `__NR_nanosleep` on Linux.
- Parking primitive exists on Tier-1:
  - macOS: ulock syscalls
  - Linux: futex wait/wake
  - Windows x64: WaitOnAddress/WakeByAddressAll from KERNELBASE.dll
- FS is progressively syscall-first with capsule enforcement at `sys_*` boundary:
  - `sys_open`, `sys_unlink`, `sys_rename`, `sys_mkdir`, `sys_access`, `sys_rmdir`,
    `sys_stat`, `sys_lstat`, `sys_fstat`, `sys_getdirentries64`
- `spawn`/`oren_join` on macOS uses fork + pipe for v0 correctness.
- Darwin fork ABI nuance handled: kernel returns X0 child_pid and X1=0/1; `sys_fork()` returns POSIX semantics.

### Hard constraints

1) No temporary C shim dylib path.
2) All OS interaction goes through `sys_*` boundary.
3) Implement macOS and Linux in parallel.
4) Internal ABI can be refactored for correctness/perf (rolling mode).

### Architecture layers

- L0: compiler + codegen (calls `oren_*` runtime APIs)
- L1: runtime services (`oren_*`) - OS agnostic
- L2: OS boundary (`sys_*`) - raw kernel-shaped operations
- L3: OS implementations (per target)

### Proposed `sys_*` interface (kernel-shaped)

Files / IO:

- `sys_open(path_ptr, flags, mode) -> fd_or_neg_errno`
- `sys_close(fd) -> 0_or_neg_errno`
- `sys_read(fd, buf_ptr, len) -> nread_or_neg_errno`
- `sys_write(fd, buf_ptr, len) -> nwritten_or_neg_errno`

Memory:

- `sys_mmap(addr, len, prot, flags, fd, off) -> ptr_or_neg_errno`
- `sys_munmap(ptr, len) -> 0_or_neg_errno`
- (optional) `sys_mprotect(ptr, len, prot)`

Threads:

- `sys_thread_create(entry_ptr, arg_ptr) -> handle_or_neg_errno`
- `sys_thread_join(handle) -> ret_or_neg_errno`
- `sys_thread_self() -> tid_token`

Parking (blocking primitive):

- `sys_park(addr_ptr, expected, timeout_ns) -> 0_or_neg_errno`
- `sys_wake(addr_ptr, count) -> nwoken_or_neg_errno`

Time:

- `sys_nanosleep(ns) -> 0_or_neg_errno`
- `sys_gettimeofday(tv_ptr, tz_ptr, abs_ptr) -> 0_or_neg_errno`

Fcntl helpers:

- `sys_fcntl(fd, cmd, arg) -> rc_or_neg_errno` (raw)
- `sys_fcntl_getfl(fd) -> oren_flags_or_neg_errno` (portable)
- `sys_fcntl_setfl(fd, oren_flags) -> rc_or_neg_errno` (portable)

### Milestones

A) Byte-accurate I/O (binary-safe)

- `oren_read_bytes(path) -> list<int 0..255>` must roundtrip embedded `0x00`

B) Syscall layer implemented (macOS + Linux)

C) Blocking primitives (no busy-spin)

D) Coroutine/scheduler readiness (channels + proper blocking)

E) GC + threads hardening (safepoints, stop-the-world, stress tests)

### Testing and verification

Local:

- `make test` baseline suite
- targeted tests for each primitive (binary I/O, channel blocking, spawn/join)

Linux arm64 under QEMU:

- build on macOS and execute ELF on QEMU host
- maintain a small smoke list for syscalls + allocator + futex

### Risks

- macOS syscall surface complexity
- thread join design without pthreads
- allocator correctness with GC tracking
- stop-the-world coordination across threads

### Acceptance criteria

Native runtime is independent when:

- native output does not import `pthread_*`, `malloc/free`, or libc stdio APIs
- core runtime behavior is built on `sys_*` and pure `.oren` code
- `make test` passes on macOS and Linux syscall-dependent tests pass under QEMU

---

## 3) HPC / Server Requirements (Roadmap Driver)

Production-grade HPC on servers needs:

- low latency + high throughput
- predictable memory and layout
- controllable concurrency
- deterministic tests and debuggable failures

### Mandatory language/compiler features

1) Explicit numeric types (width tokens)

- `u8 u16 u32 u64 u128`, `i8 i16 i32 i64 i128`, `f32 f64`, `bool`
- drive ABI/layout lowering, codegen semantics, SIMD selection

2) Efficient casting (compiler-lowered)

- cast sugar: `u8(x)`
- cast operator: `x as u8`

3) Contiguous typed buffers and views

- contiguous arrays (not boxed lists)
- zero-copy views (`ptr + len`, stride)
- fixed-size arrays for small vectors (`[N]T`)

4) Generics + traits (compile-time)

- monomorphized algorithms (`dot<T>`, `axpy<T>`, `matmul<T>`)
- constraints (`T: Float`, `T: Scalar`)

5) SIMD support (Tier-1)

- arm64 NEON (128-bit)
- x86_64 SSE2 baseline, AVX2 optional when determinism allows
- deterministic rounding and fixed reduction order

6) Concurrency (server runtime)

- OS threads for saturation
- thread pools, work queues, locks/atomics as substrate

### Immediate plan (rolling order)

1) Typecheck mode v0 (opt-in): reject invalid casts, validate typed boundaries
2) Typed buffers + views (ptr+len, stride views) aligned with deterministic AVM goals
3) SIMD hook boundary + NEON kernels with scalar fallback
4) Allocator control for large numeric buffers (aligned, arena/mmap, non-GC-scanned regions)
5) Generics + monomorphization for `std/linalg`

### Tracker

- Active priorities: `docs/STATUS.md`

## Oren Evolution and Roadmap (Rolling)

**Status:** Rolling (consolidated architecture, evolution rules, and roadmap)
**Last updated:** 2026-02-19

This section consolidates the prior evolution/roadmap notes into one coherent place.

---

## 0) The core problem Oren solves (why multiple backends exist)

Oren is two products in one:

1) A native language (server/desktop): compile `.oren` to a host executable (Mach-O on macOS, ELF on Linux) with strong control over OS boundaries and low dependencies.
2) An agent-safe execution substrate (mobile/edge/restricted): compile `.oren` to `.obc` and run on the AVM (Agent Virtual Machine), with deterministic mode, capability governance, and Virtual* backends.

Key architectural bet:

> Governed, replayable execution matters more than native peak speed in v0.

Native performance and full system access still matter for production/server usage, so Oren is a multi-backend compiler by design.

---

## 1) Architecture overview (day0 -> production)

### 1.1 Stage0 Go bootstrapper

- Entry: `cmd/oren` (Go) -> `oren_bootstrap`
- Purpose: Provide a stable starting point to compile `oren.oren` into stage1.

### 1.2 Stage1 self-hosted compiler

- Source: `oren.oren`
- Purpose: The main compiler implementation. Most language and backend evolution happens here.

### 1.3 Backends (C, native, bytecode)

Oren compiles to multiple targets:

- **C backend**: `.oren -> .c -> cc`
  - Portable, reliable for bootstrapping
  - Uses libc in `lib/runtime.[ch]` (acceptable for this backend)
- **Native backend**: `.oren -> Mach-O/ELF`
  - Syscall-first runtime (no libc shims)
  - Primary for production server/desktop
- **Bytecode backend**: `.oren -> .obc`
  - Portable bytecode executed by AVM (agent-safe / restricted environments)

These are complementary targets that form an evolution ladder, not competing ideas.

### 1.4 High-level pipeline

```
Source (.oren)
  -> shared AST
  -> backend selection
     - C backend -> C runtime
     - native backend -> syscall-first runtime
     - bytecode backend -> OBC + AVM
```

### 1.5 Syscall-first native runtime

The native backend runtime must not depend on libc or pthreads as its implementation substrate.
All OS interaction should go through the explicit `sys_*` boundary.

Why it matters:

- Avoids the predictable rewrite later ("use libc now, rewrite it out later")
- Keeps effects explicit and auditable (important for determinism and safety)
- Aligns with AVM capability governance

Primary target today: macOS arm64. Linux arm64 must be validated continuously (QEMU host).

### 1.6 AVM and Virtual* backends

AVM exists because there are environments where:

- JIT is restricted/banned (iOS/App Store)
- shipping a native toolchain is not possible
- deterministic replay and policy scanning are required

AVM offers explicit capability domains and virtualized effects:

- FS domain
- NET domain
- PROC domain
- ENV domain
- TIME/RNG domains
- AVM domain (nested universes)

Virtual* backends provide deterministic, no-host-effects simulation (VirtualFS/NET/PROC),
which is essential for capsules and replayable agent execution.

---

## 2) Language evolution rules (self-hosting stability)

This repo is self-hosting: stage1 is written in `.oren`. That means language changes can
break the compiler itself if not staged. These rules keep the build chain stable.

### 2.1 Definitions

- **Reference semantics:** C backend + `lib/runtime.[ch]` behavior unless explicitly stated.
- **Backends:** C, native arm64, bytecode/AVM.
- **Breaking change:** previously-valid programs fail to parse, typecheck, or run differently.

### 2.2 Principles

1) **Stage changes (do not flip overnight)**
   - Parser accepts new syntax (AST node exists)
   - At least one backend implements it (prefer C backend first)
   - Conformance tests exist
   - Other backends implement or explicitly reject with a clear error
   - Only then may compiler `.oren` sources use it

2) **Prefer additive syntax and desugaring**
   - Add syntax that lowers to existing constructs when possible

3) **Conformance tests are mandatory for semantics**
   - C backend test
   - native backend test (if supported)
   - AVM test (if bytecode semantics are involved)

### 2.3 Language versioning

Rolling mode today:

- No `--lang v0|v1` selector
- No per-source language version header
- Syntax/semantics evolve rapidly with the compiler and tests

Stability policy:

- Until a stability milestone is declared, everything is unstable (parser, ABI, stdlib, bytecode)
- When stability is declared, introduce versioning then (flag/header/feature gates)

### 2.4 Example rollout: `yield`

1) Add keyword + AST node
2) Implement C backend lowering (state machine)
3) Add tests
4) Implement native backend (same lowering)
5) Implement bytecode backend

Preference: stackless-first to avoid multi-stack GC and switching complexity.

---

## 3) Roadmap (phases and priorities)

This section mirrors the rolling roadmap while the active, time-ordered priorities live in `docs/STATUS.md`.

### Goals

- Fast native codegen for macOS/Linux arm64 first, with C backend for bootstrapping and constrained targets.
- Robust type system (generics, traits/interfaces, enums/ADTs, pattern matching) with a sound checker.
- Predictable memory story: optional GC (desktop/server) and deterministic/manual mode (embedded).
- Developer ergonomics: formatter, linter, LSP, test runner, package manager, debugging/profiling hooks.

### Agentic/production constraints

- Syscall-first native runtime (no libc shims)
- Native TCP/IP for production server/desktop usage
- AVM virtualization + multiverse for safe agent execution
- Compiler-in-AVM (source -> `.obc` inside sandbox) for closed-loop deployments
- Linux parity early (avoid macOS-only drift)

### Mitigation strategies

- **Runtime performance:** move from stack-machine codegen to register allocation + small opt pipeline
- **Platform limits:** keep Tier-1 targets arm64 (macOS/Linux) and x86_64 (Linux/Windows)
- **Safety:** move from conservative stack scanning to precise GC with stack maps
- **Ecosystem split:** define stdlib subset that works in `--no-gc` mode

### Phase 1

- Memory/GC: conservative stack scan done; next is precise GC with stack maps and safepoints
- Architecture: keep native backend clean for future targets
- Tier-1 parity: align arm64/x86_64 semantics and runtime surface
- Concurrency: threading primitives + channels/select exist; M:N scheduler groundwork ongoing
- FFI/Linking: macOS dynamic linking done; Linux DT_NEEDED/PLT pending
- Tooling: CLI parity, formatter skeleton, lint scaffolding

Syscall-first runtime track (Phase 1 details):

- Expand and lock `sys_*` surface (FS/PROC/ENV/TIME/NET)
- Native TCP/IP on macOS arm64 (timeouts/cancellation)
- Linux arm64 parity via QEMU host
- x86_64 Tier-1 parity via remote host validation

### Phase 2

- Optimization: register allocation, basic inlining, const-prop
- Concurrency: M:N scheduler + async I/O
- Type system: full checker + generics/monomorphization + traits + enums/ADTs
- Testing: built-in test runner, property testing, coverage hooks
- Packaging: registry, lockfiles, reproducible builds
- Tooling: LSP + DWARF symbols

### Phase 3

- Agent readiness: implement `docs/STATUS.md`
- Concurrency (advanced): pub/sub, fan-out, parallel iterators
- Targets: avoid WASM as a first-class backend; AVM hosted in WASM is acceptable
- Security/trust: deterministic builds, supply chain verification, signed artifacts
- Ecosystem: stdlib build-out (fs/net/crypto/time), Windows story, docs/examples

### Stdlib direction (rolling)

Stdlib is layered bottom-up without libc shims:

- deterministic parsing/encoding (json/yaml/cbor)
- deterministic text tooling (regex)
- small portable math helpers

Higher-level networking libraries layer on top of syscall-first NET and AVM VirtualNET.

---

## 4) Agent-native evolution track (AVM + OBC)

This track targets restricted environments (iOS/Web/Edge) where native toolchains are unavailable.

### Vision: "Universal Agency"

- Oren aims to be a safe, portable language for agents in restricted environments.
- The hybrid runtime philosophy:
  - Native mode for server/desktop
  - Bytecode mode for safe interpretation (AVM)

### AVM/OBC phases

1) **AVM Core**: C stack-machine interpreter (`lib/avm`), define OBC instruction set
2) **Bytecode Backend**: compiler emits `.obc` (`lib/compiler/codegen_bytecode.oren`)
3) **Inception**: compile `oren.oren` to `oren.obc` and run compiler-in-AVM
4) **Agent stdlib**: capability-scoped modules (`fs`, `net/http`, `semantic`, `proc`)
5) **LLM ergonomics**: script mode + FFI for host capabilities

### Current status (rolling)

- Compiler self-hosting (stage2) active
- Backends: C, native arm64, and bytecode operational
- AVM: stack-machine interpreter exists; `.obc` can be emitted and executed
- Host calls: capability-scoped `CALL_NATIVE2(domain, op, nargs)` exists (rolling ABI)

### Critical gaps (agent-grade execution)

- Capability governance (FS/NET/PROC/TIME/CRYPTO/SIMD allow-lists + budgets)
- Snapshotting + determinism (record/replay)
- Memory + concurrency hardening (GC + task interaction)

### Immediate action plan

1) Keep bootstrap AVM working while drafting next-gen plan (typed buffers + SIMD kernels + capability domains)
2) Implement byte-accurate I/O primitives for `.obc` and model artifacts
3) Implement syscall-first runtime direction (no C shims) and validate on Linux
4) Add verifier + budgets + deterministic record/replay + snapshotting

---

## 5) Strategic positioning (why Oren wins its niche)

- Oren is not trying to beat Python for humans or Rust for static safety.
- Oren aims to be the default portable, governed execution substrate for agents.

Winning niche: "PostScript for Agents"

- Safe, portable, resumable execution
- Deterministic and capability-scoped
- Portable bytecode + AVM interpreter

Mobile/edge adoption is the wedge:

- iOS/App Store rules disallow JIT, leaving a gap for fast dynamic agent execution
- AVM fills that gap without requiring host toolchains

Execution priority: runtime capability and determinism over syntax sugar.

---

## 6) References

Canonical references for deeper detail:

- AVM spec + Next-Gen plan: `docs/AVM.md`, `docs/AVM.md`
- Agentic requirements: `docs/STATUS.md`
- Core system plans (type system, syscall-first runtime, HPC): `docs/STATUS.md`
- Backends overview: `docs/COMPILER_BACKENDS.md`
- Self-hosting: `docs/TOOLCHAIN_PLATFORMS.md`
- Toolchain bootstrap: `docs/TOOLCHAIN_PLATFORMS.md`
- Active tracker: `docs/STATUS.md`

## Agentic-AI Requirements (Language + Compiler + AVM)

**Status:** Draft requirements (guidance)  
**Last updated:** 2025-12-15  
**Scope:** Oren language design + compiler toolchain + AVM execution substrate

Oren is designed for the “agent loop”:

1) an agent generates/patches code
2) code executes (often with partial trust)
3) failures are observed by another agent
4) the agent patches and replays deterministically until it converges

This document consolidates the “AI-era” requirements that make that loop safe, fast, and self-healing.

## 0) Definitions

- **Effectful operation:** touches the external world or introduces nondeterminism (FS/NET/PROC/TIME/RNG).
- **Deterministic mode:** same program + same inputs → same outputs + same trace, with effects recorded/replayed.
- **Self-healing loop:** run → structured failure → patch → deterministic replay → converge.

## 1) Non-Negotiables (Must-Have Substrate)

### 1.1 Determinism + record/replay (debuggable by agents)

Requirements:

- deterministic semantics for core operations:
  - integer overflow policy (wrap vs trap)
  - float semantics policy (IEEE754 as provided, but document corner cases)
  - string model (byte-string vs UTF-8 semantics; pick and document)
- record/replay for effectful host calls:
  - record `(domain, op, args) -> (ret, err, bytes_out)`
  - replay without touching the real host
- deterministic scheduling policy:
  - provide a “single-thread deterministic” baseline first
  - when coroutines land, define a deterministic scheduler mode (or record/replay scheduling)

Swarm implication:

- deterministic mode is the substrate for “k-of-n verification” and swarm consensus on result/state hashes (see `docs/AVM.md#avm-swarm-consensus-agent-mobility-design-validation`).

### 1.2 Snapshot / restore (resumability)

Requirements:

- snapshot includes: PC, call frames, operand stack, locals/globals, heap objects
- snapshots are content-addressable-friendly (chunked/hashes) to reduce churn
- restore resumes under deterministic constraints (or explicitly declares nondeterminism)

### 1.3 Capability model (least privilege) + virtualization hooks

Requirements:

- capability-scoped host calls (`CALL_NATIVE2(domain, op, nargs)` in the rolling ABI)
- allow-lists:
  - FS path prefixes
  - NET target allow-lists
- virtualization hooks (“Matrix sandbox”):
  - VirtualFS / VirtualNET / VirtualPROC backends
  - run the same bytecode against “real” or “simulated” services

Repo runtime constraint (design decision):

- native runtime should be **syscall-first** and avoid C shims (no glibc/libSystem dependency for core services where practical)

### 1.4 Resource metering (budgets) + cancellation/deadlines

Requirements:

- instruction budget (“gas”) with enforcement points
- wall-time deadline/timeout support
- memory budget (heap + buffers)
- I/O budgets (bytes read/written; network requests)
- cancellation token propagation for structured concurrency

### 1.5 Structured diagnostics (machine-readable)

Requirements:

- stable error codes + structured payloads:
  - `{ code, msg, span, function, backtrace, hints }`
- source mapping strategy across backends:
  - `.oren` span → IR / bytecode PC → (optional) native PC
- event log hooks for tracing:
  - `span_start`, `span_end`, `log`, `metric`, `error`

## 2) “AI-Era” Language + Toolchain Features

These features make agent-authored code easier to generate, verify, and maintain.

### 2.1 Contracts + tests as first-class syntax

Requirements:

- `assert` in the core language
- `test` blocks + a test runner that produces machine-readable output
- optional pre/post conditions for critical APIs (design-by-contract)

### 2.2 Error model that supports recovery

Effectful operations must return recoverable errors rather than hard-crashing.

Pick one model and standardize it:

- `Result<T, E>` (preferred for explicitness), or
- `throw`/`catch` with typed errors, or
- `nil` + error-code convention (least preferred; easy to ignore)

### 2.3 Structured concurrency (agent workflows)

Requirements:

- stackless coroutines (`yield` lowering) as the first implementation strategy
- structured scopes (`task_group`-like) with cancellation/deadlines
- timeouts everywhere for effectful operations

### 2.4 Semantic metadata (RAG-ready)

Requirements:

- doc comments (`///`) exported as structured artifacts (JSON/Markdown)
- symbol table export for public APIs:
  - names, signatures, visibility, docs

### 2.5 Introspection surfaces (tooling-first)

Requirements:

- compiler exports:
  - AST/IR in JSON (stable schema)
  - dependency graph / module graph
- stable formatting / pretty-printing for patch workflows

### 2.6 Token-efficiency (reduce boilerplate)

Requirements:

- syntax that is unambiguous to parse
- avoid excessive boilerplate; prefer regular constructs + inference where safe

## 3) “AI-Era” AVM Features (Agentic VM)

### 3.1 Bytecode verification + policy scanning (before execute)

Requirements:

- verifier:
  - stack depth validation
  - jump target validation
  - constant pool bounds validation
  - native call operand decoding validation
- policy scanner:
  - extract “which capability domains are used”
  - reject forbidden domains/ops for a capability set

### 3.2 Typed buffers + SIMD kernels (no-JIT performance path)

Requirements:

- `BYTES` + typed numeric buffers (start with `F32_BUF`)
- SIMD/domain ops for `dot/add/mul/reduce` (side-effect free)
- strict semantics + scalar fallback compatibility

### 3.3 Repair-friendly execution substrate

Requirements:

- snapshot/restore support (agent pause/resume)
- deterministic replay support for patch validation
- optional hot reload / safe patching:
  - load new code blob
  - compatibility check
  - migrate state when possible

### 3.4 Nested universes (“AVM in AVM”) for scalable simulation

Requirements:

- ability for a program to spawn *child universes* under:
  - strict capability subset (FS/NET/PROC/TIME/RNG/ENV)
  - hierarchical budgets (gas/time/memory/IO)
  - deterministic record/replay or Virtual* backends
- child universes must be resumable (snapshot capsules) and hashable (`RESULT_HASH`/`STATE_HASH`)

Rationale:

- enables “Matrix sandbox” simulation at scale without heavy containers/processes
- enables hierarchical governance: outer agent validates inner agents and plugins

Design reference:

- `docs/AVM.md#avm-in-avm-multiverse-design-nested-virtual-universes`

### 3.5 Deterministic trace + explainability surfaces (agent debugging)

Deterministic hashing of *final state* is necessary but not sufficient for agent repair.
Agents need *localized evidence* about where divergence or failure happened.

Requirements:

- **Deterministic trace stream** (opt-in, budgeted):
  - event categories: `op_step`, `call_native2`, `alloc`, `error`, `span_start/span_end`
  - trace must be serializable as data (`BYTES`) and replayable
- **Trace hashing**:
  - `TRACE_HASH` is computed from a canonical encoding of trace events
  - trace hashing must be independent of host timing and logging order
- **Explainability hooks**:
  - map `(pc, function)` back to source spans (when debug info is present)
  - expose “last N events” on error to enable agentic root-cause inference

Rationale:

- enables “self-healing” workflows where an agent can diff traces between two runs
- prevents “black box” failures where only a hash mismatch is available

Bootstrap status (rolling, implementation reality as of 2025-12-15):

- `avm --print-trace-hash <file.obc>` prints `TRACE_HASH <sha256>` derived from a canonical trace-event encoding (step + CALL_NATIVE2 + abort).
- `avm --print-trace-bytes-hex <file.obc>` prints:
  - `TRACE_TRUNCATED <0|1>` (best-effort capture may truncate due to budget/alloc failure)
  - `TRACE_BYTES_HEX ...` (trace stream as data; hex for transport)
  Trace capture must **not** affect program semantics: if trace bytes hit budget, AVM truncates (disables further capture) rather than aborting execution.
  Trace bytes storage is governed by `AVM_TRACE_BYTES` and is isolated from `AVM_MEM_BYTES` (program heap budget).
- Deterministic scheduling (tasks) is not implemented yet; see `docs/AVM.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly` for the design direction.

### 3.6 Governance-ready module boundaries (SOLID on bytecode artifacts)

Agentic execution becomes unsafe and unmaintainable if the runtime grows as a monolith.

Requirements:

- **Capability domains are the unit of governance**:
  - each domain/op is documented and policy-controlled
  - dangerous domains (PROC/NET/AVM) are separable and deny-by-default
- **Code as content-addressed modules**:
  - module artifacts are hashed and referenced by hash
  - policies can pin allowed module hashes for supply-chain control
- **Stable “value capsule” serialization**:
  - define a canonical wire encoding for `Nil/Int/Bool/Float/String/Bytes/List/Map`
  - required to pass results/logs/snapshots between universes and swarm nodes

## 4) Minimal High-Leverage Implementation Order (Avoid Huge Rewrites)

This ordering is chosen to unlock “agent-grade” behavior early without requiring a massive rewrite:

1) **Structured errors + stable error codes** (compiler + runtime + AVM)
2) **Budgets/timeouts everywhere** (VM loop + native calls + test harness)
3) **Capability enforcement + allow-lists** (FS first, then NET/PROC)
4) **Verifier + policy scanner** (reject bad/untrusted bytecode early)
5) **Snapshot/restore** (stop-the-world checkpoint first)
6) **Typed buffers + SIMD kernels** (F32 baseline, scalar fallback first)
7) **Structured concurrency (`yield`/tasks)** (lowering-based stackless-first)

## 5) Canonical References

- Docs index: `docs/README.md`
- AVM spec (bootstrap + Next-Gen plan section): `docs/AVM.md`, `docs/AVM.md`
- Syscall-first runtime plan: `docs/STATUS.md`
- Language spec: `docs/LANGUAGE.md`
- Concurrency model: `docs/LANGUAGE.md`

## Oren vs. Zig: Strategic Comparison

This document outlines the design philosophy of Oren by comparing it to Zig, highlighting intended advantages and acknowledging current trade-offs.

## Strategic Advantages

### 1. Hybrid Memory Management (Productivity vs. Control)
*   **Zig:** Enforces strict manual memory management (passing allocators). Excellent for systems control but adds friction for high-level logic.
*   **Oren:** Adopts a **"Dual Mode"** approach:
    *   **Default:** Optional Garbage Collection (Mark-and-Sweep) for high-level productivity (similar to Go/Python).
    *   **`--no-gc`**: A deterministic, manual mode where GC is compiled out entirely for embedded/real-time contexts.
    *   **Benefit:** Write business logic fast with GC; write drivers/hot-loops with zero overhead in the same language.

### 2. Zero-Dependency Native Toolchain
*   **Zig:** Relies on LLVM for release builds (massive dependency, slower compile times).
*   **Oren:** Uses custom backends:
    *   **Native backend** (Tier‑1 targets; rolling): emits platform binaries (Mach-O/ELF/PE).
    *   **C backend**: portable path that emits C and builds via the host toolchain (`cc` / MSVC `cl.exe`).
    *   **AVM bytecode**: emits portable `.obc` artifacts for the AVM virtual machine.
    *   **Benefit:** fast edit-run cycles and a small self-hosting path that does not require LLVM for Tier‑1 bring-up.

### 3. Native SIMD as a Primitive
*   **Zig:** Abstract SIMD via `@Vector`.
*   **Oren:** Exposes native hardware intrinsics (e.g., `simd_add_2d`, `simd_mul_4s` for ARM64 NEON) as first-class citizens.
    *   **Benefit:** Direct access to hardware acceleration for physics/graphics without fighting the optimizer.

### 4. "Script-like" Ergonomics
*   **Zig:** Explicit and verbose by design.
*   **Oren:** Python/Go-style syntax.
    *   **Benefit:** Lower cognitive load for tooling, build scripts, and UI logic.

---

## Disadvantages & Risks

### 1. Runtime Performance (The "Naive Backend" Cost)
*   **Zig:** LLVM backend produces world-class, optimized machine code.
*   **Oren (rolling):** Native backend is still evolving (not LLVM-class yet).
    *   **Impact:** performance can still lag mature optimizing compilers (Zig/Clang), especially for numeric-heavy hot loops, and is an active optimization area.

### 2. Platform Limitations
*   **Zig:** Targets virtually every CPU and OS (x86, ARM, RISC-V, WASM, Windows).
*   **Oren (rolling):** Tier‑1 intent is:
    *   `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`
    *   See `docs/TOOLCHAIN_PLATFORMS.md` for the current fact-based status and gates.
    *   **Impact:** still smaller platform surface than Zig, but no longer “ARM64 only” in rolling mode.

### 3. Safety & Type Maturity
*   **Zig:** Strong spatial safety and robust compile-time checks.
*   **Oren:** "Conceptually static" but implementation is currently loose. The Garbage Collector is **conservative**, meaning it scans the stack guessing at pointers.
    *   **Impact:** Potential for memory leaks (integers mistaken for pointers) or crashes if type tags aren't respected.

### 4. The "Split Ecosystem" Risk
*   **Zig:** Unified ecosystem (allocator interface).
*   **Oren:** Supporting both GC and Manual modes risks fragmenting the library ecosystem (e.g., a "GC-only" JSON library causing leaks in a "No-GC" project).

### 5. Tooling Maturity
*   **Zig:** Robust build system, package manager, cross-compiler.
*   **Oren:** Bare-bones compiler.
    *   **Impact:** debugger story is still rolling, but basic I/O + networking (including TLS/HTTP2 loopback gates) exists in stdlib and is actively verified; see `docs/STATUS.md` and `scripts/verify_native_net_matrix.sh` for the current scope.

## Advanced Scenarios: The "Blue Ocean" for Oren

This document outlines advanced architectural capabilities where Oren and AVM provide solutions that traditional runtimes (Python, Node.js, Docker) cannot easily match. These are the "Killer Apps" for an AI-Native runtime.

See also:

- `docs/STATUS.md`
- `docs/AVM.md` (Next-Gen plan section)

---

## 1. The "Matrix" Sandbox (Perfect Simulation)

**The Problem:** Testing autonomous agents is dangerous and slow.
*   **Traditional Failure:** Mocking functions in Python (`unittest.mock`) is leaky; an agent can bypass mocks using subprocesses or different libraries. Docker containers provide isolation but are too heavy (seconds to start, GBs of RAM) for running thousands of rapid "thought-loop" simulations.
*   **The Oren Solution:** **Deep Instruction Interception.**
    *   Since AVM controls the execution at the opcode level, it acts as a "Physics Engine" for the Agent's reality.
    *   **Scenario:** You want to test a "Sysadmin Agent" to see if it deletes the wrong files.
    *   **Implementation:** The AVM is configured with a `VirtualFS`. The Agent executes `fs.delete("/etc/passwd")`. The AVM intercepts this call, updates its in-memory virtual file system, and returns `SUCCESS`. The real host system is untouched.
    *   **Impact:** You can run 10,000 parallel, high-fidelity simulations on a single laptop in milliseconds. It is "The Truman Show" for AI Agents.

## 2. Orthogonal Persistence (The "Immortal" Agent)

**The Problem:** Long-running agent processes are expensive and fragile.
*   **Traditional Failure:** If a Python script waits for a user reply for 3 days, the process must stay alive (consuming RAM/CPU), or the developer must manually serialize complex state to a database (hard to maintain). If the server restarts, the "thread" is lost.
*   **The Oren Solution:** **Stateful Serverless.**
    *   **Mechanism:** The AVM is designed to serialize its entire runtime state (Stack, Heap, Instruction Pointer) to a single snapshot file (`agent.snap`) in microseconds.
    *   **Scenario:** An Agent sends an email and awaits a reply.
        1.  **Suspend:** AVM snapshots the state to disk and exits. Resource usage: 0.
        2.  **Resume:** 3 days later, a webhook triggers the AVM. It loads `agent.snap`. The script resumes execution *on the exact line it paused*, with all local variables restored.
    *   **Impact:** Agents can "live" forever without consuming resources when idle. No complex database state management required.

## 3. "Trustless" Edge Logic (The Privacy Filter)

**The Problem:** Running 3rd-party AI logic on sensitive user data.
*   **Traditional Failure:** Sending user data to the cloud (Privacy risk). Running a downloaded Python script locally is dangerous because it's hard to guarantee it won't exfiltrate data (audit is difficult).
*   **The Oren Solution:** **Capability-Based Security.**
    *   **Mechanism:** Oren Bytecode is verifiable. AVM enforces "Capability Contracts" at the instruction level.
    *   **Scenario:** A "Medical Diagnosis" Agent sends a script to your phone to analyze your health records.
    *   **Contract:** `Capabilities: [Math, Local_Read]. Network: NONE.`
    *   **Enforcement:** The AVM scans the bytecode. If it detects a `NET_OPEN` opcode—or any instruction not in the allowlist—it rejects the code *before* execution.
    *   **Impact:** Enables "Code-to-Data" architectures. Users can safely run untrusted AI algorithms on their private data with a mathematical guarantee that data cannot leave the device.

## 4. "Swarm Consensus" (Serverless Blockchain)

**The Problem:** Coordinating a swarm of agents without a central server or heavy blockchain.
*   **The Oren Solution:** **Deterministic Execution.**
    *   **Mechanism:** Because Oren execution is deterministic (no undefined behavior), multiple agents can run the exact same `proposal.oren` script.
    *   **Scenario:** A swarm needs to agree on a resource allocation. They exchange the logic script. Each agent runs it locally. If the output hashes match, consensus is reached.
*   **Impact:** A lightweight, trustless coordination layer for multi-agent systems.

Design validation and a concrete path to implementation:

- `docs/AVM.md#avm-swarm-consensus-agent-mobility-design-validation`

## 5. Nested Universes ("AVM in AVM")

**The Problem:** Large agentic systems need safe, fast, repeatable simulation and governance, but “one big VM” becomes a monolith.

*   **Traditional Failure:** Running untrusted plugins inside the same runtime shares state, budgets, and side effects. Separating them with processes/containers is too heavy for running thousands of tiny simulations (and often unavailable on iOS/AppStore).
*   **The Oren/AVM Solution:** **Nested deterministic universes**.
    *   **Mechanism:** An AVM program can spawn child AVM instances (universes) under a strict capability subset and sub-budgets, with effects virtualized via record/replay or Virtual* backends.
    *   **Scenario:** An outer “planner agent” evaluates 1,000 candidate plans by spawning 1,000 child universes, each running the plan against the same VirtualFS/VirtualNET fixtures.
    *   **Impact:** “Matrix sandbox” becomes composable and hierarchical: the outer agent governs budgets/caps and can validate child outputs via `RESULT_HASH`/`STATE_HASH`.

Design feasibility and a concrete staged plan:

- `docs/AVM.md#avm-in-avm-multiverse-design-nested-virtual-universes`
