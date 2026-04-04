#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <lock-dir> <command> [args...]" >&2
  exit 2
fi

lock_dir="$1"
shift

mkdir -p "$(dirname "$lock_dir")"

pid_file="$lock_dir/pid"
meta_file="$lock_dir/meta"
wait_secs="${OREN_BUILD_LOCK_WAIT_SECS:-300}"
poll_secs="${OREN_BUILD_LOCK_POLL_SECS:-1}"
start_ts="$(date +%s)"

cleanup() {
  if [[ -d "$lock_dir" ]] && [[ -f "$pid_file" ]]; then
    local holder
    holder="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$holder" == "$$" ]]; then
      rm -rf "$lock_dir"
    fi
  fi
}
trap cleanup EXIT INT TERM HUP

while ! mkdir "$lock_dir" 2>/dev/null; do
  holder=""
  if [[ -f "$pid_file" ]]; then
    holder="$(cat "$pid_file" 2>/dev/null || true)"
  fi
  if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
    rm -rf "$lock_dir"
    continue
  fi
  now_ts="$(date +%s)"
  if (( now_ts - start_ts >= wait_secs )); then
    echo "with_build_lock: timed out waiting for $lock_dir" >&2
    if [[ -f "$meta_file" ]]; then
      echo "with_build_lock: holder metadata:" >&2
      cat "$meta_file" >&2 || true
    fi
    exit 1
  fi
  sleep "$poll_secs"
done

{
  echo "pid=$$"
  echo "cwd=$(pwd)"
  printf 'cmd='
  printf '%q ' "$@"
  printf '\n'
} >"$meta_file"
printf '%s\n' "$$" >"$pid_file"

"$@"
