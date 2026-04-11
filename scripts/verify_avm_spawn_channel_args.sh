#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="build/logs"
ts="$(date +%Y%m%d_%H%M%S)"
TMP="build/tmp/verify-avm-spawn-channel-args-${ts}"
mkdir -p "$TMP" "$LOG_DIR"
trap 'rm -rf "$TMP"' EXIT

src="tests/fixtures/avm_spawn_channel_args.oren"
obc="$TMP/avm_spawn_channel_args.obc"
build_log="$LOG_DIR/verify_avm_spawn_channel_args_${ts}_build.log"
run_log="$LOG_DIR/verify_avm_spawn_channel_args_${ts}_run.log"

./oren build "$src" --backend bytecode -o "$obc" >"$build_log" 2>&1
./avm --print-run-json "$obc" >"$run_log" 2>&1

grep -Fq '"schema":"avm.run.v1"' "$run_log" || {
  echo "ERROR: missing AVM run JSON for spawn/channel args guard" >&2
  cat "$run_log" >&2 || true
  exit 1
}
grep -Fq '"exit_code":0' "$run_log" || {
  echo "ERROR: spawn/channel args guard failed" >&2
  cat "$run_log" >&2 || true
  exit 1
}

echo "avm spawn channel args verify OK"
