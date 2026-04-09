#!/usr/bin/env bash
set -euo pipefail

runs="${1:-3}"
compiler="${2:-./oren_stage2}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [runs] [compiler] [ENV=VAL ...]"
  exit 2
fi

if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler"
  exit 2
fi

base_runs="${OREN_RUNTIME_ROBUSTNESS_BASE_RUNS:-1}"
local_ptr_runs="${OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS:-1}"
preworld_runs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS:-1}"
stage2_runs="${OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS:-1}"
c_runs="${OREN_RUNTIME_ROBUSTNESS_C_RUNS:-$runs}"
fixtures="${OREN_RUNTIME_ROBUSTNESS_C_FIXTURES:-tests/native/fixtures/arith_div0.oren,tests/native/fixtures/arith_div_overflow.oren,tests/native/fixtures/index_set_negative.oren}"
base_build_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS:-720}"
preworld_build_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS:-240}"
preworld_run_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS:-30}"
preworld_green_cache_run_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS:-30}"
stage2_build_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_STAGE2_BUILD_TIMEOUT_SECS:-240}"

# Optional runtime tracing knobs (forwarded to child scripts).
# Example: OREN_RUNTIME_ROBUSTNESS_TRACE_ENV='OREN_TRACE_LIST_HDR_RING=1 OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1'
trace_env="${OREN_RUNTIME_ROBUSTNESS_TRACE_ENV:-}"
trace_env_arr=()
if [[ -n "$trace_env" ]]; then
  # shellcheck disable=SC2206
  trace_env_arr=($trace_env)
fi

mkdir -p build/logs

ts="$(date +%Y%m%d_%H%M%S)"
log="build/logs/runtime_robustness_w5_${ts}.log"
uname_out="$(uname -a)"
git_rev="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

{
  echo "ts=$ts"
  echo "runs=$runs"
  echo "base_runs=$base_runs"
  echo "local_ptr_runs=$local_ptr_runs"
  echo "preworld_runs=$preworld_runs"
  echo "stage2_runs=$stage2_runs"
  echo "c_runs=$c_runs"
  echo "compiler=$compiler"
  echo "cwd=$(pwd)"
  echo "uname=$uname_out"
  echo "git_rev=$git_rev"
  echo "fixtures=$fixtures"
  echo "base_build_timeout_secs=$base_build_timeout_secs"
  echo "preworld_build_timeout_secs=$preworld_build_timeout_secs"
  echo "preworld_run_timeout_secs=$preworld_run_timeout_secs"
  echo "preworld_green_cache_run_timeout_secs=$preworld_green_cache_run_timeout_secs"
  echo "stage2_build_timeout_secs=$stage2_build_timeout_secs"
  echo "trace_env=$trace_env"
} >"$log"

IFS=',' read -r -a fixture_arr <<< "$fixtures"

if [[ "$base_runs" =~ ^[0-9]+$ ]] && [[ "$base_runs" -gt 0 ]]; then
  echo "== stage1/base quick integration (runs=$base_runs) ==" | tee -a "$log"
  OREN_NATIVE_BUILD_TIMEOUT_SECS="$base_build_timeout_secs" \
    ./scripts/triage_native_quick_base_flake.sh "$base_runs" "$compiler" \
    "${trace_env_arr[@]}" "$@" \
    >>"$log" 2>&1
fi

if [[ "$local_ptr_runs" =~ ^[0-9]+$ ]] && [[ "$local_ptr_runs" -gt 0 ]]; then
  echo "== stage1/green-cache local-ptr mixed both-mode direct focus (runs=$local_ptr_runs) ==" | tee -a "$log"
  ./scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh "$local_ptr_runs" "$compiler" \
    "${trace_env_arr[@]}" "$@" \
    >>"$log" 2>&1
fi

if [[ "$preworld_runs" =~ ^[0-9]+$ ]] && [[ "$preworld_runs" -gt 0 ]]; then
  echo "== stage1/pre-world-lock guarded green-cache quick integration (runs=$preworld_runs) ==" | tee -a "$log"
  OREN_QI_STOP_BEFORE_WORLD_LOCK=1 \
  OREN_NATIVE_BUILD_TIMEOUT_SECS="$preworld_build_timeout_secs" \
  OREN_NATIVE_RUN_TIMEOUT_SECS="$preworld_run_timeout_secs" \
  OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS="$preworld_green_cache_run_timeout_secs" \
    ./scripts/triage_stage2_quick_until_world_lock.sh "$preworld_runs" "$compiler" \
      OREN_TRACE_GREEN_RUNQ_GUARD=1 \
      OREN_TRACE_GREEN_ARGS_STAMP=1 \
      "${trace_env_arr[@]}" "$@" \
      >>"$log" 2>&1
fi

if [[ "$stage2_runs" =~ ^[0-9]+$ ]] && [[ "$stage2_runs" -gt 0 ]]; then
  echo "== stage2 native quick integration (runs=$stage2_runs) ==" | tee -a "$log"
  OREN_NATIVE_BUILD_TIMEOUT_SECS="$stage2_build_timeout_secs" \
    ./scripts/triage_native_quick_stage2_flake_debug.sh "$stage2_runs" "$compiler" \
      "${trace_env_arr[@]}" "$@" \
      >>"$log" 2>&1
fi

if [[ "$c_runs" =~ ^[0-9]+$ ]] && [[ "$c_runs" -gt 0 ]]; then
  for fixture in "${fixture_arr[@]}"; do
    if [[ -z "$fixture" ]]; then
      continue
    fi
    echo "== C backend build flake (runs=$c_runs, src=$fixture) ==" | tee -a "$log"
    OREN_TRACE_ARITH_SRC="$fixture" \
      ./scripts/triage_arith_div0_c_build_flake.sh "$c_runs" "$compiler" \
        "${trace_env_arr[@]}" "$@" \
        >>"$log" 2>&1
  done
fi

echo "OK: runtime robustness W5 checks passed (log=$log)" >&2
