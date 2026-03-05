#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_export_csv_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_csv="${work_dir}/readiness_index.csv"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_210000.md","json":"build/reports/readiness_report_20260305_210000.json","log_dir":"build/logs/readiness_20260305_210000","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260306_010000.md","json":"build/reports/readiness_report_20260306_010000.json","log_dir":"build/logs/readiness_20260306_010000","tag":"ci"}
EOF

./scripts/readiness_report_index_export_csv.py --index "$index_path" --out-csv "$out_csv" --limit 0

rg -n "timestamp,profile,overall" "$out_csv" >/dev/null
rg -n "status_matrix_md" "$out_csv" >/dev/null
rg -n "deadbeef" "$out_csv" >/dev/null

echo "OK: readiness index CSV export smoke verified"
