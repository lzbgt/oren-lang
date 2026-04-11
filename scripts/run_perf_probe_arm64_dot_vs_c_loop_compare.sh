#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tag="${OREN_ARM64_DOT_VS_C_TAG:-perf-probe-arm64-dot-vs-c-loop-compare}"
title="${OREN_ARM64_DOT_VS_C_TITLE:-arm64 dot_product Oren-vs-C loop compare}"
target_program="${OREN_ARM64_DOT_VS_C_PROGRAM:-dot_product}"
c_source="${OREN_ARM64_DOT_VS_C_C_SOURCE:-benchmarks/dot_product/dot_product.c}"
oren_probe_target="${OREN_ARM64_DOT_VS_C_OREN_PROBE_TARGET:-perf-probe-arm64-native-hot-loop-disasm}"
oren_summary_prefix="${OREN_ARM64_DOT_VS_C_OREN_SUMMARY_PREFIX:-perf-probe-arm64-native-hot-loop-disasm-}"
tmp_dir="build/tmp/${tag}-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/${tag}-${ts}.log"
oren_wrapper_log="$log_dir/${tag}-oren-${ts}.run.log"
c_asm_log="$tmp_dir/${target_program}_c_arm64.s"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    run_capture "$oren_wrapper_log" env "${build_env_parts[@]}" make "$oren_probe_target"
else
    run_capture "$oren_wrapper_log" make "$oren_probe_target"
fi
cc -O2 -S -o "$c_asm_log" "$c_source"

OREN_WRAPPER_LOG="$oren_wrapper_log" \
C_ASM_LOG="$c_asm_log" \
BUILD_ENV="$build_env_raw" \
TITLE="$title" \
TARGET_PROGRAM="$target_program" \
C_SOURCE="$c_source" \
OREN_SUMMARY_PREFIX="$oren_summary_prefix" \
python3 - <<'PY' >"$summary_log"
import os
import re
from pathlib import Path

summary_re = re.compile(r"summary: (build/logs/" + re.escape(os.environ["OREN_SUMMARY_PREFIX"]) + r"[^ ]+\.log)")
label_re = re.compile(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):")


def read_lines(path):
    return Path(path).read_text(encoding="utf-8").splitlines()


def parse_oren_summary_path(wrapper_path):
    summary_path = None
    for line in read_lines(wrapper_path):
        m = summary_re.search(line)
        if m:
            summary_path = m.group(1)
    if summary_path is None:
        raise SystemExit(f"missing Oren hot-loop disasm summary in {wrapper_path}")
    return summary_path


def parse_oren_dot_case(summary_path):
    target = os.environ["TARGET_PROGRAM"]
    lines = read_lines(summary_path)
    try:
        start = lines.index(target)
    except ValueError:
        raise SystemExit(f"missing {target} block in {summary_path}")
    lines = lines[start + 1 :]
    data = {"summary_path": summary_path}
    snippet = []
    in_snippet = False
    for line in lines:
        if in_snippet:
            if line.startswith("    "):
                snippet.append(line[4:])
                continue
            break
        if line == "  snippet:":
            in_snippet = True
            continue
        if line.startswith("  ") and ": " in line:
            key, value = line.strip().split(": ", 1)
            data[key] = value
            continue
        if line == "":
            continue
        break
    data["snippet"] = snippet
    return data


def collect_c_label_blocks(c_lines):
    blocks = []
    idx = 0
    while idx < len(c_lines):
        line = c_lines[idx]
        m = label_re.match(line)
        if not m:
            idx += 1
            continue
        label = m.group(1)
        block = [line]
        idx += 1
        while idx < len(c_lines):
            next_line = c_lines[idx]
            if label_re.match(next_line):
                break
            if "\t" in next_line or next_line.strip().startswith(";"):
                block.append(next_line)
            idx += 1
        blocks.append((label, block))
    return blocks


def count_mnemonics(lines):
    counts = {}
    total = 0
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        parts = stripped.split(None, 1)
        if not parts:
            continue
        if parts[0].endswith(":"):
            continue
        mnemonic = parts[0]
        counts[mnemonic] = counts.get(mnemonic, 0) + 1
        total += 1
    return total, counts


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


def find_c_loop_blocks(c_lines):
    vector_candidates = []
    tail_candidates = []
    for label, block in collect_c_label_blocks(c_lines):
        total, counts = count_mnemonics(block)
        vector_score = counts.get("smlal2.2d", 0) + counts.get("smlal.2d", 0)
        tail_score = counts.get("smaddl", 0)
        if vector_score > 0:
            vector_candidates.append((vector_score, total, label, block))
        if tail_score > 0:
            tail_candidates.append((tail_score, total, label, block))
    if not vector_candidates or not tail_candidates:
        raise SystemExit(f"failed to extract C {os.environ['TARGET_PROGRAM']} loop blocks")

    vector_candidates.sort(key=lambda item: (-item[0], -item[1], item[2]))
    tail_candidates.sort(key=lambda item: (-item[0], -item[1], item[2]))
    vec_label, vec_block = vector_candidates[0][2], vector_candidates[0][3]
    mid_label = None
    mid_block = None
    if len(vector_candidates) > 1:
        mid_label, mid_block = vector_candidates[1][2], vector_candidates[1][3]
    tail_label, tail_block = tail_candidates[0][2], tail_candidates[0][3]
    return (vec_label, vec_block), (mid_label, mid_block), (tail_label, tail_block)


oren = parse_oren_dot_case(parse_oren_summary_path(os.environ["OREN_WRAPPER_LOG"]))
c_lines = read_lines(os.environ["C_ASM_LOG"])
(vec_label, c_vec), (mid_label, c_mid), (tail_label, c_tail) = find_c_loop_blocks(c_lines)

vec_total, vec_counts = count_mnemonics(c_vec)
mid_total, mid_counts = count_mnemonics(c_mid or [])
tail_total, tail_counts = count_mnemonics(c_tail)

print(os.environ["TITLE"])
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"target_program: {os.environ['TARGET_PROGRAM']}")
print(f"oren_summary: {oren['summary_path']}")
for key in [
    "range_off",
    "range_abs",
    "instruction_count",
    "range_without_cold_gc_tick_instruction_count",
    "cold_gc_tick_blocks",
    "cold_gc_tick_instruction_count",
    "mnemonic_counts",
    "range_without_cold_gc_tick_counts",
    "cold_gc_tick_counts",
    "cold_gc_tick_ranges",
]:
    if key in oren:
        print(f"oren_{key}: {oren[key]}")
print("")
print(f"c_source: {os.environ['C_SOURCE']}")
print(f"c_asm: {os.environ['C_ASM_LOG']}")
print(f"c_vector_loop_label: {vec_label}")
print(f"c_vector_loop_insns: {vec_total}")
print(f"c_vector_loop_counts: {format_counts(vec_counts, ['ldp', 'smlal2.2d', 'smlal.2d', 'subs', 'b.ne', 'add.2d', 'addp.2d', 'fmov'])}")
if c_mid:
    print(f"c_mid_loop_label: {mid_label}")
    print(f"c_mid_loop_insns: {mid_total}")
    print(f"c_mid_loop_counts: {format_counts(mid_counts, ['ldr', 'smlal2.2d', 'smlal.2d', 'adds', 'b.ne'])}")
print(f"c_tail_loop_label: {tail_label}")
print(f"c_tail_loop_insns: {tail_total}")
print(f"c_tail_loop_counts: {format_counts(tail_counts, ['ldrsw', 'smaddl', 'subs', 'b.ne'])}")
print("")
print("c_vector_loop:")
for line in c_vec:
    print(f"  {line}")
print("")
if c_mid:
    print("c_mid_loop:")
    for line in c_mid:
        print(f"  {line}")
    print("")
print("c_tail_loop:")
for line in c_tail:
    print(f"  {line}")
print("")
print(f"oren_{os.environ['TARGET_PROGRAM']}_snippet:")
for line in oren["snippet"]:
    print(f"  {line}")
PY

echo "${title} complete; summary: $summary_log"
echo "oren wrapper log: $oren_wrapper_log"
echo "c asm log: $c_asm_log"
