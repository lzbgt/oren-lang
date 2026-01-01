#!/usr/bin/env bash
set -euo pipefail

# Linux native smoke runner (local Docker Desktop linux/arm64 VM).
#
# This script:
# - builds linux/arm64 native binaries on macOS using `./oren --target linux`
# - runs them inside a linux/arm64 Docker container with `timeout`
#
# Config:
#   OREN_DOCKER_ID : existing persistent linux container id/name (default: c7e5f7bd9f5c)
#   OREN_DOCKER_TIMEOUT_SECS : per-binary run timeout (default: 15)
#   OREN_DOCKER_SMOKE_DIR : container workdir (default: /work/smoke)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOCKER_ID="${OREN_DOCKER_ID:-c7e5f7bd9f5c}"
TIMEOUT_SECS="${OREN_DOCKER_TIMEOUT_SECS:-15}"
SMOKE_DIR="${OREN_DOCKER_SMOKE_DIR:-/work/smoke}"

if ! docker inspect "$DOCKER_ID" >/dev/null 2>&1; then
  echo "[linux-docker-smoke] ERROR: required persistent docker container not found: $DOCKER_ID" >&2
  exit 2
fi
running="$(docker inspect "$DOCKER_ID" --format '{{.State.Running}}' 2>/dev/null || echo false)"
if [[ "$running" != "true" ]]; then
  echo "[linux-docker-smoke] ERROR: docker container is not running: $DOCKER_ID" >&2
  exit 2
fi

echo "[linux-docker-smoke] container=$DOCKER_ID timeout=${TIMEOUT_SECS}s"

make -s oren

mkdir -p build/linux-smoke

SMOKE_TESTS=(
  tests/native/add.oren
  tests/native/print.oren
  tests/native/test_bool_bit_ops.oren
  tests/native/test_call_stack_args.oren
  tests/native/test_env_execve_getenv.oren
  tests/native/test_sleep_ms.oren
  tests/native/test_time_now.oren
  tests/native/test_time_mono_raw.oren
  tests/native/test_system_timeout.oren
  tests/native/test_for_break_continue.oren
  tests/native/test_for_in_list.oren
  tests/native/test_for_in_string.oren
  tests/native/test_spawn_simple.oren
  tests/native/test_spawn_args.oren
  tools/bench/test_linux_tcp_loopback_fork.oren
)

echo "[linux-docker-smoke] building ${#SMOKE_TESTS[@]} linux binaries..."
BIN_NAMES=()
for t in "${SMOKE_TESTS[@]}"; do
  name="$(basename "$t" .oren)"
  BIN_NAMES+=("$name")
  out="build/linux-smoke/$name"
  ./oren build "$t" --backend native --target linux -o "$out"
  file "$out" | grep -q "ELF" || { echo "[linux-docker-smoke] FAIL: $out is not ELF"; exit 1; }
done

echo "[linux-docker-smoke] running in container..."

# Copy built ELF binaries into the container (no bind-mount assumptions).
tar -czf - -C build/linux-smoke . | docker exec -i "$DOCKER_ID" bash -lc "
set -euo pipefail
rm -rf \"$SMOKE_DIR\"
mkdir -p \"$SMOKE_DIR\"
tar -xzf - -C \"$SMOKE_DIR\"
"

docker exec "$DOCKER_ID" bash -lc "
	set -euo pipefail
	cd \"$SMOKE_DIR\"
	timeout_bin=\"\"
	if command -v timeout >/dev/null 2>&1; then timeout_bin=\"timeout\"; fi
	for name in ${BIN_NAMES[*]}; do
	  echo \"[linux-docker-smoke] run \$name\"
	  chmod +x \"./\$name\" 2>/dev/null || true
	  set +e
	  if [[ -n \"\$timeout_bin\" ]]; then
	    \"\$timeout_bin\" '${TIMEOUT_SECS}s' \"./\$name\"
	  else
	    \"./\$name\"
	  fi
	  rc=\$?
	  set -e
	  if [[ \$rc -ne 0 ]]; then
	    echo \"[linux-docker-smoke] FAIL: \$name rc=\$rc\"
	    exit \$rc
	  fi
	done
	echo \"[linux-docker-smoke] OK\"
"
