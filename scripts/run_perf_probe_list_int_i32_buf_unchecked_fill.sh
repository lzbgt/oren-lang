#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-i32-buf-unchecked-fill-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-i32-buf-unchecked-fill-${ts}.log"

runs="${OREN_LIST_INT_I32_BUF_UNCHECKED_FILL_RUNS:-3}"
warmups="${OREN_LIST_INT_I32_BUF_UNCHECKED_FILL_WARMUPS:-0}"
n="${OREN_LIST_INT_I32_BUF_UNCHECKED_FILL_N:-200000}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"

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

fill_checked_bin="$tmp_dir/fill_i32_buf_checked"
fill_unchecked_bin="$tmp_dir/fill_i32_buf_unchecked"
fill_ptr_bin="$tmp_dir/fill_i32_buf_ptr"

build_checked_cmd=(./oren_stage2 build benchmarks/fill_i32_buf/fill_i32_buf.oren --backend native --no-debug --no-cache -o "$fill_checked_bin")
build_unchecked_cmd=(./oren_stage2 build benchmarks/fill_i32_buf_unchecked/fill_i32_buf_unchecked.oren --backend native --no-debug --no-cache -o "$fill_unchecked_bin")
build_ptr_cmd=(./oren_stage2 build benchmarks/fill_i32_buf_ptr/fill_i32_buf_ptr.oren --backend native --no-debug --no-cache -o "$fill_ptr_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_checked_cmd[@]}" >"$tmp_dir/fill_i32_buf_checked.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_unchecked_cmd[@]}" >"$tmp_dir/fill_i32_buf_unchecked.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_ptr_cmd[@]}" >"$tmp_dir/fill_i32_buf_ptr.build.log" 2>&1
else
    "${build_checked_cmd[@]}" >"$tmp_dir/fill_i32_buf_checked.build.log" 2>&1
    "${build_unchecked_cmd[@]}" >"$tmp_dir/fill_i32_buf_unchecked.build.log" 2>&1
    "${build_ptr_cmd[@]}" >"$tmp_dir/fill_i32_buf_ptr.build.log" 2>&1
fi

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
FILL_CHECKED_BIN="$fill_checked_bin" \
FILL_UNCHECKED_BIN="$fill_unchecked_bin" \
FILL_PTR_BIN="$fill_ptr_bin" \
BUILD_ENV="$build_env_raw" \
python3 - <<'PY' >"$summary_log"
import os
import statistics
import subprocess
import time

runs = int(os.environ["RUNS"])
warmups = int(os.environ["WARMUPS"])
n = os.environ["N"]

def time_cmd(path):
    cmd = [path, n]
    expected = None
    samples = []
    for _ in range(warmups):
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        text = out.stdout.strip()
        if expected is None:
            expected = text
    for _ in range(runs):
        t0 = time.perf_counter()
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
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
    return {"stdout": expected, "median_s": statistics.median(samples), "cov": cov}

checked = time_cmd(os.environ["FILL_CHECKED_BIN"])
unchecked = time_cmd(os.environ["FILL_UNCHECKED_BIN"])
ptr = time_cmd(os.environ["FILL_PTR_BIN"])

print("list<int> i32-buf unchecked fill probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print("")
print("checked_fill:")
print(f"  stdout: {checked['stdout']}")
print(f"  median: {checked['median_s']:.6f}s cov={checked['cov']:.4f}")
print("")
print("unchecked_fill:")
print(f"  stdout: {unchecked['stdout']}")
print(f"  median: {unchecked['median_s']:.6f}s cov={unchecked['cov']:.4f}")
print("")
print("ptr_fill:")
print(f"  stdout: {ptr['stdout']}")
print(f"  median: {ptr['median_s']:.6f}s cov={ptr['cov']:.4f}")
print("")
print(f"unchecked/checked ratio: {(unchecked['median_s'] / checked['median_s']):.4f}x")
if unchecked["median_s"] < checked["median_s"]:
    print(f"speedup: {(checked['median_s'] / unchecked['median_s']):.4f}x")
print(f"ptr/checked ratio: {(ptr['median_s'] / checked['median_s']):.4f}x")
if ptr["median_s"] < checked["median_s"]:
    print(f"ptr speedup: {(checked['median_s'] / ptr['median_s']):.4f}x")
PY

echo "list<int> i32-buf unchecked fill probe complete; summary: $summary_log"
