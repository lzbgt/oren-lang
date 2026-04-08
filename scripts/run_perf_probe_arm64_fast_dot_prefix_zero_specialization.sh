#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-${ts}.log"
default_gap_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-default-gap-${ts}.run.log"
default_split_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-default-split-${ts}.run.log"
default_trace_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-default-trace-${ts}.run.log"
enabled_gap_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-enabled-gap-${ts}.run.log"
enabled_split_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-enabled-split-${ts}.run.log"
enabled_trace_log="$log_dir/perf-probe-arm64-fast-dot-prefix-zero-specialization-enabled-trace-${ts}.run.log"

generic_programs="${OREN_ARM64_FAST_DOT_PREFIX_ZERO_SPECIALIZATION_GENERIC_PROGRAMS:-dot_product}"
specialized_programs="${OREN_ARM64_FAST_DOT_PREFIX_ZERO_SPECIALIZATION_SPECIALIZED_PROGRAMS:-dot_product_int}"
run_smoke="${OREN_ARM64_FAST_DOT_PREFIX_ZERO_SPECIALIZATION_SMOKE:-1}"
enable_env="${OREN_ARM64_FAST_DOT_PREFIX_ZERO_SPECIALIZATION_ENABLE_ENV:-OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1}"

run_capture() {
    local run_log="$1"
    shift
    local rc=0
    if "$@" >"$run_log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    printf '%s\n' "$rc"
}

run_with_cfg() {
    local run_log="$1"
    shift
    local build_env="$1"
    shift
    env \
        OREN_BENCH_ENV_BUILD_OREN="$build_env" \
        OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION="$run_smoke" \
        OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
        OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
        "$@" >"$run_log" 2>&1
}

default_gap_rc="$(run_capture "$default_gap_log" env \
    OREN_BENCH_ENV_BUILD_OREN= \
    OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION="$run_smoke" \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-gap)"

default_split_rc="$(run_capture "$default_split_log" env \
    OREN_BENCH_ENV_BUILD_OREN= \
    OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION="$run_smoke" \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-read-split)"

default_trace_rc="$(run_capture "$default_trace_log" env \
    OREN_BENCH_ENV_BUILD_OREN= \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-trace)"

enabled_gap_rc="$(run_capture "$enabled_gap_log" env \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION="$run_smoke" \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-gap)"

enabled_split_rc="$(run_capture "$enabled_split_log" env \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    OREN_PERF_SMOKE_LIST_INT_SPECIALIZATION="$run_smoke" \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-read-split)"

enabled_trace_rc="$(run_capture "$enabled_trace_log" env \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS="$generic_programs" \
    OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS="$specialized_programs" \
    make perf-probe-list-int-specialization-trace)"

DEFAULT_GAP_LOG="$default_gap_log" \
DEFAULT_GAP_RC="$default_gap_rc" \
DEFAULT_SPLIT_LOG="$default_split_log" \
DEFAULT_SPLIT_RC="$default_split_rc" \
DEFAULT_TRACE_LOG="$default_trace_log" \
DEFAULT_TRACE_RC="$default_trace_rc" \
ENABLED_GAP_LOG="$enabled_gap_log" \
ENABLED_GAP_RC="$enabled_gap_rc" \
ENABLED_SPLIT_LOG="$enabled_split_log" \
ENABLED_SPLIT_RC="$enabled_split_rc" \
ENABLED_TRACE_LOG="$enabled_trace_log" \
ENABLED_TRACE_RC="$enabled_trace_rc" \
GENERIC_PROGRAMS="$generic_programs" \
SPECIALIZED_PROGRAMS="$specialized_programs" \
RUN_SMOKE="$run_smoke" \
ENABLE_ENV="$enable_env" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/[^ ]+\.log)")


def last_summary_path(run_log):
    hit = None
    with open(run_log, "r", encoding="utf-8") as f:
        for raw in f:
            m = summary_re.search(raw.rstrip("\n"))
            if m:
                hit = m.group(1)
    return hit


def read_text(path):
    if path is None or not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def capture_metric(text, pattern):
    m = re.search(pattern, text, re.S)
    return None if m is None else m.group(1)


def emit_case(label, gap_log, gap_rc, split_log, split_rc, trace_log, trace_rc):
    gap_summary = last_summary_path(gap_log)
    split_summary = last_summary_path(split_log)
    trace_summary = last_summary_path(trace_log)
    gap_text = read_text(gap_summary)
    split_text = read_text(split_summary)
    trace_text = read_text(trace_summary)

    print(f"{label}:")
    print(f"  gap_wrapper_log: {gap_log}")
    print(f"  gap_wrapper_exit_code: {gap_rc}")
    if gap_summary is not None:
        print(f"  gap_summary: {gap_summary}")
    print(f"  split_wrapper_log: {split_log}")
    print(f"  split_wrapper_exit_code: {split_rc}")
    if split_summary is not None:
        print(f"  split_summary: {split_summary}")
    print(f"  trace_wrapper_log: {trace_log}")
    print(f"  trace_wrapper_exit_code: {trace_rc}")
    if trace_summary is not None:
        print(f"  trace_summary: {trace_summary}")

    for key, pattern in [
        ("steady_generic_native/C", r"generic_native/C: ([0-9.]+x)"),
        ("steady_specialized_native/C", r"specialized_native/C: ([0-9.]+x)"),
        ("steady_generic_vs_specialized", r"generic_vs_specialized: ([0-9.]+x)"),
    ]:
        value = capture_metric(gap_text, pattern)
        if value is not None:
            print(f"  {key}: {value}")

    for key, pattern in [
        ("split_generic_native/C_long_per_rep", r"generic_native/C_long_per_rep: ([0-9.]+x)"),
        ("split_specialized_native/C_long_per_rep", r"specialized_native/C_long_per_rep: ([0-9.]+x)"),
        ("split_generic_vs_specialized_long_per_rep", r"generic_vs_specialized_long_per_rep: ([0-9.]+x)"),
        ("split_generic_native/C_delta", r"generic_native/C_delta: ([0-9.]+x)"),
        ("split_specialized_native/C_delta", r"specialized_native/C_delta: ([0-9.]+x)"),
        ("split_generic_vs_specialized_delta", r"generic_vs_specialized_delta: ([0-9.]+x)"),
    ]:
        value = capture_metric(split_text, pattern)
        if value is not None:
            print(f"  {key}: {value}")

    for key, pattern in [
        ("trace_generic_rewrite_init", r"generic\s+.*?rewrite_init: (\d+)"),
        ("trace_generic_list_push_unchecked", r"generic\s+.*?list_push_unchecked: (\d+)"),
        ("trace_specialized_rewrite_init", r"specialized\s+.*?rewrite_init: (\d+)"),
        ("trace_specialized_list_push_unchecked", r"specialized\s+.*?list_push_unchecked: (\d+)"),
    ]:
        value = capture_metric(trace_text, pattern)
        if value is not None:
            print(f"  {key}: {value}")
    print("")


print("arm64 fast dot prefix-zero specialization probe summary")
print("")
print(f"generic_programs: {os.environ['GENERIC_PROGRAMS']}")
print(f"specialized_programs: {os.environ['SPECIALIZED_PROGRAMS']}")
print(f"run_smoke: {os.environ['RUN_SMOKE']}")
print(f"enabled_build_env: {os.environ['ENABLE_ENV']}")
print("")

emit_case(
    "default",
    os.environ["DEFAULT_GAP_LOG"],
    os.environ["DEFAULT_GAP_RC"],
    os.environ["DEFAULT_SPLIT_LOG"],
    os.environ["DEFAULT_SPLIT_RC"],
    os.environ["DEFAULT_TRACE_LOG"],
    os.environ["DEFAULT_TRACE_RC"],
)

emit_case(
    "enabled",
    os.environ["ENABLED_GAP_LOG"],
    os.environ["ENABLED_GAP_RC"],
    os.environ["ENABLED_SPLIT_LOG"],
    os.environ["ENABLED_SPLIT_RC"],
    os.environ["ENABLED_TRACE_LOG"],
    os.environ["ENABLED_TRACE_RC"],
)
PY

echo "arm64 fast dot prefix-zero specialization probe complete; summary: $summary_log"
echo "default gap log: $default_gap_log"
echo "default split log: $default_split_log"
echo "default trace log: $default_trace_log"
echo "enabled gap log: $enabled_gap_log"
echo "enabled split log: $enabled_split_log"
echo "enabled trace log: $enabled_trace_log"

if [[ "$default_gap_rc" != "0" || "$default_split_rc" != "0" || "$default_trace_rc" != "0" ]]; then
    echo "default specialization probe failed; keeping target red"
    exit 1
fi
