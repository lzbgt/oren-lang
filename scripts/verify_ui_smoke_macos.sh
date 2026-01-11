#!/usr/bin/env bash
set -euo pipefail

# OrenUI macOS smoke (headful)
#
# This script is intentionally bounded and low-noise:
# - builds the Cocoa shim dylib via clang
# - builds a tiny Oren program that renders via `std:ui/*` and blits RGBA to a window
# - runs the program with a timeout; the program auto-exits after ~60 frames
#
# NOTE: This requires a GUI session (not suitable for headless CI environments).

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=20
run_timeout_secs=6

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

uname_s="$(uname -s)"
uname_m="$(uname -m)"
if [[ "$uname_s" != "Darwin" ]]; then
  echo "verify_ui_smoke_macos: skip (host OS is $uname_s, requires macOS)" >&2
  exit 0
fi
if [[ "$uname_m" != "arm64" && "$uname_m" != "aarch64" ]]; then
  echo "verify_ui_smoke_macos: skip (host arch is $uname_m; this script is for arm64-macos bring-up)" >&2
  exit 0
fi

compiler="${1:-./oren}"
src="examples/ui_hello.oren"

mkdir -p build/tmp build/logs

shim_src="native/orenui/cocoa/orenui_cocoa.m"
shim_out="build/liborenui_cocoa.dylib"
app_out="build/ex_ui_hello_native"
log="build/logs/ui_smoke_macos.log"

echo "== ui smoke (macos) =="
echo "compiler=$compiler"
echo "shim_src=$shim_src"
echo "shim_out=$shim_out"
echo "src=$src"
echo "out=$app_out"
echo "log=$log"

rm -f "$log" "$shim_out" "$app_out" 2>/dev/null || true

echo "== build shim dylib =="
run_with_timeout "$build_timeout_secs" clang \
  -O2 -fobjc-arc \
  -dynamiclib "$shim_src" \
  -o "$shim_out" \
  -framework Cocoa -framework CoreGraphics \
  >"$log" 2>&1

test -f "$shim_out" || { echo "FAIL: shim dylib not produced: $shim_out" >&2; tail -n 80 "$log" >&2; exit 1; }

echo "== build app =="
run_with_timeout "$build_timeout_secs" "$compiler" build "$src" \
  --backend native --platform arm64-macos --no-debug \
  --link "$shim_out" \
  -o "$app_out" >>"$log" 2>&1

test -f "$app_out" || { echo "FAIL: ui app not produced: $app_out" >&2; tail -n 120 "$log" >&2; exit 1; }

echo "== run app (headful) =="
run_with_timeout "$run_timeout_secs" "$app_out" >>"$log" 2>&1

tail -n 30 "$log"
echo "verify_ui_smoke_macos OK"

