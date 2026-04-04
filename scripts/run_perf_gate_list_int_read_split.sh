#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
short_log="$log_dir/perf-gate-list-int-read-split-short-${ts}.log"
long_log="$log_dir/perf-gate-list-int-read-split-long-${ts}.log"
summary_log="$log_dir/perf-gate-list-int-read-split-${ts}.log"
short_paths="$log_dir/perf-gate-list-int-read-split-short-${ts}.paths"
long_paths="$log_dir/perf-gate-list-int-read-split-long-${ts}.paths"

programs="${OREN_BENCH_PROGRAMS:-array_sum_int,dot_product_int}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
n="${OREN_BENCH_LIST_INT_SPLIT_N:-2000000}"
short_reps="${OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_BENCH_LIST_INT_SPLIT_LONG_REPS:-10}"
smoke="${OREN_PERF_SMOKE_LIST_INT:-1}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"

export OREN_BENCH_PROGRAMS="$programs"
export OREN_BENCH_RUNS="$runs"
export OREN_BENCH_WARMUPS="$warmups"
export OREN_BENCH_SKIP_C="${OREN_BENCH_SKIP_C:-0}"
export OREN_BENCH_SKIP_OREN_C="${OREN_BENCH_SKIP_OREN_C:-0}"
export OREN_BENCH_SKIP_NATIVE="${OREN_BENCH_SKIP_NATIVE:-0}"
export OREN_BENCH_SKIP_OBC="${OREN_BENCH_SKIP_OBC:-1}"
export OREN_BENCH_UPDATE_LATEST=0
export OREN_BENCH_UPDATE_LATEST_PRUNE=0

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"${summary_log%.log}.smoke.log" 2>&1
fi

export OREN_BENCH_ARGS="$n $short_reps"
python3 benchmarks/run_benchmarks.py >"$short_log" 2>&1
python3 - <<'PY' >"$short_paths"
import glob, os
want = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
files = sorted(glob.glob('build/benchmarks/results/*_darwin_arm64_*.json'), key=os.path.getmtime, reverse=True)
seen = {}
for f in files:
    b = os.path.basename(f)
    for w in want:
        if b.startswith(w + "_") and w not in seen:
            seen[w] = f
for w in want:
    print(w, seen[w])
PY

export OREN_BENCH_ARGS="$n $long_reps"
python3 benchmarks/run_benchmarks.py >"$long_log" 2>&1
python3 - <<'PY' >"$long_paths"
import glob, os
want = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
files = sorted(glob.glob('build/benchmarks/results/*_darwin_arm64_*.json'), key=os.path.getmtime, reverse=True)
seen = {}
for f in files:
    b = os.path.basename(f)
    for w in want:
        if b.startswith(w + "_") and w not in seen:
            seen[w] = f
for w in want:
    print(w, seen[w])
PY

SHORT_PATHS="$short_paths" LONG_PATHS="$long_paths" python3 - <<'PY' >"$summary_log"
import json, os
short_reps = int(os.environ["OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS"] if "OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS" in os.environ else "1")
long_reps = int(os.environ["OREN_BENCH_LIST_INT_SPLIT_LONG_REPS"] if "OREN_BENCH_LIST_INT_SPLIT_LONG_REPS" in os.environ else "10")
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

print(f"list<int> read split summary: short_reps={short_reps} long_reps={long_reps}")
build_env = os.environ.get("OREN_BENCH_ENV_BUILD_OREN", "")
if build_env:
    print(f"build_env: {build_env}")
for program in short:
    s = json.load(open(short[program], "r", encoding="utf-8"))
    l = json.load(open(long[program], "r", encoding="utf-8"))
    print("")
    print(program)
    long_per_rep = {}
    delta_per_rep = {}
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
        delta_per_rep[variant] = steady
        print(f"  {variant}: short={short_med:.6f}s long={long_med:.6f}s setup≈{setup:.6f}s delta≈{steady:.6f}s long/reps≈{long_rep:.6f}s cov={cov:.4f}")
    if "c" in s["results"] and "oren_native" in s["results"] and "c" in l["results"] and "oren_native" in l["results"]:
        c_short = s["results"]["c"]["median_s"]
        n_short = s["results"]["oren_native"]["median_s"]
        c_long = l["results"]["c"]["median_s"]
        n_long = l["results"]["oren_native"]["median_s"]
        c_steady = (c_long - c_short) / delta_reps
        n_steady = (n_long - n_short) / delta_reps
        print(f"  native/C delta ratio≈{(n_steady / c_steady):.4f}x")
        if "c" in long_per_rep and "oren_native" in long_per_rep:
            print(f"  native/C long-per-rep ratio≈{(long_per_rep['oren_native'] / long_per_rep['c']):.4f}x")
        if "c" in long_per_rep and "oren_c" in long_per_rep:
            print(f"  oren_c/C long-per-rep ratio≈{(long_per_rep['oren_c'] / long_per_rep['c']):.4f}x")
        if "c" in long_per_rep and "oren_native" in long_per_rep:
            delta_ratio = n_steady / c_steady
            long_ratio = long_per_rep["oren_native"] / long_per_rep["c"]
            if long_ratio > 0:
                drift = abs(delta_ratio - long_ratio) / long_ratio
                if drift > 0.25:
                    print(f"  warning: delta-vs-long steady estimate drift={drift:.2%}; prefer long-per-rep for tracker updates")
PY

echo "list<int> read split benchmark complete; summary: $summary_log"
echo "short run log: $short_log"
echo "long run log: $long_log"
