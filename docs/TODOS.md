# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (≈5–10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Canonical curated suite (preferred): `./oren test --target macos`
- Wrapper (same suite): `make test`
- Legacy (larger, slower): `make test-legacy`

## Next (Highest Priority First)

1) **Syscall-first OS substrate hardening (native backend)**
   - Lock down: PROC cancellation + TIME + ENV + NET loopback correctness; never hang.
   - Add cancellable `spawn/join` (join timeout + kill+reap) so concurrency cannot deadlock a process indefinitely.
   - Expand the curated smoke to cover: panic stacktrace readability, join timeout, env forwarding, time, and loopback TCP.

2) **Memory hygiene baseline + leak/profiling hooks**
   - Add a deterministic, failure-only memory diagnostics surface for AVM + native runtime teardown.
   - Fix any leaks found by running curated tests repeatedly (macOS first).

3) **Packed struct “view over bytes” (network parsing without allocation)**
   - Attribute-driven schema (metadata-only first), then `pack_view(Type, bytes, offset)` intrinsic.
   - Field reads become bounds-checked endian reads (`bytes_get_u{N}_{be|le}`), no host effects.

4) **Fixed-width scalars + floats + explicit casts**
   - Add `i8/i16/i32/i64/u8/u16/u32/u64` (+ `u128` later) and `f32/f64`.
   - Endian-aware casts for packet parsing (`be/le`), and robust varargs.

5) **Universal iteration model**
   - `for x in ...` works for list/map/string/bytes/streams; map iteration is key-ordered by spec.

6) **AVM deterministic cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

7) **`.obc` tooling**
   - Disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` BYTES convention).
