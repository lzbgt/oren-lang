# OBC Portability (AVM Universal Artifact)

Oren `.obc` bytecode is designed as an **AVM universal artifact**:

- `.obc` should have **no platform meaning** (no “macOS vs Linux”, no “arm64 vs x64” semantics).
- AVM itself is a native program that depends on the host OS/arch for syscalls and memory mapping.
- The **contract** is: the same `.obc` executes with the same observable results across AVM builds.

In rolling mode we enforce this with a practical, integration-style test:

- compile a representative, integrated `.obc`
- run it on multiple AVM builds
- compare stable hashes of program output + trace

## What is compared

`./avm` supports printing deterministic hashes:

- `RESULT_HASH` — hash of program-visible outputs (logical results)
- `TRACE_HASH` — hash of trace/events (execution trace surface)

Portability means **both hashes match** across platforms.

## Current portability gate (implemented)

Use the script:

`tools/verify_obc_portability.sh`

Or via Make:

`make obc-portability`

It verifies the same `.obc` (`tests/avm/test_smoke_suite.oren`) runs identically on:

- macOS arm64 (host)
- linux/arm64 (persistent docker container)
- linux/x86_64 (WSL2 on remote Win11 host)

Outputs are stored under:

- `build/tmp/obc_portability/`

## Requirements

### 1) Local host

- `./oren` and `./avm` built (normal `make test` already builds them).

### 2) Linux docker container (arm64)

This repo already has a persistent docker workflow:

- container name default: `oren-linux-oretest`
- image default: `ubuntu:24.04`

The script will create/start the container if needed, sync tracked sources, rebuild AVM, then execute the host-built `.obc`.

### 3) Remote x64 host (Win11 + WSL2)

The script uses the existing ssh proxy workflow (see `docs/REMOTE_X64_ENV.md`) and runs AVM inside WSL2 (Linux x86_64).

Environment variables (defaults match the repo’s existing conventions):

- `OREN_REMOTE_X64_HOST` (default: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY` (default: `ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002`)
- `OREN_REMOTE_X64_UNIX_ROOT` (default: `/Users/lzbgt/tmp_oren`)

## Known gaps / next steps

1) **Native Windows AVM**
   - Today, AVM is a POSIX-style program (`unistd.h`, `sys/mman.h`, etc.).
   - Running `.obc` directly on Windows (without WSL2) requires a Windows AVM port (Win32 / NT syscalls).

2) **Compiler bytecode invariants**
   - The compiler currently forces a single bytecode ABI profile (`target=avm`, `arch=avm64`) to prevent host-specific lowering from leaking into `.obc`.
   - This should converge to “bytecode compilation ignores host target entirely” as the IR and lowering become fully portable.
