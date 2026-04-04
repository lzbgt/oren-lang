#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-prebuild-list-int-slot-direct-${ts}.log"

platform="${OREN_BENCH_PLATFORM:-arm64-macos}"
compiler="./oren_stage2"
bench_cc="${OREN_BENCH_CC:-${CC:-cc}}"
uname_s="$(uname -s)"
exe_ext=""
if [[ "$uname_s" == MINGW* || "$uname_s" == MSYS* || "$uname_s" == CYGWIN* || "${OS:-}" == "Windows_NT" ]]; then
    exe_ext=".exe"
fi
all_programs=(
    array_sum_int_slot_direct
    dot_product_int_slot_direct
)

if [[ -n "${OREN_PERF_PREBUILD_PROGRAMS:-}" ]]; then
    IFS=',' read -r -a programs <<<"${OREN_PERF_PREBUILD_PROGRAMS}"
else
    programs=("${all_programs[@]}")
fi

build_program() {
    local program="$1"
    local src="$2"
    local out="$3"
    local c_src="$4"
    local c_out="$5"
    if [[ "${bench_cc##*/}" == "cl" || "${bench_cc##*/}" == "cl.exe" ]]; then
        "$bench_cc" /nologo /O2 "$c_src" "/Fe:$c_out"
    else
        "$bench_cc" -O2 -o "$c_out" "$c_src"
    fi
    ./oren_stage2 build "$src" --backend native --no-debug -o "$out"
}

needs_rebuild() {
    local native_out="$1"
    local src="$2"
    local c_out="$3"
    local c_src="$4"
    if [[ ! -x "$native_out" || ! -x "$c_out" ]]; then
        return 0
    fi
    if [[ "${OREN_PERF_PREBUILD_FORCE:-0}" == "1" ]]; then
        return 0
    fi
    if [[ "$src" -nt "$native_out" || "$compiler" -nt "$native_out" ]]; then
        return 0
    fi
    if [[ "$c_src" -nt "$c_out" ]]; then
        return 0
    fi
    return 1
}

for program in "${programs[@]}"; do
    src="benchmarks/${program}/${program}.oren"
    c_src="benchmarks/${program}/${program}.c"
    out_dir="build/benchmarks/${program}"
    out="${out_dir}/${program}_oren_native"
    c_out="${out_dir}/${program}_c${exe_ext}"
    mkdir -p "$out_dir"
    if needs_rebuild "$out" "$src" "$c_out" "$c_src"; then
        {
            echo "[build] ${program} (C + native direct-slot runtime)"
            build_program "$program" "$src" "$out" "$c_src" "$c_out"
        } >>"$log_path" 2>&1
    else
        echo "[cached] ${program}" >>"$log_path"
    fi
done

echo "slot-direct C+native prebuild complete; log: $log_path"
