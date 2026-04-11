#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-slot-abi-ceiling-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-slot-abi-ceiling-${ts}.log"
packed_vector_asm="$tmp_dir/dot_product_packed_vector.s"
packed_scalar_asm="$tmp_dir/dot_product_packed_scalar.s"
slot_vector_asm="$tmp_dir/dot_product_slot64_vector.s"
slot_scalar_asm="$tmp_dir/dot_product_slot64_scalar.s"
packed_vector_bin="$tmp_dir/dot_product_packed_vector"
packed_scalar_bin="$tmp_dir/dot_product_packed_scalar"
slot_vector_bin="$tmp_dir/dot_product_slot64_vector"
slot_scalar_bin="$tmp_dir/dot_product_slot64_scalar"
oren_canonical_bin="$tmp_dir/dot_product_int_oren_native"
oren_slot_bin="$tmp_dir/dot_product_int_slot_direct_oren_native"
slot_c_src="$tmp_dir/dot_product_slot64.c"
packed_c_src="${OREN_LIST_INT_SLOT_ABI_PACKED_C_SOURCE:-benchmarks/dot_product_int/dot_product_int.c}"

runs="${OREN_LIST_INT_SLOT_ABI_CEILING_RUNS:-5}"
warmups="${OREN_LIST_INT_SLOT_ABI_CEILING_WARMUPS:-1}"
n="${OREN_LIST_INT_SLOT_ABI_CEILING_N:-2000000}"
reps="${OREN_LIST_INT_SLOT_ABI_CEILING_REPS:-100}"
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

cat >"$slot_c_src" <<'EOF'
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

build_canonical_cmd=(./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug "${PERF_BUILD_CACHE_ARGS[@]}" -o "$oren_canonical_bin")
build_slot_cmd=(./oren_stage2 build benchmarks/dot_product_int_slot_direct/dot_product_int_slot_direct.oren --backend native --no-debug "${PERF_BUILD_CACHE_ARGS[@]}" -o "$oren_slot_bin")
if [[ ${#build_env_parts[@]} -gt 0 ]]; then
    env "${build_env_parts[@]}" "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
    env "${build_env_parts[@]}" "${build_slot_cmd[@]}" >"$tmp_dir/dot_product_int_slot_direct_oren_native.build.log" 2>&1
else
    "${build_canonical_cmd[@]}" >"$tmp_dir/dot_product_int_oren_native.build.log" 2>&1
    "${build_slot_cmd[@]}" >"$tmp_dir/dot_product_int_slot_direct_oren_native.build.log" 2>&1
fi

"$bench_cc" -O2 -S -o "$packed_vector_asm" "$packed_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -S -o "$packed_scalar_asm" "$packed_c_src"
"$bench_cc" -O2 -S -o "$slot_vector_asm" "$slot_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -S -o "$slot_scalar_asm" "$slot_c_src"
"$bench_cc" -O2 -o "$packed_vector_bin" "$packed_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$packed_scalar_bin" "$packed_c_src"
"$bench_cc" -O2 -o "$slot_vector_bin" "$slot_c_src"
"$bench_cc" -O2 "${scalar_flags[@]}" -o "$slot_scalar_bin" "$slot_c_src"

RUNS="$runs" \
WARMUPS="$warmups" \
N="$n" \
REPS="$reps" \
PACKED_VECTOR_BIN="$packed_vector_bin" \
PACKED_SCALAR_BIN="$packed_scalar_bin" \
SLOT_VECTOR_BIN="$slot_vector_bin" \
SLOT_SCALAR_BIN="$slot_scalar_bin" \
OREN_CANONICAL_BIN="$oren_canonical_bin" \
OREN_SLOT_BIN="$oren_slot_bin" \
PACKED_VECTOR_ASM="$packed_vector_asm" \
PACKED_SCALAR_ASM="$packed_scalar_asm" \
SLOT_VECTOR_ASM="$slot_vector_asm" \
SLOT_SCALAR_ASM="$slot_scalar_asm" \
BUILD_ENV="$build_env_raw" \
PERF_BUILD_USE_CACHE="$perf_build_use_cache" \
PACKED_C_SOURCE="$packed_c_src" \
SLOT_C_SOURCE="$slot_c_src" \
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
label_re = re.compile(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):")


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
        if "\tmadd\t" in text or " madd\t" in text or " madd " in text:
            score += 6 if not prefer_vector else 4
        if "smaddl" in text:
            score += 6
        if "smlal" in text or "smlal2" in text or "smull" in text:
            score += 10 if prefer_vector else 2
        if "mul\tv" in text or "mul v" in text or "mla\tv" in text or "mla v" in text:
            score += 10 if prefer_vector else 2
        if "\tmul\t" in text or "\tadd\t" in text:
            score += 2
        if "\tbl\t" in text or "\tbl " in text:
            score -= 8
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
        if label_re.match(stripped):
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
slot_vector = time_cmd(os.environ["SLOT_VECTOR_BIN"])
slot_scalar = time_cmd(os.environ["SLOT_SCALAR_BIN"])
oren_canonical = time_cmd(os.environ["OREN_CANONICAL_BIN"])
oren_slot = time_cmd(os.environ["OREN_SLOT_BIN"])

loop_specs = [
    ("packed_vector", os.environ["PACKED_VECTOR_ASM"], True),
    ("packed_scalar", os.environ["PACKED_SCALAR_ASM"], False),
    ("slot_vector", os.environ["SLOT_VECTOR_ASM"], True),
    ("slot_scalar", os.environ["SLOT_SCALAR_ASM"], False),
]

print("list<int> slot ABI ceiling probe")
print("")
if os.environ["BUILD_ENV"]:
    print(f"build_env: {os.environ['BUILD_ENV']}")
print(f"perf_build_use_cache: {os.environ['PERF_BUILD_USE_CACHE']}")
print(f"packed_c_source: {os.environ['PACKED_C_SOURCE']}")
print(f"slot_c_source: {os.environ['SLOT_C_SOURCE']}")
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
    ("c_slot64_vector", slot_vector),
    ("c_slot64_scalar", slot_scalar),
    ("oren_native_canonical", oren_canonical),
    ("oren_native_slot_direct", oren_slot),
]:
    print(f"{name}:")
    print(f"  stdout: {data['stdout']}")
    print(f"  median: {data['median_s']:.6f}s")
    print(f"  per_rep: {data['per_rep_s']:.6f}s")
    print(f"  cov: {data['cov']:.4f}")
    print("")

print(f"slot64_vector/packed_vector per_rep ratio: {(slot_vector['per_rep_s'] / packed_vector['per_rep_s']):.4f}x")
print(f"slot64_scalar/packed_scalar per_rep ratio: {(slot_scalar['per_rep_s'] / packed_scalar['per_rep_s']):.4f}x")
print(f"oren_slot/slot64_scalar per_rep ratio: {(oren_slot['per_rep_s'] / slot_scalar['per_rep_s']):.4f}x")
print(f"oren_slot/slot64_vector per_rep ratio: {(oren_slot['per_rep_s'] / slot_vector['per_rep_s']):.4f}x")
print(f"oren_canonical/slot64_scalar per_rep ratio: {(oren_canonical['per_rep_s'] / slot_scalar['per_rep_s']):.4f}x")
print(f"oren_canonical/slot64_vector per_rep ratio: {(oren_canonical['per_rep_s'] / slot_vector['per_rep_s']):.4f}x")
print(f"oren_canonical/packed_vector per_rep ratio: {(oren_canonical['per_rep_s'] / packed_vector['per_rep_s']):.4f}x")
print(f"oren_canonical/oren_slot per_rep ratio: {(oren_canonical['per_rep_s'] / oren_slot['per_rep_s']):.4f}x")
print("")

for name, path, prefer_vector in loop_specs:
    label, block = extract_loop(read_lines(path), prefer_vector)
    total, counts = count_mnemonics(block)
    print(f"{name}_loop_label: {label}")
    print(f"{name}_loop_insns: {total}")
    print(f"{name}_loop_counts: {fmt_counts(counts)}")
    print(f"{name}_loop:")
    for line in block:
        print(f"  {line}")
    print("")
PY

echo "list<int> slot ABI ceiling probe complete; summary: $summary_log"
