#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
tmp_dir="build/tmp/list_int_fast_lowering"
mkdir -p "$log_dir" "$tmp_dir"
log_path="$log_dir/verify_native_list_int_fast_lowering_${ts}.log"

build_and_check() {
  local label="$1"
  local src="$2"
  local out="$3"
  local expect="$4"
  shift 4

  {
    echo "== ${label} =="
    echo "src=${src}"
    echo "out=${out}"
    "$@"
  } >>"$log_path" 2>&1

  if ! grep -Eq "$expect" "$log_path"; then
    echo "verify_native_list_int_fast_lowering: missing expected trace for ${label}" | tee -a "$log_path" >&2
    echo "expected regex: ${expect}" | tee -a "$log_path" >&2
    exit 1
  fi
}

build_and_check \
  "arm64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_arm64" \
  'fast_list_int_get_sum_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/array_sum_int_arm64"

build_and_check \
  "arm64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_arm64" \
  'fast_list_int_dot_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/dot_product_int_arm64"

build_and_check \
  "x64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_get_sum_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/array_sum_int/array_sum_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/array_sum_int_x64_linux"

build_and_check \
  "x64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_dot_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/dot_product_int/dot_product_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/dot_product_int_x64_linux"

echo "native list<int> fast-lowering verify complete; log: $log_path"
