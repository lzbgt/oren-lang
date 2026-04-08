#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs only the stage1/stage2 base quick-integration path with per-test trace output." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

env \
  OREN_QI_LABEL="native_quick_base_only" \
  OREN_QI_FAIL_ON_RETRY=1 \
  OREN_QI_TRACE=1 \
  OREN_QI_STOP_AFTER_BASE=1 \
  "${extra_env[@]}" \
  ./scripts/triage_native_quick_flake.sh "$runs" "$compiler"
