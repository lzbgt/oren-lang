
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

## Status (Current Reality)
- **Backends**
  - **C backend (default):** transpile to C and compile with `cc` (used for the self-hosting chain).
  - **Native backend (ARM64):** emits Mach-O (macOS) or ELF (Linux) directly (`--backend native`).
  - **Bytecode backend (experimental):** emits `.obc` (`--backend bytecode`) for the AVM prototype.
- **Platforms**
  - Native backend targets **macOS arm64** and **Linux arm64**.
  - C backend is portable to any platform with a C toolchain.

## Stdlib (Rolling highlights)

This repo is intentionally syscall-first and “no libc shims” for native runtime, so the stdlib focuses on **portable, deterministic building blocks**:

- `lib/std/json.oren`: deterministic JSON representation + tolerant decode for config text (C-style comments).
- `lib/std/yaml.oren`: deterministic YAML subset + tolerant decode (YAML `#` and C/JSON `//` + `/* */` comments).
- `lib/std/cbor.oren`: deterministic CBOR subset + CBOR Sequences streaming helpers.
- `lib/std/regex.oren`: deterministic Thompson NFA regex engine (no backtracking blowups).
- `lib/std/math.oren`: small math helpers (`abs/min/max/clamp`, `is_nan`).

## Build, Test, Verify


### Prerequisites
- `go` (stage0 bootstrap)
- `make`
- `cc` (for the C backend; used in self-hosting)

### Commands
```bash
make bootstrap   # build stage0 Go compiler
make            # build stage1 self-hosted compiler (default target)
make test       # curated native + module + AVM bytecode tests (wrapper over `./oretest`)
make test-legacy # broader Makefile-driven suite (slower)
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

### Run the curated suite (recommended)
```bash
./oretest --target macos
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
  - `examples/gc_native.oren` (allocation + `native_gc_collect()` sanity)
  - `examples/ffi_test.oren` (FFI against `libSystem` via `ffi puts`)
  - `examples/libmath.oren` + `examples/ffi_from_libmath.oren` (build dylib via `--lib`, auto-generate header `.h`, `oren scan`, then link via `--link`)

## Notes / Limitations (Important)
- **AVM / `.obc` is rolling:** bytecode format, domains, and semantics are intentionally evolving quickly until a stability milestone is declared.
- **Native backend Linux dynamic linking/FFI:** the ELF emitter currently stubs unresolved imports (no real dynamic linker integration yet).
- **`--emit-c`:** only supported with `--backend c`.
- **`oren test`:** currently supports `--backend native` only.
- **`--metadata`:** currently emitted by the native backend (`<out>.meta.json`).
- **macOS signing:** the compiler attempts to codesign outputs (configured Developer ID, with ad-hoc fallback); see `docs/CODESIGN.md`.

## Docs
- `docs/README.md` the starting point

## License

Copyright (c) 2025 Lu Zongbao (rikusouhou@gmail.com).

This project is licensed under the Apache License, Version 2.0. See `LICENSE`.
