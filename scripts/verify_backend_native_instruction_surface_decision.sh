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
  echo "ERROR: native instruction-surface decision needs at least two fixtures" >&2
  exit 2
fi

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_NATIVE_INSTRUCTION_SURFACE_BUILD_TIMEOUT_SECS:-120}"

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac
platform="${arch_key}-${os_key}"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

mkdir -p build/tmp build/logs build/reports
COMPILER="${OREN_COMPILER:-./oren_stage2}"
if [[ ! -x "$COMPILER" ]]; then
  make stage2
fi

ts="$(date +%Y%m%d_%H%M%S)"
tmp_dir="build/tmp/backend_native_instruction_surface_decision_${ts}_$$"
log_prefix="build/logs/backend_native_instruction_surface_decision_${ts}_$$"
report="build/reports/backend_native_instruction_surface_decision_${ts}_$$.json"
mkdir -p "$tmp_dir"

cleanup_artifacts=1
if [[ -n "${OREN_NATIVE_INSTRUCTION_SURFACE_KEEP_ARTIFACTS:-}" ]]; then
  cleanup_artifacts=0
fi

cleanup() {
  if [[ "$cleanup_artifacts" == "1" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

sample_args=()
idx=0
for src in "${fixtures[@]}"; do
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing instruction-surface fixture: $src" >&2
    exit 2
  fi

  echo "== native instruction-surface fixture: $src ==" >&2
  set +e
  runner_output="$(./scripts/verify_backend_semantic_diff.sh "$src" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$runner_output"
  if [[ "$rc" != "0" ]]; then
    exit "$rc"
  fi

  semantic_report="$(printf '%s\n' "$runner_output" | sed -n 's/^semantic diff report: //p' | tail -n 1)"
  if [[ -z "$semantic_report" || ! -f "$semantic_report" ]]; then
    echo "ERROR: semantic diff report path missing for $src" >&2
    exit 1
  fi

  safe_base="$(basename "$src" .oren | tr -c 'A-Za-z0-9_-' '_')"
  out_native="${tmp_dir}/${idx}_${safe_base}_native${exe_ext}"
  disasm_log="${log_prefix}_${idx}_${safe_base}.disasm.log"

  echo "== native whole-binary disasm: $src ==" >&2
  run_with_timeout "$build_timeout_secs" env OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug --no-cache --disasm -o "$out_native" >"$disasm_log" 2>&1
  test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$disasm_log" >&2 || true; exit 3; }

  sample_args+=("$src" "$semantic_report" "$disasm_log")
  idx=$((idx + 1))
done

python3 - "$report" "$platform" "$default_fixture_set" "${sample_args[@]}" <<'PY'
import json
import re
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
platform = sys.argv[2]
default_fixture_set = sys.argv[3] == "1"
items = sys.argv[4:]
if len(items) % 3 != 0:
    raise SystemExit("expected source/report/disasm triples")

def count_disasm_instructions(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    count = 0
    for line in text.splitlines():
        # otool -tV: "0000000100000800\tmov\tx19, x0"
        if re.match(r"^\s*[0-9a-fA-F]{8,16}\s+[A-Za-z_.][A-Za-z0-9_.]*\b", line):
            count += 1
            continue
        # objdump -d: "  401000:\t48 89 e5\tmov %rsp,%rbp"
        if re.match(r"^\s*[0-9a-fA-F]+:\s+(?:[0-9a-fA-F]{2}\s+)+\s*[A-Za-z_.][A-Za-z0-9_.]*\b", line):
            count += 1
            continue
    return count

samples = []
for i in range(0, len(items), 3):
    src, semantic_report, disasm_log = items[i : i + 3]
    data = json.loads(Path(semantic_report).read_text(encoding="utf-8"))
    if data.get("schema") != "oren.semantic-diff.v0":
        raise SystemExit(f"{semantic_report}: semantic diff schema mismatch: {data.get('schema')!r}")
    if data.get("status") != "pass":
        raise SystemExit(f"{semantic_report}: semantic diff status mismatch: {data.get('status')!r}")
    calibration = data.get("gas_surface_calibration") or {}
    native_executed = int(calibration.get("native_executed") or 0)
    obc_executed = int(calibration.get("obc_executed") or 0)
    native_surface_id = calibration.get("native_surface_id")
    sample_class = calibration.get("source_class") or "custom"
    if sample_class not in ("smoke", "loop_heavy", "branch_heavy", "call_heavy", "alloc_heavy", "custom"):
        raise SystemExit(f"{semantic_report}: expected calibration source_class metadata, got {calibration!r}")
    native_surface_target_arch = calibration.get("native_surface_target_arch")
    native_surface_unit_family = calibration.get("native_surface_unit_family")
    obc_surface_id = calibration.get("obc_surface_id")
    obc_surface_unit_scope = calibration.get("obc_surface_unit_scope")
    obc_surface_conversion_ready = calibration.get("obc_surface_conversion_ready")
    obc_surface_avm_canonical = calibration.get("obc_surface_avm_canonical")
    whole_binary_instruction_count = count_disasm_instructions(disasm_log)
    if native_executed <= 0 or obc_executed <= 0:
        raise SystemExit(f"{semantic_report}: expected positive semantic gas counters, got {calibration!r}")
    if native_surface_id != "native_dynamic_emitter_tick_v0":
        raise SystemExit(f"{semantic_report}: expected dynamic-emitter native gas surface, got {native_surface_id!r}")
    if native_surface_target_arch not in ("arm64", "x64"):
        raise SystemExit(f"{semantic_report}: expected native dynamic-emitter target_arch metadata, got {calibration!r}")
    expected_unit_family = "fixed_width_instruction_span" if native_surface_target_arch == "arm64" else "emitted_byte_span"
    if native_surface_unit_family != expected_unit_family:
        raise SystemExit(
            f"{semantic_report}: expected native dynamic-emitter unit_family {expected_unit_family!r}, got {calibration!r}"
        )
    if obc_surface_id != "avm_opcode_cost_v0":
        raise SystemExit(f"{semantic_report}: expected AVM opcode gas surface, got {obc_surface_id!r}")
    if obc_surface_unit_scope != "avm_canonical" or obc_surface_conversion_ready is not True:
        raise SystemExit(f"{semantic_report}: expected AVM canonical conversion-ready gas metadata, got {calibration!r}")
    if obc_surface_avm_canonical is not True:
        raise SystemExit(f"{semantic_report}: expected avm_canonical=true in OBC gas metadata, got {calibration!r}")
    if whole_binary_instruction_count <= 0:
        raise SystemExit(f"{disasm_log}: failed to count native disassembly instructions")
    samples.append(
        {
            "source": src,
            "source_class": sample_class,
            "semantic_report": semantic_report,
            "disasm_log": disasm_log,
            "native_surface_id": native_surface_id,
            "native_surface_target_arch": native_surface_target_arch,
            "native_surface_unit_family": native_surface_unit_family,
            "obc_surface_id": obc_surface_id,
            "obc_surface_unit_scope": obc_surface_unit_scope,
            "obc_surface_conversion_ready": obc_surface_conversion_ready,
            "obc_surface_avm_canonical": obc_surface_avm_canonical,
            "native_dynamic_emitter_executed": native_executed,
            "obc_opcode_gas_executed": obc_executed,
            "whole_binary_instruction_count": whole_binary_instruction_count,
            "whole_binary_instruction_per_obc_gas": whole_binary_instruction_count / obc_executed,
            "whole_binary_instruction_per_native_dynamic_emitter_tick": whole_binary_instruction_count / native_executed,
        }
    )

whole_binary_ratios = [sample["whole_binary_instruction_per_obc_gas"] for sample in samples]
whole_binary_counts = [sample["whole_binary_instruction_count"] for sample in samples]
sample_classes = sorted({sample["source_class"] for sample in samples})
required_sample_classes = ["alloc_heavy", "branch_heavy", "call_heavy", "loop_heavy", "smoke"] if default_fixture_set else []
if default_fixture_set:
    missing = sorted(set(required_sample_classes) - set(sample_classes))
    if missing:
        raise SystemExit(f"default native instruction-surface decision missing sample classes: {missing!r}")
runtime_ratios = [
    sample["native_dynamic_emitter_executed"] / sample["obc_opcode_gas_executed"]
    for sample in samples
]
ratio_min = min(whole_binary_ratios)
ratio_max = max(whole_binary_ratios)
ratio_spread = ratio_max / ratio_min if ratio_min > 0 else None
runtime_ratio_min = min(runtime_ratios)
runtime_ratio_max = max(runtime_ratios)
runtime_ratio_spread = runtime_ratio_max / runtime_ratio_min if runtime_ratio_min > 0 else None
count_min = min(whole_binary_counts)
count_max = max(whole_binary_counts)
count_spread = count_max / count_min if count_min > 0 else None

decision = {
    "schema": "oren.native-instruction-surface-decision.v0",
    "status": "blocked",
    "reason": "whole_binary_disasm_not_runtime_path",
    "candidate_surface_id": "native_whole_binary_disasm_instruction_count_v0",
    "candidate_dynamic": False,
    "candidate_package_policy_may_convert": False,
    "observed_runtime_surface_id": "native_dynamic_emitter_tick_v0",
    "observed_runtime_surface_dynamic": True,
    "observed_runtime_surface_target_arch": samples[0]["native_surface_target_arch"],
    "observed_runtime_surface_unit_family": samples[0]["native_surface_unit_family"],
    "observed_obc_surface_id": "avm_opcode_cost_v0",
    "observed_obc_surface_unit_scope": "avm_canonical",
    "observed_obc_surface_conversion_ready": True,
    "observed_obc_surface_avm_canonical": True,
    "required_next_surface": "validated_native_dynamic_emitter_or_instruction_equivalent_gas",
    "required_sample_classes": required_sample_classes,
    "observed_sample_classes": sample_classes,
    "sample_class_coverage_ok": (not default_fixture_set) or set(required_sample_classes).issubset(set(sample_classes)),
    "notes": "Whole-binary native disassembly counts include linked runtime text and are not per-executed-path gas; runtime dynamic-emitter ticks are path-aware evidence but are not yet a conversion contract.",
}

out = {
    "schema": "oren.native-instruction-surface-decision-report.v0",
    "status": "pass",
    "platform": platform,
    "sample_count": len(samples),
    "required_sample_classes": required_sample_classes,
    "observed_sample_classes": sample_classes,
    "samples": samples,
    "ratio": {
        "whole_binary_instruction_count_min": count_min,
        "whole_binary_instruction_count_max": count_max,
        "whole_binary_instruction_count_spread": count_spread,
        "whole_binary_instruction_per_obc_gas_min": ratio_min,
        "whole_binary_instruction_per_obc_gas_max": ratio_max,
        "whole_binary_instruction_per_obc_gas_spread": ratio_spread,
        "native_dynamic_emitter_per_obc_gas_min": runtime_ratio_min,
        "native_dynamic_emitter_per_obc_gas_max": runtime_ratio_max,
        "native_dynamic_emitter_per_obc_gas_spread": runtime_ratio_spread,
    },
    "decision": decision,
}
out_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"native instruction surface decision report: {out_path}")
print(f"native instruction surface decision verify OK: {out_path}")
PY
