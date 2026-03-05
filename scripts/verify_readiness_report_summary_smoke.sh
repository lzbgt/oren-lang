#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_summary_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_md="${work_dir}/summary.md"
out_html="${work_dir}/summary.html"
status_faq_json="${work_dir}/status_faq.json"
status_snapshot_json="${work_dir}/status_snapshot.json"
status_matrix_json="${work_dir}/status_matrix.json"
status_overview_md="${work_dir}/status_overview.md"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$status_faq_json" <<'EOF'
{"questions":[{"question":"Are the backends production-ready?","section_key":"backend_readiness","items":["C backend: rolling","Native backend: rolling"]}]}
EOF

cat >"$status_snapshot_json" <<'EOF'
{"sections":{"production_readiness_gap":{"title":"Production readiness gap","items":["Semantic maturity: rolling"]}}}
EOF

cat >"$status_matrix_json" <<'EOF'
{"sections":{"production_readiness_gap":[{"name":"Semantic maturity","notes":"rolling","notes_lines":["rolling"],"raw":"**Semantic maturity**: rolling."}]}}
EOF

cat >"$status_overview_md" <<'EOF'
# Status Overview

## Status Snapshot
- Semantic maturity: rolling
EOF

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_210000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_210000.md","json":"build/reports/readiness_report_20260305_210000.json","log_dir":"build/logs/readiness_20260305_210000","tag":"nightly"}
{"timestamp":"20260306_010000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260306_010000.md","json":"build/reports/readiness_report_20260306_010000.json","log_dir":"build/logs/readiness_20260306_010000","tag":"ci","status_faq_json":"build/tmp/readiness_summary_smoke/status_faq.json","status_snapshot_json":"build/tmp/readiness_summary_smoke/status_snapshot.json","status_matrix_json":"build/tmp/readiness_summary_smoke/status_matrix.json","status_overview_md":"build/tmp/readiness_summary_smoke/status_overview.md"}
EOF

./scripts/readiness_report_summary.py --index "$index_path" --limit 10 --out-md "$out_md" --out-html "$out_html" --title "Smoke Summary"

rg -n "Smoke Summary" "$out_md" >/dev/null
rg -n "pass rate" "$out_md" >/dev/null
rg -n "2026-03-06" "$out_md" >/dev/null
rg -n "FAIL" "$out_md" >/dev/null
rg -n "Status FAQ" "$out_md" >/dev/null
rg -n "Status Snapshot" "$out_md" >/dev/null
rg -n "Status Matrix" "$out_md" >/dev/null
rg -n "status_overview.md" "$out_md" >/dev/null
rg -n "<title>Smoke Summary</title>" "$out_html" >/dev/null
rg -n "deadbeef" "$out_html" >/dev/null
rg -n "Status FAQ" "$out_html" >/dev/null
rg -n "Status Snapshot" "$out_html" >/dev/null
rg -n "status_overview.md" "$out_html" >/dev/null

out_md_no="${work_dir}/summary_no.md"
out_html_no="${work_dir}/summary_no.html"
./scripts/readiness_report_summary.py --index "$index_path" --limit 10 --out-md "$out_md_no" --out-html "$out_html_no" --title "Smoke Summary" --no-status-sections
! rg -n "Status FAQ" "$out_md_no" >/dev/null
! rg -n "Status Snapshot" "$out_md_no" >/dev/null
! rg -n "Status Matrix" "$out_md_no" >/dev/null
! rg -n "Status FAQ" "$out_html_no" >/dev/null
! rg -n "Status Snapshot" "$out_html_no" >/dev/null
! rg -n "Status Matrix" "$out_html_no" >/dev/null
rg -n "Status Matrix" "$out_html" >/dev/null

out_md_limit="${work_dir}/summary_limit.md"
out_html_limit="${work_dir}/summary_limit.html"
./scripts/readiness_report_summary.py --index "$index_path" --limit 10 --out-md "$out_md_limit" --out-html "$out_html_limit" --title "Smoke Summary" --status-max-items 1
rg -n "truncated" "$out_md_limit" >/dev/null

echo "OK: readiness summary smoke verified"
