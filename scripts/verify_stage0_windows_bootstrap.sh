#!/usr/bin/env bash
set -euo pipefail

# Stage0 → Stage1 bootstrap gate on native Windows (MSVC).
#
# Purpose:
# - Prove the Go bootstrap compiler (stage0) can build the stage1 compiler on x64-windows using
#   VS2022 `cl.exe` (auto-configured via vswhere + VsDevCmd/vcvars).
# - Prove the resulting stage1 executable can run on Windows and compile+run a tiny native program.
#
# This is intentionally a small, high-signal regression guard. It avoids huge logs and does not
# attempt a full stage2 build on Windows.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"
REMOTE_DIR="${OREN_REMOTE_STAGE0_BOOTSTRAP_DIR:-tmp_oren/stage0_bootstrap}"

STAGE0_BUILD_TIMEOUT_SECS="${OREN_STAGE0_BUILD_TIMEOUT_SECS:-120}"
STAGE1_BUILD_TIMEOUT_SECS="${OREN_STAGE1_BUILD_TIMEOUT_SECS:-120}"
REMOTE_RUN_TIMEOUT_SECS="${OREN_STAGE1_REMOTE_RUN_TIMEOUT_SECS:-30}"
SCP_RETRIES="${OREN_REMOTE_SCP_RETRIES:-3}"

log() { printf '%s\n' "$*"; }

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin go
need_bin ssh
need_bin scp
need_bin socat
need_bin tar

mkdir -p build/tmp

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

scp_retry() {
  local src="$1"
  local dst="$2"
  local i=1
  while true; do
    if scp -o "$REMOTE_PROXY" "$src" "$dst"; then
      return 0
    fi
    if [[ "$i" -ge "$SCP_RETRIES" ]]; then
      echo "ERROR: scp failed after ${SCP_RETRIES} attempts: $src -> $dst" >&2
      return 1
    fi
    i=$((i + 1))
    sleep 1
  done
}

log "== build: stage0 bootstrap (windows/amd64) =="
GOOS=windows GOARCH=amd64 go build -o build/tmp/oren_bootstrap_win.exe ./cmd/oren

log "== bundle: minimal sources for stage1 build =="
tar -czf build/tmp/stage0_src_bundle.tgz \
  oren.oren \
  lib \
  tests/native/print.oren

log "== remote: upload stage0 + bundle =="
scp_retry build/tmp/oren_bootstrap_win.exe "${REMOTE_HOST}:tmp_oren/oren_bootstrap_win.exe"
scp_retry build/tmp/stage0_src_bundle.tgz "${REMOTE_HOST}:tmp_oren/stage0_src_bundle.tgz"

log "== remote: extract bundle =="
ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\tmp_oren && (if exist ${REMOTE_DIR#tmp_oren/} rmdir /s /q ${REMOTE_DIR#tmp_oren/}) && mkdir ${REMOTE_DIR#tmp_oren/} && tar -xzf stage0_src_bundle.tgz -C ${REMOTE_DIR#tmp_oren/}\""

log "== remote: stage0 builds stage1 (MSVC cl.exe) =="
run_with_timeout "$STAGE0_BUILD_TIMEOUT_SECS" ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && ..\\\\oren_bootstrap_win.exe build oren.oren --target windows --cc cl -o oren_stage1.exe\""

log "== remote: stage1 builds a tiny native exe =="
run_with_timeout "$STAGE1_BUILD_TIMEOUT_SECS" ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && oren_stage1.exe build tests\\\\native\\\\print.oren --backend native --no-cache --no-debug -o print_stage1_native.exe\""

log "== remote: run the produced exe =="
out="$(
  run_with_timeout "$REMOTE_RUN_TIMEOUT_SECS" ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" "cmd.exe /v:on /c \"%USERPROFILE%\\\\${REMOTE_DIR//\//\\\\}\\\\print_stage1_native.exe\""
)"
out="$(printf '%s' "$out" | tr -d '\r')"
printf '%s\n' "$out"
echo "$out" | grep -qF "hello from native"

log "OK: stage0->stage1 MSVC bootstrap works on x64-windows"

