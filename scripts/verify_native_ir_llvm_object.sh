#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="${NATIVE_IR_LLVM_SOURCE:-examples/hello.oren}"
platform="${NATIVE_IR_LLVM_PLATFORM:-x64-linux}"
out_dir="${NATIVE_IR_LLVM_OUT_DIR:-build/native_ir/llvm_object}"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_object_toolchain.log"
dump_log="$log_dir/native_ir_llvm_object_dump.log"
emit_log="$log_dir/native_ir_llvm_object_emit.log"
manifest="$out_dir/manifest.txt"
native_ir_json="$out_dir/input.native_ir.json"
llvm_ir="$out_dir/probe.ll"
object_out="$out_dir/probe.o"

if ! ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1; then
  cat "$toolchain_log"
  exit 1
fi

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

llvm_ready="$(read_report_value llvm_ready)"
llc_path="$(read_report_value llc_path)"

"$compiler" dump native-ir "$src" --platform "$platform" -o "$native_ir_json" >"$dump_log" 2>&1

python3 - "$native_ir_json" "$platform" "$llvm_ir" >"$emit_log" <<'PY'
import json
import os
import re
import sys

path = sys.argv[1]
platform = sys.argv[2]
llvm_ir_path = sys.argv[3]
with open(path, "r", encoding="utf-8") as fh:
    ir = json.load(fh)

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

target = ir["target"]
arch = target["arch"]
os_name = target["os"]
if arch == "x64" and os_name == "windows":
    triple = "x86_64-pc-windows-msvc"
elif arch == "x64" and os_name == "linux":
    triple = "x86_64-unknown-linux-gnu"
elif arch == "arm64" and os_name == "macos":
    triple = "arm64-apple-macosx"
elif arch == "arm64" and os_name == "linux":
    triple = "aarch64-unknown-linux-gnu"
else:
    raise SystemExit(f"unsupported native IR LLVM probe target: {target}")

schema = ir["schema"].encode("utf-8")
schema_literal = "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else f"\\{b:02X}" for b in schema)
schema_len = len(schema) + 1

def llvm_name(prefix, raw, seq):
    safe = re.sub(r"[^A-Za-z0-9_.$-]", "_", raw or "")
    if not safe or not re.match(r"[A-Za-z_$.-]", safe[0]):
        safe = f"{prefix}{seq}"
    return safe.replace(".", "_").replace("-", "_")

def token_id(table, token):
    if token not in table:
        table[token] = len(table) + 1
    return table[token]

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

def lower_function(fn, out):
    value_vars = {}
    token_table = {}
    slots = collect_slots(fn)
    slot_vars = {name: f"%slot{idx}" for idx, name in enumerate(slots)}

    def result_var(value):
        if value not in value_vars:
            value_vars[value] = f"%v{len(value_vars)}"
        return value_vars[value]

    def value_ref(value):
        assert value is None or isinstance(value, str), value
        if value is None:
            return "0"
        if value in value_vars:
            return value_vars[value]
        if value in slot_vars:
            tmp = f"%v{len(value_vars)}"
            value_vars[value] = tmp
            out.write(f"  {tmp} = load i64, i64* {slot_vars[value]}, align 8\n")
            return tmp
        raise AssertionError(f"native IR value referenced before definition: {value}")

    label_names = {block["label"]: llvm_name("bb", block["label"], idx) for idx, block in enumerate(fn["blocks"])}
    out.write("define i64 @oren_native_ir_main_probe() nounwind {\n")
    for bidx, block in enumerate(fn["blocks"]):
        out.write(f"{label_names[block['label']]}:\n")
        if bidx == 0:
            for name in slots:
                out.write(f"  {slot_vars[name]} = alloca i64, align 8 ; local {name}\n")
                out.write(f"  store i64 0, i64* {slot_vars[name]}, align 8\n")
        for op in block["ops"]:
            kind = op["kind"]
            if kind == "const":
                out.write(f"  {result_var(op['result'])} = add i64 0, {const_i64(op, token_table)} ; const {op['value_kind']}\n")
            elif kind == "local_get":
                src = op["name"]
                assert src in slot_vars, (fn["name"], op, slots)
                out.write(f"  {result_var(op['result'])} = load i64, i64* {slot_vars[src]}, align 8\n")
            elif kind == "local_set":
                out.write(f"  store i64 {value_ref(op['value'])}, i64* {slot_vars[op['name']]}, align 8\n")
            elif kind == "binary":
                dst = result_var(op["result"])
                left = value_ref(op["left"])
                right = value_ref(op["right"])
                bop = op["op"]
                if bop == "+":
                    out.write(f"  {dst} = add i64 {left}, {right}\n")
                elif bop == "-":
                    out.write(f"  {dst} = sub i64 {left}, {right}\n")
                elif bop == "*":
                    out.write(f"  {dst} = mul i64 {left}, {right}\n")
                elif bop in ("==", "!=", "<", "<=", ">", ">="):
                    pred = {"==": "eq", "!=": "ne", "<": "slt", "<=": "sle", ">": "sgt", ">=": "sge"}[bop]
                    cmpv = f"%cmp{len(value_vars)}"
                    out.write(f"  {cmpv} = icmp {pred} i64 {left}, {right}\n")
                    out.write(f"  {dst} = zext i1 {cmpv} to i64\n")
                else:
                    out.write(f"  {dst} = call i64 @oren_llvm_opaque_binary(i64 {token_id(token_table, 'binary:' + bop)}, i64 {left}, i64 {right})\n")
            elif kind == "unary":
                dst = result_var(op["result"])
                val = value_ref(op["value"])
                if op["op"] == "-":
                    out.write(f"  {dst} = sub i64 0, {val}\n")
                elif op["op"] == "!":
                    cmpv = f"%cmp{len(value_vars)}"
                    out.write(f"  {cmpv} = icmp eq i64 {val}, 0\n")
                    out.write(f"  {dst} = zext i1 {cmpv} to i64\n")
                else:
                    out.write(f"  {dst} = call i64 @oren_llvm_opaque_unary(i64 {token_id(token_table, 'unary:' + op['op'])}, i64 {val})\n")
            elif kind == "call":
                for arg in op["args"]:
                    value_ref(arg)
                out.write(f"  {result_var(op['result'])} = call i64 @oren_llvm_opaque_call(i64 {token_id(token_table, 'call:' + op['callee'])}, i64 {len(op['args'])})\n")
            elif kind == "runtime_helper_call":
                for arg in op["args"]:
                    value_ref(arg)
                out.write(f"  {result_var(op['result'])} = call i64 @oren_llvm_runtime_helper(i64 {token_id(token_table, 'helper:' + op['name'])}, i64 {len(op['args'])}) ; helper {op['name']} safepoint={op['safepoint']} call_depth={op['call_depth']}\n")
            elif kind == "array":
                for elem in op["elements"]:
                    value_ref(elem)
                out.write(f"  {result_var(op['result'])} = call i64 @oren_llvm_opaque_array(i64 {len(op['elements'])})\n")
            elif kind == "index_get":
                out.write(f"  {result_var(op['result'])} = call i64 @oren_llvm_opaque_index_get(i64 {value_ref(op['container'])}, i64 {value_ref(op['index'])})\n")
            elif kind == "index_set":
                out.write(f"  call void @oren_llvm_opaque_index_set(i64 {value_ref(op['container'])}, i64 {value_ref(op['index'])}, i64 {value_ref(op['value'])})\n")
            elif kind == "expr_result":
                value_ref(op["value"])
            elif kind == "opaque_stmt":
                out.write(f"  call void @oren_llvm_opaque_stmt(i64 {token_id(token_table, 'stmt:' + op['stmt_type'])})\n")
            elif kind == "opaque_expr":
                out.write(f"  {result_var(op['result'])} = call i64 @oren_llvm_opaque_expr(i64 {token_id(token_table, 'expr:' + op['expr_type'])})\n")
            else:
                raise AssertionError((fn["name"], block["label"], op))
        term = block["terminator"]
        if term["kind"] == "return":
            out.write(f"  ret i64 {value_ref(term.get('value'))}\n")
        elif term["kind"] == "jump":
            out.write(f"  br label %{label_names[term['target']]}\n")
        elif term["kind"] == "branch":
            cond = value_ref(term["cond"])
            cmpv = f"%brcond{bidx}"
            out.write(f"  {cmpv} = icmp ne i64 {cond}, 0\n")
            out.write(f"  br i1 {cmpv}, label %{label_names[term['true']]}, label %{label_names[term['false']]}\n")
        elif term["kind"] == "panic":
            out.write("  unreachable\n")
        elif term["kind"] == "unreachable":
            out.write("  unreachable\n")
        else:
            raise AssertionError((fn["name"], block["label"], term))
    out.write("}\n")
    return len(slots), len(value_vars)

with open(llvm_ir_path, "w", encoding="utf-8") as out:
    out.write("; native_ir_llvm_lowered_subset_v0\n")
    out.write(f"source_filename = \"{path}\"\n")
    out.write(f"target triple = \"{triple}\"\n\n")
    out.write(f"@oren_native_ir_schema = private unnamed_addr constant [{schema_len} x i8] c\"{schema_literal}\\00\", align 1\n\n")
    out.write("declare i64 @oren_llvm_opaque_call(i64, i64)\n")
    out.write("declare i64 @oren_llvm_opaque_binary(i64, i64, i64)\n")
    out.write("declare i64 @oren_llvm_opaque_unary(i64, i64)\n")
    out.write("declare i64 @oren_llvm_opaque_array(i64)\n")
    out.write("declare i64 @oren_llvm_opaque_index_get(i64, i64)\n")
    out.write("declare void @oren_llvm_opaque_index_set(i64, i64, i64)\n")
    out.write("declare void @oren_llvm_opaque_stmt(i64)\n")
    out.write("declare i64 @oren_llvm_opaque_expr(i64)\n")
    out.write("declare i64 @oren_llvm_runtime_helper(i64, i64)\n\n")
    slots, values = lower_function(main, out)

if os.environ.get("NATIVE_IR_LLVM_REQUIRE_HELPERS", "1") == "1":
    assert helper_ops, main
print(f"native_ir_validated=1 platform={platform} functions={len(ir['functions'])} main_helpers={len(helper_ops)} types={len(type_map)}")
print(f"llvm_ir_lowered=1 path={llvm_ir_path} main_blocks={len(main['blocks'])} main_slots={slots} main_values={values}")
PY

test -s "$llvm_ir"
grep -Fq "native_ir_llvm_lowered_subset_v0" "$llvm_ir"
grep -Fq "define i64 @oren_native_ir_main_probe()" "$llvm_ir"
if [ "${NATIVE_IR_LLVM_REQUIRE_BRANCH:-1}" = "1" ]; then
  grep -Fq "br i1" "$llvm_ir"
fi
if [ "${NATIVE_IR_LLVM_REQUIRE_HELPERS:-1}" = "1" ]; then
  grep -Fq "; helper " "$llvm_ir"
fi

{
  printf 'native_ir_llvm_object_v0\n'
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'platform=%s\n' "$platform"
  printf 'native_ir=%s\n' "$native_ir_json"
  printf 'llvm_ir=%s\n' "$llvm_ir"
  printf 'type_layout=tagged:64:8,void:0:1\n'
  printf 'toolchain_report=%s\n' "$toolchain_report"
  printf 'llvm_ready=%s\n' "$llvm_ready"
} >"$manifest"

if [ "$llvm_ready" != "1" ]; then
  {
    printf 'status=skipped\n'
    printf 'reason=missing_full_llvm_toolchain\n'
    printf 'object=%s\n' "$object_out"
  } >>"$manifest"
  cat "$toolchain_log"
  cat "$emit_log"
  echo "SKIP: native IR LLVM object probe requires clang, llvm-config, and llc; see $manifest"
  exit 0
fi

"$llc_path" -filetype=obj "$llvm_ir" -o "$object_out" >>"$emit_log" 2>&1
test -s "$object_out"

{
  printf 'status=emitted\n'
  printf 'llvm_ir=%s\n' "$llvm_ir"
  printf 'object=%s\n' "$object_out"
  printf 'llc_path=%s\n' "$llc_path"
} >>"$manifest"

cat "$toolchain_log"
cat "$emit_log"
echo "OK: native IR LLVM object probe emitted $object_out"
