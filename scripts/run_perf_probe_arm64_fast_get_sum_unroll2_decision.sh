#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-get-sum-unroll2-decision-${ts}.log"
accept_wrapper_log="$log_dir/perf-probe-arm64-fast-get-sum-unroll2-decision-${ts}.acceptance.log"
manifest_log="$log_dir/perf-probe-arm64-fast-get-sum-unroll2-decision-${ts}.manifest.tsv"

sweeps="${OREN_ARM64_FAST_GET_SUM_UNROLL2_DECISION_SWEEPS:-3}"
run_acceptance="${OREN_ARM64_FAST_GET_SUM_UNROLL2_DECISION_RUN_ACCEPTANCE:-1}"
disabled_env="${OREN_ARM64_FAST_GET_SUM_UNROLL2_DECISION_DISABLE_ENV:-OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2=0}"

accept_summary=""
if [[ "$run_acceptance" == "1" ]]; then
    make perf-probe-arm64-fast-get-sum-unroll2-list-int >"$accept_wrapper_log" 2>&1
    accept_summary="$(python3 - "$accept_wrapper_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"summary:\s+(build/logs/perf-probe-arm64-fast-get-sum-unroll2-list-int-[^ ]+\.log)", text)
if m:
    print(m.group(1))
PY
)"
fi

: >"$manifest_log"
for sweep in $(seq 1 "$sweeps"); do
    if (( sweep % 2 == 1 )); then
        order="default disabled"
    else
        order="disabled default"
    fi
    for label in $order; do
        run_log="$log_dir/perf-probe-arm64-fast-get-sum-unroll2-decision-${ts}-${label}-s${sweep}.run.log"
        if [[ "$label" == "default" ]]; then
            env make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
        else
            env OREN_BENCH_ENV_BUILD_OREN="$disabled_env" make perf-probe-list-int-c-ceiling >"$run_log" 2>&1
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
DISABLED_ENV="$disabled_env" \
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
        key = key.strip()
        value = value.strip()
        metrics[key] = value
    return metrics


def parse_ratio_line(text, prefix):
    m = re.search(re.escape(prefix) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def parse_ceiling(path_str):
    path = Path(path_str)
    text = path.read_text(encoding="utf-8", errors="replace")
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
disabled_rows = [r for r in rows if r["label"] == "disabled"]


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
disabled_array = ratios_for("array_ratio", disabled_rows)
default_dot = ratios_for("dot_ratio", default_rows)
disabled_dot = ratios_for("dot_ratio", disabled_rows)

array_default_wins = 0
array_disabled_wins = 0
dot_default_wins = 0
dot_disabled_wins = 0
for sweep in range(1, int(os.environ["SWEEPS"]) + 1):
    d = next((r for r in default_rows if r["sweep"] == sweep), None)
    x = next((r for r in disabled_rows if r["sweep"] == sweep), None)
    if d is not None and x is not None:
        da = d["summary"].get("array_ratio")
        xa = x["summary"].get("array_ratio")
        if da is not None and xa is not None:
            if da < xa:
                array_default_wins += 1
            elif xa < da:
                array_disabled_wins += 1
        dd = d["summary"].get("dot_ratio")
        xd = x["summary"].get("dot_ratio")
        if dd is not None and xd is not None:
            if dd < xd:
                dot_default_wins += 1
            elif xd < dd:
                dot_disabled_wins += 1


def accept_pref(metrics, key):
    raw = metrics.get(key)
    if raw is None:
        return "missing"
    try:
        value = float(raw.rstrip("%"))
    except ValueError:
        return "missing"
    if value < 0:
        return "disabled"
    if value > 0:
        return "default"
    return "tie"


accept_steady_pref = accept_pref(accept_metrics, "disabled_steady_array_sum_int_native_median_delta_pct")
accept_gate_pref = accept_pref(accept_metrics, "disabled_gate_array_sum_int_native_median_delta_pct")

exact_array_pref = "tie"
if default_array and disabled_array:
    if statistics.median(default_array) < statistics.median(disabled_array):
        exact_array_pref = "default"
    elif statistics.median(disabled_array) < statistics.median(default_array):
        exact_array_pref = "disabled"

exact_dot_pref = "tie"
if default_dot and disabled_dot:
    if statistics.median(default_dot) < statistics.median(disabled_dot):
        exact_dot_pref = "default"
    elif statistics.median(disabled_dot) < statistics.median(default_dot):
        exact_dot_pref = "disabled"

print("arm64 fast get-sum unroll2 decision summary")
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"disabled_build_env: {os.environ['DISABLED_ENV']}")
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
            "disabled_steady_array_sum_int_native_median_delta_pct",
            "disabled_gate_array_sum_int_native_median_delta_pct",
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
if disabled_array:
    print(f"disabled_array_ratio_median: {median_or_none(disabled_array):.4f}x")
print(f"array_default_wins: {array_default_wins}/{os.environ['SWEEPS']}")
print(f"array_disabled_wins: {array_disabled_wins}/{os.environ['SWEEPS']}")
print(f"exact_array_pref: {exact_array_pref}")
print("")
if default_dot:
    print(f"default_dot_ratio_median: {median_or_none(default_dot):.4f}x")
if disabled_dot:
    print(f"disabled_dot_ratio_median: {median_or_none(disabled_dot):.4f}x")
print(f"dot_default_wins: {dot_default_wins}/{os.environ['SWEEPS']}")
print(f"dot_disabled_wins: {dot_disabled_wins}/{os.environ['SWEEPS']}")
print(f"exact_dot_pref: {exact_dot_pref}")
print("")
if os.environ["RUN_ACCEPTANCE"] == "1":
    agreement = "agree" if accept_steady_pref == exact_array_pref == accept_gate_pref else "disagree"
    print(f"decision_surface_alignment: {agreement}")
    print("note: acceptance_* preferences come from the local perf-gate wrapper; exact_* preferences")
    print("come from same-tree whole-operation C-ceiling reruns and are the shipped decision surface.")
PY

echo "arm64 fast get-sum unroll2 decision probe complete; summary: $summary_log"
if [[ -n "$accept_summary" ]]; then
    echo "acceptance summary: $accept_summary"
fi
echo "manifest log: $manifest_log"
