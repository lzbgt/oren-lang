#!/usr/bin/env bash
set -euo pipefail

# Build or refresh the native runtime-object "seed" directory.
#
# The seed is a copy of a valid rtobj cache entry stored in a stable location
# independent of the active `OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR`.
#
# Why:
# - Makes first-run native builds fast even when the selected cache dir is empty
#   (e.g. CI, ephemeral dirs, or benchmarking scripts that isolate cache dirs).
#
# Notes:
# - This script is best-effort and intentionally bounded: it prefers copying an
#   existing cache entry. If no suitable entry exists, it triggers a small build
#   once to populate the cache, then copies the newest matching entry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

platform=""
compiler="./oren_stage2"
debug_flag="--no-debug"

usage() {
  cat <<'EOF'
Usage: scripts/build_rtobj_seed.sh [options]

Options:
  --platform <spec>   target platform (e.g. arm64-macos, x64-linux). Default: auto-detect host.
  --compiler <path>   compiler binary (default: ./oren_stage2)
  --debug             generate seed for debug runtime objects
  --no-debug          generate seed for non-debug runtime objects (default)
  --help              show this help

Env:
  OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR   source rtobj cache dir (default: build/cache/native_runtime_obj)
  OREN_NATIVE_RUNTIME_OBJ_SEED_DIR    destination seed dir (default: build/cache/native_runtime_obj_seed)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    --compiler) compiler="${2:-}"; shift 2 ;;
    --debug) debug_flag="--debug"; shift ;;
    --no-debug) debug_flag="--no-debug"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$platform" ]]; then
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  os_key=""
  case "$uname_s" in
    Darwin) os_key="macos" ;;
    Linux) os_key="linux" ;;
    *) echo "ERROR: unsupported host OS: $uname_s" >&2; exit 2 ;;
  esac

  arch_key=""
  case "$uname_m" in
    arm64|aarch64) arch_key="arm64" ;;
    x86_64|amd64) arch_key="x64" ;;
    *) echo "ERROR: unsupported host arch: $uname_m" >&2; exit 2 ;;
  esac

  platform="${arch_key}-${os_key}"
fi

arch="${platform%%-*}"
os="${platform#*-}"

backend=""
case "$arch" in
  arm64) backend="arm64" ;;
  x64) backend="x64" ;;
  *) echo "ERROR: unsupported platform arch: $arch (platform=$platform)" >&2; exit 2 ;;
esac

cache_dir="${OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR:-build/cache/native_runtime_obj}"
seed_dir="${OREN_NATIVE_RUNTIME_OBJ_SEED_DIR:-build/cache/native_runtime_obj_seed}"

dbg="d0"
if [[ "$debug_flag" = "--debug" ]]; then dbg="d1"; fi

find_latest_key() {
  if [[ ! -d "$cache_dir" ]]; then return 1; fi
  # Newest first (mtime order).
  local key
  key="$(
    ls -1t "$cache_dir" 2>/dev/null | \
      rg "^s2_b_${backend}_" | \
      rg "_os_${os}_" | \
      rg "_${dbg}_g" | \
      head -n 1
  )"
  if [[ -z "$key" ]]; then return 1; fi
  echo "$key"
  return 0
}

copy_key_to_seed() {
  local key="$1"
  mkdir -p "$seed_dir"
  rm -rf "$seed_dir/$key" 2>/dev/null || true
  cp -R "$cache_dir/$key" "$seed_dir/"
  echo "OK: rtobj seed updated"
  echo "platform=$platform backend=$backend"
  echo "cache_dir=$cache_dir"
  echo "seed_dir=$seed_dir"
  echo "key=$key"
}

key=""
if key="$(find_latest_key)"; then
  copy_key_to_seed "$key"
  exit 0
fi

echo "NOTE: no existing rtobj cache entry found; populating cache once via a small build..." >&2

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: compiler not found/executable: $compiler" >&2
  echo "Hint: build it with: make stage2" >&2
  exit 2
fi

mkdir -p build/tmp

# Populate cache dir (do not isolate; we want it under $cache_dir).
OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR="$cache_dir" \
  "$compiler" build examples/hello.oren --backend native --platform "$platform" "$debug_flag" -o build/tmp/rtobj_seed_probe >/dev/null

key="$(find_latest_key || true)"
if [[ -z "$key" ]]; then
  echo "ERROR: still no rtobj cache entry found after build; cannot create seed" >&2
  exit 1
fi

copy_key_to_seed "$key"
