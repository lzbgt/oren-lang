#!/usr/bin/env bash
set -euo pipefail

report_path="build/tmp/readiness_report_dry_run.md"
json_path="build/tmp/readiness_report_dry_run.json"
index_path="build/tmp/readiness_report_index_dry_run.jsonl"
snapshot_dir="build/tmp"
rm -f "$report_path" "$json_path" 2>/dev/null || true
rm -f "$index_path" 2>/dev/null || true
rm -f "${snapshot_dir}/status_snapshot_"*.md "${snapshot_dir}/status_snapshot_"*.json 2>/dev/null || true
rm -f "${snapshot_dir}/status_faq_"*.md "${snapshot_dir}/status_faq_"*.json 2>/dev/null || true
rm -f "${snapshot_dir}/status_matrix_"*.md "${snapshot_dir}/status_matrix_"*.json 2>/dev/null || true
mkdir -p "$(dirname "$report_path")"

./scripts/readiness_report.sh --dry-run --profile minimal --out "$report_path" --json "$json_path" --index "$index_path" \
  --tag dry-run --no-latest --status-snapshot "$snapshot_dir" --status-faq "$snapshot_dir" --status-matrix "$snapshot_dir"

rg -n "# Oren readiness report" "$report_path" >/dev/null
rg -n "profile: minimal" "$report_path" >/dev/null
rg -n "tag: dry-run" "$report_path" >/dev/null
rg -n "overall: PASS" "$report_path" >/dev/null
rg -n "verify-native-quick" "$report_path" >/dev/null
rg -n "Production readiness gap \\(rolling snapshot\\)" "$report_path" >/dev/null
rg -n "Backend readiness \\(rolling snapshot\\)" "$report_path" >/dev/null
rg -n "Feature readiness gaps \\(requested\\)" "$report_path" >/dev/null

rg -n "\"overall\": \"PASS\"" "$json_path" >/dev/null
rg -n "\"profile\": \"minimal\"" "$json_path" >/dev/null
rg -n "\"tag\": \"dry-run\"" "$json_path" >/dev/null
rg -n "\"steps\"" "$json_path" >/dev/null
rg -n "\"status_snapshot_md\"" "$json_path" >/dev/null
rg -n "\"status_snapshot_json\"" "$json_path" >/dev/null
rg -n "\"status_faq_md\"" "$json_path" >/dev/null
rg -n "\"status_faq_json\"" "$json_path" >/dev/null
rg -n "\"status_matrix_md\"" "$json_path" >/dev/null
rg -n "\"status_matrix_json\"" "$json_path" >/dev/null
rg -n "\"report\"" "$index_path" >/dev/null
rg -n "\"tag\":\"dry-run\"" "$index_path" >/dev/null
rg -n "\"status_snapshot_md\"" "$index_path" >/dev/null
rg -n "\"status_faq_md\"" "$index_path" >/dev/null
rg -n "\"status_matrix_md\"" "$index_path" >/dev/null

snapshot_md="$(ls -t "${snapshot_dir}/status_snapshot_"*.md | head -n 1)"
snapshot_json="$(ls -t "${snapshot_dir}/status_snapshot_"*.json | head -n 1)"
test -f "$snapshot_md"
test -f "$snapshot_json"
faq_md="$(ls -t "${snapshot_dir}/status_faq_"*.md | head -n 1)"
faq_json="$(ls -t "${snapshot_dir}/status_faq_"*.json | head -n 1)"
test -f "$faq_md"
test -f "$faq_json"
matrix_md="$(ls -t "${snapshot_dir}/status_matrix_"*.md | head -n 1)"
matrix_json="$(ls -t "${snapshot_dir}/status_matrix_"*.json | head -n 1)"
test -f "$matrix_md"
test -f "$matrix_json"

echo "OK: readiness report dry-run verified"
