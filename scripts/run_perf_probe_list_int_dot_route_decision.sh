#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-list-int-dot-route-decision-${ts}.log"
slot_wrapper_log="$log_dir/perf-probe-list-int-dot-route-decision-slot-abi-${ts}.wrapper.log"
c_ceiling_wrapper_log="$log_dir/perf-probe-list-int-dot-route-decision-c-ceiling-${ts}.wrapper.log"
stability_wrapper_log="$log_dir/perf-probe-list-int-dot-route-decision-stability-${ts}.wrapper.log"

slot_runs="${OREN_LIST_INT_DOT_ROUTE_DECISION_SLOT_RUNS:-${OREN_LIST_INT_SLOT_ABI_CEILING_RUNS:-5}}"
slot_warmups="${OREN_LIST_INT_DOT_ROUTE_DECISION_SLOT_WARMUPS:-${OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS:-1}}"
slot_n="${OREN_LIST_INT_DOT_ROUTE_DECISION_SLOT_N:-${OREN_LIST_INT_SLOT_ABI_CEILING_N:-2000000}}"
slot_reps="${OREN_LIST_INT_DOT_ROUTE_DECISION_SLOT_REPS:-${OREN_LIST_INT_SLOT_ABI_CEILING_REPS:-100}}"

c_runs="${OREN_LIST_INT_DOT_ROUTE_DECISION_C_RUNS:-${OREN_LIST_INT_C_CEILING_RUNS:-5}}"
c_warmups="${OREN_LIST_INT_DOT_ROUTE_DECISION_C_WARMUPS:-${OREN_LIST_INT_C_CEILING_WARMUPS:-1}}"
c_n="${OREN_LIST_INT_DOT_ROUTE_DECISION_C_N:-${OREN_LIST_INT_C_CEILING_N:-2000000}}"
c_reps="${OREN_LIST_INT_DOT_ROUTE_DECISION_C_REPS:-${OREN_LIST_INT_C_CEILING_REPS:-100}}"

stability_sweeps="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_SWEEPS:-${OREN_LIST_INT_DOT_CEILING_STABILITY_SWEEPS:-5}}"
stability_runs="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_RUNS:-${OREN_LIST_INT_DOT_CEILING_STABILITY_RUNS:-3}}"
stability_warmups="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_WARMUPS:-${OREN_LIST_INT_DOT_CEILING_STABILITY_WARMUPS:-1}}"
stability_n="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_N:-${OREN_LIST_INT_DOT_CEILING_STABILITY_N:-20000}}"
stability_reps="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_REPS:-${OREN_LIST_INT_DOT_CEILING_STABILITY_REPS:-4}}"
stability_smoke="${OREN_LIST_INT_DOT_ROUTE_DECISION_STABILITY_SMOKE:-${OREN_PERF_SMOKE_LIST_INT:-0}}"

perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"

run_nested() {
    local wrapper_log="$1"
    shift
    "$@" >"$wrapper_log" 2>&1
    local summary
    summary="$(rg -o 'summary: build/logs/[^ ]+\.log' "$wrapper_log" | tail -n 1 | sed -E 's/^summary: //')"
    if [[ -z "$summary" ]]; then
        echo "failed to locate summary path in $wrapper_log" >&2
        return 1
    fi
    printf '%s\n' "$summary"
}

slot_summary="$(
    run_nested "$slot_wrapper_log" \
        env \
            OREN_LIST_INT_SLOT_ABI_CEILING_RUNS="$slot_runs" \
            OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS="$slot_warmups" \
            OREN_LIST_INT_SLOT_ABI_CEILING_N="$slot_n" \
            OREN_LIST_INT_SLOT_ABI_CEILING_REPS="$slot_reps" \
            OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
            ./scripts/run_perf_probe_list_int_slot_abi_ceiling.sh
)"

c_ceiling_summary="$(
    run_nested "$c_ceiling_wrapper_log" \
        env \
            OREN_LIST_INT_C_CEILING_RUNS="$c_runs" \
            OREN_LIST_INT_C_CEILING_WARMUPS="$c_warmups" \
            OREN_LIST_INT_C_CEILING_N="$c_n" \
            OREN_LIST_INT_C_CEILING_REPS="$c_reps" \
            OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
            ./scripts/run_perf_probe_list_int_c_ceiling.sh
)"

stability_summary="$(
    run_nested "$stability_wrapper_log" \
        env \
            OREN_PERF_SMOKE_LIST_INT="$stability_smoke" \
            OREN_LIST_INT_DOT_CEILING_STABILITY_SWEEPS="$stability_sweeps" \
            OREN_LIST_INT_DOT_CEILING_STABILITY_RUNS="$stability_runs" \
            OREN_LIST_INT_DOT_CEILING_STABILITY_WARMUPS="$stability_warmups" \
            OREN_LIST_INT_DOT_CEILING_STABILITY_N="$stability_n" \
            OREN_LIST_INT_DOT_CEILING_STABILITY_REPS="$stability_reps" \
            ./scripts/run_perf_probe_list_int_dot_ceiling_stability.sh
)"

SLOT_SUMMARY="$slot_summary" \
C_CEILING_SUMMARY="$c_ceiling_summary" \
STABILITY_SUMMARY="$stability_summary" \
SLOT_WRAPPER_LOG="$slot_wrapper_log" \
C_CEILING_WRAPPER_LOG="$c_ceiling_wrapper_log" \
STABILITY_WRAPPER_LOG="$stability_wrapper_log" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
BUILD_ENV="$build_env_raw" \
SLOT_RUNS="$slot_runs" \
SLOT_WARMUPS="$slot_warmups" \
SLOT_N="$slot_n" \
SLOT_REPS="$slot_reps" \
C_RUNS="$c_runs" \
C_WARMUPS="$c_warmups" \
C_N="$c_n" \
C_REPS="$c_reps" \
STABILITY_SMOKE="$stability_smoke" \
STABILITY_SWEEPS="$stability_sweeps" \
STABILITY_RUNS="$stability_runs" \
STABILITY_WARMUPS="$stability_warmups" \
STABILITY_N="$stability_n" \
STABILITY_REPS="$stability_reps" \
python3 - <<'PY' >"$summary_log"
import os
import re
from pathlib import Path


def parse_duration(text):
    if text is None:
        return None
    text = text.strip()
    if text.endswith("s"):
        text = text[:-1]
    return float(text)


def parse_ratio(text):
    if text is None:
        return None
    text = text.strip()
    if text.endswith("x"):
        text = text[:-1]
    return float(text)


def fmt(value, suffix=""):
    if value is None:
        return "missing"
    if suffix == "s":
        return f"{value:.6f}s"
    if suffix == "x":
        return f"{value:.4f}x"
    if suffix == "%":
        return f"{value:+.2f}%"
    return f"{value:.4f}"


def pct_delta(candidate, baseline):
    if candidate is None or baseline in (None, 0):
        return None
    return ((candidate / baseline) - 1.0) * 100.0


def parse_sections(path, key_name):
    sections = {}
    current = None
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        if not line:
            continue
        if line.endswith(":") and not line.startswith(" ") and not line.startswith("ratio_summary"):
            current = line[:-1]
            sections.setdefault(current, {})
            continue
        if current is None:
            continue
        if line.startswith("  ") and ":" in line:
            key, value = line.strip().split(":", 1)
            sections[current][key.strip()] = value.strip()
    out = {}
    for section, data in sections.items():
        value = data.get(key_name)
        if value is not None:
            out[section] = parse_duration(value)
    return out


def parse_named_ratios(path):
    ratios = {}
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if " per_rep ratio:" not in line:
            continue
        name, value = line.split(" per_rep ratio:", 1)
        ratios[name.strip()] = parse_ratio(value.strip())
    return ratios


def parse_stability(path):
    case_names = ["baseline", "slot_direct", "slot_public", "packed_scalar", "packed_simd"]
    rank_counts = {"array_sum": {}, "dot_product": {}}
    case_medians = {}
    section = None
    current_case = None
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if stripped == "array_sum_rank_counts:":
            section = "array_sum_rank_counts"
            current_case = None
            continue
        if stripped == "dot_product_rank_counts:":
            section = "dot_product_rank_counts"
            current_case = None
            continue
        if stripped in (f"{name}:" for name in case_names):
            section = "case"
            current_case = stripped[:-1]
            case_medians.setdefault(current_case, {})
            continue
        if section == "array_sum_rank_counts" and stripped.startswith(tuple(f"{name}:" for name in case_names)):
            name, rest = stripped.split(":", 1)
            m = re.search(r"wins=(\d+)/(\d+)", rest)
            if m:
                rank_counts["array_sum"][name] = (int(m.group(1)), int(m.group(2)))
            continue
        if section == "dot_product_rank_counts" and stripped.startswith(tuple(f"{name}:" for name in case_names)):
            name, rest = stripped.split(":", 1)
            m = re.search(r"wins=(\d+)/(\d+)", rest)
            if m:
                rank_counts["dot_product"][name] = (int(m.group(1)), int(m.group(2)))
            continue
        if section == "case" and current_case is not None:
            m = re.match(r"\s*array_sum_ratio: median=([0-9.]+)x", line)
            if m:
                case_medians[current_case]["array_sum_ratio"] = float(m.group(1))
                continue
            m = re.match(r"\s*dot_product_ratio: median=([0-9.]+)x", line)
            if m:
                case_medians[current_case]["dot_product_ratio"] = float(m.group(1))
                continue
            m = re.match(r"\s*array_vs_baseline_delta_pct: median=([+-]?[0-9.]+)%", line)
            if m:
                case_medians[current_case]["array_delta_pct"] = float(m.group(1))
                continue
            m = re.match(r"\s*dot_vs_baseline_delta_pct: median=([+-]?[0-9.]+)%", line)
            if m:
                case_medians[current_case]["dot_delta_pct"] = float(m.group(1))
                continue
    return rank_counts, case_medians


slot_per_rep = parse_sections(os.environ["SLOT_SUMMARY"], "per_rep")
slot_ratios = parse_named_ratios(os.environ["SLOT_SUMMARY"])
c_per_rep = parse_sections(os.environ["C_CEILING_SUMMARY"], "per_rep_s")
c_ratios = parse_named_ratios(os.environ["C_CEILING_SUMMARY"])
rank_counts, stability_cases = parse_stability(os.environ["STABILITY_SUMMARY"])

slot_abi_avoids_neon = False
slot64_vs_packed = slot_ratios.get("slot64_vector/packed_vector")
slot64_scalar_vs_packed_scalar = slot_ratios.get("slot64_scalar/packed_scalar")
if slot64_vs_packed is not None and slot64_vs_packed > 2.0:
    if slot64_scalar_vs_packed_scalar is None or 0.85 <= slot64_scalar_vs_packed_scalar <= 1.25:
        slot_abi_avoids_neon = True

baseline = stability_cases.get("baseline", {})
public = stability_cases.get("slot_public", {})
direct = stability_cases.get("slot_direct", {})
packed_simd = stability_cases.get("packed_simd", {})

def win_line(family, label):
    wins = rank_counts.get(family, {}).get(label)
    if wins is None:
        return "missing"
    return f"{wins[0]}/{wins[1]}"


public_promotable = False
direct_promotable = False
for label, dest in (("slot_public", "public"), ("slot_direct", "direct")):
    case = stability_cases.get(label, {})
    array_delta = case.get("array_delta_pct")
    dot_delta = case.get("dot_delta_pct")
    array_wins = rank_counts.get("array_sum", {}).get(label)
    dot_wins = rank_counts.get("dot_product", {}).get(label)
    if (
        array_delta is not None
        and dot_delta is not None
        and array_delta < 0
        and dot_delta < 0
        and array_wins is not None
        and dot_wins is not None
        and array_wins[0] * 2 > array_wins[1]
        and dot_wins[0] * 2 > dot_wins[1]
    ):
        if dest == "public":
            public_promotable = True
        else:
            direct_promotable = True

packed_promotable = False
packed_dot_delta = packed_simd.get("dot_delta_pct")
packed_array_delta = packed_simd.get("array_delta_pct")
if packed_dot_delta is not None and packed_array_delta is not None and packed_dot_delta < 0 and packed_array_delta < 0:
    packed_promotable = True

print("list<int> dot vector/slot64 route decision summary")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print("")
print("inputs:")
print(f"  slot_abi_wrapper_log: {os.environ['SLOT_WRAPPER_LOG']}")
print(f"  slot_abi_summary: {os.environ['SLOT_SUMMARY']}")
print(f"  c_ceiling_wrapper_log: {os.environ['C_CEILING_WRAPPER_LOG']}")
print(f"  c_ceiling_summary: {os.environ['C_CEILING_SUMMARY']}")
print(f"  stability_wrapper_log: {os.environ['STABILITY_WRAPPER_LOG']}")
print(f"  stability_summary: {os.environ['STABILITY_SUMMARY']}")
print("")
print("config:")
print(f"  slot_abi: runs={os.environ['SLOT_RUNS']} warmups={os.environ['SLOT_WARMUPS']} n={os.environ['SLOT_N']} reps={os.environ['SLOT_REPS']}")
print(f"  c_ceiling: runs={os.environ['C_RUNS']} warmups={os.environ['C_WARMUPS']} n={os.environ['C_N']} reps={os.environ['C_REPS']}")
print(
    "  stability: "
    f"smoke={os.environ['STABILITY_SMOKE']} sweeps={os.environ['STABILITY_SWEEPS']} "
    f"runs={os.environ['STABILITY_RUNS']} warmups={os.environ['STABILITY_WARMUPS']} "
    f"n={os.environ['STABILITY_N']} reps={os.environ['STABILITY_REPS']}"
)
print("")
print("slot_abi_ceiling:")
for key in [
    "c_packed_vector",
    "c_packed_scalar",
    "c_slot64_vector",
    "c_slot64_scalar",
    "oren_native_canonical",
    "oren_native_slot_direct",
]:
    print(f"  {key}_per_rep: {fmt(slot_per_rep.get(key), 's')}")
for key in [
    "slot64_vector/packed_vector",
    "slot64_scalar/packed_scalar",
    "oren_canonical/slot64_vector",
    "oren_canonical/slot64_scalar",
    "oren_slot/slot64_vector",
]:
    print(f"  {key}: {fmt(slot_ratios.get(key), 'x')}")
print("")
print("whole_operation_c_ceiling:")
for key in [
    "c_array_sum_slot64_vector",
    "c_array_sum_slot64_scalar",
    "oren_array_sum_int_canonical",
    "c_dot_product_packed32_vector",
    "c_dot_product_slot64_vector",
    "c_dot_product_slot64_scalar",
    "oren_dot_product_int_canonical",
]:
    print(f"  {key}_per_rep: {fmt(c_per_rep.get(key), 's')}")
for key in [
    "array_slot64_vector/array_packed32_vector",
    "oren_array_sum_int/array_slot64_vector",
    "dot_slot64_vector/dot_packed32_vector",
    "dot_slot64_scalar/dot_packed32_scalar",
    "oren_dot_product_int/dot_slot64_vector",
    "oren_dot_product_int/dot_slot64_scalar",
]:
    print(f"  {key}: {fmt(c_ratios.get(key), 'x')}")
print("")
print("route_stability:")
for label in ["baseline", "slot_direct", "slot_public", "packed_scalar", "packed_simd"]:
    case = stability_cases.get(label, {})
    print(f"  {label}:")
    print(f"    array_wins: {win_line('array_sum', label)}")
    print(f"    dot_wins: {win_line('dot_product', label)}")
    print(f"    array_median_ratio: {fmt(case.get('array_sum_ratio'), 'x')}")
    print(f"    dot_median_ratio: {fmt(case.get('dot_product_ratio'), 'x')}")
    if label != "baseline":
        print(f"    array_vs_baseline_delta_pct: {fmt(case.get('array_delta_pct'), '%')}")
        print(f"    dot_vs_baseline_delta_pct: {fmt(case.get('dot_delta_pct'), '%')}")
print("")
print("derived_decision:")
print(f"  slot64_current_abi_loses_packed_neon_headroom: {'yes' if slot_abi_avoids_neon else 'no'}")
print(f"  public_slot_route_promotable: {'yes' if public_promotable else 'no'}")
print(f"  hidden_direct_slot_route_promotable: {'yes' if direct_promotable else 'no'}")
print(f"  packed_bridge_route_promotable: {'yes' if packed_promotable else 'no'}")
print(
    "  slot64_host_ceiling_gap_dot_pct: "
    f"{fmt(pct_delta(c_per_rep.get('oren_dot_product_int_canonical'), c_per_rep.get('c_dot_product_slot64_vector')), '%')}"
)
print(
    "  slot64_host_ceiling_gap_array_pct: "
    f"{fmt(pct_delta(c_per_rep.get('oren_array_sum_int_canonical'), c_per_rep.get('c_array_sum_slot64_vector')), '%')}"
)
print("")
print("verdict:")
if public_promotable or direct_promotable or packed_promotable:
    print("  reroute candidate found; inspect the route_stability rows before changing shipped lowering")
else:
    print("  keep shipped canonical lowering; no helper/public/packed route clears the current decision surface")
if slot_abi_avoids_neon:
    print("  the remaining dot work should target representation/direct lowering for slot64 or a safe packed view,")
    print("  not another scalar-tail scheduling toggle or a generic packed bridge reroute")
else:
    print("  slot64/packed ABI attribution is inconclusive on this run; rerun before using it for default decisions")
PY

echo "list<int> dot vector/slot64 route decision probe complete; summary: $summary_log"
echo "slot ABI wrapper log: $slot_wrapper_log"
echo "C ceiling wrapper log: $c_ceiling_wrapper_log"
echo "stability wrapper log: $stability_wrapper_log"
