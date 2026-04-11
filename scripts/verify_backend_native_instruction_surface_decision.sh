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
  run_with_timeout "$build_timeout_secs" env OREN_NATIVE_GAS_ACCOUNTING=block-weighted "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug --no-cache --disasm -o "$out_native" >"$disasm_log" 2>&1
  test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$disasm_log" >&2 || true; exit 3; }

  sample_args+=("$src" "$semantic_report" "$disasm_log")
  idx=$((idx + 1))
done

python3 - "$report" "$platform" "${sample_args[@]}" <<'PY'
import json
import re
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
platform = sys.argv[2]
items = sys.argv[3:]
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
    obc_surface_id = calibration.get("obc_surface_id")
    whole_binary_instruction_count = count_disasm_instructions(disasm_log)
    if native_executed <= 0 or obc_executed <= 0:
        raise SystemExit(f"{semantic_report}: expected positive semantic gas counters, got {calibration!r}")
    if whole_binary_instruction_count <= 0:
        raise SystemExit(f"{disasm_log}: failed to count native disassembly instructions")
    samples.append(
        {
            "source": src,
            "semantic_report": semantic_report,
            "disasm_log": disasm_log,
            "native_surface_id": native_surface_id,
            "obc_surface_id": obc_surface_id,
            "native_block_weighted_executed": native_executed,
            "obc_opcode_gas_executed": obc_executed,
            "whole_binary_instruction_count": whole_binary_instruction_count,
            "whole_binary_instruction_per_obc_gas": whole_binary_instruction_count / obc_executed,
            "whole_binary_instruction_per_native_block_weighted_tick": whole_binary_instruction_count / native_executed,
        }
    )

ratios = [sample["whole_binary_instruction_per_obc_gas"] for sample in samples]
ratio_min = min(ratios)
ratio_max = max(ratios)
ratio_spread = ratio_max / ratio_min if ratio_min > 0 else None

decision = {
    "schema": "oren.native-instruction-surface-decision.v0",
    "status": "blocked",
    "reason": "whole_binary_disasm_not_runtime_path",
    "candidate_surface_id": "native_whole_binary_disasm_instruction_count_v0",
    "candidate_dynamic": False,
    "candidate_package_policy_may_convert": False,
    "required_next_surface": "native_dynamic_emitter_instruction_ticks",
    "notes": "Whole-binary native disassembly counts include linked runtime text and are not per-executed-path gas.",
}

out = {
    "schema": "oren.native-instruction-surface-decision-report.v0",
    "status": "pass",
    "platform": platform,
    "sample_count": len(samples),
    "samples": samples,
    "ratio": {
        "whole_binary_instruction_per_obc_gas_min": ratio_min,
        "whole_binary_instruction_per_obc_gas_max": ratio_max,
        "whole_binary_instruction_per_obc_gas_spread": ratio_spread,
    },
    "decision": decision,
}
out_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"native instruction surface decision report: {out_path}")
print(f"native instruction surface decision verify OK: {out_path}")
PY
