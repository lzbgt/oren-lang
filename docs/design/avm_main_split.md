# AVM CLI main.c Split

**Date:** 2026-02-25

## Goals

- Reduce `lib/avm/main.c` below the 2000-line threshold by splitting into focused units.
- Preserve CLI behavior and output byte-for-byte (no semantic changes).
- Improve maintainability by isolating verifier/policy/fs/disasm/dump utilities.

## Non-goals

- Changing AVM bytecode semantics or verifier behavior.
- Altering CLI flags, defaults, or output formats.
- Refactoring runtime/VM internals outside the CLI surface.

## Constraints

- Keep `main()` as the orchestration entrypoint.
- Avoid introducing new dependencies outside `lib/avm/`.
- Maintain stable symbol names where practical to minimize churn.

## Proposed module map

- `lib/avm/avm_cli_util.[ch]`:
  - file IO helpers (`read_file`), timing (`now_ns`), RSS (`current_rss_bytes`)
  - hex helpers (`bytes_from_hex`, `bytes_to_hex`, trusted pubkey parsing)
  - constant pool cleanup (`free_constant_pool`)
  - error map helpers (`dump_error`)

- `lib/avm/avm_cli_verify.[ch]`:
  - `VerifyResult` and bytecode verifier entrypoints.

- `lib/avm/avm_cli_policy.[ch]`:
  - policy scan + hash helpers, domain parsing, execution-context hashing.

- `lib/avm/avm_cli_fs.[ch]`:
  - FS allow-list parsing, mounts parsing, backend selection parsing.

- `lib/avm/avm_cli_disasm.[ch]`:
  - disassembler + JSON disasm output.

- `lib/avm/avm_cli_dump.[ch]`:
  - stack dump, pause JSON, JSON string escaping, value-type naming.

## Validation

- `make test` (fast Tier-1 smoke)

