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


GENERATED_HELPERS = {
    "print",
    "exit",
    "oren_string_len",
    "oren_string_eq",
    "oren_string_slice",
    "oren_string_slice_unchecked",
    "oren_string_byte_at",
    "oren_string_byte_at_unchecked",
    "oren_string_char_at",
    "oren_string_char_at_unchecked",
    "oren_string_char_code_at",
}

STRING_DESCRIPTOR_HELPERS = {
    "oren_string_slice",
    "oren_string_slice_unchecked",
    "oren_string_char_at",
    "oren_string_char_at_unchecked",
}

LIST_LEN_HELPERS = {
    "oren_list_int_len",
    "oren_list_int_len_unchecked",
    "oren_list_len",
    "oren_list_len_unchecked",
}

LIST_NEW_HELPERS = {
    "oren_new_list",
    "oren_new_list_int",
}

LIST_GET_HELPERS = {
    "oren_list_get",
    "oren_list_get_unchecked",
    "oren_list_int_get",
    "oren_list_int_get_unchecked",
}

LIST_PUSH_HELPERS = {
    "oren_list_int_push",
    "oren_list_int_push_unchecked",
    "oren_list_push",
    "oren_list_push_unchecked",
}


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
    list_values = collect_list_descriptor_values(fn)
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] != "runtime_helper_call":
                continue
            if op["name"] in LIST_NEW_HELPERS:
                continue
            if op["name"] in (LIST_LEN_HELPERS | LIST_GET_HELPERS | LIST_PUSH_HELPERS):
                if op.get("args") and op["args"][0] in list_values:
                    continue
            if op["name"] not in GENERATED_HELPERS:
                helpers.add(op["name"])
    return sorted(helpers)


def function_needs_root_hooks(fn):
    descriptors = collect_descriptor_values(fn)
    list_values = collect_list_descriptor_values(fn)
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "runtime_helper_call" and op.get("safepoint") and op.get("roots"):
                return True
            if op["kind"] == "runtime_helper_call" and op.get("safepoint") and list_values:
                return True
            if op["kind"] == "binary" and op["op"] == "+":
                if op["left"] in descriptors and op["right"] in descriptors:
                    return True
    return False


def function_needs_list_alloc(fn):
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "array":
                return True
            if op["kind"] == "runtime_helper_call" and op.get("name") in LIST_NEW_HELPERS:
                return True
    return False


def collect_generated_helpers(fn):
    helpers = set()
    descriptors = collect_descriptor_values(fn)
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "runtime_helper_call" and op["name"] in GENERATED_HELPERS:
                helpers.add(op["name"])
            elif op["kind"] == "binary" and op["op"] == "+":
                if op["left"] in descriptors and op["right"] in descriptors:
                    helpers.add("oren_string_concat")
    if "oren_string_char_at" in helpers or "oren_string_char_at_unchecked" in helpers:
        helpers.add("oren_string_slice")
    if "oren_string_slice_unchecked" in helpers:
        helpers.add("oren_string_slice")
    return helpers


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
        self.const_values = collect_const_values(fn)
        self.descriptor_values, self.descriptor_block_in = collect_descriptor_analysis(fn)
        self.list_values, self.list_block_in = collect_list_descriptor_analysis(fn)
        self.current_descriptor_locals = set()
        self.current_list_locals = set()
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

    def emit_helper_call(self, op, helper_call, helper_name, root_values):
        mark = None
        string_roots = []
        list_roots = []
        seen_string_roots = set()
        seen_list_roots = set()
        for root_value in root_values:
            if root_value in self.descriptor_values and root_value not in seen_string_roots:
                string_roots.append(root_value)
                seen_string_roots.add(root_value)
            elif root_value in self.list_values and root_value not in seen_list_roots:
                list_roots.append(root_value)
                seen_list_roots.add(root_value)
        for local_name in sorted(self.current_descriptor_locals):
            if local_name not in seen_string_roots:
                string_roots.append(local_name)
                seen_string_roots.add(local_name)
        for local_name in sorted(self.current_list_locals):
            if local_name not in seen_list_roots:
                list_roots.append(local_name)
                seen_list_roots.add(local_name)
        if op.get("safepoint") and (string_roots or list_roots):
            mark = self.scratch_var("root_mark")
            self.write_inst(f"{mark} = call i64 @oren_llvm_runtime_roots_mark() ; safepoint roots mark")
            for root_value in string_roots:
                root_ref = self.value_ref(root_value)
                self.write_inst(
                    f"call void @oren_llvm_runtime_roots_push_string(i64 {root_ref}) ; safepoint root {root_value}"
                )
            for root_value in list_roots:
                root_ref = self.value_ref(root_value)
                self.write_inst(
                    f"call void @oren_llvm_runtime_roots_push_list(i64 {root_ref}) ; safepoint root list {root_value}"
                )
            self.write_inst("call void @oren_llvm_runtime_safepoint_poll() ; forced GC safepoint poll")
        self.write_inst(f"{helper_call} ; helper {helper_name} safepoint={op.get('safepoint', False)}")
        if mark is not None:
            self.write_inst(f"call void @oren_llvm_runtime_roots_reset(i64 {mark}) ; safepoint roots reset")

    def lower(self):
        label_names = {
            block["label"]: llvm_name("bb", block["label"], idx)
            for idx, block in enumerate(self.fn["blocks"])
        }
        self.out.write("define i64 @oren_native_ir_main_probe() nounwind {\n")
        for bidx, block in enumerate(self.fn["blocks"]):
            self.out.write(f"{label_names[block['label']]}:\n")
            self.current_descriptor_locals = set(self.descriptor_block_in.get(block["label"], set()))
            self.current_list_locals = set(self.list_block_in.get(block["label"], set()))
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
            if op.get("value_kind") == "string":
                tid = token_id(self.token_table, f"string:{op.get('value')}")
                self.write_inst(f"{dst} = ptrtoint %oren_llvm_string* @oren_llvm_string_desc_{tid} to i64 ; const string")
                return
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
            if op["value"] in self.descriptor_values:
                self.current_descriptor_locals.add(name)
            else:
                self.current_descriptor_locals.discard(name)
            if op["value"] in self.list_values:
                self.current_list_locals.add(name)
            else:
                self.current_list_locals.discard(name)
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
            root_values = [r["local"] for r in op.get("roots", []) if r.get("local")]
            if op["name"] == "print":
                helper_call = f"{dst} = call i64 @oren_llvm_helper_print(i64 {helper_args[0]})"
                self.emit_helper_call(op, helper_call, "print", root_values)
                return
            if op["name"] == "exit":
                code = helper_args[0] if len(op["args"]) > 0 else "0"
                helper_call = f"{dst} = call i64 @oren_llvm_helper_exit(i64 {code})"
                self.emit_helper_call(op, helper_call, "exit", root_values)
                return
            if op["name"] == "oren_string_len":
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_len("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.emit_helper_call(op, helper_call, "oren_string_len", root_values)
                return
            if op["name"] == "oren_string_eq":
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_eq("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.emit_helper_call(op, helper_call, "oren_string_eq", root_values)
                return
            if op["name"] in LIST_NEW_HELPERS:
                cap = helper_args[0] if len(op["args"]) > 0 else "0"
                helper_call = f"{dst} = call i64 @oren_llvm_runtime_alloc_list_with_capacity(i64 0, i64 {cap})"
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in LIST_LEN_HELPERS and len(op["args"]) > 0 and op["args"][0] in self.list_values:
                helper_call = f"{dst} = call i64 @oren_llvm_helper_oren_list_len(i64 {helper_args[0]})"
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in LIST_GET_HELPERS and len(op["args"]) > 1 and op["args"][0] in self.list_values:
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_list_get("
                    f"i64 {helper_args[0]}, i64 {helper_args[1]})"
                )
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in LIST_PUSH_HELPERS and len(op["args"]) > 1 and op["args"][0] in self.list_values:
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_list_push("
                    f"i64 {helper_args[0]}, i64 {helper_args[1]})"
                )
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in ("oren_string_slice", "oren_string_slice_unchecked"):
                helper_symbol = llvm_helper_symbol(op["name"])
                helper_call = (
                    f"{dst} = call i64 @{helper_symbol}("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in ("oren_string_byte_at", "oren_string_byte_at_unchecked", "oren_string_char_code_at"):
                helper_symbol = llvm_helper_symbol(op["name"])
                helper_call = (
                    f"{dst} = call i64 @{helper_symbol}("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            if op["name"] in ("oren_string_char_at", "oren_string_char_at_unchecked"):
                helper_symbol = llvm_helper_symbol(op["name"])
                helper_call = (
                    f"{dst} = call i64 @{helper_symbol}("
                    f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                    f"i64 {helper_args[2]}, i64 {helper_args[3]})"
                )
                self.emit_helper_call(op, helper_call, op["name"], root_values)
                return
            helper_symbol = llvm_helper_symbol(op["name"])
            helper_call = (
                f"{dst} = call i64 @{helper_symbol}("
                f"i64 {len(op['args'])}, i64 {helper_args[0]}, i64 {helper_args[1]}, "
                f"i64 {helper_args[2]}, i64 {helper_args[3]})"
            )
            self.emit_helper_call(op, helper_call, op["name"], root_values)
        elif kind == "array":
            for elem in op["elements"]:
                self.value_ref(elem)
            dst = self.result_var(op["result"])
            self.write_inst(f"{dst} = call i64 @oren_llvm_runtime_alloc_list(i64 {len(op['elements'])})")
            list_ptr = self.scratch_var("list_desc")
            data_ptr_ptr = self.scratch_var("list_datap")
            data_ptr = self.scratch_var("list_data")
            self.write_inst(f"{list_ptr} = inttoptr i64 {dst} to %oren_llvm_list*")
            self.write_inst(
                f"{data_ptr_ptr} = getelementptr inbounds %oren_llvm_list, "
                f"%oren_llvm_list* {list_ptr}, i32 0, i32 1"
            )
            self.write_inst(f"{data_ptr} = load i64*, i64** {data_ptr_ptr}, align 8")
            for idx, elem in enumerate(op["elements"]):
                elem_ptr = self.scratch_var("list_elem")
                self.write_inst(f"{elem_ptr} = getelementptr inbounds i64, i64* {data_ptr}, i64 {idx}")
                self.write_inst(f"store i64 {self.value_ref(elem)}, i64* {elem_ptr}, align 8")
        elif kind == "index_get":
            dst = self.result_var(op["result"])
            container = self.value_ref(op["container"])
            index = self.value_ref(op["index"])
            if op["container"] in self.list_values:
                self.write_inst(f"{dst} = call i64 @oren_llvm_helper_oren_list_get(i64 {container}, i64 {index})")
            else:
                self.write_inst(f"{dst} = call i64 @oren_llvm_opaque_index_get(i64 {container}, i64 {index})")
        elif kind == "index_set":
            container = self.value_ref(op["container"])
            index = self.value_ref(op["index"])
            value = self.value_ref(op["value"])
            if op["container"] in self.list_values:
                self.write_inst(f"call void @oren_llvm_helper_oren_list_set(i64 {container}, i64 {index}, i64 {value})")
            else:
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
            if op["left"] in self.descriptor_values and op["right"] in self.descriptor_values:
                helper_call = (
                    f"{dst} = call i64 @oren_llvm_helper_oren_string_concat("
                    f"i64 2, i64 {left}, i64 {right}, i64 0, i64 0)"
                )
                self.emit_helper_call({"safepoint": True}, helper_call, "oren_string_concat", [op["left"], op["right"]])
                return
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
    local_assigns = {}
    for block in fn["blocks"]:
        for op in block["ops"]:
            if op["kind"] == "local_set":
                local_assigns.setdefault(op["name"], []).append(op["value"])

    local_consts = {}
    changed = True
    while changed:
        changed = False
        for block in fn["blocks"]:
            for op in block["ops"]:
                if op["kind"] == "const":
                    new_value = (op["value_kind"], op["value"])
                    old_value = consts.get(op["result"])
                    if old_value != new_value:
                        consts[op["result"]] = new_value
                        changed = True
                elif op["kind"] == "local_get":
                    assignments = local_assigns.get(op["name"], [])
                    if len(assignments) != 1:
                        continue
                    assigned_value = assignments[0]
                    value = consts.get(assigned_value)
                    if value is None:
                        continue
                    if local_consts.get(op["name"]) != value:
                        local_consts[op["name"]] = value
                        changed = True
                    old_value = consts.get(op["result"])
                    if old_value != value:
                        consts[op["result"]] = value
                        changed = True
    return consts


def collect_descriptor_values(fn):
    descriptors, _ = collect_descriptor_analysis(fn)
    return descriptors


def collect_list_descriptor_values(fn):
    values, _ = collect_list_descriptor_analysis(fn)
    return values


def collect_descriptor_analysis(fn):
    string_values, string_in, _, _ = collect_descriptor_facts(fn)
    return string_values, string_in


def collect_list_descriptor_analysis(fn):
    _, _, list_values, list_in = collect_descriptor_facts(fn)
    return list_values, list_in


def const_int_value(consts, value):
    item = consts.get(value)
    if not item or item[0] != "int":
        return None
    try:
        return int(item[1])
    except Exception:
        return None


def intersect_origin_envs(envs):
    if not envs:
        return {}
    keys = set(envs[0])
    for env in envs[1:]:
        keys &= set(env)
    out = {}
    for key in keys:
        value = envs[0][key]
        if all(env.get(key) == value for env in envs[1:]):
            out[key] = value
    return out


def collect_descriptor_facts(fn):
    blocks = fn["blocks"]
    labels = [block["label"] for block in blocks]
    all_slots = set(collect_slots(fn))
    consts = collect_const_values(fn)
    preds = {label: [] for label in labels}
    for block in blocks:
        for target in term_successors(block["terminator"]):
            if target in preds:
                preds[target].append(block["label"])

    out_string_env = {label: set(all_slots) for label in labels}
    out_list_env = {label: set(all_slots) for label in labels}
    out_origin_env = {label: {} for label in labels}
    string_in_env = {label: set() for label in labels}
    list_in_env = {label: set() for label in labels}
    final_strings = set()
    final_lists = set()
    changed = True
    while changed:
        changed = False
        strings = set()
        lists = set()
        value_list_origin = {}
        origin_elements = {}
        mutated_origins = set()
        next_string_out = {}
        next_list_out = {}
        next_origin_out = {}
        next_string_in = {}
        next_list_in = {}
        for idx, block in enumerate(blocks):
            label = block["label"]
            if idx == 0 or not preds[label]:
                local_strings = set()
                local_lists = set()
                local_origins = {}
            else:
                incoming_strings = [out_string_env[pred] for pred in preds[label]]
                incoming_lists = [out_list_env[pred] for pred in preds[label]]
                incoming_origins = [out_origin_env[pred] for pred in preds[label]]
                local_strings = set.intersection(*incoming_strings) if incoming_strings else set()
                local_lists = set.intersection(*incoming_lists) if incoming_lists else set()
                local_origins = intersect_origin_envs(incoming_origins)
            next_string_in[label] = set(local_strings)
            next_list_in[label] = set(local_lists)

            for op in block["ops"]:
                result = op.get("result")
                kind = op["kind"]
                if kind == "const" and op.get("value_kind") == "string":
                    strings.add(result)
                elif kind == "runtime_helper_call" and op.get("name") in STRING_DESCRIPTOR_HELPERS:
                    if result is not None:
                        strings.add(result)
                elif kind == "runtime_helper_call" and op.get("name") in LIST_NEW_HELPERS:
                    if result is not None:
                        lists.add(result)
                        value_list_origin[result] = result
                        origin_elements[result] = {}
                elif kind == "runtime_helper_call" and op.get("name") in LIST_PUSH_HELPERS:
                    if op.get("args"):
                        origin = value_list_origin.get(op["args"][0])
                        if origin is not None:
                            mutated_origins.add(origin)
                            origin_elements.pop(origin, None)
                            if result is not None:
                                lists.add(result)
                                value_list_origin[result] = origin
                elif kind == "runtime_helper_call" and op.get("name") in LIST_GET_HELPERS:
                    if result is not None and len(op.get("args", [])) > 1:
                        apply_list_element_fact(
                            op["args"][0],
                            op["args"][1],
                            result,
                            consts,
                            strings,
                            lists,
                            value_list_origin,
                            origin_elements,
                            mutated_origins,
                        )
                elif kind == "binary" and op.get("op") == "+":
                    if op["left"] in strings and op["right"] in strings:
                        strings.add(result)
                elif kind == "array":
                    lists.add(result)
                    value_list_origin[result] = result
                    elems = {}
                    for elem_idx, elem in enumerate(op.get("elements", [])):
                        if elem in strings or elem in lists:
                            elems[elem_idx] = elem
                    origin_elements[result] = elems
                elif kind == "index_get":
                    apply_list_element_fact(
                        op["container"],
                        op["index"],
                        result,
                        consts,
                        strings,
                        lists,
                        value_list_origin,
                        origin_elements,
                        mutated_origins,
                    )
                elif kind == "index_set":
                    origin = value_list_origin.get(op["container"])
                    if origin is not None:
                        mutated_origins.add(origin)
                        origin_elements.pop(origin, None)
                elif kind == "local_get":
                    if op["name"] in local_strings:
                        strings.add(result)
                    if op["name"] in local_lists:
                        lists.add(result)
                        origin = local_origins.get(op["name"])
                        if origin is not None:
                            value_list_origin[result] = origin
                elif kind == "local_set":
                    if op["value"] in strings:
                        local_strings.add(op["name"])
                    else:
                        local_strings.discard(op["name"])
                    if op["value"] in lists:
                        local_lists.add(op["name"])
                        origin = value_list_origin.get(op["value"])
                        if origin is not None:
                            local_origins[op["name"]] = origin
                        else:
                            local_origins.pop(op["name"], None)
                    else:
                        local_lists.discard(op["name"])
                        local_origins.pop(op["name"], None)
            next_string_out[label] = local_strings
            next_list_out[label] = local_lists
            next_origin_out[label] = local_origins

        if next_string_out != out_string_env:
            out_string_env = next_string_out
            changed = True
        if next_list_out != out_list_env:
            out_list_env = next_list_out
            changed = True
        if next_origin_out != out_origin_env:
            out_origin_env = next_origin_out
            changed = True
        if next_string_in != string_in_env:
            string_in_env = next_string_in
            changed = True
        if next_list_in != list_in_env:
            list_in_env = next_list_in
            changed = True
        if strings != final_strings:
            final_strings = strings
            changed = True
        if lists != final_lists:
            final_lists = lists
            changed = True
    return final_strings, string_in_env, final_lists, list_in_env


def apply_list_element_fact(
    container,
    index,
    result,
    consts,
    strings,
    lists,
    value_list_origin,
    origin_elements,
    mutated_origins,
):
    elem_idx = const_int_value(consts, index)
    origin = value_list_origin.get(container)
    if elem_idx is None or origin is None or origin in mutated_origins:
        return
    source = origin_elements.get(origin, {}).get(elem_idx)
    if source is None:
        return
    if source in strings:
        strings.add(result)
        return
    if source in lists:
        lists.add(result)
        source_origin = value_list_origin.get(source)
        if source_origin is not None:
            value_list_origin[result] = source_origin


def term_successors(term):
    kind = term["kind"]
    if kind == "jump":
        return [term["target"]]
    if kind == "branch":
        return [term["true"], term["false"]]
    return []


def emit_string_globals(out, token_table):
    string_tokens = collect_string_tokens(token_table)
    if not string_tokens:
        return

    out.write("\n")
    for tid, value in string_tokens:
        length, body = llvm_bytes_literal(value)
        out.write(
            f"@oren_llvm_string_bytes_{tid} = private unnamed_addr "
            f"constant [{length} x i8] c\"{body}\", align 1\n"
        )
        out.write(
            f"@oren_llvm_string_desc_{tid} = private constant %oren_llvm_string {{ "
            f"i64 {length - 1}, i8* getelementptr inbounds "
            f"([{length} x i8], [{length} x i8]* @oren_llvm_string_bytes_{tid}, i64 0, i64 0), "
            "i64 0 }, align 8\n"
        )


def emit_print_helper(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_helper_print(i64 %token) nounwind {\n")
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %token, 0\n")
    out.write("  br i1 %is_null, label %unknown, label %load\n")
    out.write("load:\n")
    out.write("  %str = inttoptr i64 %token to %oren_llvm_string*\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %str, i32 0, i32 1\n")
    out.write("  %data = load i8*, i8** %datap, align 8\n")
    out.write("  call i32 @puts(i8* %data)\n")
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


def emit_string_runtime_alloc(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_runtime_alloc_string(i64 %len) nounwind {\n")
    out.write("entry:\n")
    out.write("  %alloc_len = add i64 %len, 1\n")
    out.write("  %bytes = call i8* @oren_llvm_runtime_alloc_bytes(i64 %alloc_len, i64 1)\n")
    out.write("  %nul_p = getelementptr inbounds i8, i8* %bytes, i64 %len\n")
    out.write("  store i8 0, i8* %nul_p, align 1\n")
    out.write("  %raw_desc = call i8* @oren_llvm_runtime_alloc_bytes(i64 24, i64 2)\n")
    out.write("  %desc = bitcast i8* %raw_desc to %oren_llvm_string*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %desc, i32 0, i32 0\n")
    out.write("  store i64 %len, i64* %lenp, align 8\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %desc, i32 0, i32 1\n")
    out.write("  store i8* %bytes, i8** %datap, align 8\n")
    out.write("  %ownerp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %desc, i32 0, i32 2\n")
    out.write("  store i64 1, i64* %ownerp, align 8\n")
    out.write("  %ret = ptrtoint %oren_llvm_string* %desc to i64\n")
    out.write("  call void @oren_llvm_runtime_register_string(i64 %ret, i8* %bytes, i64 %len)\n")
    out.write("  ret i64 %ret\n")
    out.write("}\n")


def emit_string_slice_helper(out):
    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_slice("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %arg0, 0\n")
    out.write("  br i1 %is_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %src = inttoptr i64 %arg0 to %oren_llvm_string*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %src, i32 0, i32 0\n")
    out.write("  %src_len = load i64, i64* %lenp, align 8\n")
    out.write("  %start_nonneg = icmp sge i64 %arg1, 0\n")
    out.write("  %end_ge_start = icmp sge i64 %arg2, %arg1\n")
    out.write("  %end_le_len = icmp sle i64 %arg2, %src_len\n")
    out.write("  %ok_a = and i1 %start_nonneg, %end_ge_start\n")
    out.write("  %ok = and i1 %ok_a, %end_le_len\n")
    out.write("  br i1 %ok, label %copy, label %invalid\n")
    out.write("copy:\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %src, i32 0, i32 1\n")
    out.write("  %src_data = load i8*, i8** %datap, align 8\n")
    out.write("  %slice_len = sub i64 %arg2, %arg1\n")
    out.write("  %slice_ret = call i64 @oren_llvm_runtime_alloc_string(i64 %slice_len)\n")
    out.write("  %slice_desc = inttoptr i64 %slice_ret to %oren_llvm_string*\n")
    out.write("  %slice_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %slice_desc, i32 0, i32 1\n")
    out.write("  %bytes = load i8*, i8** %slice_datap, align 8\n")
    out.write("  %src_start = getelementptr inbounds i8, i8* %src_data, i64 %arg1\n")
    out.write("  call i8* @memcpy(i8* %bytes, i8* %src_start, i64 %slice_len)\n")
    out.write("  ret i64 %slice_ret\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_slice_unchecked_helper(out):
    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_slice_unchecked("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write(
        "  %ret = call i64 @oren_llvm_helper_oren_string_slice("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3)\n"
    )
    out.write("  ret i64 %ret\n")
    out.write("}\n")


def emit_string_concat_helper(out):
    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_concat("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %a_null = icmp eq i64 %arg0, 0\n")
    out.write("  %b_null = icmp eq i64 %arg1, 0\n")
    out.write("  %any_null = or i1 %a_null, %b_null\n")
    out.write("  br i1 %any_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %a = inttoptr i64 %arg0 to %oren_llvm_string*\n")
    out.write("  %b = inttoptr i64 %arg1 to %oren_llvm_string*\n")
    out.write("  %a_lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %a, i32 0, i32 0\n")
    out.write("  %b_lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %b, i32 0, i32 0\n")
    out.write("  %a_len = load i64, i64* %a_lenp, align 8\n")
    out.write("  %b_len = load i64, i64* %b_lenp, align 8\n")
    out.write("  %a_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %a, i32 0, i32 1\n")
    out.write("  %b_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %b, i32 0, i32 1\n")
    out.write("  %a_data = load i8*, i8** %a_datap, align 8\n")
    out.write("  %b_data = load i8*, i8** %b_datap, align 8\n")
    out.write("  %out_len = add i64 %a_len, %b_len\n")
    out.write("  %concat_ret = call i64 @oren_llvm_runtime_alloc_string(i64 %out_len)\n")
    out.write("  %concat_desc = inttoptr i64 %concat_ret to %oren_llvm_string*\n")
    out.write("  %concat_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %concat_desc, i32 0, i32 1\n")
    out.write("  %bytes = load i8*, i8** %concat_datap, align 8\n")
    out.write("  call i8* @memcpy(i8* %bytes, i8* %a_data, i64 %a_len)\n")
    out.write("  %b_dst = getelementptr inbounds i8, i8* %bytes, i64 %a_len\n")
    out.write("  call i8* @memcpy(i8* %b_dst, i8* %b_data, i64 %b_len)\n")
    out.write("  ret i64 %concat_ret\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_byte_at_helper(out, symbol):
    out.write("\n")
    out.write(
        f"define i64 @{symbol}("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %arg0, 0\n")
    out.write("  br i1 %is_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %str = inttoptr i64 %arg0 to %oren_llvm_string*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %str, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  %idx_nonneg = icmp sge i64 %arg1, 0\n")
    out.write("  %idx_lt_len = icmp slt i64 %arg1, %len\n")
    out.write("  %ok = and i1 %idx_nonneg, %idx_lt_len\n")
    out.write("  br i1 %ok, label %read, label %invalid\n")
    out.write("read:\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %str, i32 0, i32 1\n")
    out.write("  %data = load i8*, i8** %datap, align 8\n")
    out.write("  %ptr = getelementptr inbounds i8, i8* %data, i64 %arg1\n")
    out.write("  %byte = load i8, i8* %ptr, align 1\n")
    out.write("  %ret = zext i8 %byte to i64\n")
    out.write("  ret i64 %ret\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_byte_at_helpers(out):
    emit_string_byte_at_helper(out, "oren_llvm_helper_oren_string_byte_at")
    emit_string_byte_at_helper(out, "oren_llvm_helper_oren_string_byte_at_unchecked")
    emit_string_byte_at_helper(out, "oren_llvm_helper_oren_string_char_code_at")


def emit_string_char_at_helper(out, symbol):
    out.write("\n")
    out.write(
        f"define i64 @{symbol}("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %end = add i64 %arg1, 1\n")
    out.write("  %ret = call i64 @oren_llvm_helper_oren_string_slice(i64 3, i64 %arg0, i64 %arg1, i64 %end, i64 0)\n")
    out.write("  ret i64 %ret\n")
    out.write("}\n")


def emit_string_char_at_helpers(out):
    emit_string_char_at_helper(out, "oren_llvm_helper_oren_string_char_at")
    emit_string_char_at_helper(out, "oren_llvm_helper_oren_string_char_at_unchecked")


def emit_string_len_helper(out):
    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_len("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %arg0, 0\n")
    out.write("  br i1 %is_null, label %unknown, label %load\n")
    out.write("load:\n")
    out.write("  %str = inttoptr i64 %arg0 to %oren_llvm_string*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %str, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  ret i64 %len\n")
    out.write("unknown:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_string_eq_helper(out):
    out.write("\n")
    out.write(
        "define i64 @oren_llvm_helper_oren_string_eq("
        "i64 %argc, i64 %arg0, i64 %arg1, i64 %arg2, i64 %arg3) nounwind {\n"
    )
    out.write("entry:\n")
    out.write("  %same_handle = icmp eq i64 %arg0, %arg1\n")
    out.write("  br i1 %same_handle, label %true, label %nonnull\n")
    out.write("nonnull:\n")
    out.write("  %a_null = icmp eq i64 %arg0, 0\n")
    out.write("  %b_null = icmp eq i64 %arg1, 0\n")
    out.write("  %any_null = or i1 %a_null, %b_null\n")
    out.write("  br i1 %any_null, label %false, label %load\n")
    out.write("load:\n")
    out.write("  %a = inttoptr i64 %arg0 to %oren_llvm_string*\n")
    out.write("  %b = inttoptr i64 %arg1 to %oren_llvm_string*\n")
    out.write("  %a_lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %a, i32 0, i32 0\n")
    out.write("  %b_lenp = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %b, i32 0, i32 0\n")
    out.write("  %a_len = load i64, i64* %a_lenp, align 8\n")
    out.write("  %b_len = load i64, i64* %b_lenp, align 8\n")
    out.write("  %len_eq = icmp eq i64 %a_len, %b_len\n")
    out.write("  br i1 %len_eq, label %cmp, label %false\n")
    out.write("cmp:\n")
    out.write("  %a_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %a, i32 0, i32 1\n")
    out.write("  %b_datap = getelementptr inbounds %oren_llvm_string, %oren_llvm_string* %b, i32 0, i32 1\n")
    out.write("  %a_data = load i8*, i8** %a_datap, align 8\n")
    out.write("  %b_data = load i8*, i8** %b_datap, align 8\n")
    out.write("  %cmp_rc = call i32 @memcmp(i8* %a_data, i8* %b_data, i64 %a_len)\n")
    out.write("  %bytes_eq = icmp eq i32 %cmp_rc, 0\n")
    out.write("  br i1 %bytes_eq, label %true, label %false\n")
    out.write("true:\n")
    out.write("  ret i64 1\n")
    out.write("false:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_list_runtime_alloc(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_runtime_alloc_list(i64 %len) nounwind {\n")
    out.write("entry:\n")
    out.write("  %ret = call i64 @oren_llvm_runtime_alloc_list_with_capacity(i64 %len, i64 %len)\n")
    out.write("  ret i64 %ret\n")
    out.write("}\n")
    out.write("\n")
    out.write("define i64 @oren_llvm_runtime_alloc_list_with_capacity(i64 %len, i64 %cap) nounwind {\n")
    out.write("entry:\n")
    out.write("  %neg = icmp slt i64 %len, 0\n")
    out.write("  %cap_lt_len = icmp slt i64 %cap, %len\n")
    out.write("  %invalid_input = or i1 %neg, %cap_lt_len\n")
    out.write("  br i1 %invalid_input, label %invalid, label %alloc\n")
    out.write("alloc:\n")
    out.write("  %elem_bytes = mul i64 %cap, 8\n")
    out.write("  %raw_data = call i8* @oren_llvm_runtime_alloc_bytes(i64 %elem_bytes, i64 3)\n")
    out.write("  %data = bitcast i8* %raw_data to i64*\n")
    out.write("  %raw_desc = call i8* @oren_llvm_runtime_alloc_bytes(i64 32, i64 4)\n")
    out.write("  %desc = bitcast i8* %raw_desc to %oren_llvm_list*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %desc, i32 0, i32 0\n")
    out.write("  store i64 %len, i64* %lenp, align 8\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %desc, i32 0, i32 1\n")
    out.write("  store i64* %data, i64** %datap, align 8\n")
    out.write("  %ownerp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %desc, i32 0, i32 2\n")
    out.write("  store i64 1, i64* %ownerp, align 8\n")
    out.write("  %capp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %desc, i32 0, i32 3\n")
    out.write("  store i64 %cap, i64* %capp, align 8\n")
    out.write("  %ret = ptrtoint %oren_llvm_list* %desc to i64\n")
    out.write("  call void @oren_llvm_runtime_register_list(i64 %ret, i64* %data, i64 %len)\n")
    out.write("  ret i64 %ret\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_list_len_helper(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_helper_oren_list_len(i64 %list_handle) nounwind {\n")
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %list_handle, 0\n")
    out.write("  br i1 %is_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %list = inttoptr i64 %list_handle to %oren_llvm_list*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  ret i64 %len\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_list_get_helper(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_helper_oren_list_get(i64 %list_handle, i64 %idx) nounwind {\n")
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %list_handle, 0\n")
    out.write("  br i1 %is_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %list = inttoptr i64 %list_handle to %oren_llvm_list*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  %idx_nonneg = icmp sge i64 %idx, 0\n")
    out.write("  %idx_lt_len = icmp slt i64 %idx, %len\n")
    out.write("  %ok = and i1 %idx_nonneg, %idx_lt_len\n")
    out.write("  br i1 %ok, label %read, label %invalid\n")
    out.write("read:\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 1\n")
    out.write("  %data = load i64*, i64** %datap, align 8\n")
    out.write("  %elem = getelementptr inbounds i64, i64* %data, i64 %idx\n")
    out.write("  %ret = load i64, i64* %elem, align 8\n")
    out.write("  ret i64 %ret\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_list_push_helper(out):
    out.write("\n")
    out.write("define i64 @oren_llvm_helper_oren_list_push(i64 %list_handle, i64 %value) nounwind {\n")
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %list_handle, 0\n")
    out.write("  br i1 %is_null, label %invalid, label %load\n")
    out.write("load:\n")
    out.write("  %list = inttoptr i64 %list_handle to %oren_llvm_list*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 1\n")
    out.write("  %data = load i64*, i64** %datap, align 8\n")
    out.write("  %capp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 3\n")
    out.write("  %cap = load i64, i64* %capp, align 8\n")
    out.write("  %has_room = icmp slt i64 %len, %cap\n")
    out.write("  br i1 %has_room, label %write, label %grow\n")
    out.write("grow:\n")
    out.write("  %double_cap = mul i64 %cap, 2\n")
    out.write("  %cap_too_small = icmp slt i64 %double_cap, 4\n")
    out.write("  %next_cap = select i1 %cap_too_small, i64 4, i64 %double_cap\n")
    out.write("  %new_bytes = mul i64 %next_cap, 8\n")
    out.write("  %new_raw = call i8* @oren_llvm_runtime_alloc_bytes(i64 %new_bytes, i64 3)\n")
    out.write("  %old_raw = bitcast i64* %data to i8*\n")
    out.write("  %copy_bytes = mul i64 %len, 8\n")
    out.write("  call i8* @memcpy(i8* %new_raw, i8* %old_raw, i64 %copy_bytes)\n")
    out.write("  %new_data = bitcast i8* %new_raw to i64*\n")
    out.write("  store i64* %new_data, i64** %datap, align 8\n")
    out.write("  store i64 %next_cap, i64* %capp, align 8\n")
    out.write("  br label %write\n")
    out.write("write:\n")
    out.write("  %cur_data = load i64*, i64** %datap, align 8\n")
    out.write("  %elem = getelementptr inbounds i64, i64* %cur_data, i64 %len\n")
    out.write("  store i64 %value, i64* %elem, align 8\n")
    out.write("  %next_len = add i64 %len, 1\n")
    out.write("  store i64 %next_len, i64* %lenp, align 8\n")
    out.write("  ret i64 %list_handle\n")
    out.write("invalid:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")


def emit_list_set_helper(out):
    out.write("\n")
    out.write("define void @oren_llvm_helper_oren_list_set(i64 %list_handle, i64 %idx, i64 %value) nounwind {\n")
    out.write("entry:\n")
    out.write("  %is_null = icmp eq i64 %list_handle, 0\n")
    out.write("  br i1 %is_null, label %done, label %load\n")
    out.write("load:\n")
    out.write("  %list = inttoptr i64 %list_handle to %oren_llvm_list*\n")
    out.write("  %lenp = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 0\n")
    out.write("  %len = load i64, i64* %lenp, align 8\n")
    out.write("  %idx_nonneg = icmp sge i64 %idx, 0\n")
    out.write("  %idx_lt_len = icmp slt i64 %idx, %len\n")
    out.write("  %ok = and i1 %idx_nonneg, %idx_lt_len\n")
    out.write("  br i1 %ok, label %write, label %done\n")
    out.write("write:\n")
    out.write("  %datap = getelementptr inbounds %oren_llvm_list, %oren_llvm_list* %list, i32 0, i32 1\n")
    out.write("  %data = load i64*, i64** %datap, align 8\n")
    out.write("  %elem = getelementptr inbounds i64, i64* %data, i64 %idx\n")
    out.write("  store i64 %value, i64* %elem, align 8\n")
    out.write("  ret void\n")
    out.write("done:\n")
    out.write("  ret void\n")
    out.write("}\n")


def emit_module(ir_path, out_path, ir, main):
    schema = ir["schema"].encode("utf-8")
    schema_literal = "".join(
        chr(b) if 32 <= b < 127 and b not in (34, 92) else f"\\{b:02X}"
        for b in schema
    )
    helpers_to_emit = collect_generated_helpers(main)
    needs_string_alloc = bool({"oren_string_slice", "oren_string_concat"} & helpers_to_emit)
    needs_list_alloc = function_needs_list_alloc(main)
    needs_alloc_bytes = needs_string_alloc or needs_list_alloc
    with open(out_path, "w", encoding="utf-8") as out:
        out.write("; native_ir_llvm_lowered_subset_v0\n")
        out.write(f"source_filename = \"{ir_path}\"\n")
        out.write(f"target triple = \"{target_triple(ir['target'])}\"\n\n")
        out.write("%oren_llvm_string = type { i64, i8*, i64 }\n")
        out.write("%oren_llvm_list = type { i64, i64*, i64, i64 }\n\n")
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
        if function_needs_root_hooks(main):
            out.write("declare i64 @oren_llvm_runtime_roots_mark()\n")
            out.write("declare void @oren_llvm_runtime_roots_push_string(i64)\n")
            out.write("declare void @oren_llvm_runtime_roots_push_list(i64)\n")
            out.write("declare void @oren_llvm_runtime_safepoint_poll()\n")
            out.write("declare void @oren_llvm_runtime_roots_reset(i64)\n")
        if "print" in helpers_to_emit:
            out.write("declare i32 @puts(i8*)\n")
        if needs_alloc_bytes:
            out.write("declare i8* @oren_llvm_runtime_alloc_bytes(i64, i64)\n")
        if needs_string_alloc:
            out.write("declare void @oren_llvm_runtime_register_string(i64, i8*, i64)\n")
            out.write("declare i8* @memcpy(i8*, i8*, i64)\n")
        elif needs_list_alloc:
            out.write("declare i8* @memcpy(i8*, i8*, i64)\n")
        if needs_list_alloc:
            out.write("declare void @oren_llvm_runtime_register_list(i64, i64*, i64)\n")
        if "oren_string_eq" in helpers_to_emit:
            out.write("declare i32 @memcmp(i8*, i8*, i64)\n")
        if "exit" in helpers_to_emit:
            out.write("declare void @exit(i32)\n")
        out.write("\n")
        slots, values, token_table = lower_function(main, out)
        emit_string_globals(out, token_table)
        if needs_string_alloc:
            emit_string_runtime_alloc(out)
        if needs_list_alloc:
            emit_list_runtime_alloc(out)
            emit_list_len_helper(out)
            emit_list_get_helper(out)
            emit_list_push_helper(out)
            emit_list_set_helper(out)
        if "oren_string_slice" in helpers_to_emit:
            emit_string_slice_helper(out)
        if "oren_string_slice_unchecked" in helpers_to_emit:
            emit_string_slice_unchecked_helper(out)
        if "oren_string_concat" in helpers_to_emit:
            emit_string_concat_helper(out)
        if (
            "oren_string_byte_at" in helpers_to_emit
            or "oren_string_byte_at_unchecked" in helpers_to_emit
            or "oren_string_char_code_at" in helpers_to_emit
        ):
            emit_string_byte_at_helpers(out)
        if "oren_string_char_at" in helpers_to_emit or "oren_string_char_at_unchecked" in helpers_to_emit:
            emit_string_char_at_helpers(out)
        if "print" in helpers_to_emit:
            emit_print_helper(out)
        if "exit" in helpers_to_emit:
            emit_exit_helper(out)
        if "oren_string_len" in helpers_to_emit:
            emit_string_len_helper(out)
        if "oren_string_eq" in helpers_to_emit:
            emit_string_eq_helper(out)
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
