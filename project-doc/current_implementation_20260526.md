# Current Implementation Map

**Date:** 2026-05-26

## Compiler

- Bootstrap CLI: `cmd/oren`.
- Self-hosted compiler: `lib/compiler/`.
- Build pipeline: `lib/compiler/compiler/040_build_pipeline.oren`.
- Parser: `lib/compiler/parser_parse/`.
- Module linking: `lib/compiler/compiler/020_modules_linking.oren`.
- Optimizers: `lib/compiler/optimizer*.oren`.

## Backends

- C backend: `lib/compiler/transpiler.oren`, `lib/runtime.[ch]`.
- Native ARM64: `lib/compiler/arm64_*`.
- Native x64: `lib/compiler/x64_*`.
- Bytecode: `lib/compiler/codegen_bytecode/`.
- AVM runtime: `lib/avm/`.

## Runtime and Stdlib

- Native runtime: `lib/runtime_native/`.
- C runtime: `lib/runtime.[ch]`.
- Stdlib: `lib/std/`.
- Capability and effect contracts: `docs/CAPABILITY_RUNTIME_CONTRACT.md`,
  `docs/EFFECT_LEDGER_CONTRACT.md`.

## Verification

- Fast smoke: `make test`.
- Curated broad gate: `make test-curated`.
- AVM: `make avm && make test-avm`.
- Cross-backend parity: `make verify-backend-parity`.
- Runtime robustness: `make verify-runtime-robustness`.
- Docs site: `make docs-site`.

## Readiness

Current readiness is tracked in `docs/STATUS.md`. The highest-priority blockers are
runtime robustness, native performance/tagged-value convergence, AVM iOS embeddability,
AVM fixture manifest coverage, and compiler-in-AVM packaging.
