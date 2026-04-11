#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$#" == "0" ]]; then
  fixtures=(
    "tests/fixtures/backend_semantic_diff_smoke.oren"
    "tests/fixtures/backend_semantic_diff_gas_calibration.oren"
    "tests/fixtures/backend_semantic_diff_gas_branch_calibration.oren"
  )
else
  fixtures=("$@")
fi

if [[ "${#fixtures[@]}" -lt 2 ]]; then
  echo "ERROR: gas surface calibration set needs at least two fixtures" >&2
  exit 2
fi

mkdir -p build/reports
ts="$(date +%Y%m%d_%H%M%S)"
set_report="build/reports/backend_gas_surface_calibration_set_${ts}_$$.json"
reports=()

for src in "${fixtures[@]}"; do
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing calibration fixture: $src" >&2
    exit 2
  fi

  echo "== gas surface calibration fixture: $src ==" >&2
  set +e
  runner_output="$(./scripts/verify_backend_semantic_diff.sh "$src" 2>&1)"
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

python3 - "$set_report" "${reports[@]}" <<'PY'
import json
import os
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
report_paths = [Path(p) for p in sys.argv[2:]]

min_spread = float(os.environ.get("OREN_GAS_SURFACE_CALIBRATION_MIN_SPREAD", "1.10"))
if len(report_paths) < 2:
    raise SystemExit("gas surface calibration set needs at least two reports")

samples = []
native_surface_id = None
obc_surface_id = None

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

    cur_native_surface = calibration.get("native_surface_id")
    cur_obc_surface = calibration.get("obc_surface_id")
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

    native_executed = int(calibration.get("native_executed") or 0)
    obc_executed = int(calibration.get("obc_executed") or 0)
    native_per_obc = float(calibration.get("native_per_obc") or 0.0)
    obc_per_native = float(calibration.get("obc_per_native") or 0.0)
    if native_executed <= 0 or obc_executed <= 0:
        raise SystemExit(f"{path}: expected positive gas counters, got {calibration!r}")
    if native_per_obc <= 0.0 or obc_per_native <= 0.0:
        raise SystemExit(f"{path}: expected positive ratios, got {calibration!r}")

    samples.append(
        {
            "source": calibration.get("source") or data.get("source"),
            "report": str(path),
            "native_surface_id": cur_native_surface,
            "obc_surface_id": cur_obc_surface,
            "native_executed": native_executed,
            "obc_executed": obc_executed,
            "native_per_obc": native_per_obc,
            "obc_per_native": obc_per_native,
            "not_a_conversion": True,
            "reason": calibration.get("reason"),
        }
    )

ratios = [sample["native_per_obc"] for sample in samples]
ratio_min = min(ratios)
ratio_max = max(ratios)
ratio_spread = ratio_max / ratio_min if ratio_min > 0.0 else None
single_ratio_unsafe = ratio_spread is not None and ratio_spread >= min_spread
status = "pass" if single_ratio_unsafe else "fail"
conversion_decision = {
    "schema": "oren.gas-surface-conversion-decision.v0",
    "status": "blocked",
    "reason": "single_ratio_unsafe" if single_ratio_unsafe else "insufficient_ratio_spread_evidence",
    "native_surface_id": native_surface_id,
    "obc_surface_id": obc_surface_id,
    "comparable": False,
    "not_a_conversion": True,
    "forbidden_policy": "single_fixture_ratio",
    "required_next_surface": "native_instruction_equivalent_or_block_weighted_gas",
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
    },
    "sample_count": len(samples),
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
