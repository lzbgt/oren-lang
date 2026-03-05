#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_collect_pack_smoke"
collect_dir="${work_dir}/collect"
out_tar="${work_dir}/collect.tar.gz"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$collect_dir/sample"

printf "hello" > "$collect_dir/sample/readiness_report.md"

./scripts/readiness_report_collect_pack.py --dir "$collect_dir" --out "$out_tar" --prefix "collect"

tar -tzf "$out_tar" | rg -n "collect/sample/readiness_report.md" >/dev/null

echo "OK: readiness collect pack smoke verified"
