#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_split_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_dir="${work_dir}/splits"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"b","json":"b","log_dir":"b","tag":"ci"}
EOF

./scripts/readiness_report_index_split.py --index "$index_path" --out-dir "$out_dir" --mode profile
./scripts/readiness_report_index_split.py --index "$index_path" --out-dir "$out_dir" --mode tag

rg -n "\"profile\":\"quick\"" "$out_dir/profile_quick.jsonl" >/dev/null
rg -n "\"profile\":\"full\"" "$out_dir/profile_full.jsonl" >/dev/null
rg -n "\"tag\":\"nightly\"" "$out_dir/tag_nightly.jsonl" >/dev/null
rg -n "\"tag\":\"ci\"" "$out_dir/tag_ci.jsonl" >/dev/null

echo "OK: readiness index split smoke verified"
