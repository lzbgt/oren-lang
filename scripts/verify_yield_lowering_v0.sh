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

ready_meta="$tmpdir/ready.meta.json"
ready_dump="$tmpdir/ready.linked.json"
ready_obc="$tmpdir/ready.obc"
ready_obc_meta="$tmpdir/ready.obc.meta.json"
yield_value_log="$tmpdir/yield_value_fail.log"
yield_expr_log="$tmpdir/yield_expr_fail.log"

run_ok "$compiler" meta "$ready_src" --platform "$platform" -o "$ready_meta" --strict-yield-lowering-v0
run_ok "$compiler" dump linked "$ready_src" --platform "$platform" -o "$ready_dump" --strict-yield-lowering-v0
run_ok env OREN_TRACE_BYTECODE_YIELD_LOWERING=1 "$compiler" build "$ready_src" --backend bytecode --platform "$platform" --no-cache -o "$ready_obc" --strict-yield-lowering-v0
run_ok ./avm "$ready_obc"
run_ok python3 scripts/extract_obc_metadata.py "$ready_obc" -o "$ready_obc_meta"

run_fail "$yield_value_log" "$compiler" build tests/fixtures/yield_value_fail.oren --backend bytecode --platform "$platform" -o "$tmpdir/yield_value_fail.obc" --strict-yield-lowering-v0
run_fail "$yield_expr_log" "$compiler" build tests/fixtures/yield_expr_fail.oren --backend bytecode --platform "$platform" -o "$tmpdir/yield_expr_fail.obc" --strict-yield-lowering-v0

grep -q "'yield' does not accept a value yet" "$yield_value_log"
grep -q "'yield' is only supported as a bare statement today" "$yield_expr_log"

grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_worker" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_live_local" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_multi_yield" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_branch_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_block_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_loop_yield kind=direct_passthrough" "$log"
grep -q "\\[bc_yield_lowering_v0\\] lowered fn=ready_nested_capture" "$log"

READY_META="$ready_meta" \
READY_DUMP="$ready_dump" \
READY_OBC_META="$ready_obc_meta" \
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
ready_meta_branch = ready_funcs["ready_branch_yield"]
ready_obc_branch = ready_obc_funcs["ready_branch_yield"]
ready_dump_branch = ready_dump_details["ready_branch_yield"]
ready_meta_block = ready_funcs["ready_block_yield"]
ready_obc_block = ready_obc_funcs["ready_block_yield"]
ready_dump_block = ready_dump_details["ready_block_yield"]
ready_meta_loop = ready_funcs["ready_loop_yield"]
ready_obc_loop = ready_obc_funcs["ready_loop_yield"]
ready_dump_loop = ready_dump_details["ready_loop_yield"]
ready_meta_nested = ready_funcs["ready_nested_capture"]
ready_obc_nested = ready_obc_funcs["ready_nested_capture"]
ready_dump_nested = ready_dump_details["ready_nested_capture"]

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

for payload in (ready_meta_branch, ready_obc_branch, ready_dump_branch):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_branch_yield should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_branch_yield missing prepared_v0")
    if prepared["kind"] != "direct_passthrough":
        raise SystemExit(f"expected direct_passthrough for ready_branch_yield, got {prepared!r}")
    if prepared["resume_state"] != -1:
        raise SystemExit(f"unexpected ready_branch_yield resume_state: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 1:
        raise SystemExit(f"expected one prepared_v0 segment for ready_branch_yield, got {segs!r}")
    if segs[0]["stmt_types"] != ["ExprStmt", "Return"] or segs[0]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_branch_yield segment: {segs[0]!r}")

for payload in (ready_meta_block, ready_obc_block, ready_dump_block):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_block_yield should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_block_yield missing prepared_v0")
    if prepared["kind"] != "direct_passthrough":
        raise SystemExit(f"expected direct_passthrough for ready_block_yield, got {prepared!r}")
    if prepared["resume_state"] != -1:
        raise SystemExit(f"unexpected ready_block_yield resume_state: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 1:
        raise SystemExit(f"expected one prepared_v0 segment for ready_block_yield, got {segs!r}")
    if segs[0]["stmt_types"] != ["Block", "Return"] or segs[0]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_block_yield segment: {segs[0]!r}")

for payload in (ready_meta_loop, ready_obc_loop, ready_dump_loop):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_loop_yield should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_loop_yield missing prepared_v0")
    if prepared["kind"] != "direct_passthrough":
        raise SystemExit(f"expected direct_passthrough for ready_loop_yield, got {prepared!r}")
    if prepared["live_slots"] != ["i"]:
        raise SystemExit(f"unexpected ready_loop_yield live_slots: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 1:
        raise SystemExit(f"expected one prepared_v0 segment for ready_loop_yield, got {segs!r}")
    if segs[0]["stmt_types"] != ["Var", "While", "Return"] or segs[0]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_loop_yield segment: {segs[0]!r}")

for payload in (ready_meta_nested, ready_obc_nested, ready_dump_nested):
    gate = payload["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not True:
        raise SystemExit(f"ready_nested_capture should be lowering_v0.ready, got {gate!r}")
    prepared = payload["yield_lowering"]["prepared_v0"]
    if prepared is None:
        raise SystemExit("ready_nested_capture missing prepared_v0")
    if prepared["kind"] != "split_dispatch":
        raise SystemExit(f"expected split_dispatch for ready_nested_capture, got {prepared!r}")
    if prepared["live_slots"] != ["f"]:
        raise SystemExit(f"unexpected ready_nested_capture live_slots: {prepared!r}")
    segs = prepared["segments"]
    if len(segs) != 2:
        raise SystemExit(f"expected two prepared_v0 segments for ready_nested_capture, got {segs!r}")
    if segs[0]["stmt_types"] != ["Var", "Var"] or segs[0]["terminator"] != "yield":
        raise SystemExit(f"unexpected ready_nested_capture entry segment: {segs[0]!r}")
    if segs[1]["stmt_types"] != ["Return"] or segs[1]["terminator"] != "return":
        raise SystemExit(f"unexpected ready_nested_capture resume segment: {segs[1]!r}")

print("yield lowering v0 linked/OBC metadata verified")
PY

echo "yield lowering v0 verify OK" >>"$log"
echo "yield lowering v0 verify OK"
