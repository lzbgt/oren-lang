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
force="${OREN_FORCE_RUNTIME_OBJ_SEED:-}"
runtime_profile="${OREN_NATIVE_RUNTIME_PROFILE:-}"
capsule="0"

usage() {
  cat <<'EOF'
Usage: scripts/build_rtobj_seed.sh [options]

Options:
  --platform <spec>   target platform (e.g. arm64-macos, x64-linux). Default: auto-detect host.
  --compiler <path>   compiler binary (default: ./oren_stage2)
  --capsule           seed the capsule runtime entry (lib/runtime_native_capsule.oren)
  --runtime-profile <full|core|minimal>
                     select the non-capsule runtime profile to seed (default: env OREN_NATIVE_RUNTIME_PROFILE, else "auto")
                     - "auto": match compiler default heuristic (core unless std:net/* is present)
  --debug             generate seed for debug runtime objects
  --no-debug          generate seed for non-debug runtime objects (default)
  --force             rebuild seed even if already present
  --help              show this help

Env:
  OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR   source rtobj cache dir (default: build/cache/native_runtime_obj)
  OREN_NATIVE_RUNTIME_OBJ_SEED_DIR    destination seed dir (default: build/cache/native_runtime_obj_seed)
  OREN_FORCE_RUNTIME_OBJ_SEED         if set, do not take the fast no-op path
  OREN_NATIVE_RUNTIME_PROFILE         runtime profile override ("auto"/"core"/"minimal"/"full")
  OREN_NATIVE_RUNTIME_OBJ_CACHE_CAPSULE
                                      opt-out for capsule rtobj caching (set to 0/false)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    --compiler) compiler="${2:-}"; shift 2 ;;
    --capsule) capsule="1"; shift ;;
    --runtime-profile) runtime_profile="${2:-}"; shift 2 ;;
    --debug) debug_flag="--debug"; shift ;;
    --no-debug) debug_flag="--no-debug"; shift ;;
    --force) force="1"; shift ;;
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
    MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
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

# Current backend signature (must match rtobj cache key `_bv_<sig>`).
#
# Important: the seed directory must track backend signature bumps; otherwise `rtobj_try_load_seed_into_cache`
# will miss and stage2-native will pay a slow cold rtobj build.
	want_bv=""
	case "$backend" in
	  arm64)
	    want_bv="$(grep -E '^var RUNTIME_OBJ_BACKEND_SIG_ARM64 = ' lib/compiler/native_runtime_obj_cache.oren 2>/dev/null | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
	    ;;
	  x64)
	    want_bv="$(grep -E '^var RUNTIME_OBJ_BACKEND_SIG_X64 = ' lib/compiler/native_runtime_obj_cache.oren 2>/dev/null | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
	    ;;
	esac
	if [[ -z "$want_bv" ]]; then
	  echo "ERROR: failed to determine runtime obj backend sig for backend=$backend" >&2
  echo "Hint: check lib/compiler/native_runtime_obj_cache.oren" >&2
  exit 2
fi

# Runtime entry file used for hashing/keys (non-capsule only; capsule uses a different entry file).
#
# IMPORTANT (matches compiler defaults):
# - When OREN_NATIVE_RUNTIME_PROFILE is unset/empty, the compiler uses a heuristic:
#   it prefers the smaller "core" runtime unless std:net/* is present.
# - This seed generator cannot cheaply know the program's import graph, so the
#   default is "auto" and we seed the "core" runtime entry.
runtime_entry="lib/runtime_native_core.oren"
if [[ "$capsule" = "1" ]]; then
  runtime_entry="lib/runtime_native_capsule.oren"
else
  case "${runtime_profile:-}" in
    ""|"auto") runtime_entry="lib/runtime_native_core.oren" ;;
    full) runtime_entry="lib/runtime_native.oren" ;;
    core|minimal) runtime_entry="lib/runtime_native_core.oren" ;;
    *) echo "ERROR: unsupported --runtime-profile: ${runtime_profile}" >&2; exit 2 ;;
  esac
fi

hash_cache_dir="${OREN_NATIVE_RUNTIME_HASH_CACHE_DIR:-build/cache/native_runtime_hash}"

sanitize_runtime_path() {
  local p="$1"
  echo "$p" | sed -E 's#[/\\\\:]#_#g'
}

rtobj_env_enabled() {
  local name="$1"
  local v="${!name-}"
  [[ -z "${v:-}" ]] && return 1
  [[ "$v" == "0" || "$v" == "false" ]] && return 1
  return 0
}

rtobj_hash_opts() {
  local opts=()
  if rtobj_env_enabled OREN_TRACE_NATIVE_ALLOC_REQ; then opts+=("alloc_req"); fi
  if rtobj_env_enabled OREN_TRACE_NATIVE_LIST_HDR; then opts+=("list_hdr"); fi
  if rtobj_env_enabled OREN_TRACE_NATIVE_LIST_RESERVE; then opts+=("list_reserve"); fi
  if [[ ${#opts[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi
  local IFS=,
  echo "${opts[*]}"
}

	runtime_hash_from_cache() {
	  # Best-effort: reuse the compiler's persisted runtime hash cache to pick the correct rtobj key.
  #
  # This avoids incorrectly "no-op"ing when the runtime hash changes (e.g. edits to lib/runtime_native.oren),
  # which would leave a stale seed in place and make cross-target verification fall back to a slow rtobj build.
  local base
  base="$(sanitize_runtime_path "$runtime_entry")"
	  local p="${hash_cache_dir}/${base}.hash.txt"
	  if [[ ! -f "$p" ]]; then return 1; fi
	  local line
	  line="$(grep -E "^hash=" "$p" 2>/dev/null | head -n 1 || true)"
	  [[ -z "$line" ]] && return 1
	  local rh="${line#hash=}"
	  local opts
	  opts="$(rtobj_hash_opts)"
	  if [[ -n "$opts" ]]; then
	    echo "${rh}_opt_${opts}"
	    return 0
	  fi
	  echo "${rh}"
	  return 0
	}

find_seed_key() {
  local want_rh="${1:-}"
  if [[ ! -d "$seed_dir" ]]; then return 1; fi
  local key
  # Prefer the explicit arch key; fall back to older `_a_unknown_` entries if present.
	  key="$(
	    (
	      ls -1t "$seed_dir" 2>/dev/null | \
	        grep -E "^s2_b_${backend}_" | \
	        grep -F "_bv_${want_bv}_" | \
	        grep -F "_os_${os}_" | \
	        grep -F "_a_${arch}_" | \
	        grep -F "_${dbg}_g" | \
	        { if [[ -n "$want_rh" ]]; then grep -F "_rh_${want_rh}" || true; else cat; fi; } | \
	        head -n 1
	    ) || true
	  )"
	  if [[ -z "$key" ]]; then
	    key="$(
	      (
	        ls -1t "$seed_dir" 2>/dev/null | \
	          grep -E "^s2_b_${backend}_" | \
	          grep -F "_bv_${want_bv}_" | \
	          grep -F "_os_${os}_" | \
	          grep -F "_a_unknown_" | \
	          grep -F "_${dbg}_g" | \
	          { if [[ -n "$want_rh" ]]; then grep -F "_rh_${want_rh}" || true; else cat; fi; } | \
	          head -n 1
	      ) || true
	    )"
	  fi
  if [[ -z "$key" ]]; then return 1; fi
  echo "$key"
  return 0
}

find_latest_key() {
  local want_rh="${1:-}"
  if [[ ! -d "$cache_dir" ]]; then return 1; fi
  # Newest first (mtime order).
  local key
	  key="$(
	    (
	      ls -1t "$cache_dir" 2>/dev/null | \
	        grep -E "^s2_b_${backend}_" | \
	        grep -F "_bv_${want_bv}_" | \
	        grep -F "_os_${os}_" | \
	        grep -F "_a_${arch}_" | \
	        grep -F "_${dbg}_g" | \
	        { if [[ -n "$want_rh" ]]; then grep -F "_rh_${want_rh}" || true; else cat; fi; } | \
	        head -n 1
	    ) || true
	  )"
	  if [[ -z "$key" ]]; then
	    # Backward-compatible fallback for older cache entries that used `_a_unknown`.
	    key="$(
	      (
	        ls -1t "$cache_dir" 2>/dev/null | \
	          grep -E "^s2_b_${backend}_" | \
	          grep -F "_bv_${want_bv}_" | \
	          grep -F "_os_${os}_" | \
	          grep -F "_a_unknown_" | \
	          grep -F "_${dbg}_g" | \
	          { if [[ -n "$want_rh" ]]; then grep -F "_rh_${want_rh}" || true; else cat; fi; } | \
	          head -n 1
	      ) || true
	    )"
	  fi
  if [[ -z "$key" ]]; then return 1; fi
  echo "$key"
  return 0
}

prune_seed_dir_keep() {
  local keep="$1"
  local want_rh="${2:-}"
  [[ -z "$keep" ]] && return 0
  [[ ! -d "$seed_dir" ]] && return 0

  # Keep the seed dir bounded: remove older keys for the same (backend, os, arch, debug) profile.
  # This avoids slow directory scans over time and keeps the seed mechanism predictable.
  #
  # Also delete legacy `_a_unknown_` keys once we have an arch-qualified key.
  local names
	  names="$(
	    (
	      ls -1 "$seed_dir" 2>/dev/null | \
	        grep -E "^s2_b_${backend}_" | \
	        grep -F "_os_${os}_" | \
	        grep -F "_${dbg}_g" | \
	        { if [[ -n "$want_rh" ]]; then grep -F "_rh_${want_rh}" || true; else cat; fi; }
	    ) || true
	  )"
  [[ -z "$names" ]] && return 0

  while IFS= read -r nm; do
    [[ -z "$nm" ]] && continue
    [[ "$nm" = "$keep" ]] && continue
    # If the new key is arch-qualified, prune both matching-arch and legacy unknown-arch keys.
    if [[ "$keep" = *"_a_${arch}_"* ]]; then
      if [[ "$nm" = *"_a_${arch}_"* || "$nm" = *"_a_unknown_"* ]]; then
        rm -rf "$seed_dir/$nm" 2>/dev/null || true
      fi
    else
      # Legacy mode: only prune other unknown-arch keys.
      if [[ "$nm" = *"_a_unknown_"* ]]; then
        rm -rf "$seed_dir/$nm" 2>/dev/null || true
      fi
    fi
  done <<<"$names"

  return 0
}

copy_key_to_seed() {
  local key="$1"
  local want_rh="${2:-}"
  mkdir -p "$seed_dir"
  prune_seed_dir_keep "$key" "$want_rh"

  rm -rf "$seed_dir/$key" 2>/dev/null || true
  cp -R "$cache_dir/$key" "$seed_dir/"
  echo "OK: rtobj seed updated"
  echo "platform=$platform backend=$backend"
  echo "runtime_profile=${runtime_profile:-auto} runtime_entry=$runtime_entry"
  echo "cache_dir=$cache_dir"
  echo "seed_dir=$seed_dir"
  echo "key=$key"
}

key=""
want_rh="$(runtime_hash_from_cache || true)"

# If we don't know the runtime hash, we must not "guess" by copying an arbitrary newest entry:
# different runtime profiles (full/core) need distinct seeds keyed by `_rh_<hash>`.
if [[ -z "$want_rh" ]]; then
  force="1"
fi

if [[ -z "$force" && -n "$want_rh" ]]; then
  if key="$(find_seed_key "$want_rh")"; then
    prune_seed_dir_keep "$key" "$want_rh"
    echo "OK: rtobj seed already present (no-op)" >&2
    echo "platform=$platform backend=$backend debug=$debug_flag" >&2
    echo "runtime_profile=${runtime_profile:-auto} runtime_entry=$runtime_entry" >&2
    echo "seed_dir=$seed_dir" >&2
    echo "key=$key" >&2
    exit 0
  fi
fi

if [[ -z "$force" ]]; then
  if key="$(find_latest_key "$want_rh")"; then
    copy_key_to_seed "$key" "$want_rh"
    exit 0
  fi
fi

echo "NOTE: no existing rtobj cache entry found; populating cache once via a small build..." >&2

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: compiler not found/executable: $compiler" >&2
  echo "Hint: build it with: make stage2" >&2
  exit 2
fi

mkdir -p build/tmp

# Populate cache dir (do not isolate; we want it under $cache_dir).
#
# NOTE:
# - When runtime_profile is unset/empty, we explicitly set "auto" so the behavior
#   is deterministic for this seed probe.
rp="${runtime_profile:-auto}"
capsule_flag=""
if [[ "$capsule" = "1" ]]; then
  capsule_flag="--capsule"
fi
OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR="$cache_dir" \
OREN_NATIVE_RUNTIME_PROFILE="$rp" \
  "$compiler" build examples/hello.oren --backend native --platform "$platform" \
  $capsule_flag \
  "$debug_flag" --no-cache -o build/tmp/rtobj_seed_probe >/dev/null

want_rh="$(runtime_hash_from_cache || true)"
if [[ -z "$want_rh" ]]; then
  echo "ERROR: runtime hash cache still missing after build; cannot safely select a seed key" >&2
  echo "runtime_profile=${runtime_profile:-auto} runtime_entry=$runtime_entry" >&2
  exit 1
fi

key="$(find_latest_key "$want_rh" || true)"
if [[ -z "$key" ]]; then
  echo "ERROR: still no rtobj cache entry found after build; cannot create seed" >&2
  exit 1
fi

copy_key_to_seed "$key" "$want_rh"
