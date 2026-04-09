#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF' >&2
usage: verify_native_quick_base_seeded_cold.sh [compiler]

Build runtime astbin/rtobj seeds once, then run the base quick-integration path against
empty active runtime caches and assert the compiler takes the rtobj seed-hit path rather
than rebuilding the runtime object from scratch.
EOF
  exit 0
fi

compiler="${1:-./oren_stage2}"
prewarm_timeout_secs="${OREN_NATIVE_QUICK_BASE_COLD_SEEDED_PREWARM_TIMEOUT_SECS:-360}"
build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-240}"
build_compiler="${OREN_NATIVE_QUICK_BASE_COLD_SEEDED_BUILD_COMPILER:-./oren}"

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
log="build/logs/native_quick_base_seeded_cold_${ts}.log"
compiler_tag="$(basename "$compiler")"
phase_log="build/logs/${compiler_tag}_native_quick_base_only.phases.log"
cache_root="build/tmp/native_quick_base_seeded_cold_cache"
obj_cache="${cache_root}/native_runtime_obj"
astbin_cache="${cache_root}/native_runtime_astbin"

rm -rf "$cache_root"
mkdir -p "$obj_cache" "$astbin_cache"

{
  echo "ts=$ts"
  echo "compiler=$compiler"
  echo "build_compiler=$build_compiler"
  echo "prewarm_timeout_secs=$prewarm_timeout_secs"
  echo "build_timeout_secs=$build_timeout_secs"
  echo "obj_cache=$obj_cache"
  echo "astbin_cache=$astbin_cache"
  echo "phase_log=$phase_log"
  echo "cwd=$(pwd)"
  echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
} >"$log"

echo "== prewarm runtime astbin seed ==" | tee -a "$log"
run_with_timeout "$prewarm_timeout_secs" \
  ./scripts/build_runtime_astbin_seed.sh --compiler "$build_compiler" \
  >>"$log" 2>&1

echo "== prewarm runtime obj seed ==" | tee -a "$log"
run_with_timeout "$prewarm_timeout_secs" \
  ./scripts/build_rtobj_seed.sh --compiler "$compiler" \
  --build-compiler "$build_compiler" --debug \
  >>"$log" 2>&1

rm -f "$phase_log"

echo "== run base quick integration against empty active runtime caches ==" | tee -a "$log"
OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR="$obj_cache" \
OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR="$astbin_cache" \
OREN_NATIVE_BUILD_TIMEOUT_SECS="$build_timeout_secs" \
  ./scripts/triage_native_quick_base_flake.sh 1 "$compiler" \
  >>"$log" 2>&1

if [[ ! -f "$phase_log" ]]; then
  echo "ERROR: expected phases log missing: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

if rg -q '^phase=rtobj.miss.build.start ' "$phase_log"; then
  echo "ERROR: cold seeded base run still rebuilt the runtime object: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

if ! rg -q '^phase=rtobj.seed_hit ' "$phase_log"; then
  echo "ERROR: cold seeded base run did not record rtobj.seed_hit: $phase_log" >&2
  echo "See: $log" >&2
  exit 1
fi

echo "== phases log tail ==" >>"$log"
tail -n 40 "$phase_log" >>"$log"

echo "OK: native quick base cold seeded verified (log=$log phase_log=$phase_log)" >&2
