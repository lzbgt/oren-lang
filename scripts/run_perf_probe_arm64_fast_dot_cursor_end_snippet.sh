#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-snippet-${ts}.log"
default_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-snippet-default-${ts}.run.log"
enabled_log="$log_dir/perf-probe-arm64-fast-dot-cursor-end-snippet-enabled-${ts}.run.log"

enable_env="OREN_ARM64_FAST_LIST_INT_DOT_CURSOR_END_BOUNDS=1"

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

run_capture "$default_log" env \
    OREN_BENCH_ENV_BUILD_OREN= \
    make perf-probe-arm64-native-hot-loop-disasm

run_capture "$enabled_log" env \
    OREN_BENCH_ENV_BUILD_OREN="$enable_env" \
    make perf-probe-arm64-native-hot-loop-disasm

DEFAULT_WRAPPER_LOG="$default_log" \
ENABLED_WRAPPER_LOG="$enabled_log" \
ENABLE_ENV="$enable_env" \
python3 - <<'PY' >"$summary_log"
import os
import re
import sys
from pathlib import Path

summary_re = re.compile(r"summary: (build/logs/perf-probe-arm64-native-hot-loop-disasm-[^ ]+\.log)")


def read_lines(path):
    return Path(path).read_text(encoding="utf-8").splitlines()


def parse_summary_path(wrapper_path):
    summary_path = None
    for line in read_lines(wrapper_path):
        match = summary_re.search(line)
        if match:
            summary_path = match.group(1)
    if summary_path is None:
        raise SystemExit(f"missing hot-loop disasm summary in {wrapper_path}")
    return summary_path


def parse_dot_case(summary_path):
    lines = read_lines(summary_path)
    try:
        start = lines.index("dot_product")
    except ValueError:
        raise SystemExit(f"missing dot_product block in {summary_path}")
    lines = lines[start + 1 :]
    fields = {}
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
            fields[key] = value
            continue
        if line == "":
            continue
        break
    fields["snippet"] = snippet
    return fields


def find_first(snippet, patterns, start=0):
    for idx in range(start, len(snippet)):
        for pat in patterns:
            if pat in snippet[idx]:
                return idx
    return None


def find_next_unconditional_branch(snippet, start):
    for idx in range(start, len(snippet)):
        if "\tb\t" in snippet[idx]:
            return idx
    return None


def slice_block(snippet, start, end_exclusive):
    if start is None or end_exclusive is None or start >= end_exclusive:
        return None
    return snippet[start:end_exclusive]


def block_from_branches(snippet, start):
    if start is None:
        return None
    end = find_next_unconditional_branch(snippet, start)
    if end is None:
        return None
    return snippet[start : end + 1]


def extract_blocks(snippet):
    control_start = find_first(snippet, ["\tcmp\tx20, x21", "\tcmp\tx19, x20"])
    if control_start is None:
        raise SystemExit("missing loop control start in dot_product snippet")
    setup_start = find_first(snippet, ["\tldr\tx20, [sp]", "\tldr\tx19, [sp, #0x20]"])
    setup_block = slice_block(snippet, setup_start, control_start)

    first_tick = find_first(snippet, ["\tadd\tx9, x9, #0x1"], start=control_start)
    control_block = slice_block(snippet, control_start, first_tick)

    quad_start = find_first(snippet, ["\tldr\tx24, [x19]"], start=first_tick or 0)
    quad_block = block_from_branches(snippet, quad_start)

    quad_end = (quad_start + len(quad_block)) if quad_block is not None else 0
    double_start = find_first(snippet, ["\tldr\tx25, [x19]"], start=quad_end)
    double_block = block_from_branches(snippet, double_start)

    double_end = (double_start + len(double_block)) if double_block is not None else 0
    second_tick = find_first(snippet, ["\tadd\tx9, x9, #0x1"], start=double_end)
    single_start = find_first(snippet, ["\tldr\tx25, [x19]"], start=(second_tick or 0))
    single_block = block_from_branches(snippet, single_start)

    single_end = (single_start + len(single_block)) if single_block is not None else 0
    exit_start = find_first(
        snippet,
        ["\tldr\tx20, [sp, #0x8]", "\tstur\tx20, [x29, #-0xa0]"],
        start=single_end,
    )
    exit_tail = block_from_branches(snippet, exit_start)
    return {
        "setup_block": setup_block,
        "control_block": control_block,
        "quad_block": quad_block,
        "double_block": double_block,
        "single_block": single_block,
        "exit_tail": exit_tail,
    }


def emit_block(name, block):
    print(f"  {name}:")
    if not block:
        print("    unavailable")
        return
    for line in block:
        print(f"    {line}")


def emit_case(label, build_env, data):
    blocks = extract_blocks(data["snippet"])
    print(f"{label}: {data['summary_path']}")
    print(f"  build_env: {build_env}")
    for key in ["range_off", "range_abs", "instruction_count", "mnemonic_counts"]:
        if key in data:
            print(f"  {key}: {data[key]}")
    emit_block("setup_block", blocks["setup_block"])
    emit_block("control_block", blocks["control_block"])
    emit_block("quad_block", blocks["quad_block"])
    emit_block("double_block", blocks["double_block"])
    emit_block("single_block", blocks["single_block"])
    emit_block("exit_tail", blocks["exit_tail"])
    print("")


def load_case(wrapper_path):
    summary_path = parse_summary_path(wrapper_path)
    data = parse_dot_case(summary_path)
    data["summary_path"] = summary_path
    return data


default = load_case(os.environ["DEFAULT_WRAPPER_LOG"])
enabled = load_case(os.environ["ENABLED_WRAPPER_LOG"])

print("arm64 fast-dot cursor-end snippet")
print("")
emit_case("default", "<none>", default)
emit_case("enabled", os.environ["ENABLE_ENV"], enabled)
PY

echo "arm64 fast-dot cursor-end snippet complete; summary: $summary_log"
echo "default wrapper log: $default_log"
echo "enabled wrapper log: $enabled_log"
