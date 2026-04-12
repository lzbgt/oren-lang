#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: scripts/run_backend_semantic_diff.sh [source.oren]

Builds the source with C, native, and bytecode backends, runs all three, and
writes an agent-readable semantic-diff JSON report under build/reports/.

Environment:
  OREN_BACKEND_SEMANTIC_DIFF_SRC          default source when no arg is given
  OREN_BACKEND_SEMANTIC_DIFF_EXPECT_LINE  required normalized stdout line
  OREN_BACKEND_SEMANTIC_DIFF_KEEP_ARTIFACTS=1 keeps generated binaries/obc
  OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS  build timeout, default 120
  OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS    run timeout, default 5
  OREN_BACKEND_PARITY_TRACE_ENV           optional env forwarded to build/run

  Native run-JSON parity builds and runs with OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter
so semantic-diff reports the scoped v0 native runtime path-aware emitter gas surface.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

src="${1:-${OREN_BACKEND_SEMANTIC_DIFF_SRC:-tests/fixtures/backend_semantic_diff_smoke.oren}}"
expect_line="${OREN_BACKEND_SEMANTIC_DIFF_EXPECT_LINE:-ok: semantic diff}"

if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS:-120}"
run_timeout_secs="${OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS:-5}"

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

trace_env="${OREN_BACKEND_PARITY_TRACE_ENV:-}"
trace_env_arr=()
if [[ -n "$trace_env" ]]; then
  # shellcheck disable=SC2206
  trace_env_arr=($trace_env)
fi

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
  echo "== ensure: stage2 compiler ($COMPILER) ==" >&2
  make stage2
fi
if [[ ! -x ./avm ]]; then
  echo "== ensure: avm ==" >&2
  make avm
fi

ts="$(date +%Y%m%d_%H%M%S)"
base="$(basename "$src" .oren | tr -c 'A-Za-z0-9_-' '_')"
prefix="backend_semantic_diff_${base}_${ts}"
tmp_prefix="build/tmp/${prefix}"
log_prefix="build/logs/${prefix}"
report="build/reports/${prefix}.json"

out_c="${tmp_prefix}_c${exe_ext}"
out_native="${tmp_prefix}_native${exe_ext}"
out_obc="${tmp_prefix}.obc"

build_c="${log_prefix}_c_build.log"
build_native="${log_prefix}_native_build.log"
build_obc="${log_prefix}_obc_build.log"
run_c_out="${log_prefix}_c.stdout"
run_c_err="${log_prefix}_c.stderr"
run_native_out="${log_prefix}_native.stdout"
run_native_err="${log_prefix}_native.stderr"
run_obc_out="${log_prefix}_obc.stdout"
run_obc_err="${log_prefix}_obc.stderr"
run_native_json="${log_prefix}_native.run.json"
run_native_json_err="${log_prefix}_native.run.stderr"
run_obc_json="${log_prefix}_obc.run.json"
run_obc_json_err="${log_prefix}_obc.run.stderr"

cleanup_artifacts=1
if [[ -n "${OREN_BACKEND_SEMANTIC_DIFF_KEEP_ARTIFACTS:-}" ]]; then
  cleanup_artifacts=0
fi

cleanup() {
  if [[ "$cleanup_artifacts" == "1" ]]; then
    rm -f "$out_c" "$out_native" "$out_obc"
  fi
}
trap cleanup EXIT

echo "== semantic diff build: C ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" "$COMPILER" build "$src" --backend c -o "$out_c" >"$build_c" 2>&1
test -f "$out_c" || { echo "FAIL: missing $out_c" >&2; tail -n 120 "$build_c" >&2 || true; exit 3; }

echo "== semantic diff build: native ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug -o "$out_native" >"$build_native" 2>&1
test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$build_native" >&2 || true; exit 4; }

echo "== semantic diff build: bytecode ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" "$COMPILER" build "$src" --backend bytecode -o "$out_obc" >"$build_obc" 2>&1
test -f "$out_obc" || { echo "FAIL: missing $out_obc" >&2; tail -n 120 "$build_obc" >&2 || true; exit 5; }

set +e
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" "$out_c" >"$run_c_out" 2>"$run_c_err"
rc_c=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter "$out_native" >"$run_native_out" 2>"$run_native_err"
rc_native=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" ./avm "$out_obc" >"$run_obc_out" 2>"$run_obc_err"
rc_obc=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter OREN_NATIVE_RUN_JSON=1 "$out_native" >"$run_native_json" 2>"$run_native_json_err"
rc_native_json=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" ./avm --print-run-json "$out_obc" >"$run_obc_json" 2>"$run_obc_json_err"
rc_obc_json=$?
set -e

python3 - "$report" "$src" "$expect_line" \
  "$run_native_json" "$run_native_json_err" "$rc_native_json" \
  "$run_obc_json" "$run_obc_json_err" "$rc_obc_json" \
  c "$rc_c" "$run_c_out" "$run_c_err" "$build_c" \
  native "$rc_native" "$run_native_out" "$run_native_err" "$build_native" \
  obc "$rc_obc" "$run_obc_out" "$run_obc_err" "$build_obc" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

report = Path(sys.argv[1])
src = sys.argv[2]
expect_line = sys.argv[3]
native_run_json_log = sys.argv[4]
native_run_json_stderr_log = sys.argv[5]
native_run_json_rc = int(sys.argv[6])
obc_run_json_log = sys.argv[7]
obc_run_json_stderr_log = sys.argv[8]
obc_run_json_rc = int(sys.argv[9])
items = sys.argv[10:]

def read_text(path_s):
    return Path(path_s).read_text(encoding="utf-8", errors="replace")

def normalize(text):
    text = text.replace("\r", "")
    return "\n".join(line.rstrip() for line in text.splitlines())

def sha256_s(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def find_last_json_obj(text):
    for line in reversed(text.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    return None

def budget_deltas(summary):
    budgets = (summary or {}).get("budgets") or {}
    gas = budgets.get("gas") or {}
    gas_surface_raw = gas.get("surface")
    gas_surface = gas_surface_raw if isinstance(gas_surface_raw, dict) else {}
    heap = budgets.get("heap_bytes") or {}
    wall = budgets.get("wall_ms") or {}
    io_b = budgets.get("io_bytes") or {}
    log_b = budgets.get("log_bytes") or {}
    trace_b = budgets.get("trace_bytes") or {}
    return {
        "gas_executed": gas.get("executed"),
        "gas_remaining": gas.get("remaining"),
        "gas_kind": gas.get("kind"),
        "gas_surface_id": gas_surface.get("id"),
        "gas_surface_backend": gas_surface.get("backend"),
        "gas_surface_unit": gas_surface.get("unit"),
        "gas_surface_unit_scope": gas_surface.get("unit_scope"),
        "gas_surface_target_arch": gas_surface.get("target_arch"),
        "gas_surface_unit_family": gas_surface.get("unit_family"),
        "gas_surface_granularity": gas_surface.get("granularity"),
        "gas_surface_runtime_path_aware": gas_surface.get("runtime_path_aware"),
        "gas_surface_cross_arch_comparable": gas_surface.get("cross_arch_comparable"),
        "gas_surface_conversion_ready": gas_surface.get("conversion_ready"),
        "gas_surface_avm_canonical": gas_surface.get("avm_canonical"),
        "heap_bytes_used": heap.get("used"),
        "heap_bytes_limit": heap.get("limit"),
        "wall_elapsed_ns": wall.get("elapsed_ns"),
        "wall_ms_limit": wall.get("limit"),
        "io_bytes_used": io_b.get("used"),
        "io_bytes_limit": io_b.get("limit"),
        "log_bytes_used": log_b.get("used"),
        "log_bytes_limit": log_b.get("limit"),
        "trace_bytes_used": trace_b.get("used"),
        "trace_bytes_limit": trace_b.get("limit"),
        "trace_bytes_truncated": trace_b.get("truncated"),
    }

def unavailable_ledger(reason):
    return {
        "available": False,
        "reason": reason,
        "run_json_schema": None,
        "summary_schema": None,
        "summary": None,
        "budget_deltas": None,
        "run_json_log": None,
        "run_json_stderr_log": None,
        "run_json_exit_code": None,
    }

backends = {}
for i in range(0, len(items), 5):
    name = items[i]
    rc = int(items[i + 1])
    stdout_path = items[i + 2]
    stderr_path = items[i + 3]
    build_log = items[i + 4]
    stdout = read_text(stdout_path)
    stderr = read_text(stderr_path)
    stdout_norm = normalize(stdout)
    stderr_norm = normalize(stderr)
    backends[name] = {
        "exit_code": rc,
        "stdout_sha256": sha256_s(stdout_norm),
        "stderr_sha256": sha256_s(stderr_norm),
        "stdout_normalized": stdout_norm,
        "stderr_normalized": stderr_norm,
        "stdout_log": stdout_path,
        "stderr_log": stderr_path,
        "build_log": build_log,
        "expected_line_present": expect_line in stdout_norm.splitlines(),
        "ledger": unavailable_ledger("backend run JSON ledger export is not implemented"),
    }

native_run_json = find_last_json_obj(read_text(native_run_json_log))
native_run_json_schema = native_run_json.get("schema") if isinstance(native_run_json, dict) else None
native_ledger_summary = None
if native_run_json_schema == "oren.native-run.v0":
    native_ledger_summary = native_run_json.get("effect_ledger_summary")
native_ledger_summary_schema = native_ledger_summary.get("schema") if isinstance(native_ledger_summary, dict) else None
native_ledger_available = native_run_json_rc == 0 and native_ledger_summary_schema == "oren.effect-ledger-summary.v0"
native_domain_gates = native_ledger_summary.get("domain_gates") if isinstance(native_ledger_summary, dict) else None
native_domain_gates_schema = native_domain_gates.get("schema") if isinstance(native_domain_gates, dict) else None
native_domain_gates_ok = native_domain_gates_schema == "oren.native-capsule-effect-gates.v0"
native_resource_checks = native_ledger_summary.get("resource_checks") if isinstance(native_ledger_summary, dict) else None
native_resource_checks_schema = native_resource_checks.get("schema") if isinstance(native_resource_checks, dict) else None
native_resource_checks_ok = native_resource_checks_schema == "oren.native-capsule-resource-checks.v0"
if native_run_json_rc != 0:
    native_ledger_reason = "native run JSON execution failed"
elif native_run_json_schema != "oren.native-run.v0":
    native_ledger_reason = "missing oren.native-run.v0 JSON in native run JSON log"
elif not isinstance(native_ledger_summary, dict):
    native_ledger_reason = "missing effect_ledger_summary in native run JSON"
elif native_ledger_summary_schema != "oren.effect-ledger-summary.v0":
    native_ledger_reason = "effect_ledger_summary schema mismatch"
else:
    native_ledger_reason = None
backends["native"]["ledger"] = {
    "available": native_ledger_available,
    "reason": native_ledger_reason,
    "run_json_schema": native_run_json_schema,
    "summary_schema": native_ledger_summary_schema,
    "summary": native_ledger_summary,
    "budget_deltas": budget_deltas(native_ledger_summary) if native_ledger_available else None,
    "run_json_log": native_run_json_log,
    "run_json_stderr_log": native_run_json_stderr_log,
    "run_json_exit_code": native_run_json_rc,
}

obc_run_json = find_last_json_obj(read_text(obc_run_json_log))
obc_run_json_schema = obc_run_json.get("schema") if isinstance(obc_run_json, dict) else None
obc_ledger_summary = None
if obc_run_json_schema == "avm.run.v1":
    obc_ledger_summary = obc_run_json.get("effect_ledger_summary")
obc_ledger_summary_schema = obc_ledger_summary.get("schema") if isinstance(obc_ledger_summary, dict) else None
obc_ledger_available = obc_ledger_summary_schema == "oren.effect-ledger-summary.v0"
if obc_run_json_schema != "avm.run.v1":
    obc_ledger_reason = "missing avm.run.v1 JSON in AVM run JSON log"
elif not isinstance(obc_ledger_summary, dict):
    obc_ledger_reason = "missing effect_ledger_summary in AVM run JSON"
elif obc_ledger_summary_schema != "oren.effect-ledger-summary.v0":
    obc_ledger_reason = "effect_ledger_summary schema mismatch"
else:
    obc_ledger_reason = None
backends["obc"]["ledger"] = {
    "available": obc_ledger_available,
    "reason": obc_ledger_reason,
    "run_json_schema": obc_run_json_schema,
    "summary_schema": obc_ledger_summary_schema,
    "summary": obc_ledger_summary,
    "budget_deltas": budget_deltas(obc_ledger_summary) if obc_ledger_available else None,
    "run_json_log": obc_run_json_log,
    "run_json_stderr_log": obc_run_json_stderr_log,
    "run_json_exit_code": obc_run_json_rc,
}

order = ["c", "native", "obc"]
def gas_surface(summary):
    gas = (((summary or {}).get("budgets") or {}).get("gas") or {})
    surface = gas.get("surface")
    return surface if isinstance(surface, dict) else None

def gas_executed(summary):
    gas = (((summary or {}).get("budgets") or {}).get("gas") or {})
    value = gas.get("executed")
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None

def source_class(path):
    name = Path(path).name
    if "gas_alloc_calibration" in name:
        return "alloc_heavy"
    if "gas_call_calibration" in name:
        return "call_heavy"
    if "gas_branch_calibration" in name:
        return "branch_heavy"
    if "gas_calibration" in name:
        return "loop_heavy"
    if "smoke" in name:
        return "smoke"
    return "custom"

native_gas_surface = gas_surface(native_ledger_summary)
obc_gas_surface = gas_surface(obc_ledger_summary)
gas_surface_native_obc_comparable = (
    isinstance(native_gas_surface, dict)
    and isinstance(obc_gas_surface, dict)
    and native_gas_surface.get("id") == obc_gas_surface.get("id")
)
if not isinstance(native_gas_surface, dict):
    gas_surface_reason = "native gas surface missing"
elif not isinstance(obc_gas_surface, dict):
    gas_surface_reason = "OBC gas surface missing"
elif gas_surface_native_obc_comparable:
    gas_surface_reason = None
else:
    gas_surface_reason = "native and OBC gas surfaces differ"
native_gas_executed = gas_executed(native_ledger_summary)
obc_gas_executed = gas_executed(obc_ledger_summary)
gas_calibration_available = (
    native_gas_executed is not None
    and obc_gas_executed is not None
    and native_gas_executed > 0
    and obc_gas_executed > 0
)
native_per_obc = None
obc_per_native = None
if gas_calibration_available:
    native_per_obc = native_gas_executed / obc_gas_executed
    obc_per_native = obc_gas_executed / native_gas_executed
gas_surface_calibration = {
    "schema": "oren.gas-surface-calibration.v0",
    "mode": "empirical_single_fixture",
    "source": src,
    "source_class": source_class(src),
    "native_surface_id": native_gas_surface.get("id") if isinstance(native_gas_surface, dict) else None,
    "native_surface_unit_scope": native_gas_surface.get("unit_scope") if isinstance(native_gas_surface, dict) else None,
    "native_surface_target_arch": native_gas_surface.get("target_arch") if isinstance(native_gas_surface, dict) else None,
    "native_surface_unit_family": native_gas_surface.get("unit_family") if isinstance(native_gas_surface, dict) else None,
    "native_surface_runtime_path_aware": native_gas_surface.get("runtime_path_aware") if isinstance(native_gas_surface, dict) else None,
    "native_surface_cross_arch_comparable": native_gas_surface.get("cross_arch_comparable") if isinstance(native_gas_surface, dict) else None,
    "native_surface_conversion_ready": native_gas_surface.get("conversion_ready") if isinstance(native_gas_surface, dict) else None,
    "obc_surface_id": obc_gas_surface.get("id") if isinstance(obc_gas_surface, dict) else None,
    "obc_surface_unit_scope": obc_gas_surface.get("unit_scope") if isinstance(obc_gas_surface, dict) else None,
    "obc_surface_runtime_path_aware": obc_gas_surface.get("runtime_path_aware") if isinstance(obc_gas_surface, dict) else None,
    "obc_surface_cross_arch_comparable": obc_gas_surface.get("cross_arch_comparable") if isinstance(obc_gas_surface, dict) else None,
    "obc_surface_conversion_ready": obc_gas_surface.get("conversion_ready") if isinstance(obc_gas_surface, dict) else None,
    "obc_surface_avm_canonical": obc_gas_surface.get("avm_canonical") if isinstance(obc_gas_surface, dict) else None,
    "native_executed": native_gas_executed,
    "obc_executed": obc_gas_executed,
    "native_per_obc": native_per_obc,
    "obc_per_native": obc_per_native,
    "comparable": gas_surface_native_obc_comparable,
    "not_a_conversion": not gas_surface_native_obc_comparable,
    "reason": gas_surface_reason,
}
stdout_equal = len({backends[name]["stdout_normalized"] for name in order}) == 1
native_obc_stdout_equal = backends["native"]["stdout_normalized"] == backends["obc"]["stdout_normalized"]
exit_equal = len({backends[name]["exit_code"] for name in order}) == 1
native_obc_exit_equal = backends["native"]["exit_code"] == backends["obc"]["exit_code"]
all_ok = all(backends[name]["exit_code"] == 0 for name in order)
expect_ok = all(backends[name]["expected_line_present"] for name in order)
obc_run_json_ok = obc_run_json_rc == 0 and obc_run_json_schema == "avm.run.v1"
native_run_json_ok = native_run_json_rc == 0 and native_run_json_schema == "oren.native-run.v0"
native_ledger_ok = backends["native"]["ledger"]["available"]
obc_ledger_ok = backends["obc"]["ledger"]["available"]
ledger_available = [name for name in order if backends[name]["ledger"]["available"]]
ledger_missing = [name for name in order if not backends[name]["ledger"]["available"]]
ledger_comparable_all = len(ledger_available) == len(order)
budget_deltas_comparable_all = ledger_comparable_all and all(backends[name]["ledger"]["budget_deltas"] is not None for name in order)
avm_canonical_sidecar_gas_available = (
    stdout_equal
    and exit_equal
    and isinstance(obc_gas_surface, dict)
    and obc_gas_surface.get("id") == "avm_opcode_cost_v0"
    and obc_gas_surface.get("unit_scope") == "avm_canonical"
    and obc_gas_surface.get("conversion_ready") is True
    and obc_gas_surface.get("avm_canonical") is True
    and obc_gas_executed is not None
    and obc_gas_executed > 0
)
avm_canonical_sidecar_failure_reasons = []
if not native_obc_stdout_equal:
    avm_canonical_sidecar_failure_reasons.append("stdout_mismatch")
if not native_obc_exit_equal:
    avm_canonical_sidecar_failure_reasons.append("exit_code_mismatch")
if not (
    isinstance(obc_gas_surface, dict)
    and obc_gas_surface.get("id") == "avm_opcode_cost_v0"
    and obc_gas_surface.get("unit_scope") == "avm_canonical"
    and obc_gas_surface.get("conversion_ready") is True
    and obc_gas_surface.get("avm_canonical") is True
):
    avm_canonical_sidecar_failure_reasons.append("missing_or_noncanonical_avm_gas_surface")
elif obc_gas_executed is None or obc_gas_executed <= 0:
    avm_canonical_sidecar_failure_reasons.append("missing_or_nonpositive_avm_gas")
if avm_canonical_sidecar_gas_available:
    avm_canonical_sidecar_failure_reasons = []
avm_canonical_sidecar_gas = {
    "schema": "oren.avm-canonical-sidecar-gas.v0",
    "status": "available" if avm_canonical_sidecar_gas_available else "unavailable",
    "source": src,
    "native_backend": "native",
    "sidecar_backend": "obc",
    "same_source": True,
    "same_run_stdout_equal": native_obc_stdout_equal,
    "same_run_exit_code_equal": native_obc_exit_equal,
    "native_stdout_sha256": backends["native"]["stdout_sha256"],
    "sidecar_stdout_sha256": backends["obc"]["stdout_sha256"],
    "native_stderr_sha256": backends["native"]["stderr_sha256"],
    "sidecar_stderr_sha256": backends["obc"]["stderr_sha256"],
    "certification_status": "stdout_exit_match" if avm_canonical_sidecar_gas_available else "unavailable",
    "certification_failure_reasons": avm_canonical_sidecar_failure_reasons,
    "gas_surface": obc_gas_surface,
    "gas_executed": obc_gas_executed,
    "budget_exceeded": False,
    "budget_exceeded_source": None,
    "sidecar_error": None,
    "native_runtime_surface_id": native_gas_surface.get("id") if isinstance(native_gas_surface, dict) else None,
    "native_runtime_gas_executed": native_gas_executed,
    "native_runtime_conversion": False,
    "package_policy_may_use": False,
    "package_policy_may_use_reason": "semantic_diff_fixture_not_package_bound",
    "policy_scope": "semantic_diff_same_source_fixture",
    "reason": "same-source AVM canonical sidecar evidence; not a native runtime gas conversion",
}
status = "pass" if stdout_equal and exit_equal and all_ok and expect_ok and native_run_json_ok and native_ledger_ok and native_domain_gates_ok and native_resource_checks_ok and obc_run_json_ok and obc_ledger_ok else "fail"

out = {
    "schema": "oren.semantic-diff.v0",
    "source": src,
    "backend_order": order,
    "status": status,
    "checks": {
        "stdout_equal": stdout_equal,
        "exit_code_equal": exit_equal,
        "all_exit_zero": all_ok,
        "expected_line": expect_line,
        "expected_line_present_all": expect_ok,
        "native_run_json_exit_zero": native_run_json_rc == 0,
        "native_run_json_schema": native_run_json_schema,
        "native_run_json_schema_ok": native_run_json_schema == "oren.native-run.v0",
        "native_effect_ledger_summary_present": native_ledger_ok,
        "native_effect_ledger_summary_schema": native_ledger_summary_schema,
        "native_effect_ledger_summary_schema_ok": native_ledger_summary_schema == "oren.effect-ledger-summary.v0",
        "native_domain_gates_schema": native_domain_gates_schema,
        "native_domain_gates_schema_ok": native_domain_gates_ok,
        "native_resource_checks_schema": native_resource_checks_schema,
        "native_resource_checks_schema_ok": native_resource_checks_ok,
        "obc_run_json_exit_zero": obc_run_json_rc == 0,
        "obc_run_json_schema": obc_run_json_schema,
        "obc_run_json_schema_ok": obc_run_json_schema == "avm.run.v1",
        "obc_effect_ledger_summary_present": obc_ledger_ok,
        "obc_effect_ledger_summary_schema": obc_ledger_summary_schema,
        "obc_effect_ledger_summary_schema_ok": obc_ledger_summary_schema == "oren.effect-ledger-summary.v0",
        "ledger_available_backends": ledger_available,
        "ledger_missing_backends": ledger_missing,
        "ledger_comparable_all_backends": ledger_comparable_all,
        "budget_deltas_comparable_all_backends": budget_deltas_comparable_all,
        "gas_surface_comparable_native_obc": gas_surface_native_obc_comparable,
        "gas_surface_comparison_reason": gas_surface_reason,
        "gas_surface_calibration_available": gas_calibration_available,
        "avm_canonical_sidecar_gas_available": avm_canonical_sidecar_gas_available,
    },
    "gas_surfaces": {
        "native": native_gas_surface,
        "obc": obc_gas_surface,
        "native_obc_comparable": gas_surface_native_obc_comparable,
        "reason": gas_surface_reason,
    },
    "gas_surface_calibration": gas_surface_calibration,
    "avm_canonical_sidecar_gas": avm_canonical_sidecar_gas,
    "backends": backends,
}

report.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"semantic diff report: {report}")
if status != "pass":
    print(json.dumps(out["checks"], indent=2, sort_keys=True), file=sys.stderr)
    raise SystemExit(1)
PY

echo "OK: backend semantic diff (C/native/obc)" >&2
