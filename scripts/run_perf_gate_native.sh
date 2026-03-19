#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-gate-native-${ts}.log"

programs="${OREN_BENCH_PROGRAMS:-loop_sum,dot_product,alloc_churn,alloc_drop}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"

export OREN_BENCH_PROGRAMS="$programs"
export OREN_BENCH_RUNS="$runs"
export OREN_BENCH_WARMUPS="$warmups"
export OREN_BENCH_SKIP_OBC="${OREN_BENCH_SKIP_OBC:-1}"
export OREN_BENCH_SKIP_OREN_C="${OREN_BENCH_SKIP_OREN_C:-1}"
export OREN_BENCH_UPDATE_LATEST="${OREN_BENCH_UPDATE_LATEST:-0}"
export OREN_BENCH_UPDATE_LATEST_PRUNE="${OREN_BENCH_UPDATE_LATEST_PRUNE:-0}"

python3 benchmarks/run_benchmarks.py >"$log_path" 2>&1

echo "perf gate benchmark complete; log: $log_path"
