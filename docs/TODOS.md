# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (≈5–10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Canonical curated suite (preferred): `./oren test --target macos`
- Wrapper (same suite): `make test`
- Legacy (larger, slower): `make test-legacy`

## Next (Highest Priority First)

1) **Packed struct “view over bytes” PV3 (packet serialization without allocation)**
   - Support `pack_view("Type", bytes, off).field = value` (compile-time lowering).
   - Lower to `oren_bytes_set_u8` sequences with shifts/masks (endian-safe, no allocation).
   - Add smoke tests that build a header by writing fields then reading back.

2) **Syscall-first OS substrate hardening (native backend)**
   - Keep: PROC cancellation + TIME + ENV + NET loopback correctness; never hang.
   - Capability enrollment model: allow mapping virtual resources to host resources intentionally.
   - Expand curated smoke coverage as these evolve.

3) **Fixed-width scalars + floats + explicit casts (for network + scientific code)**
   - Add `i8/i16/i32/i64/u8/u16/u32/u64` (+ `u128` later) and `f32/f64`.
   - Endian-aware casts for packet parsing (`be/le`) and explicit bit/byte casts.
   - Varargs + function values/lambda ergonomics (spawn-safe closures) as needed by stdlib.

4) **Language core correctness + robustness**
   - Harden AST/parser/codegen invariants (scope, stack/heap, argument passing).
   - Fix nested control-flow edge cases (e.g. nested `for` break depth).
   - Keep deterministic map iteration by spec.

5) **AVM deterministic cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

6) **Tooling + maintainability**
   - `.obc` disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` BYTES convention).
   - Refactor large modules (e.g. `avm.c` / codegen) when they exceed readability thresholds, without semantic churn.
