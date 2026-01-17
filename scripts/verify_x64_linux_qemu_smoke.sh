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
RUN_TIMEOUT_SECS="${OREN_X64_LINUX_QEMU_RUN_TIMEOUT_SECS:-20}"
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
  shift 4
  log "== build: ${compiler} -> x64-linux: $(basename "$src") =="
  # NOTE: keep extra args *before* `-o`. Some rolling CLI parsing paths treat late flags as positional.
  if ! timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform x64-linux --no-cache --no-debug "$@" -o "$out" >"$logf" 2>&1; then
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
  local rc=0
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; cd /tmp/hostbins; chmod +x '$name'; : >'${name}.out'; timeout '$RUN_TIMEOUT_SECS' qemu-x86_64 './$name' >'${name}.out' 2>&1" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "--- run failed: ${name} (exit=$rc) ---" >&2
    if [[ "$rc" -eq 124 ]]; then
      echo "note: exit=124 is timeout(${RUN_TIMEOUT_SECS}s); qemu can be slow on cold starts." >&2
    fi
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && (ls -la '$name' '${name}.out' || true) && echo '--- output (tail) ---' && (tail -n 200 '${name}.out' | tr -d '\\r' || true)" >&2 || true
    return 1
  fi
  out="$(docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && cat '${name}.out' | tr -d '\\r'")"
  if [[ -n "$want" ]]; then
    if ! printf '%s\n' "$out" | grep -qF "$want"; then
      echo "--- run failed: ${name} ---" >&2
      echo "expected substring: $want" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$out" >&2
      return 1
    fi
  fi
}

run_one_env() {
  local bin="$1"
  local want="$2"
  local name="$3"
  shift 3
  if [[ "$#" -le 0 ]]; then
    echo "ERROR: run_one_env expects at least one KEY=VALUE" >&2
    exit 2
  fi
  local env_desc=""
  for kv in "$@"; do
    if [[ -z "$kv" || "$kv" == *" "* || "$kv" != *"="* ]]; then
      echo "ERROR: run_one_env expects KEY=VALUE items (no spaces): got: $kv" >&2
      exit 2
    fi
    if [[ -z "$env_desc" ]]; then
      env_desc="$kv"
    else
      env_desc="${env_desc} ${kv}"
    fi
  done
  log "== run: qemu-x86_64 ${name} (env: ${env_desc}) =="
  docker cp "$bin" "$LINUX_DOCKER_ID:/tmp/hostbins/$name"
  local rc=0
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "set -e; cd /tmp/hostbins; chmod +x '$name'; : >'${name}.out'; timeout '$RUN_TIMEOUT_SECS' env $* qemu-x86_64 './$name' >'${name}.out' 2>&1" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "--- run failed: ${name} (exit=$rc) ---" >&2
    if [[ "$rc" -eq 124 ]]; then
      echo "note: exit=124 is timeout(${RUN_TIMEOUT_SECS}s); qemu can be slow on cold starts." >&2
    fi
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && (ls -la '$name' '${name}.out' || true) && echo '--- output (tail) ---' && (tail -n 200 '${name}.out' | tr -d '\\r' || true)" >&2 || true
    return 1
  fi
  out="$(docker exec -i "$LINUX_DOCKER_ID" bash -lc "cd /tmp/hostbins && cat '${name}.out' | tr -d '\\r'")"
  if [[ -n "$want" ]]; then
    if ! printf '%s\n' "$out" | grep -qF "$want"; then
      echo "--- run failed: ${name} ---" >&2
      echo "expected substring: $want" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$out" >&2
      return 1
    fi
  fi
}

PRINT_SRC="tests/native/print.oren"
QI_SRC="tests/native/test_quick_integration_native.oren"
STD_FFI_LIBC_SMOKE_SRC="tests/native/test_std_ffi_libc_smoke.oren"
LINUX_OS_THREAD_SMOKE_SRC="tests/native/test_linux_os_thread_smoke.oren"
LINUX_ULOCK_TIMEOUT_SMOKE_SRC="tests/native/test_ulock_timeout_linux.oren"
ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC="tests/native/test_ulock_timeout_portable.oren"
OS_THREAD_PARK_UNPARK_SMOKE_SRC="tests/native/test_os_thread_park_unpark_smoke.oren"
OS_THREAD_SPAWN_MANY_SMOKE_SRC="tests/native/test_os_thread_spawn_many_smoke.oren"
GC_STW_OS_THREAD_COLLECT_SMOKE_SRC="tests/native/test_gc_stw_os_thread_collect.oren"
LIBMATH_SRC="examples/libmath.oren"
FFI_FROM_LIBMATH_SRC="examples/ffi_from_libmath.oren"

build_one "./oren" "$PRINT_SRC" "build/tmp/print_stage1_x64_linux" "build/logs/x64_linux_print_stage1.log"
build_one "./oren_stage2" "$PRINT_SRC" "build/tmp/print_stage2_x64_linux" "build/logs/x64_linux_print_stage2.log"
build_one "./oren" "$QI_SRC" "build/tmp/qi_stage1_x64_linux" "build/logs/x64_linux_qi_stage1.log"
build_one "./oren_stage2" "$QI_SRC" "build/tmp/qi_stage2_x64_linux" "build/logs/x64_linux_qi_stage2.log"
build_one "./oren" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage1_x64_linux" "build/logs/x64_linux_std_ffi_libc_smoke_stage1.log"
build_one "./oren_stage2" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage2_x64_linux" "build/logs/x64_linux_std_ffi_libc_smoke_stage2.log"
build_one "./oren" "$LINUX_OS_THREAD_SMOKE_SRC" "build/tmp/linux_os_thread_smoke_stage1_x64_linux" "build/logs/x64_linux_linux_os_thread_smoke_stage1.log"
build_one "./oren_stage2" "$LINUX_OS_THREAD_SMOKE_SRC" "build/tmp/linux_os_thread_smoke_stage2_x64_linux" "build/logs/x64_linux_linux_os_thread_smoke_stage2.log"
build_one "./oren" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage1_x64_linux" "build/logs/x64_linux_ulock_timeout_stage1.log"
build_one "./oren_stage2" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage2_x64_linux" "build/logs/x64_linux_ulock_timeout_stage2.log"
build_one "./oren" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage1_x64_linux" "build/logs/x64_linux_ulock_timeout_portable_stage1.log"
build_one "./oren_stage2" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage2_x64_linux" "build/logs/x64_linux_ulock_timeout_portable_stage2.log"
build_one "./oren" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage1_x64_linux" "build/logs/x64_linux_os_thread_park_unpark_stage1.log"
build_one "./oren_stage2" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage2_x64_linux" "build/logs/x64_linux_os_thread_park_unpark_stage2.log"
build_one "./oren" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage1_x64_linux" "build/logs/x64_linux_os_thread_spawn_many_stage1.log"
build_one "./oren_stage2" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage2_x64_linux" "build/logs/x64_linux_os_thread_spawn_many_stage2.log"
build_one "./oren" "$GC_STW_OS_THREAD_COLLECT_SMOKE_SRC" "build/tmp/gc_stw_os_thread_collect_stage1_x64_linux" "build/logs/x64_linux_gc_stw_os_thread_collect_stage1.log"
build_one "./oren_stage2" "$GC_STW_OS_THREAD_COLLECT_SMOKE_SRC" "build/tmp/gc_stw_os_thread_collect_stage2_x64_linux" "build/logs/x64_linux_gc_stw_os_thread_collect_stage2.log"

# Shared library + FFI resolution smoke (high-signal for x64-linux native backend):
# - stage1/stage2 emit a `.so` and a binary that calls into it via `ffi`.
# - run under qemu-x86_64 so we exercise real Linux syscalls + dynamic loader behavior.
build_one "./oren" "$LIBMATH_SRC" "build/tmp/libmath_stage1_x64_linux.so" "build/logs/x64_linux_libmath_stage1.log" --lib
build_one "./oren_stage2" "$LIBMATH_SRC" "build/tmp/libmath_stage2_x64_linux.so" "build/logs/x64_linux_libmath_stage2.log" --lib
build_one "./oren" "$FFI_FROM_LIBMATH_SRC" "build/tmp/ffi_from_libmath_stage1_x64_linux" "build/logs/x64_linux_ffi_from_libmath_stage1.log" --link "./libmath_stage1_x64_linux.so"
build_one "./oren_stage2" "$FFI_FROM_LIBMATH_SRC" "build/tmp/ffi_from_libmath_stage2_x64_linux" "build/logs/x64_linux_ffi_from_libmath_stage2.log" --link "./libmath_stage2_x64_linux.so"

run_one "build/tmp/print_stage1_x64_linux" "hello from native" "print_stage1_x64_linux"
run_one "build/tmp/print_stage2_x64_linux" "hello from native" "print_stage2_x64_linux"
run_one "build/tmp/qi_stage1_x64_linux" "native quick integration OK" "qi_stage1_x64_linux"
run_one "build/tmp/qi_stage2_x64_linux" "native quick integration OK" "qi_stage2_x64_linux"
run_one_env "build/tmp/qi_stage1_x64_linux" "native quick integration OK" "qi_stage1_x64_linux_cache" "OREN_GREEN_POLL_CACHE=1" "OREN_TEST_SLOW=1"
run_one_env "build/tmp/qi_stage2_x64_linux" "native quick integration OK" "qi_stage2_x64_linux_cache" "OREN_GREEN_POLL_CACHE=1" "OREN_TEST_SLOW=1"
run_one "build/tmp/std_ffi_libc_smoke_stage1_x64_linux" "" "std_ffi_libc_smoke_stage1_x64_linux"
run_one "build/tmp/std_ffi_libc_smoke_stage2_x64_linux" "" "std_ffi_libc_smoke_stage2_x64_linux"
run_one "build/tmp/linux_os_thread_smoke_stage1_x64_linux" "ok: linux os thread smoke" "linux_os_thread_smoke_stage1_x64_linux"
run_one "build/tmp/linux_os_thread_smoke_stage2_x64_linux" "ok: linux os thread smoke" "linux_os_thread_smoke_stage2_x64_linux"
run_one "build/tmp/ulock_timeout_stage1_x64_linux" "ok: ulock timeout linux" "ulock_timeout_stage1_x64_linux"
run_one "build/tmp/ulock_timeout_stage2_x64_linux" "ok: ulock timeout linux" "ulock_timeout_stage2_x64_linux"
run_one "build/tmp/ulock_timeout_portable_stage1_x64_linux" "ok: ulock timeout portable" "ulock_timeout_portable_stage1_x64_linux"
run_one "build/tmp/ulock_timeout_portable_stage2_x64_linux" "ok: ulock timeout portable" "ulock_timeout_portable_stage2_x64_linux"
run_one "build/tmp/os_thread_park_unpark_stage1_x64_linux" "ok: os thread park/unpark smoke" "os_thread_park_unpark_stage1_x64_linux"
run_one "build/tmp/os_thread_park_unpark_stage2_x64_linux" "ok: os thread park/unpark smoke" "os_thread_park_unpark_stage2_x64_linux"
run_one "build/tmp/os_thread_spawn_many_stage1_x64_linux" "ok: os thread spawn-many smoke" "os_thread_spawn_many_stage1_x64_linux"
run_one "build/tmp/os_thread_spawn_many_stage2_x64_linux" "ok: os thread spawn-many smoke" "os_thread_spawn_many_stage2_x64_linux"
run_one "build/tmp/gc_stw_os_thread_collect_stage1_x64_linux" "ok: gc stw os-thread collect" "gc_stw_os_thread_collect_stage1_x64_linux"
run_one "build/tmp/gc_stw_os_thread_collect_stage2_x64_linux" "ok: gc stw os-thread collect" "gc_stw_os_thread_collect_stage2_x64_linux"

# Copy the `.so` alongside the executable (the embedded `--link` uses a relative `./...so` path).
docker cp "build/tmp/libmath_stage1_x64_linux.so" "$LINUX_DOCKER_ID:/tmp/hostbins/libmath_stage1_x64_linux.so"
docker cp "build/tmp/libmath_stage2_x64_linux.so" "$LINUX_DOCKER_ID:/tmp/hostbins/libmath_stage2_x64_linux.so"
run_one "build/tmp/ffi_from_libmath_stage1_x64_linux" "ffi_from_libmath: OK" "ffi_from_libmath_stage1_x64_linux"
run_one "build/tmp/ffi_from_libmath_stage2_x64_linux" "ffi_from_libmath: OK" "ffi_from_libmath_stage2_x64_linux"

log "OK: x64-linux QEMU smoke passed (stage1 + stage2)"
