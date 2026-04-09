#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-get-sum-tick-mask-list-int-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-get-sum-tick-mask-list-int-default-${ts}.run.log"
mask16383_log="$log_dir/perf-probe-arm64-fast-get-sum-tick-mask-list-int-16383-${ts}.run.log"
mask65535_log="$log_dir/perf-probe-arm64-fast-get-sum-tick-mask-list-int-65535-${ts}.run.log"

programs="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_PROGRAMS:-array_sum_int}"
run_test="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_RUN_TEST:-0}"
default_label="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_DEFAULT_LABEL:-default}"
mask16383_label="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_16383_LABEL:-mask_16383}"
mask65535_label="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_65535_LABEL:-mask_65535}"
mask16383_env="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_16383_ENV:-OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK=16383}"
mask65535_env="${OREN_ARM64_FAST_GET_SUM_TICK_MASK_LIST_INT_65535_ENV:-OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK=65535}"

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
    OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-probe-arm64-list-int-acceptance)"

mask16383_rc="$(run_capture "$mask16383_log" env \
    OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN="$mask16383_env" \
    make perf-probe-arm64-list-int-acceptance)"

mask65535_rc="$(run_capture "$mask65535_log" env \
    OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN="$mask65535_env" \
    make perf-probe-arm64-list-int-acceptance)"

DEFAULT_LOG="$default_log" \
DEFAULT_RC="$default_rc" \
MASK16383_LOG="$mask16383_log" \
MASK16383_RC="$mask16383_rc" \
MASK65535_LOG="$mask65535_log" \
MASK65535_RC="$mask65535_rc" \
RUN_TEST="$run_test" \
PROGRAMS="$programs" \
DEFAULT_LABEL="$default_label" \
MASK16383_LABEL="$mask16383_label" \
MASK65535_LABEL="$mask65535_label" \
MASK16383_ENV="$mask16383_env" \
MASK65535_ENV="$mask65535_env" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-list-int-acceptance-[^ ]+\.summary\.log)")
metric_re = re.compile(r"^([a-z0-9_]+): (.+)$")


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
                    key = m.group(1)
                    if key in {
                        "exit_status",
                        "failed_step",
                        "steady_array_sum_int",
                        "steady_array_sum_int_c_median_s",
                        "steady_array_sum_int_c_cov",
                        "steady_array_sum_int_native_median_s",
                        "steady_array_sum_int_native_cov",
                        "gate_array_sum_int",
                        "gate_array_sum_int_c_median_s",
                        "gate_array_sum_int_c_cov",
                        "gate_array_sum_int_native_median_s",
                        "gate_array_sum_int_native_cov",
                        "warning_gate_array_sum_int_high_variance",
                        "disasm_array_sum_int_insns",
                        "debug_status",
                        "debug_exit_code",
                    }:
                        metrics[key] = m.group(2)
    return summary_path, metrics


def parse_float_metric(metrics, key):
    value = metrics.get(key)
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


cases = [
    (os.environ["DEFAULT_LABEL"], os.environ["DEFAULT_LOG"], os.environ["DEFAULT_RC"], ""),
    (os.environ["MASK16383_LABEL"], os.environ["MASK16383_LOG"], os.environ["MASK16383_RC"], os.environ["MASK16383_ENV"]),
    (os.environ["MASK65535_LABEL"], os.environ["MASK65535_LOG"], os.environ["MASK65535_RC"], os.environ["MASK65535_ENV"]),
]

print("arm64 fast get-sum tick-mask list<int> probe summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print("")
case_metrics = {}
for label, run_log, wrapper_rc, build_env in cases:
    summary_path, metrics = parse_acceptance(run_log)
    case_metrics[label] = metrics
    print(f"{label}: {run_log}")
    print(f"  wrapper_exit_code: {wrapper_rc}")
    if build_env:
        print(f"  build_env: {build_env}")
    if summary_path is None:
        print("  acceptance_summary: missing")
        print("")
        continue
    print(f"  acceptance_summary: {summary_path}")
    for key in [
        "exit_status",
        "failed_step",
        "steady_array_sum_int",
        "steady_array_sum_int_c_median_s",
        "steady_array_sum_int_c_cov",
        "steady_array_sum_int_native_median_s",
        "steady_array_sum_int_native_cov",
        "gate_array_sum_int",
        "gate_array_sum_int_c_median_s",
        "gate_array_sum_int_c_cov",
        "gate_array_sum_int_native_median_s",
        "gate_array_sum_int_native_cov",
        "warning_gate_array_sum_int_high_variance",
        "disasm_array_sum_int_insns",
        "debug_status",
        "debug_exit_code",
    ]:
        value = metrics.get(key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")

default_metrics = case_metrics.get(os.environ["DEFAULT_LABEL"], {})
for variant in [os.environ["MASK16383_LABEL"], os.environ["MASK65535_LABEL"]]:
    metrics = case_metrics.get(variant, {})
    for label, key in [
        (f"{variant}_steady_array_sum_int_native_median_delta_pct", "steady_array_sum_int_native_median_s"),
        (f"{variant}_gate_array_sum_int_native_median_delta_pct", "gate_array_sum_int_native_median_s"),
    ]:
        base = parse_float_metric(default_metrics, key)
        value = parse_float_metric(metrics, key)
        if base is not None and value is not None and base > 0.0:
            print(f"{label}: {((value / base) - 1.0) * 100.0:+.2f}%")
PY

echo "arm64 fast get-sum tick-mask list<int> probe complete; summary: $summary_log"
echo "default acceptance log: $default_log"
echo "mask-16383 acceptance log: $mask16383_log"
echo "mask-65535 acceptance log: $mask65535_log"
if [[ "$default_rc" != "0" ]]; then
    echo "default acceptance failed (exit=$default_rc); keeping probe target red"
    exit "$default_rc"
fi
if [[ "$mask16383_rc" != "0" ]]; then
    echo "mask-16383 experiment failed (exit=$mask16383_rc); see summary for details"
fi
if [[ "$mask65535_rc" != "0" ]]; then
    echo "mask-65535 experiment failed (exit=$mask65535_rc); see summary for details"
fi
