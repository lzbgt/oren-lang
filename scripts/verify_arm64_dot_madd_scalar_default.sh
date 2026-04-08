#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

log_path="$log_dir/verify_arm64_dot_madd_scalar_default_${ts}.log"
generic_default_run_log="$log_dir/verify_arm64_dot_madd_scalar_default_generic_default_${ts}.run.log"
generic_scalar_enabled_run_log="$log_dir/verify_arm64_dot_madd_scalar_default_generic_scalar_enabled_${ts}.run.log"
list_int_default_run_log="$log_dir/verify_arm64_dot_madd_scalar_default_list_int_default_${ts}.run.log"
list_int_scalar_enabled_run_log="$log_dir/verify_arm64_dot_madd_scalar_default_list_int_scalar_enabled_${ts}.run.log"

run_capture() {
  local run_log="$1"
  shift
  "$@" >"$run_log" 2>&1
}

extract_summary_path() {
  local run_log="$1"
  python3 - "$run_log" <<'PY'
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
m = re.search(r"summary: (build/logs/perf-probe-arm64-[^\s]+\.log)", text)
if not m:
    raise SystemExit(1)
print(m.group(1))
PY
}

run_capture "$generic_default_run_log" make perf-probe-arm64-native-hot-loop-disasm
run_capture "$generic_scalar_enabled_run_log" env \
  OREN_BENCH_ENV_BUILD_OREN='OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1' \
  make perf-probe-arm64-native-hot-loop-disasm
run_capture "$list_int_default_run_log" make perf-probe-arm64-list-int-hot-loop-disasm
run_capture "$list_int_scalar_enabled_run_log" env \
  OREN_BENCH_ENV_BUILD_OREN='OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1' \
  make perf-probe-arm64-list-int-hot-loop-disasm

generic_default_summary="$(extract_summary_path "$generic_default_run_log")"
generic_scalar_enabled_summary="$(extract_summary_path "$generic_scalar_enabled_run_log")"
list_int_default_summary="$(extract_summary_path "$list_int_default_run_log")"
list_int_scalar_enabled_summary="$(extract_summary_path "$list_int_scalar_enabled_run_log")"

GENERIC_DEFAULT_RUN_LOG="$generic_default_run_log" \
GENERIC_DEFAULT_SUMMARY="$generic_default_summary" \
GENERIC_SCALAR_ENABLED_RUN_LOG="$generic_scalar_enabled_run_log" \
GENERIC_SCALAR_ENABLED_SUMMARY="$generic_scalar_enabled_summary" \
LIST_INT_DEFAULT_RUN_LOG="$list_int_default_run_log" \
LIST_INT_DEFAULT_SUMMARY="$list_int_default_summary" \
LIST_INT_SCALAR_ENABLED_RUN_LOG="$list_int_scalar_enabled_run_log" \
LIST_INT_SCALAR_ENABLED_SUMMARY="$list_int_scalar_enabled_summary" \
python3 - <<'PY' >"$log_path"
import os
import re
import sys


def parse_case(summary_path, symbol):
    text = open(summary_path, "r", encoding="utf-8").read()
    pattern = rf"{re.escape(symbol)}\s+  log:.*?instruction_count: (\d+)\n  mnemonic_counts: ([^\n]+)"
    m = re.search(pattern, text, re.S)
    if not m:
        raise SystemExit(f"missing {symbol} disasm block in {summary_path}")
    instruction_count = int(m.group(1))
    counts_line = m.group(2)
    madd_match = re.search(r"(?:^| )madd=(\d+)(?: |$)", counts_line)
    madd_count = 0 if madd_match is None else int(madd_match.group(1))
    return instruction_count, madd_count, counts_line


cases = [
    (
        "generic_default",
        os.environ["GENERIC_DEFAULT_RUN_LOG"],
        os.environ["GENERIC_DEFAULT_SUMMARY"],
        "dot_product",
        0,
    ),
    (
        "generic_scalar_enabled",
        os.environ["GENERIC_SCALAR_ENABLED_RUN_LOG"],
        os.environ["GENERIC_SCALAR_ENABLED_SUMMARY"],
        "dot_product",
        1,
    ),
    (
        "list_int_default",
        os.environ["LIST_INT_DEFAULT_RUN_LOG"],
        os.environ["LIST_INT_DEFAULT_SUMMARY"],
        "dot_product_int",
        0,
    ),
    (
        "list_int_scalar_enabled",
        os.environ["LIST_INT_SCALAR_ENABLED_RUN_LOG"],
        os.environ["LIST_INT_SCALAR_ENABLED_SUMMARY"],
        "dot_product_int",
        1,
    ),
]

print("verify arm64 dot madd scalar default-off baseline")
print("")
failures = []
case_results = {}
for label, run_log, summary_path, symbol, expect_madd in cases:
    instruction_count, madd_count, counts_line = parse_case(summary_path, symbol)
    case_results[label] = (instruction_count, madd_count)
    print(f"{label}:")
    print(f"  wrapper_log: {run_log}")
    print(f"  summary_log: {summary_path}")
    print(f"  symbol: {symbol}")
    print(f"  instruction_count: {instruction_count}")
    print(f"  madd_count: {madd_count}")
    print(f"  mnemonic_counts: {counts_line}")
    if madd_count != expect_madd:
        failures.append(f"{label}: expected madd_count={expect_madd}, got {madd_count}")
    print("")

for baseline_label, enabled_label in [
    ("generic_default", "generic_scalar_enabled"),
    ("list_int_default", "list_int_scalar_enabled"),
]:
    baseline_insns, _ = case_results[baseline_label]
    enabled_insns, _ = case_results[enabled_label]
    if enabled_insns != baseline_insns - 1:
        failures.append(
            f"{enabled_label}: expected instruction_count={baseline_insns - 1} "
            f"(baseline - 1), got {enabled_insns}"
        )

if failures:
    print("failures:")
    for item in failures:
        print(f"  - {item}")
    sys.exit(1)
PY

echo "arm64 dot madd scalar-default verify complete; log: $log_path"
