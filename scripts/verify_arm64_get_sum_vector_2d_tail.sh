#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/verify-arm64-get-sum-vector-2d-tail-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

log_path="$log_dir/verify_arm64_get_sum_vector_2d_tail_${ts}.log"
build_env="OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1"
cases=(0 1 2 3 4 5 10 11 20 21)

expected_for_n() {
    python3 - "$1" <<'PY'
import sys

n = int(sys.argv[1])
total = 0
for i in range(n):
    total += (i * 3 + 7) % 1000
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
        env OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1 \
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
    actual="$("$bin" "$n" 1 2>>"$log_path" | tr -d '\r')"
    echo "[run] ${program} n=${n} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "arm64 get-sum vector-2d tail verify failed for ${program} n=${n}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

: >"$log_path"
array_bin="$(build_one array_sum_int)"

for n in "${cases[@]}"; do
    run_case array_sum_int "$array_bin" "$n"
done

echo "arm64 get-sum vector-2d tail verify complete; log: $log_path"
