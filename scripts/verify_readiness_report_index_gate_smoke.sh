#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_gate_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_json="${work_dir}/gate.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":50,"git_rev":"abcd1234","git_dirty":"clean","report":"b","json":"b","log_dir":"b","tag":"nightly"}
{"timestamp":"20260305_030000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"c","json":"c","log_dir":"c","tag":"ci"}
EOF

./scripts/readiness_report_index_gate.py --index "$index_path" --window 3 --min-pass-rate 60 --max-fail-streak 1 --out-json "$out_json"

set +e
./scripts/readiness_report_index_gate.py --index "$index_path" --window 3 --min-pass-rate 80
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "expected gate to fail with min-pass-rate 80" >&2
  exit 2
fi

rg -n "\"pass_rate\"" "$out_json" >/dev/null

echo "OK: readiness index gate smoke verified"
