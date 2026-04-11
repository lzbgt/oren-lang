#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-native-hot-loop-disasm-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-native-hot-loop-disasm-${ts}.log"
array_log="$tmp_dir/array_sum.build.log"
dot_log="$tmp_dir/dot_product.build.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

build_one() {
    local program="$1"
    local src="benchmarks/${program}/${program}.oren"
    local out="$tmp_dir/${program}_native"
    # The summary depends on compile-time `[arm64_loop_range]` prints. Force a real rebuild so a
    # native cache hit cannot skip lowering and leave the script with only disassembly text.
    if [[ ${#build_env_parts[@]} -gt 0 ]]; then
        env OREN_TRACE_ARM64_LOOP_RANGES=1 "${build_env_parts[@]}" \
            ./oren_stage2 build "$src" --backend native --no-debug --no-cache --disasm -o "$out"
    else
        env OREN_TRACE_ARM64_LOOP_RANGES=1 \
            ./oren_stage2 build "$src" --backend native --no-debug --no-cache --disasm -o "$out"
    fi
}

build_one array_sum >"$array_log" 2>&1
build_one dot_product >"$dot_log" 2>&1

ARRAY_LOG="$array_log" DOT_LOG="$dot_log" python3 - <<'PY' >"$summary_log"
import os
import re
import sys

range_re = re.compile(r"\[arm64_loop_range\] kind=([^\s]+) start=(\d+) end=(\d+) bytes=(\d+)")
addr_re = re.compile(r"^([0-9a-fA-F]{16})\b")
branch_target_re = re.compile(r"\b0x([0-9a-fA-F]+)\b")

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

def collect_range_insns(lines, base_addr, start_off, end_off):
    start_abs = base_addr + start_off
    end_abs = base_addr + end_off
    insns = []
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
        target = None
        if len(parts) >= 3:
            tm = branch_target_re.search(parts[2])
            if tm:
                target = int(tm.group(1), 16)
        insns.append({"addr": addr, "mnemonic": mnemonic, "line": line, "target": target})
    return insns

def count_mnemonics(insns):
    counts = {}
    for insn in insns:
        mnemonic = insn["mnemonic"]
        counts[mnemonic] = counts.get(mnemonic, 0) + 1
    return len(insns), counts

def format_counts(counts, interesting):
    parts = []
    for mnemonic in interesting:
        if mnemonic in counts:
            parts.append(f"{mnemonic}={counts[mnemonic]}")
    for mnemonic in sorted(counts):
        if mnemonic in interesting:
            continue
        parts.append(f"{mnemonic}={counts[mnemonic]}")
    return " ".join(parts)

def collect_cold_gc_tick_blocks(insns):
    cold_addrs = set()
    blocks = []
    for insn in insns:
        if insn["mnemonic"] != "b.ne" or insn["target"] is None or insn["target"] <= insn["addr"]:
            continue
        skipped = [cand for cand in insns if insn["addr"] < cand["addr"] < insn["target"]]
        if not any(cand["mnemonic"] == "bl" for cand in skipped):
            continue
        blocks.append((insn["addr"], insn["target"], skipped))
        for cand in skipped:
            cold_addrs.add(cand["addr"])
    cold_insns = [insn for insn in insns if insn["addr"] in cold_addrs]
    return blocks, cold_insns

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
    insns = collect_range_insns(lines, base, start_off, end_off)
    total_insns, counts = count_mnemonics(insns)
    cold_blocks, cold_insns = collect_cold_gc_tick_blocks(insns)
    cold_addrs = {insn["addr"] for insn in cold_insns}
    range_without_cold_insns = [insn for insn in insns if insn["addr"] not in cold_addrs]
    range_without_cold_count, range_without_cold_counts = count_mnemonics(range_without_cold_insns)
    cold_insn_count, cold_counts = count_mnemonics(cold_insns)
    print(f"  kind: {kind}")
    print(f"  text_base: 0x{base:016x}")
    print(f"  range_off: {start_off}..{end_off} ({nbytes} bytes)")
    print(f"  range_abs: 0x{start_abs:016x}..0x{end_abs:016x}")
    print(f"  instruction_count: {total_insns}")
    print(f"  range_without_cold_gc_tick_instruction_count: {range_without_cold_count}")
    print(f"  cold_gc_tick_blocks: {len(cold_blocks)}")
    print(f"  cold_gc_tick_instruction_count: {cold_insn_count}")
    interesting = ["ldr", "ldp", "str", "stp", "mul", "add", "cmp", "b", "bl"]
    formatted_counts = format_counts(counts, interesting)
    if formatted_counts:
        print(f"  mnemonic_counts: {formatted_counts}")
    formatted_range_without_cold_counts = format_counts(range_without_cold_counts, interesting)
    if formatted_range_without_cold_counts:
        print(f"  range_without_cold_gc_tick_counts: {formatted_range_without_cold_counts}")
    formatted_cold_counts = format_counts(cold_counts, interesting)
    if formatted_cold_counts:
        print(f"  cold_gc_tick_counts: {formatted_cold_counts}")
    if cold_blocks:
        ranges = " ".join(f"0x{start:016x}->0x{target:016x}" for start, target, _ in cold_blocks)
        print(f"  cold_gc_tick_ranges: {ranges}")
    print("  snippet:")
    if not snippet:
        print("    <no instructions captured>")
    else:
        for line in snippet:
            print(f"    {line}")
    print("")
    return True

print("arm64 native hot-loop disasm summary")
print("")
ok = True
ok = emit_block("array_sum", os.environ["ARRAY_LOG"], "fast_list_int_get_sum_while") and ok
ok = emit_block("dot_product", os.environ["DOT_LOG"], "fast_list_int_dot_while") and ok
if not ok:
    sys.exit(1)
PY

echo "arm64 native hot-loop disasm probe complete; summary: $summary_log"
echo "array_sum build log: $array_log"
echo "dot_product build log: $dot_log"
