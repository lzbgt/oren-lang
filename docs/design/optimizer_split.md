# Optimizer Split — Design Note

**Date:** 2026-02-25

## Goals

- Reduce `lib/compiler/optimizer.oren` below ~2000 lines by splitting into focused modules.
- Preserve current optimization behavior and entrypoints (`lower_linked_program_in_place`).
- Improve maintainability by separating folding, DCE, list<int> rewrites, and TCO.

## Non-goals

- No new optimizations or behavior changes.
- No changes to optimizer ordering or backend gating.

## Constraints

- Keep transforms deterministic and conservative.
- Avoid cyclic module dependencies.
- Keep refactor mechanical: move functions and update imports/wrappers only.

## Proposed module layout

1) `lib/compiler/optimizer_core.oren`
   - Trace helpers, backend gating, literal helpers, trivial-expr predicates.

2) `lib/compiler/optimizer_fold.oren`
   - Non-nil analysis + constant/peephole folding.

3) `lib/compiler/optimizer_dce.oren`
   - Local DCE (uses/reads collection, block pruning).

4) `lib/compiler/optimizer_list_int.oren`
   - list<int> detection, safe-int tracking, rewrite and lowering helpers.

5) `lib/compiler/optimizer_list_reserve.oren`
   - list reserve insertion + push rewrite helpers.

6) `lib/compiler/optimizer_tco.oren`
   - Tail-call optimization (direct self recursion + modulo-constant form).

7) `lib/compiler/optimizer.oren`
   - Orchestrator entrypoint, wiring of modules.

## Dependencies

- `optimizer_fold.oren` depends on `optimizer_core.oren`.
- `optimizer_dce.oren` depends on `optimizer_core.oren`.
- `optimizer_list_int.oren` depends on `optimizer_core.oren`, `optimizer_helpers.oren`, `ast.oren`.
- `optimizer_list_reserve.oren` depends on `optimizer_core.oren`, `optimizer_list_int.oren`, `optimizer_helpers.oren`, `ast.oren`.
- `optimizer_tco.oren` depends on `optimizer_core.oren`, `ast.oren`.
- `optimizer.oren` imports all modules and keeps the pass order unchanged.

## Validation

- Run `make test` (default <3 min gate).
- No fixture or output changes expected.
