# Language Evolution Rules (Spec Stability + Self-Hosting)

**Status:** Draft  
**Last updated:** 2025-12-15

This repo is self-hosting: the stage1 compiler is written in `.oren`.
That means language changes can easily break the compiler itself if not staged.

This document defines rules for evolving the language (syntax + semantics) while keeping the build chain stable.

## 0) Definitions

- **Reference semantics:** the C backend + `lib/runtime.[ch]` behavior is the authoritative semantics unless explicitly stated otherwise.
- **Backends:** C, native ARM64, bytecode/AVM.
- **Breaking change:** a change that makes previously-valid programs fail to parse, typecheck, or run differently in a user-visible way.

## 1) Principles

### P1: Stage changes; do not “flip” the compiler overnight

Any new syntax (e.g., `yield`, `async`, `await`) must follow:

1) Parser accepts it (AST node exists)
2) At least one backend implements it (prefer C backend first)
3) Conformance tests exist
4) Other backends implement it or explicitly reject with a clear error
5) Only then may the compiler’s own `.oren` sources use it

### P2: Prefer additive syntax and desugaring

If possible:

- add new syntax that desugars to existing constructs
- keep runtime impact minimal

### P3: Conformance tests are mandatory for semantics

Each new feature must have:

- at least one C-backend test
- at least one native-backend test (if supported)
- at least one AVM test (if it affects bytecode execution)

## 2) Language Versioning (Recommended)

This repo is currently operating in **rolling language mode**:

- There is **no** `--lang v0|v1` selector today.
- There is **no** per-source “language version header” today.
- Syntax/semantics may change quickly, and the compiler + tests are expected to evolve together.

Stability policy:

- Until an explicit “stable milestone” is declared, **everything is considered unstable** (parser, ABI, stdlib surface, bytecode).
- When stability is declared later, we can introduce a versioning mechanism *then* (flag, header, or feature gates), but we do not block current work on version plumbing.

## 3) Example: Introducing `yield` (Stackless Coroutines)

Recommended `yield` rollout:

1) Add keyword `yield` and AST node `YieldStmt` or `YieldExpr`.
2) Implement in C backend via compiler lowering (state machine).
3) Add tests:
   - yield basic sequencing
   - yield inside loops
   - yield + channel integration (later)
4) Implement in native backend (same lowering strategy).
5) Implement in bytecode backend.

Notes:

- “stackless-first” is preferred to avoid stack-switching complexity and GC multi-stack issues.

## 4) “Modern” features governance

Use SOLID-like rules for language feature growth:

- Each feature must have a clear motivation (e.g., “enables coroutines”).
- Avoid overlapping features until the core is stable.
- Prefer features that improve correctness and portability over syntax sugar.
