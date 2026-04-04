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
build_env="${OREN_BENCH_ENV_BUILD_OREN:-}"

current_step="init"
summary_emitted=0

emit_summary() {
    local exit_status="$1"
    local failed_step="$2"
    SMOKE_LOG="$smoke_log" \
    DISASM_WRAPPER_LOG="$disasm_log" \
    STEADY_WRAPPER_LOG="$steady_log" \
    GATE_WRAPPER_LOG="$gate_log" \
    DEBUG_WRAPPER_LOG="$debug_log" \
    TEST_WRAPPER_LOG="$test_log" \
    PROGRAMS="$programs" \
    RUN_TEST="$run_test" \
    BUILD_ENV="$build_env" \
    EXIT_STATUS="$exit_status" \
    FAILED_STEP="$failed_step" \
    python3 - <<'PY' >"$summary_log"
import os
import re


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def read_text(path):
    if not os.path.exists(path):
        return None
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
build_env = os.environ["BUILD_ENV"]
exit_status = os.environ["EXIT_STATUS"]
failed_step = os.environ["FAILED_STEP"]

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
steady_text = read_text(steady_summary) if steady_summary is not None else None
gate_text = read_text(gate_summary) if gate_summary is not None else None
disasm_text = read_text(disasm_summary) if disasm_summary is not None else None
debug_text = read_text(debug_summary) if debug_summary is not None else None

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
if build_env:
    print(f"build_env: {build_env}")
print(f"exit_status: {exit_status}")
print(f"failed_step: {failed_step}")
print("")
emit_file("smoke_wrapper_log", smoke_wrapper)
if smoke_summary is not None:
    emit_file("smoke_summary_log", smoke_summary)
emit_file("disasm_wrapper_log", disasm_wrapper)
if disasm_summary is not None:
    emit_file("disasm_summary_log", disasm_summary)
emit_file("steady_wrapper_log", steady_wrapper)
if steady_summary is not None:
    emit_file("steady_summary_log", steady_summary)
emit_file("gate_wrapper_log", gate_wrapper)
if gate_summary is not None:
    emit_file("gate_summary_log", gate_summary)
emit_file("debug_wrapper_log", debug_wrapper)
if debug_summary is not None:
    emit_file("debug_summary_log", debug_summary)
if run_test == "1" or os.path.exists(test_wrapper):
    emit_file("test_wrapper_log", test_wrapper)
print("")

for key, pattern in ratio_patterns.items():
    source_text = steady_text if key.startswith("steady_") else gate_text
    if source_text is None:
        continue
    value = find_ratio(source_text, pattern)
    if value is not None:
        print(f"{key}: {value}")

for key, pattern in disasm_patterns.items():
    if disasm_text is None:
        continue
    value = find_ratio(disasm_text, pattern)
    if value is not None:
        print(f"{key}: {value}")

if debug_text is not None:
    m = re.search(r"status: ([^\n]+)", debug_text)
    if m:
        print(f"debug_status: {m.group(1)}")
    m = re.search(r"exit_code: ([^\n]+)", debug_text)
    if m:
        print(f"debug_exit_code: {m.group(1)}")
PY
}

on_exit() {
    local status=$?
    if [[ "$summary_emitted" != "1" ]]; then
        emit_summary "$status" "$current_step"
        summary_emitted=1
    fi
    if [[ "$status" -eq 0 ]]; then
        echo "arm64 dot acceptance complete; summary: $summary_log"
    else
        echo "arm64 dot acceptance failed (exit=$status, step=$current_step); summary: $summary_log"
    fi
    echo "smoke wrapper log: $smoke_log"
    echo "disasm wrapper log: $disasm_log"
    echo "steady wrapper log: $steady_log"
    echo "gate wrapper log: $gate_log"
    echo "debug wrapper log: $debug_log"
    if [[ "$run_test" == "1" || -f "$test_log" ]]; then
        echo "test wrapper log: $test_log"
    fi
}

trap on_exit EXIT

current_step="perf-smoke-native-fast-loops"
make perf-smoke-native-fast-loops >"$smoke_log" 2>&1
current_step="perf-probe-arm64-native-hot-loop-disasm"
make perf-probe-arm64-native-hot-loop-disasm >"$disasm_log" 2>&1
current_step="perf-gate-native-steady"
env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 OREN_BENCH_PROGRAMS="$programs" \
    make perf-gate-native-steady >"$steady_log" 2>&1
current_step="perf-gate-native"
env OREN_BENCH_PROGRAMS="$programs" make perf-gate-native >"$gate_log" 2>&1
current_step="perf-debug-native-benchmark"
env OREN_BENCH_DEBUG_PROGRAM="$debug_program" OREN_BENCH_DEBUG_ARGS="$debug_args" \
    make perf-debug-native-benchmark >"$debug_log" 2>&1

if [[ "$run_test" == "1" ]]; then
    current_step="make test"
    make test >"$test_log" 2>&1
else
    : >"$test_log"
fi

current_step="complete"
emit_summary 0 "$current_step"
summary_emitted=1
