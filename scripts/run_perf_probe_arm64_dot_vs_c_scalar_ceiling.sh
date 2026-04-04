#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-arm64-dot-vs-c-scalar-ceiling-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-arm64-dot-vs-c-scalar-ceiling-${ts}.log"
wrapper_log="$log_dir/perf-probe-arm64-dot-vs-c-scalar-ceiling-${ts}.run.log"
vector_asm="$tmp_dir/dot_product_c_vector.s"
scalar_asm="$tmp_dir/dot_product_c_scalar.s"
vector_bin="$tmp_dir/dot_product_c_vector"
scalar_bin="$tmp_dir/dot_product_c_scalar"
native_bin="$tmp_dir/dot_product_oren_native"

runs="${OREN_ARM64_DOT_CEILING_RUNS:-5}"
warmups="${OREN_ARM64_DOT_CEILING_WARMUPS:-1}"
n="${OREN_ARM64_DOT_CEILING_N:-2000000}"
reps="${OREN_ARM64_DOT_CEILING_REPS:-100}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"

bench_cc="${OREN_BENCH_CC:-cc}"
cc_base="$(basename "$bench_cc")"
scalar_flags=()
if "$bench_cc" --version 2>/dev/null | rg -qi 'clang'; then
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
elif "$bench_cc" --version 2>/dev/null | rg -qi 'gcc'; then
    scalar_flags=(-fno-tree-vectorize -fno-tree-slp-vectorize)
else
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
fi

run_capture() {
    local run_log="$1"
    shift
    "$@" >"$run_log" 2>&1
}

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

build_native_cmd=(./oren_stage2 build benchmarks/dot_product/dot_product.oren --backend native --no-debug --no-cache -o "$native_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_native_cmd[@]}" >"$tmp_dir/dot_product_oren_native.build.log" 2>&1
else
    "${build_native_cmd[@]}" >"$tmp_dir/dot_product_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -S -o "$vector_asm" benchmarks/dot_product/dot_product.c
"$bench_cc" -O2 "${scalar_flags[@]}" -S -o "$scalar_asm" benchmarks/dot_product/dot_product.c
"$bench_cc" -O2 -o "$vector_bin" benchmarks/dot_product/dot_product.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$scalar_bin" benchmarks/dot_product/dot_product.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
VECTOR_BIN="$vector_bin" \
SCALAR_BIN="$scalar_bin" \
NATIVE_BIN="$native_bin" \
VECTOR_ASM="$vector_asm" \
SCALAR_ASM="$scalar_asm" \
BUILD_ENV="$build_env_raw" \
CC_BIN="$bench_cc" \
CC_BASE="$cc_base" \
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
args = [os.environ["N"], os.environ["REPS"]]
vector_bin = os.environ["VECTOR_BIN"]
scalar_bin = os.environ["SCALAR_BIN"]
native_bin = os.environ["NATIVE_BIN"]

label_re = re.compile(r"^([A-Za-z0-9_.$]+):$")


def run_one(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    return proc.stdout.strip()


def time_cmd(path):
    cmd = [path, *args]
    expected = None
    for _ in range(warmups):
        out = run_one(cmd)
        if expected is None:
            expected = out
    times = []
    for _ in range(runs):
        t0 = time.perf_counter()
        out = run_one(cmd)
        dt = time.perf_counter() - t0
        if expected is None:
            expected = out
        elif out != expected:
            raise SystemExit(f"stdout mismatch for {path}: expected {expected!r}, got {out!r}")
        times.append(dt)
    med = statistics.median(times)
    mean = statistics.mean(times)
    cov = 0.0
    if len(times) >= 2 and mean != 0:
        cov = statistics.stdev(times) / mean
    return {
        "stdout": expected,
        "median_s": med,
        "per_rep_s": med / int(os.environ["REPS"]),
        "cov": cov,
    }


def read_lines(path):
    return Path(path).read_text(encoding="utf-8").splitlines()


def extract_loop(lines, prefer_vector):
    blocks = []
    i = 0
    while i < len(lines):
        m = label_re.match(lines[i].strip())
        if not m:
            i += 1
            continue
        label = m.group(1)
        block = [lines[i]]
        i += 1
        while i < len(lines):
            cur = lines[i]
            if label_re.match(cur.strip()):
                break
            block.append(cur)
            i += 1
        text = "\n".join(block)
        score = 0
        if "smaddl" in text:
            score += 5
        if "smlal" in text or "smlal2" in text:
            score += 10 if prefer_vector else 2
        if "\tb.ne" in text or "\tbne" in text:
            score += 2
        if "\tret" not in text:
            score += 1
        if score > 0:
            blocks.append((score, label, block))
    if not blocks:
        raise SystemExit("failed to locate candidate loop block")
    blocks.sort(key=lambda item: (item[0], len(item[2])), reverse=True)
    return blocks[0][1], blocks[0][2]


def count_mnemonics(block):
    counts = {}
    total = 0
    for line in block:
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        if stripped.endswith(":"):
            continue
        parts = stripped.split(None, 1)
        if not parts:
            continue
        mnemonic = parts[0]
        counts[mnemonic] = counts.get(mnemonic, 0) + 1
        total += 1
    return total, counts


def fmt_counts(counts):
    return " ".join(f"{k}={counts[k]}" for k in sorted(counts))


vector = time_cmd(vector_bin)
scalar = time_cmd(scalar_bin)
native = time_cmd(native_bin)

vector_label, vector_block = extract_loop(read_lines(os.environ["VECTOR_ASM"]), True)
scalar_label, scalar_block = extract_loop(read_lines(os.environ["SCALAR_ASM"]), False)
vector_total, vector_counts = count_mnemonics(vector_block)
scalar_total, scalar_counts = count_mnemonics(scalar_block)

print("arm64 dot_product vector-vs-scalar C ceiling probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"cc: {os.environ['CC_BIN']}")
print(f"scalar_flags: {os.environ['SCALAR_FLAGS']}")
print(f"runs: {runs}")
print(f"warmups: {warmups}")
print(f"n: {os.environ['N']}")
print(f"reps: {os.environ['REPS']}")
print("")
print(f"vector_bin: {vector_bin}")
print(f"scalar_bin: {scalar_bin}")
print(f"native_bin: {native_bin}")
print("")
for name, data in [("c_vector", vector), ("c_scalar", scalar), ("oren_native", native)]:
    print(f"{name}:")
    print(f"  stdout: {data['stdout']}")
    print(f"  median: {data['median_s']:.6f}s")
    print(f"  per_rep: {data['per_rep_s']:.6f}s")
    print(f"  cov: {data['cov']:.4f}")
    print("")
print(f"scalar/vector per_rep ratio: {(scalar['per_rep_s'] / vector['per_rep_s']):.4f}x")
print(f"oren/scalar per_rep ratio: {(native['per_rep_s'] / scalar['per_rep_s']):.4f}x")
print(f"oren/vector per_rep ratio: {(native['per_rep_s'] / vector['per_rep_s']):.4f}x")
print("")
print(f"vector_loop_label: {vector_label}")
print(f"vector_loop_insns: {vector_total}")
print(f"vector_loop_counts: {fmt_counts(vector_counts)}")
print("")
print(f"scalar_loop_label: {scalar_label}")
print(f"scalar_loop_insns: {scalar_total}")
print(f"scalar_loop_counts: {fmt_counts(scalar_counts)}")
print("")
print("vector_loop:")
for line in vector_block:
    print(f"  {line}")
print("")
print("scalar_loop:")
for line in scalar_block:
    print(f"  {line}")
PY

echo "arm64 dot vs C scalar ceiling probe complete; summary: $summary_log"
