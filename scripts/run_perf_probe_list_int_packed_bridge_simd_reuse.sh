#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-${ts}.log"
warm_log="$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-warm-${ts}.run.log"
baseline_log="$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-base-${ts}.run.log"
packed_simd_log="$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-packed-simd-${ts}.run.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
smoke="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_SIMD_REUSE:-${OREN_PERF_SMOKE_LIST_INT:-1}}"
runs="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_RUNS:-3}"
warmups="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_WARMUPS:-0}"
n="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_N:-20000}"
short_reps="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_LONG_REPS:-10}"
baseline_programs="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_BASELINE_PROGRAMS:-dot_product_int}"
packed_programs="${OREN_LIST_INT_PACKED_BRIDGE_SIMD_REUSE_PACKED_PROGRAMS:-dot_product_int_packed_bridge}"

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
    ./scripts/run_perf_smoke_list_int.sh >"$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-list-int-smoke-${ts}.log" 2>&1
    OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND:-oren_c}" \
        ./scripts/run_perf_smoke_list_int_packed_bridge.sh >"$log_dir/perf-probe-list-int-packed-bridge-simd-reuse-packed-smoke-${ts}.log" 2>&1
fi

baseline_summary="$(run_one "$baseline_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_PROGRAMS="$baseline_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"
warm_packed_builds
packed_simd_summary="$(run_one "$packed_simd_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_ENABLE_SIMD=1 make perf-gate-list-int-read-split)"

BASELINE_SUMMARY="$baseline_summary" \
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
            m = re.match(
                r"\s+oren_native: short=([0-9.]+)s long=([0-9.]+)s setup≈([0-9.\-]+)s delta≈([0-9.\-]+)s long/reps≈([0-9.]+)s cov=([0-9.]+)",
                line,
            )
            if m:
                out[current]["native_short"] = float(m.group(1))
                out[current]["native_long"] = float(m.group(2))
                out[current]["native_setup"] = float(m.group(3))
                out[current]["native_delta"] = float(m.group(4))
                out[current]["native_long_per_rep"] = float(m.group(5))
                out[current]["native_cov"] = float(m.group(6))
                continue
            m = re.match(r"\s+native/C delta ratio≈([0-9.\-]+)x", line)
            if m:
                out[current]["delta_ratio"] = float(m.group(1))
                continue
            m = re.match(r"\s+native/C long-per-rep ratio≈([0-9.\-]+)x", line)
            if m:
                out[current]["long_ratio"] = float(m.group(1))
                continue
            m = re.match(r"\s+warning: (.+)$", line)
            if m:
                out[current]["warning"] = m.group(1)
    return out


baseline = parse_summary(os.environ["BASELINE_SUMMARY"]).get("dot_product_int", {})
packed_simd = parse_summary(os.environ["PACKED_SIMD_SUMMARY"]).get("dot_product_int_packed_bridge", {})

print("list<int> packed-bridge SIMD reuse probe summary")
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
print(f"packed_simd_summary: {os.environ['PACKED_SIMD_SUMMARY']}")
print("")

for name, data in [("baseline", baseline), ("packed_simd", packed_simd)]:
    print(f"{name}:")
    for key in [
        "native_short",
        "native_long",
        "native_setup",
        "native_delta",
        "native_long_per_rep",
        "native_cov",
        "delta_ratio",
        "long_ratio",
    ]:
        if key in data:
            print(f"  {key}: {data[key]:.6f}" if isinstance(data[key], float) else f"  {key}: {data[key]}")
    if "warning" in data:
        print(f"  warning: {data['warning']}")
    print("")

if "native_long_per_rep" in baseline and "native_long_per_rep" in packed_simd:
    print(
        "packed_simd_vs_baseline_long_per_rep: "
        f"{(packed_simd['native_long_per_rep'] / baseline['native_long_per_rep']):.4f}x"
    )
if "native_delta" in baseline and "native_delta" in packed_simd and baseline["native_delta"] != 0:
    print(
        "packed_simd_vs_baseline_delta: "
        f"{(packed_simd['native_delta'] / baseline['native_delta']):.4f}x"
    )
PY

echo "list<int> packed-bridge SIMD reuse probe complete; summary: $summary_log"
echo "warm log: $warm_log"
echo "baseline log: $baseline_log"
echo "packed-simd log: $packed_simd_log"
