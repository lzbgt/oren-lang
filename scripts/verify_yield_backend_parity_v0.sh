#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
platform="${OREN_PLATFORM:-}"

if [ -z "$platform" ]; then
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  case "$uname_s:$uname_m" in
    Darwin:arm64|Darwin:aarch64) platform="arm64-macos" ;;
    Darwin:x86_64) platform="x64-macos" ;;
    Linux:arm64|Linux:aarch64) platform="arm64-linux" ;;
    Linux:x86_64|Linux:amd64) platform="x64-linux" ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) platform="x64-windows" ;;
  esac
fi

if [ -z "$platform" ]; then
  echo "verify_yield_backend_parity_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/yield_backend_parity_v0_${ts}"
log="build/logs/verify_yield_backend_parity_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

ready_src="tests/fixtures/yield_lowering_v0_ready.oren"
bytecode_out="$tmpdir/ready_bytecode.obc"
c_out="$tmpdir/ready_c"
native_out="$tmpdir/ready_native"

run_ok env OREN_TRACE_BYTECODE_YIELD_LOWERING=1 "$compiler" build "$ready_src" \
  --backend bytecode --platform "$platform" --no-cache --strict-yield-lowering-v0 -o "$bytecode_out"
run_ok ./avm "$bytecode_out"

run_ok "$compiler" build "$ready_src" \
  --backend c --platform "$platform" --no-cache --no-debug --strict-yield-lowering-v0 -o "$c_out"
run_ok "$c_out"

run_ok "$compiler" build "$ready_src" \
  --backend native --platform "$platform" --no-cache --no-debug --strict-yield-lowering-v0 -o "$native_out"
run_ok "$native_out"

grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_worker" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_live_local" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_multi_yield" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_branch_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_block_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_loop_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_nested_capture" "$log"

echo "yield backend parity v0 verify OK" >>"$log"
echo "yield backend parity v0 verify OK"
