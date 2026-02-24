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

run_expect_panic() {
  local label="$1"
  local out="$2"
  local expect="$3"
  local grep_flags=()
  shift 2
  shift 1
  if [[ "$expect" == "INDEX_OOB" ]]; then
    expect="index out of bounds"
    grep_flags=(-i)
  fi
  set +e
  run_with_timeout "$run_timeout_secs" "$@" >"$out" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: expected non-zero exit for $label" >&2
    cat "$out" >&2
    exit 6
  fi
  grep "${grep_flags[@]}" -F "$expect" "$out" >/dev/null || {
    echo "FAIL: $label output missing expected message ($expect)" >&2
    cat "$out" >&2
    exit 7
  }
}

cases=(
  "index_set_negative|tests/native/fixtures/index_set_negative.oren|INDEX_OOB"
  "index_get_oob|tests/native/fixtures/index_get_oob.oren|INDEX_OOB"
)

for entry in "${cases[@]}"; do
  IFS="|" read -r name src expect_msg <<<"$entry"
  out_c="build/tmp/${name}_c${exe_ext}"
  out_native="build/tmp/${name}_native${exe_ext}"
  out_obc="build/tmp/${name}.obc"

  log_c="build/logs/${name}_c_build.log"
  log_native="build/logs/${name}_native_build.log"
  log_obc="build/logs/${name}_obc_build.log"
  run_c="build/logs/${name}_c_run.log"
  run_native="build/logs/${name}_native_run.log"
  run_obc="build/logs/${name}_obc_run.log"

  rm -f "$out_c" "$out_native" "$out_obc" "$log_c" "$log_native" "$log_obc" \
    "$run_c" "$run_native" "$run_obc" 2>/dev/null || true

  echo "== build: C backend ($name) ==" >&2
  run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend c -o "$out_c" >"$log_c" 2>&1
  test -f "$out_c" || { echo "FAIL: missing $out_c" >&2; tail -n 120 "$log_c" >&2 || true; exit 3; }

  echo "== build: native backend ($name) ==" >&2
  run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug -o "$out_native" >"$log_native" 2>&1
  test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$log_native" >&2 || true; exit 4; }

  echo "== build: bytecode backend ($name) ==" >&2
  run_with_timeout "$build_timeout_secs" "$COMPILER" build "$src" --backend bytecode -o "$out_obc" >"$log_obc" 2>&1
  test -f "$out_obc" || { echo "FAIL: missing $out_obc" >&2; tail -n 120 "$log_obc" >&2 || true; exit 5; }

  echo "== run: C backend ($name) ==" >&2
  run_expect_panic "c" "$run_c" "$expect_msg" "$out_c"

  echo "== run: native backend ($name) ==" >&2
  run_expect_panic "native" "$run_native" "$expect_msg" "$out_native"

  echo "== run: OBC (avm) ($name) ==" >&2
  run_expect_panic "obc" "$run_obc" "$expect_msg" ./avm "$out_obc"

done

echo "OK: index panic parity" >&2
