#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-${ts}.log"
warm_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-warm-${ts}.run.log"
baseline_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-base-${ts}.run.log"
packed_scalar_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-packed-scalar-${ts}.run.log"
packed_fresh_simd_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-packed-fresh-simd-${ts}.run.log"
packed_reuse_work_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-packed-reuse-work-${ts}.run.log"
packed_simd_log="$log_dir/perf-probe-list-int-packed-bridge-read-split-packed-simd-${ts}.run.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
smoke="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_READ_SPLIT:-1}"
runs="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_RUNS:-2}"
warmups="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_WARMUPS:-0}"
n="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_N:-20000}"
short_reps="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_LONG_REPS:-2}"
baseline_programs="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_BASELINE_PROGRAMS:-dot_product_int}"
packed_programs="${OREN_LIST_INT_PACKED_BRIDGE_SPLIT_PACKED_PROGRAMS:-dot_product_int_packed_bridge}"

run_one() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
    local summary
    summary="$(rg -o 'summary: .*' "$run_log" | tail -n 1 | sed -E 's/^summary: //')"
    if [[ -z "$summary" ]]; then
        echo "failed to locate summary path in $run_log" >&2
        return 1
    fi
    printf '%s\n' "$summary"
}

warm_packed_builds() {
    OREN_PERF_PREBUILD_PROGRAMS=dot_product_int_packed_bridge ./scripts/build_perf_artifacts_list_int_packed_bridge.sh >"$warm_log" 2>&1
}

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"$log_dir/perf-probe-list-int-packed-bridge-read-split-list-int-smoke-${ts}.log" 2>&1
    OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND:-oren_c}" \
        ./scripts/run_perf_smoke_list_int_packed_bridge.sh >"$log_dir/perf-probe-list-int-packed-bridge-read-split-packed-smoke-${ts}.log" 2>&1
fi

baseline_summary="$(run_one "$baseline_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_PROGRAMS="$baseline_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"
warm_packed_builds
packed_scalar_summary="$(run_one "$packed_scalar_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_NO_SIMD=1 make perf-gate-list-int-read-split)"
packed_fresh_simd_summary="$(run_one "$packed_fresh_simd_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_ENABLE_SIMD=1 make perf-gate-list-int-read-split)"
packed_reuse_work_summary="$(run_one "$packed_reuse_work_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1,OREN_ENABLE_SIMD=1 make perf-gate-list-int-read-split)"
packed_simd_summary="$(run_one "$packed_simd_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_ENABLE_SIMD=1 make perf-gate-list-int-read-split)"

BASELINE_SUMMARY="$baseline_summary" \
PACKED_SCALAR_SUMMARY="$packed_scalar_summary" \
PACKED_FRESH_SIMD_SUMMARY="$packed_fresh_simd_summary" \
PACKED_REUSE_WORK_SUMMARY="$packed_reuse_work_summary" \
PACKED_SIMD_SUMMARY="$packed_simd_summary" \
BUILD_ENV="$build_env_raw" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
python3 - <<'PY' >"$summary_log"
import os
import re


def parse_summary(path):
    out = {}
    current = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            if not line.startswith(" "):
                if line.startswith("list<int> read split summary:"):
                    continue
                if line.startswith("build_env:"):
                    continue
                current = line.strip()
                out[current] = {}
                continue
            if current is None:
                continue
            m_long = re.match(r"\s+native/C long-per-rep ratio≈(-?[0-9.]+)x", line)
            if m_long:
                out[current]["long"] = float(m_long.group(1))
            m_delta = re.match(r"\s+native/C delta ratio≈(-?[0-9.]+)x", line)
            if m_delta:
                out[current]["delta"] = float(m_delta.group(1))
    return out


baseline = parse_summary(os.environ["BASELINE_SUMMARY"]).get("dot_product_int", {})
packed_scalar = parse_summary(os.environ["PACKED_SCALAR_SUMMARY"]).get("dot_product_int_packed_bridge", {})
packed_fresh_simd = parse_summary(os.environ["PACKED_FRESH_SIMD_SUMMARY"]).get("dot_product_int_packed_bridge", {})
packed_reuse_work = parse_summary(os.environ["PACKED_REUSE_WORK_SUMMARY"]).get("dot_product_int_packed_bridge", {})
packed_simd = parse_summary(os.environ["PACKED_SIMD_SUMMARY"]).get("dot_product_int_packed_bridge", {})

print("list<int> packed-bridge read-split probe summary")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"n: {os.environ['N']}")
print(f"short_reps: {os.environ['SHORT_REPS']}")
print(f"long_reps: {os.environ['LONG_REPS']}")
print("")
print(f"baseline_summary: {os.environ['BASELINE_SUMMARY']}")
print(f"packed_scalar_summary: {os.environ['PACKED_SCALAR_SUMMARY']}")
print(f"packed_fresh_simd_summary: {os.environ['PACKED_FRESH_SIMD_SUMMARY']}")
print(f"packed_reuse_work_summary: {os.environ['PACKED_REUSE_WORK_SUMMARY']}")
print(f"packed_simd_summary: {os.environ['PACKED_SIMD_SUMMARY']}")
print("")

cases = [
    ("baseline", baseline),
    ("packed_scalar", packed_scalar),
    ("packed_fresh_simd", packed_fresh_simd),
    ("packed_reuse_work", packed_reuse_work),
    ("packed_simd", packed_simd),
]
for name, data in cases:
    print(f"{name}:")
    for key, label in [("long", "long_per_rep"), ("delta", "delta")]:
        if key in data:
            print(f"  native/C_{label}: {data[key]:.4f}x")
    print("")

if "long" in baseline and "long" in packed_scalar:
    print(f"packed_scalar_vs_baseline_long_per_rep: {(packed_scalar['long'] / baseline['long']):.4f}x")
if "long" in baseline and "long" in packed_fresh_simd:
    print(f"packed_fresh_simd_vs_baseline_long_per_rep: {(packed_fresh_simd['long'] / baseline['long']):.4f}x")
if "long" in baseline and "long" in packed_reuse_work:
    print(f"packed_reuse_work_vs_baseline_long_per_rep: {(packed_reuse_work['long'] / baseline['long']):.4f}x")
if "long" in baseline and "long" in packed_simd:
    print(f"packed_simd_vs_baseline_long_per_rep: {(packed_simd['long'] / baseline['long']):.4f}x")
if "delta" in baseline and "delta" in packed_scalar:
    print(f"packed_scalar_vs_baseline_delta: {(packed_scalar['delta'] / baseline['delta']):.4f}x")
if "delta" in baseline and "delta" in packed_fresh_simd:
    print(f"packed_fresh_simd_vs_baseline_delta: {(packed_fresh_simd['delta'] / baseline['delta']):.4f}x")
if "delta" in baseline and "delta" in packed_reuse_work:
    print(f"packed_reuse_work_vs_baseline_delta: {(packed_reuse_work['delta'] / baseline['delta']):.4f}x")
if "delta" in baseline and "delta" in packed_simd:
    print(f"packed_simd_vs_baseline_delta: {(packed_simd['delta'] / baseline['delta']):.4f}x")
PY

echo "list<int> packed-bridge read-split probe complete; summary: $summary_log"
echo "warm log: $warm_log"
echo "baseline log: $baseline_log"
echo "packed-scalar log: $packed_scalar_log"
echo "packed-fresh-simd log: $packed_fresh_simd_log"
echo "packed-reuse-work log: $packed_reuse_work_log"
echo "packed-simd log: $packed_simd_log"
