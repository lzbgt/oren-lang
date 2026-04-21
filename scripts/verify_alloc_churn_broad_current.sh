#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-./oren_stage2}"
RUNS="${RUNS:-10}"
BUILD="${BUILD:-1}"
EXTRA_TRACE="${EXTRA_TRACE:-0}"
CRASH_FOOTER="${CRASH_FOOTER:-1}"
REPRO_BAD_LIST_CORRELATE="${REPRO_BAD_LIST_CORRELATE:-0}"

mkdir -p "$ROOT/build/logs"

if [[ ! -x "$COMPILER" ]]; then
  echo "Compiler not found or not executable: $COMPILER" >&2
  exit 2
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -le 0 ]]; then
  echo "RUNS must be a positive integer (got: $RUNS)" >&2
  exit 2
fi

ts="$(date +%Y%m%d_%H%M%S)"
log="$ROOT/build/logs/verify_alloc_churn_broad_current_${ts}.log"
direct_bin="$ROOT/build/tmp/gc_collect_alloc_churn_debug_shape_broad_verify"
direct_build_log="$ROOT/build/logs/gc_collect_alloc_churn_debug_shape_broad_verify_${ts}.build.log"
direct_run_log="$ROOT/build/logs/gc_collect_alloc_churn_debug_shape_broad_verify_${ts}.run.log"

env OREN_NO_CACHE=1 "$COMPILER" build "$ROOT/tests/native/test_gc_collect_alloc_churn_debug_shape.oren" \
  --backend native --no-debug --no-cache -o "$direct_bin" >"$direct_build_log" 2>&1

set +e
env OREN_TRACE_CRASH_FOOTER=1 "$direct_bin" >"$direct_run_log" 2>&1
direct_rc=$?
set -e

if [[ "$direct_rc" -ne 0 ]]; then
  echo "ERROR: direct alloc_churn debug-shape probe exited rc=$direct_rc (log=$direct_run_log)" >&2
  tail -n 160 "$direct_run_log" >&2 || true
  exit 1
fi

direct_out="$(tail -n 1 "$direct_run_log" | tr -d '\r')"
if [[ "$direct_out" != "0" ]]; then
  echo "ERROR: direct alloc_churn debug-shape probe expected '0' but saw '$direct_out' (log=$direct_run_log)" >&2
  tail -n 160 "$direct_run_log" >&2 || true
  exit 1
fi

set +e
RUNS="$RUNS" \
BUILD="$BUILD" \
EXTRA_TRACE="$EXTRA_TRACE" \
CRASH_FOOTER="$CRASH_FOOTER" \
REPRO_BAD_LIST_CORRELATE="$REPRO_BAD_LIST_CORRELATE" \
COMPILER="$COMPILER" \
  bash "$ROOT/scripts/repro_bad_list_alloc_churn.sh" >"$log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 1 ]] && rg -q "^no bad-list hits in ${RUNS} runs$" "$log"; then
  echo "OK: direct alloc_churn debug-shape probe and broad current regression stayed clean for $RUNS runs (logs=$direct_run_log,$log)"
  exit 0
fi

if [[ "$rc" -eq 0 ]]; then
  echo "ERROR: alloc_churn broad current regression reproduced a hit (log=$log)" >&2
  tail -n 160 "$log" >&2 || true
  exit 1
fi

echo "ERROR: alloc_churn broad current verification exited rc=$rc (log=$log)" >&2
tail -n 160 "$log" >&2 || true
exit 1
