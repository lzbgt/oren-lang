#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
log_dir="${NATIVE_IR_LLVM_WORKFLOW_LOG_DIR:-build/logs/native_ir_llvm_workflow}"
summary="$log_dir/summary.txt"

mkdir -p "$log_dir"
: >"$summary"

run_gate() {
  local name="$1"
  shift
  local log="$log_dir/$name.log"
  local start end elapsed
  start="$(date +%s)"
  {
    printf 'gate=%s\n' "$name"
    printf 'cmd='
    printf '%q ' "$@"
    printf '\n'
  } >>"$summary"
  "$@" >"$log" 2>&1
  end="$(date +%s)"
  elapsed=$((end - start))
  printf 'duration_sec[%s]=%s\n' "$name" "$elapsed" >>"$summary"
  printf 'OK: %s (%ss)\n' "$name" "$elapsed"
}

# This workflow intentionally omits a final `make test`: the default `test`
# target is `test-native-quick`, which is already run below.
run_gate docs-site make docs-site
run_gate verify-docs-site make verify-docs-site
run_gate verify-source-line-guard make verify-source-line-guard
run_gate diff-check git diff --check
run_gate stage2 make stage2
run_gate native-ir-toolchain make verify-native-ir-toolchain
run_gate native-ir-validator make verify-native-ir-validator
run_gate native-ir-dump make verify-native-ir-dump
run_gate native-ir-parity make verify-native-ir-parity
run_gate native-ir-llvm-object env NATIVE_IR_REQUIRE_LLVM=1 make verify-native-ir-llvm-object
run_gate native-ir-llvm-lowering make verify-native-ir-llvm-lowering
run_gate native-ir-llvm-backend make verify-native-ir-llvm-backend
run_gate test-native-quick make test-native-quick
run_gate verify-native-x64-compile make verify-native-x64-compile
run_gate test-avm make test-avm
run_gate verify-libavm-ios make verify-libavm-ios

{
  printf 'skipped_make_test_after_test_native_quick=1\n'
  printf 'reason=make test is currently an alias for test-native-quick\n'
  printf 'compiler=%s\n' "$compiler"
} >>"$summary"

echo "OK: native IR LLVM workflow verification passed; summary: $summary"
