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

- Keep implementing artifact policy manifests and package capability manifests. `@oren.package(...)`
  is now the first source-level marker, and artifact manifests now include observe-only
  `source_package_check`; `--enforce-package-policy` now turns `mismatch_observed` into a build
  error. `scripts/run_package_policy.sh` now dispatches package-policy execution for AVM and
  native: the AVM path applies package capsule/gas/heap/wall declarations and rejects bytecode
  whose static used domains exceed the package allowlist, while the native path applies package
  capsule/domain policy plus a wall-time watchdog, enforces heap budgets from captured native-run
  JSON live-heap scan evidence, enforces CPU budgets from child process resource usage where
  available, and enforces gas budgets from captured `native_stmt_loop_tick_v0` evidence after
  building and running gas-budgeted artifacts with `OREN_NATIVE_GAS_ACCOUNTING=stmt`.
  Native executables now have a runtime-observed
  `OREN_NATIVE_RUN_JSON=1` bridge with wall timing, capsule domain-gate counters, selected
  FS/NET/PROC resource-check counters, a scanned live tracked-heap byte count, and default
  loop-safepoint, opt-in statement+loop, opt-in lowering-block, opt-in weighted lowering-block, or
  opt-in dynamic-emitter native gas. Native and AVM gas summaries now carry explicit
  `oren.gas-surface.v0` metadata, and semantic diff marks `native_dynamic_emitter_tick_v0` and
  canonical `avm_opcode_cost_v0` opcode-dispatch gas (`unit_scope="avm_canonical"`,
	  `runtime_path_aware=true`, `cross_arch_comparable=true`, `conversion_ready=true`,
	  `avm_canonical=true`) as non-comparable rather than pretending any positive counter is enough.
	  Semantic diff now also carries same-source `oren.avm-canonical-sidecar-gas.v0` OBC evidence with
	  `package_policy_may_use=false`, so parity tooling gets AVM canonical evidence without pretending it
	  is native gas. Native package policy now has a package-bound sidecar enforcement profile; the
	  remaining gap is broadening that profile or adding finer native instruction-equivalent gas rather
	  than another manifest-only field.
		  Native package policy can now opt into that package-bound sidecar path with
			  `OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1`: it builds a bytecode sidecar from the same source
				  and package manifest, runs it under package AVM budgets, and marks the AVM canonical gas
				  certificate usable when stdout/exit matches the native run or when the sidecar reports AVM
				  canonical gas budget exhaustion through structured `avm.run.v1.error` evidence. It also records normalized stdout/stderr hashes plus an explicit
				  `certification_status` and `certification_failure_reasons`. It can now also select
		  `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar`, which uses that certificate for
		  package `budget_gas` enforcement and reports `runner_wall_avm_canonical_gas` plus
		  `enforcement_profile="avm-sidecar"` without claiming native runtime conversion; the shared
		  dispatcher exposes the same path as
		  `scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar`, and now defaults
		  native dispatch to `auto` so gas-budgeted packages select that path.
- The initial effect-ledger schema is now pinned in `docs/EFFECT_LEDGER_CONTRACT.md`; next work is
  conforming native/AVM runtime emission and cross-backend semantic-diff consumption.
- `scripts/run_backend_semantic_diff.sh` is now the first small semantic-diff consumer: it emits
  `oren.semantic-diff.v0` JSON for C/native/OBC runs plus native/AVM ledger-summary bridges and
  explicit gas-surface comparison status. It now also records empirical
  `oren.gas-surface-calibration.v0` ratios as evidence, while marking them as not a conversion. The
  `oren.gas-surface-calibration-set.v0` guard combines tiny smoke, loop-heavy, branch-heavy,
  call-heavy, and allocation-heavy fixtures into a multi-sample report, preserving the current ratio spread as evidence
  that Oren needs a real native/AVM gas contract instead of a convenient scalar multiplier. It now also emits
	  `oren.gas-surface-conversion-decision.v0` with package-policy conversion blocked until
	  AVM canonical sidecar gas is package-bound or native instruction-equivalent gas exists, and each calibration sample
  carries native surface metadata (`unit_scope`, `target_arch`, `unit_family`, `runtime_path_aware`,
  `cross_arch_comparable`, `conversion_ready`) plus the AVM canonical surface metadata, so tooling can
  reject conversion by contract rather than by ratio heuristics alone. The first dynamic-emitter
  calibration set (`build/reports/backend_gas_surface_calibration_set_20260412_081109_85502.json`)
  still spans `~2.49x` to `~16.82x` native ticks per AVM opcode gas, so dynamic-emitter evidence is
  path-aware but still not a conversion rule. `oren.native-instruction-surface-decision.v0` also rejects whole-binary native
	  disassembly instruction counts as a shortcut by cross-checking them against the current
	  `native_dynamic_emitter_tick_v0` runtime surface: whole-binary counts include linked runtime text
		  and are not dynamic per-executed-path gas. The first static-proxy report counted the same `474624`
		  whole-binary native instructions for the original three calibration fixtures while AVM opcode gas varied
			  from `234` to `2328`; the current default guard also requires call-heavy and allocation-heavy source-class coverage.
	  Oren also guards exact native gas mode
  spellings: `stmt` and `statement` mean statement+loop gas, `basic-block` selects distinct
  lowering-block evidence, `block-weighted` selects weighted lowering-block evidence, and
  `dynamic-emitter` selects backend-local runtime path-aware emitter-span evidence rather than silently
  aliasing statement gas. Native gas-surface metadata now explicitly sets `unit_scope="backend_local"`,
  includes `target_arch` and `unit_family`, and sets `cross_arch_comparable=false`,
  `conversion_ready=false`, and `avm_canonical=false` across all native modes, so future tooling
  cannot mistake statement/basic/block-weighted/dynamic-emitter counters for instruction-equivalent gas or hide
  arm64/x64 unit-family differences. The native build cache key now
	  includes the normalized gas-accounting mode, so cached native artifacts cannot flatten those surfaces.
	  `docs/GAS_SURFACE_REGISTRY.md` and `make verify-gas-surface-registry` now make that registry
	  machine-checked across runtime JSON, semantic-diff, package-policy, and docs.
			  Next work is adding instruction-equivalent native gas or tightening the package-bound AVM sidecar
		  failure taxonomy further, not only expanding fixture scripts.
- Promote deterministic profile vocabulary in docs and metadata: determinism grade, replayability,
  scheduler policy, budget defaults, and source-required domains.
- Keep W5 representation work tied to representation contracts, not isolated scalar scheduling
  toggles.
- Treat external agent protocols as adapters. The Oren-owned API is the module manifest and effect
  ledger.
