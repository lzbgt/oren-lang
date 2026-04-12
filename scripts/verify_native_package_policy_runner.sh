#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="build/logs"
ts="$(date +%Y%m%d_%H%M%S)"
TMP="build/tmp/verify-native-package-policy-runner-${ts}"
mkdir -p "$TMP" "$LOG_DIR"
trap 'rm -rf "$TMP"; find build/tmp -maxdepth 1 -name "native_package_policy_*" -exec rm -rf {} +' EXIT

ok_out="$TMP/ok.out"
ok_err="$TMP/ok.err"
ok_json="$TMP/ok.run.json"
deny_out="$TMP/deny.out"
deny_err="$TMP/deny.err"
gas_ok_out="$TMP/gas-ok.out"
gas_ok_err="$TMP/gas-ok.err"
gas_ok_json="$TMP/gas-ok.run.json"
gas_env_override_ok_out="$TMP/gas-env-override-ok.out"
gas_env_override_ok_err="$TMP/gas-env-override-ok.err"
gas_env_override_ok_json="$TMP/gas-env-override-ok.run.json"
gas_sidecar_ok_out="$TMP/gas-sidecar-ok.out"
gas_sidecar_ok_err="$TMP/gas-sidecar-ok.err"
gas_sidecar_ok_json="$TMP/gas-sidecar-ok.run.json"
gas_auto_ok_out="$TMP/gas-auto-ok.out"
gas_auto_ok_err="$TMP/gas-auto-ok.err"
gas_auto_ok_json="$TMP/gas-auto-ok.run.json"
gas_dispatch_default_ok_out="$TMP/gas-dispatch-default-ok.out"
gas_dispatch_default_ok_err="$TMP/gas-dispatch-default-ok.err"
gas_dispatch_default_ok_json="$TMP/gas-dispatch-default-ok.run.json"
gas_fail_out="$TMP/gas-fail.out"
gas_fail_err="$TMP/gas-fail.err"
gas_fail_json="$TMP/gas-fail.run.json"
gas_sidecar_fail_out="$TMP/gas-sidecar-fail.out"
gas_sidecar_fail_err="$TMP/gas-sidecar-fail.err"
gas_sidecar_fail_json="$TMP/gas-sidecar-fail.run.json"
gas_sidecar_uncertified_out="$TMP/gas-sidecar-uncertified.out"
gas_sidecar_uncertified_err="$TMP/gas-sidecar-uncertified.err"
gas_sidecar_uncertified_json="$TMP/gas-sidecar-uncertified.run.json"
gas_sidecar_stderr_warning_out="$TMP/gas-sidecar-stderr-warning.out"
gas_sidecar_stderr_warning_err="$TMP/gas-sidecar-stderr-warning.err"
gas_sidecar_stderr_warning_json="$TMP/gas-sidecar-stderr-warning.run.json"
gas_sidecar_exit_mismatch_out="$TMP/gas-sidecar-exit-mismatch.out"
gas_sidecar_exit_mismatch_err="$TMP/gas-sidecar-exit-mismatch.err"
gas_sidecar_exit_mismatch_json="$TMP/gas-sidecar-exit-mismatch.run.json"
gas_sidecar_missing_surface_out="$TMP/gas-sidecar-missing-surface.out"
gas_sidecar_missing_surface_err="$TMP/gas-sidecar-missing-surface.err"
gas_sidecar_missing_surface_json="$TMP/gas-sidecar-missing-surface.run.json"
gas_sidecar_zero_gas_out="$TMP/gas-sidecar-zero-gas.out"
gas_sidecar_zero_gas_err="$TMP/gas-sidecar-zero-gas.err"
gas_sidecar_zero_gas_json="$TMP/gas-sidecar-zero-gas.run.json"
gas_sidecar_timeout_out="$TMP/gas-sidecar-timeout.out"
gas_sidecar_timeout_err="$TMP/gas-sidecar-timeout.err"
gas_sidecar_timeout_json="$TMP/gas-sidecar-timeout.run.json"
gas_profile_bad_out="$TMP/gas-profile-bad.out"
gas_profile_bad_err="$TMP/gas-profile-bad.err"
gas_profile_avm_bad_out="$TMP/gas-profile-avm-bad.out"
gas_profile_avm_bad_err="$TMP/gas-profile-avm-bad.err"
gas_stmt_fail_out="$TMP/gas-stmt-fail.out"
gas_stmt_fail_err="$TMP/gas-stmt-fail.err"
gas_stmt_fail_json="$TMP/gas-stmt-fail.run.json"
wall_out="$TMP/wall.out"
wall_err="$TMP/wall.err"
wall_json="$TMP/wall.run.json"
heap_ok_out="$TMP/heap-ok.out"
heap_ok_err="$TMP/heap-ok.err"
heap_ok_json="$TMP/heap-ok.run.json"
heap_fail_out="$TMP/heap-fail.out"
heap_fail_err="$TMP/heap-fail.err"
heap_fail_json="$TMP/heap-fail.run.json"
cpu_ok_out="$TMP/cpu-ok.out"
cpu_ok_err="$TMP/cpu-ok.err"
cpu_ok_json="$TMP/cpu-ok.run.json"
cpu_fail_out="$TMP/cpu-fail.out"
cpu_fail_err="$TMP/cpu-fail.err"
cpu_fail_json="$TMP/cpu-fail.run.json"

OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_ok.oren \
  >"$ok_out" 2>"$ok_err"
grep -Fq "native package policy ok" "$ok_out" || {
  echo "ERROR: native package-policy ok fixture did not report success" >&2
  cat "$ok_out" >&2 || true
  cat "$ok_err" >&2 || true
  exit 1
}
grep -Fq "native capsule effect gates " "$ok_out" || {
  echo "ERROR: native package-policy ok fixture did not report capsule effect gates" >&2
  cat "$ok_out" >&2 || true
  cat "$ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$heap_ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_heap_ok.oren \
  >"$heap_ok_out" 2>"$heap_ok_err"
grep -Fq "native package policy heap ok" "$heap_ok_out" || {
  echo "ERROR: native package-policy heap ok fixture did not report success" >&2
  cat "$heap_ok_out" >&2 || true
  cat "$heap_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$cpu_ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_cpu_ok.oren \
  >"$cpu_ok_out" 2>"$cpu_ok_err"
grep -Fq "native package policy CPU ok" "$cpu_ok_out" || {
  echo "ERROR: native package-policy CPU-ok fixture did not report success" >&2
  cat "$cpu_ok_out" >&2 || true
  cat "$cpu_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_ok_json" \
  OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1 \
  ./scripts/run_package_policy.sh --backend native --gas-profile native-stmt tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_ok_out" 2>"$gas_ok_err"
grep -Fq "native package policy gas ok" "$gas_ok_out" || {
  echo "ERROR: native package-policy gas-ok fixture did not report success" >&2
  cat "$gas_ok_out" >&2 || true
  cat "$gas_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_env_override_ok_json" \
  OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=native-stmt \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_env_override_ok_out" 2>"$gas_env_override_ok_err"
grep -Fq "native package policy gas ok" "$gas_env_override_ok_out" || {
  echo "ERROR: native package-policy env override gas profile fixture did not report success" >&2
  cat "$gas_env_override_ok_out" >&2 || true
  cat "$gas_env_override_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_ok_json" \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_ok_out" 2>"$gas_sidecar_ok_err"
grep -Fq "native package policy gas ok" "$gas_sidecar_ok_out" || {
  echo "ERROR: native package-policy AVM sidecar gas-ok fixture did not report success" >&2
  cat "$gas_sidecar_ok_out" >&2 || true
  cat "$gas_sidecar_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_auto_ok_json" \
  ./scripts/run_package_policy.sh --backend native --gas-profile auto tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_auto_ok_out" 2>"$gas_auto_ok_err"
grep -Fq "native package policy gas ok" "$gas_auto_ok_out" || {
  echo "ERROR: native package-policy auto gas profile fixture did not report success" >&2
  cat "$gas_auto_ok_out" >&2 || true
  cat "$gas_auto_ok_err" >&2 || true
  exit 1
}
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_dispatch_default_ok_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_dispatch_default_ok_out" 2>"$gas_dispatch_default_ok_err"
grep -Fq "native package policy gas ok" "$gas_dispatch_default_ok_out" || {
  echo "ERROR: native package-policy dispatcher default gas profile fixture did not report success" >&2
  cat "$gas_dispatch_default_ok_out" >&2 || true
  cat "$gas_dispatch_default_ok_err" >&2 || true
  exit 1
}

set +e
./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_deny_time.oren \
  >"$deny_out" 2>"$deny_err"
deny_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_fail_json" \
  ./scripts/run_package_policy.sh --backend native --gas-profile native-stmt tests/fixtures/native_package_policy_runner_gas_fail.oren \
  >"$gas_fail_out" 2>"$gas_fail_err"
gas_fail_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_fail_json" \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_fail.oren \
  >"$gas_sidecar_fail_out" 2>"$gas_sidecar_fail_err"
gas_sidecar_fail_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_uncertified_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_STDOUT_SUFFIX=$'\nverifier stdout mismatch\n' \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_uncertified_out" 2>"$gas_sidecar_uncertified_err"
gas_sidecar_uncertified_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_stderr_warning_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_STDERR_SUFFIX=$'\nverifier stderr warning\n' \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_stderr_warning_out" 2>"$gas_sidecar_stderr_warning_err"
gas_sidecar_stderr_warning_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_exit_mismatch_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_EXIT_CODE=42 \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_exit_mismatch_out" 2>"$gas_sidecar_exit_mismatch_err"
gas_sidecar_exit_mismatch_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_missing_surface_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_DROP_GAS_SURFACE=1 \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_missing_surface_out" 2>"$gas_sidecar_missing_surface_err"
gas_sidecar_missing_surface_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_zero_gas_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_ZERO_GAS=1 \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_zero_gas_out" 2>"$gas_sidecar_zero_gas_err"
gas_sidecar_zero_gas_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_sidecar_timeout_json" \
  OREN_NATIVE_PACKAGE_POLICY_TEST_AVM_SIDECAR_TIMEOUT=1 \
  ./scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_sidecar_timeout_out" 2>"$gas_sidecar_timeout_err"
gas_sidecar_timeout_rc=$?
OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=sidecar \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_gas_ok.oren \
  >"$gas_profile_bad_out" 2>"$gas_profile_bad_err"
gas_profile_bad_rc=$?
./scripts/run_package_policy.sh --backend avm --gas-profile avm-sidecar tests/fixtures/avm_package_policy_runner_ok.oren \
  >"$gas_profile_avm_bad_out" 2>"$gas_profile_avm_bad_err"
gas_profile_avm_bad_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$gas_stmt_fail_json" \
  ./scripts/run_package_policy.sh --backend native --gas-profile native-stmt tests/fixtures/native_package_policy_runner_gas_stmt_fail.oren \
  >"$gas_stmt_fail_out" 2>"$gas_stmt_fail_err"
gas_stmt_fail_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$wall_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_wall_timeout.oren \
  >"$wall_out" 2>"$wall_err"
wall_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$heap_fail_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_heap_fail.oren \
  >"$heap_fail_out" 2>"$heap_fail_err"
heap_fail_rc=$?
OREN_NATIVE_PACKAGE_POLICY_RUN_JSON="$cpu_fail_json" \
  ./scripts/run_package_policy.sh --backend native tests/fixtures/native_package_policy_runner_cpu_fail.oren \
  >"$cpu_fail_out" 2>"$cpu_fail_err"
cpu_fail_rc=$?
set -e

python3 - "$ok_json" "$wall_json" "$ok_out" "$heap_ok_json" "$heap_fail_json" "$cpu_ok_json" "$cpu_fail_json" "$gas_ok_json" "$gas_fail_json" "$gas_stmt_fail_json" "$gas_sidecar_ok_json" "$gas_sidecar_fail_json" "$gas_sidecar_uncertified_json" "$gas_sidecar_stderr_warning_json" "$gas_auto_ok_json" "$gas_dispatch_default_ok_json" "$gas_env_override_ok_json" "$gas_sidecar_exit_mismatch_json" "$gas_sidecar_missing_surface_json" "$gas_sidecar_zero_gas_json" "$gas_sidecar_timeout_json" <<'PY'
import json
import sys
from pathlib import Path

ok_path = Path(sys.argv[1])
wall_path = Path(sys.argv[2])
ok_stdout_path = Path(sys.argv[3])
heap_ok_path = Path(sys.argv[4])
heap_fail_path = Path(sys.argv[5])
cpu_ok_path = Path(sys.argv[6])
cpu_fail_path = Path(sys.argv[7])
gas_ok_path = Path(sys.argv[8])
gas_fail_path = Path(sys.argv[9])
gas_stmt_fail_path = Path(sys.argv[10])
gas_sidecar_ok_path = Path(sys.argv[11])
gas_sidecar_fail_path = Path(sys.argv[12])
gas_sidecar_uncertified_path = Path(sys.argv[13])
gas_sidecar_stderr_warning_path = Path(sys.argv[14])
gas_auto_ok_path = Path(sys.argv[15])
gas_dispatch_default_ok_path = Path(sys.argv[16])
gas_env_override_ok_path = Path(sys.argv[17])
gas_sidecar_exit_mismatch_path = Path(sys.argv[18])
gas_sidecar_missing_surface_path = Path(sys.argv[19])
gas_sidecar_zero_gas_path = Path(sys.argv[20])
gas_sidecar_timeout_path = Path(sys.argv[21])

def fail(msg):
    raise SystemExit(msg)

def load(path):
    if not path.is_file():
        fail(f"{path}: missing native runner JSON")
    return json.loads(path.read_text(encoding="utf-8"))

def assert_native_stmt_surface(path, surface):
    if surface.get("schema") != "oren.gas-surface.v0" or surface.get("id") != "native_stmt_loop_tick_v0":
        fail(f"{path}: expected native_stmt_loop_tick_v0 gas surface, got {surface!r}")
    if surface.get("unit_scope") != "backend_local" or surface.get("runtime_path_aware") is not True:
        fail(f"{path}: native package-policy statement gas should be backend-local runtime-path-aware evidence, got {surface!r}")
    if surface.get("target_arch") not in ("arm64", "x64"):
        fail(f"{path}: native package-policy statement gas should declare target_arch, got {surface!r}")
    if surface.get("unit_family") != "native_statement_or_op":
        fail(f"{path}: native package-policy statement gas unit_family mismatch, got {surface!r}")
    if surface.get("cross_arch_comparable") is not False or surface.get("conversion_ready") is not False:
        fail(f"{path}: native package-policy statement gas must not be conversion-ready, got {surface!r}")
    if surface.get("avm_canonical") is not False:
        fail(f"{path}: native package-policy statement gas must not claim AVM canonical units, got {surface!r}")

def assert_avm_canonical_sidecar(path, sidecar, *, budget_exceeded=False):
    if sidecar.get("schema") != "oren.avm-canonical-sidecar-gas.v0":
        fail(f"{path}: AVM canonical sidecar schema mismatch: {sidecar!r}")
    expected_status = "budget_exceeded" if budget_exceeded else "available"
    if sidecar.get("status") != expected_status:
        fail(f"{path}: expected AVM canonical sidecar status {expected_status!r}, got {sidecar!r}")
    if sidecar.get("policy_scope") != "native_package_policy_same_source_artifact":
        fail(f"{path}: AVM sidecar policy scope mismatch: {sidecar!r}")
    if sidecar.get("same_source") is not True:
        fail(f"{path}: AVM sidecar should certify same-source evidence, got {sidecar!r}")
    if sidecar.get("native_runtime_conversion") is not False:
        fail(f"{path}: AVM sidecar must not claim native runtime conversion, got {sidecar!r}")
    if not isinstance(sidecar.get("native_exit_code"), int) or not isinstance(sidecar.get("sidecar_exit_code"), int):
        fail(f"{path}: AVM sidecar should expose concrete native/sidecar exit codes, got {sidecar!r}")
    if sidecar.get("package_policy_may_use") is not True:
        fail(f"{path}: package-bound AVM sidecar should be usable as an AVM canonical certificate, got {sidecar!r}")
    expected_certification = "budget_exceeded_canonical_surface" if budget_exceeded else "stdout_exit_match"
    if sidecar.get("certification_status") != expected_certification:
        fail(f"{path}: AVM sidecar certification status mismatch: {sidecar!r}")
    if sidecar.get("certification_failure_reasons") != []:
        fail(f"{path}: certified AVM sidecar should have no failure reasons, got {sidecar!r}")
    if not isinstance(sidecar.get("certification_warnings"), list):
        fail(f"{path}: AVM sidecar should expose non-blocking certification warnings, got {sidecar!r}")
    if sidecar.get("test_injection") is not None:
        fail(f"{path}: certified AVM sidecar should not carry verifier test injection, got {sidecar!r}")
    if not sidecar.get("native_stdout_sha256") or not sidecar.get("sidecar_stdout_sha256"):
        fail(f"{path}: AVM sidecar should include normalized stdout hashes, got {sidecar!r}")
    if not sidecar.get("native_stderr_sha256") or not sidecar.get("sidecar_stderr_sha256"):
        fail(f"{path}: AVM sidecar should include normalized stderr hashes, got {sidecar!r}")
    if not isinstance(sidecar.get("same_run_stderr_equal"), bool):
        fail(f"{path}: AVM sidecar should expose explicit stderr parity, got {sidecar!r}")
    if budget_exceeded:
        if sidecar.get("native_exit_code") != 0 or sidecar.get("sidecar_exit_code") == 0:
            fail(f"{path}: AVM sidecar budget-exceeded certificate should expose native success and sidecar failure exits, got {sidecar!r}")
        if sidecar.get("package_policy_may_use_reason") != "avm_canonical_gas_budget_exceeded":
            fail(f"{path}: AVM sidecar budget-exceeded reason mismatch: {sidecar!r}")
        if sidecar.get("budget_exceeded_source") != "avm_run_json_error":
            fail(f"{path}: AVM sidecar budget-exceeded certificate should use structured AVM run JSON error, got {sidecar!r}")
        err = sidecar.get("sidecar_error") or {}
        if err.get("code") != 9 or err.get("msg") != "budget exceeded (gas)":
            fail(f"{path}: AVM sidecar budget-exceeded error mismatch: {sidecar!r}")
    else:
        if sidecar.get("native_exit_code") != 0 or sidecar.get("sidecar_exit_code") != 0:
            fail(f"{path}: AVM sidecar available certificate should expose zero native/sidecar exits, got {sidecar!r}")
        if sidecar.get("native_stdout_sha256") != sidecar.get("sidecar_stdout_sha256"):
            fail(f"{path}: AVM sidecar stdout hashes should match for available certificate, got {sidecar!r}")
        if sidecar.get("same_run_stderr_equal") is not True:
            fail(f"{path}: AVM sidecar stderr parity should be explicit for available certificate, got {sidecar!r}")
        if sidecar.get("certification_warnings") != []:
            fail(f"{path}: available AVM sidecar should not carry certification warnings, got {sidecar!r}")
        if sidecar.get("native_stderr_sha256") != sidecar.get("sidecar_stderr_sha256"):
            fail(f"{path}: AVM sidecar stderr hashes should match for available certificate, got {sidecar!r}")
        if sidecar.get("package_policy_may_use_reason") != "stdout_exit_match_with_avm_canonical_gas":
            fail(f"{path}: AVM sidecar package-policy reason mismatch: {sidecar!r}")
        if sidecar.get("budget_exceeded") is not False or sidecar.get("budget_exceeded_source") is not None:
            fail(f"{path}: AVM sidecar available certificate should not carry budget exhaustion, got {sidecar!r}")
        if sidecar.get("sidecar_error") is not None:
            fail(f"{path}: AVM sidecar available certificate should have no sidecar error, got {sidecar!r}")
    sidecar_surface = sidecar.get("gas_surface") or {}
    if sidecar_surface.get("id") != "avm_opcode_cost_v0" or sidecar_surface.get("unit_scope") != "avm_canonical":
        fail(f"{path}: AVM sidecar gas surface mismatch: {sidecar!r}")
    if sidecar_surface.get("conversion_ready") is not True or sidecar_surface.get("avm_canonical") is not True:
        fail(f"{path}: AVM sidecar should preserve canonical metadata: {sidecar!r}")

ok = load(ok_path)
if ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{ok_path}: schema mismatch: {ok.get('schema')!r}")
if ok.get("backend") != "native":
    fail(f"{ok_path}: backend mismatch: {ok.get('backend')!r}")
if ok.get("status") != "pass" or ok.get("exit_code") != 0:
    fail(f"{ok_path}: expected pass/0, got status={ok.get('status')!r} exit={ok.get('exit_code')!r}")
if ok.get("runtime_profile") != "capsule" or ok.get("capsule") is not True:
    fail(f"{ok_path}: expected capsule runtime profile, got {ok!r}")
if ok.get("cap_allow_domains") != ["TIME"]:
    fail(f"{ok_path}: expected TIME allow domain, got {ok.get('cap_allow_domains')!r}")
ok_ledger = ok.get("effect_ledger") or {}
if ok_ledger.get("available") is not True:
    fail(f"{ok_path}: expected captured native runtime ledger summary, got {ok_ledger!r}")
ok_summary = ok_ledger.get("summary") or {}
if ok_summary.get("schema") != "oren.effect-ledger-summary.v0":
    fail(f"{ok_path}: native effect ledger summary schema mismatch: {ok_summary!r}")
if (ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_only":
    fail(f"{ok_path}: expected runner_wall_only status, got {ok.get('runner_observed')!r}")
wall = ((ok.get("budgets") or {}).get("wall_ms") or {})
if wall.get("limit") != 1000 or wall.get("enforced") is not True:
    fail(f"{ok_path}: expected enforced 1000ms wall budget, got {wall!r}")
if int(wall.get("elapsed_ns") or 0) <= 0:
    fail(f"{ok_path}: expected positive elapsed_ns, got {wall!r}")

gate_prefix = "native capsule effect gates "
gate_json = None
for line in ok_stdout_path.read_text(encoding="utf-8").splitlines():
    if line.startswith(gate_prefix):
        gate_json = line[len(gate_prefix):]
if gate_json is None:
    fail(f"{ok_stdout_path}: missing native capsule effect gate JSON line")
try:
    gates = json.loads(gate_json)
except json.JSONDecodeError as exc:
    fail(f"{ok_stdout_path}: invalid native capsule effect gate JSON: {exc}")
if gates.get("schema") != "oren.native-capsule-effect-gates.v0":
    fail(f"{ok_stdout_path}: effect gate schema mismatch: {gates!r}")
if gates.get("kind") != "domain_gates" or gates.get("available") is not True:
    fail(f"{ok_stdout_path}: effect gate availability mismatch: {gates!r}")
if gates.get("capsule") is not True:
    fail(f"{ok_stdout_path}: expected capsule=true in effect gate summary: {gates!r}")
if int(gates.get("total") or 0) <= 0:
    fail(f"{ok_stdout_path}: expected positive effect gate total: {gates!r}")
if int(gates.get("denied") or 0) != 0:
    fail(f"{ok_stdout_path}: expected zero denied effect gates in success path: {gates!r}")
if int((gates.get("domains") or {}).get("TIME") or 0) <= 0:
    fail(f"{ok_stdout_path}: expected positive TIME effect gates: {gates!r}")

wall_timeout = load(wall_path)
if wall_timeout.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{wall_path}: schema mismatch: {wall_timeout.get('schema')!r}")
if wall_timeout.get("status") != "timeout" or wall_timeout.get("exit_code") != 124:
    fail(
        f"{wall_path}: expected timeout/124, got "
        f"status={wall_timeout.get('status')!r} exit={wall_timeout.get('exit_code')!r}"
    )
wall_budget = ((wall_timeout.get("budgets") or {}).get("wall_ms") or {})
if wall_budget.get("limit") != 100 or wall_budget.get("enforced") is not True:
    fail(f"{wall_path}: expected enforced 100ms wall budget, got {wall_budget!r}")
if int(wall_budget.get("elapsed_ns") or 0) <= 0:
    fail(f"{wall_path}: expected positive timeout elapsed_ns, got {wall_budget!r}")

heap_ok = load(heap_ok_path)
if heap_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{heap_ok_path}: schema mismatch: {heap_ok.get('schema')!r}")
if heap_ok.get("status") != "pass" or heap_ok.get("exit_code") != 0:
    fail(f"{heap_ok_path}: expected pass/0, got status={heap_ok.get('status')!r} exit={heap_ok.get('exit_code')!r}")
if (heap_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_native_heap":
    fail(f"{heap_ok_path}: expected runner_wall_native_heap status, got {heap_ok.get('runner_observed')!r}")
heap_ok_ledger = heap_ok.get("effect_ledger") or {}
if heap_ok_ledger.get("available") is not True:
    fail(f"{heap_ok_path}: expected native runtime ledger summary, got {heap_ok_ledger!r}")
heap_ok_summary = heap_ok_ledger.get("summary") or {}
heap_ok_budget = ((heap_ok.get("budgets") or {}).get("heap_bytes") or {})
if heap_ok_budget.get("limit") != 20000000 or heap_ok_budget.get("enforced") is not True:
    fail(f"{heap_ok_path}: expected enforced 20000000 byte heap budget, got {heap_ok_budget!r}")
if heap_ok_budget.get("exceeded") is not False:
    fail(f"{heap_ok_path}: expected non-exceeded heap budget, got {heap_ok_budget!r}")
heap_ok_used = int(heap_ok_budget.get("used") or -1)
if heap_ok_used < 0 or heap_ok_used > 20000000:
    fail(f"{heap_ok_path}: heap used outside budget: {heap_ok_budget!r}")
summary_heap = (((heap_ok_summary.get("budgets") or {}).get("heap_bytes") or {}))
if summary_heap.get("kind") != "tracked_live_scan":
    fail(f"{heap_ok_path}: expected tracked_live_scan native heap summary, got {summary_heap!r}")
if int(summary_heap.get("used") or -1) != heap_ok_used:
    fail(f"{heap_ok_path}: runner heap used does not mirror native summary: runner={heap_ok_budget!r} summary={summary_heap!r}")

heap_fail = load(heap_fail_path)
if heap_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{heap_fail_path}: schema mismatch: {heap_fail.get('schema')!r}")
if heap_fail.get("status") != "budget_exceeded" or heap_fail.get("exit_code") != 125:
    fail(
        f"{heap_fail_path}: expected budget_exceeded/125, got "
        f"status={heap_fail.get('status')!r} exit={heap_fail.get('exit_code')!r}"
    )
heap_fail_budget = ((heap_fail.get("budgets") or {}).get("heap_bytes") or {})
if heap_fail_budget.get("limit") != 1 or heap_fail_budget.get("enforced") is not True:
    fail(f"{heap_fail_path}: expected enforced 1 byte heap budget, got {heap_fail_budget!r}")
if heap_fail_budget.get("exceeded") is not True:
    fail(f"{heap_fail_path}: expected exceeded heap budget, got {heap_fail_budget!r}")
if int(heap_fail_budget.get("used") or 0) <= 1:
    fail(f"{heap_fail_path}: expected heap used to exceed 1 byte, got {heap_fail_budget!r}")

cpu_ok = load(cpu_ok_path)
if cpu_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{cpu_ok_path}: schema mismatch: {cpu_ok.get('schema')!r}")
if cpu_ok.get("status") != "pass" or cpu_ok.get("exit_code") != 0:
    fail(f"{cpu_ok_path}: expected pass/0, got status={cpu_ok.get('status')!r} exit={cpu_ok.get('exit_code')!r}")
if (cpu_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_child_cpu":
    fail(f"{cpu_ok_path}: expected runner_wall_child_cpu status, got {cpu_ok.get('runner_observed')!r}")
cpu_ok_budget = ((cpu_ok.get("budgets") or {}).get("cpu_ms") or {})
if cpu_ok_budget.get("limit") != 60000 or cpu_ok_budget.get("enforced") is not True:
    fail(f"{cpu_ok_path}: expected enforced 60000ms CPU budget, got {cpu_ok_budget!r}")
if cpu_ok_budget.get("exceeded") is not False:
    fail(f"{cpu_ok_path}: expected non-exceeded CPU budget, got {cpu_ok_budget!r}")
cpu_ok_used = int(cpu_ok_budget.get("used") or -1)
if cpu_ok_used < 0 or cpu_ok_used > 60000:
    fail(f"{cpu_ok_path}: CPU used outside budget: {cpu_ok_budget!r}")

gas_ok = load(gas_ok_path)
if gas_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_ok_path}: schema mismatch: {gas_ok.get('schema')!r}")
if gas_ok.get("status") != "pass" or gas_ok.get("exit_code") != 0:
    fail(f"{gas_ok_path}: expected pass/0, got status={gas_ok.get('status')!r} exit={gas_ok.get('exit_code')!r}")
if (gas_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_native_gas":
    fail(f"{gas_ok_path}: expected runner_wall_native_gas status, got {gas_ok.get('runner_observed')!r}")
gas_ok_ledger = gas_ok.get("effect_ledger") or {}
if gas_ok_ledger.get("available") is not True:
    fail(f"{gas_ok_path}: expected native runtime ledger summary, got {gas_ok_ledger!r}")
gas_ok_summary = gas_ok_ledger.get("summary") or {}
gas_ok_budget = ((gas_ok.get("budgets") or {}).get("gas") or {})
if gas_ok_budget.get("limit") != 100000 or gas_ok_budget.get("enforced") is not True:
    fail(f"{gas_ok_path}: expected enforced 100000 native gas budget, got {gas_ok_budget!r}")
if gas_ok_budget.get("kind") != "native_stmt_loop_tick_v0":
    fail(f"{gas_ok_path}: expected native_stmt_loop_tick_v0 gas kind, got {gas_ok_budget!r}")
gas_ok_surface = gas_ok_budget.get("surface") or {}
assert_native_stmt_surface(gas_ok_path, gas_ok_surface)
gas_ok_sidecar = gas_ok.get("avm_canonical_sidecar_gas") or {}
assert_avm_canonical_sidecar(gas_ok_path, gas_ok_sidecar)
if gas_ok_sidecar.get("same_source") is not True or gas_ok_sidecar.get("same_run_stdout_equal") is not True:
    fail(f"{gas_ok_path}: AVM sidecar should certify same-source stdout parity, got {gas_ok_sidecar!r}")
if gas_ok_sidecar.get("same_run_exit_code_equal") is not True:
    fail(f"{gas_ok_path}: AVM sidecar should certify exit-code parity, got {gas_ok_sidecar!r}")
if int(gas_ok_sidecar.get("gas_executed") or 0) <= 0:
    fail(f"{gas_ok_path}: AVM sidecar should report positive canonical gas, got {gas_ok_sidecar!r}")
if gas_ok_budget.get("exceeded") is not False:
    fail(f"{gas_ok_path}: expected non-exceeded gas budget, got {gas_ok_budget!r}")
gas_ok_used = int(gas_ok_budget.get("executed") or -1)
if gas_ok_used < 0 or gas_ok_used > 100000:
    fail(f"{gas_ok_path}: gas used outside budget: {gas_ok_budget!r}")
if gas_ok_used < 1024:
    fail(f"{gas_ok_path}: expected at least one loop-safepoint interval gas charge, got {gas_ok_budget!r}")
summary_gas = (((gas_ok_summary.get("budgets") or {}).get("gas") or {}))
if summary_gas.get("kind") != "native_stmt_loop_tick_v0":
    fail(f"{gas_ok_path}: expected native_stmt_loop_tick_v0 native gas summary, got {summary_gas!r}")
assert_native_stmt_surface(gas_ok_path, summary_gas.get("surface") or {})
if int(summary_gas.get("executed") or -1) != gas_ok_used:
    fail(f"{gas_ok_path}: runner gas used does not mirror native summary: runner={gas_ok_budget!r} summary={summary_gas!r}")

gas_env_override_ok = load(gas_env_override_ok_path)
if gas_env_override_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_env_override_ok_path}: schema mismatch: {gas_env_override_ok.get('schema')!r}")
if gas_env_override_ok.get("status") != "pass" or gas_env_override_ok.get("exit_code") != 0:
    fail(
        f"{gas_env_override_ok_path}: expected pass/0, got "
        f"status={gas_env_override_ok.get('status')!r} exit={gas_env_override_ok.get('exit_code')!r}"
    )
if (gas_env_override_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_native_gas":
    fail(
        f"{gas_env_override_ok_path}: expected env override to keep runner_wall_native_gas status, "
        f"got {gas_env_override_ok.get('runner_observed')!r}"
    )
gas_env_override_ok_budget = ((gas_env_override_ok.get("budgets") or {}).get("gas") or {})
if gas_env_override_ok_budget.get("enforcement_profile") != "native-stmt":
    fail(f"{gas_env_override_ok_path}: env override should preserve native-stmt enforcement, got {gas_env_override_ok_budget!r}")
if gas_env_override_ok_budget.get("requested_enforcement_profile") != "native-stmt":
    fail(f"{gas_env_override_ok_path}: env override should request native-stmt, got {gas_env_override_ok_budget!r}")
if gas_env_override_ok_budget.get("kind") != "native_stmt_loop_tick_v0" or gas_env_override_ok_budget.get("enforced") is not True:
    fail(f"{gas_env_override_ok_path}: env override should enforce native statement gas, got {gas_env_override_ok_budget!r}")
assert_native_stmt_surface(gas_env_override_ok_path, gas_env_override_ok_budget.get("surface") or {})

gas_sidecar_ok = load(gas_sidecar_ok_path)
if gas_sidecar_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_ok_path}: schema mismatch: {gas_sidecar_ok.get('schema')!r}")
if gas_sidecar_ok.get("status") != "pass" or gas_sidecar_ok.get("exit_code") != 0:
    fail(f"{gas_sidecar_ok_path}: expected pass/0, got status={gas_sidecar_ok.get('status')!r} exit={gas_sidecar_ok.get('exit_code')!r}")
if (gas_sidecar_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_avm_canonical_gas":
    fail(f"{gas_sidecar_ok_path}: expected runner_wall_avm_canonical_gas status, got {gas_sidecar_ok.get('runner_observed')!r}")
gas_sidecar_ok_budget = ((gas_sidecar_ok.get("budgets") or {}).get("gas") or {})
if gas_sidecar_ok_budget.get("limit") != 100000 or gas_sidecar_ok_budget.get("enforced") is not True:
    fail(f"{gas_sidecar_ok_path}: expected enforced 100000 AVM canonical gas budget, got {gas_sidecar_ok_budget!r}")
if gas_sidecar_ok_budget.get("enforcement") != "avm-canonical-sidecar" or gas_sidecar_ok_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_sidecar_ok_path}: expected AVM sidecar gas enforcement profile, got {gas_sidecar_ok_budget!r}")
if gas_sidecar_ok_budget.get("kind") != "avm_opcode_cost_v0":
    fail(f"{gas_sidecar_ok_path}: expected avm_opcode_cost_v0 gas kind, got {gas_sidecar_ok_budget!r}")
sidecar_ok = gas_sidecar_ok.get("avm_canonical_sidecar_gas") or {}
assert_avm_canonical_sidecar(gas_sidecar_ok_path, sidecar_ok)
if int(gas_sidecar_ok_budget.get("executed") or -1) != int(sidecar_ok.get("gas_executed") or -2):
    fail(f"{gas_sidecar_ok_path}: AVM sidecar gas budget should mirror sidecar certificate, got {gas_sidecar_ok_budget!r} vs {sidecar_ok!r}")

gas_auto_ok = load(gas_auto_ok_path)
if gas_auto_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_auto_ok_path}: schema mismatch: {gas_auto_ok.get('schema')!r}")
if gas_auto_ok.get("status") != "pass" or gas_auto_ok.get("exit_code") != 0:
    fail(f"{gas_auto_ok_path}: expected pass/0, got status={gas_auto_ok.get('status')!r} exit={gas_auto_ok.get('exit_code')!r}")
if (gas_auto_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_avm_canonical_gas":
    fail(f"{gas_auto_ok_path}: expected runner_wall_avm_canonical_gas status, got {gas_auto_ok.get('runner_observed')!r}")
gas_auto_ok_budget = ((gas_auto_ok.get("budgets") or {}).get("gas") or {})
if gas_auto_ok_budget.get("enforcement") != "avm-canonical-sidecar" or gas_auto_ok_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_auto_ok_path}: auto profile should resolve to AVM sidecar enforcement, got {gas_auto_ok_budget!r}")
if gas_auto_ok_budget.get("requested_enforcement_profile") != "auto":
    fail(f"{gas_auto_ok_path}: expected requested auto gas profile, got {gas_auto_ok_budget!r}")
if gas_auto_ok_budget.get("kind") != "avm_opcode_cost_v0" or gas_auto_ok_budget.get("enforced") is not True:
    fail(f"{gas_auto_ok_path}: expected enforced AVM canonical gas in auto profile, got {gas_auto_ok_budget!r}")
auto_sidecar = gas_auto_ok.get("avm_canonical_sidecar_gas") or {}
assert_avm_canonical_sidecar(gas_auto_ok_path, auto_sidecar)
if int(gas_auto_ok_budget.get("executed") or -1) != int(auto_sidecar.get("gas_executed") or -2):
    fail(f"{gas_auto_ok_path}: auto gas budget should mirror sidecar certificate, got {gas_auto_ok_budget!r} vs {auto_sidecar!r}")

gas_dispatch_default_ok = load(gas_dispatch_default_ok_path)
if gas_dispatch_default_ok.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_dispatch_default_ok_path}: schema mismatch: {gas_dispatch_default_ok.get('schema')!r}")
if gas_dispatch_default_ok.get("status") != "pass" or gas_dispatch_default_ok.get("exit_code") != 0:
    fail(
        f"{gas_dispatch_default_ok_path}: expected pass/0, got "
        f"status={gas_dispatch_default_ok.get('status')!r} exit={gas_dispatch_default_ok.get('exit_code')!r}"
    )
if (gas_dispatch_default_ok.get("runner_observed") or {}).get("budget_status") != "runner_wall_avm_canonical_gas":
    fail(
        f"{gas_dispatch_default_ok_path}: expected dispatcher default to report runner_wall_avm_canonical_gas, "
        f"got {gas_dispatch_default_ok.get('runner_observed')!r}"
    )
gas_dispatch_default_ok_budget = ((gas_dispatch_default_ok.get("budgets") or {}).get("gas") or {})
if (
    gas_dispatch_default_ok_budget.get("enforcement") != "avm-canonical-sidecar"
    or gas_dispatch_default_ok_budget.get("enforcement_profile") != "avm-sidecar"
):
    fail(
        f"{gas_dispatch_default_ok_path}: dispatcher default should resolve to AVM sidecar enforcement, "
        f"got {gas_dispatch_default_ok_budget!r}"
    )
if gas_dispatch_default_ok_budget.get("requested_enforcement_profile") != "auto":
    fail(
        f"{gas_dispatch_default_ok_path}: expected dispatcher default to request auto gas profile, "
        f"got {gas_dispatch_default_ok_budget!r}"
    )
if gas_dispatch_default_ok_budget.get("kind") != "avm_opcode_cost_v0" or gas_dispatch_default_ok_budget.get("enforced") is not True:
    fail(f"{gas_dispatch_default_ok_path}: expected enforced AVM canonical gas in dispatcher default, got {gas_dispatch_default_ok_budget!r}")
default_sidecar = gas_dispatch_default_ok.get("avm_canonical_sidecar_gas") or {}
assert_avm_canonical_sidecar(gas_dispatch_default_ok_path, default_sidecar)
if int(gas_dispatch_default_ok_budget.get("executed") or -1) != int(default_sidecar.get("gas_executed") or -2):
    fail(
        f"{gas_dispatch_default_ok_path}: dispatcher default gas budget should mirror sidecar certificate, "
        f"got {gas_dispatch_default_ok_budget!r} vs {default_sidecar!r}"
    )

cpu_fail = load(cpu_fail_path)
if cpu_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{cpu_fail_path}: schema mismatch: {cpu_fail.get('schema')!r}")
if cpu_fail.get("status") != "budget_exceeded" or cpu_fail.get("exit_code") != 126:
    fail(
        f"{cpu_fail_path}: expected budget_exceeded/126, got "
        f"status={cpu_fail.get('status')!r} exit={cpu_fail.get('exit_code')!r}"
    )
cpu_fail_budget = ((cpu_fail.get("budgets") or {}).get("cpu_ms") or {})
if cpu_fail_budget.get("limit") != 1 or cpu_fail_budget.get("enforced") is not True:
    fail(f"{cpu_fail_path}: expected enforced 1ms CPU budget, got {cpu_fail_budget!r}")
if cpu_fail_budget.get("exceeded") is not True:
    fail(f"{cpu_fail_path}: expected exceeded CPU budget, got {cpu_fail_budget!r}")
if int(cpu_fail_budget.get("used") or 0) <= 1:
    fail(f"{cpu_fail_path}: expected CPU used to exceed 1ms, got {cpu_fail_budget!r}")

gas_fail = load(gas_fail_path)
if gas_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_fail_path}: schema mismatch: {gas_fail.get('schema')!r}")
if gas_fail.get("status") != "budget_exceeded" or gas_fail.get("exit_code") != 127:
    fail(
        f"{gas_fail_path}: expected budget_exceeded/127, got "
        f"status={gas_fail.get('status')!r} exit={gas_fail.get('exit_code')!r}"
    )
gas_fail_budget = ((gas_fail.get("budgets") or {}).get("gas") or {})
if gas_fail_budget.get("limit") != 1 or gas_fail_budget.get("enforced") is not True:
    fail(f"{gas_fail_path}: expected enforced 1 native gas budget, got {gas_fail_budget!r}")
if gas_fail_budget.get("kind") != "native_stmt_loop_tick_v0":
    fail(f"{gas_fail_path}: expected native_stmt_loop_tick_v0 gas kind, got {gas_fail_budget!r}")
assert_native_stmt_surface(gas_fail_path, gas_fail_budget.get("surface") or {})
if gas_fail_budget.get("exceeded") is not True:
    fail(f"{gas_fail_path}: expected exceeded gas budget, got {gas_fail_budget!r}")
if int(gas_fail_budget.get("executed") or 0) <= 1:
    fail(f"{gas_fail_path}: expected gas used to exceed 1 tick, got {gas_fail_budget!r}")

gas_stmt_fail = load(gas_stmt_fail_path)
if gas_stmt_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_stmt_fail_path}: schema mismatch: {gas_stmt_fail.get('schema')!r}")
if gas_stmt_fail.get("status") != "budget_exceeded" or gas_stmt_fail.get("exit_code") != 127:
    fail(
        f"{gas_stmt_fail_path}: expected budget_exceeded/127, got "
        f"status={gas_stmt_fail.get('status')!r} exit={gas_stmt_fail.get('exit_code')!r}"
    )
gas_stmt_fail_budget = ((gas_stmt_fail.get("budgets") or {}).get("gas") or {})
if gas_stmt_fail_budget.get("limit") != 8 or gas_stmt_fail_budget.get("enforced") is not True:
    fail(f"{gas_stmt_fail_path}: expected enforced 8 native gas budget, got {gas_stmt_fail_budget!r}")
if gas_stmt_fail_budget.get("kind") != "native_stmt_loop_tick_v0":
    fail(f"{gas_stmt_fail_path}: expected native_stmt_loop_tick_v0 gas kind, got {gas_stmt_fail_budget!r}")
assert_native_stmt_surface(gas_stmt_fail_path, gas_stmt_fail_budget.get("surface") or {})
if gas_stmt_fail_budget.get("exceeded") is not True:
    fail(f"{gas_stmt_fail_path}: expected exceeded statement gas budget, got {gas_stmt_fail_budget!r}")
if int(gas_stmt_fail_budget.get("executed") or 0) <= 8:
    fail(f"{gas_stmt_fail_path}: expected statement gas used to exceed 8 ticks, got {gas_stmt_fail_budget!r}")

gas_sidecar_fail = load(gas_sidecar_fail_path)
if gas_sidecar_fail.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_fail_path}: schema mismatch: {gas_sidecar_fail.get('schema')!r}")
if gas_sidecar_fail.get("status") != "budget_exceeded" or gas_sidecar_fail.get("exit_code") != 127:
    fail(
        f"{gas_sidecar_fail_path}: expected budget_exceeded/127, got "
        f"status={gas_sidecar_fail.get('status')!r} exit={gas_sidecar_fail.get('exit_code')!r}"
    )
gas_sidecar_fail_budget = ((gas_sidecar_fail.get("budgets") or {}).get("gas") or {})
if gas_sidecar_fail_budget.get("limit") != 1 or gas_sidecar_fail_budget.get("enforced") is not True:
    fail(f"{gas_sidecar_fail_path}: expected enforced 1 AVM canonical gas budget, got {gas_sidecar_fail_budget!r}")
if gas_sidecar_fail_budget.get("enforcement") != "avm-canonical-sidecar" or gas_sidecar_fail_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_sidecar_fail_path}: expected AVM sidecar gas enforcement profile, got {gas_sidecar_fail_budget!r}")
if gas_sidecar_fail_budget.get("kind") != "avm_opcode_cost_v0":
    fail(f"{gas_sidecar_fail_path}: expected avm_opcode_cost_v0 gas kind, got {gas_sidecar_fail_budget!r}")
if gas_sidecar_fail_budget.get("exceeded") is not True:
    fail(f"{gas_sidecar_fail_path}: expected exceeded AVM canonical gas budget, got {gas_sidecar_fail_budget!r}")
sidecar_fail = gas_sidecar_fail.get("avm_canonical_sidecar_gas") or {}
assert_avm_canonical_sidecar(gas_sidecar_fail_path, sidecar_fail, budget_exceeded=True)

gas_sidecar_uncertified = load(gas_sidecar_uncertified_path)
if gas_sidecar_uncertified.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_uncertified_path}: schema mismatch: {gas_sidecar_uncertified.get('schema')!r}")
if gas_sidecar_uncertified.get("status") != "budget_unavailable" or gas_sidecar_uncertified.get("exit_code") != 77:
    fail(
        f"{gas_sidecar_uncertified_path}: expected budget_unavailable/77 for uncertified sidecar, got "
        f"status={gas_sidecar_uncertified.get('status')!r} exit={gas_sidecar_uncertified.get('exit_code')!r}"
    )
gas_sidecar_uncertified_budget = ((gas_sidecar_uncertified.get("budgets") or {}).get("gas") or {})
if gas_sidecar_uncertified_budget.get("limit") != 100000:
    fail(f"{gas_sidecar_uncertified_path}: expected original gas limit on uncertified sidecar, got {gas_sidecar_uncertified_budget!r}")
if gas_sidecar_uncertified_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_sidecar_uncertified_path}: expected avm-sidecar enforcement profile, got {gas_sidecar_uncertified_budget!r}")
if gas_sidecar_uncertified_budget.get("enforced") is not False:
    fail(f"{gas_sidecar_uncertified_path}: uncertified AVM sidecar gas must not be marked enforced, got {gas_sidecar_uncertified_budget!r}")
if gas_sidecar_uncertified_budget.get("reason") != "AVM canonical sidecar gas was not certified":
    fail(f"{gas_sidecar_uncertified_path}: uncertified AVM sidecar gas reason mismatch, got {gas_sidecar_uncertified_budget!r}")
sidecar_uncertified = gas_sidecar_uncertified.get("avm_canonical_sidecar_gas") or {}
if sidecar_uncertified.get("schema") != "oren.avm-canonical-sidecar-gas.v0":
    fail(f"{gas_sidecar_uncertified_path}: AVM sidecar schema mismatch: {sidecar_uncertified!r}")
if sidecar_uncertified.get("status") != "unavailable":
    fail(f"{gas_sidecar_uncertified_path}: expected unavailable AVM sidecar status, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("certification_status") != "unavailable":
    fail(f"{gas_sidecar_uncertified_path}: expected unavailable certification status, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("package_policy_may_use") is not False:
    fail(f"{gas_sidecar_uncertified_path}: uncertified sidecar must not be package-policy usable, got {sidecar_uncertified!r}")
if "stdout_mismatch" not in (sidecar_uncertified.get("certification_failure_reasons") or []):
    fail(f"{gas_sidecar_uncertified_path}: expected stdout_mismatch failure reason, got {sidecar_uncertified!r}")
unexpected_uncertified_reasons = set(sidecar_uncertified.get("certification_failure_reasons") or []) - {"stdout_mismatch"}
if unexpected_uncertified_reasons:
    fail(f"{gas_sidecar_uncertified_path}: unexpected uncertified sidecar failure reasons {unexpected_uncertified_reasons!r}, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("certification_warnings") != []:
    fail(f"{gas_sidecar_uncertified_path}: stdout-only test injection should not create sidecar warnings, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("test_injection") != "stdout_suffix":
    fail(f"{gas_sidecar_uncertified_path}: expected auditable stdout_suffix verifier injection, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("same_run_stdout_equal") is not False:
    fail(f"{gas_sidecar_uncertified_path}: expected stdout mismatch evidence, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("same_run_stderr_equal") is not True or sidecar_uncertified.get("same_run_exit_code_equal") is not True:
    fail(f"{gas_sidecar_uncertified_path}: stdout-only uncertified sidecar should preserve stderr/exit parity, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("native_exit_code") != 0 or sidecar_uncertified.get("sidecar_exit_code") != 0:
    fail(f"{gas_sidecar_uncertified_path}: stdout-only uncertified sidecar should expose zero native/sidecar exits, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("native_stdout_sha256") == sidecar_uncertified.get("sidecar_stdout_sha256"):
    fail(f"{gas_sidecar_uncertified_path}: stdout hashes should differ for injected mismatch, got {sidecar_uncertified!r}")
if sidecar_uncertified.get("native_stderr_sha256") != sidecar_uncertified.get("sidecar_stderr_sha256"):
    fail(f"{gas_sidecar_uncertified_path}: stderr hashes should still match for injected stdout mismatch, got {sidecar_uncertified!r}")
uncertified_surface = sidecar_uncertified.get("gas_surface") or {}
if uncertified_surface.get("id") != "avm_opcode_cost_v0" or uncertified_surface.get("unit_scope") != "avm_canonical":
    fail(f"{gas_sidecar_uncertified_path}: uncertified sidecar should still report AVM canonical gas surface evidence, got {sidecar_uncertified!r}")
if int(sidecar_uncertified.get("gas_executed") or 0) <= 0:
    fail(f"{gas_sidecar_uncertified_path}: uncertified sidecar should distinguish parity failure from missing gas evidence, got {sidecar_uncertified!r}")

gas_sidecar_stderr_warning = load(gas_sidecar_stderr_warning_path)
if gas_sidecar_stderr_warning.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_stderr_warning_path}: schema mismatch: {gas_sidecar_stderr_warning.get('schema')!r}")
if gas_sidecar_stderr_warning.get("status") != "pass" or gas_sidecar_stderr_warning.get("exit_code") != 0:
    fail(
        f"{gas_sidecar_stderr_warning_path}: expected pass/0 for warning-only sidecar, got "
        f"status={gas_sidecar_stderr_warning.get('status')!r} exit={gas_sidecar_stderr_warning.get('exit_code')!r}"
    )
gas_sidecar_stderr_warning_budget = ((gas_sidecar_stderr_warning.get("budgets") or {}).get("gas") or {})
if gas_sidecar_stderr_warning_budget.get("enforcement") != "avm-canonical-sidecar":
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar should still enforce AVM canonical gas, got {gas_sidecar_stderr_warning_budget!r}")
if gas_sidecar_stderr_warning_budget.get("enforced") is not True:
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar gas should remain enforced, got {gas_sidecar_stderr_warning_budget!r}")
sidecar_stderr_warning = gas_sidecar_stderr_warning.get("avm_canonical_sidecar_gas") or {}
if sidecar_stderr_warning.get("status") != "available" or sidecar_stderr_warning.get("certification_status") != "stdout_exit_match":
    fail(f"{gas_sidecar_stderr_warning_path}: stderr-only sidecar warning should keep stdout/exit certificate available, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("package_policy_may_use") is not True:
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar should remain package-policy usable, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("certification_failure_reasons") != []:
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar should not carry failure reasons, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("certification_warnings") != ["stderr_mismatch"]:
    fail(f"{gas_sidecar_stderr_warning_path}: expected stderr_mismatch warning, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("test_injection") != "stderr_suffix":
    fail(f"{gas_sidecar_stderr_warning_path}: expected auditable stderr_suffix verifier injection, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("same_run_stdout_equal") is not True or sidecar_stderr_warning.get("same_run_exit_code_equal") is not True:
    fail(f"{gas_sidecar_stderr_warning_path}: stderr-only warning should preserve stdout/exit parity, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("native_exit_code") != 0 or sidecar_stderr_warning.get("sidecar_exit_code") != 0:
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar should expose zero native/sidecar exits, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("same_run_stderr_equal") is not False:
    fail(f"{gas_sidecar_stderr_warning_path}: expected explicit stderr mismatch warning evidence, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("native_stdout_sha256") != sidecar_stderr_warning.get("sidecar_stdout_sha256"):
    fail(f"{gas_sidecar_stderr_warning_path}: stdout hashes should still match for warning-only sidecar, got {sidecar_stderr_warning!r}")
if sidecar_stderr_warning.get("native_stderr_sha256") == sidecar_stderr_warning.get("sidecar_stderr_sha256"):
    fail(f"{gas_sidecar_stderr_warning_path}: stderr hashes should differ for injected warning, got {sidecar_stderr_warning!r}")
stderr_warning_surface = sidecar_stderr_warning.get("gas_surface") or {}
if stderr_warning_surface.get("id") != "avm_opcode_cost_v0" or stderr_warning_surface.get("unit_scope") != "avm_canonical":
    fail(f"{gas_sidecar_stderr_warning_path}: warning-only sidecar should preserve AVM canonical surface evidence, got {sidecar_stderr_warning!r}")
if int(gas_sidecar_stderr_warning_budget.get("executed") or -1) != int(sidecar_stderr_warning.get("gas_executed") or -2):
    fail(
        f"{gas_sidecar_stderr_warning_path}: warning-only gas budget should mirror sidecar evidence, "
        f"got {gas_sidecar_stderr_warning_budget!r} vs {sidecar_stderr_warning!r}"
    )

def assert_sidecar_unavailable_run(path, expected_reasons, expected_injection):
    data = load(path)
    if data.get("schema") != "oren.native-package-policy-run.v0":
        fail(f"{path}: schema mismatch: {data.get('schema')!r}")
    if data.get("status") != "budget_unavailable" or data.get("exit_code") != 77:
        fail(
            f"{path}: expected budget_unavailable/77 for uncertified sidecar, got "
            f"status={data.get('status')!r} exit={data.get('exit_code')!r}"
        )
    budget = ((data.get("budgets") or {}).get("gas") or {})
    if budget.get("limit") != 100000:
        fail(f"{path}: expected original gas limit on uncertified sidecar, got {budget!r}")
    if budget.get("enforcement_profile") != "avm-sidecar":
        fail(f"{path}: expected avm-sidecar enforcement profile, got {budget!r}")
    if budget.get("enforced") is not False:
        fail(f"{path}: uncertified AVM sidecar gas must not be marked enforced, got {budget!r}")
    if budget.get("reason") != "AVM canonical sidecar gas was not certified":
        fail(f"{path}: uncertified AVM sidecar gas reason mismatch, got {budget!r}")
    sidecar = data.get("avm_canonical_sidecar_gas") or {}
    if sidecar.get("schema") != "oren.avm-canonical-sidecar-gas.v0":
        fail(f"{path}: AVM sidecar schema mismatch: {sidecar!r}")
    if sidecar.get("status") != "unavailable":
        fail(f"{path}: expected unavailable AVM sidecar status, got {sidecar!r}")
    if sidecar.get("certification_status") != "unavailable":
        fail(f"{path}: expected unavailable certification status, got {sidecar!r}")
    if sidecar.get("package_policy_may_use") is not False:
        fail(f"{path}: uncertified sidecar must not be package-policy usable, got {sidecar!r}")
    if set(sidecar.get("certification_failure_reasons") or []) != set(expected_reasons):
        fail(f"{path}: unexpected uncertified sidecar failure reasons, got {sidecar!r}")
    if sidecar.get("certification_warnings") != []:
        fail(f"{path}: uncertified sidecar should not carry warnings, got {sidecar!r}")
    if sidecar.get("test_injection") != expected_injection:
        fail(f"{path}: expected auditable verifier injection {expected_injection!r}, got {sidecar!r}")
    return data, budget, sidecar

gas_sidecar_exit_mismatch = load(gas_sidecar_exit_mismatch_path)
if gas_sidecar_exit_mismatch.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_exit_mismatch_path}: schema mismatch: {gas_sidecar_exit_mismatch.get('schema')!r}")
if gas_sidecar_exit_mismatch.get("status") != "budget_unavailable" or gas_sidecar_exit_mismatch.get("exit_code") != 77:
    fail(
        f"{gas_sidecar_exit_mismatch_path}: expected budget_unavailable/77 for exit-mismatched sidecar, got "
        f"status={gas_sidecar_exit_mismatch.get('status')!r} exit={gas_sidecar_exit_mismatch.get('exit_code')!r}"
    )
gas_sidecar_exit_mismatch_budget = ((gas_sidecar_exit_mismatch.get("budgets") or {}).get("gas") or {})
if gas_sidecar_exit_mismatch_budget.get("limit") != 100000:
    fail(f"{gas_sidecar_exit_mismatch_path}: expected original gas limit on exit-mismatched sidecar, got {gas_sidecar_exit_mismatch_budget!r}")
if gas_sidecar_exit_mismatch_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_sidecar_exit_mismatch_path}: expected avm-sidecar enforcement profile, got {gas_sidecar_exit_mismatch_budget!r}")
if gas_sidecar_exit_mismatch_budget.get("enforced") is not False:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-mismatched AVM sidecar gas must not be marked enforced, got {gas_sidecar_exit_mismatch_budget!r}")
if gas_sidecar_exit_mismatch_budget.get("reason") != "AVM canonical sidecar gas was not certified":
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-mismatched AVM sidecar gas reason mismatch, got {gas_sidecar_exit_mismatch_budget!r}")
sidecar_exit_mismatch = gas_sidecar_exit_mismatch.get("avm_canonical_sidecar_gas") or {}
if sidecar_exit_mismatch.get("schema") != "oren.avm-canonical-sidecar-gas.v0":
    fail(f"{gas_sidecar_exit_mismatch_path}: AVM sidecar schema mismatch: {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("status") != "unavailable":
    fail(f"{gas_sidecar_exit_mismatch_path}: expected unavailable AVM sidecar status, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("certification_status") != "unavailable":
    fail(f"{gas_sidecar_exit_mismatch_path}: expected unavailable certification status, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("package_policy_may_use") is not False:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-mismatched sidecar must not be package-policy usable, got {sidecar_exit_mismatch!r}")
exit_mismatch_reasons = set(sidecar_exit_mismatch.get("certification_failure_reasons") or [])
if exit_mismatch_reasons != {"exit_code_mismatch", "sidecar_exit_nonzero"}:
    fail(f"{gas_sidecar_exit_mismatch_path}: expected only exit_code_mismatch/sidecar_exit_nonzero reasons, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("certification_warnings") != []:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-code-only test injection should not create sidecar warnings, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("test_injection") != "exit_code":
    fail(f"{gas_sidecar_exit_mismatch_path}: expected auditable exit_code verifier injection, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("same_run_stdout_equal") is not True or sidecar_exit_mismatch.get("same_run_stderr_equal") is not True:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-code-only sidecar should preserve stdout/stderr parity, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("same_run_exit_code_equal") is not False:
    fail(f"{gas_sidecar_exit_mismatch_path}: expected explicit exit-code mismatch evidence, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("native_exit_code") != 0 or sidecar_exit_mismatch.get("sidecar_exit_code") != 42:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-code injection should expose native exit 0 and sidecar exit 42, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("native_stdout_sha256") != sidecar_exit_mismatch.get("sidecar_stdout_sha256"):
    fail(f"{gas_sidecar_exit_mismatch_path}: stdout hashes should still match for exit-code mismatch, got {sidecar_exit_mismatch!r}")
if sidecar_exit_mismatch.get("native_stderr_sha256") != sidecar_exit_mismatch.get("sidecar_stderr_sha256"):
    fail(f"{gas_sidecar_exit_mismatch_path}: stderr hashes should still match for exit-code mismatch, got {sidecar_exit_mismatch!r}")
exit_mismatch_surface = sidecar_exit_mismatch.get("gas_surface") or {}
if exit_mismatch_surface.get("id") != "avm_opcode_cost_v0" or exit_mismatch_surface.get("unit_scope") != "avm_canonical":
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-mismatched sidecar should preserve AVM canonical surface evidence, got {sidecar_exit_mismatch!r}")
if int(sidecar_exit_mismatch.get("gas_executed") or 0) <= 0:
    fail(f"{gas_sidecar_exit_mismatch_path}: exit-mismatched sidecar should distinguish exit failure from missing gas evidence, got {sidecar_exit_mismatch!r}")

_, _, sidecar_missing_surface = assert_sidecar_unavailable_run(
    gas_sidecar_missing_surface_path,
    ["missing_or_noncanonical_avm_gas_surface"],
    "drop_gas_surface",
)
if sidecar_missing_surface.get("same_run_stdout_equal") is not True or sidecar_missing_surface.get("same_run_stderr_equal") is not True:
    fail(f"{gas_sidecar_missing_surface_path}: missing-surface sidecar should preserve stdout/stderr parity, got {sidecar_missing_surface!r}")
if sidecar_missing_surface.get("same_run_exit_code_equal") is not True:
    fail(f"{gas_sidecar_missing_surface_path}: missing-surface sidecar should preserve exit parity, got {sidecar_missing_surface!r}")
if sidecar_missing_surface.get("native_exit_code") != 0 or sidecar_missing_surface.get("sidecar_exit_code") != 0:
    fail(f"{gas_sidecar_missing_surface_path}: missing-surface sidecar should expose zero native/sidecar exits, got {sidecar_missing_surface!r}")
if sidecar_missing_surface.get("gas_surface") is not None:
    fail(f"{gas_sidecar_missing_surface_path}: missing-surface injection should remove canonical gas surface, got {sidecar_missing_surface!r}")
if int(sidecar_missing_surface.get("gas_executed") or 0) <= 0:
    fail(f"{gas_sidecar_missing_surface_path}: missing-surface sidecar should distinguish metadata failure from missing gas execution, got {sidecar_missing_surface!r}")

_, _, sidecar_zero_gas = assert_sidecar_unavailable_run(
    gas_sidecar_zero_gas_path,
    ["missing_or_nonpositive_avm_gas"],
    "zero_gas",
)
if sidecar_zero_gas.get("same_run_stdout_equal") is not True or sidecar_zero_gas.get("same_run_stderr_equal") is not True:
    fail(f"{gas_sidecar_zero_gas_path}: zero-gas sidecar should preserve stdout/stderr parity, got {sidecar_zero_gas!r}")
if sidecar_zero_gas.get("same_run_exit_code_equal") is not True:
    fail(f"{gas_sidecar_zero_gas_path}: zero-gas sidecar should preserve exit parity, got {sidecar_zero_gas!r}")
if sidecar_zero_gas.get("native_exit_code") != 0 or sidecar_zero_gas.get("sidecar_exit_code") != 0:
    fail(f"{gas_sidecar_zero_gas_path}: zero-gas sidecar should expose zero native/sidecar exits, got {sidecar_zero_gas!r}")
zero_gas_surface = sidecar_zero_gas.get("gas_surface") or {}
if zero_gas_surface.get("id") != "avm_opcode_cost_v0" or zero_gas_surface.get("unit_scope") != "avm_canonical":
    fail(f"{gas_sidecar_zero_gas_path}: zero-gas sidecar should preserve canonical surface metadata, got {sidecar_zero_gas!r}")
if sidecar_zero_gas.get("gas_executed") is None or int(sidecar_zero_gas.get("gas_executed")) != 0:
    fail(f"{gas_sidecar_zero_gas_path}: zero-gas injection should report zero AVM canonical gas, got {sidecar_zero_gas!r}")

gas_sidecar_timeout = load(gas_sidecar_timeout_path)
if gas_sidecar_timeout.get("schema") != "oren.native-package-policy-run.v0":
    fail(f"{gas_sidecar_timeout_path}: schema mismatch: {gas_sidecar_timeout.get('schema')!r}")
if gas_sidecar_timeout.get("status") != "budget_unavailable" or gas_sidecar_timeout.get("exit_code") != 77:
    fail(
        f"{gas_sidecar_timeout_path}: expected budget_unavailable/77 for timed-out sidecar, got "
        f"status={gas_sidecar_timeout.get('status')!r} exit={gas_sidecar_timeout.get('exit_code')!r}"
    )
gas_sidecar_timeout_budget = ((gas_sidecar_timeout.get("budgets") or {}).get("gas") or {})
if gas_sidecar_timeout_budget.get("enforced") is not False or gas_sidecar_timeout_budget.get("enforcement_profile") != "avm-sidecar":
    fail(f"{gas_sidecar_timeout_path}: timed-out AVM sidecar gas must not be marked enforced, got {gas_sidecar_timeout_budget!r}")
if gas_sidecar_timeout_budget.get("reason") != "AVM canonical sidecar gas was not certified":
    fail(f"{gas_sidecar_timeout_path}: timed-out AVM sidecar gas reason mismatch, got {gas_sidecar_timeout_budget!r}")
sidecar_timeout = gas_sidecar_timeout.get("avm_canonical_sidecar_gas") or {}
if sidecar_timeout.get("schema") != "oren.avm-canonical-sidecar-gas.v0":
    fail(f"{gas_sidecar_timeout_path}: AVM sidecar schema mismatch: {sidecar_timeout!r}")
if sidecar_timeout.get("status") != "timeout" or sidecar_timeout.get("certification_status") != "timeout":
    fail(f"{gas_sidecar_timeout_path}: expected timeout certification status, got {sidecar_timeout!r}")
if sidecar_timeout.get("package_policy_may_use") is not False:
    fail(f"{gas_sidecar_timeout_path}: timed-out sidecar must not be package-policy usable, got {sidecar_timeout!r}")
if sidecar_timeout.get("certification_failure_reasons") != ["timeout"]:
    fail(f"{gas_sidecar_timeout_path}: expected timeout failure reason, got {sidecar_timeout!r}")
if sidecar_timeout.get("certification_warnings") != []:
    fail(f"{gas_sidecar_timeout_path}: timeout sidecar should not carry warnings, got {sidecar_timeout!r}")
if sidecar_timeout.get("test_injection") != "timeout":
    fail(f"{gas_sidecar_timeout_path}: expected auditable timeout verifier injection, got {sidecar_timeout!r}")
if sidecar_timeout.get("package_policy_may_use_reason") != "avm_canonical_sidecar_timeout":
    fail(f"{gas_sidecar_timeout_path}: timeout sidecar reason mismatch, got {sidecar_timeout!r}")
PY

if [[ "$deny_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy runner to reject missing TIME domain" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
fi
grep -Eiq 'capsule|requires domain|TIME' "$deny_out" "$deny_err" || {
  echo "ERROR: missing native capsule domain diagnostic" >&2
  cat "$deny_out" >&2 || true
  cat "$deny_err" >&2 || true
  exit 1
}

if [[ "$gas_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy gas budget to reject over-budget run" >&2
  cat "$gas_fail_out" >&2 || true
  cat "$gas_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native gas budget exceeded" "$gas_fail_out" "$gas_fail_err" || {
  echo "ERROR: missing native gas budget diagnostic" >&2
  cat "$gas_fail_out" >&2 || true
  cat "$gas_fail_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy AVM sidecar gas budget to reject over-budget run" >&2
  cat "$gas_sidecar_fail_out" >&2 || true
  cat "$gas_sidecar_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar gas budget exceeded" "$gas_sidecar_fail_out" "$gas_sidecar_fail_err" || {
  echo "ERROR: missing AVM sidecar gas budget diagnostic" >&2
  cat "$gas_sidecar_fail_out" >&2 || true
  cat "$gas_sidecar_fail_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_uncertified_rc" -eq 0 ]]; then
  echo "ERROR: expected uncertified AVM sidecar evidence to fail closed" >&2
  cat "$gas_sidecar_uncertified_out" >&2 || true
  cat "$gas_sidecar_uncertified_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar gas could not be certified for native run" "$gas_sidecar_uncertified_out" "$gas_sidecar_uncertified_err" || {
  echo "ERROR: missing uncertified AVM sidecar diagnostic" >&2
  cat "$gas_sidecar_uncertified_out" >&2 || true
  cat "$gas_sidecar_uncertified_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_stderr_warning_rc" -ne 0 ]]; then
  echo "ERROR: expected stderr-warning AVM sidecar evidence to remain usable" >&2
  cat "$gas_sidecar_stderr_warning_out" >&2 || true
  cat "$gas_sidecar_stderr_warning_err" >&2 || true
  exit 1
fi

if [[ "$gas_sidecar_exit_mismatch_rc" -eq 0 ]]; then
  echo "ERROR: expected exit-mismatched AVM sidecar evidence to fail closed" >&2
  cat "$gas_sidecar_exit_mismatch_out" >&2 || true
  cat "$gas_sidecar_exit_mismatch_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar gas could not be certified for native run" "$gas_sidecar_exit_mismatch_out" "$gas_sidecar_exit_mismatch_err" || {
  echo "ERROR: missing exit-mismatched AVM sidecar diagnostic" >&2
  cat "$gas_sidecar_exit_mismatch_out" >&2 || true
  cat "$gas_sidecar_exit_mismatch_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_missing_surface_rc" -eq 0 ]]; then
  echo "ERROR: expected missing-surface AVM sidecar evidence to fail closed" >&2
  cat "$gas_sidecar_missing_surface_out" >&2 || true
  cat "$gas_sidecar_missing_surface_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar gas could not be certified for native run" "$gas_sidecar_missing_surface_out" "$gas_sidecar_missing_surface_err" || {
  echo "ERROR: missing missing-surface AVM sidecar diagnostic" >&2
  cat "$gas_sidecar_missing_surface_out" >&2 || true
  cat "$gas_sidecar_missing_surface_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_zero_gas_rc" -eq 0 ]]; then
  echo "ERROR: expected zero-gas AVM sidecar evidence to fail closed" >&2
  cat "$gas_sidecar_zero_gas_out" >&2 || true
  cat "$gas_sidecar_zero_gas_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar gas could not be certified for native run" "$gas_sidecar_zero_gas_out" "$gas_sidecar_zero_gas_err" || {
  echo "ERROR: missing zero-gas AVM sidecar diagnostic" >&2
  cat "$gas_sidecar_zero_gas_out" >&2 || true
  cat "$gas_sidecar_zero_gas_err" >&2 || true
  exit 1
}

if [[ "$gas_sidecar_timeout_rc" -eq 0 ]]; then
  echo "ERROR: expected timed-out AVM sidecar evidence to fail closed" >&2
  cat "$gas_sidecar_timeout_out" >&2 || true
  cat "$gas_sidecar_timeout_err" >&2 || true
  exit 1
fi
grep -Fq "package AVM canonical sidecar timed out" "$gas_sidecar_timeout_out" "$gas_sidecar_timeout_err" || {
  echo "ERROR: missing timed-out AVM sidecar diagnostic" >&2
  cat "$gas_sidecar_timeout_out" >&2 || true
  cat "$gas_sidecar_timeout_err" >&2 || true
  exit 1
}

if [[ "$gas_profile_bad_rc" -eq 0 ]]; then
  echo "ERROR: expected invalid native package-policy gas profile to fail closed" >&2
  cat "$gas_profile_bad_out" >&2 || true
  cat "$gas_profile_bad_err" >&2 || true
  exit 1
fi
grep -Fq "OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE must be native-stmt, avm-sidecar, or auto" "$gas_profile_bad_out" "$gas_profile_bad_err" || {
  echo "ERROR: missing invalid gas profile diagnostic" >&2
  cat "$gas_profile_bad_out" >&2 || true
  cat "$gas_profile_bad_err" >&2 || true
  exit 1
}

if [[ "$gas_profile_avm_bad_rc" -eq 0 ]]; then
  echo "ERROR: expected AVM package-policy dispatch to reject native gas profile" >&2
  cat "$gas_profile_avm_bad_out" >&2 || true
  cat "$gas_profile_avm_bad_err" >&2 || true
  exit 1
fi
grep -Fq -- "--gas-profile applies only to --backend native" "$gas_profile_avm_bad_out" "$gas_profile_avm_bad_err" || {
  echo "ERROR: missing AVM gas profile rejection diagnostic" >&2
  cat "$gas_profile_avm_bad_out" >&2 || true
  cat "$gas_profile_avm_bad_err" >&2 || true
  exit 1
}

if [[ "$gas_stmt_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy statement gas budget to reject over-budget run" >&2
  cat "$gas_stmt_fail_out" >&2 || true
  cat "$gas_stmt_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native gas budget exceeded" "$gas_stmt_fail_out" "$gas_stmt_fail_err" || {
  echo "ERROR: missing native statement gas budget diagnostic" >&2
  cat "$gas_stmt_fail_out" >&2 || true
  cat "$gas_stmt_fail_err" >&2 || true
  exit 1
}

if [[ "$wall_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy wall budget to stop infinite loop" >&2
  cat "$wall_out" >&2 || true
  cat "$wall_err" >&2 || true
  exit 1
fi
grep -Fq "package native wall budget exceeded" "$wall_out" "$wall_err" || {
  echo "ERROR: missing native wall budget diagnostic" >&2
  cat "$wall_out" >&2 || true
  cat "$wall_err" >&2 || true
  exit 1
}

if [[ "$heap_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy heap budget to reject over-budget run" >&2
  cat "$heap_fail_out" >&2 || true
  cat "$heap_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native heap budget exceeded" "$heap_fail_out" "$heap_fail_err" || {
  echo "ERROR: missing native heap budget diagnostic" >&2
  cat "$heap_fail_out" >&2 || true
  cat "$heap_fail_err" >&2 || true
  exit 1
}

if [[ "$cpu_fail_rc" -eq 0 ]]; then
  echo "ERROR: expected native package-policy CPU budget to reject over-budget run" >&2
  cat "$cpu_fail_out" >&2 || true
  cat "$cpu_fail_err" >&2 || true
  exit 1
fi
grep -Fq "package native CPU budget exceeded" "$cpu_fail_out" "$cpu_fail_err" || {
  echo "ERROR: missing native CPU budget diagnostic" >&2
  cat "$cpu_fail_out" >&2 || true
  cat "$cpu_fail_err" >&2 || true
  exit 1
}

echo "native package policy runner verify OK"
