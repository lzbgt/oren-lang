#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}.log"
shape_wrapper_log="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}.shape.run.log"
accept_manifest="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}.acceptance.tsv"
ceiling_manifest="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}.ceiling.tsv"

sweeps="${OREN_ARM64_FAST_GET_SUM_VECTOR_2D_DECISION_SWEEPS:-3}"
run_acceptance="${OREN_ARM64_FAST_GET_SUM_VECTOR_2D_DECISION_RUN_ACCEPTANCE:-1}"
enabled_env="${OREN_ARM64_FAST_GET_SUM_VECTOR_2D_DECISION_ENABLE_ENV:-OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1}"

shape_summary=""
env OREN_BENCH_ENV_BUILD_OREN="$enabled_env" \
    make perf-probe-arm64-list-int-hot-loop-disasm >"$shape_wrapper_log" 2>&1
shape_summary="$(python3 - "$shape_wrapper_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"summary:\s+(build/logs/perf-probe-arm64-list-int-hot-loop-disasm-[^ ]+\.log)", text)
if m:
    print(m.group(1))
PY
)"

: >"$accept_manifest"
if [[ "$run_acceptance" == "1" ]]; then
    for label in default enabled; do
        run_log="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}-${label}.accept.run.log"
        if [[ "$label" == "default" ]]; then
            env OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS=array_sum_int \
                OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST=0 \
                OREN_BENCH_ENV_BUILD_OREN= \
                make perf-probe-arm64-list-int-acceptance >"$run_log" 2>&1
        else
            env OREN_ARM64_LIST_INT_ACCEPT_PROGRAMS=array_sum_int \
                OREN_ARM64_LIST_INT_ACCEPT_RUN_TEST=0 \
                OREN_BENCH_ENV_BUILD_OREN="$enabled_env" \
                make perf-probe-arm64-list-int-acceptance >"$run_log" 2>&1
        fi
        summary_path="$(python3 - "$run_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"summary:\s+(build/logs/perf-probe-arm64-list-int-acceptance-[^ ]+\.summary\.log)", text)
if m:
    print(m.group(1))
PY
)"
        printf '%s\t%s\t%s\n' "$label" "$run_log" "$summary_path" >>"$accept_manifest"
    done
fi

: >"$ceiling_manifest"
for sweep in $(seq 1 "$sweeps"); do
    if (( sweep % 2 == 1 )); then
        order="default enabled"
    else
        order="enabled default"
    fi
    for label in $order; do
        run_log="$log_dir/perf-probe-arm64-fast-get-sum-vector-2d-decision-${ts}-${label}-s${sweep}.ceiling.run.log"
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
        printf '%s\t%s\t%s\t%s\n' "$sweep" "$label" "$run_log" "$summary_path" >>"$ceiling_manifest"
    done
done

ACCEPT_MANIFEST="$accept_manifest" \
CEILING_MANIFEST="$ceiling_manifest" \
ENABLED_ENV="$enabled_env" \
RUN_ACCEPTANCE="$run_acceptance" \
SHAPE_SUMMARY="$shape_summary" \
SHAPE_WRAPPER_LOG="$shape_wrapper_log" \
SWEEPS="$sweeps" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
from pathlib import Path


def read_text(path_str):
    if not path_str:
        return ""
    path = Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def parse_metric_lines(path_str):
    metrics = {}
    for raw in read_text(path_str).splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        metrics[key.strip()] = value.strip()
    return metrics


def parse_float(metrics, key):
    value = metrics.get(key)
    if value is None:
        return None
    value = value.rstrip("%")
    try:
        return float(value)
    except ValueError:
        return None


def parse_ratio_line(text, prefix):
    m = re.search(re.escape(prefix) + r"\s*([0-9.]+)x", text)
    return None if m is None else float(m.group(1))


def parse_counts(raw):
    counts = {}
    for part in raw.split():
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        try:
            counts[key] = int(value)
        except ValueError:
            pass
    return counts


def parse_shape(path_str):
    text = read_text(path_str)
    array = {}
    block_lines = []
    in_array = False
    in_snippet = False
    for raw in text.splitlines():
        if raw.strip() == "array_sum_int":
            in_array = True
            continue
        if in_array and raw and not raw.startswith(" ") and raw.strip() != "array_sum_int":
            break
        if in_array and raw.strip() == "snippet:":
            in_snippet = True
            continue
        if in_array and in_snippet:
            block_lines.append(raw)
        if not in_array or ":" not in raw:
            continue
        key, value = raw.strip().split(":", 1)
        array[key.strip()] = value.strip()
    counts = parse_counts(array.get("range_without_cold_gc_tick_counts", ""))
    counts_all = parse_counts(array.get("mnemonic_counts", ""))
    block_text = "\n".join(block_lines)
    array["q_ldr_count"] = str(len(re.findall(r"\bldr\s+q", block_text)))
    array["addp_2d_count"] = str(len(re.findall(r"\baddp\.2d\b", block_text)))
    array["fmov_count"] = str(len(re.findall(r"\bfmov\b", block_text)))
    return array, counts, counts_all


def parse_ceiling(path_str):
    text = read_text(path_str)
    return {
        "path": path_str,
        "array_ratio": parse_ratio_line(text, "oren_array_sum_int/array_slot64_vector per_rep ratio:"),
        "dot_ratio": parse_ratio_line(text, "oren_dot_product_int/dot_slot64_vector per_rep ratio:"),
    }


def pct_delta(enabled, default):
    if enabled is None or default is None or default == 0:
        return None
    return ((enabled - default) / default) * 100.0


def fmt_pct(value):
    return "missing" if value is None else f"{value:+.2f}%"


def median_or_none(values):
    return None if not values else statistics.median(values)


accept_cases = {}
accept_manifest = Path(os.environ["ACCEPT_MANIFEST"])
if accept_manifest.exists():
    for raw in accept_manifest.read_text(encoding="utf-8", errors="replace").splitlines():
        label, run_log, summary = raw.split("\t")
        accept_cases[label] = {
            "run_log": run_log,
            "summary": summary,
            "metrics": parse_metric_lines(summary),
        }

ceiling_rows = []
for raw in Path(os.environ["CEILING_MANIFEST"]).read_text(encoding="utf-8", errors="replace").splitlines():
    sweep, label, run_log, summary = raw.split("\t")
    ceiling_rows.append(
        {
            "sweep": int(sweep),
            "label": label,
            "run_log": run_log,
            "summary": parse_ceiling(summary),
        }
    )

default_rows = [r for r in ceiling_rows if r["label"] == "default"]
enabled_rows = [r for r in ceiling_rows if r["label"] == "enabled"]


def ratios_for(key, subset):
    return [row["summary"][key] for row in subset if row["summary"].get(key) is not None]


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
    if d is None or e is None:
        continue
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

shape, shape_counts, shape_counts_all = parse_shape(os.environ.get("SHAPE_SUMMARY", ""))

print("arm64 fast get-sum vector-2d decision summary")
print("")
print(f"sweeps: {os.environ['SWEEPS']}")
print(f"enabled_build_env: {os.environ['ENABLED_ENV']}")
print(f"run_acceptance: {os.environ['RUN_ACCEPTANCE']}")
print("")
print(f"shape_wrapper_log: {os.environ['SHAPE_WRAPPER_LOG']}")
print(f"shape_summary: {os.environ.get('SHAPE_SUMMARY') or 'missing'}")
for key in [
    "kind",
    "instruction_count",
    "range_without_cold_gc_tick_instruction_count",
    "cold_gc_tick_blocks",
    "cold_gc_tick_instruction_count",
    "mnemonic_counts",
    "range_without_cold_gc_tick_counts",
]:
    if key in shape:
        print(f"shape_array_sum_int_{key}: {shape[key]}")
print(f"shape_array_sum_int_q_ldr_count: {shape.get('q_ldr_count', '0')}")
print(f"shape_array_sum_int_addp_2d_count: {shape.get('addp_2d_count', '0')}")
print(f"shape_array_sum_int_fmov_count: {shape.get('fmov_count', '0')}")
print("")

if os.environ["RUN_ACCEPTANCE"] == "1":
    print(f"acceptance_manifest: {os.environ['ACCEPT_MANIFEST']}")
    for label in ["default", "enabled"]:
        case = accept_cases.get(label)
        if case is None:
            continue
        print(f"{label}_acceptance_run_log: {case['run_log']}")
        print(f"{label}_acceptance_summary: {case['summary'] or 'missing'}")
        metrics = case["metrics"]
        for key in [
            "steady_array_sum_int_native_median_s",
            "steady_array_sum_int_native_cov",
            "gate_array_sum_int_native_median_s",
            "gate_array_sum_int_native_cov",
            "gate_array_sum_int",
            "disasm_array_sum_int_insns",
        ]:
            if key in metrics:
                print(f"{label}_{key}: {metrics[key]}")
    default_metrics = accept_cases.get("default", {}).get("metrics", {})
    enabled_metrics = accept_cases.get("enabled", {}).get("metrics", {})
    for key in [
        "steady_array_sum_int_native_median_s",
        "gate_array_sum_int_native_median_s",
    ]:
        delta = pct_delta(parse_float(enabled_metrics, key), parse_float(default_metrics, key))
        print(f"enabled_{key}_delta_pct: {fmt_pct(delta)}")
    print("")

print(f"ceiling_manifest: {os.environ['CEILING_MANIFEST']}")
print("")
for row in ceiling_rows:
    print(f"sweep_{row['sweep']}_{row['label']}_ceiling_run_log: {row['run_log']}")
    print(f"sweep_{row['sweep']}_{row['label']}_ceiling_summary: {row['summary']['path'] or 'missing'}")
    if row["summary"]["array_ratio"] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_array_ratio: {row['summary']['array_ratio']:.4f}x")
    if row["summary"]["dot_ratio"] is not None:
        print(f"sweep_{row['sweep']}_{row['label']}_dot_ratio: {row['summary']['dot_ratio']:.4f}x")
    print("")

default_array_median = median_or_none(default_array)
enabled_array_median = median_or_none(enabled_array)
default_dot_median = median_or_none(default_dot)
enabled_dot_median = median_or_none(enabled_dot)
if default_array_median is not None:
    print(f"default_array_ratio_median: {default_array_median:.4f}x")
if enabled_array_median is not None:
    print(f"enabled_array_ratio_median: {enabled_array_median:.4f}x")
print(f"array_ratio_median_delta_pct: {fmt_pct(pct_delta(enabled_array_median, default_array_median))}")
print(f"array_default_wins: {array_default_wins}/{os.environ['SWEEPS']}")
print(f"array_enabled_wins: {array_enabled_wins}/{os.environ['SWEEPS']}")
print("")
if default_dot_median is not None:
    print(f"default_dot_ratio_median: {default_dot_median:.4f}x")
if enabled_dot_median is not None:
    print(f"enabled_dot_ratio_median: {enabled_dot_median:.4f}x")
print(f"dot_ratio_median_delta_pct: {fmt_pct(pct_delta(enabled_dot_median, default_dot_median))}")
print(f"dot_default_wins: {dot_default_wins}/{os.environ['SWEEPS']}")
print(f"dot_enabled_wins: {dot_enabled_wins}/{os.environ['SWEEPS']}")
print("")
print("decision_rule: promote only if vector-2d wins acceptance native medians and the same-tree array_sum_int C-ceiling ratio without destabilizing the dot control.")
PY

echo "arm64 fast get-sum vector-2d decision probe complete; summary: $summary_log"
