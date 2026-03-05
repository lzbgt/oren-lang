#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_matrix_smoke"
status_path="${work_dir}/STATUS.md"
out_md="${work_dir}/matrix.md"
out_json="${work_dir}/matrix.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$status_path" <<'DATA'
# Status

## Production readiness gap (rolling snapshot)
- **Semantic maturity**: tagged value model is rolling.
  continuation detail
  - nested note
- stability gap without label

### Backend readiness (rolling snapshot)
- **C backend**: bootstrap path only.

### Feature readiness gaps (requested)
- **GMP concurrency (native)**: substrate only.
DATA

./scripts/status_matrix.py --status "$status_path" --out-md "$out_md" --out-json "$out_json"

rg -n "Status readiness matrix" "$out_md" >/dev/null
rg -n "Production readiness gap" "$out_md" >/dev/null
rg -n "Backend readiness" "$out_md" >/dev/null
rg -n "Feature readiness gaps" "$out_md" >/dev/null
rg -n "C backend" "$out_md" >/dev/null
rg -n "GMP concurrency" "$out_md" >/dev/null
rg -n "continuation detail" "$out_md" >/dev/null
rg -n "\"backend_readiness\"" "$out_json" >/dev/null
rg -n "\"name\": \"C backend\"" "$out_json" >/dev/null
rg -n "\"name\": \"item-2\"" "$out_json" >/dev/null
rg -n "continuation detail" "$out_json" >/dev/null

echo "OK: status matrix smoke verified"
