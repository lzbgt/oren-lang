#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_snapshot_smoke"
status_path="${work_dir}/STATUS.md"
out_md="${work_dir}/snapshot.md"
out_json="${work_dir}/snapshot.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$status_path" <<'DATA'
# Status

## Production readiness gap (rolling snapshot)
- item one
- item two
  continuation line
  - nested bullet

### Backend readiness (rolling snapshot)
- backend one

### Feature readiness gaps (requested)
- feature one
DATA

./scripts/status_snapshot.py --status "$status_path" --out-md "$out_md" --out-json "$out_json"

rg -n "Status snapshot" "$out_md" >/dev/null
rg -n "item one" "$out_md" >/dev/null
rg -n "backend one" "$out_md" >/dev/null
rg -n "feature one" "$out_md" >/dev/null
rg -n "continuation line" "$out_md" >/dev/null
rg -n "nested bullet" "$out_md" >/dev/null
rg -n "production_readiness_gap" "$out_json" >/dev/null
rg -n "backend_readiness" "$out_json" >/dev/null
rg -n "feature_readiness_gaps" "$out_json" >/dev/null

echo "OK: status snapshot smoke verified"
