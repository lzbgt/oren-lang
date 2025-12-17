#!/usr/bin/env bash
set -euo pipefail

# Linux native smoke runner (local Docker Desktop linux/arm64 VM).
#
# This script:
# - builds linux/arm64 native binaries on macOS using `./oren --target linux`
# - runs them inside a linux/arm64 Docker container with `timeout`
#
# Config:
#   OREN_DOCKER_IMAGE : container image (default: ubuntu:24.04)
#   OREN_DOCKER_TIMEOUT_SECS : per-binary run timeout (default: 15)
#   OREN_DOCKER_KEEP : set to 1 to keep the container around for reuse (default: 0)
#   OREN_DOCKER_NAME : container name when keeping (default: oren-linux-smoke)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE="${OREN_DOCKER_IMAGE:-ubuntu:24.04}"
TIMEOUT_SECS="${OREN_DOCKER_TIMEOUT_SECS:-15}"
KEEP="${OREN_DOCKER_KEEP:-0}"
NAME="${OREN_DOCKER_NAME:-oren-linux-smoke}"

echo "[linux-docker-smoke] image=$IMAGE timeout=${TIMEOUT_SECS}s"

make -s oren

mkdir -p build/linux-smoke

SMOKE_TESTS=(
  tests/native/add.oren
  tests/native/print.oren
  tests/native/test_bool_bit_ops.oren
  tests/native/test_call_stack_args.oren
  tests/native/test_env_execve_getenv.oren
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

DOCKER_RUN_ARGS=(--platform linux/arm64 -v "$PWD/build/linux-smoke:/smoke:ro")
if [[ "$KEEP" == "1" ]]; then
  # Create the container once and reuse it (useful for installing tools like strace/binutils).
  if ! docker inspect "$NAME" >/dev/null 2>&1; then
    docker create --name "$NAME" "${DOCKER_RUN_ARGS[@]}" "$IMAGE" bash -lc "sleep infinity" >/dev/null
  fi
  docker start "$NAME" >/dev/null
  docker exec "$NAME" bash -lc "
set -euo pipefail
cd /smoke
for name in ${BIN_NAMES[*]}; do
  echo \"[linux-docker-smoke] run \$name\"
  chmod +x \"./\$name\" 2>/dev/null || true
  set +e
  timeout '${TIMEOUT_SECS}s' \"./\$name\"
  rc=\$?
  set -e
  if [[ \$rc -ne 0 ]]; then
    echo \"[linux-docker-smoke] FAIL: \$name rc=\$rc\"
    exit \$rc
  fi
done
echo \"[linux-docker-smoke] OK\"
"
else
  docker run --rm \
    "${DOCKER_RUN_ARGS[@]}" \
    "$IMAGE" bash -lc "
set -euo pipefail
cd /smoke
for name in ${BIN_NAMES[*]}; do
  echo \"[linux-docker-smoke] run \$name\"
  chmod +x \"./\$name\" 2>/dev/null || true
  set +e
  timeout '${TIMEOUT_SECS}s' \"./\$name\"
  rc=\$?
  set -e
  if [[ \$rc -ne 0 ]]; then
    echo \"[linux-docker-smoke] FAIL: \$name rc=\$rc\"
    exit \$rc
  fi
done
echo \"[linux-docker-smoke] OK\"
"
fi
