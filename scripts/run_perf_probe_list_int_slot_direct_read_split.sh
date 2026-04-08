#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-slot-direct-read-split-${ts}.log"
baseline_smoke_log="$log_dir/perf-probe-list-int-slot-direct-read-split-baseline-smoke-${ts}.log"
slot_smoke_log="$log_dir/perf-probe-list-int-slot-direct-read-split-slot-smoke-${ts}.log"
baseline_log="$log_dir/perf-probe-list-int-slot-direct-read-split-base-${ts}.run.log"
slot_warm_log="$log_dir/perf-probe-list-int-slot-direct-read-split-slot-warm-${ts}.run.log"
slot_log="$log_dir/perf-probe-list-int-slot-direct-read-split-slot-${ts}.run.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
baseline_programs="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_BASELINE_PROGRAMS:-array_sum_int,dot_product_int}"
slot_programs="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_SLOT_PROGRAMS:-array_sum_int_slot_direct,dot_product_int_slot_direct}"
smoke="${OREN_PERF_SMOKE_LIST_INT_SLOT_DIRECT_SPLIT:-${OREN_PERF_SMOKE_LIST_INT:-1}}"
runs="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_RUNS:-2}"
warmups="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_WARMUPS:-0}"
n="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_N:-20000}"
short_reps="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_SLOT_DIRECT_SPLIT_LONG_REPS:-2}"

run_one() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
    local summary
    summary="$(rg -o 'summary: .*' "$run_log" | tail -n 1 | sed -E 's/^summary: //')"
    if [[ -z "$summary" ]]; then
        echo "failed to locate summary path in $run_log" >&2
        return 1
    fi
    printf '%s\n' "$summary"
}

if [[ "$smoke" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"$baseline_smoke_log" 2>&1
    ./scripts/run_perf_smoke_list_int_slot_direct.sh >"$slot_smoke_log" 2>&1
fi

baseline_summary="$(run_one "$baseline_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$baseline_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"
./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$slot_warm_log" 2>&1
slot_summary="$(run_one "$slot_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$slot_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"

BASELINE_SUMMARY="$baseline_summary" \
SLOT_SUMMARY="$slot_summary" \
BUILD_ENV="$build_env_raw" \
SMOKE="$smoke" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
BASELINE_SMOKE_LOG="$baseline_smoke_log" \
SLOT_SMOKE_LOG="$slot_smoke_log" \
python3 - <<'PY' >"$summary_log"
import os
import re


def parse_summary(path):
    out = {}
    current = None
    for raw in open(path, "r", encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line:
            continue
        if not line.startswith(" "):
            if line.startswith("list<int> read split summary:"):
                continue
            if line.startswith("build_env:"):
                continue
            current = line.strip()
            out[current] = {}
            continue
        if current is None:
            continue
        m_long = re.match(r"\s+native/C long-per-rep ratio≈(-?[0-9.]+)x", line)
        if m_long:
            out[current]["long"] = float(m_long.group(1))
        m_delta = re.match(r"\s+native/C delta ratio≈(-?[0-9.]+)x", line)
        if m_delta:
            out[current]["delta"] = float(m_delta.group(1))
    return out


baseline = parse_summary(os.environ["BASELINE_SUMMARY"])
slot = parse_summary(os.environ["SLOT_SUMMARY"])
pairs = [
    ("array_sum_int", "array_sum_int_slot_direct"),
    ("dot_product_int", "dot_product_int_slot_direct"),
]

print("list<int> direct-slot read-split probe summary")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"run_smoke: {os.environ['SMOKE']}")
print(f"runs: {os.environ['RUNS']}")
print(f"warmups: {os.environ['WARMUPS']}")
print(f"n: {os.environ['N']}")
print(f"short_reps: {os.environ['SHORT_REPS']}")
print(f"long_reps: {os.environ['LONG_REPS']}")
print("")
if os.environ["SMOKE"] == "1":
    print(f"baseline_smoke_log: {os.environ['BASELINE_SMOKE_LOG']}")
    print(f"slot_smoke_log: {os.environ['SLOT_SMOKE_LOG']}")
    print("")
print(f"baseline_summary: {os.environ['BASELINE_SUMMARY']}")
print(f"slot_summary: {os.environ['SLOT_SUMMARY']}")
print("")

for baseline_name, slot_name in pairs:
    b = baseline.get(baseline_name, {})
    s = slot.get(slot_name, {})
    print(f"{baseline_name}:")
    for key, label in [("long", "long_per_rep"), ("delta", "delta")]:
        bv = b.get(key)
        sv = s.get(key)
        if bv is not None:
            print(f"  canonical_native/C_{label}: {bv:.4f}x")
        if sv is not None:
            print(f"  slot_direct_native/C_{label}: {sv:.4f}x")
        if bv is not None and sv is not None:
            print(f"  slot_direct_vs_canonical_{label}: {(sv / bv):.4f}x")
    long_b = b.get("long")
    long_s = s.get("long")
    if long_b is not None and long_s is not None:
        if long_s < long_b:
            print("  winner_long_per_rep: slot_direct")
        elif long_s > long_b:
            print("  winner_long_per_rep: canonical")
        else:
            print("  winner_long_per_rep: tie")
    delta_b = b.get("delta")
    delta_s = s.get("delta")
    if delta_b is not None and delta_s is not None and (delta_b <= 0 or delta_s <= 0):
        print("  note: delta metric is unstable on this run; prefer long_per_rep for tracker updates")
    print("")
PY

echo "list<int> direct-slot read-split probe complete; summary: $summary_log"
echo "baseline log: $baseline_log"
echo "slot warm log: $slot_warm_log"
echo "slot log: $slot_log"
