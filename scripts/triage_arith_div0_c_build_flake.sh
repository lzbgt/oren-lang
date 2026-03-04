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

mkdir -p build/logs build/tmp

trace_ring_cap="${OREN_TRACE_LIST_HDR_RING_CAP:-4096}"
trace_corrupt_cap="${OREN_TRACE_LIST_CORRUPT_CAP:-256}"

for i in $(seq 1 "$runs"); do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/arith_div0_c_build_flake_${ts}_run${i}.log"
  uname_out="$(uname -a)"
  git_rev="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

  {
    echo "ts=$ts"
    echo "run=${i}/${runs}"
    echo "compiler=$compiler"
    echo "cwd=$(pwd)"
    echo "uname=$uname_out"
    echo "git_rev=$git_rev"
    echo "env: OREN_TRACE_LIST_HDR_RING=1 OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1 OREN_TRACE_LIST_HDR_RING_CAP=${trace_ring_cap} OREN_TRACE_LIST_CORRUPT=1 OREN_TRACE_LIST_CORRUPT_CAP=${trace_corrupt_cap}"
    echo "== build: C backend (arith_div0) =="
  } >"$log"

  set +e
  OREN_TRACE_LIST_HDR_RING=1 \
  OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1 \
  OREN_TRACE_LIST_HDR_RING_CAP="$trace_ring_cap" \
  OREN_TRACE_LIST_CORRUPT=1 \
  OREN_TRACE_LIST_CORRUPT_CAP="$trace_corrupt_cap" \
  "$compiler" build tests/native/fixtures/arith_div0.oren --backend c -o build/tmp/arith_div0_c_dbg \
    >>"$log" 2>&1
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run $i rc=$rc log=$log" >&2
    exit "$rc"
  fi

done

echo "OK: $runs runs passed" >&2
