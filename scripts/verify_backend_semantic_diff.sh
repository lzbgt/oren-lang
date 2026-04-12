#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

set +e
runner_output="$(./scripts/run_backend_semantic_diff.sh "$@" 2>&1)"
rc=$?
set -e

printf '%s\n' "$runner_output"
if [[ "$rc" != "0" ]]; then
  exit "$rc"
fi

report="$(printf '%s\n' "$runner_output" | sed -n 's/^semantic diff report: //p' | tail -n 1)"
if [[ -z "$report" || ! -f "$report" ]]; then
  echo "ERROR: semantic diff report path missing from runner output" >&2
  exit 1
fi

python3 - "$report" <<'PY'
import json
import sys
from pathlib import Path

report = Path(sys.argv[1])
data = json.loads(report.read_text(encoding="utf-8"))

def fail(msg):
    raise SystemExit(f"{report}: {msg}")

if data.get("schema") != "oren.semantic-diff.v0":
    fail(f"schema mismatch: {data.get('schema')!r}")
if data.get("status") != "pass":
    fail(f"status mismatch: {data.get('status')!r}")

checks = data.get("checks") or {}
for key in ("stdout_equal", "exit_code_equal", "all_exit_zero", "expected_line_present_all"):
    if checks.get(key) is not True:
        fail(f"expected {key}=true, got {checks.get(key)!r}")

if checks.get("obc_run_json_schema_ok") is not True:
    fail(f"expected obc_run_json_schema_ok=true, got {checks.get('obc_run_json_schema_ok')!r}")
if checks.get("native_run_json_schema_ok") is not True:
    fail(f"expected native_run_json_schema_ok=true, got {checks.get('native_run_json_schema_ok')!r}")
if checks.get("native_effect_ledger_summary_schema_ok") is not True:
    fail(
        "expected native_effect_ledger_summary_schema_ok=true, "
        f"got {checks.get('native_effect_ledger_summary_schema_ok')!r}"
    )
if checks.get("native_domain_gates_schema_ok") is not True:
    fail(
        "expected native_domain_gates_schema_ok=true, "
        f"got {checks.get('native_domain_gates_schema_ok')!r}"
    )
if checks.get("native_resource_checks_schema_ok") is not True:
    fail(
        "expected native_resource_checks_schema_ok=true, "
        f"got {checks.get('native_resource_checks_schema_ok')!r}"
    )
if checks.get("obc_effect_ledger_summary_schema_ok") is not True:
    fail(
        "expected obc_effect_ledger_summary_schema_ok=true, "
        f"got {checks.get('obc_effect_ledger_summary_schema_ok')!r}"
    )
if checks.get("ledger_available_backends") != ["native", "obc"]:
    fail(f"expected native/OBC ledger availability, got {checks.get('ledger_available_backends')!r}")
if sorted(checks.get("ledger_missing_backends") or []) != ["c"]:
    fail(f"expected only C ledger-missing marker, got {checks.get('ledger_missing_backends')!r}")
if checks.get("ledger_comparable_all_backends") is not False:
    fail("all-backend ledger comparison should stay false until C emits a ledger")
if checks.get("budget_deltas_comparable_all_backends") is not False:
    fail("all-backend budget-delta comparison should stay false until C emits a ledger")
if checks.get("gas_surface_comparable_native_obc") is not False:
    fail("native/OBC gas surfaces should remain non-comparable until a conversion contract exists")
if checks.get("gas_surface_comparison_reason") != "native and OBC gas surfaces differ":
    fail(f"unexpected gas-surface comparison reason: {checks.get('gas_surface_comparison_reason')!r}")

gas_surfaces = data.get("gas_surfaces") or {}
native_surface = gas_surfaces.get("native") or {}
obc_surface = gas_surfaces.get("obc") or {}
if native_surface.get("schema") != "oren.gas-surface.v0" or native_surface.get("id") != "native_dynamic_emitter_tick_v0":
    fail(f"native gas surface mismatch: {native_surface!r}")
if native_surface.get("unit_scope") != "backend_local" or native_surface.get("runtime_path_aware") is not True:
    fail(f"native dynamic-emitter surface should be backend-local runtime-path-aware evidence, got {native_surface!r}")
if native_surface.get("target_arch") not in ("arm64", "x64"):
    fail(f"native dynamic-emitter surface should declare target_arch, got {native_surface!r}")
expected_unit_family = "fixed_width_instruction_span" if native_surface.get("target_arch") == "arm64" else "emitted_byte_span"
if native_surface.get("unit_family") != expected_unit_family:
    fail(f"native dynamic-emitter unit_family mismatch, expected {expected_unit_family!r}, got {native_surface!r}")
if native_surface.get("cross_arch_comparable") is not False or native_surface.get("conversion_ready") is not False:
    fail(f"native dynamic-emitter surface must not be marked conversion-ready, got {native_surface!r}")
if obc_surface.get("schema") != "oren.gas-surface.v0" or obc_surface.get("id") != "avm_opcode_cost_v0":
    fail(f"OBC gas surface mismatch: {obc_surface!r}")
if obc_surface.get("unit") != "opcode_cost" or obc_surface.get("granularity") != "opcode_dispatch":
    fail(f"OBC gas surface should declare opcode-dispatch cost units, got {obc_surface!r}")
if obc_surface.get("unit_scope") != "avm_canonical" or obc_surface.get("runtime_path_aware") is not True:
    fail(f"OBC gas surface should be runtime-path-aware AVM canonical gas, got {obc_surface!r}")
if obc_surface.get("cross_arch_comparable") is not True or obc_surface.get("conversion_ready") is not True:
    fail(f"OBC gas surface should be the conversion-ready AVM canonical target, got {obc_surface!r}")
if obc_surface.get("avm_canonical") is not True:
    fail(f"OBC gas surface should preserve avm_canonical=true, got {obc_surface!r}")
if gas_surfaces.get("native_obc_comparable") is not False:
    fail(f"native/OBC gas surface comparison should be false, got {gas_surfaces!r}")
calibration = data.get("gas_surface_calibration") or {}
if calibration.get("schema") != "oren.gas-surface-calibration.v0":
    fail(f"gas surface calibration schema mismatch: {calibration!r}")
if calibration.get("mode") != "empirical_single_fixture":
    fail(f"gas surface calibration mode mismatch: {calibration!r}")
if calibration.get("source_class") not in ("smoke", "loop_heavy", "branch_heavy", "call_heavy", "alloc_heavy", "custom"):
    fail(f"gas surface calibration source_class mismatch: {calibration!r}")
if calibration.get("native_surface_id") != "native_dynamic_emitter_tick_v0":
    fail(f"native gas calibration surface mismatch: {calibration!r}")
if calibration.get("native_surface_unit_scope") != "backend_local" or calibration.get("native_surface_runtime_path_aware") is not True:
    fail(f"native gas calibration should preserve backend-local dynamic-emitter metadata: {calibration!r}")
if calibration.get("native_surface_target_arch") != native_surface.get("target_arch"):
    fail(f"native gas calibration should preserve target_arch metadata: {calibration!r} vs {native_surface!r}")
if calibration.get("native_surface_unit_family") != native_surface.get("unit_family"):
    fail(f"native gas calibration should preserve unit_family metadata: {calibration!r} vs {native_surface!r}")
if calibration.get("native_surface_cross_arch_comparable") is not False or calibration.get("native_surface_conversion_ready") is not False:
    fail(f"native gas calibration should preserve non-conversion-ready metadata: {calibration!r}")
if calibration.get("obc_surface_id") != "avm_opcode_cost_v0":
    fail(f"OBC gas calibration surface mismatch: {calibration!r}")
if calibration.get("obc_surface_unit_scope") != "avm_canonical" or calibration.get("obc_surface_runtime_path_aware") is not True:
    fail(f"OBC gas calibration should preserve AVM canonical runtime-path-aware metadata: {calibration!r}")
if calibration.get("obc_surface_cross_arch_comparable") is not True or calibration.get("obc_surface_conversion_ready") is not True:
    fail(f"OBC gas calibration should preserve AVM canonical conversion metadata: {calibration!r}")
if calibration.get("obc_surface_avm_canonical") is not True:
    fail(f"OBC gas calibration should preserve avm_canonical=true, got {calibration!r}")
if calibration.get("comparable") is not False or calibration.get("not_a_conversion") is not True:
    fail(f"gas calibration must remain empirical evidence, not a conversion: {calibration!r}")
if int(calibration.get("native_executed") or 0) <= 0 or int(calibration.get("obc_executed") or 0) <= 0:
    fail(f"gas calibration should include positive execution counters, got {calibration!r}")
if float(calibration.get("native_per_obc") or 0.0) <= 0.0 or float(calibration.get("obc_per_native") or 0.0) <= 0.0:
    fail(f"gas calibration should include positive ratios, got {calibration!r}")
if checks.get("gas_surface_calibration_available") is not True:
    fail(f"gas surface calibration availability mismatch: {checks!r}")

backends = data.get("backends") or {}
native = backends.get("native") or {}
native_ledger = native.get("ledger") or {}
if native_ledger.get("available") is not True:
    fail(f"native ledger should be available, got {native_ledger!r}")
if native_ledger.get("run_json_schema") != "oren.native-run.v0":
    fail(f"native run JSON schema mismatch: {native_ledger.get('run_json_schema')!r}")
if native_ledger.get("summary_schema") != "oren.effect-ledger-summary.v0":
    fail(f"native ledger summary schema mismatch: {native_ledger.get('summary_schema')!r}")
if not native_ledger.get("run_json_log") or not Path(native_ledger["run_json_log"]).is_file():
    fail(f"native run JSON log missing: {native_ledger.get('run_json_log')!r}")
if not native_ledger.get("run_json_stderr_log") or not Path(native_ledger["run_json_stderr_log"]).is_file():
    fail(f"native run JSON stderr log missing: {native_ledger.get('run_json_stderr_log')!r}")
if native_ledger.get("run_json_exit_code") != 0:
    fail(f"native run JSON exit mismatch: {native_ledger.get('run_json_exit_code')!r}")

native_summary = native_ledger.get("summary") or {}
native_budgets = native_summary.get("budgets") or {}
native_deltas = native_ledger.get("budget_deltas") or {}
if native_summary.get("backend") != "native":
    fail(f"native ledger backend mismatch: {native_summary!r}")
if native_summary.get("determinism_grade") != "native-host":
    fail(f"native determinism grade mismatch: {native_summary!r}")
domain_gates = native_summary.get("domain_gates") or {}
if domain_gates.get("schema") != "oren.native-capsule-effect-gates.v0":
    fail(f"native domain-gate summary schema mismatch: {domain_gates!r}")
if domain_gates.get("kind") != "domain_gates" or domain_gates.get("available") is not True:
    fail(f"native domain-gate summary availability mismatch: {domain_gates!r}")
resource_checks = native_summary.get("resource_checks") or {}
if resource_checks.get("schema") != "oren.native-capsule-resource-checks.v0":
    fail(f"native resource-check summary schema mismatch: {resource_checks!r}")
if resource_checks.get("kind") != "resource_checks" or resource_checks.get("available") is not True:
    fail(f"native resource-check summary availability mismatch: {resource_checks!r}")
if native_deltas.get("wall_elapsed_ns") != native_budgets.get("wall_ms", {}).get("elapsed_ns"):
    fail(f"native wall elapsed delta should mirror summary budget, got {native_deltas!r} vs {native_budgets!r}")
if native_deltas.get("wall_elapsed_ns") is None or int(native_deltas.get("wall_elapsed_ns")) < 0:
    fail(f"native wall elapsed should be non-negative, got {native_deltas!r}")
native_gas = native_budgets.get("gas") or {}
if native_gas.get("kind") != "native_dynamic_emitter_tick_v0":
    fail(f"native gas kind mismatch: {native_gas!r}")
if (native_gas.get("surface") or {}).get("id") != "native_dynamic_emitter_tick_v0":
    fail(f"native gas surface should mirror kind, got {native_gas!r}")
if native_gas.get("executed") is None or int(native_gas.get("executed")) <= 0:
    fail(f"native gas executed should be positive under semantic-diff dynamic-emitter gas, got {native_gas!r}")
if native_deltas.get("gas_executed") != native_gas.get("executed"):
    fail(f"native gas executed delta should mirror summary budget, got {native_deltas!r} vs {native_gas!r}")
if native_deltas.get("gas_remaining") != native_gas.get("remaining"):
    fail(f"native gas remaining delta should mirror summary budget, got {native_deltas!r} vs {native_gas!r}")
if native_deltas.get("gas_kind") != native_gas.get("kind"):
    fail(f"native gas kind delta should mirror summary budget, got {native_deltas!r} vs {native_gas!r}")
if native_deltas.get("gas_surface_id") != "native_dynamic_emitter_tick_v0":
    fail(f"native gas surface delta mismatch, got {native_deltas!r}")
if native_deltas.get("gas_surface_unit_scope") != "backend_local" or native_deltas.get("gas_surface_runtime_path_aware") is not True:
    fail(f"native gas surface delta should preserve backend-local dynamic-emitter metadata, got {native_deltas!r}")
if native_deltas.get("gas_surface_target_arch") != native_surface.get("target_arch"):
    fail(f"native gas surface delta should preserve target_arch metadata, got {native_deltas!r} vs {native_surface!r}")
if native_deltas.get("gas_surface_unit_family") != native_surface.get("unit_family"):
    fail(f"native gas surface delta should preserve unit_family metadata, got {native_deltas!r} vs {native_surface!r}")
if native_deltas.get("gas_surface_cross_arch_comparable") is not False or native_deltas.get("gas_surface_conversion_ready") is not False:
    fail(f"native gas surface delta should preserve non-conversion metadata, got {native_deltas!r}")
native_heap = native_budgets.get("heap_bytes") or {}
if native_heap.get("kind") != "tracked_live_scan":
    fail(f"native heap counter kind mismatch: {native_heap!r}")
if native_deltas.get("heap_bytes_used") != native_heap.get("used"):
    fail(f"native heap used delta should mirror summary budget, got {native_deltas!r} vs {native_heap!r}")
if native_deltas.get("heap_bytes_used") is None or int(native_deltas.get("heap_bytes_used")) < 0:
    fail(f"native heap used should be non-negative, got {native_deltas!r}")

obc = backends.get("obc") or {}
ledger = obc.get("ledger") or {}
if ledger.get("available") is not True:
    fail(f"OBC ledger should be available, got {ledger!r}")
if ledger.get("run_json_schema") != "avm.run.v1":
    fail(f"OBC run JSON schema mismatch: {ledger.get('run_json_schema')!r}")
if ledger.get("summary_schema") != "oren.effect-ledger-summary.v0":
    fail(f"OBC ledger summary schema mismatch: {ledger.get('summary_schema')!r}")
if not ledger.get("run_json_log") or not Path(ledger["run_json_log"]).is_file():
    fail(f"OBC run JSON log missing: {ledger.get('run_json_log')!r}")
if not ledger.get("run_json_stderr_log") or not Path(ledger["run_json_stderr_log"]).is_file():
    fail(f"OBC run JSON stderr log missing: {ledger.get('run_json_stderr_log')!r}")
if ledger.get("run_json_exit_code") != 0:
    fail(f"OBC run JSON exit mismatch: {ledger.get('run_json_exit_code')!r}")

summary = ledger.get("summary") or {}
budgets = summary.get("budgets") or {}
deltas = ledger.get("budget_deltas") or {}
obc_gas = budgets.get("gas", {})
if obc_gas.get("kind") != "avm_opcode_cost_v0":
    fail(f"OBC gas kind mismatch: {obc_gas!r}")
if (obc_gas.get("surface") or {}).get("id") != "avm_opcode_cost_v0":
    fail(f"OBC gas surface should mirror kind, got {obc_gas!r}")
obc_gas_surface = obc_gas.get("surface") or {}
if obc_gas_surface.get("unit_scope") != "avm_canonical" or obc_gas_surface.get("runtime_path_aware") is not True:
    fail(f"OBC gas summary should preserve AVM canonical runtime-path-aware metadata, got {obc_gas!r}")
if obc_gas_surface.get("cross_arch_comparable") is not True or obc_gas_surface.get("conversion_ready") is not True:
    fail(f"OBC gas summary should preserve AVM canonical conversion metadata, got {obc_gas!r}")
if obc_gas_surface.get("avm_canonical") is not True:
    fail(f"OBC gas summary should preserve avm_canonical=true, got {obc_gas!r}")
if int(deltas.get("gas_executed", 0)) <= 0:
    fail(f"expected positive OBC gas execution delta, got {deltas!r}")
if deltas.get("gas_kind") != obc_gas.get("kind"):
    fail(f"OBC gas kind delta should mirror summary budget, got {deltas!r} vs {obc_gas!r}")
if deltas.get("gas_surface_id") != "avm_opcode_cost_v0":
    fail(f"OBC gas surface delta mismatch, got {deltas!r}")
if deltas.get("gas_surface_unit_scope") != "avm_canonical" or deltas.get("gas_surface_runtime_path_aware") is not True:
    fail(f"OBC gas surface delta should preserve AVM canonical runtime-path-aware metadata, got {deltas!r}")
if deltas.get("gas_surface_cross_arch_comparable") is not True or deltas.get("gas_surface_conversion_ready") is not True:
    fail(f"OBC gas surface delta should preserve AVM canonical conversion metadata, got {deltas!r}")
if deltas.get("gas_surface_avm_canonical") is not True:
    fail(f"OBC gas surface delta should preserve avm_canonical=true, got {deltas!r}")
if deltas.get("gas_remaining") != obc_gas.get("remaining"):
    fail(f"gas remaining delta should mirror summary budget, got {deltas!r} vs {budgets!r}")
if deltas.get("heap_bytes_used") != budgets.get("heap_bytes", {}).get("used"):
    fail(f"heap used delta should mirror summary budget, got {deltas!r} vs {budgets!r}")
if deltas.get("wall_elapsed_ns") != budgets.get("wall_ms", {}).get("elapsed_ns"):
    fail(f"wall elapsed delta should mirror summary budget, got {deltas!r} vs {budgets!r}")

for name in ("c",):
    ledger = (backends.get(name) or {}).get("ledger") or {}
    if ledger.get("available") is not False:
        fail(f"{name} ledger should be unavailable for now, got {ledger!r}")
    if ledger.get("reason") != "backend run JSON ledger export is not implemented":
        fail(f"{name} ledger reason mismatch: {ledger!r}")

print(f"semantic diff report verify OK: {report}")
PY
