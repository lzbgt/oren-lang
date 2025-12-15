# Agentic-AI “Killer Features” (Language + Compiler + AVM)

**Status:** Draft requirements (guidance)  
**Last updated:** 2025-12-15  
**Scope:** Oren language design + compiler toolchain + AVM execution substrate

This repo targets an AI-made, AI-used language/runtime: code is written by agents, executed by agents, and often *debugged/repaired by agents*.

This document lists the **most valuable, modern, “AI-era” features** required to make that loop safe, fast, and self-healing.

Principle: treat **agent execution** as a first-class workload:

- untrusted code may run
- execution must be budgeted
- failures must be machine-readable
- state must be resumable
- effects must be capability-scoped

## 0) Definitions

- **Effectful operation:** any operation that can touch the external world or become nondeterministic (FS/NET/PROC/TIME/RNG).
- **Deterministic mode:** the same program + inputs produce the same outputs and the same trace (modulo allowed capabilities recorded for replay).
- **Self-healing loop:** run → observe structured failure → patch → replay deterministically → converge.

## 1) Non-Negotiables (Must-Have)

### 1.1 Deterministic execution + record/replay

Why agents need it:

- debugging must be reproducible (agents iterate fast, regressions happen)
- “retry with fix” requires identical reproduction of the failure

Requirements:

- deterministic semantics for core ops (int overflow, float behavior policy, string encoding assumptions)
- deterministic scheduler mode (for tasks/coroutines), or “single-thread deterministic” baseline
- record/replay for effectful native calls:
  - record `(domain, op, args) -> (ret, err, bytes_out)` plus timing info
  - replay without touching the real host

### 1.2 Snapshot / restore (resumability)

Why agents need it:

- long-running tasks cannot keep processes alive for days
- “pause and heal” requires checkpointing at safe points

Requirements:

- snapshot includes: PC, call frames, operand stack, locals/globals, and heap objects
- snapshot format is content-addressable-friendly (chunked or hashed) to avoid huge rewrites
- restore resumes with deterministic mode constraints

### 1.3 Capability model (least privilege) + virtualization hooks

Why agents need it:

- agent output may be unsafe by default
- sandboxing must be *enforceable*, not “convention-based”

Requirements:

- capability-scoped host calls: `CALL_NATIVE2(domain, op, nargs)`
- allow-lists (FS path prefixes, NET host allow-lists)
- a virtualization layer for “Matrix sandbox” scenarios:
  - VirtualFS / VirtualNET / VirtualPROC implementations
  - same bytecode can run against “real” or “simulated” services

Runtime constraint (repo decision):

- native runtime should be **syscall-first** and avoid C shims (no glibc/libSystem dependencies for core services where practical)

### 1.4 Resource metering (budgets) + preemption points

Why agents need it:

- agent code can loop or hang (including waiting on I/O)
- production needs to run many agent instances safely

Requirements:

- instruction budget (“gas”)
- wall-time budget (timeout) with periodic checks/preemption points
- memory budget (heap + buffers)
- I/O budgets (bytes read/written, request counts)

### 1.5 Structured diagnostics (machine-readable)

Why agents need it:

- agents must parse errors reliably (no fragile string matching)
- enables automated triage and fix suggestions

Requirements:

- stable error codes + structured payloads:
  - `{ code, msg, span, function, backtrace, hints }`
- source maps across all backends where possible:
  - `.oren` span → IR/bytecode PC → (optional) native PC
- event log hooks for tracing:
  - `span_start`, `span_end`, `log`, `metric`, `error`

## 2) Core “AI-Era” Language Features

These features help agents write correct, maintainable, *auditable* code.

### 2.1 Structured concurrency (cancellation + deadlines)

Why:

- agents often do “parallel search” and must cancel losers fast
- prevents orphaned background work and resource leaks

Requirements:

- `task_group`-like structured scope
- cancellation token propagation (implicit or explicit)
- deadline/timeouts as part of the execution context

### 2.2 Error model that supports recovery

Why:

- agent workflows must recover from partial failures (NET down, file missing)

Requirements (pick one and standardize):

- `Result<T, E>`-style values, or
- `throw`/`catch` with typed errors, or
- `nil` + `err` out-of-band convention (less ideal)

Additionally:

- effectful operations must return recoverable errors instead of hard-crashing

### 2.3 Contracts + tests as first-class syntax

Why:

- the fastest agent loop is “generate tests + run + fix”

Requirements:

- `assert` and `test` blocks (syntax + runner integration)
- optional contracts (pre/post conditions) for critical APIs

### 2.4 Introspection surfaces for agents (tooling-first)

Why:

- agents need an API to understand programs without brittle parsing

Requirements:

- compiler exports:
  - AST/IR as JSON
  - symbol table info (public API surface)
  - docs extraction (`///`) into machine-readable artifacts
- stable formatting / pretty-printing for patch workflows

## 3) Core “AI-Era” AVM Features (Agentic VM)

### 3.1 Verifiable bytecode (static checks before execution)

Why:

- agents may execute untrusted scripts; the VM should reject bad programs early

Requirements:

- bytecode verifier:
  - stack depth validation
  - jump target validation
  - constant pool bounds validation
  - native call argument count/type checks (as much as possible)
- policy scanner:
  - “this bytecode requests NET”
  - “this bytecode can spawn PROC”

### 3.2 Typed buffers + SIMD kernels (no-JIT performance path)

Why:

- embedding/vector math shows up everywhere in agent systems
- “no JIT” environments still need fast numeric primitives

Requirements:

- `BYTES` + typed numeric buffers (`F32_BUF` first)
- SIMD domain (side-effect free) for `dot/add/mul/reduce`
- strict semantics + scalar fallback compatibility

### 3.3 “Repair-friendly” execution substrate

Why:

- agents will patch code while keeping state

Requirements:

- hot reload / safe patching:
  - load new code blob
  - compatibility check
  - migrate state when possible
- deterministic replay to validate “patched behavior”

## 4) What To Implement First (Minimal, High-Leverage Order)

This ordering is designed to avoid huge rewrites:

1) **Structured errors + stable error codes** (compiler + AVM + runtime)
2) **Budgeting/timeouts everywhere** (VM loop + native calls + test harness)
3) **Capability enforcement + allow-lists** (FS first, then NET/PROC)
4) **Verifier + policy scanner** (fast, blocks whole classes of bugs)
5) **Snapshot/restore** (start with “stop-the-world checkpoint”)
6) **Typed buffers + SIMD kernels** (F32 baseline, scalar fallback first)
7) **Structured concurrency (yield/tasks)** (lowering-based stackless-first)

## 5) Related Docs

- AVM bootstrap spec: `docs/AVM_SPEC.md`
- Next-gen AVM plan: `docs/AVM_SPEC_V1.md`
- Capability domains: `docs/AVM_CAPABILITIES.md`
- VM killer-feature list: `docs/AGENTIC_VM_KILLER_FEATURES.md`
- AI-era language features: `docs/AI_FEATURES.md`
- Concurrency model: `docs/CONCURRENCY_MODEL.md`
