#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the focused green local-ptr quick-integration slice under the standard flake harness." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

env \
  OREN_QI_SRC="tests/native/test_quick_integration_green_local_ptr_focus.oren" \
  OREN_QI_LABEL="native_quick_green_local_ptr_focus" \
  OREN_QI_TRACE=1 \
  OREN_QI_ONLY_GREEN_CACHE=1 \
  OREN_QI_FAIL_ON_RETRY=1 \
  OREN_QI_GREEN_CACHE_RETRIES=0 \
  OREN_QI_STRESS_ITERS="${OREN_QI_STRESS_ITERS:-4}" \
  OREN_QI_LOCAL_PTR_MODE="${OREN_QI_LOCAL_PTR_MODE:-both}" \
  OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY="${OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY:-1}" \
  OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS="${OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS:-0}" \
  OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS="${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS:-720}" \
  OREN_TRACE_LIST_GET_BAD=1 \
  OREN_TRACE_GREEN_RUNQ_GUARD=1 \
  OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1 \
  OREN_TRACE_GREEN_ARGS_STAMP=1 \
  OREN_TRACE_GREEN_LAST_OPS=1 \
  "${extra_env[@]}" \
  ./scripts/triage_native_quick_flake.sh "$runs" "$compiler"
