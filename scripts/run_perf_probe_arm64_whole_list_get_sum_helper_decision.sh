#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-whole-list-get-sum-helper-decision-${ts}.log"
manifest_log="$log_dir/perf-probe-arm64-whole-list-get-sum-helper-decision-${ts}.manifest.tsv"
default_wrapper_log="$log_dir/perf-probe-arm64-whole-list-get-sum-helper-decision-${ts}.default-c-ceiling.log"
helper_wrapper_log="$log_dir/perf-probe-arm64-whole-list-get-sum-helper-decision-${ts}.helper-c-ceiling.log"
slot_wrapper_log="$log_dir/perf-probe-arm64-whole-list-get-sum-helper-decision-${ts}.slot-direct-split.log"

extract_summary_path() {
    local wrapper_log="$1"
    local prefix="$2"
    python3 - "$wrapper_log" "$prefix" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
prefix = sys.argv[2]
m = re.search(r"summary:\s+(build/logs/" + re.escape(prefix) + r"[^ ]+\.log)", text)
if m:
    print(m.group(1))
PY
}

make perf-probe-list-int-c-ceiling >"$default_wrapper_log" 2>&1
default_summary="$(extract_summary_path "$default_wrapper_log" "perf-probe-list-int-c-ceiling-")"

env OREN_BENCH_ENV_BUILD_OREN=OREN_NATIVE_FAST_LIST_INT_GET_SUM_WHOLE_LIST_HELPER=1 \
    make perf-probe-list-int-c-ceiling >"$helper_wrapper_log" 2>&1
helper_summary="$(extract_summary_path "$helper_wrapper_log" "perf-probe-list-int-c-ceiling-")"

env OREN_PERF_SMOKE_LIST_INT=0 \
    make perf-probe-list-int-slot-direct-read-split >"$slot_wrapper_log" 2>&1
slot_summary="$(extract_summary_path "$slot_wrapper_log" "perf-probe-list-int-slot-direct-read-split-")"

printf 'surface\twrapper_log\tsummary_log\n' >"$manifest_log"
printf 'default_c_ceiling\t%s\t%s\n' "$default_wrapper_log" "$default_summary" >>"$manifest_log"
printf 'helper_c_ceiling\t%s\t%s\n' "$helper_wrapper_log" "$helper_summary" >>"$manifest_log"
printf 'slot_direct_read_split\t%s\t%s\n' "$slot_wrapper_log" "$slot_summary" >>"$manifest_log"

DEFAULT_SUMMARY="$default_summary" \
HELPER_SUMMARY="$helper_summary" \
SLOT_SUMMARY="$slot_summary" \
DEFAULT_WRAPPER_LOG="$default_wrapper_log" \
HELPER_WRAPPER_LOG="$helper_wrapper_log" \
SLOT_WRAPPER_LOG="$slot_wrapper_log" \
MANIFEST_LOG="$manifest_log" \
python3 - <<'PY' >"$summary_log"
from pathlib import Path
import re
import os


def grab_ratio(text, label):
    m = re.search(re.escape(label) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def grab_split(text, section, key):
    pat = re.compile(
        re.escape(section) + r":\n(?:  .*\n)*?  " + re.escape(key) + r":\s*([0-9.]+)x",
        re.MULTILINE,
    )
    m = pat.search(text)
    return None if m is None else float(m.group(1))


default_text = Path(os.environ["DEFAULT_SUMMARY"]).read_text(encoding="utf-8", errors="replace")
helper_text = Path(os.environ["HELPER_SUMMARY"]).read_text(encoding="utf-8", errors="replace")
slot_text = Path(os.environ["SLOT_SUMMARY"]).read_text(encoding="utf-8", errors="replace")

default_array = grab_ratio(default_text, "oren_array_sum_int/array_slot64_vector per_rep ratio:")
helper_array = grab_ratio(helper_text, "oren_array_sum_int/array_slot64_vector per_rep ratio:")
default_dot = grab_ratio(default_text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:")
helper_dot = grab_ratio(helper_text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:")

slot_array = grab_split(slot_text, "array_sum_int", "slot_direct_native/C_long_per_rep")
slot_dot = grab_split(slot_text, "dot_product_int", "slot_direct_native/C_long_per_rep")
slot_array_gap = grab_split(slot_text, "array_sum_int", "slot_direct_vs_canonical_long_per_rep")
slot_dot_gap = grab_split(slot_text, "dot_product_int", "slot_direct_vs_canonical_long_per_rep")

print("arm64 whole-list get-sum helper decision summary")
print("")
print(f"default_wrapper_log: {os.environ['DEFAULT_WRAPPER_LOG']}")
print(f"default_summary: {os.environ['DEFAULT_SUMMARY']}")
print(f"helper_wrapper_log: {os.environ['HELPER_WRAPPER_LOG']}")
print(f"helper_summary: {os.environ['HELPER_SUMMARY']}")
print(f"slot_wrapper_log: {os.environ['SLOT_WRAPPER_LOG']}")
print(f"slot_summary: {os.environ['SLOT_SUMMARY']}")
print(f"manifest_log: {os.environ['MANIFEST_LOG']}")
print("")

if default_array is not None:
    print(f"default_exact_array_ratio: {default_array:.4f}x")
if helper_array is not None:
    print(f"helper_exact_array_ratio: {helper_array:.4f}x")
if default_array is not None and helper_array is not None:
    winner = "default" if default_array < helper_array else "helper"
    print(f"exact_array_winner: {winner}")
    print(f"exact_array_helper_vs_default: {helper_array / default_array:.4f}x")
print("")

if default_dot is not None:
    print(f"default_exact_dot_ratio: {default_dot:.4f}x")
if helper_dot is not None:
    print(f"helper_exact_dot_ratio: {helper_dot:.4f}x")
if default_dot is not None and helper_dot is not None:
    winner = "default" if default_dot < helper_dot else "helper"
    print(f"exact_dot_winner: {winner}")
    print(f"exact_dot_helper_vs_default: {helper_dot / default_dot:.4f}x")
print("")

if slot_array is not None:
    print(f"slot_direct_array_long_per_rep: {slot_array:.4f}x")
if slot_array_gap is not None:
    print(f"slot_direct_vs_canonical_array_long_per_rep: {slot_array_gap:.4f}x")
if slot_dot is not None:
    print(f"slot_direct_dot_long_per_rep: {slot_dot:.4f}x")
if slot_dot_gap is not None:
    print(f"slot_direct_vs_canonical_dot_long_per_rep: {slot_dot_gap:.4f}x")
print("")
print("note: slot_direct_* is the hidden helper ceiling on the small read-split surface.")
print("note: exact_* decides whether the canonical whole-list helper shortcut should ship.")
PY

echo "arm64 whole-list get-sum helper decision probe complete; summary: $summary_log"
echo "manifest log: $manifest_log"
