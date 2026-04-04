#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-bounds-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-bounds-default-${ts}.run.log"
enabled_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-bounds-enabled-${ts}.run.log"

run_test="${OREN_ARM64_FAST_DOT_CURSOR_END_BOUNDS_RUN_TEST:-0}"
enable_env="OREN_ARM64_FAST_LIST_INT_DOT_CURSOR_END_BOUNDS=1"

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

run_capture "$default_log" env \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-probe-arm64-dot-acceptance

run_capture "$enabled_log" env \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    make perf-probe-arm64-dot-acceptance

DEFAULT_WRAPPER_LOG="$default_log" \
ENABLED_WRAPPER_LOG="$enabled_log" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-dot-acceptance-[^ ]+\.summary\.log)")


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def parse_acceptance(wrapper_path):
    lines = read_lines(wrapper_path)
    summary_path = None
    for line in lines:
        m = summary_re.search(line)
        if m:
            summary_path = m.group(1)
    if summary_path is None:
        raise SystemExit(f"missing acceptance summary in {wrapper_path}")
    data = {"summary_path": summary_path}
    for line in read_lines(summary_path):
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        data[key] = value
    return data


def emit_case(label, data):
    print(f"{label}: {data['summary_path']}")
    for key in [
        "build_env",
        "exit_status",
        "failed_step",
        "steady_array_sum",
        "steady_dot_product",
        "gate_array_sum",
        "gate_dot_product",
        "disasm_array_sum_insns",
        "disasm_dot_product_insns",
        "debug_status",
        "debug_exit_code",
    ]:
        if key in data:
            print(f"  {key}: {data[key]}")
    print("")


default = parse_acceptance(os.environ["DEFAULT_WRAPPER_LOG"])
enabled = parse_acceptance(os.environ["ENABLED_WRAPPER_LOG"])

print("arm64 fast-dot cursor-end-bounds probe summary")
print("")
emit_case("default", default)
emit_case("enabled", enabled)
PY

echo "arm64 fast-dot cursor-end-bounds probe complete; summary: $summary_log"
echo "default wrapper log: $default_log"
echo "enabled wrapper log: $enabled_log"
