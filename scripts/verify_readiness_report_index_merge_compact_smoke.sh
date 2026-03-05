#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_merge_compact_smoke"
idx_a="${work_dir}/a.jsonl"
idx_b="${work_dir}/b.jsonl"
merged="${work_dir}/merged.jsonl"
compacted="${work_dir}/compacted.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$idx_a" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly"}
EOF

cat >"$idx_b" <<'EOF'
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"dup","json":"dup","log_dir":"dup","tag":"nightly"}
{"timestamp":"20260305_030000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"c","json":"c","log_dir":"c","tag":"ci"}
EOF

./scripts/readiness_report_index_merge.py --dedupe --out "$merged" "$idx_a" "$idx_b"
./scripts/readiness_report_index_compact.py --index "$merged" --out "$compacted" --keep 2

rg -n "20260305_030000" "$merged" >/dev/null
rg -n "20260305_020000" "$merged" >/dev/null
rg -n "20260305_010000" "$merged" >/dev/null
rg -n "20260305_030000" "$compacted" >/dev/null
rg -n "20260305_020000" "$compacted" >/dev/null

echo "OK: readiness index merge/compact smoke verified"
