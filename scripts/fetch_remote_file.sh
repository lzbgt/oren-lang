#!/usr/bin/env bash
set -euo pipefail

# Fetch an arbitrary file from the remote Win11 x64 host into the repo for diagnosis.
#
# Primary use-case:
# - Capture full failure logs from remote stage2 bring-up (e.g. x64-windows native backend hangs)
#   without copying/pasting huge logs into chat.
#
# This script:
# 1) Runs a fast SSH preflight (15s bounded).
# 2) Copies the requested remote file into the remote staging root (default:
#    %USERPROFILE%\tmp_oren\remote_fetch\) on the remote host.
# 3) scp's the staged copy into `project-doc/remote/` with a timestamp.
#
# Notes:
# - We intentionally store the full original file contents in-repo under `project-doc/remote/`.
# - Output is bounded: only prints a short destination path; does not dump the file.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REMOTE_HOST="${OREN_REMOTE_X64_HOST:-lzbgt@pc.work}"
REMOTE_PROXY="${OREN_REMOTE_X64_PROXY:-ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002}"

WIN_PATH=""
OUT_DIR=""
OUT_NAME=""
TRACE=0
ANALYZE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/fetch_remote_file.sh --win-path <ABS_WINDOWS_PATH> [--out-name <name>] [--out-dir <dir>] [--host <user@host>] [--proxy <ssh_opt>] [--no-proxy] [--analyze] [--trace]

Examples:
  ./scripts/fetch_remote_file.sh --win-path 'E:\work\oren-lang\s2_build_failure.log'
  ./scripts/fetch_remote_file.sh --win-path 'C:\Users\lzbgt\tmp_oren\stage2_from_stage1\stage1_build_stage2.log' --out-name stage1_build_stage2.log
  ./scripts/fetch_remote_file.sh --win-path 'E:\work\oren-lang\s2_build_failure.log' --host 'lzbgt@203.0.113.10'
  ./scripts/fetch_remote_file.sh --win-path 'E:\work\oren-lang\s2_build_failure.log' --host 'lzbgt@203.0.113.10' --no-proxy --analyze

Env overrides:
  OREN_REMOTE_X64_HOST   (default: lzbgt@pc.work)
  OREN_REMOTE_X64_PROXY  (default: ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002)
  OREN_REMOTE_X64_WIN_ROOT (default: C:\Users\<user>\tmp_oren) remote Windows staging root
  OREN_REMOTE_X64_SSH_ROOT (default: tmp_oren) scp/sftp staging root (Windows OpenSSH path)

Output:
  Writes the fetched file under:
    project-doc/remote/<timestamp>/
  unless --out-dir is provided.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --win-path)
      WIN_PATH="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --out-name)
      OUT_NAME="${2:-}"
      shift 2
      ;;
    --host)
      REMOTE_HOST="${2:-}"
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
    --analyze)
      ANALYZE=1
      shift
      ;;
    --trace)
      TRACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$WIN_PATH" ]]; then
  echo "ERROR: --win-path is required" >&2
  usage >&2
  exit 2
fi

remote_user="$REMOTE_HOST"
if [[ "$REMOTE_HOST" == *"@"* ]]; then
  remote_user="${REMOTE_HOST%@*}"
fi
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

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin ssh
need_bin scp
need_bin grep
if [[ -n "$REMOTE_PROXY" ]] && [[ "$REMOTE_PROXY" == *socat* ]]; then
  need_bin socat
fi

if [[ "$TRACE" -ne 0 ]]; then
  set -x
fi

mkdir -p build/logs

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
  local logf="build/logs/fetch_remote_probe.log"
  echo "== remote: ssh probe ==" >&2
  local attempt=1
  while true; do
    : >"$logf"
    set +e
    run_with_timeout 15 "${ssh_base[@]}" "cmd.exe /c \"echo OREN_REMOTE_OK\"" >"$logf" 2>&1
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      if grep -q "OREN_REMOTE_OK" "$logf" 2>/dev/null; then
        return 0
      fi
    fi
    if [[ "$attempt" -ge 2 ]]; then
      echo "ERROR: cannot reach remote host via ssh (rc=$rc host=$REMOTE_HOST)" >&2
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

ps_quote() {
  # Quote for PowerShell single-quoted strings: ' becomes ''.
  local s="$1"
  s="${s//\'/\'\'}"
  printf "%s" "$s"
}

remote_preflight

# Stage on remote into %USERPROFILE%\tmp_oren\remote_fetch\<basename>
ps_src="$(ps_quote "$WIN_PATH")"
ps_base=""
if [[ -n "$OUT_NAME" ]]; then
  ps_base="$(ps_quote "$OUT_NAME")"
fi

stage_log="build/logs/fetch_remote_stage.log"
set +e
run_with_timeout 30 "${ssh_base[@]}" "powershell -NoProfile -Command \"\
\$ErrorActionPreference='Stop'; \
\$src='${ps_src}'; \
\$root='${remote_win_root_cmd}'; \
\$dstDir=(Join-Path \$root 'remote_fetch'); \
New-Item -ItemType Directory -Force -Path \$dstDir | Out-Null; \
if ('${ps_base}' -ne '') { \$name='${ps_base}' } else { \$name=[IO.Path]::GetFileName(\$src) }; \
if ([string]::IsNullOrEmpty(\$name)) { \$name='remote_fetch.bin' }; \
\$dst=(Join-Path \$dstDir \$name); \
Copy-Item -LiteralPath \$src -Destination \$dst -Force; \
Write-Output ('FETCH_OK:' + \$name)\"" >"$stage_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: remote stage (copy) failed rc=$rc (win-path=$WIN_PATH)" >&2
  tail -n 120 "$stage_log" >&2 2>/dev/null || true
  echo "log=$stage_log" >&2
  exit "$rc"
fi

marker="$(tr -d '\r' <"$stage_log" | grep -E 'FETCH_OK:' | tail -n 1 || true)"
if [[ -z "$marker" ]]; then
  echo "ERROR: remote stage did not return FETCH_OK marker (win-path=$WIN_PATH)" >&2
  tail -n 120 "$stage_log" >&2 2>/dev/null || true
  echo "log=$stage_log" >&2
  exit 2
fi

staged_name="${marker#FETCH_OK:}"
staged_name="${staged_name#"${staged_name%%[![:space:]]*}"}"
staged_name="${staged_name%"${staged_name##*[![:space:]]}"}"
if [[ -z "$staged_name" ]]; then
  echo "ERROR: empty staged_name from marker: $marker" >&2
  exit 2
fi

ts="$(date -u '+%Y%m%d_%H%M%S')"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="project-doc/remote/${ts}"
fi
mkdir -p "$OUT_DIR"

local_dst="${OUT_DIR}/${staged_name}"
remote_src="${REMOTE_HOST}:${remote_unix_root}/remote_fetch/${staged_name}"

echo "== fetch: scp ${remote_src} -> ${local_dst} ==" >&2
set +e
run_with_timeout 60 "${scp_base[@]}" "$remote_src" "$local_dst" >"build/logs/fetch_remote_scp.log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: scp download failed rc=$rc" >&2
  tail -n 120 build/logs/fetch_remote_scp.log >&2 2>/dev/null || true
  exit "$rc"
fi

echo "OK: saved ${local_dst}"

if [[ "$ANALYZE" -ne 0 ]]; then
  analyzer="./scripts/analyze_stage2_failure_log.sh"
  if [[ -x "$analyzer" ]]; then
    echo "== analyze: ${analyzer} ${local_dst} ==" >&2
    "$analyzer" "$local_dst" || true
  else
    echo "WARN: --analyze requested but analyzer not found/executable: ${analyzer}" >&2
  fi
fi
