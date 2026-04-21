#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

work_dir="build/tmp/oretest_smoke"
bin_dir="${work_dir}/bin"
make_log="${work_dir}/make.log"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$bin_dir"

cat >"${bin_dir}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_path="${ORETEST_SMOKE_LOG:?missing ORETEST_SMOKE_LOG}"
target="${1:-}"
printf 'target=%s\tparse_jobs=%s\tfixture_jobs=%s\n' \
  "$target" "${OREN_PARSE_JOBS:-}" "${NATIVE_TEST_JOBS:-}" >>"$log_path"
EOF
chmod +x "${bin_dir}/make"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_case() {
  local case_name="$1"
  shift
  : >"$make_log"
  PATH="${bin_dir}:$PATH" ORETEST_SMOKE_LOG="$make_log" "$@"
}

assert_targets() {
  local expected="$1"
  local actual
  actual="$(cut -f1 "$make_log" | sed 's/^target=//' | paste -sd',' -)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected targets: $expected" >&2
    echo "Actual targets:   $actual" >&2
    echo "Log:" >&2
    cat "$make_log" >&2
    fail "target sequence mismatch"
  fi
}

assert_line_count() {
  local expected="$1"
  local actual
  actual="$(wc -l <"$make_log" | tr -d ' ')"
  [[ "$actual" == "$expected" ]] || fail "expected $expected make invocations, got $actual"
}

assert_log_has() {
  local pattern="$1"
  rg -n "$pattern" "$make_log" >/dev/null || fail "missing log pattern: $pattern"
}

assert_log_lacks() {
  local pattern="$1"
  if rg -n "$pattern" "$make_log" >/dev/null; then
    echo "Unexpected log pattern: $pattern" >&2
    cat "$make_log" >&2
    fail "unexpected log pattern"
  fi
}

run_case default ./oretest
assert_line_count 1
assert_targets "test-native-quick"

run_case full_cli ./oretest --full
assert_line_count 4
assert_targets "verify-native-quick-gc,verify-backend-parity,test-avm,verify-readiness-pipeline"
assert_log_lacks 'target=test-native-quick-stage2'
assert_log_lacks 'target=test-native-capsule-smoke-stage2'
assert_log_lacks 'target=verify-optimizer-list-reserve-branchy'

run_case full_env env OREN_TEST_FULL=1 ./oretest
assert_line_count 4
assert_targets "verify-native-quick-gc,verify-backend-parity,test-avm,verify-readiness-pipeline"

run_case full_env_overridden env OREN_TEST_FULL=1 ./oretest --quick
assert_line_count 1
assert_targets "test-native-quick"

run_case native_all_jobs ./oretest --native-all --jobs 7 --fixture-jobs 9
assert_line_count 1
assert_targets "test-native-all"
assert_log_has 'target=test-native-all\tparse_jobs=7\tfixture_jobs=9$'

set +e
invalid_output="$(PATH="${bin_dir}:$PATH" ORETEST_SMOKE_LOG="$make_log" ./oretest --jobs nope 2>&1)"
invalid_rc=$?
set -e
[[ "$invalid_rc" == "2" ]] || fail "expected ./oretest --jobs nope to exit 2, got $invalid_rc"
printf '%s\n' "$invalid_output" | rg -n -- '--jobs must be an integer >= 1' >/dev/null || fail "missing invalid --jobs diagnostic"

echo "OK: oretest smoke verified"
