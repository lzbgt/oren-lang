#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the focused green join-waiter stress fixture in green-only and OS-only modes." >&2
  exit 0
fi

runs="${1:-2}"
compiler="${2:-./oren_stage2}"
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

green_runs="${OREN_QI_GREEN_JOIN_WAITERS_GREEN_RUNS:-$runs}"
os_runs="${OREN_QI_GREEN_JOIN_WAITERS_OS_RUNS:-$runs}"
green_iters="${OREN_QI_GREEN_JOIN_WAITERS_GREEN_ITERS:-${OREN_QI_STRESS_ITERS:-12}}"
os_iters="${OREN_QI_GREEN_JOIN_WAITERS_OS_ITERS:-${OREN_QI_STRESS_ITERS:-12}}"
prewarm="${OREN_QI_GREEN_JOIN_WAITERS_PREWARM:-1}"
seed_build_compiler="${OREN_QI_GREEN_JOIN_WAITERS_SEED_BUILD_COMPILER:-./oren}"
if [[ ! -x "$seed_build_compiler" ]]; then
  seed_build_compiler="$compiler"
fi

for v in "$green_runs" "$os_runs" "$green_iters" "$os_iters"; do
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "run/iter knobs must be non-negative integers" >&2
    exit 2
  fi
done

mkdir -p build/logs
ts="$(date +%Y%m%d_%H%M%S)"
log="build/logs/verify_native_quick_green_join_waiters_modes_${ts}.log"

{
  echo "ts=$ts"
  echo "compiler=$compiler"
  echo "cwd=$(pwd)"
  echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "green_runs=$green_runs"
  echo "os_runs=$os_runs"
  echo "green_iters=$green_iters"
  echo "os_iters=$os_iters"
  echo "prewarm=$prewarm"
  echo "seed_build_compiler=$seed_build_compiler"
} >"$log"

if [[ "$prewarm" != "0" && "$prewarm" != "false" ]]; then
  echo "== green join waiter seed prewarm ==" | tee -a "$log"
  ./scripts/build_runtime_astbin_seed.sh --compiler "$seed_build_compiler" >>"$log" 2>&1
  ./scripts/build_rtobj_seed.sh --compiler "$compiler" --build-compiler "$seed_build_compiler" --debug >>"$log" 2>&1
fi

if [[ "$green_runs" -gt 0 ]]; then
  echo "== green join waiter stress (green mode, runs=$green_runs, iters=$green_iters) ==" | tee -a "$log"
  OREN_QI_STRESS_MODE=green \
    OREN_QI_STRESS_ITERS="$green_iters" \
    ./scripts/triage_native_quick_green_join_waiters_stress_flake.sh "$green_runs" "$compiler" "$@" \
    >>"$log" 2>&1
fi

if [[ "$os_runs" -gt 0 ]]; then
  echo "== green join waiter stress (os mode, runs=$os_runs, iters=$os_iters) ==" | tee -a "$log"
  OREN_QI_STRESS_MODE=os \
    OREN_QI_STRESS_ITERS="$os_iters" \
    ./scripts/triage_native_quick_green_join_waiters_stress_flake.sh "$os_runs" "$compiler" "$@" \
    >>"$log" 2>&1
fi

echo "OK: green join-waiter split checks passed (log=$log)" >&2
