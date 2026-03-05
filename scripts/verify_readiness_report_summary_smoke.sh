#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_summary_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/summary.md"
out_html="${work_dir}/summary.html"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_210000.md","json":"build/reports/readiness_report_20260305_210000.json","log_dir":"build/logs/readiness_20260305_210000","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260306_010000.md","json":"build/reports/readiness_report_20260306_010000.json","log_dir":"build/logs/readiness_20260306_010000","tag":"ci"}
EOF

./scripts/readiness_report_summary.py --index "$index_path" --limit 10 --out-md "$out_md" --out-html "$out_html" --title "Smoke Summary"

rg -n "Smoke Summary" "$out_md" >/dev/null
rg -n "pass rate" "$out_md" >/dev/null
rg -n "2026-03-06" "$out_md" >/dev/null
rg -n "FAIL" "$out_md" >/dev/null
rg -n "<title>Smoke Summary</title>" "$out_html" >/dev/null
rg -n "deadbeef" "$out_html" >/dev/null

echo "OK: readiness summary smoke verified"
