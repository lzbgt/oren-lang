#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_collect_list_smoke"
collect_dir="${work_dir}/collect"
out_md="${work_dir}/collect_index.md"
out_json="${work_dir}/collect_index.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$collect_dir/sample"

cat >"${collect_dir}/sample/snapshot.json" <<'EOF'
{
  "timestamp": "20260306_010000",
  "profile": "quick",
  "tag": "nightly",
  "overall": "PASS",
  "report": "readiness_report.md",
  "json": "readiness_report.json",
  "status_snapshot_md": "status_snapshot.md",
  "status_snapshot_json": "status_snapshot.json",
  "status_faq_md": "status_faq.md",
  "status_faq_json": "status_faq.json",
  "status_matrix_md": "status_matrix.md",
  "status_matrix_json": "status_matrix.json",
  "status_overview_md": "status_overview.md",
  "log_dir": "logs"
}
EOF

./scripts/readiness_report_collect_list.py --dir "$collect_dir" --out "$out_md" --out-json "$out_json"

rg -n "Readiness collection" "$out_md" >/dev/null
rg -n "20260306_010000" "$out_md" >/dev/null
rg -n "\"total\": 1" "$out_json" >/dev/null

echo "OK: readiness collect list smoke verified"
