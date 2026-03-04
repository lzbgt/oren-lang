#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "usage: $0 [runs] [compiler] [ENV=VAL ...]" >&2
  echo "env: OREN_QI_AUTO_RERUN_GUARDRAILS=1 to re-run failures with guardrails" >&2
  echo "env: OREN_QI_AUTO_RERUN_ENV='KEY=VAL ...' to override guardrail env" >&2
  exit 0
fi

runs="${1:-10}"
compiler="${2:-./oren}"
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

mkdir -p build/logs

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

auto_rerun="${OREN_QI_AUTO_RERUN_GUARDRAILS:-0}"
auto_env_default=(
  "OREN_TRACE_LIST_CORRUPT=1"
  "OREN_TRACE_LIST_HDR_RING=1"
  "OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1"
  "OREN_TRACE_LIST_HDR_RING_CAP=2048"
  "OREN_TRACE_LIST_HDR_RING_DUP=1"
  "OREN_TRACE_LIST_HDR_RING_DUP_CAP=128"
  "OREN_TRACE_GC_FREE_LIST_HDR_RING=1"
  "OREN_TRACE_GREEN_SPAWN_ALLOC_GUARD=1"
  "OREN_TRACE_GREEN_SPAWN_ALLOC_STRIDE=256"
  "OREN_TRACE_GREEN_SPAWN_RING=1"
  "OREN_TRACE_GREEN_SPAWN_RING_CAP=64"
)

run_integration() {
  local log="$1"
  shift
  : >"$log"
  {
    echo "ts=$ts"
    echo "run=${run}/${runs}"
    echo "compiler=$compiler"
    echo "cwd=$(pwd)"
    echo "uname=$(uname -a)"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  } >>"$log"
  if [[ "$#" -gt 0 ]]; then
    echo "env: $*" >>"$log"
    env "$@" ./scripts/run_native_quick_integration.sh "$compiler" >>"$log" 2>&1
  else
    ./scripts/run_native_quick_integration.sh "$compiler" >>"$log" 2>&1
  fi
  return $?
}

run=1
while [[ "$run" -le "$runs" ]]; do
  ts="$(date +%Y%m%d_%H%M%S)"
  log="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}.log"
  inner_log="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}_inner.log"
  current_log="$log"
  current_inner_src="build/logs/${compiler_base}_native_quick_integration.log"
  current_err_log="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}_interrupt.log"
  echo "== run ${run}/${runs} ==" >&2
  set +e
  if [[ "${#env_args[@]}" -gt 0 ]]; then
    run_integration "$log" "${env_args[@]}"
  else
    run_integration "$log"
  fi
  rc=$?
  set -e
  if [[ -f "build/logs/${compiler_base}_native_quick_integration.log" ]]; then
    cp -f "build/logs/${compiler_base}_native_quick_integration.log" "$inner_log"
  fi
  if [[ "$rc" -ne 0 ]]; then
    local_err_log="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}_err.log"
    if [[ -f "build/logs/${compiler_base}_native_quick_integration.log" ]]; then
      cp -f "build/logs/${compiler_base}_native_quick_integration.log" "$local_err_log"
    fi
  fi
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$auto_rerun" == "1" ]]; then
      guard_log="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}_guardrails.log"
      guard_inner="build/logs/${compiler_base}_native_quick_flake_${ts}_run${run}_guardrails_inner.log"
      guard_env=()
      if [[ -n "${OREN_QI_AUTO_RERUN_ENV:-}" ]]; then
        read -r -a guard_env <<<"${OREN_QI_AUTO_RERUN_ENV}"
      else
        guard_env=("${auto_env_default[@]}")
      fi
      if [[ "${#env_args[@]}" -gt 0 ]]; then
        guard_env=("${env_args[@]}" "${guard_env[@]}")
      fi
      echo "auto_rerun_guardrails=1" >>"$log"
      echo "auto_rerun_env: ${guard_env[*]}" >>"$log"
      set +e
      run_integration "$guard_log" "${guard_env[@]}"
      guard_rc=$?
      set -e
      if [[ -f "build/logs/${compiler_base}_native_quick_integration.log" ]]; then
        cp -f "build/logs/${compiler_base}_native_quick_integration.log" "$guard_inner"
      fi
      echo "auto_rerun_rc=${guard_rc} guard_log=${guard_log}" >>"$log"
      if [[ "$guard_rc" -ne 0 ]]; then
        echo "== guardrails log tail ==" >&2
        tail -n 120 "$guard_log" >&2 || true
        if [[ -f "$guard_inner" ]]; then
          echo "== guardrails inner log tail ==" >&2
          tail -n 80 "$guard_inner" >&2 || true
        fi
      fi
    fi
    echo "FAIL: run ${run} rc=${rc} log=${log}" >&2
    tail -n 120 "$log" >&2 || true
    if [[ -f "$inner_log" ]]; then
      echo "== inner log tail ==" >&2
      tail -n 80 "$inner_log" >&2 || true
    fi
    exit "$rc"
  fi
  run=$((run + 1))
done

echo "OK: ${runs} runs passed" >&2
