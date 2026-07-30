#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
out_dir="build/native_ir/llvm_backend"
log_dir="build/logs"
mkdir -p "$out_dir" "$log_dir"

hello_log="$log_dir/native_ir_llvm_backend_hello.log"
arith_log="$log_dir/native_ir_llvm_backend_arith.log"
reject_log="$log_dir/native_ir_llvm_backend_test_reject.log"

"$compiler" build examples/hello.oren --backend llvm-native --platform x64-linux --no-cache -o "$out_dir/hello_x64_linux.o" >"$hello_log" 2>&1
test -s "$out_dir/hello_x64_linux.o"
test -s "$out_dir/hello_x64_linux.o.native_ir.json"
test -s "$out_dir/hello_x64_linux.o.ll"
test -s "$out_dir/hello_x64_linux.o.manifest.txt"
grep -Fq "LLVM object emitted: $out_dir/hello_x64_linux.o" "$hello_log"
grep -Fq "; helper " "$out_dir/hello_x64_linux.o.ll"

"$compiler" build tests/fixtures/x64_div_mod_main.oren --backend llvm-native --platform arm64-macos --no-cache -o "$out_dir/div_mod_arm64_macos.o" >"$arith_log" 2>&1
test -s "$out_dir/div_mod_arm64_macos.o"
grep -Fq "LLVM object emitted: $out_dir/div_mod_arm64_macos.o" "$arith_log"

if "$compiler" test examples/hello.oren --backend llvm-native --platform x64-linux >"$reject_log" 2>&1; then
  echo "ERROR: llvm-native test backend unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq "compile-only" "$reject_log"

echo "OK: llvm-native build backend emitted validated LLVM objects under $out_dir"
