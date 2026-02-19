# OBC (Oren Bytecode) — Portability + Module Linking (Rolling)

Oren `.obc` bytecode is designed as an **AVM universal artifact**:

- `.obc` should have **no platform meaning** (no “macOS vs Linux”, no “arm64 vs x64” semantics).
- AVM itself is a native program that depends on the host OS/arch for syscalls and memory mapping.
- The **contract** is: the same `.obc` executes with the same observable results across AVM builds.

This document consolidates the rolling rules for portability gates and for module linking (OBX metadata).

## 1) Portability contract and gate (implemented)

### What is compared

`./avm` supports printing deterministic hashes:

- `RESULT_HASH` — hash of program-visible outputs (logical results)
- `TRACE_HASH` — hash of trace/events (execution trace surface)

Portability means **both hashes match** across platforms.

### Current portability gate

Use the script:

- `tools/verify_obc_portability.sh`

Or via Make:

- `make obc-portability`

It verifies the same `.obc` (`tests/avm/test_smoke_suite.oren`) runs identically on:

- macOS arm64 (host)
- linux/arm64 (persistent docker container)
- linux/x86_64 (WSL2 when available on remote Win11 host)

Outputs are stored under:

- `build/tmp/obc_portability/`

### Requirements

1) Local host

- `./oren` and `./avm` built (normal `make test` already builds them).

2) Linux docker container (arm64)

This repo uses an **already-running** persistent Ubuntu toolchain container (it must exist and be
running; the scripts do **not** create a container for you).

- container id/name default: `c7e5f7bd9f5c` (override via `OREN_LINUX_DOCKER_ID=...`)

The portability gate syncs **tracked** sources into `/work/repo`, rebuilds AVM inside the
container, then executes the host-built `.obc`.

3) Remote x64 host (Win11, WSL2 optional)

The script uses the existing ssh proxy workflow (see `docs/REMOTE_X64_ENV.md`) and runs AVM inside
WSL2 (Linux x86_64) when available. If WSL2 is unavailable, skip the remote Linux leg and keep the
Windows leg for native gates.

Environment variables (defaults match the repo’s existing conventions):

- `OREN_REMOTE_X64_HOST` (default: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY` (default: `ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002`)
- `OREN_REMOTE_X64_UNIX_ROOT` (default: `/Users/lzbgt/tmp_oren`)

## 2) Module linking: OBX metadata inside `.obc`

This repo currently treats `.obc` as a **single self-contained program** (AVM bytecode).
For production-grade distribution (especially “compiler-in-AVM”), we also need a way to ship
**precompiled bytecode libraries** (e.g. stdlib) and link them into a final program `.obc`.

The rolling v0 approach is:

- `.obc` execution semantics stay unchanged (AVM ignores module metadata).
- The compiler optionally appends an **unused** `BYTES` constant containing an “OBX payload”.
- Tooling/linker reads OBX metadata to rebase code + resolve symbols.

### Goals

- Allow Oren/AVM to compile user source **without shipping stdlib sources**.
- Keep `.obc` execution semantics unchanged (AVM ignores module metadata).
- Keep the format simple enough to implement in Oren itself (compiler-in-AVM).

### Non-goals (v0)

- Runtime dynamic module loading (`import` at runtime).
- Stable ABI guarantees across releases (rolling mode).
- Exporting “globals as data symbols” (v0 focuses on function symbols).

### OBX payload format (binary)

The OBX payload is a byte blob stored inside a `BYTES` constant:

- prefix: ASCII `OREN_OBX\n1\n`
- `u16` `module_name_len`, followed by `module_name` UTF-8 bytes
- `u16` `export_count`
  - repeated `export_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `addr` (**0-based** byte offset into this module’s code section)
- `u16` `reloc_count`
  - repeated `reloc_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `pos` (**0-based** byte offset into this module’s code where a `u32` address must be patched)
    - `u8`  `kind`:
      - `0` = `CALL32` target relocation
      - `1` = `PUSH_FUNC32` target relocation

The linker rebases `addr` and `pos` as it concatenates modules.

### Stable symbol names for `std:` imports

To make separate compilation feasible, stdlib modules use a stable, deterministic prefix:

- `std:math` uses prefix `STD_math_`
- `std:net/http` uses prefix `STD_net_http_`

Then `fn sqrt(x)` inside `std:math` becomes an exported symbol:

- `STD_math_sqrt`

This stable naming is required so user code compiled in “extern stdlib” mode calls the same
symbol names that exist in the precompiled stdlib bundle.

### Compiler flags (rolling)

Build a library/bundle with exports:

```
./oren build lib/std/stdlib_avm.oren --backend bytecode -o build/stdlib_bundle.obc --obc-lib
```

This emits a normal runnable `.obc` plus an OBX payload containing exported function symbols.

Rolling helper scripts:

- Build stdlib bundle and (optionally) a compiler `.obc`: `scripts/build_avm_plugins.sh`
  - Override bundle root via env `OREN_STDLIB_BUNDLE_ROOT=...`
- Build+run a host `avm` smoke (proves OBX linking works end-to-end):
  `scripts/verify_avm_bytecode_link_smoke.sh`

Build an app linking against a precompiled stdlib:

```
./oren build app.oren --backend bytecode -o app.obc --stdlib-mode obc --stdlib-obc build/stdlib_bundle.obc
```

This mode:

- keeps unresolved calls as relocations (instead of hard compile errors)
- links the stdlib bundle `.obc` into the final output `.obc`
- patches relocations using OBX exports

### Implementation notes

- The linker patches:
  - `PUSH_CONST` indices (const pool concatenation)
  - `LOAD_GLOBAL` / `STORE_GLOBAL` indices (global index rebasing)
  - `CALL32` / `PUSH_FUNC32` absolute code addresses (code section rebasing)
  - OBX relocations (symbol resolution)
- Relative jump offsets (`JMP32`/`JMP_IF32`) remain valid under concatenation.
- To keep execution correct when concatenating multiple modules, the linker strips a trailing
  `HALT` opcode from each **non-final** module during concatenation. This prevents linked libraries
  from terminating the pc=0 “skip function bodies” chain before reaching the main program’s entry.

### Files

- Linker implementation: `lib/compiler/obc_link.oren`
- Stdlib bundle root (AVM-safe subset): `lib/std/stdlib_avm.oren`
- Stdlib bundle root (full, rolling, may include native-only helpers): `lib/std/stdlib.oren`
- Module prefixing + extern stdlib mode: `lib/compiler/compiler/020_modules_linking.oren`

## 3) Known gaps / next steps

1) **Native Windows AVM**
   - Today, AVM is a POSIX-style program (`unistd.h`, `sys/mman.h`, etc.).
   - Running `.obc` directly on Windows (without WSL2) requires a Windows AVM port (Win32 / NT syscalls).

2) **Compiler bytecode invariants**
   - The compiler currently forces a single bytecode ABI profile (`target=avm`, `arch=avm64`) to prevent
     host-specific lowering from leaking into `.obc`.
   - This should converge to “bytecode compilation ignores host target entirely” as the IR and lowering
     become fully portable.
