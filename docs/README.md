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

- `docs/DESIGN.md` — design + toolchain, build/test/self-hosting, Tier‑1 targets, portability notes, remote x64 workflow

## 3) Benchmarks (perf sanity)

Local cross-backend microbenchmarks live under `benchmarks/`:

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`

## 4) Canonical doc map (read only what you need)

**Start here / trackers**

- `docs/STATUS.md` — task tracker + feature matrix, gaps, roadmap, agentic requirements
- `docs/BLEEDING_EDGE_TASKS.md` — bleeding-edge goals + derived task buckets

**Language (user-facing)**

- `docs/LANGUAGE.md` — manual + spec + appendices (single canonical language doc)

**Design + toolchain (compiler/runtime/AVM/platforms)**

- `docs/DESIGN.md` — architecture, backends, runtime layering, AVM/OBC summary, and toolchain/platform notes
- `docs/design/tagged_values.md` — staged tagged-value convergence plan and migration gates
- `docs/design/arena_loop_policy.md` — loop arena policy + GC reuse safety (alloc/GC perf track)

## 5) Rolling policy (no stubs)

This repo is in rolling mode: remove empty or duplicate docs instead of keeping stubs.
When a doc is merged, update this map and keep exactly one canonical place for each topic.
