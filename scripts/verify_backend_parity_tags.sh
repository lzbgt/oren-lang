#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin bash
need_bin diff

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS:-20}"
run_timeout_secs="${OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS:-5}"

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

if [[ ! -x ./avm ]]; then
  echo "== ensure: avm ==" >&2
  make avm
fi

exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

src="tests/fixtures/tag_parity_smoke.oren"
out_c="build/tmp/tag_parity_c${exe_ext}"
out_native="build/tmp/tag_parity_native${exe_ext}"
out_obc="build/tmp/tag_parity.obc"

log_c="build/logs/tag_parity_c_build.log"
log_native="build/logs/tag_parity_native_build.log"
log_obc="build/logs/tag_parity_obc_build.log"
run_c="build/logs/tag_parity_c_run.log"
run_native="build/logs/tag_parity_native_run.log"
run_obc="build/logs/tag_parity_obc_run.log"

rm -f "$out_c" "$out_native" "$out_obc" "$log_c" "$log_native" "$log_obc" \
  "$run_c" "$run_native" "$run_obc" 2>/dev/null || true

echo "== build: C backend ==" >&2
run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend c -o "$out_c" >"$log_c" 2>&1
test -f "$out_c" || { echo "FAIL: missing $out_c" >&2; tail -n 120 "$log_c" >&2 || true; exit 3; }

echo "== build: native backend ==" >&2
run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug -o "$out_native" >"$log_native" 2>&1
test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$log_native" >&2 || true; exit 4; }

echo "== build: bytecode backend ==" >&2
run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend bytecode -o "$out_obc" >"$log_obc" 2>&1
test -f "$out_obc" || { echo "FAIL: missing $out_obc" >&2; tail -n 120 "$log_obc" >&2 || true; exit 5; }

echo "== run: C backend ==" >&2
run_with_timeout "$run_timeout_secs" "$out_c" >"$run_c" 2>&1

echo "== run: native backend ==" >&2
run_with_timeout "$run_timeout_secs" "$out_native" >"$run_native" 2>&1

echo "== run: OBC (avm) ==" >&2
run_with_timeout "$run_timeout_secs" ./avm "$out_obc" >"$run_obc" 2>&1

normalize_out() {
  local f="$1"
  tr -d '\r' <"$f" | sed -e 's/[[:space:]]\+$//' >"${f}.norm"
}

normalize_out "$run_c"
normalize_out "$run_native"
normalize_out "$run_obc"

grep -F "ok: tag parity" "$run_c.norm" >/dev/null || { echo "FAIL: C output missing ok marker" >&2; cat "$run_c.norm" >&2; exit 6; }
grep -F "ok: tag parity" "$run_native.norm" >/dev/null || { echo "FAIL: native output missing ok marker" >&2; cat "$run_native.norm" >&2; exit 7; }
grep -F "ok: tag parity" "$run_obc.norm" >/dev/null || { echo "FAIL: obc output missing ok marker" >&2; cat "$run_obc.norm" >&2; exit 8; }

diff -u "$run_c.norm" "$run_native.norm" >/dev/null || {
  echo "FAIL: C vs native output mismatch" >&2
  diff -u "$run_c.norm" "$run_native.norm" >&2 || true
  exit 9
}

diff -u "$run_c.norm" "$run_obc.norm" >/dev/null || {
  echo "FAIL: C vs obc output mismatch" >&2
  diff -u "$run_c.norm" "$run_obc.norm" >&2 || true
  exit 10
}

echo "OK: tag parity (C/native/obc)" >&2
