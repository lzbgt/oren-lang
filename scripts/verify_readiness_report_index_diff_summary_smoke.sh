#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_diff_summary_smoke"
left="${work_dir}/left.jsonl"
right="${work_dir}/right.jsonl"
out_md="${work_dir}/diff_summary.md"
out_json="${work_dir}/diff_summary.json"
out_csv="${work_dir}/diff_summary.csv"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$left" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly","status_overview_md":"status_overview_b.md"}
EOF

cat >"$right" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly","status_overview_md":"status_overview_b.md"}
{"timestamp":"20260305_030000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"c","json":"c","log_dir":"c","tag":"ci","status_overview_md":"status_overview_c.md"}
EOF

./scripts/readiness_report_index_diff_summary.py --left "$left" --right "$right" --out-md "$out_md" --out-json "$out_json" --out-csv "$out_csv"

rg -n "Readiness index summary diff" "$out_md" >/dev/null
rg -n "\"delta\"" "$out_json" >/dev/null
rg -n "\"fails\"" "$out_json" >/dev/null
rg -n "latest_status_overview_md" "$out_json" >/dev/null
rg -n "metric,left,right,delta" "$out_csv" >/dev/null
rg -n "latest_status_overview_md" "$out_csv" >/dev/null

echo "OK: readiness index diff summary smoke verified"
