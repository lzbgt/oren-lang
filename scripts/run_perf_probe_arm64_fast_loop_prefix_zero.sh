#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-loop-prefix-zero-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-loop-prefix-zero-default-${ts}.run.log"
enabled_log="$log_dir/perf-probe-arm64-fast-loop-prefix-zero-enabled-${ts}.run.log"

run_test="${OREN_ARM64_FAST_LOOP_PREFIX_ZERO_RUN_TEST:-0}"
enable_env="OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1,OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1"

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

default_rc="$(run_capture "$default_log" env \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-probe-arm64-dot-acceptance)"

enabled_rc="$(run_capture "$enabled_log" env \
    OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    make perf-probe-arm64-dot-acceptance)"

DEFAULT_LOG="$default_log" \
DEFAULT_RC="$default_rc" \
ENABLED_LOG="$enabled_log" \
ENABLED_RC="$enabled_rc" \
RUN_TEST="$run_test" \
ENABLE_ENV="$enable_env" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-dot-acceptance-[^ ]+\.summary\.log)")
metric_re = re.compile(r"^(exit_status|failed_step|steady_array_sum|steady_dot_product|gate_array_sum|gate_dot_product|disasm_array_sum_insns|disasm_dot_product_insns|debug_status|debug_exit_code): (.+)$")


def parse_acceptance(run_log):
    summary_path = None
    with open(run_log, "r", encoding="utf-8") as f:
        for raw in f:
            m = summary_re.search(raw.rstrip("\n"))
            if m:
                summary_path = m.group(1)
    metrics = {}
    if summary_path is not None and os.path.exists(summary_path):
        with open(summary_path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.rstrip("\n")
                m = metric_re.match(line)
                if m:
                    metrics[m.group(1)] = m.group(2)
    return summary_path, metrics


cases = [
    ("default", os.environ["DEFAULT_LOG"], os.environ["DEFAULT_RC"]),
    ("enabled", os.environ["ENABLED_LOG"], os.environ["ENABLED_RC"]),
]

print("arm64 fast-loop prefix-zero probe summary")
print("")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print(f"enabled_build_env: {os.environ['ENABLE_ENV']}")
print("")
for label, run_log, wrapper_rc in cases:
    summary_path, metrics = parse_acceptance(run_log)
    print(f"{label}: {run_log}")
    print(f"  wrapper_exit_code: {wrapper_rc}")
    if summary_path is None:
        print("  acceptance_summary: missing")
        print("")
        continue
    print(f"  acceptance_summary: {summary_path}")
    for key in [
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
        value = metrics.get(key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")
PY

echo "arm64 fast-loop prefix-zero probe complete; summary: $summary_log"
echo "default acceptance log: $default_log"
echo "enabled acceptance log: $enabled_log"
if [[ "$default_rc" != "0" ]]; then
    echo "default acceptance failed (exit=$default_rc); keeping probe target red"
    exit "$default_rc"
fi
if [[ "$enabled_rc" != "0" ]]; then
    echo "enabled prefix-zero experiment failed (exit=$enabled_rc); see summary for details"
fi
