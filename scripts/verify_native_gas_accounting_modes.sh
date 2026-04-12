#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

src="${OREN_NATIVE_GAS_ACCOUNTING_MODES_SRC:-tests/fixtures/native_gas_accounting_modes.oren}"
if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

mkdir -p build/tmp build/logs

COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$COMPILER" ]]; then
  make oren
fi

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_NATIVE_GAS_MODE_BUILD_TIMEOUT_SECS:-120}"
run_timeout_secs="${OREN_NATIVE_GAS_MODE_RUN_TIMEOUT_SECS:-10}"

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

ts="$(date +%Y%m%d_%H%M%S)"
prefix="native_gas_accounting_modes_${ts}_$$"
tmp_prefix="build/tmp/${prefix}"
log_prefix="build/logs/${prefix}"
cases_file="${tmp_prefix}_cases.jsonl"
cleanup_artifacts=1
if [[ -n "${OREN_NATIVE_GAS_ACCOUNTING_MODES_KEEP_ARTIFACTS:-}" ]]; then
  cleanup_artifacts=0
fi

cleanup() {
  if [[ "$cleanup_artifacts" == "1" ]]; then
    rm -f "${tmp_prefix}"_*"${exe_ext}" "$cases_file"
  fi
}
trap cleanup EXIT

run_case() {
  local name="$1"
  local mode="$2"
  local expected_kind="$3"
  local require_positive="$4"
  local out="${tmp_prefix}_${name}${exe_ext}"
  local build_log="${log_prefix}_${name}_build.log"
  local stdout_log="${log_prefix}_${name}.stdout"
  local stderr_log="${log_prefix}_${name}.stderr"

  echo "== native gas accounting mode: $name ==" >&2
  if [[ -n "$mode" ]]; then
    run_with_timeout "$build_timeout_secs" env OREN_NATIVE_GAS_ACCOUNTING="$mode" "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug --no-cache -o "$out" >"$build_log" 2>&1
  else
    run_with_timeout "$build_timeout_secs" env -u OREN_NATIVE_GAS_ACCOUNTING "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug --no-cache -o "$out" >"$build_log" 2>&1
  fi
  test -f "$out" || { echo "FAIL: missing $out" >&2; tail -n 120 "$build_log" >&2 || true; exit 3; }

  if [[ -n "$mode" ]]; then
    run_with_timeout "$run_timeout_secs" env OREN_NATIVE_RUN_JSON=1 OREN_NATIVE_GAS_ACCOUNTING="$mode" "$out" >"$stdout_log" 2>"$stderr_log"
  else
    run_with_timeout "$run_timeout_secs" env -u OREN_NATIVE_GAS_ACCOUNTING OREN_NATIVE_RUN_JSON=1 "$out" >"$stdout_log" 2>"$stderr_log"
  fi

  python3 - "$name" "$mode" "$expected_kind" "$require_positive" "$stdout_log" "$stderr_log" <<'PY' >>"$cases_file"
import json
import sys
from pathlib import Path

name, mode, expected_kind, require_positive_s, stdout_log, stderr_log = sys.argv[1:]
require_positive = require_positive_s == "1"
text = Path(stdout_log).read_text(encoding="utf-8", errors="replace")
run_json = None
for line in reversed(text.splitlines()):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        run_json = json.loads(line)
        break
    except json.JSONDecodeError:
        continue
if not isinstance(run_json, dict):
    raise SystemExit(f"{stdout_log}: missing native run JSON for {name}")
if run_json.get("schema") != "oren.native-run.v0":
    raise SystemExit(f"{stdout_log}: schema mismatch for {name}: {run_json.get('schema')!r}")
summary = run_json.get("effect_ledger_summary") or {}
budgets = summary.get("budgets") or {}
gas = budgets.get("gas") or {}
surface = gas.get("surface") or {}
executed = gas.get("executed")
if gas.get("kind") != expected_kind:
    raise SystemExit(f"{stdout_log}: {name} expected gas kind {expected_kind}, got {gas!r}")
if surface.get("schema") != "oren.gas-surface.v0" or surface.get("id") != expected_kind:
    raise SystemExit(f"{stdout_log}: {name} expected gas surface {expected_kind}, got {gas!r}")
if name == "dynamic_emitter":
    if surface.get("unit_scope") != "backend_local" or surface.get("runtime_path_aware") is not True:
        raise SystemExit(f"{stdout_log}: dynamic-emitter gas surface should be backend-local runtime-path-aware evidence, got {surface!r}")
    if surface.get("cross_arch_comparable") is not False or surface.get("conversion_ready") is not False:
        raise SystemExit(f"{stdout_log}: dynamic-emitter gas surface must stay non-conversion-ready, got {surface!r}")
if require_positive and int(executed or 0) <= 0:
    raise SystemExit(f"{stdout_log}: {name} expected positive gas execution, got {gas!r}")
print(json.dumps({
    "name": name,
    "mode": mode if mode else "unset",
    "kind": gas.get("kind"),
    "surface_id": surface.get("id"),
    "executed": executed,
    "stdout_log": stdout_log,
    "stderr_log": stderr_log,
}, sort_keys=True))
PY
}

run_case "default" "" "native_loop_safepoint_tick_v0" "0"
run_case "stmt" "stmt" "native_stmt_loop_tick_v0" "1"
run_case "statement" "statement" "native_stmt_loop_tick_v0" "1"
run_case "basic_block" "basic-block" "native_basic_block_tick_v0" "1"
run_case "block_weighted" "block-weighted" "native_block_weighted_tick_v0" "1"
run_case "dynamic_emitter" "dynamic-emitter" "native_dynamic_emitter_tick_v0" "1"
run_case "instruction_equivalent_reserved" "instruction-equivalent" "native_loop_safepoint_tick_v0" "0"

python3 - "$cases_file" <<'PY'
import json
import sys
from pathlib import Path

cases_path = Path(sys.argv[1])
cases = [json.loads(line) for line in cases_path.read_text(encoding="utf-8").splitlines() if line.strip()]
seen = {case["name"]: case for case in cases}
required = {"default", "stmt", "statement", "basic_block", "block_weighted", "dynamic_emitter", "instruction_equivalent_reserved"}
missing = sorted(required - set(seen))
if missing:
    raise SystemExit(f"{cases_path}: missing mode cases: {missing}")
if seen["stmt"]["kind"] != seen["statement"]["kind"]:
    raise SystemExit(f"{cases_path}: stmt/statement kind mismatch: {seen!r}")
if seen["basic_block"]["kind"] != "native_basic_block_tick_v0":
    raise SystemExit(f"{cases_path}: basic-block mode mismatch: {seen['basic_block']!r}")
if seen["basic_block"]["kind"] == seen["stmt"]["kind"]:
    raise SystemExit(f"{cases_path}: basic-block must stay distinct from statement gas, got {seen!r}")
if int(seen["basic_block"].get("executed") or 0) <= 0:
    raise SystemExit(f"{cases_path}: basic-block should report positive gas, got {seen['basic_block']!r}")
if int(seen["basic_block"].get("executed") or 0) >= int(seen["stmt"].get("executed") or 0):
    raise SystemExit(f"{cases_path}: basic-block should charge fewer ticks than statement gas for this fixture, got {seen!r}")
if seen["block_weighted"]["kind"] != "native_block_weighted_tick_v0":
    raise SystemExit(f"{cases_path}: block-weighted mode mismatch: {seen['block_weighted']!r}")
if seen["block_weighted"]["kind"] == seen["basic_block"]["kind"] or seen["block_weighted"]["kind"] == seen["stmt"]["kind"]:
    raise SystemExit(f"{cases_path}: block-weighted must stay distinct from basic-block and statement gas, got {seen!r}")
if int(seen["block_weighted"].get("executed") or 0) <= 0:
    raise SystemExit(f"{cases_path}: block-weighted should report positive gas, got {seen['block_weighted']!r}")
if int(seen["block_weighted"].get("executed") or 0) <= int(seen["basic_block"].get("executed") or 0):
    raise SystemExit(f"{cases_path}: block-weighted should charge more than basic-block for this fixture, got {seen!r}")
if seen["dynamic_emitter"]["kind"] != "native_dynamic_emitter_tick_v0":
    raise SystemExit(f"{cases_path}: dynamic-emitter mode mismatch: {seen['dynamic_emitter']!r}")
if seen["dynamic_emitter"]["kind"] == seen["stmt"]["kind"] or seen["dynamic_emitter"]["kind"] == seen["basic_block"]["kind"] or seen["dynamic_emitter"]["kind"] == seen["block_weighted"]["kind"]:
    raise SystemExit(f"{cases_path}: dynamic-emitter gas must stay distinct from existing native gas surfaces, got {seen!r}")
if int(seen["dynamic_emitter"].get("executed") or 0) <= 0:
    raise SystemExit(f"{cases_path}: dynamic-emitter should report positive path-aware emitter ticks, got {seen['dynamic_emitter']!r}")
if seen["instruction_equivalent_reserved"]["kind"] != seen["default"]["kind"]:
    raise SystemExit(f"{cases_path}: instruction-equivalent gas must stay reserved and fall back to default loop-safepoint gas until implemented, got {seen!r}")
if seen["instruction_equivalent_reserved"]["kind"] == seen["stmt"]["kind"] or seen["instruction_equivalent_reserved"]["kind"] == seen["basic_block"]["kind"] or seen["instruction_equivalent_reserved"]["kind"] == seen["block_weighted"]["kind"] or seen["instruction_equivalent_reserved"]["kind"] == seen["dynamic_emitter"]["kind"]:
    raise SystemExit(f"{cases_path}: instruction-equivalent gas must stay reserved and not alias existing fine-grained modes, got {seen!r}")
print("native gas accounting modes verify OK")
PY
