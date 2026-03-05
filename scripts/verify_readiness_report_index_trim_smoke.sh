#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_trim_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_path="${work_dir}/trimmed.jsonl"
relative_out="trimmed_no_dir.jsonl"
repo_root="$(pwd)"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'DATA'
{"timestamp":"20260305_000000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260306_000000","profile":"quick","overall":"FAIL","dry_run":false,"total_duration_sec":41,"git_rev":"deadbeef","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"ci"}
{"timestamp":"20260307_000000","profile":"full","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"beadface","git_dirty":"dirty","report":"c","json":"c","log_dir":"c","tag":"ci"}
DATA

./scripts/readiness_report_index_trim.py --index "$index_path" --since "20260306_000000" --until "20260306_235959" --out "$out_path"
(cd "$work_dir" && "${repo_root}/scripts/readiness_report_index_trim.py" --index "readiness_index.jsonl" --since "20260306_000000" --until "20260306_235959" --out "$relative_out")

rg -n "20260306_000000" "$out_path" >/dev/null
! rg -n "20260305_000000" "$out_path" >/dev/null
! rg -n "20260307_000000" "$out_path" >/dev/null

lines=$(wc -l <"$out_path" | tr -d ' ')
if [[ "$lines" != "1" ]]; then
  echo "ERROR: expected 1 line after trim, got $lines" >&2
  exit 1
fi

if [[ ! -f "${work_dir}/${relative_out}" ]]; then
  echo "ERROR: expected ${relative_out} in work dir" >&2
  exit 1
fi

lines_rel=$(wc -l <"${work_dir}/${relative_out}" | tr -d ' ')
if [[ "$lines_rel" != "1" ]]; then
  echo "ERROR: expected 1 line after trim (relative), got $lines_rel" >&2
  exit 1
fi

echo "OK: readiness index trim smoke verified"
