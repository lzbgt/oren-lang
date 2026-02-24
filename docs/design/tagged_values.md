# Tagged Value Convergence Plan (Rolling)

**Last updated:** 2026-02-24

This doc expands the tagged value convergence plan into a concrete, staged
roadmap. It is intentionally lean and defers to the code + fixtures for
ground truth. See also `docs/DESIGN.md` and `docs/LANGUAGE.md`.

---

## Goals

- One canonical value model across native, C, and AVM.
- Stable `oren_type_tag` / `oren_type_name` semantics across backends.
- Deterministic truthiness, equality, and container type tests.
- Staged migration that keeps Tier-1 fixtures green.

## Non-goals (rolling)

- ABI/opcode stability across releases.
- Immediate performance parity with industrial compilers.
- Rewriting all backends at once; migrations are staged.

---

## Current facts (from docs)

- Native tagging is partial; `oren_type_tag` is best-effort for scalars.
- `nil`/`false`/`true` are runtime singleton values in native mode.
- AVM uses a tagged `AvmValue` representation.
- The OrenType tag map (nil/int/float/bool/string/list/map/func/typed buffers)
  is already documented in `docs/DESIGN.md`.
- Truthiness semantics are defined in `docs/LANGUAGE.md`:
  - `nil` and `false` are falsey
  - everything else is truthy
  - numeric `0` is truthy (do not treat 0/1 as booleans)

---

## Semantic invariants to pin

These must hold across native/C/AVM for production readiness:

- Truthiness rules per `docs/LANGUAGE.md` (nil/false falsey; everything else truthy).
- Scalar vs nil guards remain deterministic (compiler rejects scalar == nil where proven).
- `oren_type_tag` / `oren_type_name` agree across backends for:
  - nil, bool, int, string, list, map, func, typed buffers
- `list` and `list_int` both map to tag 6 until a dedicated list_int tag is introduced.

---

## Staged migration plan

### Stage 0: Observability and parity gates

- Ensure parity fixtures cover:
  - truthiness rules
  - type tags/names
  - equality of mixed-type values
- Keep `make verify-backend-parity-tags` green.

### Stage 1: Canonical tag helpers per backend

- Introduce explicit encode/decode helpers in each backend:
  - native: `native_tag_encode_*`, `native_tag_decode_*`
  - C: `oren_tag_encode_*`, `oren_tag_decode_*`
  - AVM: `avm_tag_encode_*`, `avm_tag_decode_*`
- Route `oren_type_tag` and `oren_type_name` through the helpers.

### Stage 2: Scalar tagging in native codegen

- Migrate native backend to emit canonical scalar tags (int/float/bool).
- Keep compat shims so older fixtures remain valid during the transition.
- Add a targeted fixture that distinguishes int vs float via `oren_type_tag`.

### Stage 3: Remove best-effort scalar tagging

- Remove the native “best-effort” fallback once canonical tags are reliable.
- Tighten fixtures to require scalar tag correctness across backends.

---

## Decision points (to resolve)

These need explicit decisions before Stage 2:

- Representation choice for native scalar tags (evaluate options):
  - pointer tagging
  - NaN-boxing
  - split payload + side table
- Compatibility rules for mixed tagged/untagged values during migration.
- Performance guardrails for hot paths (type-tag checks in tight loops).

---

## Deliverables (tracked in `docs/STATUS.md`)

- Tagged value convergence plan in P0.
- Expanded parity fixtures for tags/names/truthiness.
- Backend mapping table stays updated in `docs/DESIGN.md`.
