#!/usr/bin/env bash
set -euo pipefail

# Compile-only verification for x86_64 native backend targets.
#
# Purpose (rolling, fast):
# - Ensure both stage1 (`./oren`) and stage2 (`./oren_stage2`) can emit:
#   - x64-linux ELF
#   - x64-windows PE32+
# - Does not attempt to run the artifacts (requires remote/WSL); this is a local sanity gate.
#
# This script intentionally stays quiet and bounded. If a build fails, it prints the failing command.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin file
need_bin make
need_bin python3

mkdir -p build/tmp

QI_SRC="tests/native/test_quick_integration_native.oren"
PRINT_SRC="tests/native/print.oren"
PRINT_NEEDLE="hello from native"
WIN_FFI_K32_SRC="tests/native/ffi_windows_kernel32.oren"
WIN_FFI_MSVCRT_SRC="tests/native/ffi.oren"
BUILD_TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"

run_with_timeout() {
  local secs="$1"
  shift
  set +e
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  local killer=$!
  wait "$pid"
  local rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  set -e
  return "$rc"
}

if [[ ! -x ./oren ]]; then
  echo "== ensure: stage1 compiler (./oren) ==" >&2
  make stage1
fi
if [[ ! -x ./oren_stage2 ]]; then
  echo "== ensure: stage2 compiler (./oren_stage2) ==" >&2
  make stage2
fi

build_one() {
  local compiler="$1"
  local platform="$2"
  local src="$3"
  local out="$4"
  shift 4

  echo "== build: $compiler -> $platform ==" >&2
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform "$platform" --no-cache --no-debug "$@" -o "$out"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform timeout=${BUILD_TIMEOUT_SECS}s" >&2
    return "$rc"
  fi
}

check_elf_x64() {
  local p="$1"
  file "$p" | grep -qE 'ELF 64-bit.*x86-64'
}

check_pe_x64() {
  local p="$1"
  file "$p" | grep -qE 'PE32\+'
}

check_pe_x64_entry_disp8_zero_sane() {
  # Regression guard (native backend semantics):
  # x86_64 encoding requires a disp8=0 byte for [rbp] / [r13] addressing.
  # When an "optional byte" is represented as `0`, native-backend `nil==0` can cause
  # the displacement byte to be omitted, shifting the instruction stream and producing
  # a binary that crashes immediately at process entry on Windows.
  #
  # We check for the presence of the correct bytes and the absence of the known-bad pattern.
  local p="$1"
  python3 - <<'PY' "$p"
import sys
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_bytes()

good = bytes.fromhex("4d 89 65 00 49 81 c5 08")
bad  = bytes.fromhex("4d 89 65 49 81 c5 08")

if data.find(bad) != -1:
    print(f"ERROR: detected known-bad x64 disp8=0 omission pattern in {p}", file=sys.stderr)
    sys.exit(2)
if data.find(good) == -1:
    print(f"ERROR: missing expected x64 disp8=0 prologue pattern in {p}", file=sys.stderr)
    sys.exit(3)
PY
}

check_bin_contains() {
  local p="$1"
  local needle="$2"
  if command -v strings >/dev/null 2>&1; then
    strings -a "$p" | grep -qiF "$needle"
  fi
}

build_one ./oren x64-linux "$QI_SRC" build/tmp/qi_stage1_x64_linux
check_elf_x64 build/tmp/qi_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$QI_SRC" build/tmp/qi_stage2_x64_linux
check_elf_x64 build/tmp/qi_stage2_x64_linux

build_one ./oren x64-linux "$PRINT_SRC" build/tmp/print_stage1_x64_linux
check_elf_x64 build/tmp/print_stage1_x64_linux
check_bin_contains build/tmp/print_stage1_x64_linux "$PRINT_NEEDLE"

build_one ./oren_stage2 x64-linux "$PRINT_SRC" build/tmp/print_stage2_x64_linux
check_elf_x64 build/tmp/print_stage2_x64_linux
check_bin_contains build/tmp/print_stage2_x64_linux "$PRINT_NEEDLE"

build_one ./oren x64-windows "$QI_SRC" build/tmp/qi_stage1_x64_windows.exe
check_pe_x64 build/tmp/qi_stage1_x64_windows.exe
check_pe_x64_entry_disp8_zero_sane build/tmp/qi_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$QI_SRC" build/tmp/qi_stage2_x64_windows.exe
check_pe_x64 build/tmp/qi_stage2_x64_windows.exe
check_pe_x64_entry_disp8_zero_sane build/tmp/qi_stage2_x64_windows.exe

build_one ./oren x64-windows "$PRINT_SRC" build/tmp/print_stage1_x64_windows.exe
check_pe_x64 build/tmp/print_stage1_x64_windows.exe
check_bin_contains build/tmp/print_stage1_x64_windows.exe "$PRINT_NEEDLE"

build_one ./oren_stage2 x64-windows "$PRINT_SRC" build/tmp/print_stage2_x64_windows.exe
check_pe_x64 build/tmp/print_stage2_x64_windows.exe
check_bin_contains build/tmp/print_stage2_x64_windows.exe "$PRINT_NEEDLE"

build_one ./oren x64-windows "$WIN_FFI_K32_SRC" build/tmp/ffi_k32_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_k32_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$WIN_FFI_K32_SRC" build/tmp/ffi_k32_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_k32_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_MSVCRT_SRC" build/tmp/ffi_msvcrt_stage1_x64_windows.exe --link msvcrt.dll
check_pe_x64 build/tmp/ffi_msvcrt_stage1_x64_windows.exe
check_bin_contains build/tmp/ffi_msvcrt_stage1_x64_windows.exe "msvcrt.dll"

build_one ./oren_stage2 x64-windows "$WIN_FFI_MSVCRT_SRC" build/tmp/ffi_msvcrt_stage2_x64_windows.exe --link msvcrt.dll
check_pe_x64 build/tmp/ffi_msvcrt_stage2_x64_windows.exe
check_bin_contains build/tmp/ffi_msvcrt_stage2_x64_windows.exe "msvcrt.dll"

echo "OK: x64 compile-only verification passed" >&2
