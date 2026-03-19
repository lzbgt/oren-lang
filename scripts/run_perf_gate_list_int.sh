#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-gate-list-int-${ts}.log"

programs="${OREN_BENCH_PROGRAMS:-array_sum_int,dot_product_int,multi_list_push_int}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
smoke="${OREN_PERF_SMOKE_LIST_INT:-1}"

export OREN_BENCH_PROGRAMS="$programs"
export OREN_BENCH_RUNS="$runs"
export OREN_BENCH_WARMUPS="$warmups"
export OREN_BENCH_SKIP_C="${OREN_BENCH_SKIP_C:-0}"
export OREN_BENCH_SKIP_OREN_C="${OREN_BENCH_SKIP_OREN_C:-0}"
export OREN_BENCH_SKIP_NATIVE="${OREN_BENCH_SKIP_NATIVE:-0}"
export OREN_BENCH_SKIP_OBC="${OREN_BENCH_SKIP_OBC:-0}"
export OREN_BENCH_UPDATE_LATEST="${OREN_BENCH_UPDATE_LATEST:-0}"
export OREN_BENCH_UPDATE_LATEST_PRUNE="${OREN_BENCH_UPDATE_LATEST_PRUNE:-0}"

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"${log_path%.log}.smoke.log" 2>&1
fi

python3 benchmarks/run_benchmarks.py >"$log_path" 2>&1

echo "list<int> perf gate benchmark complete; log: $log_path"
