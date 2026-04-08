#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-slot-surface-read-split-${ts}.log"
baseline_smoke_log="$log_dir/perf-probe-list-int-slot-surface-read-split-baseline-smoke-${ts}.log"
surface_smoke_log="$log_dir/perf-probe-list-int-slot-surface-read-split-surface-smoke-${ts}.log"
baseline_log="$log_dir/perf-probe-list-int-slot-surface-read-split-base-${ts}.run.log"
surface_warm_log="$log_dir/perf-probe-list-int-slot-surface-read-split-surface-warm-${ts}.run.log"
surface_log="$log_dir/perf-probe-list-int-slot-surface-read-split-surface-${ts}.run.log"

build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
baseline_programs="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_BASELINE_PROGRAMS:-array_sum_int,dot_product_int}"
surface_programs="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_PROGRAMS:-array_sum_int_slot_direct,array_sum_int_slot_public,dot_product_int_slot_direct,dot_product_int_slot_public}"
smoke="${OREN_PERF_SMOKE_LIST_INT_SLOT_SURFACE_SPLIT:-${OREN_PERF_SMOKE_LIST_INT:-1}}"
runs="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_RUNS:-2}"
warmups="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_WARMUPS:-0}"
n="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_N:-20000}"
short_reps="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_SLOT_SURFACE_SPLIT_LONG_REPS:-2}"

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
    ./scripts/run_perf_smoke_list_int_slot_direct.sh >"$surface_smoke_log" 2>&1
fi

baseline_summary="$(run_one "$baseline_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$baseline_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"
./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$surface_warm_log" 2>&1
surface_summary="$(run_one "$surface_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$surface_programs" OREN_BENCH_RUNS="$runs" OREN_BENCH_WARMUPS="$warmups" OREN_BENCH_LIST_INT_SPLIT_N="$n" OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS="$short_reps" OREN_BENCH_LIST_INT_SPLIT_LONG_REPS="$long_reps" make perf-gate-list-int-read-split)"

BASELINE_SUMMARY="$baseline_summary" \
SURFACE_SUMMARY="$surface_summary" \
BUILD_ENV="$build_env_raw" \
SMOKE="$smoke" \
RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
BASELINE_SMOKE_LOG="$baseline_smoke_log" \
SURFACE_SMOKE_LOG="$surface_smoke_log" \
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
surface = parse_summary(os.environ["SURFACE_SUMMARY"])
cases = [
    ("array_sum_int", "array_sum_int_slot_direct", "array_sum_int_slot_public"),
    ("dot_product_int", "dot_product_int_slot_direct", "dot_product_int_slot_public"),
]

print("list<int> slot-surface read-split probe summary")
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
    print(f"surface_smoke_log: {os.environ['SURFACE_SMOKE_LOG']}")
    print("")
print(f"baseline_summary: {os.environ['BASELINE_SUMMARY']}")
print(f"surface_summary: {os.environ['SURFACE_SUMMARY']}")
print("")

for baseline_name, direct_name, public_name in cases:
    b = baseline.get(baseline_name, {})
    d = surface.get(direct_name, {})
    p = surface.get(public_name, {})
    print(f"{baseline_name}:")
    for key, label in [("long", "long_per_rep"), ("delta", "delta")]:
        bv = b.get(key)
        dv = d.get(key)
        pv = p.get(key)
        if bv is not None:
            print(f"  canonical_native/C_{label}: {bv:.4f}x")
        if dv is not None:
            print(f"  slot_direct_native/C_{label}: {dv:.4f}x")
        if pv is not None:
            print(f"  slot_public_native/C_{label}: {pv:.4f}x")
        if bv is not None and dv is not None:
            print(f"  slot_direct_vs_canonical_{label}: {(dv / bv):.4f}x")
        if bv is not None and pv is not None:
            print(f"  slot_public_vs_canonical_{label}: {(pv / bv):.4f}x")
        if dv is not None and pv is not None:
            print(f"  slot_public_vs_slot_direct_{label}: {(pv / dv):.4f}x")
    long_candidates = []
    for name, data in [
        ("canonical", b.get("long")),
        ("slot_direct", d.get("long")),
        ("slot_public", p.get("long")),
    ]:
        if data is not None:
            long_candidates.append((data, name))
    if long_candidates:
        print(f"  winner_long_per_rep: {min(long_candidates)[1]}")
    delta_values = [b.get("delta"), d.get("delta"), p.get("delta")]
    if any(v is not None and v <= 0 for v in delta_values):
        print("  note: delta metric is unstable on this run; prefer long_per_rep for tracker updates")
    print("")
PY

echo "list<int> slot-surface read-split probe complete; summary: $summary_log"
echo "baseline log: $baseline_log"
echo "surface warm log: $surface_warm_log"
echo "surface log: $surface_log"
