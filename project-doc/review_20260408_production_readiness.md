# Production Readiness Review Snapshot

**Updated:** 2026-05-26

This file summarizes the retained conclusion from the 2026-04-08 review. The old
turn-by-turn detail was removed to keep project docs navigable.

## Current Verdict

Oren remains rolling, not production-stable. The CLI hardening work from the original
review landed, but broader compiler/runtime production readiness is still blocked by
the items in `docs/STATUS.md`.

## Retained CLI Improvements

- Bootstrap `oren build` now chooses a host-appropriate default target rather than
  hardcoding macOS.
- `oren run` validates missing file arguments.
- Ordinary bootstrap CLI failures return structured diagnostics instead of panicking.
- REPL prompt output respects the provided writer.
- `oredoc` and `orensign` use structured runners with testable exit behavior.

## Remaining Production Blockers

- Native tagged-value convergence is still rolling.
- Runtime robustness and allocator/GC reuse remain W5 concerns.
- x64/Linux/Windows surfaces remain less mature than arm64 macOS.
- AVM is not yet production-ready as an iOS embeddable library.
- Compiler-in-AVM is still fixture-level and not packaged as a release pipeline.

## Current Verification Entrypoints

```bash
make test
make test-curated
make verify-runtime-robustness
make verify-backend-parity
make avm
make test-avm
```
