#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${ts}.log"
manifest_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${ts}.cases.tsv"

programs="${OREN_ARM64_FAST_DOT_MADD_EXACT_SUBPATH_PROGRAMS:-dot_product}"
run_test="${OREN_ARM64_FAST_DOT_MADD_EXACT_SUBPATH_RUN_TEST:-0}"

run_case() {
    local label="$1"
    local env_desc="$2"
    local run_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${label}-${ts}.run.log"
    local status=0
    local build_env=""
    shift 2
    if (($# > 0)); then
        build_env="$*"
        build_env="${build_env// /,}"
    fi
    set +e
    env \
        OREN_ARM64_DOT_ACCEPT_PROGRAMS="$programs" \
        OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
        OREN_BENCH_ENV_BUILD_OREN="$build_env" \
        make perf-probe-arm64-dot-acceptance >"$run_log" 2>&1
    status=$?
    set -e
    printf '%s\t%s\t%s\t%s\n' "$label" "$run_log" "$status" "$env_desc" >>"$manifest_log"
}

: >"$manifest_log"
run_case baseline "default shipped baseline"
run_case scalar_disabled \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0
run_case quad \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1
run_case double \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1

MANIFEST_LOG="$manifest_log" \
PROGRAMS="$programs" \
RUN_TEST="$run_test" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-dot-acceptance-[^ ]+\.summary\.log)")
metric_re = re.compile(r"^([a-z0-9_]+): (.+)$")


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


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
                        "steady_array_sum",
                        "steady_dot_product",
                        "steady_array_sum_c_median_s",
                        "steady_array_sum_c_cov",
                        "steady_array_sum_native_median_s",
                        "steady_array_sum_native_cov",
                        "steady_dot_product_c_median_s",
                        "steady_dot_product_c_cov",
                        "steady_dot_product_native_median_s",
                        "steady_dot_product_native_cov",
                        "gate_array_sum",
                        "gate_dot_product",
                        "gate_array_sum_c_median_s",
                        "gate_array_sum_c_cov",
                        "gate_array_sum_native_median_s",
                        "gate_array_sum_native_cov",
                        "gate_dot_product_c_median_s",
                        "gate_dot_product_c_cov",
                        "gate_dot_product_native_median_s",
                        "gate_dot_product_native_cov",
                        "warning_gate_dot_product_high_variance",
                        "disasm_array_sum_insns",
                        "disasm_dot_product_insns",
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


print("arm64 fast-dot exact madd subpath probe summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print("")

rows = []
with open(os.environ["MANIFEST_LOG"], "r", encoding="utf-8") as f:
    for line in f:
        if line.strip():
            rows.append(line.rstrip("\n").split("\t", 3))

case_metrics = {}
for label, run_log, status, env_desc in rows:
    summary_path, metrics = parse_acceptance(run_log)
    case_metrics[label] = metrics
    print(f"{label}:")
    print(f"  enabled_build_env: {env_desc}")
    print(f"  wrapper_log: {run_log}")
    print(f"  wrapper_exit_code: {status}")
    if summary_path is None:
        print("  acceptance_summary: missing")
        print("")
        continue
    print(f"  acceptance_summary: {summary_path}")
    for key in [
        "exit_status",
        "failed_step",
        "steady_dot_product",
        "steady_dot_product_c_median_s",
        "steady_dot_product_c_cov",
        "steady_dot_product_native_median_s",
        "steady_dot_product_native_cov",
        "gate_dot_product",
        "gate_dot_product_c_median_s",
        "gate_dot_product_c_cov",
        "gate_dot_product_native_median_s",
        "gate_dot_product_native_cov",
        "warning_gate_dot_product_high_variance",
        "disasm_dot_product_insns",
        "debug_status",
        "debug_exit_code",
    ]:
        value = metrics.get(key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")

baseline = case_metrics.get("baseline", {})
for label, metrics in case_metrics.items():
    if label == "baseline":
        continue
    for metric_key, out_key in [
        ("steady_dot_product_native_median_s", f"{label}_steady_dot_product_native_median_delta_pct"),
        ("gate_dot_product_native_median_s", f"{label}_gate_dot_product_native_median_delta_pct"),
    ]:
        base = parse_float_metric(baseline, metric_key)
        candidate = parse_float_metric(metrics, metric_key)
        if base is not None and candidate is not None and base > 0.0:
            print(f"{out_key}: {((candidate / base) - 1.0) * 100.0:+.2f}%")
PY

echo "arm64 fast-dot exact madd subpath probe complete; summary: $summary_log"
echo "case manifest: $manifest_log"
