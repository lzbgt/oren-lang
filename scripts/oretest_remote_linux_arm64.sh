#!/usr/bin/env bash
set -euo pipefail

# Run the curated test suite on a remote Linux ARM64 host.
#
# Why this exists:
# - The native backend supports `--target linux`, but executing Linux ARM64 binaries
#   must happen on a Linux ARM64 host.
# - This script keeps secrets out of the repo: it relies on your SSH config/key.
#
# Requirements on the local machine:
# - ssh, tar
# - optional: rsync (faster incremental sync)
#
# Requirements on the remote Linux machine:
# - go (for stage0 + oretest)
# - make, cc (clang/gcc)
#
# Usage:
#   SSH_DEST=blu@192.168.66.212 ./scripts/oretest_remote_linux_arm64.sh
#   SSH_DEST=blu@qemu-blu.local ./scripts/oretest_remote_linux_arm64.sh
#
# Optional:
#   REMOTE_DIR=/home/blu/oretest-run ./scripts/oretest_remote_linux_arm64.sh
#   OREN_TEST_JOBS=8 ./scripts/oretest_remote_linux_arm64.sh

SSH_DEST="${SSH_DEST:-}"
if [[ -z "${SSH_DEST}" ]]; then
  echo "ERROR: set SSH_DEST, e.g. SSH_DEST=blu@192.168.66.212" >&2
  exit 2
fi

REMOTE_DIR="${REMOTE_DIR:-/tmp/oren-oretest}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -d .git ]]; then
  echo "ERROR: must run from a git checkout (missing .git)" >&2
  exit 2
fi

REV="$(git rev-parse --short HEAD)"
REMOTE_RUN_DIR="${REMOTE_DIR}/${REV}"

echo "==> Syncing repo to ${SSH_DEST}:${REMOTE_RUN_DIR}"

ssh "${SSH_DEST}" "mkdir -p \"${REMOTE_RUN_DIR}\""

if command -v rsync >/dev/null 2>&1; then
  rsync -az --delete \
    --exclude .git \
    --exclude build \
    --exclude oren_bootstrap \
    --exclude oren \
    --exclude oren_stage2 \
    --exclude avm \
    --exclude oretest \
    ./ "${SSH_DEST}:${REMOTE_RUN_DIR}/"
else
  tar --exclude .git --exclude build -czf - . | ssh "${SSH_DEST}" "tar -xzf - -C \"${REMOTE_RUN_DIR}\""
fi

echo "==> Running Linux ARM64 curated suite on remote host"

# NOTE: `make test` now auto-selects `OREN_TEST_TARGET=linux` on Linux.
ssh "${SSH_DEST}" "cd \"${REMOTE_RUN_DIR}\" && make test"

echo "OK: remote linux arm64 suite passed (${REV})"

