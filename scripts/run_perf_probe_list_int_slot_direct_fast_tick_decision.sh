#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

tag="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_DECISION_TAG:-perf-probe-list-int-slot-direct-fast-tick-decision}"
summary_log="$log_dir/${tag}-${ts}.log"
manifest_log="$log_dir/${tag}-${ts}.manifest.tsv"
restore_default_prebuild_log="$log_dir/${tag}-${ts}-restore-default-prebuild.wrapper.log"

perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"
fast_build_env="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_DECISION_ENV:-OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1}"

slot_runs="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SLOT_RUNS:-${OREN_LIST_INT_SLOT_ABI_CEILING_RUNS:-5}}"
slot_warmups="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SLOT_WARMUPS:-${OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS:-1}}"
slot_n="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SLOT_N:-${OREN_LIST_INT_SLOT_ABI_CEILING_N:-2000000}}"
slot_reps="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SLOT_REPS:-${OREN_LIST_INT_SLOT_ABI_CEILING_REPS:-100}}"

split_runs="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_RUNS:-${OREN_LIST_INT_SLOT_DIRECT_SPLIT_RUNS:-2}}"
split_warmups="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_WARMUPS:-${OREN_LIST_INT_SLOT_DIRECT_SPLIT_WARMUPS:-0}}"
split_n="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_N:-${OREN_LIST_INT_SLOT_DIRECT_SPLIT_N:-20000}}"
split_short_reps="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_SHORT_REPS:-${OREN_LIST_INT_SLOT_DIRECT_SPLIT_SHORT_REPS:-1}}"
split_long_reps="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_LONG_REPS:-${OREN_LIST_INT_SLOT_DIRECT_SPLIT_LONG_REPS:-2}}"
split_smoke="${OREN_LIST_INT_SLOT_DIRECT_FAST_TICK_SPLIT_SMOKE:-${OREN_PERF_SMOKE_LIST_INT_SLOT_DIRECT_SPLIT:-1}}"

run_nested() {
    local label="$1"
    local kind="$2"
    local wrapper_log="$log_dir/${tag}-${ts}-${label}-${kind}.wrapper.log"
    shift 2
    "$@" >"$wrapper_log" 2>&1
    local summary
    summary="$(rg -o 'summary: build/logs/[^ ]+\.log' "$wrapper_log" | tail -n 1 | sed -E 's/^summary: //')"
    if [[ -z "$summary" ]]; then
        echo "failed to locate summary path in $wrapper_log" >&2
        return 1
    fi
    printf '%s\t%s\t%s\t%s\n' "$label" "$kind" "$wrapper_log" "$summary" >>"$manifest_log"
}

: >"$manifest_log"

run_nested default slot_abi \
    env -u OREN_BENCH_ENV_BUILD_OREN \
        OREN_LIST_INT_SLOT_ABI_CEILING_RUNS="$slot_runs" \
        OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS="$slot_warmups" \
        OREN_LIST_INT_SLOT_ABI_CEILING_N="$slot_n" \
        OREN_LIST_INT_SLOT_ABI_CEILING_REPS="$slot_reps" \
        OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
        ./scripts/run_perf_probe_list_int_slot_abi_ceiling.sh

run_nested fast_tick slot_abi \
    env \
        OREN_BENCH_ENV_BUILD_OREN="$fast_build_env" \
        OREN_LIST_INT_SLOT_ABI_CEILING_RUNS="$slot_runs" \
        OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS="$slot_warmups" \
        OREN_LIST_INT_SLOT_ABI_CEILING_N="$slot_n" \
        OREN_LIST_INT_SLOT_ABI_CEILING_REPS="$slot_reps" \
        OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
        ./scripts/run_perf_probe_list_int_slot_abi_ceiling.sh

run_nested default read_split \
    env -u OREN_BENCH_ENV_BUILD_OREN \
        OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
        OREN_PERF_PREBUILD_FORCE=1 \
        OREN_PERF_SMOKE_LIST_INT_SLOT_DIRECT_SPLIT="$split_smoke" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_RUNS="$split_runs" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_WARMUPS="$split_warmups" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_N="$split_n" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_SHORT_REPS="$split_short_reps" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_LONG_REPS="$split_long_reps" \
        ./scripts/run_perf_probe_list_int_slot_direct_read_split.sh

run_nested fast_tick read_split \
    env \
        OREN_BENCH_ENV_BUILD_OREN="$fast_build_env" \
        OREN_PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
        OREN_PERF_PREBUILD_FORCE=1 \
        OREN_PERF_SMOKE_LIST_INT_SLOT_DIRECT_SPLIT="$split_smoke" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_RUNS="$split_runs" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_WARMUPS="$split_warmups" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_N="$split_n" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_SHORT_REPS="$split_short_reps" \
        OREN_LIST_INT_SLOT_DIRECT_SPLIT_LONG_REPS="$split_long_reps" \
        ./scripts/run_perf_probe_list_int_slot_direct_read_split.sh

env -u OREN_BENCH_ENV_BUILD_OREN \
    OREN_PERF_PREBUILD_FORCE=1 \
    ./scripts/build_perf_artifacts_list_int_slot_direct.sh >"$restore_default_prebuild_log" 2>&1

MANIFEST_LOG="$manifest_log" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
FAST_BUILD_ENV="$fast_build_env" \
RESTORE_DEFAULT_PREBUILD_LOG="$restore_default_prebuild_log" \
SLOT_RUNS="$slot_runs" \
SLOT_WARMUPS="$slot_warmups" \
SLOT_N="$slot_n" \
SLOT_REPS="$slot_reps" \
SPLIT_SMOKE="$split_smoke" \
SPLIT_RUNS="$split_runs" \
SPLIT_WARMUPS="$split_warmups" \
SPLIT_N="$split_n" \
SPLIT_SHORT_REPS="$split_short_reps" \
SPLIT_LONG_REPS="$split_long_reps" \
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


def parse_read_split(path):
    sections = {}
    current = None
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        if line in ("array_sum_int:", "dot_product_int:"):
            current = line[:-1]
            sections.setdefault(current, {})
            continue
        if current is None or not line.startswith("  ") or ":" not in line:
            continue
        key, value = line.strip().split(":", 1)
        value = value.strip()
        if value.endswith("x"):
            try:
                sections[current][key] = parse_ratio(value)
            except ValueError:
                pass
        elif value in ("canonical", "slot_direct"):
            sections[current][key] = value
    return sections


manifest = {}
for raw in Path(os.environ["MANIFEST_LOG"]).read_text(encoding="utf-8", errors="replace").splitlines():
    label, kind, wrapper, summary = raw.split("\t")
    manifest.setdefault(label, {})[kind] = {"wrapper": wrapper, "summary": summary}

slot = {}
split = {}
for label in ("default", "fast_tick"):
    slot_path = manifest[label]["slot_abi"]["summary"]
    split_path = manifest[label]["read_split"]["summary"]
    slot[label] = {
        "per_rep": parse_sections(slot_path, "per_rep"),
        "ratios": parse_named_ratios(slot_path),
    }
    split[label] = parse_read_split(split_path)

default_slot = slot["default"]["per_rep"].get("oren_native_slot_direct")
fast_slot = slot["fast_tick"]["per_rep"].get("oren_native_slot_direct")
default_canonical = slot["default"]["per_rep"].get("oren_native_canonical")
fast_canonical = slot["fast_tick"]["per_rep"].get("oren_native_canonical")
default_slot64_vector = slot["default"]["per_rep"].get("c_slot64_vector")
fast_slot64_vector = slot["fast_tick"]["per_rep"].get("c_slot64_vector")

fast_promotable = False
dot_split_delta = pct_delta(
    split["fast_tick"].get("dot_product_int", {}).get("slot_direct_native/C_long_per_rep"),
    split["default"].get("dot_product_int", {}).get("slot_direct_native/C_long_per_rep"),
)
array_split_delta = pct_delta(
    split["fast_tick"].get("array_sum_int", {}).get("slot_direct_native/C_long_per_rep"),
    split["default"].get("array_sum_int", {}).get("slot_direct_native/C_long_per_rep"),
)
slot_delta = pct_delta(fast_slot, default_slot)
if (
    slot_delta is not None
    and dot_split_delta is not None
    and array_split_delta is not None
    and slot_delta < 0.0
    and dot_split_delta < 0.0
    and array_split_delta < 0.0
    and fast_slot is not None
    and fast_canonical is not None
    and fast_slot < fast_canonical
):
    fast_promotable = True

print("list<int> slot-direct fast-tick decision summary")
print("")
print(f"fast_build_env: {os.environ['FAST_BUILD_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print("")
print("inputs:")
for label in ("default", "fast_tick"):
    for kind in ("slot_abi", "read_split"):
        print(f"  {label}_{kind}_wrapper_log: {manifest[label][kind]['wrapper']}")
        print(f"  {label}_{kind}_summary: {manifest[label][kind]['summary']}")
print(f"  restore_default_prebuild_log: {os.environ['RESTORE_DEFAULT_PREBUILD_LOG']}")
print("")
print("config:")
print(
    f"  slot_abi: runs={os.environ['SLOT_RUNS']} warmups={os.environ['SLOT_WARMUPS']} "
    f"n={os.environ['SLOT_N']} reps={os.environ['SLOT_REPS']}"
)
print(
    f"  read_split: smoke={os.environ['SPLIT_SMOKE']} runs={os.environ['SPLIT_RUNS']} "
    f"warmups={os.environ['SPLIT_WARMUPS']} n={os.environ['SPLIT_N']} "
    f"short_reps={os.environ['SPLIT_SHORT_REPS']} long_reps={os.environ['SPLIT_LONG_REPS']} "
    "force_prebuild=1 restore_default_prebuild=1"
)
print("")
print("slot_abi_ceiling:")
for label in ("default", "fast_tick"):
    data = slot[label]
    print(f"  {label}:")
    for key in ("c_slot64_vector", "oren_native_canonical", "oren_native_slot_direct"):
        print(f"    {key}_per_rep: {fmt(data['per_rep'].get(key), 's')}")
    for key in ("oren_slot/slot64_vector", "oren_canonical/oren_slot"):
        print(f"    {key}: {fmt(data['ratios'].get(key), 'x')}")
print(f"  fast_tick_vs_default_slot_direct_per_rep_delta_pct: {fmt(slot_delta, '%')}")
print(f"  fast_tick_vs_default_canonical_per_rep_delta_pct: {fmt(pct_delta(fast_canonical, default_canonical), '%')}")
print(f"  fast_tick_vs_default_slot64_vector_per_rep_delta_pct: {fmt(pct_delta(fast_slot64_vector, default_slot64_vector), '%')}")
print("")
print("read_split:")
for program in ("array_sum_int", "dot_product_int"):
    print(f"  {program}:")
    default_case = split["default"].get(program, {})
    fast_case = split["fast_tick"].get(program, {})
    for key in ("slot_direct_native/C_long_per_rep", "slot_direct_vs_canonical_long_per_rep"):
        print(f"    default_{key}: {fmt(default_case.get(key), 'x')}")
        print(f"    fast_tick_{key}: {fmt(fast_case.get(key), 'x')}")
        print(f"    fast_tick_vs_default_{key}_delta_pct: {fmt(pct_delta(fast_case.get(key), default_case.get(key)), '%')}")
print("")
print("derived_decision:")
print(f"  fast_tick_promotable: {'yes' if fast_promotable else 'no'}")
print(
    "  slot_direct_still_slower_than_canonical_on_slot_abi: "
    f"{'yes' if fast_slot is not None and fast_canonical is not None and fast_slot > fast_canonical else 'no'}"
)
print(
    "  slot_direct_still_slower_than_host_slot64_vector_on_slot_abi: "
    f"{'yes' if fast_slot is not None and fast_slot64_vector is not None and fast_slot > fast_slot64_vector else 'no'}"
)
print("")
print("verdict:")
if fast_promotable:
    print("  fast-tick candidate cleared this decision surface; rerun a stronger route decision before changing shipped defaults")
else:
    print("  keep OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK opt-in; it does not clear the slot-helper decision surface")
    print("  the remaining W5 path is still real representation/direct lowering, not a safepoint tick/spill shortcut")
PY

echo "list<int> slot-direct fast-tick decision probe complete; summary: $summary_log"
