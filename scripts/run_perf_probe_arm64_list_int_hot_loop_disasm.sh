#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-list-int-hot-loop-disasm-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-list-int-hot-loop-disasm-${ts}.log"
array_log="$tmp_dir/array_sum_int.build.log"
dot_log="$tmp_dir/dot_product_int.build.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

build_one() {
    local program="$1"
    local src="benchmarks/${program}/${program}.oren"
    local out="$tmp_dir/${program}_native"
    if [[ ${#build_env_parts[@]} -gt 0 ]]; then
        env OREN_TRACE_ARM64_LOOP_RANGES=1 "${build_env_parts[@]}" \
            ./oren_stage2 build "$src" --backend native --no-debug --no-cache --disasm -o "$out"
    else
        env OREN_TRACE_ARM64_LOOP_RANGES=1 \
            ./oren_stage2 build "$src" --backend native --no-debug --no-cache --disasm -o "$out"
    fi
}

build_one array_sum_int >"$array_log" 2>&1
build_one dot_product_int >"$dot_log" 2>&1

ARRAY_LOG="$array_log" DOT_LOG="$dot_log" python3 - <<'PY' >"$summary_log"
import os
import re
import sys

range_re = re.compile(r"\[arm64_loop_range\] kind=([^\s]+) start=(\d+) end=(\d+) bytes=(\d+)")
addr_re = re.compile(r"^([0-9a-fA-F]{16})\b")


def load_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def first_text_addr(lines):
    for line in lines:
        m = addr_re.match(line)
        if m:
            return int(m.group(1), 16)
    return None


def find_range(lines, prefix):
    matches = []
    for line in lines:
        m = range_re.search(line)
        if not m:
            continue
        kind = m.group(1)
        if kind == prefix or kind.startswith(prefix + "_"):
            matches.append((kind, int(m.group(2)), int(m.group(3)), int(m.group(4))))
    if not matches:
        return None
    return matches[-1]


def collect_snippet(lines, base_addr, start_off, end_off, pad_bytes=32):
    start_abs = base_addr + start_off
    end_abs = base_addr + end_off
    keep = []
    for line in lines:
        m = addr_re.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        if start_abs - pad_bytes <= addr < end_abs + pad_bytes:
            keep.append(line)
    return start_abs, end_abs, keep


def collect_range_mnemonics(lines, base_addr, start_off, end_off):
    start_abs = base_addr + start_off
    end_abs = base_addr + end_off
    counts = {}
    total = 0
    for line in lines:
        m = addr_re.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        if not (start_abs <= addr < end_abs):
            continue
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        mnemonic = parts[1]
        total += 1
        counts[mnemonic] = counts.get(mnemonic, 0) + 1
    return total, counts


def emit_block(label, path, prefix):
    lines = load_lines(path)
    base = first_text_addr(lines)
    print(label)
    print(f"  log: {path}")
    if base is None:
        print("  error: no disassembly addresses found")
        print("")
        return False
    found = find_range(lines, prefix)
    if found is None:
        print(f"  error: no arm64 loop range found for {prefix}")
        print("")
        return False
    kind, start_off, end_off, nbytes = found
    start_abs, end_abs, snippet = collect_snippet(lines, base, start_off, end_off)
    total_insns, counts = collect_range_mnemonics(lines, base, start_off, end_off)
    print(f"  kind: {kind}")
    print(f"  text_base: 0x{base:016x}")
    print(f"  range_off: {start_off}..{end_off} ({nbytes} bytes)")
    print(f"  range_abs: 0x{start_abs:016x}..0x{end_abs:016x}")
    print(f"  instruction_count: {total_insns}")
    interesting = ["ldr", "ldp", "str", "stp", "mul", "madd", "add", "cmp", "b", "bl"]
    parts = []
    for mnemonic in interesting:
        if mnemonic in counts:
            parts.append(f"{mnemonic}={counts[mnemonic]}")
    for mnemonic in sorted(counts):
        if mnemonic in interesting:
            continue
        parts.append(f"{mnemonic}={counts[mnemonic]}")
    if parts:
        print(f"  mnemonic_counts: {' '.join(parts)}")
    print("  snippet:")
    if not snippet:
        print("    <no instructions captured>")
    else:
        for line in snippet:
            print(f"    {line}")
    print("")
    return True


print("arm64 list<int> hot-loop disasm summary")
print("")
ok = True
ok = emit_block("array_sum_int", os.environ["ARRAY_LOG"], "fast_list_int_get_sum_while") and ok
ok = emit_block("dot_product_int", os.environ["DOT_LOG"], "fast_list_int_dot_while") and ok
if not ok:
    sys.exit(1)
PY

echo "arm64 list<int> hot-loop disasm probe complete; summary: $summary_log"
echo "array_sum_int build log: $array_log"
echo "dot_product_int build log: $dot_log"
