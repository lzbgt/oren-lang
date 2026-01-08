#!/usr/bin/env bash
set -euo pipefail

# Run a small, high-signal x64-linux runtime smoke under QEMU in the persistent Linux container.
#
# Why this exists:
# - We can compile x64-linux artifacts on the macOS arm64 host (native backend cross-target).
# - But "compile-only" does not catch runtime/codegen issues (syscalls, calling convention, GC, threads).
# - Running under qemu-x86_64 in the Linux container gives us a fast, local execution gate that does not
#   depend on remote WSL2/Win11, while still exercising real Linux syscalls.
#
# Scope (rolling):
# - stage1 + stage2 emit x64-linux binaries
# - run them under qemu-x86_64 with bounded timeouts
# - keep logs tiny; print details only on failure

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LINUX_DOCKER_ID="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
RUN_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_RUN_TIMEOUT_SECS:-10}"
BUILD_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_BUILD_TIMEOUT_SECS:-120}"

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
  echo "hint: the repo expects the already-running Ubuntu toolchain container (see AGENTS.md)." >&2
  exit 2
fi

log "== preflight: container tools =="
docker exec -i "$LINUX_DOCKER_ID" bash -lc 'command -v qemu-x86_64 >/dev/null && command -v timeout >/dev/null'
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
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; cd /tmp/hostbins; chmod +x '$name'; timeout '$RUN_TIMEOUT_SECS' qemu-x86_64 './$name' >'${name}.out' 2>&1 || exit \$?"
  out="$(docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && cat '${name}.out' | tr -d '\\r'")"
  if ! printf '%s\n' "$out" | grep -qF "$want"; then
    echo "--- run failed: ${name} ---" >&2
    echo "expected substring: $want" >&2
    echo "--- output ---" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
}

PRINT_SRC="tests/native/print.oren"
QI_SRC="tests/native/test_quick_integration_native.oren"

build_one "./oren" "$PRINT_SRC" "build/tmp/print_stage1_x64_linux" "build/logs/x64_linux_print_stage1.log"
build_one "./oren_stage2" "$PRINT_SRC" "build/tmp/print_stage2_x64_linux" "build/logs/x64_linux_print_stage2.log"
build_one "./oren" "$QI_SRC" "build/tmp/qi_stage1_x64_linux" "build/logs/x64_linux_qi_stage1.log"
build_one "./oren_stage2" "$QI_SRC" "build/tmp/qi_stage2_x64_linux" "build/logs/x64_linux_qi_stage2.log"

run_one "build/tmp/print_stage1_x64_linux" "hello from native" "print_stage1_x64_linux"
run_one "build/tmp/print_stage2_x64_linux" "hello from native" "print_stage2_x64_linux"
run_one "build/tmp/qi_stage1_x64_linux" "native quick integration OK" "qi_stage1_x64_linux"
run_one "build/tmp/qi_stage2_x64_linux" "native quick integration OK" "qi_stage2_x64_linux"

log "OK: x64-linux QEMU smoke passed (stage1 + stage2)"
