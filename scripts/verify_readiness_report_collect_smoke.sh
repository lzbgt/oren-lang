#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_collect_smoke"
index_path="${work_dir}/readiness_index.jsonl"
report_path="${work_dir}/report.md"
report_json="${work_dir}/report.json"
log_dir="${work_dir}/logs"
status_md="${work_dir}/status.md"
status_json="${work_dir}/status.json"
collect_dir="${work_dir}/collect"
list_md="${work_dir}/collect_index.md"
list_json="${work_dir}/collect_index.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir" "$log_dir"

: > "$report_path"
: > "$report_json"
: > "$status_md"
: > "$status_json"

cat >"$index_path" <<EOF_INDEX
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"${report_path}","json":"${report_json}","log_dir":"${log_dir}","tag":"nightly","status_snapshot_md":"${status_md}","status_snapshot_json":"${status_json}"}
EOF_INDEX

./scripts/readiness_report_collect.py --index "$index_path" --out-dir "$collect_dir" --limit 1 --overwrite
./scripts/readiness_report_collect_list.py --dir "$collect_dir" --out "$list_md" --out-json "$list_json"

rg -n "Readiness collection" "$list_md" >/dev/null
rg -n "nightly" "$list_md" >/dev/null
rg -n "\"total\": 1" "$list_json" >/dev/null

snapshot_dir=$(ls "$collect_dir" | head -n 1)
if [[ ! -f "$collect_dir/$snapshot_dir/readiness_report.md" ]]; then
  echo "missing readiness_report.md" >&2
  exit 1
fi
if [[ ! -f "$collect_dir/$snapshot_dir/status_snapshot.md" ]]; then
  echo "missing status_snapshot.md" >&2
  exit 1
fi

echo "OK: readiness collect smoke verified"
