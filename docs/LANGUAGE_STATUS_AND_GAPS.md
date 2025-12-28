# Language Status & Gaps (Rolling, Production Roadmap)

Oren is intentionally in **rolling mode**: rapid evolution is allowed, and backward
compatibility is not required unless explicitly stated.

This document is a *fact-first* snapshot of:

1) what exists today (with references to tests/fixtures),
2) what is missing for “modern production language” maturity,
3) the prioritized gap list (feeds `docs/TODOS.md`).

It is not meant to be aspirational prose; it is a checklist tied to code and tests.

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
  - AVM has `--call-depth-max`; native/C need the same deterministic contract.
  - Design: `docs/STACK_SAFETY.md`
- **Remove native map “key kind” heuristics**
  - Any heuristic that guesses key types (e.g. based on numeric range) is a semantics risk.
  - Direction: a tagged value model or explicit key typing at IR level.
  - Rolling status: x64 native now infers key kinds for common non-literal keys (identifier int/string) during lowering, reducing reliance on runtime guessing; remaining cases still need a principled representation.
- **Varargs/spread parity (all backends + indirect calls)**
  - Varargs must be “boring and correct”: same semantics everywhere, including closures.

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

### P1: Stdlib maturity

- **Stdlib should track current grammar**
  - Avoid legacy syntax drift: if/else forms, match forms, for-in syntax, etc.
  - The repo already enforces some audits via `./oretest`; expand as grammar stabilizes.

### P2: Distribution and “production runtime” story

- **Stdlib resolution/distribution**
  - “User friendly imports” vs embedding vs precompiled `.obc` bundles needs a single
    coherent model that works for both native and AVM.
  - Related docs: `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`, `docs/OBC_MODULE_LINKING.md`

## How to Use This Doc

- When a new feature lands, add a **test/fixture reference** here (it becomes living spec).
- When an incompatibility is introduced, record it as a **rolling limitation** and link the
  TODO item that will remove it.
