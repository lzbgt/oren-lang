#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-dot-vs-c-loop-compare-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-dot-vs-c-loop-compare-${ts}.log"
oren_wrapper_log="$log_dir/perf-probe-arm64-dot-vs-c-loop-compare-oren-${ts}.run.log"
c_asm_log="$tmp_dir/dot_product_c_arm64.s"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
if [[ -n "$build_env_raw" ]]; then
    old_ifs="$IFS"
    IFS=','
    read -r -a build_env_parts <<<"$build_env_raw"
    IFS="$old_ifs"
fi

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    run_capture "$oren_wrapper_log" env "${build_env_parts[@]}" make perf-probe-arm64-native-hot-loop-disasm
else
    run_capture "$oren_wrapper_log" make perf-probe-arm64-native-hot-loop-disasm
fi
cc -O2 -S -o "$c_asm_log" benchmarks/dot_product/dot_product.c

OREN_WRAPPER_LOG="$oren_wrapper_log" \
C_ASM_LOG="$c_asm_log" \
BUILD_ENV="$build_env_raw" \
python3 - <<'PY' >"$summary_log"
import os
import re
from pathlib import Path

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-native-hot-loop-disasm-[^ ]+\.log)")
program_header_re = re.compile(r"^[A-Za-z0-9_]+$")


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
    lines = read_lines(summary_path)
    try:
        start = lines.index("dot_product")
    except ValueError:
        raise SystemExit(f"missing dot_product block in {summary_path}")
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


def extract_c_loop(c_lines, label):
    start = None
    for idx, line in enumerate(c_lines):
        if line.strip().startswith(label + ":"):
            start = idx
            break
    if start is None:
        return None
    block = []
    for idx in range(start, len(c_lines)):
        line = c_lines[idx]
        if idx != start and line and not line.startswith(("\t", " ", ";")) and line.endswith(":"):
            break
        if idx == start or "\t" in line:
            block.append(line)
    return block


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


oren = parse_oren_dot_case(parse_oren_summary_path(os.environ["OREN_WRAPPER_LOG"]))
c_lines = read_lines(os.environ["C_ASM_LOG"])
c_vec = extract_c_loop(c_lines, "LBB0_30")
c_mid = extract_c_loop(c_lines, "LBB0_34")
c_tail = extract_c_loop(c_lines, "LBB0_37")
if c_vec is None or c_tail is None:
    raise SystemExit("failed to extract C dot_product loop blocks")

vec_total, vec_counts = count_mnemonics(c_vec)
mid_total, mid_counts = count_mnemonics(c_mid or [])
tail_total, tail_counts = count_mnemonics(c_tail)

print("arm64 dot_product Oren-vs-C loop compare")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"oren_summary: {oren['summary_path']}")
for key in ["range_off", "range_abs", "instruction_count", "mnemonic_counts"]:
    if key in oren:
        print(f"oren_{key}: {oren[key]}")
print("")
print(f"c_asm: {os.environ['C_ASM_LOG']}")
print(f"c_vector_loop_label: LBB0_30")
print(f"c_vector_loop_insns: {vec_total}")
print(f"c_vector_loop_counts: {format_counts(vec_counts, ['ldp', 'smlal2.2d', 'smlal.2d', 'subs', 'b.ne', 'add.2d', 'addp.2d', 'fmov'])}")
if c_mid:
    print(f"c_mid_loop_label: LBB0_34")
    print(f"c_mid_loop_insns: {mid_total}")
    print(f"c_mid_loop_counts: {format_counts(mid_counts, ['ldr', 'smlal2.2d', 'smlal.2d', 'adds', 'b.ne'])}")
print(f"c_tail_loop_label: LBB0_37")
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
print("oren_dot_snippet:")
for line in oren["snippet"]:
    print(f"  {line}")
PY

echo "arm64 dot vs C loop compare complete; summary: $summary_log"
echo "oren wrapper log: $oren_wrapper_log"
echo "c asm log: $c_asm_log"
