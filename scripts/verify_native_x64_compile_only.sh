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
mkdir -p build/logs

QI_SRC="tests/native/test_quick_integration_native.oren"
PRINT_SRC="tests/native/print.oren"
PRINT_NEEDLE="hello from native"
CFG_OS_SRC="tests/native/cfg_os_select.oren"
WIN_FFI_K32_SRC="tests/native/ffi_windows_kernel32.oren"
WIN_FFI_MSVCRT_LINK_ATTR_SRC="tests/native/ffi_windows_msvcrt_attr_link.oren"
WIN_FFI_I32_SRC="tests/native/ffi_windows_ret_i32_signext.oren"
WIN_FFI_U32_SRC="tests/native/ffi_windows_ret_u32_zeroext.oren"
WIN_FFI_VOID_SRC="tests/native/ffi_windows_ret_void_zero.oren"
WIN_FFI_EXPORT_GETPROC_SRC="tests/native/ffi_windows_export_getprocaddress.oren"
LINUX_FFI_OK_SRC="tests/native/ffi_linux_strlen_ok.oren"
LINUX_FFI_I32_SRC="tests/native/ffi_linux_ret_i32_signext.oren"
LINUX_FFI_U32_SRC="tests/native/ffi_linux_ret_u32_zeroext.oren"
LINUX_FFI_VOID_SRC="tests/native/ffi_linux_ret_void_zero.oren"
FFI_GROUP_ITEM_ATTRS_SRC="tests/native/ffi_group_item_attrs.oren"
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
  local ccname
  ccname="$(basename "$compiler")"
  local bname
  bname="$(basename "$src" .oren)"
  local logf="build/logs/x64_compile_only_${ccname}_${platform}_${bname}.log"
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform "$platform" --no-cache --no-debug "$@" -o "$out" >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform timeout=${BUILD_TIMEOUT_SECS}s" >&2
    tail -n 120 "$logf" >&2 || true
    echo "log: $logf" >&2
    return "$rc"
  fi
  # Fail fast on known x86_64 backend hazards that may still exit 0 in some rolling states.
  if grep -Eq 'x64 native v0: missing ABI arg reg|x64 native v0: missing ABI arg regs' "$logf"; then
    echo "ERROR: compiler emitted x64 ABI arg-reg warning (treat as failure)" >&2
    tail -n 120 "$logf" >&2 || true
    echo "log: $logf" >&2
    return 2
  fi
}

check_elf_x64() {
  local p="$1"
  # Avoid `grep -q` under `set -o pipefail` (upstream can SIGPIPE and fail the pipeline).
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
}

check_elf_x64_dyn() {
  local p="$1"
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
  file "$p" | grep -i 'dynamically linked' >/dev/null
}

check_pe_x64() {
  local p="$1"
  file "$p" | grep -F 'PE32+' >/dev/null
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
    strings -a "$p" | grep -iF "$needle" >/dev/null
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

build_one ./oren x64-linux "$CFG_OS_SRC" build/tmp/cfg_os_stage1_x64_linux
check_elf_x64 build/tmp/cfg_os_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$CFG_OS_SRC" build/tmp/cfg_os_stage2_x64_linux
check_elf_x64 build/tmp/cfg_os_stage2_x64_linux

build_one ./oren x64-linux "$LINUX_FFI_OK_SRC" build/tmp/ffi_ok_stage1_x64_linux
check_elf_x64_dyn build/tmp/ffi_ok_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$LINUX_FFI_OK_SRC" build/tmp/ffi_ok_stage2_x64_linux
check_elf_x64_dyn build/tmp/ffi_ok_stage2_x64_linux

build_one ./oren x64-linux "$LINUX_FFI_I32_SRC" build/tmp/ffi_i32_stage1_x64_linux
check_elf_x64_dyn build/tmp/ffi_i32_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$LINUX_FFI_I32_SRC" build/tmp/ffi_i32_stage2_x64_linux
check_elf_x64_dyn build/tmp/ffi_i32_stage2_x64_linux

build_one ./oren x64-linux "$LINUX_FFI_U32_SRC" build/tmp/ffi_u32_stage1_x64_linux
check_elf_x64_dyn build/tmp/ffi_u32_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$LINUX_FFI_U32_SRC" build/tmp/ffi_u32_stage2_x64_linux
check_elf_x64_dyn build/tmp/ffi_u32_stage2_x64_linux

build_one ./oren x64-linux "$LINUX_FFI_VOID_SRC" build/tmp/ffi_void_stage1_x64_linux
check_elf_x64_dyn build/tmp/ffi_void_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$LINUX_FFI_VOID_SRC" build/tmp/ffi_void_stage2_x64_linux
check_elf_x64_dyn build/tmp/ffi_void_stage2_x64_linux

build_one ./oren x64-linux "$FFI_GROUP_ITEM_ATTRS_SRC" build/tmp/ffi_group_item_attrs_stage1_x64_linux
check_elf_x64_dyn build/tmp/ffi_group_item_attrs_stage1_x64_linux

build_one ./oren_stage2 x64-linux "$FFI_GROUP_ITEM_ATTRS_SRC" build/tmp/ffi_group_item_attrs_stage2_x64_linux
check_elf_x64_dyn build/tmp/ffi_group_item_attrs_stage2_x64_linux

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

build_one ./oren x64-windows "$CFG_OS_SRC" build/tmp/cfg_os_stage1_x64_windows.exe
check_pe_x64 build/tmp/cfg_os_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$CFG_OS_SRC" build/tmp/cfg_os_stage2_x64_windows.exe
check_pe_x64 build/tmp/cfg_os_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_K32_SRC" build/tmp/ffi_k32_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_k32_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$WIN_FFI_K32_SRC" build/tmp/ffi_k32_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_k32_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_MSVCRT_LINK_ATTR_SRC" build/tmp/ffi_msvcrt_link_attr_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_msvcrt_link_attr_stage1_x64_windows.exe
check_bin_contains build/tmp/ffi_msvcrt_link_attr_stage1_x64_windows.exe "msvcrt.dll"

build_one ./oren_stage2 x64-windows "$WIN_FFI_MSVCRT_LINK_ATTR_SRC" build/tmp/ffi_msvcrt_link_attr_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_msvcrt_link_attr_stage2_x64_windows.exe
check_bin_contains build/tmp/ffi_msvcrt_link_attr_stage2_x64_windows.exe "msvcrt.dll"

build_one ./oren x64-windows "$WIN_FFI_I32_SRC" build/tmp/ffi_i32_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_i32_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$WIN_FFI_I32_SRC" build/tmp/ffi_i32_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_i32_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_U32_SRC" build/tmp/ffi_u32_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_u32_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$WIN_FFI_U32_SRC" build/tmp/ffi_u32_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_u32_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_VOID_SRC" build/tmp/ffi_void_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_void_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$WIN_FFI_VOID_SRC" build/tmp/ffi_void_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_void_stage2_x64_windows.exe

build_one ./oren x64-windows "$FFI_GROUP_ITEM_ATTRS_SRC" build/tmp/ffi_group_item_attrs_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_group_item_attrs_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows "$FFI_GROUP_ITEM_ATTRS_SRC" build/tmp/ffi_group_item_attrs_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_group_item_attrs_stage2_x64_windows.exe

build_one ./oren x64-windows "$WIN_FFI_EXPORT_GETPROC_SRC" build/tmp/ffi_export_stage1_x64_windows.exe
check_pe_x64 build/tmp/ffi_export_stage1_x64_windows.exe
check_bin_contains build/tmp/ffi_export_stage1_x64_windows.exe "oren_test_export_cb"

build_one ./oren_stage2 x64-windows "$WIN_FFI_EXPORT_GETPROC_SRC" build/tmp/ffi_export_stage2_x64_windows.exe
check_pe_x64 build/tmp/ffi_export_stage2_x64_windows.exe
check_bin_contains build/tmp/ffi_export_stage2_x64_windows.exe "oren_test_export_cb"

echo "OK: x64 compile-only verification passed" >&2
