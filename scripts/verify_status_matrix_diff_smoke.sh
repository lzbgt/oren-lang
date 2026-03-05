#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_matrix_diff_smoke"
left_status="${work_dir}/left.md"
right_status="${work_dir}/right.md"
out_md="${work_dir}/diff.md"
out_json="${work_dir}/diff.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$left_status" <<'DATA'
# Status

## Production readiness gap
- **Semantic maturity**: rolling.

### Backend readiness
- **C backend**: bootstrap path only.

### Feature readiness gaps
- **GMP concurrency (native)**: substrate only.
DATA

cat >"$right_status" <<'DATA'
# Status

## Production readiness gap
- **Semantic maturity**: rolling.
- **Performance parity**: hot loops above target.
  detail line

### Backend readiness
- **C backend**: bootstrap path only.

### Feature readiness gaps
- **GMP concurrency (native)**: substrate only.
- **Compiler-in-AVM**: design intent only.
DATA

./scripts/status_matrix_diff.py --left "$left_status" --right "$right_status" --out-md "$out_md" --out-json "$out_json"

rg -n "Status matrix diff" "$out_md" >/dev/null
rg -n "Production readiness gap" "$out_md" >/dev/null
rg -n "Performance parity" "$out_md" >/dev/null
rg -n "detail line" "$out_md" >/dev/null
rg -n "\"added\"" "$out_json" >/dev/null
rg -n "Compiler-in-AVM" "$out_json" >/dev/null

echo "OK: status matrix diff smoke verified"
