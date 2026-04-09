#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "Builds the focused green local-ptr binary once and reruns the direct mixed both-mode slice." >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
extra_env=()
if [[ "$#" -gt 2 ]]; then
  extra_env=("${@:3}")
fi

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi
if [[ "$runs" -le 0 ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"
compiler_base="$(basename "$compiler")"
label="${OREN_QI_LABEL:-native_quick_green_local_ptr_both_direct}"
src="tests/native/test_quick_integration_green_local_ptr_focus.oren"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

mkdir -p build/tmp build/logs
out="build/tmp/${compiler_base}_${label}${exe_ext}"
build_log="build/logs/${compiler_base}_${label}_build.log"

echo "== build focused green local-ptr direct binary ==" >&2
echo "compiler=$compiler" >&2
echo "src=$src" >&2
echo "out=$out" >&2

"$compiler" build "$src" --backend native --platform "$platform" --debug -o "$out" >"$build_log" 2>&1

run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/${compiler_base}_${label}_${ts}_run${run}.log"
  echo "== direct run ${run}/${runs} ==" >&2
  {
    echo "ts=$ts"
    echo "run=${run}/${runs}"
    echo "compiler=$compiler"
    echo "platform=$platform"
    echo "src=$src"
    echo "out=$out"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  } >"$log"
  set +e
  env \
    OREN_QI_TRACE=1 \
    OREN_QI_STRESS_ITERS="${OREN_QI_STRESS_ITERS:-4}" \
    OREN_QI_LOCAL_PTR_MODE="${OREN_QI_LOCAL_PTR_MODE:-both}" \
    OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY="${OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY:-1}" \
    OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS="${OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS:-0}" \
    OREN_TRACE_LIST_GET_BAD=1 \
    OREN_TRACE_GREEN_RUNQ_GUARD=1 \
    OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1 \
    OREN_TRACE_GREEN_ARGS_STAMP=1 \
    OREN_TRACE_GREEN_LAST_OPS=1 \
    "${extra_env[@]}" \
    "$out" >>"$log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    err_log="build/logs/${compiler_base}_${label}_${ts}_run${run}_err.log"
    cp -f "$log" "$err_log"
    echo "FAIL: direct run ${run} rc=${rc} log=${log}" >&2
    tail -n 120 "$log" >&2 || true
    exit "$rc"
  fi
  run=$((run + 1))
done

echo "OK: ${runs} direct runs passed" >&2
