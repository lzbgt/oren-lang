# Reflection v1 (Plan, Rolling)

Oren is still in rolling mode with a v0 dynamic runtime surface, but multiple active tracks now require
**real, stable reflection**:

- **FFI** and syscall-first I/O: stable type/ABI boundaries (`@abi`, `@pack`, typed buffers, endian types).
- **Varargs and generic utilities**: formatting/logging needs to safely inspect “what is inside the rest-list”.
- **Serde** (binary formats, config): schema-driven encode/decode and versioning.
- **Tooling**: docs generation, IDE indexers, linting.

Today, Oren already emits a rich metadata graph (attributes are compile-time metadata, not runtime decorators).
Reflection v1 is the plan to turn that metadata into a **stable, queryable runtime surface** that works across:

- native backends (`arm64-*`, `x64-*`)
- C backend (bootstrap + portability)
- AVM bytecode (`.obc`)

This doc is a design plan; it is not claiming the full surface is implemented yet.

## 0.5) Current rolling v0 (implemented)

As an immediate, low-risk step toward reflection v1, the compiler now tags struct/type-constructor values
with a reserved map key (2026-01-10):

- Struct values are still **map-shaped** in v0 across backends (native, C backend, AVM bytecode):
  - `struct User { id, name }`
  - `User(1, "a")` lowers to: `{"__oren_type":"User","id":1,"name":"a"}`
- The reserved key is **`"__oren_type"`**.
  - User code may not declare a field named `__oren_type` (parser rejects it).
- `oren_type_name(v)` (native + C backend) checks for `__oren_type` when `v` is a map:
  - returns `"User"` for `User(...)`
  - still returns `"map"` for ordinary map literals without the tag.

In addition, the stdlib now exposes a minimal wrapper module:

- `lib/std/reflect.oren` (`std:reflect` in spirit; import path is still rolling)
  - `tag(v)` / `name(v)` wrappers (call through to `oren_type_tag` / `oren_type_name`)
  - stable tag constants (`TAG_NIL`, `TAG_STRING`, `TAG_LIST`, `TAG_FUNC`, …) matching `lib/runtime.h` `OrenType`
    - 2026-01-12: native backend now tags first-class function values as `TAG_FUNC` (guarded by `tests/native/test_quick_integration_native.oren`).
    - 2026-01-13: Tier‑1 native smoke now asserts the non-numeric tag/name contract under real x64 hosts:
      - `tests/fixtures/tier1_native_smoke_main.oren` checks `tag/name` for `nil/bool/int/string/func/list/map/u8_buf`
      - also checks that struct values expose a stable type name via `__oren_type` (even though structs remain map-shaped in v0)

This is intentionally **not** the final reflection design:

- it does not provide a stable `TypeId`
- it does not expose fields/attributes at runtime
- it is a pragmatic v0 affordance to make varargs/logging safer and more informative while the full
  type system and tagged value model are still converging.

## 0) Non-goals (keep scope bounded)

- No compile-time macros / arbitrary code execution in the compiler.
- No “full dependent typing”.
- No runtime `eval`.
- No promise of a final “v2” type system here; this is the minimum reflection layer needed for production stdlib.

## 1) Requirements (what reflection must answer)

Reflection v1 must provide enough information to implement the following *portably* (with the same source file):

1) **Value-level type identification**
   - “Given a runtime value `v`, what is its type?”
   - Must distinguish at least: `nil`, `bool`, `int`, `string`, `list`, `map`, typed buffers (`[]u8`, `[]i32`, …),
     and user-defined `struct` types.

2) **Type descriptor lookup**
   - “Given a `TypeId`, what is the type’s name, module path, and (for structs) fields?”
   - Must provide enough to implement:
     - `to_string` / formatting
     - generic JSON-ish debug printers
     - schema/serde for structs

3) **Field introspection (structs only, v1)**
   - Field name list
   - Field order (stable)
   - Field type ids
   - Optional: per-field attributes (`@doc`, `@serde.*`, `@pack`, `@abi`, …)

4) **Backend portability**
   - The same program should observe the same reflection results under:
     - C backend (stage0/stage1 bootstrap)
     - native backend
     - AVM bytecode
   - Implementation detail differences (value representation, pointer tagging, object layout) must not leak into the reflection API.

## 2) Constraints (what makes this hard in Oren)

Oren v0 is still in rolling mode without a full static type checker, and backends currently use different internal
value representations to get performance and bring-up velocity.

Relevant existing docs:

- Dynamic value representation work: `docs/COMPILER_AND_BACKENDS.md#native-tagged-value-representation`
- Object model direction: `docs/OBJECT_MODEL.md`
- Type-system stabilization direction: `docs/TYPE_SYSTEM_PLAN.md`
- Attribute contract: `docs/ATTRIBUTES.md`

Key constraints for reflection v1:

- **Performance:** reflection must not require 64-byte “fat values” everywhere.
  - Reflection data should be **out-of-line** (tables) and referenced by compact ids.
- **Determinism:** type ids must be stable and reproducible for a build (and ideally across builds when source is unchanged).
- **Cross-arch:** layout/ABI facts must be expressible without assuming one CPU ABI.

## 3) Proposed architecture (two layers)

Reflection v1 is split into two layers:

### 3.1 Compile-time metadata (already exists; formalize as a contract)

The compiler already canonicalizes attributes into deterministic metadata (example: `@cfg(...)` → `@oren.cfg(...)`).

Action for reflection:

- define a single “reflection metadata table” schema as a **compiler output contract**
  - minimal stable types (string, int, bool, list, map)
  - stable keys for common attributes

This table exists even if the program never calls `std:reflect`.

### 3.2 Runtime reflection API (`std:reflect`)

Expose a stable runtime-facing API that reads from the compiled metadata table:

- `type_id_of(v) -> u64`
- `type_info(id) -> TypeInfo`
- `fields_of(id) -> []FieldInfo` (only for structs in v1)

Important: the runtime API must hide how `v` is represented (tagged pointers, boxed objects, etc.).

## 4) Type identity (TypeId)

Introduce `TypeId` as a compact stable identifier:

- width: `u64` (portable across Tier‑1, easy to store in buffers and metadata)
- meaning: identifies a *type descriptor entry* in a per-program type table

Two design choices:

1) **Build-stable ids (recommended for v1)**
   - `TypeId = hash(module_path, type_name, shape_signature, abi_signature, compiler_version_tag)`
   - Pros: can be stable across builds if inputs are stable.
   - Cons: requires careful definition of the hashed inputs.

2) **Index-based ids**
   - `TypeId = index in type table`
   - Pros: simplest.
   - Cons: unstable under unrelated source edits; painful for caches and tooling.

Rolling recommendation: use build-stable hash ids for user-defined types and reserved fixed ids for builtins.

## 5) Minimum “type descriptor” schema

Define `TypeInfo` and `FieldInfo` (conceptual):

- `TypeInfo`:
  - `id: u64`
  - `kind: string` (example: `"nil"`, `"bool"`, `"int"`, `"string"`, `"list"`, `"map"`, `"buf"`, `"struct"`)
  - `name: string` (for structs and named builtins)
  - `module: string` (for structs)
  - `attrs: map` (optional; contains canonicalized `@oren.*` metadata)

- `FieldInfo`:
  - `name: string`
  - `type_id: u64`
  - `index: int` (stable order)
  - `attrs: map` (optional)

For v1, field offsets and sizes are intentionally out of scope unless `@abi` is present and the backend can
guarantee layout stability for the target ABI.

## 6) How this connects to varargs and “rest lists”

In Oren today, varargs calls are lowered by packing the “rest” arguments into a list.

Without reflection, generic utilities (like debug printers, structured logging, `printf`-style formatters)
can only treat rest elements as opaque “dynamic values”.

With reflection v1:

- the stdlib can implement `debug_any(v)` by switching on `type_info(type_id_of(v)).kind`
- `format("%v", v)` can become deterministic across backends
- varargs processing no longer depends on backend-specific heuristics (for example “is this pointer tagged?”)

## 7) Work plan (incremental, production-oriented)

### Phase A — lock the metadata contract (compiler-only)

- Define the reflection type table schema in docs (and enforce deterministic ordering).
- Ensure metadata is emitted consistently across backends (C/native/AVM).
- Add a tiny fixture that compiles under all backends and asserts a stable set of metadata keys exist.

### Phase B — add `std:reflect` and `TypeId` (runtime + stdlib)

- Implement `type_id_of(v)` for v0 dynamic values (native + C + AVM).
- Implement `type_info(id)` by looking up the compiled type table.

### Phase C — struct fields (first-class reflection)

- Emit field lists for `struct` declarations (name + type id + index).
- Implement `fields_of(id)` and add fixtures for “serde-like” traversal.

### Phase D — start consuming reflection in stdlib

- Update varargs utilities (logging/formatting) to use reflection rather than ad-hoc checks.
- Make “rest list element processing” portable and deterministic.

### Phase E — future: ABI-aware reflection (optional)

Once `@abi` structs have a stable per-target layout contract, reflection can optionally expose:

- field offsets
- field sizes
- total struct size

This is needed for safe “memcpy style” FFI tooling, but it must not leak into v1 prematurely.

## 8) Related work (tracked elsewhere)

- Value representation refactor targets: `docs/COMPILER_AND_BACKENDS.md#native-tagged-value-representation`
- Type-system stabilization targets: `docs/TYPE_SYSTEM_PLAN.md`
- Stdlibrary layering (crypto/net split): `docs/STDLIB_LAYERS.md`
