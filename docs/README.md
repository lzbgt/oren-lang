# Start Here: Oren Docs (Canonical)

**Last updated:** 2026-02-19

This file is the single **entry point** for the Oren docs. It merges the former root README
orientation with the docs index so you can start in one place and branch out only when needed.

## 0) What Oren is (fast orientation)

Oren is a **self-hosted language + compiler** with three execution backends:

- **C backend**: portable bootstrap path via a host C toolchain.
- **Native backend**: direct Mach-O/ELF/PE output (Tier‑1 intent).
- **Bytecode backend (OBC)**: `.obc` for the AVM (deterministic, capability-governed VM).

Design intent (rolling): deterministic execution for agent workflows, capability-gated effects,
and a path to compiler-in-AVM for sandboxed compilation.

## 1) Current reality (backends + platforms)

- **C backend (default)**: used in the stage0→stage1 chain and portable to any host with `cc`.
- **Native backend (Tier‑1 intent)**: arm64 is most mature; x86_64 Linux/Windows are in rolling bring‑up.
- **Bytecode backend (experimental)**: emits `.obc` for AVM; format and semantics are still evolving.

Tier‑1 intent targets (rolling): `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

## 2) Quick start (fast path)

Build + test:

```bash
make bootstrap   # build stage0 Go compiler
make            # build stage1 self-hosted compiler
make test       # fast native smoke
```

Build and run a hello binary (C backend by default):

```bash
./oren build examples/hello.oren -o hello
./hello
```

Emit bytecode and run under AVM:

```bash
./oren build examples/hello.oren --backend bytecode -o hello.obc
make avm
./avm hello.obc
```

Details and platform-specific notes live in:

- `docs/BUILD_AND_VERIFY.md`
- `docs/TIER1_SUPPORT_MATRIX.md`
- `docs/REMOTE_X64_ENV.md`

## 3) Benchmarks (perf sanity)

Local cross-backend microbenchmarks live under `benchmarks/`:

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`

## 4) Canonical doc map (read only what you need)

**Start here / trackers**

- `docs/TODOS.md` — single source-of-truth task tracker (rolling priority order)
- `docs/LANGUAGE_STATUS_AND_GAPS.md` — fact-first snapshot of what works vs missing
- `docs/EVOLUTION_AND_ROADMAP.md` — evolution narrative + roadmap
- `docs/AGENTIC_REQUIREMENTS.md` — agentic requirements and order of operations

**Language (user-facing)**

- `docs/LANGUAGE_MANUAL.md` — how to write Oren today
- `docs/LANGUAGE_SPEC.md` — grammar + semantics intent
- `docs/LANGUAGE_FEATURE_MATRIX.md` — feature → status → implementation → tests
- `docs/ATTRIBUTES.md` — attribute cookbook + deterministic metadata contract
- `docs/COMPILER_GOTCHAS.md` — known hazards + invariants

**Compiler + backends (implementation)**

- `docs/COMPILER_AND_BACKENDS.md` — compiler pipeline, IR map, backend design, perf playbook
- `docs/IMPLEMENTATION_NOTES.md` — deep internal notes
- `docs/TOOLCHAIN_SELF_HOSTING.md` — stage0→stage1→stage2 bootstrapping model
- `docs/SELF_HOSTING.md` — self-hosting requirements and contracts

**AVM + OBC (VM + determinism)**

- `docs/AVM_AND_OBC.md` — AVM/OBC spec + next-gen plan
- `docs/STACK_SAFETY.md` — call-depth / recursion guard model
- `docs/CONCURRENCY_MODEL.md` — concurrency + IPC semantics

**Stdlib + system design**

- `docs/STDLIB_LAYERS.md` — builtin syslib vs shipped stdlib separation
- `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` — module resolution + distribution
- `docs/DESIGN_COLLECTIONS.md` — lists/maps/containers design
- `docs/MEMORY.md` — memory model notes

**Networking + IO**

- `docs/NET_TLS.md`
- `docs/NET_HTTP2.md`
- `docs/NET_WEBSOCKET.md`
- `docs/ASYNC_IO_AND_SELECT.md`
- `docs/WINDOWS_IOCP_NETPOLL.md`

**Platform + tooling**

- `docs/BUILD_AND_VERIFY.md`
- `docs/TEST_SYSTEM.md`
- `docs/PORTABILITY_GUIDE.md`
- `docs/REMOTE_X64_ENV.md`
- `docs/TIER1_SUPPORT_MATRIX.md`

**Other**

- `docs/ADVANCED_SCENARIOS.md` — “killer app” scenarios
- `docs/COMPARISON.md` — comparison notes
- `docs/GUI.md` — UI direction

## 5) Rolling policy (no stubs)

This repo is in rolling mode: remove empty or duplicate docs instead of keeping stubs.
When a doc is merged, update this map and keep exactly one canonical place for each topic.
