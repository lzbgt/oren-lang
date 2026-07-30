#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="tests/fixtures/native_ir_llvm_map_main.oren"
out_dir="build/native_ir/llvm_map_runtime"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_map_runtime_toolchain.log"
native_log="$log_dir/native_ir_llvm_map_runtime_native.log"
llvm_build_log="$log_dir/native_ir_llvm_map_runtime_build.log"
link_log="$log_dir/native_ir_llvm_map_runtime_link.log"
llvm_run_log="$log_dir/native_ir_llvm_map_runtime_run.log"
summary="$out_dir/summary.txt"
harness="$out_dir/map_harness.c"
object="$out_dir/map_arm64_macos.o"
native_bin="$out_dir/native_oracle"
llvm_bin="$out_dir/llvm_map_probe"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

clang_path="$(read_report_value clang_path)"
if [ -z "$clang_path" ] || [ "$clang_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: clang is required for native IR LLVM map runtime linking" >&2
  exit 1
fi

"$compiler" build "$src" --backend native --platform arm64-macos --no-cache -o "$native_bin" >"$native_log" 2>&1
"$native_bin" >>"$native_log" 2>&1

"$compiler" build "$src" --backend llvm-native --platform arm64-macos --no-cache -o "$object" >"$llvm_build_log" 2>&1
test -s "$object"
test -s "$object.native_ir.json"
test -s "$object.ll"
python3 - "$object.native_ir.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    ir = json.load(f)

main = next((fn for fn in ir.get("functions", []) if fn.get("name") == "main"), None)
if main is None:
    raise SystemExit("missing main in native IR")

found_literal_pairs = False
for block in main.get("blocks", []):
    ops = block.get("ops", [])
    for i, op in enumerate(ops):
        if op.get("kind") != "opaque_expr" or op.get("expr_type") != "Hash":
            continue
        result = op.get("result")
        writes = 0
        for next_op in ops[i + 1:]:
            if next_op.get("kind") == "opaque_expr" and next_op.get("expr_type") == "Hash":
                break
            if next_op.get("kind") == "index_set" and next_op.get("container") == result:
                writes += 1
            if next_op.get("kind") == "local_set" and next_op.get("value") == result:
                break
        if writes >= 2:
            found_literal_pairs = True
            break
    if found_literal_pairs:
        break

if not found_literal_pairs:
    raise SystemExit("expected non-empty Hash literal pairs to lower into index_set ops")
PY
grep -Fq "%oren_llvm_map = type { i64, i64*, i64*, i64*, i64, i64 }" "$object.ll"
grep -Fq "define i64 @oren_llvm_runtime_alloc_map" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_map_find" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_map_find_string" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_map_len" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_map_get" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_map_get_string" "$object.ll"
grep -Fq "define void @oren_llvm_helper_oren_map_store_new" "$object.ll"
grep -Fq "define void @oren_llvm_helper_oren_map_set" "$object.ll"
grep -Fq "define void @oren_llvm_helper_oren_map_set_string" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_register_map(i64, i64*, i64*, i64*, i64, i64)" "$object.ll"
grep -Fq "declare i32 @memcmp(i8*, i8*, i64)" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_roots_push_map(i64)" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_register_map" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_roots_push_map" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_roots_push_list" "$object.ll"
grep -Fq "call i64 @oren_llvm_helper_oren_map_len" "$object.ll"
grep -Fq "call i64 @oren_llvm_helper_oren_map_get" "$object.ll"
grep -Fq "call void @oren_llvm_helper_oren_map_set" "$object.ll"
grep -Fq "call i64 @oren_llvm_helper_oren_list_get" "$object.ll"
if grep -Fq "call i64 @oren_llvm_opaque_expr" "$object.ll" ||
   grep -Fq "call i64 @oren_llvm_opaque_index_get" "$object.ll" ||
   grep -Fq "call void @oren_llvm_opaque_index_set" "$object.ll" ||
   grep -Fq "declare i64 @oren_llvm_helper_oren_map_len(i64, i64, i64, i64, i64)" "$object.ll"; then
  echo "ERROR: map runtime IR fell back to opaque or generic map calls" >&2
  exit 1
fi

cat >"$harness" <<'C'
#include <stdint.h>
#include <stdio.h>

extern int64_t oren_native_ir_main_probe(void);
extern int64_t oren_llvm_runtime_registered_maps(void);
extern int64_t oren_llvm_runtime_root_depth(void);
extern int64_t oren_llvm_runtime_root_pushes(void);
extern int64_t oren_llvm_runtime_safepoint_collections(void);

int main(void) {
    int64_t rc = oren_native_ir_main_probe();
    if (rc != 0) {
        fprintf(stderr, "oren_native_ir_main_probe returned %lld\n", (long long)rc);
        return 1;
    }
    if (oren_llvm_runtime_registered_maps() < 1) {
        fprintf(stderr, "expected registered LLVM map descriptors\n");
        return 1;
    }
    if (oren_llvm_runtime_root_pushes() < 1) {
        fprintf(stderr, "expected LLVM map roots across helper safepoints\n");
        return 1;
    }
    if (oren_llvm_runtime_safepoint_collections() < 1) {
        fprintf(stderr, "expected forced LLVM map safepoint collection\n");
        return 1;
    }
    if (oren_llvm_runtime_root_depth() != 0) {
        fprintf(stderr, "expected LLVM descriptor roots to reset after map helper calls\n");
        return 1;
    }
    return 0;
}
C

"$clang_path" "$harness" "$object" lib/runtime.c lib/runtime_buf.c -Ilib -pthread -o "$llvm_bin" >"$link_log" 2>&1
OREN_LLVM_FORCE_GC_AT_SAFEPOINT=1 "$llvm_bin" >"$llvm_run_log" 2>&1

end="$(date +%s)"
{
  printf 'native_ir_llvm_map_runtime_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'native_oracle=%s\n' "$native_bin"
  printf 'llvm_object=%s\n' "$object"
  printf 'llvm_executable=%s\n' "$llvm_bin"
  printf 'coverage=host-arm64-macos,native-oracle,llvm-link,llvm-execute,real-c-runtime-hooks,llvm-map-descriptor-layout,empty-hash-allocation,non-empty-hash-literal-lowering,hash-literal-index-set-ir,map-key-kind-sidecar,map-string-key-semantic-find,map-string-key-set-helper,map-string-key-get-helper,map-len-helper,map-runtime-registration,map-safepoint-roots,nested-list-map-provenance,nested-map-value-provenance,forced-gc-at-map-safepoint\n'
} >"$summary"

echo "OK: native IR LLVM map runtime parity passed; summary: $summary"
