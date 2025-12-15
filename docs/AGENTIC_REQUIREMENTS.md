# Agentic-AI Requirements (Language + Compiler + AVM)

**Status:** Draft requirements (guidance)  
**Last updated:** 2025-12-15  
**Scope:** Oren language design + compiler toolchain + AVM execution substrate

Oren is designed for the “agent loop”:

1) an agent generates/patches code
2) code executes (often with partial trust)
3) failures are observed by another agent
4) the agent patches and replays deterministically until it converges

This document consolidates the “AI-era” requirements that make that loop safe, fast, and self-healing.

## 0) Definitions

- **Effectful operation:** touches the external world or introduces nondeterminism (FS/NET/PROC/TIME/RNG).
- **Deterministic mode:** same program + same inputs → same outputs + same trace, with effects recorded/replayed.
- **Self-healing loop:** run → structured failure → patch → deterministic replay → converge.

## 1) Non-Negotiables (Must-Have Substrate)

### 1.1 Determinism + record/replay (debuggable by agents)

Requirements:

- deterministic semantics for core operations:
  - integer overflow policy (wrap vs trap)
  - float semantics policy (IEEE754 as provided, but document corner cases)
  - string model (byte-string vs UTF-8 semantics; pick and document)
- record/replay for effectful host calls:
  - record `(domain, op, args) -> (ret, err, bytes_out)`
  - replay without touching the real host
- deterministic scheduling policy:
  - provide a “single-thread deterministic” baseline first
  - when coroutines land, define a deterministic scheduler mode (or record/replay scheduling)

Swarm implication:

- deterministic mode is the substrate for “k-of-n verification” and swarm consensus on result/state hashes (see `docs/AVM_SWARM_CONSENSUS.md`).

### 1.2 Snapshot / restore (resumability)

Requirements:

- snapshot includes: PC, call frames, operand stack, locals/globals, heap objects
- snapshots are content-addressable-friendly (chunked/hashes) to reduce churn
- restore resumes under deterministic constraints (or explicitly declares nondeterminism)

### 1.3 Capability model (least privilege) + virtualization hooks

Requirements:

- capability-scoped host calls (`CALL_NATIVE2(domain, op, nargs)` in the rolling ABI)
- allow-lists:
  - FS path prefixes
  - NET target allow-lists
- virtualization hooks (“Matrix sandbox”):
  - VirtualFS / VirtualNET / VirtualPROC backends
  - run the same bytecode against “real” or “simulated” services

Repo runtime constraint (design decision):

- native runtime should be **syscall-first** and avoid C shims (no glibc/libSystem dependency for core services where practical)

### 1.4 Resource metering (budgets) + cancellation/deadlines

Requirements:

- instruction budget (“gas”) with enforcement points
- wall-time deadline/timeout support
- memory budget (heap + buffers)
- I/O budgets (bytes read/written; network requests)
- cancellation token propagation for structured concurrency

### 1.5 Structured diagnostics (machine-readable)

Requirements:

- stable error codes + structured payloads:
  - `{ code, msg, span, function, backtrace, hints }`
- source mapping strategy across backends:
  - `.oren` span → IR / bytecode PC → (optional) native PC
- event log hooks for tracing:
  - `span_start`, `span_end`, `log`, `metric`, `error`

## 2) “AI-Era” Language + Toolchain Features

These features make agent-authored code easier to generate, verify, and maintain.

### 2.1 Contracts + tests as first-class syntax

Requirements:

- `assert` in the core language
- `test` blocks + a test runner that produces machine-readable output
- optional pre/post conditions for critical APIs (design-by-contract)

### 2.2 Error model that supports recovery

Effectful operations must return recoverable errors rather than hard-crashing.

Pick one model and standardize it:

- `Result<T, E>` (preferred for explicitness), or
- `throw`/`catch` with typed errors, or
- `nil` + error-code convention (least preferred; easy to ignore)

### 2.3 Structured concurrency (agent workflows)

Requirements:

- stackless coroutines (`yield` lowering) as the first implementation strategy
- structured scopes (`task_group`-like) with cancellation/deadlines
- timeouts everywhere for effectful operations

### 2.4 Semantic metadata (RAG-ready)

Requirements:

- doc comments (`///`) exported as structured artifacts (JSON/Markdown)
- symbol table export for public APIs:
  - names, signatures, visibility, docs

### 2.5 Introspection surfaces (tooling-first)

Requirements:

- compiler exports:
  - AST/IR in JSON (stable schema)
  - dependency graph / module graph
- stable formatting / pretty-printing for patch workflows

### 2.6 Token-efficiency (reduce boilerplate)

Requirements:

- syntax that is unambiguous to parse
- avoid excessive boilerplate; prefer regular constructs + inference where safe

## 3) “AI-Era” AVM Features (Agentic VM)

### 3.1 Bytecode verification + policy scanning (before execute)

Requirements:

- verifier:
  - stack depth validation
  - jump target validation
  - constant pool bounds validation
  - native call operand decoding validation
- policy scanner:
  - extract “which capability domains are used”
  - reject forbidden domains/ops for a capability set

### 3.2 Typed buffers + SIMD kernels (no-JIT performance path)

Requirements:

- `BYTES` + typed numeric buffers (start with `F32_BUF`)
- SIMD/domain ops for `dot/add/mul/reduce` (side-effect free)
- strict semantics + scalar fallback compatibility

### 3.3 Repair-friendly execution substrate

Requirements:

- snapshot/restore support (agent pause/resume)
- deterministic replay support for patch validation
- optional hot reload / safe patching:
  - load new code blob
  - compatibility check
  - migrate state when possible

## 4) Minimal High-Leverage Implementation Order (Avoid Huge Rewrites)

This ordering is chosen to unlock “agent-grade” behavior early without requiring a massive rewrite:

1) **Structured errors + stable error codes** (compiler + runtime + AVM)
2) **Budgets/timeouts everywhere** (VM loop + native calls + test harness)
3) **Capability enforcement + allow-lists** (FS first, then NET/PROC)
4) **Verifier + policy scanner** (reject bad/untrusted bytecode early)
5) **Snapshot/restore** (stop-the-world checkpoint first)
6) **Typed buffers + SIMD kernels** (F32 baseline, scalar fallback first)
7) **Structured concurrency (`yield`/tasks)** (lowering-based stackless-first)

## 5) Canonical References

- Docs index: `docs/README.md`
- AVM bootstrap spec: `docs/AVM_SPEC.md`
- AVM next-gen plan: `docs/AVM_SPEC_V1.md`
- Syscall-first runtime plan: `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`
- Language spec: `docs/LANGUAGE_SPEC.md`
- Concurrency model: `docs/CONCURRENCY_MODEL.md`
