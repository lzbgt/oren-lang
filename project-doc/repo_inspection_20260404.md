# Repository Inspection Snapshot

**Updated:** 2026-05-26

This is the current repo map. Historical inspection detail was removed because the
implementation has moved substantially.

## Core Directories

- `cmd/` - Go bootstrap tools (`oren`, `oredoc`, `orensign`).
- `lib/compiler/` - self-hosted compiler, parser, lowering, optimizers, and backends.
- `lib/runtime.[ch]` - C backend runtime.
- `lib/runtime_native/` - native backend runtime.
- `lib/avm/` - AVM bytecode VM implementation in C.
- `lib/std/` - shipped stdlib modules.
- `tests/` - fixtures and integration surfaces used as executable spec.
- `scripts/` - verification, readiness, profiling, and triage tools.
- `docs/` - canonical current documentation.
- `project-doc/` - focused dated investigation notes that still affect decisions.

## Main Build Paths

```bash
make
make test
make test-curated
make avm
make test-avm
./oretest
./oretest --selfhost
```

## Current Documentation Shape

- `docs/README.md` is the entry point.
- `docs/STATUS.md` is the concise current readiness snapshot.
- `docs/BLEEDING_EDGE_TASKS.md` is the current task priority list.
- `docs/LANGUAGE.md` is the concise language reference.
- `docs/site/index.html` is the generated navigation site.

## Guardrails

- Do not let source files exceed 2000 lines.
- Keep docs concise and current; do not paste rolling turn logs into canonical docs.
- Raw evidence belongs in `build/logs/`; retained conclusions belong in focused docs.
