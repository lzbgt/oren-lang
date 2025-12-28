# Native Tagged Value Representation (ARM64 + x86_64) — Design + Migration Plan (Rolling)

This document is **design guidance** for converging the **native backend** (arm64 + x86_64) onto a production‑grade **tagged value** model that is consistent with:

- the **C backend** value model (`lib/runtime.h`: `OrenValue { type, union }`)
- the **AVM** value model (tagged value types + tagged constants; see `docs/AVM_SPEC.md`)
- the language semantics in `docs/LANGUAGE_SPEC.md` (type‑strict equality, `nil` distinct from `false`, etc.)

## 0) Why this is urgent (current mismatch)

### Current state by backend

1) **C backend** (today): values are structurally tagged
   - `lib/runtime.h` defines `OrenValue` as `{ OrenType type; union {...} }`.
   - This can represent `nil`, `bool`, `int`, `float`, `string`, list/map/function, typed buffers, etc.

2) **AVM** (today): values are tagged (VM tag + payload)
   - The VM needs a tag for determinism and serialization.

3) **Native backend** (today):
   - values are mostly treated as **untagged `i64` carriers** in registers/stack.
   - heap objects (lists/maps) are recognized via **magic words** at fixed offsets (e.g. `'LIST'`, `'MAP\0'` in x64 bring‑up).
   - **Rolling status (x86_64 bring-up):** the historical “`key < 4096`” map key heuristic is removed.
     - map get/set now require an explicit `known_key_kind` hint inferred during shared lowering (conservative; unknown cases abort on the map path)
     - this is still not a final value model: it is an incremental step until the native backend adopts an explicit tagged representation (so key types are carried as data, not guessed or assumed)

### Why a tagged representation is required

The language semantics require:

- `nil` distinct from `false`
- type‑strict `==` / `!=` (e.g. `1 == 1.0` is false)
- maps where keys can be `int` or `string` (and eventually other types) without “magic numeric ranges”
- predictable serialization and determinism (AVM + replay)

So the native backend must not depend on “is it < 4096?” or “does it look like a pointer?”.
Even “compiler-inferred key kind” is only a stopgap — production requires a principled tagged value model.

## 1) Design goals (production constraints)

Non‑negotiable goals:

1) **Cross‑backend semantic convergence**
   - a program’s results must match across native / C / AVM (modulo performance).

2) **Determinism**
   - representation must not depend on host allocator pointer patterns.

3) **Performance on 64‑bit CPUs**
   - values should stay “register‑friendly” for hot loops and syscall‑first servers.

4) **Staged rollout**
   - rolling mode allows refactors, but we must avoid “big bang” changes that stall progress.

## 2) Representation options (with tradeoffs)

### Option A — Box everything (pointer to heap object with an explicit type tag)

**Idea:**
- Every value is a pointer to a heap object with a header `{tag, payload...}`.

**Pros:**
- simplest semantics
- no bit‑level tricks; full range for ints/floats

**Cons:**
- too slow / too GC‑heavy for HPC + server hot paths
- complicates FFI and syscall boundaries

This is not recommended as the long‑term default.

### Option B — Low‑bit pointer tagging (immediates + heap pointers)

**Idea:**
- Represent some values as immediates (e.g. `nil`, `bool`, small `int`) using a tag in low bits.
- Represent heap objects as aligned pointers.

**Pros:**
- common systems‑VM technique; fast branches for small ints / bool / nil
- keeps heap objects as pointers (good for lists/maps/strings/bufs)

**Cons:**
- “small int” immediate cannot represent all `i64` values if low bits are used for tags.
  - therefore large ints require boxing (or a separate representation rule)
- requires **all strings to be heap objects** (string literals cannot be raw `char*` without a header/type)

This is a strong candidate if we accept “small int immediate + boxed big int” as the dynamic `int` runtime model.

### Option C — NaN-boxing (float + non-float values share one 64-bit word)

**Idea:**
- Use IEEE‑754 `f64` bit patterns:
  - non‑NaN values represent floats
  - a chosen NaN range encodes `nil/bool/int/pointer` payloads

**Pros:**
- efficient `float` path (no boxing for floats)

**Cons:**
- highest implementation complexity
- requires careful, explicit decisions about NaN payload canonicalization for determinism
- requires precise documentation and cross‑backend conversion rules

This is viable for a production VM, but should be staged in after a simpler “pointer tagging + boxed float” path if needed.

## 3) Recommended staged plan (rolling)

### Phase 1 — Remove “heuristics” by introducing explicit key tagging

Goal: remove the x64 map key heuristic and make map key type checks explicit.

Minimal work required:

1) **Strings become heap objects** in native mode (including literals)
   - string values must carry a type identity (`STRING`) that is not “pointer range dependent”.
   - string comparisons and `len/slice` can then dispatch by type.

2) **Map entries store a typed key representation**
   - use a canonical key tag (`INT`, `STRING`, later `BOOL/NIL`, etc.)
   - do not infer key type from the numeric value.

This phase can be implemented without committing to a final universal 64‑bit value layout, as long as maps can reliably distinguish key types.

### Phase 2 — Converge native values to a canonical tagged model

Goal: a single value model for native backend codegen that matches language semantics:

- `nil`, `bool`, `int`, `float`, heap/object, function, typed buffers.

Recommended direction:

- adopt **pointer tagging** for `nil/bool/small-int` + heap pointers
- box “big int” values outside the small‑int range
- initially box floats (or treat floats as a separate heap object), then consider NaN‑boxing later if float perf becomes a bottleneck

### Phase 3 — Align C backend + AVM conversions explicitly

Goal: deterministic conversions between:

- C backend `OrenValue` (struct tagged)
- AVM `AvmValue` (VM tagged)
- native backend “word” (tagged/boxed)

This requires:

- a canonical set of runtime tags (shared enum in docs + tooling)
- explicit boundary conversion helpers

## 4) Immediate next engineering tasks (what to implement next)

1) Decide and document a **canonical runtime tag set** for: `nil/bool/int/float/string/list/map/func/buf`.
2) Define the native string object layout (header + length + bytes pointer / inline bytes policy).
3) Replace x64 map key heuristic with explicit tagging:
   - store key tag in each entry
   - compare keys by `(tag, value)` not by “value range”
4) Add fixtures:
   - map key cases that currently break the heuristic (e.g. integer key `50000`)
   - `nil` vs `false` equality semantics (native must match C/AVM)

## 5) Notes on correctness vs performance

- For production server workloads, **correctness + determinism** are non‑negotiable.
- Performance can be recovered incrementally:
  - inline fast paths for small ints
  - typed buffers for HPC avoid dynamic boxing entirely
