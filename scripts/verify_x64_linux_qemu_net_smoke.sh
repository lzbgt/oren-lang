#!/usr/bin/env bash
set -euo pipefail

# Run loopback NET fixtures (x64-linux) under QEMU in the persistent Linux container.
#
# Requires:
# - qemu-x86_64 in container
# - amd64 glibc loader present in container (see `make setup-x64-linux-qemu`)
#
# This gate is intentionally local and deterministic (loopback only), and does not require remote WSL2.
#
# Keep logs bounded:
# - store build logs under build/logs
# - on failure print only tail snippets

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LINUX_DOCKER_ID="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
RUN_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_NET_RUN_TIMEOUT_SECS:-25}"
BUILD_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_NET_BUILD_TIMEOUT_SECS:-120}"

log() { printf '%s\n' "$*"; }

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin docker

if ! docker ps --format '{{.ID}}' | grep -q "^${LINUX_DOCKER_ID}$"; then
  echo "ERROR: required Linux container is not running: ${LINUX_DOCKER_ID}" >&2
  exit 2
fi

log "== preflight: container qemu + amd64 loader =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; command -v qemu-x86_64 >/dev/null; test -e /lib64/ld-linux-x86-64.so.2'
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'mkdir -p /tmp/hostbins'

mkdir -p build/tmp
mkdir -p build/logs

build_one() {
  local compiler="$1"
  local src="$2"
  local out="$3"
  local logf="$4"
  log "== build: ${compiler} -> x64-linux: $(basename "$src") =="
  if ! timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform x64-linux --no-cache --no-debug -o "$out" >"$logf" 2>&1; then
    echo "--- build failed: $out ---" >&2
    tail -n 200 "$logf" >&2 || true
    return 1
  fi
  # Fail fast on known x86_64 backend hazards that may still exit 0 in some rolling states.
  if grep -Eq 'x64 native v0: missing ABI arg reg|x64 native v0: missing ABI arg regs' "$logf"; then
    echo "--- build produced x64 ABI arg-reg warning (treat as failure) ---" >&2
    tail -n 200 "$logf" >&2 || true
    return 1
  fi
}

run_one() {
  local bin="$1"
  local want="$2"
  local name="$3"
  log "== run: qemu-x86_64 ${name} =="
  docker cp "$bin" "$LINUX_DOCKER_ID:/tmp/hostbins/$name"
  # Regression guard: loopback NET fixtures should not *require* OpenSSL at load time.
  # TLS/HTTPS/WSS tests are covered by the Tier‑1 NET matrix on real x64 hosts (WSL2/Win11).
  # Note: some x64-linux outputs may be fully static (no PT_DYNAMIC). Treat that as OK.
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; if readelf -d '/tmp/hostbins/$name' >/tmp/hostbins/${name}.dyn 2>/dev/null; then grep -E 'NEEDED' /tmp/hostbins/${name}.dyn | grep -q 'libssl\\.so' && { echo 'ERROR: unexpected DT_NEEDED libssl for '$name >&2; exit 2; } || true; fi"
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; if readelf -d '/tmp/hostbins/$name' >/tmp/hostbins/${name}.dyn 2>/dev/null; then grep -E 'NEEDED' /tmp/hostbins/${name}.dyn | grep -q 'libcrypto\\.so' && { echo 'ERROR: unexpected DT_NEEDED libcrypto for '$name >&2; exit 2; } || true; fi"
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; cd /tmp/hostbins; chmod +x '$name'; timeout '$RUN_TIMEOUT_SECS' qemu-x86_64 './$name' >'${name}.out' 2>&1"
  out="$(docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && cat '${name}.out' | tr -d '\\r'")"
  if ! printf '%s\n' "$out" | grep -qF "$want"; then
    echo "--- run failed: ${name} ---" >&2
    echo "expected substring: $want" >&2
    echo "--- output ---" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
}

NET_SUITE_SRC="tests/native/test_net_suite.oren"
DNS_LOOPBACK_SRC="tests/native/test_dns_loopback.oren"
HTTP_LOOPBACK_SRC="tests/native/test_http_get_loopback.oren"
WS_ECHO_SRC="tests/native/test_ws_echo_loopback.oren"

build_one "./oren" "$NET_SUITE_SRC" "build/tmp/net_suite_stage1_x64_linux" "build/logs/x64_linux_net_suite_stage1.log"
build_one "./oren_stage2" "$NET_SUITE_SRC" "build/tmp/net_suite_stage2_x64_linux" "build/logs/x64_linux_net_suite_stage2.log"
build_one "./oren" "$DNS_LOOPBACK_SRC" "build/tmp/dns_loop_stage1_x64_linux" "build/logs/x64_linux_dns_loop_stage1.log"
build_one "./oren_stage2" "$DNS_LOOPBACK_SRC" "build/tmp/dns_loop_stage2_x64_linux" "build/logs/x64_linux_dns_loop_stage2.log"
build_one "./oren" "$HTTP_LOOPBACK_SRC" "build/tmp/http_loop_stage1_x64_linux" "build/logs/x64_linux_http_loop_stage1.log"
build_one "./oren_stage2" "$HTTP_LOOPBACK_SRC" "build/tmp/http_loop_stage2_x64_linux" "build/logs/x64_linux_http_loop_stage2.log"
build_one "./oren" "$WS_ECHO_SRC" "build/tmp/ws_echo_stage1_x64_linux" "build/logs/x64_linux_ws_echo_stage1.log"
build_one "./oren_stage2" "$WS_ECHO_SRC" "build/tmp/ws_echo_stage2_x64_linux" "build/logs/x64_linux_ws_echo_stage2.log"

run_one "build/tmp/net_suite_stage1_x64_linux" "net suite: OK" "net_suite_stage1_x64_linux"
run_one "build/tmp/net_suite_stage2_x64_linux" "net suite: OK" "net_suite_stage2_x64_linux"
run_one "build/tmp/dns_loop_stage1_x64_linux" "dns_loopback: OK" "dns_loop_stage1_x64_linux"
run_one "build/tmp/dns_loop_stage2_x64_linux" "dns_loopback: OK" "dns_loop_stage2_x64_linux"
run_one "build/tmp/http_loop_stage1_x64_linux" "http_get_loopback: OK" "http_loop_stage1_x64_linux"
run_one "build/tmp/http_loop_stage2_x64_linux" "http_get_loopback: OK" "http_loop_stage2_x64_linux"
run_one "build/tmp/ws_echo_stage1_x64_linux" "ws_echo_loopback: OK" "ws_echo_stage1_x64_linux"
run_one "build/tmp/ws_echo_stage2_x64_linux" "ws_echo_loopback: OK" "ws_echo_stage2_x64_linux"

log "OK: x64-linux QEMU NET smoke passed (stage1 + stage2)"
