# Oren Type System Plan (Rolling → Production)

This document is **design guidance** (not a frozen spec).

Oren today is *semantically typed at runtime* (tagged values), but it is still missing a **production-grade static type layer** needed for:

- safe & fast syscall-first servers (no accidental allocations/conversions)
- scientific/HPC + SIMD-friendly code (explicit widths, predictable layout)
- FFI and packet parsing (endianness and packed views)
- future self-hosting (compiler & AVM in `.oren`)

The strategy is **gradual typing**: keep v0 bootstrapping and keep running code working, while making it possible to incrementally enforce compile-time types.

## 0) Non-negotiables (project constraints)

1) **Rolling ABI / rolling language** until v1 is explicitly stabilized.
2) **Syscall-first** for the native backend runtime (no libc shims).
3) **Deterministic semantics** (esp. for AVM and replay).
4) **Casting must be cheap**: casts are compiler-lowered rewrites or back-end intrinsics, not user-level function calls.

## 1) Current state (v0 reality)

### Runtime types (today)

- runtime values are tagged: `nil`, `bool`, `int`, `float`, heap/object, etc.
- many operations are dynamically typed (and panic/error on mismatch)

### "Type annotations" (today)

Oren already has `: <type>` annotation positions:

- locals: `var x: u8 = ...`
- fields: `struct H { len: u16be }`
- fn params/returns: `fn f(x: u8): u8 { ... }`

In v0 these annotations are currently implemented as a **lowering pass**:

- annotated values are **normalized at boundaries** (wrap/truncate for ints, deterministic rounding for `f32`, etc.)
- this gives immediate cross-backend meaning without requiring full static typing yet

### Cast sugar (today)

`u8(x)`, `i32(x)`, `f32(x)`, `bool(x)`, and endian-tagged spellings (`u16be(x)`) are treated as **builtin cast sugar**:

- the compiler rewrites them into deterministic cast expressions (integers) or intrinsic calls (`oren_f32_round`, `oren_bool_norm`, `oren_trunc_int`).
- the **native backend can inline** these intrinsics (no function call overhead in the emitted binary).

## 2) Target model: "Static when you want it"

Oren should support *both*:

1) **Compile-time polymorphism** (monomorphized generics)
2) **Runtime polymorphism** (trait objects / protocol objects)

They solve different problems:

- compile-time: maximum performance, no virtual calls, best for HPC/networking
- runtime: heterogenous containers, plugin-like architectures, reflective tooling

### 2.1 Primitive width types are language tokens (not attributes)

These are **core type tokens**, not annotation attributes:

- signed: `i8 i16 i32 i64 i128 isize`
- unsigned: `u8 u16 u32 u64 u128 usize`
- floats: `f32 f64`
- `bool`, `nil`, `string`, `bytes`

Endianness should be represented as **type-level wrappers**, not as separate primitive kinds:

- `u16be`, `u16le`, etc. are convenient surface spellings, but internally they should desugar to:
  - "stored as bytes with an endian view", or
  - "parse from bytes as endian and produce a host-order scalar"

Which one is chosen is context dependent (packed structs vs scalar arithmetic).

### 2.2 Packed structs are "views" (zero-copy) by default

For packet parsing and syscall-first networking, the primary story should be:

- `@pack struct Header { ... }` defines a **layout view**
- accessors read/write from `bytes` or `ptr` without heap allocations

This gives correctness + performance without requiring a huge GC story to be perfect first.

### 2.3 Traits / protocols: compile-time + runtime

We want "primitives implement traits" because:

- it gives uniform APIs: `Eq`, `Ord`, `Hash`, `Add`, `BitAnd`, etc.
- generic algorithms work over `u32`, `i64`, structs, etc.

But we need to avoid "define trait impls manually for every primitive".

Plan:

- **compiler-provided blanket impls** for builtins:
  - e.g. `impl<T: Int> Add for T` is not expressible in v0, but can be treated as a builtin rule.
- later, when generics exist:
  - true blanket impls become a first-class surface feature.

Runtime trait objects (`dyn Trait`) are separate and optional:

- needed for heterogenous lists and plugin-like patterns
- not needed for HPC hot loops

## 3) Roadmap (phased, to minimize rewrites)

### Phase A — "Typed boundaries" (v0 → v0.5)

Goal: **make the current lowering model correct and complete**, without trying to reject programs yet.

- [casting] finalize builtin cast sugar set + semantics
- [syntax] add a dedicated cast operator: `expr as u16` (desugars to builtin cast)
- [meta] compiler emits a stable type-kind in metadata for every annotated node

### Phase B — Gradual type checker (v0.5)

Goal: allow `oren build --typecheck` (or default later) to *validate* annotated code.

- verify that annotated boundaries do not produce impossible values:
  - e.g. `f32(x)` requires floaty input
  - `u8(x)` requires numeric input (or define coercion rules explicitly)
- type-check function signatures:
  - callers must satisfy param types (with explicit casts)
  - return expression must satisfy return type

This is a "lint that can be turned into an error" while the language is rolling.

### Phase C — Full static types + generics (v1 direction)

Goal: production compiler capabilities:

- full type inference for `var` with explicit width tokens available
- generics + constraints (traits/protocols)
- monomorphization for performance
- trait objects for runtime polymorphism (explicit)

## 4) Casting rules (production intent)

Oren should be explicit like C for performance, but also deterministic and documented:

- integer narrowing uses wrap/truncate (unless a checked-cast form is used)
- float narrowing `f64 -> f32` is deterministic rounding to IEEE-754 float32 then widening
- endian casts are **not arithmetic casts**; they are view/parse conversions with explicit semantics

We intentionally avoid a separate "strict mode" toggle:

- the language semantics themselves should be strict and deterministic.
