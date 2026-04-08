#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-i32-buf-read-split-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-i32-buf-read-split-${ts}.log"
i32_buf_short_log="$log_dir/perf-probe-list-int-i32-buf-read-split-i32-buf-short-${ts}.run.log"
i32_buf_long_log="$log_dir/perf-probe-list-int-i32-buf-read-split-i32-buf-long-${ts}.run.log"
canonical_short_log="$log_dir/perf-probe-list-int-i32-buf-read-split-canonical-short-${ts}.run.log"
canonical_long_log="$log_dir/perf-probe-list-int-i32-buf-read-split-canonical-long-${ts}.run.log"

runs="${OREN_LIST_INT_I32_BUF_READ_SPLIT_RUNS:-3}"
warmups="${OREN_LIST_INT_I32_BUF_READ_SPLIT_WARMUPS:-0}"
n="${OREN_LIST_INT_I32_BUF_READ_SPLIT_N:-200000}"
short_reps="${OREN_LIST_INT_I32_BUF_READ_SPLIT_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_I32_BUF_READ_SPLIT_LONG_REPS:-20}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
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

packed_vector_bin="$tmp_dir/dot_product_c_vector"
packed_scalar_bin="$tmp_dir/dot_product_c_scalar"
oren_i32_buf_bin="$tmp_dir/dot_product_i32_buf_oren_native"
oren_canonical_bin="$tmp_dir/dot_product_int_oren_native"

build_i32_buf_cmd=(./oren_stage2 build benchmarks/dot_product_i32_buf/dot_product_i32_buf.oren --backend native --no-debug --no-cache -o "$oren_i32_buf_bin")
build_canonical_cmd=(./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug --no-cache -o "$oren_canonical_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
else
    "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
    "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$packed_vector_bin" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$packed_scalar_bin" benchmarks/dot_product_int/dot_product_int.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
PACKED_VECTOR_BIN="$packed_vector_bin" \
PACKED_SCALAR_BIN="$packed_scalar_bin" \
OREN_I32_BUF_BIN="$oren_i32_buf_bin" \
OREN_CANONICAL_BIN="$oren_canonical_bin" \
BUILD_ENV="$build_env_raw" \
I32_BUF_SHORT_LOG="$i32_buf_short_log" \
I32_BUF_LONG_LOG="$i32_buf_long_log" \
CANONICAL_SHORT_LOG="$canonical_short_log" \
CANONICAL_LONG_LOG="$canonical_long_log" \
python3 - <<'PY' >"$summary_log"
import json
import os
import statistics
import subprocess
import time
from pathlib import Path

runs = int(os.environ["RUNS"])
warmups = int(os.environ["WARMUPS"])
n = os.environ["N"]
short_reps = int(os.environ["SHORT_REPS"])
long_reps = int(os.environ["LONG_REPS"])
if long_reps <= short_reps:
    raise SystemExit("LONG_REPS must be greater than SHORT_REPS")
delta_reps = long_reps - short_reps


def time_cmd(path, reps, extra_env=None):
    cmd = [path, n, str(reps)]
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    expected = None
    samples = []
    for _ in range(warmups):
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True, env=env)
        text = out.stdout.strip()
        if expected is None:
            expected = text
    for _ in range(runs):
        t0 = time.perf_counter()
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True, env=env)
        dt = time.perf_counter() - t0
        text = out.stdout.strip()
        if expected is None:
            expected = text
        elif text != expected:
            raise SystemExit(f"stdout mismatch for {path}: expected {expected!r}, got {text!r}")
        samples.append(dt)
    mean = statistics.mean(samples)
    cov = 0.0
    if len(samples) >= 2 and mean != 0.0:
        cov = statistics.stdev(samples) / mean
    return {
        "stdout": expected,
        "median_s": statistics.median(samples),
        "cov": cov,
    }


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def summarize_pair(short_data, long_data):
    steady = (long_data["median_s"] - short_data["median_s"]) / delta_reps
    setup = short_data["median_s"] - steady * short_reps
    long_per_rep = long_data["median_s"] / long_reps
    return {
        "short": short_data,
        "long": long_data,
        "delta_per_rep_s": steady,
        "setup_s": setup,
        "long_per_rep_s": long_per_rep,
        "setup_share_of_long": 0.0 if long_data["median_s"] == 0.0 else setup / long_data["median_s"],
    }


cases = {
    "c_packed_vector": {
        "path": os.environ["PACKED_VECTOR_BIN"],
        "extra_env": None,
    },
    "c_packed_scalar": {
        "path": os.environ["PACKED_SCALAR_BIN"],
        "extra_env": None,
    },
    "oren_i32_buf_scalar": {
        "path": os.environ["OREN_I32_BUF_BIN"],
        "extra_env": {"OREN_NO_SIMD": "1"},
    },
    "oren_i32_buf_simd": {
        "path": os.environ["OREN_I32_BUF_BIN"],
        "extra_env": {"OREN_ENABLE_SIMD": "1"},
    },
    "oren_native_canonical": {
        "path": os.environ["OREN_CANONICAL_BIN"],
        "extra_env": None,
    },
}

results = {}
for name, spec in cases.items():
    short_data = time_cmd(spec["path"], short_reps, spec["extra_env"])
    long_data = time_cmd(spec["path"], long_reps, spec["extra_env"])
    results[name] = summarize_pair(short_data, long_data)

write_json(os.environ["I32_BUF_SHORT_LOG"], {
    "oren_i32_buf_scalar": results["oren_i32_buf_scalar"]["short"],
    "oren_i32_buf_simd": results["oren_i32_buf_simd"]["short"],
    "c_packed_vector": results["c_packed_vector"]["short"],
    "c_packed_scalar": results["c_packed_scalar"]["short"],
})
write_json(os.environ["I32_BUF_LONG_LOG"], {
    "oren_i32_buf_scalar": results["oren_i32_buf_scalar"]["long"],
    "oren_i32_buf_simd": results["oren_i32_buf_simd"]["long"],
    "c_packed_vector": results["c_packed_vector"]["long"],
    "c_packed_scalar": results["c_packed_scalar"]["long"],
})
write_json(os.environ["CANONICAL_SHORT_LOG"], {
    "oren_native_canonical": results["oren_native_canonical"]["short"],
})
write_json(os.environ["CANONICAL_LONG_LOG"], {
    "oren_native_canonical": results["oren_native_canonical"]["long"],
})

print("list<int> i32-buf read split probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print(f"short_reps: {short_reps}")
print(f"long_reps: {long_reps}")
print("")

for name in [
    "c_packed_vector",
    "c_packed_scalar",
    "oren_i32_buf_scalar",
    "oren_i32_buf_simd",
    "oren_native_canonical",
]:
    data = results[name]
    short_data = data["short"]
    long_data = data["long"]
    print(f"{name}:")
    print(f"  stdout: {short_data['stdout']}")
    print(f"  short: {short_data['median_s']:.6f}s cov={short_data['cov']:.4f}")
    print(f"  long: {long_data['median_s']:.6f}s cov={long_data['cov']:.4f}")
    print(f"  setup≈{data['setup_s']:.6f}s")
    print(f"  delta≈{data['delta_per_rep_s']:.6f}s")
    print(f"  long/reps≈{data['long_per_rep_s']:.6f}s")
    print(f"  setup_share_of_long≈{data['setup_share_of_long']:.2%}")
    print("")

def ratio(a, b, key):
    return results[a][key] / results[b][key]

print(f"oren_i32_buf_simd/c_packed_vector long-per-rep ratio: {ratio('oren_i32_buf_simd', 'c_packed_vector', 'long_per_rep_s'):.4f}x")
print(f"oren_i32_buf_simd/oren_native_canonical long-per-rep ratio: {ratio('oren_i32_buf_simd', 'oren_native_canonical', 'long_per_rep_s'):.4f}x")
print(f"oren_i32_buf_simd/oren_i32_buf_scalar long-per-rep ratio: {ratio('oren_i32_buf_simd', 'oren_i32_buf_scalar', 'long_per_rep_s'):.4f}x")
for lhs, rhs in [
    ("oren_i32_buf_simd", "c_packed_vector"),
    ("oren_i32_buf_simd", "oren_native_canonical"),
    ("oren_i32_buf_simd", "oren_i32_buf_scalar"),
]:
    lhs_delta = results[lhs]["delta_per_rep_s"]
    rhs_delta = results[rhs]["delta_per_rep_s"]
    if lhs_delta > 0.0 and rhs_delta > 0.0:
        print(f"{lhs}/{rhs} delta ratio: {(lhs_delta / rhs_delta):.4f}x")
print("")

vector_long = results["c_packed_vector"]["long_per_rep_s"]
scalar_long = results["c_packed_scalar"]["long_per_rep_s"]
if scalar_long > 0.0:
    drift = abs(vector_long - scalar_long) / scalar_long
    if drift < 0.20:
        print(f"warning: packed-i32 C vector/scalar long-per-rep drift={drift:.2%}; setup still materially affects whole-process timing")
        print("warning: prefer this read-split probe over the setup-mixed full-process ceiling numbers for kernel attribution")
setup_heavy = False
for name in results:
    if results[name]["setup_share_of_long"] > 0.60:
        setup_heavy = True
if setup_heavy:
    print("warning: one or more variants are still setup-heavy even after the split; prefer positive delta ratios over long-per-rep for repeated-kernel attribution")
PY

echo "list<int> i32-buf read split probe complete; summary: $summary_log"
echo "i32-buf short run log: $i32_buf_short_log"
echo "i32-buf long run log: $i32_buf_long_log"
echo "canonical short run log: $canonical_short_log"
echo "canonical long run log: $canonical_long_log"
