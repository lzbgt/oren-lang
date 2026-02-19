# AVM Design (Rolling)

This document consolidates the rolling AVM design notes into a single reference. It preserves the original content but organizes it into a coherent sequence so links and updates stay consistent.

## Contents
- [AVM Anti-Tamper / Anti-Hack at Startup (Rolling)](#avm-anti-tamper-anti-hack-at-startup-rolling)
- [AVM Concurrency Model (Deterministic, Syscall-First-Aligned, Multiverse-Friendly)](#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly)
- [AVM-in-AVM (“Multiverse”) Design: Nested Virtual Universes](#avm-in-avm-multiverse-design-nested-virtual-universes)
- [AVM Plugins + Nesting (OBC-First, iOS-Safe) (Rolling)](#avm-plugins-nesting-obc-first-ios-safe-rolling)
- [AVM Swarm Consensus + Agent Mobility (Design Validation)](#avm-swarm-consensus-agent-mobility-design-validation)
- [AVM NEON Mapping Plan (arm64, No-JIT-First)](#avm-neon-mapping-plan-arm64-no-jit-first)
- [AVM Time Calibration (Host Convenience)](#avm-time-calibration-host-convenience)

## AVM Anti-Tamper / Anti-Hack at Startup (Rolling)

This doc discusses whether AVM should verify its own integrity at startup (anti-tamper), and what it can
and cannot realistically defend against.

The key question:

> “What if a hacker replaced the AVM binary and also replaced the embedded root public key / verification code?”

### Threat levels (be explicit)

There are multiple “attacker strengths”:

1) **Artifact tampering in transit / at rest**
   - attacker can modify downloaded `.obc` / `.obx` / manifests
   - attacker cannot replace the AVM binary installed on the machine

2) **Local filesystem tampering (no kernel/root)**
   - attacker can modify files in user-writable directories
   - attacker cannot modify system-protected binaries or bypass OS protections

3) **Local machine compromise (root / kernel / debugger)**
   - attacker can replace `/path/to/avm`, patch it on disk, inject code at runtime,
     hook syscalls, change environment, etc.

The AVM signature model (Root CA → org → dev cert chain) is designed primarily for (1) and (2).
For (3), “self-checking” is fundamentally limited (see below).

### What AVM already defends (and how)

- **`.obc` provenance**: AVM verifies `OREN_SIG\n1\n` and optionally `OREN_CERTS\n1\n` before running artifacts.
  - The trust anchor is the **trusted root public key** (embedded or provided externally).
  - If the root public key is trustworthy, tampered artifacts are rejected.

### The hard truth: self-checking cannot create trust from nothing

If the attacker can replace the AVM binary, they can replace:

- the embedded root public key
- the signature verifier implementation
- the startup “self-check” routine itself

So AVM **cannot** “prove its own correctness” to itself if the attacker controls the executable.

This is a classical bootstrapping problem:

- A program cannot securely verify itself without an external trusted anchor.

Therefore, anti-tamper at startup is only meaningful when combined with an *external* trust boundary:

- OS code signing / notarization (macOS)
- secure boot + measured boot (TPM) (Linux/Windows)
- hardware attestation / enclave / TPM quotes
- reproducible build + external hash pinning

### Recommended trust anchors (practical)

#### A) OS code signing (macOS-first)

You already use codesigning for `oren` builds. Extending that mindset to AVM:

- distribute AVM as a codesigned binary
- optionally require notarization for “production distribution” builds

If AVM is codesigned and installed into a protected location, a simple “replace avm” attack becomes harder.

AVM startup “self-check” can then become:

- “verify that the binary is codesigned by expected team id” (platform API check)
- “verify we are not running under a debugger” (anti-debug; mostly a speed bump)

This provides “tamper evidence” under attacker levels (1) and (2), but does not defeat root compromise.

#### B) External root pubkey pinning

For deployments that want maximum control:

- do not embed a root pubkey in AVM
- instead pass `--trusted-pubkey` (or a set) via a deployment mechanism the attacker cannot change
  - system policy file in a protected directory
  - mobile/desktop MDM configuration
  - container image digest / Kubernetes secret (still has its own trust chain)

Then “replace AVM and also replace embedded pubkey” is less meaningful because the trust anchor is outside the binary.

#### C) Measured boot / attestation (future)

To defend against attacker level (3), you need attestation:

- boot measures AVM binary hash into TPM PCRs
- a remote verifier checks PCR quote + policy
- only then is AVM trusted to run sensitive workloads

This is bigger than rolling-mode AVM right now, but is the “correct” direction if you want production-grade anti-tamper.

### What AVM can do at startup (useful, limited)

#### 1) “Self-hash” (weak but cheap)

AVM can compute a hash of its own on-disk image and log it, or compare to an expected hash.

Limitation:

- if the attacker can patch the binary, they can patch the expected hash or the hashing code.

Still useful as:

- diagnostics / telemetry (“what exact AVM build is running?”)
- accidental corruption detection

#### 2) Verify embedded root pubkey is non-zero and matches a build-time constant

This is only meaningful when combined with external constraints (codesign / immutable deployment).
Otherwise the attacker replaces both.

#### 3) Anti-debug / anti-hook checks (speed bumps)

Examples:

- detect debugger attach
- detect LD_PRELOAD / DYLD injection patterns
- detect writable+executable memory mappings

Limitations:

- easy to bypass for a motivated attacker
- can cause false positives and harm developer UX

These are generally not recommended as default policy in rolling mode; they can exist behind a “hardened mode”.

### Answer to “what if hacker replaced the certs and sig?”

#### If they only replace the `.obc`’s certs/sig (OREN_CERTS/OREN_SIG)

AVM rejects it because:

- signature check fails, unless attacker has a valid delegated signing key.

#### If they replace the AVM binary to trust their own key

Then all bets are off unless you have an external trust boundary:

- OS code signing / secure boot / attestation / protected config pinning

This is not unique to Oren: it is the same for basically all verifiers (package managers, runtimes, etc).

### Rolling roadmap recommendation

P0 (now):

- keep artifact signature verification as the primary enforcement boundary
- document the bootstrapping limitation clearly (this doc)
- add optional “diagnostic self-hash” mode (not a security promise)

P1 (soon):

- ship codesigned AVM builds; consider a “release” build pipeline step that signs AVM
- allow a trusted pubkey *set* provided externally (rotation story)

P2 (later):

- measured boot / attestation integration for production deployments that require it


## AVM Concurrency Model (Deterministic, Syscall-First-Aligned, Multiverse-Friendly)

**Status:** Draft (design guidance + priorities)  
**Last updated:** 2025-12-15  
**Scope:** AVM execution semantics (bytecode VM), not the native backend runtime

This document defines what “concurrency” should mean for **AVM** in the AI/agent era, especially given:

- AVM supports **nested universes** (AVM-in-AVM) (`docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`)
- AVM targets restricted environments (iOS/Web/Edge) and must stay **no-JIT-first**
- Oren’s native runtime roadmap is **syscall-first** and avoids libc/pthreads (`docs/SYSCALL_FIRST_RUNTIME_PLAN.md`)

The key requirement is not raw throughput; it is **deterministic, governable concurrency** that composes with:

- capability gating and virtualization
- snapshot/restore and “agent mobility”
- record/replay auditing
- swarm consensus (`docs/AVM_DESIGN.md#avm-swarm-consensus-agent-mobility-design-validation`)

### 0) Non-negotiables

1) **Deterministic baseline**
   - AVM must have a single-thread deterministic execution mode that is stable enough for consensus.
2) **No host-thread nondeterminism in the core VM**
   - AVM must not depend on OS thread scheduling to define semantics.
3) **Blocking is always explicit and budgeted**
   - Any “wait” must be representable as a deterministic state transition (for snapshot/replay), and be subject to gas/time budgets.

### 1) Model: Cooperative, deterministic “tasks” (green threads)

AVM concurrency should be **cooperative** and **deterministic**:

- A VM instance contains N lightweight tasks (“fibers”, “coroutines”, “green threads”).
- At any point, exactly one task is “running” in the interpreter.
- Tasks yield only at explicit yield points:
  - `sleep_ms`
  - blocking channel operations
  - `await` on a syscall-like host op (VirtualFS/VirtualNET/VirtualPROC)
  - explicit `yield` (when syntax lands)

This is aligned with:

- **snapshot/restore**: the scheduler state and task stacks are data
- **nested universes**: each child universe can be modeled as a task that runs under a separate budget allocation
- **syscall-first thinking**: “blocking” means “park until an event”, not “spin”

#### 1.1 Deterministic scheduler rule

Scheduler determinism rule (recommended v0):

- Maintain a FIFO ready queue of runnable task IDs.
- On yield/block, the current task is moved to:
  - ready queue tail (voluntary yield), or
  - a wait queue keyed by (channel/time/event)
- On wake, tasks are enqueued in deterministic order:
  - time events ordered by `(wake_time, task_id)`
  - channel wakeups ordered by `(channel_id, enqueue_order)`

This ensures:

- given the same program + inputs + virtual time + replay logs, scheduling is deterministic
- `TRACE_HASH` can validate schedule decisions without recording them separately

### 2) Syscall-first alignment: AVM “syscalls” are capability-scoped host services

The native runtime’s syscall-first plan (`sys_*`) is about **native backend** independence from libc.

For AVM, “syscall-first alignment” means something analogous:

- all effectful / potentially blocking operations are modeled as explicit **capability-scoped calls**
- such calls must be:
  - denyable (capabilities)
  - budgeted (gas/time/io/log)
  - virtualizable / replayable (Virtual* backends)

Conceptually:

> AVM concurrency is an event loop that multiplexes capability-scoped “syscalls”.

Examples:

- `FS.read_file` may be instantaneous in “real host mode”, but in VirtualFS it is a deterministic lookup.
- `NET.http_request` (future) should always be modeled as an async op with replay logs providing responses in deterministic mode.

### 3) Nested universes as concurrent tasks (multiverse scheduling)

Nested universes (domain `AVM`, run child `.obc`) should integrate with the scheduler as:

- **spawn child universe** → create a child task whose execution is the child VM run
- **join** → parent task blocks until the child finishes (or budget aborts)

Important design choice:

- Child universes should not share mutable memory with the parent.
- Parent/child communicate via explicit data:
  - returned `MAP` (exit_code, hashes, logs)
  - `BYTES` replay log blobs (already supported)

This keeps universes composable and governable.

### 4) No OS threads in AVM semantics (but parallelism is a host optimization)

AVM semantics should be defined as **single-threaded**.

Implementations may:

- run multiple AVM instances in parallel at the host layer (outside semantics)
- use SIMD kernels for pure compute domains

But:

- bytecode-visible concurrency semantics must remain deterministic.

This is crucial for:

- consensus verification
- reproducible agent debugging
- stable snapshot/resume behavior

### 5) What we need before true concurrency lands (prerequisites)

To add task scheduling without breaking determinism, AVM needs:

1) A deterministic trace stream and `TRACE_HASH` (agent debugging + schedule validation)
2) A stable “blocking primitive” model in the VM:
   - “blocked on channel”
   - “blocked until virtual time >= t”
   - “blocked on event id”
3) Snapshot/restore that includes scheduler state
4) Virtualized TIME and record/replay for effectful domains (already partially present)

### 6) Priorities (derived from repo TODOs)

Near-term “must-have” tasks to unlock deterministic concurrency:

- Implement deterministic `TRACE_HASH` and a canonical trace encoding (see `docs/TODOS.md` P1).
- Define the `TASK` domain surface (design first):
  - spawn task (pure)
  - join task (blocking)
  - channel ops + select (blocking)
- Extend snapshot/restore to include tasks + wait queues (once tasks exist).


## AVM-in-AVM (“Multiverse”) Design: Nested Virtual Universes

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

### 0) Is it attractive?

Yes, if (and only if) the following constraints are met:

1) **Deterministic semantics + deterministic serialization** exist (or are explicitly enabled as a mode).
2) **Effect virtualization** exists so that “universe A” can be replayed identically on another node.
3) **Hierarchical budgeting** exists so parents can cap child universes and avoid denial-of-service.
4) **Capsule-able state** exists (snapshot/restore) so universes can migrate or suspend cheaply.

Without these, “VM-in-VM” becomes either:

- a slow novelty (pure interpreter inside interpreter), or
- an unsafe escape hatch (child can still touch host).

### 1) What “nested universes” means (precise model)

We define a **Universe** as an execution instance:

- **program**: `.obc` bytecode (or a code pointer in the future)
- **policy**: capability set + allowlists + budgets + deterministic mode flags
- **inputs**: args + injected fixtures (files/env/net fixtures) + optional initial snapshot
- **effects**: either forbidden, or mediated via record/replay / Virtual* backends
- **outputs**: result value, structured error, optional snapshot, and hashes

The key property:

> A universe is a *function of* `(program, policy, inputs, replay_log)` producing `(result, produced_log, snapshot, hashes)`.

That makes a child universe composable inside a parent agent workflow.

### 2) Two implementation strategies (feasibility)

#### 2.1 Strategy A (high feasibility, high value): “Nested universes via host service”

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

#### 2.2 Strategy B (possible but low value): “AVM interpreter written in Oren”

Write a bytecode interpreter in `.oren`, compile it to `.obc`, and run it on AVM.

Feasible in principle, but:

- performance is much worse (interpreter-in-interpreter)
- it increases attack surface in user space
- it doesn’t magically solve effect virtualization; it still needs the same host boundary

This can be a later “proof of bootstrapping” demo, not the core architecture.

### 3) The “Capsule” abstraction (what moves between nodes/universes)

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

### 4) Determinism boundary: what must be replayed/virtualized

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
- NET is virtualized in bootstrap via **VirtualNET fixtures** (no host network; deterministic fixture responses).

Nested universes become dramatically more attractive once TIME and RNG are virtualized, because agents often depend on them even when “no external I/O” is intended.

### 4.1) Virtual by default, host by explicit enrollment (recommended)

In this repo’s design, capability **domains** (FS/NET/PROC/…) define *what effect is being requested*.
Separately, each domain is bound at runtime to a **backend**:

- **virtual backend**: no host effects, deterministic fixtures, snapshot-friendly
- **host backend**: touches real host resources, not inherently deterministic or snapshot-portable

Recommended rule (matches capsule safety goals):

1) **Capsule / simulation / nested universes default to virtual backends** (VirtualFS/VirtualNET/VirtualPROC).
2) Host backends are allowed only by **explicit enrollment** in the execution context (and therefore bound into `EXEC_HASH_SHA256` / job objects).

This keeps governance honest: a verifier can distinguish “safe simulation” vs “live host effects”.

### 4.2) Direct host mapping (no relay) vs proxying through the parent

There are two ways a child universe can touch real resources:

#### Option A: direct host mapping (no relay; simplest)

The child universe runs with `*_backend=host` and directly executes host calls in-process.

This is attractive because:

- no “relay protocol” between universes is required
- performance is better (no marshaling or forwarding)
- semantics are simple (“child is just another VM instance in the same host process”)

Safety requirement (must hold):

- child effective policy must be a strict subset of the parent:
  - capabilities subset
  - allowlists subset (FS prefixes / NET allowlist / PROC allowlist)
  - budgets subset (gas/mem/io/log/timeouts)
- backend selection must be bound into `exec_hash` so it is audit-visible

Tradeoff:

- determinism is reduced unless effects are recorded/replayed
- snapshot/mobility is reduced because host resources cannot be serialized directly

#### Option B: proxying/relaying via the parent (more control; more complexity)

The child universe requests effects, but the parent (or host) performs them on its behalf.

This can add control points (e.g., interactive approvals, extra auditing), but it introduces:

- an IPC/protocol design problem
- performance overhead
- new failure modes (relay bugs break determinism)

Recommendation:

- Use Option A (direct host mapping) for trusted “live” workflows.
- Use Virtual backends + record/replay for deterministic/governed workflows.

### 4.3) Handle delegation (fd/socket passing) — later, explicit mode only

A tempting extension is to allow the parent universe to pass already-open host resources to a child:

- open file descriptors
- sockets
- process handles

This is powerful, but it has sharp edges for the core niche (determinism + mobility):

- raw host handles are not snapshot-portable
- replay on another node cannot reproduce the same handle identity
- policy must define who owns closing the handle and how budgets are charged

Recommended v0 stance:

- **Name-based access only** in nested universes (paths/URLs/commands) under allowlists.
- Do **not** allow passing raw host handles between universes in capsule/deterministic mode.

If/when handle delegation is added later:

- make it an explicit opt-in execution flag (e.g., `host_handles_allowed=1`)
- bind it into `exec_hash` (so governance sees that the run is non-portable)
- define snapshot restrictions clearly (either “cannot snapshot” or “snapshot does not preserve handles”)

### 5) Hierarchical budgets (must-have for safety)

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

### 6) Why this is an “AI-era” killer feature (not a traditional VM feature)

Nested universes enable a common agent loop pattern:

1) Outer agent proposes N candidate plans.
2) For each plan, it spawns a child universe with a VirtualFS/VirtualNET fixture set.
3) Each child runs the plan code deterministically with strict budgets.
4) Outer agent compares child `RESULT_HASH`/trace summaries and selects the best plan.
5) Outer agent optionally replays the winning child universe on multiple swarm nodes (k-of-n).

This is “best-first search with safe simulation” as a first-class runtime capability.

### 6.1) Closing the loop: compiler-in-AVM (source → `.obc` inside the sandbox)

This repo’s “agent-native” ambition becomes dramatically more powerful once AVM can **ingest Oren source** and **emit `.obc`** *without a host toolchain*.

At a systems level, this does **not** require AVM to implement a full compiler in C.
Instead, AVM can run the compiler itself as a deterministic capsule:

- `oren.obc` (the Oren compiler compiled to bytecode)
- optional compiler snapshot (warm-start)
- strict governance: caps + budgets (gas/mem/io/log) + deterministic TIME/RNG

#### Why this is attractive (agentic / swarm reasons)

- **Compilation becomes reproducible** (hashable) when the compiler capsule + inputs are fixed.
- A swarm can validate:
  1) the compiler capsule hash, and
  2) the produced `.obc` hash,
  before trusting the result.
- “Self-healing toolchains”: an agent can ship source, compile in-sandbox, and iterate without ever requiring `cc`/`ld`/`codesign`.

#### What is required (practical prerequisites)

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

### 6.2) Current bootstrap cfg keys for nested universes (implementation reality)

When calling `oren_avm_run_obc_bytes(child_obc_bytes, cfg_map)`, the following `cfg` keys exist today (rolling, unstable):

- Capabilities/budgets/determinism:
  - `allowed_domains: int` (bitmask)
  - `gas_limit: int`, `deadline_ns: int`, `mem_bytes: int`, `io_bytes: int`, `log_bytes: int`
  - `deterministic: bool`, `time_start_ns: int`, `time_step_ns: int`, `rng_seed: int`
- Virtual backends (avoid host effects):
  - `fs_backend: int` (`1` = VirtualFS, `0` = host FS)
  - `proc_backend: int` (`1` = VirtualPROC, `0` = host PROC)
  - `net_backend: int` (`1` = VirtualNET, `0` = host NET (not implemented in bootstrap)`)
- Fixture injection as data (for nested universes):
  - `vfs_fixtures: bytes` with magic `AVMVFS01` (path→bytes table)
  - `proc_fixtures: bytes` with magic `AVMPRC01` (cmd→exit_code table)
  - `net_fixtures: bytes` with magic `AVMNET01` (url→body table)

Notes (important, implementation reality):

- **Capability nesting is enforced:** if the parent universe is restricted (deny-by-default with an allowlist),
  the child’s requested `allowed_domains` must be a **subset** of the parent’s allow mask.
  - Example: if the child needs `NET` (domain 4), the parent must also allow domain 4 (otherwise the parent cannot delegate it).
- **Input type matters:** `oren_avm_run_obc_bytes` requires `child_obc_bytes` to be true `BYTES`.
  - `oren_read_bytes(path)` in AVM is legacy and returns `list<int 0..255>`; pack it with `oren_bytes_pack(...)` before calling `oren_avm_run_obc_bytes`.

#### Return shape (today)

On success, `oren_avm_run_obc_bytes(...)` returns a `map` with these keys:

- `exit_code: int`
- `result_hash: bytes` (32 bytes)
- `state_hash: bytes` (32 bytes)
- `record_log: bytes` (magic `AVMLOG01`)
- `last_error: err | nil`
- `vfs_snapshot: bytes | nil` (magic `AVMVFS01` when present)
- `result: any | nil` (child `oren_set_result(...)` value)

### 7) Top emergency tasks (prioritized)

These are the most urgent tasks to make “multiverse” real (not speculative).

#### P0 (blocking): make deterministic universes self-contained

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

#### P1 (high leverage): child-universe service surface

5) **Add an `AVM` capability domain** (host service) to spawn/run child universes.
   - Input: program bytes + caps + budgets + replay log bytes + optional initial snapshot.
   - Output: child result + child result hash + produced log bytes + optional snapshot.
6) **Hash the replay log and print `REPLAY_LOG_HASH`** (and include it in job objects).

#### P2 (scale): traces, verification, governance

7) **Deterministic trace hashing** (optional but high value).
8) **Policy scanner becomes “domain/op” precise** (deny specific ops, not just domains).
9) **VirtualNET / VirtualPROC** backends (fixtures) so simulations can cover real workflows safely.

### 8) Related docs

- Swarm consensus + mobility: `docs/AVM_DESIGN.md#avm-swarm-consensus-agent-mobility-design-validation`
- Next-gen AVM plan (see “Next-Gen AVM Plan” section): `docs/AVM_SPEC.md`
- Agentic requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`

## AVM Plugins + Nesting (OBC-First, iOS-Safe) (Rolling)

Oren’s “restricted environment” track (iOS/App Store, Web, Edge) requires:

- **no JIT** (interpreter-first AVM),
- **capability gating** (no ambient FS/PROC/NET),
- **determinism + budgets** (replayable, composable sandboxes),
- and a distribution story where **stdlib and compiler can run as bytecode**.

This doc is a fact-first bridge between:

- multiverse execution (`docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`),
- bytecode module linking (`docs/OBC.md`),
- stdlib distribution/resolution (`docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`),
- and the repo-wide roadmap (`docs/TODOS.md`, `docs/LANGUAGE_STATUS_AND_GAPS.md`).

**Last updated:** 2026-01-16

---

### 1) Terminology (concrete)

- **OBC**: an `.obc` bytecode program executed by the AVM interpreter.
- **OBX**: linker metadata embedded as an unused `BYTES` constant inside `.obc` (exports + relocs). AVM ignores it at runtime. See `docs/OBC.md`.
- **Universe**: one AVM instance with its own budgets, deterministic TIME/RNG, and capability allow mask.
- **Child universe / nesting**: running one `.obc` inside another via a governance boundary (caps + budgets + virtual backends).

This repo uses “plugin” in two different senses. Keeping them separate avoids design drift.

---

### 2) Plugin Model A (works with iOS constraints): plugin = child universe

#### Why this is the default “plugin” model for AVM

On iOS/App Store, a “plugin” must not:

- require `dlopen` of arbitrary native code,
- require JIT,
- share ambient host effects (FS/NET/PROC) unless explicitly delegated.

So the most robust plugin shape is:

1) Outer program (host or AVM) selects a plugin `.obc` (as `BYTES`).
2) Outer runs it as a **child universe** with an explicit config map:
   - `allowed_domains` subset,
   - budgets (`gas_limit`, `mem_bytes`, `deadline_ns`, `io_bytes`, `log_bytes`),
   - virtual backends + fixtures (VirtualFS/VirtualPROC/VirtualNET),
   - deterministic TIME/RNG.
3) Child returns:
   - `exit_code`, `result`, `result_hash`, `state_hash`,
   - optional `record_log` + `vfs_snapshot`.

Status (fact, today):

- Nested-universe execution is described (and partially implemented) via `oren_avm_run_obc_bytes(child_obc_bytes, cfg_map)`:
  - Interface + cfg keys: `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes` section “6.2 Current bootstrap cfg keys”.
  - Determinism/fixtures intent: `docs/AVM_SPEC.md` (Next-Gen plan section), `docs/AGENTIC_REQUIREMENTS.md`.

This model is already “plugin-friendly” because:

- it composes with budgets (prevents “plugin fork bombs”),
- it composes with determinism (replay log is data),
- it composes with capability delegation (parent can only delegate what it has).

#### What “stdlib and compiler as plugins” means under Model A

- **stdlib**: ship a precompiled `stdlib_bundle.obc` and link it at compile-time (preferred) or run it in a child universe for isolated tooling tasks.
- **compiler**: ship `oren.obc` and run it in a child universe to compile source → output `.obc` inside VirtualFS.

This is “compiler-in-AVM” without requiring a C compiler inside the sandbox.

---

### 3) Plugin Model B (future, more complex): runtime module loading inside one universe

This is the classic dynamic language “plugin” model: load modules at runtime and call their functions *in the same VM instance*.

What it enables:

- shared caches (one copy of stdlib across multiple apps),
- smaller app artifacts (load-on-demand modules),
- “true plugin” APIs: trait objects + dynamic dispatch to code discovered at runtime.

What it requires (not fully implemented today):

1) **Runtime module identity and policy**
   - stable module naming / hashing scheme,
   - allow/deny rules: which modules may be loaded.

2) **A bytecode linking ABI usable at runtime**
   - exported symbol table
   - relocation / import resolution
   - global storage model: “per module” vs “shared globals”.

3) **Loader surface**
   - load module bytes, verify, link into current universe, return a module handle.

Current repo status (fact):

- Compile-time linking exists via OBX (`docs/OBC.md`).
- Runtime dynamic module loading is explicitly a **non-goal** of the current OBX v0 format.

Therefore, treat Model B as a later step once the module ABI is stable and the security model is precise.

---

### 4) Practical milestone: compiler-in-AVM (source → `.obc` as data)

The “iOS-safe” end state is:

- Ship `libavm` + `oren.obc` in the app bundle.
- Provide a VirtualFS tree containing:
  - user sources,
  - stdlib sources OR precompiled stdlib bundle (depending on mode),
  - output path.
- Run `oren.obc` in a restricted universe to produce `out.obc` into VirtualFS.
- Optionally verify and run the produced `out.obc` as a second child universe (or as a sibling universe).

Key supporting docs:

- `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes` (compiler-in-AVM section)
- `docs/OBC.md` (precompiled stdlib bundle + relocations)
- `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` (stdlib specifiers + distribution models)

---

### 5) Recommended tracker items (so we don’t drift)

When updating `docs/TODOS.md`, keep these as separate deliverables:

1) **Model A hardening (child-universe plugins)**
   - stable `cfg` schema for `oren_avm_run_obc_bytes`
   - record/replay logs as `BYTES` (not paths)
   - deterministic TIME/RNG + budgets enforcement

2) **Compiler-in-AVM packaging**
   - produce and ship `oren.obc`
   - produce and ship `stdlib_bundle.obc` (or stdlib pack)

3) **Model B runtime module loading (optional later)**
   - only after module ABI + policy model is mature
   - likely built on top of OBX, but not the same as compile-time OBX linking

---

### 6) Local workflow (build + run smoke)

This repo includes a small “bytecode linking actually works” smoke that is useful before
attempting full compiler-in-AVM.

Build the stdlib bundle (exports via OBX) and run a tiny linked program under the host `avm`:

```
./scripts/verify_avm_bytecode_link_smoke.sh
```

Notes (rolling):

- `scripts/build_avm_plugins.sh` defaults to `lib/std/stdlib_avm.oren` (AVM-safe subset).
- Override the bundle root via `OREN_STDLIB_BUNDLE_ROOT=...` when experimenting.

Outputs (rolling):

- stdlib bundle: `build/plugins/stdlib_bundle.obc`
- linked app: `build/tmp/avm_obc_link_smoke.obc`
- logs: `build/logs/*avm_obc_link_smoke*`

Optional (heavier, rolling):

```
OREN_BUILD_COMPILER_OBC=1 ./scripts/build_avm_plugins.sh
```

This attempts to build a self-contained `build/plugins/oren.obc` by linking against `stdlib_bundle.obc`.

## AVM Swarm Consensus + Agent Mobility (Design Validation)

**Status:** Draft (design + feasibility analysis)  
**Last updated:** 2025-12-15  
**Scope:** “Swarms of agentic AI” running Oren bytecode (`.obc`) on AVM across many nodes

This document validates and extends the idea:

> Many AVM nodes form a swarm. They can reach consensus on outcomes. An AI agent can “flow everywhere” across the swarm, migrate between nodes, validate work, and extend capabilities safely.

The goal is to turn this into a **practical, testable architecture** that is attractive for AI-era workloads, without pretending away distributed-systems realities.

Related design extension:

- Nested universes (“AVM in AVM”): `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`

### 0) What problem this solves (and what it does not)

#### Solves

- **Deterministic validation at scale:** many nodes independently run the same `.obc` and agree on outputs/state hashes.
- **Safe untrusted code execution:** capability-gated side effects mean “agent code” can be evaluated without giving it arbitrary host control.
- **Agent mobility:** an agent’s execution state can be snapshotted and resumed on another node (or after a crash).
- **Self-healing workflows:** deterministic record/replay enables “retry with fix” across nodes.

#### Does not solve automatically

- **Sybil resistance / identity:** you still need identities, attestation, or membership controls.
- **Network truth:** consensus can’t fix “the external world changed” unless effects are virtualized or recorded.
- **Byzantine faults:** if nodes lie, you need a BFT-style protocol and signatures.
- **Privacy:** you must design what state can be shared and what must be encrypted/redacted.

### 1) Core primitives (must exist to make the idea real)

The swarm vision is only practicable if these primitives are defined and enforced.

#### 1.1 Deterministic execution and deterministic serialization

Requirement:

- same `.obc` + same inputs + same deterministic mode + same capability replay log
  → same **result** and same **state hash**.

Implications for AVM:

- define core semantics precisely (ints, floats policy, string encoding)
- define map ordering policy (either ordered maps, or “unordered but canonicalized” when hashing/serializing)
- define deterministic scheduling policy for concurrency (or forbid concurrency in deterministic consensus runs)

#### 1.2 Verifier + policy scanner (before execute)

Before any node runs a job, it must be able to verify:

- bytecode validity (stack discipline, jump targets, constant bounds)
- capability usage: which domains are used (`FS/NET/PROC/TIME/RNG/…`)

This enables “trustless-ish” execution:

- nodes can refuse bytecode that requests forbidden capability domains
- nodes can enforce budgets and avoid hangs

#### 1.3 Capability-gated host effects + virtualization

Effectful domains (FS/NET/PROC/TIME/RNG) must be:

- capability-scoped
- deny-by-default in restricted modes
- virtualizable (VirtualFS/VirtualNET/VirtualPROC) for simulation and replay

This turns “consensus on a computation” into something meaningful, because:

- external effects are either banned, virtualized, or recorded/replayed

#### 1.4 Snapshot / restore (“agent mobility”)

An “agent flowing across the swarm” means:

- node A can snapshot the VM state
- node B can restore and continue execution

This requires:

- a stable snapshot format (ideally content-addressed / chunked)
- well-defined “safe points” for snapshotting (e.g., at instruction boundaries, not mid-native-call)

### 2) Two swarm modes (separate them explicitly)

The swarm idea becomes practical when you distinguish:

#### Mode A: Deterministic consensus jobs (“compute consensus”)

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

#### Mode B: Distributed agent execution (“service consensus”)

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

### 3) Minimal protocol sketch (practicable, not hand-wavy)

This is an intentionally minimal design that can be implemented incrementally.

#### 3.1 Job object (what the swarm agrees on)

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

Job scanning (rolling, no-execute tooling):

- `avm --print-job <file.obc>` prints a text form with:
  - `JOB_HASH_SHA256 <hex>`
  - `PROGRAM_HASH_SHA256 <hex>`
  - `INPUT_HASH_SHA256 <hex>`
  - `EXEC_HASH_SHA256 <hex>`
  - policy lines (`POLICY_*`)
- `avm --print-job-json <file.obc>` prints `{"schema":"avm.job.v7", ...}`

Current `job_hash_sha256` (v7) definition:

- `job_hash_sha256 = SHA256( "AVMJOB07" || program_hash_sha256_bytes || policy_hash_sha256_bytes || input_hash_sha256_bytes || exec_hash_sha256_bytes )`

Current `input_hash_sha256` (v1) definition:

- `input_hash_sha256 = SHA256( "AVMINP01" || args || snapshot_hash? || replay_log_hash? )`
  - `args` are the CLI args passed after `--` (count + length-prefixed strings)
  - `snapshot_hash` is `SHA256("AVMSNAP1" || snapshot_bytes)` if `--snapshot-in` is provided
  - `replay_log_hash` is `SHA256("AVMRLOG1" || replay_log_bytes)` if `AVM_REPLAY_LOG` or `AVM_REPLAY_LOG_HEX` is provided

Current `exec_hash_sha256` (v7) definition:

- `exec_hash_sha256 = SHA256( "AVMCTX07" || flags || outputs || trace_limits || fs_backend || proc_backend || proc_fixtures || net_backend || effective_allow_domains_mask || fs_allow_prefixes || budgets || deterministic_knobs )`
  - flags include: `capsule`, `verify_strict`, `deny_by_default`, `record_enabled`, `replay_enabled`
  - outputs include:
    - record sink kind (`none|file|mem`) and `snapshot_out_enabled` (paths are intentionally not hashed)
    - requested output surfaces: `state_hash`, `result_hash`, `trace_hash`, `trace_bytes`, `record_log_hex`
  - `trace_limits` include the effective trace step limit (`--trace-limit`) and `AVM_TRACE_BYTES` (when trace bytes output is requested)
  - `fs_backend` selects whether FS domain uses host filesystem or VirtualFS (`host|vfs`)
  - `proc_backend` selects whether PROC domain uses host subprocess or VirtualPROC (`host|vproc`) and binds `proc_exit_code` when `vproc` is selected
  - `net_backend` selects whether NET domain uses host network or VirtualNET (`host|vnet`) and binds `net_fixtures_hash_sha256` when fixtures are provided
  - `effective_allow_domains_mask` is what AVM will actually enforce (e.g. capsule default CORE+EXIT when deny-by-default and no allowlist provided)
  - `fs_allow_prefixes` is the normalized comma-separated list (count + length-prefixed strings)
  - budgets include: `gas`, `timeout_ms`, `mem_bytes`, `io_bytes`, `log_bytes`, `trace_bytes` (with capsule defaults applied if env unset)

#### 3.2 Node execution and attestation (minimum viable)

Each node returns:

- `(job_id, result_hash, exit_status)` signed by node identity (or at least tagged with node ID)

Consensus rule (non-Byzantine baseline):

- accept the result if `k-of-n` nodes agree on `result_hash` (k configurable)

If you need Byzantine tolerance:

- require signatures + membership + BFT (out of scope for v0, but the design must not prevent it)

#### 3.3 Agent mobility protocol (snapshot routing)

“Flow everywhere” becomes concrete as:

- a snapshot blob `snap` + `snap_hash`
- a “resume ticket”: `(snap_hash, job_id, pc, budgets, capabilities)`
- any node can resume by fetching `snap` and continuing

Important:

- resuming must preserve the same deterministic constraints if the goal is consensus

### 4) Why this is attractive (if the requirements are met)

Compared with “just run Python on many machines”, this design can offer:

1) **Verifiable computation**: bytecode verifier + deterministic mode + replay logs
2) **Safety**: capability gating at the VM boundary, not “library convention”
3) **Fast simulation**: VirtualFS/VirtualNET turns agents into “simulated worlds” at scale
4) **Operational resilience**: snapshot/restore enables “immortal agents” (pause/resume)
5) **Governance**: policies are explicit inputs (policy hash), and results are reproducible

### 5) Feasibility constraints (what must be implemented first)

This idea is **attractive** and **practicable** only if the system provides:

1) Deterministic mode definition (including map order / numeric corner cases)
2) Bytecode verifier + capability scanner
3) Stable structured errors (machine-readable) instead of crashes
4) Budgets/timeouts and cancellation
5) Snapshot/restore with canonical serialization and hashing

Without (5), “agent mobility” is limited to “restart from scratch”.
Without (2) and (4), swarms become fragile and unsafe (hangs, malicious bytecode).

### 6) Concrete next steps (aligned with current repo)

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

### 7) Related Docs

- Canonical requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`
- AVM spec (bootstrap + Next-Gen plan section): `docs/AVM_SPEC.md`

## AVM NEON Mapping Plan (arm64, No-JIT-First)

This document defines how the current **typed-buffer kernel ABI** in the C AVM (scalar fallback) evolves into **NEON-accelerated** kernels on arm64 while preserving:

- determinism (consensus safety)
- snapshot/hash stability
- rolling ABI friendliness (we can add kernels, but stable kernels must not change semantics)

Scope: macOS arm64 first, but the plan is written to also apply to Linux arm64.

### 1) Goals

1) **Keep semantics stable**: NEON is an optimization, not a semantic change.
2) **No JIT required**: acceleration is in the interpreter/runtime (C code) using intrinsics.
3) **Determinism-first**: consensus mode must not become “depends on compiler flags”.
4) **Minimal surface**: small set of kernels that unlock most ML-ish workloads.

### 2) Kernel ABI nucleus (what we freeze)

The “ABI nucleus” is the set of kernels whose **names + argument order + return convention** are intended to become stable.

Rule: in-place kernels end with `_into` and always have:

- `dst` first
- inputs next
- scalar last (if any)
- return value is `dst` (for fluent `.oren` style, but still in-place)

Examples:

- `oren_buf_add_f32_into(dst, a, b) -> dst`
- `oren_buf_mul_f32_into(dst, a, b) -> dst`
- `oren_buf_scale_f32_into(dst, a, scalar) -> dst`

Scalar reductions are *not* `_into`:

- `oren_buf_dot_f32(a, b) -> float`
- `oren_buf_reduce_sum_f32(a) -> float`

We also provide allocation-free reduction forms (for pipeline style code and for SIMD kernels that want a “dst first” convention):

- `oren_buf_dot_f32_into(out:f64_buf, a:f32_buf, b:f32_buf) -> out` (stores at `out[0]`)
- `oren_buf_reduce_sum_f32_into(out:f64_buf, a:f32_buf) -> out` (stores at `out[0]`)
- `oren_buf_dot_i32_into(out:i64_buf, a:i32_buf, b:i32_buf) -> out` (stores at `out[0]`)
- `oren_buf_reduce_sum_i32_into(out:i64_buf, a:i32_buf) -> out` (stores at `out[0]`)

### 3) Data layout and loads/stores (must not change)

- Typed buffers are byte arrays with canonical little-endian element encoding:
  - `i32/i64`: two’s complement little-endian
  - `f32/f64`: IEEE-754 bit pattern little-endian
- NEON paths must interpret memory the same way.

Practical requirement:

- Use `memcpy` loads/stores (or unaligned-safe intrinsics) so behavior does not depend on alignment.
- Do not reinterpret pointers into `float*` / `int32_t*` unless alignment is guaranteed and verified.

### 4) Determinism rules for NEON kernels

Determinism constraints (consensus safety) apply even when NEON is enabled:

1) **No fast-math** (`-fno-fast-math`).
2) **No FP contraction / no FMA drift** (`-ffp-contract=off` + TU pragmas).
3) **Fixed evaluation order** for reductions.

Important nuance:

- Elementwise ops (`add`, `mul`, `scale`) are naturally deterministic given IEEE-754 and fixed per-element order.
- Reductions (`dot`, `reduce_sum`) are sensitive to reassociation. Even if SIMD is used, the reduction order must be fixed.

### 5) Recommended NEON strategies per kernel

#### 5.1 Elementwise kernels

These are safe to SIMD as “map” operations:

- `*_add_*_into`
- `*_mul_*_into`
- `*_scale_*_into`

Strategy:

- Process `N` elements in chunks of 4 (for f32) with `float32x4_t`.
- Use a scalar tail loop for `N % 4`.
- Writes must be exact element-by-element results (no reordering).

#### 5.2 Reduction kernels (dot/sum)

These are more delicate.

Strategy for `f32` reductions:

- Compute per-lane partial sums in vector registers (`float32x4_t`).
- Reduce lanes in a **fixed, explicit order** (pairwise in a deterministic sequence).
- Accumulate into a `double` scalar accumulator (already the scalar fallback policy).
- Use a scalar tail loop for remaining elements.

This yields a deterministic order that is stable across compilers and platforms *as long as* fast-math and FP contraction are disabled.

Implementation note (current repo):

- The NEON reductions preserve the scalar semantics by converting `f32 -> f64` and accumulating into a scalar `double` in a fixed element order.
- We intentionally avoid fused multiply-add intrinsics for reductions (no `vmlaq_f64`) to prevent FMA drift.

### 6) Feature gating: runtime + build-time

Runtime:

- Runtime opt-in flag: `AVM_ENABLE_SIMD=1` (default off until validated).
- AVM must remain correct without SIMD; SIMD is an optimization only.
- Consensus mode (deterministic) can force SIMD on/off depending on policy, but it must be explicit and stable.

Build-time:

- Keep AVM built with determinism flags by default.
- Add optional `AVM_SIMD_CFLAGS` when we introduce NEON intrinsics.

### 7) Testing strategy (high signal)

1) Keep a scalar reference implementation (the current code).
2) Add a SIMD-enabled build mode and run the same test suite:
   - smoke suite covers elementwise and reduction kernels
   - state-hash / snapshot-resume tests ensure determinism invariants stay true
3) For float kernels:
   - use exactly representable test constants where possible (e.g. 1.5, 0.25)
   - ensure reductions are tested (dot + reduce_sum)

### 8) What we do next (repo tasks)

1) Freeze the ABI nucleus list in `docs/AVM_SPEC.md` (names + arg order + return convention).
2) Implement NEON versions behind a build flag and runtime flag.
3) Validate:
   - macOS arm64 first
   - linux/arm64 in docker/qemu later

## AVM Time Calibration (Host Convenience)

AVM supports a deterministic virtual clock for consensus and nested universes:

- In deterministic mode (`AVM_DETERMINISTIC=1`), `oren_time_now_ns()` is **derived** from:
  - `AVM_TIME_START_NS` (virtual origin)
  - accumulated `oren_sleep_ms(ms)` (`+ ms * 1e6`)
  - executed “gas” count (`+ gas_executed * AVM_TIME_STEP_NS`)

This is a *logical clock*. It is **not** intended to match the host wall clock.

### What `AVM_TIME_STEP_NS` means

`AVM_TIME_STEP_NS` is:

- “virtual nanoseconds per gas unit”

It is **not**:

- “nanoseconds of CPU time per instruction”
- “cycles”
- “a real-time guarantee”

Consensus semantics depend on **gas** being deterministic and semantic. `AVM_TIME_STEP_NS` is just a scale factor mapping gas units into a monotonic virtual time value.

### Why calibrate it anyway?

Sometimes you want virtual timeouts/backoffs to “feel” roughly like real time on your development machine (especially when you haven’t stabilized gas costs or implemented more realistic domain costs yet).

For that, you can measure how many gas units per second your host executes and pick a convenient `AVM_TIME_STEP_NS`.

### macOS benchmark script

This repo includes a small “pure compute” benchmark that:

- runs an infinite loop (stopped safely by `AVM_GAS=...`)
- measures host wall elapsed time
- reports `ns_per_gas` and suggests `AVM_TIME_STEP_NS`

Run:

```sh
bash tools/bench/bench_time_scale.sh
```

Or override the benchmark gas budget:

```sh
AVM_GAS_BENCH=200000000 bash tools/bench/bench_time_scale.sh
```

The script prints a JSON line from:

- `./avm --print-run-json build/bench_gas.obc`

and computes:

- `ns_per_gas = wall_elapsed_ns / gas_executed`

### Important limitations

- The benchmark result is **host- and build-dependent** (CPU, OS, compiler flags, etc.).
- This does **not** make deterministic virtual time “more correct”; it only makes it more intuitive for interactive use.
- For consensus jobs, treat virtual time as a *simulation time* derived from work, not as a wall-clock substitute.
