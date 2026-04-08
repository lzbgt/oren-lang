#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs the focused green local-ptr plain-mode slice under the standard flake harness." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

env \
  OREN_QI_LABEL="native_quick_green_local_ptr_plain" \
  OREN_QI_LOCAL_PTR_MODE=plain \
  "${extra_env[@]}" \
  ./scripts/triage_native_quick_green_local_ptr_flake.sh "$runs" "$compiler"
