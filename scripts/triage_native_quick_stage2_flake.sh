#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
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

mkdir -p build/logs
run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/native_quick_stage2_flake_${ts}_run${run}.log"
  inner_log="build/logs/native_quick_stage2_flake_${ts}_run${run}_inner.log"
  echo "== run ${run}/${runs} ==" >&2
  set +e
  : >"$log"
  {
    echo "ts=$ts"
    echo "run=${run}/${runs}"
    echo "compiler=$compiler"
    echo "cwd=$(pwd)"
    echo "uname=$(uname -a)"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  } >>"$log"
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    echo "env: ${env_args[*]}" >>"$log"
    env "${env_args[@]}" ./scripts/run_native_quick_integration.sh "$compiler" >>"$log" 2>&1
  else
    ./scripts/run_native_quick_integration.sh "$compiler" >>"$log" 2>&1
  fi
  rc=$?
  set -e
  if [[ -f build/logs/oren_stage2_native_quick_integration.log ]]; then
    cp -f build/logs/oren_stage2_native_quick_integration.log "$inner_log"
  fi
  if [[ "$rc" -ne 0 ]]; then
    failures=$((failures + 1))
    echo "FAIL: run ${run} rc=${rc} log=${log}" >&2
    tail -n 120 "$log" >&2 || true
    exit "$rc"
  fi
  run=$((run + 1))
done

echo "OK: ${runs} runs passed" >&2
