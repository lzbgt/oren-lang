#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
out_dir="build/native_ir/llvm_smoke"
log_dir="build/logs"
mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_smoke_toolchain.log"
hello_log="$log_dir/native_ir_llvm_smoke_hello.log"
arith_log="$log_dir/native_ir_llvm_smoke_arith.log"
reject_log="$log_dir/native_ir_llvm_smoke_test_reject.log"
runtime_log="$log_dir/native_ir_llvm_smoke_runtime.log"
helper_runtime_log="$log_dir/native_ir_llvm_smoke_helper_runtime.log"
exit_runtime_log="$log_dir/native_ir_llvm_smoke_exit_runtime.log"
string_runtime_log="$log_dir/native_ir_llvm_smoke_string_runtime.log"
string_eq_runtime_log="$log_dir/native_ir_llvm_smoke_string_eq_runtime.log"
string_slice_runtime_log="$log_dir/native_ir_llvm_smoke_string_slice_runtime.log"
string_access_runtime_log="$log_dir/native_ir_llvm_smoke_string_access_runtime.log"
list_runtime_log="$log_dir/native_ir_llvm_smoke_list_runtime.log"
summary="$out_dir/summary.txt"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

"$compiler" build examples/hello.oren --backend llvm-native --platform x64-linux --no-cache -o "$out_dir/hello_x64_linux.o" >"$hello_log" 2>&1
test -s "$out_dir/hello_x64_linux.o"
test -s "$out_dir/hello_x64_linux.o.native_ir.json"
test -s "$out_dir/hello_x64_linux.o.ll"
grep -Fq "; helper " "$out_dir/hello_x64_linux.o.ll"
grep -Fq "LLVM object emitted: $out_dir/hello_x64_linux.o" "$hello_log"

"$compiler" build tests/fixtures/x64_div_mod_main.oren --backend llvm-native --platform arm64-macos --no-cache -o "$out_dir/div_mod_arm64_macos.o" >"$arith_log" 2>&1
test -s "$out_dir/div_mod_arm64_macos.o"
test -s "$out_dir/div_mod_arm64_macos.o.native_ir.json"
test -s "$out_dir/div_mod_arm64_macos.o.ll"
grep -Fq "target triple = \"arm64-apple-macosx\"" "$out_dir/div_mod_arm64_macos.o.ll"
grep -Fq "LLVM object emitted: $out_dir/div_mod_arm64_macos.o" "$arith_log"

if "$compiler" test examples/hello.oren --backend llvm-native --platform x64-linux >"$reject_log" 2>&1; then
  echo "ERROR: llvm-native test backend unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq "compile-only" "$reject_log"

./scripts/verify_native_ir_llvm_runtime.sh "$compiler" >"$runtime_log" 2>&1
./scripts/verify_native_ir_llvm_helper_runtime.sh "$compiler" >"$helper_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_exit_runtime.sh "$compiler" >"$exit_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_string_runtime.sh "$compiler" >"$string_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_string_eq_runtime.sh "$compiler" >"$string_eq_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_string_slice_runtime.sh "$compiler" >"$string_slice_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_string_access_runtime.sh "$compiler" >"$string_access_runtime_log" 2>&1
./scripts/verify_native_ir_llvm_list_runtime.sh "$compiler" >"$list_runtime_log" 2>&1

end="$(date +%s)"
{
  printf 'native_ir_llvm_smoke_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'hello_object=%s\n' "$out_dir/hello_x64_linux.o"
  printf 'arith_object=%s\n' "$out_dir/div_mod_arm64_macos.o"
  printf 'runtime_summary=build/native_ir/llvm_runtime/summary.txt\n'
  printf 'helper_runtime_summary=build/native_ir/llvm_helper_runtime/summary.txt\n'
  printf 'exit_runtime_summary=build/native_ir/llvm_exit_runtime/summary.txt\n'
  printf 'string_runtime_summary=build/native_ir/llvm_string_runtime/summary.txt\n'
  printf 'string_eq_runtime_summary=build/native_ir/llvm_string_eq_runtime/summary.txt\n'
  printf 'string_slice_runtime_summary=build/native_ir/llvm_string_slice_runtime/summary.txt\n'
  printf 'string_access_runtime_summary=build/native_ir/llvm_string_access_runtime/summary.txt\n'
  printf 'list_runtime_summary=build/native_ir/llvm_list_runtime/summary.txt\n'
  printf 'coverage=toolchain,llvm-native-build-dispatch,native-ir-dump,llvm-lower,llc-object,helper-call,helper-free-arith,test-reject,llvm-link,llvm-execute,named-print-helper,named-exit-helper,named-oren-string-len-helper,named-oren-string-eq-helper,named-oren-string-slice-helper,named-oren-string-access-helpers,llvm-list-descriptor-layout,helper-execute,exit-status,string-helper-execute,string-eq-helper-execute,string-slice-helper-execute,string-access-helper-execute,list-helper-execute,forced-gc-at-generated-helper-safepoint\n'
} >"$summary"

echo "OK: native IR LLVM smoke passed; summary: $summary"
