#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bin="build/tmp/alloc_churn_len128_smoke"
build_log="build/logs/alloc_churn_len128_smoke_build.log"
expected="10"

mkdir -p build/tmp build/logs

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_case() {
  local case_name="$1"
  shift
  local out
  out="$(env "$@" "$bin")"
  if [[ "$out" != "$expected" ]]; then
    echo "case=$case_name expected=$expected actual=$out" >&2
    fail "alloc_churn len128 smoke mismatch"
  fi
}

env OREN_NO_CACHE=1 ./oren_stage2 build benchmarks/alloc_churn/alloc_churn.oren \
  --backend native --no-debug --no-cache -o "$bin" >"$build_log" 2>&1

run_case boxed_default OREN_BENCH_ITERS=5
run_case list_int_default OREN_BENCH_ITERS=5 OREN_BENCH_FORCE_LIST_INT=1
run_case boxed_override_len OREN_BENCH_ITERS=5 OREN_BENCH_LIST_LEN=128
run_case list_int_override_len OREN_BENCH_ITERS=5 OREN_BENCH_FORCE_LIST_INT=1 OREN_BENCH_LIST_LEN=128

echo "OK: alloc_churn len128 smoke verified"
