#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-steady-${ts}.log"
smoke_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-steady-smoke-${ts}.log"
base_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-steady-base-${ts}.run.log"
mask16383_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-steady-dot-16383-${ts}.run.log"
mask65535_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-steady-dot-65535-${ts}.run.log"

programs="${OREN_ARM64_FAST_LOOP_TICK_STEADY_PROGRAMS:-dot_product}"
runs="${OREN_ARM64_FAST_LOOP_TICK_STEADY_RUNS:-5}"
warmups="${OREN_ARM64_FAST_LOOP_TICK_STEADY_WARMUPS:-1}"
n="${OREN_ARM64_FAST_LOOP_TICK_STEADY_N:-2000000}"
reps="${OREN_ARM64_FAST_LOOP_TICK_STEADY_REPS:-100}"
smoke="${OREN_PERF_SMOKE_NATIVE_FAST_LOOPS:-1}"

if [[ "$smoke" == "1" ]]; then
    make perf-smoke-native-fast-loops >"$smoke_log" 2>&1
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

baseline_summary="$(run_one "$base_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_STEADY_N="$n" \
    OREN_BENCH_NATIVE_STEADY_REPS="$reps" \
    make perf-gate-native-steady)"

mask16383_summary="$(run_one "$mask16383_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_STEADY_N="$n" \
    OREN_BENCH_NATIVE_STEADY_REPS="$reps" \
    OREN_BENCH_ENV_BUILD_OREN=OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383 \
    make perf-gate-native-steady)"

mask65535_summary="$(run_one "$mask65535_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_STEADY_N="$n" \
    OREN_BENCH_NATIVE_STEADY_REPS="$reps" \
    OREN_BENCH_ENV_BUILD_OREN=OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=65535 \
    make perf-gate-native-steady)"

BASELINE_SUMMARY="$baseline_summary" \
MASK16383_SUMMARY="$mask16383_summary" \
MASK65535_SUMMARY="$mask65535_summary" \
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
                if line.startswith("native steady summary:"):
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
    ("dot_mask_16383", os.environ["MASK16383_SUMMARY"]),
    ("dot_mask_65535", os.environ["MASK65535_SUMMARY"]),
]
programs = [p for p in os.environ.get("OREN_ARM64_FAST_LOOP_TICK_STEADY_PROGRAMS", "dot_product").replace(",", " ").split() if p]

print("arm64 fast-loop steady tick-mask probe summary")
print("")
for name, path in cases:
    print(f"{name}: {path}")
    data = parse_summary(path)
    for program in programs:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C steady ratio≈{ratio:.4f}x")
    print("")
PY

echo "arm64 fast-loop steady tick-mask probe complete; summary: $summary_log"
if [[ "$smoke" == "1" ]]; then
    echo "smoke log: $smoke_log"
fi
echo "base log: $base_log"
echo "dot-16383 log: $mask16383_log"
echo "dot-65535 log: $mask65535_log"
