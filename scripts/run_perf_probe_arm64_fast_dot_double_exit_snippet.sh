#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp"
mkdir -p "$log_dir" "$tmp_dir"

baseline_disasm_log="$log_dir/perf-probe-arm64-fast-dot-double-exit-snippet-baseline-${ts}.disasm.log"
double_disasm_log="$log_dir/perf-probe-arm64-fast-dot-double-exit-snippet-double-${ts}.disasm.log"
summary_log="$log_dir/perf-probe-arm64-fast-dot-double-exit-snippet-${ts}.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
if [[ -n "$build_env_raw" ]]; then
    old_ifs="$IFS"
    IFS=','
    read -r -a build_env_parts <<<"$build_env_raw"
    IFS="$old_ifs"
fi

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env OREN_TRACE_ARM64_LOOP_RANGES=1 "${build_env_parts[@]}" \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
        --backend native --no-debug --no-cache --disasm \
        -o "$tmp_dir/perf_probe_arm64_fast_dot_double_exit_snippet_baseline_${ts}" \
        >"$baseline_disasm_log" 2>&1
else
    env OREN_TRACE_ARM64_LOOP_RANGES=1 \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
        --backend native --no-debug --no-cache --disasm \
        -o "$tmp_dir/perf_probe_arm64_fast_dot_double_exit_snippet_baseline_${ts}" \
        >"$baseline_disasm_log" 2>&1
fi

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env OREN_TRACE_ARM64_LOOP_RANGES=1 "${build_env_parts[@]}" \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1 \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
        --backend native --no-debug --no-cache --disasm \
        -o "$tmp_dir/perf_probe_arm64_fast_dot_double_exit_snippet_double_${ts}" \
        >"$double_disasm_log" 2>&1
else
    env OREN_TRACE_ARM64_LOOP_RANGES=1 \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1 \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
        --backend native --no-debug --no-cache --disasm \
        -o "$tmp_dir/perf_probe_arm64_fast_dot_double_exit_snippet_double_${ts}" \
        >"$double_disasm_log" 2>&1
fi

BASELINE_DISASM_LOG="$baseline_disasm_log" \
DOUBLE_DISASM_LOG="$double_disasm_log" \
BUILD_ENV="$build_env_raw" \
python3 - <<'PY' >"$summary_log"
import os
from pathlib import Path


def extract_range_line(lines):
    for line in lines:
        if "[arm64_loop_range] kind=fast_list_int_dot_while_no_tick" in line:
            return line
    return None


def extract_double_block(lines):
    start = None
    end = None
    for i in range(len(lines) - 2):
        if "ldr\tx25, [x19]" in lines[i] and "ldr\tx28, [x19, #0x8]" in lines[i + 1]:
            start = i
            break
    if start is None:
        return None
    for j in range(start, min(len(lines), start + 24)):
        if "\tadd\tx20, x20, #0x2" in lines[j]:
            for k in range(j + 1, min(len(lines), j + 4)):
                if "\tb\t" in lines[k]:
                    end = k
                    break
            break
    if end is None:
        return None
    return lines[start:end + 1]


def emit_case(label, path):
    lines = Path(path).read_text().splitlines()
    print(f"{label}:")
    print(f"  disasm_log: {path}")
    range_line = extract_range_line(lines)
    if range_line is not None:
        print(f"  loop_range: {range_line}")
    block = extract_double_block(lines)
    if block is None:
        print("  double_block: unavailable")
        print("")
        return
    print("  double_block:")
    for line in block:
        print(f"    {line}")
    print("")


print("arm64 fast-dot double-exit snippet")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
    print("")
emit_case("baseline", os.environ["BASELINE_DISASM_LOG"])
emit_case("exact_double", os.environ["DOUBLE_DISASM_LOG"])
PY

echo "arm64 fast-dot double-exit snippet complete; summary: $summary_log"
echo "baseline disasm log: $baseline_disasm_log"
echo "double disasm log: $double_disasm_log"
