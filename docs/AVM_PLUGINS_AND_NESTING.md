# AVM Plugins + Nesting (OBC-First, iOS-Safe) (Rolling)

Oren’s “restricted environment” track (iOS/App Store, Web, Edge) requires:

- **no JIT** (interpreter-first AVM),
- **capability gating** (no ambient FS/PROC/NET),
- **determinism + budgets** (replayable, composable sandboxes),
- and a distribution story where **stdlib and compiler can run as bytecode**.

This doc is a fact-first bridge between:

- multiverse execution (`docs/AVM_MULTIVERSE.md`),
- bytecode module linking (`docs/OBC_MODULE_LINKING.md`),
- stdlib distribution/resolution (`docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`),
- and the repo-wide roadmap (`docs/TODOS.md`, `docs/LANGUAGE_STATUS_AND_GAPS.md`).

**Last updated:** 2026-01-15

---

## 1) Terminology (concrete)

- **OBC**: an `.obc` bytecode program executed by the AVM interpreter.
- **OBX**: linker metadata embedded as an unused `BYTES` constant inside `.obc` (exports + relocs). AVM ignores it at runtime. See `docs/OBC_MODULE_LINKING.md`.
- **Universe**: one AVM instance with its own budgets, deterministic TIME/RNG, and capability allow mask.
- **Child universe / nesting**: running one `.obc` inside another via a governance boundary (caps + budgets + virtual backends).

This repo uses “plugin” in two different senses. Keeping them separate avoids design drift.

---

## 2) Plugin Model A (works with iOS constraints): plugin = child universe

### Why this is the default “plugin” model for AVM

On iOS/App Store, a “plugin” must not:

- require `dlopen` of arbitrary native code,
- require JIT,
- share ambient host effects (FS/NET/PROC) unless explicitly delegated.

So the most robust plugin shape is:

1) Outer program (host or AVM) selects a plugin `.obc` (as `BYTES`).
2) Outer runs it as a **child universe** with an explicit config map:
   - `allowed_domains` subset,
   - budgets (`gas_limit`, `mem_bytes`, `deadline_ns`, `io_bytes`, `log_bytes`),
   - virtual backends + fixtures (VirtualFS/VirtualPROC/VirtualNET),
   - deterministic TIME/RNG.
3) Child returns:
   - `exit_code`, `result`, `result_hash`, `state_hash`,
   - optional `record_log` + `vfs_snapshot`.

Status (fact, today):

- Nested-universe execution is described (and partially implemented) via `oren_avm_run_obc_bytes(child_obc_bytes, cfg_map)`:
  - Interface + cfg keys: `docs/AVM_MULTIVERSE.md` section “6.2 Current bootstrap cfg keys”.
  - Determinism/fixtures intent: `docs/AVM_SPEC_V1.md`, `docs/AGENTIC_REQUIREMENTS.md`.

This model is already “plugin-friendly” because:

- it composes with budgets (prevents “plugin fork bombs”),
- it composes with determinism (replay log is data),
- it composes with capability delegation (parent can only delegate what it has).

### What “stdlib and compiler as plugins” means under Model A

- **stdlib**: ship a precompiled `stdlib_bundle.obc` and link it at compile-time (preferred) or run it in a child universe for isolated tooling tasks.
- **compiler**: ship `oren.obc` and run it in a child universe to compile source → output `.obc` inside VirtualFS.

This is “compiler-in-AVM” without requiring a C compiler inside the sandbox.

---

## 3) Plugin Model B (future, more complex): runtime module loading inside one universe

This is the classic dynamic language “plugin” model: load modules at runtime and call their functions *in the same VM instance*.

What it enables:

- shared caches (one copy of stdlib across multiple apps),
- smaller app artifacts (load-on-demand modules),
- “true plugin” APIs: trait objects + dynamic dispatch to code discovered at runtime.

What it requires (not fully implemented today):

1) **Runtime module identity and policy**
   - stable module naming / hashing scheme,
   - allow/deny rules: which modules may be loaded.

2) **A bytecode linking ABI usable at runtime**
   - exported symbol table
   - relocation / import resolution
   - global storage model: “per module” vs “shared globals”.

3) **Loader surface**
   - load module bytes, verify, link into current universe, return a module handle.

Current repo status (fact):

- Compile-time linking exists via OBX (`docs/OBC_MODULE_LINKING.md`).
- Runtime dynamic module loading is explicitly a **non-goal** of the current OBX v0 format.

Therefore, treat Model B as a later step once the module ABI is stable and the security model is precise.

---

## 4) Practical milestone: compiler-in-AVM (source → `.obc` as data)

The “iOS-safe” end state is:

- Ship `libavm` + `oren.obc` in the app bundle.
- Provide a VirtualFS tree containing:
  - user sources,
  - stdlib sources OR precompiled stdlib bundle (depending on mode),
  - output path.
- Run `oren.obc` in a restricted universe to produce `out.obc` into VirtualFS.
- Optionally verify and run the produced `out.obc` as a second child universe (or as a sibling universe).

Key supporting docs:

- `docs/AVM_MULTIVERSE.md` (compiler-in-AVM section)
- `docs/OBC_MODULE_LINKING.md` (precompiled stdlib bundle + relocations)
- `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` (stdlib specifiers + distribution models)

---

## 5) Recommended tracker items (so we don’t drift)

When updating `docs/TODOS.md`, keep these as separate deliverables:

1) **Model A hardening (child-universe plugins)**
   - stable `cfg` schema for `oren_avm_run_obc_bytes`
   - record/replay logs as `BYTES` (not paths)
   - deterministic TIME/RNG + budgets enforcement

2) **Compiler-in-AVM packaging**
   - produce and ship `oren.obc`
   - produce and ship `stdlib_bundle.obc` (or stdlib pack)

3) **Model B runtime module loading (optional later)**
   - only after module ABI + policy model is mature
   - likely built on top of OBX, but not the same as compile-time OBX linking

