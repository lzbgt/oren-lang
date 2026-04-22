#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

compiler="${1:-./oren_stage2}"
stamp="$(date +%Y%m%d_%H%M%S)"
tmp_dir="build/tmp/generator_import_yield_regression_${stamp}"
log_dir="build/logs"
mkdir -p "$tmp_dir" "$log_dir"

run_success_case() {
  local name="$1"
  local src="$2"
  local log="$log_dir/${name}_${stamp}.log"
  local out="$tmp_dir/${name}.obc"
  local rc=0

  OREN_TRACE_PHASES=1 OREN_TRACE_PASSES=1 timeout 12s \
    "$compiler" build "$src" -o "$out" --backend bytecode >"$log" 2>&1 || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "expected success for ${name}, got rc=${rc}" >&2
    echo "log: $log" >&2
    return 1
  fi
  if [[ ! -f "$out" ]]; then
    echo "missing bytecode output for ${name}: $out" >&2
    return 1
  fi
  if ! rg -q 'Bytecode emitted|Bytecode size' "$log"; then
    echo "success log for ${name} did not contain bytecode emission marker" >&2
    echo "log: $log" >&2
    return 1
  fi
  echo "ok ${name} log=${log}"
}

run_success_case \
  "generator_import_resume_control_no_import_v0" \
  "tests/fixtures/generator_import_resume_control_no_import_v0.oren"
run_success_case \
  "generator_import_yield_control_import_no_yield_v0" \
  "tests/fixtures/generator_import_yield_control_import_no_yield_v0.oren"
run_success_case \
  "generator_import_yield_regression_stmt_v0" \
  "tests/fixtures/generator_import_yield_regression_stmt_v0.oren"
run_success_case \
  "generator_import_resume_regression_v0" \
  "tests/fixtures/generator_import_resume_regression_v0.oren"
run_success_case \
  "generator_import_delegate_regression_v0" \
  "tests/fixtures/generator_import_delegate_regression_v0.oren"
run_success_case \
  "generator_import_delegate_step_regression_v0" \
  "tests/fixtures/generator_import_delegate_step_regression_v0.oren"
run_success_case \
  "generator_import_yield_from_regression_v0" \
  "tests/fixtures/generator_import_yield_from_regression_v0.oren"
run_success_case \
  "generator_import_close_regression_v0" \
  "tests/fixtures/generator_import_close_regression_v0.oren"
run_success_case \
  "generator_import_delegate_close_regression_v0" \
  "tests/fixtures/generator_import_delegate_close_regression_v0.oren"
run_success_case \
  "generator_import_on_close_regression_v0" \
  "tests/fixtures/generator_import_on_close_regression_v0.oren"
run_success_case \
  "generator_import_on_finalize_regression_v0" \
  "tests/fixtures/generator_import_on_finalize_regression_v0.oren"
run_success_case \
  "generator_import_defer_regression_v0" \
  "tests/fixtures/generator_import_defer_regression_v0.oren"

echo "probe logs are under ${log_dir}, outputs under ${tmp_dir}"
