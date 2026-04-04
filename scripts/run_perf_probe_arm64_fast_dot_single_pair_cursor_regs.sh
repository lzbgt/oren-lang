#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-${ts}.log"
smoke_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-smoke-${ts}.log"
steady_default_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-steady-default-${ts}.run.log"
steady_disabled_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-steady-disabled-${ts}.run.log"
gate_default_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-gate-default-${ts}.run.log"
gate_disabled_log="$log_dir/perf-probe-arm64-fast-dot-single-pair-cursor-regs-gate-disabled-${ts}.run.log"

runs="${OREN_ARM64_FAST_DOT_CURSOR_REGS_RUNS:-5}"
warmups="${OREN_ARM64_FAST_DOT_CURSOR_REGS_WARMUPS:-1}"
steady_n="${OREN_ARM64_FAST_DOT_CURSOR_REGS_STEADY_N:-2000000}"
steady_reps="${OREN_ARM64_FAST_DOT_CURSOR_REGS_STEADY_REPS:-100}"
smoke="${OREN_PERF_SMOKE_NATIVE_FAST_LOOPS:-1}"
disable_env="OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0"

if [[ "$smoke" == "1" ]]; then
    make perf-smoke-native-fast-loops >"$smoke_log" 2>&1
fi

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

run_capture "$steady_default_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 \
    OREN_BENCH_PROGRAMS=dot_product \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_STEADY_N="$steady_n" \
    OREN_BENCH_NATIVE_STEADY_REPS="$steady_reps" \
    make perf-gate-native-steady

run_capture "$steady_disabled_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 \
    OREN_BENCH_PROGRAMS=dot_product \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_STEADY_N="$steady_n" \
    OREN_BENCH_NATIVE_STEADY_REPS="$steady_reps" \
    OREN_BENCH_ENV_BUILD_OREN="$disable_env" \
    make perf-gate-native-steady

run_capture "$gate_default_log" env \
    OREN_BENCH_PROGRAMS=dot_product \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-gate-native

run_capture "$gate_disabled_log" env \
    OREN_BENCH_PROGRAMS=dot_product \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_ENV_BUILD_OREN="$disable_env" \
    make perf-gate-native

STEADY_DEFAULT_LOG="$steady_default_log" \
STEADY_DISABLED_LOG="$steady_disabled_log" \
GATE_DEFAULT_LOG="$gate_default_log" \
GATE_DISABLED_LOG="$gate_disabled_log" \
python3 - <<'PY' >"$summary_log"
import os
import re

steady_log_re = re.compile(r"summary: (build/logs/perf-gate-native-steady-[^ ]+\.log)")
steady_re = re.compile(r"native/C steady ratio≈([0-9.]+)x")
md_row_re = re.compile(r"\| (c|oren_native) \| ([0-9.]+) \|")
gate_log_re = re.compile(r"log: (build/logs/perf-gate-native-[^ ]+\.log)")
gate_md_re = re.compile(r"(?:^|/)(build/benchmarks/results/dot_product_[^ ]+\.md)$")

def parse_steady(path):
    summary_path = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            m = steady_log_re.search(raw.rstrip("\n"))
            if m:
                summary_path = m.group(1)
    if summary_path is None:
        return None
    ratio = None
    with open(summary_path, "r", encoding="utf-8") as f:
        for raw in f:
            m = steady_re.search(raw.rstrip("\n"))
            if m:
                ratio = float(m.group(1))
    return ratio

def parse_gate(path):
    gate_log = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            m = gate_log_re.search(raw.rstrip("\n"))
            if m:
                gate_log = m.group(1)
    if gate_log is None:
        return None, None
    md_path = None
    with open(gate_log, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = gate_md_re.search(line)
            if m:
                md_path = m.group(1)
                break
    if md_path is None:
        return None, None
    c = None
    native = None
    with open(md_path, "r", encoding="utf-8") as f:
        for raw in f:
            m = md_row_re.match(raw.rstrip("\n"))
            if not m:
                continue
            if m.group(1) == "c":
                c = float(m.group(2))
            elif m.group(1) == "oren_native":
                native = float(m.group(2))
    if c is None or native is None:
        return md_path, None
    return md_path, native / c

cases = [
    ("steady default", os.environ["STEADY_DEFAULT_LOG"], "steady"),
    ("steady disabled", os.environ["STEADY_DISABLED_LOG"], "steady"),
    ("gate default", os.environ["GATE_DEFAULT_LOG"], "gate"),
    ("gate disabled", os.environ["GATE_DISABLED_LOG"], "gate"),
]

print("arm64 fast-dot single-pair cursor-reg probe summary")
print("")
for label, path, kind in cases:
    print(f"{label}: {path}")
    if kind == "steady":
        ratio = parse_steady(path)
        if ratio is not None:
            print(f"  dot_product: native/C steady ratio≈{ratio:.4f}x")
    else:
        md_path, ratio = parse_gate(path)
        if md_path is not None:
            print(f"  results: {md_path}")
        if ratio is not None:
            print(f"  dot_product: native/C median ratio={ratio:.4f}x")
    print("")
PY

echo "arm64 fast-dot single-pair cursor-reg probe complete; summary: $summary_log"
if [[ "$smoke" == "1" ]]; then
    echo "smoke log: $smoke_log"
fi
echo "steady default log: $steady_default_log"
echo "steady disabled log: $steady_disabled_log"
echo "gate default log: $gate_default_log"
echo "gate disabled log: $gate_disabled_log"
