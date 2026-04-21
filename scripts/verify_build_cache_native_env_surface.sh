#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren_stage2}"

if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler" >&2
  exit 2
fi

host_os="$(uname -s)"
host_arch="$(uname -m)"
if [[ "$host_os" != "Darwin" ]] || [[ "$host_arch" != "arm64" && "$host_arch" != "aarch64" ]]; then
  echo "SKIP: native cache env-surface smoke currently targets arm64-macos only"
  exit 0
fi

fixture="tests/native/test_gc_reuse_alloc_churn_min.oren"
cache_dir="build/tmp/cache_env_surface"
log_dir="build/logs/cache_env_surface"
out0="$cache_dir/out_nonneg0"
out1="$cache_dir/out_nonneg1"
out0_restore="$cache_dir/out_nonneg0_restore"
log0="$log_dir/build_nonneg0.log"
log1="$log_dir/build_nonneg1.log"
log0_restore="$log_dir/build_nonneg0_restore.log"

mkdir -p build/logs
rm -rf "$cache_dir" "$log_dir"
mkdir -p "$cache_dir" "$log_dir"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  echo "Missing shasum/sha256sum" >&2
  exit 2
}

build_variant() {
  local mode="$1"
  local out="$2"
  local log="$3"
  env \
    OREN_CACHE_DIR="$cache_dir" \
    OREN_TRACE_BUILD=1 \
    OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR="$mode" \
    "$compiler" build "$fixture" --backend native --platform arm64-macos --no-debug -o "$out" --codesign - \
    >"$log" 2>&1
}

build_variant 0 "$out0" "$log0"
hash0="$(sha256_file "$out0")"

build_variant 1 "$out1" "$log1"
hash1="$(sha256_file "$out1")"

if [[ "$hash0" == "$hash1" ]]; then
  echo "ERROR: native build cache reused the same artifact across OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=0/1" >&2
  echo "hash=$hash0" >&2
  tail -n 80 "$log1" >&2 || true
  exit 1
fi

if ! grep -Fq "[build] native emit start (arm64) target=macos" "$log1"; then
  echo "ERROR: nonneg-linear=1 build did not recompile; expected native emit on cache miss" >&2
  tail -n 80 "$log1" >&2 || true
  exit 1
fi

build_variant 0 "$out0_restore" "$log0_restore"
hash0_restore="$(sha256_file "$out0_restore")"

if [[ "$hash0" != "$hash0_restore" ]]; then
  echo "ERROR: cached restore for nonneg-linear=0 did not reproduce the original artifact" >&2
  echo "hash0=$hash0" >&2
  echo "hash0_restore=$hash0_restore" >&2
  tail -n 80 "$log0_restore" >&2 || true
  exit 1
fi

if grep -Fq "[build] native emit start (arm64) target=macos" "$log0_restore"; then
  echo "ERROR: repeated nonneg-linear=0 build did not restore from cache" >&2
  tail -n 80 "$log0_restore" >&2 || true
  exit 1
fi

echo "OK: native build cache tracks arm64 fast-list env surface"
