#!/usr/bin/env bash
set -euo pipefail

# Verify `.obc` portability across AVM builds (rolling).
#
# Goal:
# - `.obc` is an AVM artifact (platform-neutral intent).
# - The same `.obc` should execute with identical RESULT_HASH/TRACE_HASH on:
#   - macOS arm64 (host)
#   - linux/arm64 (docker container)
#   - linux/x86_64 (WSL2 on remote Win11 host)
#
# This script is intentionally integration-style: it uses the real toolchain to
# compile a known integrated Oren program, then runs it on multiple AVM builds.
#
# Inputs:
# - OREN_LINUX_DOCKER_IMAGE (default: ubuntu:24.04)
# - OREN_LINUX_DOCKER_NAME  (default: oren-linux-oretest)
# - OREN_REMOTE_X64_HOST    (default: lzbgt@pc.work)
# - OREN_REMOTE_X64_PROXY   (default: "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002")
#
# Notes:
# - The linux docker container must be linux/arm64 on an arm64 host (Apple Silicon).
# - The remote host must have WSL2 + gcc + make installed.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="build/tmp/obc_portability"
mkdir -p "$OUT_DIR"

TIMEOUT_BIN="${OREN_TIMEOUT_BIN:-}"
if [[ -z "$TIMEOUT_BIN" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
  fi
fi

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$TIMEOUT_BIN" ]]; then
    # -k 2: allow a short grace period before hard kill.
    "$TIMEOUT_BIN" -k 2 "$secs" "$@"
  else
    "$@"
  fi
}

OB_SRC="tests/avm/test_smoke_suite.oren"
OB_OBC="$OUT_DIR/test_smoke_suite.obc"
OB_SHA="$OUT_DIR/obc.sha256"

echo "[obc-portability] building OBC: $OB_SRC"
./oren build "$OB_SRC" --backend bytecode -o "$OB_OBC" >/dev/null

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$OB_OBC" | tee "$OB_SHA" >/dev/null
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OB_OBC" | tee "$OB_SHA" >/dev/null
else
  echo "ERROR: need shasum or sha256sum" >&2
  exit 2
fi

extract_hashes() {
  local f="$1"
  local r t
  r="$(grep -E '^RESULT_HASH ' "$f" | tail -n 1 | awk '{print $2}')"
  t="$(grep -E '^TRACE_HASH ' "$f"  | tail -n 1 | awk '{print $2}')"
  if [[ -z "$r" || -z "$t" ]]; then
    echo "ERROR: missing RESULT_HASH/TRACE_HASH in $f" >&2
    exit 2
  fi
  printf '%s %s\n' "$r" "$t"
}

echo "[obc-portability] run: macOS host AVM"
./avm --print-result-hash --print-trace-hash "$OB_OBC" | tee "$OUT_DIR/mac_arm64.out" >/dev/null
MAC_HASHES="$(extract_hashes "$OUT_DIR/mac_arm64.out")"
echo "[obc-portability] mac RESULT/TRACE: $MAC_HASHES"

echo "[obc-portability] run: linux/arm64 docker AVM"
IMAGE="${OREN_LINUX_DOCKER_IMAGE:-ubuntu:24.04}"
NAME="${OREN_LINUX_DOCKER_NAME:-oren-linux-oretest}"

# Create a persistent container if missing.
if ! docker inspect "$NAME" >/dev/null 2>&1; then
  docker create --name "$NAME" --init --platform linux/arm64 -v "$PWD:/repo:ro" "$IMAGE" bash -lc 'sleep infinity' >/dev/null
fi
docker start "$NAME" >/dev/null || true

# Sync tracked sources into /work/repo so the container's AVM matches the host repo.
git ls-files -z | tar -czf - --null -T - | docker exec -i "$NAME" bash -lc 'set -euo pipefail; rm -rf /work/repo/*; mkdir -p /work/repo; tar -xzf - -C /work/repo'

# Rebuild avm (fast; avoids running the full test suite).
DOCKER_TIMEOUT_SECS="${OREN_DOCKER_TIMEOUT_SECS:-600}"
run_with_timeout "$DOCKER_TIMEOUT_SECS" docker exec "$NAME" bash -lc 'set -euo pipefail; cd /work/repo; rm -f ./avm; make avm CC=gcc >/dev/null'
run_with_timeout "$DOCKER_TIMEOUT_SECS" docker exec "$NAME" bash -lc "set -euo pipefail; cd /work/repo; ./avm --print-result-hash --print-trace-hash /repo/$OB_OBC" \
  | tee "$OUT_DIR/linux_docker_arm64.out" >/dev/null
LINUX_HASHES="$(extract_hashes "$OUT_DIR/linux_docker_arm64.out")"
echo "[obc-portability] linux/arm64 RESULT/TRACE: $LINUX_HASHES"

echo "[obc-portability] run: linux/x86_64 (WSL2) AVM"
REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

SSH=(ssh -o "$REMOTE_PROXY" "$REMOTE_HOST")
SCP=(scp -o "$REMOTE_PROXY")

REMOTE_UNIX_ROOT="${OREN_REMOTE_X64_UNIX_ROOT:-/Users/lzbgt/tmp_oren}"
REMOTE_SUBDIR="obc_portability"

echo "[obc-portability] remote mkdir"
REMOTE_TIMEOUT_SECS="${OREN_REMOTE_TIMEOUT_SECS:-600}"
REMOTE_WSL_TIMEOUT_SECS="${OREN_REMOTE_WSL_TIMEOUT_SECS:-900}"
run_with_timeout "$REMOTE_TIMEOUT_SECS" "${SSH[@]}" 'cmd.exe /c "if not exist %USERPROFILE%\\tmp_oren\\obc_portability mkdir %USERPROFILE%\\tmp_oren\\obc_portability"' >/dev/null

# Ship the same `.obc` and a tarball of tracked sources so WSL can build AVM.
REPO_TGZ="$OUT_DIR/repo.tgz"
git ls-files -z | tar -czf "$REPO_TGZ" --null -T -

echo "[obc-portability] remote scp obc + repo.tgz"
run_with_timeout "$REMOTE_TIMEOUT_SECS" "${SCP[@]}" "$OB_OBC" "$REMOTE_HOST:$REMOTE_UNIX_ROOT/$REMOTE_SUBDIR/test_smoke_suite.obc" >/dev/null
run_with_timeout "$REMOTE_TIMEOUT_SECS" "${SCP[@]}" "$REPO_TGZ" "$REMOTE_HOST:$REMOTE_UNIX_ROOT/$REMOTE_SUBDIR/repo.tgz" >/dev/null

echo "[obc-portability] remote build+run in WSL"
run_with_timeout "$REMOTE_WSL_TIMEOUT_SECS" "${SSH[@]}" 'wsl.exe -e bash -lc "set -euo pipefail; root=/mnt/c/Users/lzbgt/tmp_oren/obc_portability; echo \"[wsl] unpack\"; mkdir -p $root/repo; tar -xzf $root/repo.tgz -C $root/repo; echo \"[wsl] build avm\"; cd $root/repo; make avm CC=gcc >/dev/null; echo \"[wsl] run\"; ./avm --print-result-hash --print-trace-hash $root/test_smoke_suite.obc"' \
  | tee "$OUT_DIR/wsl_x64.out" >/dev/null
WSL_HASHES="$(extract_hashes "$OUT_DIR/wsl_x64.out")"
echo "[obc-portability] wsl/x64 RESULT/TRACE: $WSL_HASHES"

echo "[obc-portability] comparing hashes..."
if [[ "$MAC_HASHES" != "$LINUX_HASHES" ]]; then
  echo "FAIL: mac != linux/arm64" >&2
  exit 1
fi
if [[ "$MAC_HASHES" != "$WSL_HASHES" ]]; then
  echo "FAIL: mac != wsl/x64" >&2
  exit 1
fi

echo "[obc-portability] OK: hashes match across mac arm64 + linux/arm64 docker + linux/x64 WSL2"
