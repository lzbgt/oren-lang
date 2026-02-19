# Design (Language + Compiler + Runtime + AVM)

**Last updated:** 2026-02-19

This document is the lean, canonical design reference. It merges the former
compiler/backend, runtime/stdlib, and AVM documents into one place.

Scope: high-signal facts that remain true in rolling mode. For exact semantics,
trust code + fixtures first (see `tests/` and `docs/STATUS.md`).

---

## System overview (rolling)

Oren is a self-hosted language + compiler with three execution backends:

- C backend: portable bootstrap path via a host C toolchain.
- Native backend: direct Mach-O/ELF/PE output (Tier-1 intent).
- Bytecode backend (OBC): `.obc` for the AVM (deterministic, capability-gated VM).

Design intent:

- Deterministic execution (agent-grade) with structured diagnostics.
- Capability-scoped effects (FS/NET/PROC/TIME/RNG/ENV).
- A path to compiler-in-AVM for sandboxed compilation.

Rolling policy: ABI and opcodes can change until an explicit stabilization
milestone is declared.

---

## Compiler pipeline (front-end and lowering)

Primary pipeline entry: `lib/compiler/compiler/040_build_pipeline.oren`.

Phases:

1) Parse + AST: `lib/compiler/lexer.oren`, `lib/compiler/parser_parse/*`.
2) Module linking + `@cfg` filtering: `lib/compiler/compiler/020_modules_linking.oren`.
3) Lowering passes (impls, traits, generics, sugar) under `lib/compiler/`.
4) Backend codegen (native / C / bytecode).

Evidence:

- Parser and diagnostics fixtures: `tests/native/fixtures/`.
- Module behavior: `tests/modules/`.

---

## Backend outputs

### C backend design and ABI

- Emits C and builds via a host toolchain (used for stage0 -> stage1).
- Entry: `lib/compiler/transpiler.oren` plus `lib/runtime.[ch]`.

### Native backend overview

- arm64: `lib/compiler/arm64_macho.oren`, `lib/compiler/arm64_elf.oren`.
- x64: `lib/compiler/x64_elf.oren`, `lib/compiler/x64_pe.oren`, `lib/compiler/x64_native_program.oren`.
- Runtime: `lib/runtime_native/` (syscall-first; avoid libc where practical).

Entry semantics (rolling): entry stub -> `native_runtime_init` -> `__top_level__` -> `main` (optional).
Tier-1 intent targets: `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

Dynamic linking (rolling):

- macOS: Mach-O binding opcodes + GOT stubs.
- Linux: dynamic ELF + `dlsym` resolver when at least one `--link`/`@ffi.link` is present.
- Windows: lazy `LoadLibraryA`/`GetProcAddress` stubs.

Native tagged value representation is not fully converged yet; track in `docs/STATUS.md`.

### Native runtime layout

Native runtime layout details are enforced by the backend emitters and runtime
helpers (literal pools, entry stub init, and runtime globals). Use source and
fixtures as the ground truth: `lib/compiler/*` and `tests/native/fixtures/`.

### Native backend performance playbook

Key levers for hot paths:

- Inty propagation and lowerings that avoid runtime helpers.
- `LIST_INT` and typed buffer fast paths.
- Allocation fast paths (reuse, slabs).

Gates live in `docs/STATUS.md`.

### Native backend guardrails

Avoid backend-only semantics. Track invariants in `docs/STATUS.md` and keep
fixtures aligned across backends.

### Native backend code reuse plan

Rolling direction: reduce arm64/x64 divergence by sharing lowering and helpers,
leaving only target-specific emit.

### Native tagged value representation

Tagged value convergence is still rolling. The canonical model and migration
plan are tracked in `docs/STATUS.md`.

### Bytecode backend (OBC)

- Compiler: `lib/compiler/codegen_bytecode/`.
- VM: `lib/avm/`.
- Output: `.obc` with constant pool + opcode stream.

---

## Runtime and stdlib layering

Layering model (rolling):

1) Intrinsics: compiler/runtime-known primitives (string/list ops, alloc hooks).
2) Builtin syslib: minimal shipped modules used by the toolchain (strings, bytes, math).
3) Shipped stdlib: network, crypto, codecs, etc.
4) Third-party libs.

Constraints:

- Syscall-first for native runtime (no libc dependency for core services).
- Deterministic behavior for AVM and capability-scoped effects.

Evidence:

- Runtime behavior: `tests/native/test_*` and fixtures under `tests/native/fixtures/`.
- Networking + TLS loopback gates: `tests/native/test_tls_loopback.oren`,
  `tests/native/test_https_get_loopback.oren`, `tests/native/test_wss_echo_loopback.oren`.

### TLS provider availability

TLS is OS-dependent. Providers today live under `lib/std/net/`:

- macOS: SecureTransport.
- Linux: OpenSSL.
- Windows: Schannel/SSPI.

When a provider is not implemented on a target, `tls.*` helpers return a structured error.

### UI v0 schema (headless core)

Headless UI core is under `lib/std/ui/` with a JSON-like command schema used by
`std:ui/commands`. See `tests/avm/test_ui_*` for fixtures.

---

## AVM and OBC (bootstrap spec summary)

### Value model (rolling)

- `AvmValue` tagged union (`lib/avm/avm.h`).
- Stack-based VM (`lib/avm/avm_vm.c`).
- Heap: currently `malloc` for heap objects (no GC yet).
- `LIST_INT` is an unboxed int64 list fast-path for tight loops.

### OBC wire format (today)

- Header: magic `0x0ECD`.
- Const count: `u16` little-endian.
- Constant pool:
  - `0`: NIL
  - `1`: INT (`u64` little-endian)
  - `2`: BOOL (`u8`)
  - `3`: FLOAT (`u64` float64 bit pattern)
  - `4`: STRING (`u16` length + bytes)
  - `8`: BYTES (`u32` length + bytes)
- Code: byte stream of 8-bit opcodes + operands.

Rolling metadata conventions (unused BYTES constants appended by compiler):

- `OREN_META\n1\n` + JSON metadata (same structure as native `--metadata`).
- `OREN_OBX\n1\n` + binary export/reloc table used by the linker.
- `OREN_SIG\n1\n` + ed25519 signature over a canonical hash (optional enforcement).

### Capability model (rolling)

- Effects are grouped by domains (FS/NET/PROC/ENV/TIME/RNG).
- AVM can enforce domain allow-lists before execution.

Evidence:

- AVM smoke and determinism fixtures: `tests/avm/`.

### AVM concurrency model (deterministic, syscall-first, aligned multiverse-friendly)

AVM does not implement deterministic task scheduling yet. The direction is
single-thread deterministic scheduling with explicit budgets and effect gating.
Track in `docs/STATUS.md`.

### AVM NEON mapping plan (arm64, no-JIT-first)

SIMD in AVM (arm64 NEON) is gated and must remain deterministic.
Track gating and test coverage in `docs/STATUS.md`.

### AVM in AVM multiverse design (nested virtual universes)

Nested AVM execution is supported behind capability gating (Domain AVM). The
design direction is deterministic, budgeted child universes with virtualized
effects and snapshot/restore semantics. Track in `docs/STATUS.md`.

### AVM swarm consensus (agent mobility design validation)

Result hashing exists in the AVM state. Swarm consensus is rolling and tracked
in `docs/STATUS.md`.

---

## Performance levers (rolling)

Hot-loop parity depends on compiler + runtime cooperation:

- Inty propagation and lowering to native arithmetic fast paths.
- Typed buffers and SIMD kernels (native + AVM).
- Allocation fast paths (small object slabs, reuse).

The weighted performance tracker and gates live in `docs/STATUS.md`.

---

## Platform and toolchain

Tier-1 intent targets: `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

Build/test/self-hosting details live in `docs/TOOLCHAIN_PLATFORMS.md`.

---

## Canonical references

- Entry point: `docs/README.md`
- Language manual + spec: `docs/LANGUAGE.md`
- Status, tracker, feature matrix: `docs/STATUS.md`
- Platforms/toolchain: `docs/TOOLCHAIN_PLATFORMS.md`
- Sources of truth: `tests/` and `lib/`
