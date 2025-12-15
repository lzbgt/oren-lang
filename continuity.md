# Oren Continuity Notes

This file is a short, factual snapshot of the repo state.

## What Works
- **Self-hosting:** `cmd/oren` (Go stage0) builds the stage1 compiler (`./oren`), and `./oren` can rebuild itself (`oren_stage2` via `make verify`).
- **Backends:**
  - **C backend (default):** transpile to C + compile with `cc` (`lib/runtime.c`).
  - **Native backend (ARM64):** emits Mach-O (macOS) and a minimal ELF (Linux) (`lib/runtime_native.oren` injected).
  - **Bytecode backend (experimental):** emits `.obc`; the AVM prototype lives under `lib/avm/`.
- **Test/verify entry points:** `make test`, `make verify`.

## Key Limitations (Known)
- **Native backend strings:** `+` is integer-only; use `string_concat(a, b)` for strings.
- **Native backend Linux FFI:** ELF dynamic linking isn’t implemented yet; unresolved imports are stubbed.

## Prioritized TODOs (Roadmap-Driven)
These are pulled from `docs/ROADMAP.md` and the agent-native track in `docs/OREN_EVOLUTION.md`.

### P0 (Correctness / Parity)
- **Native backend strings:** implement `+` operator string concatenation (or remove `+` from strings until v1), so native and C backends match semantics.
- **Spawn Stability:** `spawn`/`oren_join` on native backend is sensitive to runtime/ABI regressions; all native tests are now executed with a hard timeout via `make test` to prevent hangs from blocking CI/dev.
- **Native Linux dynamic linking:** implement `DT_NEEDED`/PLT/GOT relocations so `ffi` works on ELF (currently stubbed).

### P1 (Performance / Portability)
- **Native register allocation:** move from stack-heavy codegen toward an IR + register allocator, plus basic peephole opts.
- **x86_64 native backend skeleton:** validate cross-arch compiler architecture (per roadmap).

### Agent-Native Track (AVM + Bytecode)
- **AVM core hardening:** expand value types/op coverage and add memory management strategy (currently `malloc`-based).
- **Bytecode backend fixes:** Fixed critical stack corruption bugs in `codegen_bytecode.oren` (locals persistence, expression return values). Verified with `test_compiler_boot.oren`.
- **Next:** Debug string/memory logic in AVM (test logic anomaly), then proceed to full self-hosting ("Inception").

## References
- Toolchain overview: `README.md`
- Build & verify: `docs/BUILD_AND_VERIFY.md`
- Backends: `docs/C_BACKEND.md`, `docs/NATIVE_BACKEND.md`
- Roadmap: `docs/ROADMAP.md`
