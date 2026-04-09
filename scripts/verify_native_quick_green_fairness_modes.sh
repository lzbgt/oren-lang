#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs focused green fairness mode splits sequentially under the standard flake harness." >&2
  exit 0
fi

runs="${1:-3}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

fail_count=0

run_case() {
  local title="$1"
  shift
  echo "== $title ==" >&2
  if ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler" "$@" "${extra_env[@]}"; then
    echo "PASS: $title" >&2
  else
    local rc=$?
    echo "FAIL: $title rc=$rc" >&2
    fail_count=$((fail_count + 1))
  fi
}

# Keep the leaf controls first so one full triage run still captures the useful passing surface
# before it reaches the mixed fairness repros.
run_case \
  "focused fairness: short-only without topology, zero-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=short_only \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=zero_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_short_only_notopology

run_case \
  "focused fairness: short-only without topology, one-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=short_only \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_short_only_notopology_onearg

run_case \
  "focused fairness: hogs-only without topology" \
  OREN_QI_GREEN_FAIRNESS_MODE=hogs_only \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=zero_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_hogs_only_notopology

run_case \
  "focused fairness: full + topology, zero-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=zero_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=1 \
  OREN_QI_LABEL=native_quick_green_fairness_full_topology

run_case \
  "focused fairness: full without topology, zero-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=zero_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_full_notopology_zeroarg

run_case \
  "focused fairness: full without topology, one-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg

run_case \
  "focused fairness: full + topology, one-arg shorts" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=1 \
  OREN_QI_LABEL=native_quick_green_fairness_full_topology_onearg

if [[ "$fail_count" -gt 0 ]]; then
  echo "FAIL: focused green fairness mode splits had $fail_count failing case(s)" >&2
  exit 1
fi

echo "OK: focused green fairness mode splits passed" >&2
