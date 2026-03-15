#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "env: OREN_NATIVE_BUILD_TIMEOUT_SECS / OREN_NATIVE_RUN_TIMEOUT_SECS / OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS" >&2
  echo "env: OREN_QI_STOP_BEFORE_WORLD_LOCK=1 (skip world-lock smoke)" >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren_stage2}"
if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi
if [[ "$runs" -le 0 ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  exit 2
fi

compiler_base="$(basename "$compiler")"
env_args=()
if [[ "$#" -gt 2 ]]; then
  env_args=("${@:3}")
fi

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=10
run_timeout_secs=5
if [[ -n "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS}"
fi
if [[ -n "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  run_timeout_secs="${OREN_NATIVE_RUN_TIMEOUT_SECS}"
fi

run_with_timeout() {
  local secs="$1"
  shift
  if [[ "${uname_s:-}" == "Darwin" ]]; then
    if [[ -z "$secs" || "$secs" == "0" ]]; then
      "$@"
      return $?
    fi
    set +e
    "$@" &
    local pid=$!
    (
      sleep "$secs"
      kill -TERM "$pid" 2>/dev/null
      sleep "$timeout_kill_secs"
      kill -KILL "$pid" 2>/dev/null
    ) &
    local watcher=$!
    wait "$pid"
    local rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    set -e
    return "$rc"
  fi

  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

run_with_timeout_retry() {
  local secs="$1"
  shift
  run_with_timeout "$secs" "$@"
  local rc=$?
  if [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]; then
    local secs2=$((secs * 2))
    echo "WARN: timeout (rc=$rc). Retrying with ${secs2}s." >&2
    run_with_timeout "$secs2" "$@"
    return $?
  fi
  return "$rc"
}

run_smoke_step() {
  local label="$1"
  local src="$2"
  local out="$3"
  local step_log="$4"
  local run_secs="$5"
  local tail_lines="${6:-5}"
  rm -f "$step_log" "$out" 2>/dev/null || true
  if ! run_with_timeout "$build_timeout_secs" "$compiler" build "$src" \
    --backend native --platform "$platform" --debug -o "$out" >"$step_log" 2>&1; then
    local rc=$?
    echo "== ${label} ==" >>"$log"
    echo "FAIL: build rc=${rc}" >>"$log"
    tail -n 120 "$step_log" >>"$log" 2>/dev/null || true
    echo "FAIL: ${label} build rc=${rc}; see ${log}" >&2
    exit "$rc"
  fi
  local rc=0
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    run_with_timeout_retry "$run_secs" env "${env_args[@]}" "$out" >>"$step_log" 2>&1 || rc=$?
  else
    run_with_timeout_retry "$run_secs" "$out" >>"$step_log" 2>&1 || rc=$?
  fi
  echo "== ${label} ==" >>"$log"
  tail -n "$tail_lines" "$step_log" >>"$log" 2>/dev/null || true
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run rc=${rc}" >>"$log"
    tail -n 120 "$step_log" >>"$log" 2>/dev/null || true
    echo "FAIL: ${label} run rc=${rc}; see ${log}" >&2
    exit "$rc"
  fi
}

uname_s="$(uname -s)"
uname_m="$(uname -m)"

os_key=""
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac

if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  run_timeout_secs=12
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  build_timeout_secs=20
fi

arch_key=""
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"

mkdir -p build/tmp build/logs

current_log=""
current_inner_src=""
current_err_log=""
trap_cleanup() {
  local sig="$1"
  if [[ -n "${current_log}" ]]; then
    echo "INTERRUPTED: signal ${sig}" >>"$current_log"
  fi
  if [[ -n "${current_inner_src}" && -n "${current_err_log}" && -f "${current_inner_src}" ]]; then
    cp -f "${current_inner_src}" "${current_err_log}" 2>/dev/null || true
  fi
}
trap 'trap_cleanup TERM; exit 143' TERM
trap 'trap_cleanup INT; exit 130' INT

compiler_base="$(basename "$compiler")"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
  if [[ -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
    build_timeout_secs=30
  fi
  if [[ -z "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
    run_timeout_secs=10
  fi
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  if [[ "$compiler_base" == *stage2* ]]; then
    run_timeout_secs=15
  fi
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  if [[ "$compiler_base" == *stage2* ]]; then
    build_timeout_secs=25
  fi
fi

green_cache_run_timeout_secs="$run_timeout_secs"
if [[ -n "${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS:-}" ]]; then
  green_cache_run_timeout_secs="${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS}"
fi

stop_before_world_lock="${OREN_QI_STOP_BEFORE_WORLD_LOCK:-0}"

run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/${compiler_base}_native_quick_until_world_lock_${ts}_run${run}.log"
  current_log="$log"
  current_inner_src="build/logs/${compiler_base}_native_quick_integration.log"
  current_err_log="build/logs/${compiler_base}_native_quick_until_world_lock_${ts}_run${run}_interrupt.log"
  echo "== run ${run}/${runs} ==" >&2
  echo "log: ${log}" >&2
  : >"$log"
  {
    echo "ts=$ts"
    echo "run=${run}/${runs}"
    echo "compiler=$compiler"
    echo "platform=$platform"
    echo "cwd=$(pwd)"
    echo "uname=$(uname -a)"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    echo "build_timeout_secs=$build_timeout_secs"
    echo "run_timeout_secs=$run_timeout_secs"
    echo "green_cache_run_timeout_secs=$green_cache_run_timeout_secs"
    echo "stop_before_world_lock=$stop_before_world_lock"
  } >>"$log"
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    echo "env: ${env_args[*]}" >>"$log"
  fi

  qi_src="tests/native/test_quick_integration_native.oren"
  qi_out="build/tmp/${compiler_base}_native_quick_integration${exe_ext}"
  qi_log="build/logs/${compiler_base}_native_quick_integration.log"
  rm -f "$qi_log" "$qi_out" 2>/dev/null || true
  if ! run_with_timeout "$build_timeout_secs" "$compiler" build "$qi_src" \
    --backend native --platform "$platform" --debug -o "$qi_out" >"$qi_log" 2>&1; then
    rc=$?
    echo "== native quick integration ==" >>"$log"
    echo "FAIL: build rc=${rc}" >>"$log"
    tail -n 120 "$qi_log" >>"$log" 2>/dev/null || true
    echo "FAIL: native quick integration build rc=${rc}; see ${log}" >&2
    exit "$rc"
  fi
  rc=0
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    run_with_timeout_retry "$run_timeout_secs" env "${env_args[@]}" "$qi_out" >>"$qi_log" 2>&1 || rc=$?
  else
    run_with_timeout_retry "$run_timeout_secs" "$qi_out" >>"$qi_log" 2>&1 || rc=$?
  fi
  echo "== native quick integration ==" >>"$log"
  tail -n 5 "$qi_log" >>"$log"
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run rc=${rc}" >>"$log"
    tail -n 120 "$qi_log" >>"$log" 2>/dev/null || true
    echo "FAIL: native quick integration run rc=${rc}; see ${log}" >&2
    exit "$rc"
  fi
  echo "== native quick integration (OREN_GREEN_POLL_CACHE=1) ==" >>"$qi_log"
  rc=0
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    run_with_timeout_retry "$green_cache_run_timeout_secs" env OREN_GREEN_POLL_CACHE=1 "${env_args[@]}" "$qi_out" >>"$qi_log" 2>&1 || rc=$?
  else
    run_with_timeout_retry "$green_cache_run_timeout_secs" env OREN_GREEN_POLL_CACHE=1 "$qi_out" >>"$qi_log" 2>&1 || rc=$?
  fi
  echo "== native quick integration (OREN_GREEN_POLL_CACHE=1) ==" >>"$log"
  tail -n 5 "$qi_log" >>"$log"
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: run rc=${rc}" >>"$log"
    tail -n 120 "$qi_log" >>"$log" 2>/dev/null || true
    echo "FAIL: native quick integration (OREN_GREEN_POLL_CACHE=1) run rc=${rc}; see ${log}" >&2
    exit "$rc"
  fi

  ul_src="tests/native/test_ulock_timeout_portable.oren"
  ul_out="build/tmp/${compiler_base}_ulock_timeout_portable${exe_ext}"
  ul_log="build/logs/${compiler_base}_ulock_timeout_portable.log"
  run_smoke_step "ulock timeout portable smoke" "$ul_src" "$ul_out" "$ul_log" "$run_timeout_secs" 3

  ot_src="tests/native/test_os_thread_park_unpark_smoke.oren"
  ot_out="build/tmp/${compiler_base}_os_thread_park_unpark_smoke${exe_ext}"
  ot_log="build/logs/${compiler_base}_os_thread_park_unpark_smoke.log"
  run_smoke_step "os thread park/unpark smoke" "$ot_src" "$ot_out" "$ot_log" "$run_timeout_secs" 3

  om_src="tests/native/test_os_thread_spawn_many_smoke.oren"
  om_out="build/tmp/${compiler_base}_os_thread_spawn_many_smoke${exe_ext}"
  om_log="build/logs/${compiler_base}_os_thread_spawn_many_smoke.log"
  run_smoke_step "os thread spawn-many smoke" "$om_src" "$om_out" "$om_log" "$run_timeout_secs" 3

  gc_src="tests/native/test_gc_stw_os_thread_collect.oren"
  gc_out="build/tmp/${compiler_base}_gc_stw_os_thread_collect${exe_ext}"
  gc_log="build/logs/${compiler_base}_gc_stw_os_thread_collect.log"
  run_smoke_step "gc stw os-thread collect smoke" "$gc_src" "$gc_out" "$gc_log" "$run_timeout_secs" 3

  if [[ "$stop_before_world_lock" == "1" ]]; then
    echo "== green two workers world-lock smoke (skipped) ==" >>"$log"
    echo "skip_reason=OREN_QI_STOP_BEFORE_WORLD_LOCK=1" >>"$log"
    echo "run ${run}/${runs} OK (pre-world-lock stop); see ${log}" >&2
    run=$((run + 1))
    continue
  fi

  gw_src="tests/native/test_green_two_workers_world_lock_smoke.oren"
  gw_out="build/tmp/${compiler_base}_green_two_workers_world_lock_smoke${exe_ext}"
  gw_log="build/logs/${compiler_base}_green_two_workers_world_lock_smoke.log"
  run_smoke_step "green two workers world-lock smoke" "$gw_src" "$gw_out" "$gw_log" "$run_timeout_secs" 3

  echo "run ${run}/${runs} OK; see ${log}" >&2
  run=$((run + 1))
done

echo "OK: ${runs} runs passed" >&2
