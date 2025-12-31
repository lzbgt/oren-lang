# IR and Compiler Internals (Rolling, AI-Friendly)

**Last updated:** 2025-12-30  

This document is an **implementation map** for AI agents and maintainers:

- what “IR” means in this repo today (rolling reality),
- what the pipeline stages are,
- where the core data structures live,
- what **CoreIR** is intended to become (the semantics-owning boundary),
- and what has already landed (CoreIR v0 scaffold).

It complements:

- `docs/LANGUAGE_MANUAL.md` (user-facing “how to write Oren today”)
- `docs/LANGUAGE_SPEC.md` (grammar + semantics intent)
- `docs/BACKEND_ARCHITECTURE.md` (high-level architecture + invariants)
- `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md` (native backend reuse direction)

## 1) Terminology: “IR” in rolling v0

Oren is rolling. The word “IR” is used in two ways:

1) **Current reality (today):**
   - The compiler mostly operates on a **JSON-map AST** (mutable tree of `{type: ...}` nodes).
   - Most “lowering passes” are **AST rewrites** (backend-neutral).
   - Backends (C/native/bytecode) often still operate directly on this lowered AST.

2) **Target architecture (North Star):**
   - Introduce a canonical, backend-independent **CoreIR** that *owns semantics*.
   - Backends become thin adapters: `CoreIR -> BackendIR -> output`.

The goal is not “IR for its own sake”; the goal is:

- semantic parity across backends,
- maximal code reuse between arm64 and x86_64,
- deterministic behavior for AVM/multiverse workflows.

## 2) High-level pipeline (where to read code)

The pipeline is implemented in Oren itself under `lib/compiler/`.

Suggested “follow the code” order:

1) **Lexer / Parser**
   - Tokens: `lib/compiler/token.oren`
   - Lexer: `lib/compiler/lexer.oren`
   - Parser entry: `lib/compiler/parser.oren`
   - Parser internals: `lib/compiler/parser_core.oren`, `lib/compiler/parser_parse/**`
   - AST constructors (node shapes): `lib/compiler/ast.oren`

2) **Linking / modules**
   - Module linking: `lib/compiler/compiler/020_modules_linking.oren`
   - Generic specialization call rewrite: `lib/compiler/generic_call_lowering.oren`

3) **Name resolution / type hints / “static-first” rewrites**
   - Renamer: `lib/compiler/renamer.oren`
   - Type name resolve: `lib/compiler/type_name_resolve.oren`
   - Type annotation lowering: `lib/compiler/type_ann_lowering.oren`
   - Impl/traits lowering (method sugar, recv-kind hints, etc.): `lib/compiler/impl_lowering.oren`

4) **Optimizer (rolling)**
   - `lib/compiler/optimizer.oren`
   - Important note: optimizations must remain semantics-preserving under the chosen evaluation order.

5) **Backend selection**
   - Bytecode: `lib/compiler/codegen_bytecode/**`
   - C backend: `lib/compiler/transpiler.oren`
   - Native backends:
     - arm64 facade: `lib/compiler/codegen_arm64.oren`
     - x86_64 facade: `lib/compiler/codegen_x64.oren`

### Native runtime injection (compiler-side)

Both native backends ultimately want the same model:

- compile user program + the Oren “native runtime” sources into one output binary
- the runtime sources are modularized using a tiny include directive:
  - `// @include "relative/path.oren"`
- includes are expanded at compile time (compiler-side), then parsed as normal Oren source.

Implementation:

- Shared include expander: `lib/compiler/native_runtime_inject.oren`
- arm64 native injects runtime by default: `lib/compiler/arm64_native_program.oren`
- x86_64 native injects runtime by default: `lib/compiler/x64_native_program/090_program_entry.oren`
  - Tier‑1 rule: runtime injection is mandatory on x86_64; debug uses narrower fixtures/matrices rather than a runtime toggle.

- Shared injection + post-injection DCE: `lib/compiler/native_runtime_bundle.oren`
  - tags injected statements as runtime vs user (so backends do not rely on indices)
  - Tier-1 invariant: the injected runtime must not contain top-level executable statements
  - startup order: `native_runtime_init` runs first; then a synthesized `__top_level__` runs user global initializers and top-level statements
    - runtime global initializers are **not** executed in `__top_level__` (runtime init owns runtime globals)
  - compiler guardrail: constant-like runtime globals with non-zero initializers must be assigned in `native_runtime_init` (so Tier‑1 does not depend on top-level init order).

- the injected native runtime references syscall stubs (`sys_*`) that must be correctly lowered by the backend.

The CLI entry and dispatch live under `lib/compiler/compiler/**` (including `040_build_pipeline.oren`).

## 3) Current “IR”: AST and LinkedProgram shapes

### 3.1 AST node shape (rolling)

AST nodes are plain maps, typically with:

- `type`: a string tag (`"Function"`, `"Call"`, `"If"`, …)
- `token`: optional token metadata (file/line/col)
- node-specific fields (e.g., `"left"`, `"right"`, `"body"`, `"params"`, …)

Canonical constructors are in `lib/compiler/ast.oren`.

### 3.2 LinkedProgram shape (rolling)

Module linking produces a “linked” program map that backends consume.

The exact fields evolve, but common keys include:

- `statements`: flattened top-level statement list after module resolution
- `aliases`: import alias map (used by capture analysis to avoid capturing module names)
- `type_ns`: type namespace map (used by type-name resolution / impl lowering)

Backends should treat unknown fields as “future expansion” and avoid relying on map iteration order.

## 4) CoreIR: what it is supposed to mean

CoreIR is the intended semantics-owning boundary:

- It encodes evaluation order and short-circuit rules explicitly.
- It owns container operation semantics (`xs[i]`, `xs[i]=v`, `len`, `push`) in a backend-neutral way.
- It owns callable semantics (closures + varargs + spread + indirect calls).
- It exposes a stable “effect model” surface so AVM/capsules/native share the same conceptual domains.

Backends should not “decide what `for` means” or “how `...rest` is represented”.
Those decisions must be centralized, deterministic, and regression-tested.

References:

- Architecture: `docs/BACKEND_ARCHITECTURE.md`
- Native reuse direction: `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`

## 5) CoreIR v0 scaffold (what exists today)

We are introducing CoreIR incrementally.

The first landed piece is a minimal **CoreIR v0 scaffold**:

- `lib/compiler/coreir.oren`

What it does (today):

- deterministic extraction of top-level function declarations
- collects metadata needed by multiple backends:
  - `declared_functions` (map)
  - `func_decl_order` (list; source order)
  - `func_arity` (map)
  - `func_varargs_fixed` (map)

Initial consumer (today):

- x86_64 native backend prepass:
  - `lib/compiler/x64_native_program/080_functions_compile.oren`
- Bytecode backend prepass (declared funcs + varargs map):
  - `lib/compiler/codegen_bytecode/030_tail.oren`
- C backend transpiler prepass (direct-call + varargs lowering metadata):
  - `lib/compiler/transpiler.oren`

Why this matters:

- It removes the first piece of duplicated semantic metadata extraction.
- It makes arm64 and x86_64 converge on the same deterministic function/varargs facts.
- It is a safe stepping stone toward moving call canonicalization into CoreIR next.

## 6) Next CoreIR expansions (prioritized)

This is the suggested “rolling-safe” order to expand CoreIR while continuously keeping backends working:

1) **Call canonicalization**
   - Represent every call as one of:
     - `CallDirect(name, args...)`
     - `CallIndirect(fn_value, args_list)`
     - `CallSpreadDirect(name, fixed_args..., spread_list)`
     - `CallSpreadIndirect(fn_value, fixed_args..., spread_list)`
   - Lower varargs (`...rest`) and spread (`xs...`) deterministically at CoreIR boundary.
   - Motivation: this is the highest cross-backend coupling surface (C/native/bytecode/AVM).

2) **Container ops canonicalization**
   - Treat `xs[i]`, `xs[i]=v`, `len(xs)`, `push(xs, v)` as CoreIR ops with deterministic error behavior.
   - Ensure “hot path is not a stdlib call” for builtins.
   - Motivation: performance and semantic parity across backends.

3) **Effect model encoding**
   - Encode effectful operations as domain/op calls (conceptually aligned with AVM) so:
     - AVM enforces by policy
     - native/C enforce via capsule runtime policy and deterministic errors

4) **NativeIR extraction for arm64+x86_64 reuse**
   - Once CoreIR is stable for “meaning”, lower to a machine-ish NativeIR for ISA selection:
     - `Load/StoreLocal`, `Const`, `BinOp`, `Cmp`, `Branch`, `Call`, `Return`, …
   - This reduces duplication between `arm64_native_*` and `x64_native_program/**`.

Track these items in `docs/TODOS.md` (CoreIR boundary section).

## 7) Practical guidance (for contributors / agents)

When you modify semantics in a lowering pass:

- update the relevant section(s) in:
  - `docs/LANGUAGE_SPEC.md` (normative intent)
  - `docs/LANGUAGE_MANUAL.md` (practical usage)
  - `docs/LANGUAGE_FEATURE_MATRIX.md` (status + evidence)
- ensure there is a fixture or integration test that exercises the semantic contract.

When you add a new backend feature:

- first add/extend a shared lowering pass or CoreIR rule if the feature is semantic,
- then add the backend implementation,
- then add fixtures that run under multiple backends (where possible).
