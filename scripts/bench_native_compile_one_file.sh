#!/usr/bin/env bash
set -euo pipefail

# Benchmark the native backend "compile one file" throughput with bounded output.
#
# This is intended for rolling perf regressions and "it took >10s" investigations:
# - forces artifact cache off (`--no-cache`)
# - isolates the runtime object cache in a temp dir so you see a clean miss -> hit
# - applies a hard timeout per build step (default 10s) to avoid hangs
#
# Example:
#   ./scripts/bench_native_compile_one_file.sh
#   ./scripts/bench_native_compile_one_file.sh --debug --trace
#   OREN_NATIVE_BUILD_TIMEOUT_SECS=10 ./scripts/bench_native_compile_one_file.sh --no-debug

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="./oren_stage2"
src="examples/hello.oren"
platform=""
debug_flag="--no-debug"
trace=0

timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"

usage() {
  cat <<'EOF'
Usage: scripts/bench_native_compile_one_file.sh [options]

Options:
  --compiler <path>   compiler binary (default: ./oren_stage2)
  --src <path>        input source file (default: examples/hello.oren)
  --platform <spec>   platform override (default: auto-detect host, e.g. arm64-macos)
  --debug             measure debug builds (default is --no-debug)
  --no-debug          measure non-debug builds
  --trace             enable bounded phase tracing (OREN_TRACE_BUILD=1)
  --help              show this help

Env:
  OREN_NATIVE_BUILD_TIMEOUT_SECS   per-build timeout (default: 10)

Notes:
  - Always uses `--no-cache` (artifact cache off) so you measure real compilation work.
  - Uses an isolated runtime-object cache dir so the first build is a miss and the second is a hit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compiler)
      compiler="${2:-}"
      shift 2
      ;;
    --src)
      src="${2:-}"
      shift 2
      ;;
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --debug)
      debug_flag="--debug"
      shift
      ;;
    --no-debug)
      debug_flag="--no-debug"
      shift
      ;;
    --trace)
      trace=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$platform" ]]; then
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  os_key=""
  case "$uname_s" in
    Darwin) os_key="macos" ;;
    Linux) os_key="linux" ;;
    *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
  esac

  arch_key=""
  case "$uname_m" in
    arm64|aarch64) arch_key="arm64" ;;
    x86_64|amd64) arch_key="x64" ;;
    *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
  esac

  platform="${arch_key}-${os_key}"
fi

run_with_timeout() {
  local secs="$1"
  shift
  set +e
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  local killer=$!
  wait "$pid"
  local rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  set -e
  return "$rc"
}

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: compiler not found/executable: $compiler" >&2
  echo "Hint: build it with: make stage2" >&2
  exit 2
fi
if [[ ! -f "$src" ]]; then
  echo "ERROR: source file not found: $src" >&2
  exit 2
fi

mkdir -p build/tmp

rtobj_dir="$(mktemp -d build/tmp/rtobj_bench.XXXXXX)"
out="build/tmp/bench_native_out"

python_now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

export OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR="$rtobj_dir"
export OREN_TRACE_RUNTIME_OBJ_CACHE=1
if [[ "$trace" -ne 0 ]]; then
  export OREN_TRACE_BUILD=1
else
  unset OREN_TRACE_BUILD || true
fi

echo "== bench: native compile one file =="
echo "compiler=$compiler"
echo "src=$src"
echo "platform=$platform"
echo "debug_flag=$debug_flag"
echo "timeout=${timeout_secs}s"
echo "rtobj_dir=$rtobj_dir"

echo "-- run 1 (expected rtobj miss) --"
rm -f "$out" 2>/dev/null || true
ts0="$(python_now_ms)"
set +e
run_with_timeout "$timeout_secs" "$compiler" build "$src" --backend native --platform "$platform" --no-cache "$debug_flag" -o "$out"
rc1=$?
set -e
ts1="$(python_now_ms)"
echo "elapsed_ms=$((ts1 - ts0))"
if [[ "$rc1" -ne 0 ]]; then
  echo "ERROR: run 1 failed or timed out (rc=$rc1)" >&2
  exit "$rc1"
fi

echo "-- run 2 (expected rtobj hit) --"
rm -f "$out" 2>/dev/null || true
ts2="$(python_now_ms)"
set +e
run_with_timeout "$timeout_secs" "$compiler" build "$src" --backend native --platform "$platform" --no-cache "$debug_flag" -o "$out"
rc2=$?
set -e
ts3="$(python_now_ms)"
echo "elapsed_ms=$((ts3 - ts2))"
if [[ "$rc2" -ne 0 ]]; then
  echo "ERROR: run 2 failed or timed out (rc=$rc2)" >&2
  exit "$rc2"
fi

echo "OK: bench complete"
