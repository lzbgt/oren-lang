#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_audit_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/audit.md"
out_json="${work_dir}/audit.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

# create fake report/json/logs to satisfy audit
mkdir -p "$work_dir/logs"
: > "$work_dir/report.md"
: > "$work_dir/report.json"

cat >"$index_path" <<EOF_INDEX
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"${work_dir}/report.md","json":"${work_dir}/report.json","log_dir":"${work_dir}/logs","tag":"nightly"}
EOF_INDEX

./scripts/readiness_report_index_audit.py --index "$index_path" --out-md "$out_md" --out-json "$out_json"

rg -n "Readiness index audit" "$out_md" >/dev/null
rg -n "missing any: 0" "$out_md" >/dev/null
rg -n "\"missing_any\": 0" "$out_json" >/dev/null

echo "OK: readiness index audit smoke verified"
