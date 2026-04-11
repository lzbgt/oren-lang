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
  the OBC artifact with `--print-run-json` and records the AVM `effect_ledger_summary`,
  normalized `budget_deltas`, ledger availability per backend, and whether full all-backend
  ledger/budget comparison is possible. Native/C ledger export is still intentionally reported
  as unavailable rather than inferred from logs.

## Verification Map

Use this guard when changing the effect-ledger contract or its doc wiring:

```sh
make verify-effect-ledger-contract
make verify-avm-effect-ledger-json
```

The contract guard checks this schema note, the capability contract, the roadmap docs, Makefile
wiring, and then runs the AVM JSON guard. The AVM guard checks the current
`effect_ledger_summary` runtime bridge with in-memory record logs, deterministic trace bytes,
`AVM_TIMEOUT_MS` wall-budget reporting, and the `AVM_LOG_BYTES` record-header budget edge. Full
native/AVM ledger parity fixtures are still future work.

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
      "gas": { "executed": 10, "remaining": 99990 },
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
