#!/usr/bin/env bash
set -euo pipefail

# Prepare the persistent Linux container to execute x64-linux ELF binaries under qemu-x86_64.
#
# Problem:
# - Our Tier‑1 host is arm64-macos, and we have an arm64 Ubuntu container for Linux tooling.
# - qemu-x86_64 can run x86_64 binaries, but dynamically-linked ELF needs the x86_64 loader:
#     /lib64/ld-linux-x86-64.so.2
#   and a minimal x86_64 glibc runtime set.
#
# Solution:
# - Enable Debian/Ubuntu multiarch (amd64)
# - Install libc + minimal runtime libs for amd64 into the container
# - Ensure /lib64/ld-linux-x86-64.so.2 exists (symlink if needed)
#
# This is idempotent and intentionally separate from the verification gates so tests remain fast and deterministic.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/linux_docker_lib.sh"

LINUX_DOCKER_REF="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"

log() { printf '%s\n' "$*"; }

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin docker

LINUX_DOCKER_ID="$(linux_docker_require_running "$LINUX_DOCKER_REF")"

log "== setup: enable amd64 multiarch in container ${LINUX_DOCKER_ID} =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; dpkg --add-architecture amd64; dpkg --print-foreign-architectures | grep -qx amd64'

log "== setup: fix apt sources for multiarch (arm64 ports + amd64 archive) =="
# The container may use an arm64-only mirror (ubuntu-ports) without an `Architectures:` filter.
# Once `amd64` is enabled, apt will try to fetch amd64 indexes from that mirror (404).
# Fix by:
# - pinning the existing ubuntu-ports sources to arm64 only
# - adding an amd64-only source pointing at the standard Ubuntu archive/security endpoints
docker exec -i "$LINUX_DOCKER_ID" bash -lc '
set -e

src=/etc/apt/sources.list.d/ubuntu.sources
if [ -e "$src" ] && ! grep -q "^Architectures:" "$src"; then
  sed -i "/^Signed-By:/i Architectures: arm64" "$src"
fi

amd=/etc/apt/sources.list.d/amd64.sources
if [ ! -e "$amd" ]; then
cat >"$amd" <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main universe restricted multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main universe restricted multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi
'

log "== setup: apt-get update =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; export DEBIAN_FRONTEND=noninteractive; apt-get -qq update'

log "== setup: install x86_64 loader + glibc runtime (amd64) =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; export DEBIAN_FRONTEND=noninteractive; apt-get -qq install -y libc6:amd64 libgcc-s1:amd64'

# Optional: install OpenSSL runtime for x86_64 inside the container.
# With the current Linux TLS provider design, non-TLS programs should not require OpenSSL at load time.
# Keep this opt-in so the sysroot stays minimal.
if [ "${OREN_X64_LINUX_QEMU_INSTALL_OPENSSL:-0}" = "1" ]; then
  log "== setup: install x86_64 OpenSSL runtime (amd64) =="
  docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; export DEBIAN_FRONTEND=noninteractive; apt-get -qq install -y libssl3:amd64'
fi

log "== setup: ensure x86_64 ld-linux path exists =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc '\
  set -e; \
  if [ -e /lib64/ld-linux-x86-64.so.2 ]; then exit 0; fi; \
  if [ -e /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]; then \
    mkdir -p /lib64; \
    ln -sf /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; \
    exit 0; \
  fi; \
  echo "ERROR: amd64 glibc loader missing after install" >&2; \
  ls -la /lib /lib64 /lib/x86_64-linux-gnu 2>/dev/null || true; \
  exit 2'

log "OK: x64-linux qemu sysroot ready in container ${LINUX_DOCKER_ID}"
