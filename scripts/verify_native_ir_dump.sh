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
types = {t["id"]: t for t in ir["types"]}
assert types["tagged"] == {"id": "tagged", "kind": "oren_value", "bits": 64, "align": 8, "abi_class": "integer"}, types
assert types["void"]["kind"] == "void", types

funcs = ir["functions"]
names = [fn["name"] for fn in funcs]
assert "main" in names, names[-10:]
assert "STD_list_push" in names, names[:10]
assert len(names) == len(set(names)), "duplicate function names in native IR dump"

main = next(fn for fn in funcs if fn["name"] == "main")
assert main["arity"] == 0, main
assert main["frame_slots"] == 0, main
assert main["return_type"] == "tagged", main
value_types = {vt["value"]: vt["type"] for vt in main["value_types"]}
assert value_types and all(t == "tagged" for t in value_types.values()), main["value_types"]
assert len(main["blocks"]) > 1, main["blocks"]
entry = main["blocks"][0]
assert entry["label"] == "entry", entry
labels = {block["label"] for block in main["blocks"]}
assert len(labels) == len(main["blocks"]), main["blocks"]
for block in main["blocks"]:
    term = block["terminator"]
    if term["kind"] == "jump":
        assert term["target"] in labels, block
    elif term["kind"] == "branch":
        assert term["true"] in labels and term["false"] in labels, block
ops = [op for block in main["blocks"] for op in block["ops"]]
assert isinstance(ops, list) and len(ops) > 0, entry
op_kinds = {op["kind"] for op in ops}
for kind in ("array", "binary", "call", "const", "index_get", "local_set", "runtime_helper_call"):
    assert kind in op_kinds, (kind, ops)
helper_ops = [op for op in ops if op["kind"] == "runtime_helper_call"]
assert helper_ops == main["helper_calls"], (helper_ops, main["helper_calls"])
assert len(main["roots"]) > 0, main
root_locals = {root["local"] for root in main["roots"]}
helper_names = {op["name"] for op in helper_ops}
assert {"print", "exit"}.issubset(helper_names), helper_ops
for op in helper_ops:
    assert op["safepoint"] is True, op
    assert op["call_depth"] == "enter_exit", op
    assert op["arg_types"] == ["tagged"] * len(op["args"]), op
    assert op["result_type"] == "tagged", op
    if op["result"] is not None:
        assert value_types[op["result"]] == "tagged", (op, value_types)
    assert isinstance(op["clobbers"], list) and len(op["clobbers"]) > 0, op
    assert isinstance(op["roots"], list), op
    for root in op["roots"]:
        assert root["kind"] == "tagged", root
        assert root["local"] in root_locals, (root, main["roots"])
for op in ops:
    if op["kind"] == "opaque_stmt":
        assert op["stmt_type"] not in {"If", "While"}, op
    if op["kind"] == "opaque_expr":
        assert op["expr_type"] not in {"If", "While"}, op
term_kinds = {block["terminator"]["kind"] for block in main["blocks"]}
assert "branch" in term_kinds and "jump" in term_kinds and "return" in term_kinds, main["blocks"]

print(f"OK: native IR dump functions={len(funcs)} path={path}")
PY

echo "OK: native IR dump smoke passed"
