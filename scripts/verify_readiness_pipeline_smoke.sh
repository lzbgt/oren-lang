#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_pipeline_smoke"
index_path="${work_dir}/readiness_index.jsonl"
log_path="${work_dir}/pipeline.log"
baseline="${work_dir}/baseline.jsonl"
status_path="${work_dir}/STATUS.md"
status_baseline="${work_dir}/STATUS_baseline.md"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$baseline" <<'EOF'
{"timestamp":"20260304_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
EOF

cat >"$status_path" <<'EOF'
# Status

## Production readiness gap (rolling snapshot)
- item one

### Backend readiness (rolling snapshot)
- backend one

### Feature readiness gaps (requested)
- feature one
EOF

cat >"$status_baseline" <<'EOF'
# Status

## Production readiness gap (rolling snapshot)
- item zero

### Backend readiness (rolling snapshot)
- backend zero

### Feature readiness gaps (requested)
- feature zero
EOF

./scripts/readiness_pipeline.sh --dry-run --index "$index_path" --tag smoke --summary-limit 5 --stats-limit 5 --log "$log_path" \
  --diff-against "$baseline" --gate-pass-rate 50 --gate-window 1 --trim-since-days 1 \
  --status-path "$status_path" --status-diff-against "$status_baseline" --audit --audit-allow-missing

rg -n "\"tag\":\"smoke\"" "$index_path" >/dev/null
rg -n "Oren readiness summary" "build/reports/readiness_summary_dry_run.md" >/dev/null
rg -n "Readiness index stats" "build/reports/readiness_index_stats_dry_run.md" >/dev/null
rg -n "timestamp,profile,overall" "build/reports/readiness_index_dry_run.csv" >/dev/null
rg -n "Readiness rollup" "build/reports/readiness_rollup_dry_run.md" >/dev/null
rg -n "Oren readiness dashboard" "build/reports/readiness_dashboard_dry_run.html" >/dev/null
rg -n "OK: readiness index schema validated" "$log_path" >/dev/null
rg -n "Readiness index summary diff" "build/reports/readiness_index_diff_summary_dry_run.md" >/dev/null
rg -n "Status snapshot" "build/reports/status_snapshot_dry_run.md" >/dev/null
rg -n "Status snapshot diff" "build/reports/status_snapshot_diff_dry_run.md" >/dev/null
rg -n "Readiness index latest" "build/reports/readiness_index_latest_dry_run.md" >/dev/null
rg -n "Readiness index trend" "build/reports/readiness_index_trend_dry_run.md" >/dev/null
rg -n "Trend window" "build/reports/readiness_dashboard_dry_run.html" >/dev/null
rg -n "Readiness index profiles" "build/reports/readiness_index_profiles_dry_run.md" >/dev/null
rg -n "Readiness index tags" "build/reports/readiness_index_tags_dry_run.md" >/dev/null
rg -n "Readiness index audit" "build/reports/readiness_index_audit_dry_run.md" >/dev/null

echo "OK: readiness pipeline smoke verified"
