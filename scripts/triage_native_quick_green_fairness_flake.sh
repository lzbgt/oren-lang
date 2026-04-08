#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the focused green fairness quick-integration slice under the standard flake harness." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

mode="${OREN_QI_GREEN_FAIRNESS_MODE:-full}"
include_topology="${OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY:-1}"
mode_tag="$(printf '%s' "$mode" | tr -c 'A-Za-z0-9' '_')"
topology_tag="topology"
if [[ "$include_topology" == "0" ]]; then
  topology_tag="notopology"
fi
label_default="native_quick_green_fairness_${mode_tag}_${topology_tag}"

env \
  OREN_QI_SRC="tests/native/test_quick_integration_green_fairness_focus.oren" \
  OREN_QI_LABEL="${OREN_QI_LABEL:-$label_default}" \
  OREN_QI_TRACE=1 \
  OREN_QI_ONLY_GREEN_CACHE=1 \
  OREN_QI_FAIL_ON_RETRY=1 \
  OREN_QI_GREEN_CACHE_RETRIES=0 \
  OREN_QI_STRESS_ITERS="${OREN_QI_STRESS_ITERS:-4}" \
  OREN_QI_GREEN_FAIRNESS_MODE="$mode" \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY="$include_topology" \
  OREN_TRACE_GREEN_FAIRNESS=1 \
  OREN_TRACE_LIST_GET_BAD=1 \
  OREN_TRACE_GREEN_RUNQ_GUARD=1 \
  OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1 \
  OREN_TRACE_GREEN_ARGS_STAMP=1 \
  OREN_TRACE_GREEN_LAST_OPS=1 \
  "${extra_env[@]}" \
  ./scripts/triage_native_quick_flake.sh "$runs" "$compiler"
