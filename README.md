# Oren (rolling)

Oren is a **self-hosted language + compiler** with three execution backends:

- **C backend** (portable bootstrap)
- **Native backend** (Mach-O / ELF / PE output; Tier‑1 intent)
- **Bytecode backend (OBC)** for the **AVM** (deterministic, capability‑governed VM)

The project targets agent‑grade determinism, capability‑gated effects, and a path to
compiler‑in‑AVM for sandboxed compilation.

## Quick start

```bash
make bootstrap   # stage0 Go compiler
make            # stage1 self-hosted compiler
make test       # fast native smoke
```

Build and run a hello binary:

```bash
./oren build examples/hello.oren -o hello
./hello
```

Run bytecode under AVM:

```bash
./oren build examples/hello.oren --backend bytecode -o hello.obc
make avm
./avm hello.obc
```

## Docs

Start here: `docs/README.md` (canonical entry point and doc map).

## Benchmarks

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`

## License

Copyright (c) 2025 Lu Zongbao (rikusouhou@gmail.com).

This project is licensed under the Apache License, Version 2.0. See `LICENSE`.
