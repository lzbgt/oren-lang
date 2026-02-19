# Docs Index (Canonical Map)

**Last updated:** 2026-02-19  
This folder contains the **canonical specs** and living design notes for Oren (rolling).

## 1) “Start Here”

- `docs/TODOS.md` — the single source of truth task tracker (execution order).
- `docs/LANGUAGE_STATUS_AND_GAPS.md` — fact-first snapshot of what works today and what’s missing (feeds `docs/TODOS.md`).
- `docs/LANGUAGE_MANUAL.md` — practical guide for writing Oren *today* (examples, idioms, what works now).
- `docs/LANGUAGE_FEATURE_MATRIX.md` — AI-friendly map: feature → status → implementation → fixtures.
- `docs/COMPILER_AND_BACKENDS.md` — AI-friendly compiler pipeline + IR map (CoreIR/NativeIR/BytecodeIR direction + current reality).
- `docs/EVOLUTION_AND_ROADMAP.md` — beginner narrative + evolution rules + roadmap (day0 -> production).
- `docs/AGENTIC_REQUIREMENTS.md` — top agentic-AI requirements (language + compiler + AVM), prioritized and implementation-ordered.
- `docs/EVOLUTION_AND_ROADMAP.md` — what to implement next (phases, priorities).
- `docs/BUILD_AND_VERIFY.md` — how to build, test, and verify the toolchain.
- `docs/TEST_SYSTEM.md` — how the repo test/build system evolves from Makefile → Oren-native tooling.
- `docs/STDLIB_LAYERS.md` — builtin syslib vs shipped stdlib separation (no-libc-shims constraint).
- `docs/ATTRIBUTES.md` — attribute cookbook and deterministic metadata contract (serde/pack/abi/doc).

## 2) Canonical Specs

- Language: `docs/LANGUAGE_SPEC.md`
- AVM (bootstrap spec + next-gen plan section): `docs/AVM_AND_OBC.md`
- OBC portability + module linking (OBX): `docs/AVM_AND_OBC.md`

## 3) Runtime / Backend Design

- Syscall-first native runtime plan (no C shims): `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`
- Native backend notes: `docs/COMPILER_AND_BACKENDS.md#native-backend-overview`
- C backend notes: `docs/COMPILER_AND_BACKENDS.md#c-backend-design-and-abi`
- Collections + container ops + unboxed list<int> design: `docs/DESIGN_COLLECTIONS.md`
- Memory notes: `docs/MEMORY.md`
- Windows IOCP netpoller design: `docs/WINDOWS_IOCP_NETPOLL.md`
- Remote x86_64 (Win11, WSL2 optional) workflow: `docs/REMOTE_X64_ENV.md`

## 4) Concurrency

- Concurrency and IPC model: `docs/CONCURRENCY_MODEL.md`
- AVM deterministic concurrency model: `docs/AVM_AND_OBC.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`

## 5) Strategy / Narrative / “Why”

- Overall evolution strategy: `docs/EVOLUTION_AND_ROADMAP.md`
- Advanced scenarios (“killer apps”): `docs/ADVANCED_SCENARIOS.md`
- Swarm consensus + agent mobility: `docs/AVM_AND_OBC.md#avm-swarm-consensus-agent-mobility-design-validation`
- Nested universes (“AVM in AVM”): `docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes`
- Comparison notes: `docs/COMPARISON.md`

## 6) Tools

- Local swarm harness (k-of-n agreement): `tools/avm_swarm_local.sh`

## 7) No Stubs (Rolling)

Rolling policy: remove empty/duplicate docs instead of keeping “stub” files.
Prefer updating links and index entries when names move.
