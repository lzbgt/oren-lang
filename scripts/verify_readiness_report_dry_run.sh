#!/usr/bin/env bash
set -euo pipefail

report_path="build/tmp/readiness_report_dry_run.md"
rm -f "$report_path" 2>/dev/null || true
mkdir -p "$(dirname "$report_path")"

./scripts/readiness_report.sh --dry-run --profile minimal --out "$report_path"

rg -n "# Oren readiness report" "$report_path" >/dev/null
rg -n "profile: minimal" "$report_path" >/dev/null
rg -n "overall: PASS" "$report_path" >/dev/null
rg -n "verify-native-quick" "$report_path" >/dev/null

echo "OK: readiness report dry-run verified"
