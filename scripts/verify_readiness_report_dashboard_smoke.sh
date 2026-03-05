#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_dashboard_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_html="${work_dir}/dashboard.html"
audit_json="${work_dir}/audit.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_010000.md","json":"build/reports/readiness_report_20260305_010000.json","log_dir":"build/logs/readiness_20260305_010000","tag":"nightly"}
{"timestamp":"20260305_120000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260305_120000.md","json":"build/reports/readiness_report_20260305_120000.json","log_dir":"build/logs/readiness_20260305_120000","tag":"ci"}
EOF

cat >"$audit_json" <<'EOF'
{"checked":2,"missing_any":0,"missing_report":0,"missing_json":0,"missing_log_dir":0,"samples":[]}
EOF

./scripts/readiness_report_dashboard.py --index "$index_path" --out-html "$out_html" --limit 10 --rollup-days 7 --title "Smoke Dashboard" \
  --audit-json "$audit_json"

rg -n "Smoke Dashboard" "$out_html" >/dev/null
rg -n "deadbeef" "$out_html" >/dev/null
rg -n "Daily rollup" "$out_html" >/dev/null
rg -n "Audit summary" "$out_html" >/dev/null
rg -n "Audit missing" "$out_html" >/dev/null
rg -n "class='ok'" "$out_html" >/dev/null

echo "OK: readiness dashboard smoke verified"
