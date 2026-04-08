#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-double-sweep-${ts}.log"
build_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-double-sweep-${ts}.build.log"
cases_log="$log_dir/perf-probe-arm64-fast-dot-madd-exact-double-sweep-${ts}.cases.tsv"
out_bin="$tmp_dir/perf_probe_arm64_fast_dot_madd_exact_double_sweep_${ts}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

max_n="${OREN_ARM64_FAST_DOT_MADD_EXACT_DOUBLE_SWEEP_MAX_N:-24}"
reps="${OREN_ARM64_FAST_DOT_MADD_EXACT_DOUBLE_SWEEP_REPS:-1}"

if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1 \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
            --backend native --no-debug --no-cache -o "$out_bin" >"$build_log" 2>&1
else
    env \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0 \
        OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1 \
        ./oren_stage2 build benchmarks/dot_product/dot_product.oren \
            --backend native --no-debug --no-cache -o "$out_bin" >"$build_log" 2>&1
fi

: >"$cases_log"

CASES_LOG="$cases_log" \
OUT_BIN="$out_bin" \
LOG_DIR="$log_dir" \
TS="$ts" \
MAX_N="$max_n" \
REPS="$reps" \
python3 - <<'PY'
import os
import pathlib
import subprocess

cases_log = pathlib.Path(os.environ["CASES_LOG"])
out_bin = os.environ["OUT_BIN"]
log_dir = pathlib.Path(os.environ["LOG_DIR"])
ts = os.environ["TS"]
max_n = int(os.environ["MAX_N"])
reps = os.environ["REPS"]

with cases_log.open("w", encoding="utf-8") as cases:
    for n in range(1, max_n + 1):
        run_log = log_dir / f"perf-probe-arm64-fast-dot-madd-exact-double-sweep-{ts}-n{n}.run.log"
        p = subprocess.run([out_bin, str(n), reps], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with run_log.open("wb") as f:
            f.write(p.stdout)
            f.write(p.stderr)
        out = (p.stdout + p.stderr).decode("utf-8", "replace").replace("\n", " ").strip()
        status = p.returncode
        if status < 0:
            status = 128 + (-status)
        cases.write(f"{n}\t{status}\t{run_log}\t{out}\n")
PY

CASES_LOG="$cases_log" \
OUT_BIN="$out_bin" \
BUILD_LOG="$build_log" \
BUILD_ENV="$build_env_raw" \
MAX_N="$max_n" \
REPS="$reps" \
python3 - <<'PY' >"$summary_log"
import os

rows = []
with open(os.environ["CASES_LOG"], "r", encoding="utf-8") as f:
    for line in f:
        n, status, run_log, out = line.rstrip("\n").split("\t", 3)
        rows.append((int(n), int(status), run_log, out))

fail_ns = [n for n, status, _, _ in rows if status != 0]
pass_ns = [n for n, status, _, _ in rows if status == 0]
fail_mods = sorted({n % 4 for n in fail_ns})

print("arm64 fast-dot exact madd double sweep")
print("")
print(f"binary: {os.environ['OUT_BIN']}")
print(f"build_log: {os.environ['BUILD_LOG']}")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"max_n: {os.environ['MAX_N']}")
print(f"reps: {os.environ['REPS']}")
print(f"pass_ns: {pass_ns}")
print(f"fail_ns: {fail_ns}")
print(f"fail_mod4: {fail_mods}")
print("")

for n, status, run_log, out in rows:
    print(f"n={n}:")
    print(f"  exit_code: {status}")
    print(f"  run_log: {run_log}")
    if out:
        print(f"  output: {out}")
    print("")
PY

echo "arm64 exact-double sweep complete; summary: $summary_log"
echo "build log: $build_log"
echo "cases log: $cases_log"
