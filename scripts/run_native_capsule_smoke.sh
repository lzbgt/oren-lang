#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren_stage2}"
test_src="tests/native/fixtures/capsule_ok.oren"

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"
run_timeout_secs="${OREN_NATIVE_RUN_TIMEOUT_SECS:-5}"
cache_mode="${OREN_NATIVE_CAPSULE_SMOKE_CACHE:-1}"

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
fi
out="build/tmp/${compiler_base}_native_capsule_smoke${exe_ext}"
log="build/logs/${compiler_base}_native_capsule_smoke.log"

echo "== native capsule smoke ==" | tee "$log"
echo "compiler=$compiler" | tee -a "$log"
echo "platform=$platform" | tee -a "$log"
echo "src=$test_src" | tee -a "$log"
echo "out=$out" | tee -a "$log"
echo "log=$log" | tee -a "$log"

rm -f "$out" 2>/dev/null || true

# NOTE:
# - Keep this smoke fast (bounded) by using `--no-debug` (smaller binaries).
# - Use the compiler build cache by default. For stage2 verification on this host, forcing
#   `--no-cache` can turn a minimal capsule smoke into a multi-minute cold compile that trips
#   watchdogs before the actual runtime path is exercised.
# - Set `OREN_NATIVE_CAPSULE_SMOKE_CACHE=0` to force a cold build when compile-path timing is
#   the thing under investigation.
# - Do not force-disable runtime bundle caches here: doing so turns this into an "rtobj miss"
#   benchmark and can legitimately take >10s on modern hosts.
cache_arg=""
if [[ "$cache_mode" == "0" ]]; then
  cache_arg="--no-cache"
fi
run_with_timeout "$build_timeout_secs" "$compiler" build "$test_src" \
  --backend native --platform "$platform" --capsule --no-debug $cache_arg -o "$out" >>"$log" 2>&1

run_with_timeout "$run_timeout_secs" "$out" >>"$log" 2>&1

tail -n 10 "$log"
grep -q "capsule ok" "$log"
