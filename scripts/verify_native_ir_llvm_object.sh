#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="${NATIVE_IR_LLVM_SOURCE:-examples/hello.oren}"
platform="${NATIVE_IR_LLVM_PLATFORM:-x64-linux}"
out_dir="${NATIVE_IR_LLVM_OUT_DIR:-build/native_ir/llvm_object}"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_object_toolchain.log"
dump_log="$log_dir/native_ir_llvm_object_dump.log"
emit_log="$log_dir/native_ir_llvm_object_emit.log"
manifest="$out_dir/manifest.txt"
native_ir_json="$out_dir/input.native_ir.json"
llvm_ir="$out_dir/probe.ll"
object_out="$out_dir/probe.o"

if ! ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1; then
  cat "$toolchain_log"
  exit 1
fi

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

llvm_ready="$(read_report_value llvm_ready)"
llc_path="$(read_report_value llc_path)"

"$compiler" dump native-ir "$src" --platform "$platform" -o "$native_ir_json" >"$dump_log" 2>&1
python3 scripts/native_ir_llvm_lower.py "$native_ir_json" "$platform" "$llvm_ir" >"$emit_log" 2>&1

test -s "$llvm_ir"
grep -Fq "native_ir_llvm_lowered_subset_v0" "$llvm_ir"
grep -Fq "define i64 @oren_native_ir_main_probe()" "$llvm_ir"
if [ "${NATIVE_IR_LLVM_REQUIRE_BRANCH:-1}" = "1" ]; then
  grep -Fq "br i1" "$llvm_ir"
fi
if [ "${NATIVE_IR_LLVM_REQUIRE_HELPERS:-1}" = "1" ]; then
  grep -Fq "; helper " "$llvm_ir"
fi

{
  printf 'native_ir_llvm_object_v0\n'
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'platform=%s\n' "$platform"
  printf 'native_ir=%s\n' "$native_ir_json"
  printf 'llvm_ir=%s\n' "$llvm_ir"
  printf 'type_layout=tagged:64:8,void:0:1\n'
  printf 'lowerer=scripts/native_ir_llvm_lower.py\n'
  printf 'toolchain_report=%s\n' "$toolchain_report"
  printf 'llvm_ready=%s\n' "$llvm_ready"
} >"$manifest"

if [ "$llvm_ready" != "1" ]; then
  {
    printf 'status=skipped\n'
    printf 'reason=missing_full_llvm_toolchain\n'
    printf 'object=%s\n' "$object_out"
  } >>"$manifest"
  cat "$toolchain_log"
  cat "$emit_log"
  echo "SKIP: native IR LLVM object probe requires clang, llvm-config, and llc; see $manifest"
  exit 0
fi

"$llc_path" -filetype=obj "$llvm_ir" -o "$object_out" >>"$emit_log" 2>&1
test -s "$object_out"

{
  printf 'status=emitted\n'
  printf 'llvm_ir=%s\n' "$llvm_ir"
  printf 'object=%s\n' "$object_out"
  printf 'llc_path=%s\n' "$llc_path"
} >>"$manifest"

cat "$toolchain_log"
cat "$emit_log"
echo "OK: native IR LLVM object probe emitted $object_out"
