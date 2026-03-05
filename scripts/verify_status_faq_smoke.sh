#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_faq_smoke"
status_path="${work_dir}/STATUS.md"
out_md="${work_dir}/status_faq.md"
out_json="${work_dir}/status_faq.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$status_path" <<'EOF'
# Status

## Production readiness gap (rolling snapshot)
- gap one

### Backend readiness (rolling snapshot)
- backend one
- backend two

### Feature readiness gaps (requested)
- feature one
  feature detail
EOF

./scripts/status_faq.py --status "$status_path" --out-md "$out_md" --out-json "$out_json"

rg -n "Status FAQ" "$out_md" >/dev/null
rg -n "Are the backends production-ready" "$out_md" >/dev/null
rg -n "backend one" "$out_md" >/dev/null
rg -n "Which feature readiness gaps are still open" "$out_md" >/dev/null
rg -n "feature one" "$out_md" >/dev/null
rg -n "feature detail" "$out_md" >/dev/null
rg -n "production readiness gaps" "$out_md" >/dev/null
rg -n "gap one" "$out_md" >/dev/null
rg -n "\"question\"" "$out_json" >/dev/null
rg -n "\"backend_readiness\"" "$out_json" >/dev/null
rg -n "feature detail" "$out_json" >/dev/null

echo "OK: status faq smoke verified"
