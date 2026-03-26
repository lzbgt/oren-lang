#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir"
log_path="$log_dir/perf-prebuild-list-int-packed-bridge-${ts}.log"

platform="${OREN_BENCH_PLATFORM:-arm64-macos}"
compiler="./oren_stage2"
all_programs=(
    array_sum_int_packed_bridge
    dot_product_int_packed_bridge
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
    case "$program" in
        array_sum_int_packed_bridge)
            ./oren_stage2 build "$src" --backend native --no-debug -o "$out"
            ;;
        dot_product_int_packed_bridge)
            OREN_NATIVE_RUNTIME_PROFILE=full ./oren_stage2 build "$src" --backend native --no-debug -o "$out"
            ;;
        *)
            echo "unknown packed-bridge program: $program" >&2
            return 1
            ;;
    esac
}

needs_rebuild() {
    local out="$1"
    local src="$2"
    if [[ ! -x "$out" ]]; then
        return 0
    fi
    if [[ "${OREN_PERF_PREBUILD_FORCE:-0}" == "1" ]]; then
        return 0
    fi
    if [[ "$src" -nt "$out" || "$compiler" -nt "$out" ]]; then
        return 0
    fi
    return 1
}

for program in "${programs[@]}"; do
    src="benchmarks/${program}/${program}.oren"
    out_dir="build/benchmarks/${program}"
    out="${out_dir}/${program}_oren_native"
    mkdir -p "$out_dir"
    if needs_rebuild "$out" "$src"; then
        {
            case "$program" in
                array_sum_int_packed_bridge)
                    echo "[build] ${program} (native core runtime)"
                    ;;
                dot_product_int_packed_bridge)
                    echo "[build] ${program} (native full runtime)"
                    ;;
            esac
            build_program "$program" "$src" "$out"
        } >>"$log_path" 2>&1
    else
        echo "[cached] ${program}" >>"$log_path"
    fi
done

echo "packed-bridge native prebuild complete; log: $log_path"
