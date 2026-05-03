#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
platform="${OREN_PLATFORM:-}"
source scripts/verify_parallel_jobs.sh
native_build_timeout_secs="${OREN_VERIFY_NATIVE_BUILD_TIMEOUT_SECS:-180}"

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
  echo "verify_task_surface_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/task_surface_v0_${ts}"
log="build/logs/verify_task_surface_v0_${ts}.log"
mkdir -p "$tmpdir"
native_astbin_seed="$(verify_native_astbin_seed_path "$platform" "$log" || true)"
if [ -n "$native_astbin_seed" ]; then
  echo "native_runtime_astbin_seed=$native_astbin_seed" >>"$log"
fi

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

src="tests/fixtures/task_surface_v0.oren"
bytecode_out="$tmpdir/task_bytecode.obc"
c_out="$tmpdir/task_c"
native_out="$tmpdir/task_native"

run_bytecode() {
  run_logged "$compiler" build "$src" --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
  run_logged ./avm "$bytecode_out"
}

run_c() {
  run_logged "$compiler" build "$src" --backend c --platform "$platform" --no-cache --no-debug -o "$c_out"
  run_logged "$c_out"
}

run_native() {
  run_native_build_timeout_logged "$native_build_timeout_secs" "$compiler" build "$src" --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"
  run_logged "$native_out"
}

verify_parallel_start bytecode run_bytecode
verify_parallel_start c run_c
verify_parallel_start native run_native
verify_parallel_wait "$log"

echo "verify_task_surface_v0: OK ($log)"
