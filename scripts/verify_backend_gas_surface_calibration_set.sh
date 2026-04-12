#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$#" == "0" ]]; then
  default_fixture_set=1
    fixtures=(
      "tests/fixtures/backend_semantic_diff_smoke.oren"
      "tests/fixtures/backend_semantic_diff_gas_calibration.oren"
      "tests/fixtures/backend_semantic_diff_gas_branch_calibration.oren"
      "tests/fixtures/backend_semantic_diff_gas_call_calibration.oren"
      "tests/fixtures/backend_semantic_diff_gas_alloc_calibration.oren"
    )
else
  default_fixture_set=0
  fixtures=("$@")
fi

if [[ "${#fixtures[@]}" -lt 2 ]]; then
  echo "ERROR: gas surface calibration set needs at least two fixtures" >&2
  exit 2
fi

mkdir -p build/reports
ts="$(date +%Y%m%d_%H%M%S)"
set_report="build/reports/backend_gas_surface_calibration_set_${ts}_$$.json"
semantic_run_timeout_secs="${OREN_GAS_SURFACE_CALIBRATION_SEMANTIC_RUN_TIMEOUT_SECS:-20}"
reports=()

for src in "${fixtures[@]}"; do
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing calibration fixture: $src" >&2
    exit 2
  fi

  echo "== gas surface calibration fixture: $src ==" >&2
  set +e
  runner_output="$(env OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS="${OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS:-$semantic_run_timeout_secs}" ./scripts/verify_backend_semantic_diff.sh "$src" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$runner_output"
  if [[ "$rc" != "0" ]]; then
    exit "$rc"
  fi

  report="$(printf '%s\n' "$runner_output" | sed -n 's/^semantic diff report: //p' | tail -n 1)"
  if [[ -z "$report" || ! -f "$report" ]]; then
    echo "ERROR: semantic diff report path missing for $src" >&2
    exit 1
  fi
  reports+=("$report")
done

python3 - "$set_report" "$default_fixture_set" "${reports[@]}" <<'PY'
import json
import os
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
default_fixture_set = sys.argv[2] == "1"
report_paths = [Path(p) for p in sys.argv[3:]]

min_spread = float(os.environ.get("OREN_GAS_SURFACE_CALIBRATION_MIN_SPREAD", "1.10"))
if len(report_paths) < 2:
    raise SystemExit("gas surface calibration set needs at least two reports")

samples = []
native_surface_id = None
obc_surface_id = None
native_target_arch = None
native_unit_family = None
required_next_surface = "native_instruction_equivalent_or_package_bound_avm_canonical_sidecar_gas"

def valid_sha256(value):
    return isinstance(value, str) and len(value) == 64

for path in report_paths:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != "oren.semantic-diff.v0":
        raise SystemExit(f"{path}: semantic diff schema mismatch: {data.get('schema')!r}")
    if data.get("status") != "pass":
        raise SystemExit(f"{path}: semantic diff status mismatch: {data.get('status')!r}")

    calibration = data.get("gas_surface_calibration") or {}
    if calibration.get("schema") != "oren.gas-surface-calibration.v0":
        raise SystemExit(f"{path}: calibration schema mismatch: {calibration!r}")
    if calibration.get("mode") != "empirical_single_fixture":
        raise SystemExit(f"{path}: calibration mode mismatch: {calibration!r}")
    if calibration.get("comparable") is not False or calibration.get("not_a_conversion") is not True:
        raise SystemExit(f"{path}: calibration must remain evidence, not conversion: {calibration!r}")
    sidecar = data.get("avm_canonical_sidecar_gas") or {}
    if sidecar.get("schema") != "oren.avm-canonical-sidecar-gas.v0" or sidecar.get("status") != "available":
        raise SystemExit(f"{path}: missing AVM canonical sidecar gas evidence: {sidecar!r}")
    sidecar_surface = sidecar.get("gas_surface") or {}
    if sidecar_surface.get("id") != "avm_opcode_cost_v0" or sidecar_surface.get("unit_scope") != "avm_canonical":
        raise SystemExit(f"{path}: AVM canonical sidecar gas surface mismatch: {sidecar!r}")
    if sidecar_surface.get("conversion_ready") is not True or sidecar_surface.get("avm_canonical") is not True:
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve canonical metadata: {sidecar!r}")
    if sidecar.get("same_source") is not True or sidecar.get("native_runtime_conversion") is not False:
        raise SystemExit(f"{path}: sidecar must stay same-source evidence, not native conversion: {sidecar!r}")
    if sidecar.get("package_policy_may_use") is not False:
        raise SystemExit(f"{path}: semantic-diff sidecar is not package-policy binding yet: {sidecar!r}")
    if sidecar.get("policy_scope") != "semantic_diff_same_source_fixture":
        raise SystemExit(f"{path}: AVM canonical sidecar policy scope mismatch: {sidecar!r}")
    if sidecar.get("same_run_stderr_equal") is not True:
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve semantic-diff stderr parity evidence: {sidecar!r}")
    if sidecar.get("same_run_exit_code_equal") is not True:
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve semantic-diff exit-code parity evidence: {sidecar!r}")
    if sidecar.get("native_exit_code") != 0 or sidecar.get("sidecar_exit_code") != 0:
        raise SystemExit(f"{path}: AVM canonical sidecar should expose zero native/sidecar exits: {sidecar!r}")
    if sidecar.get("certification_warnings") != []:
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve warning-free semantic-diff evidence: {sidecar!r}")
    if sidecar.get("test_injection") is not None:
        raise SystemExit(f"{path}: semantic-diff sidecar should not carry verifier test injection: {sidecar!r}")
    if not valid_sha256(sidecar.get("source_sha256")):
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve source identity hash: {sidecar!r}")
    if not sidecar.get("native_artifact") or not valid_sha256(sidecar.get("native_artifact_sha256")):
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve native artifact identity hash: {sidecar!r}")
    if not sidecar.get("sidecar_artifact") or not valid_sha256(sidecar.get("sidecar_artifact_sha256")):
        raise SystemExit(f"{path}: AVM canonical sidecar should preserve sidecar artifact identity hash: {sidecar!r}")
    if sidecar.get("program_args") != [] or not valid_sha256(sidecar.get("program_args_sha256")):
        raise SystemExit(f"{path}: semantic-diff AVM canonical sidecar should preserve empty program-args binding: {sidecar!r}")
    if sidecar.get("package_policy_sha256") is not None or sidecar.get("package_policy_declared") is not False:
        raise SystemExit(f"{path}: semantic-diff AVM canonical sidecar should not claim package-policy binding: {sidecar!r}")

    cur_native_surface = calibration.get("native_surface_id")
    cur_obc_surface = calibration.get("obc_surface_id")
    cur_sample_class = calibration.get("source_class") or "custom"
    if cur_native_surface != "native_dynamic_emitter_tick_v0":
        raise SystemExit(f"{path}: expected native dynamic-emitter calibration surface, got {calibration!r}")
    if cur_obc_surface != "avm_opcode_cost_v0":
        raise SystemExit(f"{path}: expected AVM opcode gas calibration surface, got {calibration!r}")
    if cur_sample_class not in ("smoke", "loop_heavy", "branch_heavy", "call_heavy", "alloc_heavy", "custom"):
        raise SystemExit(f"{path}: calibration source_class mismatch: {calibration!r}")
    if native_surface_id is None:
        native_surface_id = cur_native_surface
    if obc_surface_id is None:
        obc_surface_id = cur_obc_surface
    if cur_native_surface != native_surface_id:
        raise SystemExit(
            f"{path}: native gas surface mismatch: {cur_native_surface!r} != {native_surface_id!r}"
        )
    if cur_obc_surface != obc_surface_id:
        raise SystemExit(
            f"{path}: OBC gas surface mismatch: {cur_obc_surface!r} != {obc_surface_id!r}"
        )
    cur_native_unit_scope = calibration.get("native_surface_unit_scope")
    cur_native_target_arch = calibration.get("native_surface_target_arch")
    cur_native_unit_family = calibration.get("native_surface_unit_family")
    cur_native_runtime_path_aware = calibration.get("native_surface_runtime_path_aware")
    cur_native_cross_arch_comparable = calibration.get("native_surface_cross_arch_comparable")
    cur_native_conversion_ready = calibration.get("native_surface_conversion_ready")
    cur_obc_unit_scope = calibration.get("obc_surface_unit_scope")
    cur_obc_runtime_path_aware = calibration.get("obc_surface_runtime_path_aware")
    cur_obc_cross_arch_comparable = calibration.get("obc_surface_cross_arch_comparable")
    cur_obc_conversion_ready = calibration.get("obc_surface_conversion_ready")
    cur_obc_avm_canonical = calibration.get("obc_surface_avm_canonical")
    if cur_native_unit_scope != "backend_local" or cur_native_runtime_path_aware is not True:
        raise SystemExit(
            f"{path}: native dynamic-emitter calibration should be backend-local runtime-path-aware evidence: {calibration!r}"
        )
    if cur_native_target_arch not in ("arm64", "x64"):
        raise SystemExit(f"{path}: native dynamic-emitter calibration should declare target_arch: {calibration!r}")
    expected_unit_family = "fixed_width_instruction_span" if cur_native_target_arch == "arm64" else "emitted_byte_span"
    if cur_native_unit_family != expected_unit_family:
        raise SystemExit(
            f"{path}: native dynamic-emitter unit_family mismatch, expected {expected_unit_family!r}: {calibration!r}"
        )
    if native_target_arch is None:
        native_target_arch = cur_native_target_arch
    if native_unit_family is None:
        native_unit_family = cur_native_unit_family
    if cur_native_target_arch != native_target_arch:
        raise SystemExit(
            f"{path}: native dynamic-emitter target_arch mismatch: {cur_native_target_arch!r} != {native_target_arch!r}"
        )
    if cur_native_unit_family != native_unit_family:
        raise SystemExit(
            f"{path}: native dynamic-emitter unit_family mismatch: {cur_native_unit_family!r} != {native_unit_family!r}"
        )
    if cur_native_cross_arch_comparable is not False or cur_native_conversion_ready is not False:
        raise SystemExit(
            f"{path}: native dynamic-emitter calibration must remain non-conversion-ready: {calibration!r}"
        )
    if cur_obc_unit_scope != "avm_canonical" or cur_obc_runtime_path_aware is not True:
        raise SystemExit(f"{path}: OBC calibration should preserve AVM canonical runtime-path-aware metadata: {calibration!r}")
    if cur_obc_cross_arch_comparable is not True or cur_obc_conversion_ready is not True:
        raise SystemExit(f"{path}: OBC calibration should preserve AVM canonical conversion metadata: {calibration!r}")
    if cur_obc_avm_canonical is not True:
        raise SystemExit(f"{path}: OBC calibration should preserve avm_canonical=true: {calibration!r}")

    native_executed = int(calibration.get("native_executed") or 0)
    obc_executed = int(calibration.get("obc_executed") or 0)
    native_per_obc = float(calibration.get("native_per_obc") or 0.0)
    obc_per_native = float(calibration.get("obc_per_native") or 0.0)
    if native_executed <= 0 or obc_executed <= 0:
        raise SystemExit(f"{path}: expected positive gas counters, got {calibration!r}")
    if int(sidecar.get("gas_executed") or 0) != obc_executed:
        raise SystemExit(f"{path}: AVM sidecar gas must mirror OBC canonical gas, got {sidecar!r} vs {calibration!r}")
    if native_per_obc <= 0.0 or obc_per_native <= 0.0:
        raise SystemExit(f"{path}: expected positive ratios, got {calibration!r}")

    samples.append(
        {
            "source": calibration.get("source") or data.get("source"),
            "source_class": cur_sample_class,
            "report": str(path),
            "native_surface_id": cur_native_surface,
            "native_surface_unit_scope": cur_native_unit_scope,
            "native_surface_target_arch": cur_native_target_arch,
            "native_surface_unit_family": cur_native_unit_family,
            "native_surface_runtime_path_aware": cur_native_runtime_path_aware,
            "native_surface_cross_arch_comparable": cur_native_cross_arch_comparable,
            "native_surface_conversion_ready": cur_native_conversion_ready,
            "obc_surface_id": cur_obc_surface,
            "obc_surface_unit_scope": cur_obc_unit_scope,
            "obc_surface_runtime_path_aware": cur_obc_runtime_path_aware,
            "obc_surface_cross_arch_comparable": cur_obc_cross_arch_comparable,
            "obc_surface_conversion_ready": cur_obc_conversion_ready,
            "obc_surface_avm_canonical": cur_obc_avm_canonical,
            "avm_canonical_sidecar_available": True,
            "avm_canonical_sidecar_gas_executed": int(sidecar.get("gas_executed") or 0),
            "avm_canonical_sidecar_policy_scope": sidecar.get("policy_scope"),
            "avm_canonical_sidecar_package_policy_may_use": sidecar.get("package_policy_may_use"),
            "avm_canonical_sidecar_stderr_equal": sidecar.get("same_run_stderr_equal"),
            "avm_canonical_sidecar_exit_code_equal": sidecar.get("same_run_exit_code_equal"),
            "avm_canonical_sidecar_native_exit_code": sidecar.get("native_exit_code"),
            "avm_canonical_sidecar_sidecar_exit_code": sidecar.get("sidecar_exit_code"),
            "avm_canonical_sidecar_certification_warnings": sidecar.get("certification_warnings"),
            "avm_canonical_sidecar_test_injection": sidecar.get("test_injection"),
            "avm_canonical_sidecar_source_sha256": sidecar.get("source_sha256"),
            "avm_canonical_sidecar_native_artifact": sidecar.get("native_artifact"),
            "avm_canonical_sidecar_native_artifact_sha256": sidecar.get("native_artifact_sha256"),
            "avm_canonical_sidecar_sidecar_artifact": sidecar.get("sidecar_artifact"),
            "avm_canonical_sidecar_sidecar_artifact_sha256": sidecar.get("sidecar_artifact_sha256"),
            "avm_canonical_sidecar_identity_hashes_present": True,
            "avm_canonical_sidecar_program_args": sidecar.get("program_args"),
            "avm_canonical_sidecar_program_args_sha256": sidecar.get("program_args_sha256"),
            "avm_canonical_sidecar_package_policy_sha256": sidecar.get("package_policy_sha256"),
            "avm_canonical_sidecar_package_policy_declared": sidecar.get("package_policy_declared"),
            "avm_canonical_sidecar_input_binding_present": True,
            "native_executed": native_executed,
            "obc_executed": obc_executed,
            "native_per_obc": native_per_obc,
            "obc_per_native": obc_per_native,
            "not_a_conversion": True,
            "reason": calibration.get("reason"),
        }
    )

ratios = [sample["native_per_obc"] for sample in samples]
sample_classes = sorted({sample["source_class"] for sample in samples})
required_sample_classes = ["alloc_heavy", "branch_heavy", "call_heavy", "loop_heavy", "smoke"] if default_fixture_set else []
if default_fixture_set:
    missing = sorted(set(required_sample_classes) - set(sample_classes))
    if missing:
        raise SystemExit(f"default gas calibration set missing sample classes: {missing!r}")
ratio_min = min(ratios)
ratio_max = max(ratios)
ratio_spread = ratio_max / ratio_min if ratio_min > 0.0 else None
single_ratio_unsafe = ratio_spread is not None and ratio_spread >= min_spread
status = "pass" if single_ratio_unsafe else "fail"
surface_metadata_blocks_conversion = any(
    sample["native_surface_unit_scope"] == "backend_local"
    or sample["native_surface_target_arch"] in ("arm64", "x64")
    or sample["native_surface_cross_arch_comparable"] is False
    or sample["native_surface_conversion_ready"] is False
    for sample in samples
)
if surface_metadata_blocks_conversion is not True:
    raise SystemExit("native dynamic-emitter surface metadata should block gas conversion")
conversion_decision = {
    "schema": "oren.gas-surface-conversion-decision.v0",
    "status": "blocked",
    "reason": "single_ratio_unsafe" if single_ratio_unsafe else "insufficient_ratio_spread_evidence",
    "native_surface_id": native_surface_id,
    "obc_surface_id": obc_surface_id,
    "comparable": False,
    "not_a_conversion": True,
    "surface_metadata_blocks_conversion": surface_metadata_blocks_conversion,
    "native_surface_conversion_ready": False,
    "obc_surface_unit_scope": "avm_canonical",
    "obc_surface_runtime_path_aware": True,
    "obc_surface_cross_arch_comparable": True,
    "obc_surface_conversion_ready": True,
    "obc_surface_avm_canonical": True,
    "avm_canonical_sidecar_available": all(sample["avm_canonical_sidecar_available"] for sample in samples),
    "package_policy_may_use_avm_sidecar": False,
    "avm_canonical_sidecar_stderr_equal_all": all(sample["avm_canonical_sidecar_stderr_equal"] for sample in samples),
    "avm_canonical_sidecar_exit_code_equal_all": all(sample["avm_canonical_sidecar_exit_code_equal"] for sample in samples),
    "avm_canonical_sidecar_warning_free": all(not sample["avm_canonical_sidecar_certification_warnings"] for sample in samples),
    "avm_canonical_sidecar_test_injection_free": all(sample["avm_canonical_sidecar_test_injection"] is None for sample in samples),
    "avm_canonical_sidecar_identity_hashes_present_all": all(
        sample["avm_canonical_sidecar_identity_hashes_present"] for sample in samples
    ),
    "avm_canonical_sidecar_input_binding_present_all": all(
        sample["avm_canonical_sidecar_input_binding_present"] for sample in samples
    ),
    "forbidden_policy": "single_fixture_ratio",
    "required_next_surface": required_next_surface,
    "required_sample_classes": required_sample_classes,
    "observed_sample_classes": sample_classes,
    "sample_class_coverage_ok": (not default_fixture_set) or set(required_sample_classes).issubset(set(sample_classes)),
    "package_policy_may_convert": False,
}

out = {
    "schema": "oren.gas-surface-calibration-set.v0",
    "status": status,
    "surface_pair": {
        "native": native_surface_id,
        "obc": obc_surface_id,
        "comparable": False,
        "not_a_conversion": True,
        "native_surface_unit_scope": "backend_local",
        "native_surface_target_arch": native_target_arch,
        "native_surface_unit_family": native_unit_family,
        "native_surface_runtime_path_aware": True,
        "native_surface_cross_arch_comparable": False,
        "native_surface_conversion_ready": False,
        "obc_surface_unit_scope": "avm_canonical",
        "obc_surface_runtime_path_aware": True,
        "obc_surface_cross_arch_comparable": True,
        "obc_surface_conversion_ready": True,
        "obc_surface_avm_canonical": True,
        "avm_canonical_sidecar_available": all(sample["avm_canonical_sidecar_available"] for sample in samples),
        "package_policy_may_use_avm_sidecar": False,
        "avm_canonical_sidecar_stderr_equal_all": all(sample["avm_canonical_sidecar_stderr_equal"] for sample in samples),
        "avm_canonical_sidecar_warning_free": all(not sample["avm_canonical_sidecar_certification_warnings"] for sample in samples),
        "avm_canonical_sidecar_test_injection_free": all(sample["avm_canonical_sidecar_test_injection"] is None for sample in samples),
        "avm_canonical_sidecar_identity_hashes_present_all": all(
            sample["avm_canonical_sidecar_identity_hashes_present"] for sample in samples
        ),
        "avm_canonical_sidecar_input_binding_present_all": all(
            sample["avm_canonical_sidecar_input_binding_present"] for sample in samples
        ),
    },
    "sample_count": len(samples),
    "required_sample_classes": required_sample_classes,
    "observed_sample_classes": sample_classes,
    "samples": samples,
    "ratio": {
        "native_per_obc_min": ratio_min,
        "native_per_obc_max": ratio_max,
        "native_per_obc_spread": ratio_spread,
        "min_required_spread": min_spread,
        "single_ratio_unsafe": single_ratio_unsafe,
    },
    "conversion_decision": conversion_decision,
}

out_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"gas surface calibration set report: {out_path}")
if status != "pass":
    raise SystemExit(
        f"{out_path}: native/OBC gas ratio spread {ratio_spread!r} is below required {min_spread}; "
        "revisit the calibration-set fixtures or conversion contract"
    )
print(f"gas surface calibration set verify OK: {out_path}")
PY
