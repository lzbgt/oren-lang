#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_trend_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/trend.md"
out_json="${work_dir}/trend.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF_INDEX'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"report_a","json":"json_a","log_dir":"log_a","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"report_b","json":"json_b","log_dir":"log_b","tag":"ci","status_overview_md":"status_overview_b.md"}
{"timestamp":"20260307_030000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":60,"git_rev":"beadface","git_dirty":"clean","report":"report_c","json":"json_c","log_dir":"log_c","tag":"nightly","status_overview_md":"status_overview_c.md"}
EOF_INDEX

./scripts/readiness_report_index_trend.py --index "$index_path" --out-md "$out_md" --out-json "$out_json" --window 2

rg -n "Readiness index trend" "$out_md" >/dev/null
rg -n "window size: 2" "$out_md" >/dev/null
rg -n "overall: 66.7%" "$out_md" >/dev/null
rg -n "window: 50.0%" "$out_md" >/dev/null
rg -n "status_overview_c.md" "$out_md" >/dev/null
rg -n "Status overview coverage" "$out_md" >/dev/null
rg -n "overall: 2 \\(66.7%\\)" "$out_md" >/dev/null
rg -n "window: 2 \\(100.0%\\)" "$out_md" >/dev/null
rg -n "\"window\": 2" "$out_json" >/dev/null
rg -n "\"overall_pass_rate\": 66.7" "$out_json" >/dev/null
rg -n "\"window_pass_rate\": 50.0" "$out_json" >/dev/null
rg -n "\"status_overview_md\": \"status_overview_c.md\"" "$out_json" >/dev/null
rg -n "\"status_overview\"" "$out_json" >/dev/null

echo "OK: readiness index trend smoke verified"
