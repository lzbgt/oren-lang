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
make readiness-report  # quick readiness snapshot (build/reports)
make readiness-report-json  # readiness snapshot + JSON summary
make readiness-report-index  # append JSONL summary for automation
make readiness-report-summary  # build summary markdown + HTML
make readiness-report-index-stats  # build index stats (md + json)
make readiness-report-index-prune  # prune index to last N entries
make readiness-report-index-csv  # export index to CSV
make readiness-report-index-query  # filter index by fields/time
make readiness-report-index-rollup  # daily rollup (md + json)
make readiness-report-dashboard  # build HTML dashboard
make readiness-pipeline  # run readiness report + summary + stats + validate
```

Note: `make test` intentionally runs negative fixtures, so parse/typecheck errors are
expected in the output; treat a non-zero exit status as failure.

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
Readiness schema/tooling: `docs/READINESS.md`.
Readiness index JSON schema: `docs/readiness_index.schema.json`.

## Benchmarks

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`
- Full sweep: `make benchmarks`

## License

Copyright (c) 2025 Lu Zongbao (rikusouhou@gmail.com).

This project is licensed under the Apache License, Version 2.0. See `LICENSE`.
