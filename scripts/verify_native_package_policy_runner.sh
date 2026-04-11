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
deny_out="$TMP/deny.out"
deny_err="$TMP/deny.err"
unsupported_out="$TMP/unsupported.out"
unsupported_err="$TMP/unsupported.err"
wall_out="$TMP/wall.out"
wall_err="$TMP/wall.err"

./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_ok.oren \
  >"$ok_out" 2>"$ok_err"
grep -Fq "native package policy ok" "$ok_out" || {
  echo "ERROR: native package-policy ok fixture did not report success" >&2
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
./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_wall_timeout.oren \
  >"$wall_out" 2>"$wall_err"
wall_rc=$?
set -e

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
