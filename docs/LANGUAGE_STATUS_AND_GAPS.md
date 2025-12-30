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

This doc answers: “what’s real today?” and “what’s missing to reach that definition?”

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
  - Real-hardware x86_64 run validation is opt-in (Win11 + WSL2): `docs/REMOTE_X64_ENV.md`
    - Tier‑1 TIME substrate (Linux+Windows): `tests/native/test_time_suite.oren` (expects `oren_sleep_ms` + wall/mono time to work without libc)
    - Tier‑1 parity fixture (closures + varargs): `tests/fixtures/tier1_native_lambda_varargs_main.oren` (gated by `OREN_REMOTE_RUN=1`)
    - Tier‑1 parity fixture (map dynamic key-kind on empty maps): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (gated by `OREN_REMOTE_RUN=1`)
    - Tier‑1 parity fixture (map get via dynamic key; nil-key miss semantics): `tests/fixtures/tier1_native_map_get_dynamic_key_main.oren` (gated by `OREN_REMOTE_RUN=1`)
    - Tier‑1 parity fixture (string ops: `+` / `len` / `slice`): `tests/fixtures/tier1_native_string_ops_main.oren` (gated by `OREN_REMOTE_RUN=1`)
    - Tier‑1 parity fixture (float literals + `+ - * /` + casts `f32/i64`): `tests/fixtures/tier1_native_float_ops_main.oren` (gated by `OREN_REMOTE_RUN=1`)
    - Tier‑1 parity fixture (process args / `oren_args()` across Linux+Windows): `tests/fixtures/tier1_native_args_main.oren` (gated by `OREN_REMOTE_RUN=1`)

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
    - Tier‑1 x86_64 evidence (empty map + dynamic string key): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (remote gate via `OREN_REMOTE_RUN=1`)
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
    - NET substrate is now proved by `tests/native/test_net_suite.oren` on Win11 (WinSock + select wait backend + WSAStartup gated in runtime).
    - PROC substrate (Tier‑1 Windows): rolling but now regression-gated:
      - POSIX fork/exec/wait4 do not exist, so the runtime uses `CreateProcessA` via `sys_win_createprocess` for `oren_proc_spawn`/`oren_system`.
      - Proof gate: `OREN_REMOTE_RUN=1 make test` runs `tests/fixtures/tier1_native_smoke_main.oren` on Win11+WSL2; the fixture calls `oren_system("echo tier1 smoke proc ok")` and returns non‑zero on failure.
      - Note: `tests/native/test_spawn_*` also exercise language-level `spawn/join` which is currently fork+pipe based and not Windows-safe yet (separate Tier‑1 gap).
  - Track: `docs/TODOS.md` (P0.1–P0.3), `docs/NATIVE_BACKEND.md`.

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
  - The repo already enforces some audits via `./oretest`; expand as grammar stabilizes.

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
