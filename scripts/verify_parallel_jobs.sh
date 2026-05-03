#!/usr/bin/env bash

# Shared helpers for verifier scripts that build/run independent backend artifacts.
# Callers define $tmpdir and pass the aggregate verifier log to verify_parallel_wait.

VERIFY_PARALLEL_PIDS=()
VERIFY_PARALLEL_LOGS=()
VERIFY_PARALLEL_NAMES=()

run_logged() {
  local start_s=""
  local end_s=""
  local rc=0
  start_s="$(date +%s)"
  echo "\$ $*"
  set +e
  "$@"
  rc=$?
  set -e
  end_s="$(date +%s)"
  echo "# duration_s=$((end_s - start_s)) rc=$rc"
  return "$rc"
}

run_timeout_logged() {
  local timeout_secs="$1"
  shift
  local start_s=""
  local end_s=""
  local rc=0
  start_s="$(date +%s)"
  echo "\$ $*  # timeout=${timeout_secs}s"
  set +e
  python3 - "$timeout_secs" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_secs = float(sys.argv[1])
cmd = sys.argv[2:]
kwargs = {}
if hasattr(os, "setsid"):
    kwargs["start_new_session"] = True
proc = subprocess.Popen(cmd, **kwargs)
try:
    raise SystemExit(proc.wait(timeout=timeout_secs))
except subprocess.TimeoutExpired:
    if hasattr(os, "killpg"):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    else:
        proc.kill()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        pass
    raise SystemExit(124)
PY
  rc=$?
  set -e
  end_s="$(date +%s)"
  echo "# duration_s=$((end_s - start_s)) rc=$rc"
  return "$rc"
}

verify_native_astbin_seed_path() {
  local platform="$1"
  local log_file="${2:-/dev/stderr}"

  if [[ "${OREN_VERIFY_NATIVE_DIRECT_ASTBIN:-1}" = "0" || "${OREN_VERIFY_NATIVE_DIRECT_ASTBIN:-1}" = "false" ]]; then
    return 1
  fi

  local seed_compiler="${OREN_NATIVE_ASTBIN_SEED_COMPILER:-./oren}"
  local seed_dir="${OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR:-build/cache/native_runtime_astbin_seed}"
  if [[ "$seed_dir" = "0" || "$seed_dir" = "false" ]]; then
    return 1
  fi
  if [[ ! -x ./scripts/build_runtime_astbin_seed.sh || ! -x "$seed_compiler" ]]; then
    return 1
  fi

  ./scripts/build_runtime_astbin_seed.sh --platform "$platform" --compiler "$seed_compiler" >>"$log_file" 2>&1 || return 1

  local os="${platform#*-}"
  local index="${seed_dir}/.runtime_astbin_seed_index_os_${os}.txt"
  if [[ ! -f "$index" ]]; then
    return 1
  fi

  local variant="native_core"
  case "${OREN_NATIVE_RUNTIME_PROFILE:-auto}" in
    full) variant="native_full" ;;
    core|minimal|auto|"") variant="native_core" ;;
    *) variant="native_core" ;;
  esac

  local base
  base="$(
    (grep -E "^${variant}=" "$index" || true) | head -n 1 | sed -E "s/^${variant}=//"
  )"
  if [[ -z "$base" ]]; then
    return 1
  fi

  local path="${seed_dir}/${base}"
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  printf "%s\n" "$path"
}

verify_native_rtobj_seed_prewarm() {
  local platform="$1"
  local log_file="${2:-/dev/stderr}"
  local compiler="${3:-./oren_stage2}"

  if [[ "${OREN_VERIFY_NATIVE_RTOBJ_SEED:-1}" = "0" || "${OREN_VERIFY_NATIVE_RTOBJ_SEED:-1}" = "false" ]]; then
    return 0
  fi

  local seed_compiler="${OREN_NATIVE_RTOBJ_SEED_BUILD_COMPILER:-${OREN_NATIVE_ASTBIN_SEED_COMPILER:-./oren}}"
  if [[ ! -x ./scripts/build_rtobj_seed.sh || ! -x "$compiler" || ! -x "$seed_compiler" ]]; then
    return 1
  fi

  local profile="${OREN_NATIVE_RUNTIME_PROFILE:-core}"
  if [[ "$profile" = "auto" || "$profile" = "" ]]; then
    profile="core"
  fi

  # Default to the source-validated no-op path. Use OREN_VERIFY_NATIVE_FORCE_RTOBJ_SEED=1
  # only when deliberately reproing or measuring cold seed refresh behavior.
  if [[ "${OREN_VERIFY_NATIVE_FORCE_RTOBJ_SEED:-0}" = "0" || "${OREN_VERIFY_NATIVE_FORCE_RTOBJ_SEED:-0}" = "false" ]]; then
    ./scripts/build_rtobj_seed.sh --platform "$platform" --compiler "$compiler" \
      --build-compiler "$seed_compiler" --runtime-profile "$profile" --no-debug >>"$log_file" 2>&1 || return 1
  else
    env OREN_FORCE_RUNTIME_OBJ_SEED=1 ./scripts/build_rtobj_seed.sh --platform "$platform" \
      --compiler "$compiler" --build-compiler "$seed_compiler" --runtime-profile "$profile" \
      --no-debug >>"$log_file" 2>&1 || return 1
  fi

  return 0
}

run_native_build_timeout_logged() {
  local timeout_secs="$1"
  shift
  if [[ -n "${native_astbin_seed:-}" ]]; then
    run_timeout_logged "$timeout_secs" env OREN_NATIVE_RUNTIME_ASTBIN="$native_astbin_seed" "$@"
    return $?
  fi
  run_timeout_logged "$timeout_secs" "$@"
}

verify_parallel_start() {
  local name="$1"
  shift
  local job_log="$tmpdir/${name}.parallel.log"
  VERIFY_PARALLEL_NAMES+=("$name")
  VERIFY_PARALLEL_LOGS+=("$job_log")
  (
    set -euo pipefail
    local_start="$(date +%s)"
    echo "## started_at_s=${local_start}"
    "$@"
    local_end="$(date +%s)"
    echo "## duration_s=$((local_end - local_start))"
  ) >"$job_log" 2>&1 &
  VERIFY_PARALLEL_PIDS+=("$!")
}

verify_parallel_wait() {
  local aggregate_log="$1"
  local rc=0
  local failed=""
  local i=0
  local pid=""
  for pid in "${VERIFY_PARALLEL_PIDS[@]}"; do
    if ! wait "$pid"; then
      rc=1
      failed="${failed} ${VERIFY_PARALLEL_NAMES[$i]}"
    fi
    i=$((i + 1))
  done
  i=0
  for job_log in "${VERIFY_PARALLEL_LOGS[@]}"; do
    {
      echo "## parallel job: ${VERIFY_PARALLEL_NAMES[$i]}"
      cat "$job_log"
    } >>"$aggregate_log"
    i=$((i + 1))
  done
  VERIFY_PARALLEL_PIDS=()
  VERIFY_PARALLEL_LOGS=()
  VERIFY_PARALLEL_NAMES=()
  if [ "$rc" -ne 0 ]; then
    echo "parallel verifier jobs failed:${failed}" >>"$aggregate_log"
    return "$rc"
  fi
}
