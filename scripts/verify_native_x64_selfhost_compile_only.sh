#!/usr/bin/env bash
set -euo pipefail

# Compile-only self-hosting sanity gate for x86_64 native backend targets.
#
# Purpose (rolling):
# - When remote Win11/WSL2 execution is unavailable, still keep a *high-signal* check
#   that the full compiler program (`oren.oren`) can be compiled for:
#     - x64-linux (ELF)
#     - x64-windows (PE32+)
# - This is heavier than the small-fixture x64 compile-only suite; it is not part of `make test`.
#
# Notes:
# - This does NOT run the produced artifacts (requires remote/QEMU).
# - Default uses `--no-cache` to avoid stale build-cache masking regressions.
#
# Env:
#   OREN_SELFHOST_BUILD_TIMEOUT_SECS (default: 240)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/verify_native_x64_selfhost_compile_only.sh [--targets <csv>] [--cache] [--trace]

Targets (comma-separated):
  all (default)
  x64-linux   (alias: x64-wsl)
  x64-win     (alias: x64-windows)

Flags:
  --cache   Enable the compiler build cache (default: off / --no-cache)
  --trace   Print each build step (still keeps logs bounded on success)

Examples:
  ./scripts/verify_native_x64_selfhost_compile_only.sh
  ./scripts/verify_native_x64_selfhost_compile_only.sh --targets x64-win
  OREN_SELFHOST_BUILD_TIMEOUT_SECS=480 ./scripts/verify_native_x64_selfhost_compile_only.sh --trace
EOF
}

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin file
need_bin make

mkdir -p build/tmp
mkdir -p build/logs

TARGETS_CSV="all"
TRACE=0
USE_CACHE=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace)
      TRACE=1
      shift
      ;;
    --cache)
      USE_CACHE=1
      shift
      ;;
    --targets)
      TARGETS_CSV="${2:-}"
      if [[ -z "$TARGETS_CSV" ]]; then
        echo "ERROR: --targets requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

normalize_target() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  case "$t" in
    all) echo all ;;
    linux|x64-linux|x64-wsl|wsl) echo x64-linux ;;
    win|windows|x64-win|x64-windows) echo x64-win ;;
    *) echo "$t" ;;
  esac
}

WANT_LINUX=1
WANT_WIN=1
if [[ "$TARGETS_CSV" != "all" ]]; then
  WANT_LINUX=0
  WANT_WIN=0
  IFS=',' read -r -a _parts <<<"$TARGETS_CSV"
  for p in "${_parts[@]}"; do
    p="$(normalize_target "$p")"
    case "$p" in
      x64-linux) WANT_LINUX=1 ;;
      x64-win) WANT_WIN=1 ;;
      *) echo "ERROR: unknown target selector: $p" >&2; usage >&2; exit 2 ;;
    esac
  done
fi

BUILD_TIMEOUT_SECS="${OREN_SELFHOST_BUILD_TIMEOUT_SECS:-240}"

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

if [[ ! -x ./oren_stage2 ]]; then
  echo "== ensure: stage2 compiler (./oren_stage2) ==" >&2
  make stage2
fi

SRC="oren.oren"

build_one() {
  local platform="$1"
  local out="$2"

  if [[ "$TRACE" -eq 1 ]]; then
    echo "== selfhost build: platform=$platform src=$SRC out=$out ==" >&2
  fi

  local cache_arg="--no-cache"
  if [[ "$USE_CACHE" -eq 1 ]]; then
    cache_arg=""
  fi

  local logf="build/logs/x64_selfhost_compile_only_${platform}.log"
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECS" ./oren_stage2 build "$SRC" \
    --backend native --platform "$platform" --no-debug $cache_arg -o "$out" \
    >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: selfhost build failed or timed out: platform=$platform timeout=${BUILD_TIMEOUT_SECS}s" >&2
    tail -n 160 "$logf" >&2 || true
    echo "log: $logf" >&2
    return "$rc"
  fi
}

check_elf_x64() {
  local p="$1"
  file "$p" | grep -E 'ELF 64-bit.*x86-64' >/dev/null
}

check_pe_x64_exe() {
  local p="$1"
  file "$p" | grep -F 'PE32+' >/dev/null
  file "$p" | grep -F '(DLL)' >/dev/null && return 2
  return 0
}

echo -n "== x64 selfhost compile-only: platforms=" >&2
if [[ "$WANT_LINUX" -eq 1 ]]; then echo -n "x64-linux " >&2; fi
if [[ "$WANT_WIN" -eq 1 ]]; then echo -n "x64-win " >&2; fi
if [[ "$USE_CACHE" -eq 1 ]]; then
  echo -n "cache=on " >&2
else
  echo -n "cache=off " >&2
fi
echo "timeout=${BUILD_TIMEOUT_SECS}s ==" >&2

if [[ "$WANT_LINUX" -eq 1 ]]; then
  build_one x64-linux "build/tmp/oren_selfhost_x64_linux"
  check_elf_x64 "build/tmp/oren_selfhost_x64_linux"
fi

if [[ "$WANT_WIN" -eq 1 ]]; then
  build_one x64-windows "build/tmp/oren_selfhost_x64_windows.exe"
  check_pe_x64_exe "build/tmp/oren_selfhost_x64_windows.exe"
fi

echo "OK: x64 selfhost compile-only verification passed" >&2

