#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Runs only the green-cache rerun path from native quick integration." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi

if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler" >&2
  exit 2
fi

OREN_QI_STOP_AFTER_GREEN_CACHE=1 \
./scripts/triage_native_quick_flake.sh "$runs" "$compiler" \
  OREN_QI_TRACE=1 \
  OREN_TRACE_GC_STW=1 \
  OREN_TRACE_GREEN_RUNQ_GUARD=1 \
  OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1 \
  "$@"
