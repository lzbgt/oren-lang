# Tech Spec: **MANTIS** — A GPU-less Generic Intelligent System for Commodity Workstations

*(Modular, event-driven, self-optimizing autonomy stack that runs on normal x86 PCs without CUDA/TPU.)*

## 0. Goals and non-goals

### Goals

* **Generic**: supports many domains (robotics, ops automation, simulation agents, interactive assistants, anomaly response, scheduling, etc.) via plugins.
* **No GPU dependency**: runs on typical workstations (x86_64, 4–32 cores, 16–128 GB RAM).
* **Adaptive**: online self-optimization under explicit constraints (safety, latency, power, policy).
* **Compute efficient**: exploits **sparsity, events, memory, and modular structure**; avoids large dense training.
* **Predictable & debuggable**: reproducible decisions, introspection, rollback.

### Non-goals

* Not trying to be a full LLM replacement.
* Not doing giant end-to-end differentiable training.
* Not guaranteeing “human-level generality”; target is **general competent agency** across structured tasks.

---

## 1. Design principles (the “why it works on CPU”)

1. **Eventization over frames**: compute only on change/novelty/violations.
2. **Small brains + strong structure**: reflex layer + skills + executive router + memory.
3. **Learning = selection + calibration**, not massive gradient descent.
4. **Memory as first-class compute**: retrieval and reuse beats re-deriving.
5. **Two-speed loops**: hard real-time decisions are stable; optimization runs slower and safely.
6. **Confidence is currency**: every module reports uncertainty/health/cost; routing uses it.

---

## 2. System overview

### High-level pipeline

**Inputs → Event Bus → World State + Memory → Executive Router → Skills → Action → Monitors → Optimizer**

### Core components

1. **Event Bus (EBUS)**: routes sparse events with timestamps and provenance.
2. **World Model (WM)**: minimal belief/state representation + constraints.
3. **Memory Subsystem (MEM)**: episodic + semantic + procedural memory (retrieval first).
4. **Skill Library (SKL)**: parameterized behaviors/controllers/strategies.
5. **Executive Router (EXEC)**: chooses skills + parameters given context/confidence/cost.
6. **Safety Envelope (SAFE)**: hard constraints + veto + rollback triggers.
7. **Auto-Optimizer (AUTO)**: online tuning & selection using CPU-friendly algorithms.
8. **Observability (OBS)**: traceable decisions, reproducible replays, metrics.

---

## 3. Key innovation: **Tri-Loop Autonomy**

MANTIS is defined by three coupled loops, each CPU-friendly:

### Loop A — Reflex & safety loop (fast, deterministic)

* Frequency: 50–1000 Hz depending on domain.
* No learning; only bounded controllers and constraints.
* Inputs: immediate hazards, control state, rate limits.
* Output: safe action or veto.

**Guarantee**: bounded response time and stability.

### Loop B — Executive decision loop (medium)

* Frequency: 1–50 Hz.
* Selects skill, sets parameters, manages modes.
* Uses contextual confidence + cost + memory retrieval.
* Implements **subsumption** (higher layers can’t break safety).

**Guarantee**: decisions are explainable and replayable.

### Loop C — Auto-optimization loop (slow)

* Frequency: 0.1–1 Hz (or on milestone events).
* Runs *shadow evaluation* and safe online tuning.
* Algorithms: contextual bandits + Bayesian optimization + online regression.

**Guarantee**: improvement without destabilizing Loop A/B.

---

## 4. “Generic intelligence” mechanism (no GPU)

### 4.1 Eventization (EBUS)

Raw streams are converted into sparse **events**:

* novelty spikes, threshold crossings, state changes
* prediction errors (residuals)
* constraint violations and near-violations
* external triggers (user command, schedule tick)

**Event schema (canonical)**

```json
{
  "t": 1735689600.123,
  "type": "NOVELTY|OBS|CONSTRAINT|GOAL|REWARD|HEARTBEAT",
  "source": "module_id",
  "payload": { "key": "value" },
  "confidence": 0.0,
  "cost_hint": { "cpu_us": 50, "mem_bytes": 128 }
}
```

### 4.2 World Model (WM): “thin” by design

* Minimal state sufficient for task + safety.
* Supports:

  * **belief** (mean + covariance or confidence scalar)
  * **constraints** (invariant checks, safety envelopes)
  * **time** (causality, TTLs)
* Avoids heavy learned latent spaces by default.

### 4.3 Memory Subsystem (MEM): intelligence amplifier

Three memories with explicit read/write policies:

1. **Episodic Memory** (what happened):

   * Append-only event log + compressed summaries (“episodes”).
2. **Semantic Memory** (what is generally true):

   * Facts, rules, environment models, operator policies.
3. **Procedural Memory** (how to act):

   * Skill parameter sets, “recipes,” policies that worked in contexts.

**Retrieval**: approximate nearest neighbor (HNSW/IVF) over CPU embeddings (small).
**Write control**: only commit when value is proven (rewarded, stable, safe).

### 4.4 Skill Library (SKL): parametric competence

A “skill” is a bounded actor with:

* preconditions
* action interface
* tunable parameters (bounded)
* predicted cost and expected outcome distribution
* health signals and stop conditions

Skill examples (generic):

* stabilize / track / explore / search / allocate resources / negotiate schedule / remediate anomaly

---

## 5. Executive Router (EXEC): selection, not brute force

EXEC chooses **(skill, parameters, horizon)** via:

* current context features (from WM + events)
* retrieved similar episodes (MEM)
* skill confidence/cost predictions
* safety feasibility (SAFE)

### Decision rule (generic)

Maximize:
[
\text{Score} = \mathbb{E}[R] - \lambda_C \cdot \text{CPUCost} - \lambda_L \cdot \text{LatencyRisk} - \lambda_U \cdot \text{Uncertainty} - \lambda_V \cdot \text{ViolationRisk}
]
subject to hard constraints from SAFE.

No GPU needed: the candidate set is small (dozens of skills), scoring is cheap.

---

## 6. Auto-Optimizer (AUTO): safe online improvement (CPU-first)

### 6.1 Contextual Bandits (primary engine)

Use Thompson Sampling / UCB to select among:

* skill variants
* parameter “bins”
* gating thresholds
* memory retrieval policies
* planner budget (how much search)

**Why**: extremely light compute, online, handles non-stationary environments with decay.

### 6.2 Bayesian Optimization (secondary, low cadence)

For continuous parameters:

* noise scales, time constants, thresholds, horizons
* only when stable and enough samples exist

**Constraint**: BO runs in shadow mode first; commit only if improvement is statistically credible.

### 6.3 Online Regression (calibration)

Use RLS / Kalman-style parameter tracking to:

* predict residuals
* estimate confidence/uncertainty
* learn reliability of modules under contexts

### 6.4 Shadow evaluation and rollback (innovation: “safe A/B in real time”)

* New configuration runs in parallel producing *proposed* decisions.
* SAFE compares predicted risk + constraint margins.
* Only promotes to live if:

  * no constraint violations in shadow window
  * reward improvement exceeds threshold
  * stability metrics remain bounded

Rollback triggers:

* instability spike
* violation margin below threshold
* confidence collapse

---

## 7. Safety Envelope (SAFE): hard guarantees

SAFE enforces:

* invariants (never violate)
* action bounds and rate limits
* watch-dogs (timeouts, stuck detection)
* “dead-man” fallback skill (safe idle / retract / stop)

SAFE is **outside** learning. Learning can propose; SAFE disposes.

---

## 8. Observability & reproducibility (required for “generic”)

Every decision is traceable:

* event lineage → context vector → retrieved memories → candidate scoring → chosen action
* deterministic replay mode:

  * freeze RNG seeds
  * snapshot WM + MEM pointers
  * record module versions + params

Outputs:

* decision traces (JSONL)
* per-module health dashboards
* regression tests from captured episodes

---

## 9. Performance targets (workstation)

Baseline target on a typical workstation (e.g., 8–16 cores):

* Loop A: < 1 ms worst-case for reflex checks (domain dependent)
* Loop B: 1–10 ms decision latency for typical candidate sets (10–200 skills)
* Loop C: < 50–200 ms per optimization tick, amortized (0.1–1 Hz)

Memory:

* episodic log: 1–10 GB/day (configurable sampling/compression)
* retrieval index: 0.5–20 GB depending on embedding size and retention

---

## 10. Public interfaces (module API)

### 10.1 Module contract

Each module implements:

* `init(config)`
* `on_event(event) -> events[]`
* `tick(dt) -> events[]` (optional)
* `health() -> {metrics}`
* `params() -> {schema, values}`
* `set_params(values)` (bounded updates only)

### 10.2 Skill contract

* `preconditions(wm, mem) -> bool`
* `predict(wm, mem) -> {reward_dist, risk, cost}`
* `act(wm, mem) -> action`
* `terminate(wm, mem) -> bool`

---

## 11. What makes this “most advantage” vs GPU-centric stacks

1. **Latency and determinism**: CPU event loops beat GPU batch pipelines for real-time.
2. **Sample efficiency**: bandits + memory reuse + small calibration learn from little data.
3. **Robustness**: explicit uncertainty + constraints + rollback avoids catastrophic drift.
4. **Generality through composition**: new domains = new skills + adapters, not retraining a giant net.
5. **Hardware friendliness**: scales down (mini-PC) and up (servers) without hardware lock-in.
6. **Debuggability**: traceable decisions; no opaque monolith.

---

## 12. Implementation plan (phased, generic)

### Phase 1 — Kernel (2–4 weeks)

* Event Bus, WM skeleton, SAFE invariants
* Module/Skill API
* Observability + deterministic replay

### Phase 2 — Intelligence core (4–8 weeks)

* Memory subsystem (episodic + retrieval)
* Executive router (candidate scoring)
* Bandit tuner (contextual) + shadow evaluation

### Phase 3 — Generalization tooling (ongoing)

* Skill SDK + templates
* Benchmark suite (multiple domains)
* Auto-configuration + episode-to-test conversion

---

## 13. Acceptance criteria (generic)

* Runs end-to-end on CPU-only machine, no CUDA libs.
* Demonstrates **online improvement** on at least 3 distinct tasks/domains without retraining a large model.
* Zero constraint violations under defined test scenarios.
* Full decision trace + deterministic replay reproduces actions within tolerance.
* New domain can be added by implementing ≤ N skills and adapters (no core changes).

---

### Optional extensions (still CPU-friendly)

* Lightweight local language interface (small quantized LLM CPU inference) as *non-critical* advisor; actions still go through SAFE + EXEC.
* Distributed multi-agent mode: each agent runs local loops; shared memory via event replication.

