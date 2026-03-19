#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-packed-bridge-${ts}.log"
warm_log="$log_dir/perf-probe-list-int-packed-bridge-warm-${ts}.run.log"
base_log="$log_dir/perf-probe-list-int-packed-bridge-base-${ts}.run.log"
packed_scalar_log="$log_dir/perf-probe-list-int-packed-bridge-packed-scalar-${ts}.run.log"
packed_simd_log="$log_dir/perf-probe-list-int-packed-bridge-packed-simd-${ts}.run.log"
packed_programs="array_sum_int_packed_bridge,dot_product_int_packed_bridge"

if [[ "${OREN_PERF_SMOKE_LIST_INT:-1}" == "1" ]]; then
    OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND:-oren_c}" \
        ./scripts/run_perf_smoke_list_int_packed_bridge.sh >"$log_dir/perf-probe-list-int-packed-bridge-smoke-${ts}.log" 2>&1
fi

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
    env \
        OREN_BENCH_PROGRAMS="$packed_programs" \
        OREN_BENCH_SKIP_OREN_C=1 \
        OREN_BENCH_SKIP_OBC=1 \
        OREN_BENCH_RUNS=1 \
        OREN_BENCH_WARMUPS=0 \
        OREN_BENCH_ENV_BUILD_OREN=OREN_NATIVE_RUNTIME_PROFILE=full \
        python3 benchmarks/run_benchmarks.py >"$warm_log" 2>&1
}

baseline_summary="$(run_one "$base_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_OREN_C=1 make perf-gate-list-int-steady)"
warm_packed_builds
packed_scalar_summary="$(run_one "$packed_scalar_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_ENV_BUILD_OREN=OREN_NATIVE_RUNTIME_PROFILE=full OREN_BENCH_ENV_OREN_NATIVE=OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_NO_SIMD=1 make perf-gate-list-int-steady)"
packed_simd_summary="$(run_one "$packed_simd_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$packed_programs" OREN_BENCH_ENV_BUILD_OREN=OREN_NATIVE_RUNTIME_PROFILE=full OREN_BENCH_ENV_OREN_NATIVE=OREN_ENABLE_SIMD=1 make perf-gate-list-int-steady)"

BASELINE_SUMMARY="$baseline_summary" \
PACKED_SCALAR_SUMMARY="$packed_scalar_summary" \
PACKED_SIMD_SUMMARY="$packed_simd_summary" \
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
    ("baseline", os.environ["BASELINE_SUMMARY"]),
    ("packed_scalar", os.environ["PACKED_SCALAR_SUMMARY"]),
    ("packed_simd", os.environ["PACKED_SIMD_SUMMARY"]),
]

program_sets = {
    "baseline": ["array_sum_int", "dot_product_int"],
    "packed_scalar": ["array_sum_int_packed_bridge", "dot_product_int_packed_bridge"],
    "packed_simd": ["array_sum_int_packed_bridge", "dot_product_int_packed_bridge"],
}
print("list<int> packed-bridge steady probe summary")
print("")
for name, path in cases:
    print(f"{name}: {path}")
    data = parse_summary(path)
    for program in program_sets[name]:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C steady ratio≈{ratio:.4f}x")
    print("")
PY

echo "list<int> packed-bridge steady probe complete; summary: $summary_log"
echo "warm log: $warm_log"
echo "base log: $base_log"
echo "packed-scalar log: $packed_scalar_log"
echo "packed-simd log: $packed_simd_log"
