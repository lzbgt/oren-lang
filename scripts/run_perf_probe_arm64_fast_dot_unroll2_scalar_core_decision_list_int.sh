#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-${ts}.log"
read_split_wrapper_log="$log_dir/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-read-split-${ts}.run.log"
gate_wrapper_log="$log_dir/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-gate-stability-${ts}.run.log"

case_set="${OREN_ARM64_FAST_DOT_UNROLL2_SCALAR_CORE_DECISION_LIST_INT_CASES:-baseline unroll2_enabled scalar_enabled unroll2_scalar_enabled}"
candidate="${OREN_ARM64_FAST_DOT_UNROLL2_SCALAR_CORE_DECISION_LIST_INT_CANDIDATE:-unroll2_scalar_enabled}"

extract_summary_path() {
    local run_log="$1"
    local prefix="$2"
    python3 - "$run_log" "$prefix" <<'PY'
import re
import sys

run_log, prefix = sys.argv[1], sys.argv[2]
text = open(run_log, "r", encoding="utf-8").read()
m = re.search(rf"summary: (build/logs/{re.escape(prefix)}[^\s]+\.log)", text)
if not m:
    raise SystemExit(1)
print(m.group(1))
PY
}

set +e
env \
    OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_LIST_INT_CASES="$case_set" \
    make perf-probe-arm64-fast-dot-scalar-core-read-split-list-int >"$read_split_wrapper_log" 2>&1
read_split_rc=$?
set -e

read_split_summary=""
if [[ "$read_split_rc" == "0" ]]; then
    read_split_summary="$(extract_summary_path "$read_split_wrapper_log" "perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-" || true)"
fi

set +e
env \
    OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_LIST_INT_CASES="$case_set" \
    make perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int >"$gate_wrapper_log" 2>&1
gate_rc=$?
set -e

gate_summary=""
if [[ "$gate_rc" == "0" ]]; then
    gate_summary="$(extract_summary_path "$gate_wrapper_log" "perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-" || true)"
fi

READ_SPLIT_WRAPPER_LOG="$read_split_wrapper_log" \
READ_SPLIT_WRAPPER_RC="$read_split_rc" \
READ_SPLIT_SUMMARY="$read_split_summary" \
GATE_WRAPPER_LOG="$gate_wrapper_log" \
GATE_WRAPPER_RC="$gate_rc" \
GATE_SUMMARY="$gate_summary" \
CASE_SET="$case_set" \
CANDIDATE="$candidate" \
python3 - <<'PY' >"$summary_log"
import os
import re


def parse_pct(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_wins(value):
    if value is None:
        return None
    m = re.match(r"(\d+)/(\d+)$", value)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def fmt_pct(value):
    if isinstance(value, (int, float)):
        return f"{value:+.2f}%"
    return "missing"


read_split_summary = os.environ["READ_SPLIT_SUMMARY"]
gate_summary = os.environ["GATE_SUMMARY"]
candidate = os.environ["CANDIDATE"]

read_split_deltas = {}
if read_split_summary and os.path.exists(read_split_summary):
    text = open(read_split_summary, "r", encoding="utf-8").read()
    for raw in text.splitlines():
        m = re.match(r"^([a-z0-9_]+)_dot_product_int_native_(short|setup|delta|long_per_rep)_delta_pct: ([+-][0-9.]+)%$", raw)
        if m:
            read_split_deltas.setdefault(m.group(1), {})[m.group(2)] = float(m.group(3))

gate_deltas = {}
if gate_summary and os.path.exists(gate_summary):
    current = None
    for raw in open(gate_summary, "r", encoding="utf-8"):
        line = raw.rstrip("\n")
        m_case = re.match(r"^([a-z0-9_]+):$", line)
        if m_case:
            current = m_case.group(1)
            gate_deltas.setdefault(current, {})
            continue
        if current is None:
            continue
        m_native = re.match(
            r"^  vs_baseline_native_delta_pct: median=([+-][0-9.]+)% "
            r"min=([+-][0-9.]+)% max=([+-][0-9.]+)% wins=(\d+/\d+)$",
            line,
        )
        if m_native:
            gate_deltas[current]["native_delta_pct_median"] = float(m_native.group(1))
            gate_deltas[current]["native_delta_pct_min"] = float(m_native.group(2))
            gate_deltas[current]["native_delta_pct_max"] = float(m_native.group(3))
            gate_deltas[current]["native_delta_wins"] = m_native.group(4)
            continue
        m_ratio = re.match(
            r"^  vs_baseline_native_over_c_delta_pct: median=([+-][0-9.]+)% "
            r"min=([+-][0-9.]+)% max=([+-][0-9.]+)% wins=(\d+/\d+)$",
            line,
        )
        if m_ratio:
            gate_deltas[current]["native_over_c_delta_pct_median"] = float(m_ratio.group(1))
            gate_deltas[current]["native_over_c_delta_pct_min"] = float(m_ratio.group(2))
            gate_deltas[current]["native_over_c_delta_pct_max"] = float(m_ratio.group(3))
            gate_deltas[current]["native_over_c_delta_wins"] = m_ratio.group(4)

print("arm64 fast dot unroll2 + scalar-core decision list<int> summary")
print("")
print(f"case_set: {os.environ['CASE_SET']}")
print(f"candidate: {candidate}")
print(f"read_split_wrapper_log: {os.environ['READ_SPLIT_WRAPPER_LOG']}")
print(f"read_split_wrapper_exit_code: {os.environ['READ_SPLIT_WRAPPER_RC']}")
print(f"read_split_summary: {read_split_summary or 'missing'}")
print(f"gate_stability_wrapper_log: {os.environ['GATE_WRAPPER_LOG']}")
print(f"gate_stability_wrapper_exit_code: {os.environ['GATE_WRAPPER_RC']}")
print(f"gate_stability_summary: {gate_summary or 'missing'}")
print("")

print("read_split_native_deltas:")
for label in os.environ["CASE_SET"].split():
    if label == "baseline":
        continue
    metrics = read_split_deltas.get(label, {})
    if not metrics:
        print(f"  {label}: missing")
        continue
    ordered = ", ".join(
        f"{key}={metrics[key]:+.2f}%"
        for key in ["short", "setup", "delta", "long_per_rep"]
        if key in metrics
    )
    print(f"  {label}: {ordered}")
print("")

print("gate_stability_deltas:")
for label in os.environ["CASE_SET"].split():
    if label == "baseline":
        continue
    metrics = gate_deltas.get(label, {})
    if not metrics:
        print(f"  {label}: missing")
        continue
    print(
        f"  {label}: native_median={fmt_pct(metrics.get('native_delta_pct_median'))} "
        f"wins={metrics.get('native_delta_wins', 'missing')}; "
        f"native_over_c={fmt_pct(metrics.get('native_over_c_delta_pct_median'))} "
        f"wins={metrics.get('native_over_c_delta_wins', 'missing')}"
    )
print("")

candidate_read = read_split_deltas.get(candidate, {})
candidate_gate = gate_deltas.get(candidate, {})
read_long = parse_pct(candidate_read.get("long_per_rep"))
gate_native = parse_pct(candidate_gate.get("native_delta_pct_median"))
gate_ratio = parse_pct(candidate_gate.get("native_over_c_delta_pct_median"))
gate_native_wins = parse_wins(candidate_gate.get("native_delta_wins"))
gate_ratio_wins = parse_wins(candidate_gate.get("native_over_c_delta_wins"))

read_split_win = read_long is not None and read_long < 0.0
gate_native_win = (
    gate_native is not None
    and gate_native < 0.0
    and gate_native_wins is not None
    and gate_native_wins[0] > gate_native_wins[1] / 2.0
)
gate_ratio_win = (
    gate_ratio is not None
    and gate_ratio < 0.0
    and gate_ratio_wins is not None
    and gate_ratio_wins[0] > gate_ratio_wins[1] / 2.0
)
promotable = read_split_win and gate_native_win and gate_ratio_win

print(f"candidate_read_split_long_per_rep_win: {'yes' if read_split_win else 'no'}")
print(f"candidate_gate_native_median_win: {'yes' if gate_native_win else 'no'}")
print(f"candidate_gate_native_over_c_win: {'yes' if gate_ratio_win else 'no'}")
print(f"candidate_promotable: {'yes' if promotable else 'no'}")
if not promotable:
    print("decision: keep the candidate opt-in until it wins read-split long-per-rep and both order-balanced gate views.")
else:
    print("decision: candidate clears this decision surface; run broader integration before any default flip.")
PY

echo "arm64 fast-dot unroll2 scalar-core decision list<int> probe complete; summary: $summary_log"
echo "read-split wrapper log: $read_split_wrapper_log"
echo "gate-stability wrapper log: $gate_wrapper_log"

if [[ "$read_split_rc" != "0" ]]; then
    echo "read-split leg failed (exit=$read_split_rc)"
    exit "$read_split_rc"
fi
if [[ "$gate_rc" != "0" ]]; then
    echo "gate-stability leg failed (exit=$gate_rc)"
    exit "$gate_rc"
fi
