# Design: Unboxed `list<int>` (native runtime)

## Context

Recent benchmarks on arm64-macOS show the native backend is still far behind C for
array-heavy workloads:

- `array_sum`: native ~36× C
- `dot_product`: native ~45× C

Disabling list validation and list index checks **does not** materially change
performance, which implies the dominant costs are boxed integer operations,
list element boxing/unboxing, and GC/track overhead.

This design proposes an **unboxed list<int>** to reduce per‑element overhead and
allow tighter native lowering.

## Goals

- Provide a fast list type for integer workloads.
- Reduce per‑element overhead (no boxing, no GC scanning of elements).
- Enable simpler native lowering for `xs[i]` in tight loops.
- Maintain correct behavior for existing `list` users (rolling mode).

## Non‑Goals

- Full generic specialization or JIT.
- Automatic whole‑program type inference for every list.
- Breaking existing list semantics without an explicit opt‑in path.

## Proposed Representation

Introduce a **new tracked allocation kind** for `list<int>` in the native runtime
(e.g. `LIST_INT_KIND = 7`), leaving the current list kind (`2`) unchanged.

List header layout remains the same:

```
[count][capacity][buffer_ptr][magic]
```

For `list<int>`:

- `buffer_ptr` points to a contiguous array of **unboxed int64** values.
- GC does **not** scan the elements (they are not pointers).
- `list_magic()` remains unchanged (so the header remains recognizable).

### GC / tracking

- The alloc metadata `kind` distinguishes list kinds.
- The GC should treat `LIST_INT_KIND` as **non‑pointer payload** and skip element
  scanning.

## API / Language Surface

Provide an explicit, opt‑in constructor and helpers:

- `list.int_new(cap)` or `@list.int` annotation (exact syntax TBD).
- Runtime helpers:
  - `oren_new_list_int(cap)`
  - `oren_list_int_push(list, value)`
  - `oren_list_int_get(list, idx)`
  - `oren_list_int_set(list, idx, value)`

These helpers mirror existing list ops but assume integer values. Generic list
ops should accept both list kinds, but the specialized ops require list<int>.

## Compiler Lowering

### Type inference (minimal)

Start with **explicit opt‑in**:

- A new AST marker or builtin constructor yields `recv_kind = "list_int"`.
- The compiler attaches this `recv_kind` to index expressions (`xs[i]`).

### Native backend lowering

- For `recv_kind == "list_int"`, emit direct loads/stores of int64 values.
- Bounds checks remain for correctness (and can be hoisted later).
- Skip map fallback and dynamic kind checks.

## Safety and Compatibility

- Existing `list` remains unchanged.
- `list<int>` requires explicit use; no silent behavior changes.
- Generic list operations can detect `kind==LIST_INT_KIND` and fall back to
  list‑int helpers when possible.

## Tests / Gates

- New fixtures:
  - `tests/native/test_list_int_basic.oren`
  - `tests/native/test_list_int_bounds.oren`
  - `tests/native/test_list_int_mixed_reject.oren`
- Benchmarks:
  - `array_sum` and `dot_product` with list<int> should show a large reduction
    in native overhead.

## Rollout Plan

1. Add runtime kind + helpers (`oren_new_list_int`, `oren_list_int_*`).
2. Add compiler surface (explicit constructor) + lowering for index/set.
3. Add tests + benchmarks.
4. Add optional conversion helpers if needed (`list.to_int_list`).

## Open Questions

- Syntax choice (`list.int_new`, annotation, or new literal form?).
- Interaction with `list` methods from `std:list` (dual dispatch?).
- Whether to allow `list<int>` to accept `nil` (probably no; keep strict).

