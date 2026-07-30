#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
mkdir -p build/logs build/tmp/native_ir_llvm_lowering

log="build/logs/native_ir_llvm_lowering.log"

{
  echo "compiler=$compiler"
  echo "fixtures=hello,int_arith,direct_call,string_concat,list_ops,panic_div0,runtime_print"
  echo "platforms=x64-linux,x64-windows,arm64-macos"
} >"$log"

python3 - "$compiler" "$log" <<'PY'
import os
import re
import subprocess
import sys

compiler = sys.argv[1]
log_path = sys.argv[2]

fixtures = [
    ("hello", "examples/hello.oren", True, True),
    ("int_arith", "tests/fixtures/x64_div_mod_main.oren", False, False),
    ("direct_call", "tests/fixtures/x64_nested_call_args_main.oren", False, False),
    ("string_concat", "tests/fixtures/tier1_native_string_ops_main.oren", False, False),
    ("list_ops", "tests/fixtures/x64_list_ops_main.oren", True, False),
    ("panic_div0", "tests/fixtures/x64_div0_main.oren", False, False),
    ("runtime_print", "tests/fixtures/x64_print_main.oren", True, False),
]

platforms = [
    ("x64-linux", 'target triple = "x86_64-unknown-linux-gnu"'),
    ("x64-windows", 'target triple = "x86_64-pc-windows-msvc"'),
    ("arm64-macos", 'target triple = "arm64-apple-macosx"'),
]

out_root = "build/tmp/native_ir_llvm_lowering"


def safe(s):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", s)


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


with open(log_path, "a", encoding="utf-8") as log:
    checked = 0
    for label, src, expect_helper, expect_branch in fixtures:
        for platform, triple_line in platforms:
            stem = safe(label + "_" + platform)
            out_dir = os.path.join(out_root, stem)
            env = os.environ.copy()
            env["NATIVE_IR_LLVM_SOURCE"] = src
            env["NATIVE_IR_LLVM_PLATFORM"] = platform
            env["NATIVE_IR_LLVM_OUT_DIR"] = out_dir
            env["NATIVE_IR_LLVM_REQUIRE_HELPERS"] = "1" if expect_helper else "0"
            env["NATIVE_IR_LLVM_REQUIRE_BRANCH"] = "1" if expect_branch else "0"
            cmd = ["./scripts/verify_native_ir_llvm_object.sh", compiler]
            log.write(f"\n== {label} {platform} ==\n")
            log.write("$ " + " ".join(cmd) + "\n")
            subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, check=True)

            llvm_ir = os.path.join(out_dir, "probe.ll")
            manifest = os.path.join(out_dir, "manifest.txt")
            ll = read(llvm_ir)
            mf = read(manifest)

            assert "; native_ir_llvm_lowered_subset_v0" in ll, (label, platform, llvm_ir)
            assert triple_line in ll, (label, platform, triple_line, ll[:200])
            assert "define i64 @oren_native_ir_main_probe() nounwind" in ll, (label, platform, llvm_ir)
            assert "ret i64" in ll or "unreachable" in ll, (label, platform, llvm_ir)
            assert "llvm_ir=" + llvm_ir in mf, (label, platform, manifest, mf)
            assert "type_layout=tagged:64:8,void:0:1" in mf, (label, platform, mf)
            if expect_branch:
                assert "br i1" in ll, (label, platform, "missing branch")
            if expect_helper:
                assert "@oren_llvm_runtime_helper" in ll and "; helper " in ll, (label, platform, "missing helper marker")
            log.write(f"OK: {label} {platform} llvm_ir={llvm_ir}\n")
            checked += 1

print(f"OK: native IR LLVM textual lowering parity passed ({checked} cases)")
PY
