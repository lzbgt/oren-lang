#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

tag="${OREN_ARM64_FAST_PUSH_TICK_MASK_DECISION_TAG:-perf-probe-arm64-fast-push-tick-mask-decision}"
title="${OREN_ARM64_FAST_PUSH_TICK_MASK_DECISION_TITLE:-arm64 fast list<int> push tick-mask decision summary}"
sweeps="${OREN_ARM64_FAST_PUSH_TICK_MASK_DECISION_SWEEPS:-3}"
perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"

default_label="${OREN_ARM64_FAST_PUSH_TICK_MASK_DEFAULT_LABEL:-default}"
mask16383_label="${OREN_ARM64_FAST_PUSH_TICK_MASK_16383_LABEL:-mask_16383}"
mask65535_label="${OREN_ARM64_FAST_PUSH_TICK_MASK_65535_LABEL:-mask_65535}"
mask16383_env="${OREN_ARM64_FAST_PUSH_TICK_MASK_16383_ENV:-OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=16383}"
mask65535_env="${OREN_ARM64_FAST_PUSH_TICK_MASK_65535_ENV:-OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=65535}"

summary_log="$log_dir/${tag}-${ts}.log"
manifest_log="$log_dir/${tag}-${ts}.manifest.tsv"

extract_summary_path() {
    local run_log="$1"
    local prefix="$2"
    python3 - "$run_log" "$prefix" <<'PY'
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

run_fill_case() {
    local label="$1"
    local build_env="$2"
    local wrapper_log="$log_dir/${tag}-${ts}.${label}-fill.log"
    if [[ -n "$build_env" ]]; then
        env OREN_BENCH_ENV_BUILD_OREN="$build_env" make perf-probe-list-int-fill-share-decision >"$wrapper_log" 2>&1
    else
        env make perf-probe-list-int-fill-share-decision >"$wrapper_log" 2>&1
    fi
    local summary_path
    summary_path="$(extract_summary_path "$wrapper_log" "perf-probe-list-int-fill-share-decision-")"
    printf '%s\t%s\n' "$wrapper_log" "$summary_path"
}

default_fill_meta="$(run_fill_case "$default_label" "")"
mask16383_fill_meta="$(run_fill_case "$mask16383_label" "$mask16383_env")"
mask65535_fill_meta="$(run_fill_case "$mask65535_label" "$mask65535_env")"

default_fill_wrapper_log="${default_fill_meta%%$'\t'*}"
default_fill_summary="${default_fill_meta#*$'\t'}"
mask16383_fill_wrapper_log="${mask16383_fill_meta%%$'\t'*}"
mask16383_fill_summary="${mask16383_fill_meta#*$'\t'}"
mask65535_fill_wrapper_log="${mask65535_fill_meta%%$'\t'*}"
mask65535_fill_summary="${mask65535_fill_meta#*$'\t'}"

: >"$manifest_log"
for sweep in $(seq 1 "$sweeps"); do
    case $(( (sweep - 1) % 3 )) in
        0) order=("$default_label" "$mask16383_label" "$mask65535_label") ;;
        1) order=("$mask16383_label" "$mask65535_label" "$default_label") ;;
        2) order=("$mask65535_label" "$default_label" "$mask16383_label") ;;
    esac
    for label in "${order[@]}"; do
        run_log="$log_dir/${tag}-${ts}-${label}-s${sweep}.run.log"
        build_env=""
        if [[ "$label" == "$mask16383_label" ]]; then
            build_env="$mask16383_env"
        elif [[ "$label" == "$mask65535_label" ]]; then
            build_env="$mask65535_env"
        fi
        if [[ -n "$build_env" ]]; then
            env OREN_BENCH_ENV_BUILD_OREN="$build_env" make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        else
            env make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        fi
        summary_path="$(extract_summary_path "$run_log" "perf-probe-list-int-c-ceiling-")"
        printf '%s\t%s\t%s\t%s\n' "$sweep" "$label" "$run_log" "$summary_path" >>"$manifest_log"
    done
done

DEFAULT_FILL_WRAPPER_LOG="$default_fill_wrapper_log" \
DEFAULT_FILL_SUMMARY="$default_fill_summary" \
MASK16383_FILL_WRAPPER_LOG="$mask16383_fill_wrapper_log" \
MASK16383_FILL_SUMMARY="$mask16383_fill_summary" \
MASK65535_FILL_WRAPPER_LOG="$mask65535_fill_wrapper_log" \
MASK65535_FILL_SUMMARY="$mask65535_fill_summary" \
MANIFEST_LOG="$manifest_log" \
SWEEPS="$sweeps" \
TITLE="$title" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
DEFAULT_LABEL="$default_label" \
MASK16383_LABEL="$mask16383_label" \
MASK65535_LABEL="$mask65535_label" \
MASK16383_ENV="$mask16383_env" \
MASK65535_ENV="$mask65535_env" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
from pathlib import Path


def parse_ratio(text, prefix):
    m = re.search(re.escape(prefix) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def read_summary_text(path_str):
    if not path_str:
        return ""
    path = Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def fmt_ratio(value):
    return "missing" if value is None else f"{value:.4f}x"


def parse_fill(path_str):
    text = read_summary_text(path_str)
    return {
        "path": path_str,
        "fill_vs_c_vector": parse_ratio(text, "oren_fill_list_int/c_fill_slot64_vector per_rep ratio:"),
        "fill_vs_setup": parse_ratio(text, "oren_fill_list_int/oren_array_sum_setup_est ratio:"),
        "fill_vs_steady": parse_ratio(text, "oren_fill_list_int/oren_array_sum_steady_per_rep ratio:"),
        "array_steady_vs_c_vector": parse_ratio(text, "oren_array_sum/c_array_sum_slot64_vector steady_per_rep ratio:"),
    }


def parse_ceiling(path_str):
    text = read_summary_text(path_str)
    return {
        "path": path_str,
        "array_ratio": parse_ratio(text, "oren_array_sum_int/array_slot64_vector per_rep ratio:"),
        "dot_ratio": parse_ratio(text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:"),
    }


case_labels = [
    os.environ["DEFAULT_LABEL"],
    os.environ["MASK16383_LABEL"],
    os.environ["MASK65535_LABEL"],
]

fill_cases = {
    os.environ["DEFAULT_LABEL"]: parse_fill(os.environ["DEFAULT_FILL_SUMMARY"]),
    os.environ["MASK16383_LABEL"]: parse_fill(os.environ["MASK16383_FILL_SUMMARY"]),
    os.environ["MASK65535_LABEL"]: parse_fill(os.environ["MASK65535_FILL_SUMMARY"]),
}

rows = []
for raw in Path(os.environ["MANIFEST_LOG"]).read_text(encoding="utf-8", errors="replace").splitlines():
    sweep, label, run_log, summary_path = raw.split("\t")
    rows.append(
        {
            "sweep": int(sweep),
            "label": label,
            "run_log": run_log,
            "summary": parse_ceiling(summary_path),
        }
    )


def ratios_for(label, key):
    values = []
    for row in rows:
        if row["label"] != label:
            continue
        value = row["summary"].get(key)
        if value is not None:
            values.append(value)
    return values


def median_or_none(values):
    return None if not values else statistics.median(values)


def best_label_by_fill():
    best = None
    best_value = None
    for label in case_labels:
        value = fill_cases[label]["fill_vs_c_vector"]
        if value is None:
            continue
        if best_value is None or value < best_value:
            best = label
            best_value = value
    return best


def best_label_by_median(key):
    best = None
    best_value = None
    for label in case_labels:
        values = ratios_for(label, key)
        med = median_or_none(values)
        if med is None:
            continue
        if best_value is None or med < best_value:
            best = label
            best_value = med
    return best


def win_counts(key):
    counts = {label: 0 for label in case_labels}
    for sweep in range(1, int(os.environ["SWEEPS"]) + 1):
        per_sweep = []
        for row in rows:
            if row["sweep"] != sweep:
                continue
            value = row["summary"].get(key)
            if value is not None:
                per_sweep.append((value, row["label"]))
        if not per_sweep:
            continue
        per_sweep.sort()
        best_value, best_label = per_sweep[0]
        tied = [label for value, label in per_sweep if value == best_value]
        if len(tied) == 1:
            counts[best_label] += 1
    return counts


array_wins = win_counts("array_ratio")
dot_wins = win_counts("dot_ratio")
fill_pref = best_label_by_fill()
exact_array_pref = best_label_by_median("array_ratio")
exact_dot_pref = best_label_by_median("dot_ratio")

print(os.environ["TITLE"])
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print(f"default_label: {os.environ['DEFAULT_LABEL']}")
print(f"{os.environ['MASK16383_LABEL']}_build_env: {os.environ['MASK16383_ENV']}")
print(f"{os.environ['MASK65535_LABEL']}_build_env: {os.environ['MASK65535_ENV']}")
print("")

for label, wrapper_key, summary_key in [
    (os.environ["DEFAULT_LABEL"], "DEFAULT_FILL_WRAPPER_LOG", "DEFAULT_FILL_SUMMARY"),
    (os.environ["MASK16383_LABEL"], "MASK16383_FILL_WRAPPER_LOG", "MASK16383_FILL_SUMMARY"),
    (os.environ["MASK65535_LABEL"], "MASK65535_FILL_WRAPPER_LOG", "MASK65535_FILL_SUMMARY"),
]:
    print(f"{label}_fill_wrapper_log: {os.environ[wrapper_key]}")
    print(f"{label}_fill_summary: {os.environ[summary_key]}")
print("")

for label in case_labels:
    metrics = fill_cases[label]
    print(f"{label}_fill_vs_c_vector: {fmt_ratio(metrics['fill_vs_c_vector'])}")
    print(f"{label}_fill_vs_setup: {fmt_ratio(metrics['fill_vs_setup'])}")
    print(f"{label}_fill_vs_steady: {fmt_ratio(metrics['fill_vs_steady'])}")
    print(f"{label}_array_steady_vs_c_vector: {fmt_ratio(metrics['array_steady_vs_c_vector'])}")
    print("")
print(f"fill_pref: {fill_pref}")
print("")
print(f"manifest_log: {os.environ['MANIFEST_LOG']}")
print("")

for row in rows:
    print(f"sweep_{row['sweep']}_{row['label']}_run_log: {row['run_log']}")
    print(f"sweep_{row['sweep']}_{row['label']}_summary: {row['summary']['path']}")
    if row["summary"]["array_ratio"] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_array_ratio: {row['summary']['array_ratio']:.4f}x")
    if row["summary"]["dot_ratio"] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_dot_ratio: {row['summary']['dot_ratio']:.4f}x")
    print("")

for label in case_labels:
    values = ratios_for(label, "array_ratio")
    med = median_or_none(values)
    if med is not None:
        print(f"{label}_array_ratio_median: {med:.4f}x")
print(f"array_{os.environ['DEFAULT_LABEL']}_wins: {array_wins[os.environ['DEFAULT_LABEL']]}/{os.environ['SWEEPS']}")
print(f"array_{os.environ['MASK16383_LABEL']}_wins: {array_wins[os.environ['MASK16383_LABEL']]}/{os.environ['SWEEPS']}")
print(f"array_{os.environ['MASK65535_LABEL']}_wins: {array_wins[os.environ['MASK65535_LABEL']]}/{os.environ['SWEEPS']}")
print(f"exact_array_pref: {exact_array_pref}")
print("")

for label in case_labels:
    values = ratios_for(label, "dot_ratio")
    med = median_or_none(values)
    if med is not None:
        print(f"{label}_dot_ratio_median: {med:.4f}x")
print(f"dot_{os.environ['DEFAULT_LABEL']}_wins: {dot_wins[os.environ['DEFAULT_LABEL']]}/{os.environ['SWEEPS']}")
print(f"dot_{os.environ['MASK16383_LABEL']}_wins: {dot_wins[os.environ['MASK16383_LABEL']]}/{os.environ['SWEEPS']}")
print(f"dot_{os.environ['MASK65535_LABEL']}_wins: {dot_wins[os.environ['MASK65535_LABEL']]}/{os.environ['SWEEPS']}")
print(f"exact_dot_pref: {exact_dot_pref}")
print("")

if fill_pref == exact_array_pref == exact_dot_pref:
    print("decision_surface_alignment: agree")
else:
    print("decision_surface_alignment: disagree")
print("note: fill_pref comes from the fill-share/setup surface; exact_* preferences come from same-tree")
print("whole-operation C-ceiling reruns on the shipped benchmark programs.")
PY

echo "${title}; summary: $summary_log"
echo "default fill wrapper log: $default_fill_wrapper_log"
echo "${mask16383_label} fill wrapper log: $mask16383_fill_wrapper_log"
echo "${mask65535_label} fill wrapper log: $mask65535_fill_wrapper_log"
