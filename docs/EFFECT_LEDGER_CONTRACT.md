# Effect Ledger Contract

**Last updated:** 2026-04-12

This is the Oren v0 target contract for effect ledgers. It is a schema and tooling
contract first: the runtime does not yet emit a complete ledger for every effect.
The point is to define the evidence shape before adding more ad-hoc traces.

## Why This Exists

Oren's differentiator is deterministic, capability-governed native/AVM execution
with replayable evidence. A capability decision without a stable record is hard for
agents, tests, and deployment controllers to audit. Logs are not enough: Oren needs
typed effect records that can be replayed, diffed across backends, and attached to
artifact manifests or minimized bug reports.

## Effect Ledger v0

An effect ledger is an ordered JSON object:

```json
{
  "version": 1,
  "schema": "oren.effect-ledger.v0",
  "backend": "native",
  "runtime_profile": "capsule",
  "determinism_grade": "replayable-host",
  "source_digest": "sha256:...",
  "artifact_digest": "sha256:...",
  "entries": [
    {
      "seq": 0,
      "phase": "run",
      "domain": "FS",
      "operation": "read_file",
      "resource": "mount:workspace/path:data/input.txt",
      "decision": "allow",
      "denial_reason": null,
      "budget_before": { "cpu_steps": 1200, "effect_calls": 8 },
      "budget_delta": { "cpu_steps": 20, "effect_calls": 1 },
      "budget_after": { "cpu_steps": 1220, "effect_calls": 9 },
      "input_digest": "sha256:...",
      "output_digest": "sha256:...",
      "redaction": "path-salted-digest",
      "replay_mode": "recorded",
      "schedule_epoch": 3,
      "source_span": "tests/fixtures/example.oren:12:8"
    }
  ]
}
```

Required top-level fields:

- `version`: integer schema version, currently `1`.
- `schema`: stable schema id, currently `oren.effect-ledger.v0`.
- `backend`: `native`, `bytecode`, `c`, or a future backend id.
- `runtime_profile`: `core`, `full`, `capsule`, `avm`, `none`, or a future versioned profile.
- `determinism_grade`: `pure`, `deterministic-host`, `replayable-host`, or `nondeterministic`.
- `source_digest`: source or source-bundle digest when available.
- `artifact_digest`: emitted artifact digest when available.
- `entries`: ordered effect records.

Required entry fields:

- `seq`: monotonically increasing effect sequence number within this ledger.
- `phase`: `compile`, `run`, `replay`, `test`, or `semantic-diff`.
- `domain`: one of the capability domains from `docs/CAPABILITY_RUNTIME_CONTRACT.md`, such as
  `FS`, `NET`, `PROC`, `ENV`, `TIME`, `RNG`, `EXIT`, or `AVM`.
- `operation`: stable operation id, for example `read_file`, `tcp_connect`, `env_get`,
  `time_now_ns`, `rand_u64`, `proc_spawn`, or `avm_run`.
- `resource`: policy-readable resource label. Raw secrets or full host paths should not be
  required in deterministic/capsule ledgers.
- `decision`: `allow`, `deny`, `virtualize`, `replay`, or `redact`.
- `denial_reason`: null for non-denials, otherwise a stable reason id such as
  `domain_not_allowed`, `resource_not_allowed`, `budget_exceeded`, or `profile_forbidden`.
- `budget_before`, `budget_delta`, `budget_after`: budget objects or null when not tracked.
- `input_digest` and `output_digest`: digests or null; large payloads should not be embedded.
- `redaction`: redaction policy id for sensitive fields.
- `replay_mode`: `recorded`, `virtual`, `deterministic`, `nondeterministic`, or `not_replayable`.
- `schedule_epoch`: scheduler epoch or null for non-concurrent contexts.
- `source_span`: source location string or null when unavailable.

## Design Rules

- Denial is data. A denied effect should be ledgerable even when native capsule mode also fails
  closed for that API.
- The ledger is policy-readable, not a raw syscall trace. It records the language/runtime operation
  and capability decision, not every host syscall detail.
- The ledger must be backend-comparable. Native and AVM records should converge on the same domain,
  operation, decision, replay, and budget vocabulary even if their internal implementations differ.
- The ledger must be redaction-aware by default. Secret values, credentials, full host paths, and
  unbounded output bytes belong behind digests or explicit redaction policy.
- The ledger should compose with semantic diffs. Cross-backend parity tooling should be able to
  compare `entries` and budget deltas without scraping logs.
- The first repo-level semantic-diff consumer is intentionally smaller than the full ledger:
  `scripts/run_backend_semantic_diff.sh` emits `oren.semantic-diff.v0` JSON with C/native/OBC
  exit codes, normalized stdout/stderr hashes, log paths, and a pass/fail verdict. It also runs
  a second native execution with `OREN_NATIVE_RUN_JSON=1` and the OBC artifact with
  `--print-run-json`. Those runs record native/AVM `effect_ledger_summary` bridges, normalized
  `budget_deltas`, ledger availability per backend, and whether full all-backend ledger/budget
  comparison is possible. The report also exposes explicit gas-surface metadata and currently marks
  native/OBC gas as non-comparable because native `native_dynamic_emitter_tick_v0` is not the same unit as
  AVM `avm_opcode_cost_v0`. It includes `oren.gas-surface-calibration.v0` empirical ratios for the
  fixture, but those ratios are evidence only and are flagged as `not_a_conversion` until a real
  conversion contract exists. `scripts/verify_backend_gas_surface_calibration_set.sh` writes an
  `oren.gas-surface-calibration-set.v0` report from default smoke, loop-heavy, and branch-heavy
  fixtures. The report keeps the current ratio spread explicit as `single_ratio_unsafe` and emits an
  `oren.gas-surface-conversion-decision.v0` object that blocks package-policy gas conversion from a
  single empirical ratio until Oren has validated native dynamic-emitter or instruction-equivalent gas evidence.
  C ledger export is still intentionally reported as unavailable rather than inferred from logs.
- The native package-policy runner can separately emit `oren.native-package-policy-run.v0`
  through `OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path>`. That file is runner-observed
  wall/gas/heap/CPU-budget evidence for native capsule execution and can include a captured native
  `effect_ledger` summary when the runner enables `OREN_NATIVE_RUN_JSON=1`; native heap budgets
  are enforced from the captured `heap_bytes.used` live-heap scan, native CPU budgets are enforced
  from child process resource usage where available, and native gas budgets are enforced from the
  captured `native_stmt_loop_tick_v0` counter after the runner builds and runs the artifact with
  `OREN_NATIVE_GAS_ACCOUNTING=stmt`.
- Native capsule runtime now exposes `oren.native-capsule-effect-gates.v0` through
  `native_capsule_effect_gate_summary_json()` and the native run JSON `domain_gates` field.
  This is the first native-owned effect evidence bridge: it counts central capsule domain-gate
  checks and denied gates.
- Native capsule runtime also exposes `oren.native-capsule-resource-checks.v0` through
  `native_capsule_resource_check_summary_json()` and the native run JSON `resource_checks` field.
  This counts selected concrete FS/NET/PROC resource allow/deny decisions after a domain gate,
  such as FS prefix/mount checks, NET socket/endpoint checks, and PROC exec/argv/wait/kill checks.
  It is still a summary bridge, not a complete ordered effect ledger.

## Verification Map

Use this guard when changing the effect-ledger contract or its doc wiring:

```sh
make verify-effect-ledger-contract
make verify-avm-effect-ledger-json
```

The contract guard checks this schema note, the capability contract, the roadmap docs, Makefile
wiring, and then runs the AVM JSON guard. The AVM guard checks the current
`effect_ledger_summary` runtime bridge with in-memory record logs, deterministic trace bytes,
`AVM_TIMEOUT_MS` wall-budget reporting, and the `AVM_LOG_BYTES` record-header budget edge. The
native package-policy guard checks the current capsule domain-gate counter bridge, and
`make verify-native-capsule-resource-checks` checks the native resource-check summary bridge.
Full native/AVM ledger parity fixtures are still future work.

## Current AVM Run Summary

AVM `--print-run-json` now includes an `effect_ledger_summary` object. This is intentionally not
the full ordered ledger above; it is a compact bridge surface that reports whether deterministic
mode, record/replay, and budget accounting were active for the run:

```json
{
  "effect_ledger_summary": {
    "schema": "oren.effect-ledger-summary.v0",
    "backend": "bytecode",
    "runtime_profile": "avm",
    "determinism_grade": "replayable-host",
    "determinism": {
      "enabled": true,
      "virtual_now_ns": 123456,
      "virtual_step_ns": 7,
      "virtual_sleep_ns": 0
    },
    "record": { "enabled": true, "sink": "mem", "bytes": 64 },
    "replay": { "enabled": false, "source": "none", "bytes": 0, "position": 0 },
    "budgets": {
      "gas": {
        "executed": 10,
        "remaining": 99990,
        "kind": "avm_opcode_cost_v0",
        "surface": {
          "schema": "oren.gas-surface.v0",
          "id": "avm_opcode_cost_v0",
          "backend": "bytecode",
          "unit": "opcode_cost",
          "granularity": "opcode_dispatch",
          "avm_canonical": true
        }
      },
      "heap_bytes": { "limit": 0, "used": 0 },
      "wall_ms": { "limit": 1000, "elapsed_ns": 250000 },
      "io_bytes": { "limit": 0, "used": 0 },
      "log_bytes": { "limit": 0, "used": 64 },
      "trace_bytes": { "enabled": false, "limit": 0, "used": 0, "truncated": false }
    }
  }
}
```

The summary is useful for orchestration and smoke tests, but the future feature is still the full
entry ledger with domains, operations, decisions, digests, redaction, replay, and source spans.
The summary intentionally reports budget counters that already exist in the VM, rather than a
parallel accounting system.

Native executables can now opt into the same compact bridge by setting
`OREN_NATIVE_RUN_JSON=1`. On normal `main` return or explicit `exit(...)`, the native runtime
prints one `oren.native-run.v0` JSON line containing `effect_ledger_summary`. Native currently
reports `wall_ms.elapsed_ns` from runtime monotonic time, includes the
`oren.native-capsule-effect-gates.v0` `domain_gates` object, includes the
`oren.native-capsule-resource-checks.v0` `resource_checks` object, and reports `heap_bytes.used`
from a report-time scan of live native GC tracking nodes with `kind="tracked_live_scan"`. Gas is
reported as `kind="native_loop_safepoint_tick_v0"` by default; backend loop poll sites charge their
mask interval when they fire, while direct/manual native `oren_gc_safepoint()` arrivals charge one tick.
When matching build/run invocations set `OREN_NATIVE_GAS_ACCOUNTING=stmt`, the same field reports
`kind="native_stmt_loop_tick_v0"` and also charges backend statement/op boundaries. The exact synonym
`statement` reports the same surface, while `OREN_NATIVE_GAS_ACCOUNTING=basic-block` reports the
distinct `kind="native_basic_block_tick_v0"` surface for native lowering basic-block entry ticks plus
loop-poll ticks. `OREN_NATIVE_GAS_ACCOUNTING=block-weighted` reports
`kind="native_block_weighted_tick_v0"`, using static lowering-block weights plus explicit loop-condition
charges and loop-poll ticks. `OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter` reports
`kind="native_dynamic_emitter_tick_v0"`, using patchable runtime notes that charge executed backend emitter
spans while excluding the gas-note call overhead itself. Semantic diff uses the dynamic-emitter mode so it
has runtime path-aware native evidence, but each gas object carries an explicit `surface` object with
`schema="oren.gas-surface.v0"`. The dynamic-emitter surface also reports
`unit_scope="backend_local"`, `runtime_path_aware=true`, `cross_arch_comparable=false`, and
`conversion_ready=false`; arm64 and x64 can therefore expose path-aware evidence without pretending the
counter is architecture-neutral instruction gas. That surface keeps native
`native_dynamic_emitter_tick_v0` distinct from AVM `avm_opcode_cost_v0`; semantic diff reports the current
native/OBC gas surfaces as non-comparable until Oren validates a conversion contract. The exact native mode spelling
`instruction-equivalent` is reserved: today the guard proves it falls back to default loop-safepoint
gas instead of silently aliasing statement, basic-block, block-weighted, or dynamic-emitter gas.
`make verify-native-gas-accounting-modes` guards those mode contracts. The native build cache key
also records the normalized gas mode, and the dedicated gas-mode verifier forces `--no-cache` so
emitted gas notes are tested directly. The current semantic-diff report also records empirical
`native_per_obc` and `obc_per_native` ratios
under `oren.gas-surface-calibration.v0`; those numbers are calibration evidence, not a rule that
package policy may use for enforcement. `make verify-backend-semantic-diff-gas-calibration` runs the
same schema guard against an additional loop-heavy fixture, and
`make verify-backend-gas-surface-calibration-set` writes an `oren.gas-surface-calibration-set.v0`
report proving the current ratio spread across default, loop-heavy, and branch-heavy fixtures is too
fixture-sensitive to promote as a conversion rule. The same report carries an
`oren.gas-surface-conversion-decision.v0` decision with `package_policy_may_convert=false` and
`required_next_surface="validated_native_dynamic_emitter_or_instruction_equivalent_gas"`.
`make verify-backend-native-instruction-surface-decision` records a second blocker:
`oren.native-instruction-surface-decision.v0` rejects whole-binary native disassembly instruction counts
as a runtime gas surface by cross-checking them against the current `native_dynamic_emitter_tick_v0`
runtime surface. Whole-binary counts include linked runtime text and are not per-executed-path evidence.
The first report (`build/reports/backend_native_instruction_surface_decision_20260412_083236_29513.json`)
counted the same `474624` whole-binary native instructions for the default, loop-heavy, and branch-heavy
fixtures while AVM opcode gas varied, so the required next step is validating dynamic-emitter evidence or
adding instruction-equivalent native gas, not promoting a static binary-size proxy.
The first dynamic-emitter calibration set
(`build/reports/backend_gas_surface_calibration_set_20260412_081109_85502.json`) narrowed the contract to
runtime path-aware native evidence, but still blocked conversion: default smoke, loop-heavy, and
branch-heavy samples measured `native_per_obc` ratios of `~16.82x`, `~4.07x`, and `~2.49x`, so
`single_ratio_unsafe` remains true.
