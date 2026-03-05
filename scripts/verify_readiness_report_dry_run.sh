#!/usr/bin/env bash
set -euo pipefail

report_path="build/tmp/readiness_report_dry_run.md"
json_path="build/tmp/readiness_report_dry_run.json"
index_path="build/tmp/readiness_report_index_dry_run.jsonl"
rm -f "$report_path" "$json_path" 2>/dev/null || true
rm -f "$index_path" 2>/dev/null || true
mkdir -p "$(dirname "$report_path")"

./scripts/readiness_report.sh --dry-run --profile minimal --out "$report_path" --json "$json_path" --index "$index_path" --tag dry-run --no-latest

rg -n "# Oren readiness report" "$report_path" >/dev/null
rg -n "profile: minimal" "$report_path" >/dev/null
rg -n "tag: dry-run" "$report_path" >/dev/null
rg -n "overall: PASS" "$report_path" >/dev/null
rg -n "verify-native-quick" "$report_path" >/dev/null
rg -n "Backend readiness \\(rolling snapshot\\)" "$report_path" >/dev/null
rg -n "Feature readiness gaps \\(requested\\)" "$report_path" >/dev/null

rg -n "\"overall\": \"PASS\"" "$json_path" >/dev/null
rg -n "\"profile\": \"minimal\"" "$json_path" >/dev/null
rg -n "\"tag\": \"dry-run\"" "$json_path" >/dev/null
rg -n "\"steps\"" "$json_path" >/dev/null
rg -n "\"report\"" "$index_path" >/dev/null
rg -n "\"tag\":\"dry-run\"" "$index_path" >/dev/null

echo "OK: readiness report dry-run verified"
