#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ "$#" -ne 4 ]; then
  echo "usage: scripts/build_native_ir_llvm_backend.sh <compiler> <source.oren> <platform> <out.o>" >&2
  exit 2
fi

compiler="$1"
src="$2"
platform="$3"
object_out="$4"

out_dir="$(dirname "$object_out")"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"
native_ir_json="$object_out.native_ir.json"
llvm_ir="$object_out.ll"
manifest="$object_out.manifest.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_backend_toolchain.log"
dump_log="$log_dir/native_ir_llvm_backend_dump.log"
lower_log="$log_dir/native_ir_llvm_backend_lower.log"
llc_log="$log_dir/native_ir_llvm_backend_llc.log"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

llc_path="$(read_report_value llc_path)"
if [ -z "$llc_path" ] || [ "$llc_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: full LLVM toolchain is required for --backend llvm-native" >&2
  exit 1
fi

"$compiler" dump native-ir "$src" --platform "$platform" -o "$native_ir_json" >"$dump_log" 2>&1
NATIVE_IR_LLVM_REQUIRE_HELPERS="${NATIVE_IR_LLVM_REQUIRE_HELPERS:-0}" python3 scripts/native_ir_llvm_lower.py "$native_ir_json" "$platform" "$llvm_ir" >"$lower_log" 2>&1
"$llc_path" -filetype=obj "$llvm_ir" -o "$object_out" >"$llc_log" 2>&1
test -s "$object_out"

{
  printf 'native_ir_llvm_backend_v0\n'
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'platform=%s\n' "$platform"
  printf 'native_ir=%s\n' "$native_ir_json"
  printf 'llvm_ir=%s\n' "$llvm_ir"
  printf 'object=%s\n' "$object_out"
  printf 'llc_path=%s\n' "$llc_path"
  printf 'toolchain_report=%s\n' "$toolchain_report"
} >"$manifest"

cat "$toolchain_log"
cat "$lower_log"
echo "LLVM object emitted: $object_out"
