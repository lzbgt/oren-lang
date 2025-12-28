# Docs Index (Canonical Map)

**Last updated:** 2025-12-28  
This folder contains both **canonical specs** and a few **compatibility stubs** kept to avoid link rot while the repo evolves in rolling mode.

## 1) “Start Here”

- `docs/TODOS.md` — the single source of truth task tracker (execution order).
- `docs/LANGUAGE_MANUAL.md` — practical guide for writing Oren *today* (examples, idioms, what works now).
- `docs/EVOLUTION_GUIDE.md` — beginner guide: bootstrapping + backends + day0→final evolution narrative.
- `docs/AGENTIC_REQUIREMENTS.md` — top agentic-AI requirements (language + compiler + AVM), prioritized and implementation-ordered.
- `docs/ROADMAP.md` — what to implement next (phases, priorities).
- `docs/BUILD_AND_VERIFY.md` — how to build, test, and verify the toolchain.
- `docs/TEST_SYSTEM.md` — how the repo test/build system evolves from Makefile → Oren-native tooling.
- `docs/STDLIB_LAYERS.md` — builtin syslib vs shipped stdlib separation (no-libc-shims constraint).
- `docs/ATTRIBUTES.md` — attribute cookbook and deterministic metadata contract (serde/pack/abi/doc).

## 2) Canonical Specs

- Language: `docs/LANGUAGE_SPEC.md`
- AVM (bootstrap, current): `docs/AVM_SPEC.md`
- AVM (next-gen plan): `docs/AVM_SPEC_V1.md`

## 3) Runtime / Backend Design

- Syscall-first native runtime plan (no C shims): `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`
- Native backend notes: `docs/NATIVE_BACKEND.md`
- C backend notes: `docs/C_BACKEND.md`
- Memory notes: `docs/MEMORY.md`

## 4) Concurrency

- Concurrency and IPC model: `docs/CONCURRENCY_MODEL.md`
- AVM deterministic concurrency model: `docs/AVM_CONCURRENCY.md`

## 5) Strategy / Narrative / “Why”

- Overall evolution strategy: `docs/OREN_EVOLUTION.md`
- Advanced scenarios (“killer apps”): `docs/ADVANCED_SCENARIOS.md`
- Swarm consensus + agent mobility: `docs/AVM_SWARM_CONSENSUS.md`
- Nested universes (“AVM in AVM”): `docs/AVM_MULTIVERSE.md`
- Comparison notes: `docs/COMPARISON.md`

## 7) Tools

- Local swarm harness (k-of-n agreement): `tools/avm_swarm_local.sh`

## 6) Compatibility Stubs (Kept for Link Stability)

These docs are intentionally short and point to canonical locations:

- `docs/AI_FEATURES.md` → `docs/AGENTIC_REQUIREMENTS.md`
- `docs/AGENTIC_AI_TOP_FEATURES.md` → `docs/AGENTIC_REQUIREMENTS.md`
- `docs/AGENTIC_VM_KILLER_FEATURES.md` → `docs/AGENTIC_REQUIREMENTS.md`
- `docs/AVM_CAPABILITIES.md` → `docs/AVM_SPEC_V1.md`
