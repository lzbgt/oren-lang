# Oren Language Feature Matrix (Rolling, AI-Friendly)

**Last updated:** 2025-12-28  

This document is a **quick index** for AI agents and maintainers:

- what a feature is,
- whether it is **Implemented / Rolling / Planned**,
- where the implementation lives (compiler/runtime),
- where the behavior is validated (fixtures/examples).

It complements:

- `docs/LANGUAGE_MANUAL.md` (how to write Oren today),
- `docs/LANGUAGE_SPEC.md` (grammar + semantics),
- `docs/LANGUAGE_STATUS_AND_GAPS.md` (production gaps, evidence-backed).

Status legend:

- **Implemented**: supported by the Stage1 compiler and used in current code.
- **Rolling**: supported, but semantics/ABI may still evolve (must stay regression-tested).
- **Planned**: design intent; track via `docs/TODOS.md` / `docs/ROADMAP.md`.

## Core language

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Modules + `import` | Rolling | Parser: `lib/compiler/parser_parse/**`; Linking: `lib/compiler/compiler/020_modules_linking.oren` | Examples: `examples/module_app.oren`; Tests: `tests/modules/` |
| Top-level statements + entry | Rolling | Native entry stubs: `lib/compiler/arm64_*`, `lib/compiler/x64_*`; Bytecode entry: `lib/compiler/codegen_bytecode/030_tail.oren`; C entry: `lib/compiler/transpiler.oren` | Manual: `docs/LANGUAGE_MANUAL.md`; Examples: `examples/hello.oren`, `examples/hello_c.oren` |
| Program termination (`exit`) | Rolling | Builtins/runtime: `exit(code)` lowered per-backend; termination semantics are standardized via `exit` | Use `exit(code)` for portability; do not rely on `main` return value (rolling) |
| `fn` + named functions | Implemented | Parser + lowering + all backends | Everywhere; compile pipeline: `lib/compiler/compiler/040_build_pipeline.oren` |
| Function values + lambdas | Rolling | C backend: `lib/compiler/transpiler.oren` (closures + wrappers); Native runtime: `lib/runtime_native/120_first_class_fn.oren`; Bytecode: `lib/compiler/codegen_bytecode/**` | AVM: `tests/avm/test_closure_fn_values.oren` |
| Varargs (`...rest`) + spread calls | Rolling | Parser marks `is_varargs`; Bytecode/C/native lowering handle spread and rest list packing | Manual/spec sections; fixtures under `tests/**` that exercise spread/varargs |
| Control flow: `if/else`, `while`, `for`, `switch/case` | Implemented/Rolling | Parser + lowering; `for x in ...` is sugar in lowering | Example: `examples/hello.oren`; Tests: `tests/native/` + `tests/avm/test_switch.oren` |
| `match` | Rolling | Parser contextual keyword + lowering into deterministic control flow | Tests: `tests/modules/test_match_enum.oren` |
| `enum` | Rolling | Lowered as tagged-map constructors | Tests: `tests/modules/test_match_enum.oren`; Spec: `docs/LANGUAGE_SPEC.md` “enum/match” section |

## Types and “static-first” constructs

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Type annotations (syntax) | Rolling | Parser supports `: type_name`; lowering uses hints | Manual/spec: type annotation sections |
| Traits + impl blocks (static-first) | Rolling | Parser: `lib/compiler/parser_parse/**`; Lowering: impl rewrite passes under `lib/compiler/**` | Tests: `tests/modules/test_trait_*.oren` |
| `dyn` / runtime trait objects | Planned | Design docs (static-first + opt-in runtime polymorphism) | Track: `docs/TODOS.md` |

## Containers and performance

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| List literal `[]` and indexing `xs[i]` | Rolling | Shared lowering + backend intrinsics; C uses runtime helpers | Tests: `tests/native/fixtures/**`; Docs: `docs/DESIGN_CONTAINER_OPS.md` |
| List `push/len` as operations (no wrapper overhead) | Rolling | Native fast-paths + lowering; std:list maps to intrinsics | Track: `docs/TODOS.md` (P0.3) |
| `slice_view` / `clone` / `slice_copy` | Partially Rolling / Planned | stdlib + planned intrinsic semantics | Track: `docs/DESIGN_CONTAINER_OPS.md`, `docs/TODOS.md` |
| Typed buffers `[]i32`, `[]f64`, ... | Rolling | Stdlib: `lib/std/buffer.oren` + runtime helpers | Docs: `docs/HPC_SERVER_PLAN.md` |

## Runtime model (determinism, safety, AVM)

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Deterministic diagnostics (`OREN_DIAG`) | Rolling | Runtime + emit points (native/C) | Fixtures: `tests/native/fixtures/diag_fail.oren` |
| Stack safety (call depth guard) | Rolling | AVM flag; C env; native guards | Docs: `docs/STACK_SAFETY.md`; fixtures: `tests/native/fixtures/call_depth_overflow.oren` |
| Tail-call optimization | Rolling (subset) | Lowering/codegen passes | Docs: `docs/STACK_SAFETY.md` |
| Capsule model (native capability gating) | Rolling | Native runtime + syscall emit constraints | Fixtures: `tests/native/fixtures/capsule_*` |
| AVM execution of `.obc` | Rolling | Runtime: `lib/avm/**`; codegen: `lib/compiler/codegen_bytecode/**` | Examples: `examples/avm_*`; Tests: `tests/avm/**` |
| Compiler-in-AVM | Planned | Bytecode compiler + AVM host interface constraints | Track: `docs/TODOS.md` (P0.10), `docs/TOOLCHAIN_SELF_HOSTING.md` |

## HPC / SIMD (arm64 NEON-first)

| Feature | Status | Where (impl) | Evidence / notes |
|---|---|---|---|
| Typed buffers (`[]i32`, `[]f32`, `[]f64`, …) | Rolling | Stdlib/runtime surfaces under `lib/std/buffer.oren` + `lib/runtime_native/typed_buffers/**` | Manual: `docs/LANGUAGE_MANUAL.md` (Typed buffers section) |
| Native SIMD toggle | Rolling | Native runtime parses `OREN_ENABLE_SIMD` / `OREN_NO_SIMD`: `lib/runtime_native/040_capsule_core.oren` | SIMD must be an optimization only; scalar semantics are authoritative |
| SIMD intrinsics (arm64 NEON) | Rolling (arm64); Planned (x86_64) | Native arm64 codegen lowers `simd_*` intrinsics: `lib/compiler/arm64_native_expr/**` | Spec lists the intrinsic family: `docs/LANGUAGE_SPEC.md` (“Native Backend Intrinsics”) |
| SIMD-backed typed-buffer kernels (dot/axpy/gemm/etc.) | Rolling (arm64); Planned (x86_64) | Runtime dispatch in `lib/runtime_native/typed_buffers/**` + arm64 intrinsic lowering | Determinism guard: SIMD and scalar paths must be bit-identical; validated by `tests/native/test_simd_suite.oren` |
| AVM SIMD (NEON) | Planned / Rolling (gated) | Build/runtime gating exists (`AVM_ENABLE_SIMD=1`, arm64 NEON): `lib/avm/avm_native.c`, `lib/avm/main.c` | Design constraints: `docs/AVM_NEON_MAPPING_PLAN.md` (determinism-first); not treated as mature until fully covered by AVM tests |
| HPC roadmap (math/linalg + perf harness) | Rolling (in progress) | Design docs: `docs/HPC_SERVER_PLAN.md`, typed-buffer + linalg layers | Tracker: `docs/TODOS.md` (P1.3) |

## Tooling / ecosystem

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| `oren` CLI subcommands + completion | Rolling | CLI: `lib/compiler/compiler/000_prelude.oren`; completion docs | Docs: `docs/CLI_COMPLETION.md` |
| Package registry (`oren-packages`) integration | Planned | Module resolution + lockfiles + reproducible builds | Track: `docs/TODOS.md`, `docs/ROADMAP.md` |
