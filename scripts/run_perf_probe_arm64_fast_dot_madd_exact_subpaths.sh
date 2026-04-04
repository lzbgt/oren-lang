#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${ts}.log"
manifest_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${ts}.cases.tsv"

programs="${OREN_ARM64_FAST_DOT_MADD_EXACT_SUBPATH_PROGRAMS:-array_sum,dot_product}"
run_test="${OREN_ARM64_FAST_DOT_MADD_EXACT_SUBPATH_RUN_TEST:-0}"

run_case() {
    local label="$1"
    local env_desc="$2"
    local run_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-subpaths-${label}-${ts}.run.log"
    local status=0
    shift 2
    set +e
    env \
        OREN_ARM64_DOT_ACCEPT_PROGRAMS="$programs" \
        OREN_ARM64_DOT_ACCEPT_RUN_TEST="$run_test" \
        "$@" \
        make perf-probe-arm64-dot-acceptance >"$run_log" 2>&1
    status=$?
    set -e
    printf '%s\t%s\t%s\t%s\n' "$label" "$run_log" "$status" "$env_desc" >>"$manifest_log"
}

: >"$manifest_log"
run_case baseline "default shipped baseline"
run_case quad \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1
run_case double \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1
run_case scalar \
    "OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1" \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
    OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1

MANIFEST_LOG="$manifest_log" \
PROGRAMS="$programs" \
RUN_TEST="$run_test" \
python3 - <<'PY' >"$summary_log"
import os
import re


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def last_capture(lines, pattern):
    rgx = re.compile(pattern)
    hit = None
    for line in lines:
        m = rgx.search(line)
        if m:
            hit = m.group(1)
    return hit


def extract_value(text, key):
    m = re.search(rf"^{re.escape(key)}: ([^\n]+)$", text, re.M)
    return None if m is None else m.group(1)


print("arm64 fast-dot exact madd subpath probe summary")
print("")
print(f"programs: {os.environ['PROGRAMS']}")
print(f"run_make_test: {os.environ['RUN_TEST']}")
print("")

with open(os.environ["MANIFEST_LOG"], "r", encoding="utf-8") as f:
    rows = [line.rstrip("\n").split("\t", 3) for line in f if line.strip()]

for label, run_log, status, env_desc in rows:
    print(f"{label}:")
    print(f"  enabled_build_env: {env_desc}")
    print(f"  wrapper_log: {run_log}")
    print(f"  exit_code: {status}")
    wrapper_lines = read_lines(run_log)
    summary_path = last_capture(wrapper_lines, r"summary: (build/logs/perf-probe-arm64-dot-acceptance-[^ ]+\.summary\.log)")
    if summary_path is None:
        print("  acceptance_summary_log: unavailable")
        if status != "0":
            print("  verdict: acceptance run exited non-zero before emitting a summary")
        print("")
        continue
    print(f"  acceptance_summary_log: {summary_path}")
    summary_text = read_text(summary_path)
    for key in [
        "failed_step",
        "steady_array_sum",
        "steady_dot_product",
        "gate_array_sum",
        "gate_dot_product",
        "disasm_array_sum_insns",
        "disasm_dot_product_insns",
        "debug_status",
        "debug_exit_code",
    ]:
        value = extract_value(summary_text, key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")
PY

echo "arm64 fast-dot exact madd subpath probe complete; summary: $summary_log"
echo "case manifest: $manifest_log"
