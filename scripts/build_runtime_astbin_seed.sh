#!/usr/bin/env bash
set -euo pipefail

# Build or refresh the native runtime AST (astbin) "seed" directory.
#
# Why:
# - Stage2-native parsing of the expanded native runtime can be very slow on cold cache,
#   especially for capsule builds (`lib/runtime_native_capsule.oren`).
# - Stage1 (`./oren`) is much faster at parsing large sources on the primary dev host.
# - A seed directory lets the stage2-native compiler copy prebuilt runtime astbins into
#   the active cache dir on demand (see: OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR).
#
# This is a *non-artifact* cache; it is safe to regenerate any time.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

platform=""
compiler="./oren"
work_dir="${OREN_NATIVE_RUNTIME_ASTBIN_SEED_WORK_DIR:-build/tmp/runtime_astbin_seed_work}"
seed_dir="${OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR:-build/cache/native_runtime_astbin_seed}"

usage() {
  cat <<'EOF'
Usage: scripts/build_runtime_astbin_seed.sh [options]

Options:
  --platform <spec>   target platform (e.g. arm64-macos, x64-linux). Default: auto-detect host.
  --compiler <path>   compiler binary (default: ./oren, stage1 recommended)
  --work-dir <dir>    temp work dir for generating astbins (default: build/tmp/runtime_astbin_seed_work)
  --seed-dir <dir>    seed dir (default: build/cache/native_runtime_astbin_seed)
  --help              show this help

Behavior:
  - Builds two tiny programs (non-capsule + capsule) to force the compiler to locate and
    (if missing) parse+encode the runtime astbin, then copies the exact cache file into the seed dir.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    --compiler) compiler="${2:-}"; shift 2 ;;
    --work-dir) work_dir="${2:-}"; shift 2 ;;
    --cache-dir) work_dir="${2:-}"; shift 2 ;; # backward-compatible alias
    --seed-dir) seed_dir="${2:-}"; shift 2 ;;
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

if [[ "$seed_dir" = "0" || "$seed_dir" = "false" ]]; then
  echo "NOTE: seed disabled (OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=$seed_dir)" >&2
  exit 0
fi

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: compiler not found/executable: $compiler" >&2
  echo "Hint: build it with: make stage1 (./oren) or set --compiler ./oren_stage2" >&2
  exit 2
fi

mkdir -p build/tmp build/logs "$work_dir" "$seed_dir"

extract_cache_path() {
  local log_text="$1"
  # Prefer a "wrote" (fresh) line; fall back to "hit" (already present).
  local line
  line="$(
    printf "%s\n" "$log_text" | rg "cache astbin (wrote|hit) path=" | tail -n 1 || true
  )"
  if [[ -z "$line" ]]; then
    return 1
  fi
  printf "%s\n" "$line" | sed -E 's/.* path=([^ ]+).*/\1/'
}

build_one() {
  local name="$1"
  shift
  local out="build/tmp/astbin_seed_${name}_out"
  local log="build/logs/astbin_seed_${name}.log"
  local cache_one="${work_dir}/${name}"
  rm -f "$out" "$log" 2>/dev/null || true
  rm -rf "$cache_one" 2>/dev/null || true
  mkdir -p "$cache_one"

  # `--no-cache` is build-cache only; runtime astbin cache remains enabled and is written under $cache_one.
  local out_text
  out_text="$(
    OREN_TRACE_RUNTIME_BUNDLE=1 \
    OREN_NATIVE_RUNTIME_ASTBIN_CACHE=1 \
    OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR="$cache_one" \
    OREN_NATIVE_RUNTIME_OBJ_CACHE=0 \
      "$compiler" build "$@" --backend native --platform "$platform" --no-debug --no-cache -o "$out" 2>&1 | tee "$log"
  )"

  local p
  p="$(extract_cache_path "$out_text")"
  if [[ -z "$p" ]]; then
    # Fallback (robustness): if tracing isn't available, pick the newest astbin in this isolated dir.
    local base
    base="$(ls -1t "$cache_one" 2>/dev/null | rg "\\.astbin$" | head -n 1 || true)"
    if [[ -z "$base" ]]; then
      echo "ERROR: failed to detect runtime astbin cache path for $name (see $log)" >&2
      exit 1
    fi
    p="$cache_one/$base"
  fi
  if [[ ! -f "$p" ]]; then
    echo "ERROR: detected cache path does not exist: $p (from $log)" >&2
    exit 1
  fi

  cp -f "$p" "$seed_dir/"
  echo "OK: seeded $(basename "$p")"
}

echo "== runtime astbin seed ==" >&2
echo "platform=$platform" >&2
echo "compiler=$compiler" >&2
echo "work_dir=$work_dir" >&2
echo "seed_dir=$seed_dir" >&2

# Non-capsule runtime (lib/runtime_native.oren).
build_one "native" "tests/native/test_quick_integration_native.oren"

# Capsule runtime (lib/runtime_native_capsule.oren).
build_one "capsule" "tests/native/fixtures/capsule_ok.oren" --capsule

echo "OK: runtime astbin seed updated" >&2
