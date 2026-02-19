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

- `docs/TOOLCHAIN.md` — build/test/self-hosting + verification flow
- `docs/PLATFORMS.md` — Tier‑1 targets, portability notes, remote x64 workflow

## 3) Benchmarks (perf sanity)

Local cross-backend microbenchmarks live under `benchmarks/`:

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`

## 4) Canonical doc map (read only what you need)

**Start here / trackers**

- `docs/TODOS.md` — single source-of-truth task tracker (weighted + gated)
- `docs/STATUS_AND_ROADMAP.md` — feature matrix, gaps, roadmap, agentic requirements

**Language (user-facing)**

- `docs/LANGUAGE_MANUAL.md` — how to write Oren today
- `docs/LANGUAGE_SPEC.md` — grammar + semantics intent
- `docs/LANGUAGE_APPENDICES.md` — attributes, traits, reflection, object/memory/concurrency/stack model

**Compiler + backends (implementation)**

- `docs/COMPILER.md` — compiler pipeline, IR map, implementation notes, gotchas
- `docs/BACKENDS.md` — C/native/bytecode backends + perf playbook
- `docs/AVM_SPEC.md` — bootstrap AVM spec + instruction set
- `docs/AVM_ROADMAP.md` — next‑gen AVM plan + multiverse design
- `docs/OBC_DISTRIBUTION.md` — OBC portability/linking + signing model

**Stdlib + system design**

- `docs/STDLIB_AND_RUNTIME.md` — stdlib layers, module resolution, collections, GUI, scheduler

**Networking + IO**

- `docs/NETWORKING_IO.md` — async IO, TLS/HTTP2/WS, netpoll

**Platform + tooling**

- `docs/TOOLCHAIN.md` — build, test, self-hosting, CLI/codesign
- `docs/PLATFORMS.md` — portability, Tier‑1 matrix, remote x64

**Other**

- `docs/STATUS_AND_ROADMAP.md` — comparisons + scenarios (kept lean)

## 5) Rolling policy (no stubs)

This repo is in rolling mode: remove empty or duplicate docs instead of keeping stubs.
When a doc is merged, update this map and keep exactly one canonical place for each topic.
