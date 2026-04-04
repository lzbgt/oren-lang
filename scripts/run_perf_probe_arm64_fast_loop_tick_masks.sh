#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-${ts}.log"
smoke_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-smoke-${ts}.log"
base_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-base-${ts}.run.log"
mask16383_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-dot-16383-${ts}.run.log"
mask65535_log="$log_dir/perf-probe-arm64-fast-loop-tick-masks-dot-65535-${ts}.run.log"

programs="${OREN_ARM64_FAST_LOOP_TICK_PROGRAMS:-array_sum,dot_product}"
runs="${OREN_ARM64_FAST_LOOP_TICK_RUNS:-5}"
warmups="${OREN_ARM64_FAST_LOOP_TICK_WARMUPS:-1}"

if [[ "${OREN_PERF_SMOKE_LIST_INT:-1}" == "1" ]]; then
    make verify-native-list-int-fast-lowering >"$smoke_log" 2>&1
fi

run_one() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
    printf '%s\n' "$run_log"
}

baseline_summary="$(run_one "$base_log" env \
    OREN_PERF_SMOKE_LIST_INT=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    make perf-gate-native)"

mask16383_summary="$(run_one "$mask16383_log" env \
    OREN_PERF_SMOKE_LIST_INT=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_ENV_BUILD_OREN=OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383 \
    make perf-gate-native)"

mask65535_summary="$(run_one "$mask65535_log" env \
    OREN_PERF_SMOKE_LIST_INT=0 \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_ENV_BUILD_OREN=OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=65535 \
    make perf-gate-native)"

BASELINE_RUN_LOG="$baseline_summary" \
MASK16383_RUN_LOG="$mask16383_summary" \
MASK65535_RUN_LOG="$mask65535_summary" \
python3 - <<'PY' >"$summary_log"
import os
import re

def parse_benchmark_md(path):
    program = None
    c_median = None
    native_median = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if program is None:
                m_prog = re.match(r"# (.+) benchmark \(", line)
                if m_prog:
                    program = m_prog.group(1)
                    continue
            m_row = re.match(r"\| (c|oren_native) \| ([0-9.]+) \|", line)
            if not m_row:
                continue
            if m_row.group(1) == "c":
                c_median = float(m_row.group(2))
            elif m_row.group(1) == "oren_native":
                native_median = float(m_row.group(2))
    if program is None or c_median is None or native_median is None:
        return None
    return program, native_median / c_median

def parse_run_log(path):
    out = {}
    gate_log = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m_gate = re.search(r"(build/logs/perf-gate-native-[^ ]+\.log)", line)
            if m_gate:
                gate_log = m_gate.group(1)
    if gate_log is None:
        return out
    with open(gate_log, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.endswith(".md"):
                continue
            parsed = parse_benchmark_md(line)
            if parsed is None:
                continue
            program, ratio = parsed
            out[program] = ratio
    return out

cases = [
    ("baseline", os.environ["BASELINE_RUN_LOG"]),
    ("dot_mask_16383", os.environ["MASK16383_RUN_LOG"]),
    ("dot_mask_65535", os.environ["MASK65535_RUN_LOG"]),
]
programs = ["array_sum", "dot_product"]

print("arm64 fast-loop tick-mask probe summary")
print("")
for name, path in cases:
    print(f"{name}: {path}")
    data = parse_run_log(path)
    for program in programs:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C median ratio={ratio:.4f}x")
    print("")
PY

echo "arm64 fast-loop tick-mask probe complete; summary: $summary_log"
if [[ "${OREN_PERF_SMOKE_LIST_INT:-1}" == "1" ]]; then
    echo "smoke log: $smoke_log"
fi
echo "base log: $base_log"
echo "dot-16383 log: $mask16383_log"
echo "dot-65535 log: $mask65535_log"
