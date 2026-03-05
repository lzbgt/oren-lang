#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_diff_smoke"
left="${work_dir}/left.jsonl"
right="${work_dir}/right.jsonl"
out_md="${work_dir}/diff.md"
out_json="${work_dir}/diff.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$left" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly"}
EOF

cat >"$right" <<'EOF'
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly"}
{"timestamp":"20260305_030000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"c","json":"c","log_dir":"c","tag":"ci"}
EOF

./scripts/readiness_report_index_diff.py --left "$left" --right "$right" --out-md "$out_md" --out-json "$out_json" --sample 2

rg -n "Readiness index diff" "$out_md" >/dev/null
rg -n "\"overlap\"" "$out_json" >/dev/null
rg -n "\"left_only\"" "$out_json" >/dev/null
rg -n "deadbeef" "$out_json" >/dev/null

echo "OK: readiness index diff smoke verified"
