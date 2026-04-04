#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-default-${ts}.run.log"
enabled_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-enabled-${ts}.run.log"

programs="${OREN_ARM64_FAST_DOT_MADD_EXACT_PROGRAMS:-array_sum,dot_product}"
run_test="${OREN_ARM64_FAST_DOT_MADD_EXACT_RUN_TEST:-0}"
enable_env="OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1"

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

set +e
run_capture "$default_log" env \
    OREN_ARM64_DOT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    make perf-probe-arm64-dot-acceptance
default_status=$?

run_capture "$enabled_log" env \
    OREN_ARM64_DOT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    "$enable_env" \
    make perf-probe-arm64-dot-acceptance
enabled_status=$?
set -e

DEFAULT_LOG="$default_log" \
ENABLED_LOG="$enabled_log" \
DEFAULT_STATUS="$default_status" \
ENABLED_STATUS="$enabled_status" \
PROGRAMS="$programs" \
RUN_TEST="$run_test" \
ENABLE_ENV="$enable_env" \
python3 - <<'PY' >"$summary_log"
import os
import re


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def last_capture(lines, pattern):
    rgx = re.compile(pattern)
    hit = None
    for line in lines:
        m = rgx.search(line)
        if m:
            hit = m.group(1)
    return hit


def emit_file(label, path):
    print(f"{label}: {path}")


def emit_case(label, wrapper_path, status):
    print(f"{label}:")
    emit_file("  wrapper_log", wrapper_path)
    print(f"  exit_code: {status}")
    lines = read_lines(wrapper_path)
    summary_path = last_capture(lines, r"summary: (build/logs/perf-probe-arm64-dot-acceptance-[^ ]+\.summary\.log)")
    if summary_path is None:
        print("  acceptance_summary_log: unavailable")
        if status != 0:
            print("  verdict: acceptance run exited non-zero before emitting a summary")
        print("")
        return

    emit_file("  acceptance_summary_log", summary_path)
    text = read_text(summary_path)
    keys = [
        "steady_array_sum",
        "steady_dot_product",
        "gate_array_sum",
        "gate_dot_product",
        "disasm_array_sum_insns",
        "disasm_dot_product_insns",
        "debug_status",
        "debug_exit_code",
    ]
    for key in keys:
        m = re.search(rf"^{re.escape(key)}: ([^\n]+)$", text, re.M)
        if m:
            print(f"  {key}: {m.group(1)}")
    print("")


print("arm64 fast-dot exact madd probe summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print(f"enabled_build_env: {os.environ['ENABLE_ENV']}")
print("")
emit_case("default", os.environ["DEFAULT_LOG"], int(os.environ["DEFAULT_STATUS"]))
emit_case("enabled", os.environ["ENABLED_LOG"], int(os.environ["ENABLED_STATUS"]))
PY

echo "arm64 fast-dot exact madd probe complete; summary: $summary_log"
echo "default log: $default_log"
echo "enabled log: $enabled_log"
