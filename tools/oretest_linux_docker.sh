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
#   OREN_LINUX_DOCKER_ID       : existing persistent container id/name (default: c7e5f7bd9f5c)
#   OREN_LINUX_DOCKER_JOBS     : forwarded to OREN_TEST_JOBS (default: detected via nproc)
#   OREN_LINUX_DOCKER_CLEAN    : if 1, wipe /work/repo before sync (default: 0)
#

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOCKER_ID="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
CLEAN="${OREN_LINUX_DOCKER_CLEAN:-0}"
JOBS="${OREN_LINUX_DOCKER_JOBS:-}"

# Go module mirrors (the repo uses the Go toolchain directive; on some networks
# the default proxy can time out).
#
# Examples:
#   OREN_LINUX_DOCKER_GOPROXY=https://goproxy.cn,direct
#   OREN_LINUX_DOCKER_GOSUMDB=sum.golang.google.cn
GOPROXY="${OREN_LINUX_DOCKER_GOPROXY:-https://goproxy.cn,direct}"
GOSUMDB="${OREN_LINUX_DOCKER_GOSUMDB:-sum.golang.google.cn}"

if ! docker inspect "$DOCKER_ID" >/dev/null 2>&1; then
  echo "[linux-oretest-docker] ERROR: required persistent container not found: $DOCKER_ID" >&2
  echo "[linux-oretest-docker] Hint: restore/start the existing Ubuntu toolchain container (do not create a new one)." >&2
  exit 2
fi
running="$(docker inspect "$DOCKER_ID" --format '{{.State.Running}}' 2>/dev/null || echo false)"
if [[ "$running" != "true" ]]; then
  echo "[linux-oretest-docker] ERROR: container is not running: $DOCKER_ID" >&2
  echo "[linux-oretest-docker] Hint: start it, then retry." >&2
  exit 2
fi

if [[ -z "$JOBS" ]]; then
  JOBS="$(docker exec "$DOCKER_ID" bash -lc 'nproc 2>/dev/null || echo 4' | tr -d '\r' | tr -d '\n' || true)"
  if [[ -z "$JOBS" ]]; then
    JOBS=4
  fi
fi

# Verify the container has the required tooling (we do not mutate/provision it here).
docker exec "$DOCKER_ID" bash -lc '
set -euo pipefail
if ! command -v go >/dev/null 2>&1; then
  echo "missing go toolchain in container" >&2
  exit 2
fi
if ! command -v cc >/dev/null 2>&1; then
  echo "missing C compiler (cc) in container" >&2
  exit 2
fi
'

echo "[linux-oretest-docker] running make test (OREN_TEST_JOBS=$JOBS)"

# Sync sources into the container.
#
# IMPORTANT:
# - Do NOT copy host-built binaries like `./oretest` or `./oren` into the Linux container,
#   or `make` may treat them as up-to-date and attempt to execute a macOS binary.
# - Use tracked files as the source of truth (git index), not `tar .`.
#
# NOTE:
# This runner syncs only tracked files (`git ls-files`). If you add new files but do not
# `git add`/commit them, the container will not see them and tests may fail with confusing
# "cannot open file" errors.
echo "[linux-oretest-docker] syncing tracked sources into /work/repo"
ALLOW_DIRTY="${OREN_LINUX_DOCKER_ALLOW_DIRTY:-0}"
if [[ "$ALLOW_DIRTY" != "1" ]]; then
  if git status --porcelain --untracked-files=normal | grep -q '^??'; then
    echo "[linux-oretest-docker] ERROR: untracked files present; this runner syncs tracked sources only." >&2
    echo "[linux-oretest-docker] Hint: run \`git add -A\` (and commit), or set OREN_LINUX_DOCKER_ALLOW_DIRTY=1." >&2
    exit 2
  fi
fi
git ls-files -z \
  | tar -czf - --null -T - \
  | docker exec -i "$DOCKER_ID" bash -lc '
	set -euo pipefail
	mkdir -p /work/repo
	if [[ "'"$CLEAN"'" == "1" ]]; then
	  rm -rf /work/repo/*
fi
tar -xzf - -C /work/repo
'

run_in_container() {
  if docker exec "$DOCKER_ID" bash -lc 'command -v tini >/dev/null 2>&1'; then
    docker exec "$DOCKER_ID" tini -s -- bash -lc "$1"
  else
    docker exec "$DOCKER_ID" bash -lc "$1"
  fi
}

# Prefer `tini -s` as a child subreaper when available. This prevents zombie buildup
# from fork/spawn tests inside long-lived containers whose PID 1 does not reap children.
run_in_container "
set -euo pipefail
mkdir -p /work/repo
cd /work/repo
# IMPORTANT:
# The repo sync does not include a .git directory, and file mtimes come from tar.
# If previous build artifacts exist, make can incorrectly treat them as up-to-date.
# Remove well-known build outputs each run to force correct rebuilds without wiping
# the whole workspace (keeps incremental apt-installed toolchain, etc.).
rm -f ./oren ./oren_bootstrap ./oretest ./avm || true
rm -f ./oredoc || true
rm -rf ./build/logs || true
export OREN_TEST_JOBS='$JOBS'
export OREN_TEST_NATIVE_JOBS='${OREN_TEST_NATIVE_JOBS:-1}'
export OREN_TEST_FIXTURE_JOBS='${OREN_TEST_FIXTURE_JOBS:-1}'
export OREN_TEST_FULL='${OREN_TEST_FULL:-0}'
export OREN_TEST_VERBOSE='${OREN_TEST_VERBOSE:-0}'
export OREN_NO_GC='${OREN_NO_GC:-}'
export GOPROXY='$GOPROXY'
export GOSUMDB='$GOSUMDB'
make bootstrap
make test
"

echo "[linux-oretest-docker] OK"
