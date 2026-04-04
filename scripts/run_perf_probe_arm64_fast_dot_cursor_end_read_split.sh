#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-read-split-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-read-split-default-${ts}.run.log"
enabled_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-read-split-enabled-${ts}.run.log"

programs="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_PROGRAMS:-dot_product}"
runs="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_RUNS:-5}"
warmups="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_WARMUPS:-1}"
split_n="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_N:-2000000}"
short_reps="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_ARM64_FAST_DOT_CURSOR_END_READ_SPLIT_LONG_REPS:-10}"
smoke="${OREN_PERF_SMOKE_NATIVE_FAST_LOOPS:-1}"
enable_env="OREN_ARM64_FAST_LIST_INT_DOT_CURSOR_END_BOUNDS=1"

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

run_capture "$default_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS="$smoke" \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_SPLIT_N="$split_n" \
    OREN_BENCH_NATIVE_SPLIT_SHORT_REPS="$short_reps" \
    OREN_BENCH_NATIVE_SPLIT_LONG_REPS="$long_reps" \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-gate-native-read-split

run_capture "$enabled_log" env \
    OREN_PERF_SMOKE_NATIVE_FAST_LOOPS="$smoke" \
    OREN_BENCH_PROGRAMS="$programs" \
    OREN_BENCH_RUNS="$runs" \
    OREN_BENCH_WARMUPS="$warmups" \
    OREN_BENCH_NATIVE_SPLIT_N="$split_n" \
    OREN_BENCH_NATIVE_SPLIT_SHORT_REPS="$short_reps" \
    OREN_BENCH_NATIVE_SPLIT_LONG_REPS="$long_reps" \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    make perf-gate-native-read-split

DEFAULT_WRAPPER_LOG="$default_log" \
ENABLED_WRAPPER_LOG="$enabled_log" \
python3 - <<'PY' >"$summary_log"
import os
import re
from pathlib import Path

summary_re = re.compile(r"summary: (build/logs/perf-gate-native-read-split-[^ ]+\.log)")
program_header_re = re.compile(r"^[A-Za-z0-9_]+$")
metric_re = re.compile(
    r"^(c|oren_native): short=([0-9.]+)s long=([0-9.]+)s setup≈([0-9.]+)s "
    r"delta≈([0-9.]+)s long/reps≈([0-9.]+)s cov=([0-9.]+)$"
)
ratio_re = re.compile(r"^native/C (long-per-rep|delta) ratio≈([0-9.]+)x$")


def read_lines(path):
    return Path(path).read_text(encoding="utf-8").splitlines()


def parse_summary_path(wrapper_path):
    summary_path = None
    for line in read_lines(wrapper_path):
        m = summary_re.search(line)
        if m:
            summary_path = m.group(1)
    if summary_path is None:
        raise SystemExit(f"missing read-split summary in {wrapper_path}")
    return summary_path


def parse_summary(summary_path):
    data = {"summary_path": summary_path, "programs": {}}
    current_program = None
    for raw in read_lines(summary_path):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("native read split summary: "):
            data["header"] = line
            continue
        if line.startswith("build_env: "):
            data["build_env"] = line.split(": ", 1)[1]
            continue
        if program_header_re.match(line):
            current_program = line
            data["programs"][current_program] = {}
            continue
        if current_program is None:
            continue
        m = metric_re.match(line)
        if m:
            variant = m.group(1)
            data["programs"][current_program][variant] = {
                "short_s": float(m.group(2)),
                "long_s": float(m.group(3)),
                "setup_s": float(m.group(4)),
                "delta_s": float(m.group(5)),
                "long_per_rep_s": float(m.group(6)),
                "cov": float(m.group(7)),
            }
            continue
        m = ratio_re.match(line)
        if m:
            key = "long_per_rep_ratio_x" if m.group(1) == "long-per-rep" else "delta_ratio_x"
            data["programs"][current_program][key] = float(m.group(2))
    return data


def emit_case(label, data):
    print(f"{label}: {data['summary_path']}")
    print(f"  build_env: {data.get('build_env', '<none>')}")
    if "header" in data:
        print(f"  {data['header']}")
    for program, metrics in data["programs"].items():
        print(f"  {program}:")
        for variant in ["c", "oren_native"]:
            if variant not in metrics:
                continue
            row = metrics[variant]
            print(
                f"    {variant}: short={row['short_s']:.6f}s long={row['long_s']:.6f}s "
                f"setup≈{row['setup_s']:.6f}s delta≈{row['delta_s']:.6f}s "
                f"long/reps≈{row['long_per_rep_s']:.6f}s cov={row['cov']:.4f}"
            )
        if "long_per_rep_ratio_x" in metrics:
            print(f"    native/C long-per-rep ratio≈{metrics['long_per_rep_ratio_x']:.4f}x")
        if "delta_ratio_x" in metrics:
            print(f"    native/C delta ratio≈{metrics['delta_ratio_x']:.4f}x")
    print("")


default = parse_summary(parse_summary_path(os.environ["DEFAULT_WRAPPER_LOG"]))
enabled = parse_summary(parse_summary_path(os.environ["ENABLED_WRAPPER_LOG"]))

print("arm64 fast-dot cursor-end read-split probe summary")
print("")
emit_case("default", default)
emit_case("enabled", enabled)
PY

echo "arm64 fast-dot cursor-end read-split probe complete; summary: $summary_log"
echo "default wrapper log: $default_log"
echo "enabled wrapper log: $enabled_log"
