#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
src="tests/fixtures/native_ir_llvm_list_main.oren"
out_dir="build/native_ir/llvm_list_runtime"
log_dir="build/logs"
toolchain_dir="${NATIVE_IR_TOOLCHAIN_OUT_DIR:-build/native_ir}"
toolchain_report="$toolchain_dir/toolchain.txt"

mkdir -p "$out_dir" "$log_dir"

toolchain_log="$log_dir/native_ir_llvm_list_runtime_toolchain.log"
native_log="$log_dir/native_ir_llvm_list_runtime_native.log"
llvm_build_log="$log_dir/native_ir_llvm_list_runtime_build.log"
link_log="$log_dir/native_ir_llvm_list_runtime_link.log"
llvm_run_log="$log_dir/native_ir_llvm_list_runtime_run.log"
summary="$out_dir/summary.txt"
harness="$out_dir/list_harness.c"
object="$out_dir/list_arm64_macos.o"
native_bin="$out_dir/native_oracle"
llvm_bin="$out_dir/llvm_list_probe"

start="$(date +%s)"

NATIVE_IR_REQUIRE_LLVM=1 ./scripts/verify_native_ir_toolchain.sh >"$toolchain_log" 2>&1

read_report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, length(k) + 2); exit }' "$toolchain_report"
}

clang_path="$(read_report_value clang_path)"
if [ -z "$clang_path" ] || [ "$clang_path" = "missing" ]; then
  cat "$toolchain_log"
  echo "ERROR: clang is required for native IR LLVM list runtime linking" >&2
  exit 1
fi

"$compiler" build "$src" --backend native --platform arm64-macos --no-cache -o "$native_bin" >"$native_log" 2>&1
"$native_bin" >>"$native_log" 2>&1

"$compiler" build "$src" --backend llvm-native --platform arm64-macos --no-cache -o "$object" >"$llvm_build_log" 2>&1
test -s "$object"
test -s "$object.ll"
grep -Fq "%oren_llvm_list = type { i64, i64*, i64, i64 }" "$object.ll"
grep -Fq "define i64 @oren_llvm_runtime_alloc_list" "$object.ll"
grep -Fq "define i64 @oren_llvm_runtime_alloc_list_with_capacity" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_list_len" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_list_get" "$object.ll"
grep -Fq "define i64 @oren_llvm_helper_oren_list_push" "$object.ll"
grep -Fq "define void @oren_llvm_helper_oren_list_set" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_roots_push_list(i64)" "$object.ll"
grep -Fq "declare void @oren_llvm_runtime_register_list(i64, i64*, i64)" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_register_list" "$object.ll"
grep -Fq "call void @oren_llvm_runtime_roots_push_list" "$object.ll"
grep -Fq "store i64 1, i64* %ownerp, align 8" "$object.ll"
grep -Fq "store i64 %cap, i64* %capp, align 8" "$object.ll"
grep -Fq "call i64 @oren_llvm_runtime_alloc_list_with_capacity(i64 0" "$object.ll"
grep -Fq "call i64 @oren_llvm_helper_oren_list_len" "$object.ll"
grep -Fq "call i64 @oren_llvm_helper_oren_list_push" "$object.ll"
list_get_count="$(grep -F "call i64 @oren_llvm_helper_oren_list_get" "$object.ll" | wc -l | tr -d ' ')"
if [ "$list_get_count" -lt 6 ]; then
  echo "ERROR: expected descriptor-backed list get calls" >&2
  exit 1
fi
concat_count="$(grep -F "call i64 @oren_llvm_helper_oren_string_concat" "$object.ll" | wc -l | tr -d ' ')"
if [ "$concat_count" -lt 3 ]; then
  echo "ERROR: expected nested list element descriptor concat" >&2
  exit 1
fi
grep -Fq "call void @oren_llvm_helper_oren_list_set" "$object.ll"
if grep -Fq "call i64 @oren_llvm_opaque_array" "$object.ll" ||
   grep -Fq "call i64 @oren_llvm_opaque_index_get" "$object.ll" ||
   grep -Fq "call void @oren_llvm_opaque_index_set" "$object.ll"; then
  echo "ERROR: list runtime IR fell back to opaque array/index calls" >&2
  exit 1
fi
if grep -Fq "@oren_llvm_helper_oren_list_int_push" "$object.ll" ||
   grep -Fq "@oren_llvm_helper_oren_list_int_len" "$object.ll" ||
   grep -Fq "@oren_llvm_helper_oren_list_int_get" "$object.ll"; then
  echo "ERROR: descriptor-backed list-int helpers were not normalized to list descriptor helpers" >&2
  exit 1
fi

cat >"$harness" <<'C'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct OrenLlvmString {
    int64_t len;
    char* data;
    int64_t owner_kind;
} OrenLlvmString;

typedef struct OrenLlvmList {
    int64_t len;
    int64_t* data;
    int64_t owner_kind;
    int64_t capacity;
} OrenLlvmList;

extern int64_t oren_native_ir_main_probe(void);
extern void* oren_llvm_runtime_alloc_bytes(int64_t byte_count, int64_t alloc_kind);
extern void oren_llvm_runtime_register_string(int64_t desc_handle, char* data, int64_t len);
extern void oren_llvm_runtime_register_list(int64_t desc_handle, int64_t* data, int64_t len);
extern int64_t oren_llvm_runtime_roots_mark(void);
extern void oren_llvm_runtime_roots_push_list(int64_t desc_handle);
extern void oren_llvm_runtime_roots_reset(int64_t mark);
extern void oren_llvm_runtime_safepoint_poll(void);
extern int64_t oren_llvm_runtime_is_live_string(int64_t desc_handle);
extern int64_t oren_llvm_runtime_is_live_list(int64_t desc_handle);
extern int64_t oren_llvm_runtime_registered_strings(void);
extern int64_t oren_llvm_runtime_registered_lists(void);
extern int64_t oren_llvm_runtime_root_depth(void);
extern int64_t oren_llvm_runtime_root_pushes(void);
extern int64_t oren_llvm_runtime_safepoint_collections(void);

static OrenLlvmString* make_string(const char* text) {
    int64_t len = (int64_t)strlen(text);
    char* data = (char*)oren_llvm_runtime_alloc_bytes(len + 1, 1);
    memcpy(data, text, (size_t)len + 1u);
    OrenLlvmString* desc = (OrenLlvmString*)oren_llvm_runtime_alloc_bytes(24, 2);
    desc->len = len;
    desc->data = data;
    desc->owner_kind = 1;
    oren_llvm_runtime_register_string((int64_t)(uintptr_t)desc, data, len);
    return desc;
}

static OrenLlvmList* make_list1(int64_t item) {
    int64_t* data = (int64_t*)oren_llvm_runtime_alloc_bytes(8, 3);
    data[0] = item;
    OrenLlvmList* desc = (OrenLlvmList*)oren_llvm_runtime_alloc_bytes(32, 4);
    desc->len = 1;
    desc->data = data;
    desc->owner_kind = 1;
    desc->capacity = 1;
    oren_llvm_runtime_register_list((int64_t)(uintptr_t)desc, data, 1);
    return desc;
}

int main(void) {
    int64_t rc = oren_native_ir_main_probe();
    if (rc != 0) {
        fprintf(stderr, "oren_native_ir_main_probe returned %lld\n", (long long)rc);
        return 1;
    }
    if (oren_llvm_runtime_registered_lists() < 1) {
        fprintf(stderr, "expected at least one registered LLVM list descriptor\n");
        return 1;
    }
    if (oren_llvm_runtime_registered_strings() < 1) {
        fprintf(stderr, "expected at least one registered LLVM string descriptor\n");
        return 1;
    }
    if (oren_llvm_runtime_root_pushes() < 1) {
        fprintf(stderr, "expected LLVM descriptor roots across helper safepoint\n");
        return 1;
    }
    if (oren_llvm_runtime_safepoint_collections() < 1) {
        fprintf(stderr, "expected forced LLVM helper safepoint collection\n");
        return 1;
    }
    if (oren_llvm_runtime_root_depth() != 0) {
        fprintf(stderr, "expected LLVM descriptor roots to reset after helper calls\n");
        return 1;
    }
    OrenLlvmString* nested_string = make_string("nested");
    OrenLlvmList* child = make_list1((int64_t)(uintptr_t)nested_string);
    OrenLlvmList* parent = make_list1((int64_t)(uintptr_t)child);
    int64_t mark = oren_llvm_runtime_roots_mark();
    oren_llvm_runtime_roots_push_list((int64_t)(uintptr_t)parent);
    oren_llvm_runtime_safepoint_poll();
    oren_llvm_runtime_roots_reset(mark);
    if (!oren_llvm_runtime_is_live_list((int64_t)(uintptr_t)parent) ||
        !oren_llvm_runtime_is_live_list((int64_t)(uintptr_t)child) ||
        !oren_llvm_runtime_is_live_string((int64_t)(uintptr_t)nested_string)) {
        fprintf(stderr, "expected parent list root to retain nested list/string descriptors\n");
        return 1;
    }
    if (oren_llvm_runtime_root_depth() != 0) {
        fprintf(stderr, "expected LLVM descriptor roots to reset after nested root proof\n");
        return 1;
    }
    return 0;
}
C

"$clang_path" "$harness" "$object" lib/runtime.c lib/runtime_buf.c -Ilib -pthread -o "$llvm_bin" >"$link_log" 2>&1
OREN_LLVM_FORCE_GC_AT_SAFEPOINT=1 "$llvm_bin" >"$llvm_run_log" 2>&1

end="$(date +%s)"
{
  printf 'native_ir_llvm_list_runtime_v0\n'
  printf 'duration_sec=%s\n' "$((end - start))"
  printf 'compiler=%s\n' "$compiler"
  printf 'source=%s\n' "$src"
  printf 'native_oracle=%s\n' "$native_bin"
  printf 'llvm_object=%s\n' "$object"
  printf 'llvm_executable=%s\n' "$llvm_bin"
  printf 'coverage=host-arm64-macos,native-oracle,llvm-link,llvm-execute,real-c-runtime-hooks,llvm-list-descriptor-layout,array-literal-allocation,list-index-get-helper,list-index-set-helper,list-push-growth-helper,list-len-helper,list-local-descriptor-propagation,nested-list-index-provenance,descriptor-root-kind-routing,list-runtime-registration,list-safepoint-roots,forced-gc-at-list-safepoint,nested-list-descriptor-roots\n'
} >"$summary"

echo "OK: native IR LLVM list runtime parity passed; summary: $summary"
