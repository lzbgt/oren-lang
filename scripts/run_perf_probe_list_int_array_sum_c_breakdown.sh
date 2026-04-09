#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-array-sum-c-breakdown-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-array-sum-c-breakdown-${ts}.log"
array_packed_vector_bin="$tmp_dir/array_sum_packed32_vector"
array_packed_scalar_bin="$tmp_dir/array_sum_packed32_scalar"
array_slot_vector_bin="$tmp_dir/array_sum_slot64_vector"
array_slot_scalar_bin="$tmp_dir/array_sum_slot64_scalar"
oren_array_bin="$tmp_dir/array_sum_int_oren_native"
array_packed_c_src="$tmp_dir/array_sum_packed32.c"

runs="${OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_RUNS:-5}"
warmups="${OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_WARMUPS:-1}"
n="${OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_N:-2000000}"
short_reps="${OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_SHORT_REPS:-1}"
long_reps="${OREN_LIST_INT_ARRAY_SUM_C_BREAKDOWN_LONG_REPS:-100}"
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

cat >"$array_packed_c_src" <<'EOF'
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t parse_u64(const char *s) {
    if (!s || !*s) return 0ULL;
    char *end = NULL;
    unsigned long long v = strtoull(s, &end, 10);
    if (!end || *end != '\0') return 0ULL;
    return (uint64_t)v;
}

int main(int argc, char **argv) {
    uint64_t n = 2000000ULL;
    uint64_t reps = 1ULL;
    if (argc > 1) n = parse_u64(argv[1]);
    if (argc > 2) reps = parse_u64(argv[2]);

    uint32_t *xs = (uint32_t *)malloc((size_t)n * sizeof(uint32_t));
    if (!xs) {
        fprintf(stderr, "alloc failed\n");
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        xs[i] = (uint32_t)((i * 3ULL + 7ULL) % 1000ULL);
    }

    uint64_t sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += (uint64_t)xs[i];
        }
    }

    printf("%" PRIu64 "\n", sum);
    free(xs);
    return 0;
}
EOF

build_array_cmd=(./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug --no-cache -o "$oren_array_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_array_cmd[@]}" >"$tmp_dir/array_sum_int_oren_native.build.log" 2>&1
else
    "${build_array_cmd[@]}" >"$tmp_dir/array_sum_int_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$array_packed_vector_bin" "$array_packed_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$array_packed_scalar_bin" "$array_packed_c_src"
"$bench_cc" -O2 -o "$array_slot_vector_bin" benchmarks/array_sum_int/array_sum_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$array_slot_scalar_bin" benchmarks/array_sum_int/array_sum_int.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
SHORT_REPS="$short_reps" \
LONG_REPS="$long_reps" \
ARRAY_PACKED_VECTOR_BIN="$array_packed_vector_bin" \
ARRAY_PACKED_SCALAR_BIN="$array_packed_scalar_bin" \
ARRAY_SLOT_VECTOR_BIN="$array_slot_vector_bin" \
ARRAY_SLOT_SCALAR_BIN="$array_slot_scalar_bin" \
OREN_ARRAY_BIN="$oren_array_bin" \
BUILD_ENV="$build_env_raw" \
CC_BIN="$bench_cc" \
SCALAR_FLAGS="${scalar_flags[*]}" \
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


def run_one(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    return proc.stdout.strip()


def time_cmd(path, reps):
    cmd = [path, n, str(reps)]
    expected = None
    for _ in range(warmups):
        out = run_one(cmd)
        if expected is None:
            expected = out
    times = []
    for _ in range(runs):
        start = time.perf_counter()
        out = run_one(cmd)
        elapsed = time.perf_counter() - start
        if expected is None:
            expected = out
        elif out != expected:
            raise SystemExit(f"stdout mismatch for {path}: expected {expected!r}, got {out!r}")
        times.append(elapsed)
    med = statistics.median(times)
    mean = statistics.mean(times)
    cov = 0.0
    if len(times) >= 2 and mean != 0.0:
        cov = statistics.stdev(times) / mean
    return {"stdout": expected, "median_s": med, "cov": cov}


def derive_breakdown(short_run, long_run):
    steady_per_rep = (long_run["median_s"] - short_run["median_s"]) / delta_reps
    setup_est = short_run["median_s"] - steady_per_rep * short_reps
    long_per_rep = long_run["median_s"] / long_reps
    return {
        "short_s": short_run["median_s"],
        "short_cov": short_run["cov"],
        "long_s": long_run["median_s"],
        "long_cov": long_run["cov"],
        "setup_est_s": setup_est,
        "steady_per_rep_s": steady_per_rep,
        "long_per_rep_s": long_per_rep,
        "stdout": long_run["stdout"],
    }


cases = [
    ("c_array_sum_packed32_vector", os.environ["ARRAY_PACKED_VECTOR_BIN"]),
    ("c_array_sum_packed32_scalar", os.environ["ARRAY_PACKED_SCALAR_BIN"]),
    ("c_array_sum_slot64_vector", os.environ["ARRAY_SLOT_VECTOR_BIN"]),
    ("c_array_sum_slot64_scalar", os.environ["ARRAY_SLOT_SCALAR_BIN"]),
    ("oren_array_sum_int_canonical", os.environ["OREN_ARRAY_BIN"]),
]

data = {}
for name, path in cases:
    short_run = time_cmd(path, short_reps)
    long_run = time_cmd(path, long_reps)
    data[name] = derive_breakdown(short_run, long_run)

print("list<int> array_sum_int C breakdown probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"cc: {os.environ['CC_BIN']}")
print(f"scalar_flags: {os.environ['SCALAR_FLAGS']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {n}")
print(f"short_reps: {short_reps}")
print(f"long_reps: {long_reps}")
print("")
for name, stats in data.items():
    print(f"{name}:")
    print(f"  short_s: {stats['short_s']:.6f}")
    print(f"  short_cov: {stats['short_cov']:.4f}")
    print(f"  long_s: {stats['long_s']:.6f}")
    print(f"  long_cov: {stats['long_cov']:.4f}")
    print(f"  setup_est_s: {stats['setup_est_s']:.6f}")
    print(f"  steady_per_rep_s: {stats['steady_per_rep_s']:.6f}")
    print(f"  long_per_rep_s: {stats['long_per_rep_s']:.6f}")
    print(f"  stdout: {stats['stdout']}")
    print("")

print("ratio_summary:")
def ratio_line(lhs_name, lhs_key, rhs_name, rhs_key):
    lhs = data[lhs_name][lhs_key]
    rhs = data[rhs_name][rhs_key]
    print(f"{lhs_name}/{rhs_name} {lhs_key}/{rhs_key} ratio: {(lhs / rhs):.4f}x")

ratio_line("c_array_sum_slot64_vector", "setup_est_s", "c_array_sum_packed32_vector", "setup_est_s")
ratio_line("oren_array_sum_int_canonical", "setup_est_s", "c_array_sum_slot64_vector", "setup_est_s")
ratio_line("oren_array_sum_int_canonical", "setup_est_s", "c_array_sum_slot64_scalar", "setup_est_s")
ratio_line("c_array_sum_slot64_vector", "steady_per_rep_s", "c_array_sum_packed32_vector", "steady_per_rep_s")
ratio_line("oren_array_sum_int_canonical", "steady_per_rep_s", "c_array_sum_slot64_vector", "steady_per_rep_s")
ratio_line("oren_array_sum_int_canonical", "steady_per_rep_s", "c_array_sum_slot64_scalar", "steady_per_rep_s")
PY

echo "list<int> array_sum_int C breakdown probe complete; summary: $summary_log"
