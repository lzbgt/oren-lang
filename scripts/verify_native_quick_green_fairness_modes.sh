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

echo "== focused fairness: full + topology ==" >&2
./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=1 \
  OREN_QI_LABEL=native_quick_green_fairness_full_topology \
  "${extra_env[@]}"

echo "== focused fairness: full without topology ==" >&2
./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler" \
  OREN_QI_GREEN_FAIRNESS_MODE=full \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_full_notopology \
  "${extra_env[@]}"

echo "== focused fairness: short-only without topology ==" >&2
./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler" \
  OREN_QI_GREEN_FAIRNESS_MODE=short_only \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_short_only_notopology \
  "${extra_env[@]}"

echo "== focused fairness: hogs-only without topology ==" >&2
./scripts/triage_native_quick_green_fairness_flake.sh "$runs" "$compiler" \
  OREN_QI_GREEN_FAIRNESS_MODE=hogs_only \
  OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 \
  OREN_QI_LABEL=native_quick_green_fairness_hogs_only_notopology \
  "${extra_env[@]}"

echo "OK: focused green fairness mode splits passed" >&2
