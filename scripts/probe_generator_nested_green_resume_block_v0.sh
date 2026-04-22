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
  echo "probe_generator_nested_green_resume_block_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/generator_nested_green_resume_block_v0_${ts}"
log="build/logs/probe_generator_nested_green_resume_block_v0_${ts}.log"
mkdir -p "$tmpdir"

src="tests/fixtures/generator_nested_green_resume_block_v0.oren"
native_out="$tmpdir/generator_nested_green_resume_block_v0_native"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

run_ok "$compiler" build "$src" \
  --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"

echo "\$ /usr/bin/perl -e 'alarm shift @ARGV; exec @ARGV' 6 env OREN_TRACE_GENERATOR_CORE=1 OREN_TRACE_GREEN_RUNQ_ARGS=1 $native_out" >>"$log"
if /usr/bin/perl -e 'alarm shift @ARGV; exec @ARGV' 6 \
  env OREN_TRACE_GENERATOR_CORE=1 OREN_TRACE_GREEN_RUNQ_ARGS=1 \
  "$native_out" >>"$log" 2>&1; then
  echo "probe_generator_nested_green_resume_block_v0: expected nested green resume to block" >&2
  exit 1
fi

grep -F "main:before_next" "$log" >/dev/null
grep -F "outer:start" "$log" >/dev/null
grep -F "outer:before_next" "$log" >/dev/null
grep -F "trace: green_runq push_local" "$log" >/dev/null
grep -F "[trace] generator resume.after_yield" "$log" >/dev/null
if grep -F "inner:start" "$log" >/dev/null; then
  echo "probe_generator_nested_green_resume_block_v0: expected inner worker to remain unscheduled in blocked repro" >&2
  exit 1
fi

echo "generator nested green resume block repro OK" >>"$log"
echo "generator nested green resume block repro OK"
