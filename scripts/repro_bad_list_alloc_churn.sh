#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/build/tmp/alloc_churn_badlist}"
LOG_DIR="${LOG_DIR:-$ROOT/build/logs}"
RUNS="${RUNS:-10}"
BUILD="${BUILD:-1}"
EXTRA_TRACE="${EXTRA_TRACE:-0}"
CRASH_FOOTER="${CRASH_FOOTER:-1}"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required (ripgrep)." >&2
  exit 2
fi

if [ "$BUILD" != "0" ]; then
  env OREN_NO_CACHE=1 "$ROOT/./oren_stage2" build benchmarks/alloc_churn/alloc_churn.oren \
    --backend native --no-debug --no-cache -o "$BIN"
fi

mkdir -p "$LOG_DIR"

iters_list=(20000 200000 500000 1000000)
gc_every_list=(50 20 5 2 1)
gc_thr_list=(200 50 20 10 5)
list_len_list=(64 128)
force_int_list=(0 1)
small_ints_list=(0 1)

for ((i=0; i<RUNS; i++)); do
  iters="${iters_list[i % ${#iters_list[@]}]}"
  gc_every="${gc_every_list[i % ${#gc_every_list[@]}]}"
  gc_thr="${gc_thr_list[i % ${#gc_thr_list[@]}]}"
  list_len="${list_len_list[i % ${#list_len_list[@]}]}"
  force_int="${force_int_list[i % ${#force_int_list[@]}]}"
  small_ints="${small_ints_list[i % ${#small_ints_list[@]}]}"

  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/alloc_churn_bad_list_auto_${ts}_${i}.log"

  set +e
  trace_extra_env=()
  crash_footer_env=()
  if [ "$EXTRA_TRACE" != "0" ]; then
    trace_extra_env+=("OREN_TRACE_GC_REUSE_SUMMARY=1")
    trace_extra_env+=("OREN_TRACE_GC_LIST_HDR_KIND=64")
    trace_extra_env+=("OREN_TRACE_GC_LIST_HDR_OK=64")
  fi
  if [ "$CRASH_FOOTER" != "0" ]; then
    crash_footer_env+=("OREN_TRACE_CRASH_FOOTER=1")
  fi

  env OREN_BENCH_ITERS="$iters" \
      OREN_BENCH_LIST_LEN="$list_len" \
      OREN_BENCH_GC_EVERY="$gc_every" \
      OREN_BENCH_FORCE_LIST_INT="$force_int" \
      OREN_BENCH_SMALL_INTS="$small_ints" \
      OREN_GC_AUTO=1 \
      OREN_GC_ALLOC_THRESHOLD="$gc_thr" \
      OREN_GC_REUSE_BLOCKS=1 \
      OREN_GC_REUSE_LISTS=1 \
      OREN_GC_REUSE_LISTS_UNSAFE=1 \
      OREN_GC_POISON_LIST_HEADERS=1 \
      OREN_TRACE_GC_REUSE_BAD_LIST=1 \
      OREN_TRACE_GC_REUSE_BAD_LIST_CAP=8 \
      OREN_TRACE_GC_REUSE_BAD_LIST_SAFE=1 \
      OREN_TRACE_GC_REUSE_BAD_LIST_RING_PRE=64 \
      OREN_TRACE_GC_REUSE_BAD_LIST_RING_RECENT=64 \
      OREN_TRACE_GC_RING_PRE=1 \
      OREN_TRACE_GC_RING_RECENT=1 \
      "${trace_extra_env[@]}" \
      "${crash_footer_env[@]}" \
      "$BIN" > "$log" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "run $i exited status $status (log=$log)" >&2
  fi

  if rg -n "\\[crash_footer_raw\\]" "$log" >/dev/null; then
    line="$(rg -m 1 -n "\\[crash_footer_raw\\]" "$log")"
    echo "crash_footer_raw: $line"
    if rg -n "\\[crash_footer_raw\\] ring idx=" "$log" >/dev/null; then
      echo "crash_footer_raw_ring:"
      rg -m 3 -n "\\[crash_footer_raw\\] ring idx=" "$log"
    fi
  fi

  if rg -n "\\[gc_reuse_bad_list\\]" "$log" >/dev/null; then
    line="$(rg -n "\\[gc_reuse_bad_list\\]" "$log" | head -n 1)"
    ptr="$(echo "$line" | sed -E 's/.*ptr=([0-9]+).*/\\1/')"
    node="$(echo "$line" | sed -E 's/.*node=([0-9]+).*/\\1/')"
    echo "bad-list hit: log=$log ptr=$ptr node=$node"
    echo "filters: OREN_TRACE_LIST_HDR_REINIT_PTR=$ptr OREN_TRACE_ALLOC_KIND_CHANGE_PTR=$ptr"
    echo "filters: OREN_TRACE_LIST_HDR_REINIT_NODE=$node OREN_TRACE_ALLOC_KIND_CHANGE_NODE=$node"
    exit 0
  fi
done

echo "no bad-list hits in $RUNS runs"
exit 1
