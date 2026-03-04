#!/usr/bin/env bash
set -euo pipefail

runs="${1:-3}"
compiler="${2:-./oren_stage2}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [runs] [compiler] [ENV=VAL ...]"
  exit 2
fi

if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler"
  exit 2
fi

OREN_NATIVE_RUN_TIMEOUT_SECS=60 \
OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=60 \
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
./scripts/triage_native_quick_stage2_flake.sh "$runs" "$compiler" \
  OREN_QI_TRACE_GREEN_LIST_GUARD=0 \
  OREN_QI_TRACE_GREEN_LIST=0 \
  OREN_QI_TRACE_GREEN_LIST_LIGHT=0 \
  OREN_TRACE_GREEN_ENTRY_ARGS=0 \
  OREN_TRACE_GREEN_ENTRY_ARGS_LIGHT=0 \
  OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=0 \
  OREN_TRACE_GREEN_ARGS_STAMP=0 \
  OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1 \
  OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=256 \
  OREN_TRACE_GREEN_SPAWN_RING=1 \
  OREN_TRACE_GREEN_SPAWN_RING_CAP=64 \
  OREN_TRACE_LIST_HDR_RING=1 \
  OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1 \
  OREN_TRACE_LIST_HDR_RING_CAP=2048 \
  OREN_TRACE_LIST_HDR_RING_DUP=1 \
  OREN_TRACE_LIST_HDR_RING_DUP_CAP=128 \
  "$@"
