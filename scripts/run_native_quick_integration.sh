#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren}"
test_src="tests/native/test_quick_integration_native.oren"

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

uname_s="$(uname -s)"
uname_m="$(uname -m)"

os_key=""
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac

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
out="build/tmp/${compiler_base}_native_quick_integration${exe_ext}"
log="build/logs/${compiler_base}_native_quick_integration.log"

echo "== native quick integration =="
echo "compiler=$compiler"
echo "platform=$platform"
echo "src=$test_src"
echo "out=$out"
echo "log=$log"

rm -f "$log" "$out" 2>/dev/null || true

run_with_timeout "$build_timeout_secs" "$compiler" build "$test_src" \
  --backend native --platform "$platform" --debug -o "$out" >"$log" 2>&1

run_with_timeout "$run_timeout_secs" "$out" >>"$log" 2>&1

echo "== native quick integration (OREN_GREEN_POLL_CACHE=1) ==" >>"$log"
OREN_GREEN_POLL_CACHE=1 run_with_timeout "$run_timeout_secs" "$out" >>"$log" 2>&1

tail -n 5 "$log"

echo "== ulock timeout portable smoke ==" >>"$log"
ul_src="tests/native/test_ulock_timeout_portable.oren"
ul_out="build/tmp/${compiler_base}_ulock_timeout_portable${exe_ext}"
ul_log="build/logs/${compiler_base}_ulock_timeout_portable.log"
rm -f "$ul_log" "$ul_out" 2>/dev/null || true

run_with_timeout "$build_timeout_secs" "$compiler" build "$ul_src" \
  --backend native --platform "$platform" --debug -o "$ul_out" >"$ul_log" 2>&1
run_with_timeout "$run_timeout_secs" "$ul_out" >>"$ul_log" 2>&1
tail -n 3 "$ul_log" >>"$log"

echo "== os thread park/unpark smoke ==" >>"$log"
ot_src="tests/native/test_os_thread_park_unpark_smoke.oren"
ot_out="build/tmp/${compiler_base}_os_thread_park_unpark_smoke${exe_ext}"
ot_log="build/logs/${compiler_base}_os_thread_park_unpark_smoke.log"
rm -f "$ot_log" "$ot_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$ot_src" \
  --backend native --platform "$platform" --debug -o "$ot_out" >"$ot_log" 2>&1
run_with_timeout "$run_timeout_secs" "$ot_out" >>"$ot_log" 2>&1
tail -n 3 "$ot_log" >>"$log"

echo "== os thread spawn-many smoke ==" >>"$log"
om_src="tests/native/test_os_thread_spawn_many_smoke.oren"
om_out="build/tmp/${compiler_base}_os_thread_spawn_many_smoke${exe_ext}"
om_log="build/logs/${compiler_base}_os_thread_spawn_many_smoke.log"
rm -f "$om_log" "$om_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$om_src" \
  --backend native --platform "$platform" --debug -o "$om_out" >"$om_log" 2>&1
run_with_timeout "$run_timeout_secs" "$om_out" >>"$om_log" 2>&1
tail -n 3 "$om_log" >>"$log"

echo "== gc stw os-thread collect smoke ==" >>"$log"
gc_src="tests/native/test_gc_stw_os_thread_collect.oren"
gc_out="build/tmp/${compiler_base}_gc_stw_os_thread_collect${exe_ext}"
gc_log="build/logs/${compiler_base}_gc_stw_os_thread_collect.log"
rm -f "$gc_log" "$gc_out" 2>/dev/null || true
run_with_timeout "$build_timeout_secs" "$compiler" build "$gc_src" \
  --backend native --platform "$platform" --debug -o "$gc_out" >"$gc_log" 2>&1
run_with_timeout "$run_timeout_secs" "$gc_out" >>"$gc_log" 2>&1
tail -n 3 "$gc_log" >>"$log"

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
