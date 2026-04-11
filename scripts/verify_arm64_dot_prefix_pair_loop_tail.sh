#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/verify-arm64-dot-prefix-pair-loop-tail-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

log_path="$log_dir/verify_arm64_dot_prefix_pair_loop_tail_${ts}.log"
build_env="OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1"
cases=(0 1 2 3 10 11 20 21)

expected_for_n() {
    python3 - "$1" <<'PY'
import sys

n = int(sys.argv[1])
total = 0
for i in range(n):
    total += ((i * 3 + 1) % 1000) * ((i * 7 + 2) % 1000)
print(total)
PY
}

build_one() {
    local program="$1"
    local src="benchmarks/${program}/${program}.oren"
    local bin="$tmp_dir/${program}_oren_native"
    {
        echo "[build] ${program}"
        echo "[build_env] ${build_env}"
        env OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1 \
            ./oren_stage2 build "$src" --backend native --no-debug --no-cache -o "$bin"
    } >>"$log_path" 2>&1
    printf '%s\n' "$bin"
}

run_case() {
    local program="$1"
    local bin="$2"
    local n="$3"
    local expected
    expected="$(expected_for_n "$n")"
    local actual
    actual="$("$bin" "$n" 3 2>>"$log_path" | tr -d '\r')"
    echo "[run] ${program} n=${n} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "arm64 dot prefix pair-loop tail verify failed for ${program} n=${n}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

: >"$log_path"
dot_bin="$(build_one dot_product)"
dot_int_bin="$(build_one dot_product_int)"

for n in "${cases[@]}"; do
    run_case dot_product "$dot_bin" "$n"
    run_case dot_product_int "$dot_int_bin" "$n"
done

echo "arm64 dot prefix pair-loop tail verify complete; log: $log_path"
