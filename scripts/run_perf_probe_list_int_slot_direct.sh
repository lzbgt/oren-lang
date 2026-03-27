#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-slot-direct-${ts}.log"
warm_log="$log_dir/perf-probe-list-int-slot-direct-warm-${ts}.run.log"
base_log="$log_dir/perf-probe-list-int-slot-direct-base-${ts}.run.log"
slot_log="$log_dir/perf-probe-list-int-slot-direct-slot-${ts}.run.log"
slot_programs="array_sum_int_slot_direct,dot_product_int_slot_direct"

if [[ "${OREN_PERF_SMOKE_LIST_INT:-1}" == "1" ]]; then
    ./scripts/run_perf_smoke_list_int_slot_direct.sh >"$log_dir/perf-probe-list-int-slot-direct-smoke-${ts}.log" 2>&1
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

warm_slot_builds() {
    ./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$warm_log" 2>&1
}

baseline_summary="$(run_one "$base_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_OREN_C=1 make perf-gate-list-int-steady)"
warm_slot_builds
slot_summary="$(run_one "$slot_log" env OREN_PERF_SMOKE_LIST_INT=0 OREN_BENCH_SKIP_BUILD=1 OREN_BENCH_SKIP_OREN_C=1 OREN_BENCH_PROGRAMS="$slot_programs" make perf-gate-list-int-steady)"

BASELINE_SUMMARY="$baseline_summary" \
SLOT_SUMMARY="$slot_summary" \
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
    ("baseline", os.environ["BASELINE_SUMMARY"], ["array_sum_int", "dot_product_int"]),
    ("slot_direct", os.environ["SLOT_SUMMARY"], ["array_sum_int_slot_direct", "dot_product_int_slot_direct"]),
]

print("list<int> direct-slot steady probe summary")
print("")
for name, path, programs in cases:
    print(f"{name}: {path}")
    data = parse_summary(path)
    for program in programs:
        ratio = data.get(program)
        if ratio is not None:
            print(f"  {program}: native/C steady ratio≈{ratio:.4f}x")
    print("")
PY

echo "list<int> direct-slot steady probe complete; summary: $summary_log"
echo "warm log: $warm_log"
echo "base log: $base_log"
echo "slot log: $slot_log"
