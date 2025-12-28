# Backend Architecture (Reuse + Consistency Across C / Native / Bytecode + AVM)

This repo targets Oren as a **modern, efficient, technically solid, future‑proof language** with:

- **3 compiler backends**: `c`, `native`, `bytecode` (`.obc`)
- **AVM** (Agent Virtual Machine) as a first‑class execution target for `.obc`
- “compiler in AVM” and nested universes (“AVM in AVM”) as a core agentic capability
- Tier‑1 **arm64** and **x86_64** support across **macOS / Linux / Windows** (rolling)

This document describes the architecture needed to keep those components:

- **consistent** (same language semantics everywhere),
- **reusable** (no N×M duplication across backends and targets),
- **provable** (fixtures and differential tests catch regressions),
- **SOLID** (clear module boundaries and stable interfaces).

## Non‑Negotiable Invariants

1) **Semantic parity is the product.**
   - If a language feature behaves differently across backends, that is a bug (unless explicitly documented as a rolling limitation).

2) **Determinism is a first‑class constraint.**
   - For AVM/multiverse, we need deterministic execution under budgets and virtualized backends (see `docs/AVM_SPEC.md`).
   - For native, we need deterministic build outputs when requested (`--deterministic`).

3) **Capabilities are explicit.**
   - Effectful operations must be expressible in a capability-domain model (FS/NET/PROC/ENV/TIME/…).
   - AVM enforces this directly; native and C backends must converge on the same logical model.

4) **Tier‑1 means “real validation,” not “best effort.”**
   - Tier‑1 targets must be validated on real machines (or equivalent trusted infrastructure), not only “builds on my laptop”.
   - See `docs/REMOTE_X64_ENV.md` for x86_64 validation, and existing arm64 fixtures.

## The Unification Strategy: One Frontend, One Canonical IR, Thin Backends

Today the repo already has:

- A production‑oriented **C backend** (architecture neutral via the host C toolchain): `docs/C_BACKEND.md`
- A high‑performance **native backend** (arm64 rich; x86_64 bring‑up): `docs/NATIVE_BACKEND.md`
- A portable **bytecode backend** emitting `.obc`, executed by **AVM**: `docs/AVM_SPEC.md`

To keep this scalable, we need a structure that avoids re‑implementing semantics per backend.

### Recommended pipeline

**Stage A — Frontend (shared)**

1) Parse → AST
2) Resolve imports → linked module graph
3) Typecheck / monomorphize / lower high-level sugar
4) Produce a canonical, backend-independent IR

Call this canonical IR **CoreIR**:

- It must represent *language semantics* precisely:
  - evaluation order
  - short‑circuiting rules
  - loop `break/continue` rules
  - varargs/spread lowering decisions
  - closure capture layout rules
- It must be deterministic (stable ordering, no map iteration dependence).

**Stage B — Backend adapters (thin)**

Each backend implements:

- `CoreIR -> BackendIR` (mechanical lowering, no language semantics)
- `BackendIR -> output` (encoding / emission / linking)

Concrete mapping:

- **Bytecode backend**: `CoreIR -> BytecodeIR -> .obc`
- **C backend**: `CoreIR -> C-IR (or C AST) -> C source -> toolchain`
- **Native backend**: `CoreIR -> NativeIR -> ISA selection + ABI -> object format`

`NativeIR` here matches the direction in `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`.

Key rule: **only Stage A decides semantics**. Stage B should never decide what “`for` means” or how `...rest` is represented.

## Canonical Runtime ABI: Make “Callables” the Spine

The single biggest cross-backend semantic surface is **callables**:

- named functions used as values
- lambdas/closures with captured environments
- varargs (`...rest`) and spread (`xs...`)
- indirect calls and spawn/join

The repo already has a strong direction:

- C backend: uniform callable ABI via `oren_call_obj(...)` / `oren_call_obj_list(...)` (`docs/C_BACKEND.md`)
- AVM: explicit `PUSH_FUNC`, `MAKE_CLOSURE`, `CALL_INDIRECT` (see `docs/AVM_SPEC.md`)
- Native (arm64): runtime helpers exist (`lib/runtime_native/120_first_class_fn.oren`) and callable lowering is being centralized (`lib/compiler/native_callable.oren`)

### Canonical callable model (recommended)

Define a single logical callable value model:

- `FuncValue = { code_ptr, env_ptr }`
- Call ABI: `call(FuncValue, args_list) -> value`

Notes:

- `args_list` is a *real* list object in each backend/runtime, not an ad-hoc stack convention.
- Direct calls can still be optimized (no list allocation) by wrappers, but the semantic model stays the same.

This model makes:

- **varargs** natural (`...rest` is a list; spread concatenates lists)
- **closures** natural (`env_ptr` points at a list/struct of captures)
- **AVM/native/C** alignment straightforward (all can implement `call_obj_list`)

### Rolling reality (today)

Some backends are still “mid-convergence”:

- x86_64 native now uses the **uniform callable ABI** for *function values + indirect calls*:
  - `FuncValue = { code_ptr, env_ptr }` stored in a small “fnobj” record
  - indirect calls build an `args_list` and call `code_ptr(env_ptr, args_list)`
  - named function values point at synthesized wrappers `__oren_fnwrap_*`
  - lambda literals lower to heap fnobj records where `env_ptr` points at a capture-by-value list (or `0` for capture-free lambdas), and `code_ptr` points at `__oren_lambda_*` wrappers
- x86_64 native now has a **best-effort panic trace** (RBP chain) and a minimal **addr→fn+offset** symbolication path (embedded symtab, fixed-base emitters) so Tier‑1 bring-up failures are diagnosable without AVM.
- Remaining Tier‑1 gaps: symbolic stack traces (addr→fn/line mapping), richer `OREN_DIAG` parity with runtime-native diagnostics, and performance work (avoid per-call `args_list` allocations for common cases).

Implementation note (rolling):

- Fixed-base constants for x64 ELF/PE are centralized in `lib/compiler/native_abi.oren` (`x64_v0_*` helpers) so the emitters and the panic symbolication logic cannot drift.

This is acceptable in rolling mode as long as:

- the direction is explicit,
- fixtures guard what is implemented today,
- the ABI surface is not painted into a corner.

## Capabilities + IO: Keep the Effect Model Consistent

AVM has a capability-domain model baked in (domains + ops, policy scanning, strict verification).

For consistency:

- **CoreIR** should encode effectful operations in a domain/op form (conceptually).
- C/native backends should lower those to:
  - syscall-first runtime helpers (native),
  - runtime C functions / libc bridging where applicable (C backend),
  - `CALL_NATIVE2` (AVM).

This is how “AVM as stdlib” stays feasible:

- stdlib can be compiled into `.obc` and run in a sandbox with VirtualFS/NET/PROC
- native/server deployments can run the same stdlib logic with host syscalls (subject to runtime capsule policy)

## SOLID Backend Boundaries (Practical Rules)

To keep the codebase maintainable as targets grow:

- **Single Responsibility**
  - frontend passes decide semantics
  - backend passes decide representation/encoding
  - emitters decide file formats (Mach‑O/ELF/PE)
- **Open/Closed**
  - adding a new target should be mostly “implement a new ABI table + emitter”, not “edit 20 existing files”
- **Liskov**
  - a backend is a drop-in implementation of the same CoreIR contract (same tests should apply)
- **Interface Segregation**
  - `NativeABI` should expose small queries (arg regs, alignment, shadow space), not leak instruction encoders
- **Dependency Inversion**
  - shared lowering depends on abstract `ABI`/`Emitter` interfaces; ISA-specific code depends on shared lowering, not the reverse

## Test Strategy (How We Prevent Semantic Drift)

1) **Curated cross-backend tests** for semantics:
   - same `.oren` source compiled under `--backend c`, `--backend native`, `--backend bytecode`
   - compare exit codes and (where deterministic) stdout

2) **Targeted fixtures** for ABI-sensitive behavior:
   - x86_64 Win64 shadow space and arg regs
   - SysV vs Win64 arg register count differences
   - stack alignment-sensitive calls

3) **Opt-in remote Tier‑1 smoke**:
   - validate x86_64 on real Windows + WSL2 (`OREN_REMOTE_RUN=1 ./oretest ...`)

## References (Existing Docs)

- Native backend overview: `docs/NATIVE_BACKEND.md`
- Native code reuse plan (arm64/x86_64): `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`
- C backend callable ABI: `docs/C_BACKEND.md`
- AVM bytecode + capabilities: `docs/AVM_SPEC.md` and `docs/AVM_SPEC_V1.md`
- `.obc` module linking (“OBX”): `docs/OBC_MODULE_LINKING.md`
- Stdlib layering / distribution: `docs/STDLIB_LAYERS.md` and `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`
