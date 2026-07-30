#!/usr/bin/env python3
"""Lower validated native_ir_v0 JSON to the current textual LLVM subset."""

import json
import os
import re
import sys


def load_ir(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def target_triple(target):
    arch = target["arch"]
    os_name = target["os"]
    if arch == "x64" and os_name == "windows":
        return "x86_64-pc-windows-msvc"
    if arch == "x64" and os_name == "linux":
        return "x86_64-unknown-linux-gnu"
    if arch == "arm64" and os_name == "macos":
        return "arm64-apple-macosx"
    if arch == "arm64" and os_name == "linux":
        return "aarch64-unknown-linux-gnu"
    raise SystemExit(f"unsupported native IR LLVM probe target: {target}")


def llvm_name(prefix, raw, seq):
    safe = re.sub(r"[^A-Za-z0-9_.$-]", "_", raw or "")
    if not safe or not re.match(r"[A-Za-z_$.-]", safe[0]):
        safe = f"{prefix}{seq}"
    return safe.replace(".", "_").replace("-", "_")


def llvm_symbol_suffix(raw):
    safe = re.sub(r"[^A-Za-z0-9_]", "_", raw or "")
    if not safe:
        safe = "anon"
    if not re.match(r"[A-Za-z_]", safe[0]):
        safe = "_" + safe
    return safe


def llvm_helper_symbol(name):
    return "oren_llvm_helper_" + llvm_symbol_suffix(name)


def token_id(table, token):
    if token not in table:
        table[token] = len(table) + 1
    return table[token]


def llvm_bytes_literal(raw):
    data = raw.encode("utf-8") + b"\0"
    out = []
    for b in data:
        if 32 <= b < 127 and b not in (34, 92):
            out.append(chr(b))
        else:
            out.append(f"\\{b:02X}")
    return len(data), "".join(out)


def const_i64(op, token_table):
    kind = op.get("value_kind")
    value = op.get("value")
    if kind == "int":
        try:
            return str(int(value))
        except Exception:
            return str(token_id(token_table, f"int:{value}"))
    if kind == "bool":
        return "1" if value is True or value == "true" else "0"
    if kind == "nil":
        return "0"
    return str(token_id(token_table, f"{kind}:{value}"))


def collect_slots(fn):
    slots = []
    seen = set()
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "local_set":
                name = op["name"]
                if name not in seen:
                    seen.add(name)
                    slots.append(name)
    return slots


def collect_generic_helpers(fn):
    helpers = set()
    generated_helpers = {
        "print",
        "exit",
        "oren_string_len",
        "oren_string_eq",
        "oren_string_slice",
        "oren_string_byte_at",
        "oren_string_byte_at_unchecked",
        "oren_string_char_at",
        "oren_string_char_at_unchecked",
    }
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "runtime_helper_call" and op["name"] not in generated_helpers:
                helpers.add(op["name"])
    return sorted(helpers)


def validate_ir(ir):
    assert ir["schema"] == "native_ir_v0", ir.get("schema")
    assert ir["validation"]["ok"] is True, ir["validation"]
    assert ir["validation"]["errors"] == [], ir["validation"]
    type_map = {t["id"]: t for t in ir["types"]}
    assert type_map["tagged"]["bits"] == 64 and type_map["tagged"]["align"] == 8, type_map
    assert type_map["void"]["kind"] == "void", type_map
    assert len(ir["functions"]) > 0, ir
    main = next((fn for fn in ir["functions"] if fn["name"] == "main"), None)
    assert main is not None, [fn["name"] for fn in ir["functions"][:20]]
    assert main["return_type"] == "tagged", main
    value_types = {vt["value"]: vt["type"] for vt in main["value_types"]}
    assert value_types and all(t == "tagged" for t in value_types.values()), main["value_types"]
    helper_ops = [op for block in main["blocks"] for op in block["ops"] if op["kind"] == "runtime_helper_call"]
    for op in helper_ops:
        assert op["arg_types"] == ["tagged"] * len(op["args"]), op
        assert op["result_type"] == "tagged", op
    if os.environ.get("NATIVE_IR_LLVM_REQUIRE_HELPERS", "1") == "1":
        assert helper_ops, main
    return main, helper_ops, type_map


class FunctionLowerer:
    def __init__(self, fn, out):
        self.fn = fn
        self.out = out
        self.value_vars = {}
        self.token_table = {}
        self.scratch_seq = 0
        self.slots = collect_slots(fn)
        self.slot_vars = {name: f"%slot{idx}" for idx, name in enumerate(self.slots)}

    def result_var(self, value):
        if value not in self.value_vars:
            self.value_vars[value] = f"%v{len(self.value_vars)}"
        return self.value_vars[value]

    def scratch_var(self, prefix):
        name = f"%{prefix}{self.scratch_seq}"
        self.scratch_seq += 1
        return name

    def value_ref(self, value):
        assert value is None or isinstance(value, str), value
        if value is None:
            return "0"
        if value in self.value_vars:
            return self.value_vars[value]
        if value in self.slot_vars:
            tmp = self.scratch_var("load")
            self.out.write(f"  {tmp} = load i64, i64* {self.slot_vars[value]}, align 8\n")
            return tmp
        raise AssertionError(f"native IR value referenced before definition: {value}")

    def write_inst(self, inst):
        self.out.write(f"  {inst}\n")

    def lower(self):
        label_names = {
            block["label"]: llvm_name("bb", block["label"], idx)
            for idx, block in enumerate(self.fn["blocks"])
        }
        self.out.write("define i64 @oren_native_ir_main_probe() nounwind {\n")
        for bidx, block in enumerate(self.fn["blocks"]):
            self.out.write(f"{label_names[block['label']]}:\n")
            if bidx == 0:
                for name in self.slots:
                    self.write_inst(f"{self.slot_vars[name]} = alloca i64, align 8 ; local {name}")
                    self.write_inst(f"store i64 0, i64* {self.slot_vars[name]}, align 8")
            for op in block["ops"]:
                self.lower_op(op)
            self.lower_term(block["terminator"], label_names, bidx)
        self.out.write("}\n")
        return len(self.slots), len(self.value_vars), self.token_table

    def lower_op(self, op):
        kind = op["kind"]
        if kind == "const":
            dst = self.result_var(op["result"])
            literal = const_i64(op, self.token_table)
            self.write_inst(f"{dst} = add i64 0, {literal} ; const {op['value_kind']}")
        elif kind == "local_get":
            src = op["name"]
            assert src in self.slot_vars, (self.fn["name"], op, self.slots)
            self.write_inst(f"{self.result_var(op['result'])} = load i64, i64* {self.slot_vars[src]}, align 8")
        elif kind == "local_set":
            name = op["name"]
            assert name in self.slot_vars, (self.fn["name"], op, self.slots)
            self.write_inst(f"store i64 {self.value_ref(op['value'])}, i64* {self.slot_vars[name]}, align 8")
        elif kind == "binary":
            self.lower_binary(op)
        elif kind == "unary":
            self.lower_unary(op)
        elif kind == "call":
            for arg in op["args"]:
                self.value_ref(arg)
            dst = self.result_var(op["result"])
            callee_id = token_id(self.token_table, "call:" + op["callee"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_call(i64 {callee_id}, i64 {len(op['args'])})")
        elif kind == "runtime_helper_call":
            helper_args = [self.value_ref(arg) for arg in op["args"]]
            while len(helper_args) < 4:
                helper_args.append("0")
            dst = self.result_var(op["result"]) if op.get("result") is not None else self.scratch_var("helper")
            if op["name"] == "print":
                helper_call = f"{dst} = call i64 @oren_llvm_helper_print(i64 {helper_args[0]})"
                self.write_inst(f"{helper_call} ; helper print safepoint={op['safepoint']}")
                return
            if op["name"] == "exit":
                code = helper_args[0] if len(op["args"]) > 0 else "0"
                helper_call = f"{dst} = call i64 @oren_llvm_helper_exit(i64 {code})"
                self.write_inst(f"{helper_call} ; helper exit safepoint={op['safepoint']}")
                return
            if op["name"] == "oren_string_len":
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_len("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.write_inst(f"{helper_call} ; helper oren_string_len safepoint={op['safepoint']}")
                return
            if op["name"] == "oren_string_eq":
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_eq("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.write_inst(f"{helper_call} ; helper oren_string_eq safepoint={op['safepoint']}")
                return
            if op["name"] == "oren_string_slice":
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_slice("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.write_inst(f"{helper_call} ; helper oren_string_slice safepoint={op['safepoint']}")
                return
            if op["name"] in ("oren_string_byte_at", "oren_string_byte_at_unchecked"):
                helper_symbol = llvm_helper_symbol(op["name"])
                helper_call = (
                    f"{dst} = call i64 @{helper_symbol}("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.write_inst(f"{helper_call} ; helper {op['name']} safepoint={op['safepoint']}")
                return
            if op["name"] in ("oren_string_char_at", "oren_string_char_at_unchecked"):
                helper_symbol = llvm_helper_symbol(op["name"])
                helper_call = (
                    f"{dst} = call i64 @{helper_symbol}("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.write_inst(f"{helper_call} ; helper {op['name']} safepoint={op['safepoint']}")
                return
            helper_symbol = llvm_helper_symbol(op["name"])
            helper_call = (
                f"{dst} = call i64 @{helper_symbol}("
                f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                f"i64 {helper_args[2]}, i64 {helper_args[3]})"
            )
            self.write_inst(f"{helper_call} ; helper {op['name']} safepoint={op['safepoint']}")
        elif kind == "array":
            for elem in op["elements"]:
                self.value_ref(elem)
            dst = self.result_var(op["result"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_array(i64 {len(op['elements'])})")
        elif kind == "index_get":
            dst = self.result_var(op["result"])
            container = self.value_ref(op["container"])
            index = self.value_ref(op["index"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_index_get(i64 {container}, i64 {index})")
        elif kind == "index_set":
            container = self.value_ref(op["container"])
            index = self.value_ref(op["index"])
            value = self.value_ref(op["value"])
            self.write_inst(f"call void @oren_llvm_opaque_index_set(i64 {container}, i64 {index}, i64 {value})")
        elif kind == "expr_result":
            self.value_ref(op["value"])
        elif kind == "opaque_stmt":
            stmt_id = token_id(self.token_table, "stmt:" + op["stmt_type"])
            self.write_inst(f"call void @oren_llvm_opaque_stmt(i64 {stmt_id})")
        elif kind == "opaque_expr":
            dst = self.result_var(op["result"])
            expr_id = token_id(self.token_table, "expr:" + op["expr_type"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_expr(i64 {expr_id})")
        else:
            raise AssertionError((self.fn["name"], op))

    def lower_binary(self, op):
        dst = self.result_var(op["result"])
        left = self.value_ref(op["left"])
        right = self.value_ref(op["right"])
        bop = op["op"]
        if bop == "+":
            self.write_inst(f"{dst} = add i64 {left}, {right}")
        elif bop == "-":
            self.write_inst(f"{dst} = sub i64 {left}, {right}")
        elif bop == "*":
            self.write_inst(f"{dst} = mul i64 {left}, {right}")
        elif bop in ("==", "!=", "<", "<=", ">", ">="):
            pred = {"==": "eq", "!=": "ne", "<": "slt", "<=": "sle", ">": "sgt", ">=": "sge"}[bop]
            cmpv = self.scratch_var("cmp")
            self.write_inst(f"{cmpv} = icmp {pred} i64 {left}, {right}")
            self.write_inst(f"{dst} = zext i1 {cmpv} to i64")
        else:
            op_id = token_id(self.token_table, "binary:" + bop)
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_binary(i64 {op_id}, i64 {left}, i64 {right})")

    def lower_unary(self, op):
        dst = self.result_var(op["result"])
        val = self.value_ref(op["value"])
        if op["op"] == "-":
            self.write_inst(f"{dst} = sub i64 0, {val}")
        elif op["op"] == "!":
            cmpv = self.scratch_var("cmp")
            self.write_inst(f"{cmpv} = icmp eq i64 {val}, 0")
            self.write_inst(f"{dst} = zext i1 {cmpv} to i64")
        else:
            op_id = token_id(self.token_table, "unary:" + op["op"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_unary(i64 {op_id}, i64 {val})")

    def lower_term(self, term, label_names, block_index):
        if term["kind"] == "return":
            self.write_inst(f"ret i64 {self.value_ref(term.get('value'))}")
        elif term["kind"] == "jump":
            self.write_inst(f"br label %{label_names[term['target']]}")
        elif term["kind"] == "branch":
            cond = self.value_ref(term["cond"])
            cmpv = self.scratch_var(f"brcond{block_index}_")
            self.write_inst(f"{cmpv} = icmp ne i64 {cond}, 0")
            self.write_inst(f"br i1 {cmpv}, label %{label_names[term['true']]}, label %{label_names[term['false']]}")
        elif term["kind"] in ("panic", "unreachable"):
            self.write_inst("unreachable")
        else:
            raise AssertionError((self.fn["name"], term))


def lower_function(fn, out):
    return FunctionLowerer(fn, out).lower()


def collect_string_tokens(token_table):
    string_tokens = []
    for token, tid in token_table.items():
        if token.startswith("string:"):
            string_tokens.append((tid, token[len("string:") :]))
    string_tokens.sort()
    return string_tokens


def collect_const_values(fn):
    consts = {}
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "const":
                consts[op["result"]] = (op["value_kind"], op["value"])
    return consts


def collect_const_string_slices(fn, token_table):
    consts = collect_const_values(fn)
    slices = []
    seen = set()
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] != "runtime_helper_call" or op["name"] != "oren_string_slice":
                continue
            if len(op["args"]) < 3:
                continue
            source = consts.get(op["args"][0])
            start = consts.get(op["args"][1])
            end = consts.get(op["args"][2])
            if source is None or start is None or end is None:
                continue
            if source[0] != "string" or start[0] != "int" or end[0] != "int":
                continue
            try:
                start_i = int(start[1])
                end_i = int(end[1])
            except Exception:
                continue
            value = source[1]
            if start_i < 0 or end_i < start_i or end_i > len(value):
                continue
            source_tid = token_id(token_table, f"string:{value}")
            result_tid = token_id(token_table, f"string:{value[start_i:end_i]}")
            key = (source_tid, start_i, end_i, result_tid)
            if key not in seen:
                seen.add(key)
                slices.append(key)
    return sorted(slices)


def collect_const_string_byte_accesses(fn, token_table, helper_names):
    consts = collect_const_values(fn)
    accesses = []
    seen = set()
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] != "runtime_helper_call" or op["name"] not in helper_names:
                continue
            if len(op["args"]) < 2:
                continue
            source = consts.get(op["args"][0])
            index = consts.get(op["args"][1])
            if source is None or index is None:
                continue
            if source[0] != "string" or index[0] != "int":
                continue
            try:
                index_i = int(index[1])
            except Exception:
                continue
            data = source[1].encode("utf-8")
            if index_i < 0 or index_i >= len(data):
                continue
            source_tid = token_id(token_table, f"string:{source[1]}")
            key = (source_tid, index_i, data[index_i])
            if key not in seen:
                seen.add(key)
                accesses.append(key)
    return sorted(accesses)


def collect_const_string_char_accesses(fn, token_table, helper_names):
    consts = collect_const_values(fn)
    accesses = []
    seen = set()
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] != "runtime_helper_call" or op["name"] not in helper_names:
                continue
            if len(op["args"]) < 2:
                continue
            source = consts.get(op["args"][0])
            index = consts.get(op["args"][1])
            if source is None or index is None:
                continue
            if source[0] != "string" or index[0] != "int":
                continue
            try:
                index_i = int(index[1])
            except Exception:
                continue
            value = source[1]
            if index_i < 0 or index_i >= len(value):
                continue
            source_tid = token_id(token_table, f"string:{value}")
            result_tid = token_id(token_table, f"string:{value[index_i]}")
            key = (source_tid, index_i, result_tid)
            if key not in seen:
                seen.add(key)
                accesses.append(key)
    return sorted(accesses)


def emit_print_helper(out, token_table):
    string_tokens = collect_string_tokens(token_table)
    if not string_tokens:
        return

    out.write("\n")
    for tid, value in string_tokens:
        length, body = llvm_bytes_literal(value)
        out.write(
            f"@oren_llvm_string_token_{tid} = private unnamed_addr "
            f"constant [{length} x i8] c\"{body}\", align 1\n"
        )

    out.write("\n")
    out.write("define i64 @oren_llvm_helper_print(i64 %token) nounwind {\n")
    out.write("entry:\n")
    out.write("  switch i64 %token, label %unknown [\n")
    for tid, _value in string_tokens:
        out.write(f"    i64 {tid}, label %tok_{tid}\n")
    out.write("  ]\n")
    for tid, value in string_tokens:
        length = len(value.encode("utf-8")) + 1
        out.write(f"tok_{tid}:\n")
        out.write(
            f"  %p_{tid} = getelementptr inbounds [{length} x i8], "
            f"[{length} x i8]* @oren_llvm_string_token_{tid}, i64 0, i64 0\n"
        )
        out.write(f"  call i32 @puts(i8* %p_{tid})\n")
        out.write("  ret i64 0\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_exit_helper(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_helper_exit(i64 %code) nounwind {\n")
    out.write("entry:\n")
    out.write("  %code32 = trunc i64 %code to i32\n")
    out.write("  call void @exit(i32 %code32)\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_index_switch_helper(out, symbol, accesses):
    out.write("\n")
    out.write(
        f"define i64 @{symbol}("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    if not accesses:
        out.write("  ret i64 0\n")
        out.write("}\n")
        return

    by_source = {}
    for source_tid, index_i, result in accesses:
        by_source.setdefault(source_tid, []).append((index_i, result))

    out.write("  switch i64 %arg0, label %unknown [\n")
    for source_tid in sorted(by_source):
        out.write(f"    i64 {source_tid}, label %src_{source_tid}\n")
    out.write("  ]\n")
    for source_tid, indexes in sorted(by_source.items()):
        out.write(f"src_{source_tid}:\n")
        out.write("  switch i64 %arg1, label %unknown [\n")
        for index_i, _result in sorted(indexes):
            out.write(f"    i64 {index_i}, label %src_{source_tid}_idx_{index_i}\n")
        out.write("  ]\n")
        for index_i, result in sorted(indexes):
            out.write(f"src_{source_tid}_idx_{index_i}:\n")
            out.write(f"  ret i64 {result}\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_slice_helper(out, fn, token_table):
    slices = collect_const_string_slices(fn, token_table)

    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_slice("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    if not slices:
        out.write("  ret i64 0\n")
        out.write("}\n")
        return

    by_source = {}
    for source_tid, start_i, end_i, result_tid in slices:
        by_source.setdefault(source_tid, {}).setdefault(start_i, []).append((end_i, result_tid))

    out.write("  switch i64 %arg0, label %unknown [\n")
    for source_tid in sorted(by_source):
        out.write(f"    i64 {source_tid}, label %src_{source_tid}\n")
    out.write("  ]\n")
    for source_tid, starts in sorted(by_source.items()):
        out.write(f"src_{source_tid}:\n")
        out.write("  switch i64 %arg1, label %unknown [\n")
        for start_i in sorted(starts):
            out.write(f"    i64 {start_i}, label %src_{source_tid}_start_{start_i}\n")
        out.write("  ]\n")
        for start_i, ends in sorted(starts.items()):
            out.write(f"src_{source_tid}_start_{start_i}:\n")
            out.write("  switch i64 %arg2, label %unknown [\n")
            for end_i, _result_tid in sorted(ends):
                out.write(f"    i64 {end_i}, label %src_{source_tid}_slice_{start_i}_{end_i}\n")
            out.write("  ]\n")
            for end_i, result_tid in sorted(ends):
                out.write(f"src_{source_tid}_slice_{start_i}_{end_i}:\n")
                out.write(f"  ret i64 {result_tid}\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_byte_at_helpers(out, fn, token_table):
    byte_accesses = collect_const_string_byte_accesses(
        fn,
        token_table,
        {"oren_string_byte_at", "oren_string_byte_at_unchecked"},
    )
    emit_index_switch_helper(out, "oren_llvm_helper_oren_string_byte_at", byte_accesses)
    emit_index_switch_helper(out, "oren_llvm_helper_oren_string_byte_at_unchecked", byte_accesses)


def emit_string_char_at_helpers(out, fn, token_table):
    char_accesses = collect_const_string_char_accesses(
        fn,
        token_table,
        {"oren_string_char_at", "oren_string_char_at_unchecked"},
    )
    emit_index_switch_helper(out, "oren_llvm_helper_oren_string_char_at", char_accesses)
    emit_index_switch_helper(out, "oren_llvm_helper_oren_string_char_at_unchecked", char_accesses)


def emit_string_len_helper(out, token_table):
    string_tokens = [
        (tid, len(value.encode("utf-8")))
        for tid, value in collect_string_tokens(token_table)
    ]

    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_len("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    if not string_tokens:
        out.write("  ret i64 0\n")
        out.write("}\n")
        return
    out.write("  switch i64 %arg0, label %unknown [\n")
    for tid, _length in string_tokens:
        out.write(f"    i64 {tid}, label %tok_{tid}\n")
    out.write("  ]\n")
    for tid, length in string_tokens:
        out.write(f"tok_{tid}:\n")
        out.write(f"  ret i64 {length}\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_eq_helper(out, token_table):
    string_tokens = collect_string_tokens(token_table)

    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_eq("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    if not string_tokens:
        out.write("  ret i64 0\n")
        out.write("}\n")
        return
    out.write("  switch i64 %arg0, label %unknown [\n")
    for tid, _value in string_tokens:
        out.write(f"    i64 {tid}, label %tok_{tid}\n")
    out.write("  ]\n")
    for tid, _value in string_tokens:
        out.write(f"tok_{tid}:\n")
        out.write(f"  %eq_{tid} = icmp eq i64 %arg1, {tid}\n")
        out.write(f"  %ret_{tid} = zext i1 %eq_{tid} to i64\n")
        out.write(f"  ret i64 %ret_{tid}\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_module(ir_path, out_path, ir, main):
    schema = ir["schema"].encode("utf-8")
    schema_literal = "".join(
        chr(b) if 32 <= b < 127 and b not in (34, 92) else f"\\{b:02X}"
        for b in schema
    )
    with open(out_path, "w", encoding="utf-8") as out:
        out.write("; native_ir_llvm_lowered_subset_v0\n")
        out.write(f"source_filename = \"{ir_path}\"\n")
        out.write(f"target triple = \"{target_triple(ir['target'])}\"\n\n")
        out.write("@oren_native_ir_schema = private unnamed_addr constant ")
        out.write(f"[{len(schema) + 1} x i8] c\"{schema_literal}\\00\", align 1\n\n")
        out.write("declare i64 @oren_llvm_opaque_call(i64, i64)\n")
        out.write("declare i64 @oren_llvm_opaque_binary(i64, i64, i64)\n")
        out.write("declare i64 @oren_llvm_opaque_unary(i64, i64)\n")
        out.write("declare i64 @oren_llvm_opaque_array(i64)\n")
        out.write("declare i64 @oren_llvm_opaque_index_get(i64, i64)\n")
        out.write("declare void @oren_llvm_opaque_index_set(i64, i64, i64)\n")
        out.write("declare void @oren_llvm_opaque_stmt(i64)\n")
        out.write("declare i64 @oren_llvm_opaque_expr(i64)\n")
        for helper in collect_generic_helpers(main):
            out.write(f"declare i64 @{llvm_helper_symbol(helper)}(i64, i64, i64, i64, i64)\n")
        out.write("declare i32 @puts(i8*)\n\n")
        out.write("declare void @exit(i32)\n\n")
        slots, values, token_table = lower_function(main, out)
        emit_string_slice_helper(out, main, token_table)
        emit_string_byte_at_helpers(out, main, token_table)
        emit_string_char_at_helpers(out, main, token_table)
        emit_print_helper(out, token_table)
        emit_exit_helper(out)
        emit_string_len_helper(out, token_table)
        emit_string_eq_helper(out, token_table)
        return slots, values


def main(argv):
    if len(argv) != 4:
        raise SystemExit("usage: native_ir_llvm_lower.py <native-ir.json> <platform> <out.ll>")
    ir_path, platform, out_path = argv[1], argv[2], argv[3]
    ir = load_ir(ir_path)
    main_fn, helper_ops, type_map = validate_ir(ir)
    slots, values = emit_module(ir_path, out_path, ir, main_fn)
    print(
        f"native_ir_validated=1 platform={platform} functions={len(ir['functions'])} "
        f"main_helpers={len(helper_ops)} types={len(type_map)}"
    )
    print(
        f"llvm_ir_lowered=1 path={out_path} main_blocks={len(main_fn['blocks'])} "
        f"main_slots={slots} main_values={values}"
    )


if __name__ == "__main__":
    main(sys.argv)
