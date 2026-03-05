#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_latest_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/latest.md"
out_json="${work_dir}/latest.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF_INDEX'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"report_a","json":"json_a","log_dir":"log_a","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"report_b","json":"json_b","log_dir":"log_b","tag":"ci","status_overview_md":"status_overview_b.md"}
{"timestamp":"20260307_030000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":60,"git_rev":"beadface","git_dirty":"clean","report":"report_c","json":"json_c","log_dir":"log_c","tag":"nightly","status_overview_md":"status_overview_c.md"}
EOF_INDEX

./scripts/readiness_report_index_latest.py --index "$index_path" --out-md "$out_md" --out-json "$out_json" --groups profile,tag

rg -n "Readiness index latest" "$out_md" >/dev/null
rg -n "Latest by profile" "$out_md" >/dev/null
rg -n "Latest by tag" "$out_md" >/dev/null
rg -n "20260307_030000" "$out_md" >/dev/null
rg -n "deadbeef" "$out_md" >/dev/null
rg -n "status_overview_c.md" "$out_md" >/dev/null
rg -n "\"total\": 3" "$out_json" >/dev/null
rg -n "\"profile\"" "$out_json" >/dev/null
rg -n "\"tag\"" "$out_json" >/dev/null

echo "OK: readiness index latest smoke verified"
