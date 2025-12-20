# Traits & Polymorphism (Static-first, Dyn-opt-in)

**Status:** Design doc (rolling; implementation may evolve)
**Scope:** Oren language semantics + AVM determinism constraints

This repo targets a “modern systems language” experience while keeping AVM execution:

- deterministic (replayable / consensus-friendly)
- capability-governed (FS/NET/PROC/ENV/TIME)
- efficient (no hidden allocations, SIMD-friendly data types)

That combination strongly suggests a **two-tier polymorphism model**:

1) **Static (compile-time) polymorphism**: zero-cost, deterministic, preferred.
2) **Dynamic (runtime) polymorphism**: explicit opt-in, governed, and restricted where necessary.

This document explains why both are needed, and how to keep the model elegant.

---

## 1) Why both static and dynamic exist

### Static dispatch is best for “systems + determinism”

Static polymorphism is what you want for:

- syscall-first stdlib wrappers (hot paths)
- numeric kernels and typed buffers (`i32_buf`, `f32_buf`, …)
- compiler-in-AVM style pipelines (predictable semantics)
- deterministic hashing (trace/result hashes)

Because:

- calls can be inlined / specialized
- no runtime vtables are required
- behavior is determined by source + compilation output only

### Dynamic dispatch is best for “plugins + heterogeneous containers”

Dynamic polymorphism is what you want for:

- plugin-style tool interfaces selected at runtime
- heterogeneous containers (e.g. list of “things that implement Writer”)
- cross-module / cross-universe boundaries where concrete types are unknown upfront

But it must be **explicit** and **governed**, because hidden runtime dispatch makes
performance, debugging, and determinism harder.

---

## 2) The recommended Oren model (v1 direction)

### 2.1 `trait` means compile-time by default

**Rule:** `trait` is a compile-time contract. It does not imply a runtime representation.

The “happy path”:

```oren
trait Add {
    fn add(self, rhs)
}

impl Add for i32 {
    fn add(self, rhs) { return self + rhs }
}

fn f(x, y) {
    // static dispatch: compiler resolves the impl
    return x.add(y)
}
```

### 2.2 `dyn Trait` (or equivalent) is explicit runtime dispatch

**Rule:** runtime polymorphism must be opt-in (spelled in source), e.g.:

```oren
var w: dyn Writer = make_writer()
w.write("hi")
```

Exact syntax is rolling, but the property is non-negotiable:

- if dispatch is dynamic, the source must say so.

---

## 3) Determinism constraints for runtime trait objects

If AVM is used for consensus/replay/snapshots, “trait objects” cannot be “host pointers”.

### 3.1 Stable representation (no host-pointer identity)

A trait object must be a deterministic value, conceptually:

```
{ value, vtable_id }
```

Where `vtable_id` is derived from deterministic program identity, such as:

- module path
- trait name
- impl symbol set (methods)
- (optional) version hash of the impl body / symbol signature

Never derive it from:

- process address
- dynamic loader pointers
- host timestamps

### 3.2 Governance / policy

Some operations must be restricted or explicitly defined:

- Equality: comparing trait objects by pointer identity is non-deterministic across universes; avoid or forbid.
- Hashing: using trait objects as map keys must be forbidden unless a stable hash is defined.
- Serialization: crossing universe boundaries needs a stable encoding; otherwise forbid by policy.

A simple safe rule for early v1 is:

- trait objects are callable only,
- but not comparable and not hashable,
- and not allowed as map keys.

---

## 4) How this relates to AVM and “modern power”

### 4.1 Static traits give you zero-cost abstractions

Static traits cover most “modern language” use cases:

- iterators (compile-time lowering)
- numeric traits (`Add`, `Mul`, etc.)
- serialization helpers (derive-like expansion from metadata)

### 4.2 Dynamic traits enable agentic tool interfaces

When you need “a list of tools” chosen dynamically, `dyn Trait` becomes useful,
but it must integrate with:

- capability model (tool calls are effects)
- determinism (record/replay, hashes, snapshots)

Treat runtime polymorphism as a **VM feature**, not just “syntax sugar”.

---

## 5) Generic traits without per-type boilerplate (blanket impls + defaults)

The pain you’re pointing at is real: if Oren requires writing `impl Add for i32`, `impl Add for i64`, `impl Add for u64`, … for every trait, the model becomes noisy and *not* AI/agentic-friendly.

A modern, elegant way to avoid that is to support **generic trait mechanisms** at the *language* level, but keep them **deterministic** and **toolable**.

There are three complementary mechanisms; Oren should use **all three**, but staged.

### 5.1 Trait default methods (big win, minimal complexity)

Allow traits to provide **default method bodies**, expressed only in terms of:

- other trait methods
- pure operators on primitives
- whitelisted builtin helpers

Example direction:

```oren
trait Eq {
    fn eq(self, rhs)

    // default impl in terms of eq
    fn ne(self, rhs) { return !self.eq(rhs) }
}
```

Why it matters:

- you implement the “minimum core” (`eq`) once per type,
- you get a full surface (`ne`) for free,
- it does not require generics or a type checker.

Determinism note: defaults are just code; they compile like any other function and are deterministic.

### 5.2 Blanket impls / impl templates (“generic impl”) 

A **blanket impl** is an implementation that applies to a *family* of types.

This is how Rust avoids per-type boilerplate for `Option<T>`, `Vec<T>`, etc.

In Oren’s rolling world (where we’re still growing the type system), the *most future-proof* plan is:

- support generic impls over **nominal types** *once generics exist* (v1+), and
- in v0/v0.5, allow a limited “kind constraint” form for primitives/containers.

Rolling v0 (implemented today) also supports a minimal “catch-all” blanket:

```oren
// Applies to any runtime value.
// This is intentionally limited (no constraints yet) but unblocks ergonomic defaults.
impl Eq for any { fn eq(self, rhs) { ... } }
```

Resolution rule:

- If both `impl Trait for Type` and `impl Trait for any` exist, the concrete `Type` impl wins.

Conceptual examples (v1 direction):

```oren
// Applies to any T that is Eq.
impl[T] Eq for Option[T] where T: Eq {
    fn eq(self, rhs) {
        // ... compare tags and payloads ...
    }
}

// Applies to any T that is ToString.
impl[T] ToString for List[T] where T: ToString {
    fn to_string(self) { ... }
}
```

For primitives, you want “blanket over kinds”:

```oren
// Applies to all signed integer widths.
impl Eq for signed_int {
    fn eq(self, rhs) { return self == rhs }
}

// Applies to all floats.
impl Eq for float {
    fn eq(self, rhs) { return self == rhs }
}
```

We don’t have `signed_int`/`float` kind types yet — but *documenting this now* keeps the model coherent, and lets us add the syntax later without rewrites.

### 5.3 Derive-style expansion (attributes) for “data traits”

For traits that are purely structural (serde, hashing, comparisons), the most ergonomic solution is a derive.

Example:

```oren
@derive(Eq, Hash)
struct User { id: u64, name: string }
```

This is not runtime reflection.

It is **compile-time code generation** driven by metadata, which is deterministic and AVM-friendly.

---

## 6) Coherence + determinism rules for generic impls (non-negotiable)

Generic impls are powerful, but they can destroy determinism if resolution is ambiguous.

Oren should adopt a simple, strict **coherence rule** (Rust-like):

1) For any pair `(Trait, Type)`, there must be **at most one applicable impl**.
2) If multiple impls could apply, compilation is an error **unless** there is a single “most specific” impl by a well-defined subsumption rule.
3) Cross-module resolution must be deterministic:
   - the set of visible impls is determined by explicit imports/modules,
   - no runtime discovery, no reflection.

Rolling v0 enforcement (implemented):

- **Single impl block rule:** there must be exactly one `impl Trait for Type { ... }` block per `(Trait, Type)`.
  - Splitting methods across multiple impl blocks is rejected deterministically.
- **Blanket impl:** `impl Trait for any { ... }` is allowed as a catch-all.
  - Exact `impl Trait for SomeType` overrides the `any` blanket.

### 6.1 Practical staged enforcement (no big rewrite)

- v0/v0.5: keep current explicit `impl Trait for Type` lowering + method-sugar registry.
  - if multiple impls collide on the same `Type.method` name, error (already implemented).
- v1: add an *optional explicit qualification syntax* for ambiguity resolution.
  - example direction: `Trait.method(x, ...)` or `Type::Trait::method(x, ...)` (syntax TBD).
- v1+: introduce blanket impls with a strict overlap checker.

This staging keeps Oren **powerful** while maintaining a **solid foundation**.

## 5) Bootstrap reality (v0 rolling)

Current implementation status:

- `trait` and `impl` syntax exists and is accepted by the parser.
- `impl` is lowered deterministically into top-level functions (bootstrap strategy).
- No runtime trait objects exist yet.

See also:

- `docs/OBJECT_MODEL.md`
- `docs/LANGUAGE_SPEC.md`
