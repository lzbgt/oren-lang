#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
mkdir -p build/logs build/tmp

out="build/tmp/hello.native_ir.json"
log="build/logs/native_ir_dump_hello.log"

{
  echo "compiler=$compiler"
  echo "source=examples/hello.oren"
  echo "platform=x64-linux"
} >"$log"

"$compiler" dump native-ir examples/hello.oren --platform x64-linux -o "$out" >>"$log" 2>&1

python3 - "$out" >>"$log" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    ir = json.load(fh)

assert ir["schema"] == "native_ir_v0", ir.get("schema")
assert ir["target"] == {"arch": "x64", "os": "linux", "abi": "sysv"}, ir["target"]
assert ir["validation"]["ok"] is True, ir["validation"]
assert ir["validation"]["errors"] == [], ir["validation"]

funcs = ir["functions"]
names = [fn["name"] for fn in funcs]
assert "main" in names, names[-10:]
assert "STD_list_push" in names, names[:10]
assert len(names) == len(set(names)), "duplicate function names in native IR dump"

main = next(fn for fn in funcs if fn["name"] == "main")
assert main["arity"] == 0, main
assert main["frame_slots"] == 0, main
assert len(main["blocks"]) == 1, main["blocks"]
entry = main["blocks"][0]
assert entry["label"] == "entry", entry
ops = entry["ops"]
assert isinstance(ops, list) and len(ops) > 0, entry
op_kinds = {op["kind"] for op in ops}
for kind in ("array", "binary", "call", "const", "index_get", "local_set", "opaque_stmt"):
    assert kind in op_kinds, (kind, ops)
assert entry["terminator"]["kind"] == "return", entry

print(f"OK: native IR dump functions={len(funcs)} path={path}")
PY

echo "OK: native IR dump smoke passed"
