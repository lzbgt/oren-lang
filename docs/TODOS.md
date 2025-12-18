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
   - Next enrollments (beyond domain bitmask):
      - **DONE NET:** enforce caps at raw `sys_*` boundary (no bypass), add vnet-style endpoint mapping, add per-socket fd capabilities
      - **DONE PROC:** enforce caps at raw `sys_*` boundary (no bypass); force capsule envp on execve; restrict wait/kill to owned child pids
      - **FS:** finish syscall-boundary enforcement beyond `sys_open` (DONE: unlink/rename/mkdir; next: rmdir/stat/readdir/etc), then mounts UX polish + virtual mount mirroring (native/AVM)

2) **P0 [prod] Fixed-width scalars + floats + explicit casts (network + scientific code)**
   - Define cast semantics (truncate vs checked) and ensure consistent behavior across native/C/AVM.
   - Extend casts to cover `f32/f64` story (including parsing + bit-casts) and endian-aware helpers (`be/le`).
   - Tighten `i64/u64` semantics for v0 (u64 currently limited to `0..MAX_I64` until big-int/u128 story exists).
   - DONE: native float operator parity for floaty expressions (compile-time tracked), plus canonical tests.

3) **P1 [correctness] Language core robustness**
   - Harden parser/codegen invariants (scope, stack/heap, argument passing).
   - Fix nested control-flow edge cases (e.g. nested `for` break depth).
   - Ensure deterministic container behavior matches spec across all backends.
   - Define and enforce string equality semantics across backends (native now does content-compare for "stringy" expressions; extend coverage as needed).

4) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

5) **P2 [ux] Tooling**
   - `.obc` disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` BYTES convention).

6) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (e.g. AVM/codegen) once behavior is covered by tests.

## Recently Completed

- AVM multiverse: nested universes inherit VirtualFS and host FS restrictions.
- AVM host FS mounts: `--fs-mounts[-read|-write]` maps virtual paths to enrolled host prefixes (determinism-friendly).
- AVM float64: `.obc` FLOAT consts + `* /` ops, mixed numeric comparisons, canonical float ops test.
- PROC argv allowlist: add `<prefix>*` suffix-wildcard matcher for safer ergonomic enrollment.
- Native backend: float operator parity for floaty expressions + fixed SCVTF/FCVTZS instruction encodings.
- Native capsule NET: enforce capability checks at raw `sys_*` NET boundary (no bypass), add `OREN_NET_TCP_*_MAP`, add per-fd NET capability tags.
- Native capsule PROC: enforce capability checks at raw `sys_*` PROC boundary (no bypass), force capsule envp on execve, restrict wait/kill to owned child pids.
- Native capsule FS: enforce syscall-boundary checks for `sys_open` (no bypass), including mount-enrolled host path allow and virtual->host resolution.
- Native capsule FS: add syscall-boundary checks for `sys_unlink/sys_rename/sys_mkdir` (no bypass) + canonical tests.
