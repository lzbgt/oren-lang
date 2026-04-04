#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
bench_log="$log_dir/perf-gate-native-steady-${ts}.bench.log"
summary_log="$log_dir/perf-gate-native-steady-${ts}.log"

programs="${OREN_BENCH_PROGRAMS:-array_sum,dot_product}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
n="${OREN_BENCH_NATIVE_STEADY_N:-2000000}"
reps="${OREN_BENCH_NATIVE_STEADY_REPS:-100}"
smoke="${OREN_PERF_SMOKE_NATIVE_FAST_LOOPS:-1}"

export OREN_BENCH_PROGRAMS="$programs"
export OREN_BENCH_RUNS="$runs"
export OREN_BENCH_WARMUPS="$warmups"
export OREN_BENCH_SKIP_C="${OREN_BENCH_SKIP_C:-0}"
export OREN_BENCH_SKIP_OREN_C="${OREN_BENCH_SKIP_OREN_C:-1}"
export OREN_BENCH_SKIP_NATIVE="${OREN_BENCH_SKIP_NATIVE:-0}"
export OREN_BENCH_SKIP_OBC=1
export OREN_BENCH_UPDATE_LATEST=0
export OREN_BENCH_UPDATE_LATEST_PRUNE=0
export OREN_BENCH_ARGS="$n $reps"

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_native_fast_loops.sh >"${summary_log%.log}.smoke.log" 2>&1
fi

python3 benchmarks/run_benchmarks.py >"$bench_log" 2>&1

BENCH_LOG="$bench_log" python3 - <<'PY' >"$summary_log"
import json, os

programs = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
reps = int(os.environ.get("OREN_BENCH_NATIVE_STEADY_REPS", "100"))
paths = {}
with open(os.environ["BENCH_LOG"], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line.endswith(".json"):
            continue
        base = os.path.basename(line)
        for program in programs:
            if base.startswith(program + "_") and program not in paths:
                paths[program] = line

print(f"native steady summary: reps={reps}")
for program in programs:
    data = json.load(open(paths[program], "r", encoding="utf-8"))
    results = data["results"]
    print("")
    print(program)
    for variant in ["c", "oren_c", "oren_native"]:
        if variant not in results:
            continue
        med = results[variant]["median_s"]
        cov = results[variant].get("cov", 0.0)
        print(f"  {variant}: median={med:.6f}s per_rep≈{(med / reps):.6f}s cov={cov:.4f}")
    if "c" in results and "oren_native" in results:
        c = results["c"]["median_s"] / reps
        n = results["oren_native"]["median_s"] / reps
        print(f"  native/C steady ratio≈{(n / c):.4f}x")
    if "c" in results and "oren_c" in results:
        c = results["c"]["median_s"] / reps
        oc = results["oren_c"]["median_s"] / reps
        print(f"  oren_c/C steady ratio≈{(oc / c):.4f}x")
PY

echo "native steady benchmark complete; summary: $summary_log"
echo "bench log: $bench_log"
