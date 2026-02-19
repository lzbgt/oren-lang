# Design: Collections & Container Operations

This document merges the prior container-ops and unboxed `list<int>` design notes into
one coherent plan. It covers:

- **Container operations** (`push`, `len`, `get`, `set`, iteration) across generics and `dyn`.
- **Performance-first specialization** for integer-heavy lists (`list<int>` unboxed payload).
- **Lowering rules** that keep the compiler/backends stable in rolling mode.

---

## 0) Goals and Non-goals

### Goals

1) **Modern, ergonomic surface syntax**
   - Support `push(xs, v)` and future `xs.push(v)` sugar without backend penalties.
2) **Extensibility**
   - User-defined containers can participate via traits.
3) **`dyn`-friendly**
   - `push(&mut dyn Push[T], v)` dispatches through a vtable.
4) **Performance predictability**
   - Built-ins lower to intrinsics; generic code monomorphizes; dynamic uses vtables.
5) **Backends remain stable**
   - Kernel `oren_*` intrinsics stay in place to keep bootstrapping safe.
6) **Concrete perf win for integer-heavy loops**
   - `list<int>` has an unboxed representation in the native runtime.

### Non-goals (first slice)

- Full trait-object ABI design if not already stable.
- Operator overloading syntax (e.g. `<<` / `+=`) in the first implementation slice.
- Breaking legacy list semantics without explicit opt-in.

---

## 1) Three-layer model for container ops

### Layer A — Kernel intrinsics (`oren_*`)

Examples: `oren_list_push`, `oren_list_len`, `oren_string_len`, `oren_buf_len`, …

Properties:
- **Reserved namespace**: not user-idiomatic.
- **Compiler/runtime coupling**: lowering and runtime may depend on exact names.
- **Stability**: keep stable and avoid renaming during rolling mode.

### Layer B — Stdlib wrappers (safe now)

Provide thin wrappers (e.g. `std:list`) that call `oren_*` intrinsics.

Properties:
- Zero ABI risk.
- Enables gradual migration away from raw intrinsics.
- Standardizes naming and semantics.

### Layer C — Language-level “operations” (future)

Treat `push`, `len`, etc. as **language operations**:
- Lower to intrinsic fast paths for built-ins.
- Lower to trait impls for known types.
- Lower to vtable calls for `dyn`.

This yields modern syntax with deterministic, low-overhead lowering.

---

## 2) Semantics: `push` is an operation

Define `push(container, value)` as a single semantic operation with deterministic lowering.

Lowering rules (ordered):

1) **Intrinsic fast path**
   - If the container type is a built-in list (or other built-in container), lower to
     `oren_list_push` / `oren_*` intrinsic.
2) **Static trait dispatch**
   - If `Push[T] for C` is known, lower to the resolved method (monomorphized).
3) **Dynamic dispatch**
   - If the container is `dyn Push[T]`, lower to a vtable call.
4) **Otherwise: type error**

This keeps ergonomics without runtime penalties for built-ins.

### Infallible vs fallible push

- `push(&mut C, T) -> nil` (infallible, may abort on OOM depending on policy)
- `try_push(&mut C, T) -> bool` or `Result` for long-lived server/HPC usage

Recommendation: expose both for production-grade ergonomics.

---

## 3) Index operations remain index-based

`get`/`set` for lists remain index syntax:

- `x = xs[i]`
- `xs[i] = v`

Reasons:
- Already optimal across backends.
- Avoids naming drift (`get` vs `at` vs `index`).
- Supports aggressive lowering and bounds-check hoisting.

---

## 4) Unboxed `list<int>` (native runtime)

### Context

Benchmarks show native backend is far behind the C backend for array-heavy workloads
(e.g. `array_sum`, `dot_product`). Disabling bounds checks does not close the gap,
which implies the dominant costs are boxing/unboxing and GC scanning.

### Goals

- Provide a fast list for integer-heavy workloads.
- Eliminate per-element boxing and GC scanning.
- Enable native lowering to direct load/store of int64 values.

### Non-goals

- Full generic specialization or JIT.
- Implicit global changes to list semantics.
- Silent behavior changes without opt-in.

### Proposed representation

Introduce a **new tracked allocation kind** for `list<int>` in the native runtime
(e.g. `LIST_INT_KIND = 7`), leaving the current list kind unchanged.

Header layout is unchanged:

```
[count][capacity][buffer_ptr][magic]
```

For `list<int>`:
- `buffer_ptr` points to a contiguous array of **unboxed int64**.
- GC **does not** scan the elements.
- `list_magic()` remains unchanged so the header stays recognizable.

### Runtime API surface

Provide opt-in helpers:

- `oren_new_list_int(cap)`
- `oren_list_int_push(list, value)`
- `oren_list_int_get(list, idx)`
- `oren_list_int_set(list, idx, value)`

Generic list ops accept both list kinds, but specialized ops require list<int>.

### Compiler lowering

Minimal, explicit opt-in:

- Introduce an AST marker or constructor that yields `recv_kind = "list_int"`.
- Attach `recv_kind` to index expressions (`xs[i]`), enabling specialized lowering.

Native backend lowering:
- For `recv_kind == "list_int"`, emit direct int64 loads/stores.
- Keep bounds checks for correctness (hoist later if safe).

### Safety & compatibility

- Existing list behavior is unchanged.
- `list<int>` is explicit, not automatic.
- Generic list ops can detect `LIST_INT_KIND` and use specialized helpers.

---

## 4B) Unboxed `list<int>` in AVM / OBC (rolling)

### Context

OBC/AVM remains far from C on list-heavy benchmarks because list payloads are boxed
as `AvmValue[]`. Fused opcodes reduce dispatch overhead, but each iteration still
loads boxed values and pays memory bandwidth + tag overhead.

### Goals

- Unbox AVM `list<int>` payloads to reduce per-element overhead.
- Preserve deterministic execution and snapshot/restore correctness.
- Keep the change explicit and opt-in for rolling safety.

### Non-goals

- Generalize to all list element types.
- Replace boxed lists across the board.
- Add JIT/host-specific SIMD in the interpreter.

### Proposed representation (rolling)

Introduce a dedicated list-int payload in AVM rather than overloading boxed lists:

Option A (explicit value type):
- Add `AVM_VAL_LIST_INT` and `AvmListInt`:
  - `count`, `capacity`, `int64_t* items`
- Update `GET_INDEX` / `SET_INDEX` and list ops to accept both list kinds.

Option B (dual payload in AvmList):
- Extend `AvmList` with `int64_t* int_items` + `int has_int_items`.
- `oren_new_list_int` allocates `int_items` and sets `all_int = 1`.
- Non-int writes drop `int_items` and fall back to boxed semantics.

Option A is clearer and avoids dual-payload edge cases, but requires a new value
type and broader VM handling. Option B minimizes value-type churn but is trickier
to keep correct under mixed list operations.

### Bytecode lowering (preferred)

- Lower `oren_new_list_int(cap)` to a new opcode (e.g. `NEW_LIST_INT`) that returns
  the unboxed list-int value.
- Lower `oren_list_int_push` / `oren_list_int_get` / `oren_list_int_set` to dedicated
  opcodes that operate on list-int payloads.
- Extend `LIST_SUM_INT_LOOP` / `LIST_DOT` / `LIST_SUM3_INT_LOOP` to fast-path list-int
  payloads using `int64_t*` directly.

### Snapshot + determinism

- Snapshot encoder/decoder must handle the new list-int value type or payload.
- Hashing and trace output must be identical across hosts (no platform-specific
  float behavior; int64 only).

### Rollout (AVM)

1) Add list-int payload (Option A or B) + serialization support.
2) Add bytecode opcodes + lowering for list-int new/push/get/set.
3) Update fused loop ops to use `int64_t*` payload when available.
4) Add AVM-focused benchmarks for list-int loops and integrate into `RESULTS_LATEST.md`.

---

## 5) Interaction between container ops and `list<int>`

- `push(xs, v)` on a `list<int>` should lower to `oren_list_int_push` once the
  compiler knows `xs` is `list<int>`.
- Index ops (`xs[i]`, `xs[i] = v`) lower directly to unboxed loads/stores.
- This design preserves the same surface syntax while enabling fast paths.

---

## 6) Tests, benchmarks, rollout

### Tests (native)

- `tests/native/test_list_int_basic.oren`
- `tests/native/test_list_int_bounds.oren`
- `tests/native/test_list_int_mixed_reject.oren`

### Benchmarks

- Re-run `array_sum` and `dot_product` with `list<int>`; expect large reduction
  in native overhead relative to C.

### Rollout plan

1) Runtime kind + helpers.
2) Compiler surface (explicit constructor/marker) + lowering.
3) Tests + benchmarks.
4) Optional conversions (e.g. `list.to_int_list`).

---

## 7) Open questions

- Syntax choice: `list.int_new`, annotation, or new literal form.
- Standard library surface for dual dispatch (`list` vs `list<int>`).
- Behavior for `nil` in `list<int>` (likely disallow).
