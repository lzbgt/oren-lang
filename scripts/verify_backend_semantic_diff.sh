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
if checks.get("obc_effect_ledger_summary_schema_ok") is not True:
    fail(
        "expected obc_effect_ledger_summary_schema_ok=true, "
        f"got {checks.get('obc_effect_ledger_summary_schema_ok')!r}"
    )
if checks.get("ledger_available_backends") != ["obc"]:
    fail(f"expected only OBC ledger availability, got {checks.get('ledger_available_backends')!r}")
if sorted(checks.get("ledger_missing_backends") or []) != ["c", "native"]:
    fail(f"expected C/native ledger-missing markers, got {checks.get('ledger_missing_backends')!r}")
if checks.get("ledger_comparable_all_backends") is not False:
    fail("all-backend ledger comparison should stay false until C/native emit ledgers")
if checks.get("budget_deltas_comparable_all_backends") is not False:
    fail("all-backend budget-delta comparison should stay false until C/native emit ledgers")

backends = data.get("backends") or {}
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
if int(deltas.get("gas_executed", 0)) <= 0:
    fail(f"expected positive OBC gas execution delta, got {deltas!r}")
if deltas.get("gas_remaining") != budgets.get("gas", {}).get("remaining"):
    fail(f"gas remaining delta should mirror summary budget, got {deltas!r} vs {budgets!r}")
if deltas.get("heap_bytes_used") != budgets.get("heap_bytes", {}).get("used"):
    fail(f"heap used delta should mirror summary budget, got {deltas!r} vs {budgets!r}")
if deltas.get("wall_elapsed_ns") != budgets.get("wall_ms", {}).get("elapsed_ns"):
    fail(f"wall elapsed delta should mirror summary budget, got {deltas!r} vs {budgets!r}")

for name in ("c", "native"):
    ledger = (backends.get(name) or {}).get("ledger") or {}
    if ledger.get("available") is not False:
        fail(f"{name} ledger should be unavailable for now, got {ledger!r}")
    if ledger.get("reason") != "backend run JSON ledger export is not implemented":
        fail(f"{name} ledger reason mismatch: {ledger!r}")

print(f"semantic diff report verify OK: {report}")
PY
