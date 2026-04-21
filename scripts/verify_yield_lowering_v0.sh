#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren}"

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
blocked_nonstrict_obc="$tmpdir/blocked.nonstrict.obc"
blocked_nonstrict_obc_meta="$tmpdir/blocked.nonstrict.obc.meta.json"

run_ok "$compiler" meta "$ready_src" -o "$ready_meta" --strict-yield-lowering-v0
run_ok "$compiler" dump linked "$ready_src" -o "$ready_dump" --strict-yield-lowering-v0
run_ok "$compiler" build "$ready_src" --backend bytecode -o "$ready_obc" --strict-yield-lowering-v0
run_ok "$compiler" build "$blocked_src" --backend bytecode -o "$blocked_nonstrict_obc"
run_ok python3 scripts/extract_obc_metadata.py "$ready_obc" -o "$ready_obc_meta"
run_ok python3 scripts/extract_obc_metadata.py "$blocked_nonstrict_obc" -o "$blocked_nonstrict_obc_meta"

blocked_meta_log="$tmpdir/blocked.meta.log"
blocked_dump_log="$tmpdir/blocked.dump.log"
blocked_build_log="$tmpdir/blocked.build.log"

run_fail "$blocked_meta_log" "$compiler" meta "$blocked_src" -o "$tmpdir/blocked.meta.json" --strict-yield-lowering-v0
run_fail "$blocked_dump_log" "$compiler" dump linked "$blocked_src" -o "$tmpdir/blocked.linked.json" --strict-yield-lowering-v0
run_fail "$blocked_build_log" "$compiler" build "$blocked_src" --backend bytecode -o "$tmpdir/blocked.obc" --strict-yield-lowering-v0

for f in "$blocked_meta_log" "$blocked_dump_log" "$blocked_build_log"; do
  grep -q "yield lowering v0 blocked" "$f"
  grep -q "blocked_multi_yield" "$f"
  grep -q "blocked_live_local" "$f"
  grep -q "blocked_nested_literal" "$f"
  grep -q "blocked_non_top_level" "$f"
  grep -q "multiple_yields" "$f"
  grep -q "live_locals_across_yield" "$f"
  grep -q "nested_function_literal" "$f"
  grep -q "non_top_level_yield" "$f"
done

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


def expect_blocker(name, blocker):
    func = funcs_by_name(blocked_obc_meta)[name]
    gate = func["yield_lowering"]["lowering_v0"]
    if gate["ready"] is not False:
        raise SystemExit(f"{name} should remain blocked in embedded metadata, got {gate!r}")
    if blocker not in gate["blockers"]:
        raise SystemExit(f"{name} missing blocker {blocker!r}: {gate!r}")
    if func["yield_lowering"]["prepared_v0"] is not None:
        raise SystemExit(f"{name} should not have prepared_v0 in embedded metadata")


expect_blocker("blocked_multi_yield", "multiple_yields")
expect_blocker("blocked_live_local", "live_locals_across_yield")
expect_blocker("blocked_nested_literal", "nested_function_literal")
expect_blocker("blocked_non_top_level", "non_top_level_yield")

print("yield lowering v0 linked/OBC metadata verified")
PY

echo "yield lowering v0 verify OK" >>"$log"
echo "yield lowering v0 verify OK"
