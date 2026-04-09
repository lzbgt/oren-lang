#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-push-single-list-cursor-list-int-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-push-single-list-cursor-list-int-default-${ts}.run.log"
disabled_log="$log_dir/perf-probe-arm64-fast-push-single-list-cursor-list-int-disabled-${ts}.run.log"

programs="${OREN_ARM64_FAST_PUSH_CURSOR_LIST_INT_PROGRAMS:-array_sum_int}"
run_test="${OREN_ARM64_FAST_PUSH_CURSOR_LIST_INT_RUN_TEST:-0}"
disable_env="${OREN_ARM64_FAST_PUSH_CURSOR_LIST_INT_DISABLE_ENV:-OREN_ARM64_FAST_LIST_INT_PUSH_SINGLE_LIST_CURSOR=0}"

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

disabled_rc="$(run_capture "$disabled_log" env \
    OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS="$programs" \
    OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST="$run_test" \
    OREN_BENCH_ENV_BUILD_OREN="$disable_env" \
    make perf-probe-arm64-list-int-acceptance)"

DEFAULT_LOG="$default_log" \
DEFAULT_RC="$default_rc" \
DISABLED_LOG="$disabled_log" \
DISABLED_RC="$disabled_rc" \
RUN_TEST="$run_test" \
PROGRAMS="$programs" \
DISABLE_ENV="$disable_env" \
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
    ("default", os.environ["DEFAULT_LOG"], os.environ["DEFAULT_RC"]),
    ("disabled", os.environ["DISABLED_LOG"], os.environ["DISABLED_RC"]),
]

print("arm64 fast push single-list cursor list<int> probe summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print(f"disabled_build_env: {os.environ['DISABLE_ENV']}")
print("")
case_metrics = {}
for label, run_log, wrapper_rc in cases:
    summary_path, metrics = parse_acceptance(run_log)
    case_metrics[label] = metrics
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

default_metrics = case_metrics.get("default", {})
disabled_metrics = case_metrics.get("disabled", {})
for label, key in [
    ("disabled_steady_array_sum_int_native_median_delta_pct", "steady_array_sum_int_native_median_s"),
    ("disabled_gate_array_sum_int_native_median_delta_pct", "gate_array_sum_int_native_median_s"),
]:
    base = parse_float_metric(default_metrics, key)
    disabled = parse_float_metric(disabled_metrics, key)
    if base is not None and disabled is not None and base > 0.0:
        print(f"{label}: {((disabled / base) - 1.0) * 100.0:+.2f}%")
PY

echo "arm64 fast push single-list cursor list<int> probe complete; summary: $summary_log"
echo "default acceptance log: $default_log"
echo "disabled acceptance log: $disabled_log"
if [[ "$default_rc" != "0" ]]; then
    echo "default acceptance failed (exit=$default_rc); keeping probe target red"
    exit "$default_rc"
fi
if [[ "$disabled_rc" != "0" ]]; then
    echo "disabled cursor list<int> experiment failed (exit=$disabled_rc); see summary for details"
fi
