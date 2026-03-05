#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_schema_smoke"
index_path="${work_dir}/readiness_index.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":42,"git_rev":"abcd1234","git_dirty":"clean","report":"build/reports/readiness_report_20260305_010000.md","json":"build/reports/readiness_report_20260305_010000.json","log_dir":"build/logs/readiness_20260305_010000","status_faq_md":"build/reports/status_faq_20260305_010000.md","status_faq_json":"build/reports/status_faq_20260305_010000.json","tag":"nightly"}
EOF

./scripts/readiness_report_index_validate_schema.py --index "$index_path" --schema "docs/readiness_index.schema.json"

echo "OK: readiness index schema smoke verified"
