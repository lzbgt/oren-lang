#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-${ts}.log"
manifest_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-${ts}.cases.tsv"

programs="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_PROGRAMS:-dot_product_int}"
runs="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_RUNS:-5}"
warmups="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_WARMUPS:-1}"
n="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_N:-2000000}"
short_reps="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_SHORT_REPS:-1}"
long_reps="${OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_LONG_REPS:-10}"

run_case() {
    local label="$1"
    local env_desc="$2"
    local run_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-${label}-${ts}.run.log"
    local status=0
    local build_env=""
    shift 2
    if (($# > 0)); then
        build_env="$*"
        build_env="${build_env// /,}"
    fi
    set +e
    env \
        OREN_PERF_SMOKE_LIST_INT=0 \
        OREN_BENCH_SKIP_OREN_C=1 \
        OREN_BENCH_PROGRAMS="$programs" \
        OREN_BENCH_RUNS="$runs" \
        OREN_BENCH_WARMUPS="$warmups" \
        OREN_BENCH_LIST_INT_SPLIT_N="$n" \
        OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" \
        OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" \
        OREN_BENCH_ENV_BUILD_OREN="$build_env" \
        make perf-gate-list-int-read-split >"$run_log" 2>&1
    status=$?
    set -e
    printf '%s\t%s\t%s\t%s\n' "$label" "$run_log" "$status" "$env_desc" >>"$manifest_log"
}

: >"$manifest_log"
run_case baseline "default shipped baseline"
run_case cursor_disabled \
    "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0" \
    OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0
run_case scalar_enabled \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1
run_case cursor_scalar_enabled \
    "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1

MANIFEST_LOG="$manifest_log" \
PROGRAMS="$programs" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
python3 - <<'PY' >"$summary_log"
import os
import re

summary_re = re.compile(r"summary: (build/logs/perf-gate-list-int-read-split-[^ ]+\.log)")


def parse_summary(run_log):
    summary_path = None
    with open(run_log, "r", encoding="utf-8") as f:
        for raw in f:
            m = summary_re.search(raw.rstrip("\n"))
            if m:
                summary_path = m.group(1)
    metrics = {}
    if summary_path is None or not os.path.exists(summary_path):
        return summary_path, metrics
    text = open(summary_path, "r", encoding="utf-8").read()
    patterns = {
        "dot_product_int_c_short_s": r"dot_product_int\s+  c: short=([0-9.]+)s",
        "dot_product_int_c_long_s": r"dot_product_int\s+  c: short=[0-9.]+s long=([0-9.]+)s",
        "dot_product_int_c_setup_s": r"dot_product_int\s+  c: .*?setup≈([0-9.\-]+)s",
        "dot_product_int_c_delta_s": r"dot_product_int\s+  c: .*?delta≈([0-9.\-]+)s",
        "dot_product_int_c_long_per_rep_s": r"dot_product_int\s+  c: .*?long/reps≈([0-9.]+)s",
        "dot_product_int_c_cov": r"dot_product_int\s+  c: .*?cov=([0-9.]+)",
        "dot_product_int_native_short_s": r"dot_product_int\s+.*?oren_native: short=([0-9.]+)s",
        "dot_product_int_native_long_s": r"dot_product_int\s+.*?oren_native: short=[0-9.]+s long=([0-9.]+)s",
        "dot_product_int_native_setup_s": r"dot_product_int\s+.*?oren_native: .*?setup≈([0-9.\-]+)s",
        "dot_product_int_native_delta_s": r"dot_product_int\s+.*?oren_native: .*?delta≈([0-9.\-]+)s",
        "dot_product_int_native_long_per_rep_s": r"dot_product_int\s+.*?oren_native: .*?long/reps≈([0-9.]+)s",
        "dot_product_int_native_cov": r"dot_product_int\s+.*?oren_native: .*?cov=([0-9.]+)",
        "dot_product_int_native_over_c_long_per_rep": r"dot_product_int\s+.*?native/C long-per-rep ratio≈([0-9.]+x)",
        "dot_product_int_native_over_c_delta": r"dot_product_int\s+.*?native/C delta ratio≈([0-9.]+x)",
        "warning_delta_vs_long_drift": r"dot_product_int\s+.*?(warning: delta-vs-long steady estimate drift=[0-9.]+%; prefer long-per-rep for tracker updates)",
    }
    for key, pattern in patterns.items():
        m = re.search(pattern, text, re.S)
        if m:
            metrics[key] = m.group(1)
    return summary_path, metrics


def parse_float_metric(metrics, key):
    value = metrics.get(key)
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


print("arm64 fast dot scalar-core read-split list<int> summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"n: {os.environ['N']}")
print(f"short_reps: {os.environ['SHORT_REPS']}")
print(f"long_reps: {os.environ['LONG_REPS']}")
print("")

rows = []
with open(os.environ["MANIFEST_LOG"], "r", encoding="utf-8") as f:
    for line in f:
        if line.strip():
            rows.append(line.rstrip("\n").split("\t", 3))

case_metrics = {}
ordered_keys = [
    "dot_product_int_c_short_s",
    "dot_product_int_c_long_s",
    "dot_product_int_c_setup_s",
    "dot_product_int_c_delta_s",
    "dot_product_int_c_long_per_rep_s",
    "dot_product_int_c_cov",
    "dot_product_int_native_short_s",
    "dot_product_int_native_long_s",
    "dot_product_int_native_setup_s",
    "dot_product_int_native_delta_s",
    "dot_product_int_native_long_per_rep_s",
    "dot_product_int_native_cov",
    "dot_product_int_native_over_c_long_per_rep",
    "dot_product_int_native_over_c_delta",
    "warning_delta_vs_long_drift",
]
for label, run_log, status, env_desc in rows:
    summary_path, metrics = parse_summary(run_log)
    case_metrics[label] = metrics
    print(f"{label}:")
    print(f"  enabled_build_env: {env_desc}")
    print(f"  wrapper_log: {run_log}")
    print(f"  wrapper_exit_code: {status}")
    if summary_path is None:
        print("  read_split_summary: missing")
        print("")
        continue
    print(f"  read_split_summary: {summary_path}")
    for key in ordered_keys:
        value = metrics.get(key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")

baseline = case_metrics.get("baseline", {})
for label, metrics in case_metrics.items():
    if label == "baseline":
        continue
    for metric_key, out_key in [
        ("dot_product_int_native_short_s", f"{label}_dot_product_int_native_short_delta_pct"),
        ("dot_product_int_native_setup_s", f"{label}_dot_product_int_native_setup_delta_pct"),
        ("dot_product_int_native_delta_s", f"{label}_dot_product_int_native_delta_delta_pct"),
        ("dot_product_int_native_long_per_rep_s", f"{label}_dot_product_int_native_long_per_rep_delta_pct"),
    ]:
        base = parse_float_metric(baseline, metric_key)
        candidate = parse_float_metric(metrics, metric_key)
        if base is not None and candidate is not None and base != 0.0:
            print(f"{out_key}: {((candidate / base) - 1.0) * 100.0:+.2f}%")
PY

echo "arm64 fast-dot scalar-core read-split list<int> probe complete; summary: $summary_log"
echo "case manifest: $manifest_log"
