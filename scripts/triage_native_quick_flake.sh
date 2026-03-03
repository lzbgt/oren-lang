#!/usr/bin/env bash
set -euo pipefail

runs="${1:-10}"
compiler="${2:-./oren}"

if [[ "$runs" -le 0 ]]; then
  echo "usage: $0 [runs] [compiler]" >&2
  exit 2
fi

mkdir -p build/logs

run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/native_quick_flake_${ts}_run${run}.log"
  inner_log="build/logs/native_quick_flake_${ts}_run${run}_inner.log"
  echo "== run ${run}/${runs} ==" >&2
  set +e
  ./scripts/run_native_quick_integration.sh "$compiler" >"$log" 2>&1
  rc=$?
  set -e
  if [[ -f build/logs/oren_native_quick_integration.log ]]; then
    cp -f build/logs/oren_native_quick_integration.log "$inner_log"
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run ${run} rc=${rc} log=${log}" >&2
    tail -n 120 "$log" >&2 || true
    exit "$rc"
  fi
  run=$((run + 1))
done

echo "OK: ${runs} runs passed" >&2
