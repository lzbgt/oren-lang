#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="tests/fixtures/native_ir_llvm_bytes_main.oren"
out_dir="build/native_ir/llvm_bytes_runtime"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_bytes_runtime_toolchain.log"
native_log="$log_dir/native_ir_llvm_bytes_runtime_native.log"
llvm_build_log="$log_dir/native_ir_llvm_bytes_runtime_build.log"
link_log="$log_dir/native_ir_llvm_bytes_runtime_link.log"
llvm_run_log="$log_dir/native_ir_llvm_bytes_runtime_run.log"
summary="$out_dir/summary.txt"
harness="$out_dir/bytes_harness.c"
object="$out_dir/bytes_arm64_macos.o"
native_bin="$out_dir/native_oracle"
llvm_bin="$out_dir/llvm_bytes_probe"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

clang_path="$(read_report_value clang_path)"
if [ -z "$clang_path" ] || [ "$clang_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: clang is required for native IR LLVM bytes runtime linking" >&2
  exit 1
fi

"$compiler" build "$src" --backend native --platform arm64-macos --no-cache -o "$native_bin" >"$native_log" 2>&1
"$native_bin" >>"$native_log" 2>&1

"$compiler" build "$src" --backend llvm-native --platform arm64-macos --no-cache -o "$object" >"$llvm_build_log" 2>&1
test -s "$object"
test -s "$object.ll"
grep -Fq "%oren_llvm_bytes = type { i64, i8*, i64 }" "$object.ll"
grep -Fq "define i64 @oren_llvm_runtime_alloc_bytes_desc" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_hex_nibble" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_bytes_from_hex" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_bytes_len" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_bytes_get_u8" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_register_bytes(i64, i8*, i64)" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_roots_push_bytes(i64)" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_register_bytes" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_roots_push_bytes" "$object.ll"
grep -Fq "call i8* @oren_llvm_runtime_alloc_bytes(i64 %len, i64 5)" "$object.ll"
grep -Fq "store i64 1, i64* %ownerp, align 8" "$object.ll"
if grep -Fq "declare i64 @oren_llvm_helper_oren_bytes_len(i64, i64, i64, i64, i64)" "$object.ll" ||
   grep -Fq "declare i64 @oren_llvm_helper_oren_bytes_get_u8(i64, i64, i64, i64, i64)" "$object.ll"; then
  echo "ERROR: descriptor-backed bytes helpers fell back to generic runtime declarations" >&2
  exit 1
fi

cat >"$harness" <<'C'
#include <stdint.h>
#include <stdio.h>

extern int64_t oren_native_ir_main_probe(void);
extern int64_t oren_llvm_runtime_registered_bytes(void);
extern int64_t oren_llvm_runtime_root_depth(void);
extern int64_t oren_llvm_runtime_root_pushes(void);
extern int64_t oren_llvm_runtime_safepoint_collections(void);

int main(void) {
    int64_t rc = oren_native_ir_main_probe();
    if (rc != 0) {
        fprintf(stderr, "oren_native_ir_main_probe returned %lld\n", (long long)rc);
        return 1;
    }
    if (oren_llvm_runtime_registered_bytes() < 2) {
        fprintf(stderr, "expected registered LLVM bytes descriptors\n");
        return 1;
    }
    if (oren_llvm_runtime_root_pushes() < 1) {
        fprintf(stderr, "expected LLVM bytes descriptor roots across helper safepoints\n");
        return 1;
    }
    if (oren_llvm_runtime_safepoint_collections() < 1) {
        fprintf(stderr, "expected forced LLVM bytes safepoint collection\n");
        return 1;
    }
    if (oren_llvm_runtime_root_depth() != 0) {
        fprintf(stderr, "expected LLVM descriptor roots to reset after bytes helper calls\n");
        return 1;
    }
    return 0;
}
C

"$clang_path" "$harness" "$object" lib/runtime.c lib/runtime_buf.c -Ilib -pthread -o "$llvm_bin" >"$link_log" 2>&1
OREN_LLVM_FORCE_GC_AT_SAFEPOINT=1 "$llvm_bin" >"$llvm_run_log" 2>&1

end="$(date +%s)"
{
  printf 'native_ir_llvm_bytes_runtime_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'native_oracle=%s\n' "$native_bin"
  printf 'llvm_object=%s\n' "$object"
  printf 'llvm_executable=%s\n' "$llvm_bin"
  printf 'coverage=host-arm64-macos,native-oracle,llvm-link,llvm-execute,real-c-runtime-hooks,llvm-bytes-descriptor-layout,bytes-from-hex-helper,bytes-len-helper,bytes-get-u8-helper,bytes-runtime-registration,bytes-safepoint-roots,forced-gc-at-bytes-safepoint\n'
} >"$summary"

echo "OK: native IR LLVM bytes runtime parity passed; summary: $summary"
