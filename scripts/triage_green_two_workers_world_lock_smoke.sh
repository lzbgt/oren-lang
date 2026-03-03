#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "env: OREN_WORLD_LOCK_SMOKE_TIMEOUT_SECS (default: 120)" >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren_stage2}"
if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi
if [[ "$runs" -le 0 ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi

env_args=()
if [[ "$#" -gt 2 ]]; then
  env_args=("${@:3}")
fi

timeout_secs="${OREN_WORLD_LOCK_SMOKE_TIMEOUT_SECS:-120}"

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

mkdir -p build/logs build/tmp

compiler_base="$(basename "$compiler")"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

out="build/tmp/${compiler_base}_green_two_workers_world_lock_smoke${exe_ext}"
build_ts="$(date +%Y%m%d_%H%M%S)"
build_log="build/logs/${compiler_base}_green_two_workers_world_lock_smoke_build_${build_ts}.log"
{
  echo "ts=$build_ts"
  echo "compiler=$compiler"
  echo "platform=$platform"
  echo "cwd=$(pwd)"
  echo "uname=$(uname -a)"
  echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
} >"$build_log"
if [[ "${#env_args[@]}" -gt 0 ]]; then
  echo "env: ${env_args[*]}" >>"$build_log"
fi

"$compiler" build tests/native/test_green_two_workers_world_lock_smoke.oren \
  --backend native --platform "$platform" --debug -o "$out" >>"$build_log" 2>&1

run_with_watchdog() {
  local secs="$1"
  shift
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
    sleep 2
    kill -KILL "$pid" 2>/dev/null
  ) &
  local watcher=$!
  wait "$pid"
  local rc=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  set -e
  return "$rc"
}

run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/green_two_workers_world_lock_smoke_${ts}_run${run}.log"
  echo "== run ${run}/${runs} ==" >&2
  : >"$log"
  {
    echo "ts=$ts"
    echo "run=${run}/${runs}"
    echo "compiler=$compiler"
    echo "platform=$platform"
    echo "out=$out"
    echo "build_log=$build_log"
    echo "cwd=$(pwd)"
    echo "uname=$(uname -a)"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    echo "timeout_secs=$timeout_secs"
  } >>"$log"
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    echo "env: ${env_args[*]}" >>"$log"
    run_with_watchdog "$timeout_secs" env "${env_args[@]}" "$out" >>"$log" 2>&1
  else
    run_with_watchdog "$timeout_secs" "$out" >>"$log" 2>&1
  fi
  rc=$?
  echo "run_rc=$rc" >>"$log"
  if [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]; then
    echo "WARN: watchdog timeout/kill (rc=$rc)" >>"$log"
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run ${run} rc=${rc} log=${log}" >&2
    tail -n 120 "$log" >&2 || true
    exit "$rc"
  fi
  run=$((run + 1))
done

echo "OK: ${runs} runs passed" >&2
