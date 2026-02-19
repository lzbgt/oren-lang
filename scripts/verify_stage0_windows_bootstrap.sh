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
SCP_TIMEOUT_SECS="${OREN_REMOTE_SCP_TIMEOUT_SECS:-120}"

log() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage:
  scripts/verify_stage0_windows_bootstrap.sh [--host <user@host>] [--proxy <ssh_opt>] [--no-proxy]

Env overrides:
  OREN_REMOTE_X64_HOST   (default: lzbgt@pc.work)
  OREN_REMOTE_X64_PROXY  (default: ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002)
  OREN_REMOTE_STAGE0_BOOTSTRAP_DIR (default: tmp_oren/stage0_bootstrap)
  OREN_REMOTE_X64_WIN_ROOT (default: C:\Users\<user>\tmp_oren) remote Windows staging root
  OREN_REMOTE_X64_SSH_ROOT (default: tmp_oren) scp/sftp staging root (Windows OpenSSH path)
  OREN_REMOTE_SCP_TIMEOUT_SECS (default: 120)
EOF
}

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
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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
remote_dir_rel="${REMOTE_DIR}"
remote_dir_rel="${remote_dir_rel#tmp_oren/}"
remote_dir_rel="${remote_dir_rel#tmp_oren\\}"
remote_dir_win="${remote_win_root_cmd}\\${remote_dir_rel//\//\\}"

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
need_bin tar
need_bin grep
if [[ -n "$REMOTE_PROXY" ]] && [[ "$REMOTE_PROXY" == *socat* ]]; then
  need_bin socat
fi

mkdir -p build/tmp build/logs

ssh_opt_proxy=()
scp_opt_proxy=()
if [[ -n "$REMOTE_PROXY" ]]; then
  ssh_opt_proxy=(-o "$REMOTE_PROXY")
  scp_opt_proxy=(-o "$REMOTE_PROXY")
fi

SSH=(ssh "${ssh_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 "$REMOTE_HOST")
SCP=(scp -q "${scp_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

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

scp_retry() {
  local src="$1"
  local dst="$2"
  local i=1
  while true; do
    if run_with_timeout "$SCP_TIMEOUT_SECS" "${SCP[@]}" "$src" "$dst"; then
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

remote_preflight() {
  local logf="build/logs/stage0_windows_bootstrap_remote_probe.log"
  log "== remote: ssh probe =="
  local attempt=1
  while true; do
    : >"$logf"
    set +e
    run_with_timeout 15 "${SSH[@]}" "cmd.exe /c \"echo OREN_REMOTE_OK\"" >"$logf" 2>&1
    local rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      if grep -q "OREN_REMOTE_OK" "$logf" 2>/dev/null; then
        return 0
      fi
    fi

    if [[ "$attempt" -ge 2 ]]; then
      echo "ERROR: cannot reach remote Win11 host via ssh (rc=$rc host=$REMOTE_HOST)" >&2
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

remote_preflight

log "== build: stage0 bootstrap (windows/amd64) =="
GOOS=windows GOARCH=amd64 go build -o build/tmp/oren_bootstrap_win.exe ./cmd/oren

log "== bundle: minimal sources for stage1 build =="
tar -czf build/tmp/stage0_src_bundle.tgz \
  oren.oren \
  lib \
  tests/native/print.oren

log "== remote: upload stage0 + bundle =="
scp_retry build/tmp/oren_bootstrap_win.exe "${REMOTE_HOST}:${remote_unix_root}/oren_bootstrap_win.exe"
scp_retry build/tmp/stage0_src_bundle.tgz "${REMOTE_HOST}:${remote_unix_root}/stage0_src_bundle.tgz"

log "== remote: extract bundle =="
"${SSH[@]}" "cmd.exe /v:on /c \"cd ${remote_win_root_cmd} && (if exist ${remote_dir_rel//\//\\\\} rmdir /s /q ${remote_dir_rel//\//\\\\}) && mkdir ${remote_dir_rel//\//\\\\} && tar -xzf stage0_src_bundle.tgz -C ${remote_dir_rel//\//\\\\}\""

log "== remote: stage0 builds stage1 (MSVC cl.exe) =="
run_with_timeout "$STAGE0_BUILD_TIMEOUT_SECS" "${SSH[@]}" "cmd.exe /v:on /c \"cd ${remote_dir_win} && ..\\\\oren_bootstrap_win.exe build oren.oren --target windows --cc cl -o oren_stage1.exe\""

log "== remote: stage1 builds a tiny native exe =="
run_with_timeout "$STAGE1_BUILD_TIMEOUT_SECS" "${SSH[@]}" "cmd.exe /v:on /c \"cd ${remote_dir_win} && oren_stage1.exe build tests\\\\native\\\\print.oren --backend native --no-cache --no-debug -o print_stage1_native.exe\""

log "== remote: run the produced exe =="
out="$(
  run_with_timeout "$REMOTE_RUN_TIMEOUT_SECS" "${SSH[@]}" "cmd.exe /v:on /c \"${remote_dir_win}\\\\print_stage1_native.exe\""
)"
out="$(printf '%s' "$out" | tr -d '\r')"
printf '%s\n' "$out"
echo "$out" | grep -qF "hello from native"

log "OK: stage0->stage1 MSVC bootstrap works on x64-windows"
