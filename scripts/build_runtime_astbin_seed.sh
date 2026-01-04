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

sha256_file() {
  local p="$1"
  if [[ ! -f "$p" ]]; then
    echo ""
    return 0
  fi
  shasum -a 256 "$p" | awk '{print $1}'
}

runtime_sources_sha256() {
  # Hash all runtime source inputs that affect the runtime bundle fingerprint (astbin filename):
  # - root runtime files
  # - all included `lib/runtime_native/**/*.oren` modules
  #
  # This keeps the seed no-op check correct even when compiler-side fingerprinting changes
  # (as long as the stage1 compiler binary is also unchanged).
  local files
  files="$(
    {
      echo "lib/runtime_native.oren"
      echo "lib/runtime_native_capsule.oren"
      find lib/runtime_native -type f -name '*.oren' -print 2>/dev/null || true
    } | LC_ALL=C sort -u
  )"

  if [[ -z "$files" ]]; then
    echo ""
    return 0
  fi

  # Stable "hash of (hash,file)" so ordering differences don't matter.
  local per_file
  per_file="$(
    printf "%s\n" "$files" | while IFS= read -r f; do
      if [[ -f "$f" ]]; then
        local h
        h="$(sha256_file "$f")"
        if [[ -n "$h" ]]; then
          printf "%s  %s\n" "$h" "$f"
        fi
      fi
    done | LC_ALL=C sort
  )"
  if [[ -z "$per_file" ]]; then
    echo ""
    return 0
  fi
  printf "%s\n" "$per_file" | shasum -a 256 | awk '{print $1}'
}

# Fast no-op path:
# If the seed dir already contains (at least) both runtime variants for this OS, skip rebuilding.
# This keeps `make stage2` bounded in tight edit/verify loops.
#
# Force rebuild by setting:
#   OREN_FORCE_RUNTIME_ASTBIN_SEED=1
if [[ -d "$seed_dir" && -z "${OREN_FORCE_RUNTIME_ASTBIN_SEED:-}" ]]; then
  os="${platform#*-}"
  # NOTE: `rg` exits 1 on "no matches", and this script runs with `set -euo pipefail`.
  # Treat "no matches" as count=0 (do not abort).
  total="$(
    (ls -1 "$seed_dir" 2>/dev/null | rg "_os_${os}_pruned3\\.astbin$" || true) | wc -l | tr -d ' '
  )"

  # Correctness guard: ensure the seed matches the current runtime sources *and* the chosen seed compiler.
  # We cannot rely on matching the astbin basename against the runtime-obj hash:
  # - astbin filename is derived from `_rt_bundle_runtime_fingerprint_v2(expanded_runtime_src)`
  # - runtime-obj cache uses `rtobj_runtime_hash(...)`
  #
  # Instead, store a small meta file per OS capturing:
  # - runtime_sources_sha256 (all runtime inputs that affect the bundle fingerprint)
  # - compiler_sha256 (so compiler fingerprinting changes also invalidate the seed)
  meta="$seed_dir/.runtime_astbin_seed_meta_os_${os}.txt"
  if [[ "$total" -ge 2 && -f "$meta" ]]; then
    want_runtime_sha="$(runtime_sources_sha256)"
    want_compiler_sha="$(sha256_file "$compiler")"

    have_runtime_sha="$(
      rg "^runtime_sources_sha256=" "$meta" | head -n 1 | sed -E 's/^runtime_sources_sha256=//'
    )"
    have_compiler_sha="$(
      rg "^compiler_sha256=" "$meta" | head -n 1 | sed -E 's/^compiler_sha256=//'
    )"

    if [[ -n "$want_runtime_sha" && -n "$want_compiler_sha" && "$want_runtime_sha" == "$have_runtime_sha" && "$want_compiler_sha" == "$have_compiler_sha" ]]; then
      echo "OK: runtime astbin seed already present (os=$os files=$total)" >&2
      exit 0
    fi
  fi
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

os="${platform#*-}"
meta="$seed_dir/.runtime_astbin_seed_meta_os_${os}.txt"
{
  echo "seed_gen=1"
  echo "os=$os"
  echo "platform=$platform"
  echo "compiler_path=$compiler"
  echo "compiler_sha256=$(sha256_file "$compiler")"
  echo "runtime_sources_sha256=$(runtime_sources_sha256)"
  echo "created_at_ns=$(date +%s%N 2>/dev/null || date +%s)"
} >"$meta"

echo "OK: runtime astbin seed updated" >&2
