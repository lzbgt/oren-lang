#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_snapshot_diff_smoke"
left_status="${work_dir}/STATUS_left.md"
right_status="${work_dir}/STATUS_right.md"
out_md="${work_dir}/diff.md"
out_json="${work_dir}/diff.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$left_status" <<'DATA'
# Status

## Production readiness gap (rolling snapshot)
- item one
- item two

### Backend readiness (rolling snapshot)
- backend one

### Feature readiness gaps (requested)
- feature one
DATA

cat >"$right_status" <<'DATA'
# Status

## Production readiness gap (rolling snapshot)
- item two
- item three

### Backend readiness (rolling snapshot)
- backend one
- backend two

### Feature readiness gaps (requested)
- feature two
DATA

./scripts/status_snapshot_diff.py --left "$left_status" --right "$right_status" --out-md "$out_md" --out-json "$out_json"

rg -n "Status snapshot diff" "$out_md" >/dev/null
rg -n "item three" "$out_md" >/dev/null
rg -n "item one" "$out_md" >/dev/null
rg -n "backend two" "$out_md" >/dev/null
rg -n "feature two" "$out_md" >/dev/null
rg -n "production_readiness_gap" "$out_json" >/dev/null
rg -n "backend_readiness" "$out_json" >/dev/null
rg -n "feature_readiness_gaps" "$out_json" >/dev/null

echo "OK: status snapshot diff smoke verified"
