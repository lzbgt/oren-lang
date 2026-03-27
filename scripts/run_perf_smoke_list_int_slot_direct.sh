#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-smoke-list-int-slot-direct-${ts}.log"

bin_path() {
    local program="$1"
    printf 'build/benchmarks/%s/%s_oren_native\n' "$program" "$program"
}

{
    echo "[build] slot-direct benchmarks backend=native"
    ./scripts/build_perf_artifacts_list_int_slot_direct.sh
} >>"$log_path" 2>&1

run_native_check() {
    local program="$1"
    local expected="$2"
    shift 2
    local bin
    bin="$(bin_path "$program")"

    echo "[run] ${program} args='$*'" >>"$log_path"
    local actual
    actual="$("$bin" "$@" 2>>"$log_path" | tr -d '\r')"
    echo "[out] ${program} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "slot-direct perf smoke failed for ${program}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

run_native_check array_sum_int_slot_direct 205 10 3
run_native_check array_sum_int_slot_direct 710 20 3
run_native_check dot_product_int_slot_direct 6590 10 3
run_native_check dot_product_int_slot_direct 54380 20 3

echo "slot-direct list<int> perf smoke complete; log: $log_path"
