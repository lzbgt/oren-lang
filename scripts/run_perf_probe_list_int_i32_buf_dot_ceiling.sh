#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-i32-buf-dot-ceiling-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-i32-buf-dot-ceiling-${ts}.log"
packed_vector_asm="$tmp_dir/dot_product_c_vector.s"
packed_scalar_asm="$tmp_dir/dot_product_c_scalar.s"
packed_vector_bin="$tmp_dir/dot_product_c_vector"
packed_scalar_bin="$tmp_dir/dot_product_c_scalar"
oren_i32_buf_bin="$tmp_dir/dot_product_i32_buf_oren_native"
oren_canonical_bin="$tmp_dir/dot_product_int_oren_native"

runs="${OREN_LIST_INT_I32_BUF_DOT_CEILING_RUNS:-3}"
warmups="${OREN_LIST_INT_I32_BUF_DOT_CEILING_WARMUPS:-0}"
n="${OREN_LIST_INT_I32_BUF_DOT_CEILING_N:-20000}"
reps="${OREN_LIST_INT_I32_BUF_DOT_CEILING_REPS:-20}"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"

bench_cc="${OREN_BENCH_CC:-cc}"
scalar_flags=()
if "$bench_cc" --version 2>/dev/null | rg -qi 'clang'; then
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
elif "$bench_cc" --version 2>/dev/null | rg -qi 'gcc'; then
    scalar_flags=(-fno-tree-vectorize -fno-tree-slp-vectorize)
else
    scalar_flags=(-fno-vectorize -fno-slp-vectorize)
fi

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

build_i32_buf_cmd=(./oren_stage2 build benchmarks/dot_product_i32_buf/dot_product_i32_buf.oren --backend native --no-debug --no-cache -o "$oren_i32_buf_bin")
build_canonical_cmd=(./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug --no-cache -o "$oren_canonical_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
else
    "${build_i32_buf_cmd[@]}" >"$tmp_dir/dot_product_i32_buf_oren_native.build.log" 2>&1
    "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -S -o "$packed_vector_asm" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -S -o "$packed_scalar_asm" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 -o "$packed_vector_bin" benchmarks/dot_product_int/dot_product_int.c
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$packed_scalar_bin" benchmarks/dot_product_int/dot_product_int.c

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
PACKED_VECTOR_BIN="$packed_vector_bin" \
PACKED_SCALAR_BIN="$packed_scalar_bin" \
OREN_I32_BUF_BIN="$oren_i32_buf_bin" \
OREN_CANONICAL_BIN="$oren_canonical_bin" \
PACKED_VECTOR_ASM="$packed_vector_asm" \
PACKED_SCALAR_ASM="$packed_scalar_asm" \
BUILD_ENV="$build_env_raw" \
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
args = [os.environ["N"], os.environ["REPS"]]
label_re = re.compile(r"^([A-Za-z0-9_.$]+):$")


def run_one(cmd, extra_env=None):
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True, env=env)
    return proc.stdout.strip()


def time_cmd(path, extra_env=None):
    cmd = [path, *args]
    expected = None
    for _ in range(warmups):
        out = run_one(cmd, extra_env)
        if expected is None:
            expected = out
    times = []
    for _ in range(runs):
        t0 = time.perf_counter()
        out = run_one(cmd, extra_env)
        dt = time.perf_counter() - t0
        if expected is None:
            expected = out
        elif out != expected:
            raise SystemExit(f"stdout mismatch for {path}: expected {expected!r}, got {out!r}")
        times.append(dt)
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
        if "\tb.ne" in text or "\tbne" in text:
            score += 3
        if "smaddl" in text:
            score += 6
        if "smlal" in text or "smlal2" in text:
            score += 10 if prefer_vector else 2
        if "\tret" not in text:
            score += 1
        if score > 0:
            blocks.append((score, len(block), label, block))
    if not blocks:
        raise SystemExit("failed to locate candidate loop block")
    blocks.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return blocks[0][2], blocks[0][3]


def count_mnemonics(block):
    counts = {}
    total = 0
    for line in block:
        stripped = line.strip()
        if not stripped or stripped.startswith(";") or stripped.startswith("//"):
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


packed_vector = time_cmd(os.environ["PACKED_VECTOR_BIN"])
packed_scalar = time_cmd(os.environ["PACKED_SCALAR_BIN"])
oren_i32_buf_scalar = time_cmd(os.environ["OREN_I32_BUF_BIN"], {"OREN_NO_SIMD": "1"})
oren_i32_buf_simd = time_cmd(os.environ["OREN_I32_BUF_BIN"], {"OREN_ENABLE_SIMD": "1"})
oren_canonical = time_cmd(os.environ["OREN_CANONICAL_BIN"])

vector_label, vector_block = extract_loop(read_lines(os.environ["PACKED_VECTOR_ASM"]), True)
scalar_label, scalar_block = extract_loop(read_lines(os.environ["PACKED_SCALAR_ASM"]), False)
vector_total, vector_counts = count_mnemonics(vector_block)
scalar_total, scalar_counts = count_mnemonics(scalar_block)

print("list<int> i32-buf dot ceiling probe")
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
for name, data in [
    ("c_packed_vector", packed_vector),
    ("c_packed_scalar", packed_scalar),
    ("oren_i32_buf_scalar", oren_i32_buf_scalar),
    ("oren_i32_buf_simd", oren_i32_buf_simd),
    ("oren_native_canonical", oren_canonical),
]:
    print(f"{name}:")
    print(f"  stdout: {data['stdout']}")
    print(f"  median: {data['median_s']:.6f}s")
    print(f"  per_rep: {data['per_rep_s']:.6f}s")
    print(f"  cov: {data['cov']:.4f}")
    print("")

print(f"oren_i32_buf_scalar/c_packed_scalar per_rep ratio: {(oren_i32_buf_scalar['per_rep_s'] / packed_scalar['per_rep_s']):.4f}x")
print(f"oren_i32_buf_simd/c_packed_vector per_rep ratio: {(oren_i32_buf_simd['per_rep_s'] / packed_vector['per_rep_s']):.4f}x")
print(f"oren_i32_buf_simd/oren_i32_buf_scalar per_rep ratio: {(oren_i32_buf_simd['per_rep_s'] / oren_i32_buf_scalar['per_rep_s']):.4f}x")
print(f"oren_native_canonical/oren_i32_buf_simd per_rep ratio: {(oren_canonical['per_rep_s'] / oren_i32_buf_simd['per_rep_s']):.4f}x")
print(f"oren_native_canonical/c_packed_vector per_rep ratio: {(oren_canonical['per_rep_s'] / packed_vector['per_rep_s']):.4f}x")
print("")
print(f"packed_vector_loop_label: {vector_label}")
print(f"packed_vector_loop_insns: {vector_total}")
print(f"packed_vector_loop_counts: {fmt_counts(vector_counts)}")
print("")
print(f"packed_scalar_loop_label: {scalar_label}")
print(f"packed_scalar_loop_insns: {scalar_total}")
print(f"packed_scalar_loop_counts: {fmt_counts(scalar_counts)}")
print("")
PY

echo "list<int> i32-buf dot ceiling probe complete; summary: $summary_log"
