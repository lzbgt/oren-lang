# AVM-in-AVM (“Multiverse”) Design: Nested Virtual Universes

**Status:** Draft (design + feasibility + priorities)  
**Last updated:** 2025-12-15  
**Scope:** AVM running *child AVM instances* as a capability-governed service (nested deterministic “universes”)

This document extends the swarm/agentic vision with a specific idea:

> An AVM program can spawn a child AVM, creating nested virtual “universes”.  
> Universes can be deterministic, record/replay-effectful, capability-bounded, and resumable.

The target outcome is not “cool recursion”; it is a **practical agent substrate**:

- run thousands of safe simulations (“Matrix”) *inside* a larger agent
- sandbox untrusted plugins as child universes
- enable hierarchical governance and validation (“outer world validates inner worlds”)
- support “agent mobility” even across nested computations (snapshot capsules)

## 0) Is it attractive?

Yes, if (and only if) the following constraints are met:

1) **Deterministic semantics + deterministic serialization** exist (or are explicitly enabled as a mode).
2) **Effect virtualization** exists so that “universe A” can be replayed identically on another node.
3) **Hierarchical budgeting** exists so parents can cap child universes and avoid denial-of-service.
4) **Capsule-able state** exists (snapshot/restore) so universes can migrate or suspend cheaply.

Without these, “VM-in-VM” becomes either:

- a slow novelty (pure interpreter inside interpreter), or
- an unsafe escape hatch (child can still touch host).

## 1) What “nested universes” means (precise model)

We define a **Universe** as an execution instance:

- **program**: `.obc` bytecode (or a code pointer in the future)
- **policy**: capability set + allowlists + budgets + deterministic mode flags
- **inputs**: args + injected fixtures (files/env/net fixtures) + optional initial snapshot
- **effects**: either forbidden, or mediated via record/replay / Virtual* backends
- **outputs**: result value, structured error, optional snapshot, and hashes

The key property:

> A universe is a *function of* `(program, policy, inputs, replay_log)` producing `(result, produced_log, snapshot, hashes)`.

That makes a child universe composable inside a parent agent workflow.

## 2) Two implementation strategies (feasibility)

### 2.1 Strategy A (high feasibility, high value): “Nested universes via host service”

Add a capability domain (conceptually `AVM`) that lets a parent program request:

- spawn a child AVM instance
- run it under specified budgets and capability subset
- return child `RESULT_HASH`/`STATE_HASH` (and optionally the produced replay log)

This does **not** require writing an interpreter in Oren. It requires implementing a host service in `lib/avm` that:

- creates a new `AvmVM`
- loads child program bytes
- enforces budgets/capabilities (subset of parent)
- uses deterministic record/replay or Virtual* backends

Why this is attractive:

- gives “multi-universe” without performance collapse
- keeps enforcement at the AVM boundary (still capability-governed)
- allows strict hierarchy: child can never exceed parent budgets/caps

This is the recommended first approach.

### 2.2 Strategy B (possible but low value): “AVM interpreter written in Oren”

Write a bytecode interpreter in `.oren`, compile it to `.obc`, and run it on AVM.

Feasible in principle, but:

- performance is much worse (interpreter-in-interpreter)
- it increases attack surface in user space
- it doesn’t magically solve effect virtualization; it still needs the same host boundary

This can be a later “proof of bootstrapping” demo, not the core architecture.

## 3) The “Capsule” abstraction (what moves between nodes/universes)

A **Universe Capsule** is the unit that can be:

- hashed (for consensus),
- stored (for persistence),
- transferred (for mobility),
- resumed (for continuation).

Minimum capsule fields (conceptual):

- `program_hash` (hash of `.obc` bytes)
- `policy_hash` (caps, allowlists, budgets, deterministic flags)
- `input_hash` (args + any injected fixtures + initial snapshot hash)
- `replay_log_hash` (if record/replay is used)
- `result_hash` (after run)
- `snapshot_hash` (optional, if paused or persisted)

Design rule:

> A swarm node should be able to verify a capsule without trusting the producer, by rerunning deterministically.

## 4) Determinism boundary: what must be replayed/virtualized

For nested universes to be meaningful, effectful domains must be either:

1) **forbidden** in consensus mode, or
2) **recorded** and replayed exactly.

Effectful domains include:

- FS (filesystem)
- PROC (subprocess)
- ENV (environment)
- TIME (clock, sleep)
- RNG/CRYPTO (randomness, entropy)
- NET (network)

Bootstrap status (repo reality as of 2025-12-15):

- FS/PROC/ENV now support minimal record/replay logs in `avm` (rolling), including in-memory “log as data” (`BYTES`).
- TIME/RNG are virtualized in deterministic mode (derived virtual clock + deterministic PRNG).
- NET is not virtualized yet.

Nested universes become dramatically more attractive once TIME and RNG are virtualized, because agents often depend on them even when “no external I/O” is intended.

## 5) Hierarchical budgets (must-have for safety)

Parent/child budgeting must be **hierarchical**:

- Parent has a total budget (gas/time/memory/IO/log).
- Parent allocates sub-budgets to each child universe.
- Child cannot exceed allocated budget.
- Parent cannot exceed its own budget due to child overhead.

This prevents:

- “fork bomb” universes
- slow replay log amplification attacks
- memory blowups from nested simulation
- log amplification attacks (producing huge record/replay logs as “data capsules”)

## 6) Why this is an “AI-era” killer feature (not a traditional VM feature)

Nested universes enable a common agent loop pattern:

1) Outer agent proposes N candidate plans.
2) For each plan, it spawns a child universe with a VirtualFS/VirtualNET fixture set.
3) Each child runs the plan code deterministically with strict budgets.
4) Outer agent compares child `RESULT_HASH`/trace summaries and selects the best plan.
5) Outer agent optionally replays the winning child universe on multiple swarm nodes (k-of-n).

This is “best-first search with safe simulation” as a first-class runtime capability.

## 6.1) Closing the loop: compiler-in-AVM (source → `.obc` inside the sandbox)

This repo’s “agent-native” ambition becomes dramatically more powerful once AVM can **ingest Oren source** and **emit `.obc`** *without a host toolchain*.

At a systems level, this does **not** require AVM to implement a full compiler in C.
Instead, AVM can run the compiler itself as a deterministic capsule:

- `oren.obc` (the Oren compiler compiled to bytecode)
- optional compiler snapshot (warm-start)
- strict governance: caps + budgets (gas/mem/io/log) + deterministic TIME/RNG

### Why this is attractive (agentic / swarm reasons)

- **Compilation becomes reproducible** (hashable) when the compiler capsule + inputs are fixed.
- A swarm can validate:
  1) the compiler capsule hash, and
  2) the produced `.obc` hash,
  before trusting the result.
- “Self-healing toolchains”: an agent can ship source, compile in-sandbox, and iterate without ever requiring `cc`/`ld`/`codesign`.

### What is required (practical prerequisites)

To make “source → `.obc` inside AVM” useful (not just theoretical), we need:

1) **VirtualFS fixture** for nested universes:
   - parent provides a virtual filesystem tree (as data)
   - child compiler reads `main.oren` and writes `out.obc` into VirtualFS
2) **A stable input channel**:
   - either a VirtualFS file, or explicit `stdin_bytes` / `input_bytes` provided by policy
3) **A result retrieval channel**:
   - either VirtualFS file read-back, or returning `BYTES` directly
4) **Deterministic compilation mode**:
   - deterministic TIME/RNG already exist; compilation must avoid host nondeterminism (env, clocks)
5) **Budgeted logs**:
   - record/replay logs and capsule outputs must be budgeted to prevent amplification.

This design composes naturally with “AVM-in-AVM”: compilation is “just another universe”.

## 7) Top emergency tasks (prioritized)

These are the most urgent tasks to make “multiverse” real (not speculative).

### P0 (blocking): make deterministic universes self-contained

0) **Make the bytecode verifier reliably accept valid code** (no false rejects).
   - Nested universes require verifying *child* `.obc` before running it.
   - Verifier must handle interprocedural calls without spurious “stack height mismatch at join”.
   - Baseline approach (bootstrap): treat callee entry stack depth as `nargs` (relative-to-fp), not caller `sp`.

1) **Introduce `BYTES` as a first-class value type** (packed buffers).
   - Required to carry replay logs *in-memory* (not via host filesystem).
   - Required to embed `.obc` blobs and fixtures as data.
2) **Move record/replay logs from “file paths” to “bytes blobs”** (or support both):
   - `record_log_bytes` and `replay_log_bytes` should be representable as `BYTES`.
   - prefer “log as data” so child universes can be spawned and replayed without host FS.
3) **Virtualize TIME and RNG** (deterministic clock + deterministic RNG).
   - Without this, “deterministic” universes still diverge in common workloads.
4) **Add memory budget enforcement** (heap + buffers).
   - Nested universes without memory caps are unsafe.

### P1 (high leverage): child-universe service surface

5) **Add an `AVM` capability domain** (host service) to spawn/run child universes.
   - Input: program bytes + caps + budgets + replay log bytes + optional initial snapshot.
   - Output: child result + child result hash + produced log bytes + optional snapshot.
6) **Hash the replay log and print `REPLAY_LOG_HASH`** (and include it in job objects).

### P2 (scale): traces, verification, governance

7) **Deterministic trace hashing** (optional but high value).
8) **Policy scanner becomes “domain/op” precise** (deny specific ops, not just domains).
9) **VirtualNET / VirtualPROC** backends (fixtures) so simulations can cover real workflows safely.

## 8) Related docs

- Swarm consensus + mobility: `docs/AVM_SWARM_CONSENSUS.md`
- Next-gen AVM plan: `docs/AVM_SPEC_V1.md`
- Agentic requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`
