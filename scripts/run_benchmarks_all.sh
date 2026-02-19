#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d-%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/benchmarks-all-${ts}.log"

export OREN_BENCH_PROGRAM="${OREN_BENCH_PROGRAM:-all}"
export OREN_BENCH_UPDATE_LATEST="${OREN_BENCH_UPDATE_LATEST:-1}"
export OREN_BENCH_UPDATE_LATEST_PRUNE="${OREN_BENCH_UPDATE_LATEST_PRUNE:-1}"

python3 benchmarks/run_benchmarks.py >"$log_path" 2>&1

echo "benchmarks complete; log: $log_path"
