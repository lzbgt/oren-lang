#!/usr/bin/env bash
set -euo pipefail

# Run loopback TLS/HTTPS/WSS fixtures (x64-linux) under QEMU in the persistent Linux container.
#
# Requirements:
# - qemu-x86_64 + timeout available in container
# - amd64 glibc loader present in container (see `make setup-x64-linux-qemu`)
# - amd64 OpenSSL runtime present in container (opt-in):
#     OREN_X64_LINUX_QEMU_INSTALL_OPENSSL=1 make setup-x64-linux-qemu
#
# Keep logs bounded:
# - store build logs under build/logs
# - on failure print only tail snippets

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/linux_docker_lib.sh"

LINUX_DOCKER_REF="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
RUN_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_TLS_RUN_TIMEOUT_SECS:-35}"
BUILD_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_TLS_BUILD_TIMEOUT_SECS:-180}"

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

log "== preflight: container qemu + amd64 loader + amd64 openssl =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; command -v qemu-x86_64 >/dev/null; command -v timeout >/dev/null; test -e /lib64/ld-linux-x86-64.so.2'

if ! docker exec -i "$LINUX_DOCKER_ID" bash -lc 'set -e; test -e /lib/x86_64-linux-gnu/libssl.so.3; test -e /lib/x86_64-linux-gnu/libcrypto.so.3'; then
  echo "ERROR: missing amd64 OpenSSL runtime in container (needed for TLS/HTTPS/WSS fixtures)" >&2
  echo "hint: run: OREN_X64_LINUX_QEMU_INSTALL_OPENSSL=1 make setup-x64-linux-qemu" >&2
  exit 2
fi

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
  local name="$2"
  log "== run: qemu-x86_64 ${name} =="
  docker cp "$bin" "$LINUX_DOCKER_ID:/tmp/hostbins/$name"
  if ! docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; cd /tmp/hostbins; chmod +x '$name'; timeout '$RUN_TIMEOUT_SECS' qemu-x86_64 './$name' >'${name}.out' 2>&1"; then
    echo "--- run failed: ${name} ---" >&2
    out="$(docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && cat '${name}.out' | tr -d '\\r'")" || true
    printf '%s\n' "$out" | tail -n 200 >&2 || true
    return 1
  fi
  # Success path: fixtures usually print nothing; treat any output as informational, not as a failure.
}

TLS_LOOPBACK_SRC="tests/native/test_tls_loopback.oren"
HTTPS_LOOPBACK_SRC="tests/native/test_https_get_loopback.oren"
WSS_LOOPBACK_SRC="tests/native/test_wss_echo_loopback.oren"
HTTP2_PREFACE_LOOPBACK_SRC="tests/native/test_http2_preface_loopback.oren"
HPACK_SMOKE_SRC="tests/native/test_hpack_smoke.oren"
HTTP2_HEADERS_LOOPBACK_SRC="tests/native/test_http2_headers_loopback.oren"

build_one "./oren" "$TLS_LOOPBACK_SRC" "build/tmp/tls_loop_stage1_x64_linux" "build/logs/x64_linux_tls_loop_stage1.log"
build_one "./oren_stage2" "$TLS_LOOPBACK_SRC" "build/tmp/tls_loop_stage2_x64_linux" "build/logs/x64_linux_tls_loop_stage2.log"
build_one "./oren" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_loop_stage1_x64_linux" "build/logs/x64_linux_https_loop_stage1.log"
build_one "./oren_stage2" "$HTTPS_LOOPBACK_SRC" "build/tmp/https_loop_stage2_x64_linux" "build/logs/x64_linux_https_loop_stage2.log"
build_one "./oren" "$WSS_LOOPBACK_SRC" "build/tmp/wss_loop_stage1_x64_linux" "build/logs/x64_linux_wss_loop_stage1.log"
build_one "./oren_stage2" "$WSS_LOOPBACK_SRC" "build/tmp/wss_loop_stage2_x64_linux" "build/logs/x64_linux_wss_loop_stage2.log"
build_one "./oren" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_preface_stage1_x64_linux" "build/logs/x64_linux_http2_preface_stage1.log"
build_one "./oren_stage2" "$HTTP2_PREFACE_LOOPBACK_SRC" "build/tmp/http2_preface_stage2_x64_linux" "build/logs/x64_linux_http2_preface_stage2.log"
build_one "./oren" "$HPACK_SMOKE_SRC" "build/tmp/hpack_smoke_stage1_x64_linux" "build/logs/x64_linux_hpack_smoke_stage1.log"
build_one "./oren_stage2" "$HPACK_SMOKE_SRC" "build/tmp/hpack_smoke_stage2_x64_linux" "build/logs/x64_linux_hpack_smoke_stage2.log"
build_one "./oren" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage1_x64_linux" "build/logs/x64_linux_http2_headers_stage1.log"
build_one "./oren_stage2" "$HTTP2_HEADERS_LOOPBACK_SRC" "build/tmp/http2_headers_stage2_x64_linux" "build/logs/x64_linux_http2_headers_stage2.log"

run_one "build/tmp/tls_loop_stage1_x64_linux" "tls_loop_stage1_x64_linux"
run_one "build/tmp/tls_loop_stage2_x64_linux" "tls_loop_stage2_x64_linux"
run_one "build/tmp/https_loop_stage1_x64_linux" "https_loop_stage1_x64_linux"
run_one "build/tmp/https_loop_stage2_x64_linux" "https_loop_stage2_x64_linux"
run_one "build/tmp/wss_loop_stage1_x64_linux" "wss_loop_stage1_x64_linux"
run_one "build/tmp/wss_loop_stage2_x64_linux" "wss_loop_stage2_x64_linux"
run_one "build/tmp/http2_preface_stage1_x64_linux" "http2_preface_stage1_x64_linux"
run_one "build/tmp/http2_preface_stage2_x64_linux" "http2_preface_stage2_x64_linux"
run_one "build/tmp/hpack_smoke_stage1_x64_linux" "hpack_smoke_stage1_x64_linux"
run_one "build/tmp/hpack_smoke_stage2_x64_linux" "hpack_smoke_stage2_x64_linux"
run_one "build/tmp/http2_headers_stage1_x64_linux" "http2_headers_stage1_x64_linux"
run_one "build/tmp/http2_headers_stage2_x64_linux" "http2_headers_stage2_x64_linux"

log "OK: x64-linux QEMU TLS/HTTPS/WSS/HTTP2 smoke passed (stage1 + stage2)"
