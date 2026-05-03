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
