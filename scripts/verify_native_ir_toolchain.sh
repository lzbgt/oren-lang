#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

out_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
report="$out_dir/toolchain.txt"
require_llvm="${NATIVE_IR_REQUIRE_LLVM:-0}"

mkdir -p "$out_dir"

tool_path() {
  command -v "$1" 2>/dev/null || true
}

tool_version_first_line() {
  local path="$1"
  if [ -z "$path" ]; then
    printf 'missing'
    return 0
  fi
  "$path" --version 2>/dev/null | sed -n '1p' || printf 'unknown'
}

clang_path="$(tool_path clang)"
llvm_config_path="$(tool_path llvm-config)"
llc_path="$(tool_path llc)"

clang_status="missing"
llvm_config_status="missing"
llc_status="missing"
if [ -n "$clang_path" ]; then clang_status="present"; fi
if [ -n "$llvm_config_path" ]; then llvm_config_status="present"; fi
if [ -n "$llc_path" ]; then llc_status="present"; fi

llvm_ready=0
if [ "$clang_status" = "present" ] && [ "$llvm_config_status" = "present" ] && [ "$llc_status" = "present" ]; then
  llvm_ready=1
fi

{
  printf 'native_ir_toolchain_v0\n'
  printf 'host_os=%s\n' "$(uname -s 2>/dev/null || printf unknown)"
  printf 'host_arch=%s\n' "$(uname -m 2>/dev/null || printf unknown)"
  printf 'clang_status=%s\n' "$clang_status"
  printf 'clang_path=%s\n' "${clang_path:-missing}"
  printf 'clang_version=%s\n' "$(tool_version_first_line "$clang_path")"
  printf 'llvm_config_status=%s\n' "$llvm_config_status"
  printf 'llvm_config_path=%s\n' "${llvm_config_path:-missing}"
  if [ -n "$llvm_config_path" ]; then
    printf 'llvm_config_version=%s\n' "$("$llvm_config_path" --version 2>/dev/null || printf unknown)"
    printf 'llvm_config_targets=%s\n' "$("$llvm_config_path" --targets-built 2>/dev/null || printf unknown)"
  else
    printf 'llvm_config_version=missing\n'
    printf 'llvm_config_targets=missing\n'
  fi
  printf 'llc_status=%s\n' "$llc_status"
  printf 'llc_path=%s\n' "${llc_path:-missing}"
  printf 'llc_version=%s\n' "$(tool_version_first_line "$llc_path")"
  printf 'llvm_ready=%s\n' "$llvm_ready"
  printf 'require_llvm=%s\n' "$require_llvm"
} >"$report"

cat "$report"

if [ "$require_llvm" = "1" ] && [ "$llvm_ready" != "1" ]; then
  echo "ERROR: native IR LLVM backend work requires clang, llvm-config, and llc." >&2
  echo "       Install a full LLVM toolchain or unset NATIVE_IR_REQUIRE_LLVM for detect-only mode." >&2
  exit 1
fi

echo "OK: native IR toolchain detection report written to $report"
