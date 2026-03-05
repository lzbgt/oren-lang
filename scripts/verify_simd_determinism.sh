#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_SIMD_VERIFY_BUILD_TIMEOUT_SECS:-40}"
run_timeout_secs="${OREN_SIMD_VERIFY_RUN_TIMEOUT_SECS:-10}"

run_with_timeout() {
  local secs="$1"
  shift
  if [[ "${uname_s:-}" == "Darwin" ]]; then
    if [[ -z "$secs" || "$secs" == "0" ]]; then
      "$@"
      return $?
    fi
    set +e
    "$@" &
    local pid=$!
    (
      sleep "$secs"
      kill -TERM "$pid" 2>/dev/null
      sleep "$timeout_kill_secs"
      kill -KILL "$pid" 2>/dev/null
    ) &
    local watcher=$!
    wait "$pid"
    local rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    set -e
    return "$rc"
  fi

  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

uname_s="$(uname -s)"
uname_m="$(uname -m)"

os_key=""
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac

arch_key=""
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"

mkdir -p build/tmp build/logs

COMPILER="${OREN_COMPILER:-./oren_stage2}"
if [[ ! -x "$COMPILER" ]]; then
  echo "== ensure: stage2 compiler ($COMPILER) ==" >&2
  make stage2
fi

exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

src="tests/native/test_simd_suite.oren"
out="build/tmp/simd_suite_native${exe_ext}"
build_log="build/logs/simd_suite_native_build.log"

scalar_out="build/logs/simd_suite_scalar.log"
simd_out="build/logs/simd_suite_simd.log"
scalar_norm="build/logs/simd_suite_scalar.norm"
simd_norm="build/logs/simd_suite_simd.norm"

echo "== SIMD determinism verify =="
echo "compiler=$COMPILER"
echo "platform=$platform"
echo "src=$src"
echo "out=$out"

rm -f "$out" "$build_log" "$scalar_out" "$simd_out" "$scalar_norm" "$simd_norm" 2>/dev/null || true

OREN_NATIVE_RUNTIME_PROFILE=full OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0 run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" \
  --backend native --platform "$platform" --debug -o "$out" >"$build_log" 2>&1

set +e
OREN_NO_SIMD=1 run_with_timeout "$run_timeout_secs" "$out" >"$scalar_out" 2>&1
scalar_rc=$?
set -e
if [[ "$scalar_rc" -ne 0 ]]; then
  echo "FAIL: scalar run failed (rc=$scalar_rc)" >&2
  cat "$scalar_out" >&2
  exit 3
fi

set +e
OREN_ENABLE_SIMD=1 run_with_timeout "$run_timeout_secs" "$out" >"$simd_out" 2>&1
simd_rc=$?
set -e
if [[ "$simd_rc" -ne 0 ]]; then
  echo "FAIL: SIMD run failed (rc=$simd_rc)" >&2
  cat "$simd_out" >&2
  exit 4
fi

grep -F "SIMD_ENABLED=" "$scalar_out" || true
grep -F "SIMD_ENABLED=" "$simd_out" || true

grep -v '^SIMD_ENABLED=' "$scalar_out" >"$scalar_norm"
grep -v '^SIMD_ENABLED=' "$simd_out" >"$simd_norm"

if ! diff -u "$scalar_norm" "$simd_norm" >/dev/null; then
  echo "FAIL: SIMD output mismatch vs scalar baseline" >&2
  diff -u "$scalar_norm" "$simd_norm" >&2 || true
  exit 5
fi

echo "OK: SIMD determinism verified (scalar vs SIMD output match)"
