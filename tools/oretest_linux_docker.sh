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
#   OREN_LINUX_DOCKER_JOBS     : forwarded to OREN_TEST_JOBS (default: 4)
#

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE="${OREN_LINUX_DOCKER_IMAGE:-ubuntu:24.04}"
NAME="${OREN_LINUX_DOCKER_NAME:-oren-linux-oretest}"
RESTART="${OREN_LINUX_DOCKER_RESTART:-1}"
JOBS="${OREN_LINUX_DOCKER_JOBS:-4}"

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
'

echo "[linux-oretest-docker] running make test (OREN_TEST_JOBS=$JOBS)"
docker exec "$NAME" bash -lc "
set -euo pipefail
rm -rf /work/repo && mkdir -p /work/repo
if [[ -d /src ]]; then
  SRC=/src
else
  SRC=/repo
fi
cd \"\$SRC\"
tar \
  --exclude .git \
  --exclude build \
  --exclude ./oren_bootstrap \
  --exclude ./oren \
  --exclude ./oren_stage2 \
  --exclude ./oren_stage3 \
  --exclude ./avm \
  --exclude ./oretest \
  -czf - . \
  | tar -xzf - -C /work/repo
cd /work/repo
export OREN_TEST_JOBS='$JOBS'
export GOPROXY='$GOPROXY'
export GOSUMDB='$GOSUMDB'
make bootstrap
make test
"

echo "[linux-oretest-docker] OK"
