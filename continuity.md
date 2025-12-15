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

## References
- Toolchain overview: `README.md`
- Build & verify: `docs/BUILD_AND_VERIFY.md`
- Backends: `docs/C_BACKEND.md`, `docs/NATIVE_BACKEND.md`
- Roadmap: `docs/ROADMAP.md`
