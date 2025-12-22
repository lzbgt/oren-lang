# OBC Module Linking (Rolling)

This repo currently treats `.obc` as a **single self-contained program** (AVM bytecode).
For production-grade distribution (especially “compiler-in-AVM”), we also need a way to ship
**precompiled bytecode libraries** (e.g. stdlib) and link them into a final program `.obc`.

This document specifies the **rolling v0** approach used by the self-hosted compiler in this repo.

## Goals

- Allow Oren/AVM to compile user source **without shipping stdlib sources**.
- Keep `.obc` execution semantics unchanged (AVM ignores module metadata).
- Keep the format simple enough to implement in Oren itself (so the compiler can run inside AVM).

## Non-Goals (v0)

- Runtime dynamic module loading (`import` at runtime).
- Stable ABI guarantees across releases (rolling mode).
- Exporting “globals as data symbols” (v0 focuses on function symbols).

## Key Idea: OBX metadata inside `.obc`

`.obc` remains:

- magic `0x0ECD` (bytes `CD 0E`)
- `u16` const count
- tagged constants
- code bytes

To support linking, the compiler optionally appends an **unused** `BYTES` constant containing
an “OBX payload”. AVM does not reference it; it is tooling/linker metadata only.

## OBX Payload Format (binary)

The OBX payload is a byte blob stored inside a `BYTES` constant:

- prefix: ASCII `OREN_OBX\n1\n`
- `u16` `module_name_len`, followed by `module_name` UTF-8 bytes
- `u16` `export_count`
  - repeated `export_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `addr` (byte offset into this module’s code section)
- `u16` `reloc_count`
  - repeated `reloc_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `pos` (byte offset into this module’s code where a `u32` address must be patched)
    - `u8`  `kind`:
      - `0` = `CALL32` target relocation
      - `1` = `PUSH_FUNC32` target relocation

The linker rebases `addr` and `pos` as it concatenates modules.

## Stable Symbol Names for `std:` Imports

To make separate compilation feasible, stdlib modules use a stable, deterministic prefix:

- `std:math` uses prefix `STD_math_`
- `std:net/http` uses prefix `STD_net_http_`

Then `fn sqrt(x)` inside `std:math` becomes an exported symbol:

- `STD_math_sqrt`

This stable naming is required so user code compiled in “extern stdlib” mode calls the same
symbol names that exist in the precompiled stdlib bundle.

## Compiler Flags (Rolling)

### Build a library/bundle with exports

Build bytecode and include OBX exports:

```
./oren build lib/std/stdlib.oren --backend bytecode -o build/stdlib_bundle.obc --obc-lib
```

This emits a normal runnable `.obc` plus an OBX payload containing exported function symbols.

### Build an app linking against a precompiled stdlib

Compile user code while treating `std:` imports as extern (no std sources loaded), then link in the bundle:

```
./oren build app.oren --backend bytecode -o app.obc --stdlib-mode obc --stdlib-obc build/stdlib_bundle.obc
```

This mode:

- keeps unresolved calls as relocations (instead of hard compile errors)
- links the stdlib bundle `.obc` into the final output `.obc`
- patches relocations using OBX exports

## Implementation Notes

- The linker patches:
  - `PUSH_CONST` indices (const pool concatenation)
  - `LOAD_GLOBAL` / `STORE_GLOBAL` indices (global index rebasing)
  - `CALL32` / `PUSH_FUNC32` absolute code addresses (code section rebasing)
  - OBX relocations (symbol resolution)
- Relative jump offsets (`JMP32`/`JMP_IF32`) remain valid under concatenation.

## Files

- Linker implementation: `lib/compiler/obc_link.oren`
- Stdlib bundle root: `lib/std/stdlib.oren`
- Module prefixing + extern stdlib mode: `lib/compiler/compiler/020_modules_linking.oren`

