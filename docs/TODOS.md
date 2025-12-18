# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (≈5–10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Canonical curated suite (preferred): `./oren test --target macos`
- Wrapper (same suite): `make test`
- Legacy (larger, slower): `make test-legacy`

## Next (Highest Priority First)

1) **P0 [safety] Syscall-first OS substrate hardening (native backend)**
   - Keep: PROC cancellation + TIME + ENV + NET loopback correctness; never hang.
   - Define/implement a capability enrollment model (explicit mapping virtual -> host resources).

2) **P0 [prod] Fixed-width scalars + floats + explicit casts (network + scientific code)**
   - Define cast semantics (truncate vs checked).
   - Extend casts to cover `i64/u64` (and checked variants) and `f32/f64` story.
   - Keep endian-aware helpers for packet parsing/serialization (`be/le`) and explicit bit/byte casts.

3) **P1 [correctness] Language core robustness**
   - Harden parser/codegen invariants (scope, stack/heap, argument passing).
   - Fix nested control-flow edge cases (e.g. nested `for` break depth).
   - Ensure deterministic container behavior matches spec across all backends.

4) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

5) **P2 [ux] Tooling**
   - `.obc` disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` BYTES convention).

6) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (e.g. AVM/codegen) once behavior is covered by tests.

## Recently Completed

- Packed struct views PV2/PV3: `pack_view("Type", bytes, off).field` reads and writes lower to byte ops (no allocation).
- Endian-aware byte writes: `oren_bytes_set_{u16,i16,u32,i32}_{be,le}` added across backends with tests.
- Fixed-width integer cast APIs (wrap/truncate): `lib/std/ints.oren` with native/module/avm tests.
