#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/list_int_fast_lowering"
mkdir -p "$log_dir" "$tmp_dir"
log_path="$log_dir/verify_native_list_int_fast_lowering_${ts}.log"
build_seq=0
last_build_log=""

run_build() {
  local label="$1"
  local src="$2"
  local out="$3"
  shift 3
  build_seq=$((build_seq + 1))
  last_build_log="${tmp_dir}/trace_${build_seq}.log"

  {
    echo "== ${label} =="
    echo "src=${src}"
    echo "out=${out}"
    "$@"
  } >"$last_build_log" 2>&1
  cat "$last_build_log" >>"$log_path"
}

check_expect() {
  local label="$1"
  local expect="$2"

  if ! grep -Eq "$expect" "$last_build_log"; then
    echo "verify_native_list_int_fast_lowering: missing expected trace for ${label}" | tee -a "$log_path" >&2
    echo "expected regex: ${expect}" | tee -a "$log_path" >&2
    exit 1
  fi
}

build_and_check() {
  local label="$1"
  local src="$2"
  local out="$3"
  local expect="$4"
  shift 4

  run_build "$label" "$src" "$out" "$@"
  check_expect "$label" "$expect"
}

build_and_check \
  "arm64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_arm64" \
  'fast_list_int_get_sum_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/array_sum_int_arm64"

run_build \
  "arm64 canonical array_sum auto-list<int> lowerings" \
  "benchmarks/array_sum/array_sum.oren" \
  "${tmp_dir}/array_sum_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/array_sum/array_sum.oren --backend native --no-debug --no-cache -o "${tmp_dir}/array_sum_arm64"
check_expect "arm64 canonical array_sum push lowering" 'fast_list_int_push_while(_no_tick)?'
check_expect "arm64 canonical array_sum get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'

build_and_check \
  "arm64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_arm64" \
  'fast_list_int_dot_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/dot_product_int_arm64"

run_build \
  "arm64 canonical dot_product auto-list<int> lowerings" \
  "benchmarks/dot_product/dot_product.oren" \
  "${tmp_dir}/dot_product_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/dot_product/dot_product.oren --backend native --no-debug --no-cache -o "${tmp_dir}/dot_product_arm64"
check_expect "arm64 canonical dot_product push lowering" 'fast_list_int_push_while(_no_tick)?'
check_expect "arm64 canonical dot_product dot lowering" 'fast_list_int_dot_while(_no_tick)?'

build_and_check \
  "x64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_get_sum_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/array_sum_int/array_sum_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/array_sum_int_x64_linux"

build_and_check \
  "x64 canonical array_sum auto-list<int> get-sum lowering" \
  "benchmarks/array_sum/array_sum.oren" \
  "${tmp_dir}/array_sum_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_get_sum_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/array_sum/array_sum.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/array_sum_x64_linux"

build_and_check \
  "x64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_dot_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/dot_product_int/dot_product_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/dot_product_int_x64_linux"

build_and_check \
  "x64 canonical dot_product auto-list<int> dot lowering" \
  "benchmarks/dot_product/dot_product.oren" \
  "${tmp_dir}/dot_product_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_dot_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/dot_product/dot_product.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/dot_product_x64_linux"

run_build \
  "arm64 commuted list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_commuted.oren" \
  "${tmp_dir}/list_int_fast_lowering_commuted_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build tests/fixtures/list_int_fast_lowering_commuted.oren --backend native --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_commuted_arm64"
check_expect "arm64 commuted list<int> get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'
check_expect "arm64 commuted list<int> dot lowering" 'fast_list_int_dot_while(_no_tick)?'

run_build \
  "x64 commuted list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_commuted.oren" \
  "${tmp_dir}/list_int_fast_lowering_commuted_x64_linux" \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build tests/fixtures/list_int_fast_lowering_commuted.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_commuted_x64_linux"
check_expect "x64 commuted list<int> get-sum lowering" '\[x64_list_fast\].*kind=fast_list_int_get_sum_while'
check_expect "x64 commuted list<int> dot lowering" '\[x64_list_fast\].*kind=fast_list_int_dot_while'

run_build \
  "arm64 temp-normalized list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_temp.oren" \
  "${tmp_dir}/list_int_fast_lowering_temp_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build tests/fixtures/list_int_fast_lowering_temp.oren --backend native --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_temp_arm64"
check_expect "arm64 temp-normalized list<int> get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'
check_expect "arm64 temp-normalized list<int> dot lowering" 'fast_list_int_dot_while(_no_tick)?'

run_build \
  "x64 temp-normalized list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_temp.oren" \
  "${tmp_dir}/list_int_fast_lowering_temp_x64_linux" \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build tests/fixtures/list_int_fast_lowering_temp.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_temp_x64_linux"
check_expect "x64 temp-normalized list<int> get-sum lowering" '\[x64_list_fast\].*kind=fast_list_int_get_sum_while'
check_expect "x64 temp-normalized list<int> dot lowering" '\[x64_list_fast\].*kind=fast_list_int_dot_while'

echo "native list<int> fast-lowering verify complete; log: $log_path"
