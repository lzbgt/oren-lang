# Oren Language-System Bets For 2026-2032

**Date:** 2026-04-12

This note is intentionally more speculative than `project-doc/oren_feature_horizon_20260412.md`.
The archived source material is useful as pressure evidence, but the goal here is not to copy
protocols or echo standardization roadmaps. The goal is to name Oren-specific language-system
features that should still matter if today's agent protocols, framework names, and deployment
fashions disappear.

## Framing

The durable 2026-2032 pressure is not "support MCP" or any other single protocol. The durable
pressure is that software will increasingly be written, invoked, inspected, replayed, and repaired
by semi-autonomous agents under policy. A modern language should therefore make execution evidence
and authority boundaries part of the language contract, not an afterthought in CI or platform glue.

Oren's strongest lane is:

> deterministic, capability-governed native/AVM execution with replayable evidence.

That is different from a normal systems language, a normal VM language, and a normal sandbox target.
It is a language plus runtime plus artifact contract.

## High-Conviction Bets

1. **Determinism grades, not one boolean.**
   Oren should eventually classify functions/modules by determinism grade:
   `pure`, `deterministic-host`, `replayable-host`, and `nondeterministic`. The difference matters.
   `pure` means no host effects. `deterministic-host` may read declared immutable inputs.
   `replayable-host` can consume time/RNG/IO only through ledgered effects. `nondeterministic`
   should be visible in metadata and rejected by capsule/deterministic profiles unless explicitly
   allowed.

2. **AVM as a counterfactual execution substrate.**
   AVM should not be positioned only as portable bytecode. The more original feature is cheap
   branchable execution: snapshot a program, fork universes, change a policy decision, input, RNG
   stream, time tick, or tool result, and compare outcomes. This makes AVM useful for agent planning,
   audit, tests, and repair loops in a way a normal native binary is not.

3. **Effect ledgers as normal return-side evidence.**
   Host calls should have stable ledger records: domain, operation, resource handle, budget delta,
   input digest, output digest, denial reason, replay behavior, and source span. Logs are too weak;
   ledgers should be structured data that an agent, verifier, or deployment controller can consume.

4. **Budgeted interfaces.**
   Oren modules should be able to publish resource contracts: max CPU steps, wall-clock class,
   heap, output bytes, syscalls, open handles, network endpoints, child processes, and AVM child
   universe count. This is not just deployment config; it belongs at the module/interface boundary.

5. **Denial-as-data, not just exceptions.**
   Capability denial should be representable as typed data in deterministic profiles. Fatal process
   termination is sometimes necessary for native capsule failure, but AVM and deterministic native
   modes should prefer structured denial values where an agent can continue reasoning.

6. **Cross-backend semantic diff as a compiler product.**
   Oren should have a first-class command that runs the same fixture on C/native/AVM and emits a
   semantic diff: value tags, output bytes, effect ledger deltas, budget deltas, panic class, source
   span, and scheduler decisions. This turns backend parity from a hidden test habit into a language
   feature.

7. **Representation contracts instead of optimizer hope.**
   Data layout should become an explicit contract: slot64 list, packed i32 view, typed-buffer view,
   owned packed copy, borrowed packed view, and aliasing/mutability rules. The compiler should
   optimize inside the declared contract. This is the path to practical performance without losing
   deterministic and capability semantics.

8. **Compiler-in-AVM as a trust boundary.**
   Compile-time execution should be pure by default and then explicitly capability-scoped, budgeted,
   and replayable. The long-term goal is that untrusted packages can run compile-time code inside
   AVM rather than inheriting ambient host authority from the build machine.

9. **Artifact policy manifests as build facts.**
   Every emitted artifact should be able to carry a small policy block: backend, runtime profile,
   deterministic mode, source-required domains, allowed domains, declared budgets, source digest,
   compiler revision, and known unstable surfaces. This is not a security certification by itself;
   it is the substrate for automated trust decisions.

10. **Agent-callable modules without protocol lock-in.**
    Oren packages should expose callable commands with typed inputs/outputs, capability needs,
    redaction rules, consent requirements, and structured failures. The schema can adapt to MCP,
    future NIST-aligned standards, CLI, HTTP, or AVM invocation, but the language contract should be
    Oren-native and protocol-independent.

11. **Schedule capsules.**
    Concurrency should have a replayable profile. A schedule capsule records task creation, channel
    sends/receives, select choices, timer ticks, GC safepoints, and external-effect unblock points.
    Replaying a failure should not require guessing the scheduler interleaving.

12. **Policy-readable data classes.**
    Types and buffers should eventually carry optional data-class metadata: public, secret,
    credential, personal, model-input, model-output, persistent, ephemeral, redact-on-log. This lets
    effect ledgers and agent-callable modules know what cannot be emitted, persisted, or sent over
    NET without policy.

13. **Runtime profile conformance fixtures.**
    `core`, `full`, `capsule`, deterministic native, and AVM profiles should be versioned and tested
    like language modes. A package should be able to say "I conform to capsule-v1 and avm-det-v1"
    and ship machine-checkable evidence.

14. **Semantic package manifests.**
    Package manifests should not be only dependency lists. They should summarize capability domains,
    determinism grades, runtime profile needs, budget defaults, exported agent-callable commands,
    data-class surfaces, and backend support claims.

15. **Replay-minimized bug reports.**
    The compiler/runtime should be able to produce a compact replay bundle: source digest, artifact
    manifest, input digests, effect ledger, schedule capsule, AVM snapshot id, and semantic diff.
    This is the agent-era version of a minimal reproduction.

## What Not To Build As Identity

- Do not make Oren "MCP in a language." Protocols age; the Oren feature is authority-aware,
  replayable invocation that can project into many protocols.
- Do not make Oren "Zig with a VM." Zig is strongest as an explicit C/toolchain replacement.
  Oren's thesis is governed execution evidence across native and AVM.
- Do not make Oren "Wasm but custom." Wasm's deterministic profile is useful pressure evidence,
  but AVM should earn its place through policy, replay, snapshots, and Oren semantic parity.
- Do not make Oren "Rust but easier." Memory safety pressure is real, but Oren's differentiation is
  deterministic capability governance plus backend parity, not ownership syntax.

## Immediate Translation Into Repo Work

- Keep implementing artifact policy manifests and package capability manifests. They are the first
  concrete layer of proof-carrying runtime profiles.
- Define the stable effect-ledger schema before adding more ad-hoc traces.
- Add a small AVM/native semantic-diff command rather than only expanding fixture scripts.
- Promote deterministic profile vocabulary in docs and metadata: determinism grade, replayability,
  scheduler policy, budget defaults, and source-required domains.
- Keep W5 representation work tied to representation contracts, not isolated scalar scheduling
  toggles.
- Treat external agent protocols as adapters. The Oren-owned API is the module manifest and effect
  ledger.
