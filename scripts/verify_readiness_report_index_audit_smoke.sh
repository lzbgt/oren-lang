#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_audit_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/audit.md"
out_json="${work_dir}/audit.json"
out_csv="${work_dir}/audit.csv"
out_samples_csv="${work_dir}/audit_samples.csv"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

# create fake report/json/logs to satisfy audit
mkdir -p "$work_dir/logs"
: > "$work_dir/report.md"
: > "$work_dir/report.json"
: > "$work_dir/status_snapshot.md"
: > "$work_dir/status_snapshot.json"
: > "$work_dir/status_faq.md"
: > "$work_dir/status_faq.json"
: > "$work_dir/status_matrix.md"
: > "$work_dir/status_matrix.json"
: > "$work_dir/status_overview.md"

cat >"$index_path" <<EOF_INDEX
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"${work_dir}/report.md","json":"${work_dir}/report.json","log_dir":"${work_dir}/logs","status_snapshot_md":"${work_dir}/status_snapshot.md","status_snapshot_json":"${work_dir}/status_snapshot.json","status_faq_md":"${work_dir}/status_faq.md","status_faq_json":"${work_dir}/status_faq.json","status_matrix_md":"${work_dir}/status_matrix.md","status_matrix_json":"${work_dir}/status_matrix.json","status_overview_md":"${work_dir}/status_overview.md","tag":"nightly"}
EOF_INDEX

./scripts/readiness_report_index_audit.py --index "$index_path" --out-md "$out_md" --out-json "$out_json" --out-csv "$out_csv" --out-samples-csv "$out_samples_csv" \
  --max-missing-report 10 --max-missing-json 10 --max-missing-log-dir 10 --max-missing-status-matrix-md 10 --max-missing-status-overview-md 10

rg -n "Readiness index audit" "$out_md" >/dev/null
rg -n "missing any: 0" "$out_md" >/dev/null
rg -n "missing status_faq_md: 0" "$out_md" >/dev/null
rg -n "\"missing_any\": 0" "$out_json" >/dev/null
rg -n "missing_status_overview_md" "$out_csv" >/dev/null
rg -n "status_overview_md" "$out_samples_csv" >/dev/null

echo "OK: readiness index audit smoke verified"
