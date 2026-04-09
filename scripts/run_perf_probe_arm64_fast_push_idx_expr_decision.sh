#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

tag="${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG:-perf-probe-arm64-fast-push-idx-expr-decision}"
title="${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE:-arm64 fast list<int> push idx-expr decision summary}"
variant_label="${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL:-disabled}"
variant_env="${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV:-${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_DISABLE_ENV:-OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR=0}}"

summary_log="$log_dir/${tag}-${ts}.log"
default_fill_wrapper_log="$log_dir/${tag}-${ts}.default-fill.log"
variant_fill_wrapper_log="$log_dir/${tag}-${ts}.${variant_label}-fill.log"
manifest_log="$log_dir/${tag}-${ts}.manifest.tsv"

sweeps="${OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_SWEEPS:-3}"
perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"

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

make perf-probe-list-int-fill-share-decision >"$default_fill_wrapper_log" 2>&1
default_fill_summary="$(extract_summary_path "$default_fill_wrapper_log" "perf-probe-list-int-fill-share-decision-")"

env OREN_BENCH_ENV_BUILD_OREN="$variant_env" \
    make perf-probe-list-int-fill-share-decision >"$variant_fill_wrapper_log" 2>&1
variant_fill_summary="$(extract_summary_path "$variant_fill_wrapper_log" "perf-probe-list-int-fill-share-decision-")"

: >"$manifest_log"
for sweep in $(seq 1 "$sweeps"); do
    if (( sweep % 2 == 1 )); then
        order="default ${variant_label}"
    else
        order="${variant_label} default"
    fi
    for label in $order; do
        run_log="$log_dir/${tag}-${ts}-${label}-s${sweep}.run.log"
        if [[ "$label" == "default" ]]; then
            env make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        else
            env OREN_BENCH_ENV_BUILD_OREN="$variant_env" make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        fi
        summary_path="$(extract_summary_path "$run_log" "perf-probe-list-int-c-ceiling-")"
        printf '%s\t%s\t%s\t%s\n' "$sweep" "$label" "$run_log" "$summary_path" >>"$manifest_log"
    done
done

DEFAULT_FILL_WRAPPER_LOG="$default_fill_wrapper_log" \
DEFAULT_FILL_SUMMARY="$default_fill_summary" \
VARIANT_FILL_WRAPPER_LOG="$variant_fill_wrapper_log" \
VARIANT_FILL_SUMMARY="$variant_fill_summary" \
MANIFEST_LOG="$manifest_log" \
SWEEPS="$sweeps" \
VARIANT_ENV="$variant_env" \
VARIANT_LABEL="$variant_label" \
TITLE="$title" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
from pathlib import Path


def parse_ratio(text, prefix):
    m = re.search(re.escape(prefix) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def parse_fill(path_str):
    path = Path(path_str)
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        "path": path_str,
        "fill_vs_c_vector": parse_ratio(text, "oren_fill_list_int/c_fill_slot64_vector per_rep ratio:"),
        "fill_vs_setup": parse_ratio(text, "oren_fill_list_int/oren_array_sum_setup_est ratio:"),
        "fill_vs_steady": parse_ratio(text, "oren_fill_list_int/oren_array_sum_steady_per_rep ratio:"),
        "array_steady_vs_c_vector": parse_ratio(text, "oren_array_sum/c_array_sum_slot64_vector steady_per_rep ratio:"),
    }


def parse_ceiling(path_str):
    path = Path(path_str)
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        "path": path_str,
        "array_ratio": parse_ratio(text, "oren_array_sum_int/array_slot64_vector per_rep ratio:"),
        "dot_ratio": parse_ratio(text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:"),
    }


default_fill = parse_fill(os.environ["DEFAULT_FILL_SUMMARY"])
variant_fill = parse_fill(os.environ["VARIANT_FILL_SUMMARY"])
variant_label = os.environ["VARIANT_LABEL"]

rows = []
manifest = Path(os.environ["MANIFEST_LOG"])
for raw in manifest.read_text(encoding="utf-8", errors="replace").splitlines():
    sweep, label, run_log, summary = raw.split("\t")
    rows.append(
        {
            "sweep": int(sweep),
            "label": label,
            "run_log": run_log,
            "summary": parse_ceiling(summary),
        }
    )

default_rows = [r for r in rows if r["label"] == "default"]
variant_rows = [r for r in rows if r["label"] == variant_label]


def ratios_for(key, subset):
    out = []
    for row in subset:
        value = row["summary"].get(key)
        if value is not None:
            out.append(value)
    return out


def median_or_none(values):
    return None if not values else statistics.median(values)


default_array = ratios_for("array_ratio", default_rows)
variant_array = ratios_for("array_ratio", variant_rows)
default_dot = ratios_for("dot_ratio", default_rows)
variant_dot = ratios_for("dot_ratio", variant_rows)

array_default_wins = 0
array_variant_wins = 0
dot_default_wins = 0
dot_variant_wins = 0
for sweep in range(1, int(os.environ["SWEEPS"]) + 1):
    d = next((r for r in default_rows if r["sweep"] == sweep), None)
    x = next((r for r in variant_rows if r["sweep"] == sweep), None)
    if d is None or x is None:
        continue
    da = d["summary"].get("array_ratio")
    xa = x["summary"].get("array_ratio")
    if da is not None and xa is not None:
        if da < xa:
            array_default_wins += 1
        elif xa < da:
            array_variant_wins += 1
    dd = d["summary"].get("dot_ratio")
    xd = x["summary"].get("dot_ratio")
    if dd is not None and xd is not None:
        if dd < xd:
            dot_default_wins += 1
        elif xd < dd:
            dot_variant_wins += 1

fill_pref = "tie"
if default_fill["fill_vs_c_vector"] is not None and variant_fill["fill_vs_c_vector"] is not None:
    if default_fill["fill_vs_c_vector"] < variant_fill["fill_vs_c_vector"]:
        fill_pref = "default"
    elif variant_fill["fill_vs_c_vector"] < default_fill["fill_vs_c_vector"]:
        fill_pref = variant_label

exact_array_pref = "tie"
if default_array and variant_array:
    if statistics.median(default_array) < statistics.median(variant_array):
        exact_array_pref = "default"
    elif statistics.median(variant_array) < statistics.median(default_array):
        exact_array_pref = variant_label

exact_dot_pref = "tie"
if default_dot and variant_dot:
    if statistics.median(default_dot) < statistics.median(variant_dot):
        exact_dot_pref = "default"
    elif statistics.median(variant_dot) < statistics.median(default_dot):
        exact_dot_pref = variant_label

print(os.environ["TITLE"])
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"variant_label: {variant_label}")
print(f"variant_build_env: {os.environ['VARIANT_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print("")
print(f"default_fill_wrapper_log: {os.environ['DEFAULT_FILL_WRAPPER_LOG']}")
print(f"default_fill_summary: {default_fill['path']}")
print(f"{variant_label}_fill_wrapper_log: {os.environ['VARIANT_FILL_WRAPPER_LOG']}")
print(f"{variant_label}_fill_summary: {variant_fill['path']}")
print("")
for label, metrics in [("default", default_fill), (variant_label, variant_fill)]:
    print(f"{label}_fill_vs_c_vector: {metrics['fill_vs_c_vector']:.4f}x")
    print(f"{label}_fill_vs_setup: {metrics['fill_vs_setup']:.4f}x")
    print(f"{label}_fill_vs_steady: {metrics['fill_vs_steady']:.4f}x")
    print(f"{label}_array_steady_vs_c_vector: {metrics['array_steady_vs_c_vector']:.4f}x")
    print("")
print(f"fill_pref: {fill_pref}")
print("")
print(f"manifest_log: {os.environ['MANIFEST_LOG']}")
print("")
for row in rows:
    print(f"sweep_{row['sweep']}_{row['label']}_run_log: {row['run_log']}")
    print(f"sweep_{row['sweep']}_{row['label']}_summary: {row['summary']['path']}")
    if row['summary']['array_ratio'] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_array_ratio: {row['summary']['array_ratio']:.4f}x")
    if row['summary']['dot_ratio'] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_dot_ratio: {row['summary']['dot_ratio']:.4f}x")
    print("")

if default_array:
    print(f"default_array_ratio_median: {median_or_none(default_array):.4f}x")
if variant_array:
    print(f"{variant_label}_array_ratio_median: {median_or_none(variant_array):.4f}x")
print(f"array_default_wins: {array_default_wins}/{os.environ['SWEEPS']}")
print(f"array_{variant_label}_wins: {array_variant_wins}/{os.environ['SWEEPS']}")
print(f"exact_array_pref: {exact_array_pref}")
print("")
if default_dot:
    print(f"default_dot_ratio_median: {median_or_none(default_dot):.4f}x")
if variant_dot:
    print(f"{variant_label}_dot_ratio_median: {median_or_none(variant_dot):.4f}x")
print(f"dot_default_wins: {dot_default_wins}/{os.environ['SWEEPS']}")
print(f"dot_{variant_label}_wins: {dot_variant_wins}/{os.environ['SWEEPS']}")
print(f"exact_dot_pref: {exact_dot_pref}")
print("")
if fill_pref == exact_array_pref:
    print("decision_surface_alignment: agree")
else:
    print("decision_surface_alignment: disagree")
print("note: fill_pref comes from the fill-share/setup surface; exact_* preferences come from same-tree")
print("whole-operation C-ceiling reruns on the shipped benchmark programs.")
PY

echo "${title}; summary: $summary_log"
echo "default fill wrapper log: $default_fill_wrapper_log"
echo "${variant_label} fill wrapper log: $variant_fill_wrapper_log"
