# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (about 5-10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Canonical curated suite (preferred): `./oren test --target macos`
- Wrapper (same suite): `make test`
- Legacy (larger, slower): `make test-legacy`

## Next (Highest Priority First)

1) **P0 [safety] Syscall-first OS substrate hardening (native backend)**
   - Keep: PROC cancellation + TIME + ENV + NET loopback correctness; never hang.
   - Capability enrollment model: explicit mapping virtual -> host resources; deny-by-default with capability checks at the raw `sys_*` boundary (no bypass).
   - Next: mounts UX polish + virtual mount mirroring (native/AVM) + more FS syscalls as needed.

2) **P0 [maint] Centralize OS ABI constants in repo-owned tables (no SDK header dependency)**
   - Keep syscall numbers / struct offsets in repo code + `docs/refs/*`.
   - Treat system headers as audit-only.
   - macOS arm64 is largely done via `lib/compiler/arm64_abi_macos.oren` + `docs/refs/darwin_arm64_abi.md` (syscall reg/imm + core syscalls).
   - Linux arm64 baseline table added via `lib/compiler/arm64_abi_linux.oren` (syscall reg/imm + core syscalls).
   - Next: Linux arm64 parity tables + a single shared ABI layer used by native codegen.

3) **P1 [correctness] Unify language-level `==` / `!=` semantics for strings across backends**
   - Native backend uses a compile-time "stringy" heuristic + runtime `strcmp`; AVM/C backends do type-tagged `strcmp`.
   - Keep expanding coverage via tests: strings from FS (`readdir`), ENV, `realpath`, `read_file`, etc.
   - Must keep `s == nil` safe (no accidental `strcmp(s, 0)` lowering).

4) **P1 [prod] Fixed-width scalars + floats + explicit casts (network + scientific code)**
   - Define cast semantics (truncate vs checked) and enforce consistent behavior across native/C/AVM.
   - Extend casts to cover `f32/f64` + endian-aware helpers (`be/le`) for packed parsing.

5) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

6) **P2 [ux] Tooling**
   - `.obc` disassembler ("otool-like") + metadata extractor (reads embedded `OREN_META\n1\n` bytes convention).

7) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (AVM/codegen) once behavior is covered by tests.

## Recently Completed (high signal)

- AVM FS-domain helpers: `oren_exists` + `oren_readdir` (VFS + host mounts), plus CORE `oren_realpath` (pure lexical).
- macOS arm64 ABI constants moved into repo-owned module: `lib/compiler/arm64_abi_macos.oren` (+ refs in `docs/refs/darwin_arm64_abi.md`).
- Native backend string comparisons: fixed false-floaty Index classification that broke `names[i] == "lit"` for lists produced by helpers like `oren_readdir`.
- Native backend syscall ABI: moved Darwin syscall reg/imm + base syscalls into `lib/compiler/arm64_abi_macos.oren`, removed entry-stub magic SVC encodings, and fixed Linux arm64 `pipe2` syscall number to 59 (from `docs/refs/linux_asm_generic_unistd.h`).
- Linux arm64 syscall ABI: introduced repo-owned constants (`lib/compiler/arm64_abi_linux.oren`) and removed hardcoded `x8`/`svc #0` + core syscall numbers from codegen hot spots.
