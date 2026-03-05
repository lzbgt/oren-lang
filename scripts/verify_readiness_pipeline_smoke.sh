#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_pipeline_smoke"
index_path="${work_dir}/readiness_index.jsonl"
log_path="${work_dir}/pipeline.log"
baseline="${work_dir}/baseline.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$baseline" <<'EOF'
{"timestamp":"20260304_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
EOF

./scripts/readiness_pipeline.sh --dry-run --index "$index_path" --tag smoke --summary-limit 5 --stats-limit 5 --log "$log_path" \
  --diff-against "$baseline" --gate-pass-rate 50 --gate-window 1 --trim-since-days 1

rg -n "\"tag\":\"smoke\"" "$index_path" >/dev/null
rg -n "Oren readiness summary" "build/reports/readiness_summary_dry_run.md" >/dev/null
rg -n "Readiness index stats" "build/reports/readiness_index_stats_dry_run.md" >/dev/null
rg -n "timestamp,profile,overall" "build/reports/readiness_index_dry_run.csv" >/dev/null
rg -n "Readiness rollup" "build/reports/readiness_rollup_dry_run.md" >/dev/null
rg -n "Oren readiness dashboard" "build/reports/readiness_dashboard_dry_run.html" >/dev/null
rg -n "OK: readiness index schema validated" "$log_path" >/dev/null
rg -n "Readiness index summary diff" "build/reports/readiness_index_diff_summary_dry_run.md" >/dev/null
rg -n "Status snapshot" "build/reports/status_snapshot_dry_run.md" >/dev/null

echo "OK: readiness pipeline smoke verified"
