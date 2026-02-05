# Oren Rolling Goals: Use **MANTIS** as a Testbed to Drive Oren to Production‑Level “Modern Language” Maturity

**Status:** Draft goal document (for rolling execution)  
**Audience:** Oren maintainers / agent instances improving Oren over time  
**Repo context:** This MANTIS workspace vendors Oren as `third_party/oren-lang/` (formerly `third_party/compiler-mini/`)  
**Pinned Oren revision (in this workspace):** `934c759e5e85a52a71ca45672fb373c40a21c0aa`

## 0) Problem Statement

MANTIS (`mantis.md`) is a **GPU‑less, CPU‑first generic intelligent system** built around:

- sparse events (EBUS),
- a thin world model (WM),
- a memory subsystem (MEM) with retrieval-first design,
- a skill library (SKL) routed by an executive (EXEC),
- a hard safety envelope (SAFE),
- a slow auto-optimizer (AUTO),
- and determinism / traceability / replay (OBS).

If MANTIS is to be implemented as **Oren’s first‑party stdlib** (or as a “stdlib-class” library),
then Oren must provide **stable, cross-backend primitives** for:

- determinism + replay,
- capability governance,
- concurrency + timeouts + cancellation,
- efficient numeric compute (typed buffers),
- canonical serialization and observability surfaces,
- and a coherent packaging/distribution story for “skills” as plugins.

This document defines the **language/runtime/VM/tooling features** Oren should mature toward so that:

1) MANTIS can be implemented cleanly as an Oren library, and
2) that library can run **consistently** across Oren’s 3 backends (`c`, `native`, `bytecode/AVM`).

## 0.1) Key Requirement (Direction Lock)

**MANTIS must be implemented as Oren native-backend stdlib first**, and must also be runnable **fully inside AVM** for constrained sandbox applications (e.g., iOS).

This implies **three execution modes** that must remain supported:

1) **Native-performance mode (primary)**  
   `std:mantis/*` runs under `--backend native` with production-level reliability and performance on CPU workstations/servers.

2) **AVM sandbox mode (constrained platforms)**  
   The same `std:mantis/*` codebase can be compiled under `--backend bytecode` and executed by AVM, so the full MANTIS system can run inside a capability-governed sandbox (target examples: iOS / app-store constraints / edge environments).

3) **Native host + AVM sandboxing (recommended for “safe plugins”)**  
   Oren native deployments can embed AVM as a **native stdlib component** (conceptually `std:avm/*`) and run untrusted parts (skills/tools/policies) inside AVM capsules, optionally using multiverse (nested universes) for “sandbox-in-sandbox” workflows and deterministic simulation.

This direction drives several design constraints in Sections 3, 5, and 6 (portability matrix + AVM performance gates).

### 0.1.1) Hard Requirement: Loop A Must Run Inside AVM

MANTIS defines a fast “Reflex & safety loop” (Loop A) intended to run at **50–1000 Hz** with bounded response time (native-performance target).

**Requirement:** MANTIS Loop A must be runnable inside AVM as a capsule/library (for sandbox mode and for AVM-in-native sandboxing):

- AVM must support a **low-latency** and **predictable** execution mode suitable for Loop A (within the configured budgets and deterministic mode constraints).
- Loop A code must be portable (no host syscalls), and must use only the “AVM-safe” subset of the stdlib/platform layer.
- Safety behavior must be deterministic and auditable (traceable decisions, reproducible replay) in this mode.

**Performance clarification:**
- Native-performance mode targets the full 50–1000 Hz envelope on workstation CPUs.
- AVM sandbox mode targets **functional correctness + bounded latency** for a defined Loop A workload class on constrained devices; the exact latency target must be explicitly specified and regression-gated (see Section 6).

Implication: MANTIS is not only a “stdlib target”; it is also a **determinism and latency forcing function** for AVM’s scheduler, budgets, and interpreter loop.

## 0.2) MANTIS is the “Modern Oren” Integration Testbed (North Star)

Oren is currently in **rolling** status: fast evolution is allowed, and maturity is achieved by:

- a clear target architecture,
- stable contracts where needed,
- and regression-backed behavior (tests as living spec).

MANTIS is an intentionally demanding, CPU-first system design (`mantis.md`) that exercises many “modern language” requirements at once:

- **Lightweight concurrency**: many small tasks, cancellation, timeouts.
- **Async IO**: FS/NET/PROC readiness integrated with channels/select (not “one OS thread per socket”).
- **Determinism and replay**: reproducible debugging, auditability, and trustable regression tests.
- **Storage**: append-only logs + KV indexes + snapshots + compaction.
- **Compression**: log segments and snapshot blobs with deterministic outputs.
- **Vector compute + retrieval**: typed buffers, deterministic kernels, ANN indexing, and persistence.

The role of MANTIS in Oren’s evolution is therefore:

> MANTIS is the integration suite that continuously forces Oren toward the correct path for a modern production language and runtime.

## 1) Definitions (Terms Used in This Doc)

- **Backend parity:** The same source program (and the MANTIS stdlib) behaves the same under `--backend c`, `--backend native`, and `--backend bytecode` (AVM), except where explicitly documented.
- **Deterministic mode:** Given fixed inputs + fixed policy + fixed replay log (if any), execution is repeatable, and outputs/traces are stable enough for regression tests and reproducible debugging.
- **Capability domain:** A labeled group of effectful operations (FS/NET/PROC/TIME/RNG/ENV/…), policy-controlled and denyable.
- **Skill capsule:** A packaged unit of code executed under explicit budgets and capabilities (preferably runnable in AVM, optionally also native).

## 2) Non‑Goals (Explicitly Out of Scope for This Goal Doc)

- “Replace LLMs” or “train large dense models” (MANTIS is explicitly not that).
- GPU/CUDA features.
- Perfect backward compatibility during Oren’s rolling phase (this doc is a *directional* goal, but it requires stable milestones for consumers).

## 3) Target Operating Model (Recommended for MANTIS)

To be “stdlib‑suitable”, Oren should enable a **native-first + AVM-runnable** architecture, where AVM is also usable as a native-hosted sandbox:

- **Trusted MANTIS kernel:** runs as `native` (or `c`) for workstation performance and OS integration.
- **Untrusted / pluggable skills:** run as AVM **capsules** (`.obc`) with:
  - deny‑by‑default capabilities,
  - explicit budgets,
  - deterministic replay/simulation (VirtualFS/VirtualNET/VirtualPROC),
  - policy scanning before execution.

This model is consistent with Oren’s stated direction (agent capsules + AVM governance), and it aligns with MANTIS’s need for:

- safe plugin execution,
- deterministic replay,
- bounded compute/IO cost.

### 3.1) Portability contract: “native std first, portable to AVM”

To keep `std:mantis/*` runnable in AVM while still being high-performance natively, treat MANTIS as a **platform-abstracted stdlib**:

- `std:mantis/core/*` is “pure logic”:
  - event bus (in-memory),
  - world model updates,
  - skill routing/scoring,
  - safety checks,
  - optimizer logic (bandits/BO) in deterministic math.
- All effectful operations are behind small interfaces in `std:mantis/platform/*`:
  - clock/time, RNG seeding,
  - filesystem/log storage,
  - networking (if any),
  - process/subprocess (if any),
  - tracing sinks (file vs bytes).

**Strict portability rule:** `std:mantis/core/*` must not call OS-specific syscalls or “raw native” helpers directly; it only talks to platform interfaces.

Backends:

- **Native backend:** platform impls can use host FS/NET/PROC where policy allows (and can still be capsule-governed).
- **AVM:** platform impls must work under capability restrictions using AVM’s FS/NET/PROC virtualization (VirtualFS/VirtualNET/VirtualPROC) and must remain deterministic/replayable.

Native-host sandboxing (AVM as stdlib in native):

- Native deployments should be able to run untrusted code as `.obc` inside AVM even when the outer process is native.
- Multiverse (nested universes) should be usable in native as a sandboxing primitive:
  - run child universes with restricted caps and budgets,
  - snapshot/resume for “what-if” evaluation,
  - deterministic validation of candidate actions/skills.

Concurrency note (important):

- Native `spawn` semantics are OS-dependent in rolling mode (e.g., POSIX fork+pipe vs Windows threads), and AVM uses VM tasks.
- Therefore, `std:mantis/*` must prefer message-passing concurrency patterns (channels/select) and avoid relying on shared-memory thread semantics.

Loop A note (hard requirement):

- `std:mantis/core/*` must be implementable in an AVM-compatible subset so Loop A can run inside AVM.
- Any real-world IO or heavy work must be moved out of Loop A into slower loops (or into platform backends) so Loop A remains low-latency under AVM.

### 3.2) “Modern language” direction anchors (what MANTIS should force Oren to get right)

To keep Oren evolving toward modern production language maturity, MANTIS should remain a forcing function for:

- **Lightweight tasks**: language-level concurrency should not be defined by OS processes; it should scale to many small tasks.
- **Async IO**: IO readiness integrates with the scheduler and channels/select; avoid “one thread per socket/process” designs.
- **Structured concurrency**: cancellation and deadlines propagate; no orphan background work.
- **Composable stdlib**: the stdlib provides primitives (storage/compression/trace) so applications don’t reinvent them.
- **Determinism as a feature**: replay and trace hashes are first-class and budgeted.
- **Portability + governance**: the same logic runs in AVM capsules under strict capability policies.

## 4) Priority Levels

- **P0:** blocks implementing MANTIS as stdlib in a robust way.
- **P1:** high-leverage improvements that make MANTIS practical on CPU and easier to operate.
- **P2:** “finish” items for ecosystem maturity, distribution, and performance scaling.

## 5) Feature Goals (Draft)

### P0 — Must‑Have Substrate (Blockers)

#### P0.1 Native deterministic mode (record/replay + virtual TIME/RNG + deterministic scheduling option)

**Why (MANTIS mapping):**
- MANTIS requires deterministic replay and traceability (`mantis.md` “Observability & reproducibility”).
- If determinism exists only in AVM, MANTIS cannot provide a single operational story across deployments.

**Goal:**
- Add a first‑class “deterministic native runtime mode” where:
  - effectful operations are routed through a capability layer that can record/replay,
  - TIME and RNG can be virtualized (or recorded/replayed),
  - concurrency scheduling can be made deterministic (at least as an opt‑in mode).

**Acceptance criteria (minimum):**
- A MANTIS kernel program run in native deterministic mode can:
  - emit a replay log,
  - rerun with that replay log without touching the real host,
  - produce identical outputs/traces across reruns on the same host.

**Portability acceptance criteria (native-first):**
- The determinism/replay contract must be implementable in both:
  - native platform layer (host effects recorded/replayed), and
  - AVM platform layer (Virtual* backends + record/replay log).

#### P0.6 Storage substrate for MANTIS (embedded KV + append-only log + snapshots)

**Why (MANTIS mapping):**
- MANTIS’s episodic memory is an append-only log, and the spec anticipates large write volume (GB/day scale) and a retrieval index. A production MANTIS needs persistence, compaction, and snapshot-friendly layouts, not ad-hoc files.

**Goal:**
Provide a small, production-grade storage substrate that MANTIS can build on as stdlib modules:

- **Embedded KV store** (metadata and indexes)
  - `get/put/del`
  - batch writes (group commit)
  - prefix/range scans with **defined deterministic order** (bytewise lexicographic keys)
  - snapshot read views (consistent reads for deterministic replay)
  - background or explicit compaction with “no semantic change” guarantees
- **Append-only log segments** (episodic event storage)
  - chunked/segmented on disk
  - checksums and corruption detection
  - stable record encoding (canonical bytes)
  - read APIs that support scan-by-time and scan-by-offset

**Backend alignment requirement:**
- **Native/C**: host-backed filesystem storage (subject to capability policy).
- **AVM**: at minimum, a “VirtualKV/VirtualLog” backend (or VirtualFS-backed implementation) so tests can run deterministically without host FS access.

**Acceptance criteria (minimum):**
- Crash safety: after a process crash during writes, the KV/log can be reopened without silent corruption; partial writes are detected and handled deterministically.
- Determinism: for a fixed dataset, `scan_prefix` (or equivalent) returns keys in a stable defined order across reruns.
- Snapshot correctness: a snapshot read view remains consistent while writes proceed (or while compaction runs).
- Replay usability: storage state can be snapshotted and referenced by content hashes for deterministic replay tests.

**Portability acceptance criteria (AVM):**
- The same storage API used by `std:mantis/core/*` must run under AVM with:
  - deny-by-default FS policies (unless explicitly allowed),
  - VirtualFS-enabled tests that do not touch the host filesystem,
  - deterministic iteration/scans (including compaction behavior if implemented).

#### P0.7 AVM as a native stdlib component (embedding + sandbox parity)

**Why (MANTIS mapping):**
- AVM is the constrained-sandbox execution target (e.g., iOS).
- Native deployments also want sandboxing for untrusted plugins/skills/tools without relying on OS process isolation.
- Therefore AVM must be embeddable as a first-class **native stdlib** component, not only a standalone CLI tool.

**Goal:**
- Provide a stable embedding API for AVM in native deployments (conceptually `std:avm/*`):
  - load/verify `.obc`,
  - apply capability policy and budgets,
  - run/step/snapshot/resume,
  - extract trace hashes and policy usage,
  - run nested universes (multiverse) as a governance/sandbox primitive.

**Acceptance criteria (minimum):**
- Native MANTIS can run a skill/tool in an AVM capsule and:
  - deny-by-default caps, allowlist specific domains/ops,
  - enforce budgets (gas/time/mem/io/log),
  - obtain a deterministic result hash + trace hash for audit/replay.

#### P0.2 Standardized structured errors across language + stdlib + runtime (all backends)

**Why (MANTIS mapping):**
- MANTIS modules need explicit health/error reporting, and SAFE must be able to veto/rollback deterministically.

**Goal:**
- Define one canonical error model used consistently:
  - representation is stable across backends,
  - interop with diagnostics (`OREN_DIAG`) is defined (human + machine).

**Acceptance criteria (minimum):**
- Same error value shape across native/C/AVM for:
  - bounds errors,
  - capability violations,
  - budget/timeouts,
  - user-level “fail/assert” style failures.

#### P0.3 Concurrency primitives converge across backends (tasks/channels/select + timeouts + cancellation)

**Why (MANTIS mapping):**
- MANTIS is explicitly multi-loop and will often require concurrency (parallel skill evaluation, background optimization, IO).

**Goal:**
- Provide a coherent concurrency API:
  - `spawn`, `join`, `join_timeout`
  - channels and `select`
  - cancellation tokens + deadline propagation
  - deterministic scheduling option (ties into P0.1)

**Modern direction requirement (lightweight tasks):**
- On native targets, `spawn` must evolve into a **lightweight task** primitive (green-thread / coroutine style):
  - `spawn` must not require `fork` to be the semantics-defining mechanism.
  - the unit of concurrency is a runtime-managed task with a deterministic scheduling option.
- AVM’s task model should remain the portability baseline, and native should converge toward it in semantics and APIs.

**Acceptance criteria (minimum):**
- A common suite of concurrency tests passes identically under:
  - `--backend native` (macOS + Linux),
  - `--backend c`,
  - `--backend bytecode` (AVM).

**Portability emphasis for MANTIS:**
- Provide a stable, deterministic “message-passing” subset (`channels` + `select` + timeouts + cancellation) that MANTIS can rely on across backends without assuming shared-memory threads.

#### P0.4 Capability domains unified as a library surface (not VM-only)

**Why (MANTIS mapping):**
- MANTIS skills are plugins; running them safely requires least-privilege policies and auditability.

**Goal:**
- Make “capability domains” a stable, shared abstraction:
  - a registry of domains/ops,
  - a policy format,
  - enforcement points in AVM *and* native runtime.

**Acceptance criteria (minimum):**
- A skill capsule can be scanned before execution to produce:
  - used domains/ops,
  - declared/required budgets,
  - and be rejected/allowed by policy consistently across backends.

#### P0.5 Canonical serialization for core values + `bytes` + typed buffers

**Why (MANTIS mapping):**
- MANTIS requires trace logs, episodes, snapshots, reproducible replay, and optional distributed workflows.

**Goal:**
- Define and implement stable encodings for:
  - core dynamic values (`Nil/Int/Bool/Float/String/List/Map`)
  - `Bytes`
  - typed buffers (i32/i64/f32/f64/u8)

**Acceptance criteria (minimum):**
- Same logical structure serializes to identical bytes across:
  - native (macOS/Linux),
  - AVM,
  - and `c` backend,
  when in deterministic mode and given the same inputs.

---

### P1 — High Leverage (Makes MANTIS Practical and Ergonomic)

#### P1.1 Stdlib Event Bus primitives (`std:event`, queues, timers)

**Why (MANTIS mapping):**
- MANTIS is eventized by design (`mantis.md` “Eventization over frames”).

**Goal:**
- Provide stdlib building blocks:
  - efficient event queue / ring buffer,
  - timer scheduling helpers (tick loops),
  - deterministic ordering guarantees (tie-breakers).

**Acceptance criteria (minimum):**
- A reference EBUS implementation can hit MANTIS-like loop frequencies on CPU without pathological allocations.

#### P1.2 Stdlib Memory subsystem primitives (append-only log, retention, snapshot-friendly storage)

**Why (MANTIS mapping):**
- MANTIS’s “MEM as amplifier” requires careful log retention and stable replay.

**Goal:**
- Provide reusable components:
  - append-only log segments,
  - compaction/retention policies,
  - snapshot and restore hooks.

#### P1.3 Deterministic CPU retrieval index (ANN) using typed buffers

**Why (MANTIS mapping):**
- MANTIS explicitly calls for ANN retrieval (HNSW/IVF).

**Goal:**
- A deterministic or determinism-friendly ANN library:
  - stable search order tie-breakers,
  - pure compute kernels over typed buffers,
  - batch query API.

**Acceptance criteria (minimum):**
- ANN retrieval results are stable across reruns in deterministic mode.

#### P1.4 Observability library: trace events + spans + JSONL/bytes sinks

**Why (MANTIS mapping):**
- MANTIS requires “decision traces (JSONL)” and replayability.

**Goal:**
- `std:trace` module with:
  - structured spans,
  - stable schemas,
  - deterministic ordering rules,
  - output sinks (JSONL + bytes blob for capsule transport).

#### P1.5 Packaging/distribution story for stdlib‑class libraries and skill capsules

**Why (MANTIS mapping):**
- MANTIS “skills” must be distributable and policy-scannable.

**Goal:**
- A coherent import + distribution model for:
  - `std:` modules,
  - bundled precompiled `.obc` libraries (where applicable),
  - reproducible build inputs (lockfiles/hashes),
  - toolchain pinning for rolling ABI periods.

#### P1.6 Vector store + retrieval index persistence (CPU-first; deterministic)

**Why (MANTIS mapping):**
- MANTIS explicitly calls for retrieval-first memory and ANN indexing (HNSW/IVF). The index itself and the vector payloads must be persistable and reproducible.

**Goal:**
- A stdlib-layer “vector store” abstraction built on P0.6 storage:
  - `id -> vector` (typed buffer payload)
  - `id -> metadata` (timestamps, tags, provenance, reward signals)
  - index persistence for the chosen ANN structure (or a deterministic rebuild pipeline)
  - deterministic query behavior (tie-breakers, stable top-k ordering when scores equal)

**Acceptance criteria (minimum):**
- Given the same vectors + query + config, retrieval results are stable across reruns in deterministic mode.
- Index rebuild from persisted raw vectors produces identical retrieval results (or a declared stable equivalence contract) under deterministic settings.

#### P1.7 Async IO + scheduler integration (channels/select as the surface)

**Why (MANTIS mapping):**
- MANTIS is event-driven and often IO-driven (operators, tools, telemetry, environment interfaces). A modern runtime must not require N OS threads or N OS processes for N concurrent waits.

**Goal:**
- Provide an async IO story that works for both:
  - native backend deployments, and
  - AVM portability constraints.

Requirements:

- **Native:** a runtime scheduler + netpoller abstraction where:
  - IO readiness is exposed as events/channels,
  - `select` composes over both “pure channels” and IO readiness events,
  - timeouts and cancellation are enforced by the scheduler (not ad-hoc busy loops).
- **AVM:** maintain determinism-friendly virtualization:
  - VirtualFS/VirtualNET/VirtualPROC fixtures remain first-class for deterministic tests,
  - “host NET/PROC/FS” (if enabled) must be record/replayable and capability-governed.

**Acceptance criteria (minimum):**
- A MANTIS module can wait on multiple IO sources without spawning one OS thread/process per source.
- Cancellation + timeouts are consistent under native deterministic mode and AVM deterministic mode.

#### P1.8 Compression stdlib (deterministic; portable to AVM)

**Why (MANTIS mapping):**
- Episodic logs, snapshots, and vector payloads benefit from compression (disk footprint + IO bandwidth).

**Goal:**
- Provide `std:compress/*` modules suitable for:
  - compressing log segments and snapshot blobs,
  - deterministic outputs (given same input + settings),
  - portability to AVM (no reliance on host libc compression behavior).

Minimum capabilities:
- “bytes in → bytes out” APIs over `bytes` / `u8_buf`.
- Streaming interfaces (incremental compress/decompress) to avoid unbounded memory.
- A determinism contract: byte-identical outputs for fixed parameters in deterministic mode.

**Acceptance criteria (minimum):**
- MANTIS can store compressed episodic segments and restore them under AVM using VirtualFS (no host filesystem dependency).

---

### P2 — Ecosystem Maturity / Long-Term Scaling

#### P2.1 Compiler‑in‑AVM (“closed loop” build inside a capsule)

**Why (MANTIS mapping):**
- Enables trusted execution of skill source inside a sandbox; strengthens governance and reproducibility.

**Goal:**
- Make `.oren -> .obc` compilation runnable inside AVM under budgets/caps.

#### P2.2 Performance/operability primitives aligned with MANTIS latency targets

**Why (MANTIS mapping):**
- MANTIS sets explicit CPU latency targets for its loops.

**Goal:**
- Provide:
  - stable profiling counters/timers,
  - bounded allocation strategies for hot loops,
  - optional CPU affinity/pinning primitives (once native scheduler exists).

#### P2.3 “Skill capsule UX” hardening: signing, policy-by-default, reproducible artifact metadata

**Why (MANTIS mapping):**
- Skills are supply-chain inputs; policy scanning and trust roots matter if MANTIS is meant to be extensible.

**Goal:**
- Signed artifacts, stable policy metadata extraction, and reproducible build artifact manifests.

---

## 5.1) Additional “Modern Language” Feature Requirements (Driven by MANTIS)

The sections above focus on cross-backend substrate and stdlib primitives. To make Oren a **production-level modern language** (with MANTIS as the forcing testbed), Oren should also evolve in these language/runtime/tooling areas.

These requirements are framed as “what MANTIS needs” rather than general taste.

### P0-LANG — Language/runtime requirements (blockers for stdlib-scale systems)

#### P0-LANG.1 First-class async (`async`/`await`) with cancellation + deadlines

**Why (MANTIS mapping):**
- MANTIS is event-driven and must integrate IO and background work without blocking the world.

**Goal:**
- Provide a canonical async model:
  - `async` functions and `await` points,
  - cancellation tokens and deadlines are part of task context,
  - timeouts are uniform across IO and pure waits.

**Acceptance criteria (minimum):**
- `std:mantis/platform/*` can expose async IO as `await`-able operations, and `std:mantis/core/*` can compose them without backend-specific logic.

#### P0-LANG.2 Structured concurrency (task groups / nurseries)

**Why (MANTIS mapping):**
- MANTIS runs multiple loops and background services; production systems must not leak tasks or create nondeterministic shutdown behavior.

**Goal:**
- Provide a structured concurrency primitive (language or stdlib) where:
  - spawned tasks are owned by a parent scope,
  - cancellation and deadlines propagate,
  - scope exit deterministically joins/cancels children.

**Acceptance criteria (minimum):**
- MANTIS can express “run N workers until first success, cancel the rest” deterministically (native and AVM).

#### P0-LANG.3 Explicit `unsafe` boundary for raw memory ops

**Why (MANTIS mapping):**
- Implementing efficient queues/storage codecs sometimes requires low-level operations, but stdlib-grade code must keep hazards explicit.

**Goal:**
- Require an `unsafe` marker (block or function annotation) for raw pointer/memory intrinsics.
- Provide safe stdlib wrappers for common byte/codec work.

**Acceptance criteria (minimum):**
- `std:mantis/core/*` does not require `unsafe`.
- Only low-level storage/codec kernels require `unsafe` and remain encapsulated.

#### P0-LANG.4 One canonical error model with ergonomic sugar

**Why (MANTIS mapping):**
- MANTIS modules must return structured failures and SAFE must decide deterministically, not via panics.

**Goal:**
- Standardize on one model (e.g., `Result<T, E>` or typed errors) and provide ergonomic sugar (`?` / `try`-style).

**Acceptance criteria (minimum):**
- Stdlib modules used by MANTIS (storage, compress, platform IO, trace) can be written without panic-as-control-flow.

#### P0-LANG.5 Deterministic container iteration semantics (language-level contract)

**Why (MANTIS mapping):**
- Trace hashes, storage compaction, ANN build/rebuild, and reproducible replay all depend on stable ordering.

**Goal:**
- Define deterministic iteration semantics for core containers (especially maps) in deterministic mode (and ideally always).

**Acceptance criteria (minimum):**
- MANTIS traces and snapshots do not change due to container iteration nondeterminism.

#### P0-LANG.6 Deterministic execution profile for AVM Loop A

**Why (MANTIS mapping):**
- Loop A must run inside AVM (Section 0.1.1). AVM needs a well-defined low-latency profile.

**Goal:**
- Define an AVM execution profile suitable for Loop A:
  - predictable scheduling behavior,
  - bounded per-step overhead,
  - minimal allocation requirements in the hot path,
  - budgets that do not introduce nondeterministic stalls.

**Acceptance criteria (minimum):**
- A reference Loop A workload can run inside AVM with bounded worst-case latency under a documented configuration.

### P1-LANG — Tooling and ecosystem requirements (high leverage)

#### P1-LANG.1 First-class tests (`test` blocks) + machine-readable runner output

**Why (MANTIS mapping):**
- MANTIS is a testbed; Oren needs regression-backed evolution. Tests must run under native and AVM in a comparable way.

**Goal:**
- Provide first-class test syntax (or a standardized pattern) and a runner that emits machine-readable output (JSON).

**Acceptance criteria (minimum):**
- The MANTIS suite can run:
  - natively (fast path),
  - in AVM capsule mode (deterministic fixtures),
  and produce comparable structured results.

#### P1-LANG.2 Stable bytecode versioning milestone for `.obc`

**Why (MANTIS mapping):**
- If Loop A must run in AVM, AVM becomes production-critical; rolling ABI must graduate to a versioned contract.

**Goal:**
- Introduce `.obc` versioning and a compatibility policy once a “stability milestone” is declared.

**Acceptance criteria (minimum):**
- `std:mantis/*` compiled artifacts can be pinned to a specific `.obc` version and validated by policy scanning tooling.

#### P1-LANG.3 Ergonomic generics/traits for real stdlib data structures

**Why (MANTIS mapping):**
- MANTIS needs generic queues, caches, indexes, and backend interfaces.

**Goal:**
- Improve generics/traits ergonomics and diagnostics so stdlib-scale generic code is maintainable.

### P2-LANG — Optional but valuable for long-term “most modern” goals

#### P2-LANG.1 Capability/effect annotations reflected in tooling

**Why (MANTIS mapping):**
- Governance is central: skills and platform backends must be policy-controlled.

**Goal:**
- Ensure capability requirements can be extracted and scanned from artifacts (native + `.obc`) in a stable way.

---

## 5.2) Additional Stdlib Modules Needed for Modern MANTIS-Class Systems

These modules are not “nice-to-have”; without them, large systems will reinvent fragile wheels.

### P0-STDLIB — Core building blocks

- `std:collections/deque` (ring buffer) for event bus queues
- `std:collections/heap` (priority queue) for scheduling and timers
- `std:collections/lru` (or equivalent bounded cache)
- `std:metrics` (counters/gauges/histograms) with deterministic export modes
- `std:codec/*` (binary codecs and stable schemas)
  - varint/leb128 (if chosen), fixed-endian helpers, stable record framing
- `std:platform/*` (portable OS abstraction)
  - `fs`, `net`, `proc`, `env`, `time`, `rng`
  - native and AVM implementations with deterministic fixtures

### P1-STDLIB — MANTIS enablement libraries

- `std:stats` (rolling mean/variance, quantiles, distributions) for calibration/bandits
- `std:opt` (bandit algorithms, online regression helpers, BO scaffolding)
- `std:cas` (content-addressed helpers): chunking, manifests, stable hashing conventions

## 6) Validation Strategy (How to Prove Progress)

To keep rolling changes grounded, each feature should land with:

1) **A small integration test** (one per feature) that:
   - runs under `--backend native`, `--backend c`, and `--backend bytecode` where applicable,
   - has deterministic outputs.
2) **A “capsule” test** that validates:
   - policy scan output,
   - deny-by-default behavior,
   - budgets (gas/time/mem/io/log).
3) **A replay test** that demonstrates:
  - run -> record,
  - rerun -> replay,
  - identical outputs/hashes.

4) **A storage invariants suite** that demonstrates:
  - crash recovery on power-loss-like truncation cases (simulated),
  - deterministic scan order invariants,
  - snapshot read consistency while writes continue,
  - compaction does not change logical contents.

5) **A backend portability matrix for `std:mantis/*`** that demonstrates:
  - native (macOS arm64) runs the MANTIS core suite (fast path),
  - native (Linux arm64/x86_64 where available) runs the same suite,
  - AVM runs the **full MANTIS suite** under `--capsule` + VirtualFS/VirtualPROC/VirtualNET fixtures (no host effects),
  - native-hosted AVM runs the same capsule suite (AVM as embedded stdlib), including multiverse sandboxing scenarios,
  - outputs/hashes match expected deterministic baselines when deterministic mode is enabled.

6) **A “modern language” stress suite** derived from MANTIS that demonstrates:
  - many small tasks (scheduler scalability) without OS process explosion,
  - async IO correctness under cancellation and timeouts,
  - storage + compression soak tests (bounded memory, compaction correctness),
  - ANN retrieval correctness + persistence invariants.

7) **An AVM Loop A performance gate** (because Loop A must run inside AVM):
  - a reference Loop A “reflex checks” workload runs under AVM in a bounded time budget,
  - worst-case latency stays within a documented target envelope for the chosen workload class (separate targets for workstation vs constrained devices),
  - performance regressions are caught by the rolling test harness.

## 7) Immediate Next Steps (For the Next Agent Instance)

- Decide the “MANTIS as stdlib” execution split: native kernel vs AVM skills (hybrid recommended).
- Choose and standardize the error model (P0.2) and capability model (P0.4) first; they constrain every higher layer.
- Implement the determinism/replay contract (P0.1 + P0.5) early; it becomes the regression backbone.
- Choose the initial storage design (P0.6):
  - simplest viable (Bitcask-style log + in-memory index + compaction), or
  - scalable (LSM tree), while keeping deterministic iteration/scan semantics explicit.

- Establish the AVM Loop A target configuration:
  - deterministic mode knobs (time/rng/scheduler),
  - budgets suitable for 50–1000 Hz reflex checks,
  - profiling/benchmark harness to enforce regressions.

- Start the “modern language” track:
  - async/await + structured concurrency plan (P0-LANG.1 / P0-LANG.2),
  - `.obc` stability milestone plan (P1-LANG.2),
  - stdlib module roadmap for collections/codec/metrics (Section 5.2).
