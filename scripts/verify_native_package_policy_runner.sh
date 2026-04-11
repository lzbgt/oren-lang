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
set -e

python3 - "$ok_json" "$wall_json" "$ok_out" <<'PY'
import json
import sys
from pathlib import Path

ok_path = Path(sys.argv[1])
wall_path = Path(sys.argv[2])
ok_stdout_path = Path(sys.argv[3])

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
if (ok.get("effect_ledger") or {}).get("available") is not False:
    fail(f"{ok_path}: native effect ledger must stay unavailable until runtime export lands")
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
  echo "ERROR: expected native package-policy runner to reject unsupported gas budget" >&2
  cat "$unsupported_out" >&2 || true
  cat "$unsupported_err" >&2 || true
  exit 1
fi
grep -Fq "cannot enforce budget_gas" "$unsupported_out" "$unsupported_err" || {
  echo "ERROR: missing unsupported native budget diagnostic" >&2
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

echo "native package policy runner verify OK"
