#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="build/logs"
ts="$(date +%Y%m%d_%H%M%S)"
TMP="build/tmp/verify-avm-package-policy-runner-${ts}"
mkdir -p "$TMP" "$LOG_DIR"
trap 'rm -rf "$TMP"' EXIT

ok_out="$TMP/ok.out"
ok_err="$TMP/ok.err"
deny_out="$TMP/deny.out"
deny_err="$TMP/deny.err"
gas_out="$TMP/gas.out"
gas_err="$TMP/gas.err"

./scripts/run_avm_package_policy.sh tests/fixtures/avm_package_policy_runner_ok.oren \
  -- --print-run-json >"$ok_out" 2>"$ok_err"

set +e
./scripts/run_avm_package_policy.sh tests/fixtures/avm_package_policy_runner_deny_rng.oren \
  -- --print-run-json >"$deny_out" 2>"$deny_err"
deny_rc=$?
./scripts/run_avm_package_policy.sh tests/fixtures/avm_package_policy_runner_gas_fail.oren \
  -- --print-run-json >"$gas_out" 2>"$gas_err"
gas_rc=$?
set -e

if [[ "$deny_rc" -eq 0 ]]; then
  echo "ERROR: expected package policy runner to deny undeclared RNG domain" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
fi
grep -Eiq 'den(y|ied)|capability|domain' "$deny_out" "$deny_err" || {
  echo "ERROR: missing domain-denial diagnostic" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
}

if [[ "$gas_rc" -eq 0 ]]; then
  echo "ERROR: expected package gas budget to stop infinite loop" >&2
  cat "$gas_out" >&2 || true
  cat "$gas_err" >&2 || true
  exit 1
fi
grep -Fq "AVM error: code=9" "$gas_out" "$gas_err" || {
  echo "ERROR: missing AVM gas budget diagnostic" >&2
  cat "$gas_out" >&2 || true
  cat "$gas_err" >&2 || true
  exit 1
}

python3 - "$ok_out" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
run = None
for line in path.read_text().splitlines():
    line = line.strip()
    if line.startswith("{") and '"schema":"avm.run.v1"' in line:
        run = json.loads(line)
if run is None:
    raise SystemExit(f"missing avm.run.v1 JSON in {path}")

ledger = run.get("effect_ledger_summary")
if not isinstance(ledger, dict):
    raise SystemExit("missing effect_ledger_summary")
budgets = ledger.get("budgets", {})
gas = budgets.get("gas", {})
if int(gas.get("executed", 0)) <= 0:
    raise SystemExit(f"expected positive gas execution count, got {gas!r}")
if int(gas.get("remaining", 0)) <= 0:
    raise SystemExit(f"expected remaining package gas budget, got {gas!r}")
if int(gas.get("executed", 0)) + int(gas.get("remaining", 0)) != 100000:
    raise SystemExit(f"package gas budget was not applied exactly, got {gas!r}")
heap = budgets.get("heap_bytes", {})
if int(heap.get("limit", 0)) != 1048576:
    raise SystemExit(f"package heap budget was not applied, got {heap!r}")
wall = budgets.get("wall_ms", {})
if int(wall.get("limit", 0)) != 1000:
    raise SystemExit(f"package wall budget was not applied, got {wall!r}")
if int(wall.get("elapsed_ns", -1)) < 0:
    raise SystemExit(f"package wall budget should report elapsed ns, got {wall!r}")
PY

echo "avm package policy runner verify OK"
