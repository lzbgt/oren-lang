#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_audit_trend_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/audit_trend.md"
out_json="${work_dir}/audit_trend.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

mkdir -p "$work_dir/logs"
: > "$work_dir/report.md"
: > "$work_dir/report.json"

cat >"$index_path" <<EOF_INDEX
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"${work_dir}/report.md","json":"${work_dir}/report.json","log_dir":"${work_dir}/logs","tag":"nightly"}
{"timestamp":"20260305_120000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"${work_dir}/missing_report.md","json":"${work_dir}/report.json","log_dir":"${work_dir}/logs","status_matrix_md":"${work_dir}/missing_matrix.md","tag":"ci"}
EOF_INDEX

./scripts/readiness_report_index_audit_trend.py --index "$index_path" --out-md "$out_md" --out-json "$out_json" --limit 10 --max-missing-any 10

rg -n "Readiness index audit trend" "$out_md" >/dev/null
rg -n "missing_any" "$out_md" >/dev/null
rg -n "status_matrix_md" "$out_md" >/dev/null
rg -n "\"missing_any\"" "$out_json" >/dev/null
rg -n "\"missing_by_kind\"" "$out_json" >/dev/null

echo "OK: readiness index audit trend smoke verified"
