#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

SRC="tools/bench/bench_linalg_matmul_f32.oren"
OUT="build/bench_linalg_matmul_f32"

echo "[build] $SRC -> $OUT"
./oren build --backend=native --out="$OUT" "$SRC" >/dev/null

echo "[run] $OUT"
"$OUT"
