#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren}"
platform="${OREN_PLATFORM:-}"

if [ -z "$platform" ]; then
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  case "$uname_s:$uname_m" in
    Darwin:arm64|Darwin:aarch64) platform="arm64-macos" ;;
    Darwin:x86_64) platform="x64-macos" ;;
    Linux:arm64|Linux:aarch64) platform="arm64-linux" ;;
    Linux:x86_64|Linux:amd64) platform="x64-linux" ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) platform="x64-windows" ;;
  esac
fi

if [ -z "$platform" ]; then
  echo "verify_yield_lowering_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/yield_lowering_v0_${ts}"
log="build/logs/verify_yield_lowering_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

run_fail() {
  local out="$1"
  shift
  echo "\$ $*" >>"$log"
  set +e
  "$@" >"$out" 2>&1
  local rc=$?
  set -e
  cat "$out" >>"$log"
  if [ "$rc" -eq 0 ]; then
    echo "expected failure: $*" >>"$log"
    cat "$log"
    exit 1
  fi
}

ready_src="tests/fixtures/yield_lowering_v0_ready.oren"
blocked_src="tests/fixtures/yield_lowering_v0_blocked.oren"

ready_meta="$tmpdir/ready.meta.json"
ready_dump="$tmpdir/ready.linked.json"
ready_obc="$tmpdir/ready.obc"
ready_obc_meta="$tmpdir/ready.obc.meta.json"
ready_run_log="$tmpdir/ready.run.log"
blocked_nonstrict_obc="$tmpdir/blocked.nonstrict.obc"
blocked_nonstrict_obc_meta="$tmpdir/blocked.nonstrict.obc.meta.json"

run_ok "$compiler" meta "$ready_src" --platform "$platform" -o "$ready_meta" --strict-yield-lowering-v0
run_ok "$compiler" dump linked "$ready_src" --platform "$platform" -o "$ready_dump" --strict-yield-lowering-v0
run_ok env OREN_TRACE_BYTECODE_YIELD_LOWERING=1 "$compiler" build "$ready_src" --backend bytecode --platform "$platform" --no-cache -o "$ready_obc" --strict-yield-lowering-v0
run_ok ./avm "$ready_obc"
run_ok env OREN_TRACE_BYTECODE_YIELD_LOWERING=1 "$compiler" build "$blocked_src" --backend bytecode --platform "$platform" --no-cache -o "$blocked_nonstrict_obc"
run_ok python3 scripts/extract_obc_metadata.py "$ready_obc" -o "$ready_obc_meta"
run_ok python3 scripts/extract_obc_metadata.py "$blocked_nonstrict_obc" -o "$blocked_nonstrict_obc_meta"

blocked_meta_log="$tmpdir/blocked.meta.log"
blocked_dump_log="$tmpdir/blocked.dump.log"
blocked_build_log="$tmpdir/blocked.build.log"

run_fail "$blocked_meta_log" "$compiler" meta "$blocked_src" --platform "$platform" -o "$tmpdir/blocked.meta.json" --strict-yield-lowering-v0
run_fail "$blocked_dump_log" "$compiler" dump linked "$blocked_src" --platform "$platform" -o "$tmpdir/blocked.linked.json" --strict-yield-lowering-v0
run_fail "$blocked_build_log" "$compiler" build "$blocked_src" --backend bytecode --platform "$platform" -o "$tmpdir/blocked.obc" --strict-yield-lowering-v0

for f in "$blocked_meta_log" "$blocked_dump_log" "$blocked_build_log"; do
  grep -q "yield lowering v0 blocked" "$f"
  grep -q "blocked_nested_literal" "$f"
  grep -q "blocked_non_top_level" "$f"
  grep -q "nested_function_literal" "$f"
  grep -q "non_top_level_yield" "$f"
done

grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_worker" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_live_local" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_multi_yield" "$log"
if grep -q "\\[bc_yield_lowering_v0\\] lowered fn=blocked_" "$log"; then
  echo "unexpected lowering trace for blocked fixture" >>"$log"
  cat "$log"
  exit 1
fi

READY_META="$ready_meta" \
READY_DUMP="$ready_dump" \
READY_OBC_META="$ready_obc_meta" \
BLOCKED_OBC_META="$blocked_nonstrict_obc_meta" \
python3 - >>"$log" <<'PY'
import json
import os


def load(path_env):
    with open(os.environ[path_env], "r", encoding="utf-8") as fh:
        return json.load(fh)


def funcs_by_name(payload):
    return {f["name"]: f for f in payload["functions"]}


ready_meta = load("READY_META")
ready_dump = load("READY_DUMP")
ready_obc_meta = load("READY_OBC_META")["metadata"]
blocked_obc_meta = load("BLOCKED_OBC_META")["metadata"]

ready_funcs = funcs_by_name(ready_meta)
ready_obc_funcs = funcs_by_name(ready_obc_meta)
ready_dump_details = {f["name"]: f for f in ready_dump["function_details"]}

ready_meta_worker = ready_funcs["ready_worker"]
ready_obc_worker = ready_obc_funcs["ready_worker"]
ready_dump_worker = ready_dump_details["ready_worker"]
ready_meta_live = ready_funcs["ready_live_local"]
ready_obc_live = ready_obc_funcs["ready_live_local"]
ready_dump_live = ready_dump_details["ready_live_local"]
ready_meta_multi = ready_funcs["ready_multi_yield"]
ready_obc_multi = ready_obc_funcs["ready_multi_yield"]
ready_dump_multi = ready_dump_details["ready_multi_yield"]

for payload in (ready_meta_worker, ready_obc_worker, ready_dump_worker):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_worker should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_worker missing prepared_v0")
    if prepared["entry_state"] != 0 or prepared["resume_state"] != 1:
        raise SystemExit(f"unexpected prepared_v0 states: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 2:
        raise SystemExit(f"expected two prepared_v0 segments, got {segs!r}")
    if segs[0]["stmt_types"] != ["ExprStmt"] or segs[0]["terminator"] != "yield":
        raise SystemExit(f"unexpected entry segment: {segs[0]!r}")
    if segs[1]["stmt_types"] != ["ExprStmt", "Return"] or segs[1]["terminator"] != "return":
        raise SystemExit(f"unexpected resume segment: {segs[1]!r}")

for payload in (ready_meta_live, ready_obc_live, ready_dump_live):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_live_local should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_live_local missing prepared_v0")
    if prepared["live_slots"] != ["acc"]:
        raise SystemExit(f"unexpected ready_live_local live_slots: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 2:
        raise SystemExit(f"expected two prepared_v0 segments for ready_live_local, got {segs!r}")
    if segs[0]["stmt_types"] != ["Var"] or segs[0]["terminator"] != "yield":
        raise SystemExit(f"unexpected ready_live_local entry segment: {segs[0]!r}")
    if segs[1]["stmt_types"] != ["Return"] or segs[1]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_live_local resume segment: {segs[1]!r}")

for payload in (ready_meta_multi, ready_obc_multi, ready_dump_multi):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_multi_yield should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_multi_yield missing prepared_v0")
    if prepared["live_slots"] != ["acc"]:
        raise SystemExit(f"unexpected ready_multi_yield live_slots: {prepared!r}")
    if prepared["entry_state"] != 0 or prepared["resume_state"] != 1:
        raise SystemExit(f"unexpected ready_multi_yield states: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 3:
        raise SystemExit(f"expected three prepared_v0 segments for ready_multi_yield, got {segs!r}")
    if segs[0]["stmt_types"] != ["Var"] or segs[0]["terminator"] != "yield":
        raise SystemExit(f"unexpected ready_multi_yield entry segment: {segs[0]!r}")
    if segs[1]["stmt_types"] != ["Assign"] or segs[1]["terminator"] != "yield":
        raise SystemExit(f"unexpected ready_multi_yield middle segment: {segs[1]!r}")
    if segs[2]["stmt_types"] != ["Return"] or segs[2]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_multi_yield resume segment: {segs[2]!r}")


def expect_blocker(name, blocker):
    func = funcs_by_name(blocked_obc_meta)[name]
    gate = func["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not False:
        raise SystemExit(f"{name} should remain blocked in embedded metadata, got {gate!r}")
    if blocker not in gate["blockers"]:
        raise SystemExit(f"{name} missing blocker {blocker!r}: {gate!r}")
    if func["yield_lowering"]["prepared_v0"] is not None:
        raise SystemExit(f"{name} should not have prepared_v0 in embedded metadata")


expect_blocker("blocked_nested_literal", "nested_function_literal")
expect_blocker("blocked_non_top_level", "non_top_level_yield")

print("yield lowering v0 linked/OBC metadata verified")
PY

echo "yield lowering v0 verify OK" >>"$log"
echo "yield lowering v0 verify OK"
