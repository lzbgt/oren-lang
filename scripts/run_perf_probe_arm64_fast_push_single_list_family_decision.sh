#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

tag="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_TAG:-perf-probe-arm64-fast-push-single-list-family-decision}"
title="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_TITLE:-arm64 fast list<int> push single-list family decision summary}"
variant_label="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_VARIANT_LABEL:-disabled}"
variant_env="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_VARIANT_ENV:-OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4=0}"
causal_programs="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_CAUSAL_PROGRAMS:-array_sum_int,array_sum_int_step7}"
control_programs="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_CONTROL_PROGRAMS:-dot_product_int}"
sweeps="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_SWEEPS:-3}"
steady_runs="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_STEADY_RUNS:-3}"
steady_warmups="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_STEADY_WARMUPS:-1}"
steady_n="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_N:-2000000}"
steady_reps="${OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_REPS:-100}"
perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"

summary_log="$log_dir/${tag}-${ts}.log"
default_fill_wrapper_log="$log_dir/${tag}-${ts}.default-fill.log"
variant_fill_wrapper_log="$log_dir/${tag}-${ts}.${variant_label}-fill.log"
manifest_log="$log_dir/${tag}-${ts}.manifest.tsv"

all_programs="$causal_programs"
if [[ -n "$control_programs" ]]; then
    all_programs="${all_programs},${control_programs}"
fi

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
            env \
                OREN_PERF_SMOKE_LIST_INT=0 \
                OREN_BENCH_PROGRAMS="$all_programs" \
                OREN_BENCH_RUNS="$steady_runs" \
                OREN_BENCH_WARMUPS="$steady_warmups" \
                OREN_BENCH_LIST_INT_STEADY_N="$steady_n" \
                OREN_BENCH_LIST_INT_STEADY_REPS="$steady_reps" \
                OREN_BENCH_SKIP_OREN_C=1 \
                make perf-gate-list-int-steady >"$run_log" 2>&1
        else
            env \
                OREN_BENCH_ENV_BUILD_OREN="$variant_env" \
                OREN_PERF_SMOKE_LIST_INT=0 \
                OREN_BENCH_PROGRAMS="$all_programs" \
                OREN_BENCH_RUNS="$steady_runs" \
                OREN_BENCH_WARMUPS="$steady_warmups" \
                OREN_BENCH_LIST_INT_STEADY_N="$steady_n" \
                OREN_BENCH_LIST_INT_STEADY_REPS="$steady_reps" \
                OREN_BENCH_SKIP_OREN_C=1 \
                make perf-gate-list-int-steady >"$run_log" 2>&1
        fi
        summary_path="$(extract_summary_path "$run_log" "perf-gate-list-int-steady-")"
        printf '%s\t%s\t%s\t%s\n' "$sweep" "$label" "$run_log" "$summary_path" >>"$manifest_log"
    done
done

DEFAULT_FILL_WRAPPER_LOG="$default_fill_wrapper_log" \
DEFAULT_FILL_SUMMARY="$default_fill_summary" \
VARIANT_FILL_WRAPPER_LOG="$variant_fill_wrapper_log" \
VARIANT_FILL_SUMMARY="$variant_fill_summary" \
MANIFEST_LOG="$manifest_log" \
CAUSAL_PROGRAMS="$causal_programs" \
CONTROL_PROGRAMS="$control_programs" \
ALL_PROGRAMS="$all_programs" \
SWEEPS="$sweeps" \
VARIANT_ENV="$variant_env" \
VARIANT_LABEL="$variant_label" \
TITLE="$title" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
STEADY_RUNS="$steady_runs" \
STEADY_WARMUPS="$steady_warmups" \
STEADY_N="$steady_n" \
STEADY_REPS="$steady_reps" \
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


def parse_steady(path_str):
    text = read_summary_text(path_str)
    metrics = {}
    current_program = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped:
            continue
        if not line.startswith(" ") and "summary:" not in stripped and ":" not in stripped:
            current_program = stripped
            continue
        if current_program is None:
            continue
        m = re.search(r"native/C steady ratio≈([0-9.]+)x", stripped)
        if m:
            metrics[current_program] = float(m.group(1))
    return {"path": path_str, "ratios": metrics}


def median_or_none(values):
    return None if not values else statistics.median(values)


def pref(default_values, variant_values, variant_label):
    if not default_values or not variant_values:
        return "missing"
    default_med = statistics.median(default_values)
    variant_med = statistics.median(variant_values)
    if default_med < variant_med:
        return "default"
    if variant_med < default_med:
        return variant_label
    return "tie"


def group_pref(programs, medians, variant_label):
    prefs = []
    for program in programs:
        data = medians.get(program)
        if data is None:
            continue
        p = pref(data["default"], data[variant_label], variant_label)
        if p != "missing":
            prefs.append(p)
    if not prefs:
        return "missing"
    if all(p == "default" for p in prefs):
        return "default"
    if all(p == variant_label for p in prefs):
        return variant_label
    if all(p == "tie" for p in prefs):
        return "tie"
    return "mixed"


default_fill = parse_fill(os.environ["DEFAULT_FILL_SUMMARY"])
variant_fill = parse_fill(os.environ["VARIANT_FILL_SUMMARY"])
variant_label = os.environ["VARIANT_LABEL"]
causal_programs = [p for p in os.environ["CAUSAL_PROGRAMS"].split(",") if p]
control_programs = [p for p in os.environ["CONTROL_PROGRAMS"].split(",") if p]
all_programs = [p for p in os.environ["ALL_PROGRAMS"].split(",") if p]

rows = []
for raw in Path(os.environ["MANIFEST_LOG"]).read_text(encoding="utf-8", errors="replace").splitlines():
    sweep, label, run_log, summary = raw.split("\t")
    rows.append(
        {
            "sweep": int(sweep),
            "label": label,
            "run_log": run_log,
            "summary": parse_steady(summary),
        }
    )

default_rows = [r for r in rows if r["label"] == "default"]
variant_rows = [r for r in rows if r["label"] == variant_label]

program_values = {}
for program in all_programs:
    program_values[program] = {"default": [], variant_label: []}
for row in rows:
    for program in all_programs:
        value = row["summary"]["ratios"].get(program)
        if value is not None:
            program_values[program][row["label"]].append(value)

wins = {
    program: {"default": 0, variant_label: 0}
    for program in all_programs
}
for sweep in range(1, int(os.environ["SWEEPS"]) + 1):
    d = next((r for r in default_rows if r["sweep"] == sweep), None)
    x = next((r for r in variant_rows if r["sweep"] == sweep), None)
    if d is None or x is None:
        continue
    for program in all_programs:
        dv = d["summary"]["ratios"].get(program)
        xv = x["summary"]["ratios"].get(program)
        if dv is None or xv is None:
            continue
        if dv < xv:
            wins[program]["default"] += 1
        elif xv < dv:
            wins[program][variant_label] += 1

fill_pref = "tie"
if default_fill["fill_vs_c_vector"] is not None and variant_fill["fill_vs_c_vector"] is not None:
    if default_fill["fill_vs_c_vector"] < variant_fill["fill_vs_c_vector"]:
        fill_pref = "default"
    elif variant_fill["fill_vs_c_vector"] < default_fill["fill_vs_c_vector"]:
        fill_pref = variant_label

causal_pref = group_pref(causal_programs, program_values, variant_label)
control_pref = group_pref(control_programs, program_values, variant_label)

print(os.environ["TITLE"])
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"variant_label: {variant_label}")
print(f"variant_build_env: {os.environ['VARIANT_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print(f"causal_programs: {', '.join(causal_programs)}")
print(f"control_programs: {', '.join(control_programs) if control_programs else '(none)'}")
print(f"steady_runs: {os.environ['STEADY_RUNS']}")
print(f"steady_warmups: {os.environ['STEADY_WARMUPS']}")
print(f"steady_n: {os.environ['STEADY_N']}")
print(f"steady_reps: {os.environ['STEADY_REPS']}")
print("")
print(f"default_fill_wrapper_log: {os.environ['DEFAULT_FILL_WRAPPER_LOG']}")
print(f"default_fill_summary: {default_fill['path']}")
print(f"{variant_label}_fill_wrapper_log: {os.environ['VARIANT_FILL_WRAPPER_LOG']}")
print(f"{variant_label}_fill_summary: {variant_fill['path']}")
print("")
for label, metrics in [("default", default_fill), (variant_label, variant_fill)]:
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
    for program in all_programs:
        value = row["summary"]["ratios"].get(program)
        if value is not None:
            print(f"sweep_{row['sweep']}_{row['label']}_{program}_native_c_ratio: {value:.4f}x")
    print("")

for program in all_programs:
    data = program_values[program]
    default_med = median_or_none(data["default"])
    variant_med = median_or_none(data[variant_label])
    if default_med is not None:
        print(f"default_{program}_native_c_ratio_median: {default_med:.4f}x")
    if variant_med is not None:
        print(f"{variant_label}_{program}_native_c_ratio_median: {variant_med:.4f}x")
    print(f"{program}_default_wins: {wins[program]['default']}/{os.environ['SWEEPS']}")
    print(f"{program}_{variant_label}_wins: {wins[program][variant_label]}/{os.environ['SWEEPS']}")
    print(f"{program}_pref: {pref(data['default'], data[variant_label], variant_label)}")
    print("")

print(f"causal_pref: {causal_pref}")
print(f"control_pref: {control_pref}")
if fill_pref == causal_pref:
    print("decision_surface_alignment: agree")
else:
    print("decision_surface_alignment: disagree")
print("note: fill_pref comes from the fill-share/setup surface; causal_pref is computed only from")
print("the exact single-list benchmark family, while control_pref is reported separately for structurally")
print("ineligible exact programs such as multi-push dot surfaces.")
PY

echo "${title}; summary: $summary_log"
echo "default fill wrapper log: $default_fill_wrapper_log"
echo "${variant_label} fill wrapper log: $variant_fill_wrapper_log"
