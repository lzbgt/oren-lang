# x64 Emit Ops Split

**Date:** 2026-02-25

## Goals

- Reduce `lib/compiler/x64_native_program/060_emit_ops.oren` below 2000 lines.
- Keep semantics identical across native emit paths (no opcode or lowering changes).
- Improve maintainability by separating locals/linetab helpers, matchers, and emit loops.

## Non-goals

- Changing fast-loop detection rules or runtime ABI.
- Reworking label/fixup emission APIs.
- Performance tuning beyond file structure.

## Constraints

- Preserve current function names and call sites to avoid broad churn.
- Keep `_emit_ops_in_fn` as the central dispatch entry point.
- Maintain deterministic lowering in existing fast-path loops.

## Module map

- `lib/compiler/x64_native_program/055_emit_ops_locals.oren`
  - Local slot collection, line-table recording, GC safepoint helpers.
- `lib/compiler/x64_native_program/056_emit_ops_match.oren`
  - Expression/loop pattern matching for fast-path emitters.
- `lib/compiler/x64_native_program/057_emit_ops_while_emit.oren`
  - Generic while emission and fast-path loop emitters.
- `lib/compiler/x64_native_program/060_emit_ops.oren`
  - `_emit_ops_in_fn` main dispatcher.

## Validation

- `make test`
