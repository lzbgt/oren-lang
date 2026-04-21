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

run_with_timeout() {
  local secs="$1"
  shift
  local had_errexit=0
  case "$-" in
    *e*) had_errexit=1 ;;
  esac
  set +e
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  local killer=$!
  wait "$pid"
  local rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  fi
  return "$rc"
}

base_prewarm="${OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM:-1}"
base_prewarm_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS:-360}"
base_prewarm_build_compiler="${OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER:-./oren}"
if [[ ! -x "$base_prewarm_build_compiler" ]]; then
  base_prewarm_build_compiler="$compiler"
fi

base_runs="${OREN_RUNTIME_ROBUSTNESS_BASE_RUNS:-1}"
local_ptr_runs="${OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS:-1}"
preworld_runs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS:-1}"
world_lock_runs="${OREN_RUNTIME_ROBUSTNESS_WORLD_LOCK_RUNS:-1}"
stage2_runs="${OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS:-1}"
c_runs="${OREN_RUNTIME_ROBUSTNESS_C_RUNS:-$runs}"
fixtures="${OREN_RUNTIME_ROBUSTNESS_C_FIXTURES:-tests/native/fixtures/arith_div0.oren,tests/native/fixtures/arith_div_overflow.oren,tests/native/fixtures/index_set_negative.oren}"
base_build_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS:-720}"
preworld_build_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS:-240}"
preworld_run_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS:-30}"
preworld_green_cache_run_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS:-30}"
world_lock_timeout_secs="${OREN_RUNTIME_ROBUSTNESS_WORLD_LOCK_TIMEOUT_SECS:-120}"
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
  echo "world_lock_runs=$world_lock_runs"
  echo "stage2_runs=$stage2_runs"
  echo "c_runs=$c_runs"
  echo "compiler=$compiler"
  echo "cwd=$(pwd)"
  echo "uname=$uname_out"
  echo "git_rev=$git_rev"
  echo "fixtures=$fixtures"
  echo "base_prewarm=$base_prewarm"
  echo "base_prewarm_timeout_secs=$base_prewarm_timeout_secs"
  echo "base_prewarm_build_compiler=$base_prewarm_build_compiler"
  echo "base_build_timeout_secs=$base_build_timeout_secs"
  echo "preworld_build_timeout_secs=$preworld_build_timeout_secs"
  echo "preworld_run_timeout_secs=$preworld_run_timeout_secs"
  echo "preworld_green_cache_run_timeout_secs=$preworld_green_cache_run_timeout_secs"
  echo "world_lock_timeout_secs=$world_lock_timeout_secs"
  echo "stage2_build_timeout_secs=$stage2_build_timeout_secs"
  echo "trace_env=$trace_env"
} >"$log"

IFS=',' read -r -a fixture_arr <<< "$fixtures"

if [[ "$base_runs" =~ ^[0-9]+$ ]] && [[ "$base_runs" -gt 0 ]]; then
  if [[ "$base_prewarm" != "0" && "$base_prewarm" != "false" ]]; then
    base_prewarm_log="build/logs/runtime_robustness_base_prewarm_${ts}.log"
    {
      echo "ts=$ts"
      echo "compiler=$compiler"
      echo "build_compiler=$base_prewarm_build_compiler"
      echo "timeout_secs=$base_prewarm_timeout_secs"
      echo "cwd=$(pwd)"
      echo "git_rev=$git_rev"
    } >"$base_prewarm_log"
    echo "== stage1/base runtime seed prewarm ==" | tee -a "$log"
    if ! run_with_timeout "$base_prewarm_timeout_secs" \
      ./scripts/build_runtime_astbin_seed.sh --compiler "$base_prewarm_build_compiler" \
      >>"$base_prewarm_log" 2>&1; then
      echo "ERROR: stage1/base runtime astbin seed prewarm failed (log=$base_prewarm_log)" | tee -a "$log"
      tail -n 120 "$base_prewarm_log" | tee -a "$log"
      exit 1
    fi
    if ! run_with_timeout "$base_prewarm_timeout_secs" \
      ./scripts/build_rtobj_seed.sh --compiler "$compiler" \
      --build-compiler "$base_prewarm_build_compiler" --debug \
      >>"$base_prewarm_log" 2>&1; then
      echo "ERROR: stage1/base runtime obj seed prewarm failed (log=$base_prewarm_log)" | tee -a "$log"
      tail -n 120 "$base_prewarm_log" | tee -a "$log"
      exit 1
    fi
    echo "OK: stage1/base runtime seed prewarm complete (log=$base_prewarm_log)" | tee -a "$log"
  fi
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

if [[ "$world_lock_runs" =~ ^[0-9]+$ ]] && [[ "$world_lock_runs" -gt 0 ]]; then
  echo "== direct world-lock smoke with entry/list tracing (runs=$world_lock_runs) ==" | tee -a "$log"
  OREN_WORLD_LOCK_SMOKE_TIMEOUT_SECS="$world_lock_timeout_secs" \
    ./scripts/triage_green_two_workers_world_lock_smoke.sh "$world_lock_runs" "$compiler" \
      OREN_GREEN_POLL_CACHE=1 \
      OREN_TRACE_GREEN_RUNQ_GUARD=1 \
      OREN_TRACE_GREEN_ARGS_STAMP=1 \
      OREN_TRACE_GREEN_ENTRY_ARGS=1 \
      OREN_QI_TRACE_GREEN_LIST=1 \
      OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1 \
      OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50 \
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

echo "== alloc_churn tracked-header reuse smoke ==" | tee -a "$log"
./scripts/verify_alloc_churn_tracking_smoke.sh "$compiler" >>"$log" 2>&1

echo "== green join-waiter split guard ==" | tee -a "$log"
./scripts/verify_native_quick_green_join_waiters_modes.sh 2 "$compiler" >>"$log" 2>&1

echo "OK: runtime robustness W5 checks passed (log=$log)" >&2
