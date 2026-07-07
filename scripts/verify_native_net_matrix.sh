#!/usr/bin/env bash
set -euo pipefail

# Verify Oren's native NET substrate across the Tier‑1 matrix without external runners.
#
# This focuses on loopback-only network behavior (no external connectivity):
# - TCP listen/connect/accept/read/write (+ syscall-first send/recv)
# - UDP bind/sendto/recvfrom
# - DNS A query loopback over UDP (authoritative toy server; no external resolver)
# - HTTP/1.1 GET loopback (Content-Length + chunked) over TCP (uses spawn)
# - WebSocket (ws://) handshake + text echo over TCP (uses spawn)
#
# It builds:
# - stage0 (Go): ./oren_bootstrap
# - stage1 (self-hosted): ./oren
# - stage2 (self-hosted): ./oren_stage2
#
# Then it compiles+executes these tests as native binaries:
#   tests/native/test_net_suite.oren
#   tests/native/test_dns_loopback.oren
#   tests/native/test_http_get_loopback.oren
#   tests/native/test_ws_echo_loopback.oren
#
# Targets:
# - host platform (runs locally)
# - arm64-linux (runs in the persistent container)
# - x64-linux (runs under remote WSL2)
# - x64-windows (runs on remote Win11)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/linux_docker_lib.sh"

detect_host_platform() {
  local uname_s uname_m os_key arch_key
  uname_s="$(uname -s 2>/dev/null || echo "")"
  uname_m="$(uname -m 2>/dev/null || echo "")"
  os_key=""
  case "$uname_s" in
    Darwin) os_key="macos" ;;
    Linux) os_key="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
    *) os_key="" ;;
  esac
  arch_key=""
  case "$uname_m" in
    arm64|aarch64) arch_key="arm64" ;;
    x86_64|amd64) arch_key="x64" ;;
    *) arch_key="" ;;
  esac
  if [[ -n "$os_key" && -n "$arch_key" ]]; then
    echo "${arch_key}-${os_key}"
    return 0
  fi
  return 1
}

LOCAL_PLATFORM="$(detect_host_platform 2>/dev/null || true)"
LOCAL_TAG="${LOCAL_PLATFORM//-/_}"
LOCAL_EXE_EXT=""
if [[ "$LOCAL_PLATFORM" == *"-windows" ]]; then
  LOCAL_EXE_EXT=".exe"
fi

NET_SUITE_SRC="tests/native/test_net_suite.oren"
DNS_LOOPBACK_SRC="tests/native/test_dns_loopback.oren"
HTTP_LOOPBACK_SRC="tests/native/test_http_get_loopback.oren"
HTTPS_LOOPBACK_SRC="tests/native/test_https_get_loopback.oren"
WS_ECHO_SRC="tests/native/test_ws_echo_loopback.oren"
WSS_ECHO_SRC="tests/native/test_wss_echo_loopback.oren"
TLS_LOOPBACK_SRC="tests/native/test_tls_loopback.oren"
HTTP2_PREFACE_LOOPBACK_SRC="tests/native/test_http2_preface_loopback.oren"
HPACK_SMOKE_SRC="tests/native/test_hpack_smoke.oren"
HTTP2_HEADERS_LOOPBACK_SRC="tests/native/test_http2_headers_loopback.oren"

LINUX_DOCKER_REF="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
LINUX_DOCKER_ID=""
BUILD_TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"
STAGE2_BUILD_TIMEOUT_SECS="${OREN_NATIVE_STAGE2_BUILD_TIMEOUT_SECS:-120}"
STAGE2_HTTPS_LOCAL_TIMEOUT_SECS="${OREN_NATIVE_STAGE2_HTTPS_LOCAL_TIMEOUT_SECS:-180}"
STAGE2_WS_LOCAL_TIMEOUT_SECS="${OREN_NATIVE_STAGE2_WS_LOCAL_TIMEOUT_SECS:-180}"
STAGE2_HTTP2_HEADERS_LOCAL_TIMEOUT_SECS="${OREN_NATIVE_STAGE2_HTTP2_HEADERS_LOCAL_TIMEOUT_SECS:-180}"
STAGE2_BUILD_TIMEOUT_SECS_ARM64_LINUX="${OREN_NATIVE_STAGE2_BUILD_TIMEOUT_SECS_ARM64_LINUX:-900}"
SCP_RETRIES="${OREN_REMOTE_SCP_RETRIES:-6}"
SCP_TIMEOUT_SECS="${OREN_REMOTE_SCP_TIMEOUT_SECS:-120}"
WS_ECHO_N="${OREN_WS_ECHO_N:-}"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

usage() {
  cat <<'EOF'
Usage: scripts/verify_native_net_matrix.sh [--targets <csv>] [--local-only]
       scripts/verify_native_net_matrix.sh [--targets <csv>] [--trace]
       scripts/verify_native_net_matrix.sh [--targets <csv>] [--skip-remote]
       scripts/verify_native_net_matrix.sh [--host <user@host>] [--proxy <ssh_opt>] [--no-proxy]

Runs (loopback-only; no external network):
  - tests/native/test_net_suite.oren
  - tests/native/test_dns_loopback.oren
  - tests/native/test_http_get_loopback.oren
  - tests/native/test_https_get_loopback.oren
  - tests/native/test_ws_echo_loopback.oren
  - tests/native/test_wss_echo_loopback.oren
  - tests/native/test_tls_loopback.oren
  - tests/native/test_http2_preface_loopback.oren
  - tests/native/test_hpack_smoke.oren
  - tests/native/test_http2_headers_loopback.oren

Targets (comma-separated):
  all         (default)
  stage0      build ./oren_bootstrap
  stage1      build ./oren
  stage2      build ./oren_stage2
  local       run local host platform (stage1 + stage2)
  arm64-linux run linux/arm64 in docker container
  x64-win     run x64-windows on remote Win11
  x64-wsl     run x64-linux under remote WSL2

Examples:
  ./scripts/verify_native_net_matrix.sh
  ./scripts/verify_native_net_matrix.sh --targets local
  ./scripts/verify_native_net_matrix.sh --targets arm64-linux
  ./scripts/verify_native_net_matrix.sh --targets x64-win,x64-wsl
  ./scripts/verify_native_net_matrix.sh --targets local,arm64-linux --skip-remote

Env overrides:
  OREN_LINUX_DOCKER_ID   (default: c7e5f7bd9f5c; container name, full ID, or unambiguous ID prefix)
  OREN_NATIVE_BUILD_TIMEOUT_SECS (default: 10) timeout for each stage1 `oren build ...` step (rolling hang guard)
  OREN_NATIVE_STAGE2_BUILD_TIMEOUT_SECS (default: 120) timeout floor for stage2 `oren build ...` steps
  OREN_NATIVE_STAGE2_HTTPS_LOCAL_TIMEOUT_SECS (default: 180) local stage2 HTTPS fixture timeout floor
  OREN_NATIVE_STAGE2_WS_LOCAL_TIMEOUT_SECS (default: 180) local stage2 WebSocket fixture timeout floor
  OREN_NATIVE_STAGE2_HTTP2_HEADERS_LOCAL_TIMEOUT_SECS (default: 180) local stage2 HTTP/2 headers fixture timeout floor
  OREN_NATIVE_STAGE2_BUILD_TIMEOUT_SECS_ARM64_LINUX (default: 900) stage2 arm64-linux cross-build timeout floor
  OREN_NATIVE_BUILD_TIMEOUT_SECS_X64_WINDOWS (default: 15) timeout override for x64-windows cross builds (toolchain-heavy)
  OREN_REMOTE_X64_HOST   (default: lzbgt@pc.work)
  OREN_REMOTE_X64_PROXY  (default: ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002)
  OREN_REMOTE_X64_WIN_ROOT (default: C:\Users\<user>\tmp_oren) remote Windows staging root
  OREN_REMOTE_X64_WSL_ROOT (default: /mnt/c/Users/<user>/tmp_oren) remote WSL staging root
  OREN_REMOTE_X64_SSH_ROOT (default: tmp_oren) scp/sftp staging root (Windows OpenSSH path)
  OREN_REMOTE_SCP_TIMEOUT_SECS (default: 120)
  OREN_WS_ECHO_N         (optional) run ws echo loop N times (stress)
  OREN_CANON_I32_ABORT   (optional) set to 1 to hard-fail on non-canonical i32 values on all targets
EOF
}

LOCAL_ONLY=0
SKIP_REMOTE=0
TARGETS_CSV="all"
TRACE=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="${2:-}"
      if [[ -z "$REMOTE_HOST" ]]; then
        echo "ERROR: --host requires a value (example: user@203.0.113.10)" >&2
        exit 2
      fi
      shift 2
      ;;
    --proxy)
      REMOTE_PROXY="${2:-}"
      shift 2
      ;;
    --no-proxy)
      REMOTE_PROXY=""
      shift
      ;;
    --local-only)
      LOCAL_ONLY=1
      shift
      ;;
    --skip-remote)
      SKIP_REMOTE=1
      shift
      ;;
    --trace)
      TRACE=1
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

log() { printf '%s\n' "$*"; }

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

host_os="$(uname -s)"
host_arch="$(uname -m)"
if [[ "$host_os" != "Darwin" ]]; then
  echo "ERROR: this script currently assumes a macOS host; got OS=$host_os" >&2
  exit 2
fi
if [[ "$host_arch" != "arm64" ]]; then
  echo "ERROR: this script currently assumes an arm64 macOS host; got arch=$host_arch" >&2
  exit 2
fi

need_bin go
need_bin make

detect_parse_jobs() {
  sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4
}

clamp_int() {
  local v="$1"
  local lo="$2"
  local hi="$3"
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    echo "$lo"
    return 0
  fi
  if [[ "$v" -lt "$lo" ]]; then
    echo "$lo"
    return 0
  fi
  if [[ "$v" -gt "$hi" ]]; then
    echo "$hi"
    return 0
  fi
  echo "$v"
}

# Compiler performance knobs (rolling guardrails):
# - OREN_PARSE_JOBS: parallel module parsing / include-aggregation (stage2 hotspot for large graphs)
# - GC env: reduce compiler-runtime GC churn while compiling big module graphs
#
# IMPORTANT: these are applied only to the compiler process (not the test binaries we run),
# so they do not mask GC/runtime regressions in the NET tests themselves.
OREN_NET_MATRIX_PARSE_JOBS="${OREN_PARSE_JOBS:-}"
if [[ -z "$OREN_NET_MATRIX_PARSE_JOBS" ]]; then
  OREN_NET_MATRIX_PARSE_JOBS="$(detect_parse_jobs)"
fi
# Keep it bounded to avoid oversubscription on large hosts; still plenty for stage2 parsing.
OREN_NET_MATRIX_PARSE_JOBS="$(clamp_int "$OREN_NET_MATRIX_PARSE_JOBS" 1 16)"

OREN_NET_MATRIX_GC_ALLOC_THRESHOLD="$(clamp_int "${OREN_GC_ALLOC_THRESHOLD:-4000000}" 1000000 1000000000)"
OREN_NET_MATRIX_GC_STACK_SCAN_LIMIT_BYTES="$(clamp_int "${OREN_GC_STACK_SCAN_LIMIT_BYTES:-8388608}" 1048576 268435456)"

COMPILER_ENV=(
  "OREN_PARSE_JOBS=${OREN_NET_MATRIX_PARSE_JOBS}"
  # Native backend uses fork-based spawn today; enable fork-parallel module parsing (ASTBIN bounce)
  # so large stdlib graphs (TLS/HTTP2) stay under the rolling 10s build timeout.
  "OREN_PARSE_FORK_PARALLEL=1"
  "OREN_GC_AUTO=1"
  "OREN_GC_ALLOC_THRESHOLD=${OREN_NET_MATRIX_GC_ALLOC_THRESHOLD}"
  "OREN_GC_STACK_SCAN_LIMIT_BYTES=${OREN_NET_MATRIX_GC_STACK_SCAN_LIMIT_BYTES}"
)
if [[ "$TRACE" -ne 0 ]]; then
  # Minimal, bounded output in logs (one summary line per build).
  COMPILER_ENV+=("OREN_TRACE_BUILD_SUMMARY=1" "OREN_TRACE_BUILD_SLOW_MS=0")
fi

normalize_target() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  case "$t" in
    win|windows|x64-windows) echo x64-win ;;
    wsl|x64-linux|linux-x64) echo x64-wsl ;;
    *) echo "$t" ;;
  esac
}

TARGETS_NORM=()
if [[ "$TARGETS_CSV" != "all" ]]; then
  IFS=',' read -r -a _parts <<<"$TARGETS_CSV"
  for p in "${_parts[@]}"; do
    TARGETS_NORM+=("$(normalize_target "$p")")
  done
fi

has_target() {
  local want="$1"
  if [[ "$TARGETS_CSV" == "all" ]]; then
    return 0
  fi
  want="$(normalize_target "$want")"
  for p in "${TARGETS_NORM[@]}"; do
    if [[ "$p" == "$want" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "$LOCAL_ONLY" -eq 0 ]]; then
  if has_target arm64-linux; then
    need_bin docker
  fi
  if [[ "$SKIP_REMOTE" -eq 0 ]] && ( has_target x64-win || has_target x64-wsl ); then
    need_bin ssh
    need_bin scp
    need_bin tar
    need_bin grep
    if [[ -n "$REMOTE_PROXY" ]] && [[ "$REMOTE_PROXY" == *socat* ]]; then
      need_bin socat
    fi
  fi
fi

if [[ "$SKIP_REMOTE" -ne 0 && "$TARGETS_CSV" != "all" ]]; then
  # Explicit remote target selection + skip-remote is contradictory; force callers to be clear.
  if has_target x64-win || has_target x64-wsl; then
    echo "ERROR: --skip-remote cannot be used when --targets explicitly includes x64-win or x64-wsl" >&2
    echo "Hint: use --targets local,arm64-linux (no remote), or omit --skip-remote to run remote verification." >&2
    exit 2
  fi
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
    sleep 1
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

need_stage1_and_stage2() {
  # Rolling correctness: keep stage1/stage2 in sync with the repo source.
  #
  # Relying on "file exists" can leave a stale `./oren_stage2` after compiler changes,
  # which makes Tier‑1 gates silently test old behavior (or fail with confusing symptoms).
  log "== ensure: stage1 compiler (./oren) =="
  make stage1
  log "== ensure: stage2 compiler (./oren_stage2) =="
  make stage2
}

if has_target stage0; then
  log "== build: stage0 (Go bootstrap) =="
  make bootstrap
fi
if has_target stage1; then
  log "== build: stage1 (self-hosted) =="
  make stage1
fi
if has_target stage2; then
  log "== build: stage2 (self-hosted) =="
  make stage2
fi

if has_target local || has_target arm64-linux || has_target x64-win || has_target x64-wsl; then
  need_stage1_and_stage2
fi

mkdir -p build/tmp

abi_warn_patterns='x64 native v0: missing ABI arg reg|x64 native v0: missing ABI arg regs'

build_native_bin_src() {
  local compiler="$1"
  local platform="$2"
  local src="$3"
  local out="$4"

  if [[ ! -x "$compiler" ]]; then
    echo "ERROR: missing compiler executable: $compiler (build with: make stage1 stage2)" >&2
    exit 2
  fi

  local timeout_secs="$BUILD_TIMEOUT_SECS"
  if [[ "$(basename "$compiler")" == "oren_stage2" ]]; then
    timeout_secs="$STAGE2_BUILD_TIMEOUT_SECS"
    if [[ "$platform" == "$LOCAL_PLATFORM" && "$src" == "$HTTPS_LOOPBACK_SRC" && "$timeout_secs" -lt "$STAGE2_HTTPS_LOCAL_TIMEOUT_SECS" ]]; then
      timeout_secs="$STAGE2_HTTPS_LOCAL_TIMEOUT_SECS"
    fi
    if [[ "$platform" == "$LOCAL_PLATFORM" && "$src" == "$WS_ECHO_SRC" && "$timeout_secs" -lt "$STAGE2_WS_LOCAL_TIMEOUT_SECS" ]]; then
      timeout_secs="$STAGE2_WS_LOCAL_TIMEOUT_SECS"
    fi
    if [[ "$platform" == "$LOCAL_PLATFORM" && "$src" == "$HTTP2_HEADERS_LOOPBACK_SRC" && "$timeout_secs" -lt "$STAGE2_HTTP2_HEADERS_LOCAL_TIMEOUT_SECS" ]]; then
      timeout_secs="$STAGE2_HTTP2_HEADERS_LOCAL_TIMEOUT_SECS"
    fi
    if [[ "$platform" == "arm64-linux" && "$timeout_secs" -lt "$STAGE2_BUILD_TIMEOUT_SECS_ARM64_LINUX" ]]; then
      timeout_secs="$STAGE2_BUILD_TIMEOUT_SECS_ARM64_LINUX"
    fi
  fi
  if [[ "$platform" == "x64-windows" ]]; then
    local t_override="${OREN_NATIVE_BUILD_TIMEOUT_SECS_X64_WINDOWS:-}"
    if [[ -n "$t_override" ]]; then
      timeout_secs="$t_override"
    else
      # Cross-linking PE/COFF on macOS is currently slower than Mach-O; keep the
      # hang guard, but avoid false positives while we keep optimizing x64-win.
      #
      # NOTE: stage2 now has a persistent module ASTBIN cache, and module prefixes are
      # stable across entrypoints, so large stdlib graphs (TLS/HTTP2/HPACK) should stay
      # close to the rolling 10s target even on x64-windows cross builds.
      if [[ "$timeout_secs" -lt 12 ]]; then timeout_secs=12; fi
    fi
  fi

  mkdir -p build/logs
  local compiler_id
  compiler_id="$(basename "$compiler")"
  local src_id
  src_id="$(basename "$src")"
  src_id="${src_id%.oren}"
  local out_id
  out_id="$(basename "$out")"
  local logf="build/logs/net_matrix_build_${compiler_id}_${platform}_${src_id}_${out_id}.log"

  set +e
  run_with_timeout "$timeout_secs" env "${COMPILER_ENV[@]}" "$compiler" build "$src" --backend native --platform "$platform" --no-debug -o "$out" >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform src=$src timeout=${timeout_secs}s" >&2
    tail -n 80 "$logf" 2>/dev/null || true
    exit "$rc"
  fi

  # Fail fast on known x64-native backend correctness warnings, even if the compiler exits 0.
  if grep -Eq "$abi_warn_patterns" "$logf"; then
    echo "ERROR: ABI arg-reg warnings found in build log (compiler=$compiler platform=$platform src=$src)" >&2
    grep -nE "$abi_warn_patterns" "$logf" | head -n 40 >&2 || true
    echo "log=$logf" >&2
    exit 1
  fi

  log "Build successful: $out"
}

run_local_bin() {
  local bin="$1"
  if [[ ! -x "$bin" ]]; then
    echo "ERROR: missing binary: $bin" >&2
    exit 2
  fi
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  local tbin=""
  tbin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
  if [[ -n "$tbin" ]]; then
    if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
      env OREN_CANON_I32_ABORT=1 "$tbin" 20s "$bin"
    else
      "$tbin" 20s "$bin"
    fi
  else
    if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
      env OREN_CANON_I32_ABORT=1 "$bin"
    else
      "$bin"
    fi
  fi
}

if has_target local; then
  if [[ -z "$LOCAL_PLATFORM" ]]; then
    echo "ERROR: could not detect host platform for --targets local (uname -s / uname -m unsupported?)" >&2
    exit 2
  fi

  log "== verify: local ${LOCAL_PLATFORM} (stage1 + stage2) =="

  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$NET_SUITE_SRC" "build/tmp/net_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$NET_SUITE_SRC" "build/tmp/net_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$WS_ECHO_SRC" "build/tmp/ws_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$WS_ECHO_SRC" "build/tmp/ws_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$WSS_ECHO_SRC" "build/tmp/wss_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$WSS_ECHO_SRC" "build/tmp/wss_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren" "$LOCAL_PLATFORM" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  build_native_bin_src "./oren_stage2" "$LOCAL_PLATFORM" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"

  run_local_bin "build/tmp/net_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/net_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/dns_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/dns_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/https_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/https_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/ws_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/ws_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/wss_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/wss_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/tls_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/tls_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http2_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http2_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/hpack_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/hpack_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http2_headers_stage1_${LOCAL_TAG}${LOCAL_EXE_EXT}"
  run_local_bin "build/tmp/http2_headers_stage2_${LOCAL_TAG}${LOCAL_EXE_EXT}"

  log "OK: local ${LOCAL_PLATFORM}"
fi

if [[ "$LOCAL_ONLY" -ne 0 ]]; then
  log "OK: local-only verification complete"
  exit 0
fi

run_in_linux_container() {
  local bin="$1"
  local dst="/tmp/$(basename "$bin")"
  docker cp "$bin" "${LINUX_DOCKER_ID}:${dst}"
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  local canon_env=""
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    canon_env="OREN_CANON_I32_ABORT=1 "
  fi
  if [[ -n "$WS_ECHO_N" ]]; then
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "chmod +x '$dst' && ${canon_env}OREN_WS_ECHO_N='$WS_ECHO_N' timeout 20s '$dst'"
  else
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "chmod +x '$dst' && ${canon_env}timeout 20s '$dst'"
  fi
}

remote_user="$REMOTE_HOST"
if [[ "$REMOTE_HOST" == *"@"* ]]; then
  remote_user="${REMOTE_HOST%@*}"
fi
remote_win_root="${OREN_REMOTE_X64_WIN_ROOT:-C:\\Users\\${remote_user}\\tmp_oren}"
remote_win_root_cmd="${remote_win_root//\//\\}"
remote_unix_root="${OREN_REMOTE_X64_SSH_ROOT:-}"
if [[ -z "$remote_unix_root" ]]; then
  if [[ -n "${OREN_REMOTE_X64_WIN_ROOT:-}" ]]; then
    remote_unix_root="${remote_win_root_cmd//\\//}"
  else
    remote_unix_root="tmp_oren"
  fi
fi
remote_wsl_root="${OREN_REMOTE_X64_WSL_ROOT:-}"
if [[ -z "$remote_wsl_root" ]]; then
  if [[ -n "${OREN_REMOTE_X64_WIN_ROOT:-}" && "$remote_win_root_cmd" =~ ^([A-Za-z]):\\(.*)$ ]]; then
    drive="${BASH_REMATCH[1],,}"
    rest="${BASH_REMATCH[2]//\\//}"
    remote_wsl_root="/mnt/${drive}/${rest}"
  else
    remote_wsl_root="/mnt/c/Users/${remote_user}/tmp_oren"
  fi
fi

ssh_opt_proxy=()
scp_opt_proxy=()
if [[ -n "$REMOTE_PROXY" ]]; then
  ssh_opt_proxy=(-o "$REMOTE_PROXY")
  scp_opt_proxy=(-o "$REMOTE_PROXY")
fi

ssh_base=(ssh "${ssh_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 "$REMOTE_HOST")
# OpenSSH scp defaults to SFTP mode on modern clients; Windows OpenSSH servers can be flaky under
# proxying/SSH jump setups. Allow forcing legacy scp protocol for reliability.
scp_legacy="${OREN_SCP_LEGACY:-1}"
scp_legacy_opt=()
if [[ -n "$scp_legacy" && "$scp_legacy" != "0" ]]; then
  scp_legacy_opt=(-O)
fi
scp_base=(scp -q -C "${scp_legacy_opt[@]}" "${scp_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

remote_preflight() {
  mkdir -p build/logs
  local logf="build/logs/native_net_remote_probe.log"

  log "== remote: ssh probe =="
  local attempt=1
  while true; do
    : >"$logf"
    set +e
    run_with_timeout 25 "${ssh_base[@]}" "cmd.exe /c \"echo OREN_REMOTE_OK\"" >"$logf" 2>&1
    local rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      if grep -q "OREN_REMOTE_OK" "$logf" 2>/dev/null; then
        log "OK: remote ssh probe"
        return 0
      fi
    fi

    if [[ "$attempt" -ge 5 ]]; then
      echo "ERROR: cannot reach remote x64 host via ssh (rc=$rc host=$REMOTE_HOST)" >&2
      tail -n 80 "$logf" >&2 2>/dev/null || true
      if grep -Eq 'socat\\[[0-9]+\\] W CONNECT .*:22: Not Found' "$logf" 2>/dev/null; then
        echo "HINT: ProxyCommand could not resolve the hostname. Try setting:" >&2
        echo "  OREN_REMOTE_X64_HOST=<user@IP>" >&2
        echo "or override OREN_REMOTE_X64_PROXY to a direct SSH connection (no proxy)." >&2
      fi
      if [[ "$REMOTE_HOST" == *"pc.work"* ]]; then
        echo "HINT: If 'pc.work' is not resolvable from this network, set:" >&2
        echo "  OREN_REMOTE_X64_HOST=<user@IP>" >&2
      fi
      echo "log=$logf" >&2
      exit 2
    fi

    echo "WARN: remote ssh probe failed (attempt ${attempt} rc=${rc}); retrying..." >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

remote_wsl_preflight() {
  if ! has_target x64-wsl; then
    return 0
  fi
  if [[ "$SKIP_REMOTE" -ne 0 ]]; then
    return 0
  fi
  mkdir -p build/logs
  local logf="build/logs/native_net_remote_wsl_probe.log"
  log "== remote: wsl probe =="
  : >"$logf"
  set +e
  run_with_timeout 15 "${ssh_base[@]}" "cmd.exe /c \"wsl.exe -e bash -lc \\\"echo OREN_WSL_OK\\\"\"" >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] && grep -q "OREN_WSL_OK" "$logf" 2>/dev/null; then
    log "OK: remote WSL probe"
    return 0
  fi
  echo "ERROR: remote WSL2 is not available (x64-wsl targets requested) host=$REMOTE_HOST" >&2
  tail -n 80 "$logf" >&2 2>/dev/null || true
  echo "HINT: install WSL on the remote host (wsl.exe --install) or run --targets x64-win only." >&2
  echo "log=$logf" >&2
  exit 3
}

remote_mkdir() {
  # IMPORTANT: `cmd.exe` can inherit a non-zero ERRORLEVEL under some ssh server setups.
  # Force success to avoid "false failures" when the directory already exists.
  "${ssh_base[@]}" "cmd.exe /c \"if not exist \\\"${remote_win_root_cmd}\\\" mkdir \\\"${remote_win_root_cmd}\\\" 2>nul & exit /b 0\""
}

remote_del() {
  local name="$1"
  "${ssh_base[@]}" "cmd.exe /c \"del /f /q \\\"${remote_win_root_cmd}\\\\${name}\\\" 2>nul\""
}

remote_ssh_retry() {
  local cmd="$1"
  local attempt=1
  local max_attempts=5
  while true; do
    set +e
    run_with_timeout 40 "${ssh_base[@]}" "$cmd"
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if [[ "$rc" -eq 255 || "$rc" -eq 143 ]]; then
      if [[ "$attempt" -ge "$max_attempts" ]]; then
        echo "ERROR: remote ssh command failed after ${attempt}/${max_attempts} attempts (rc=${rc})" >&2
        echo "cmd=${cmd}" >&2
        return "$rc"
      fi
      echo "WARN: remote ssh command transient failure (rc=${rc}) attempt ${attempt}/${max_attempts}; retrying..." >&2
      sleep "$attempt"
      attempt=$((attempt + 1))
      continue
    fi
    echo "ERROR: remote ssh command failed (rc=${rc})" >&2
    echo "cmd=${cmd}" >&2
    return "$rc"
  done
}

remote_kill_win() {
  local exe="$1"
  "${ssh_base[@]}" "cmd.exe /c \"taskkill /f /im ${exe} >nul 2>nul\""
}

remote_kill_wsl() {
  local exe="$1"
  "${ssh_base[@]}" "wsl.exe -e bash -lc \"pkill -9 -x '${exe}' >/dev/null 2>&1 || true\""
}

remote_upload() {
  local src="$1"
  local dst_name="$2"
  remote_del "$dst_name" >/dev/null 2>&1 || true

  local attempt=1
  while true; do
    set +e
    run_with_timeout "$SCP_TIMEOUT_SECS" "${scp_base[@]}" "$src" "${REMOTE_HOST}:${remote_unix_root}/${dst_name}"
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi

    if [[ "$attempt" -ge "$SCP_RETRIES" ]]; then
      echo "ERROR: scp failed after ${attempt}/${SCP_RETRIES} attempts: ${src} -> ${dst_name} (rc=${rc})" >&2
      return "$rc"
    fi

    echo "WARN: scp failed (attempt ${attempt}/${SCP_RETRIES}) rc=${rc}; retrying..." >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

remote_run_win() {
  local exe_name="$1"
  local extra_env="${2:-}"
  local attempt=1
  local max_attempts=3
  while true; do
    log ">> win: run ${exe_name} (attempt ${attempt}/${max_attempts})"
    remote_kill_win "$exe_name" >/dev/null 2>&1 || true
    local envp=""
    local canon_abort="${OREN_CANON_I32_ABORT:-}"
    if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
      envp="set OREN_CANON_I32_ABORT=1 & "
    fi
    if [[ -n "$WS_ECHO_N" ]]; then
      envp+="set OREN_WS_ECHO_N=${WS_ECHO_N} & "
    fi
    if [[ -n "$extra_env" ]]; then
      envp+="${extra_env} & "
    fi
    set +e
    run_with_timeout 40 "${ssh_base[@]}" "cmd.exe /v:on /c \"${envp}${remote_win_root_cmd}\\\\${exe_name} & set RC=!ERRORLEVEL! & echo EXIT=!RC! & exit /b !RC!\""
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    # Retry only when ssh/proxy is flaky (rc=255) or the outer timeout tripped (rc=143).
    if [[ "$rc" -eq 255 || "$rc" -eq 143 ]]; then
      log "WARN: win run transient ssh failure (rc=${rc}) for ${exe_name}; retrying..."
      remote_kill_win "$exe_name" >/dev/null 2>&1 || true
      if [[ "$attempt" -ge "$max_attempts" ]]; then
        log "!! win: ${exe_name} failed after ${attempt}/${max_attempts} attempts (ssh wrapper rc=${rc})"
        return "$rc"
      fi
      sleep "$attempt"
      attempt=$((attempt + 1))
      continue
    fi
    log "!! win: ${exe_name} failed (ssh wrapper rc=${rc})"
    remote_kill_win "$exe_name" >/dev/null 2>&1 || true
    return "$rc"
  done
}

remote_run_wsl() {
  local bin_name="$1"
  local attempt=1
  local max_attempts=3
  while true; do
    log ">> wsl: run ${bin_name} (attempt ${attempt}/${max_attempts})"
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
    local full="${remote_wsl_root}/${bin_name}"
    local envp=""
    local canon_abort="${OREN_CANON_I32_ABORT:-}"
    if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
      envp="OREN_CANON_I32_ABORT=1 "
    fi
    if [[ "$TRACE" -ne 0 ]]; then
      envp+="OREN_QI_TRACE=1 "
    fi
    if [[ -n "$WS_ECHO_N" ]]; then
      envp+="OREN_WS_ECHO_N=${WS_ECHO_N} "
    fi
    local cmd="file ${full} || true; chmod +x ${full} && ${envp}timeout 20s ${full}; rc="
    cmd+='$?'
    cmd+="; echo EXIT="
    cmd+='$rc'
    cmd+="; exit "
    cmd+='$rc'
    set +e
    run_with_timeout 40 "${ssh_base[@]}" "wsl.exe -e bash -lc \"${cmd}\""
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if [[ "$rc" -eq 255 || "$rc" -eq 143 ]]; then
      log "WARN: wsl run transient ssh failure (rc=${rc}) for ${bin_name}; retrying..."
      remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
      if [[ "$attempt" -ge "$max_attempts" ]]; then
        log "!! wsl: ${bin_name} failed after ${attempt}/${max_attempts} attempts (ssh wrapper rc=${rc})"
        return "$rc"
      fi
      sleep "$attempt"
      attempt=$((attempt + 1))
      continue
    fi
    log "!! wsl: ${bin_name} failed (ssh wrapper rc=${rc})"
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
    return "$rc"
  done
}

if has_target arm64-linux; then
  LINUX_DOCKER_ID="$(linux_docker_require_running "$LINUX_DOCKER_REF")"
  log "== verify: linux/arm64 via docker container id=${LINUX_DOCKER_ID} =="

  build_native_bin_src "./oren" "arm64-linux" "$NET_SUITE_SRC" "build/tmp/net_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$NET_SUITE_SRC" "build/tmp/net_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$WS_ECHO_SRC" "build/tmp/ws_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$WS_ECHO_SRC" "build/tmp/ws_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$WSS_ECHO_SRC" "build/tmp/wss_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$WSS_ECHO_SRC" "build/tmp/wss_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_arm64_linux"

  run_in_linux_container "build/tmp/net_stage1_arm64_linux"
  run_in_linux_container "build/tmp/net_stage2_arm64_linux"
  run_in_linux_container "build/tmp/dns_stage1_arm64_linux"
  run_in_linux_container "build/tmp/dns_stage2_arm64_linux"
  run_in_linux_container "build/tmp/http_stage1_arm64_linux"
  run_in_linux_container "build/tmp/http_stage2_arm64_linux"
  run_in_linux_container "build/tmp/https_stage1_arm64_linux"
  run_in_linux_container "build/tmp/https_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ws_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ws_stage2_arm64_linux"
  run_in_linux_container "build/tmp/wss_stage1_arm64_linux"
  run_in_linux_container "build/tmp/wss_stage2_arm64_linux"
  run_in_linux_container "build/tmp/tls_stage1_arm64_linux"
  run_in_linux_container "build/tmp/tls_stage2_arm64_linux"
  run_in_linux_container "build/tmp/http2_stage1_arm64_linux"
  run_in_linux_container "build/tmp/http2_stage2_arm64_linux"
  run_in_linux_container "build/tmp/hpack_stage1_arm64_linux"
  run_in_linux_container "build/tmp/hpack_stage2_arm64_linux"
  run_in_linux_container "build/tmp/http2_headers_stage1_arm64_linux"
  run_in_linux_container "build/tmp/http2_headers_stage2_arm64_linux"

  log "OK: linux/arm64 container"
fi

if [[ "$SKIP_REMOTE" -ne 0 ]]; then
  if [[ "$TARGETS_CSV" == "all" ]]; then
    log "SKIP: remote x64 Windows/WSL2 disabled by --skip-remote"
  fi
elif has_target x64-win || has_target x64-wsl; then
  log "== verify: remote x64 Windows + WSL2 via ${REMOTE_HOST} =="
  remote_preflight
  remote_mkdir
  remote_wsl_preflight
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-win; then
  build_native_bin_src "./oren" "x64-windows" "$NET_SUITE_SRC" "build/tmp/net_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$NET_SUITE_SRC" "build/tmp/net_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WS_ECHO_SRC" "build/tmp/ws_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WS_ECHO_SRC" "build/tmp/ws_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WSS_ECHO_SRC" "build/tmp/wss_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WSS_ECHO_SRC" "build/tmp/wss_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_x64_windows.exe"

  # Uploading 20+ artifacts via ProxyCommand can be flaky. Bundle into one tarball and extract on the remote host.
  win_tar_local="build/tmp/native_net_x64_win.tar"
  win_tar_remote="native_net_x64_win.tar"
  rm -f "$win_tar_local" 2>/dev/null || true
  tar -cf "$win_tar_local" -C build/tmp \
    net_stage1_x64_windows.exe net_stage2_x64_windows.exe \
    dns_stage1_x64_windows.exe dns_stage2_x64_windows.exe \
    http_stage1_x64_windows.exe http_stage2_x64_windows.exe \
    https_stage1_x64_windows.exe https_stage2_x64_windows.exe \
    ws_stage1_x64_windows.exe ws_stage2_x64_windows.exe \
    wss_stage1_x64_windows.exe wss_stage2_x64_windows.exe \
    tls_stage1_x64_windows.exe tls_stage2_x64_windows.exe \
    http2_stage1_x64_windows.exe http2_stage2_x64_windows.exe \
    hpack_stage1_x64_windows.exe hpack_stage2_x64_windows.exe \
    http2_headers_stage1_x64_windows.exe http2_headers_stage2_x64_windows.exe
  remote_upload "$win_tar_local" "$win_tar_remote"
  remote_ssh_retry "cmd.exe /v:on /c \"pushd ${remote_win_root_cmd} && tar -xf ${win_tar_remote} && popd\""

  log "-- run: Win11 (x64-windows) --"
  win_net_env="set OREN_NETPOLL_WIN_IOCP=1"
  if [[ -n "${OREN_NETPOLL_IOCP_DEBUG:-}" && "${OREN_NETPOLL_IOCP_DEBUG}" != "0" ]]; then
    win_net_env+=" & set OREN_NETPOLL_IOCP_DEBUG=1"
  fi
  remote_run_win "net_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "net_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "dns_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "dns_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "http_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "http_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "https_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "https_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "ws_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "ws_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "wss_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "wss_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "tls_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "tls_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "http2_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "http2_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "hpack_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "hpack_stage2_x64_windows.exe" "$win_net_env"
  remote_run_win "http2_headers_stage1_x64_windows.exe" "$win_net_env"
  remote_run_win "http2_headers_stage2_x64_windows.exe" "$win_net_env"
  log "OK: remote Win11 x64"
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-wsl; then
  build_native_bin_src "./oren" "x64-linux" "$NET_SUITE_SRC" "build/tmp/net_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$NET_SUITE_SRC" "build/tmp/net_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$WS_ECHO_SRC" "build/tmp/ws_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$WS_ECHO_SRC" "build/tmp/ws_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$WSS_ECHO_SRC" "build/tmp/wss_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$WSS_ECHO_SRC" "build/tmp/wss_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_x64_linux"

  # Same bundling strategy for WSL2 artifacts (keeps the remote gate reliable over ProxyCommand).
  wsl_tar_local="build/tmp/native_net_x64_wsl.tar"
  wsl_tar_remote="native_net_x64_wsl.tar"
  rm -f "$wsl_tar_local" 2>/dev/null || true
  tar -cf "$wsl_tar_local" -C build/tmp \
    net_stage1_x64_linux net_stage2_x64_linux \
    dns_stage1_x64_linux dns_stage2_x64_linux \
    http_stage1_x64_linux http_stage2_x64_linux \
    https_stage1_x64_linux https_stage2_x64_linux \
    ws_stage1_x64_linux ws_stage2_x64_linux \
    wss_stage1_x64_linux wss_stage2_x64_linux \
    tls_stage1_x64_linux tls_stage2_x64_linux \
    http2_stage1_x64_linux http2_stage2_x64_linux \
    hpack_stage1_x64_linux hpack_stage2_x64_linux \
    http2_headers_stage1_x64_linux http2_headers_stage2_x64_linux
  remote_upload "$wsl_tar_local" "$wsl_tar_remote"
  remote_ssh_retry "wsl.exe -e bash -lc \"tar -xf '${remote_wsl_root}/${wsl_tar_remote}' -C '${remote_wsl_root}' && chmod +x '${remote_wsl_root}'/*_x64_linux\""

  log "-- run: WSL2 (x64-linux) --"
  remote_run_wsl "net_stage1_x64_linux"
  remote_run_wsl "net_stage2_x64_linux"
  remote_run_wsl "dns_stage1_x64_linux"
  remote_run_wsl "dns_stage2_x64_linux"
  remote_run_wsl "http_stage1_x64_linux"
  remote_run_wsl "http_stage2_x64_linux"
  remote_run_wsl "https_stage1_x64_linux"
  remote_run_wsl "https_stage2_x64_linux"
  remote_run_wsl "ws_stage1_x64_linux"
  remote_run_wsl "ws_stage2_x64_linux"
  remote_run_wsl "wss_stage1_x64_linux"
  remote_run_wsl "wss_stage2_x64_linux"
  remote_run_wsl "tls_stage1_x64_linux"
  remote_run_wsl "tls_stage2_x64_linux"
  remote_run_wsl "http2_stage1_x64_linux"
  remote_run_wsl "http2_stage2_x64_linux"
  remote_run_wsl "hpack_stage1_x64_linux"
  remote_run_wsl "hpack_stage2_x64_linux"
  remote_run_wsl "http2_headers_stage1_x64_linux"
  remote_run_wsl "http2_headers_stage2_x64_linux"
  log "OK: remote WSL2 x64"
fi

log "ALL OK: native NET matrix verification passed"
