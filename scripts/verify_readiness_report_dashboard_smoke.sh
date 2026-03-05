#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_dashboard_smoke"
index_path="${work_dir}/readiness_index.jsonl"
out_html="${work_dir}/dashboard.html"
audit_json="${work_dir}/audit.json"
audit_trend_json="${work_dir}/audit_trend.json"
audit_samples_json="${work_dir}/audit_samples.json"
status_faq_json="${work_dir}/status_faq.json"
status_snapshot_json="${work_dir}/status_snapshot.json"
status_matrix_json="${work_dir}/status_matrix.json"
status_overview_md="${work_dir}/status_overview.md"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_010000.md","json":"build/reports/readiness_report_20260305_010000.json","log_dir":"build/logs/readiness_20260305_010000","tag":"nightly"}
{"timestamp":"20260305_120000","profile":"full","overall":"FAIL","dry_run":false,"total_duration_sec":120,"git_rev":"deadbeef","git_dirty":"dirty","report":"build/reports/readiness_report_20260305_120000.md","json":"build/reports/readiness_report_20260305_120000.json","log_dir":"build/logs/readiness_20260305_120000","tag":"ci","status_overview_md":"build/tmp/readiness_dashboard_smoke/status_overview.md"}
EOF

cat >"$audit_json" <<'EOF'
{"checked":2,"missing_any":0,"missing_report":0,"missing_json":0,"missing_log_dir":0,"samples":[]}
EOF

cat >"$audit_trend_json" <<'EOF'
{"window":5,"checked":2,"missing_any":1,"missing_by_kind":{"report":1,"json":0},"entries":[{"timestamp":"20260305_120000","profile":"full","tag":"ci","overall":"FAIL","missing_any":1,"missing":["report"]}]}
EOF

cat >"$audit_samples_json" <<'EOF'
{"samples":[{"timestamp":"20260305_120000","profile":"full","tag":"ci","missing":["report"]}]}
EOF

cat >"$status_faq_json" <<'EOF'
{"questions":[{"question":"Are the backends production-ready?","section_key":"backend_readiness","items_structured":[{"raw":"C backend: not production\\n  Native: rolling","lines":["C backend: not production","  Native: rolling"],"head":"C backend: not production","continuations":["  Native: rolling"]},{"raw":"Native backend: rolling","lines":["Native backend: rolling"],"head":"Native backend: rolling"}]}]}
EOF

cat >"$status_snapshot_json" <<'EOF'
{"sections":{"production_readiness_gap":{"title":"Production readiness gap","items_structured":[{"raw":"Semantic maturity: rolling\\n  detail","lines":["Semantic maturity: rolling","  detail"],"head":"Semantic maturity: rolling","continuations":["  detail"]},{"raw":"Performance parity: hot loops above target","lines":["Performance parity: hot loops above target"],"head":"Performance parity: hot loops above target"}]},"backend_readiness":{"title":"Backend readiness","items":["C backend: bootstrap path only"]},"feature_readiness_gaps":{"title":"Feature readiness gaps","items":["GMP concurrency: substrate only"]}}}
EOF

cat >"$status_matrix_json" <<'EOF'
{"sections":{"production_readiness_gap":[{"name":"Semantic maturity","notes":"rolling","notes_lines":["rolling"],"raw":"**Semantic maturity**: rolling."},{"name":"Performance parity","notes":"hot loops above target","notes_lines":["hot loops above target"],"raw":"**Performance parity**: hot loops above target."}],"backend_readiness":[{"name":"C backend","notes":"bootstrap path only","notes_lines":["bootstrap path only"],"raw":"**C backend**: bootstrap path only."}],"feature_readiness_gaps":[{"name":"GMP concurrency (native)","notes":"substrate only","notes_lines":["substrate only"],"raw":"**GMP concurrency (native)**: substrate only."}]}}
EOF

cat >"$status_overview_md" <<'EOF'
# Status Overview

## Status Snapshot
- Semantic maturity: rolling
EOF

./scripts/readiness_report_dashboard.py --index "$index_path" --out-html "$out_html" --limit 10 --rollup-days 7 --title "Smoke Dashboard" \
  --audit-json "$audit_json" --audit-trend-json "$audit_trend_json" --audit-samples-json "$audit_samples_json" \
  --status-faq-json "$status_faq_json" \
  --status-snapshot-json "$status_snapshot_json" \
  --status-matrix-json "$status_matrix_json" \
  --audit-samples-only-missing --audit-missing-threshold 2 --audit-trend-missing-threshold 2 \
  --audit-missing-warn-threshold 0 --audit-trend-missing-warn-threshold 0

rg -n "Smoke Dashboard" "$out_html" >/dev/null
rg -n "deadbeef" "$out_html" >/dev/null
rg -n "Daily rollup" "$out_html" >/dev/null
rg -n "Overview" "$out_html" >/dev/null
rg -n "Audit summary" "$out_html" >/dev/null
rg -n "Audit missing" "$out_html" >/dev/null
rg -n "class='ok'" "$out_html" >/dev/null
rg -n "Top missing \\(trend\\)" "$out_html" >/dev/null
rg -n "Audit trend" "$out_html" >/dev/null
rg -n "Missing by kind" "$out_html" >/dev/null
rg -n "Audit samples" "$out_html" >/dev/null
rg -n "Audit trend missing_any" "$out_html" >/dev/null
rg -n "Audit warnings" "$out_html" >/dev/null
rg -n "<li>Audit trend missing_any" "$out_html" >/dev/null
rg -n "Status FAQ" "$out_html" >/dev/null
rg -n "Are the backends production-ready" "$out_html" >/dev/null
rg -n "Native: rolling" "$out_html" >/dev/null
rg -n "Status Snapshot" "$out_html" >/dev/null
rg -n "Semantic maturity: rolling" "$out_html" >/dev/null
rg -n "Status Matrix" "$out_html" >/dev/null
rg -n "GMP concurrency" "$out_html" >/dev/null
rg -n "status_overview.md" "$out_html" >/dev/null

out_html_limit="${work_dir}/dashboard_limit.html"
./scripts/readiness_report_dashboard.py --index "$index_path" --out-html "$out_html_limit" --limit 10 --rollup-days 7 --title "Smoke Dashboard" \
  --audit-json "$audit_json" --audit-trend-json "$audit_trend_json" --audit-samples-json "$audit_samples_json" \
  --status-faq-json "$status_faq_json" \
  --status-snapshot-json "$status_snapshot_json" \
  --status-matrix-json "$status_matrix_json" \
  --status-max-items 1 \
  --audit-samples-only-missing --audit-missing-threshold 2 --audit-trend-missing-threshold 2 \
  --audit-missing-warn-threshold 0 --audit-trend-missing-warn-threshold 0
rg -n "truncated" "$out_html_limit" >/dev/null

echo "OK: readiness dashboard smoke verified"
