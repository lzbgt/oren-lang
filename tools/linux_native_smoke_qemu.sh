#!/usr/bin/env bash
set -euo pipefail

# Linux native smoke runner (trusted QEMU host).
#
# This script:
# - builds linux/arm64 native binaries on macOS using `./oren --target linux`
# - copies them to a trusted Linux arm64 host via ssh/scp
# - runs them under a timeout on the remote
#
# Assumptions:
# - Remote host is Linux aarch64 and can run the produced ELF binaries.
# - Remote host has `timeout` installed (coreutils). If not, install it or adjust.
#
# Config:
#   OREN_QEMU_HOST : ssh target (default: blu@qemu-blu.local)
#   OREN_QEMU_DIR  : remote directory (default: /tmp/oren-linux-smoke)
#   OREN_QEMU_TIMEOUT_SECS : per-binary run timeout (default: 10)
#   OREN_QEMU_RETRIES : ssh/scp retry attempts (default: 30)
#   OREN_QEMU_RETRY_SLEEP_SECS : seconds between retries (default: 1)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HOST="${OREN_QEMU_HOST:-blu@qemu-blu.local}"
REMOTE_DIR="${OREN_QEMU_DIR:-/tmp/oren-linux-smoke}"
TIMEOUT_SECS="${OREN_QEMU_TIMEOUT_SECS:-10}"
RETRIES="${OREN_QEMU_RETRIES:-30}"
RETRY_SLEEP_SECS="${OREN_QEMU_RETRY_SLEEP_SECS:-1}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
)

echo "[linux-smoke] host=$HOST dir=$REMOTE_DIR timeout=${TIMEOUT_SECS}s"

make -s oren

mkdir -p build/linux-smoke

ssh_retry() {
  local attempt=1
  while true; do
    ssh "${SSH_OPTS[@]}" "$@"
    local rc=$?
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    # Only retry on SSH transport failures (OpenSSH uses 255 for these).
    # If the remote command ran but failed (rc != 0 and rc != 255), surface it immediately.
    if [[ "$rc" -ne 255 ]]; then
      return "$rc"
    fi
    if [[ "$attempt" -ge "$RETRIES" ]]; then
      echo "[linux-smoke] FAIL: ssh retries exhausted ($RETRIES)"
      return 1
    fi
    echo "[linux-smoke] ssh retry $attempt/$RETRIES..."
    sleep "$RETRY_SLEEP_SECS"
    attempt=$((attempt + 1))
  done
}

scp_retry() {
  local attempt=1
  while true; do
    scp -q "${SSH_OPTS[@]}" "$@"
    local rc=$?
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    # scp also uses 255 for SSH transport failures.
    if [[ "$rc" -ne 255 ]]; then
      return "$rc"
    fi
    if [[ "$attempt" -ge "$RETRIES" ]]; then
      echo "[linux-smoke] FAIL: scp retries exhausted ($RETRIES)"
      return 1
    fi
    echo "[linux-smoke] scp retry $attempt/$RETRIES..."
    sleep "$RETRY_SLEEP_SECS"
    attempt=$((attempt + 1))
  done
}

SMOKE_TESTS=(
  tests/native/add.oren
  tests/native/print.oren
  tests/native/test_bool_bit_ops.oren
  tests/native/test_env_execve_getenv.oren
  tests/native/test_for_break_continue.oren
  tests/native/test_for_in_list.oren
  tests/native/test_for_in_string.oren
  tests/native/test_spawn_simple.oren
  tests/native/test_spawn_args.oren
  tools/bench/test_linux_tcp_loopback_fork.oren
)

echo "[linux-smoke] building ${#SMOKE_TESTS[@]} linux binaries..."
for t in "${SMOKE_TESTS[@]}"; do
  name="$(basename "$t" .oren)"
  out="build/linux-smoke/$name"
  ./oren build "$t" --backend native --target linux -o "$out"
  file "$out" | grep -q "ELF" || { echo "[linux-smoke] FAIL: $out is not ELF"; exit 1; }
done

echo "[linux-smoke] uploading to $HOST..."
ssh_retry "$HOST" "mkdir -p '$REMOTE_DIR' && (command -v timeout >/dev/null 2>&1 || { echo 'remote missing: timeout'; exit 2; })"
scp_retry build/linux-smoke/* "$HOST:$REMOTE_DIR/"

echo "[linux-smoke] running on $HOST..."
for t in "${SMOKE_TESTS[@]}"; do
  name="$(basename "$t" .oren)"
  echo "[linux-smoke] run $name"
  ssh_retry "$HOST" "cd '$REMOTE_DIR' && timeout '${TIMEOUT_SECS}s' './$name'"
done

echo "[linux-smoke] OK"
