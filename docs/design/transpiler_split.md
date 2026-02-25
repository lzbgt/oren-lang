# Transpiler Split (C backend) — Design Note

**Date:** 2026-02-25

## Goals

- Reduce `lib/compiler/transpiler.oren` below ~2000 lines by splitting into focused modules.
- Preserve current C backend semantics and public entrypoints (`transpile_entry`).
- Improve maintainability and testability by isolating responsibilities.

## Non-goals

- No changes to generated C output or runtime ABI.
- No behavioral changes to optimization heuristics or fast-loop selection.
- No changes to public call sites (build pipeline keeps `transpile_entry`).

## Constraints

- Avoid cyclic module dependencies.
- Keep refactor mechanical: move functions, update imports, adjust call sites.
- Maintain deterministic output and performance characteristics.

## Proposed module layout

1) `lib/compiler/transpiler_core.oren`
   - `new_transpiler`, emit/indent/flush helpers, join utilities, `list_contains`, `str_eq`.

2) `lib/compiler/transpiler_state.oren`
   - inty/const tracking: `_transpiler_inty_*`, `_transpiler_const_*`, `_transpiler_expr_is_inty`.

3) `lib/compiler/transpiler_expr.oren`
   - expression analysis helpers: `_transpiler_is_ident`, `_transpiler_is_int_lit`,
     list get/push detection, list-get collection, `expr_uses_ident`, fast RHS helpers.

4) `lib/compiler/transpiler_loops_match.oren`
   - loop matching and numeric pattern helpers: `_transpiler_is_simple_inc`,
     `_transpiler_match_*` helpers, LCG matching, list loop matchers.

5) `lib/compiler/transpiler_loops_emit.oren`
   - loop emission helpers: `_transpiler_emit_while_basic` and fast-loop emitters.

6) `lib/compiler/transpiler_c_utils.oren`
   - C naming/escaping utilities, type ctor helpers, arg list helper, function signatures,
     and literal parsing for C backend.

7) `lib/compiler/transpiler_lambda.oren`
   - lambda capture analysis + gensym helpers + lambda transpile helpers.

8) `lib/compiler/transpiler.oren`
   - orchestrator: `transpile_statement`, `transpile_expression`, `transpile_function`,
     `transpile_entry` and glue imports.

## Dependency sketch

- `transpiler.oren` imports all modules.
- `transpiler_state.oren` depends on `transpiler_c_utils.oren` (for `ns_resolve`, name helpers) and `transpiler_core.oren` (for list utils).
- `transpiler_expr.oren` depends on `transpiler_core.oren`, `transpiler_state.oren`, and `transpiler_c_utils.oren`.
- `transpiler_loops_match.oren` depends on `transpiler_expr.oren` + `transpiler_state.oren`.
- `transpiler_loops_emit.oren` depends on `transpiler_core.oren`, `transpiler_loops_match.oren`, and `transpiler_c_utils.oren`.
- `transpiler_lambda.oren` depends on `transpiler_core.oren` + `transpiler_c_utils.oren`.

This keeps dependencies acyclic with `transpiler.oren` at the top.

## Migration plan

1) Move core helpers into `transpiler_core.oren`, adjust imports.
2) Move inty/const helpers and `_transpiler_expr_is_inty` into `transpiler_state.oren`.
3) Move expression analysis helpers into `transpiler_expr.oren`.
4) Move loop matchers into `transpiler_loops_match.oren` and loop emitters into `transpiler_loops_emit.oren`.
5) Move C utility helpers into `transpiler_c_utils.oren`.
6) Move lambda helpers into `transpiler_lambda.oren`.
7) Keep `transpile_*` entrypoints in `transpiler.oren` and update to use module-qualified calls.

## Validation

- Run `make test` with the standard 3‑minute gate.
- Ensure `transpile_entry` behavior is unchanged (no fixture churn expected).
