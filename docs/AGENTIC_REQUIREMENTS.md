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

- deterministic mode is the substrate for “k-of-n verification” and swarm consensus on result/state hashes (see `docs/AVM_DESIGN.md#avm-swarm-consensus-agent-mobility-design-validation`).

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

### 3.4 Nested universes (“AVM in AVM”) for scalable simulation

Requirements:

- ability for a program to spawn *child universes* under:
  - strict capability subset (FS/NET/PROC/TIME/RNG/ENV)
  - hierarchical budgets (gas/time/memory/IO)
  - deterministic record/replay or Virtual* backends
- child universes must be resumable (snapshot capsules) and hashable (`RESULT_HASH`/`STATE_HASH`)

Rationale:

- enables “Matrix sandbox” simulation at scale without heavy containers/processes
- enables hierarchical governance: outer agent validates inner agents and plugins

Design reference:

- `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`

### 3.5 Deterministic trace + explainability surfaces (agent debugging)

Deterministic hashing of *final state* is necessary but not sufficient for agent repair.
Agents need *localized evidence* about where divergence or failure happened.

Requirements:

- **Deterministic trace stream** (opt-in, budgeted):
  - event categories: `op_step`, `call_native2`, `alloc`, `error`, `span_start/span_end`
  - trace must be serializable as data (`BYTES`) and replayable
- **Trace hashing**:
  - `TRACE_HASH` is computed from a canonical encoding of trace events
  - trace hashing must be independent of host timing and logging order
- **Explainability hooks**:
  - map `(pc, function)` back to source spans (when debug info is present)
  - expose “last N events” on error to enable agentic root-cause inference

Rationale:

- enables “self-healing” workflows where an agent can diff traces between two runs
- prevents “black box” failures where only a hash mismatch is available

Bootstrap status (rolling, implementation reality as of 2025-12-15):

- `avm --print-trace-hash <file.obc>` prints `TRACE_HASH <sha256>` derived from a canonical trace-event encoding (step + CALL_NATIVE2 + abort).
- `avm --print-trace-bytes-hex <file.obc>` prints:
  - `TRACE_TRUNCATED <0|1>` (best-effort capture may truncate due to budget/alloc failure)
  - `TRACE_BYTES_HEX ...` (trace stream as data; hex for transport)
  Trace capture must **not** affect program semantics: if trace bytes hit budget, AVM truncates (disables further capture) rather than aborting execution.
  Trace bytes storage is governed by `AVM_TRACE_BYTES` and is isolated from `AVM_MEM_BYTES` (program heap budget).
- Deterministic scheduling (tasks) is not implemented yet; see `docs/AVM_DESIGN.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly` for the design direction.

### 3.6 Governance-ready module boundaries (SOLID on bytecode artifacts)

Agentic execution becomes unsafe and unmaintainable if the runtime grows as a monolith.

Requirements:

- **Capability domains are the unit of governance**:
  - each domain/op is documented and policy-controlled
  - dangerous domains (PROC/NET/AVM) are separable and deny-by-default
- **Code as content-addressed modules**:
  - module artifacts are hashed and referenced by hash
  - policies can pin allowed module hashes for supply-chain control
- **Stable “value capsule” serialization**:
  - define a canonical wire encoding for `Nil/Int/Bool/Float/String/Bytes/List/Map`
  - required to pass results/logs/snapshots between universes and swarm nodes

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
