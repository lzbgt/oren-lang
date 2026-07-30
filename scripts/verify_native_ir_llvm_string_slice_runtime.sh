#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="tests/fixtures/native_ir_llvm_string_slice_main.oren"
out_dir="build/native_ir/llvm_string_slice_runtime"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_string_slice_runtime_toolchain.log"
native_log="$log_dir/native_ir_llvm_string_slice_runtime_native.log"
llvm_build_log="$log_dir/native_ir_llvm_string_slice_runtime_build.log"
link_log="$log_dir/native_ir_llvm_string_slice_runtime_link.log"
llvm_run_log="$log_dir/native_ir_llvm_string_slice_runtime_run.log"
summary="$out_dir/summary.txt"
harness="$out_dir/string_slice_harness.c"
runtime_hooks="tests/fixtures/native_ir_llvm_runtime_hooks.c"
object="$out_dir/string_slice_arm64_macos.o"
native_bin="$out_dir/native_oracle"
llvm_bin="$out_dir/llvm_string_slice_probe"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

clang_path="$(read_report_value clang_path)"
if [ -z "$clang_path" ] || [ "$clang_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: clang is required for native IR LLVM string slice runtime linking" >&2
  exit 1
fi

"$compiler" build "$src" --backend native --platform arm64-macos --no-cache -o "$native_bin" >"$native_log" 2>&1
"$native_bin" >>"$native_log" 2>&1

"$compiler" build "$src" --backend llvm-native --platform arm64-macos --no-cache -o "$object" >"$llvm_build_log" 2>&1
test -s "$object"
test -s "$object.ll"
grep -Fq "; helper oren_string_slice" "$object.ll"
grep -Fq "; helper oren_string_concat" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_string_slice" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_string_concat" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_string_len" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_string_eq" "$object.ll"
grep -Fq "%oren_llvm_string = type { i64, i8*, i64 }" "$object.ll"
grep -Fq "@oren_llvm_string_desc_" "$object.ll"
grep -Fq "define i64 @oren_llvm_runtime_alloc_string" "$object.ll"
grep -Fq "call i64 @oren_llvm_runtime_alloc_string" "$object.ll"
grep -Fq "declare i8* @oren_llvm_runtime_alloc_bytes(i64, i64)" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_register_string(i64, i8*, i64)" "$object.ll"
grep -Fq "call i8* @oren_llvm_runtime_alloc_bytes" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_register_string" "$object.ll"
grep -Fq "store i64 1, i64* %ownerp, align 8" "$object.ll"
grep -Fq "call i8* @memcpy" "$object.ll"
grep -Fq "bcd" "$object.ll"
if grep -Fq "@malloc" "$object.ll"; then
  echo "ERROR: LLVM string slice runtime IR embedded libc malloc instead of runtime allocation hooks" >&2
  exit 1
fi
if grep -Fq "@oren_llvm_runtime_helper" "$object.ll"; then
  echo "ERROR: stale generic LLVM runtime helper dispatcher appeared in string slice runtime IR" >&2
  exit 1
fi

cat >"$harness" <<'C'
#include <stdint.h>
#include <stdio.h>

extern int64_t oren_native_ir_main_probe(void);
extern int64_t oren_llvm_runtime_registered_strings(void);

int main(void) {
    int64_t rc = oren_native_ir_main_probe();
    if (rc != 0) {
        fprintf(stderr, "oren_native_ir_main_probe returned %lld\n", (long long)rc);
        return 1;
    }
    if (oren_llvm_runtime_registered_strings() < 2) {
        fprintf(stderr, "expected slice and concat runtime string registrations\n");
        return 1;
    }
    return 0;
}
C

"$clang_path" "$harness" "$runtime_hooks" "$object" -o "$llvm_bin" >"$link_log" 2>&1
"$llvm_bin" >"$llvm_run_log" 2>&1

end="$(date +%s)"
{
  printf 'native_ir_llvm_string_slice_runtime_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'native_oracle=%s\n' "$native_bin"
  printf 'llvm_object=%s\n' "$object"
  printf 'llvm_executable=%s\n' "$llvm_bin"
  printf 'coverage=host-arm64-macos,native-oracle,llvm-link,llvm-execute,named-oren-string-slice-helper,named-oren-string-concat-helper,runtime-hook-backed-slice-materialization,runtime-hook-backed-concat-materialization,string-owner-metadata,string-runtime-registration,string-len-compose,string-eq-compose\n'
} >"$summary"

echo "OK: native IR LLVM string slice runtime parity passed; summary: $summary"
