#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-./oren_stage2}"
mkdir -p "$ROOT/build/logs" "$ROOT/build/tmp"

if [[ ! -x "$COMPILER" ]]; then
  echo "Compiler not found or not executable: $COMPILER" >&2
  exit 2
fi

build_case() {
  local name="$1"
  local src="$2"
  local mode_flag="$3"
  shift 3
  local out="$ROOT/build/tmp/${name}"
  local log="$ROOT/build/logs/${name}.build.log"
  rm -f "$out" "$log" 2>/dev/null || true
  env OREN_NO_CACHE=1 "$@" "$COMPILER" build "$ROOT/$src" \
    --backend native "$mode_flag" --no-cache -o "$out" >"$log" 2>&1
  printf '%s\n' "$out"
}

run_case() {
  local name="$1"
  local expected="$2"
  local bin="$3"
  shift 3
  local log="$ROOT/build/logs/${name}.run.log"
  rm -f "$log" 2>/dev/null || true
  set +e
  env \
    OREN_GC_AUTO=1 \
    OREN_GC_ALLOC_THRESHOLD=10 \
    OREN_GC_REUSE_BLOCKS=1 \
    OREN_GC_REUSE_LISTS=1 \
    OREN_GC_REUSE_LISTS_UNSAFE=1 \
    OREN_GC_POISON_LIST_HEADERS=1 \
    OREN_TRACE_CRASH_FOOTER=1 \
    OREN_TRACE_LIST_PANIC_FOOTER=1 \
    "$@" \
    "$bin" >"$log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: tracking smoke '$name' exited rc=$rc (log=$log)" >&2
    tail -n 120 "$log" >&2 || true
    exit 1
  fi
  if rg -n "on non-list|\\[gc_reuse_bad_list\\]" "$log" >/dev/null 2>&1; then
    echo "ERROR: tracking smoke '$name' emitted a list-tracking failure (log=$log)" >&2
    tail -n 160 "$log" >&2 || true
    exit 1
  fi
  local out
  out="$(tail -n 1 "$log" | tr -d '\r')"
  if [[ "$out" != "$expected" ]]; then
    echo "ERROR: tracking smoke '$name' expected '$expected' but saw '$out' (log=$log)" >&2
    tail -n 120 "$log" >&2 || true
    exit 1
  fi
  echo "ok: $name (log=$log)"
}

min_bin="$(build_case gc_reuse_alloc_churn_min tests/native/test_gc_reuse_alloc_churn_min.oren --no-debug OREN_ARENA_AUTO_LOOP=0)"
run_case gc_reuse_alloc_churn_min 0 "$min_bin"

generic_bin="$(build_case gc_reuse_alloc_churn_generic tests/native/test_gc_reuse_alloc_churn_generic.oren --no-debug OREN_ARENA_AUTO_LOOP=0)"
run_case gc_reuse_alloc_churn_generic 0 "$generic_bin"

collect_bin="$(build_case gc_collect_list_int_live tests/native/test_gc_collect_list_int_live.oren --no-debug OREN_ARENA_AUTO_LOOP=0)"
run_case gc_collect_list_int_live 999 "$collect_bin"

collect_len128_bin="$(build_case gc_collect_list_int_len128_loop_live tests/native/test_gc_collect_list_int_len128_loop_live.oren --no-debug OREN_ARENA_AUTO_LOOP=0)"
run_case gc_collect_list_int_len128_loop_live 7028 "$collect_len128_bin"

auto_bin="$(build_case gc_auto_list_int_live tests/native/test_gc_auto_list_int_live.oren --no-debug OREN_ARENA_AUTO_LOOP=0)"
run_case gc_auto_list_int_live 127 "$auto_bin"

echo "OK: alloc_churn tracking smoke passed"
