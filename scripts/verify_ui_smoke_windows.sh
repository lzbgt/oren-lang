#!/usr/bin/env bash
set -euo pipefail

# OrenUI Windows smoke (headful)
#
# This script mirrors `scripts/verify_ui_smoke_macos.sh` but targets x64-windows.
#
# It is intentionally bounded and low-noise:
# - builds the Win32 shim DLL via MSVC `cl.exe`
# - builds a tiny Oren program that renders via `std:ui/*` and blits RGBA to a window
# - runs the program; it auto-exits after ~60 frames
#
# NOTE:
# - This requires a GUI session.
# - It does NOT require a VS Developer Prompt:
#   - it auto-configures a VS2022 MSVC environment via `scripts/win_msvc_cmd.cmd`.
# - It is not part of `make test` (headful).

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=60
run_timeout_secs=10

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

is_windows_host() {
  if [[ "${OS:-}" == "Windows_NT" ]]; then
    return 0
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if ! is_windows_host; then
  echo "verify_ui_smoke_windows: skip (not running on Windows host)" >&2
  exit 0
fi

msvc_cmd_posix="scripts/win_msvc_cmd.cmd"
msvc_cmd_cmd="scripts\\win_msvc_cmd.cmd"
if [[ ! -f "$msvc_cmd_posix" ]]; then
  echo "verify_ui_smoke_windows: skip (missing $msvc_cmd_posix)" >&2
  exit 0
fi

compiler="${1:-./oren_stage2.exe}"
src="examples/ui_hello.oren"

mkdir -p build/tmp build/logs

shim_src="native/orenui/win32/orenui_win32.c"
shim_out="build/tmp/orenui_win32.dll"
app_out="build/tmp/ex_ui_hello_x64_windows.exe"
log="build/logs/ui_smoke_windows.log"

echo "== ui smoke (windows) =="
echo "compiler=$compiler"
echo "shim_src=$shim_src"
echo "shim_out=$shim_out"
echo "src=$src"
echo "out=$app_out"
echo "log=$log"

rm -f "$log" "$shim_out" "$app_out" 2>/dev/null || true

echo "== build shim dll (cl.exe) =="
run_with_timeout "$build_timeout_secs" cmd.exe /v:on /c \
  "call ${msvc_cmd_cmd} cl.exe ^
    /nologo /O2 /MT /W3 /EHsc /LD ^
    /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS /DORENUI_EXPORTS ^
    ${shim_src} ^
    user32.lib gdi32.lib ^
    /link /nologo /OUT:${shim_out}" \
  >"$log" 2>&1

test -f "$shim_out" || { echo "FAIL: shim dll not produced: $shim_out" >&2; tail -n 120 "$log" >&2; exit 1; }

echo "== build app =="
run_with_timeout "$build_timeout_secs" "$compiler" build "$src" \
  --backend native --platform x64-windows --no-debug \
  --link "$shim_out" \
  -o "$app_out" >>"$log" 2>&1

test -f "$app_out" || { echo "FAIL: ui app not produced: $app_out" >&2; tail -n 160 "$log" >&2; exit 1; }

echo "== run app (headful) =="
run_with_timeout "$run_timeout_secs" "$app_out" >>"$log" 2>&1

tail -n 40 "$log"
echo "verify_ui_smoke_windows OK"
