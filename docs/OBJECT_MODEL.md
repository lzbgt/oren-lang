# Oren Object Model (Traits/Protocols + Composition)

**Status:** Draft (rolling)  
**Goal:** a modern, AI/agentic-friendly model that stays syscall-first and multiverse/AVM compatible.

This document defines the recommended object model for Oren:

- **Traits / protocols** for behavior
- **Composition** for code reuse
- **No inheritance-first design**
- **Sum types (ADTs)** for state machines (planned)

It is intentionally aligned with:

- syscall-first native runtime (no libc/pthreads shims)
- AVM determinism + multiverse execution (policy scan, replay, snapshot)

## 1) Principles (what we optimize for)

1) **Governability**
   - Effects (FS/NET/PROC/ENV/TIME) must be explicit and auditable.
2) **Determinism and replayability**
   - Especially for AVM: semantics must not depend on host clocks/schedulers.
3) **Toolability**
   - Disasm/debug/profiling should be able to attribute behavior and cost.
4) **No huge rewrites**
   - Prefer staged evolution; keep v0 bootstrapping possible.

## 2) Data vs behavior

Oren should treat these separately:

- **Data:** `struct` (and later `enum`) — stable shapes, predictable layout/encoding.
- **Behavior:** `trait` — capability/behavior contracts that types can implement.

This mirrors successful systems-language patterns (Rust/Swift/Go-like protocols) and avoids fragile class hierarchies.

## 3) Traits / protocols

A trait defines required functions (methods). Conceptually:

```oren
trait Reader {
    fn read(self, n)
}
```

### Primitives implementing traits (recommended: YES)

Oren should allow **all runtime value kinds**, including primitives, to implement traits:

- integers / floats
- strings / bytes
- lists / maps
- function values / closures
- user-defined structs/enums

Why this matters:

- it keeps the stdlib clean: `to_string(x)` / `hash(x)` / `iter(x)` are uniform
- it avoids special-casing primitives in the compiler and tooling
- it aligns with “protocols + composition” rather than “primitive exceptions”

Determinism note:

- “implements trait” is a **compile-time relation**. It must not depend on host state.
- method resolution must be deterministic given the program and its imports (no reflection-based late binding by default).

Example direction:

```oren
trait ToString { fn to_string(self) }

impl ToString for i64 { fn to_string(self) { return oren_int_to_string(self) } }
impl ToString for string { fn to_string(self) { return self } }
```

### Dispatch policy (recommended)

- Default: **static dispatch** (monomorphize / direct call) where types are known.
- Optional: **dynamic dispatch** via “trait objects” only when needed.

This keeps native performance good and keeps AVM semantics clear.

### Structural vs nominal conformance (rolling decision)

For Oren’s goals (auditable codegen, deterministic replay, self-hosting), prefer:

- **nominal conformance** as the default: `impl Trait for Type` is explicit
- optional **structural conformance** only as a later, opt-in feature (tooling-heavy; easy to make “too magic”)

Nominal `impl` keeps “what code runs” stable and obvious, which matters for consensus-like workflows.

## 4) Composition (preferred reuse mechanism)

Instead of inheritance, reuse behavior and data via:

- embedding fields (has-a)
- forwarding functions
- small traits composed together

Example idea:

```oren
struct TcpConn { fd }
struct BufferedReader { inner, buf }
```

This is more SOLID-aligned than inheritance:

- interfaces (traits) stay small
- data ownership is explicit

## 5) Capabilities as traits (syscall-first + AVM governance)

The most important use of traits in Oren is the OS boundary:

- FS
- NET
- PROC
- ENV
- TIME

Design direction:

- stdlib APIs should accept explicit capability objects (implementing these traits)
- AVM can inject VirtualFS/VirtualNET/VirtualPROC implementations
- native runtime can provide Host* implementations via syscall-first `sys_*`

This prevents “hidden host effects” and composes with nested universes.

## 6) Deterministic dispatch + trait objects

Traits must not re-introduce nondeterminism.

Recommended rules:

1) Static dispatch is pure: calling `T.foo(x)` must be the same across machines.
2) Dynamic dispatch is explicit:
   - “trait object” must be a distinct runtime representation (e.g. `{ v, vtable_id }`), not implicit reflection.
3) VTable identity must be stable:
   - derived from module path + trait name + impl symbol set, not host pointers
4) Cross-universe safety:
   - passing trait objects between universes must preserve semantics or be disallowed by policy.

## 7) Sum types (ADTs) + pattern matching (planned)

For agentic workflows, “closed world” state modeling matters more than class hierarchies.

Example direction:

```oren
enum State {
    Idle
    Running(job)
    Waiting(deadline_ms)
    Failed(err)
}
```

Then:

- `match state { ... }` ensures explicit handling
- later, exhaustiveness checking makes self-healing logic safer

## 8) Implementation reality today (bootstrap)

Current state in this repo:

- `struct`/`class` exist and are represented as runtime maps keyed by strings.
- no user-defined methods, no trait syntax yet
- concurrency primitives are in flux; avoid baking in inheritance assumptions

So this document is the **direction**: it guides evolution without forcing an immediate rewrite.

## 9) Staged implementation plan (minimal rewrite)

1) Add `trait` declarations as compile-time contracts (doc + parser support first).
2) Add `impl Trait for Type` with static dispatch for:
   - core runtime types (string/list/map/int/float) first
   - then user-defined structs/enums
3) Add “trait objects” (explicit opt-in) only when needed (plugins / heterogeneous containers).
4) Add derive-style expansion via attributes (`@oren.derive(...)`) to reduce boilerplate.
5) Add a stabilized v1 type system pass (optional) once the core bootstrapping story is complete.
