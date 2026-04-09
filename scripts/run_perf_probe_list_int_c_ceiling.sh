#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-c-ceiling-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-c-ceiling-${ts}.log"
array_packed_vector_bin="$tmp_dir/array_sum_packed32_vector"
array_packed_scalar_bin="$tmp_dir/array_sum_packed32_scalar"
array_slot_vector_bin="$tmp_dir/array_sum_slot64_vector"
array_slot_scalar_bin="$tmp_dir/array_sum_slot64_scalar"
dot_packed_vector_bin="$tmp_dir/dot_product_packed32_vector"
dot_packed_scalar_bin="$tmp_dir/dot_product_packed32_scalar"
dot_slot_vector_bin="$tmp_dir/dot_product_slot64_vector"
dot_slot_scalar_bin="$tmp_dir/dot_product_slot64_scalar"
oren_array_bin="$tmp_dir/array_sum_int_oren_native"
oren_dot_bin="$tmp_dir/dot_product_int_oren_native"
array_packed_c_src="$tmp_dir/array_sum_packed32.c"
dot_slot_c_src="$tmp_dir/dot_product_slot64.c"

runs="${OREN_LIST_INT_C_CEILING_RUNS:-5}"
warmups="${OREN_LIST_INT_C_CEILING_WARMUPS:-1}"
n="${OREN_LIST_INT_C_CEILING_N:-2000000}"
reps="${OREN_LIST_INT_C_CEILING_REPS:-100}"
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

cat >"$dot_slot_c_src" <<'EOF'
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

    int64_t *a = (int64_t *)malloc((size_t)n * sizeof(int64_t));
    int64_t *b = (int64_t *)malloc((size_t)n * sizeof(int64_t));
    if (!a || !b) {
        fprintf(stderr, "alloc failed\n");
        free(a);
        free(b);
        return 1;
    }

    for (uint64_t i = 0; i < n; i++) {
        a[i] = (int64_t)((i * 3ULL + 1ULL) % 1000ULL);
        b[i] = (int64_t)((i * 7ULL + 2ULL) % 1000ULL);
    }

    int64_t sum = 0;
    for (uint64_t rep = 0; rep < reps; rep++) {
        sum = 0;
        for (uint64_t i = 0; i < n; i++) {
            sum += a[i] * b[i];
        }
    }

    printf("%" PRId64 "\n", sum);
    free(a);
    free(b);
    return 0;
}
EOF

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

build_array_cmd=(./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug "${PERF_BUILD_CACHE_ARGS[@]}" -o "$oren_array_bin")
build_dot_cmd=(./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug "${PERF_BUILD_CACHE_ARGS[@]}" -o "$oren_dot_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_array_cmd[@]}" >"$tmp_dir/array_sum_int_oren_native.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_dot_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
else
    "${build_array_cmd[@]}" >"$tmp_dir/array_sum_int_oren_native.build.log" 2>&1
    "${build_dot_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -o "$array_packed_vector_bin" "$array_packed_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$array_packed_scalar_bin" "$array_packed_c_src"
"$bench_cc" -O2 -o "$array_slot_vector_bin" benchmarks/array_sum_int/array_sum_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$array_slot_scalar_bin" benchmarks/array_sum_int/array_sum_int.c
"$bench_cc" -O2 -o "$dot_packed_vector_bin" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$dot_packed_scalar_bin" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 -o "$dot_slot_vector_bin" "$dot_slot_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$dot_slot_scalar_bin" "$dot_slot_c_src"

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
ARRAY_PACKED_VECTOR_BIN="$array_packed_vector_bin" \
ARRAY_PACKED_SCALAR_BIN="$array_packed_scalar_bin" \
ARRAY_SLOT_VECTOR_BIN="$array_slot_vector_bin" \
ARRAY_SLOT_SCALAR_BIN="$array_slot_scalar_bin" \
DOT_PACKED_VECTOR_BIN="$dot_packed_vector_bin" \
DOT_PACKED_SCALAR_BIN="$dot_packed_scalar_bin" \
DOT_SLOT_VECTOR_BIN="$dot_slot_vector_bin" \
DOT_SLOT_SCALAR_BIN="$dot_slot_scalar_bin" \
OREN_ARRAY_BIN="$oren_array_bin" \
OREN_DOT_BIN="$oren_dot_bin" \
BUILD_ENV="$build_env_raw" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
CC_BIN="$bench_cc" \
SCALAR_FLAGS="${scalar_flags[*]}" \
python3 - <<'PY' >"$summary_log"
import os
import statistics
import subprocess
import time

runs = int(os.environ["RUNS"])
warmups = int(os.environ["WARMUPS"])
array_args = [os.environ["N"], os.environ["REPS"]]
dot_args = [os.environ["N"], os.environ["REPS"]]


def run_one(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    return proc.stdout.strip()


def time_cmd(path, args):
    cmd = [path, *args]
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
    return {
        "stdout": expected,
        "median_s": med,
        "per_rep_s": med / int(os.environ["REPS"]),
        "cov": cov,
    }


def fmt_run(name, data):
    print(f"{name}:")
    print(f"  median_s: {data['median_s']:.6f}")
    print(f"  per_rep_s: {data['per_rep_s']:.6f}")
    print(f"  cov: {data['cov']:.4f}")
    print(f"  stdout: {data['stdout']}")
    print("")


def ratio_line(lhs_name, lhs, rhs_name, rhs):
    print(f"{lhs_name}/{rhs_name} per_rep ratio: {(lhs['per_rep_s'] / rhs['per_rep_s']):.4f}x")


array_packed_vector = time_cmd(os.environ["ARRAY_PACKED_VECTOR_BIN"], array_args)
array_packed_scalar = time_cmd(os.environ["ARRAY_PACKED_SCALAR_BIN"], array_args)
array_slot_vector = time_cmd(os.environ["ARRAY_SLOT_VECTOR_BIN"], array_args)
array_slot_scalar = time_cmd(os.environ["ARRAY_SLOT_SCALAR_BIN"], array_args)
dot_packed_vector = time_cmd(os.environ["DOT_PACKED_VECTOR_BIN"], dot_args)
dot_packed_scalar = time_cmd(os.environ["DOT_PACKED_SCALAR_BIN"], dot_args)
dot_slot_vector = time_cmd(os.environ["DOT_SLOT_VECTOR_BIN"], dot_args)
dot_slot_scalar = time_cmd(os.environ["DOT_SLOT_SCALAR_BIN"], dot_args)
oren_array = time_cmd(os.environ["OREN_ARRAY_BIN"], array_args)
oren_dot = time_cmd(os.environ["OREN_DOT_BIN"], dot_args)

print("list<int> canonical C ceiling probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print(f"cc: {os.environ['CC_BIN']}")
print(f"scalar_flags: {os.environ['SCALAR_FLAGS']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {os.environ['N']}")
print(f"reps: {os.environ['REPS']}")
print("")

fmt_run("c_array_sum_slot64_vector", array_slot_vector)
fmt_run("c_array_sum_slot64_scalar", array_slot_scalar)
fmt_run("oren_array_sum_int_canonical", oren_array)
fmt_run("c_array_sum_packed32_vector", array_packed_vector)
fmt_run("c_array_sum_packed32_scalar", array_packed_scalar)
fmt_run("c_dot_product_packed32_vector", dot_packed_vector)
fmt_run("c_dot_product_packed32_scalar", dot_packed_scalar)
fmt_run("c_dot_product_slot64_vector", dot_slot_vector)
fmt_run("c_dot_product_slot64_scalar", dot_slot_scalar)
fmt_run("oren_dot_product_int_canonical", oren_dot)

print("ratio_summary:")
ratio_line("array_packed32_vector", array_packed_vector, "array_packed32_scalar", array_packed_scalar)
ratio_line("array_slot64_vector", array_slot_vector, "array_slot64_scalar", array_slot_scalar)
ratio_line("array_slot64_vector", array_slot_vector, "array_packed32_vector", array_packed_vector)
ratio_line("array_slot64_scalar", array_slot_scalar, "array_packed32_scalar", array_packed_scalar)
ratio_line("oren_array_sum_int", oren_array, "array_slot64_vector", array_slot_vector)
ratio_line("oren_array_sum_int", oren_array, "array_slot64_scalar", array_slot_scalar)
ratio_line("oren_array_sum_int", oren_array, "array_packed32_vector", array_packed_vector)
ratio_line("dot_packed32_vector", dot_packed_vector, "dot_packed32_scalar", dot_packed_scalar)
ratio_line("dot_slot64_vector", dot_slot_vector, "dot_packed32_vector", dot_packed_vector)
ratio_line("dot_slot64_scalar", dot_slot_scalar, "dot_packed32_scalar", dot_packed_scalar)
ratio_line("oren_dot_product_int", oren_dot, "dot_slot64_vector", dot_slot_vector)
ratio_line("oren_dot_product_int", oren_dot, "dot_slot64_scalar", dot_slot_scalar)
ratio_line("oren_dot_product_int", oren_dot, "dot_packed32_vector", dot_packed_vector)
PY

echo "list<int> canonical C ceiling probe complete; summary: $summary_log"
