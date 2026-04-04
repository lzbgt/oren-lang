#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-debug-native-benchmark-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

program="${OREN_BENCH_DEBUG_PROGRAM:-benchmarks/dot_product/dot_product.oren}"
compiler="${OREN_BENCH_DEBUG_COMPILER:-./oren_stage2}"
run_args_raw="${OREN_BENCH_DEBUG_ARGS:-10 3}"
platform_arg=()
if [[ -n "${OREN_BENCH_DEBUG_PLATFORM:-}" ]]; then
    platform_arg=(--platform "${OREN_BENCH_DEBUG_PLATFORM}")
fi

if [[ ! -f "$program" ]]; then
    echo "perf debug: missing benchmark source: $program" >&2
    exit 2
fi

program_base="$(basename "${program%.*}")"
build_log="$log_dir/perf-debug-native-benchmark-${program_base}-${ts}.build.log"
run_log="$log_dir/perf-debug-native-benchmark-${program_base}-${ts}.run.log"
summary_log="$log_dir/perf-debug-native-benchmark-${program_base}-${ts}.log"
out_bin="$tmp_dir/${program_base}_oren_native_debug"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
if [[ -n "$build_env_raw" ]]; then
    read -r -a build_env_parts <<<"$build_env_raw"
fi

read -r -a run_args <<<"$run_args_raw"

{
    echo "[build] compiler=$compiler"
    echo "[build] program=$program"
    echo "[build] output=$out_bin"
    echo "[build] args=${run_args[*]}"
    if [[ -n "$build_env_raw" ]]; then
        echo "[build_env] $build_env_raw"
    fi
} >"$build_log"

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "$compiler" build "$program" --backend native --no-debug --no-cache "${platform_arg[@]}" -o "$out_bin" >>"$build_log" 2>&1
else
    "$compiler" build "$program" --backend native --no-debug --no-cache "${platform_arg[@]}" -o "$out_bin" >>"$build_log" 2>&1
fi

{
    echo "[run] $out_bin ${run_args[*]}"
} >"$run_log"
set +e
"$out_bin" "${run_args[@]}" >>"$run_log" 2>&1
run_rc=$?
set -e

{
    echo "perf debug native benchmark summary"
    echo ""
    if [[ $run_rc -eq 0 ]]; then
        echo "status: ok"
    else
        echo "status: nonzero"
    fi
    echo "exit_code: $run_rc"
    echo "program: $program"
    echo "binary: $out_bin"
    echo "args: ${run_args[*]}"
    echo "build_log: $build_log"
    echo "run_log: $run_log"
    if [[ $run_rc -ne 0 ]]; then
        echo "manual_debug: lldb -- $out_bin ${run_args[*]}"
    fi
} >"$summary_log"

if [[ $run_rc -eq 0 ]]; then
    echo "native benchmark debug run complete; summary: $summary_log"
    exit 0
fi

echo "native benchmark debug run detected nonzero exit; summary: $summary_log" >&2
exit "$run_rc"
