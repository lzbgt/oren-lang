#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
short_log="$log_dir/perf-gate-native-read-split-short-${ts}.log"
long_log="$log_dir/perf-gate-native-read-split-long-${ts}.log"
summary_log="$log_dir/perf-gate-native-read-split-${ts}.log"
short_paths="$log_dir/perf-gate-native-read-split-short-${ts}.paths"
long_paths="$log_dir/perf-gate-native-read-split-long-${ts}.paths"

programs="${OREN_BENCH_PROGRAMS:-array_sum,dot_product}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
n="${OREN_BENCH_NATIVE_SPLIT_N:-2000000}"
short_reps="${OREN_BENCH_NATIVE_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_BENCH_NATIVE_SPLIT_LONG_REPS:-10}"
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

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_native_fast_loops.sh >"${summary_log%.log}.smoke.log" 2>&1
fi

export OREN_BENCH_ARGS="$n $short_reps"
python3 benchmarks/run_benchmarks.py >"$short_log" 2>&1
RUN_LOG="$short_log" python3 - <<'PY' >"$short_paths"
import os
want = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
seen = {}
with open(os.environ["RUN_LOG"], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line.endswith(".json"):
            continue
        base = os.path.basename(line)
        for w in want:
            if base.startswith(w + "_") and w not in seen:
                seen[w] = line
for w in want:
    print(w, seen[w])
PY

export OREN_BENCH_ARGS="$n $long_reps"
python3 benchmarks/run_benchmarks.py >"$long_log" 2>&1
RUN_LOG="$long_log" python3 - <<'PY' >"$long_paths"
import os
want = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
seen = {}
with open(os.environ["RUN_LOG"], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line.endswith(".json"):
            continue
        base = os.path.basename(line)
        for w in want:
            if base.startswith(w + "_") and w not in seen:
                seen[w] = line
for w in want:
    print(w, seen[w])
PY

SHORT_PATHS="$short_paths" LONG_PATHS="$long_paths" python3 - <<'PY' >"$summary_log"
import json, os

short_reps = int(os.environ.get("OREN_BENCH_NATIVE_SPLIT_SHORT_REPS", "1"))
long_reps = int(os.environ.get("OREN_BENCH_NATIVE_SPLIT_LONG_REPS", "10"))
delta_reps = long_reps - short_reps
if delta_reps <= 0:
    raise SystemExit("long reps must be greater than short reps")

def load_paths(path):
    out = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            program, json_path = line.split(" ", 1)
            out[program] = json_path
    return out

short = load_paths(os.environ["SHORT_PATHS"])
long = load_paths(os.environ["LONG_PATHS"])
variants = ["c", "oren_c", "oren_native"]

print(f"native read split summary: short_reps={short_reps} long_reps={long_reps}")
for program in short:
    s = json.load(open(short[program], "r", encoding="utf-8"))
    l = json.load(open(long[program], "r", encoding="utf-8"))
    print("")
    print(program)
    long_per_rep = {}
    for variant in variants:
        if variant not in s["results"] or variant not in l["results"]:
            continue
        short_med = s["results"][variant]["median_s"]
        long_med = l["results"][variant]["median_s"]
        steady = (long_med - short_med) / delta_reps
        setup = short_med - steady * short_reps
        long_rep = long_med / long_reps
        cov = l["results"][variant].get("cov", 0.0)
        long_per_rep[variant] = long_rep
        print(f"  {variant}: short={short_med:.6f}s long={long_med:.6f}s setup≈{setup:.6f}s delta≈{steady:.6f}s long/reps≈{long_rep:.6f}s cov={cov:.4f}")
    if "c" in long_per_rep and "oren_native" in long_per_rep:
        print(f"  native/C long-per-rep ratio≈{(long_per_rep['oren_native'] / long_per_rep['c']):.4f}x")
        c_short = s["results"]["c"]["median_s"]
        n_short = s["results"]["oren_native"]["median_s"]
        c_long = l["results"]["c"]["median_s"]
        n_long = l["results"]["oren_native"]["median_s"]
        c_steady = (c_long - c_short) / delta_reps
        n_steady = (n_long - n_short) / delta_reps
        print(f"  native/C delta ratio≈{(n_steady / c_steady):.4f}x")
PY

echo "native read split benchmark complete; summary: $summary_log"
echo "short run log: $short_log"
echo "long run log: $long_log"
