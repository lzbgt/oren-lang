#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF' >&2
usage: verify_native_quick_stage2_direct_autoseed.sh [compiler]

Run the direct stage2 native quick-integration script against empty active runtime caches
and empty runtime seed dirs, and assert the script auto-prewarms the current runtime seed
so the compile takes the rtobj seed-hit path instead of rebuilding the runtime object.
EOF
  exit 0
fi

compiler="${1:-./oren_stage2}"
build_compiler="${OREN_QI_RUNTIME_SEED_BUILD_COMPILER:-./oren}"
build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-240}"
run_timeout_secs="${OREN_NATIVE_RUN_TIMEOUT_SECS:-120}"
seed_timeout_secs="${OREN_QI_RUNTIME_SEED_TIMEOUT_SECS:-240}"

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: compiler not found or not executable: $compiler" >&2
  exit 2
fi
if [[ ! -x "$build_compiler" ]]; then
  build_compiler="$compiler"
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

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
log="build/logs/stage2_native_quick_direct_autoseed_${ts}.log"
phase_log="build/logs/stage2_native_quick_direct_autoseed_${ts}.phases.log"
root="build/tmp/stage2_native_quick_direct_autoseed_${ts}"
obj_cache="${root}/native_runtime_obj"
astbin_cache="${root}/native_runtime_astbin"
obj_seed="${root}/native_runtime_obj_seed"
astbin_seed="${root}/native_runtime_astbin_seed"

cleanup() {
  if [[ "${OREN_KEEP_NATIVE_QUICK_STAGE2_DIRECT_AUTOSEED_TMP:-0}" == "1" ]]; then
    return 0
  fi
  rm -rf "$root" 2>/dev/null || true
}
trap cleanup EXIT

rm -rf "$root"
mkdir -p "$obj_cache" "$astbin_cache" "$obj_seed" "$astbin_seed"

{
  echo "ts=$ts"
  echo "compiler=$compiler"
  echo "build_compiler=$build_compiler"
  echo "build_timeout_secs=$build_timeout_secs"
  echo "run_timeout_secs=$run_timeout_secs"
  echo "seed_timeout_secs=$seed_timeout_secs"
  echo "obj_cache=$obj_cache"
  echo "astbin_cache=$astbin_cache"
  echo "obj_seed=$obj_seed"
  echo "astbin_seed=$astbin_seed"
  echo "phase_log=$phase_log"
  echo "cwd=$(pwd)"
  echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
} >"$log"

echo "== direct stage2 quick integration with empty caches + seed dirs ==" | tee -a "$log"
run_with_timeout 720 env \
  OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR="$obj_cache" \
  OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR="$astbin_cache" \
  OREN_NATIVE_RUNTIME_OBJ_SEED_DIR="$obj_seed" \
  OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR="$astbin_seed" \
  OREN_NATIVE_BUILD_TIMEOUT_SECS="$build_timeout_secs" \
  OREN_NATIVE_RUN_TIMEOUT_SECS="$run_timeout_secs" \
  OREN_QI_RUNTIME_SEED_TIMEOUT_SECS="$seed_timeout_secs" \
  OREN_QI_RUNTIME_SEED_BUILD_COMPILER="$build_compiler" \
  OREN_QI_SKIP_GREEN_CACHE=1 \
  OREN_QI_STOP_AFTER_BASE=1 \
  OREN_TRACE_BUILD_PHASES_PATH="$phase_log" \
  ./scripts/run_native_quick_integration.sh "$compiler" >>"$log" 2>&1

if [[ ! -f "$phase_log" ]]; then
  echo "ERROR: expected phases log missing: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

if rg -q '^phase=rtobj\.miss\.build\.start ' "$phase_log"; then
  echo "ERROR: direct stage2 quick integration still rebuilt the runtime object: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

if ! rg -q '^phase=rtobj\.seed_hit ' "$phase_log"; then
  echo "ERROR: direct stage2 quick integration did not record rtobj.seed_hit: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

if ! find "$obj_seed" -mindepth 1 -maxdepth 1 | grep -q .; then
  echo "ERROR: runtime obj seed dir stayed empty: $obj_seed" >&2
  echo "See: $log" >&2
  exit 1
fi

echo "== phases log tail ==" >>"$log"
tail -n 40 "$phase_log" >>"$log"

echo "OK: direct stage2 quick integration auto-prewarmed rtobj seed (log=$log phase_log=$phase_log)" >&2
