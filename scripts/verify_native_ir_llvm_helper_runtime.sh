#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="tests/fixtures/x64_print_main.oren"
out_dir="build/native_ir/llvm_helper_runtime"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_helper_runtime_toolchain.log"
native_log="$log_dir/native_ir_llvm_helper_runtime_native.log"
llvm_build_log="$log_dir/native_ir_llvm_helper_runtime_build.log"
link_log="$log_dir/native_ir_llvm_helper_runtime_link.log"
llvm_run_log="$log_dir/native_ir_llvm_helper_runtime_run.log"
summary="$out_dir/summary.txt"
harness="$out_dir/helper_harness.c"
object="$out_dir/helper_arm64_macos.o"
native_bin="$out_dir/native_oracle"
llvm_bin="$out_dir/llvm_helper_probe"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

clang_path="$(read_report_value clang_path)"
if [ -z "$clang_path" ] || [ "$clang_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: clang is required for native IR LLVM helper runtime linking" >&2
  exit 1
fi

"$compiler" build "$src" --backend native --platform arm64-macos --no-cache -o "$native_bin" >"$native_log" 2>&1
"$native_bin" >>"$native_log" 2>&1
grep -Fq "x64 hello" "$native_log"

"$compiler" build "$src" --backend llvm-native --platform arm64-macos --no-cache -o "$object" >"$llvm_build_log" 2>&1
test -s "$object"
test -s "$object.ll"
grep -Fq "; helper print" "$object.ll"
grep -Fq "@oren_llvm_runtime_helper(i64" "$object.ll"

cat >"$harness" <<'C'
#include <stdint.h>
#include <stdio.h>

static int64_t helper_calls = 0;
static int64_t helper_argc = -1;
static int64_t helper_arg0 = -1;

int64_t oren_llvm_runtime_helper(int64_t helper_id, int64_t argc, int64_t arg0, int64_t arg1, int64_t arg2, int64_t arg3) {
    (void)helper_id;
    (void)arg1;
    (void)arg2;
    (void)arg3;
    helper_calls += 1;
    helper_argc = argc;
    helper_arg0 = arg0;
    puts("x64 hello");
    return 0;
}

extern int64_t oren_native_ir_main_probe(void);

int main(void) {
    int64_t rc = oren_native_ir_main_probe();
    if (rc != 0 || helper_calls != 1 || helper_argc != 1 || helper_arg0 <= 0) {
        fprintf(stderr, "rc=%lld helper_calls=%lld argc=%lld arg0=%lld\n",
                (long long)rc, (long long)helper_calls, (long long)helper_argc, (long long)helper_arg0);
        return 1;
    }
    return 0;
}
C

"$clang_path" "$harness" "$object" -o "$llvm_bin" >"$link_log" 2>&1
"$llvm_bin" >"$llvm_run_log" 2>&1
grep -Fq "x64 hello" "$llvm_run_log"

end="$(date +%s)"
{
  printf 'native_ir_llvm_helper_runtime_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'native_oracle=%s\n' "$native_bin"
  printf 'llvm_object=%s\n' "$object"
  printf 'llvm_executable=%s\n' "$llvm_bin"
  printf 'coverage=host-arm64-macos,native-oracle,llvm-link,llvm-execute,runtime-helper-symbol,helper-argc,helper-arg0,print-output\n'
} >"$summary"

echo "OK: native IR LLVM helper runtime parity passed; summary: $summary"
