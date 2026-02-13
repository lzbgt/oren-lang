
## Vision / Mission (Agent-Native, AI-era Ambition)

This repo is not “just another language + compiler”. It is aiming at an **AI-era execution substrate**:

- A practical, self-hosting language (Oren) that can implement its own libraries in `.oren`.
- A deterministic, capability-governed virtual machine (AVM) that can run agent code as **data capsules**.
- A path to “AVM inside AVM” (nested universes) and **swarm consensus** workflows where agents can be validated/replayed across nodes.

### Core thesis

Agent systems need **replayability + governance** more than they need “max micro-benchmark speed” on day 1:

- Programs must be runnable in restricted sandboxes without a native toolchain.
- Effects must be explicit (capability domains), budgeted (gas/mem/io/log), and ideally record/replayable.
- Determinism must compose with nested universes (“multi-universe simulation” is a killer primitive for agents).

### Hybrid execution model (what exists + what it’s for)

- **Native mode:** compile to machine code (or via the C backend) for performance and full system access where allowed.
- **Bytecode mode:** compile to portable bytecode (`.obc`) intended to run on **AVM (Agent Virtual Machine)**:
  - deterministic hashing (`STATE_HASH` / `RESULT_HASH`) for k-of-n validation
  - capability domains (`CALL_NATIVE2 domain/op`) for governance and sandboxing
  - deterministic TIME/RNG (virtual clock derived from executed steps + seeded PRNG)
  - nested universes (AVM-in-AVM) under restricted caps + budgets

### “Closed Loop” compiler-in-AVM (design target)

The end-state for restricted deployments (mobile/edge) is a **closed loop**:

- AVM can run the Oren compiler itself as a bytecode “capsule” (`oren.obc`)
- agent code can ship as `.oren` source, and be compiled to `.obc` inside the sandbox
- compilation can be made deterministic and policy-governed (caps + gas/mem/io/log) and validated via hashes

This is the foundation for self-healing agent workflows where “code is data”, compilation is reproducible, and a swarm can validate both the compiler capsule and the produced `.obc`.

Authoritative specs/strategy docs:
- `docs/AGENTIC_REQUIREMENTS.md` (top requirements, prioritized)
- `docs/AVM_SPEC.md` (current bootstrap spec)
- `docs/AVM_SPEC_V1.md` (next-gen direction)
- `docs/AVM_SWARM_CONSENSUS.md` (swarm validation + mobility model)
- `docs/AVM_MULTIVERSE.md` (nested universes / AVM-in-AVM)
- `docs/ROADMAP.md` and `docs/OREN_EVOLUTION.md`
- Practical manual (what works today): `docs/LANGUAGE_MANUAL.md`

## Status (Current Reality)
- **Backends**
  - **C backend (default):** transpile to C and compile with `cc` (used for the self-hosting chain).
  - **Native backend (Tier‑1 intent):** emits Mach-O (macOS), ELF (Linux), or PE32+ (Windows) directly (`--backend native`).
  - **Bytecode backend (experimental):** emits `.obc` (`--backend bytecode`) for the AVM prototype.
- **Platforms**
  - **Tier‑1 intent (rolling):** `arm64` + `x86_64` across **macOS / Linux / Windows**.
  - Practical reality today:
    - native arm64 is the most feature-complete
    - native x86_64 exists for Linux ELF + Windows PE32+ but is still bring-up (see `docs/TODOS.md` and `docs/REMOTE_X64_ENV.md`)
  - C backend is portable to any platform with a C toolchain.

## Stdlib (Rolling highlights)

This repo is intentionally syscall-first and “no libc shims” for native runtime, so the stdlib focuses on **portable, deterministic building blocks**:

- `lib/std/json.oren`: deterministic JSON representation + tolerant decode for config text (C-style comments).
- `lib/std/yaml.oren`: deterministic YAML subset + tolerant decode (YAML `#` and C/JSON `//` + `/* */` comments).
- `lib/std/cbor.oren`: deterministic CBOR subset + CBOR Sequences streaming helpers.
- `lib/std/regex.oren`: deterministic Thompson NFA regex engine (no backtracking blowups).
- `lib/std/math.oren`: small math helpers (`abs/min/max/clamp`, `is_nan`).
- `lib/std/linalg.oren`: scalar-first + typed-buffer HPC kernels (dot/axpy/matmul), with deterministic order and NEON-ready boundaries.
  - f64 buffer matmul is available (`matmul_f64_buf`) via dot-slice building blocks.
  - i32 matmul uses a microkernel boundary (1×4) to reduce overhead and enable NEON-friendly implementations.

## Build, Test, Verify


### Prerequisites
- `go` (stage0 bootstrap)
- `make`
- A C toolchain (for the stage0→stage1 self-host chain, via the C backend):
  - macOS/Linux: `cc`
  - Windows (x64): VS2022 Build Tools / `cl.exe` (stage0 auto-configures via `vswhere.exe` + `VsDevCmd.bat` / `vcvars64.bat`; see `docs/REMOTE_X64_ENV.md`)

Windows note (rolling):

- The build uses bash scripts under `scripts/`; prefer MSYS2/Git Bash/Cygwin when running `make` locally on Windows.
- Windows IOCP readiness is still experimental; select‑v0 remains the default unless `OREN_NETPOLL_WIN_IOCP_READY=1` is set (see `docs/WINDOWS_IOCP_NETPOLL.md`).

### Commands
```bash
make bootstrap   # build stage0 Go compiler
make            # build stage1 self-hosted compiler (default target)
make test       # fast native smoke (stage1)
make test-native-all # native tests (all tests/native/*.oren)
make verify-native-quick # stage1 + stage2 native smoke
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
./oren build examples/hello.oren --backend native --target macos --arch arm64 -o hello_native
./oren build examples/hello.oren --backend native --target linux --arch arm64 -o hello_linux_arm64
```

### Build a native x86_64 binary (Linux ELF / Windows PE32+ bring-up)
```bash
./oren build examples/hello.oren --backend native --target linux --arch x64 -o hello_linux_x64
./oren build examples/hello.oren --backend native --target windows --arch x64 -o hello_win_x64.exe
```

Notes:

- The Linux/Windows x86_64 backend is Tier‑1 intent but still in bring-up; see `docs/TODOS.md`.
- To run x86_64 artifacts on real hardware (Win11 + WSL2), use the documented remote workflow: `docs/REMOTE_X64_ENV.md`.

### Debug vs release (native backend)

- Native builds default to **debug** (readable stack traces, debug-info tables).
- Use `--no-debug` (or `OREN_NATIVE_NO_DEBUG=1`) for **release** builds.
- `@cfg("debug")` / `@cfg("release")` can be used to gate debug-only statements:

```oren
@cfg("debug") print("trace: enter foo")
```

### Fast native verification (recommended on macOS/Linux)
```bash
make verify-native-quick
```

### Build bytecode + run on AVM (experimental)
```bash
./oren build examples/hello.oren --backend bytecode -o hello.obc
make avm
./avm hello.obc
```

### “Scan before execute” (policy scanning; no bytecode execution)
```bash
./avm --print-policy hello.obc
./avm --print-policy-json hello.obc
```

### Governance job object (bind program + policy + inputs; no bytecode execution)
```bash
./avm --print-job hello.obc
./avm --print-job-json hello.obc
```

### Run as an untrusted capsule (safe defaults; rolling)
```bash
./avm --capsule hello.obc
```

Allow a small approved set (example: enable FS only under `build/`):
```bash
./avm --capsule --allow-domains "0,1,6" --fs-allow-prefixes "build/" hello.obc
```

### Budgets / determinism knobs (AVM; rolling)
AVM is designed for agent/governance workflows, so it supports explicit budgets:

- `AVM_GAS`: instruction-step budget
- `AVM_TIMEOUT_MS`: wall-time timeout
- `AVM_MEM_BYTES`: heap budget for VM heap objects
- `AVM_IO_BYTES`: filesystem bytes read/written budget
- `AVM_LOG_BYTES`: record/replay log growth budget (including header)
- `AVM_DETERMINISTIC=1`: enable virtual TIME + deterministic RNG (`AVM_TIME_*`, `AVM_RNG_SEED`)

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
  - `examples/gc_test.oren` (allocation + `native_gc_collect()` sanity; used by `make examples-test`)
  - `examples/ffi_test.oren` (FFI against `libSystem` via `ffi puts`)
  - `examples/libmath.oren` + `examples/ffi_from_libmath.oren` (build dylib via `--lib`, auto-generate header `.h`, `oren scan`, then link via `--link`)

## Notes / Limitations (Important)
- **AVM / `.obc` is rolling:** bytecode format, domains, and semantics are intentionally evolving quickly until a stability milestone is declared.
- **Native backend Linux dynamic linking/FFI:** the ELF emitter currently stubs unresolved imports (no real dynamic linker integration yet).
- **`--emit-c`:** only supported with `--backend c`.
- **`--metadata`:** currently emitted by the native backend (`<out>.meta.json`).
- **macOS signing:** the compiler attempts to codesign outputs (configured Developer ID, with ad-hoc fallback); see `docs/CODESIGN.md`.

## Docs
- `docs/README.md` the starting point

## License

Copyright (c) 2025 Lu Zongbao (rikusouhou@gmail.com).

This project is licensed under the Apache License, Version 2.0. See `LICENSE`.
