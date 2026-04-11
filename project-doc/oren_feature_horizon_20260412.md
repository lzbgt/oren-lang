# Oren Feature Horizon Research

**Date:** 2026-04-12

This note indexes the archived source pages under `project-doc/web/feature-horizon-20260412/`
and extracts engineering implications for Oren's differentiation work. The HTML snapshots are
stored locally so future agent work can inspect the original sources without relying only on
chat history or partial summaries.

## Source Archive

| Area | Local archive | Original URL recorded in archive |
| --- | --- | --- |
| CHERI | `project-doc/web/feature-horizon-20260412/cheri/cambridge-cheri.html` | `https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/` |
| CHERI Alliance | `project-doc/web/feature-horizon-20260412/cheri/cheri-alliance-who-we-are.html` | `https://cheri-alliance.org/who-we-are/` |
| CISA memory-safe languages | `project-doc/web/feature-horizon-20260412/cisa/cisa-memory-safe-languages.html` | `https://www.cisa.gov/resources-tools/resources/memory-safe-languages-reducing-vulnerabilities-modern-software-development` |
| CISA memory-safe roadmap alert | `project-doc/web/feature-horizon-20260412/cisa/cisa-memory-safe-roadmaps-alert.html` | `https://www.cisa.gov/news-events/alerts/2023/12/06/cisa-releases-joint-guide-software-manufacturers-case-memory-safe-roadmaps` |
| CISA product security bad practices | `project-doc/web/feature-horizon-20260412/cisa/cisa-product-security-bad-practices.html` | `https://www.cisa.gov/resources-tools/resources/product-security-bad-practices` |
| Model Context Protocol architecture | `project-doc/web/feature-horizon-20260412/mcp/mcp-2025-11-25-architecture.html` | `https://modelcontextprotocol.io/specification/2025-11-25/architecture` |
| Model Context Protocol changes | `project-doc/web/feature-horizon-20260412/mcp/mcp-2025-11-25-changelog.html` | `https://modelcontextprotocol.io/specification/2025-11-25/changelog` |
| NIST AI RMF generative AI profile | `project-doc/web/feature-horizon-20260412/nist/nist-ai-rmf-generative-ai-profile.html` | `https://www.nist.gov/publications/artificial-intelligence-risk-management-framework-generative-artificial-intelligence` |
| NIST PQC FIPS announcement | `project-doc/web/feature-horizon-20260412/nist/nist-pqc-fips-announcement.html` | `https://www.nist.gov/news-events/news/2024/08/announcing-approval-three-federal-information-processing-standards-fips` |
| NIST SSDF SP 800-218 | `project-doc/web/feature-horizon-20260412/nist/nist-ssdf-sp800-218.html` | `https://csrc.nist.gov/pubs/sp/800/218/final` |
| OpenTelemetry semantic conventions | `project-doc/web/feature-horizon-20260412/opentelemetry/opentelemetry-semantic-conventions.html` | `https://opentelemetry.io/docs/concepts/semantic-conventions/` |
| OpenTelemetry specification | `project-doc/web/feature-horizon-20260412/opentelemetry/opentelemetry-spec.html` | `https://opentelemetry.io/docs/specs/otel/` |
| Reproducible Builds formal definition | `project-doc/web/feature-horizon-20260412/reproducible-builds/formal-definition.html` | `https://reproducible-builds.org/docs/formal-definition/` |
| Rust Foundation strategic plan | `project-doc/web/feature-horizon-20260412/rust/rust-foundation-strategic-plan-2026-2028.html` | `https://rustfoundation.org/strategic-plan/` |
| Rust project goals | `project-doc/web/feature-horizon-20260412/rust/rust-project-goals-2025h2.html` | `https://rust-lang.github.io/rust-project-goals/2025h2/index.html` |
| SLSA v1.1 | `project-doc/web/feature-horizon-20260412/slsa/slsa-spec-v1.1.html` | `https://slsa.dev/spec/v1.1/` |
| NIST AI Agent Standards Initiative | `project-doc/web/feature-horizon-20260412/nist/nist-ai-agent-standards-initiative-2026.html` | `https://www.nist.gov/news-events/news/2026/02/announcing-ai-agent-standards-initiative-interoperable-and-secure` |
| WebAssembly 3.0 | `project-doc/web/feature-horizon-20260412/wasm/webassembly-wasm-3-completed.html` | `https://webassembly.org/news/2025-09-17-wasm-3.0/` |
| WebAssembly Component Model | `project-doc/web/feature-horizon-20260412/wasm/bytecodealliance-component-model-concepts.html` | `https://component-model.bytecodealliance.org/design/component-model-concepts.html` |
| WASI | `project-doc/web/feature-horizon-20260412/wasm/wasi-dev.html` | `https://wasi.dev/` |

MCP is archived here only as point-in-time protocol evidence. It is not the strategic target for
Oren. The Oren-owned surface should be deterministic execution evidence, module manifests, effect
ledgers, and replayable AVM/native behavior that can later adapt to many protocols.

## Implications For Oren

1. **Memory safety is table stakes, not enough differentiation.**
   CISA and Rust ecosystem material point toward a market where memory safety is expected for
   new systems work. Oren should not position itself as merely "another safer systems language";
   the stronger axis is governed deterministic execution with capability manifests, budgets,
   replay, and cross-backend parity.

2. **Capability semantics should stay explicit and machine-readable.**
   The CHERI sources make capability hardware and memory provenance relevant to the long-term
   language design space. Oren's current `@cap.requires(...)` metadata and capsule runtime should
   keep moving toward explicit source/package manifests rather than implicit ambient authority.
   That keeps a future hardware-capability or sandbox-backed mapping plausible.

3. **Agent-readable contracts are a product feature, but protocol lock-in is not.**
   MCP and the 2026 NIST AI Agent Standards Initiative are pressure signals: agents need secure,
   interoperable, typed boundaries. They are not Oren's thesis. Oren should own the deeper language
   contract: metadata output, diagnostics, readiness reports, capability manifests, effect ledgers,
   semantic diffs, and replay logs as first-class artifacts that can project into many protocols.

4. **Supply-chain posture should be built into the toolchain.**
   SLSA, Reproducible Builds, NIST SSDF, NIST AI RMF, and NIST PQC sources favor reproducible
   builds, provenance, dependency clarity, risk-management artifacts, crypto agility, and
   secure-by-default release workflows. Oren's deterministic metadata and runtime-profile selection
   should lead toward build attestations that include source capability requirements, backend,
   runtime profile, compiler hash, policy inputs, and crypto/runtime dependency posture.

5. **WASI/component interop is a natural sandbox target.**
   WASI and the WebAssembly Component Model align with capability-oriented host imports and
   component boundaries. Oren should keep AVM policy and native capsule vocabulary close enough to
   sandbox/component terminology that future WASM/WASI targets do not need a separate authority
   model.

6. **Deterministic execution is becoming an explicit runtime feature elsewhere.**
   WebAssembly 3.0's deterministic profile is useful pressure evidence: deterministic execution is
   no longer only a test harness concern. Oren should go further by attaching determinism to source
   capability domains, AVM replay, native runtime profiles, schedule traces, and artifact manifests.

7. **Observability needs stable semantic events, not ad-hoc traces.**
   OpenTelemetry's specification and semantic-convention split is a useful model: Oren runtime and
   AVM events should eventually have stable names and fields for capability denials, budget
   consumption, GC/scheduler actions, replay divergence, and host-effect calls.

8. **PQC and AI-era risk controls should shape stdlib and toolchain APIs.**
   NIST's PQC standardization and AI RMF profile point at two durable 2026-2032 pressures:
   cryptographic agility and governed agent workflows. Oren does not need to become a crypto
   research language, but the standard library and build tooling should avoid hard-coded crypto
   assumptions, expose policy-readable algorithm choices, and make AI/tool host effects visible
   through the same capability and provenance machinery.

## 2026-2032 Feature Horizon

The strongest Oren path is not to chase every modern language feature. The demanding feature
set should make Oren a governed execution system that can still produce practical native code.

## Forecast Bets Beyond The Source Material

The sources above are pressure signals, not the product thesis by themselves. The Oren-specific
forecast is that a new language should make the following ideas first-class before mainstream
languages fully converge on them.

The deeper forecast is archived separately in
`project-doc/oren_language_system_bets_20260412.md`. That note is deliberately protocol-independent:
it treats today's agent protocols as adapters and argues for Oren-owned semantics such as
determinism grades, AVM counterfactual execution, effect ledgers, budgeted interfaces,
denial-as-data, schedule capsules, and semantic package manifests.

1. **Determinism as a selectable semantic mode, not a VM accident.**
   A program should be able to choose a fast native profile, a deterministic native profile, or an
   AVM profile, with the compiler making effect, time, RNG, scheduling, and host IO differences
   explicit. This is more than "runs in a sandbox": determinism becomes a language/runtime contract.

2. **Effect ledgers instead of ambient syscall wrappers.**
   Host effects should produce typed ledger entries: requested capability, policy decision, budget
   delta, input/output digest, replay behavior, and failure mode. That gives agents and auditors a
   small artifact to reason over without scraping process logs.

3. **Budgets as part of the interface, not deployment config.**
   Function/module signatures should eventually express resource and effect budgets well enough that
   tooling can answer: "Can this package run in capsule profile with 10 ms CPU, no NET, deterministic
   RNG, and 4 MB heap?" This is stronger than an env knob and weaker than heavyweight formal proof.

4. **Agent-callable modules as a language target.**
   Oren packages should be able to expose commands/tools with typed input/output, capability
   requirements, redaction rules, consent prompts, and structured errors. That treats the agent/tool
   boundary as a compilation target like native or AVM, not as a README convention.

5. **Replayable multiverse execution.**
   AVM snapshots should support cheap forks for "what if this policy/input/tool result were
   different?" The forecast is that agent workflows need deterministic branches, not only one
   sequential run. This makes AVM more than portability; it becomes a search and audit substrate.

6. **Cross-backend semantic diff as a compiler feature.**
   Oren already treats C/native/OBC parity seriously through fixtures. The stronger feature is a
   compiler/runtime command that emits a structured semantic diff when native and AVM disagree:
   value tags, effects, budget deltas, scheduler events, and source spans.

7. **Representation contracts instead of hidden optimizer heroics.**
   Users should be able to request a safe packed view, slot64 list view, typed-buffer view, or
   aliasing mode with clear semantics. The compiler then optimizes inside that declared contract.
   This is a middle path between high-level containers that hide layout and low-level languages that
   force representation details everywhere.

8. **Proof-carrying runtime profiles for ordinary builds.**
   Each build should carry a small, checkable claim: source capabilities, runtime profile,
   dependency capability union, build provenance, deterministic mode, and known unstable surfaces.
   The goal is not academic proof of the whole compiler; it is boring, automatable evidence that a
   package is allowed to run under a policy.

9. **Policy-readable crypto and data sensitivity.**
   Future stdlib APIs should expose algorithm families, key lifecycle hints, data sensitivity, and
   redaction boundaries in metadata. This lets package manifests and agent tools make safe choices
   as PQC migration and AI data-governance pressure increase.

10. **Docs/tests/status as compiler-facing API.**
    Oren should continue turning status matrices, readiness reports, and failure artifacts into
    machine-readable contracts. The forecast is that agent-maintained systems will depend on this as
    much as human-readable docs.

### 2026-2027: Make The Governance Contract Boring

- **Package capability manifests.**
  Extend per-source `capabilities` metadata into package-level declarations for required domains,
  runtime profile, budget defaults, denied-by-default behavior, and dependency effect surfaces.
  This is the highest-leverage follow-up because it turns Oren's differentiator into an auditable
  build input instead of a doc promise.
- **Deterministic build and compile-time effects.**
  Any future `comptime`-like surface should be pure by default, then explicitly budgeted and
  capability-scoped when it needs FS/NET/TIME/RNG. The compiler-in-AVM direction depends on this:
  compile-time execution cannot silently inherit ambient host authority.
- **Capability and provenance metadata bundle.**
  Native and AVM builds should emit a small machine-readable bundle: compiler revision, backend,
  source digest, dependency digest, runtime profile, capability domains, policy inputs, and
  reproducibility mode. This maps naturally to SLSA/NIST-style provenance without overclaiming a
  security certification.
- **Stable capability event schema.**
  Define named events for capability allow/deny, budget consumption, replay divergence, host-effect
  calls, scheduler decisions, and GC safepoints. OpenTelemetry's split between signals and semantic
  conventions is the right shape: Oren should have stable low-cardinality fields, not one-off trace
  strings.
- **Memory-safe default lanes plus explicit unsafe boundaries.**
  CISA/Rust pressure means new systems work is expected to have a memory-safety story. Oren should
  make safe lists, slices, typed buffers, string/bytes, FFI, syscalls, and pointer intrinsics visibly
  separated, with unsafe or capsule-disallowed boundaries obvious in metadata and diagnostics.

### 2028-2029: Make Components And Agents First-Class

- **Interface/world declarations.**
  Add WIT-like interface/world declarations for package imports and exports, but map them to Oren
  capability domains and native/AVM profiles. The target is one authority model that can later
  project to AVM, native capsule, and WASI/component interop.
- **Agent tool module contract.**
  Define an Oren-owned module contract for typed inputs/outputs, capability negotiation, consent
  and scope metadata, isolated sessions, redaction, and structured errors. Do not make this
  MCP-specific: protocol adapters should project the Oren contract into whatever agent ecosystem
  survives.
- **Deterministic scheduler profile.**
  Stabilize a replayable scheduler mode for green threads, channels/select, timers, GC interaction,
  and host IO. Native can keep a faster opportunistic profile, but the deterministic profile must
  be a language/runtime contract, not an integration-test accident.
- **Representation contracts for performance parity.**
  Finish the real `list<int>` / typed-buffer / packed-view story rather than promoting scalar
  scheduling toggles. Users should be able to request safe packed views or slot64 semantics with
  clear aliasing, mutability, overflow, and backend-parity behavior.

### 2030-2032: Hardware, Crypto, And Assurance Headroom

- **CHERI-aware provenance model.**
  Keep pointer/capability semantics clean enough that a future CHERI-like target or sandbox mapping
  can preserve bounds, permissions, and compartment boundaries. This is a design constraint now,
  not an implementation promise for the current backend.
- **PQC-ready crypto surface.**
  Expose algorithm agility, policy metadata, and test vectors around post-quantum-ready APIs so
  package manifests and build attestations can state which crypto families are used. Avoid baking
  fixed legacy algorithm choices into high-level APIs.
- **Formalized runtime profiles.**
  Turn `core`, `full`, and `capsule` into versioned profiles with explicit effect, allocation,
  concurrency, determinism, and observability guarantees. Add conformance fixtures that run across
  C/native/AVM where applicable.
- **Replayable audit artifacts.**
  Build replay artifacts that include inputs, budgets, capability decisions, scheduler traces,
  runtime profile, binary metadata, and source capability manifest. This is the long-term proof
  vehicle for agentic and regulated workflows.
- **Gradual rigorous engineering lane.**
  CHERI's formal-model culture is the right north star for critical parts of Oren: VM bytecode
  validation, capability policy evaluation, manifest normalization, and deterministic scheduler
  semantics are better first targets than trying to verify the whole compiler.

## Concrete Follow-Ups

- Extend the new per-source `capabilities` metadata and artifact manifest `policy` block into a
  package-level manifest that declares runtime profile, domain requirements, and budget defaults.
  The first source-level marker is now `@oren.package(...)`; artifact manifests now also emit
  `source_package_check`, with opt-in enforcement through `--enforce-package-policy`.
- Add an attestation-oriented metadata bundle for native builds: compiler revision, backend,
  runtime profile, source capability domains, and deterministic build inputs.
- Define a small stable event schema for capability decisions and budget consumption before adding
  more tracing knobs.
- Add determinism grades to metadata: pure, deterministic-host, replayable-host, and
  nondeterministic.
- Sketch the AVM counterfactual execution API: snapshot, fork, policy override, effect replay,
  semantic diff.
- Add a policy-readable crypto inventory to metadata before adding broad crypto APIs; the feature
  should support PQC migration rather than hard-code one algorithm generation.
- Specify an Oren-native tool/module metadata subset for packages that expose agent-callable
  commands, including capability domains, redaction, consent, budgets, and structured failure modes.
- Keep W5 representation/direct-lowering work separate from the product thesis: performance parity
  remains necessary, but Oren's differentiation is the governed execution contract around that
  performance surface.
