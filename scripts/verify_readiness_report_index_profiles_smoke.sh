#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_profiles_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/profiles.md"
out_json="${work_dir}/profiles.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF_INDEX'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"report_a","json":"json_a","log_dir":"log_a","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"report_b","json":"json_b","log_dir":"log_b","tag":"ci"}
{"timestamp":"20260307_030000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":60,"git_rev":"beadface","git_dirty":"clean","report":"report_c","json":"json_c","log_dir":"log_c","tag":"nightly"}
EOF_INDEX

./scripts/readiness_report_index_profiles.py --index "$index_path" --out-md "$out_md" --out-json "$out_json"

rg -n "Readiness index profiles" "$out_md" >/dev/null
rg -n "quick" "$out_md" >/dev/null
rg -n "full" "$out_md" >/dev/null
rg -n "\"profiles\"" "$out_json" >/dev/null
rg -n "\"quick\"" "$out_json" >/dev/null
rg -n "\"full\"" "$out_json" >/dev/null

echo "OK: readiness index profiles smoke verified"
