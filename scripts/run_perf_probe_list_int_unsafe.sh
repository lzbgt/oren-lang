#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-unsafe-${ts}.log"
base_log="$log_dir/perf-probe-list-int-unsafe-base-${ts}.run.log"
assume_list_log="$log_dir/perf-probe-list-int-unsafe-assume-list-${ts}.run.log"
assume_index_log="$log_dir/perf-probe-list-int-unsafe-assume-index-${ts}.run.log"
both_log="$log_dir/perf-probe-list-int-unsafe-both-${ts}.run.log"

if [[ "${OREN_PERF_SMOKE_LIST_INT:-1}" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int.sh >"$log_dir/perf-probe-list-int-unsafe-smoke-${ts}.log" 2>&1
fi

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

baseline_summary="$(run_one "$base_log" env OREN_PERF_SMOKE_LIST_INT=0 make perf-gate-list-int-steady)"
assume_list_summary="$(run_one "$assume_list_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_ENV_OREN_NATIVE=OREN_LIST_ASSUME_LIST=1 make perf-gate-list-int-steady)"
assume_index_summary="$(run_one "$assume_index_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_NATIVE_ASSUME_LIST_INDEX=1 make perf-gate-list-int-steady)"
both_summary="$(run_one "$both_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_NATIVE_ASSUME_LIST_INDEX=1 OREN_BENCH_ENV_OREN_NATIVE=OREN_LIST_ASSUME_LIST=1 make perf-gate-list-int-steady)"

BASELINE_SUMMARY="$baseline_summary" \
ASSUME_LIST_SUMMARY="$assume_list_summary" \
ASSUME_INDEX_SUMMARY="$assume_index_summary" \
BOTH_SUMMARY="$both_summary" \
python3 - <<'PY' >"$summary_log"
import os
import re

def parse_summary(path):
    out = {}
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
                continue
            if current is None:
                continue
            m = re.match(r"\s+native/C steady ratio≈([0-9.]+)x", line)
            if m:
                out[current] = float(m.group(1))
    return out

cases = [
    ("baseline", os.environ["BASELINE_SUMMARY"]),
    ("assume_list", os.environ["ASSUME_LIST_SUMMARY"]),
    ("assume_index", os.environ["ASSUME_INDEX_SUMMARY"]),
    ("assume_both", os.environ["BOTH_SUMMARY"]),
]

programs = ["array_sum_int", "dot_product_int"]
print("list<int> unsafe steady probe summary")
print("")
for name, path in cases:
    print(f"{name}: {path}")
    data = parse_summary(path)
    for program in programs:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C steady ratio≈{ratio:.4f}x")
    print("")
PY

echo "list<int> unsafe steady probe complete; summary: $summary_log"
echo "base log: $base_log"
echo "assume-list log: $assume_list_log"
echo "assume-index log: $assume_index_log"
echo "both log: $both_log"
