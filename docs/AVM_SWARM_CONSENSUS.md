# AVM Swarm Consensus + Agent Mobility (Design Validation)

**Status:** Draft (design + feasibility analysis)  
**Last updated:** 2025-12-15  
**Scope:** “Swarms of agentic AI” running Oren bytecode (`.obc`) on AVM across many nodes

This document validates and extends the idea:

> Many AVM nodes form a swarm. They can reach consensus on outcomes. An AI agent can “flow everywhere” across the swarm, migrate between nodes, validate work, and extend capabilities safely.

The goal is to turn this into a **practical, testable architecture** that is attractive for AI-era workloads, without pretending away distributed-systems realities.

## 0) What problem this solves (and what it does not)

### Solves

- **Deterministic validation at scale:** many nodes independently run the same `.obc` and agree on outputs/state hashes.
- **Safe untrusted code execution:** capability-gated side effects mean “agent code” can be evaluated without giving it arbitrary host control.
- **Agent mobility:** an agent’s execution state can be snapshotted and resumed on another node (or after a crash).
- **Self-healing workflows:** deterministic record/replay enables “retry with fix” across nodes.

### Does not solve automatically

- **Sybil resistance / identity:** you still need identities, attestation, or membership controls.
- **Network truth:** consensus can’t fix “the external world changed” unless effects are virtualized or recorded.
- **Byzantine faults:** if nodes lie, you need a BFT-style protocol and signatures.
- **Privacy:** you must design what state can be shared and what must be encrypted/redacted.

## 1) Core primitives (must exist to make the idea real)

The swarm vision is only practicable if these primitives are defined and enforced.

### 1.1 Deterministic execution and deterministic serialization

Requirement:

- same `.obc` + same inputs + same deterministic mode + same capability replay log
  → same **result** and same **state hash**.

Implications for AVM:

- define core semantics precisely (ints, floats policy, string encoding)
- define map ordering policy (either ordered maps, or “unordered but canonicalized” when hashing/serializing)
- define deterministic scheduling policy for concurrency (or forbid concurrency in deterministic consensus runs)

### 1.2 Verifier + policy scanner (before execute)

Before any node runs a job, it must be able to verify:

- bytecode validity (stack discipline, jump targets, constant bounds)
- capability usage: which domains are used (`FS/NET/PROC/TIME/RNG/…`)

This enables “trustless-ish” execution:

- nodes can refuse bytecode that requests forbidden capability domains
- nodes can enforce budgets and avoid hangs

### 1.3 Capability-gated host effects + virtualization

Effectful domains (FS/NET/PROC/TIME/RNG) must be:

- capability-scoped
- deny-by-default in restricted modes
- virtualizable (VirtualFS/VirtualNET/VirtualPROC) for simulation and replay

This turns “consensus on a computation” into something meaningful, because:

- external effects are either banned, virtualized, or recorded/replayed

### 1.4 Snapshot / restore (“agent mobility”)

An “agent flowing across the swarm” means:

- node A can snapshot the VM state
- node B can restore and continue execution

This requires:

- a stable snapshot format (ideally content-addressed / chunked)
- well-defined “safe points” for snapshotting (e.g., at instruction boundaries, not mid-native-call)

## 2) Two swarm modes (separate them explicitly)

The swarm idea becomes practical when you distinguish:

### Mode A: Deterministic consensus jobs (“compute consensus”)

Goal:

- many nodes run the same job and agree on the output/state hash.

Typical usage:

- verify a proposed patch
- verify that a plan produces expected outputs
- verify a model-scoring routine produces stable results

Constraints:

- deterministic mode on
- external effects disabled or replayed
- strict budgets

### Mode B: Distributed agent execution (“service consensus”)

Goal:

- agents do real work (I/O, network, subprocess) and coordinate.

Typical usage:

- web research agent, build agent, deployment agent

Constraints:

- consensus applies to *records of effects* and *auditable traces*, not “truth”
- you still want capability gating and budgets, but determinism is partial

Practical approach:

- run Mode B as “best effort” with auditing
- use Mode A for verification and governance (“does this change match policy?”)

## 3) Minimal protocol sketch (practicable, not hand-wavy)

This is an intentionally minimal design that can be implemented incrementally.

### 3.1 Job object (what the swarm agrees on)

A “consensus job” is:

- `program_hash`: hash of `.obc`
- `policy_hash`: hash of allowed capabilities + budgets
- `input_hash`: hash of explicit inputs (args, provided files, initial snapshot)
- `replay_log_hash` (optional): if effects are replayed

The job result is:

- `exit_status` (success/error)
- `result_hash` (hash of returned value or final state)
- `trace_hash` (optional: hash of deterministic execution trace)

Practical bootstrap approach:

- start with **state hashing** (hash heap + globals + stack + control state) because it is easy to compute and hard to fake accidentally
- add **result-only hashing** when the VM has an explicit result contract (so it’s not “whatever happens to be on the operand stack”)

Bootstrap status (rolling, as implemented today):

- `avm --print-state-hash <file.obc>` prints `STATE_HASH ...`
- `avm --print-result-hash <file.obc>` prints `RESULT_HASH ...`
- result selection is explicit via `oren_set_result(v)` (if not called, the result is treated as `nil`)

### 3.2 Node execution and attestation (minimum viable)

Each node returns:

- `(job_id, result_hash, exit_status)` signed by node identity (or at least tagged with node ID)

Consensus rule (non-Byzantine baseline):

- accept the result if `k-of-n` nodes agree on `result_hash` (k configurable)

If you need Byzantine tolerance:

- require signatures + membership + BFT (out of scope for v0, but the design must not prevent it)

### 3.3 Agent mobility protocol (snapshot routing)

“Flow everywhere” becomes concrete as:

- a snapshot blob `snap` + `snap_hash`
- a “resume ticket”: `(snap_hash, job_id, pc, budgets, capabilities)`
- any node can resume by fetching `snap` and continuing

Important:

- resuming must preserve the same deterministic constraints if the goal is consensus

## 4) Why this is attractive (if the requirements are met)

Compared with “just run Python on many machines”, this design can offer:

1) **Verifiable computation**: bytecode verifier + deterministic mode + replay logs
2) **Safety**: capability gating at the VM boundary, not “library convention”
3) **Fast simulation**: VirtualFS/VirtualNET turns agents into “simulated worlds” at scale
4) **Operational resilience**: snapshot/restore enables “immortal agents” (pause/resume)
5) **Governance**: policies are explicit inputs (policy hash), and results are reproducible

## 5) Feasibility constraints (what must be implemented first)

This idea is **attractive** and **practicable** only if the system provides:

1) Deterministic mode definition (including map order / numeric corner cases)
2) Bytecode verifier + capability scanner
3) Stable structured errors (machine-readable) instead of crashes
4) Budgets/timeouts and cancellation
5) Snapshot/restore with canonical serialization and hashing

Without (5), “agent mobility” is limited to “restart from scratch”.
Without (2) and (4), swarms become fragile and unsafe (hangs, malicious bytecode).

## 6) Concrete next steps (aligned with current repo)

These are staged to avoid huge rewrites:

1) **Finish error contract** and standardize error representation (today: map-based `{"__err":...}`).
2) **Finalize budgets** (gas + deadlines) across host calls, not just interpreter loop.
3) **Implement verifier + capability scanner** for `.obc`.
4) **Define canonical snapshot format** and implement snapshot/restore for core types.
5) Add a minimal “swarm harness” (future):
   - multiple AVM runs on the same machine to simulate k-of-n consensus
   - compare `result_hash` outputs

Bootstrap status (rolling):

- AVM supports `--print-state-hash` / `--print-result-hash` and a local “k-of-n” harness to validate determinism on one machine:
  - `tools/avm_swarm_local.sh`
  - hash is SHA-256 over a canonicalized serialization (maps hashed in canonical key order)

## 7) Related Docs

- Canonical requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`
- AVM bootstrap spec: `docs/AVM_SPEC.md`
- AVM next-gen plan: `docs/AVM_SPEC_V1.md`
