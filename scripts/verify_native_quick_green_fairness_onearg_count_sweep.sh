#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler]" >&2
  echo "Runs a serial one-arg green fairness count sweep and preserves every case result." >&2
  exit 0
fi

runs="${1:-3}"
compiler="${2:-./oren}"
fail_count=0

run_case() {
  local desc="$1"
  shift
  echo "== $desc ==" >&2
  if "$@"; then
    echo "PASS: $desc" >&2
  else
    local rc=$?
    echo "FAIL: $desc rc=$rc" >&2
    fail_count=$((fail_count + 1))
  fi
}

run_case "focused fairness: short-only, one-arg shorts=40" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=short_only \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=40 \
    OREN_QI_LABEL=native_quick_green_fairness_short_only_notopology_onearg_s40 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

run_case "focused fairness: full, one-arg shorts, hogs=1 shorts=1" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=full \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_HOGS=1 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=1 \
    OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg_h1_s1 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

run_case "focused fairness: full, one-arg shorts, hogs=8 shorts=1" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=full \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_HOGS=8 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=1 \
    OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg_h8_s1 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

run_case "focused fairness: full, one-arg shorts, hogs=1 shorts=8" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=full \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_HOGS=1 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=8 \
    OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg_h1_s8 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

run_case "focused fairness: full, one-arg shorts, hogs=8 shorts=8" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=full \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_HOGS=8 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=8 \
    OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg_h8_s8 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

run_case "focused fairness: full, one-arg shorts, hogs=8 shorts=40" \
  env \
    OREN_QI_GREEN_FAIRNESS_MODE=full \
    OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg \
    OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
    OREN_QI_GREEN_FAIRNESS_HOGS=8 \
    OREN_QI_GREEN_FAIRNESS_SHORTS=40 \
    OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg_h8_s40 \
    ./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler"

if [[ "$fail_count" -ne 0 ]]; then
  echo "FAIL: focused green fairness one-arg count sweep had $fail_count failing case(s)" >&2
  exit 1
fi

echo "OK: focused green fairness one-arg count sweep passed" >&2
