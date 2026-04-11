#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="build/logs"
ts="$(date +%Y%m%d_%H%M%S)"
TMP="build/tmp/verify-native-package-policy-runner-${ts}"
mkdir -p "$TMP" "$LOG_DIR"
trap 'rm -rf "$TMP"; find build/tmp -maxdepth 1 -name "native_package_policy_*" -exec rm -rf {} +' EXIT

ok_out="$TMP/ok.out"
ok_err="$TMP/ok.err"
ok_json="$TMP/ok.run.json"
deny_out="$TMP/deny.out"
deny_err="$TMP/deny.err"
unsupported_out="$TMP/unsupported.out"
unsupported_err="$TMP/unsupported.err"
wall_out="$TMP/wall.out"
wall_err="$TMP/wall.err"
wall_json="$TMP/wall.run.json"
heap_ok_out="$TMP/heap-ok.out"
heap_ok_err="$TMP/heap-ok.err"
heap_ok_json="$TMP/heap-ok.run.json"
heap_fail_out="$TMP/heap-fail.out"
heap_fail_err="$TMP/heap-fail.err"
heap_fail_json="$TMP/heap-fail.run.json"
cpu_ok_out="$TMP/cpu-ok.out"
cpu_ok_err="$TMP/cpu-ok.err"
cpu_ok_json="$TMP/cpu-ok.run.json"
cpu_fail_out="$TMP/cpu-fail.out"
cpu_fail_err="$TMP/cpu-fail.err"
cpu_fail_json="$TMP/cpu-fail.run.json"

OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_ok.oren \
  >"$ok_out" 2>"$ok_err"
grep -Fq "native package policy ok" "$ok_out" || {
  echo "ERROR: native package-policy ok fixture did not report success" >&2
  cat "$ok_out" >&2 || true
  cat "$ok_err" >&2 || true
  exit 1
}
grep -Fq "native capsule effect gates " "$ok_out" || {
  echo "ERROR: native package-policy ok fixture did not report capsule effect gates" >&2
  cat "$ok_out" >&2 || true
  cat "$ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$heap_ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_heap_ok.oren \
  >"$heap_ok_out" 2>"$heap_ok_err"
grep -Fq "native package policy heap ok" "$heap_ok_out" || {
  echo "ERROR: native package-policy heap ok fixture did not report success" >&2
  cat "$heap_ok_out" >&2 || true
  cat "$heap_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$cpu_ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_cpu_ok.oren \
  >"$cpu_ok_out" 2>"$cpu_ok_err"
grep -Fq "native package policy CPU ok" "$cpu_ok_out" || {
  echo "ERROR: native package-policy CPU-ok fixture did not report success" >&2
  cat "$cpu_ok_out" >&2 || true
  cat "$cpu_ok_err" >&2 || true
  exit 1
}

set +e
./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_deny_time.oren \
  >"$deny_out" 2>"$deny_err"
deny_rc=$?
./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_unsupported_gas.oren \
  >"$unsupported_out" 2>"$unsupported_err"
unsupported_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$wall_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_wall_timeout.oren \
  >"$wall_out" 2>"$wall_err"
wall_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$heap_fail_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_heap_fail.oren \
  >"$heap_fail_out" 2>"$heap_fail_err"
heap_fail_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$cpu_fail_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_cpu_fail.oren \
  >"$cpu_fail_out" 2>"$cpu_fail_err"
cpu_fail_rc=$?
set -e

python3 - "$ok_json" "$wall_json" "$ok_out" "$heap_ok_json" "$heap_fail_json" "$cpu_ok_json" "$cpu_fail_json" <<'PY'
import json
import sys
from pathlib import Path

ok_path = Path(sys.argv[1])
wall_path = Path(sys.argv[2])
ok_stdout_path = Path(sys.argv[3])
heap_ok_path = Path(sys.argv[4])
heap_fail_path = Path(sys.argv[5])
cpu_ok_path = Path(sys.argv[6])
cpu_fail_path = Path(sys.argv[7])

def fail(msg):
    raise SystemExit(msg)

def load(path):
    if not path.is_file():
        fail(f"{path}: missing native runner JSON")
    return json.loads(path.read_text(encoding="utf-8"))

ok = load(ok_path)
if ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{ok_path}: schema mismatch: {ok.get('schema')!r}")
if ok.get("backend") != "native":
    fail(f"{ok_path}: backend mismatch: {ok.get('backend')!r}")
if ok.get("status") != "pass" or ok.get("exit_code") != 0:
    fail(f"{ok_path}: expected pass/0, got status={ok.get('status')!r} exit={ok.get('exit_code')!r}")
if ok.get("runtime_profile") != "capsule" or ok.get("capsule") is not True:
    fail(f"{ok_path}: expected capsule runtime profile, got {ok!r}")
if ok.get("cap_allow_domains") != ["TIME"]:
    fail(f"{ok_path}: expected TIME allow domain, got {ok.get('cap_allow_domains')!r}")
ok_ledger = ok.get("effect_ledger") or {}
if ok_ledger.get("available") is not True:
    fail(f"{ok_path}: expected captured native runtime ledger summary, got {ok_ledger!r}")
ok_summary = ok_ledger.get("summary") or {}
if ok_summary.get("schema") != "oren.effect-ledger-summary.v0":
    fail(f"{ok_path}: native effect ledger summary schema mismatch: {ok_summary!r}")
if (ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_only":
    fail(f"{ok_path}: expected runner_wall_only status, got {ok.get('runner_observed')!r}")
wall = ((ok.get("budgets") or {}).get("wall_ms") or {})
if wall.get("limit") != 1000 or wall.get("enforced") is not True:
    fail(f"{ok_path}: expected enforced 1000ms wall budget, got {wall!r}")
if int(wall.get("elapsed_ns") or 0) <= 0:
    fail(f"{ok_path}: expected positive elapsed_ns, got {wall!r}")

gate_prefix = "native capsule effect gates "
gate_json = None
for line in ok_stdout_path.read_text(encoding="utf-8").splitlines():
    if line.startswith(gate_prefix):
        gate_json = line[len(gate_prefix):]
if gate_json is None:
    fail(f"{ok_stdout_path}: missing native capsule effect gate JSON line")
try:
    gates = json.loads(gate_json)
except json.JSONDecodeError as exc:
    fail(f"{ok_stdout_path}: invalid native capsule effect gate JSON: {exc}")
if gates.get("schema") != "oren.native-capsule-effect-gates.v0":
    fail(f"{ok_stdout_path}: effect gate schema mismatch: {gates!r}")
if gates.get("kind") != "domain_gates" or gates.get("available") is not True:
    fail(f"{ok_stdout_path}: effect gate availability mismatch: {gates!r}")
if gates.get("capsule") is not True:
    fail(f"{ok_stdout_path}: expected capsule=true in effect gate summary: {gates!r}")
if int(gates.get("total") or 0) <= 0:
    fail(f"{ok_stdout_path}: expected positive effect gate total: {gates!r}")
if int(gates.get("denied") or 0) != 0:
    fail(f"{ok_stdout_path}: expected zero denied effect gates in success path: {gates!r}")
if int((gates.get("domains") or {}).get("TIME") or 0) <= 0:
    fail(f"{ok_stdout_path}: expected positive TIME effect gates: {gates!r}")

wall_timeout = load(wall_path)
if wall_timeout.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{wall_path}: schema mismatch: {wall_timeout.get('schema')!r}")
if wall_timeout.get("status") != "timeout" or wall_timeout.get("exit_code") != 124:
    fail(
        f"{wall_path}: expected timeout/124, got "
        f"status={wall_timeout.get('status')!r} exit={wall_timeout.get('exit_code')!r}"
    )
wall_budget = ((wall_timeout.get("budgets") or {}).get("wall_ms") or {})
if wall_budget.get("limit") != 100 or wall_budget.get("enforced") is not True:
    fail(f"{wall_path}: expected enforced 100ms wall budget, got {wall_budget!r}")
if int(wall_budget.get("elapsed_ns") or 0) <= 0:
    fail(f"{wall_path}: expected positive timeout elapsed_ns, got {wall_budget!r}")

heap_ok = load(heap_ok_path)
if heap_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{heap_ok_path}: schema mismatch: {heap_ok.get('schema')!r}")
if heap_ok.get("status") != "pass" or heap_ok.get("exit_code") != 0:
    fail(f"{heap_ok_path}: expected pass/0, got status={heap_ok.get('status')!r} exit={heap_ok.get('exit_code')!r}")
if (heap_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_native_heap":
    fail(f"{heap_ok_path}: expected runner_wall_native_heap status, got {heap_ok.get('runner_observed')!r}")
heap_ok_ledger = heap_ok.get("effect_ledger") or {}
if heap_ok_ledger.get("available") is not True:
    fail(f"{heap_ok_path}: expected native runtime ledger summary, got {heap_ok_ledger!r}")
heap_ok_summary = heap_ok_ledger.get("summary") or {}
heap_ok_budget = ((heap_ok.get("budgets") or {}).get("heap_bytes") or {})
if heap_ok_budget.get("limit") != 20000000 or heap_ok_budget.get("enforced") is not True:
    fail(f"{heap_ok_path}: expected enforced 20000000 byte heap budget, got {heap_ok_budget!r}")
if heap_ok_budget.get("exceeded") is not False:
    fail(f"{heap_ok_path}: expected non-exceeded heap budget, got {heap_ok_budget!r}")
heap_ok_used = int(heap_ok_budget.get("used") or -1)
if heap_ok_used < 0 or heap_ok_used > 20000000:
    fail(f"{heap_ok_path}: heap used outside budget: {heap_ok_budget!r}")
summary_heap = (((heap_ok_summary.get("budgets") or {}).get("heap_bytes") or {}))
if summary_heap.get("kind") != "tracked_live_scan":
    fail(f"{heap_ok_path}: expected tracked_live_scan native heap summary, got {summary_heap!r}")
if int(summary_heap.get("used") or -1) != heap_ok_used:
    fail(f"{heap_ok_path}: runner heap used does not mirror native summary: runner={heap_ok_budget!r} summary={summary_heap!r}")

heap_fail = load(heap_fail_path)
if heap_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{heap_fail_path}: schema mismatch: {heap_fail.get('schema')!r}")
if heap_fail.get("status") != "budget_exceeded" or heap_fail.get("exit_code") != 125:
    fail(
        f"{heap_fail_path}: expected budget_exceeded/125, got "
        f"status={heap_fail.get('status')!r} exit={heap_fail.get('exit_code')!r}"
    )
heap_fail_budget = ((heap_fail.get("budgets") or {}).get("heap_bytes") or {})
if heap_fail_budget.get("limit") != 1 or heap_fail_budget.get("enforced") is not True:
    fail(f"{heap_fail_path}: expected enforced 1 byte heap budget, got {heap_fail_budget!r}")
if heap_fail_budget.get("exceeded") is not True:
    fail(f"{heap_fail_path}: expected exceeded heap budget, got {heap_fail_budget!r}")
if int(heap_fail_budget.get("used") or 0) <= 1:
    fail(f"{heap_fail_path}: expected heap used to exceed 1 byte, got {heap_fail_budget!r}")

cpu_ok = load(cpu_ok_path)
if cpu_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{cpu_ok_path}: schema mismatch: {cpu_ok.get('schema')!r}")
if cpu_ok.get("status") != "pass" or cpu_ok.get("exit_code") != 0:
    fail(f"{cpu_ok_path}: expected pass/0, got status={cpu_ok.get('status')!r} exit={cpu_ok.get('exit_code')!r}")
if (cpu_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_child_cpu":
    fail(f"{cpu_ok_path}: expected runner_wall_child_cpu status, got {cpu_ok.get('runner_observed')!r}")
cpu_ok_budget = ((cpu_ok.get("budgets") or {}).get("cpu_ms") or {})
if cpu_ok_budget.get("limit") != 60000 or cpu_ok_budget.get("enforced") is not True:
    fail(f"{cpu_ok_path}: expected enforced 60000ms CPU budget, got {cpu_ok_budget!r}")
if cpu_ok_budget.get("exceeded") is not False:
    fail(f"{cpu_ok_path}: expected non-exceeded CPU budget, got {cpu_ok_budget!r}")
cpu_ok_used = int(cpu_ok_budget.get("used") or -1)
if cpu_ok_used < 0 or cpu_ok_used > 60000:
    fail(f"{cpu_ok_path}: CPU used outside budget: {cpu_ok_budget!r}")

cpu_fail = load(cpu_fail_path)
if cpu_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{cpu_fail_path}: schema mismatch: {cpu_fail.get('schema')!r}")
if cpu_fail.get("status") != "budget_exceeded" or cpu_fail.get("exit_code") != 126:
    fail(
        f"{cpu_fail_path}: expected budget_exceeded/126, got "
        f"status={cpu_fail.get('status')!r} exit={cpu_fail.get('exit_code')!r}"
    )
cpu_fail_budget = ((cpu_fail.get("budgets") or {}).get("cpu_ms") or {})
if cpu_fail_budget.get("limit") != 1 or cpu_fail_budget.get("enforced") is not True:
    fail(f"{cpu_fail_path}: expected enforced 1ms CPU budget, got {cpu_fail_budget!r}")
if cpu_fail_budget.get("exceeded") is not True:
    fail(f"{cpu_fail_path}: expected exceeded CPU budget, got {cpu_fail_budget!r}")
if int(cpu_fail_budget.get("used") or 0) <= 1:
    fail(f"{cpu_fail_path}: expected CPU used to exceed 1ms, got {cpu_fail_budget!r}")
PY

if [[ "$deny_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy runner to reject missing TIME domain" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
fi
grep -Eiq 'capsule|requires domain|TIME' "$deny_out" "$deny_err" || {
  echo "ERROR: missing native capsule domain diagnostic" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
}

if [[ "$unsupported_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy runner to fail closed for native gas budget" >&2
  cat "$unsupported_out" >&2 || true
  cat "$unsupported_err" >&2 || true
  exit 1
fi
grep -Fq "cannot enforce budget_gas" "$unsupported_out" "$unsupported_err" || {
  echo "ERROR: missing native gas unsupported diagnostic" >&2
  cat "$unsupported_out" >&2 || true
  cat "$unsupported_err" >&2 || true
  exit 1
}

if [[ "$wall_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy wall budget to stop infinite loop" >&2
  cat "$wall_out" >&2 || true
  cat "$wall_err" >&2 || true
  exit 1
fi
grep -Fq "package native wall budget exceeded" "$wall_out" "$wall_err" || {
  echo "ERROR: missing native wall budget diagnostic" >&2
  cat "$wall_out" >&2 || true
  cat "$wall_err" >&2 || true
  exit 1
}

if [[ "$heap_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy heap budget to reject over-budget run" >&2
  cat "$heap_fail_out" >&2 || true
  cat "$heap_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native heap budget exceeded" "$heap_fail_out" "$heap_fail_err" || {
  echo "ERROR: missing native heap budget diagnostic" >&2
  cat "$heap_fail_out" >&2 || true
  cat "$heap_fail_err" >&2 || true
  exit 1
}

if [[ "$cpu_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy CPU budget to reject over-budget run" >&2
  cat "$cpu_fail_out" >&2 || true
  cat "$cpu_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native CPU budget exceeded" "$cpu_fail_out" "$cpu_fail_err" || {
  echo "ERROR: missing native CPU budget diagnostic" >&2
  cat "$cpu_fail_out" >&2 || true
  cat "$cpu_fail_err" >&2 || true
  exit 1
}

echo "native package policy runner verify OK"
