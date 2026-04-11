#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

tag="perf-probe-arm64-fast-dot-prefix-pair-loop-decision"
summary_log="$log_dir/${tag}-${ts}.log"
generic_log="$log_dir/${tag}-generic-${ts}.run.log"
list_int_log="$log_dir/${tag}-list-int-${ts}.run.log"
enable_env="${OREN_ARM64_FAST_DOT_PREFIX_PAIR_LOOP_DECISION_ENABLE_ENV:-OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1}"

run_capture() {
    local run_log="$1"
    shift
    local rc=0
    if "$@" >"$run_log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    printf '%s\n' "$rc"
}

generic_rc="$(run_capture "$generic_log" env \
    OREN_ARM64_FAST_DOT_PREFIX_ZERO_ENABLE_ENV="$enable_env" \
    make perf-probe-arm64-fast-dot-prefix-zero)"

list_int_rc="$(run_capture "$list_int_log" env \
    OREN_ARM64_FAST_DOT_PREFIX_ZERO_LIST_INT_ENABLE_ENV="$enable_env" \
    make perf-probe-arm64-fast-dot-prefix-zero-list-int)"

GENERIC_LOG="$generic_log" \
GENERIC_RC="$generic_rc" \
LIST_INT_LOG="$list_int_log" \
LIST_INT_RC="$list_int_rc" \
ENABLE_ENV="$enable_env" \
python3 - <<'PY' >"$summary_log"
import os
import re


def summary_path(run_log, prefix):
    pat = re.compile(rf"summary: (build/logs/{re.escape(prefix)}[^\s]+\.log)")
    path = None
    with open(run_log, "r", encoding="utf-8") as f:
        for raw in f:
            m = pat.search(raw.rstrip("\n"))
            if m:
                path = m.group(1)
    return path


def parse_summary(path):
    metrics = {}
    if path is None or not os.path.exists(path):
        return metrics
    metric_re = re.compile(r"^([a-z0-9_]+): (.+)$")
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            m = metric_re.match(raw.rstrip("\n"))
            if m:
                metrics[m.group(1)] = m.group(2)
    return metrics


def pct(metrics, key):
    raw = metrics.get(key)
    if raw is None:
        return None
    try:
        return float(raw.rstrip("%"))
    except ValueError:
        return None


def fmt(value):
    if value is None:
        return "missing"
    return f"{value:+.2f}%"


cases = [
    (
        "generic",
        os.environ["GENERIC_LOG"],
        os.environ["GENERIC_RC"],
        "perf-probe-arm64-fast-dot-prefix-zero-",
        "dot_product",
    ),
    (
        "list_int",
        os.environ["LIST_INT_LOG"],
        os.environ["LIST_INT_RC"],
        "perf-probe-arm64-fast-dot-prefix-zero-list-int-",
        "dot_product_int",
    ),
]

parsed = []
for label, run_log, rc, prefix, program in cases:
    path = summary_path(run_log, prefix)
    metrics = parse_summary(path)
    steady_key = f"steady_{program}_native_median_delta_pct"
    gate_key = f"gate_{program}_native_median_delta_pct"
    parsed.append(
        {
            "label": label,
            "program": program,
            "run_log": run_log,
            "wrapper_rc": rc,
            "summary": path,
            "metrics": metrics,
            "steady_delta": pct(metrics, steady_key),
            "gate_delta": pct(metrics, gate_key),
        }
    )

print("arm64 fast dot prefix pair-loop decision summary")
print("")
print(f"enabled_build_env: {os.environ['ENABLE_ENV']}")
print("")

all_win = True
for item in parsed:
    metrics = item["metrics"]
    program = item["program"]
    steady_delta = item["steady_delta"]
    gate_delta = item["gate_delta"]
    if steady_delta is None or steady_delta >= 0.0 or gate_delta is None or gate_delta >= 0.0:
        all_win = False
    print(f"{item['label']}:")
    print(f"  wrapper_log: {item['run_log']}")
    print(f"  wrapper_exit_code: {item['wrapper_rc']}")
    print(f"  summary: {item['summary'] or 'missing'}")
    for key in [
        f"steady_{program}",
        f"steady_{program}_native_median_s",
        f"gate_{program}",
        f"gate_{program}_native_median_s",
        f"disasm_{program}_insns",
    ]:
        if key in metrics:
            print(f"  {key}: {metrics[key]}")
    print(f"  steady_native_delta: {fmt(steady_delta)}")
    print(f"  gate_native_delta: {fmt(gate_delta)}")
    print("")

print(f"candidate_simple_surface_win: {'yes' if all_win else 'no'}")
if all_win:
    print("decision: pair-loop candidate clears this simple generic + explicit prefix-zero surface; run broader read-split/gate stability before any default flip.")
else:
    print("decision: keep the pair-loop candidate opt-in on this simple surface; it must improve both generic and explicit steady/gate native medians before broader promotion work.")
PY

echo "arm64 fast dot prefix pair-loop decision probe complete; summary: $summary_log"
echo "generic wrapper log: $generic_log"
echo "list<int> wrapper log: $list_int_log"

if [[ "$generic_rc" != "0" ]]; then
    echo "generic prefix pair-loop leg failed (exit=$generic_rc)"
    exit "$generic_rc"
fi
if [[ "$list_int_rc" != "0" ]]; then
    echo "list<int> prefix pair-loop leg failed (exit=$list_int_rc)"
    exit "$list_int_rc"
fi
