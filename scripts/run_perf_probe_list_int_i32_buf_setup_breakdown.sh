#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-i32-buf-setup-breakdown-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-i32-buf-setup-breakdown-${ts}.log"

runs="${OREN_LIST_INT_I32_BUF_SETUP_BREAKDOWN_RUNS:-3}"
warmups="${OREN_LIST_INT_I32_BUF_SETUP_BREAKDOWN_WARMUPS:-0}"
n="${OREN_LIST_INT_I32_BUF_SETUP_BREAKDOWN_N:-200000}"
short_reps="${OREN_LIST_INT_I32_BUF_SETUP_BREAKDOWN_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_I32_BUF_SETUP_BREAKDOWN_LONG_REPS:-1000}"
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

fill_c_bin="$tmp_dir/fill_i32_buf_c"
fill_oren_bin="$tmp_dir/fill_i32_buf_oren_native"
dot_c_bin="$tmp_dir/dot_product_i32_buf_c_vector"
dot_oren_bin="$tmp_dir/dot_product_i32_buf_oren_native"

build_fill_oren_cmd=(./oren_stage2 build benchmarks/fill_i32_buf/fill_i32_buf.oren --backend native --no-debug --no-cache -o "$fill_oren_bin")
build_dot_oren_cmd=(./oren_stage2 build benchmarks/dot_product_i32_buf/dot_product_i32_buf.oren --backend native --no-debug --no-cache -o "$dot_oren_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_fill_oren_cmd[@]}" >"$tmp_dir/fill_i32_buf_oren_native.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_dot_oren_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
else
    "${build_fill_oren_cmd[@]}" >"$tmp_dir/fill_i32_buf_oren_native.build.log" 2>&1
    "${build_dot_oren_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$fill_c_bin" benchmarks/fill_i32_buf/fill_i32_buf.c
"$bench_cc" -O2 -o "$dot_c_bin" benchmarks/dot_product_i32_buf/dot_product_i32_buf.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
FILL_C_BIN="$fill_c_bin" \
FILL_OREN_BIN="$fill_oren_bin" \
DOT_C_BIN="$dot_c_bin" \
DOT_OREN_BIN="$dot_oren_bin" \
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


def time_cmd(cmd, extra_env=None):
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
            raise SystemExit(f"stdout mismatch for {cmd[0]}: expected {expected!r}, got {text!r}")
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


fill = {
    "c_fill": time_cmd([os.environ["FILL_C_BIN"], n]),
    "oren_i32_buf_fill": time_cmd([os.environ["FILL_OREN_BIN"], n]),
}

dot = {
    "c_packed_vector": summarize_pair(
        time_cmd([os.environ["DOT_C_BIN"], n, str(short_reps)]),
        time_cmd([os.environ["DOT_C_BIN"], n, str(long_reps)]),
    ),
    "oren_i32_buf_simd": summarize_pair(
        time_cmd([os.environ["DOT_OREN_BIN"], n, str(short_reps)], {"OREN_ENABLE_SIMD": "1"}),
        time_cmd([os.environ["DOT_OREN_BIN"], n, str(long_reps)], {"OREN_ENABLE_SIMD": "1"}),
    ),
}

print("list<int> i32-buf setup breakdown probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print(f"short_reps: {short_reps}")
print(f"long_reps: {long_reps}")
print("")

for name in ["c_fill", "oren_i32_buf_fill"]:
    data = fill[name]
    print(f"{name}:")
    print(f"  stdout: {data['stdout']}")
    print(f"  median: {data['median_s']:.6f}s cov={data['cov']:.4f}")
    print("")

for name in ["c_packed_vector", "oren_i32_buf_simd"]:
    data = dot[name]
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

print(f"oren_i32_buf_fill/c_fill median ratio: {(fill['oren_i32_buf_fill']['median_s'] / fill['c_fill']['median_s']):.4f}x")
print(f"oren_i32_buf_simd.setup/c_packed_vector.setup ratio: {(dot['oren_i32_buf_simd']['setup_s'] / dot['c_packed_vector']['setup_s']):.4f}x")
print(f"oren_i32_buf_fill share of oren_i32_buf_simd setup: {(fill['oren_i32_buf_fill']['median_s'] / dot['oren_i32_buf_simd']['setup_s']):.2%}")
print(f"c_fill share of c_packed_vector setup: {(fill['c_fill']['median_s'] / dot['c_packed_vector']['setup_s']):.2%}")
if dot["oren_i32_buf_simd"]["setup_s"] > fill["oren_i32_buf_fill"]["median_s"]:
    print(f"oren_i32_buf residual setup beyond fill≈{(dot['oren_i32_buf_simd']['setup_s'] - fill['oren_i32_buf_fill']['median_s']):.6f}s")
if dot["c_packed_vector"]["setup_s"] > fill["c_fill"]["median_s"]:
    print(f"c residual setup beyond fill≈{(dot['c_packed_vector']['setup_s'] - fill['c_fill']['median_s']):.6f}s")
PY

echo "list<int> i32-buf setup breakdown probe complete; summary: $summary_log"
