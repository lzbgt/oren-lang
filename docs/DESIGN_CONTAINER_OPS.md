# Container Operations (push/len/get) — Generic + `dyn` Design

This document proposes a production-oriented design for **container operations** in Oren
(e.g. `push`, `len`, `get`, `set`, iteration) that is:

- **Generic-first** (static dispatch when types are known).
- **`dyn`-friendly** (dynamic dispatch when using trait objects / interface values).
- **Performance predictable** (fast paths for built-in containers; optional fallible APIs).
- **Future-proof** (user-defined containers can participate without compiler rewrites).

This is written to keep Oren modern and ergonomic without destabilizing the compiler/runtime
bootstrap chain.

---

## 0) Goals and Non-goals

### Goals

1) **Modern surface syntax**
   - Allow clean code like `push(xs, v)` and/or `xs.push(v)` later.
2) **Extensibility**
   - User-defined container types can support `push`/`len` via traits.
3) **`dyn` support**
   - `push(&mut dyn Push[T], v)` works and dispatches through a vtable.
4) **Performance**
   - When container type is known, calls monomorphize (static dispatch).
   - Built-in containers can lower directly to intrinsics (no abstraction penalty).
5) **Stability of the kernel ABI**
   - The low-level `oren_*` functions remain stable and reserved.

### Non-goals (for the first implementation slice)

- Implementing the full trait-object ABI/vtable machinery if it is not already stable.
- Adding operator overloading syntax (`<<`, `+=`, etc.) immediately.
- Renaming `oren_*` intrinsics in-place (too risky for bootstrapping and lowering).

---

## 1) Three-layer model (recommended)

To avoid breaking bootstrapping and backend lowering, treat the system as three layers:

### Layer A — Kernel intrinsics (`oren_*`)

Examples: `oren_list_push`, `oren_list_len`, `oren_string_len`, `oren_buf_len`, …

Properties:
- **Reserved namespace**: `oren_*` is not idiomatic user API.
- **Compiler/runtime coupling**: compiler lowering and/or runtime exports may depend on these exact names.
- **Stability**: keep stable; avoid renaming.

### Layer B — Stdlib wrappers (today’s safe step)

Provide small wrappers in `lib/std/*` that call `oren_*`.

Example (today): `lib/std/list.oren` exports `list.push(xs, v)` which calls `oren_list_push(xs, v)`.

Properties:
- Zero ABI risk.
- Enables incremental migration away from noisy `oren_*` in most code.
- Provides a place to standardize semantics and naming.

### Layer C — Language-level “operations” (future)

Treat `push`, `len`, etc. as **language operations** that the compiler can lower:
- to intrinsic fast paths for built-ins, or
- to trait calls for user-defined containers, or
- to vtable calls for `dyn`.

This layer gives Oren the “modern language feel”.

---

## 2) Core idea: `push` is an operation, not a specific function

Instead of hardcoding “list push”, define **a standardized contract**:

### Trait-based contract (generic)

Conceptual sketch:

- `trait Push[T] { fn push(self: &mut Self, value: T) }`

Then:
- `[]T` implements `Push[T]`
- future containers (`Vec[T]`, `RingBuf[T]`, `SmallVec[T]`, typed buffer builders, etc.) can implement it too

### `dyn` contract (dynamic dispatch)

If Oren supports trait objects:
- `&mut dyn Push[i32]` should dispatch `push` via a vtable.

This is essential for plugin-like extensibility, heterogeneous container handling, and “object capability”
patterns where container implementations vary behind an interface.

---

## 3) Desugaring / lowering rules (deterministic and future-proof)

Define `push(container, value)` as a *single semantic operation* with deterministic lowering:

1) **Intrinsic fast path (built-in container)**
   - If the typechecker knows the container is a built-in list type (`[]T`):
     - Lower to `oren_list_push(container, value)`.
   - This preserves performance and keeps kernels simple.

2) **Static trait dispatch (generic)**
   - Else if the typechecker can resolve an impl `Push[T] for C`:
     - Lower to the statically resolved impl method.
   - This monomorphizes for known `C`.

3) **Dynamic dispatch (`dyn`)**
   - Else if the container is `dyn Push[T]`:
     - Lower to a vtable call.

4) **Otherwise: type error**
   - “type does not support push”

This gives a clean “best available dispatch” strategy that stays stable over time.

---

## 4) Semantics: infallible vs fallible push

For production/server-grade behavior, define semantics early:

### `push` (infallible convenience)

- Signature conceptually: `push(&mut C, T) -> nil`
- On OOM:
  - either panic/abort (simple, fast), or
  - obey a configured allocator policy (future).

### `try_push` (fallible)

- Signature conceptually: `try_push(&mut C, T) -> bool` or `-> Result[nil, Err]`
- Useful for:
  - long-running servers,
  - HPC batch jobs that prefer controlled failure,
  - sandbox/capsule modes that restrict allocations.

Recommendation:
- Provide both: `push` and `try_push`.

---

## 5) Interaction with built-in syntax (`xs.push(v)`)

Method-call syntax is optional sugar:

- `xs.push(v)` could desugar to `push(xs, v)`
- Or it could desugar to a trait method call directly (depending on language design)

Either way, it should preserve the dispatch rules above.

This makes “push as operator” compatible with `dyn` and generics.

---

## 5.1 Performance note: “not a function call” at runtime

It is correct to be suspicious of *generic userland function calls* in hot code, but the
important distinction is:

- **surface syntax** (what the program text looks like), vs
- **lowered form** (what codegen actually emits).

For container ops like `push` and `len`, the intended design is:

- user writes an ergonomic operation form (e.g. `xs.push(v)` or `push(xs, v)`),
- the compiler recognizes this as a **container operation**, and
- lowers it to an intrinsic fast path (e.g. `oren_list_push(xs, v)` / `oren_list_len(xs)`).

This means there is **no extra call overhead** vs “operator syntax”, because the call is not
implemented as an indirect dispatch through a normal function symbol.

### Why `get/set` should stay index-based

For lists, `get` and `set` already have an optimal surface syntax:

- `x = xs[i]`
- `xs[i] = v`

These should remain the canonical way to access and update elements. They:

- avoid naming issues (`get` vs `at` vs `index`),
- are trivially optimizable in all backends,
- match the “container ops are not library calls” direction.

### Why `push` needs a dedicated operation

Unlike `set`, `push` mutates container length and may trigger growth/allocation.
Index syntax alone can’t represent “append” unless the language adds auto-grow semantics
to `xs[len(xs)] = v` (not recommended; it blurs bounds safety and is hard to make deterministic).

So `push` should be a first-class **operation** with deterministic lowering.

---

## 6) List cloning and slice views (production ergonomics)

Oren’s built-in list values are **mutable heap objects**. That implies:

- **Assignment is cheap** (it copies a reference to the same list object).
- “Copy” must be explicit when you want independent mutation.

### Heterogeneous elements (dynamic “value” list)

In rolling v0, lists store **boxed runtime values** (they are not unboxed “`Vec<T>`” arrays).
Practically:

- A list may be **heterogeneous** at runtime (different element kinds in the same list).
- “Element types” are therefore a *static intent* (casts at boundaries), not a guaranteed storage layout.
- If you need stable numeric layout/perf, use **typed buffers** (`[]i32`, `[]f32`, `[]f64`, etc.) rather than lists.

This matters for copy/view operations:

- `clone(xs)` and `slice_copy(xs, ...)` are **shallow**: they copy element values as-is (references remain shared).
- `slice_view(xs, ...)` is a **view**: it never copies elements and reflects the underlying list at iteration time.

### `clone(xs)` — explicit shallow copy

Recommended semantics for rolling v0:

- `clone(xs)` returns a **new list** containing the same element values (shallow copy).
- Nested containers are not deep-copied (consistent with reference semantics).

### `slice_copy(xs, off, n)` — copying subrange

- Returns a new list containing `n` elements starting at `off`.
- Returns an `Err` map on out-of-bounds instead of panicking (server/HPC friendly).

### `slice_view(xs, off, n)` — cheap non-copy view (iterator-first)

Lists do not currently have a dedicated “view” runtime value kind, but we can still provide
an O(1) non-copy slice view using the existing “iterable map” protocol.

Shape (rolling):

- `{"__iter":"list_slice","base":xs,"off":off,"len":n}`

Backends implement this in `oren_iter_next` so `for x in list.slice_view(...) { ... }` yields
the underlying list elements, not metadata.

Important native-backend constraint:
- The marker `"list_slice"` must be a **string literal** so the native runtime can safely do
  pointer equality on `__iter` values without calling `strcmp` on untagged integers.

---

## 6) Naming policy (important for stability)

### Reserve `oren_*`

- Treat `oren_*` as “kernel namespace”.
- Keep it stable and non-idiomatic.

### Stdlib / userland should prefer `std/*`

Examples:
- `list.push(xs, v)` instead of `oren_list_push(xs, v)`
- `string.len(s)` instead of `oren_string_len(s)`

### Reserve operation names

Names like `push`, `len`, `get`, `set`, `iter`, `next` should be treated as:
- candidates for language-level operations (future),
- with standardized semantics.

---

## 7) Implementation plan (incremental, low-risk)

### Phase 1 (now): wrappers + documentation

1) Add `lib/std/list.oren` wrappers calling `oren_list_*`.
2) Start migrating non-kernel code to use `list.*` wrappers.
3) Keep bootstrapping stable (no intrinsic renames).

### Phase 2: compiler-directed lowering for operations

1) Teach the compiler to recognize `push(xs, v)` as an operation.
2) Apply the deterministic dispatch rules:
   - intrinsic for `[]T`,
   - otherwise trait resolution,
   - otherwise `dyn` vtable.

### Phase 3: audits + enforcement

Add repo audits to:
- discourage direct `oren_*` usage in most stdlib modules,
- keep a tight allowlist for low-level kernel/ABI code.

---

## 8) Current repository status

- The compiler’s CLI has been modernized to parse click-style args (`--opt=value`, interspersed args).
- This document establishes the same “modern Oren feel” direction for core container operations.
