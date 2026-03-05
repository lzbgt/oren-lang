#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_query_rollup_smoke"
index_path="${work_dir}/readiness_index.jsonl"
query_out="${work_dir}/query.jsonl"
query_faq_out="${work_dir}/query_faq.jsonl"
rollup_md="${work_dir}/rollup.md"
rollup_json="${work_dir}/rollup.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_010000.md","json":"build/reports/readiness_report_20260305_010000.json","log_dir":"build/logs/readiness_20260305_010000","status_faq_md":"build/reports/status_faq_20260305_010000.md","tag":"nightly"}
{"timestamp":"20260305_120000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260305_120000.md","json":"build/reports/readiness_report_20260305_120000.json","log_dir":"build/logs/readiness_20260305_120000","tag":"ci"}
{"timestamp":"20260306_090000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":60,"git_rev":"bead2222","git_dirty":"clean","report":"build/reports/readiness_report_20260306_090000.md","json":"build/reports/readiness_report_20260306_090000.json","log_dir":"build/logs/readiness_20260306_090000","tag":"nightly"}
EOF

./scripts/readiness_report_index_query.py --index "$index_path" --profile quick --out "$query_out"
./scripts/readiness_report_index_query.py --index "$index_path" --require-field status_faq_md --out "$query_faq_out"
./scripts/readiness_report_index_rollup.py --index "$index_path" --out-md "$rollup_md" --out-json "$rollup_json" --limit-days 0

rg -n "20260305_010000" "$query_out" >/dev/null
rg -n "20260306_090000" "$query_out" >/dev/null
rg -n "20260305_010000" "$query_faq_out" >/dev/null
! rg -n "20260306_090000" "$query_faq_out" >/dev/null
rg -n "Readiness rollup" "$rollup_md" >/dev/null
rg -n "\"day\": \"2026-03-05\"" "$rollup_json" >/dev/null
rg -n "\"pass\": 1" "$rollup_json" >/dev/null

echo "OK: readiness index query + rollup smoke verified"
