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
   - Next: implement resource-level enrollments (beyond domain bitmask):
     - FS: allowlisted prefixes/mounts (DONE: split read/write prefixes; NEXT: mounts + read/write separation for mount rules)
     - NET: loopback vs explicit allowlist, future vnet mapping
     - PROC: explicit subprocess allowlist (argv + env), cancellation

2) **P0 [prod] Fixed-width scalars + floats + explicit casts (network + scientific code)**
   - Define cast semantics (truncate vs checked).
   - Extend casts to cover `f32/f64` story (including parsing + bit-casts).
   - Tighten `i64/u64` semantics for v0 (u64 currently limited to `0..MAX_I64` until big-int/u128 story exists).
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
- Checked integer casts + native structured errors:
  - `lib/std/ints.oren`: `try_*` casts returning `oren_err(4, ...)` on out-of-range.
  - `lib/runtime_native.oren`: `oren_err/oren_is_err/oren_err_code/oren_err_msg` now implemented for native backend portability.
- Native backend string `oren_string_char_at` semantics aligned with C/AVM (returns 1-byte string + bounds checks), and internal callers updated to use raw byte reads where appropriate.
- Capsule mode (native backend): `--capsule` compile-time capability gating using `@cap.requires(domain="...")` annotations (FS/NET/PROC/ENV/TIME) plus compile-fail fixtures.
- Capsule mode (native runtime): `OREN_CAPSULE=1` deny-by-default enforcement + `OREN_CAP_ALLOW_DOMAINS=...` enrollment (defense-in-depth), with repo-runner fixtures.
- Capsule mode (native runtime, FS): path allowlists now support `OREN_FS_ALLOW_READ_PREFIXES` / `OREN_FS_ALLOW_WRITE_PREFIXES` (fallback: `OREN_FS_ALLOW_PREFIXES`).
