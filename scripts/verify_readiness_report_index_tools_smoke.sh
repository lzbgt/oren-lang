#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_tools_smoke"
index_path="${work_dir}/readiness_index.jsonl"
stats_md="${work_dir}/stats.md"
stats_json="${work_dir}/stats.json"
pruned="${work_dir}/pruned.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_210000.md","json":"build/reports/readiness_report_20260305_210000.json","log_dir":"build/logs/readiness_20260305_210000","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260306_010000.md","json":"build/reports/readiness_report_20260306_010000.json","log_dir":"build/logs/readiness_20260306_010000","tag":"ci"}
EOF

./scripts/readiness_report_index_validate.py --index "$index_path"
./scripts/readiness_report_index_stats.py --index "$index_path" --out-md "$stats_md" --out-json "$stats_json" --limit 0
./scripts/readiness_report_index_prune.py --index "$index_path" --keep 1 --out "$pruned"

rg -n "Readiness index stats" "$stats_md" >/dev/null
rg -n "\"total\": 2" "$stats_json" >/dev/null
rg -n "deadbeef" "$stats_md" >/dev/null
rg -n "deadbeef" "$stats_json" >/dev/null
rg -n "deadbeef" "$pruned" >/dev/null

echo "OK: readiness index tools smoke verified"
