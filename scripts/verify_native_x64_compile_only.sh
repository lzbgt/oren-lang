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

mkdir -p build/tmp

TEST_SRC="tests/native/test_quick_integration_native.oren"
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
  local out="$3"

  echo "== build: $compiler -> $platform ==" >&2
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$TEST_SRC" --backend native --platform "$platform" --no-cache --no-debug -o "$out"
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

build_one ./oren x64-linux build/tmp/qi_stage1_x64_linux
check_elf_x64 build/tmp/qi_stage1_x64_linux

build_one ./oren_stage2 x64-linux build/tmp/qi_stage2_x64_linux
check_elf_x64 build/tmp/qi_stage2_x64_linux

build_one ./oren x64-windows build/tmp/qi_stage1_x64_windows.exe
check_pe_x64 build/tmp/qi_stage1_x64_windows.exe

build_one ./oren_stage2 x64-windows build/tmp/qi_stage2_x64_windows.exe
check_pe_x64 build/tmp/qi_stage2_x64_windows.exe

echo "OK: x64 compile-only verification passed" >&2
