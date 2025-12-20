#!/usr/bin/env bash
set -euo pipefail

# Run the curated suite (`make test`) inside a persistent linux/arm64 Docker container.
#
# Why this exists:
# - `tools/linux_native_smoke_docker.sh` validates that emitted ELF binaries execute.
# - This script validates the full toolchain on Linux (Go oretest + C AVM build + linux native target).
# - Uses a persistent container to avoid repeated `apt-get install` cost.
#
# Config:
#   OREN_LINUX_DOCKER_IMAGE    : container image (default: ubuntu:24.04)
#   OREN_LINUX_DOCKER_NAME     : container name (default: oren-linux-oretest)
#   OREN_LINUX_DOCKER_RESTART  : restart container before running (default: 1)
#   OREN_LINUX_DOCKER_JOBS     : forwarded to OREN_TEST_JOBS (default: detected via nproc)
#   OREN_LINUX_DOCKER_CLEAN    : if 1, wipe /work/repo before sync (default: 0)
#

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE="${OREN_LINUX_DOCKER_IMAGE:-ubuntu:24.04}"
NAME="${OREN_LINUX_DOCKER_NAME:-oren-linux-oretest}"
RESTART="${OREN_LINUX_DOCKER_RESTART:-1}"
CLEAN="${OREN_LINUX_DOCKER_CLEAN:-0}"
JOBS="${OREN_LINUX_DOCKER_JOBS:-}"

# Use `--init` so PID 1 reaps zombies created by fork/spawn tests.
# NOTE: the container may have been created earlier with a different mountpoint
# (`/repo`). We detect which one exists at runtime and adapt.
DOCKER_RUN_ARGS=(--init --platform linux/arm64 -v "$PWD:/repo:ro")

# Optional apt mirror to speed up installs, e.g.:
#   OREN_LINUX_DOCKER_APT_MIRROR=https://mirrors.aliyun.com/ubuntu-ports/
APT_MIRROR="${OREN_LINUX_DOCKER_APT_MIRROR:-}"

# Go module mirrors (the repo uses the Go toolchain directive; on some networks
# the default proxy can time out).
#
# Examples:
#   OREN_LINUX_DOCKER_GOPROXY=https://goproxy.cn,direct
#   OREN_LINUX_DOCKER_GOSUMDB=sum.golang.google.cn
GOPROXY="${OREN_LINUX_DOCKER_GOPROXY:-https://goproxy.cn,direct}"
GOSUMDB="${OREN_LINUX_DOCKER_GOSUMDB:-sum.golang.google.cn}"

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  docker create --name "$NAME" "${DOCKER_RUN_ARGS[@]}" "$IMAGE" bash -lc 'sleep infinity' >/dev/null
fi

docker start "$NAME" >/dev/null || true
if [[ "$RESTART" == "1" ]]; then
  docker restart "$NAME" >/dev/null
fi

if [[ -z "$JOBS" ]]; then
  JOBS="$(docker exec "$NAME" bash -lc 'nproc 2>/dev/null || echo 4' | tr -d '\r' | tr -d '\n' || true)"
  if [[ -z "$JOBS" ]]; then
    JOBS=4
  fi
fi

# Install deps only if missing.
docker exec "$NAME" bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if [[ -n "'"$APT_MIRROR"'" ]]; then
  # Ubuntu ports images use `ports.ubuntu.com/ubuntu-ports`.
  # Keep this best-effort: if the mirror is unreachable, apt will fail and the user can unset it.
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i "s|http://ports.ubuntu.com/ubuntu-ports/|'"$APT_MIRROR"'|g" /etc/apt/sources.list || true
    sed -i "s|https://ports.ubuntu.com/ubuntu-ports/|'"$APT_MIRROR"'|g" /etc/apt/sources.list || true
  fi
fi
if ! command -v go >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq golang-go >/dev/null
fi
if ! command -v cc >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq build-essential >/dev/null
fi
if ! command -v tini >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq tini >/dev/null
fi
'

echo "[linux-oretest-docker] running make test (OREN_TEST_JOBS=$JOBS)"

# Sync sources into the container.
#
# IMPORTANT:
# - Do NOT copy host-built binaries like `./oretest` or `./oren` into the Linux container,
#   or `make` may treat them as up-to-date and attempt to execute a macOS binary.
# - Use tracked files as the source of truth (git index), not `tar .`.
echo "[linux-oretest-docker] syncing tracked sources into /work/repo"
git ls-files -z \
  | tar -czf - --null -T - \
  | docker exec -i "$NAME" bash -lc '
set -euo pipefail
mkdir -p /work/repo
if [[ "'"$CLEAN"'" == "1" ]]; then
  rm -rf /work/repo/*
fi
tar -xzf - -C /work/repo
'

# Use `tini -s` as a child subreaper even if the container was not created with
# `--init`. This prevents zombie buildup from fork/spawn tests inside long-lived
# containers whose PID 1 does not reap children.
docker exec "$NAME" tini -s -- bash -lc "
set -euo pipefail
mkdir -p /work/repo
cd /work/repo
# IMPORTANT:
# The repo sync does not include a .git directory, and file mtimes come from tar.
# If previous build artifacts exist, make can incorrectly treat them as up-to-date.
# Remove well-known build outputs each run to force correct rebuilds without wiping
# the whole workspace (keeps incremental apt-installed toolchain, etc.).
rm -f ./oren ./oren_bootstrap ./oretest ./avm || true
rm -rf ./build/logs || true
export OREN_TEST_JOBS='$JOBS'
export OREN_TEST_FULL='${OREN_TEST_FULL:-0}'
export OREN_TEST_VERBOSE='${OREN_TEST_VERBOSE:-0}'
export OREN_NO_GC='${OREN_NO_GC:-}'
export GOPROXY='$GOPROXY'
export GOSUMDB='$GOSUMDB'
make bootstrap
make test
"

echo "[linux-oretest-docker] OK"
