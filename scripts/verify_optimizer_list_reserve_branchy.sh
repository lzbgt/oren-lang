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
need_bin grep

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_OPT_LIST_RESERVE_BUILD_TIMEOUT_SECS:-20}"
run_timeout_secs="${OREN_OPT_LIST_RESERVE_RUN_TIMEOUT_SECS:-5}"

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

exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

src="tests/fixtures/list_reserve_branchy_control_flow_smoke.oren"
out="build/tmp/list_reserve_branchy_control_flow_smoke${exe_ext}"
logf="build/logs/list_reserve_branchy_control_flow_smoke_build.log"
runf="build/logs/list_reserve_branchy_control_flow_smoke_run.log"

rm -f "$out" "$logf" "$runf" 2>/dev/null || true

echo "== build: optimizer list reserve branchy control flow ==" >&2
run_with_timeout "$build_timeout_secs" \
  env OREN_TRACE_LIST_RESERVE=1 \
  "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug --no-cache -o "$out" \
  >"$logf" 2>&1

test -f "$out" || {
  echo "FAIL: missing $out" >&2
  tail -n 120 "$logf" >&2 || true
  exit 3
}

grep -F "[opt] list_reserve name=xs n=n" "$logf" >/dev/null || {
  echo "FAIL: missing boxed list reserve trace" >&2
  tail -n 120 "$logf" >&2 || true
  exit 4
}
grep -F "[opt] list_push_unchecked name=xs" "$logf" >/dev/null || {
  echo "FAIL: missing boxed unchecked push trace" >&2
  tail -n 120 "$logf" >&2 || true
  exit 5
}
grep -F "[opt] list_int_reserve name=ys n=n" "$logf" >/dev/null || {
  echo "FAIL: missing list<int> reserve trace" >&2
  tail -n 120 "$logf" >&2 || true
  exit 6
}
grep -F "[opt] list_int_push_unchecked name=ys" "$logf" >/dev/null || {
  echo "FAIL: missing list<int> unchecked push trace" >&2
  tail -n 120 "$logf" >&2 || true
  exit 7
}

echo "== run: optimizer list reserve branchy control flow ==" >&2
run_with_timeout "$run_timeout_secs" "$out" >"$runf" 2>&1
grep -F "ok: list reserve branchy control flow" "$runf" >/dev/null || {
  echo "FAIL: runtime output missing ok marker" >&2
  cat "$runf" >&2 || true
  exit 8
}

echo "OK: optimizer list reserve branchy control flow" >&2
