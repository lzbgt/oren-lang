#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-native-hot-loop-disasm-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-native-hot-loop-disasm-${ts}.log"
array_log="$tmp_dir/array_sum.build.log"
dot_log="$tmp_dir/dot_product.build.log"

build_one() {
    local program="$1"
    local src="benchmarks/${program}/${program}.oren"
    local out="$tmp_dir/${program}_native"
    env OREN_TRACE_ARM64_LOOP_RANGES=1 \
        ./oren_stage2 build "$src" --backend native --no-debug --disasm -o "$out"
}

build_one array_sum >"$array_log" 2>&1
build_one dot_product >"$dot_log" 2>&1

ARRAY_LOG="$array_log" DOT_LOG="$dot_log" python3 - <<'PY' >"$summary_log"
import os
import re

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

def emit_block(label, path, prefix):
    lines = load_lines(path)
    base = first_text_addr(lines)
    print(label)
    print(f"  log: {path}")
    if base is None:
        print("  error: no disassembly addresses found")
        print("")
        return
    found = find_range(lines, prefix)
    if found is None:
        print(f"  error: no arm64 loop range found for {prefix}")
        print("")
        return
    kind, start_off, end_off, nbytes = found
    start_abs, end_abs, snippet = collect_snippet(lines, base, start_off, end_off)
    print(f"  kind: {kind}")
    print(f"  text_base: 0x{base:016x}")
    print(f"  range_off: {start_off}..{end_off} ({nbytes} bytes)")
    print(f"  range_abs: 0x{start_abs:016x}..0x{end_abs:016x}")
    print("  snippet:")
    if not snippet:
        print("    <no instructions captured>")
    else:
        for line in snippet:
            print(f"    {line}")
    print("")

print("arm64 native hot-loop disasm summary")
print("")
emit_block("array_sum", os.environ["ARRAY_LOG"], "fast_list_int_get_sum_while")
emit_block("dot_product", os.environ["DOT_LOG"], "fast_list_int_dot_while")
PY

echo "arm64 native hot-loop disasm probe complete; summary: $summary_log"
echo "array_sum build log: $array_log"
echo "dot_product build log: $dot_log"
