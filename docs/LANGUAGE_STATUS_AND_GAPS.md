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

## What’s Still Missing for Production Maturity (Gap List)

This section is intentionally phrased as “missing or not yet proved by tests”, because
production maturity requires both implementation *and* regression coverage.

### P0: Semantic parity and safety invariants

- **Stack safety parity across backends**
  - AVM has `--call-depth-max`.
  - C backend has `OREN_CALL_DEPTH_MAX` env.
  - Native backend (x64 bring-up) now supports `oren build --call-depth-max <n>`; runtime env parsing in the x64 entry stub is still pending for full parity.
  - Design: `docs/STACK_SAFETY.md`
- **Remove native map “key kind” heuristics**
  - Any heuristic that guesses key types (e.g. based on numeric range) is a semantics risk.
  - Direction: a tagged value model or explicit key typing at IR level.
  - Rolling status:
    - x64 native key-kind guessing (`key < 4096`) is removed for map get/set; key kind is inferred conservatively during lowering, and unknown cases abort(1) on the map path (tagged values remain the full fix)
    - x64 native now also propagates `recv_kind` on `Index` so codegen can avoid dynamic LIST/MAP dispatch when the receiver kind is known (still validates runtime magic; remaining unknown cases need a principled representation)
- **Varargs/spread parity (all backends + indirect calls)**
  - Varargs must be “boring and correct”: same semantics everywhere, including closures.

- **Tier‑1 OS/arch parity: native backends must converge**
  - Targets (Tier‑1 intent): macOS + Linux + Windows, on arm64 + x86_64.
  - Production readiness requires more than “it links”:
    - stable entry semantics (`__top_level__` + `main`),
    - deterministic panic/diagnostic contracts (`OREN_DIAG`),
    - consistent container fast-path semantics (no backend-only behavior),
    - capsule gating parity for syscall surfaces.
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
    - a stable, documented contract for env/flag precedence across all subcommands
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
