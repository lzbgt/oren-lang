#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren}"
test_src="${OREN_QI_SRC:-tests/native/test_quick_integration_native.oren}"
test_label="${OREN_QI_LABEL:-native_quick_integration}"

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
python3_bin="$(command -v python3 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=10
run_timeout_secs=5
skip_base_run="${OREN_QI_SKIP_BASE_RUN:-0}"
skip_green_cache="${OREN_QI_SKIP_GREEN_CACHE:-0}"
stop_after_base="${OREN_QI_STOP_AFTER_BASE:-0}"
stop_after_green_cache="${OREN_QI_STOP_AFTER_GREEN_CACHE:-0}"
only_green_cache="${OREN_QI_ONLY_GREEN_CACHE:-0}"
green_cache_first="${OREN_QI_GREEN_CACHE_FIRST:-0}"
green_cache_runs="${OREN_QI_GREEN_CACHE_RUNS:-1}"
green_cache_retries="${OREN_QI_GREEN_CACHE_RETRIES:-1}"
followon_smoke_retries="${OREN_QI_FOLLOWON_SMOKE_RETRIES:-1}"
fail_on_retry="${OREN_QI_FAIL_ON_RETRY:-0}"

retry_base_count=0
retry_green_cache_count=0
retry_followon_count=0
retry_total_count=0

if [[ "$only_green_cache" == "1" ]]; then
  skip_base_run=1
  stop_after_base=0
  stop_after_green_cache=1
  skip_green_cache=0
fi
if ! [[ "$green_cache_runs" =~ ^[0-9]+$ ]]; then
  echo "OREN_QI_GREEN_CACHE_RUNS must be a positive integer" >&2
  exit 2
fi
if [[ "$green_cache_runs" -le 0 ]]; then
  echo "OREN_QI_GREEN_CACHE_RUNS must be >= 1" >&2
  exit 2
fi
if ! [[ "$followon_smoke_retries" =~ ^[0-9]+$ ]]; then
  echo "OREN_QI_FOLLOWON_SMOKE_RETRIES must be a non-negative integer" >&2
  exit 2
fi
if [[ -n "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS}"
fi
if [[ -n "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  run_timeout_secs="${OREN_NATIVE_RUN_TIMEOUT_SECS}"
fi

is_timeout_rc() {
  local rc="${1:-0}"
  [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]
}

record_retry() {
  local bucket="${1:-}"
  case "$bucket" in
    base) retry_base_count=$((retry_base_count + 1)) ;;
    green_cache) retry_green_cache_count=$((retry_green_cache_count + 1)) ;;
    followon) retry_followon_count=$((retry_followon_count + 1)) ;;
  esac
  retry_total_count=$((retry_total_count + 1))
}

emit_retry_summary() {
  echo "retry_base_count=$retry_base_count" >>"$log"
  echo "retry_green_cache_count=$retry_green_cache_count" >>"$log"
  echo "retry_followon_count=$retry_followon_count" >>"$log"
  echo "retry_total_count=$retry_total_count" >>"$log"
}

build_step_checked() {
  local label="$1"
  local step_log="$2"
  shift 2

  set +e
  "$@" >"$step_log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi

  echo "ERROR: ${label} build failed (rc=$rc)" >&2
  if is_timeout_rc "$rc"; then
    echo "WARN: ${label} build timed out/terminated" >&2
  fi
  tail -n 80 "$step_log" >&2 2>/dev/null || true
  exit "$rc"
}

run_step_checked() {
  local label="$1"
  local step_log="$2"
  shift 2

  local attempt=0
  while true; do
    set +e
    "$@" >>"$step_log" 2>&1
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi

    echo "run_rc=$rc" >>"$step_log"
    if ! is_timeout_rc "$rc" || [[ "$attempt" -ge "$followon_smoke_retries" ]]; then
      echo "ERROR: ${label} failed (rc=$rc)" >&2
      tail -n 80 "$step_log" >&2 2>/dev/null || true
      exit "$rc"
    fi

    attempt=$((attempt + 1))
    record_retry followon
    echo "WARN: ${label} timeout-like rc=${rc}; retry ${attempt}/${followon_smoke_retries}" >>"$step_log"
  done
}

expect_compile_failure_step() {
  local label="$1"
  local step_log="$2"
  shift 2

  set +e
  "$@" >"$step_log" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: ${label} expected failure but build succeeded" >&2
    tail -n 80 "$step_log" >&2 2>/dev/null || true
    exit 1
  fi

  echo "ok: ${label}" >>"$step_log"
}

run_with_timeout() {
  local secs="$1"
  shift
  # macOS robustness:
  # GNU coreutils `timeout` has been observed to segfault on some self-hosted Oren
  # native binaries on Darwin. Prefer a tiny bash-native watchdog there.
  if [[ "${uname_s:-}" == "Darwin" ]]; then
    if [[ -z "$secs" || "$secs" == "0" ]]; then
      "$@"
      return $?
    fi

    if [[ -n "$python3_bin" ]]; then
      "$python3_bin" - "$secs" "$timeout_kill_secs" "$@" <<'PY'
import subprocess
import sys

secs = float(sys.argv[1])
kill_secs = float(sys.argv[2])
cmd = sys.argv[3:]

def norm_rc(rc):
    if rc < 0:
        return 128 + (-rc)
    return rc

p = subprocess.Popen(cmd)
try:
    rc = p.wait(timeout=secs)
    raise SystemExit(norm_rc(rc))
except subprocess.TimeoutExpired:
    try:
        p.terminate()
    except ProcessLookupError:
        raise SystemExit(143)
    try:
        rc = p.wait(timeout=kill_secs)
        raise SystemExit(norm_rc(rc))
    except subprocess.TimeoutExpired:
        try:
            p.kill()
        except ProcessLookupError:
            raise SystemExit(143)
        rc = p.wait()
        raise SystemExit(norm_rc(rc))
PY
      return $?
    fi

    # Best-effort watchdog: run command in background, kill if it exceeds the timeout.
    # Keep it simple: Tier‑1 smokes here do not spawn child processes that need group-kill.
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
  local retry_bucket="followon"
  local secs="$1"
  if ! [[ "$secs" =~ ^[0-9]+$ ]]; then
    retry_bucket="$1"
    secs="$2"
    shift
  fi
  shift
  run_with_timeout "$secs" "$@"
  local rc=$?
  # Common timeout exit codes:
  # - GNU timeout: 124
  # - SIGKILL: 137
  # - SIGTERM: 143
  if [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]; then
    local secs2=$((secs * 2))
    record_retry "$retry_bucket"
    echo "WARN: timeout (rc=$rc). Retrying with ${secs2}s." >&2
    run_with_timeout "$secs2" "$@"
    return $?
  fi
  return "$rc"
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
  # macOS: under full-suite load, the native quick-integration base run can
  # now legitimately exceed the older 120s watchdog on this host. A fresh
  # 2026-04-09 rerun false-reded at 120s (and again on the built-in 240s
  # retry) while the same fixture completed cleanly with an explicit 360s
  # base-run budget. Keep that wider default so healthy verification runs do
  # not fail before the existing green-cache retry logic even starts.
  run_timeout_secs=360
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  # macOS: under full-suite load, self-hosted native quick builds can transiently exceed
  # the older 20s watchdog even when the resulting binary is healthy. Keep more headroom
  # so verification fails on real hangs, not on scheduler noise.
  build_timeout_secs=30
fi

arch_key=""
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"

mkdir -p build/tmp build/logs

compiler_base="$(basename "$compiler")"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
  # First-run native builds can be slower on Windows due to cold runtime caches.
  # Keep a hang guard but allow more headroom by default on Windows hosts.
  if [[ -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
    build_timeout_secs=30
  fi
  if [[ -z "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
    run_timeout_secs=10
  fi
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  if [[ "$compiler_base" == *stage2* ]]; then
    # Stage2 used to need a separate bump from the older smaller watchdogs.
    # The current shared macOS base-run default is already 360s, which is
    # wider than the previously proven stage2 budget, so just keep the floor.
    if [[ "$run_timeout_secs" -lt 360 ]]; then
      run_timeout_secs=360
    fi
  fi
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  if [[ "$compiler_base" == *stage2* ]]; then
    # Direct standalone `./oren_stage2` quick-integration rebuilds on this host can still exceed
    # the older 35s watchdog even with an rtobj hit. After the 2026-03-28 fast-loop matcher widen,
    # a measured healthy debug rebuild was already ~171s deep before finishing local BL resolve and
    # false-reded at the prior 180s guard, so keep a modestly wider stage2 standalone budget here.
    build_timeout_secs=240
  fi
fi
out="build/tmp/${compiler_base}_${test_label}${exe_ext}"
log="build/logs/${compiler_base}_${test_label}.log"
phases_log="${OREN_TRACE_BUILD_PHASES_PATH:-${log%.log}.phases.log}"
if [[ "$phases_log" == "0" ]]; then
  phases_log=""
fi
green_cache_run_timeout_secs="$run_timeout_secs"
if [[ -n "${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS:-}" ]]; then
  green_cache_run_timeout_secs="${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS}"
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS:-}" ]]; then
  # macOS: under full-suite load, the OREN_GREEN_POLL_CACHE rerun can exceed the
  # stage1 base-run watchdog even when the binary exits cleanly. A 240s budget
  # still false-red on this host after the rerun had already emitted its last
  # visible debug lines, while a direct stage1 rerun with 360s completed cleanly.
  # Self-hosted stage2 still false-reds at 360s and only clears on the built-in
  # 720s retry, so keep separate proven defaults for stage1 vs stage2 here.
  if [[ "$compiler_base" == *stage2* ]]; then
    if [[ "$green_cache_run_timeout_secs" -lt 720 ]]; then
      green_cache_run_timeout_secs=720
    fi
  else
    if [[ "$green_cache_run_timeout_secs" -lt 360 ]]; then
      green_cache_run_timeout_secs=360
    fi
  fi
fi

echo "== native quick integration =="
echo "compiler=$compiler"
echo "platform=$platform"
echo "label=$test_label"
echo "src=$test_src"
echo "out=$out"
echo "log=$log"
if [[ -n "$phases_log" ]]; then
  echo "phases_log=$phases_log"
fi
echo "build_timeout_secs=$build_timeout_secs"
echo "run_timeout_secs=$run_timeout_secs"
echo "green_cache_run_timeout_secs=$green_cache_run_timeout_secs"
echo "followon_smoke_retries=$followon_smoke_retries"
echo "fail_on_retry=$fail_on_retry"
echo "stop_after_base=$stop_after_base"

rm -f "$log" "$out" 2>/dev/null || true
if [[ -n "$phases_log" ]]; then
  rm -f "$phases_log" 2>/dev/null || true
fi
{
  echo "== native quick integration =="
  echo "compiler=$compiler"
  echo "platform=$platform"
  echo "label=$test_label"
  echo "src=$test_src"
  echo "out=$out"
  if [[ -n "$phases_log" ]]; then
    echo "phases_log=$phases_log"
  fi
  echo "build_timeout_secs=$build_timeout_secs"
  echo "run_timeout_secs=$run_timeout_secs"
  echo "green_cache_run_timeout_secs=$green_cache_run_timeout_secs"
  echo "followon_smoke_retries=$followon_smoke_retries"
  echo "fail_on_retry=$fail_on_retry"
  echo "stop_after_base=$stop_after_base"
} >>"$log"

set +e
if [[ -n "$phases_log" ]]; then
  run_with_timeout "$build_timeout_secs" env "OREN_TRACE_BUILD_PHASES_PATH=$phases_log" \
    "$compiler" build "$test_src" --backend native --platform "$platform" --debug -o "$out" >>"$log" 2>&1
else
  run_with_timeout "$build_timeout_secs" "$compiler" build "$test_src" \
    --backend native --platform "$platform" --debug -o "$out" >>"$log" 2>&1
fi
build_rc=$?
set -e
if [[ "$build_rc" -ne 0 ]]; then
  if [[ "$build_rc" -eq 124 || "$build_rc" -eq 137 || "$build_rc" -eq 143 ]]; then
    echo "ERROR: quick integration build timed out or was terminated (rc=$build_rc, build_timeout_secs=$build_timeout_secs)" >>"$log"
  else
    echo "ERROR: quick integration build failed (rc=$build_rc)" >>"$log"
  fi
  if [[ -n "$phases_log" && -f "$phases_log" ]]; then
    {
      echo "== build phase log =="
      tail -n 20 "$phases_log"
    } >>"$log"
  fi
  tail -n 20 "$log"
  exit "$build_rc"
fi

run_green_cache() {
  if [[ "$skip_green_cache" == "1" ]]; then
    echo "SKIP: green cache run disabled (OREN_QI_SKIP_GREEN_CACHE=1)" >>"$log"
    return 0
  fi
  echo "== native quick integration (OREN_GREEN_POLL_CACHE=1) ==" >>"$log"
  echo "green_cache_run_timeout_secs=$green_cache_run_timeout_secs" >>"$log"
  echo "green_cache_runs=$green_cache_runs" >>"$log"
  echo "green_cache_retries=$green_cache_retries" >>"$log"
  local i
  for ((i=1; i<=green_cache_runs; i++)); do
    if [[ "$green_cache_runs" -gt 1 ]]; then
      echo "== green cache run ${i}/${green_cache_runs} ==" >>"$log"
    fi
    local attempt=0
    while true; do
      set +e
      OREN_GREEN_POLL_CACHE=1 run_with_timeout_retry green_cache "$green_cache_run_timeout_secs" "$out" >>"$log" 2>&1
      local rc=$?
      set -e
      if [[ "$rc" -eq 0 ]]; then
        break
      fi
      if [[ "$attempt" -ge "$green_cache_retries" ]]; then
        return "$rc"
      fi
      attempt=$((attempt + 1))
      record_retry green_cache
      echo "WARN: green cache run failed (rc=${rc}); retry ${attempt}/${green_cache_retries}" >>"$log"
    done
  done
}

run_base() {
  if [[ "$skip_base_run" == "1" ]]; then
    echo "SKIP: base run disabled (OREN_QI_SKIP_BASE_RUN=1)" >>"$log"
    return 0
  fi
  set +e
  run_with_timeout_retry base "$run_timeout_secs" "$out" >>"$log" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

phase_rc=0
if [[ "$green_cache_first" == "1" ]]; then
  set +e
  run_green_cache
  phase_rc=$?
  set -e
  if [[ "$phase_rc" -eq 0 && "$stop_after_green_cache" != "1" ]]; then
    set +e
    run_base
    phase_rc=$?
    set -e
  fi
else
  set +e
  run_base
  phase_rc=$?
  set -e
  if [[ "$phase_rc" -eq 0 ]]; then
    echo "native quick integration base phase OK" >>"$log"
  fi
  if [[ "$phase_rc" -eq 0 && "$stop_after_base" == "1" ]]; then
    emit_retry_summary
    if [[ "$fail_on_retry" == "1" && "$retry_total_count" -gt 0 ]]; then
      echo "FAIL: retries observed with OREN_QI_FAIL_ON_RETRY=1" >>"$log"
      tail -n 8 "$log"
      exit 86
    fi
    echo "skip_reason=OREN_QI_STOP_AFTER_BASE=1" >>"$log"
    tail -n 8 "$log"
    exit 0
  fi
  if [[ "$phase_rc" -eq 0 ]]; then
    set +e
    run_green_cache
    phase_rc=$?
    set -e
  fi
fi

tail -n 5 "$log"

if [[ "$phase_rc" -ne 0 ]]; then
  emit_retry_summary
  exit "$phase_rc"
fi
if [[ "$stop_after_green_cache" == "1" ]]; then
  emit_retry_summary
  if [[ "$fail_on_retry" == "1" && "$retry_total_count" -gt 0 ]]; then
    echo "FAIL: retries observed with OREN_QI_FAIL_ON_RETRY=1" >>"$log"
    tail -n 8 "$log"
    exit 86
  fi
  exit 0
fi

if [[ "${OREN_QI_SKIP_TEST_RUNNER:-0}" != "1" ]]; then
  echo "== test runner smoke ==" >>"$log"
  tr_src="tests/fixtures/test_runner_smoke.oren"
  tr_log="build/logs/${compiler_base}_test_runner_smoke.log"
  rm -f "$tr_log" 2>/dev/null || true
  build_step_checked "test runner smoke" "$tr_log" \
    run_with_timeout "$build_timeout_secs" "$compiler" test "$tr_src" \
    --backend native --platform "$platform" --debug
  echo "ok: test runner smoke" >>"$tr_log"
  tail -n 3 "$tr_log" >>"$log"
fi

if [[ "${OREN_QI_SKIP_SPREAD_SMOKE:-0}" != "1" ]]; then
  echo "== spread/varargs smoke ==" >>"$log"
  sp_src="tests/fixtures/tier1_native_spread_smoke_main.oren"
  sp_out="build/tmp/${compiler_base}_spread_smoke${exe_ext}"
  sp_log="build/logs/${compiler_base}_spread_smoke.log"
  rm -f "$sp_out" "$sp_log" 2>/dev/null || true
  build_step_checked "spread/varargs smoke" "$sp_log" \
    run_with_timeout "$build_timeout_secs" "$compiler" build "$sp_src" \
    --backend native --platform "$platform" --debug -o "$sp_out"
  run_step_checked "spread/varargs smoke" "$sp_log" \
    run_with_timeout_retry "$run_timeout_secs" "$sp_out"
  echo "ok: spread/varargs smoke" >>"$sp_log"
  tail -n 3 "$sp_log" >>"$log"
fi

if [[ "${OREN_QI_SKIP_RESULT_SMOKE:-0}" != "1" ]]; then
  echo "== result smoke ==" >>"$log"
  rs_src="tests/fixtures/tier1_native_result_smoke_main.oren"
  rs_out="build/tmp/${compiler_base}_result_smoke${exe_ext}"
  rs_log="build/logs/${compiler_base}_result_smoke.log"
  rm -f "$rs_out" "$rs_log" 2>/dev/null || true
  build_step_checked "result smoke" "$rs_log" \
    run_with_timeout "$build_timeout_secs" "$compiler" build "$rs_src" \
    --backend native --platform "$platform" --debug -o "$rs_out"
  run_step_checked "result smoke" "$rs_log" \
    run_with_timeout_retry "$run_timeout_secs" "$rs_out"
  echo "ok: result smoke" >>"$rs_log"
  tail -n 3 "$rs_log" >>"$log"
fi

echo "== ulock timeout portable smoke ==" >>"$log"
ul_src="tests/native/test_ulock_timeout_portable.oren"
ul_out="build/tmp/${compiler_base}_ulock_timeout_portable${exe_ext}"
ul_log="build/logs/${compiler_base}_ulock_timeout_portable.log"
rm -f "$ul_log" "$ul_out" 2>/dev/null || true

build_step_checked "ulock timeout portable smoke" "$ul_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$ul_src" \
  --backend native --platform "$platform" --debug -o "$ul_out"
run_step_checked "ulock timeout portable smoke" "$ul_log" \
  run_with_timeout_retry "$run_timeout_secs" "$ul_out"
echo "ok: ulock timeout portable smoke" >>"$ul_log"
tail -n 3 "$ul_log" >>"$log"

echo "== os thread park/unpark smoke ==" >>"$log"
ot_src="tests/native/test_os_thread_park_unpark_smoke.oren"
ot_out="build/tmp/${compiler_base}_os_thread_park_unpark_smoke${exe_ext}"
ot_log="build/logs/${compiler_base}_os_thread_park_unpark_smoke.log"
rm -f "$ot_log" "$ot_out" 2>/dev/null || true
build_step_checked "os thread park/unpark smoke" "$ot_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$ot_src" \
  --backend native --platform "$platform" --debug -o "$ot_out"
run_step_checked "os thread park/unpark smoke" "$ot_log" \
  run_with_timeout_retry "$run_timeout_secs" "$ot_out"
echo "ok: os thread park/unpark smoke" >>"$ot_log"
tail -n 3 "$ot_log" >>"$log"

echo "== os thread spawn-many smoke ==" >>"$log"
om_src="tests/native/test_os_thread_spawn_many_smoke.oren"
om_out="build/tmp/${compiler_base}_os_thread_spawn_many_smoke${exe_ext}"
om_log="build/logs/${compiler_base}_os_thread_spawn_many_smoke.log"
rm -f "$om_log" "$om_out" 2>/dev/null || true
build_step_checked "os thread spawn-many smoke" "$om_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$om_src" \
  --backend native --platform "$platform" --debug -o "$om_out"
run_step_checked "os thread spawn-many smoke" "$om_log" \
  run_with_timeout_retry "$run_timeout_secs" "$om_out"
echo "ok: os thread spawn-many smoke" >>"$om_log"
tail -n 3 "$om_log" >>"$log"

echo "== gc stw os-thread collect smoke ==" >>"$log"
gc_src="tests/native/test_gc_stw_os_thread_collect.oren"
gc_out="build/tmp/${compiler_base}_gc_stw_os_thread_collect${exe_ext}"
gc_log="build/logs/${compiler_base}_gc_stw_os_thread_collect.log"
rm -f "$gc_log" "$gc_out" 2>/dev/null || true
build_step_checked "gc stw os-thread collect smoke" "$gc_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$gc_src" \
  --backend native --platform "$platform" --debug -o "$gc_out"
run_step_checked "gc stw os-thread collect smoke" "$gc_log" \
  run_with_timeout_retry "$run_timeout_secs" "$gc_out"
echo "ok: gc stw os-thread collect smoke" >>"$gc_log"
tail -n 3 "$gc_log" >>"$log"

echo "== green two workers world-lock smoke ==" >>"$log"
gw_src="tests/native/test_green_two_workers_world_lock_smoke.oren"
gw_out="build/tmp/${compiler_base}_green_two_workers_world_lock_smoke${exe_ext}"
gw_log="build/logs/${compiler_base}_green_two_workers_world_lock_smoke.log"
rm -f "$gw_log" "$gw_out" 2>/dev/null || true
build_step_checked "green two workers world-lock smoke" "$gw_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$gw_src" \
  --backend native --platform "$platform" --debug -o "$gw_out"
run_step_checked "green two workers world-lock smoke" "$gw_log" \
  run_with_timeout_retry "$run_timeout_secs" "$gw_out"
echo "ok: green two workers world-lock smoke" >>"$gw_log"
tail -n 3 "$gw_log" >>"$log"

echo "== green two workers M<P deterministic smoke ==" >>"$log"
md_src="tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren"
md_out="build/tmp/${compiler_base}_green_two_workers_m_less_p_deterministic_smoke${exe_ext}"
md_log="build/logs/${compiler_base}_green_two_workers_m_less_p_deterministic_smoke.log"
rm -f "$md_log" "$md_out" 2>/dev/null || true
build_step_checked "green two workers M<P deterministic smoke" "$md_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$md_src" \
  --backend native --platform "$platform" --debug -o "$md_out"
run_step_checked "green two workers M<P deterministic smoke" "$md_log" \
  run_with_timeout_retry "$run_timeout_secs" "$md_out"
echo "ok: green two workers M<P deterministic smoke" >>"$md_log"
tail -n 3 "$md_log" >>"$log"

echo "== arena auto loop smoke ==" >>"$log"
arena_src="tests/native/test_arena_auto_loop_smoke.oren"
arena_out="build/tmp/${compiler_base}_arena_auto_loop_smoke${exe_ext}"
arena_log="build/logs/${compiler_base}_arena_auto_loop_smoke.log"
rm -f "$arena_log" "$arena_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop smoke" "$arena_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_src" \
  --backend native --platform "$platform" --debug -o "$arena_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop smoke" "$arena_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_out"
if ! grep -q "\\[arena\\]" "$arena_log" 2>/dev/null; then
  echo "ERROR: arena auto loop trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop smoke" >>"$arena_log"
tail -n 3 "$arena_log" >>"$log"

echo "== arena auto loop assign smoke ==" >>"$log"
arena_assign_src="tests/native/test_arena_auto_loop_assign_smoke.oren"
arena_assign_out="build/tmp/${compiler_base}_arena_auto_loop_assign_smoke${exe_ext}"
arena_assign_log="build/logs/${compiler_base}_arena_auto_loop_assign_smoke.log"
rm -f "$arena_assign_log" "$arena_assign_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop assign smoke" "$arena_assign_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_assign_src" \
  --backend native --platform "$platform" --debug -o "$arena_assign_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop assign smoke" "$arena_assign_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_assign_out"
if ! grep -q "\\[arena\\]" "$arena_assign_log" 2>/dev/null; then
  echo "ERROR: arena auto loop assign trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_assign_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop assign smoke" >>"$arena_assign_log"
tail -n 3 "$arena_assign_log" >>"$log"

echo "== arena auto loop list<int> smoke ==" >>"$log"
arena_int_src="tests/native/test_arena_auto_loop_list_int_smoke.oren"
arena_int_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_smoke${exe_ext}"
arena_int_log="build/logs/${compiler_base}_arena_auto_loop_list_int_smoke.log"
rm -f "$arena_int_log" "$arena_int_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop list<int> smoke" "$arena_int_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop list<int> smoke" "$arena_int_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_int_out"
if ! grep -q "\\[arena\\]" "$arena_int_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_int_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop list<int> smoke" >>"$arena_int_log"
tail -n 3 "$arena_int_log" >>"$log"

echo "== arena auto loop list<int> assign smoke ==" >>"$log"
arena_int_assign_src="tests/native/test_arena_auto_loop_list_int_assign_smoke.oren"
arena_int_assign_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_assign_smoke${exe_ext}"
arena_int_assign_log="build/logs/${compiler_base}_arena_auto_loop_list_int_assign_smoke.log"
rm -f "$arena_int_assign_log" "$arena_int_assign_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop list<int> assign smoke" "$arena_int_assign_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_assign_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_assign_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop list<int> assign smoke" "$arena_int_assign_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_int_assign_out"
if ! grep -q "\\[arena\\]" "$arena_int_assign_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> assign trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_int_assign_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop list<int> assign smoke" >>"$arena_int_assign_log"
tail -n 3 "$arena_int_assign_log" >>"$log"

echo "== arena auto loop conditional-assign skip smoke ==" >>"$log"
arena_skip_src="tests/native/test_arena_auto_loop_conditional_assign_skip_smoke.oren"
arena_skip_out="build/tmp/${compiler_base}_arena_auto_loop_conditional_assign_skip_smoke${exe_ext}"
arena_skip_log="build/logs/${compiler_base}_arena_auto_loop_conditional_assign_skip_smoke.log"
rm -f "$arena_skip_log" "$arena_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop conditional-assign skip smoke" "$arena_skip_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_skip_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop conditional-assign skip smoke" "$arena_skip_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_skip_out"
if grep -q "\\[arena\\]" "$arena_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop conditional-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_skip_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop conditional-assign skip smoke" >>"$arena_skip_log"
tail -n 3 "$arena_skip_log" >>"$log"

echo "== arena auto loop list<int> conditional-assign skip smoke ==" >>"$log"
arena_int_skip_src="tests/native/test_arena_auto_loop_list_int_conditional_assign_skip_smoke.oren"
arena_int_skip_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_conditional_assign_skip_smoke${exe_ext}"
arena_int_skip_log="build/logs/${compiler_base}_arena_auto_loop_list_int_conditional_assign_skip_smoke.log"
rm -f "$arena_int_skip_log" "$arena_int_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop list<int> conditional-assign skip smoke" "$arena_int_skip_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_skip_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop list<int> conditional-assign skip smoke" "$arena_int_skip_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_int_skip_out"
if grep -q "\\[arena\\]" "$arena_int_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> conditional-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_int_skip_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop list<int> conditional-assign skip smoke" >>"$arena_int_skip_log"
tail -n 3 "$arena_int_skip_log" >>"$log"

echo "== arena auto loop conditional list literal skip smoke ==" >>"$log"
arena_lit_skip_src="tests/native/test_arena_auto_loop_conditional_list_lit_skip_smoke.oren"
arena_lit_skip_out="build/tmp/${compiler_base}_arena_auto_loop_conditional_list_lit_skip_smoke${exe_ext}"
arena_lit_skip_log="build/logs/${compiler_base}_arena_auto_loop_conditional_list_lit_skip_smoke.log"
rm -f "$arena_lit_skip_log" "$arena_lit_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop conditional list literal skip smoke" "$arena_lit_skip_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_lit_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_lit_skip_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop conditional list literal skip smoke" "$arena_lit_skip_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_lit_skip_out"
if grep -q "\\[arena\\]" "$arena_lit_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop conditional list literal should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_lit_skip_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop conditional list literal skip smoke" >>"$arena_lit_skip_log"
tail -n 3 "$arena_lit_skip_log" >>"$log"

echo "== arena auto loop use-before-assign skip smoke ==" >>"$log"
arena_use_before_src="tests/native/test_arena_auto_loop_use_before_assign_skip_smoke.oren"
arena_use_before_out="build/tmp/${compiler_base}_arena_auto_loop_use_before_assign_skip_smoke${exe_ext}"
arena_use_before_log="build/logs/${compiler_base}_arena_auto_loop_use_before_assign_skip_smoke.log"
rm -f "$arena_use_before_log" "$arena_use_before_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop use-before-assign skip smoke" "$arena_use_before_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_use_before_src" \
  --backend native --platform "$platform" --debug -o "$arena_use_before_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop use-before-assign skip smoke" "$arena_use_before_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_use_before_out"
if grep -q "\\[arena\\]" "$arena_use_before_log" 2>/dev/null; then
  echo "ERROR: arena auto loop use-before-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_use_before_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop use-before-assign skip smoke" >>"$arena_use_before_log"
tail -n 3 "$arena_use_before_log" >>"$log"

echo "== arena auto loop list<int> use-before-assign skip smoke ==" >>"$log"
arena_int_use_before_src="tests/native/test_arena_auto_loop_list_int_use_before_assign_skip_smoke.oren"
arena_int_use_before_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_use_before_assign_skip_smoke${exe_ext}"
arena_int_use_before_log="build/logs/${compiler_base}_arena_auto_loop_list_int_use_before_assign_skip_smoke.log"
rm -f "$arena_int_use_before_log" "$arena_int_use_before_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop list<int> use-before-assign skip smoke" "$arena_int_use_before_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_use_before_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_use_before_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop list<int> use-before-assign skip smoke" "$arena_int_use_before_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_int_use_before_out"
if grep -q "\\[arena\\]" "$arena_int_use_before_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> use-before-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_int_use_before_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop list<int> use-before-assign skip smoke" >>"$arena_int_use_before_log"
tail -n 3 "$arena_int_use_before_log" >>"$log"

echo "== arena auto loop empty list literal smoke ==" >>"$log"
arena_lit_src="tests/native/test_arena_auto_loop_empty_list_smoke.oren"
arena_lit_out="build/tmp/${compiler_base}_arena_auto_loop_empty_list_smoke${exe_ext}"
arena_lit_log="build/logs/${compiler_base}_arena_auto_loop_empty_list_smoke.log"
rm -f "$arena_lit_log" "$arena_lit_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop empty list literal smoke" "$arena_lit_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_lit_src" \
  --backend native --platform "$platform" --debug -o "$arena_lit_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop empty list literal smoke" "$arena_lit_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_lit_out"
if ! grep -q "\\[arena\\]" "$arena_lit_log" 2>/dev/null; then
  echo "ERROR: arena auto loop empty list trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_lit_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop empty list literal smoke" >>"$arena_lit_log"
tail -n 3 "$arena_lit_log" >>"$log"

echo "== arena auto loop nested continue smoke ==" >>"$log"
arena_nested_src="tests/native/test_arena_auto_loop_nested_continue_smoke.oren"
arena_nested_out="build/tmp/${compiler_base}_arena_auto_loop_nested_continue_smoke${exe_ext}"
arena_nested_log="build/logs/${compiler_base}_arena_auto_loop_nested_continue_smoke.log"
rm -f "$arena_nested_log" "$arena_nested_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop nested continue smoke" "$arena_nested_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_nested_src" \
  --backend native --platform "$platform" --debug -o "$arena_nested_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop nested continue smoke" "$arena_nested_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_nested_out"
if ! grep -q "\\[arena\\]" "$arena_nested_log" 2>/dev/null; then
  echo "ERROR: arena auto loop nested continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_nested_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop nested continue smoke" >>"$arena_nested_log"
tail -n 3 "$arena_nested_log" >>"$log"

echo "== arena auto loop continue smoke ==" >>"$log"
arena_cont_src="tests/native/test_arena_auto_loop_continue_smoke.oren"
arena_cont_out="build/tmp/${compiler_base}_arena_auto_loop_continue_smoke${exe_ext}"
arena_cont_log="build/logs/${compiler_base}_arena_auto_loop_continue_smoke.log"
rm -f "$arena_cont_log" "$arena_cont_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop continue smoke" "$arena_cont_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_cont_src" \
  --backend native --platform "$platform" --debug -o "$arena_cont_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop continue smoke" "$arena_cont_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_cont_out"
if ! grep -q "\\[arena\\]" "$arena_cont_log" 2>/dev/null; then
  echo "ERROR: arena auto loop continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_cont_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop continue smoke" >>"$arena_cont_log"
tail -n 3 "$arena_cont_log" >>"$log"

echo "== arena auto loop break smoke ==" >>"$log"
arena_break_src="tests/native/test_arena_auto_loop_break_smoke.oren"
arena_break_out="build/tmp/${compiler_base}_arena_auto_loop_break_smoke${exe_ext}"
arena_break_log="build/logs/${compiler_base}_arena_auto_loop_break_smoke.log"
rm -f "$arena_break_log" "$arena_break_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop break smoke" "$arena_break_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_break_src" \
  --backend native --platform "$platform" --debug -o "$arena_break_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop break smoke" "$arena_break_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_break_out"
if ! grep -q "\\[arena\\]" "$arena_break_log" 2>/dev/null; then
  echo "ERROR: arena auto loop break trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_break_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop break smoke" >>"$arena_break_log"
tail -n 3 "$arena_break_log" >>"$log"

echo "== arena auto loop return smoke ==" >>"$log"
arena_ret_src="tests/native/test_arena_auto_loop_return_smoke.oren"
arena_ret_out="build/tmp/${compiler_base}_arena_auto_loop_return_smoke${exe_ext}"
arena_ret_log="build/logs/${compiler_base}_arena_auto_loop_return_smoke.log"
rm -f "$arena_ret_log" "$arena_ret_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop return smoke" "$arena_ret_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_ret_src" \
  --backend native --platform "$platform" --debug -o "$arena_ret_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop return smoke" "$arena_ret_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_ret_out"
if ! grep -q "\\[arena\\]" "$arena_ret_log" 2>/dev/null; then
  echo "ERROR: arena auto loop return trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_ret_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop return smoke" >>"$arena_ret_log"
tail -n 3 "$arena_ret_log" >>"$log"

echo "== arena auto loop for-post continue smoke ==" >>"$log"
arena_fpc_src="tests/native/test_arena_auto_loop_for_post_continue_smoke.oren"
arena_fpc_out="build/tmp/${compiler_base}_arena_auto_loop_for_post_continue_smoke${exe_ext}"
arena_fpc_log="build/logs/${compiler_base}_arena_auto_loop_for_post_continue_smoke.log"
rm -f "$arena_fpc_log" "$arena_fpc_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 build_step_checked "arena auto loop for-post continue smoke" "$arena_fpc_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_fpc_src" \
  --backend native --platform "$platform" --debug -o "$arena_fpc_out"
OREN_TRACE_ARENA=1 run_step_checked "arena auto loop for-post continue smoke" "$arena_fpc_log" \
  run_with_timeout_retry "$run_timeout_secs" "$arena_fpc_out"
if ! grep -q "\\[arena\\]" "$arena_fpc_log" 2>/dev/null; then
  echo "ERROR: arena auto loop for-post continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_fpc_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: arena auto loop for-post continue smoke" >>"$arena_fpc_log"
tail -n 3 "$arena_fpc_log" >>"$log"

echo "== loop list reuse escape smoke (opt-in) ==" >>"$log"
reuse_src="tests/native/test_loop_list_reuse_escape_smoke.oren"
reuse_out="build/tmp/${compiler_base}_loop_list_reuse_escape_smoke${exe_ext}"
reuse_log="build/logs/${compiler_base}_loop_list_reuse_escape_smoke.log"
rm -f "$reuse_log" "$reuse_out" 2>/dev/null || true
OREN_OPT_LOOP_LIST_REUSE=1 build_step_checked "loop list reuse escape smoke" "$reuse_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$reuse_src" \
  --backend native --platform "$platform" --debug -o "$reuse_out"
run_step_checked "loop list reuse escape smoke" "$reuse_log" \
  run_with_timeout_retry "$run_timeout_secs" "$reuse_out"
echo "ok: loop list reuse escape smoke" >>"$reuse_log"
tail -n 3 "$reuse_log" >>"$log"

echo "== gc reuse tracking smoke ==" >>"$log"
gc_reuse_src="tests/native/test_gc_reuse_tracking.oren"
gc_reuse_out="build/tmp/${compiler_base}_gc_reuse_tracking_smoke${exe_ext}"
gc_reuse_log="build/logs/${compiler_base}_gc_reuse_tracking_smoke.log"
rm -f "$gc_reuse_log" "$gc_reuse_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=0 build_step_checked "gc reuse tracking smoke" "$gc_reuse_log" \
  run_with_timeout "$build_timeout_secs" "$compiler" build "$gc_reuse_src" \
  --backend native --platform "$platform" --debug -o "$gc_reuse_out"
OREN_GC_REUSE_BLOCKS=1 \
OREN_GC_REUSE_LISTS=1 \
OREN_GC_REUSE_LISTS_UNSAFE=1 \
OREN_TRACE_GC_REUSE_SUMMARY=1 \
run_step_checked "gc reuse tracking smoke" "$gc_reuse_log" \
  run_with_timeout_retry "$run_timeout_secs" "$gc_reuse_out"
if ! grep -q "gc reuse tracking OK" "$gc_reuse_log" 2>/dev/null; then
  echo "ERROR: gc reuse tracking smoke missing success marker" >&2
  tail -n 80 "$gc_reuse_log" >&2 2>/dev/null || true
  exit 1
fi
if ! grep -Eq "\\[gc_reuse_summary\\].*hits=[1-9]" "$gc_reuse_log" 2>/dev/null; then
  echo "ERROR: gc reuse tracking smoke did not observe any reuse hits" >&2
  tail -n 80 "$gc_reuse_log" >&2 2>/dev/null || true
  exit 1
fi
echo "ok: gc reuse tracking smoke" >>"$gc_reuse_log"
tail -n 4 "$gc_reuse_log" >>"$log"

if [[ "$os_key" != "windows" ]]; then
  # Cross-platform CLI robustness smoke:
  # Accept Windows-style `\` separators even on POSIX hosts so scripts/logs are portable.
  #
  # This is compile-only (fast) and intentionally does not run the binary.
  echo "== path separator smoke (backslash input) =="
  bs_src='examples\myapp.oren'
  bs_out="build/tmp/${compiler_base}_backslash_path_smoke"
  bs_log="build/logs/${compiler_base}_backslash_path_smoke.log"
  rm -f "$bs_out" "$bs_log" 2>/dev/null || true
  build_step_checked "path separator smoke (backslash input)" "$bs_log" \
    run_with_timeout "$build_timeout_secs" "$compiler" build "$bs_src" \
    --backend native --platform "$platform" --no-debug -o "$bs_out"
  test -f "$bs_out" || { echo "FAIL: backslash path smoke did not produce output: $bs_out" >&2; tail -n 80 "$bs_log" >&2; exit 1; }
  echo "OK: backslash path smoke"

  # Output-path separator smoke:
  # Ensure `-o` paths that contain backslashes do not create mixed-separator artifacts like:
  #   build/.../native/examples\myapp.exe
  # (a known x64-windows bring-up hazard under remote Win11 shells).
  #
  # We pass a backslash-heavy output path, but validate the normalized on-disk path.
  echo "== path separator smoke (backslash -o output) =="
  bs_out2='build\tmp\'"${compiler_base}"'_backslash_out_smoke'
  bs_out2_norm="${bs_out2//\\//}"
  bs_log2="build/logs/${compiler_base}_backslash_out_smoke.log"
  rm -f "$bs_out2_norm" "$bs_log2" 2>/dev/null || true
  build_step_checked "path separator smoke (backslash -o output)" "$bs_log2" \
    run_with_timeout "$build_timeout_secs" "$compiler" build "$bs_src" \
    --backend native --platform "$platform" --no-debug -o "$bs_out2"
  test -f "$bs_out2_norm" || { echo "FAIL: backslash -o smoke did not produce output: $bs_out2_norm (from -o $bs_out2)" >&2; tail -n 80 "$bs_log2" >&2; exit 1; }
  echo "OK: backslash -o smoke"
fi

echo "== typecheck smoke (numeric vs nil) =="
tc_src="tests/fixtures/typecheck_bad_numeric_nil.oren"
tc_log="build/logs/${compiler_base}_typecheck_smoke.log"
tc_out="build/tmp/${compiler_base}_typecheck_smoke.obc"
rm -f "$tc_log" "$tc_out" 2>/dev/null || true

expect_compile_failure_step "typecheck smoke (numeric vs nil)" "$tc_log" \
  "$compiler" build "$tc_src" --backend bytecode --typecheck -o "$tc_out"
tail -n 5 "$tc_log"

echo "== reserved identifier prefix smoke =="
rp_src="tests/fixtures/reserved_ident_prefix_fail.oren"
rp_log="build/logs/${compiler_base}_reserved_ident_prefix_smoke.log"
rp_out="build/tmp/${compiler_base}_reserved_ident_prefix_smoke.obc"
rm -f "$rp_log" "$rp_out" 2>/dev/null || true

expect_compile_failure_step "reserved identifier prefix smoke" "$rp_log" \
  "$compiler" build "$rp_src" --backend bytecode --strict-ident-prefixes -o "$rp_out"
tail -n 5 "$rp_log"

echo "== nil-compare guard smoke (late scalar use) =="
ng_src="tests/fixtures/nil_guard_bad_late_scalar_nil_compare.oren"
ng_log="build/logs/${compiler_base}_nil_guard_smoke.log"
ng_out="build/tmp/${compiler_base}_nil_guard_smoke.obc"
rm -f "$ng_log" "$ng_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (late scalar use)" "$ng_log" \
  "$compiler" build "$ng_src" --backend bytecode -o "$ng_out"
tail -n 5 "$ng_log"

echo "== nil-compare guard smoke (late scalar use: arithmetic literal) =="
ng1_src="tests/fixtures/nil_guard_bad_late_arith_literal_nil_compare.oren"
ng1_log="build/logs/${compiler_base}_nil_guard_smoke_arith_literal.log"
ng1_out="build/tmp/${compiler_base}_nil_guard_smoke_arith_literal.obc"
rm -f "$ng1_log" "$ng1_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (late scalar use: arithmetic literal)" "$ng1_log" \
  "$compiler" build "$ng1_src" --backend bytecode -o "$ng1_out"
tail -n 5 "$ng1_log"

echo "== nil-compare guard smoke (param late scalar use: arithmetic literal) =="
ngp_src="tests/fixtures/nil_guard_bad_param_arith_literal_nil_compare.oren"
ngp_log="build/logs/${compiler_base}_nil_guard_smoke_param_arith_literal.log"
ngp_out="build/tmp/${compiler_base}_nil_guard_smoke_param_arith_literal.obc"
rm -f "$ngp_log" "$ngp_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (param late scalar use: arithmetic literal)" "$ngp_log" \
  "$compiler" build "$ngp_src" --backend bytecode -o "$ngp_out"
tail -n 5 "$ngp_log"

echo "== nil-compare guard smoke (late bitwise use) =="
ngb_src="tests/fixtures/nil_guard_bad_late_bitwise_nil_compare.oren"
ngb_log="build/logs/${compiler_base}_nil_guard_smoke_bitwise.log"
ngb_out="build/tmp/${compiler_base}_nil_guard_smoke_bitwise.obc"
rm -f "$ngb_log" "$ngb_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (late bitwise use)" "$ngb_log" \
  "$compiler" build "$ngb_src" --backend bytecode -o "$ngb_out"
tail -n 5 "$ngb_log"

echo "== nil-compare guard smoke (late scalar use, top-level) =="
ng2_src="tests/fixtures/nil_guard_bad_late_scalar_nil_compare_top_level.oren"
ng2_log="build/logs/${compiler_base}_nil_guard_smoke_top_level.log"
ng2_out="build/tmp/${compiler_base}_nil_guard_smoke_top_level.obc"
rm -f "$ng2_log" "$ng2_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (late scalar use, top-level)" "$ng2_log" \
  "$compiler" build "$ng2_src" --backend bytecode -o "$ng2_out"
tail -n 5 "$ng2_log"

echo "== nil-compare guard smoke (annotated call result) =="
ng3_src="tests/fixtures/nil_guard_bad_annotated_call_nil_compare.oren"
ng3_log="build/logs/${compiler_base}_nil_guard_smoke_annotated_call.log"
ng3_out="build/tmp/${compiler_base}_nil_guard_smoke_annotated_call.obc"
rm -f "$ng3_log" "$ng3_out" 2>/dev/null || true

expect_compile_failure_step "nil-compare guard smoke (annotated call result)" "$ng3_log" \
  "$compiler" build "$ng3_src" --backend bytecode -o "$ng3_out"
tail -n 5 "$ng3_log"

echo "== typecheck smoke (bool vs nil) =="
tc2_src="tests/fixtures/typecheck_bad_bool_nil.oren"
tc2_log="build/logs/${compiler_base}_typecheck_smoke_bool_nil.log"
tc2_out="build/tmp/${compiler_base}_typecheck_smoke_bool_nil.obc"
rm -f "$tc2_log" "$tc2_out" 2>/dev/null || true

expect_compile_failure_step "typecheck smoke (bool vs nil)" "$tc2_log" \
  "$compiler" build "$tc2_src" --backend bytecode --typecheck -o "$tc2_out"
tail -n 5 "$tc2_log"

echo "== parser smoke (reserved struct field __oren_type) =="
rs_src="tests/fixtures/typecheck_bad_reserved_struct_field_oren_type.oren"
rs_log="build/logs/${compiler_base}_parser_smoke_reserved_oren_type_field.log"
rs_out="build/tmp/${compiler_base}_parser_smoke_reserved_oren_type_field.obc"
rm -f "$rs_log" "$rs_out" 2>/dev/null || true

expect_compile_failure_step "parser smoke (reserved struct field __oren_type)" "$rs_log" \
  "$compiler" build "$rs_src" --backend bytecode --typecheck -o "$rs_out"
tail -n 5 "$rs_log"

echo "native quick integration follow-on OK"
echo "native quick integration follow-on OK" >>"$log"
emit_retry_summary
if [[ "$fail_on_retry" == "1" && "$retry_total_count" -gt 0 ]]; then
  echo "FAIL: retries observed with OREN_QI_FAIL_ON_RETRY=1" >>"$log"
  tail -n 8 "$log"
  exit 86
fi
