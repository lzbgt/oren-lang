#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-dot-ceiling-${ts}.log"
base_log="$log_dir/perf-probe-list-int-dot-ceiling-base-${ts}.run.log"
slot_warm_log="$log_dir/perf-probe-list-int-dot-ceiling-slot-warm-${ts}.run.log"
slot_log="$log_dir/perf-probe-list-int-dot-ceiling-slot-${ts}.run.log"
packed_warm_log="$log_dir/perf-probe-list-int-dot-ceiling-packed-warm-${ts}.run.log"
packed_scalar_log="$log_dir/perf-probe-list-int-dot-ceiling-packed-scalar-${ts}.run.log"
packed_simd_log="$log_dir/perf-probe-list-int-dot-ceiling-packed-simd-${ts}.run.log"
canonical_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-canonical-smoke-${ts}.log"
slot_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-slot-smoke-${ts}.log"
packed_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-packed-smoke-${ts}.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
baseline_programs="${OREN_LIST_INT_DOT_CEILING_BASELINE_PROGRAMS:-array_sum_int,dot_product_int}"
slot_programs="array_sum_int_slot_direct,dot_product_int_slot_direct"
packed_programs="array_sum_int_packed_bridge,dot_product_int_packed_bridge"
smoke="${OREN_PERF_SMOKE_LIST_INT:-1}"
runs="${OREN_LIST_INT_DOT_CEILING_RUNS:-2}"
warmups="${OREN_LIST_INT_DOT_CEILING_WARMUPS:-0}"
n="${OREN_LIST_INT_DOT_CEILING_N:-20000}"
reps="${OREN_LIST_INT_DOT_CEILING_REPS:-2}"

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

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"$canonical_smoke_log" 2>&1
    ./scripts/run_perf_smoke_list_int_slot_direct.sh >"$slot_smoke_log" 2>&1
    OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND=native \
        ./scripts/run_perf_smoke_list_int_packed_bridge.sh >"$packed_smoke_log" 2>&1
fi

baseline_summary="$(run_one "$base_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$baseline_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_STEADY_N="$n" OREN_BENCH_LIST_INT_STEADY_REPS="$reps" make perf-gate-list-int-steady)"
./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$slot_warm_log" 2>&1
slot_summary="$(run_one "$slot_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$slot_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_STEADY_N="$n" OREN_BENCH_LIST_INT_STEADY_REPS="$reps" make perf-gate-list-int-steady)"
./scripts/build_perf_artifacts_list_int_packed_bridge.sh >"$packed_warm_log" 2>&1
packed_scalar_summary="$(run_one "$packed_scalar_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_STEADY_N="$n" OREN_BENCH_LIST_INT_STEADY_REPS="$reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_NO_SIMD=1 make perf-gate-list-int-steady)"
packed_simd_summary="$(run_one "$packed_simd_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_STEADY_N="$n" OREN_BENCH_LIST_INT_STEADY_REPS="$reps" OREN_BENCH_ENV_OREN_NATIVE=OREN_ENABLE_SIMD=1 make perf-gate-list-int-steady)"

BASELINE_SUMMARY="$baseline_summary" \
SLOT_SUMMARY="$slot_summary" \
PACKED_SCALAR_SUMMARY="$packed_scalar_summary" \
PACKED_SIMD_SUMMARY="$packed_simd_summary" \
BUILD_ENV="$build_env_raw" \
SMOKE="$smoke" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
CANONICAL_SMOKE_LOG="$canonical_smoke_log" \
SLOT_SMOKE_LOG="$slot_smoke_log" \
PACKED_SMOKE_LOG="$packed_smoke_log" \
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
                if line.startswith("list<int> steady summary:"):
                    continue
                current = line.strip()
                continue
            if current is None:
                continue
            m = re.match(r"\s+native/C steady ratio≈([0-9.]+)x", line)
            if m:
                out[current] = float(m.group(1))
    return out


cases = [
    ("baseline", os.environ["BASELINE_SUMMARY"], ["array_sum_int", "dot_product_int"]),
    ("slot_direct", os.environ["SLOT_SUMMARY"], ["array_sum_int_slot_direct", "dot_product_int_slot_direct"]),
    ("packed_scalar", os.environ["PACKED_SCALAR_SUMMARY"], ["array_sum_int_packed_bridge", "dot_product_int_packed_bridge"]),
    ("packed_simd", os.environ["PACKED_SIMD_SUMMARY"], ["array_sum_int_packed_bridge", "dot_product_int_packed_bridge"]),
]

dot_keys = {
    "baseline": "dot_product_int",
    "slot_direct": "dot_product_int_slot_direct",
    "packed_scalar": "dot_product_int_packed_bridge",
    "packed_simd": "dot_product_int_packed_bridge",
}

array_keys = {
    "baseline": "array_sum_int",
    "slot_direct": "array_sum_int_slot_direct",
    "packed_scalar": "array_sum_int_packed_bridge",
    "packed_simd": "array_sum_int_packed_bridge",
}

parsed = {}
for name, path, _ in cases:
    parsed[name] = parse_summary(path)

baseline_dot = parsed["baseline"].get(dot_keys["baseline"])
baseline_array = parsed["baseline"].get(array_keys["baseline"])

print("list<int> dot-path ceiling probe summary")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"run_smoke: {os.environ['SMOKE']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"n: {os.environ['N']}")
print(f"reps: {os.environ['REPS']}")
print("")
if os.environ["SMOKE"] == "1":
    print(f"canonical_smoke_log: {os.environ['CANONICAL_SMOKE_LOG']}")
    print(f"slot_smoke_log: {os.environ['SLOT_SMOKE_LOG']}")
    print(f"packed_smoke_log: {os.environ['PACKED_SMOKE_LOG']}")
    print("")

for name, path, programs in cases:
    print(f"{name}: {path}")
    data = parsed[name]
    for program in programs:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C steady ratio≈{ratio:.4f}x")
    dot_ratio = data.get(dot_keys[name])
    if baseline_dot is not None and dot_ratio is not None and name != "baseline":
        print(f"  dot_vs_baseline: {(dot_ratio / baseline_dot):.4f}x")
    array_ratio = data.get(array_keys[name])
    if baseline_array is not None and array_ratio is not None and name != "baseline":
        print(f"  array_vs_baseline: {(array_ratio / baseline_array):.4f}x")
    print("")

ranking = []
for name in ["baseline", "slot_direct", "packed_scalar", "packed_simd"]:
    ratio = parsed[name].get(dot_keys[name])
    if ratio is not None:
        ranking.append((ratio, name))
ranking.sort()

print("dot_product_rank:")
for ratio, name in ranking:
    print(f"  {name}: {ratio:.4f}x")
PY

echo "list<int> dot-path ceiling probe complete; summary: $summary_log"
echo "base log: $base_log"
echo "slot warm log: $slot_warm_log"
echo "slot log: $slot_log"
echo "packed warm log: $packed_warm_log"
echo "packed scalar log: $packed_scalar_log"
echo "packed simd log: $packed_simd_log"
