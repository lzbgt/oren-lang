
## Vision / Mission (Agent-Native)

Oren is aimed at **agent execution**, not just “a static language”.

- **Vision:** make Oren a practical “native tongue” for AI agents: fast on servers/desktops, but still runnable in restricted environments.
- **Core idea:** a **hybrid runtime model**:
  - **Native mode:** compile to machine code (or via the C backend) for performance and full system access where allowed.
  - **Bytecode mode:** compile to portable bytecode (`.obc`) intended to run on **AVM (Agent Virtual Machine)** in environments where native execution/toolchains aren’t available.
- **Long-term goals (design direction):** safe/capability-scoped execution, portability, and tooling that supports fast “read → fix compiler → rebuild” loops for agents.

Authoritative strategy/roadmap docs:
- `docs/OREN_EVOLUTION.md`
- `docs/ROADMAP.md` (see “Agent-Native Track (AVM + Bytecode)”)

## Status (Current Reality)
- **Backends**
  - **C backend (default):** transpile to C and compile with `cc` (used for the self-hosting chain).
  - **Native backend (ARM64):** emits Mach-O (macOS) or ELF (Linux) directly (`--backend native`).
  - **Bytecode backend (experimental):** emits `.obc` (`--backend bytecode`) for the AVM prototype.
- **Platforms**
  - Native backend targets **macOS arm64** and **Linux arm64**.
  - C backend is portable to any platform with a C toolchain.

## Build, Test, Verify


### Prerequisites
- `go` (stage0 bootstrap)
- `make`
- `cc` (for the C backend; used in self-hosting)

### Commands
```bash
make bootstrap   # build stage0 Go compiler
make            # build stage1 self-hosted compiler (default target)
make test       # native backend tests + module tests
make verify     # clean + stage2 self-hosting verification
```

## Using The Compiler

### Build an executable (C backend, default)
```bash
./oren build examples/hello.oren -o hello
```

### Emit C only (C backend)
```bash
./oren build examples/hello.oren --backend c --emit-c
# writes examples/hello.oren.c
```

### Build a native ARM64 binary (macOS/Linux)
```bash
./oren build examples/hello.oren --backend native -o hello_native
./oren build examples/hello.oren --backend native --target linux -o hello_linux
```

### Run native tests (single file)
```bash
./oren test tests/native/test_gc.oren --target macos
```

### Build bytecode + run on AVM (experimental)
```bash
./oren build examples/hello.oren --backend bytecode -o hello.obc
make avm
./avm hello.obc
```

## Examples

Run the example suite (builds + executes across backends):
```bash
make examples-test
```

Individual examples:
- **C backend**
  - `examples/hello_c.oren` (top-level script style)
  - `examples/module_app.oren` + `examples/modules/math.oren` (module import + name resolution)
  - `examples/spawn_c.oren` (threads via `spawn` + `oren_join`)
- **Native backend**
  - `examples/gc_native.oren` (allocation + `native_gc_collect()` sanity)
  - `examples/ffi_test.oren` (FFI against `libSystem` via `ffi puts`)
  - `examples/libmath.oren` + `examples/ffi_from_libmath.oren` (build dylib via `--lib`, auto-generate header `.h`, `oren scan`, then link via `--link`)

## Notes / Limitations (Important)
- **Native backend string concatenation:** `+` is integer-only; use `string_concat(a, b)` for strings.
- **Native backend Linux dynamic linking/FFI:** the ELF emitter currently stubs unresolved imports (no real dynamic linker integration yet).
- **`--emit-c`:** only supported with `--backend c`.
- **`oren test`:** currently supports `--backend native` only.
- **`--metadata`:** currently emitted by the native backend (`<out>.meta.json`).
- **macOS signing:** the compiler attempts to codesign outputs (configured Developer ID, with ad-hoc fallback); see `docs/CODESIGN.md`.

## Docs
- `docs/README.md` the starting point
