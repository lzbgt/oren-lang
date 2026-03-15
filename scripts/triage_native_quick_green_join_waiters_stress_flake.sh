#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the in-process GC join-waiter stress fixture under the standard flake harness." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

env \
  OREN_QI_SRC="tests/native/test_quick_integration_green_join_waiters_stress.oren" \
  OREN_QI_LABEL="native_quick_green_join_waiters_stress" \
  OREN_QI_TRACE=1 \
  OREN_QI_ONLY_GREEN_CACHE=1 \
  OREN_QI_STRESS_ITERS="${OREN_QI_STRESS_ITERS:-4}" \
  OREN_NATIVE_RUN_TIMEOUT_SECS="${OREN_NATIVE_RUN_TIMEOUT_SECS:-20}" \
  OREN_TRACE_GC_STW=1 \
  OREN_TRACE_GC_STW_WAITERS=1 \
  OREN_TRACE_GREEN_LAST_OPS=1 \
  "${extra_env[@]}" \
  ./scripts/triage_native_quick_flake.sh "$runs" "$compiler"
