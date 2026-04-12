# Gas Surface Registry

This registry is the canonical inventory for gas counters that appear in Oren run JSON,
semantic-diff reports, package-policy runner evidence, and calibration reports.

The rule is intentionally strict: only AVM opcode gas is currently a conversion-ready
canonical gas unit. Native counters are runtime evidence for native execution and native
package-policy enforcement, but they are not AVM gas and must not be converted into AVM gas by
a fixture-specific ratio.

## Registered Surfaces

| Surface | Backend | Unit scope | Unit family | Conversion status | Primary consumers |
|---|---|---|---|---|---|
| `avm_opcode_cost_v0` | `bytecode` | `avm_canonical` | opcode dispatch | `cross_arch_comparable=true`, `conversion_ready=true`, `avm_canonical=true` | AVM `effect_ledger_summary`, semantic diff, calibration set |
| `native_loop_safepoint_tick_v0` | `native` | `backend_local` | native loop safepoint | `cross_arch_comparable=false`, `conversion_ready=false`, `avm_canonical=false` | default native `OREN_NATIVE_RUN_JSON=1` |
| `native_stmt_loop_tick_v0` | `native` | `backend_local` | native statement or op | `cross_arch_comparable=false`, `conversion_ready=false`, `avm_canonical=false` | native package-policy gas budgets |
| `native_basic_block_tick_v0` | `native` | `backend_local` | native lowering block | `cross_arch_comparable=false`, `conversion_ready=false`, `avm_canonical=false` | native gas-mode verification |
| `native_block_weighted_tick_v0` | `native` | `backend_local` | native lowering block weight | `cross_arch_comparable=false`, `conversion_ready=false`, `avm_canonical=false` | native gas-mode verification |
| `native_dynamic_emitter_tick_v0` | `native` | `backend_local` | `fixed_width_instruction_span` on arm64, `emitted_byte_span` on x64 | `cross_arch_comparable=false`, `conversion_ready=false`, `avm_canonical=false` | semantic diff and gas calibration |

## Policy

- Package-policy conversion from native gas to AVM gas is blocked until a validated conversion
  contract exists.
- `native_stmt_loop_tick_v0` can enforce native package `budget_gas`, but only as a native
  statement/op plus loop-poll budget.
- `native_dynamic_emitter_tick_v0` is runtime path-aware evidence for semantic diff, but it is
  architecture-specific and remains non-conversion-ready.
- `oren.avm-canonical-sidecar-gas.v0` is not a new gas surface. It is a semantic-diff
  same-source sidecar that reuses the AVM canonical `avm_opcode_cost_v0` run for evidence while
  preserving `package_policy_may_use=false`.
- The native package-policy runner's `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar` profile
  can enforce package `budget_gas` from a package-bound `oren.avm-canonical-sidecar-gas.v0`
  certificate, reporting `runner_wall_avm_canonical_gas` and
  `enforcement_profile="avm-sidecar"`. The shared dispatcher exposes the same profile as
  `scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar`, and
  now defaults native runs to `auto` when no explicit profile or env override is present. `auto`
  selects that sidecar profile when the package declares `budget_gas`. This still is not a native
  runtime gas conversion.
- `instruction-equivalent` is a reserved native gas-accounting spelling. It must not alias any
  current native surface until a real implementation and conversion contract exist.
- Calibration reports can record empirical ratios, but `oren.gas-surface-calibration.v0` and
  `oren.gas-surface-calibration-set.v0` must keep those ratios out of enforcement.

## AVM Canonical Sidecar Evidence

Semantic diff runs the same source through C, native, and OBC. The OBC leg can produce
`avm_opcode_cost_v0`, which is already AVM canonical and conversion-ready inside the AVM unit
system. `oren.avm-canonical-sidecar-gas.v0` records that OBC value next to native backend-local
gas for the same source/fixture, with `native_runtime_conversion=false`.

That sidecar is useful for parity analysis because it gives every semantic-diff sample an AVM
canonical gas certificate. Under semantic diff its scope is `semantic_diff_same_source_fixture`, so
package policy must not use it. The native package-policy runner can opt into a stronger
`native_package_policy_same_source_artifact` sidecar with
`OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1`; that certificate is package-bound AVM evidence only when
the bytecode sidecar runs with the same package budgets and matches native stdout/exit after run-JSON
lines are removed, or when the sidecar itself reports AVM canonical gas budget exhaustion. Sidecar
records include normalized stdout/stderr hashes, `certification_status`,
`certification_failure_reasons`, and `package_policy_may_use_reason` so consumers can distinguish
parity certificates, budget-exceeded certificates, and non-certified sidecar outcomes.
Budget-exceeded sidecar certificates prefer the structured AVM `avm.run.v1.error` object
(`code=9`, `msg="budget exceeded (gas)"`) over stderr text.
`OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar`, dispatcher
`--gas-profile avm-sidecar` on `--backend native`, or the dispatcher default `auto` profile for a
gas-budgeted package makes that certificate the runner's gas enforcement profile. It still sets
`native_runtime_conversion=false` and uses AVM canonical `avm_opcode_cost_v0` units, not native
backend-local gas units.

## Guards

Use these checks when changing gas accounting, run JSON, package policy, or semantic diff:

```sh
make verify-gas-surface-registry
make verify-effect-ledger-contract
make verify-backend-gas-surface-calibration-set
make verify-backend-native-instruction-surface-decision
make verify-native-gas-accounting-modes
```

`make verify-gas-surface-registry` emits `oren.gas-surface-registry-check.v0` JSON under
`build/reports/` and verifies that the registry, runtime metadata, semantic-diff tooling, native
package policy, and docs still agree on each surface's canonicality and conversion status.
