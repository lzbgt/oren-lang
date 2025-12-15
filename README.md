# Oren Programming Language

Oren is a modern, statically-typed (conceptually), self-hosting programming language that targets **macOS (Mach-O)** and **Linux (ELF)** on **ARM64**. It features a clean syntax, module system, and native SIMD support.

It is written by AI agent and for AI agent: [revolutionary cases in mind](docs/OREN_EVOLUTION.md)

## Quick Start

### Prerequisites
- macOS (Apple Silicon) or Linux (ARM64).
- `go` (for initial bootstrap).
- `make`.
- `cc` (for C backend).

### Build & Test
1. **Bootstrap**: Build the compiler using the stage0 Go compiler.
   ```bash
   make bootstrap
   ```
2. **Verify**: Run the full self-hosting verification suite (Bootstrap -> Stage 1 -> Stage 2 -> Native Tests).
   ```bash
   make verify
   ```
3. **Run Tests**:
   ```bash
   make test
   ```

### Codesigning on macOS
- Default identity: `Developer ID Application: Zongbao Lu (US56HHF2Y4)` is pre-wired for convenience. Builds/tests on macOS auto-codesign using this unless overridden.
- Override by setting `CODESIGN_IDENTITY`, or pass `--codesign "<identity>"` to `./oren build ...`; the Go bootstrap also respects `OREN_CODESIGN_ID` if you prefer an env var.
- Optional notarization: `--notarize [--notary-profile <profile>]` will submit with `notarytool` and staple the ticket. Provide a keychain profile or set `APPLE_ID`, `APPLE_ID_PASS`, and `APPLE_TEAM_ID` in the environment.
- Installing the identity: In Xcode → Settings → Accounts, sign in with your Apple Developer account, select your team, then **Manage Certificates…** and create/download a *Developer ID Application* certificate. Verify availability with `security find-identity -v -p codesigning`. End users do **not** need your certificate; a Developer ID–signed + notarized binary runs without extra setup.
- More detail: see `docs/CODESIGN.md`.

### Memory
- Runtime tracks strings/lists/maps and frees them on shutdown; call `oren_gc_collect()` to mark/sweep from registered roots, or `oren_free(value)` for deterministic release.
- Disable GC scanning with `--no-gc` (or env `OREN_NO_GC=1`) to make the collector/roots a no-op while still getting shutdown cleanup—useful for constrained/embedded targets.
- See `docs/MEMORY.md` for the current memory model, GC hooks, and roadmap.
- Lists/maps in the C runtime are protected by a coarse mutex for thread-safe reads/writes; finer-grained concurrency and safepoints are on the roadmap.

## Roadmap
- Active roadmap is tracked in `docs/ROADMAP.md` (memory/GC, concurrency, FFI/linking, type system, tooling, package manager, async/tasks, x86_64, and ecosystem goals).

## Features

- **Backends**:
  - **Native (Default)**: Generates Mach-O (macOS) or ELF (Linux) executables directly.
  - **C**: Transpiles to C for portability (`--backend c`).

- **Language Features**:
  - **Variables**: `var x = 10`.
  - **Control Flow**: `if/else`, `while` loops.
  - **Functions**: `fn add(a, b) { return a + b }`.
  - **Modules**: `import alias "path/to/file.oren"`.
  - **Structs**: `struct Point { x, y }` (C backend only currently).
  - **SIMD**: Native 128-bit NEON intrinsics (`simd_add_2d`, `simd_mul_4s`, etc.).

- **CLI Tools**:
  - `--target linux|macos`: Cross-compile (header generation).
  - `--disasm`: Disassemble output using `otool` or `objdump`.

## Project Structure
- `oren.oren`: The self-hosted compiler source (monolithic).
- `cmd/oren`: Stage 0 Go bootstrap compiler.
- `lib/`: Runtime library (C backend).
- `tests/`: Unit tests (Native, Modules, Legacy).
- `docs/`: Documentation (`NATIVE_BACKEND.md`, `LANGUAGE_SPEC.md`).

## Self-Hosting
Oren is self-hosting. The `oren.oren` compiler can compile itself.
See `docs/SELF_HOSTING.md` for details.
