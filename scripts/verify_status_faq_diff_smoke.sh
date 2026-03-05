#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_faq_diff_smoke"
left_status="${work_dir}/STATUS_left.md"
right_status="${work_dir}/STATUS_right.md"
out_md="${work_dir}/status_faq_diff.md"
out_json="${work_dir}/status_faq_diff.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$left_status" <<'EOF'
# Status

### Backend readiness (rolling snapshot)
- backend one

### Feature readiness gaps (requested)
- feature one
EOF

cat >"$right_status" <<'EOF'
# Status

### Backend readiness (rolling snapshot)
- backend one
- backend two

### Feature readiness gaps (requested)
- feature two
EOF

./scripts/status_faq_diff.py --left "$left_status" --right "$right_status" --out-md "$out_md" --out-json "$out_json"

rg -n "Status FAQ diff" "$out_md" >/dev/null
rg -n "backend two" "$out_md" >/dev/null
rg -n "feature one" "$out_md" >/dev/null
rg -n "\"questions\"" "$out_json" >/dev/null

echo "OK: status FAQ diff smoke verified"
