# Oren Evolution and Roadmap (Rolling)

**Status:** Rolling (consolidated architecture, evolution rules, and roadmap)
**Last updated:** 2026-02-19

This document merges and replaces the prior:

- `docs/EVOLUTION_GUIDE.md`
- `docs/ROADMAP.md`
- `docs/LANGUAGE_EVOLUTION.md`
- `docs/OREN_EVOLUTION.md`

It exists to keep the evolution narrative, stability rules, and roadmap in one coherent place.

---

## 0) The core problem Oren solves (why multiple backends exist)

Oren is two products in one:

1) A native language (server/desktop): compile `.oren` to a host executable (Mach-O on macOS, ELF on Linux) with strong control over OS boundaries and low dependencies.
2) An agent-safe execution substrate (mobile/edge/restricted): compile `.oren` to `.obc` and run on the AVM (Agent Virtual Machine), with deterministic mode, capability governance, and Virtual* backends.

Key architectural bet:

> Governed, replayable execution matters more than native peak speed in v0.

Native performance and full system access still matter for production/server usage, so Oren is a multi-backend compiler by design.

---

## 1) Architecture overview (day0 -> production)

### 1.1 Stage0 Go bootstrapper

- Entry: `cmd/oren` (Go) -> `oren_bootstrap`
- Purpose: Provide a stable starting point to compile `oren.oren` into stage1.

### 1.2 Stage1 self-hosted compiler

- Source: `oren.oren`
- Purpose: The main compiler implementation. Most language and backend evolution happens here.

### 1.3 Backends (C, native, bytecode)

Oren compiles to multiple targets:

- **C backend**: `.oren -> .c -> cc`
  - Portable, reliable for bootstrapping
  - Uses libc in `lib/runtime.[ch]` (acceptable for this backend)
- **Native backend**: `.oren -> Mach-O/ELF`
  - Syscall-first runtime (no libc shims)
  - Primary for production server/desktop
- **Bytecode backend**: `.oren -> .obc`
  - Portable bytecode executed by AVM (agent-safe / restricted environments)

These are complementary targets that form an evolution ladder, not competing ideas.

### 1.4 High-level pipeline

```
Source (.oren)
  -> shared AST
  -> backend selection
     - C backend -> C runtime
     - native backend -> syscall-first runtime
     - bytecode backend -> OBC + AVM
```

### 1.5 Syscall-first native runtime

The native backend runtime must not depend on libc or pthreads as its implementation substrate.
All OS interaction should go through the explicit `sys_*` boundary.

Why it matters:

- Avoids the predictable rewrite later ("use libc now, rewrite it out later")
- Keeps effects explicit and auditable (important for determinism and safety)
- Aligns with AVM capability governance

Primary target today: macOS arm64. Linux arm64 must be validated continuously (QEMU host).

### 1.6 AVM and Virtual* backends

AVM exists because there are environments where:

- JIT is restricted/banned (iOS/App Store)
- shipping a native toolchain is not possible
- deterministic replay and policy scanning are required

AVM offers explicit capability domains and virtualized effects:

- FS domain
- NET domain
- PROC domain
- ENV domain
- TIME/RNG domains
- AVM domain (nested universes)

Virtual* backends provide deterministic, no-host-effects simulation (VirtualFS/NET/PROC),
which is essential for capsules and replayable agent execution.

---

## 2) Language evolution rules (self-hosting stability)

This repo is self-hosting: stage1 is written in `.oren`. That means language changes can
break the compiler itself if not staged. These rules keep the build chain stable.

### 2.1 Definitions

- **Reference semantics:** C backend + `lib/runtime.[ch]` behavior unless explicitly stated.
- **Backends:** C, native arm64, bytecode/AVM.
- **Breaking change:** previously-valid programs fail to parse, typecheck, or run differently.

### 2.2 Principles

1) **Stage changes (do not flip overnight)**
   - Parser accepts new syntax (AST node exists)
   - At least one backend implements it (prefer C backend first)
   - Conformance tests exist
   - Other backends implement or explicitly reject with a clear error
   - Only then may compiler `.oren` sources use it

2) **Prefer additive syntax and desugaring**
   - Add syntax that lowers to existing constructs when possible

3) **Conformance tests are mandatory for semantics**
   - C backend test
   - native backend test (if supported)
   - AVM test (if bytecode semantics are involved)

### 2.3 Language versioning

Rolling mode today:

- No `--lang v0|v1` selector
- No per-source language version header
- Syntax/semantics evolve rapidly with the compiler and tests

Stability policy:

- Until a stability milestone is declared, everything is unstable (parser, ABI, stdlib, bytecode)
- When stability is declared, introduce versioning then (flag/header/feature gates)

### 2.4 Example rollout: `yield`

1) Add keyword + AST node
2) Implement C backend lowering (state machine)
3) Add tests
4) Implement native backend (same lowering)
5) Implement bytecode backend

Preference: stackless-first to avoid multi-stack GC and switching complexity.

---

## 3) Roadmap (phases and priorities)

This section mirrors the rolling roadmap while the active, time-ordered priorities live in `docs/TODOS.md`.

### Goals

- Fast native codegen for macOS/Linux arm64 first, with C backend for bootstrapping and constrained targets.
- Robust type system (generics, traits/interfaces, enums/ADTs, pattern matching) with a sound checker.
- Predictable memory story: optional GC (desktop/server) and deterministic/manual mode (embedded).
- Developer ergonomics: formatter, linter, LSP, test runner, package manager, debugging/profiling hooks.

### Agentic/production constraints

- Syscall-first native runtime (no libc shims)
- Native TCP/IP for production server/desktop usage
- AVM virtualization + multiverse for safe agent execution
- Compiler-in-AVM (source -> `.obc` inside sandbox) for closed-loop deployments
- Linux parity early (avoid macOS-only drift)

### Mitigation strategies

- **Runtime performance:** move from stack-machine codegen to register allocation + small opt pipeline
- **Platform limits:** keep Tier-1 targets arm64 (macOS/Linux) and x86_64 (Linux/Windows)
- **Safety:** move from conservative stack scanning to precise GC with stack maps
- **Ecosystem split:** define stdlib subset that works in `--no-gc` mode

### Phase 1

- Memory/GC: conservative stack scan done; next is precise GC with stack maps and safepoints
- Architecture: keep native backend clean for future targets
- Tier-1 parity: align arm64/x86_64 semantics and runtime surface
- Concurrency: threading primitives + channels/select exist; M:N scheduler groundwork ongoing
- FFI/Linking: macOS dynamic linking done; Linux DT_NEEDED/PLT pending
- Tooling: CLI parity, formatter skeleton, lint scaffolding

Syscall-first runtime track (Phase 1 details):

- Expand and lock `sys_*` surface (FS/PROC/ENV/TIME/NET)
- Native TCP/IP on macOS arm64 (timeouts/cancellation)
- Linux arm64 parity via QEMU host
- x86_64 Tier-1 parity via remote host validation

### Phase 2

- Optimization: register allocation, basic inlining, const-prop
- Concurrency: M:N scheduler + async I/O
- Type system: full checker + generics/monomorphization + traits + enums/ADTs
- Testing: built-in test runner, property testing, coverage hooks
- Packaging: registry, lockfiles, reproducible builds
- Tooling: LSP + DWARF symbols

### Phase 3

- Agent readiness: implement `docs/AGENTIC_REQUIREMENTS.md`
- Concurrency (advanced): pub/sub, fan-out, parallel iterators
- Targets: avoid WASM as a first-class backend; AVM hosted in WASM is acceptable
- Security/trust: deterministic builds, supply chain verification, signed artifacts
- Ecosystem: stdlib build-out (fs/net/crypto/time), Windows story, docs/examples

### Stdlib direction (rolling)

Stdlib is layered bottom-up without libc shims:

- deterministic parsing/encoding (json/yaml/cbor)
- deterministic text tooling (regex)
- small portable math helpers

Higher-level networking libraries layer on top of syscall-first NET and AVM VirtualNET.

---

## 4) Agent-native evolution track (AVM + OBC)

This track targets restricted environments (iOS/Web/Edge) where native toolchains are unavailable.

### Vision: "Universal Agency"

- Oren aims to be a safe, portable language for agents in restricted environments.
- The hybrid runtime philosophy:
  - Native mode for server/desktop
  - Bytecode mode for safe interpretation (AVM)

### AVM/OBC phases

1) **AVM Core**: C stack-machine interpreter (`lib/avm`), define OBC instruction set
2) **Bytecode Backend**: compiler emits `.obc` (`lib/compiler/codegen_bytecode.oren`)
3) **Inception**: compile `oren.oren` to `oren.obc` and run compiler-in-AVM
4) **Agent stdlib**: capability-scoped modules (`fs`, `net/http`, `semantic`, `proc`)
5) **LLM ergonomics**: script mode + FFI for host capabilities

### Current status (rolling)

- Compiler self-hosting (stage2) active
- Backends: C, native arm64, and bytecode operational
- AVM: stack-machine interpreter exists; `.obc` can be emitted and executed
- Host calls: capability-scoped `CALL_NATIVE2(domain, op, nargs)` exists (rolling ABI)

### Critical gaps (agent-grade execution)

- Capability governance (FS/NET/PROC/TIME/CRYPTO/SIMD allow-lists + budgets)
- Snapshotting + determinism (record/replay)
- Memory + concurrency hardening (GC + task interaction)

### Immediate action plan

1) Keep bootstrap AVM working while drafting next-gen plan (typed buffers + SIMD kernels + capability domains)
2) Implement byte-accurate I/O primitives for `.obc` and model artifacts
3) Implement syscall-first runtime direction (no C shims) and validate on Linux
4) Add verifier + budgets + deterministic record/replay + snapshotting

---

## 5) Strategic positioning (why Oren wins its niche)

- Oren is not trying to beat Python for humans or Rust for static safety.
- Oren aims to be the default portable, governed execution substrate for agents.

Winning niche: "PostScript for Agents"

- Safe, portable, resumable execution
- Deterministic and capability-scoped
- Portable bytecode + AVM interpreter

Mobile/edge adoption is the wedge:

- iOS/App Store rules disallow JIT, leaving a gap for fast dynamic agent execution
- AVM fills that gap without requiring host toolchains

Execution priority: runtime capability and determinism over syntax sugar.

---

## 6) References

Canonical references for deeper detail:

- AVM spec + Next-Gen plan: `docs/AVM_AND_OBC.md`
- Agentic requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Core system plans (type system, syscall-first runtime, HPC): `docs/CORE_SYSTEM_PLANS.md`
- Backends overview: `docs/COMPILER_AND_BACKENDS.md`
- Self-hosting: `docs/SELF_HOSTING.md`
- Toolchain bootstrap: `docs/TOOLCHAIN_SELF_HOSTING.md`
- Active tracker: `docs/TODOS.md`
