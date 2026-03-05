#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/status_markdown_smoke"
status_path="${work_dir}/STATUS.md"
faq_json="${work_dir}/status_faq.json"
snapshot_json="${work_dir}/status_snapshot.json"
matrix_json="${work_dir}/status_matrix.json"
out_md="${work_dir}/status_overview.md"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$status_path" <<'DATA'
# Status

## Production readiness gap (rolling snapshot)
- **Semantic maturity**: tagged value model is rolling.
  continuation detail
- stability gap without label

### Backend readiness (rolling snapshot)
- **C backend**: bootstrap path only.
- **Native backend**: Tier-1 intent only.

### Feature readiness gaps (requested)
- **GMP concurrency (native)**: substrate only.
DATA

./scripts/status_faq.py --status "$status_path" --out-json "$faq_json" --out-md "${work_dir}/status_faq.md"
./scripts/status_snapshot.py --status "$status_path" --out-json "$snapshot_json" --out-md "${work_dir}/status_snapshot.md"
./scripts/status_matrix.py --status "$status_path" --out-json "$matrix_json" --out-md "${work_dir}/status_matrix.md"

./scripts/status_markdown_render.py \
  --faq-json "$faq_json" \
  --snapshot-json "$snapshot_json" \
  --matrix-json "$matrix_json" \
  --max-items 1 \
  --title "Status Overview" \
  --out-md "$out_md"

rg -n "# Status Overview" "$out_md" >/dev/null
rg -n "## Status FAQ" "$out_md" >/dev/null
rg -n "Are the backends production-ready" "$out_md" >/dev/null
rg -n "C backend" "$out_md" >/dev/null
rg -n "## Status Snapshot" "$out_md" >/dev/null
rg -n "Production readiness gap" "$out_md" >/dev/null
rg -n "continuation detail" "$out_md" >/dev/null
rg -n "## Status Matrix" "$out_md" >/dev/null
rg -n "Feature readiness gaps" "$out_md" >/dev/null
rg -n "GMP concurrency" "$out_md" >/dev/null
rg -n "truncated, 2 total" "$out_md" >/dev/null

echo "OK: status markdown smoke verified"
