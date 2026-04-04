#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-specialization-gap-${ts}.log"
native_smoke_log="$log_dir/perf-probe-list-int-specialization-gap-native-smoke-${ts}.log"
list_int_smoke_log="$log_dir/perf-probe-list-int-specialization-gap-list-int-smoke-${ts}.log"
generic_log="$log_dir/perf-probe-list-int-specialization-gap-generic-${ts}.run.log"
specialized_log="$log_dir/perf-probe-list-int-specialization-gap-specialized-${ts}.run.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
generic_programs="${OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS:-array_sum,dot_product}"
specialized_programs="${OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS:-array_sum_int,dot_product_int}"
smoke="${OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION:-1}"
runs="${OREN_LIST_INT_SPECIALIZATION_RUNS:-3}"
warmups="${OREN_LIST_INT_SPECIALIZATION_WARMUPS:-1}"
n="${OREN_LIST_INT_SPECIALIZATION_N:-200000}"
reps="${OREN_LIST_INT_SPECIALIZATION_REPS:-10}"

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
    ./scripts/run_perf_smoke_native_fast_loops.sh >"$native_smoke_log" 2>&1
    ./scripts/run_perf_smoke_list_int.sh >"$list_int_smoke_log" 2>&1
fi

generic_summary="$(run_one "$generic_log" env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 OREN_BENCH_PROGRAMS="$generic_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_NATIVE_STEADY_N="$n" OREN_BENCH_NATIVE_STEADY_REPS="$reps" make perf-gate-native-steady)"
specialized_summary="$(run_one "$specialized_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_PROGRAMS="$specialized_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_STEADY_N="$n" OREN_BENCH_LIST_INT_STEADY_REPS="$reps" make perf-gate-list-int-steady)"

GENERIC_SUMMARY="$generic_summary" \
SPECIALIZED_SUMMARY="$specialized_summary" \
BUILD_ENV="$build_env_raw" \
SMOKE="$smoke" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
NATIVE_SMOKE_LOG="$native_smoke_log" \
LIST_INT_SMOKE_LOG="$list_int_smoke_log" \
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
                if line.startswith("native steady summary:") or line.startswith("list<int> steady summary:"):
                    continue
                current = line.strip()
                continue
            if current is None:
                continue
            m = re.match(r"\s+native/C steady ratio≈([0-9.]+)x", line)
            if m:
                out[current] = float(m.group(1))
    return out


generic = parse_summary(os.environ["GENERIC_SUMMARY"])
specialized = parse_summary(os.environ["SPECIALIZED_SUMMARY"])

pairs = [
    ("array_sum", "array_sum_int"),
    ("dot_product", "dot_product_int"),
]

print("list<int> specialization-gap probe summary")
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
    print(f"native_smoke_log: {os.environ['NATIVE_SMOKE_LOG']}")
    print(f"list_int_smoke_log: {os.environ['LIST_INT_SMOKE_LOG']}")
    print("")
print(f"generic_summary: {os.environ['GENERIC_SUMMARY']}")
print(f"specialized_summary: {os.environ['SPECIALIZED_SUMMARY']}")
print("")

for generic_name, specialized_name in pairs:
    g = generic.get(generic_name)
    s = specialized.get(specialized_name)
    print(f"{generic_name}:")
    if g is not None:
        print(f"  generic_native/C: {g:.4f}x")
    if s is not None:
        print(f"  specialized_native/C: {s:.4f}x")
    if g is not None and s is not None:
        print(f"  generic_vs_specialized: {(g / s):.4f}x")
    print("")
PY

echo "list<int> specialization-gap probe complete; summary: $summary_log"
echo "generic log: $generic_log"
echo "specialized log: $specialized_log"
