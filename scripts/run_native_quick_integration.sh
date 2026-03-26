#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren}"
test_src="${OREN_QI_SRC:-tests/native/test_quick_integration_native.oren}"
test_label="${OREN_QI_LABEL:-native_quick_integration}"

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs=10
run_timeout_secs=5
skip_base_run="${OREN_QI_SKIP_BASE_RUN:-0}"
skip_green_cache="${OREN_QI_SKIP_GREEN_CACHE:-0}"
stop_after_green_cache="${OREN_QI_STOP_AFTER_GREEN_CACHE:-0}"
only_green_cache="${OREN_QI_ONLY_GREEN_CACHE:-0}"
green_cache_first="${OREN_QI_GREEN_CACHE_FIRST:-0}"
green_cache_runs="${OREN_QI_GREEN_CACHE_RUNS:-1}"
green_cache_retries="${OREN_QI_GREEN_CACHE_RETRIES:-1}"

if [[ "$only_green_cache" == "1" ]]; then
  skip_base_run=1
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
if [[ -n "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS}"
fi
if [[ -n "${OREN_NATIVE_RUN_TIMEOUT_SECS:-}" ]]; then
  run_timeout_secs="${OREN_NATIVE_RUN_TIMEOUT_SECS}"
fi

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
  local secs="$1"
  shift
  run_with_timeout "$secs" "$@"
  local rc=$?
  # Common timeout exit codes:
  # - GNU timeout: 124
  # - SIGKILL: 137
  # - SIGTERM: 143
  if [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]; then
    local secs2=$((secs * 2))
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
  # Slightly more headroom on macOS to avoid flaky quick-integration timeouts.
  run_timeout_secs=12
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
    run_timeout_secs=15
  fi
fi
if [[ "$os_key" == "macos" && -z "${OREN_NATIVE_BUILD_TIMEOUT_SECS:-}" ]]; then
  if [[ "$compiler_base" == *stage2* ]]; then
    build_timeout_secs=35
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
      OREN_GREEN_POLL_CACHE=1 run_with_timeout_retry "$green_cache_run_timeout_secs" "$out" >>"$log" 2>&1
      local rc=$?
      if [[ "$rc" -eq 0 ]]; then
        break
      fi
      if [[ "$attempt" -ge "$green_cache_retries" ]]; then
        return "$rc"
      fi
      attempt=$((attempt + 1))
      echo "WARN: green cache run failed (rc=${rc}); retry ${attempt}/${green_cache_retries}" >>"$log"
    done
  done
}

run_base() {
  if [[ "$skip_base_run" == "1" ]]; then
    echo "SKIP: base run disabled (OREN_QI_SKIP_BASE_RUN=1)" >>"$log"
    return 0
  fi
  run_with_timeout_retry "$run_timeout_secs" "$out" >>"$log" 2>&1
}

if [[ "$green_cache_first" == "1" ]]; then
  run_green_cache
  if [[ "$stop_after_green_cache" == "1" ]]; then
    exit 0
  fi
  run_base
else
  run_base
  run_green_cache
fi

tail -n 5 "$log"

if [[ "$stop_after_green_cache" == "1" ]]; then
  exit 0
fi

if [[ "${OREN_QI_SKIP_TEST_RUNNER:-0}" != "1" ]]; then
  echo "== test runner smoke ==" >>"$log"
  tr_src="tests/fixtures/test_runner_smoke.oren"
  tr_log="build/logs/${compiler_base}_test_runner_smoke.log"
  rm -f "$tr_log" 2>/dev/null || true
  run_with_timeout "$build_timeout_secs" "$compiler" test "$tr_src" \
    --backend native --platform "$platform" --debug >"$tr_log" 2>&1
  tail -n 3 "$tr_log" >>"$log"
fi

if [[ "${OREN_QI_SKIP_SPREAD_SMOKE:-0}" != "1" ]]; then
  echo "== spread/varargs smoke ==" >>"$log"
  sp_src="tests/fixtures/tier1_native_spread_smoke_main.oren"
  sp_out="build/tmp/${compiler_base}_spread_smoke${exe_ext}"
  sp_log="build/logs/${compiler_base}_spread_smoke.log"
  rm -f "$sp_out" "$sp_log" 2>/dev/null || true
  run_with_timeout "$build_timeout_secs" "$compiler" build "$sp_src" \
    --backend native --platform "$platform" --debug -o "$sp_out" >"$sp_log" 2>&1
  run_with_timeout "$run_timeout_secs" "$sp_out" >>"$sp_log" 2>&1
  tail -n 3 "$sp_log" >>"$log"
fi

if [[ "${OREN_QI_SKIP_RESULT_SMOKE:-0}" != "1" ]]; then
  echo "== result smoke ==" >>"$log"
  rs_src="tests/fixtures/tier1_native_result_smoke_main.oren"
  rs_out="build/tmp/${compiler_base}_result_smoke${exe_ext}"
  rs_log="build/logs/${compiler_base}_result_smoke.log"
  rm -f "$rs_out" "$rs_log" 2>/dev/null || true
  run_with_timeout "$build_timeout_secs" "$compiler" build "$rs_src" \
    --backend native --platform "$platform" --debug -o "$rs_out" >"$rs_log" 2>&1
  run_with_timeout "$run_timeout_secs" "$rs_out" >>"$rs_log" 2>&1
  tail -n 3 "$rs_log" >>"$log"
fi

echo "== ulock timeout portable smoke ==" >>"$log"
ul_src="tests/native/test_ulock_timeout_portable.oren"
ul_out="build/tmp/${compiler_base}_ulock_timeout_portable${exe_ext}"
ul_log="build/logs/${compiler_base}_ulock_timeout_portable.log"
rm -f "$ul_log" "$ul_out" 2>/dev/null || true

run_with_timeout "$build_timeout_secs" "$compiler" build "$ul_src" \
  --backend native --platform "$platform" --debug -o "$ul_out" >"$ul_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$ul_out" >>"$ul_log" 2>&1
tail -n 3 "$ul_log" >>"$log"

echo "== os thread park/unpark smoke ==" >>"$log"
ot_src="tests/native/test_os_thread_park_unpark_smoke.oren"
ot_out="build/tmp/${compiler_base}_os_thread_park_unpark_smoke${exe_ext}"
ot_log="build/logs/${compiler_base}_os_thread_park_unpark_smoke.log"
rm -f "$ot_log" "$ot_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$ot_src" \
  --backend native --platform "$platform" --debug -o "$ot_out" >"$ot_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$ot_out" >>"$ot_log" 2>&1
tail -n 3 "$ot_log" >>"$log"

echo "== os thread spawn-many smoke ==" >>"$log"
om_src="tests/native/test_os_thread_spawn_many_smoke.oren"
om_out="build/tmp/${compiler_base}_os_thread_spawn_many_smoke${exe_ext}"
om_log="build/logs/${compiler_base}_os_thread_spawn_many_smoke.log"
rm -f "$om_log" "$om_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$om_src" \
  --backend native --platform "$platform" --debug -o "$om_out" >"$om_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$om_out" >>"$om_log" 2>&1
tail -n 3 "$om_log" >>"$log"

echo "== gc stw os-thread collect smoke ==" >>"$log"
gc_src="tests/native/test_gc_stw_os_thread_collect.oren"
gc_out="build/tmp/${compiler_base}_gc_stw_os_thread_collect${exe_ext}"
gc_log="build/logs/${compiler_base}_gc_stw_os_thread_collect.log"
rm -f "$gc_log" "$gc_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$gc_src" \
  --backend native --platform "$platform" --debug -o "$gc_out" >"$gc_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$gc_out" >>"$gc_log" 2>&1
tail -n 3 "$gc_log" >>"$log"

echo "== green two workers world-lock smoke ==" >>"$log"
gw_src="tests/native/test_green_two_workers_world_lock_smoke.oren"
gw_out="build/tmp/${compiler_base}_green_two_workers_world_lock_smoke${exe_ext}"
gw_log="build/logs/${compiler_base}_green_two_workers_world_lock_smoke.log"
rm -f "$gw_log" "$gw_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$gw_src" \
  --backend native --platform "$platform" --debug -o "$gw_out" >"$gw_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$gw_out" >>"$gw_log" 2>&1
tail -n 3 "$gw_log" >>"$log"

echo "== green two workers M<P deterministic smoke ==" >>"$log"
md_src="tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren"
md_out="build/tmp/${compiler_base}_green_two_workers_m_less_p_deterministic_smoke${exe_ext}"
md_log="build/logs/${compiler_base}_green_two_workers_m_less_p_deterministic_smoke.log"
rm -f "$md_log" "$md_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$md_src" \
  --backend native --platform "$platform" --debug -o "$md_out" >"$md_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$md_out" >>"$md_log" 2>&1
tail -n 3 "$md_log" >>"$log"

echo "== arena auto loop smoke ==" >>"$log"
arena_src="tests/native/test_arena_auto_loop_smoke.oren"
arena_out="build/tmp/${compiler_base}_arena_auto_loop_smoke${exe_ext}"
arena_log="build/logs/${compiler_base}_arena_auto_loop_smoke.log"
rm -f "$arena_log" "$arena_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_src" \
  --backend native --platform "$platform" --debug -o "$arena_out" >"$arena_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_out" >>"$arena_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_log" 2>/dev/null; then
  echo "ERROR: arena auto loop trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_log" >>"$log"

echo "== arena auto loop assign smoke ==" >>"$log"
arena_assign_src="tests/native/test_arena_auto_loop_assign_smoke.oren"
arena_assign_out="build/tmp/${compiler_base}_arena_auto_loop_assign_smoke${exe_ext}"
arena_assign_log="build/logs/${compiler_base}_arena_auto_loop_assign_smoke.log"
rm -f "$arena_assign_log" "$arena_assign_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_assign_src" \
  --backend native --platform "$platform" --debug -o "$arena_assign_out" >"$arena_assign_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_assign_out" >>"$arena_assign_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_assign_log" 2>/dev/null; then
  echo "ERROR: arena auto loop assign trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_assign_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_assign_log" >>"$log"

echo "== arena auto loop list<int> smoke ==" >>"$log"
arena_int_src="tests/native/test_arena_auto_loop_list_int_smoke.oren"
arena_int_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_smoke${exe_ext}"
arena_int_log="build/logs/${compiler_base}_arena_auto_loop_list_int_smoke.log"
rm -f "$arena_int_log" "$arena_int_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_out" >"$arena_int_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_int_out" >>"$arena_int_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_int_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_int_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_int_log" >>"$log"

echo "== arena auto loop list<int> assign smoke ==" >>"$log"
arena_int_assign_src="tests/native/test_arena_auto_loop_list_int_assign_smoke.oren"
arena_int_assign_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_assign_smoke${exe_ext}"
arena_int_assign_log="build/logs/${compiler_base}_arena_auto_loop_list_int_assign_smoke.log"
rm -f "$arena_int_assign_log" "$arena_int_assign_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_assign_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_assign_out" >"$arena_int_assign_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_int_assign_out" >>"$arena_int_assign_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_int_assign_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> assign trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_int_assign_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_int_assign_log" >>"$log"

echo "== arena auto loop conditional-assign skip smoke ==" >>"$log"
arena_skip_src="tests/native/test_arena_auto_loop_conditional_assign_skip_smoke.oren"
arena_skip_out="build/tmp/${compiler_base}_arena_auto_loop_conditional_assign_skip_smoke${exe_ext}"
arena_skip_log="build/logs/${compiler_base}_arena_auto_loop_conditional_assign_skip_smoke.log"
rm -f "$arena_skip_log" "$arena_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_skip_out" >"$arena_skip_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_skip_out" >>"$arena_skip_log" 2>&1
if grep -q "\\[arena\\]" "$arena_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop conditional-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_skip_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_skip_log" >>"$log"

echo "== arena auto loop list<int> conditional-assign skip smoke ==" >>"$log"
arena_int_skip_src="tests/native/test_arena_auto_loop_list_int_conditional_assign_skip_smoke.oren"
arena_int_skip_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_conditional_assign_skip_smoke${exe_ext}"
arena_int_skip_log="build/logs/${compiler_base}_arena_auto_loop_list_int_conditional_assign_skip_smoke.log"
rm -f "$arena_int_skip_log" "$arena_int_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_skip_out" >"$arena_int_skip_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_int_skip_out" >>"$arena_int_skip_log" 2>&1
if grep -q "\\[arena\\]" "$arena_int_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> conditional-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_int_skip_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_int_skip_log" >>"$log"

echo "== arena auto loop conditional list literal skip smoke ==" >>"$log"
arena_lit_skip_src="tests/native/test_arena_auto_loop_conditional_list_lit_skip_smoke.oren"
arena_lit_skip_out="build/tmp/${compiler_base}_arena_auto_loop_conditional_list_lit_skip_smoke${exe_ext}"
arena_lit_skip_log="build/logs/${compiler_base}_arena_auto_loop_conditional_list_lit_skip_smoke.log"
rm -f "$arena_lit_skip_log" "$arena_lit_skip_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_lit_skip_src" \
  --backend native --platform "$platform" --debug -o "$arena_lit_skip_out" >"$arena_lit_skip_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_lit_skip_out" >>"$arena_lit_skip_log" 2>&1
if grep -q "\\[arena\\]" "$arena_lit_skip_log" 2>/dev/null; then
  echo "ERROR: arena auto loop conditional list literal should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_lit_skip_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_lit_skip_log" >>"$log"

echo "== arena auto loop use-before-assign skip smoke ==" >>"$log"
arena_use_before_src="tests/native/test_arena_auto_loop_use_before_assign_skip_smoke.oren"
arena_use_before_out="build/tmp/${compiler_base}_arena_auto_loop_use_before_assign_skip_smoke${exe_ext}"
arena_use_before_log="build/logs/${compiler_base}_arena_auto_loop_use_before_assign_skip_smoke.log"
rm -f "$arena_use_before_log" "$arena_use_before_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_use_before_src" \
  --backend native --platform "$platform" --debug -o "$arena_use_before_out" >"$arena_use_before_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_use_before_out" >>"$arena_use_before_log" 2>&1
if grep -q "\\[arena\\]" "$arena_use_before_log" 2>/dev/null; then
  echo "ERROR: arena auto loop use-before-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_use_before_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_use_before_log" >>"$log"

echo "== arena auto loop list<int> use-before-assign skip smoke ==" >>"$log"
arena_int_use_before_src="tests/native/test_arena_auto_loop_list_int_use_before_assign_skip_smoke.oren"
arena_int_use_before_out="build/tmp/${compiler_base}_arena_auto_loop_list_int_use_before_assign_skip_smoke${exe_ext}"
arena_int_use_before_log="build/logs/${compiler_base}_arena_auto_loop_list_int_use_before_assign_skip_smoke.log"
rm -f "$arena_int_use_before_log" "$arena_int_use_before_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_int_use_before_src" \
  --backend native --platform "$platform" --debug -o "$arena_int_use_before_out" >"$arena_int_use_before_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_int_use_before_out" >>"$arena_int_use_before_log" 2>&1
if grep -q "\\[arena\\]" "$arena_int_use_before_log" 2>/dev/null; then
  echo "ERROR: arena auto loop list<int> use-before-assign should skip (unexpected [arena] output)" >&2
  tail -n 80 "$arena_int_use_before_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_int_use_before_log" >>"$log"

echo "== arena auto loop empty list literal smoke ==" >>"$log"
arena_lit_src="tests/native/test_arena_auto_loop_empty_list_smoke.oren"
arena_lit_out="build/tmp/${compiler_base}_arena_auto_loop_empty_list_smoke${exe_ext}"
arena_lit_log="build/logs/${compiler_base}_arena_auto_loop_empty_list_smoke.log"
rm -f "$arena_lit_log" "$arena_lit_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_lit_src" \
  --backend native --platform "$platform" --debug -o "$arena_lit_out" >"$arena_lit_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_lit_out" >>"$arena_lit_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_lit_log" 2>/dev/null; then
  echo "ERROR: arena auto loop empty list trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_lit_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_lit_log" >>"$log"

echo "== arena auto loop nested continue smoke ==" >>"$log"
arena_nested_src="tests/native/test_arena_auto_loop_nested_continue_smoke.oren"
arena_nested_out="build/tmp/${compiler_base}_arena_auto_loop_nested_continue_smoke${exe_ext}"
arena_nested_log="build/logs/${compiler_base}_arena_auto_loop_nested_continue_smoke.log"
rm -f "$arena_nested_log" "$arena_nested_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_nested_src" \
  --backend native --platform "$platform" --debug -o "$arena_nested_out" >"$arena_nested_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_nested_out" >>"$arena_nested_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_nested_log" 2>/dev/null; then
  echo "ERROR: arena auto loop nested continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_nested_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_nested_log" >>"$log"

echo "== arena auto loop continue smoke ==" >>"$log"
arena_cont_src="tests/native/test_arena_auto_loop_continue_smoke.oren"
arena_cont_out="build/tmp/${compiler_base}_arena_auto_loop_continue_smoke${exe_ext}"
arena_cont_log="build/logs/${compiler_base}_arena_auto_loop_continue_smoke.log"
rm -f "$arena_cont_log" "$arena_cont_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_cont_src" \
  --backend native --platform "$platform" --debug -o "$arena_cont_out" >"$arena_cont_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_cont_out" >>"$arena_cont_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_cont_log" 2>/dev/null; then
  echo "ERROR: arena auto loop continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_cont_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_cont_log" >>"$log"

echo "== arena auto loop break smoke ==" >>"$log"
arena_break_src="tests/native/test_arena_auto_loop_break_smoke.oren"
arena_break_out="build/tmp/${compiler_base}_arena_auto_loop_break_smoke${exe_ext}"
arena_break_log="build/logs/${compiler_base}_arena_auto_loop_break_smoke.log"
rm -f "$arena_break_log" "$arena_break_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_break_src" \
  --backend native --platform "$platform" --debug -o "$arena_break_out" >"$arena_break_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_break_out" >>"$arena_break_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_break_log" 2>/dev/null; then
  echo "ERROR: arena auto loop break trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_break_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_break_log" >>"$log"

echo "== arena auto loop return smoke ==" >>"$log"
arena_ret_src="tests/native/test_arena_auto_loop_return_smoke.oren"
arena_ret_out="build/tmp/${compiler_base}_arena_auto_loop_return_smoke${exe_ext}"
arena_ret_log="build/logs/${compiler_base}_arena_auto_loop_return_smoke.log"
rm -f "$arena_ret_log" "$arena_ret_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_ret_src" \
  --backend native --platform "$platform" --debug -o "$arena_ret_out" >"$arena_ret_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_ret_out" >>"$arena_ret_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_ret_log" 2>/dev/null; then
  echo "ERROR: arena auto loop return trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_ret_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_ret_log" >>"$log"

echo "== arena auto loop for-post continue smoke ==" >>"$log"
arena_fpc_src="tests/native/test_arena_auto_loop_for_post_continue_smoke.oren"
arena_fpc_out="build/tmp/${compiler_base}_arena_auto_loop_for_post_continue_smoke${exe_ext}"
arena_fpc_log="build/logs/${compiler_base}_arena_auto_loop_for_post_continue_smoke.log"
rm -f "$arena_fpc_log" "$arena_fpc_out" 2>/dev/null || true
OREN_ARENA_AUTO_LOOP=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$arena_fpc_src" \
  --backend native --platform "$platform" --debug -o "$arena_fpc_out" >"$arena_fpc_log" 2>&1
OREN_TRACE_ARENA=1 run_with_timeout_retry "$run_timeout_secs" "$arena_fpc_out" >>"$arena_fpc_log" 2>&1
if ! grep -q "\\[arena\\]" "$arena_fpc_log" 2>/dev/null; then
  echo "ERROR: arena auto loop for-post continue trace missing (expected [arena] output)" >&2
  tail -n 80 "$arena_fpc_log" >&2 2>/dev/null || true
  exit 1
fi
tail -n 3 "$arena_fpc_log" >>"$log"

echo "== loop list reuse escape smoke (opt-in) ==" >>"$log"
reuse_src="tests/native/test_loop_list_reuse_escape_smoke.oren"
reuse_out="build/tmp/${compiler_base}_loop_list_reuse_escape_smoke${exe_ext}"
reuse_log="build/logs/${compiler_base}_loop_list_reuse_escape_smoke.log"
rm -f "$reuse_log" "$reuse_out" 2>/dev/null || true
OREN_OPT_LOOP_LIST_REUSE=1 run_with_timeout "$build_timeout_secs" "$compiler" build "$reuse_src" \
  --backend native --platform "$platform" --debug -o "$reuse_out" >"$reuse_log" 2>&1
run_with_timeout_retry "$run_timeout_secs" "$reuse_out" >>"$reuse_log" 2>&1
tail -n 3 "$reuse_log" >>"$log"

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
  run_with_timeout "$build_timeout_secs" "$compiler" build "$bs_src" \
    --backend native --platform "$platform" --no-debug -o "$bs_out" >"$bs_log" 2>&1
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
  run_with_timeout "$build_timeout_secs" "$compiler" build "$bs_src" \
    --backend native --platform "$platform" --no-debug -o "$bs_out2" >"$bs_log2" 2>&1
  test -f "$bs_out2_norm" || { echo "FAIL: backslash -o smoke did not produce output: $bs_out2_norm (from -o $bs_out2)" >&2; tail -n 80 "$bs_log2" >&2; exit 1; }
  echo "OK: backslash -o smoke"
fi

echo "== typecheck smoke (numeric vs nil) =="
tc_src="tests/fixtures/typecheck_bad_numeric_nil.oren"
tc_log="build/logs/${compiler_base}_typecheck_smoke.log"
tc_out="build/tmp/${compiler_base}_typecheck_smoke.obc"
rm -f "$tc_log" "$tc_out" 2>/dev/null || true

set +e
"$compiler" build "$tc_src" --backend bytecode --typecheck -o "$tc_out" >"$tc_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: typecheck smoke expected failure but build succeeded"
  tail -n 80 "$tc_log"
  exit 1
fi
tail -n 5 "$tc_log"

echo "== reserved identifier prefix smoke =="
rp_src="tests/fixtures/reserved_ident_prefix_fail.oren"
rp_log="build/logs/${compiler_base}_reserved_ident_prefix_smoke.log"
rp_out="build/tmp/${compiler_base}_reserved_ident_prefix_smoke.obc"
rm -f "$rp_log" "$rp_out" 2>/dev/null || true

set +e
"$compiler" build "$rp_src" --backend bytecode --strict-ident-prefixes -o "$rp_out" >"$rp_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: reserved identifier prefix smoke expected failure but build succeeded"
  tail -n 80 "$rp_log"
  exit 1
fi
tail -n 5 "$rp_log"

echo "== nil-compare guard smoke (late scalar use) =="
ng_src="tests/fixtures/nil_guard_bad_late_scalar_nil_compare.oren"
ng_log="build/logs/${compiler_base}_nil_guard_smoke.log"
ng_out="build/tmp/${compiler_base}_nil_guard_smoke.obc"
rm -f "$ng_log" "$ng_out" 2>/dev/null || true

set +e
"$compiler" build "$ng_src" --backend bytecode -o "$ng_out" >"$ng_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke expected failure but build succeeded"
  tail -n 80 "$ng_log"
  exit 1
fi
tail -n 5 "$ng_log"

echo "== nil-compare guard smoke (late scalar use: arithmetic literal) =="
ng1_src="tests/fixtures/nil_guard_bad_late_arith_literal_nil_compare.oren"
ng1_log="build/logs/${compiler_base}_nil_guard_smoke_arith_literal.log"
ng1_out="build/tmp/${compiler_base}_nil_guard_smoke_arith_literal.obc"
rm -f "$ng1_log" "$ng1_out" 2>/dev/null || true

set +e
"$compiler" build "$ng1_src" --backend bytecode -o "$ng1_out" >"$ng1_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke (arith literal) expected failure but build succeeded"
  tail -n 80 "$ng1_log"
  exit 1
fi
tail -n 5 "$ng1_log"

echo "== nil-compare guard smoke (param late scalar use: arithmetic literal) =="
ngp_src="tests/fixtures/nil_guard_bad_param_arith_literal_nil_compare.oren"
ngp_log="build/logs/${compiler_base}_nil_guard_smoke_param_arith_literal.log"
ngp_out="build/tmp/${compiler_base}_nil_guard_smoke_param_arith_literal.obc"
rm -f "$ngp_log" "$ngp_out" 2>/dev/null || true

set +e
"$compiler" build "$ngp_src" --backend bytecode -o "$ngp_out" >"$ngp_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke (param arith literal) expected failure but build succeeded"
  tail -n 80 "$ngp_log"
  exit 1
fi
tail -n 5 "$ngp_log"

echo "== nil-compare guard smoke (late bitwise use) =="
ngb_src="tests/fixtures/nil_guard_bad_late_bitwise_nil_compare.oren"
ngb_log="build/logs/${compiler_base}_nil_guard_smoke_bitwise.log"
ngb_out="build/tmp/${compiler_base}_nil_guard_smoke_bitwise.obc"
rm -f "$ngb_log" "$ngb_out" 2>/dev/null || true

set +e
"$compiler" build "$ngb_src" --backend bytecode -o "$ngb_out" >"$ngb_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke (bitwise) expected failure but build succeeded"
  tail -n 80 "$ngb_log"
  exit 1
fi
tail -n 5 "$ngb_log"

echo "== nil-compare guard smoke (late scalar use, top-level) =="
ng2_src="tests/fixtures/nil_guard_bad_late_scalar_nil_compare_top_level.oren"
ng2_log="build/logs/${compiler_base}_nil_guard_smoke_top_level.log"
ng2_out="build/tmp/${compiler_base}_nil_guard_smoke_top_level.obc"
rm -f "$ng2_log" "$ng2_out" 2>/dev/null || true

set +e
"$compiler" build "$ng2_src" --backend bytecode -o "$ng2_out" >"$ng2_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke (top-level) expected failure but build succeeded"
  tail -n 80 "$ng2_log"
  exit 1
fi
tail -n 5 "$ng2_log"

echo "== nil-compare guard smoke (annotated call result) =="
ng3_src="tests/fixtures/nil_guard_bad_annotated_call_nil_compare.oren"
ng3_log="build/logs/${compiler_base}_nil_guard_smoke_annotated_call.log"
ng3_out="build/tmp/${compiler_base}_nil_guard_smoke_annotated_call.obc"
rm -f "$ng3_log" "$ng3_out" 2>/dev/null || true

set +e
"$compiler" build "$ng3_src" --backend bytecode -o "$ng3_out" >"$ng3_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: nil-compare guard smoke (annotated call) expected failure but build succeeded"
  tail -n 80 "$ng3_log"
  exit 1
fi
tail -n 5 "$ng3_log"

echo "== typecheck smoke (bool vs nil) =="
tc2_src="tests/fixtures/typecheck_bad_bool_nil.oren"
tc2_log="build/logs/${compiler_base}_typecheck_smoke_bool_nil.log"
tc2_out="build/tmp/${compiler_base}_typecheck_smoke_bool_nil.obc"
rm -f "$tc2_log" "$tc2_out" 2>/dev/null || true

set +e
"$compiler" build "$tc2_src" --backend bytecode --typecheck -o "$tc2_out" >"$tc2_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: typecheck smoke (bool vs nil) expected failure but build succeeded"
  tail -n 80 "$tc2_log"
  exit 1
fi
tail -n 5 "$tc2_log"

echo "== parser smoke (reserved struct field __oren_type) =="
rs_src="tests/fixtures/typecheck_bad_reserved_struct_field_oren_type.oren"
rs_log="build/logs/${compiler_base}_parser_smoke_reserved_oren_type_field.log"
rs_out="build/tmp/${compiler_base}_parser_smoke_reserved_oren_type_field.obc"
rm -f "$rs_log" "$rs_out" 2>/dev/null || true

set +e
"$compiler" build "$rs_src" --backend bytecode --typecheck -o "$rs_out" >"$rs_log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: parser smoke (reserved __oren_type) expected failure but build succeeded"
  tail -n 80 "$rs_log"
  exit 1
fi
tail -n 5 "$rs_log"
