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

## 5) Bootstrap reality (v0 rolling)

Current implementation status:

- `trait` and `impl` syntax exists and is accepted by the parser.
- `impl` is lowered deterministically into top-level functions (bootstrap strategy).
- No runtime trait objects exist yet.

See also:

- `docs/OBJECT_MODEL.md`
- `docs/LANGUAGE_SPEC.md`
