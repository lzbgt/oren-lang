#!/usr/bin/env bash
set -euo pipefail

# OrenUI Linux smoke (headful; X11)
#
# This script is intentionally bounded and low-noise:
# - builds the X11 shim shared library via `cc`
# - builds a tiny Oren program that renders via `std:ui/*` and blits RGBA to a window
# - runs the program with a timeout; the program auto-exits after ~60 frames
#
# NOTE:
# - This requires a Linux desktop session with X11 and a working DISPLAY.
# - It is not suitable for WSL2 by default (usually headless / no X server).
# - It is intentionally NOT part of `make test` or `make verify`.

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=30
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
if [[ "$uname_s" != "Linux" ]]; then
  echo "verify_ui_smoke_linux: skip (host OS is $uname_s, requires Linux)" >&2
  exit 0
fi

if ! command -v cc >/dev/null 2>&1; then
  echo "verify_ui_smoke_linux: skip (missing cc)" >&2
  exit 0
fi

pkg_cfg="$(command -v pkg-config 2>/dev/null || echo "")"
if [[ -z "$pkg_cfg" ]]; then
  echo "verify_ui_smoke_linux: skip (missing pkg-config; install X11 dev packages + pkg-config)" >&2
  exit 0
fi
if ! pkg-config --exists x11; then
  echo "verify_ui_smoke_linux: skip (missing X11 dev package; e.g. apt-get install libx11-dev)" >&2
  exit 0
fi

compiler="${1:-./oren_stage2}"
src="examples/ui_hello.oren"

mkdir -p build/tmp build/logs

shim_src="native/orenui/x11/orenui_x11.c"
shim_out="build/tmp/liborenui_x11.so"
app_out="build/tmp/ex_ui_hello_native_linux"
log="build/logs/ui_smoke_linux.log"

arch="$(uname -m)"
platform="x64-linux"
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  platform="arm64-linux"
fi

echo "== ui smoke (linux/x11) =="
echo "platform=$platform"
echo "compiler=$compiler"
echo "shim_src=$shim_src"
echo "shim_out=$shim_out"
echo "src=$src"
echo "out=$app_out"
echo "log=$log"

rm -f "$log" "$shim_out" "$app_out" 2>/dev/null || true

echo "== build shim so =="
run_with_timeout "$build_timeout_secs" cc \
  -O2 -fPIC -shared \
  "$shim_src" \
  -I native/orenui \
  $(pkg-config --cflags x11) \
  $(pkg-config --libs x11) \
  -o "$shim_out" \
  >"$log" 2>&1

test -f "$shim_out" || { echo "FAIL: shim so not produced: $shim_out" >&2; tail -n 120 "$log" >&2; exit 1; }

echo "== build app =="
run_with_timeout "$build_timeout_secs" "$compiler" build "$src" \
  --backend native --platform "$platform" --no-debug \
  --link "$shim_out" \
  -o "$app_out" >>"$log" 2>&1

test -f "$app_out" || { echo "FAIL: ui app not produced: $app_out" >&2; tail -n 160 "$log" >&2; exit 1; }

if [[ -z "${DISPLAY:-}" ]]; then
  echo "verify_ui_smoke_linux: skip run (DISPLAY not set; built artifacts only)" >&2
  tail -n 40 "$log"
  exit 0
fi

echo "== run app (headful) =="
run_with_timeout "$run_timeout_secs" "$app_out" >>"$log" 2>&1

tail -n 40 "$log"
echo "verify_ui_smoke_linux OK"

