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
# - arm64-macos (runs locally)
# - arm64-linux (runs in the persistent container)
# - x64-linux (runs under remote WSL2)
# - x64-windows (runs on remote Win11)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

LINUX_DOCKER_ID="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
BUILD_TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"
SCP_RETRIES="${OREN_REMOTE_SCP_RETRIES:-3}"
WS_ECHO_N="${OREN_WS_ECHO_N:-}"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

usage() {
  cat <<'EOF'
Usage: scripts/verify_native_net_matrix.sh [--targets <csv>] [--local-only]
       scripts/verify_native_net_matrix.sh [--targets <csv>] [--trace]

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
  local       run local arm64-macos (stage1 + stage2)
  arm64-linux run linux/arm64 in docker container
  x64-win     run x64-windows on remote Win11
  x64-wsl     run x64-linux under remote WSL2

Examples:
  ./scripts/verify_native_net_matrix.sh
  ./scripts/verify_native_net_matrix.sh --targets local
  ./scripts/verify_native_net_matrix.sh --targets arm64-linux
  ./scripts/verify_native_net_matrix.sh --targets x64-win,x64-wsl

Env overrides:
  OREN_LINUX_DOCKER_ID   (default: c7e5f7bd9f5c)
  OREN_NATIVE_BUILD_TIMEOUT_SECS (default: 10) timeout for each `oren build ...` step (rolling hang guard)
  OREN_REMOTE_X64_HOST   (default: lzbgt@pc.work)
  OREN_REMOTE_X64_PROXY  (default: ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002)
  OREN_WS_ECHO_N         (optional) run ws echo loop N times (stress)
  OREN_CANON_I32_ABORT   (optional) set to 1 to hard-fail on non-canonical i32 values on all targets
EOF
}

LOCAL_ONLY=0
TARGETS_CSV="all"
TRACE=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=1
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
  if has_target x64-win || has_target x64-wsl; then
    need_bin ssh
    need_bin scp
    need_bin socat
  fi
fi

run_with_timeout() {
  local secs="$1"
  shift
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
  set -e
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
  run_with_timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform "$platform" --debug -o "$out" >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform src=$src timeout=${BUILD_TIMEOUT_SECS}s" >&2
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
  log "== verify: local arm64-macos (stage1 + stage2) =="

  build_native_bin_src "./oren" "arm64-macos" "$NET_SUITE_SRC" "build/tmp/net_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$NET_SUITE_SRC" "build/tmp/net_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$DNS_LOOPBACK_SRC" "build/tmp/dns_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$HTTP_LOOPBACK_SRC" "build/tmp/http_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$WS_ECHO_SRC" "build/tmp/ws_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$WS_ECHO_SRC" "build/tmp/ws_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$WSS_ECHO_SRC" "build/tmp/wss_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$WSS_ECHO_SRC" "build/tmp/wss_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$TLS_LOOPBACK_SRC" "build/tmp/tls_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$HPACK_SMOKE_SRC" "build/tmp/hpack_stage2_arm64_macos"
  build_native_bin_src "./oren" "arm64-macos" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_arm64_macos"
  build_native_bin_src "./oren_stage2" "arm64-macos" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_arm64_macos"

  run_local_bin "build/tmp/net_stage1_arm64_macos"
  run_local_bin "build/tmp/net_stage2_arm64_macos"
  run_local_bin "build/tmp/dns_stage1_arm64_macos"
  run_local_bin "build/tmp/dns_stage2_arm64_macos"
  run_local_bin "build/tmp/http_stage1_arm64_macos"
  run_local_bin "build/tmp/http_stage2_arm64_macos"
  run_local_bin "build/tmp/https_stage1_arm64_macos"
  run_local_bin "build/tmp/https_stage2_arm64_macos"
  run_local_bin "build/tmp/ws_stage1_arm64_macos"
  run_local_bin "build/tmp/ws_stage2_arm64_macos"
  run_local_bin "build/tmp/wss_stage1_arm64_macos"
  run_local_bin "build/tmp/wss_stage2_arm64_macos"
  run_local_bin "build/tmp/tls_stage1_arm64_macos"
  run_local_bin "build/tmp/tls_stage2_arm64_macos"
  run_local_bin "build/tmp/http2_stage1_arm64_macos"
  run_local_bin "build/tmp/http2_stage2_arm64_macos"
  run_local_bin "build/tmp/hpack_stage1_arm64_macos"
  run_local_bin "build/tmp/hpack_stage2_arm64_macos"
  run_local_bin "build/tmp/http2_headers_stage1_arm64_macos"
  run_local_bin "build/tmp/http2_headers_stage2_arm64_macos"

  log "OK: local arm64-macos"
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
remote_unix_root="tmp_oren"
remote_win_root="C:\\Users\\${remote_user}\\tmp_oren"
remote_wsl_root="/mnt/c/Users/${remote_user}/tmp_oren"

ssh_base=(ssh -o "$REMOTE_PROXY" "$REMOTE_HOST")
scp_base=(scp -q -o "$REMOTE_PROXY")

remote_mkdir() {
  "${ssh_base[@]}" 'cmd.exe /c "if not exist %USERPROFILE%\\tmp_oren mkdir %USERPROFILE%\\tmp_oren"'
}

remote_del() {
  local name="$1"
  "${ssh_base[@]}" "cmd.exe /c \"del /f /q %USERPROFILE%\\\\tmp_oren\\\\${name} 2>nul\""
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
    "${scp_base[@]}" "$src" "${REMOTE_HOST}:${remote_unix_root}/${dst_name}"
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
  remote_kill_win "$exe_name" >/dev/null 2>&1 || true
  local envp=""
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    envp="set OREN_CANON_I32_ABORT=1 & "
  fi
  if [[ -n "$WS_ECHO_N" ]]; then
    envp+="set OREN_WS_ECHO_N=${WS_ECHO_N} & "
  fi
  set +e
  run_with_timeout 40 "${ssh_base[@]}" "cmd.exe /v:on /c \"${envp}${remote_win_root}\\\\${exe_name} & set RC=!ERRORLEVEL! & echo EXIT=!RC! & exit /b !RC!\""
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_win "$exe_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

remote_run_wsl() {
  local bin_name="$1"
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
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

if has_target arm64-linux; then
  log "== verify: linux/arm64 via docker container id=${LINUX_DOCKER_ID} =="
  docker ps --filter "id=${LINUX_DOCKER_ID}" --format 'id={{.ID}} status={{.Status}}' | grep -q "id=${LINUX_DOCKER_ID}" || {
    echo "ERROR: required persistent container not running: ${LINUX_DOCKER_ID}" >&2
    exit 2
  }

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

if has_target x64-win || has_target x64-wsl; then
  log "== verify: remote x64 Windows + WSL2 via ${REMOTE_HOST} =="
  remote_mkdir
fi

if has_target x64-win; then
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

  remote_upload "build/tmp/net_stage1_x64_windows.exe" "net_stage1_x64_windows.exe"
  remote_upload "build/tmp/net_stage2_x64_windows.exe" "net_stage2_x64_windows.exe"
  remote_upload "build/tmp/dns_stage1_x64_windows.exe" "dns_stage1_x64_windows.exe"
  remote_upload "build/tmp/dns_stage2_x64_windows.exe" "dns_stage2_x64_windows.exe"
  remote_upload "build/tmp/http_stage1_x64_windows.exe" "http_stage1_x64_windows.exe"
  remote_upload "build/tmp/http_stage2_x64_windows.exe" "http_stage2_x64_windows.exe"
  remote_upload "build/tmp/https_stage1_x64_windows.exe" "https_stage1_x64_windows.exe"
  remote_upload "build/tmp/https_stage2_x64_windows.exe" "https_stage2_x64_windows.exe"
  remote_upload "build/tmp/ws_stage1_x64_windows.exe" "ws_stage1_x64_windows.exe"
  remote_upload "build/tmp/ws_stage2_x64_windows.exe" "ws_stage2_x64_windows.exe"
  remote_upload "build/tmp/wss_stage1_x64_windows.exe" "wss_stage1_x64_windows.exe"
  remote_upload "build/tmp/wss_stage2_x64_windows.exe" "wss_stage2_x64_windows.exe"
  remote_upload "build/tmp/tls_stage1_x64_windows.exe" "tls_stage1_x64_windows.exe"
  remote_upload "build/tmp/tls_stage2_x64_windows.exe" "tls_stage2_x64_windows.exe"
  remote_upload "build/tmp/http2_stage1_x64_windows.exe" "http2_stage1_x64_windows.exe"
  remote_upload "build/tmp/http2_stage2_x64_windows.exe" "http2_stage2_x64_windows.exe"
  remote_upload "build/tmp/hpack_stage1_x64_windows.exe" "hpack_stage1_x64_windows.exe"
  remote_upload "build/tmp/hpack_stage2_x64_windows.exe" "hpack_stage2_x64_windows.exe"
  remote_upload "build/tmp/http2_headers_stage1_x64_windows.exe" "http2_headers_stage1_x64_windows.exe"
  remote_upload "build/tmp/http2_headers_stage2_x64_windows.exe" "http2_headers_stage2_x64_windows.exe"

  log "-- run: Win11 (x64-windows) --"
  remote_run_win "net_stage1_x64_windows.exe"
  remote_run_win "net_stage2_x64_windows.exe"
  remote_run_win "dns_stage1_x64_windows.exe"
  remote_run_win "dns_stage2_x64_windows.exe"
  remote_run_win "http_stage1_x64_windows.exe"
  remote_run_win "http_stage2_x64_windows.exe"
  remote_run_win "https_stage1_x64_windows.exe"
  remote_run_win "https_stage2_x64_windows.exe"
  remote_run_win "ws_stage1_x64_windows.exe"
  remote_run_win "ws_stage2_x64_windows.exe"
  remote_run_win "wss_stage1_x64_windows.exe"
  remote_run_win "wss_stage2_x64_windows.exe"
  remote_run_win "tls_stage1_x64_windows.exe"
  remote_run_win "tls_stage2_x64_windows.exe"
  remote_run_win "http2_stage1_x64_windows.exe"
  remote_run_win "http2_stage2_x64_windows.exe"
  remote_run_win "hpack_stage1_x64_windows.exe"
  remote_run_win "hpack_stage2_x64_windows.exe"
  remote_run_win "http2_headers_stage1_x64_windows.exe"
  remote_run_win "http2_headers_stage2_x64_windows.exe"
  log "OK: remote Win11 x64"
fi

if has_target x64-wsl; then
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

  remote_upload "build/tmp/net_stage1_x64_linux" "net_stage1_x64_linux"
  remote_upload "build/tmp/net_stage2_x64_linux" "net_stage2_x64_linux"
  remote_upload "build/tmp/dns_stage1_x64_linux" "dns_stage1_x64_linux"
  remote_upload "build/tmp/dns_stage2_x64_linux" "dns_stage2_x64_linux"
  remote_upload "build/tmp/http_stage1_x64_linux" "http_stage1_x64_linux"
  remote_upload "build/tmp/http_stage2_x64_linux" "http_stage2_x64_linux"
  remote_upload "build/tmp/https_stage1_x64_linux" "https_stage1_x64_linux"
  remote_upload "build/tmp/https_stage2_x64_linux" "https_stage2_x64_linux"
  remote_upload "build/tmp/ws_stage1_x64_linux" "ws_stage1_x64_linux"
  remote_upload "build/tmp/ws_stage2_x64_linux" "ws_stage2_x64_linux"
  remote_upload "build/tmp/wss_stage1_x64_linux" "wss_stage1_x64_linux"
  remote_upload "build/tmp/wss_stage2_x64_linux" "wss_stage2_x64_linux"
  remote_upload "build/tmp/tls_stage1_x64_linux" "tls_stage1_x64_linux"
  remote_upload "build/tmp/tls_stage2_x64_linux" "tls_stage2_x64_linux"
  remote_upload "build/tmp/http2_stage1_x64_linux" "http2_stage1_x64_linux"
  remote_upload "build/tmp/http2_stage2_x64_linux" "http2_stage2_x64_linux"
  remote_upload "build/tmp/hpack_stage1_x64_linux" "hpack_stage1_x64_linux"
  remote_upload "build/tmp/hpack_stage2_x64_linux" "hpack_stage2_x64_linux"
  remote_upload "build/tmp/http2_headers_stage1_x64_linux" "http2_headers_stage1_x64_linux"
  remote_upload "build/tmp/http2_headers_stage2_x64_linux" "http2_headers_stage2_x64_linux"

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
