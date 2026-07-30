#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
mkdir -p build/logs build/tmp/native_ir_parity

log="build/logs/native_ir_parity.log"

{
  echo "compiler=$compiler"
  echo "fixtures=hello,int_arith,direct_call,string_concat,list_ops,panic_div0,runtime_print"
  echo "platforms=x64-linux,x64-windows,arm64-macos"
} >"$log"

python3 - "$compiler" "$log" <<'PY'
import json
import os
import re
import subprocess
import sys

compiler = sys.argv[1]
log_path = sys.argv[2]

fixtures = [
    ("hello", "examples/hello.oren", ["main", "STD_list_push"], ["array", "binary", "call", "index_get", "local_set", "runtime_helper_call"]),
    ("int_arith", "tests/fixtures/x64_div_mod_main.oren", ["main"], ["binary", "const"]),
    ("direct_call", "tests/fixtures/x64_nested_call_args_main.oren", ["main", "add2"], ["call"]),
    ("string_concat", "tests/fixtures/tier1_native_string_ops_main.oren", ["main", "_mk_hi"], ["binary", "call"]),
    ("list_ops", "tests/fixtures/x64_list_ops_main.oren", ["main"], ["const", "local_set", "runtime_helper_call"]),
    ("panic_div0", "tests/fixtures/x64_div0_main.oren", ["main"], ["binary", "const"]),
    ("runtime_print", "tests/fixtures/x64_print_main.oren", ["main"], ["const", "expr_result", "runtime_helper_call"]),
]

platforms = [
    ("x64-linux", {"arch": "x64", "os": "linux", "abi": "sysv"}),
    ("x64-windows", {"arch": "x64", "os": "windows", "abi": "win64"}),
    ("arm64-macos", {"arch": "arm64", "os": "macos", "abi": "aapcs"}),
]

out_dir = "build/tmp/native_ir_parity"


def safe(s):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", s)


def run_dump(kind, src, platform, out_path, log):
    cmd = [compiler, "dump", kind, src, "--platform", platform, "-o", out_path]
    log.write("$ " + " ".join(cmd) + "\n")
    subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True)


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def assert_cfg_closed(src, platform, fn):
    labels = [block["label"] for block in fn["blocks"]]
    assert len(labels) == len(set(labels)), (src, platform, fn["name"], "duplicate block label", labels)
    label_set = set(labels)
    assert labels and labels[0] == "entry", (src, platform, fn["name"], labels)
    for block in fn["blocks"]:
        term = block["terminator"]
        kind = term["kind"]
        if kind == "jump":
            assert term["target"] in label_set, (src, platform, fn["name"], block)
        elif kind == "branch":
            assert term["true"] in label_set, (src, platform, fn["name"], block)
            assert term["false"] in label_set, (src, platform, fn["name"], block)
            assert isinstance(term["cond"], str) and term["cond"], (src, platform, fn["name"], block)
        else:
            assert kind in {"return", "panic", "unreachable"}, (src, platform, fn["name"], block)


def assert_helper_surface(src, platform, expected_target, fn):
    ops = [op for block in fn["blocks"] for op in block["ops"]]
    helper_ops = [op for op in ops if op["kind"] == "runtime_helper_call"]
    assert helper_ops == fn["helper_calls"], (src, platform, fn["name"], helper_ops, fn["helper_calls"])
    root_locals = {root["local"] for root in fn["roots"]}
    for root in fn["roots"]:
        assert root["kind"] == "tagged", (src, platform, fn["name"], root)
    for op in helper_ops:
        assert op["safepoint"] is True, (src, platform, fn["name"], op)
        assert op["call_depth"] == "enter_exit", (src, platform, fn["name"], op)
        assert isinstance(op["clobbers"], list) and len(op["clobbers"]) > 0, (src, platform, fn["name"], op)
        if expected_target["abi"] == "win64":
            assert "rcx" in op["clobbers"] and "rdi" not in op["clobbers"], (src, platform, fn["name"], op)
        elif expected_target["abi"] == "sysv":
            assert "rdi" in op["clobbers"] and "rsi" in op["clobbers"], (src, platform, fn["name"], op)
        elif expected_target["abi"] == "aapcs":
            assert "x0" in op["clobbers"] and "x17" in op["clobbers"], (src, platform, fn["name"], op)
        assert isinstance(op["roots"], list), (src, platform, fn["name"], op)
        for root in op["roots"]:
            assert root["kind"] == "tagged", (src, platform, fn["name"], op, root)
            assert root["local"] in root_locals, (src, platform, fn["name"], op, root, fn["roots"])


with open(log_path, "a", encoding="utf-8") as log:
    checked = 0
    for label, src, required_names, required_main_op_kinds in fixtures:
        for platform, expected_target in platforms:
            stem = safe(label + "_" + platform)
            linked_path = os.path.join(out_dir, stem + ".linked.json")
            ir_path = os.path.join(out_dir, stem + ".native_ir.json")

            log.write(f"\n== {label} {platform} ==\n")
            run_dump("linked", src, platform, linked_path, log)
            run_dump("native-ir", src, platform, ir_path, log)

            linked = load_json(linked_path)
            ir = load_json(ir_path)

            linked_names = linked["functions"]
            ir_functions = ir["functions"]
            ir_names = [fn["name"] for fn in ir_functions]

            assert ir["schema"] == "native_ir_v0", ir.get("schema")
            assert ir["target"] == expected_target, (src, platform, ir["target"], expected_target)
            assert ir["validation"]["ok"] is True, (src, platform, ir["validation"])
            assert ir["validation"]["errors"] == [], (src, platform, ir["validation"])
            assert linked_names == ir_names, (src, platform, linked_names, ir_names)
            assert len(ir_names) == len(set(ir_names)), (src, platform, "duplicate native IR function names")

            for name in required_names:
                assert name in ir_names, (src, platform, f"missing required function {name}", ir_names)

            for fn in ir_functions:
                assert isinstance(fn["arity"], int) and fn["arity"] >= 0, (src, platform, fn)
                assert fn["frame_slots"] == fn["arity"], (src, platform, fn)
                assert len(fn["blocks"]) >= 1, (src, platform, fn)
                assert_cfg_closed(src, platform, fn)
                assert_helper_surface(src, platform, expected_target, fn)
                for block in fn["blocks"]:
                    assert isinstance(block["ops"], list), (src, platform, block)

            main = next(fn for fn in ir_functions if fn["name"] == "main")
            main_ops = [op for block in main["blocks"] for op in block["ops"]]
            main_kinds = {op["kind"] for op in main_ops}
            for kind in required_main_op_kinds:
                assert kind in main_kinds, (src, platform, f"missing main op kind {kind}", main_ops)
            for op in main_ops:
                if op["kind"] == "opaque_stmt":
                    assert op["stmt_type"] not in {"If", "While"}, (src, platform, op)
                if op["kind"] == "opaque_expr":
                    assert op["expr_type"] not in {"If", "While"}, (src, platform, op)
            main_terms = {block["terminator"]["kind"] for block in main["blocks"]}
            if label in {"hello", "list_ops"}:
                assert "branch" in main_terms and "jump" in main_terms, (src, platform, main["blocks"])
            if label == "hello":
                helper_names = {op["name"] for op in main_ops if op["kind"] == "runtime_helper_call"}
                assert {"print", "exit"}.issubset(helper_names), (src, platform, helper_names, main_ops)
            if label == "runtime_print":
                helper_names = {op["name"] for op in main_ops if op["kind"] == "runtime_helper_call"}
                assert "print" in helper_names, (src, platform, helper_names, main_ops)

            log.write(f"OK: {label} {platform} functions={len(ir_names)}\n")
            checked += 1

print(f"OK: native IR linked-surface parity fixtures passed ({checked} cases)")
PY
