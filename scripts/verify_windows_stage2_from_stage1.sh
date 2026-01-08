#!/usr/bin/env bash
set -euo pipefail

# Stage0 → Stage1 → Stage2 bootstrap gate on native Windows (MSVC + native backend).
#
# Purpose:
# - Prove stage0 (Go) can build stage1 on x64-windows using VS2022 `cl.exe` (auto-configured).
# - Prove stage1 can build stage2 on Windows via the native backend (x64-windows PE output).
# - Prove the resulting stage2 can compile+run a tiny native program on Windows.
#
# Why this gate exists:
# - `scripts/verify_selfhost_x64_compiler.sh` proves a stage2 compiler binary can *run* on x86_64 hosts,
#   but it does not prove that stage1 can *produce* stage2 on native Windows.
# - Historically, native backend hangs/regressions showed up specifically in the “build the compiler” path.
#
# Keep logs bounded:
# - This script is a high-signal regression guard; it avoids dumping compiler logs unless a step fails.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"
REMOTE_DIR="${OREN_REMOTE_STAGE2_BOOTSTRAP_DIR:-tmp_oren/stage2_from_stage1}"

STAGE0_BUILD_TIMEOUT_SECS="${OREN_STAGE0_BUILD_TIMEOUT_SECS:-120}"
# Rolling performance intent: building stage2 (the compiler) on native Windows must stay bounded.
# Default timeout keeps regressions actionable; override via env if the remote host changes.
STAGE2_BUILD_TIMEOUT_SECS="${OREN_STAGE2_BUILD_TIMEOUT_SECS:-240}"
REMOTE_COMPILE_TIMEOUT_SECS="${OREN_STAGE2_REMOTE_COMPILE_TIMEOUT_SECS:-120}"
REMOTE_RUN_TIMEOUT_SECS="${OREN_STAGE2_REMOTE_RUN_TIMEOUT_SECS:-30}"
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
    if scp -q -o "$REMOTE_PROXY" "$src" "$dst"; then
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

log "== bundle: minimal sources for stage2 build =="
tar -czf build/tmp/stage2_src_bundle.tgz \
  oren.oren \
  lib \
  tests/native/print.oren

log "== remote: upload stage0 + bundle =="
scp_retry build/tmp/oren_bootstrap_win.exe "${REMOTE_HOST}:tmp_oren/oren_bootstrap_win.exe"
scp_retry build/tmp/stage2_src_bundle.tgz "${REMOTE_HOST}:tmp_oren/stage2_src_bundle.tgz"

log "== remote: extract bundle =="
ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\tmp_oren && (if exist ${REMOTE_DIR#tmp_oren/} rmdir /s /q ${REMOTE_DIR#tmp_oren/}) && mkdir ${REMOTE_DIR#tmp_oren/} && tar -xzf stage2_src_bundle.tgz -C ${REMOTE_DIR#tmp_oren/}\""

log "== remote: stage0 builds stage1 (MSVC cl.exe) =="
run_with_timeout "$STAGE0_BUILD_TIMEOUT_SECS" \
  ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
  "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && ..\\\\oren_bootstrap_win.exe build oren.oren --target windows --cc cl -o oren_stage1.exe\""

log "== remote: stage1 builds stage2 (native backend; x64-windows PE) =="
stage2_log="stage1_build_stage2.log"
set +e
run_with_timeout "$STAGE2_BUILD_TIMEOUT_SECS" \
  ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
  "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && (oren_stage1.exe build oren.oren --backend native --platform x64-windows --no-debug -o oren_stage2.exe > ${stage2_log} 2>&1)\""
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: stage1->stage2 build failed or timed out (timeout=${STAGE2_BUILD_TIMEOUT_SECS}s); tailing ${stage2_log}:" >&2
  # PowerShell is present on modern Windows; use tail to avoid huge logs.
  ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
    "powershell -NoProfile -Command \"Set-Location -LiteralPath '%USERPROFILE%\\\\${REMOTE_DIR//\//\\\\}'; if (Test-Path -LiteralPath '${stage2_log}') { Get-Content -LiteralPath '${stage2_log}' -Tail 120 } else { Write-Host 'missing log: ${stage2_log}' }\""
  exit "$rc"
fi

# Fail fast on known x64-native backend correctness warnings (even if the compiler exits 0).
# Use PowerShell to avoid cmd.exe quoting pitfalls around patterns with spaces.
ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
  "powershell -NoProfile -Command \"Set-Location -LiteralPath '%USERPROFILE%\\\\${REMOTE_DIR//\//\\\\}'; if (!(Test-Path -LiteralPath '${stage2_log}')) { Write-Host 'missing log: ${stage2_log}'; exit 2 }; if (Select-String -LiteralPath '${stage2_log}' -SimpleMatch -Pattern 'x64 native v0: missing ABI arg reg') { Write-Host 'ERROR: ABI arg-reg warnings found in stage1->stage2 build log'; Select-String -LiteralPath '${stage2_log}' -SimpleMatch -Pattern 'x64 native v0: missing ABI arg reg' | Select-Object -First 20; exit 3 }\""

log "== remote: stage2 builds a tiny native exe (guard: canon i32) =="
run_with_timeout "$REMOTE_COMPILE_TIMEOUT_SECS" \
  ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
  "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && set OREN_CANON_I32_ABORT=1&& oren_stage2.exe build tests\\\\native\\\\print.oren --backend native --no-cache --no-debug -o print_stage2_native.exe\""

log "== remote: run the produced exe =="
out="$(
  run_with_timeout "$REMOTE_RUN_TIMEOUT_SECS" \
    ssh -o "$REMOTE_PROXY" "$REMOTE_HOST" \
    "cmd.exe /v:on /c \"cd %USERPROFILE%\\\\${REMOTE_DIR//\//\\\\} && set OREN_CANON_I32_ABORT=1&& print_stage2_native.exe & echo EXIT=!ERRORLEVEL!\""
)"
out="$(printf '%s' "$out" | tr -d '\r')"
printf '%s\n' "$out"
echo "$out" | grep -qF "hello from native"
echo "$out" | grep -qF "EXIT=0"

log "OK: stage0->stage1->stage2 self-host build works on x64-windows"
