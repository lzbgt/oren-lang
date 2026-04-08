#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-smoke-native-fast-loops-${ts}.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
if [[ -n "$build_env_raw" ]]; then
    old_ifs="$IFS"
    IFS=','
    read -r -a build_env_parts <<<"$build_env_raw"
    IFS="$old_ifs"
fi

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
        echo "native fast-loop perf smoke failed for ${program}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

build_native_bin array_sum
build_native_bin dot_product

run_native_check array_sum 205 10 3
run_native_check array_sum 710 20 3
run_native_check dot_product 6590 10 3
run_native_check dot_product 54380 20 3

echo "native fast-loop perf smoke complete; log: $log_path"
