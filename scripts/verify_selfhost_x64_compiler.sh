#!/usr/bin/env bash
set -euo pipefail

# Verify that Oren's self-hosted compiler can run on x86_64 hosts (Win11 + WSL2)
# and successfully compile+run a tiny native program.
#
# Why this exists (rolling):
# - The native backend can emit x64-linux and x64-windows binaries from the macOS/arm64 dev host,
#   but "Tier‑1 support" also requires the compiler binary itself to run on those platforms.
# - This script closes that gap by:
#   1) building an x64-linux compiler binary (ELF) and an x64-windows compiler binary (PE),
#   2) copying them + minimal runtime sources to the remote Win11 machine,
#   3) running the compiler on WSL2 + Windows to compile a tiny program and execute it.
#
# Notes:
# - This is intentionally NOT part of the default fast matrix; building the compiler for x64 can
#   be expensive. Use it when bringing up x64 self-hosting.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

REMOTE_DIR_NAME="${OREN_REMOTE_SELFHOST_DIR_NAME:-tmp_oren_selfhost}"
# IMPORTANT: for OpenSSH on Windows, scp/sftp path handling is not consistent for POSIX-style
# absolute paths like `/Users/<name>/...`. Prefer a home-relative path for reliability.
REMOTE_DIR_SSH="${OREN_REMOTE_SELFHOST_DIR_SSH:-$REMOTE_DIR_NAME}"
REMOTE_DIR_WIN="${OREN_REMOTE_SELFHOST_DIR_WIN:-%USERPROFILE%\\$REMOTE_DIR_NAME}"

# Timeouts:
# - compiler build can be slow on cross-target x64 bring-up; keep this generous.
BUILD_COMPILER_TIMEOUT_SECS="${OREN_SELFHOST_COMPILER_BUILD_TIMEOUT_SECS:-1200}"
# - running the compiler to compile a tiny file should still be bounded.
REMOTE_COMPILE_TIMEOUT_SECS="${OREN_SELFHOST_REMOTE_COMPILE_TIMEOUT_SECS:-120}"
REMOTE_RUN_TIMEOUT_SECS="${OREN_SELFHOST_REMOTE_RUN_TIMEOUT_SECS:-30}"
SCP_RETRIES="${OREN_REMOTE_SCP_RETRIES:-3}"

TARGETS_CSV="x64-win,x64-wsl"
TRACE=0
TRACE_ENV=""

usage() {
  cat <<'EOF'
Usage: scripts/verify_selfhost_x64_compiler.sh [--targets <csv>] [--trace]

Targets (comma-separated):
  x64-win   run the x64-windows compiler on remote Win11 (cmd.exe)
  x64-wsl   run the x64-linux compiler under remote WSL2 (Linux ELF)

Env overrides:
  OREN_REMOTE_X64_HOST
  OREN_REMOTE_X64_PROXY
  OREN_REMOTE_SELFHOST_DIR_WIN   (default: %USERPROFILE%\\tmp_oren_selfhost)
  OREN_REMOTE_SELFHOST_DIR_SSH   (default: /Users/lzbgt/tmp_oren_selfhost)
  OREN_SELFHOST_COMPILER_BUILD_TIMEOUT_SECS (default: 1200)
  OREN_SELFHOST_REMOTE_COMPILE_TIMEOUT_SECS (default: 120)
  OREN_SELFHOST_REMOTE_RUN_TIMEOUT_SECS (default: 30)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      TARGETS_CSV="${2:-}"
      if [[ -z "$TARGETS_CSV" ]]; then
        echo "ERROR: --targets requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --trace)
      TRACE=1
      shift
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin make
need_bin ssh
need_bin scp
need_bin socat
need_bin tar
need_bin grep

if [[ "$TRACE" -eq 1 ]]; then
  set -x
  TRACE_ENV=1
fi

host_os="$(uname -s)"
host_arch="$(uname -m)"
if [[ "$host_os" != "Darwin" || "$host_arch" != "arm64" ]]; then
  echo "ERROR: this script currently assumes a macOS arm64 host; got OS=$host_os arch=$host_arch" >&2
  exit 2
fi

normalize_target() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  case "$t" in
    win|windows|x64-windows) echo x64-win ;;
    wsl|linux-x64|x64-linux) echo x64-wsl ;;
    *) echo "$t" ;;
  esac
}

TARGETS_NORM=()
IFS=',' read -r -a _parts <<<"$TARGETS_CSV"
for p in "${_parts[@]}"; do
  TARGETS_NORM+=("$(normalize_target "$p")")
done

has_target() {
  local want
  want="$(normalize_target "$1")"
  for p in "${TARGETS_NORM[@]}"; do
    if [[ "$p" == "$want" ]]; then
      return 0
    fi
  done
  return 1
}

run_with_timeout() {
  local secs="$1"
  shift
  set +e
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  local killer=$!
  wait "$pid"
  local rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  set -e
  return "$rc"
}

SSH=(ssh -o "$REMOTE_PROXY" "$REMOTE_HOST")
SCP=(scp -o "$REMOTE_PROXY")

mkdir -p build/tmp

parse_jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

remote_user="$REMOTE_HOST"
if [[ "$REMOTE_HOST" == *"@"* ]]; then
  remote_user="${REMOTE_HOST%@*}"
fi
REMOTE_DIR_WSL="${OREN_REMOTE_SELFHOST_DIR_WSL:-/mnt/c/Users/${remote_user}/${REMOTE_DIR_NAME}}"

scp_put() {
  local src="$1"
  local dst="$2"

  local attempt=1
  while true; do
    set +e
    "${SCP[@]}" "$src" "$dst"
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if [[ "$attempt" -ge "$SCP_RETRIES" ]]; then
      echo "ERROR: scp failed after ${attempt}/${SCP_RETRIES} attempts: ${src} -> ${dst} (rc=${rc})" >&2
      return "$rc"
    fi
    echo "WARN: scp failed (attempt ${attempt}/${SCP_RETRIES}) rc=${rc}; retrying..." >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

# Cross-target compiler builds are large and can allocate heavily.
# Keep them bounded by enabling the cooperative GC trigger and limiting stack scan.
gc_stack_scan_limit="${OREN_GC_STACK_SCAN_LIMIT_BYTES:-8388608}"
# For the self-host compiler build (oren.oren), a too-small GC threshold can cause severe
# GC thrash and make the build look "hung". Use a larger default than the tiny-file gates.
gc_alloc_threshold="${OREN_SELFHOST_GC_ALLOC_THRESHOLD:-20000000}"

echo "== ensure: stage2 compiler (host) =="
make stage2 >/dev/null

# Build the compiler binaries for x64 targets (this can be slow on cold caches).
COMPILER_LINUX="build/tmp/oren_selfhost_x64_linux"
COMPILER_WIN="build/tmp/oren_selfhost_x64_windows.exe"

echo "== build: compiler x64-linux (native backend) =="
run_with_timeout "$BUILD_COMPILER_TIMEOUT_SECS" \
  env \
    OREN_PARSE_JOBS="$parse_jobs" \
    OREN_GC_AUTO=1 \
    OREN_GC_ALLOC_THRESHOLD="$gc_alloc_threshold" \
    OREN_GC_STACK_SCAN_LIMIT_BYTES="$gc_stack_scan_limit" \
    ${TRACE_ENV:+OREN_TRACE_PHASES=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_PROGRESS=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_SUMMARY=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_STRIDE=1000} \
    ${TRACE_ENV:+OREN_TRACE_X64_SLOW_FN_MS=2000} \
    ${TRACE_ENV:+OREN_TRACE_RUNTIME_OBJ_CACHE=1} \
    ${TRACE_ENV:+OREN_TRACE_BUILD_SUMMARY=1} \
    ${TRACE_ENV:+OREN_TRACE_BUILD_SLOW_MS=0} \
    ./oren_stage2 build oren.oren --backend native --platform x64-linux --no-debug -o "$COMPILER_LINUX"

echo "== build: compiler x64-windows (native backend) =="
run_with_timeout "$BUILD_COMPILER_TIMEOUT_SECS" \
  env \
    OREN_PARSE_JOBS="$parse_jobs" \
    OREN_GC_AUTO=1 \
    OREN_GC_ALLOC_THRESHOLD="$gc_alloc_threshold" \
    OREN_GC_STACK_SCAN_LIMIT_BYTES="$gc_stack_scan_limit" \
    ${TRACE_ENV:+OREN_TRACE_PHASES=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_PROGRESS=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_SUMMARY=1} \
    ${TRACE_ENV:+OREN_TRACE_X64_COMPILE_STRIDE=1000} \
    ${TRACE_ENV:+OREN_TRACE_X64_SLOW_FN_MS=2000} \
    ${TRACE_ENV:+OREN_TRACE_RUNTIME_OBJ_CACHE=1} \
    ${TRACE_ENV:+OREN_TRACE_BUILD_SUMMARY=1} \
    ${TRACE_ENV:+OREN_TRACE_BUILD_SLOW_MS=0} \
    ./oren_stage2 build oren.oren --backend native --platform x64-windows --no-debug -o "$COMPILER_WIN"

# Package a minimal on-disk layout that the compiler expects at runtime:
# - injected runtime sources live at lib/runtime_native*.oren + lib/runtime_native/**
# - a tiny test program at ./print.oren
PKG_DIR="build/tmp/selfhost_pkg"
PKG_TGZ="build/tmp/selfhost_pkg.tgz"
rm -rf "$PKG_DIR" "$PKG_TGZ" 2>/dev/null || true
mkdir -p "$PKG_DIR/lib"

cp -f lib/runtime_native.oren "$PKG_DIR/lib/runtime_native.oren"
cp -f lib/runtime_native_core.oren "$PKG_DIR/lib/runtime_native_core.oren"
cp -f lib/runtime_native_capsule.oren "$PKG_DIR/lib/runtime_native_capsule.oren"
rm -rf "$PKG_DIR/lib/runtime_native" 2>/dev/null || true
cp -R lib/runtime_native "$PKG_DIR/lib/runtime_native"

cat >"$PKG_DIR/print.oren" <<'EOF'
print("hello from native")
exit(0)
EOF

tar -czf "$PKG_TGZ" -C "$PKG_DIR" .

echo "== remote: prepare dir =="
"${SSH[@]}" "cmd.exe /c \"mkdir ${REMOTE_DIR_WIN} 2>nul & exit /b 0\""

echo "== remote: copy artifacts =="
scp_put "$COMPILER_LINUX" "$REMOTE_HOST:$REMOTE_DIR_SSH/oren_selfhost_x64_linux"
scp_put "$COMPILER_WIN" "$REMOTE_HOST:$REMOTE_DIR_SSH/oren_selfhost_x64_windows.exe"
scp_put "$PKG_TGZ" "$REMOTE_HOST:$REMOTE_DIR_SSH/selfhost_pkg.tgz"

echo "== remote: unpack runtime sources (WSL2 tar into /mnt/c) =="
run_with_timeout "$REMOTE_COMPILE_TIMEOUT_SECS" "${SSH[@]}" \
  "wsl.exe -e bash -lc \"set -euo pipefail; mkdir -p '${REMOTE_DIR_WSL}'; cd '${REMOTE_DIR_WSL}'; rm -rf lib print.oren; tar -xzf '${REMOTE_DIR_WSL}/selfhost_pkg.tgz' -C .; echo OK\""

if has_target x64-wsl; then
  echo "== remote: self-host compile+run (x64-linux under WSL2) =="
  out="$(
    run_with_timeout "$REMOTE_COMPILE_TIMEOUT_SECS" "${SSH[@]}" \
      "wsl.exe -e bash -lc \"set -euo pipefail; cd '${REMOTE_DIR_WSL}'; chmod +x ./oren_selfhost_x64_linux; ./oren_selfhost_x64_linux build print.oren --backend native --platform x64-linux --no-cache --no-debug -o out_linux; chmod +x ./out_linux; ./out_linux; echo EXIT=\$?\""
  )"
  printf '%s\n' "$out"
  echo "$out" | grep -q "hello from native"
  echo "$out" | grep -q "EXIT=0"
fi

if has_target x64-win; then
  echo "== remote: self-host compile+run (x64-windows under cmd.exe) =="
  # Use a conservative timeout wrapper on the local host to avoid hanging forever on remote.
  out="$(
    run_with_timeout "$REMOTE_COMPILE_TIMEOUT_SECS" "${SSH[@]}" \
      "cmd.exe /v:on /c \"cd ${REMOTE_DIR_WIN} && oren_selfhost_x64_windows.exe build print.oren --backend native --platform x64-windows --no-cache --no-debug -o out_win.exe && out_win.exe & echo EXIT=!ERRORLEVEL!\""
  )"
  printf '%s\n' "$out"
  echo "$out" | grep -q "hello from native"
  echo "$out" | grep -q "EXIT=0"
fi

echo "OK: x64 self-host compiler gate passed"
