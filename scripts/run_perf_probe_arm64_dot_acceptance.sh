#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

programs="${OREN_ARM64_DOT_ACCEPT_PROGRAMS:-array_sum,dot_product}"
debug_program="${OREN_BENCH_DEBUG_PROGRAM:-benchmarks/dot_product/dot_product.oren}"
debug_args="${OREN_BENCH_DEBUG_ARGS:-10 3}"
run_test="${OREN_ARM64_DOT_ACCEPT_RUN_TEST:-1}"

smoke_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.smoke.log"
disasm_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.disasm.log"
steady_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.steady.log"
gate_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.gate.log"
debug_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.debug.log"
test_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.test.log"
summary_log="$log_dir/perf-probe-arm64-dot-acceptance-${ts}.summary.log"

make perf-smoke-native-fast-loops >"$smoke_log" 2>&1
make perf-probe-arm64-native-hot-loop-disasm >"$disasm_log" 2>&1
env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 OREN_BENCH_PROGRAMS="$programs" \
    make perf-gate-native-steady >"$steady_log" 2>&1
env OREN_BENCH_PROGRAMS="$programs" make perf-gate-native >"$gate_log" 2>&1
env OREN_BENCH_DEBUG_PROGRAM="$debug_program" OREN_BENCH_DEBUG_ARGS="$debug_args" \
    make perf-debug-native-benchmark >"$debug_log" 2>&1

if [[ "$run_test" == "1" ]]; then
    make test >"$test_log" 2>&1
else
    : >"$test_log"
fi

SMOKE_LOG="$smoke_log" \
DISASM_WRAPPER_LOG="$disasm_log" \
STEADY_WRAPPER_LOG="$steady_log" \
GATE_WRAPPER_LOG="$gate_log" \
DEBUG_WRAPPER_LOG="$debug_log" \
TEST_WRAPPER_LOG="$test_log" \
PROGRAMS="$programs" \
RUN_TEST="$run_test" \
python3 - <<'PY' >"$summary_log"
import os
import re
import sys


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def last_capture(lines, pattern):
    rgx = re.compile(pattern)
    hit = None
    for line in lines:
        m = rgx.search(line)
        if m:
            hit = m.group(1)
    return hit


def emit_file(label, path):
    print(f"{label}: {path}")


smoke_wrapper = os.environ["SMOKE_LOG"]
disasm_wrapper = os.environ["DISASM_WRAPPER_LOG"]
steady_wrapper = os.environ["STEADY_WRAPPER_LOG"]
gate_wrapper = os.environ["GATE_WRAPPER_LOG"]
debug_wrapper = os.environ["DEBUG_WRAPPER_LOG"]
test_wrapper = os.environ["TEST_WRAPPER_LOG"]
programs = os.environ["PROGRAMS"]
run_test = os.environ["RUN_TEST"]

smoke_lines = read_lines(smoke_wrapper)
disasm_wrapper_lines = read_lines(disasm_wrapper)
steady_wrapper_lines = read_lines(steady_wrapper)
gate_wrapper_lines = read_lines(gate_wrapper)
debug_wrapper_lines = read_lines(debug_wrapper)

smoke_summary = last_capture(smoke_lines, r"native fast-loop perf smoke complete; log: (.+)")
disasm_summary = last_capture(disasm_wrapper_lines, r"summary: (.+)")
steady_summary = last_capture(steady_wrapper_lines, r"summary: (.+)")
gate_summary = last_capture(gate_wrapper_lines, r"summary: (.+)")
debug_summary = last_capture(debug_wrapper_lines, r"summary: (.+)")

if smoke_summary is None:
    raise SystemExit("acceptance: failed to locate smoke summary path")
if disasm_summary is None:
    raise SystemExit("acceptance: failed to locate disasm summary path")
if steady_summary is None:
    raise SystemExit("acceptance: failed to locate steady summary path")
if gate_summary is None:
    raise SystemExit("acceptance: failed to locate gate summary path")
if debug_summary is None:
    raise SystemExit("acceptance: failed to locate debug summary path")

steady_text = read_text(steady_summary)
gate_text = read_text(gate_summary)
disasm_text = read_text(disasm_summary)
debug_text = read_text(debug_summary)

ratio_patterns = {
    "steady_array_sum": r"array_sum\s+  c:.*?native/C steady ratio≈([0-9.]+x)",
    "steady_dot_product": r"dot_product\s+  c:.*?native/C steady ratio≈([0-9.]+x)",
    "gate_array_sum": r"array_sum\s+  c:.*?native/C median ratio=([0-9.]+x)",
    "gate_dot_product": r"dot_product\s+  c:.*?native/C median ratio=([0-9.]+x)",
}

def find_ratio(text, pattern):
    m = re.search(pattern, text, re.S)
    return None if m is None else m.group(1)


disasm_patterns = {
    "disasm_array_sum_insns": r"array_sum\s+  log:.*?instruction_count: (\d+)",
    "disasm_dot_product_insns": r"dot_product\s+  log:.*?instruction_count: (\d+)",
}

print("arm64 dot acceptance summary")
print("")
print(f"programs: {programs}")
print(f"run_make_test: {run_test}")
print("")
emit_file("smoke_wrapper_log", smoke_wrapper)
emit_file("smoke_summary_log", smoke_summary)
emit_file("disasm_wrapper_log", disasm_wrapper)
emit_file("disasm_summary_log", disasm_summary)
emit_file("steady_wrapper_log", steady_wrapper)
emit_file("steady_summary_log", steady_summary)
emit_file("gate_wrapper_log", gate_wrapper)
emit_file("gate_summary_log", gate_summary)
emit_file("debug_wrapper_log", debug_wrapper)
emit_file("debug_summary_log", debug_summary)
if run_test == "1":
    emit_file("test_wrapper_log", test_wrapper)
print("")

for key, pattern in ratio_patterns.items():
    value = find_ratio(steady_text if key.startswith("steady_") else gate_text, pattern)
    if value is not None:
        print(f"{key}: {value}")

for key, pattern in disasm_patterns.items():
    value = find_ratio(disasm_text, pattern)
    if value is not None:
        print(f"{key}: {value}")

m = re.search(r"status: ([^\n]+)", debug_text)
if m:
    print(f"debug_status: {m.group(1)}")
m = re.search(r"exit_code: ([^\n]+)", debug_text)
if m:
    print(f"debug_exit_code: {m.group(1)}")
PY

echo "arm64 dot acceptance complete; summary: $summary_log"
echo "smoke wrapper log: $smoke_log"
echo "disasm wrapper log: $disasm_log"
echo "steady wrapper log: $steady_log"
echo "gate wrapper log: $gate_log"
echo "debug wrapper log: $debug_log"
if [[ "$run_test" == "1" ]]; then
    echo "test wrapper log: $test_log"
fi
