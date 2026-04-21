#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren}"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/yield_lowering_v0_${ts}"
log="build/logs/verify_yield_lowering_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

run_fail() {
  local out="$1"
  shift
  echo "\$ $*" >>"$log"
  set +e
  "$@" >"$out" 2>&1
  local rc=$?
  set -e
  cat "$out" >>"$log"
  if [ "$rc" -eq 0 ]; then
    echo "expected failure: $*" >>"$log"
    cat "$log"
    exit 1
  fi
}

ready_src="tests/fixtures/yield_lowering_v0_ready.oren"
blocked_src="tests/fixtures/yield_lowering_v0_blocked.oren"

ready_meta="$tmpdir/ready.meta.json"
ready_dump="$tmpdir/ready.linked.json"
ready_obc="$tmpdir/ready.obc"
blocked_nonstrict_obc="$tmpdir/blocked.nonstrict.obc"

run_ok "$compiler" meta "$ready_src" -o "$ready_meta" --strict-yield-lowering-v0
run_ok "$compiler" dump linked "$ready_src" -o "$ready_dump" --strict-yield-lowering-v0
run_ok "$compiler" build "$ready_src" --backend bytecode -o "$ready_obc" --strict-yield-lowering-v0
run_ok "$compiler" build "$blocked_src" --backend bytecode -o "$blocked_nonstrict_obc"

blocked_meta_log="$tmpdir/blocked.meta.log"
blocked_dump_log="$tmpdir/blocked.dump.log"
blocked_build_log="$tmpdir/blocked.build.log"

run_fail "$blocked_meta_log" "$compiler" meta "$blocked_src" -o "$tmpdir/blocked.meta.json" --strict-yield-lowering-v0
run_fail "$blocked_dump_log" "$compiler" dump linked "$blocked_src" -o "$tmpdir/blocked.linked.json" --strict-yield-lowering-v0
run_fail "$blocked_build_log" "$compiler" build "$blocked_src" --backend bytecode -o "$tmpdir/blocked.obc" --strict-yield-lowering-v0

for f in "$blocked_meta_log" "$blocked_dump_log" "$blocked_build_log"; do
  grep -q "yield lowering v0 blocked" "$f"
  grep -q "blocked_multi_yield" "$f"
  grep -q "blocked_live_local" "$f"
  grep -q "blocked_nested_literal" "$f"
  grep -q "blocked_non_top_level" "$f"
  grep -q "multiple_yields" "$f"
  grep -q "live_locals_across_yield" "$f"
  grep -q "nested_function_literal" "$f"
  grep -q "non_top_level_yield" "$f"
done

echo "yield lowering v0 verify OK" >>"$log"
echo "yield lowering v0 verify OK"
