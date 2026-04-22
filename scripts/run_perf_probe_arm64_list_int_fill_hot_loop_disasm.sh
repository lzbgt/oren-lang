#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-list-int-fill-hot-loop-disasm-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-list-int-fill-hot-loop-disasm-${ts}.log"
fill_log="$tmp_dir/fill_list_int.build.log"
array_log="$tmp_dir/array_sum_int.build.log"
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

build_one fill_list_int >"$fill_log" 2>&1
build_one array_sum_int >"$array_log" 2>&1

FILL_LOG="$fill_log" ARRAY_LOG="$array_log" python3 - <<'PY' >"$summary_log"
import os
import re
import sys

range_re = re.compile(r"\[arm64_loop_range\] kind=([^\s]+) start=(\d+) end=(\d+) bytes=(\d+)")
addr_re = re.compile(r"^([0-9a-fA-F]{16})\b")
branch_target_re = re.compile(r"\b0x([0-9a-fA-F]+)\b")
tick_step_re = re.compile(r"\bsubs\s+x9,\s*x9,\s*#(?:0x)?([0-9a-fA-F]+)\b")


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


def category_counts(insns):
    categories = {
        "loads": 0,
        "stores": 0,
        "arith": 0,
        "moves": 0,
        "compare_tick": 0,
        "branches": 0,
        "calls": 0,
        "other": 0,
    }
    for insn in insns:
        mnemonic = insn["mnemonic"]
        if mnemonic in {"ldr", "ldp", "ldur"}:
            categories["loads"] += 1
        elif mnemonic in {"str", "stp", "stur"}:
            categories["stores"] += 1
        elif mnemonic in {"add", "sub", "mul", "madd", "msub", "udiv", "umulh", "lsr", "csel"}:
            categories["arith"] += 1
        elif mnemonic == "mov":
            categories["moves"] += 1
        elif mnemonic in {"cmp", "subs"}:
            categories["compare_tick"] += 1
        elif mnemonic == "bl":
            categories["calls"] += 1
        elif mnemonic == "b" or mnemonic.startswith("b."):
            categories["branches"] += 1
        else:
            categories["other"] += 1
    return categories


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


def format_category_counts(counts):
    order = ["loads", "stores", "arith", "moves", "compare_tick", "branches", "calls", "other"]
    return " ".join(f"{key}={counts[key]}" for key in order if counts.get(key))


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


def find_main_iter_insns(hot_insns, start_abs, end_abs):
    main_step = 1
    for insn in hot_insns:
        m = tick_step_re.search(insn["line"])
        if not m:
            continue
        step = int(m.group(1), 16)
        if step > main_step:
            main_step = step
    if main_step <= 1:
        return hot_insns, 1

    scalar_target = None
    for insn in hot_insns:
        target = insn["target"]
        if target is None:
            continue
        if not (insn["addr"] < target < end_abs):
            continue
        if not insn["mnemonic"].startswith("b."):
            continue
        scalar_target = target
        break

    if scalar_target is None:
        return hot_insns, main_step

    main_iter_insns = [insn for insn in hot_insns if start_abs <= insn["addr"] < scalar_target]
    if not main_iter_insns:
        return hot_insns, main_step

    return main_iter_insns, main_step


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
    hot_insns = [insn for insn in insns if insn["addr"] not in cold_addrs]
    hot_count, hot_counts = count_mnemonics(hot_insns)
    cold_count, cold_counts = count_mnemonics(cold_insns)
    main_iter_insns, main_iter_elems = find_main_iter_insns(hot_insns, start_abs, end_abs)
    main_iter_hot, main_iter_counts = count_mnemonics(main_iter_insns)
    main_iter_per_elem = float(main_iter_hot) / float(main_iter_elems)
    hot_category_counts = category_counts(hot_insns)
    main_iter_category_counts = category_counts(main_iter_insns)
    cold_category_counts = category_counts(cold_insns)
    print(f"  kind: {kind}")
    print(f"  text_base: 0x{base:016x}")
    print(f"  range_off: {start_off}..{end_off} ({nbytes} bytes)")
    print(f"  range_abs: 0x{start_abs:016x}..0x{end_abs:016x}")
    print(f"  instruction_count: {total_insns}")
    print(f"  hot_instruction_count: {hot_count}")
    print(f"  main_iter_output_elements: {main_iter_elems}")
    print(f"  main_iter_hot_instruction_count: {main_iter_hot}")
    print(f"  main_iter_hot_instructions_per_output_elem: {main_iter_per_elem:.2f}")
    print(f"  cold_gc_tick_blocks: {len(cold_blocks)}")
    print(f"  cold_gc_tick_instruction_count: {cold_count}")
    interesting = ["ldr", "ldp", "str", "stp", "mul", "madd", "msub", "udiv", "add", "subs", "cmp", "b", "bl"]
    formatted_counts = format_counts(counts, interesting)
    if formatted_counts:
        print(f"  mnemonic_counts: {formatted_counts}")
    formatted_hot_counts = format_counts(hot_counts, interesting)
    if formatted_hot_counts:
        print(f"  hot_counts: {formatted_hot_counts}")
    formatted_main_iter_counts = format_counts(main_iter_counts, interesting)
    if formatted_main_iter_counts:
        print(f"  main_iter_counts: {formatted_main_iter_counts}")
    formatted_cold_counts = format_counts(cold_counts, interesting)
    if formatted_cold_counts:
        print(f"  cold_gc_tick_counts: {formatted_cold_counts}")
    formatted_hot_category_counts = format_category_counts(hot_category_counts)
    if formatted_hot_category_counts:
        print(f"  hot_category_counts: {formatted_hot_category_counts}")
    formatted_main_iter_category_counts = format_category_counts(main_iter_category_counts)
    if formatted_main_iter_category_counts:
        print(f"  main_iter_category_counts: {formatted_main_iter_category_counts}")
    formatted_cold_category_counts = format_category_counts(cold_category_counts)
    if formatted_cold_category_counts:
        print(f"  cold_gc_tick_category_counts: {formatted_cold_category_counts}")
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


print("arm64 list<int> fill hot-loop disasm summary")
print("")
ok = True
ok = emit_block("fill_list_int", os.environ["FILL_LOG"], "fast_list_int_push_while") and ok
ok = emit_block("array_sum_int", os.environ["ARRAY_LOG"], "fast_list_int_push_while") and ok
if not ok:
    sys.exit(1)
PY

echo "arm64 list<int> fill hot-loop disasm probe complete; summary: $summary_log"
echo "fill_list_int build log: $fill_log"
echo "array_sum_int build log: $array_log"
