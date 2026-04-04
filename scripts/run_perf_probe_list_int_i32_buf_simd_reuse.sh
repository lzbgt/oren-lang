#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-i32-buf-simd-reuse-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-i32-buf-simd-reuse-${ts}.log"

runs="${OREN_LIST_INT_I32_BUF_SIMD_REUSE_RUNS:-3}"
warmups="${OREN_LIST_INT_I32_BUF_SIMD_REUSE_WARMUPS:-0}"
n="${OREN_LIST_INT_I32_BUF_SIMD_REUSE_N:-200000}"
short_reps="${OREN_LIST_INT_I32_BUF_SIMD_REUSE_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_I32_BUF_SIMD_REUSE_LONG_REPS:-1000}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
bench_cc="${OREN_BENCH_CC:-cc}"

join_build_env() {
    local out=()
    local raw="$1"
    if [[ -z "$raw" ]]; then
        return 0
    fi
    local old_ifs="$IFS"
    IFS=','
    read -r -a out <<<"$raw"
    IFS="$old_ifs"
    printf '%s\0' "${out[@]}"
}

mapfile -d '' -t build_env_parts < <(join_build_env "$build_env_raw")

packed_vector_bin="$tmp_dir/dot_product_c_vector"
oren_i32_buf_bin="$tmp_dir/dot_product_i32_buf_oren_native"

build_i32_buf_cmd=(./oren_stage2 build benchmarks/dot_product_i32_buf/dot_product_i32_buf.oren --backend native --no-debug --no-cache -o "$oren_i32_buf_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
else
    "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$packed_vector_bin" benchmarks/dot_product_i32_buf/dot_product_i32_buf.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
PACKED_VECTOR_BIN="$packed_vector_bin" \
OREN_I32_BUF_BIN="$oren_i32_buf_bin" \
BUILD_ENV="$build_env_raw" \
python3 - <<'PY' >"$summary_log"
import os
import statistics
import subprocess
import time

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


packed = summarize_pair(time_cmd(os.environ["PACKED_VECTOR_BIN"], short_reps), time_cmd(os.environ["PACKED_VECTOR_BIN"], long_reps))
oren = summarize_pair(
    time_cmd(os.environ["OREN_I32_BUF_BIN"], short_reps, {"OREN_ENABLE_SIMD": "1"}),
    time_cmd(os.environ["OREN_I32_BUF_BIN"], long_reps, {"OREN_ENABLE_SIMD": "1"}),
)

print("list<int> i32-buf SIMD reuse probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print(f"short_reps: {short_reps}")
print(f"long_reps: {long_reps}")
print("")

for name, data in [("c_packed_vector", packed), ("oren_i32_buf_simd", oren)]:
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

print(f"oren_i32_buf_simd/c_packed_vector long-per-rep ratio: {(oren['long_per_rep_s'] / packed['long_per_rep_s']):.4f}x")
if oren["delta_per_rep_s"] > 0.0 and packed["delta_per_rep_s"] > 0.0:
    print(f"oren_i32_buf_simd/c_packed_vector delta ratio: {(oren['delta_per_rep_s'] / packed['delta_per_rep_s']):.4f}x")
if oren["setup_share_of_long"] > 0.25 or packed["setup_share_of_long"] > 0.25:
    print("warning: setup still contributes materially; prefer the delta ratio when both deltas are positive")
PY

echo "list<int> i32-buf SIMD reuse probe complete; summary: $summary_log"
