#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-${ts}.log"
manifest_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-${ts}.cases.tsv"
slot_warm_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-slot-warm-${ts}.run.log"
packed_warm_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-packed-warm-${ts}.run.log"
canonical_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-canonical-smoke-${ts}.log"
slot_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-slot-smoke-${ts}.log"
packed_smoke_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-packed-smoke-${ts}.log"

smoke="${OREN_PERF_SMOKE_LIST_INT:-0}"
sweeps="${OREN_LIST_INT_DOT_CEILING_STABILITY_SWEEPS:-5}"
runs="${OREN_LIST_INT_DOT_CEILING_STABILITY_RUNS:-3}"
warmups="${OREN_LIST_INT_DOT_CEILING_STABILITY_WARMUPS:-1}"
n="${OREN_LIST_INT_DOT_CEILING_STABILITY_N:-20000}"
reps="${OREN_LIST_INT_DOT_CEILING_STABILITY_REPS:-4}"
cov_warn="${OREN_LIST_INT_DOT_CEILING_STABILITY_COV_WARN:-0.10}"

cases=(
    baseline
    slot_direct
    slot_public
    packed_scalar
    packed_simd
)

case_programs() {
    case "$1" in
        baseline)
            printf '%s\n' "array_sum_int,dot_product_int"
            ;;
        slot_direct)
            printf '%s\n' "array_sum_int_slot_direct,dot_product_int_slot_direct"
            ;;
        slot_public)
            printf '%s\n' "array_sum_int_slot_public,dot_product_int_slot_public"
            ;;
        packed_scalar|packed_simd)
            printf '%s\n' "array_sum_int_packed_bridge,dot_product_int_packed_bridge"
            ;;
        *)
            return 1
            ;;
    esac
}

case_desc() {
    case "$1" in
        baseline)
            printf '%s\n' "default shipped canonical loops"
            ;;
        slot_direct)
            printf '%s\n' "hidden direct-slot helper benchmarks"
            ;;
        slot_public)
            printf '%s\n' "public std:linalg slot-surface benchmarks"
            ;;
        packed_scalar)
            printf '%s\n' "packed bridge benchmark with scalar native path"
            ;;
        packed_simd)
            printf '%s\n' "packed bridge benchmark with SIMD native path"
            ;;
        *)
            return 1
            ;;
    esac
}

case_native_env() {
    case "$1" in
        baseline|slot_direct|slot_public)
            ;;
        packed_scalar)
            printf '%s\n' "OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_NO_SIMD=1"
            ;;
        packed_simd)
            printf '%s\n' "OREN_ENABLE_SIMD=1"
            ;;
        *)
            return 1
            ;;
    esac
}

case_skip_build() {
    case "$1" in
        slot_direct|packed_scalar|packed_simd)
            printf '1\n'
            ;;
        baseline|slot_public)
            printf '0\n'
            ;;
        *)
            return 1
            ;;
    esac
}

run_case() {
    local sweep="$1"
    local order_idx="$2"
    local label="$3"
    local programs="$4"
    local desc="$5"
    local native_env="$6"
    local skip_build="$7"
    local run_log="$log_dir/perf-probe-list-int-dot-ceiling-stability-${label}-sweep${sweep}-${ts}.run.log"
    local status=0
    local case_summary=""

    local -a cmd=(
        env
        OREN_PERF_SMOKE_LIST_INT=0
        OREN_BENCH_PROGRAMS="$programs"
        OREN_BENCH_RUNS="$runs"
        OREN_BENCH_WARMUPS="$warmups"
        OREN_BENCH_LIST_INT_STEADY_N="$n"
        OREN_BENCH_LIST_INT_STEADY_REPS="$reps"
        OREN_BENCH_SKIP_OREN_C=1
        OREN_BENCH_SKIP_OBC=1
        OREN_BENCH_UPDATE_LATEST=0
        OREN_BENCH_UPDATE_LATEST_PRUNE=0
    )
    if [[ "$skip_build" == "1" ]]; then
        cmd+=(OREN_BENCH_SKIP_BUILD=1)
    fi
    if [[ -n "$native_env" ]]; then
        cmd+=(OREN_BENCH_ENV_OREN_NATIVE="$native_env")
    fi
    cmd+=(make perf-gate-list-int-steady)

    set +e
    "${cmd[@]}" >"$run_log" 2>&1
    status=$?
    set -e

    if [[ "$status" == "0" ]]; then
        case_summary="$(rg -o 'summary: .*' "$run_log" | tail -n 1 | sed -E 's/^summary: //')"
        if [[ -z "$case_summary" ]]; then
            echo "failed to locate summary path in $run_log" >&2
            status=98
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sweep" \
        "$order_idx" \
        "$label" \
        "$programs" \
        "$desc" \
        "$native_env" \
        "$run_log" \
        "$status" \
        "$case_summary" >>"$manifest_log"
}

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"$canonical_smoke_log" 2>&1
    ./scripts/run_perf_smoke_list_int_slot_direct.sh >"$slot_smoke_log" 2>&1
    OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND=native \
        ./scripts/run_perf_smoke_list_int_packed_bridge.sh >"$packed_smoke_log" 2>&1
fi

./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$slot_warm_log" 2>&1
./scripts/build_perf_artifacts_list_int_packed_bridge.sh >"$packed_warm_log" 2>&1

: >"$manifest_log"
case_count="${#cases[@]}"
sweep=1
while [[ "$sweep" -le "$sweeps" ]]; do
    start_idx=$(( (sweep - 1) % case_count ))
    order_idx=0
    while [[ "$order_idx" -lt "$case_count" ]]; do
        case_idx=$(( (start_idx + order_idx) % case_count ))
        label="${cases[$case_idx]}"
        programs="$(case_programs "$label")"
        desc="$(case_desc "$label")"
        native_env="$(case_native_env "$label")"
        skip_build="$(case_skip_build "$label")"
        run_case "$sweep" "$order_idx" "$label" "$programs" "$desc" "$native_env" "$skip_build"
        order_idx=$((order_idx + 1))
    done
    sweep=$((sweep + 1))
done

MANIFEST_LOG="$manifest_log" \
SMOKE="$smoke" \
SWEEPS="$sweeps" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
COV_WARN="$cov_warn" \
CANONICAL_SMOKE_LOG="$canonical_smoke_log" \
SLOT_SMOKE_LOG="$slot_smoke_log" \
PACKED_SMOKE_LOG="$packed_smoke_log" \
SLOT_WARM_LOG="$slot_warm_log" \
PACKED_WARM_LOG="$packed_warm_log" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
from collections import defaultdict


cases = ["baseline", "slot_direct", "slot_public", "packed_scalar", "packed_simd"]
dot_keys = {
    "baseline": "dot_product_int",
    "slot_direct": "dot_product_int_slot_direct",
    "slot_public": "dot_product_int_slot_public",
    "packed_scalar": "dot_product_int_packed_bridge",
    "packed_simd": "dot_product_int_packed_bridge",
}
array_keys = {
    "baseline": "array_sum_int",
    "slot_direct": "array_sum_int_slot_direct",
    "slot_public": "array_sum_int_slot_public",
    "packed_scalar": "array_sum_int_packed_bridge",
    "packed_simd": "array_sum_int_packed_bridge",
}


def pct_delta(candidate, baseline):
    if baseline == 0:
        return None
    return ((candidate / baseline) - 1.0) * 100.0


def parse_summary(path):
    by_program = {}
    current = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            if not line.startswith(" "):
                if line.startswith("list<int> steady summary:"):
                    continue
                current = line.strip()
                by_program.setdefault(current, {})
                continue
            if current is None:
                continue
            m = re.match(
                r"\s+(c|oren_native): median=([0-9.]+)s per_rep≈([0-9.]+)s cov=([0-9.]+)",
                line,
            )
            if m:
                variant = m.group(1)
                by_program[current][f"{variant}_median_s"] = float(m.group(2))
                by_program[current][f"{variant}_per_rep_s"] = float(m.group(3))
                by_program[current][f"{variant}_cov"] = float(m.group(4))
                continue
            m = re.match(r"\s+native/C steady ratio≈([0-9.]+)x", line)
            if m:
                by_program[current]["native_over_c"] = float(m.group(1))
    return by_program


rows = []
with open(os.environ["MANIFEST_LOG"], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue
        sweep, order_idx, label, programs, desc, native_env, run_log, status, summary_log = line.split(
            "\t", 8
        )
        row = {
            "sweep": int(sweep),
            "order_idx": int(order_idx),
            "label": label,
            "programs": programs,
            "desc": desc,
            "native_env": native_env,
            "run_log": run_log,
            "status": int(status),
            "summary_log": summary_log,
        }
        if row["status"] == 0 and row["summary_log"] and os.path.exists(row["summary_log"]):
            parsed = parse_summary(row["summary_log"])
            row["parsed"] = parsed
            dot_program = dot_keys[label]
            array_program = array_keys[label]
            dot_data = parsed.get(dot_program, {})
            array_data = parsed.get(array_program, {})
            row["dot_program"] = dot_program
            row["array_program"] = array_program
            row["dot_ratio"] = dot_data.get("native_over_c")
            row["array_ratio"] = array_data.get("native_over_c")
            row["dot_native_cov"] = dot_data.get("oren_native_cov")
            row["array_native_cov"] = array_data.get("oren_native_cov")
            row["dot_c_cov"] = dot_data.get("c_cov")
            row["array_c_cov"] = array_data.get("c_cov")
        rows.append(row)

rows_by_sweep = defaultdict(dict)
rows_by_case = defaultdict(list)
for row in rows:
    rows_by_sweep[row["sweep"]][row["label"]] = row
    rows_by_case[row["label"]].append(row)

cov_warn = float(os.environ["COV_WARN"])

print("list<int> dot-path ceiling stability summary")
print("")
print("purpose: order-sensitive ranking surface for canonical vs direct-slot vs public-slot vs packed paths")
print(f"run_smoke: {os.environ['SMOKE']}")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"n: {os.environ['N']}")
print(f"reps: {os.environ['REPS']}")
print(f"cov_warn: {cov_warn:.2f}")
print("rotation: order-balanced round-robin; each sweep shifts the starting case by one slot")
print(f"slot_warm_log: {os.environ['SLOT_WARM_LOG']}")
print(f"packed_warm_log: {os.environ['PACKED_WARM_LOG']}")
if os.environ["SMOKE"] == "1":
    print(f"canonical_smoke_log: {os.environ['CANONICAL_SMOKE_LOG']}")
    print(f"slot_smoke_log: {os.environ['SLOT_SMOKE_LOG']}")
    print(f"packed_smoke_log: {os.environ['PACKED_SMOKE_LOG']}")
print("")

for sweep in sorted(rows_by_sweep):
    print(f"sweep {sweep}:")
    ordered = sorted(rows_by_sweep[sweep].values(), key=lambda item: item["order_idx"])
    for row in ordered:
        print(f"  {row['label']}:")
        print(f"    order_idx: {row['order_idx']}")
        print(f"    description: {row['desc']}")
        if row["native_env"]:
            print(f"    native_env: {row['native_env']}")
        print(f"    programs: {row['programs']}")
        print(f"    wrapper_log: {row['run_log']}")
        print(f"    wrapper_exit_code: {row['status']}")
        if row["summary_log"]:
            print(f"    summary_log: {row['summary_log']}")
        if row.get("array_ratio") is not None:
            print(f"    array_sum_ratio: {row['array_ratio']:.4f}x")
            print(f"    dot_product_ratio: {row['dot_ratio']:.4f}x")
            if (
                row.get("array_c_cov") is not None
                and row.get("array_native_cov") is not None
                and (row["array_c_cov"] >= cov_warn or row["array_native_cov"] >= cov_warn)
            ):
                print(
                    "    warning_array_high_variance: "
                    f"c_cov={row['array_c_cov']:.4f} native_cov={row['array_native_cov']:.4f}"
                )
            if (
                row.get("dot_c_cov") is not None
                and row.get("dot_native_cov") is not None
                and (row["dot_c_cov"] >= cov_warn or row["dot_native_cov"] >= cov_warn)
            ):
                print(
                    "    warning_dot_high_variance: "
                    f"c_cov={row['dot_c_cov']:.4f} native_cov={row['dot_native_cov']:.4f}"
                )
    baseline = rows_by_sweep[sweep].get("baseline")
    if baseline and baseline.get("array_ratio") is not None and baseline.get("dot_ratio") is not None:
        for label in cases:
            if label == "baseline":
                continue
            candidate = rows_by_sweep[sweep].get(label)
            if not candidate or candidate.get("array_ratio") is None or candidate.get("dot_ratio") is None:
                continue
            print(
                f"  {label}_vs_baseline_array_delta_pct: "
                f"{pct_delta(candidate['array_ratio'], baseline['array_ratio']):+.2f}%"
            )
            print(
                f"  {label}_vs_baseline_dot_delta_pct: "
                f"{pct_delta(candidate['dot_ratio'], baseline['dot_ratio']):+.2f}%"
            )
    print("")


def complete_metric_sweeps(metric_key):
    out = {}
    for sweep, sweep_rows in rows_by_sweep.items():
        if all(label in sweep_rows and sweep_rows[label].get(metric_key) is not None for label in cases):
            out[sweep] = {label: sweep_rows[label][metric_key] for label in cases}
    return out


def print_rank_counts(title, metric_key):
    metric_sweeps = complete_metric_sweeps(metric_key)
    print(f"{title}:")
    print(f"  complete_sweeps: {len(metric_sweeps)}")
    if not metric_sweeps:
        print("  error: no complete sweeps")
        print("")
        return
    rank_counts = {label: [0] * len(cases) for label in cases}
    winners = {label: 0 for label in cases}
    for values in metric_sweeps.values():
        ranking = sorted((ratio, label) for label, ratio in values.items())
        for rank_idx, (_, label) in enumerate(ranking):
            rank_counts[label][rank_idx] += 1
        winners[ranking[0][1]] += 1
    for label in cases:
        counts = " ".join(f"rank{idx + 1}={count}" for idx, count in enumerate(rank_counts[label]))
        print(f"  {label}: wins={winners[label]}/{len(metric_sweeps)} {counts}")
    print("")


print_rank_counts("array_sum_rank_counts", "array_ratio")
print_rank_counts("dot_product_rank_counts", "dot_ratio")

for label in cases:
    print(f"{label}:")
    case_rows = [row for row in rows_by_case[label] if row.get("array_ratio") is not None and row.get("dot_ratio") is not None]
    if not case_rows:
        print("  error: no successful sweeps")
        print("")
        continue
    array_values = [row["array_ratio"] for row in case_rows]
    dot_values = [row["dot_ratio"] for row in case_rows]
    array_native_cov_values = [row["array_native_cov"] for row in case_rows if row.get("array_native_cov") is not None]
    dot_native_cov_values = [row["dot_native_cov"] for row in case_rows if row.get("dot_native_cov") is not None]
    print(
        f"  array_sum_ratio: median={statistics.median(array_values):.4f}x "
        f"min={min(array_values):.4f}x max={max(array_values):.4f}x"
    )
    print(
        f"  dot_product_ratio: median={statistics.median(dot_values):.4f}x "
        f"min={min(dot_values):.4f}x max={max(dot_values):.4f}x"
    )
    if array_native_cov_values:
        print(
            f"  array_native_cov: median={statistics.median(array_native_cov_values):.4f} "
            f"min={min(array_native_cov_values):.4f} max={max(array_native_cov_values):.4f}"
        )
    if dot_native_cov_values:
        print(
            f"  dot_native_cov: median={statistics.median(dot_native_cov_values):.4f} "
            f"min={min(dot_native_cov_values):.4f} max={max(dot_native_cov_values):.4f}"
        )
    if label != "baseline":
        array_deltas = []
        dot_deltas = []
        for sweep in sorted(rows_by_sweep):
            baseline = rows_by_sweep[sweep].get("baseline")
            candidate = rows_by_sweep[sweep].get(label)
            if not baseline or not candidate:
                continue
            if baseline.get("array_ratio") is None or candidate.get("array_ratio") is None:
                continue
            array_deltas.append(pct_delta(candidate["array_ratio"], baseline["array_ratio"]))
            dot_deltas.append(pct_delta(candidate["dot_ratio"], baseline["dot_ratio"]))
        if array_deltas:
            print(
                f"  array_vs_baseline_delta_pct: median={statistics.median(array_deltas):+.2f}% "
                f"min={min(array_deltas):+.2f}% max={max(array_deltas):+.2f}%"
            )
        if dot_deltas:
            print(
                f"  dot_vs_baseline_delta_pct: median={statistics.median(dot_deltas):+.2f}% "
                f"min={min(dot_deltas):+.2f}% max={max(dot_deltas):+.2f}%"
            )
    print("")

print("decision_note:")
print("  use this stability probe for public-slot vs hidden-helper ordering")
print("  keep make perf-probe-list-int-dot-ceiling as the cheap quick surface for fast sanity checks")
PY

echo "list<int> dot-path ceiling stability probe complete; summary: $summary_log"
echo "manifest: $manifest_log"
echo "slot warm log: $slot_warm_log"
echo "packed warm log: $packed_warm_log"
