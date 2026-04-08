#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the focused green local-ptr plain/workers slices sequentially." >&2
  exit 0
fi

runs="${1:-3}"
compiler="${2:-./oren}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi
if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler" >&2
  exit 2
fi

plain_runs="${OREN_QI_LOCAL_PTR_PLAIN_RUNS:-$runs}"
workers_runs="${OREN_QI_LOCAL_PTR_WORKERS_RUNS:-$runs}"
plain_iters="${OREN_QI_LOCAL_PTR_PLAIN_STRESS_ITERS:-${OREN_QI_STRESS_ITERS:-4}}"
workers_iters="${OREN_QI_LOCAL_PTR_WORKERS_STRESS_ITERS:-${OREN_QI_STRESS_ITERS:-4}}"

for v in "$plain_runs" "$workers_runs" "$plain_iters" "$workers_iters"; do
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "run/iter knobs must be non-negative integers" >&2
    exit 2
  fi
done

mkdir -p build/logs
ts="$(date +%Y%m%d_%H%M%S)"
log="build/logs/verify_native_quick_green_local_ptr_modes_${ts}.log"

{
  echo "ts=$ts"
  echo "compiler=$compiler"
  echo "cwd=$(pwd)"
  echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "plain_runs=$plain_runs"
  echo "workers_runs=$workers_runs"
  echo "plain_iters=$plain_iters"
  echo "workers_iters=$workers_iters"
} >"$log"

if [[ "$plain_runs" -gt 0 ]]; then
  echo "== green local ptr plain (runs=$plain_runs, iters=$plain_iters) ==" | tee -a "$log"
  OREN_QI_STRESS_ITERS="$plain_iters" \
    ./scripts/triage_native_quick_green_local_ptr_plain_flake.sh "$plain_runs" "$compiler" "$@" \
    >>"$log" 2>&1
fi

if [[ "$workers_runs" -gt 0 ]]; then
  echo "== green local ptr workers (runs=$workers_runs, iters=$workers_iters) ==" | tee -a "$log"
  OREN_QI_STRESS_ITERS="$workers_iters" \
    ./scripts/triage_native_quick_green_local_ptr_workers_flake.sh "$workers_runs" "$compiler" "$@" \
    >>"$log" 2>&1
fi

echo "OK: green local ptr split checks passed (log=$log)" >&2
