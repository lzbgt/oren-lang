#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-smoke-list-int-packed-bridge-${ts}.log"
backend="${OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND:-oren_c}"
platform="${OREN_BENCH_PLATFORM:-arm64-macos}"

build_native_bin() {
    local program="$1"
    local out_dir="build/benchmarks/${program}"
    local src="benchmarks/${program}/${program}.oren"
    local bin="${out_dir}/${program}_${backend}"
    mkdir -p "$out_dir"

    {
        echo "[build] ${program} backend=${backend}"
        if [[ "$backend" == "native" ]]; then
            OREN_NATIVE_RUNTIME_PROFILE=full ./oren_stage2 build "$src" --backend native --no-debug -o "$bin"
        else
            ./oren_stage2 build "$src" --backend c --platform "$platform" --no-debug -o "$bin"
        fi
    } >>"$log_path" 2>&1
}

run_native_check() {
    local program="$1"
    local expected="$2"
    local env_assignments="$3"
    shift 3
    local bin="build/benchmarks/${program}/${program}_${backend}"

    echo "[run] ${program} env='${env_assignments}' args='$*'" >>"$log_path"

    local actual
    if [[ -n "$env_assignments" ]]; then
        actual="$(env ${env_assignments} "$bin" "$@" 2>>"$log_path" | tr -d '\r')"
    else
        actual="$("$bin" "$@" 2>>"$log_path" | tr -d '\r')"
    fi
    echo "[out] ${program} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "packed-bridge perf smoke failed for ${program}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

build_native_bin array_sum_int_packed_bridge
build_native_bin dot_product_int_packed_bridge

run_native_check array_sum_int_packed_bridge 205 "" 10 3
run_native_check array_sum_int_packed_bridge 710 "" 20 3
run_native_check dot_product_int_packed_bridge 6590 "" 10 3
run_native_check dot_product_int_packed_bridge 54380 "" 20 3
run_native_check dot_product_int_packed_bridge 6590 "OREN_BENCH_PACKED_BRIDGE_SCALAR=1" 10 3
run_native_check dot_product_int_packed_bridge 54380 "OREN_BENCH_PACKED_BRIDGE_SCALAR=1" 20 3

echo "packed-bridge list<int> perf smoke complete; log: $log_path"
