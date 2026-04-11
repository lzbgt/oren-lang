#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-${ts}.log"
manifest_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-${ts}.cases.tsv"

programs="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_PROGRAMS:-dot_product_int}"
sweeps="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_SWEEPS:-4}"
runs="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_RUNS:-5}"
warmups="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_WARMUPS:-1}"
bench_args="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_ARGS:-2000000 1}"
case_set="${OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_CASES:-baseline cursor_disabled scalar_enabled cursor_scalar_enabled}"

read -r -a cases <<<"$case_set"

case_env_desc() {
    case "$1" in
        baseline)
            printf '%s\n' "default shipped baseline"
            ;;
        cursor_disabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0"
            ;;
        scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        cursor_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1"
            ;;
        unroll2_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_pair_post_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1"
            ;;
        unroll2_dual_accum_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1"
            ;;
        unroll2_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        unroll2_pair_post_dual_accum_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1"
            ;;
        unroll2_pair_post_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        unroll2_madd_all_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_pair_post_madd_all_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        scalar_post_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1"
            ;;
        scalar_post_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        low32_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1"
            ;;
        low32_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_low32_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1"
            ;;
        unroll2_low32_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        prefix_pair_loop_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1"
            ;;
        *)
            printf 'unknown case: %s\n' "$1" >&2
            return 1
            ;;
    esac
}

case_build_env() {
    case "$1" in
        baseline)
            ;;
        cursor_disabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0"
            ;;
        scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        cursor_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1"
            ;;
        unroll2_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_pair_post_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1"
            ;;
        unroll2_dual_accum_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1"
            ;;
        unroll2_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        unroll2_pair_post_dual_accum_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1"
            ;;
        unroll2_pair_post_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        unroll2_madd_all_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_pair_post_madd_all_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        scalar_post_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1"
            ;;
        scalar_post_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        low32_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1"
            ;;
        low32_scalar_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1"
            ;;
        unroll2_low32_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1"
            ;;
        unroll2_low32_dual_madd_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1,OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1,OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1"
            ;;
        prefix_pair_loop_enabled)
            printf '%s\n' "OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1"
            ;;
        *)
            printf 'unknown case: %s\n' "$1" >&2
            return 1
            ;;
    esac
}

latest_result_json() {
    python3 - <<'PY'
import glob
import os

paths = sorted(
    glob.glob("build/benchmarks/results/dot_product_int_darwin_arm64_*.json"),
    key=os.path.getmtime,
)
if not paths:
    raise SystemExit(1)
print(paths[-1])
PY
}

run_case() {
    local sweep="$1"
    local order_idx="$2"
    local label="$3"
    local env_desc="$4"
    local build_env="$5"
    local run_log="$log_dir/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-${label}-sweep${sweep}-${ts}.run.log"
    local status=0
    local result_json=""

    set +e
    env \
        OREN_PERF_SMOKE_LIST_INT=0 \
        OREN_BENCH_PROGRAMS="$programs" \
        OREN_BENCH_RUNS="$runs" \
        OREN_BENCH_WARMUPS="$warmups" \
        OREN_BENCH_ARGS="$bench_args" \
        OREN_BENCH_SKIP_OREN_C=1 \
        OREN_BENCH_SKIP_OBC=1 \
        OREN_BENCH_UPDATE_LATEST=0 \
        OREN_BENCH_UPDATE_LATEST_PRUNE=0 \
        OREN_BENCH_ENV_BUILD_OREN="$build_env" \
        make perf-gate-list-int >"$run_log" 2>&1
    status=$?
    if [[ "$status" == "0" ]]; then
        result_json="$(latest_result_json)"
    fi
    set -e

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sweep" \
        "$order_idx" \
        "$label" \
        "$run_log" \
        "$status" \
        "$env_desc" \
        "$result_json" >>"$manifest_log"
}

: >"$manifest_log"
case_count="${#cases[@]}"
sweep=1
while [[ "$sweep" -le "$sweeps" ]]; do
    start_idx=$(( (sweep - 1) % case_count ))
    order_idx=0
    while [[ "$order_idx" -lt "$case_count" ]]; do
        case_idx=$(( (start_idx + order_idx) % case_count ))
        label="${cases[$case_idx]}"
        env_desc="$(case_env_desc "$label")"
        build_env="$(case_build_env "$label")"
        run_case "$sweep" "$order_idx" "$label" "$env_desc" "$build_env"
        order_idx=$((order_idx + 1))
    done
    sweep=$((sweep + 1))
done

MANIFEST_LOG="$manifest_log" \
PROGRAMS="$programs" \
SWEEPS="$sweeps" \
RUNS="$runs" \
WARMUPS="$warmups" \
BENCH_ARGS="$bench_args" \
CASE_SET="$case_set" \
python3 - <<'PY' >"$summary_log"
import json
import os
import statistics
from collections import defaultdict


def pct_delta(candidate, baseline):
    if baseline == 0:
        return None
    return ((candidate / baseline) - 1.0) * 100.0


rows = []
with open(os.environ["MANIFEST_LOG"], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue
        sweep, order_idx, label, run_log, status, env_desc, result_json = line.split("\t", 6)
        rows.append(
            {
                "sweep": int(sweep),
                "order_idx": int(order_idx),
                "label": label,
                "run_log": run_log,
                "status": int(status),
                "env_desc": env_desc,
                "result_json": result_json,
            }
        )

metrics_by_case = defaultdict(list)
metrics_by_sweep = defaultdict(dict)

for row in rows:
    print_row = dict(row)
    if row["status"] == 0 and row["result_json"] and os.path.exists(row["result_json"]):
        data = json.load(open(row["result_json"], "r", encoding="utf-8"))
        c = data["results"]["c"]
        native = data["results"]["oren_native"]
        print_row.update(
            {
                "c_median_s": c["median_s"],
                "c_cov": c.get("cov", 0.0),
                "native_median_s": native["median_s"],
                "native_cov": native.get("cov", 0.0),
                "native_over_c": native["median_s"] / c["median_s"],
            }
        )
    metrics_by_case[row["label"]].append(print_row)
    metrics_by_sweep[row["sweep"]][row["label"]] = print_row

print("arm64 fast dot scalar-core gate stability list<int> summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"bench_args: {os.environ['BENCH_ARGS']}")
case_labels = os.environ["CASE_SET"].split()
print(f"case_set: {os.environ['CASE_SET']}")
print("rotation: order-balanced round-robin; each case shifts start position once")
print("")

for sweep in sorted(metrics_by_sweep):
    print(f"sweep {sweep}:")
    ordered = sorted(metrics_by_sweep[sweep].values(), key=lambda item: item["order_idx"])
    for row in ordered:
        print(f"  {row['label']}:")
        print(f"    order_idx: {row['order_idx']}")
        print(f"    enabled_build_env: {row['env_desc']}")
        print(f"    wrapper_log: {row['run_log']}")
        print(f"    wrapper_exit_code: {row['status']}")
        if row.get("result_json"):
            print(f"    result_json: {row['result_json']}")
        if "c_median_s" in row:
            print(f"    c_median_s: {row['c_median_s']:.6f}")
            print(f"    c_cov: {row['c_cov']:.4f}")
            print(f"    native_median_s: {row['native_median_s']:.6f}")
            print(f"    native_cov: {row['native_cov']:.4f}")
            print(f"    native_over_c: {row['native_over_c']:.4f}x")
            if row["c_cov"] >= 0.10 or row["native_cov"] >= 0.10:
                print(
                    "    warning_high_variance: "
                    f"c_cov={row['c_cov']:.4f} native_cov={row['native_cov']:.4f}"
                )
    baseline = metrics_by_sweep[sweep].get("baseline")
    if baseline and "native_median_s" in baseline:
        for label in [item for item in case_labels if item != "baseline"]:
            candidate = metrics_by_sweep[sweep].get(label)
            if candidate and "native_median_s" in candidate:
                delta_native = pct_delta(candidate["native_median_s"], baseline["native_median_s"])
                delta_ratio = pct_delta(candidate["native_over_c"], baseline["native_over_c"])
                print(
                    f"  {label}_vs_baseline_native_delta_pct: {delta_native:+.2f}%"
                )
                print(
                    f"  {label}_vs_baseline_native_over_c_delta_pct: {delta_ratio:+.2f}%"
                )
    print("")

for label in case_labels:
    case_rows = [row for row in metrics_by_case[label] if "native_median_s" in row]
    print(f"{label}:")
    if not case_rows:
        print("  error: no successful sweeps")
        print("")
        continue
    native_values = [row["native_median_s"] for row in case_rows]
    ratio_values = [row["native_over_c"] for row in case_rows]
    c_values = [row["c_median_s"] for row in case_rows]
    native_cov_values = [row["native_cov"] for row in case_rows]
    print(
        f"  native_median_s: median={statistics.median(native_values):.6f} "
        f"min={min(native_values):.6f} max={max(native_values):.6f}"
    )
    print(
        f"  native_over_c: median={statistics.median(ratio_values):.4f}x "
        f"min={min(ratio_values):.4f}x max={max(ratio_values):.4f}x"
    )
    print(
        f"  c_median_s: median={statistics.median(c_values):.6f} "
        f"min={min(c_values):.6f} max={max(c_values):.6f}"
    )
    print(
        f"  native_cov: median={statistics.median(native_cov_values):.4f} "
        f"min={min(native_cov_values):.4f} max={max(native_cov_values):.4f}"
    )
    if label != "baseline":
        deltas_native = []
        deltas_ratio = []
        win_count_native = 0
        win_count_ratio = 0
        for sweep in sorted(metrics_by_sweep):
            baseline = metrics_by_sweep[sweep].get("baseline")
            candidate = metrics_by_sweep[sweep].get(label)
            if not baseline or not candidate:
                continue
            if "native_median_s" not in baseline or "native_median_s" not in candidate:
                continue
            delta_native = pct_delta(candidate["native_median_s"], baseline["native_median_s"])
            delta_ratio = pct_delta(candidate["native_over_c"], baseline["native_over_c"])
            deltas_native.append(delta_native)
            deltas_ratio.append(delta_ratio)
            if delta_native < 0:
                win_count_native += 1
            if delta_ratio < 0:
                win_count_ratio += 1
        if deltas_native:
            print(
                f"  vs_baseline_native_delta_pct: median={statistics.median(deltas_native):+.2f}% "
                f"min={min(deltas_native):+.2f}% max={max(deltas_native):+.2f}% "
                f"wins={win_count_native}/{len(deltas_native)}"
            )
        if deltas_ratio:
            print(
                f"  vs_baseline_native_over_c_delta_pct: median={statistics.median(deltas_ratio):+.2f}% "
                f"min={min(deltas_ratio):+.2f}% max={max(deltas_ratio):+.2f}% "
                f"wins={win_count_ratio}/{len(deltas_ratio)}"
            )
    print("")
PY

echo "arm64 fast-dot scalar-core gate-stability list<int> probe complete; summary: $summary_log"
echo "case manifest: $manifest_log"
