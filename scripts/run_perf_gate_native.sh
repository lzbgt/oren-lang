#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
bench_log="$log_dir/perf-gate-native-${ts}.log"
summary_log="$log_dir/perf-gate-native-${ts}.summary.log"

programs="${OREN_BENCH_PROGRAMS:-loop_sum,dot_product,alloc_churn,alloc_drop}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
cov_warn="${OREN_BENCH_COV_WARN:-0.10}"

export OREN_BENCH_PROGRAMS="$programs"
export OREN_BENCH_RUNS="$runs"
export OREN_BENCH_WARMUPS="$warmups"
export OREN_BENCH_SKIP_OBC="${OREN_BENCH_SKIP_OBC:-1}"
export OREN_BENCH_SKIP_OREN_C="${OREN_BENCH_SKIP_OREN_C:-1}"
export OREN_BENCH_UPDATE_LATEST="${OREN_BENCH_UPDATE_LATEST:-0}"
export OREN_BENCH_UPDATE_LATEST_PRUNE="${OREN_BENCH_UPDATE_LATEST_PRUNE:-0}"

python3 benchmarks/run_benchmarks.py >"$bench_log" 2>&1

BENCH_LOG="$bench_log" OREN_BENCH_COV_WARN="$cov_warn" python3 - <<'PY' >"$summary_log"
import json, os

programs = [p for p in os.environ["OREN_BENCH_PROGRAMS"].replace(",", " ").split() if p]
cov_warn = float(os.environ.get("OREN_BENCH_COV_WARN", "0.10"))
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

print(f"native gate summary: runs={os.environ['OREN_BENCH_RUNS']} warmups={os.environ['OREN_BENCH_WARMUPS']}")
for program in programs:
    if program not in paths:
        continue
    data = json.load(open(paths[program], "r", encoding="utf-8"))
    results = data["results"]
    print("")
    print(program)
    for variant in ["c", "oren_c", "oren_native"]:
        if variant not in results:
            continue
        med = results[variant]["median_s"]
        cov = results[variant].get("cov", 0.0)
        print(f"  {variant}: median={med:.6f}s cov={cov:.4f}")
    if "c" in results and "oren_native" in results:
        c = results["c"]["median_s"]
        n = results["oren_native"]["median_s"]
        print(f"  native/C median ratio={n / c:.4f}x")
        c_cov = results["c"].get("cov", 0.0)
        n_cov = results["oren_native"].get("cov", 0.0)
        if c_cov >= cov_warn or n_cov >= cov_warn:
            print(f"  warning: high gate variance (c cov={c_cov:.4f}, native cov={n_cov:.4f})")
    if "c" in results and "oren_c" in results:
        c = results["c"]["median_s"]
        oc = results["oren_c"]["median_s"]
        print(f"  oren_c/C median ratio={oc / c:.4f}x")
PY

echo "perf gate benchmark complete; log: $bench_log"
echo "summary: $summary_log"
