#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-fill-share-decision-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-fill-share-decision-${ts}.log"
breakdown_wrapper_log="$log_dir/perf-probe-list-int-fill-share-decision-${ts}.breakdown-wrapper.log"

runs="${OREN_LIST_INT_FILL_SHARE_DECISION_RUNS:-5}"
warmups="${OREN_LIST_INT_FILL_SHARE_DECISION_WARMUPS:-1}"
n="${OREN_LIST_INT_FILL_SHARE_DECISION_N:-2000000}"
fill_reps="${OREN_LIST_INT_FILL_SHARE_DECISION_FILL_REPS:-10}"
breakdown_short_reps="${OREN_LIST_INT_FILL_SHARE_DECISION_BREAKDOWN_SHORT_REPS:-1}"
breakdown_long_reps="${OREN_LIST_INT_FILL_SHARE_DECISION_BREAKDOWN_LONG_REPS:-100}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_use_cache="${OREN_PERF_BUILD_USE_CACHE:-0}"

bench_cc="${OREN_BENCH_CC:-cc}"
scalar_flags=()
if "$bench_cc" --version 2>/dev/null | rg -qi 'clang'; then
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
elif "$bench_cc" --version 2>/dev/null | rg -qi 'gcc'; then
    scalar_flags=(-fno-tree-vectorize -fno-tree-slp-vectorize)
else
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
fi

perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")
perf_build_cache_args

oren_fill_bin="$tmp_dir/fill_list_int_oren_native"
c_fill_slot_vector_bin="$tmp_dir/fill_list_int_slot64_vector"
c_fill_slot_scalar_bin="$tmp_dir/fill_list_int_slot64_scalar"

build_fill_cmd=(./oren_stage2 build benchmarks/fill_list_int/fill_list_int.oren --backend native --no-debug "${PERF_BUILD_CACHE_ARGS[@]}" -o "$oren_fill_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_fill_cmd[@]}" >"$tmp_dir/fill_list_int_oren_native.build.log" 2>&1
else
    "${build_fill_cmd[@]}" >"$tmp_dir/fill_list_int_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$c_fill_slot_vector_bin" benchmarks/fill_list_int/fill_list_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$c_fill_slot_scalar_bin" benchmarks/fill_list_int/fill_list_int.c

env \
    OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_RUNS="$runs" \
    OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_WARMUPS="$warmups" \
    OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_N="$n" \
    OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_SHORT_REPS="$breakdown_short_reps" \
    OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_LONG_REPS="$breakdown_long_reps" \
    OREN_BENCH_ENV_BUILD_OREN="$build_env_raw" \
    ./scripts/run_perf_probe_list_int_array_sum_c_breakdown.sh >"$breakdown_wrapper_log" 2>&1

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
FILL_REPS="$fill_reps" \
OREN_FILL_BIN="$oren_fill_bin" \
C_FILL_SLOT_VECTOR_BIN="$c_fill_slot_vector_bin" \
C_FILL_SLOT_SCALAR_BIN="$c_fill_slot_scalar_bin" \
BREAKDOWN_WRAPPER_LOG="$breakdown_wrapper_log" \
BUILD_ENV="$build_env_raw" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
CC_BIN="$bench_cc" \
SCALAR_FLAGS="${scalar_flags[*]}" \
python3 - <<'PY' >"$summary_log"
import os
import re
import statistics
import subprocess
import time
from pathlib import Path

runs = int(os.environ["RUNS"])
warmups = int(os.environ["WARMUPS"])
n = os.environ["N"]
fill_reps = int(os.environ["FILL_REPS"])
breakdown_wrapper_log = Path(os.environ["BREAKDOWN_WRAPPER_LOG"])


def parse_breakdown_summary_path(wrapper_log):
    text = wrapper_log.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"summary:\s+(build/logs/perf-probe-list-int-array-sum-c-breakdown-[^ ]+\.log)", text)
    if m is None:
        raise SystemExit(f"missing breakdown summary path in {wrapper_log}")
    return Path(m.group(1))


def parse_breakdown(summary_path):
    lines = summary_path.read_text(encoding="utf-8", errors="replace").splitlines()
    data = {}
    section = None
    for raw in lines:
        line = raw.rstrip("\n")
        if not line:
            continue
        if line.endswith(":") and not line.startswith("ratio_summary"):
            section = line[:-1]
            data[section] = {}
            continue
        if line.startswith("ratio_summary:"):
            section = None
            data["ratio_summary"] = {}
            continue
        if line.startswith("  ") and section is not None and ":" in line:
            key, value = line.strip().split(":", 1)
            data[section][key.strip()] = value.strip()
        elif section is None and " ratio:" in line:
            key, value = line.split(" ratio:", 1)
            data["ratio_summary"][key.strip()] = value.strip()
    return data


def run_one(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    return proc.stdout.strip()


def time_cmd(path):
    cmd = [path, n, str(fill_reps)]
    expected = None
    for _ in range(warmups):
        out = run_one(cmd)
        if expected is None:
            expected = out
    samples = []
    for _ in range(runs):
        t0 = time.perf_counter()
        out = run_one(cmd)
        dt = time.perf_counter() - t0
        if expected is None:
            expected = out
        elif out != expected:
            raise SystemExit(f"stdout mismatch for {path}: expected {expected!r}, got {out!r}")
        samples.append(dt)
    mean = statistics.mean(samples)
    cov = 0.0
    if len(samples) >= 2 and mean != 0.0:
        cov = statistics.stdev(samples) / mean
    med = statistics.median(samples)
    return {
        "stdout": expected,
        "median_s": med,
        "cov": cov,
        "per_rep_s": med / fill_reps,
    }


def parse_float(text):
    if text is None:
        return None
    text = text.strip()
    if text.endswith("x"):
        text = text[:-1]
    return float(text)


breakdown_summary = parse_breakdown_summary_path(breakdown_wrapper_log)
breakdown = parse_breakdown(breakdown_summary)

oren_fill = time_cmd(os.environ["OREN_FILL_BIN"])
c_fill_slot_vector = time_cmd(os.environ["C_FILL_SLOT_VECTOR_BIN"])
c_fill_slot_scalar = time_cmd(os.environ["C_FILL_SLOT_SCALAR_BIN"])

oren_array = breakdown["oren_array_sum_int_canonical"]
c_array_slot_vector = breakdown["c_array_sum_slot64_vector"]
c_array_slot_scalar = breakdown["c_array_sum_slot64_scalar"]

oren_array_setup_est = parse_float(oren_array.get("setup_est_s"))
oren_array_steady = parse_float(oren_array.get("steady_per_rep_s"))
c_array_slot_vector_setup = parse_float(c_array_slot_vector.get("setup_est_s"))
c_array_slot_vector_steady = parse_float(c_array_slot_vector.get("steady_per_rep_s"))
c_array_slot_scalar_setup = parse_float(c_array_slot_scalar.get("setup_est_s"))

print("list<int> array_sum fill-share decision probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print(f"cc: {os.environ['CC_BIN']}")
print(f"scalar_flags: {os.environ['SCALAR_FLAGS']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print(f"fill_reps: {fill_reps}")
print(f"array_sum_breakdown_wrapper: {breakdown_wrapper_log}")
print(f"array_sum_breakdown_summary: {breakdown_summary}")
print("")

print("oren_fill_list_int:")
print(f"  median_s: {oren_fill['median_s']:.6f}")
print(f"  per_rep_s: {oren_fill['per_rep_s']:.6f}")
print(f"  cov: {oren_fill['cov']:.4f}")
print(f"  stdout: {oren_fill['stdout']}")
print("")
print("c_fill_list_int_slot64_vector:")
print(f"  median_s: {c_fill_slot_vector['median_s']:.6f}")
print(f"  per_rep_s: {c_fill_slot_vector['per_rep_s']:.6f}")
print(f"  cov: {c_fill_slot_vector['cov']:.4f}")
print(f"  stdout: {c_fill_slot_vector['stdout']}")
print("")
print("c_fill_list_int_slot64_scalar:")
print(f"  median_s: {c_fill_slot_scalar['median_s']:.6f}")
print(f"  per_rep_s: {c_fill_slot_scalar['per_rep_s']:.6f}")
print(f"  cov: {c_fill_slot_scalar['cov']:.4f}")
print(f"  stdout: {c_fill_slot_scalar['stdout']}")
print("")

print("array_sum_breakdown_excerpt:")
for label, section in [
    ("c_array_sum_slot64_vector", c_array_slot_vector),
    ("c_array_sum_slot64_scalar", c_array_slot_scalar),
    ("oren_array_sum_int_canonical", oren_array),
]:
    print(f"{label}:")
    for key in [
        "setup_est_s",
        "steady_per_rep_s",
        "long_per_rep_s",
        "short_s",
        "long_s",
    ]:
        value = section.get(key)
        if value is not None:
            print(f"  {key}: {value}")
    print("")

print("derived:")
print(f"oren_fill_list_int/c_fill_slot64_vector per_rep ratio: {(oren_fill['per_rep_s'] / c_fill_slot_vector['per_rep_s']):.4f}x")
print(f"oren_fill_list_int/c_fill_slot64_scalar per_rep ratio: {(oren_fill['per_rep_s'] / c_fill_slot_scalar['per_rep_s']):.4f}x")
if oren_array_setup_est is not None:
    print(f"oren_fill_list_int/oren_array_sum_setup_est ratio: {(oren_fill['per_rep_s'] / oren_array_setup_est):.4f}x")
if c_array_slot_vector_setup is not None:
    print(f"oren_fill_list_int/c_array_sum_slot64_vector_setup ratio: {(oren_fill['per_rep_s'] / c_array_slot_vector_setup):.4f}x")
if c_array_slot_scalar_setup is not None:
    print(f"oren_fill_list_int/c_array_sum_slot64_scalar_setup ratio: {(oren_fill['per_rep_s'] / c_array_slot_scalar_setup):.4f}x")
if oren_array_steady is not None:
    print(f"oren_fill_list_int/oren_array_sum_steady_per_rep ratio: {(oren_fill['per_rep_s'] / oren_array_steady):.4f}x")
if c_array_slot_vector_steady is not None:
    print(f"oren_array_sum/c_array_sum_slot64_vector steady_per_rep ratio: {(oren_array_steady / c_array_slot_vector_steady):.4f}x")
    print(f"oren_fill_list_int/c_array_sum_slot64_vector steady_per_rep ratio: {(oren_fill['per_rep_s'] / c_array_slot_vector_steady):.4f}x")

fill_reweights_to_setup = "unknown"
if oren_array_setup_est is not None:
    if oren_fill["per_rep_s"] >= oren_array_setup_est * 0.8:
        fill_reweights_to_setup = "fill_dominates_setup"
    elif oren_fill["per_rep_s"] <= oren_array_setup_est * 0.3:
        fill_reweights_to_setup = "fill_is_minor_setup_component"
    else:
        fill_reweights_to_setup = "fill_is_material_but_not_most_setup"

remaining_blocker = "unknown"
if oren_array_steady is not None:
    if oren_fill["per_rep_s"] < oren_array_steady:
        remaining_blocker = "steady_read_path_still_larger"
    else:
        remaining_blocker = "fill_path_is_at_least_as_large"

print(f"setup_reweighting: {fill_reweights_to_setup}")
print(f"remaining_blocker_shape: {remaining_blocker}")
print("")
print("note: this probe pairs a new single-list list<int> fill-only benchmark with the exact")
print("array_sum breakdown surface so the repo can compare fill-only whole-operation cost against")
print("the current setup estimate and repeated-read steady cost on the same shipped tree.")
PY

echo "list<int> array_sum fill-share decision probe complete; summary: $summary_log"
