#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-smoke-list-int-${ts}.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

build_native() {
    local src="$1"
    local out="$2"
    if [[ ${#build_env_parts[@]} -gt 0 ]]; then
        env "${build_env_parts[@]}" ./oren_stage2 build "$src" --backend native --no-debug --no-cache -o "$out"
    else
        ./oren_stage2 build "$src" --backend native --no-debug --no-cache -o "$out"
    fi
}

build_native_bin() {
    local program="$1"
    local out_dir="build/benchmarks/${program}"
    local src="benchmarks/${program}/${program}.oren"
    local bin="${out_dir}/${program}_oren_native"
    mkdir -p "$out_dir"

    {
        echo "[build] ${program}"
        if [[ -n "$build_env_raw" ]]; then
            echo "[build_env] ${build_env_raw}"
        fi
        build_native "$src" "$bin"
    } >>"$log_path" 2>&1
}

run_native_check() {
    local program="$1"
    local expected="$2"
    shift 2
    local bin="build/benchmarks/${program}/${program}_oren_native"

    echo "[run] ${program} $*" >>"$log_path"

    local actual
    actual="$("$bin" "$@" 2>>"$log_path" | tr -d '\r')"
    echo "[out] ${program} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "list<int> perf smoke failed for ${program}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

build_native_bin array_sum_int
build_native_bin array_sum_int_step7
build_native_bin dot_product_int

run_native_check array_sum_int 205 10 3
run_native_check array_sum_int 710 20 3
run_native_check array_sum_int_step7 335 10 3
run_native_check array_sum_int_step7 1370 20 3
run_native_check dot_product_int 6590 10 3
run_native_check dot_product_int 54380 20 3

echo "list<int> perf smoke complete; log: $log_path"
