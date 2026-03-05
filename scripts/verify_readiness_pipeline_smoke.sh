#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_pipeline_smoke"
index_path="${work_dir}/readiness_index.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

./scripts/readiness_pipeline.sh --dry-run --index "$index_path" --tag smoke --summary-limit 5 --stats-limit 5

rg -n "\"tag\":\"smoke\"" "$index_path" >/dev/null
rg -n "Oren readiness summary" "build/reports/readiness_summary_dry_run.md" >/dev/null
rg -n "Readiness index stats" "build/reports/readiness_index_stats_dry_run.md" >/dev/null
rg -n "timestamp,profile,overall" "build/reports/readiness_index_dry_run.csv" >/dev/null
rg -n "Readiness rollup" "build/reports/readiness_rollup_dry_run.md" >/dev/null
rg -n "Oren readiness dashboard" "build/reports/readiness_dashboard_dry_run.html" >/dev/null

echo "OK: readiness pipeline smoke verified"
