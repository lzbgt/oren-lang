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

python3 - "$native_ir_json" "$platform" >"$emit_log" <<'PY'
import json
import sys

path = sys.argv[1]
platform = sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    ir = json.load(fh)

assert ir["schema"] == "native_ir_v0", ir.get("schema")
assert ir["validation"]["ok"] is True, ir["validation"]
assert ir["validation"]["errors"] == [], ir["validation"]
assert len(ir["functions"]) > 0, ir
main = next((fn for fn in ir["functions"] if fn["name"] == "main"), None)
assert main is not None, [fn["name"] for fn in ir["functions"][:20]]
helper_ops = [op for block in main["blocks"] for op in block["ops"] if op["kind"] == "runtime_helper_call"]
print(f"native_ir_validated=1 platform={platform} functions={len(ir['functions'])} main_helpers={len(helper_ops)}")
PY

{
  printf 'native_ir_llvm_object_v0\n'
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'platform=%s\n' "$platform"
  printf 'native_ir=%s\n' "$native_ir_json"
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

python3 - "$native_ir_json" "$llvm_ir" <<'PY'
import json
import sys

src_path = sys.argv[1]
out_path = sys.argv[2]
with open(src_path, "r", encoding="utf-8") as fh:
    ir = json.load(fh)

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

with open(out_path, "w", encoding="utf-8") as out:
    out.write("; native_ir_llvm_object_probe_v0\n")
    out.write(f"source_filename = \"{src_path}\"\n")
    out.write(f"target triple = \"{triple}\"\n\n")
    out.write(f"@oren_native_ir_schema = private unnamed_addr constant [{schema_len} x i8] c\"{schema_literal}\\00\", align 1\n\n")
    out.write("define i64 @oren_native_ir_object_probe() nounwind {\n")
    out.write("entry:\n")
    out.write("  ret i64 0\n")
    out.write("}\n")
PY

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
