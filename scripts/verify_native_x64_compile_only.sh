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
# Default output is bounded. Use `--trace` to print each build step.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/verify_native_x64_compile_only.sh [--targets <csv>] [--trace]

Targets (comma-separated):
  all (default)
  x64-linux   (alias: x64-wsl)
  x64-win     (alias: x64-windows)
  stage1
  stage2

Examples:
  ./scripts/verify_native_x64_compile_only.sh
  ./scripts/verify_native_x64_compile_only.sh --targets x64-win
  ./scripts/verify_native_x64_compile_only.sh --targets x64-wsl,stage2
  ./scripts/verify_native_x64_compile_only.sh --trace

Env:
  OREN_NATIVE_BUILD_TIMEOUT_SECS (default: 10)
  OREN_NATIVE_BUILD_TIMEOUT_SECS_NET_TLS_HTTP2 (default: 15) timeout override for the large NET/TLS/HTTP2 compile-only smoke fixture
EOF
}

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

TARGETS_CSV="all"
TRACE=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace)
      TRACE=1
      shift
      ;;
    --targets)
      TARGETS_CSV="${2:-}"
      if [[ -z "$TARGETS_CSV" ]]; then
        echo "ERROR: --targets requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

normalize_target() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  case "$t" in
    all) echo all ;;
    linux|x64-linux|x64-wsl|wsl) echo x64-linux ;;
    win|windows|x64-win|x64-windows) echo x64-win ;;
    stage1|s1) echo stage1 ;;
    stage2|s2) echo stage2 ;;
    *) echo "$t" ;;
  esac
}

WANT_LINUX=1
WANT_WIN=1
WANT_STAGE1=1
WANT_STAGE2=1
if [[ "$TARGETS_CSV" != "all" ]]; then
  WANT_LINUX=0
  WANT_WIN=0
  WANT_STAGE1=0
  WANT_STAGE2=0
  IFS=',' read -r -a _parts <<<"$TARGETS_CSV"
  for p in "${_parts[@]}"; do
    p="$(normalize_target "$p")"
    case "$p" in
      x64-linux) WANT_LINUX=1 ;;
      x64-win) WANT_WIN=1 ;;
      stage1) WANT_STAGE1=1 ;;
      stage2) WANT_STAGE2=1 ;;
      *) echo "ERROR: unknown target selector: $p" >&2; usage >&2; exit 2 ;;
    esac
  done
  # If caller only selected stage(s), default platforms to both.
  if [[ "$WANT_LINUX" -eq 0 && "$WANT_WIN" -eq 0 ]]; then
    WANT_LINUX=1
    WANT_WIN=1
  fi
  # If caller only selected platforms, default compilers to both.
  if [[ "$WANT_STAGE1" -eq 0 && "$WANT_STAGE2" -eq 0 ]]; then
    WANT_STAGE1=1
    WANT_STAGE2=1
  fi
fi

BUILD_TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"

# Compiler-only performance knobs (rolling hang guard):
# - Stage2 native backend uses fork-based spawn on macOS/Linux today; module parsing can be
#   parallelized via ASTBIN worker bounce (`OREN_PARSE_FORK_PARALLEL=1`).
# - This also enables the persistent module ASTBIN cache to populate (workers already have
#   ASTBIN bytes), which keeps large stdlib graphs bounded across multiple `oren build` invocations.
X64_PARSE_JOBS="${OREN_PARSE_JOBS:-8}"
if [[ "$X64_PARSE_JOBS" -lt 1 ]]; then X64_PARSE_JOBS=1; fi
if [[ "$X64_PARSE_JOBS" -gt 16 ]]; then X64_PARSE_JOBS=16; fi

COMPILER_ENV=(
  "OREN_PARSE_JOBS=${X64_PARSE_JOBS}"
  "OREN_PARSE_FORK_PARALLEL=1"
)

QI_SRC="tests/native/test_quick_integration_native.oren"
PRINT_SRC="tests/native/print.oren"
PRINT_NEEDLE="hello from native"
CFG_OS_SRC="tests/native/cfg_os_select.oren"
NET_TLS_HTTP2_SMOKE_SRC="tests/fixtures/x64_compile_only_net_tls_http2_smoke.oren"

WIN_FFI_K32_SRC="tests/native/ffi_windows_kernel32.oren"
STD_FFI_K32_SMOKE_SRC="tests/native/test_std_ffi_kernel32_smoke.oren"
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
FFI_GROUP_DEFAULT_RET_SRC="tests/native/ffi_group_default_ret.oren"
FFI_ALIAS_SYMBOLS_SRC="tests/native/ffi_alias_symbols.oren"
FFI_GROUP_LINK_SUGAR_SRC="tests/native/ffi_group_link_sugar.oren"
FFI_GROUP_LINK_SUGAR_MULTILINE_SRC="tests/native/ffi_group_link_sugar_multiline.oren"
FFI_GROUP_MULTILINE_ITEMS_SRC="tests/native/ffi_group_multiline_items.oren"
FFI_RET_PTR_USIZE_SRC="tests/native/ffi_ret_ptr_usize.oren"
FFI_LIBC_PORTABLE_SRC="tests/native/ffi_libc_portable.oren"
LIBMATH_SRC="examples/libmath.oren"

run_with_timeout() {
  local secs="$1"
  shift
  local had_errexit=0
  case "$-" in
    *e*) had_errexit=1 ;;
  esac
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
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  fi
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

ensure_runtime_astbin_seed() {
  # Keep x64 compile-only runs bounded on cold caches.
  #
  # Stage2-native parsing/expansion of the native runtime bundle can be very slow on the first run
  # (especially with capsule/cfg pruning + astbin encode). The runtime bundle has a built-in "seed"
  # directory mechanism that allows a faster compiler (stage1) to pre-warm astbin blobs and then
  # copy them into the active cache dir on demand.
  #
  # We seed per-OS (linux/windows) to keep x64 backend smoke fixtures under the tight timeout guard.
  local platform="$1"
  local seed_log="build/logs/runtime_astbin_seed_${platform}.log"

  if [[ ! -x ./scripts/build_runtime_astbin_seed.sh ]]; then
    echo "ERROR: missing runtime astbin seed helper: scripts/build_runtime_astbin_seed.sh" >&2
    return 2
  fi

  # Use stage1 by default for seeding (faster on cold parse); stage2 will consume the seed.
  # Suppress output by default; the seed helper itself is chatty with tracing enabled.
  if [[ "$TRACE" -eq 1 ]]; then
    echo "== seed: native runtime astbin (platform=$platform) ==" >&2
    ./scripts/build_runtime_astbin_seed.sh --platform "$platform" --compiler ./oren 2>&1 | tee "$seed_log"
    return "${PIPESTATUS[0]}"
  fi

  ./scripts/build_runtime_astbin_seed.sh --platform "$platform" --compiler ./oren >"$seed_log" 2>&1
}

ensure_runtime_obj_seed() {
  # Keep first-run stage2-native builds bounded by ensuring the rtobj seed exists for the
  # runtime profiles used by this suite.
  local platform="$1"
  local runtime_profile="$2" # core|full|minimal|auto
  local seed_log="build/logs/runtime_obj_seed_${platform}_${runtime_profile}.log"

  if [[ ! -x ./scripts/build_rtobj_seed.sh ]]; then
    echo "ERROR: missing runtime obj seed helper: scripts/build_rtobj_seed.sh" >&2
    return 2
  fi

  if [[ "$TRACE" -eq 1 ]]; then
    echo "== seed: runtime obj (platform=$platform profile=$runtime_profile) ==" >&2
    ./scripts/build_rtobj_seed.sh --platform "$platform" --runtime-profile "$runtime_profile" --compiler ./oren_stage2 --no-debug 2>&1 | tee "$seed_log"
    return "${PIPESTATUS[0]}"
  fi

  ./scripts/build_rtobj_seed.sh --platform "$platform" --runtime-profile "$runtime_profile" --compiler ./oren_stage2 --no-debug >"$seed_log" 2>&1
}

build_one() {
  local compiler="$1"
  local platform="$2"
  local src="$3"
  local out="$4"
  shift 4

  if [[ "$TRACE" -eq 1 ]]; then
    echo "== build: compiler=$compiler platform=$platform src=$src out=$out ==" >&2
  fi

  local ccname
  ccname="$(basename "$compiler")"
  local bname
  bname="$(basename "$src" .oren)"
  local logf="build/logs/x64_compile_only_${ccname}_${platform}_${bname}.log"

  # Rolling hang guard:
  # Most fixtures should stay <10s, but the NET/TLS/HTTP2 compile-only smoke intentionally
  # forces a very large stdlib closure (and we run with `--no-cache`), so allow a slightly
  # larger guard to avoid false positives while still detecting true hangs.
  local timeout_secs="$BUILD_TIMEOUT_SECS"
  if [[ "$src" == "$NET_TLS_HTTP2_SMOKE_SRC" ]]; then
    local t_override="${OREN_NATIVE_BUILD_TIMEOUT_SECS_NET_TLS_HTTP2:-}"
    if [[ -n "$t_override" ]]; then
      timeout_secs="$t_override"
    else
      if [[ "$timeout_secs" -lt 15 ]]; then timeout_secs=15; fi
    fi
  fi

  set +e
  run_with_timeout "$timeout_secs" env "${COMPILER_ENV[@]}" "$compiler" build "$src" \
    --backend native --platform "$platform" --no-cache --no-debug "$@" -o "$out" \
    >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform timeout=${timeout_secs}s" >&2
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
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
}

check_elf_x64_dyn() {
  local p="$1"
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
  file "$p" | grep -i 'dynamically linked' >/dev/null
}

check_elf_x64_so() {
  local p="$1"
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
  file "$p" | grep -i 'shared object' >/dev/null
}

check_pe_x64() {
  local p="$1"
  file "$p" | grep -F 'PE32+' >/dev/null
}

check_pe_x64_exe() {
  local p="$1"
  check_pe_x64 "$p"
  file "$p" | grep -F '(DLL)' >/dev/null && return 2
  return 0
}

check_pe_x64_dll() {
  local p="$1"
  check_pe_x64 "$p"
  file "$p" | grep -F '(DLL)' >/dev/null
}

check_pe_x64_entry_disp8_zero_sane() {
  # Regression guard (native backend semantics):
  # x86_64 encoding requires a disp8=0 byte for [rbp] / [r13] addressing.
  # When an "optional byte" is represented as `0`, native-backend `nil==0` can cause
  # the displacement byte to be omitted, shifting the instruction stream and producing
  # a binary that crashes immediately at process entry on Windows.
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

check_pe_exports_contains() {
  local p="$1"
  shift
  local script="scripts/pe_exports_check.py"
  if [[ ! -f "$script" ]]; then
    echo "ERROR: missing pe export checker: $script" >&2
    return 2
  fi
  local args=()
  for sym in "$@"; do
    args+=("--contains" "$sym")
  done
  python3 "$script" "$p" "${args[@]}"
}

check_bin_contains() {
  local p="$1"
  local needle="$2"
  if command -v strings >/dev/null 2>&1; then
    strings -a "$p" | grep -iF "$needle" >/dev/null
  fi
}

run_suite_x64_linux() {
  local compiler="$1"
  local tag="$2"

  build_one "$compiler" x64-linux "$QI_SRC" "build/tmp/qi_${tag}_x64_linux"
  check_elf_x64 "build/tmp/qi_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$NET_TLS_HTTP2_SMOKE_SRC" "build/tmp/net_tls_http2_smoke_${tag}_x64_linux"
  check_elf_x64 "build/tmp/net_tls_http2_smoke_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$PRINT_SRC" "build/tmp/print_${tag}_x64_linux"
  check_elf_x64 "build/tmp/print_${tag}_x64_linux"
  check_bin_contains "build/tmp/print_${tag}_x64_linux" "$PRINT_NEEDLE"

  build_one "$compiler" x64-linux "$CFG_OS_SRC" "build/tmp/cfg_os_${tag}_x64_linux"
  check_elf_x64 "build/tmp/cfg_os_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$LINUX_FFI_OK_SRC" "build/tmp/ffi_ok_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_ok_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$LINUX_FFI_I32_SRC" "build/tmp/ffi_i32_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_i32_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$LINUX_FFI_U32_SRC" "build/tmp/ffi_u32_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_u32_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$LINUX_FFI_VOID_SRC" "build/tmp/ffi_void_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_void_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_GROUP_ITEM_ATTRS_SRC" "build/tmp/ffi_group_item_attrs_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_group_item_attrs_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_GROUP_DEFAULT_RET_SRC" "build/tmp/ffi_group_default_ret_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_group_default_ret_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_GROUP_MULTILINE_ITEMS_SRC" "build/tmp/ffi_group_multiline_items_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_group_multiline_items_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_RET_PTR_USIZE_SRC" "build/tmp/ffi_ret_ptr_usize_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_ret_ptr_usize_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_ALIAS_SYMBOLS_SRC" "build/tmp/ffi_alias_symbols_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_alias_symbols_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_GROUP_LINK_SUGAR_SRC" "build/tmp/ffi_group_link_sugar_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_group_link_sugar_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_GROUP_LINK_SUGAR_MULTILINE_SRC" "build/tmp/ffi_group_link_sugar_multiline_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_group_link_sugar_multiline_${tag}_x64_linux"

  build_one "$compiler" x64-linux "$FFI_LIBC_PORTABLE_SRC" "build/tmp/ffi_libc_portable_${tag}_x64_linux"
  check_elf_x64_dyn "build/tmp/ffi_libc_portable_${tag}_x64_linux"

  # Shared library output: `.so` + generated header.
  build_one "$compiler" x64-linux "$LIBMATH_SRC" "build/tmp/libmath_${tag}_x64_linux.so" --lib
  check_elf_x64_so "build/tmp/libmath_${tag}_x64_linux.so"
  test -f "build/tmp/libmath_${tag}_x64_linux.h"
  grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' "build/tmp/libmath_${tag}_x64_linux.h" >/dev/null
  grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' "build/tmp/libmath_${tag}_x64_linux.h" >/dev/null
}

run_suite_x64_win() {
  local compiler="$1"
  local tag="$2"

  build_one "$compiler" x64-windows "$QI_SRC" "build/tmp/qi_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/qi_${tag}_x64_windows.exe"
  check_pe_x64_entry_disp8_zero_sane "build/tmp/qi_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$NET_TLS_HTTP2_SMOKE_SRC" "build/tmp/net_tls_http2_smoke_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/net_tls_http2_smoke_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$PRINT_SRC" "build/tmp/print_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/print_${tag}_x64_windows.exe"
  check_bin_contains "build/tmp/print_${tag}_x64_windows.exe" "$PRINT_NEEDLE"

  build_one "$compiler" x64-windows "$CFG_OS_SRC" "build/tmp/cfg_os_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/cfg_os_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$WIN_FFI_K32_SRC" "build/tmp/ffi_k32_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_k32_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$STD_FFI_K32_SMOKE_SRC" "build/tmp/std_ffi_k32_smoke_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/std_ffi_k32_smoke_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$WIN_FFI_MSVCRT_LINK_ATTR_SRC" "build/tmp/ffi_msvcrt_link_attr_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_msvcrt_link_attr_${tag}_x64_windows.exe"
  check_bin_contains "build/tmp/ffi_msvcrt_link_attr_${tag}_x64_windows.exe" "msvcrt.dll"

  build_one "$compiler" x64-windows "$WIN_FFI_I32_SRC" "build/tmp/ffi_i32_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_i32_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$WIN_FFI_U32_SRC" "build/tmp/ffi_u32_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_u32_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$WIN_FFI_VOID_SRC" "build/tmp/ffi_void_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_void_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_GROUP_ITEM_ATTRS_SRC" "build/tmp/ffi_group_item_attrs_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_group_item_attrs_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_GROUP_DEFAULT_RET_SRC" "build/tmp/ffi_group_default_ret_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_group_default_ret_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_GROUP_MULTILINE_ITEMS_SRC" "build/tmp/ffi_group_multiline_items_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_group_multiline_items_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_RET_PTR_USIZE_SRC" "build/tmp/ffi_ret_ptr_usize_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_ret_ptr_usize_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_ALIAS_SYMBOLS_SRC" "build/tmp/ffi_alias_symbols_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_alias_symbols_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_GROUP_LINK_SUGAR_SRC" "build/tmp/ffi_group_link_sugar_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_group_link_sugar_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_GROUP_LINK_SUGAR_MULTILINE_SRC" "build/tmp/ffi_group_link_sugar_multiline_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_group_link_sugar_multiline_${tag}_x64_windows.exe"

  build_one "$compiler" x64-windows "$FFI_LIBC_PORTABLE_SRC" "build/tmp/ffi_libc_portable_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_libc_portable_${tag}_x64_windows.exe"
  check_bin_contains "build/tmp/ffi_libc_portable_${tag}_x64_windows.exe" "msvcrt.dll"

  build_one "$compiler" x64-windows "$WIN_FFI_EXPORT_GETPROC_SRC" "build/tmp/ffi_export_${tag}_x64_windows.exe"
  check_pe_x64_exe "build/tmp/ffi_export_${tag}_x64_windows.exe"
  check_pe_exports_contains "build/tmp/ffi_export_${tag}_x64_windows.exe" "oren_test_export_cb"

  # Shared library output: `.dll` + generated header.
  build_one "$compiler" x64-windows "$LIBMATH_SRC" "build/tmp/libmath_${tag}_x64_windows.dll" --lib
  check_pe_x64_dll "build/tmp/libmath_${tag}_x64_windows.dll"
  test -f "build/tmp/libmath_${tag}_x64_windows.h"
  grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' "build/tmp/libmath_${tag}_x64_windows.h" >/dev/null
  grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' "build/tmp/libmath_${tag}_x64_windows.h" >/dev/null
  check_pe_exports_contains "build/tmp/libmath_${tag}_x64_windows.dll" "add" "mul"
}

echo -n "== x64 compile-only: platforms=" >&2
if [[ "$WANT_LINUX" -eq 1 ]]; then echo -n "x64-linux " >&2; fi
if [[ "$WANT_WIN" -eq 1 ]]; then echo -n "x64-win " >&2; fi
echo -n "compilers=" >&2
if [[ "$WANT_STAGE1" -eq 1 ]]; then echo -n "stage1 " >&2; fi
if [[ "$WANT_STAGE2" -eq 1 ]]; then echo -n "stage2 " >&2; fi
echo "timeout=${BUILD_TIMEOUT_SECS}s ==" >&2

if [[ "$WANT_LINUX" -eq 1 ]]; then
  ensure_runtime_astbin_seed x64-linux || {
    echo "ERROR: runtime astbin seed failed for x64-linux (see build/logs/runtime_astbin_seed_x64-linux.log)" >&2
    tail -n 120 build/logs/runtime_astbin_seed_x64-linux.log >&2 || true
    exit 2
  }
  # Seed both profiles because this suite compiles both:
  # - core: quick fixtures
  # - full: std:net smoke fixture
  ensure_runtime_obj_seed x64-linux core || {
    echo "ERROR: runtime obj seed failed for x64-linux/core (see build/logs/runtime_obj_seed_x64-linux_core.log)" >&2
    tail -n 120 build/logs/runtime_obj_seed_x64-linux_core.log >&2 || true
    exit 2
  }
  ensure_runtime_obj_seed x64-linux full || {
    echo "ERROR: runtime obj seed failed for x64-linux/full (see build/logs/runtime_obj_seed_x64-linux_full.log)" >&2
    tail -n 120 build/logs/runtime_obj_seed_x64-linux_full.log >&2 || true
    exit 2
  }
fi

if [[ "$WANT_WIN" -eq 1 ]]; then
  ensure_runtime_astbin_seed x64-windows || {
    echo "ERROR: runtime astbin seed failed for x64-windows (see build/logs/runtime_astbin_seed_x64-windows.log)" >&2
    tail -n 120 build/logs/runtime_astbin_seed_x64-windows.log >&2 || true
    exit 2
  }
  ensure_runtime_obj_seed x64-windows core || {
    echo "ERROR: runtime obj seed failed for x64-windows/core (see build/logs/runtime_obj_seed_x64-windows_core.log)" >&2
    tail -n 120 build/logs/runtime_obj_seed_x64-windows_core.log >&2 || true
    exit 2
  }
  ensure_runtime_obj_seed x64-windows full || {
    echo "ERROR: runtime obj seed failed for x64-windows/full (see build/logs/runtime_obj_seed_x64-windows_full.log)" >&2
    tail -n 120 build/logs/runtime_obj_seed_x64-windows_full.log >&2 || true
    exit 2
  }
fi

if [[ "$WANT_LINUX" -eq 1 ]]; then
  echo "== suite: x64-linux ==" >&2
  if [[ "$WANT_STAGE1" -eq 1 ]]; then run_suite_x64_linux ./oren stage1; fi
  if [[ "$WANT_STAGE2" -eq 1 ]]; then run_suite_x64_linux ./oren_stage2 stage2; fi
fi

if [[ "$WANT_WIN" -eq 1 ]]; then
  echo "== suite: x64-windows (compile-only) ==" >&2
  if [[ "$WANT_STAGE1" -eq 1 ]]; then run_suite_x64_win ./oren stage1; fi
  if [[ "$WANT_STAGE2" -eq 1 ]]; then run_suite_x64_win ./oren_stage2 stage2; fi
fi

echo "OK: x64 compile-only verification passed" >&2
