#!/usr/bin/env bash
set -euo pipefail

# Verify native backend across a practical Tier‑1 matrix without any external test runner.
#
# Host requirements:
# - macOS arm64 host (this script is written primarily for that workflow)
# - docker (for linux/arm64 container execution)
# - ssh/scp (socat only if using the default ProxyCommand; can be disabled via --no-proxy)
#
# This verifies the integrated native smoke:
#   tests/native/test_quick_integration_native.oren
#
# It builds:
# - stage0 (Go): ./oren_bootstrap
# - stage1 (self-hosted): ./oren
# - stage2 (self-hosted): ./oren_stage2
#
# Then it compiles that test to:
# - host platform (runs locally)
# - arm64-linux (runs in the persistent container)
# - x64-linux (runs under remote WSL2)
# - x64-windows (runs on remote Win11)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEST_SRC="tests/native/test_quick_integration_native.oren"
TIER1_SRC="tests/fixtures/tier1_native_smoke_main.oren"
TIER1_EXPECT_MARKERS=1
GREEN_2W_WORLD_LOCK_SRC="tests/native/test_green_two_workers_world_lock_smoke.oren"
GREEN_2W_M_LESS_P_SMOKE_SRC="tests/native/test_green_two_workers_m_less_p_smoke.oren"
GREEN_2W_M_LESS_P_DETERMINISTIC_SRC="tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren"
WIN_FFI_K32_SRC="tests/native/ffi_windows_kernel32.oren"
WIN_FFI_MSVCRT_ATTR_SRC="tests/native/ffi_windows_msvcrt_attr_dll.oren"
WIN_FFI_MSVCRT_LINK_ATTR_SRC="tests/native/ffi_windows_msvcrt_attr_link.oren"
WIN_FFI_I32_SRC="tests/native/ffi_windows_ret_i32_signext.oren"
WIN_FFI_U32_SRC="tests/native/ffi_windows_ret_u32_zeroext.oren"
WIN_FFI_VOID_SRC="tests/native/ffi_windows_ret_void_zero.oren"
WIN_FFI_EXPORT_GETPROC_SRC="tests/native/ffi_windows_export_getprocaddress.oren"
WIN_DNS_DEFAULT_RESOLVER_SMOKE="tests/fixtures/windows_dns_default_resolver_smoke.oren"
WIN_IOCP_WAKE_SMOKE_SRC="tests/fixtures/windows_iocp_wake_smoke.oren"
LINUX_FFI_PANIC_SRC="tests/native/ffi_linux_unresolved_panics.oren"
LINUX_FFI_OK_SRC="tests/native/ffi_linux_strlen_ok.oren"
LINUX_FFI_I32_SRC="tests/native/ffi_linux_ret_i32_signext.oren"
LINUX_FFI_U32_SRC="tests/native/ffi_linux_ret_u32_zeroext.oren"
LINUX_FFI_VOID_SRC="tests/native/ffi_linux_ret_void_zero.oren"
LINUX_OS_THREAD_SMOKE_SRC="tests/native/test_linux_os_thread_smoke.oren"
LINUX_ULOCK_TIMEOUT_SMOKE_SRC="tests/native/test_ulock_timeout_linux.oren"
ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC="tests/native/test_ulock_timeout_portable.oren"
OS_THREAD_PARK_UNPARK_SMOKE_SRC="tests/native/test_os_thread_park_unpark_smoke.oren"
OS_THREAD_SPAWN_MANY_SMOKE_SRC="tests/native/test_os_thread_spawn_many_smoke.oren"
STD_FFI_LIBC_SMOKE_SRC="tests/native/test_std_ffi_libc_smoke.oren"
STD_FFI_KERNEL32_SMOKE_SRC="tests/native/test_std_ffi_kernel32_smoke.oren"
LIBMATH_SRC="examples/libmath.oren"

LINUX_DOCKER_ID="${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
BUILD_TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-10}"
SCP_RETRIES="${OREN_REMOTE_SCP_RETRIES:-6}"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

usage() {
  cat <<'EOF'
Usage: scripts/verify_native_matrix.sh [--targets <csv>] [--local-only]
       scripts/verify_native_matrix.sh [--tier1-src <path>] [--targets <csv>]
       scripts/verify_native_matrix.sh [--targets <csv>] [--trace]
       scripts/verify_native_matrix.sh [--targets <csv>] [--skip-remote]
       scripts/verify_native_matrix.sh [--host <user@host>] [--proxy <ssh_opt>] [--no-proxy]

Runs:
  1) local host platform (stage1 + stage2)
  2) linux/arm64 in existing docker container (stage1 + stage2 compiled artifacts)
  3) remote windows/x64 on Win11 (stage1 + stage2 compiled artifacts)
  4) remote linux/x64 under WSL2 (stage1 + stage2 compiled artifacts)

Targets (comma-separated):
  all         (default)
  stage0      build ./oren_bootstrap
  stage1      build ./oren
  stage2      build ./oren_stage2
  local       run local native quick (stage1+stage2; host platform)
  arm64-linux run linux/arm64 in docker container
  x64-linux-qemu  run x64-linux under qemu-x86_64 in the linux container (no remote required)
  x64-win     run x64-windows on remote Win11
  x64-wsl     run x64-linux under remote WSL2
  x64-win-tier1  (opt-in) run Tier‑1 native smoke fixture on remote Win11
  x64-wsl-tier1  (opt-in) run Tier‑1 native smoke fixture under remote WSL2

Examples:
  ./scripts/verify_native_matrix.sh
  ./scripts/verify_native_matrix.sh --targets stage0,stage1,stage2,local
  ./scripts/verify_native_matrix.sh --targets x64-win,x64-wsl
  ./scripts/verify_native_matrix.sh --targets x64-win-tier1
  ./scripts/verify_native_matrix.sh --targets x64-wsl --trace
  ./scripts/verify_native_matrix.sh --targets x64-win-tier1 --tier1-src tests/fixtures/tier1_native_lambda_varargs_main.oren
  ./scripts/verify_native_matrix.sh --targets local,arm64-linux --skip-remote

Env overrides:
  OREN_LINUX_DOCKER_ID   (default: c7e5f7bd9f5c)
  OREN_NATIVE_BUILD_TIMEOUT_SECS (default: 10) timeout for each `oren build ...` step (rolling hang guard)
  OREN_REMOTE_X64_HOST   (default: lzbgt@pc.work)
  OREN_REMOTE_X64_PROXY  (default: ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002)
  OREN_REMOTE_X64_WIN_ROOT (default: C:\Users\<user>\tmp_oren) remote Windows staging root
  OREN_REMOTE_X64_WSL_ROOT (default: /mnt/c/Users/<user>/tmp_oren) remote WSL staging root
  OREN_REMOTE_X64_SSH_ROOT (default: tmp_oren) scp/sftp staging root (Windows OpenSSH path)
  OREN_CANON_I32_ABORT   (optional) set to 1 to hard-fail on non-canonical i32 values on all targets

Notes:
  - This script does NOT start containers; it expects the persistent container to exist and be running.
  - Remote steps require ssh/scp connectivity to the Win11 host, and WSL2 to be available there.
EOF
}

LOCAL_ONLY=0
SKIP_REMOTE=0
TARGETS_CSV="all"
TRACE=0
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="${2:-}"
      if [[ -z "$REMOTE_HOST" ]]; then
        echo "ERROR: --host requires a value (example: user@203.0.113.10)" >&2
        exit 2
      fi
      shift 2
      ;;
    --proxy)
      REMOTE_PROXY="${2:-}"
      shift 2
      ;;
    --no-proxy)
      REMOTE_PROXY=""
      shift
      ;;
    --local-only)
      LOCAL_ONLY=1
      shift
      ;;
    --skip-remote)
      SKIP_REMOTE=1
      shift
      ;;
    --trace)
      TRACE=1
      shift
      ;;
    --targets)
      TARGETS_CSV="${2:-}"
      if [[ -z "$TARGETS_CSV" ]]; then
        echo "ERROR: --targets requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --tier1-src)
      TIER1_SRC="${2:-}"
      if [[ -z "$TIER1_SRC" ]]; then
        echo "ERROR: --tier1-src requires a value" >&2
        exit 2
      fi
      # Safety: when overriding the Tier‑1 source, disable default marker assertions,
      # because only `tier1_native_smoke_main.oren` prints the full marker set.
      # (Exit code remains authoritative.)
      TIER1_EXPECT_MARKERS=0
      shift 2
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() { printf '%s\n' "$*"; }

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

host_os="$(uname -s)"
host_arch="$(uname -m)"
if [[ "$host_os" != "Darwin" ]]; then
  echo "ERROR: this script currently assumes a macOS host; got OS=$host_os" >&2
  exit 2
fi
if [[ "$host_arch" != "arm64" ]]; then
  echo "ERROR: this script currently assumes an arm64 macOS host; got arch=$host_arch" >&2
  exit 2
fi

need_bin go
need_bin make

mkdir -p build/tmp build/logs

normalize_target() {
  local t="$1"
  # Trim whitespace
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  # Common typos / aliases from interactive usage.
  case "$t" in
    starge0) echo stage0 ;;
    starge1) echo stage1 ;;
    starge2) echo stage2 ;;
    win|windows|x64-windows) echo x64-win ;;
    wsl|x64-linux|linux-x64) echo x64-wsl ;;
    qemu|x64-qemu|x64-linux-qemu) echo x64-linux-qemu ;;
    win-tier1|windows-tier1|x64-windows-tier1) echo x64-win-tier1 ;;
    wsl-tier1|x64-linux-tier1|linux-x64-tier1) echo x64-wsl-tier1 ;;
    *) echo "$t" ;;
  esac
}

TARGETS_NORM=()
if [[ "$TARGETS_CSV" != "all" ]]; then
  IFS=',' read -r -a _parts <<<"$TARGETS_CSV"
  for p in "${_parts[@]}"; do
    TARGETS_NORM+=("$(normalize_target "$p")")
  done
fi

has_target() {
  local want="$1"
  if [[ "$TARGETS_CSV" == "all" ]]; then
    # Rolling ergonomics:
    # `all` is intended to mean "the default fast matrix", not "every opt-in fixture".
    #
    # Tier‑1 fixtures are still available, but must be requested explicitly:
    #   --targets x64-win-tier1,x64-wsl-tier1
    #
    # This keeps `./scripts/verify_native_matrix.sh` fast enough to run frequently.
    if [[ "$want" == "x64-win-tier1" || "$want" == "x64-wsl-tier1" ]]; then
      return 1
    fi
    return 0
  fi
  want="$(normalize_target "$want")"
  for p in "${TARGETS_NORM[@]}"; do
    if [[ "$p" == "$want" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "$LOCAL_ONLY" -eq 0 ]]; then
  # Only require tools for the targets we are actually going to execute.
  # (Common workflows like `--targets local` or `--targets arm64-linux` should not
  # fail just because remote x64 prerequisites aren't installed.)
  if has_target arm64-linux || has_target x64-linux-qemu; then
    need_bin docker
  fi
  if [[ "$SKIP_REMOTE" -eq 0 ]] && ( has_target x64-win || has_target x64-wsl || has_target x64-win-tier1 || has_target x64-wsl-tier1 ); then
    need_bin ssh
    need_bin scp
    need_bin tar
    need_bin grep
    if [[ -n "$REMOTE_PROXY" ]] && [[ "$REMOTE_PROXY" == *socat* ]]; then
      need_bin socat
    fi
  fi
fi

if [[ "$SKIP_REMOTE" -ne 0 && "$TARGETS_CSV" != "all" ]]; then
  # Explicit remote target selection + skip-remote is contradictory; force callers to be clear.
  if has_target x64-win || has_target x64-wsl || has_target x64-win-tier1 || has_target x64-wsl-tier1; then
    echo "ERROR: --skip-remote cannot be used when --targets explicitly includes remote x64 targets" >&2
    echo "Hint: use --targets local,arm64-linux (no remote), or omit --skip-remote to run remote verification." >&2
    exit 2
  fi
fi

run_with_timeout() {
  local secs="$1"
  shift
  local had_errexit=0
  case "$-" in
    *e*) had_errexit=1 ;;
  esac
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
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  fi
  return "$rc"
}

need_stage1_and_stage2() {
  # The purpose of this script is to verify the **native backend** artifacts produced by:
  # - stage1 compiler (`./oren`)
  # - stage2 compiler (`./oren_stage2`)
  #
  # Rolling: `make stage2` now builds `./oren_stage2` via the native backend by default on arm64-macos too.
  # If you need the legacy C-backend bootstrap, use: `make stage2 OREN_STAGE2_BACKEND=c`.
  if [[ ! -x ./oren ]]; then
    log "== ensure: stage1 compiler (./oren) =="
    make stage1
  fi
  if [[ ! -x ./oren_stage2 ]]; then
    log "== ensure: stage2 compiler (./oren_stage2) =="
    make stage2
  fi
}

if has_target stage0; then
  log "== build: stage0 (Go bootstrap) =="
  make bootstrap
fi
if has_target stage1; then
  log "== build: stage1 (self-hosted) =="
  make stage1
fi
if has_target stage2; then
  log "== build: stage2 (self-hosted) =="
  make stage2
fi

# For any verification target (local/docker/remote), ensure stage1+stage2 compilers exist.
if has_target local || has_target arm64-linux || has_target x64-linux-qemu || has_target x64-win || has_target x64-wsl; then
  need_stage1_and_stage2
fi

if has_target local; then
  log "== verify: local host platform (stage1 + stage2) =="
  make verify-native-quick
fi

if [[ "$LOCAL_ONLY" -ne 0 ]]; then
  log "OK: local-only verification complete"
  exit 0
fi

build_native_bin_src() {
  local compiler="$1"
  local platform="$2"
  local src="$3"
  local out="$4"
  shift 4

  if [[ ! -x "$compiler" ]]; then
    echo "ERROR: missing compiler executable: $compiler (build with: make stage1 stage2)" >&2
    exit 2
  fi
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECS" "$compiler" build "$src" --backend native --platform "$platform" --debug -o "$out" "$@"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: build failed or timed out: compiler=$compiler platform=$platform src=$src timeout=${BUILD_TIMEOUT_SECS}s" >&2
    exit "$rc"
  fi
}

build_native_bin() {
  local compiler="$1"
  local platform="$2"
  local out="$3"
  build_native_bin_src "$compiler" "$platform" "$TEST_SRC" "$out"
}

build_green_worker_fixtures() {
  local platform="$1"
  local ext=""
  if [[ "$platform" == "x64-windows" ]]; then
    ext=".exe"
  fi
  # Keep this list small and high-signal: it should remain reasonable as part of Tier‑1 gates.
  #
  # Intent:
  # - world lock safety w/ 2 workers (allocator/GC not parallel yet)
  # - real spawn injection path acquires extra P (M<P) in world-lock mode
  # - deterministic P swap + P2 acquisition (test-only debug API)
  build_native_bin_src "./oren" "$platform" "$GREEN_2W_WORLD_LOCK_SRC" "build/tmp/green2w_world_lock_stage1_${platform}${ext}"
  build_native_bin_src "./oren_stage2" "$platform" "$GREEN_2W_WORLD_LOCK_SRC" "build/tmp/green2w_world_lock_stage2_${platform}${ext}"
  build_native_bin_src "./oren" "$platform" "$GREEN_2W_M_LESS_P_SMOKE_SRC" "build/tmp/green2w_m_less_p_smoke_stage1_${platform}${ext}"
  build_native_bin_src "./oren_stage2" "$platform" "$GREEN_2W_M_LESS_P_SMOKE_SRC" "build/tmp/green2w_m_less_p_smoke_stage2_${platform}${ext}"
  build_native_bin_src "./oren" "$platform" "$GREEN_2W_M_LESS_P_DETERMINISTIC_SRC" "build/tmp/green2w_m_less_p_det_stage1_${platform}${ext}"
  build_native_bin_src "./oren_stage2" "$platform" "$GREEN_2W_M_LESS_P_DETERMINISTIC_SRC" "build/tmp/green2w_m_less_p_det_stage2_${platform}${ext}"
}

run_in_linux_container() {
  local bin="$1"
  local dst="/tmp/$(basename "$bin")"
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  local canon_env=""
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    canon_env="OREN_CANON_I32_ABORT=1 "
  fi

  # Best-effort cleanup of any previous stuck processes/artifacts.
  docker exec -i "$LINUX_DOCKER_ID" bash -lc 'pkill -9 -x qi_stage1_arm64_linux >/dev/null 2>&1 || true; pkill -9 -x qi_stage2_arm64_linux >/dev/null 2>&1 || true; rm -f /tmp/qi_stage* || true' >/dev/null 2>&1 || true
  docker cp "$bin" "${LINUX_DOCKER_ID}:${dst}"
  docker exec -i "$LINUX_DOCKER_ID" bash -lc "chmod +x '$dst' && ${canon_env}'$dst'"
}

run_in_linux_container_expect_fail_contains() {
  local bin="$1"
  local needle="$2"
  local needle2="${3:-}"
  local dst="/tmp/$(basename "$bin")"
  local out="/tmp/oren_$(basename "$bin").out"

  docker cp "$bin" "${LINUX_DOCKER_ID}:${dst}"
  if [[ -n "$needle2" ]]; then
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "chmod +x '$dst'; rm -f '$out'; set +e; '$dst' >'$out' 2>&1; rc=\$?; set -e; cat '$out'; echo EXIT=\$rc; if [ \$rc -eq 0 ]; then exit 96; fi; grep -qF \"$needle\" '$out' && grep -qF \"$needle2\" '$out'"
  else
    docker exec -i "$LINUX_DOCKER_ID" bash -lc "chmod +x '$dst'; rm -f '$out'; set +e; '$dst' >'$out' 2>&1; rc=\$?; set -e; cat '$out'; echo EXIT=\$rc; if [ \$rc -eq 0 ]; then exit 96; fi; grep -qF \"$needle\" '$out'"
  fi
}

remote_user="$REMOTE_HOST"
if [[ "$REMOTE_HOST" == *"@"* ]]; then
  remote_user="${REMOTE_HOST%@*}"
fi
# IMPORTANT: for OpenSSH on Windows, scp/sftp path handling is not consistent for POSIX-style
# absolute paths like `/Users/<name>/...`. Use a home-relative path for reliability unless
# an explicit SSH root is provided (e.g. "G:/work/tmp_oren").
remote_win_root="${OREN_REMOTE_X64_WIN_ROOT:-C:\\Users\\${remote_user}\\tmp_oren}"
remote_win_root_cmd="${remote_win_root//\//\\}"
remote_unix_root="${OREN_REMOTE_X64_SSH_ROOT:-}"
if [[ -z "$remote_unix_root" ]]; then
  if [[ -n "${OREN_REMOTE_X64_WIN_ROOT:-}" ]]; then
    remote_unix_root="${remote_win_root_cmd//\\//}"
  else
    remote_unix_root="tmp_oren"
  fi
fi
remote_wsl_root="${OREN_REMOTE_X64_WSL_ROOT:-}"
if [[ -z "$remote_wsl_root" ]]; then
  if [[ -n "${OREN_REMOTE_X64_WIN_ROOT:-}" && "$remote_win_root_cmd" =~ ^([A-Za-z]):\\(.*)$ ]]; then
    drive="${BASH_REMATCH[1],,}"
    rest="${BASH_REMATCH[2]//\\//}"
    remote_wsl_root="/mnt/${drive}/${rest}"
  else
    remote_wsl_root="/mnt/c/Users/${remote_user}/tmp_oren"
  fi
fi

ssh_opt_proxy=()
scp_opt_proxy=()
if [[ -n "$REMOTE_PROXY" ]]; then
  ssh_opt_proxy=(-o "$REMOTE_PROXY")
  scp_opt_proxy=(-o "$REMOTE_PROXY")
fi

ssh_base=(ssh "${ssh_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 "$REMOTE_HOST")
# OpenSSH scp defaults to SFTP mode on modern clients; Windows OpenSSH servers can be flaky under
# proxying/SSH jump setups. Allow forcing legacy scp protocol for reliability.
scp_legacy="${OREN_SCP_LEGACY:-1}"
scp_legacy_opt=()
if [[ -n "$scp_legacy" && "$scp_legacy" != "0" ]]; then
  scp_legacy_opt=(-O)
fi
scp_base=(scp -q -C "${scp_legacy_opt[@]}" "${scp_opt_proxy[@]}" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

remote_preflight() {
  mkdir -p build/logs
  local logf="build/logs/native_matrix_remote_probe.log"

  log "== remote: ssh probe =="
  local attempt=1
  while true; do
    : >"$logf"
    set +e
    run_with_timeout 15 "${ssh_base[@]}" "cmd.exe /c \"echo OREN_REMOTE_OK\"" >"$logf" 2>&1
    local rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      if grep -q "OREN_REMOTE_OK" "$logf" 2>/dev/null; then
        log "OK: remote ssh probe"
        return 0
      fi
    fi

    # Flaky proxy/ssh can hang long enough to hit the outer timeout (rc=143 from SIGTERM).
    # Retry once so the whole matrix isn't blocked by a single transient.
    if [[ "$attempt" -ge 2 ]]; then
      echo "ERROR: cannot reach remote x64 host via ssh (rc=$rc host=$REMOTE_HOST)" >&2
      tail -n 80 "$logf" >&2 2>/dev/null || true
      if grep -Eq 'socat\\[[0-9]+\\] W CONNECT .*:22: Not Found' "$logf" 2>/dev/null; then
        echo "HINT: ProxyCommand could not resolve the hostname. Try setting:" >&2
        echo "  OREN_REMOTE_X64_HOST=<user@IP>" >&2
        echo "or override OREN_REMOTE_X64_PROXY to a direct SSH connection (no proxy)." >&2
      fi
      if [[ "$REMOTE_HOST" == *"pc.work"* ]]; then
        echo "HINT: If 'pc.work' is not resolvable from this network, set:" >&2
        echo "  OREN_REMOTE_X64_HOST=<user@IP>" >&2
      fi
      echo "log=$logf" >&2
      exit 2
    fi

    echo "WARN: remote ssh probe failed (attempt ${attempt} rc=${rc}); retrying..." >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

remote_wsl_preflight() {
  if ! has_target x64-wsl && ! has_target x64-wsl-tier1; then
    return 0
  fi
  if [[ "$SKIP_REMOTE" -ne 0 ]]; then
    return 0
  fi
  mkdir -p build/logs
  local logf="build/logs/native_matrix_remote_wsl_probe.log"
  log "== remote: wsl probe =="
  : >"$logf"
  set +e
  run_with_timeout 15 "${ssh_base[@]}" "cmd.exe /c \"wsl.exe -e bash -lc \\\"echo OREN_WSL_OK\\\"\"" >"$logf" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] && grep -q "OREN_WSL_OK" "$logf" 2>/dev/null; then
    log "OK: remote WSL probe"
    return 0
  fi
  echo "ERROR: remote WSL2 is not available (x64-wsl targets requested) host=$REMOTE_HOST" >&2
  tail -n 80 "$logf" >&2 2>/dev/null || true
  echo "HINT: install WSL on the remote host (wsl.exe --install) or run --targets x64-win-tier1 only." >&2
  echo "log=$logf" >&2
  exit 3
}

remote_mkdir() {
  # Ensure the Windows user profile staging directory exists. (This also backs the WSL /mnt/c path.)
  # IMPORTANT: `cmd.exe` can inherit a non-zero ERRORLEVEL under some ssh server setups.
  # Force success to avoid "false failures" when the directory already exists.
  "${ssh_base[@]}" "cmd.exe /c \"if not exist \\\"${remote_win_root_cmd}\\\" mkdir \\\"${remote_win_root_cmd}\\\" 2>nul & exit /b 0\""
}

remote_del() {
  # Best-effort remove of a previously-uploaded artifact.
  # This avoids intermittent scp failures when a prior run left the file locked/read-only.
  local name="$1"
  "${ssh_base[@]}" "cmd.exe /c \"del /f /q \\\"${remote_win_root_cmd}\\\\${name}\\\" 2>nul\""
}

remote_kill_win() {
  local exe="$1"
  "${ssh_base[@]}" "cmd.exe /c \"taskkill /f /im ${exe} >nul 2>nul\""
}

remote_kill_wsl() {
  local exe="$1"
  # Best-effort: kill by process name (not `-f`), otherwise it can match the current shell command line.
  "${ssh_base[@]}" "wsl.exe -e bash -lc \"pkill -9 -x '${exe}' >/dev/null 2>&1 || true\""
}

remote_upload() {
  local src="$1"
  local dst_name="$2"
  # Best-effort pre-delete: leaving a stale or locked file can cause scp to fail on Windows OpenSSH.
  # Network connectivity to the proxy can also be flaky; retries keep Tier‑1 verification ergonomic.
  remote_del "$dst_name" >/dev/null 2>&1 || true

  local attempt=1
  while true; do
    set +e
    "${scp_base[@]}" "$src" "${REMOTE_HOST}:${remote_unix_root}/${dst_name}"
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi

    if [[ "$attempt" -ge "$SCP_RETRIES" ]]; then
      echo "ERROR: scp failed after ${attempt}/${SCP_RETRIES} attempts: ${src} -> ${dst_name} (rc=${rc})" >&2
      return "$rc"
    fi

    echo "WARN: scp failed (attempt ${attempt}/${SCP_RETRIES}) rc=${rc}; retrying..." >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

remote_run_win() {
  local exe_name="$1"
  shift || true
  remote_kill_win "$exe_name" >/dev/null 2>&1 || true
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  local envp=""
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    envp="set OREN_CANON_I32_ABORT=1 & "
  fi
  # Optional extra environment variables (KEY=VALUE) for this run.
  #
  # IMPORTANT (cmd.exe quoting): keep this strict and avoid introducing `&`/`|` injection hazards.
  if [[ "$#" -gt 0 ]]; then
    for kv in "$@"; do
      if [[ -z "$kv" || "$kv" != *"="* ]]; then
        echo "ERROR: remote_run_win expects KEY=VALUE env items; got: $kv" >&2
        return 2
      fi
      if [[ "$kv" == *" "* || "$kv" == *"&"* || "$kv" == *"|"* || "$kv" == *"<"* || "$kv" == *">"* ]]; then
        echo "ERROR: remote_run_win env contains unsafe characters (spaces or shell metachars): $kv" >&2
        return 2
      fi
      envp+="set ${kv} & "
    done
  fi
  local want_tier1=0
  if [[ "$exe_name" == tier1_* ]]; then
    want_tier1=1
  fi
  set +e
  # Preserve the program's exit code (do not let trailing `echo` mask failures).
  #
  # Additionally, Tier‑1 fixtures must print key markers; otherwise we treat it as a failure
  # even if the process exits 0 (prevents silent early-exit false positives).
  local cmd=""
  if [[ "$want_tier1" -ne 0 ]]; then
    cmd="${envp}set OUT=%TEMP%\\\\oren_${exe_name}.out & del /f /q !OUT! >NUL 2>&1 & ${remote_win_root_cmd}\\\\${exe_name} > !OUT! 2>&1 & set RC=!ERRORLEVEL! & type !OUT! & echo EXIT=!RC!"
    if [[ "$TIER1_EXPECT_MARKERS" -ne 0 ]]; then
      cmd+=" & if !RC! EQU 0 (findstr /C:\"tier1 spawn join ok\" !OUT! >NUL || exit /b 97)"
      cmd+=" & if !RC! EQU 0 (findstr /C:\"tier1 proc ok\" !OUT! >NUL || exit /b 98)"
    fi
    cmd+=" & exit /b !RC!"
  else
    cmd="${envp}${remote_win_root_cmd}\\\\${exe_name} & set RC=!ERRORLEVEL! & echo EXIT=!RC! & exit /b !RC!"
  fi
  run_with_timeout 30 "${ssh_base[@]}" "cmd.exe /v:on /c \"${cmd}\""
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_win "$exe_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

remote_run_wsl() {
  local bin_name="$1"
  shift || true
  remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  # Use WSL-side `timeout` to avoid leaving background processes if the outer ssh is terminated.
  local envp=""
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    envp="OREN_CANON_I32_ABORT=1 "
  fi
  # Optional extra environment variables (KEY=VALUE) for this run.
  if [[ "$#" -gt 0 ]]; then
    for kv in "$@"; do
      if [[ -z "$kv" || "$kv" != *"="* ]]; then
        echo "ERROR: remote_run_wsl expects KEY=VALUE env items; got: $kv" >&2
        return 2
      fi
      # Keep quoting simple: disallow chars that break `bash -lc "..."` and avoid injection hazards.
      if [[ "$kv" == *" "* || "$kv" == *"\""* || "$kv" == *"'"* || "$kv" == *"$"* || "$kv" == *"\\"* ]]; then
        echo "ERROR: remote_run_wsl env contains unsafe characters: $kv" >&2
        return 2
      fi
      envp+="${kv} "
    done
  fi
  if [[ "$TRACE" -ne 0 ]]; then
    envp+="OREN_QI_TRACE=1 "
  fi
  local full="${remote_wsl_root}/${bin_name}"
  local want_tier1=0
  if [[ "$bin_name" == tier1_* ]]; then
    want_tier1=1
  fi

  # Preserve the program's exit code and emit a stable EXIT=... marker for log scanning.
  #
  # Additionally, Tier‑1 fixtures must print key markers; otherwise we treat it as a failure
  # even if the process exits 0 (prevents silent early-exit false positives).
  local cmd=""
  if [[ "$want_tier1" -ne 0 ]]; then
    local out="/tmp/oren_${bin_name}.out"
    cmd="file ${full} || true; chmod +x ${full} && rm -f '${out}'; ${envp}timeout 20s ${full} >'${out}' 2>&1; rc="
    cmd+='$?'
    cmd+="; cat '${out}'; echo EXIT="
    cmd+='$rc'
    if [[ "$TIER1_EXPECT_MARKERS" -ne 0 ]]; then
      # Only enforce marker checks on successful exit. If the program fails, preserve its
      # real exit code (the output already includes a stable EXIT=... marker).
      cmd+="; if [ "
      cmd+='$rc'
      cmd+=" -eq 0 ]; then grep -q 'tier1 spawn join ok' '${out}' || exit 97; grep -q 'tier1 proc ok' '${out}' || exit 98; fi"
    fi
    cmd+="; exit "
    cmd+='$rc'
  else
    cmd="file ${full} || true; chmod +x ${full} && ${envp}timeout 20s ${full}; rc="
    cmd+='$?'
    cmd+="; echo EXIT="
    cmd+='$rc'
    cmd+="; exit "
    cmd+='$rc'
  fi
  set +e
  run_with_timeout 30 "${ssh_base[@]}" "wsl.exe -e bash -lc \"${cmd}\""
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

remote_run_wsl_expect_fail_contains() {
  local bin_name="$1"
  local needle="$2"
  local needle2="${3:-}"
  remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  local full="${remote_wsl_root}/${bin_name}"
  local envp=""
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    envp="OREN_CANON_I32_ABORT=1 "
  fi
  if [[ "$TRACE" -ne 0 ]]; then
    envp+="OREN_QI_TRACE=1 "
  fi

  local out="/tmp/oren_${bin_name}.out"
  local cmd="file ${full} || true; chmod +x ${full} && rm -f '${out}'; ${envp}timeout 20s ${full} >'${out}' 2>&1; rc="
  cmd+='$?'
  cmd+="; cat '${out}'; echo EXIT="
  cmd+='$rc'
  cmd+="; if [ "
  cmd+='$rc'
  # IMPORTANT (Windows ssh/cmd.exe quoting): avoid double quotes inside the WSL command string,
  # otherwise `cmd.exe` can terminate the outer `"..."` early and truncate the script.
  cmd+=" -eq 0 ]; then exit 96; fi; grep -qF '"
  cmd+="$needle"
  cmd+="' '${out}' || exit 97; "
  if [[ -n "$needle2" ]]; then
    cmd+="grep -qF '"
    cmd+="$needle2"
    cmd+="' '${out}' || exit 98; "
  fi
  cmd+="exit 0"

  set +e
  run_with_timeout 30 "${ssh_base[@]}" "wsl.exe -e bash -lc \"${cmd}\""
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

remote_run_wsl_expect_ok_contains() {
  local bin_name="$1"
  local needle="$2"
  local needle2="${3:-}"
  remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  local full="${remote_wsl_root}/${bin_name}"
  local envp=""
  local canon_abort="${OREN_CANON_I32_ABORT:-}"
  if [[ -n "$canon_abort" && "$canon_abort" != "0" ]]; then
    envp="OREN_CANON_I32_ABORT=1 "
  fi
  if [[ "$TRACE" -ne 0 ]]; then
    envp+="OREN_QI_TRACE=1 "
  fi

  local out="/tmp/oren_${bin_name}.out"
  local cmd="file ${full} || true; chmod +x ${full} && rm -f '${out}'; ${envp}timeout 20s ${full} >'${out}' 2>&1; rc="
  cmd+='$?'
  cmd+="; cat '${out}'; echo EXIT="
  cmd+='$rc'
  cmd+="; if [ "
  cmd+='$rc'
  cmd+=" -ne 0 ]; then exit 96; fi; grep -qF '"
  cmd+="$needle"
  cmd+="' '${out}' || exit 97; "
  if [[ -n "$needle2" ]]; then
    cmd+="grep -qF '"
    cmd+="$needle2"
    cmd+="' '${out}' || exit 98; "
  fi
  cmd+="exit 0"

  set +e
  run_with_timeout 30 "${ssh_base[@]}" "wsl.exe -e bash -lc \"${cmd}\""
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    remote_kill_wsl "$bin_name" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

if has_target arm64-linux; then
  log "== verify: linux/arm64 via docker container id=${LINUX_DOCKER_ID} =="
  docker ps --filter "id=${LINUX_DOCKER_ID}" --format 'id={{.ID}} status={{.Status}}' | grep -q "id=${LINUX_DOCKER_ID}" || {
    echo "ERROR: required persistent container not running: ${LINUX_DOCKER_ID}" >&2
    exit 2
  }

  build_native_bin "./oren" "arm64-linux" "build/tmp/qi_stage1_arm64_linux"
  build_native_bin "./oren_stage2" "arm64-linux" "build/tmp/qi_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_FFI_PANIC_SRC" "build/tmp/ffi_panic_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_FFI_PANIC_SRC" "build/tmp/ffi_panic_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_FFI_OK_SRC" "build/tmp/ffi_ok_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_FFI_OK_SRC" "build/tmp/ffi_ok_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_FFI_I32_SRC" "build/tmp/ffi_i32_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_FFI_I32_SRC" "build/tmp/ffi_i32_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_FFI_U32_SRC" "build/tmp/ffi_u32_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_FFI_U32_SRC" "build/tmp/ffi_u32_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_FFI_VOID_SRC" "build/tmp/ffi_void_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_FFI_VOID_SRC" "build/tmp/ffi_void_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage2_arm64_linux"
  build_native_bin_src "./oren" "arm64-linux" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage1_arm64_linux"
  build_native_bin_src "./oren_stage2" "arm64-linux" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage2_arm64_linux"
  # Shared library output: `.so` + generated header.
  build_native_bin_src "./oren" "arm64-linux" "$LIBMATH_SRC" "build/tmp/libmath_stage1_arm64_linux.so" --lib
  build_native_bin_src "./oren_stage2" "arm64-linux" "$LIBMATH_SRC" "build/tmp/libmath_stage2_arm64_linux.so" --lib
  file "build/tmp/libmath_stage1_arm64_linux.so" | grep -Ei 'ELF 64-bit.*(shared object.*(ARM aarch64|aarch64)|(ARM aarch64|aarch64).*shared object)' >/dev/null
  file "build/tmp/libmath_stage2_arm64_linux.so" | grep -Ei 'ELF 64-bit.*(shared object.*(ARM aarch64|aarch64)|(ARM aarch64|aarch64).*shared object)' >/dev/null
  test -f "build/tmp/libmath_stage1_arm64_linux.h"
  test -f "build/tmp/libmath_stage2_arm64_linux.h"
  grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' "build/tmp/libmath_stage1_arm64_linux.h" >/dev/null
  grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' "build/tmp/libmath_stage1_arm64_linux.h" >/dev/null
  grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' "build/tmp/libmath_stage2_arm64_linux.h" >/dev/null
  grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' "build/tmp/libmath_stage2_arm64_linux.h" >/dev/null
  run_in_linux_container "build/tmp/qi_stage1_arm64_linux"
  run_in_linux_container "build/tmp/qi_stage2_arm64_linux"
  run_in_linux_container_expect_fail_contains "build/tmp/ffi_panic_stage1_arm64_linux" "ffi unresolved:" "oren_panic"
  run_in_linux_container_expect_fail_contains "build/tmp/ffi_panic_stage2_arm64_linux" "ffi unresolved:" "oren_panic"
  run_in_linux_container "build/tmp/ffi_ok_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ffi_ok_stage2_arm64_linux"
  run_in_linux_container "build/tmp/std_ffi_libc_smoke_stage1_arm64_linux"
  run_in_linux_container "build/tmp/std_ffi_libc_smoke_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ffi_i32_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ffi_i32_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ffi_u32_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ffi_u32_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ffi_void_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ffi_void_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ulock_timeout_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ulock_timeout_stage2_arm64_linux"
  run_in_linux_container "build/tmp/ulock_timeout_portable_stage1_arm64_linux"
  run_in_linux_container "build/tmp/ulock_timeout_portable_stage2_arm64_linux"
  run_in_linux_container "build/tmp/os_thread_park_unpark_stage1_arm64_linux"
  run_in_linux_container "build/tmp/os_thread_park_unpark_stage2_arm64_linux"
  run_in_linux_container "build/tmp/os_thread_spawn_many_stage1_arm64_linux"
  run_in_linux_container "build/tmp/os_thread_spawn_many_stage2_arm64_linux"
  log "OK: linux/arm64 container"
fi

if has_target x64-linux-qemu; then
  log "== verify: x64-linux runtime smoke under qemu-x86_64 (linux container) =="
  # This gate is intentionally separate from remote WSL2:
  # - it catches runtime/codegen issues that compile-only checks miss
  # - it stays usable even when remote Win11/WSL2 is unreachable
  #
  # Requires `make setup-x64-linux-qemu` once to install the amd64 loader in the container.
  ./scripts/verify_x64_linux_qemu_smoke.sh
fi

if has_target x64-win || has_target x64-wsl || has_target x64-win-tier1 || has_target x64-wsl-tier1; then
  if [[ "$SKIP_REMOTE" -ne 0 ]]; then
    log "SKIP: remote x64 Windows + WSL2 disabled by --skip-remote"
  else
    log "== verify: remote x64 Windows + WSL2 via ${REMOTE_HOST} =="
    remote_preflight
    remote_mkdir
    remote_wsl_preflight
  fi
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-win; then
  build_native_bin "./oren" "x64-windows" "build/tmp/qi_stage1_x64_windows.exe"
  build_native_bin "./oren_stage2" "x64-windows" "build/tmp/qi_stage2_x64_windows.exe"

  build_native_bin_src "./oren" "x64-windows" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage2_x64_windows.exe"

  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_K32_SRC" "build/tmp/ffi_k32_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_K32_SRC" "build/tmp/ffi_k32_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$STD_FFI_KERNEL32_SMOKE_SRC" "build/tmp/std_ffi_kernel32_smoke_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$STD_FFI_KERNEL32_SMOKE_SRC" "build/tmp/std_ffi_kernel32_smoke_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_MSVCRT_ATTR_SRC" "build/tmp/ffi_msvcrt_attr_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_MSVCRT_ATTR_SRC" "build/tmp/ffi_msvcrt_attr_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_MSVCRT_LINK_ATTR_SRC" "build/tmp/ffi_msvcrt_link_attr_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_MSVCRT_LINK_ATTR_SRC" "build/tmp/ffi_msvcrt_link_attr_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_I32_SRC" "build/tmp/ffi_i32_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_I32_SRC" "build/tmp/ffi_i32_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_U32_SRC" "build/tmp/ffi_u32_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_U32_SRC" "build/tmp/ffi_u32_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_VOID_SRC" "build/tmp/ffi_void_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_VOID_SRC" "build/tmp/ffi_void_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_FFI_EXPORT_GETPROC_SRC" "build/tmp/ffi_export_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_FFI_EXPORT_GETPROC_SRC" "build/tmp/ffi_export_stage2_x64_windows.exe"
  build_native_bin_src "./oren" "x64-windows" "$WIN_DNS_DEFAULT_RESOLVER_SMOKE" "build/tmp/win_dns_default_resolver_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_DNS_DEFAULT_RESOLVER_SMOKE" "build/tmp/win_dns_default_resolver_stage2_x64_windows.exe"

  remote_upload "build/tmp/qi_stage1_x64_windows.exe" "qi_stage1_x64_windows.exe"
  remote_upload "build/tmp/qi_stage2_x64_windows.exe" "qi_stage2_x64_windows.exe"
  remote_upload "build/tmp/ulock_timeout_portable_stage1_x64_windows.exe" "ulock_timeout_portable_stage1_x64_windows.exe"
  remote_upload "build/tmp/ulock_timeout_portable_stage2_x64_windows.exe" "ulock_timeout_portable_stage2_x64_windows.exe"
  remote_upload "build/tmp/os_thread_park_unpark_stage1_x64_windows.exe" "os_thread_park_unpark_stage1_x64_windows.exe"
  remote_upload "build/tmp/os_thread_park_unpark_stage2_x64_windows.exe" "os_thread_park_unpark_stage2_x64_windows.exe"
  remote_upload "build/tmp/os_thread_spawn_many_stage1_x64_windows.exe" "os_thread_spawn_many_stage1_x64_windows.exe"
  remote_upload "build/tmp/os_thread_spawn_many_stage2_x64_windows.exe" "os_thread_spawn_many_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_k32_stage1_x64_windows.exe" "ffi_k32_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_k32_stage2_x64_windows.exe" "ffi_k32_stage2_x64_windows.exe"
  remote_upload "build/tmp/std_ffi_libc_smoke_stage1_x64_windows.exe" "std_ffi_libc_smoke_stage1_x64_windows.exe"
  remote_upload "build/tmp/std_ffi_libc_smoke_stage2_x64_windows.exe" "std_ffi_libc_smoke_stage2_x64_windows.exe"
  remote_upload "build/tmp/std_ffi_kernel32_smoke_stage1_x64_windows.exe" "std_ffi_kernel32_smoke_stage1_x64_windows.exe"
  remote_upload "build/tmp/std_ffi_kernel32_smoke_stage2_x64_windows.exe" "std_ffi_kernel32_smoke_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_msvcrt_attr_stage1_x64_windows.exe" "ffi_msvcrt_attr_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_msvcrt_attr_stage2_x64_windows.exe" "ffi_msvcrt_attr_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_msvcrt_link_attr_stage1_x64_windows.exe" "ffi_msvcrt_link_attr_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_msvcrt_link_attr_stage2_x64_windows.exe" "ffi_msvcrt_link_attr_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_i32_stage1_x64_windows.exe" "ffi_i32_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_i32_stage2_x64_windows.exe" "ffi_i32_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_u32_stage1_x64_windows.exe" "ffi_u32_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_u32_stage2_x64_windows.exe" "ffi_u32_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_void_stage1_x64_windows.exe" "ffi_void_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_void_stage2_x64_windows.exe" "ffi_void_stage2_x64_windows.exe"
  remote_upload "build/tmp/ffi_export_stage1_x64_windows.exe" "ffi_export_stage1_x64_windows.exe"
  remote_upload "build/tmp/ffi_export_stage2_x64_windows.exe" "ffi_export_stage2_x64_windows.exe"
  remote_upload "build/tmp/win_dns_default_resolver_stage1_x64_windows.exe" "win_dns_default_resolver_stage1_x64_windows.exe"
  remote_upload "build/tmp/win_dns_default_resolver_stage2_x64_windows.exe" "win_dns_default_resolver_stage2_x64_windows.exe"

  log "-- run: Win11 (x64-windows) --"
  remote_run_win "qi_stage1_x64_windows.exe"
  remote_run_win "qi_stage2_x64_windows.exe"
  remote_run_win "ulock_timeout_portable_stage1_x64_windows.exe"
  remote_run_win "ulock_timeout_portable_stage2_x64_windows.exe"
  remote_run_win "os_thread_park_unpark_stage1_x64_windows.exe"
  remote_run_win "os_thread_park_unpark_stage2_x64_windows.exe"
  remote_run_win "os_thread_spawn_many_stage1_x64_windows.exe"
  remote_run_win "os_thread_spawn_many_stage2_x64_windows.exe"
  remote_run_win "ffi_k32_stage1_x64_windows.exe"
  remote_run_win "ffi_k32_stage2_x64_windows.exe"
  remote_run_win "std_ffi_libc_smoke_stage1_x64_windows.exe"
  remote_run_win "std_ffi_libc_smoke_stage2_x64_windows.exe"
  remote_run_win "std_ffi_kernel32_smoke_stage1_x64_windows.exe"
  remote_run_win "std_ffi_kernel32_smoke_stage2_x64_windows.exe"
  remote_run_win "ffi_msvcrt_attr_stage1_x64_windows.exe"
  remote_run_win "ffi_msvcrt_attr_stage2_x64_windows.exe"
  remote_run_win "ffi_msvcrt_link_attr_stage1_x64_windows.exe"
  remote_run_win "ffi_msvcrt_link_attr_stage2_x64_windows.exe"
  remote_run_win "ffi_i32_stage1_x64_windows.exe"
  remote_run_win "ffi_i32_stage2_x64_windows.exe"
  remote_run_win "ffi_u32_stage1_x64_windows.exe"
  remote_run_win "ffi_u32_stage2_x64_windows.exe"
  remote_run_win "ffi_void_stage1_x64_windows.exe"
  remote_run_win "ffi_void_stage2_x64_windows.exe"
  remote_run_win "ffi_export_stage1_x64_windows.exe"
  remote_run_win "ffi_export_stage2_x64_windows.exe"
  remote_run_win "win_dns_default_resolver_stage1_x64_windows.exe"
  remote_run_win "win_dns_default_resolver_stage2_x64_windows.exe"
  log "OK: remote Win11 x64"
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-win-tier1; then
  build_native_bin_src "./oren" "x64-windows" "$TIER1_SRC" "build/tmp/tier1_stage1_x64_windows.exe"
  build_native_bin_src "./oren_stage2" "x64-windows" "$TIER1_SRC" "build/tmp/tier1_stage2_x64_windows.exe"

  remote_upload "build/tmp/tier1_stage1_x64_windows.exe" "tier1_stage1_x64_windows.exe"
  remote_upload "build/tmp/tier1_stage2_x64_windows.exe" "tier1_stage2_x64_windows.exe"

  log "-- run: Win11 Tier‑1 native smoke (x64-windows) --"
  remote_run_win "tier1_stage1_x64_windows.exe"
  remote_run_win "tier1_stage2_x64_windows.exe"
  log "-- run: Win11 Tier‑1 native smoke (x64-windows; OREN_NO_GREEN=1) --"
  remote_run_win "tier1_stage1_x64_windows.exe" "OREN_NO_GREEN=1"
  remote_run_win "tier1_stage2_x64_windows.exe" "OREN_NO_GREEN=1"

  # When running the default Tier‑1 smoke, extend it with a small set of green-worker (GMP) fixtures.
  # This keeps Windows/WSL2 coverage “automatic” for the current P0 focus area.
  if [[ "$TIER1_EXPECT_MARKERS" -ne 0 ]]; then
    log "-- build+run: Win11 IOCP wake smoke (x64-windows; OREN_NETPOLL_WIN_IOCP=1) --"
    build_native_bin_src "./oren" "x64-windows" "$WIN_IOCP_WAKE_SMOKE_SRC" "build/tmp/win_iocp_wake_stage1_x64_windows.exe"
    build_native_bin_src "./oren_stage2" "x64-windows" "$WIN_IOCP_WAKE_SMOKE_SRC" "build/tmp/win_iocp_wake_stage2_x64_windows.exe"
    remote_upload "build/tmp/win_iocp_wake_stage1_x64_windows.exe" "win_iocp_wake_stage1_x64_windows.exe"
    remote_upload "build/tmp/win_iocp_wake_stage2_x64_windows.exe" "win_iocp_wake_stage2_x64_windows.exe"
    remote_run_win "win_iocp_wake_stage1_x64_windows.exe" "OREN_NETPOLL_WIN_IOCP=1"
    remote_run_win "win_iocp_wake_stage2_x64_windows.exe" "OREN_NETPOLL_WIN_IOCP=1"

    log "-- build+run: Win11 Tier‑1 green-worker fixtures (x64-windows) --"
    build_green_worker_fixtures "x64-windows"
    remote_upload "build/tmp/green2w_world_lock_stage1_x64-windows.exe" "green2w_world_lock_stage1_x64_windows.exe"
    remote_upload "build/tmp/green2w_world_lock_stage2_x64-windows.exe" "green2w_world_lock_stage2_x64_windows.exe"
    remote_upload "build/tmp/green2w_m_less_p_smoke_stage1_x64-windows.exe" "green2w_m_less_p_smoke_stage1_x64_windows.exe"
    remote_upload "build/tmp/green2w_m_less_p_smoke_stage2_x64-windows.exe" "green2w_m_less_p_smoke_stage2_x64_windows.exe"
    remote_upload "build/tmp/green2w_m_less_p_det_stage1_x64-windows.exe" "green2w_m_less_p_det_stage1_x64_windows.exe"
    remote_upload "build/tmp/green2w_m_less_p_det_stage2_x64-windows.exe" "green2w_m_less_p_det_stage2_x64_windows.exe"
    remote_run_win "green2w_world_lock_stage1_x64_windows.exe"
    remote_run_win "green2w_world_lock_stage2_x64_windows.exe"
    remote_run_win "green2w_m_less_p_smoke_stage1_x64_windows.exe"
    remote_run_win "green2w_m_less_p_smoke_stage2_x64_windows.exe"
    remote_run_win "green2w_m_less_p_det_stage1_x64_windows.exe"
    remote_run_win "green2w_m_less_p_det_stage2_x64_windows.exe"
  fi
  log "OK: remote Win11 x64 tier1"
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-wsl; then
  build_native_bin "./oren" "x64-linux" "build/tmp/qi_stage1_x64_linux"
  build_native_bin "./oren_stage2" "x64-linux" "build/tmp/qi_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_FFI_PANIC_SRC" "build/tmp/ffi_panic_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_FFI_PANIC_SRC" "build/tmp/ffi_panic_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_FFI_OK_SRC" "build/tmp/ffi_ok_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_FFI_OK_SRC" "build/tmp/ffi_ok_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$STD_FFI_LIBC_SMOKE_SRC" "build/tmp/std_ffi_libc_smoke_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_FFI_I32_SRC" "build/tmp/ffi_i32_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_FFI_I32_SRC" "build/tmp/ffi_i32_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_FFI_U32_SRC" "build/tmp/ffi_u32_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_FFI_U32_SRC" "build/tmp/ffi_u32_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_FFI_VOID_SRC" "build/tmp/ffi_void_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_FFI_VOID_SRC" "build/tmp/ffi_void_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_ULOCK_TIMEOUT_SMOKE_SRC" "build/tmp/ulock_timeout_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$ULOCK_TIMEOUT_PORTABLE_SMOKE_SRC" "build/tmp/ulock_timeout_portable_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$LINUX_OS_THREAD_SMOKE_SRC" "build/tmp/linux_os_thread_smoke_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$LINUX_OS_THREAD_SMOKE_SRC" "build/tmp/linux_os_thread_smoke_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$OS_THREAD_PARK_UNPARK_SMOKE_SRC" "build/tmp/os_thread_park_unpark_stage2_x64_linux"
  build_native_bin_src "./oren" "x64-linux" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$OS_THREAD_SPAWN_MANY_SMOKE_SRC" "build/tmp/os_thread_spawn_many_stage2_x64_linux"

  remote_upload "build/tmp/qi_stage1_x64_linux" "qi_stage1_x64_linux"
  remote_upload "build/tmp/qi_stage2_x64_linux" "qi_stage2_x64_linux"
  remote_upload "build/tmp/ffi_panic_stage1_x64_linux" "ffi_panic_stage1_x64_linux"
  remote_upload "build/tmp/ffi_panic_stage2_x64_linux" "ffi_panic_stage2_x64_linux"
  remote_upload "build/tmp/ffi_ok_stage1_x64_linux" "ffi_ok_stage1_x64_linux"
  remote_upload "build/tmp/ffi_ok_stage2_x64_linux" "ffi_ok_stage2_x64_linux"
  remote_upload "build/tmp/std_ffi_libc_smoke_stage1_x64_linux" "std_ffi_libc_smoke_stage1_x64_linux"
  remote_upload "build/tmp/std_ffi_libc_smoke_stage2_x64_linux" "std_ffi_libc_smoke_stage2_x64_linux"
  remote_upload "build/tmp/ffi_i32_stage1_x64_linux" "ffi_i32_stage1_x64_linux"
  remote_upload "build/tmp/ffi_i32_stage2_x64_linux" "ffi_i32_stage2_x64_linux"
  remote_upload "build/tmp/ffi_u32_stage1_x64_linux" "ffi_u32_stage1_x64_linux"
  remote_upload "build/tmp/ffi_u32_stage2_x64_linux" "ffi_u32_stage2_x64_linux"
  remote_upload "build/tmp/ffi_void_stage1_x64_linux" "ffi_void_stage1_x64_linux"
  remote_upload "build/tmp/ffi_void_stage2_x64_linux" "ffi_void_stage2_x64_linux"
  remote_upload "build/tmp/ulock_timeout_stage1_x64_linux" "ulock_timeout_stage1_x64_linux"
  remote_upload "build/tmp/ulock_timeout_stage2_x64_linux" "ulock_timeout_stage2_x64_linux"
  remote_upload "build/tmp/ulock_timeout_portable_stage1_x64_linux" "ulock_timeout_portable_stage1_x64_linux"
  remote_upload "build/tmp/ulock_timeout_portable_stage2_x64_linux" "ulock_timeout_portable_stage2_x64_linux"
  remote_upload "build/tmp/linux_os_thread_smoke_stage1_x64_linux" "linux_os_thread_smoke_stage1_x64_linux"
  remote_upload "build/tmp/linux_os_thread_smoke_stage2_x64_linux" "linux_os_thread_smoke_stage2_x64_linux"
  remote_upload "build/tmp/os_thread_park_unpark_stage1_x64_linux" "os_thread_park_unpark_stage1_x64_linux"
  remote_upload "build/tmp/os_thread_park_unpark_stage2_x64_linux" "os_thread_park_unpark_stage2_x64_linux"
  remote_upload "build/tmp/os_thread_spawn_many_stage1_x64_linux" "os_thread_spawn_many_stage1_x64_linux"
  remote_upload "build/tmp/os_thread_spawn_many_stage2_x64_linux" "os_thread_spawn_many_stage2_x64_linux"

  log "-- run: WSL2 (x64-linux) --"
  remote_run_wsl "qi_stage1_x64_linux"
  remote_run_wsl "qi_stage2_x64_linux"
  remote_run_wsl_expect_fail_contains "ffi_panic_stage1_x64_linux" "ffi unresolved:" "oren_panic"
  remote_run_wsl_expect_fail_contains "ffi_panic_stage2_x64_linux" "ffi unresolved:" "oren_panic"
  remote_run_wsl "ffi_ok_stage1_x64_linux"
  remote_run_wsl "ffi_ok_stage2_x64_linux"
  remote_run_wsl "std_ffi_libc_smoke_stage1_x64_linux"
  remote_run_wsl "std_ffi_libc_smoke_stage2_x64_linux"
  remote_run_wsl "ffi_i32_stage1_x64_linux"
  remote_run_wsl "ffi_i32_stage2_x64_linux"
  remote_run_wsl "ffi_u32_stage1_x64_linux"
  remote_run_wsl "ffi_u32_stage2_x64_linux"
  remote_run_wsl "ffi_void_stage1_x64_linux"
  remote_run_wsl "ffi_void_stage2_x64_linux"
  remote_run_wsl "ulock_timeout_stage1_x64_linux"
  remote_run_wsl "ulock_timeout_stage2_x64_linux"
  remote_run_wsl "ulock_timeout_portable_stage1_x64_linux"
  remote_run_wsl "ulock_timeout_portable_stage2_x64_linux"
  remote_run_wsl "linux_os_thread_smoke_stage1_x64_linux"
  remote_run_wsl "linux_os_thread_smoke_stage2_x64_linux"
  remote_run_wsl "os_thread_park_unpark_stage1_x64_linux"
  remote_run_wsl "os_thread_park_unpark_stage2_x64_linux"
  remote_run_wsl "os_thread_spawn_many_stage1_x64_linux"
  remote_run_wsl "os_thread_spawn_many_stage2_x64_linux"
  log "OK: remote WSL2 x64"
fi

if [[ "$SKIP_REMOTE" -eq 0 ]] && has_target x64-wsl-tier1; then
  build_native_bin_src "./oren" "x64-linux" "$TIER1_SRC" "build/tmp/tier1_stage1_x64_linux"
  build_native_bin_src "./oren_stage2" "x64-linux" "$TIER1_SRC" "build/tmp/tier1_stage2_x64_linux"

  remote_upload "build/tmp/tier1_stage1_x64_linux" "tier1_stage1_x64_linux"
  remote_upload "build/tmp/tier1_stage2_x64_linux" "tier1_stage2_x64_linux"

  log "-- run: WSL2 Tier‑1 native smoke (x64-linux) --"
  remote_run_wsl "tier1_stage1_x64_linux"
  remote_run_wsl "tier1_stage2_x64_linux"
  log "-- run: WSL2 Tier‑1 native smoke (x64-linux; OREN_NO_GREEN=1) --"
  remote_run_wsl "tier1_stage1_x64_linux" "OREN_NO_GREEN=1"
  remote_run_wsl "tier1_stage2_x64_linux" "OREN_NO_GREEN=1"

  if [[ "$TIER1_EXPECT_MARKERS" -ne 0 ]]; then
    log "-- build+run: WSL2 Tier‑1 green-worker fixtures (x64-linux) --"
    build_green_worker_fixtures "x64-linux"
    remote_upload "build/tmp/green2w_world_lock_stage1_x64-linux" "green2w_world_lock_stage1_x64_linux"
    remote_upload "build/tmp/green2w_world_lock_stage2_x64-linux" "green2w_world_lock_stage2_x64_linux"
    remote_upload "build/tmp/green2w_m_less_p_smoke_stage1_x64-linux" "green2w_m_less_p_smoke_stage1_x64_linux"
    remote_upload "build/tmp/green2w_m_less_p_smoke_stage2_x64-linux" "green2w_m_less_p_smoke_stage2_x64_linux"
    remote_upload "build/tmp/green2w_m_less_p_det_stage1_x64-linux" "green2w_m_less_p_det_stage1_x64_linux"
    remote_upload "build/tmp/green2w_m_less_p_det_stage2_x64-linux" "green2w_m_less_p_det_stage2_x64_linux"
    remote_run_wsl "green2w_world_lock_stage1_x64_linux"
    remote_run_wsl "green2w_world_lock_stage2_x64_linux"
    remote_run_wsl "green2w_m_less_p_smoke_stage1_x64_linux"
    remote_run_wsl "green2w_m_less_p_smoke_stage2_x64_linux"
    remote_run_wsl "green2w_m_less_p_det_stage1_x64_linux"
    remote_run_wsl "green2w_m_less_p_det_stage2_x64_linux"
  fi
  log "OK: remote WSL2 x64 tier1"
fi

log "ALL OK: native matrix verification passed"
