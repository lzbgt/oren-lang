# Oren Feature Horizon Research

**Date:** 2026-04-12

This note indexes the archived source pages under `project-doc/web/feature-horizon-20260412/`
and extracts engineering implications for Oren's differentiation work. The HTML snapshots are
stored locally so future agent work can inspect the original sources without relying only on
chat history or partial summaries.

## Source Archive

| Area | Local archive | Original URL recorded in archive |
| --- | --- | --- |
| CHERI | `project-doc/web/feature-horizon-20260412/cheri/cambridge-cheri.html` | Not declared in the HTML snapshot. |
| CHERI Alliance | `project-doc/web/feature-horizon-20260412/cheri/cheri-alliance-who-we-are.html` | `https://cheri-alliance.org/who-we-are/` |
| CISA memory-safe languages | `project-doc/web/feature-horizon-20260412/cisa/cisa-memory-safe-languages.html` | `https://www.cisa.gov/resources-tools/resources/memory-safe-languages-reducing-vulnerabilities-modern-software-development` |
| CISA memory-safe roadmap alert | `project-doc/web/feature-horizon-20260412/cisa/cisa-memory-safe-roadmaps-alert.html` | `https://www.cisa.gov/news-events/alerts/2023/12/06/cisa-releases-joint-guide-software-manufacturers-case-memory-safe-roadmaps` |
| CISA product security bad practices | `project-doc/web/feature-horizon-20260412/cisa/cisa-product-security-bad-practices.html` | `https://www.cisa.gov/resources-tools/resources/product-security-bad-practices` |
| Model Context Protocol architecture | `project-doc/web/feature-horizon-20260412/mcp/mcp-2025-11-25-architecture.html` | `https://modelcontextprotocol.io/specification/2025-11-25/architecture` |
| Model Context Protocol changes | `project-doc/web/feature-horizon-20260412/mcp/mcp-2025-11-25-changelog.html` | `https://modelcontextprotocol.io/specification/2025-11-25/changelog` |
| NIST AI RMF generative AI profile | `project-doc/web/feature-horizon-20260412/nist/nist-ai-rmf-generative-ai-profile.html` | `https://www.nist.gov/publications/artificial-intelligence-risk-management-framework-generative-artificial-intelligence` |
| NIST PQC FIPS announcement | `project-doc/web/feature-horizon-20260412/nist/nist-pqc-fips-announcement.html` | `https://www.nist.gov/news-events/news/2024/08/announcing-approval-three-federal-information-processing-standards-fips` |
| NIST SSDF SP 800-218 | `project-doc/web/feature-horizon-20260412/nist/nist-ssdf-sp800-218.html` | Not declared in the HTML snapshot. |
| OpenTelemetry semantic conventions | `project-doc/web/feature-horizon-20260412/opentelemetry/opentelemetry-semantic-conventions.html` | `https://opentelemetry.io/docs/concepts/semantic-conventions/` |
| OpenTelemetry specification | `project-doc/web/feature-horizon-20260412/opentelemetry/opentelemetry-spec.html` | `https://opentelemetry.io/docs/specs/otel/` |
| Rust Foundation strategic plan | `project-doc/web/feature-horizon-20260412/rust/rust-foundation-strategic-plan-2026-2028.html` | `https://rustfoundation.org/strategic-plan/` |
| Rust project goals | `project-doc/web/feature-horizon-20260412/rust/rust-project-goals-2025h2.html` | Not declared in the HTML snapshot. |
| SLSA v1.1 | `project-doc/web/feature-horizon-20260412/slsa/slsa-spec-v1.1.html` | Not declared in the HTML snapshot. |
| WebAssembly Component Model | `project-doc/web/feature-horizon-20260412/wasm/bytecodealliance-component-model-concepts.html` | Not declared in the HTML snapshot. |
| WASI | `project-doc/web/feature-horizon-20260412/wasm/wasi-dev.html` | `https://wasi.dev/` |

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

3. **Agent-readable contracts are a product feature.**
   MCP exists because tools and agents need explicit, typed protocol boundaries. Oren should
   treat metadata output, diagnostics, readiness reports, capability manifests, and replay logs as
   first-class contracts for agents, not as incidental compiler debug output.

4. **Supply-chain posture should be built into the toolchain.**
   SLSA, NIST SSDF, NIST AI RMF, and NIST PQC sources favor reproducible builds, provenance,
   dependency clarity, risk-management artifacts, crypto agility, and secure-by-default release
   workflows. Oren's deterministic metadata and runtime-profile selection should lead toward build
   attestations that include source capability requirements, backend, runtime profile, compiler hash,
   policy inputs, and crypto/runtime dependency posture.

5. **WASI/component interop is a natural sandbox target.**
   WASI and the WebAssembly Component Model align with capability-oriented host imports and
   component boundaries. Oren should keep AVM policy and native capsule vocabulary close enough to
   sandbox/component terminology that future WASM/WASI targets do not need a separate authority
   model.

6. **Observability needs stable semantic events, not ad-hoc traces.**
   OpenTelemetry's specification and semantic-convention split is a useful model: Oren runtime and
   AVM events should eventually have stable names and fields for capability denials, budget
   consumption, GC/scheduler actions, replay divergence, and host-effect calls.

## Concrete Follow-Ups

- Extend the new per-source `capabilities` metadata into a package-level manifest that declares
  runtime profile, domain requirements, and budget defaults.
- Add an attestation-oriented metadata bundle for native builds: compiler revision, backend,
  runtime profile, source capability domains, and deterministic build inputs.
- Define a small stable event schema for capability decisions and budget consumption before adding
  more tracing knobs.
- Keep W5 representation/direct-lowering work separate from the product thesis: performance parity
  remains necessary, but Oren's differentiation is the governed execution contract around that
  performance surface.
