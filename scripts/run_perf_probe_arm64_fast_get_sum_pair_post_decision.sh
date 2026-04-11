#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-get-sum-pair-post-decision-${ts}.log"
accept_wrapper_log="$log_dir/perf-probe-arm64-fast-get-sum-pair-post-decision-${ts}.acceptance.log"
manifest_log="$log_dir/perf-probe-arm64-fast-get-sum-pair-post-decision-${ts}.manifest.tsv"

sweeps="${OREN_ARM64_FAST_GET_SUM_PAIR_POST_DECISION_SWEEPS:-3}"
run_acceptance="${OREN_ARM64_FAST_GET_SUM_PAIR_POST_DECISION_RUN_ACCEPTANCE:-1}"
enabled_env="${OREN_ARM64_FAST_GET_SUM_PAIR_POST_DECISION_ENABLE_ENV:-OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1}"

accept_summary=""
if [[ "$run_acceptance" == "1" ]]; then
    make perf-probe-arm64-fast-get-sum-pair-post-list-int >"$accept_wrapper_log" 2>&1
    accept_summary="$(python3 - "$accept_wrapper_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"summary:\s+(build/logs/perf-probe-arm64-fast-get-sum-pair-post-list-int-[^ ]+\.log)", text)
if m:
    print(m.group(1))
PY
)"
fi

: >"$manifest_log"
for sweep in $(seq 1 "$sweeps"); do
    if (( sweep % 2 == 1 )); then
        order="default enabled"
    else
        order="enabled default"
    fi
    for label in $order; do
        run_log="$log_dir/perf-probe-arm64-fast-get-sum-pair-post-decision-${ts}-${label}-s${sweep}.run.log"
        if [[ "$label" == "default" ]]; then
            env make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        else
            env OREN_BENCH_ENV_BUILD_OREN="$enabled_env" make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        fi
        summary_path="$(python3 - "$run_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"summary:\s+(build/logs/perf-probe-list-int-c-ceiling-[^ ]+\.log)", text)
if m:
    print(m.group(1))
PY
)"
        printf '%s\t%s\t%s\t%s\n' "$sweep" "$label" "$run_log" "$summary_path" >>"$manifest_log"
    done
done

ACCEPT_SUMMARY="$accept_summary" \
ACCEPT_WRAPPER_LOG="$accept_wrapper_log" \
MANIFEST_LOG="$manifest_log" \
RUN_ACCEPTANCE="$run_acceptance" \
SWEEPS="$sweeps" \
ENABLED_ENV="$enabled_env" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
from pathlib import Path


def parse_acceptance(path_str):
    if not path_str:
        return {}
    path = Path(path_str)
    if not path.exists():
        return {}
    metrics = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        metrics[key.strip()] = value.strip()
    return metrics


def parse_ratio_line(text, prefix):
    m = re.search(re.escape(prefix) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def read_summary_text(path_str):
    if not path_str:
        return ""
    path = Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def parse_ceiling(path_str):
    text = read_summary_text(path_str)
    return {
        "path": path_str,
        "array_ratio": parse_ratio_line(text, "oren_array_sum_int/array_slot64_vector per_rep ratio:"),
        "dot_ratio": parse_ratio_line(text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:"),
    }


accept_metrics = parse_acceptance(os.environ.get("ACCEPT_SUMMARY", ""))
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
enabled_rows = [r for r in rows if r["label"] == "enabled"]


def ratios_for(key, subset):
    return [row["summary"][key] for row in subset if row["summary"].get(key) is not None]


def median_or_none(values):
    return None if not values else statistics.median(values)


default_array = ratios_for("array_ratio", default_rows)
enabled_array = ratios_for("array_ratio", enabled_rows)
default_dot = ratios_for("dot_ratio", default_rows)
enabled_dot = ratios_for("dot_ratio", enabled_rows)

array_default_wins = 0
array_enabled_wins = 0
dot_default_wins = 0
dot_enabled_wins = 0
for sweep in range(1, int(os.environ["SWEEPS"]) + 1):
    d = next((r for r in default_rows if r["sweep"] == sweep), None)
    e = next((r for r in enabled_rows if r["sweep"] == sweep), None)
    if d is not None and e is not None:
        da = d["summary"].get("array_ratio")
        ea = e["summary"].get("array_ratio")
        if da is not None and ea is not None:
            if da < ea:
                array_default_wins += 1
            elif ea < da:
                array_enabled_wins += 1
        dd = d["summary"].get("dot_ratio")
        ed = e["summary"].get("dot_ratio")
        if dd is not None and ed is not None:
            if dd < ed:
                dot_default_wins += 1
            elif ed < dd:
                dot_enabled_wins += 1


def accept_pref(metrics, key):
    raw = metrics.get(key)
    if raw is None:
        return "missing"
    try:
        value = float(raw.rstrip("%"))
    except ValueError:
        return "missing"
    if value < 0:
        return "enabled"
    if value > 0:
        return "default"
    return "tie"


accept_steady_pref = accept_pref(accept_metrics, "enabled_steady_array_sum_int_native_median_delta_pct")
accept_gate_pref = accept_pref(accept_metrics, "enabled_gate_array_sum_int_native_median_delta_pct")

exact_array_pref = "tie"
if default_array and enabled_array:
    if statistics.median(default_array) < statistics.median(enabled_array):
        exact_array_pref = "default"
    elif statistics.median(enabled_array) < statistics.median(default_array):
        exact_array_pref = "enabled"

exact_dot_pref = "tie"
if default_dot and enabled_dot:
    if statistics.median(default_dot) < statistics.median(enabled_dot):
        exact_dot_pref = "default"
    elif statistics.median(enabled_dot) < statistics.median(default_dot):
        exact_dot_pref = "enabled"

print("arm64 fast get-sum pair-post decision summary")
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"enabled_build_env: {os.environ['ENABLED_ENV']}")
print(f"run_acceptance: {os.environ['RUN_ACCEPTANCE']}")
print("")
if os.environ["RUN_ACCEPTANCE"] == "1":
    print(f"acceptance_wrapper_log: {os.environ['ACCEPT_WRAPPER_LOG']}")
    if os.environ.get("ACCEPT_SUMMARY"):
        print(f"acceptance_summary: {os.environ['ACCEPT_SUMMARY']}")
        for key in [
            "steady_array_sum_int",
            "steady_array_sum_int_native_median_s",
            "steady_array_sum_int_native_cov",
            "gate_array_sum_int",
            "gate_array_sum_int_native_median_s",
            "gate_array_sum_int_native_cov",
            "disasm_array_sum_int_insns",
            "enabled_steady_array_sum_int_native_median_delta_pct",
            "enabled_gate_array_sum_int_native_median_delta_pct",
        ]:
            value = accept_metrics.get(key)
            if value is not None:
                print(f"{key}: {value}")
        print(f"acceptance_steady_pref: {accept_steady_pref}")
        print(f"acceptance_gate_pref: {accept_gate_pref}")
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

if default_array:
    print(f"default_array_ratio_median: {median_or_none(default_array):.4f}x")
if enabled_array:
    print(f"enabled_array_ratio_median: {median_or_none(enabled_array):.4f}x")
print(f"array_default_wins: {array_default_wins}/{os.environ['SWEEPS']}")
print(f"array_enabled_wins: {array_enabled_wins}/{os.environ['SWEEPS']}")
print(f"exact_array_pref: {exact_array_pref}")
print("")
if default_dot:
    print(f"default_dot_ratio_median: {median_or_none(default_dot):.4f}x")
if enabled_dot:
    print(f"enabled_dot_ratio_median: {median_or_none(enabled_dot):.4f}x")
print(f"dot_default_wins: {dot_default_wins}/{os.environ['SWEEPS']}")
print(f"dot_enabled_wins: {dot_enabled_wins}/{os.environ['SWEEPS']}")
print(f"exact_dot_pref: {exact_dot_pref}")
print("")
if os.environ["RUN_ACCEPTANCE"] == "1":
    agreement = "agree" if accept_steady_pref == exact_array_pref == accept_gate_pref else "disagree"
    print(f"decision_surface_alignment: {agreement}")
    print("note: acceptance_* preferences come from the local get-sum-only perf-gate wrapper;")
    print("exact_* preferences come from same-tree whole-operation C-ceiling reruns and are the")
    print("shipped decision surface for this arm64 get-sum branch.")
PY

echo "arm64 fast get-sum pair-post decision probe complete; summary: $summary_log"
