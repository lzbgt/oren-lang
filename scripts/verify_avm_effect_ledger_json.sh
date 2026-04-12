#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP="build/tmp/verify-avm-effect-ledger-json"
LOG_DIR="build/logs"
mkdir -p "$TMP" "$LOG_DIR"

build_obc() {
  local src="$1"
  local out="$2"
  local log="$3"
  ./oren build "$src" --backend bytecode -o "$out" >"$log" 2>&1
}

record_obc="$TMP/test_time_rng_record_replay_mem.obc"
det_obc="$TMP/test_time_rng_deterministic.obc"
build_obc tests/avm/test_time_rng_record_replay_mem.oren "$record_obc" "$LOG_DIR/verify_avm_effect_ledger_json_record_build.log"
build_obc tests/avm/test_time_rng_deterministic.oren "$det_obc" "$LOG_DIR/verify_avm_effect_ledger_json_deterministic_build.log"

record_out="$TMP/record.out"
record_err="$TMP/record.err"
AVM_RECORD_MEM=1 \
AVM_LOG_BYTES=4096 \
AVM_TIMEOUT_MS=1000 \
  ./avm --print-run-json "$record_obc" >"$record_out" 2>"$record_err"

det_out="$TMP/deterministic_trace.out"
det_err="$TMP/deterministic_trace.err"
AVM_DETERMINISTIC=1 \
AVM_TIME_START_NS=123456 \
AVM_TIME_STEP_NS=7 \
AVM_RNG_SEED=42 \
AVM_TRACE_BYTES=4096 \
  ./avm --print-run-json --print-trace-bytes-hex "$det_obc" >"$det_out" 2>"$det_err"

small_log_out="$TMP/small_log.out"
small_log_err="$TMP/small_log.err"
set +e
AVM_RECORD_MEM=1 \
AVM_LOG_BYTES=4 \
  ./avm --print-run-json "$record_obc" >"$small_log_out" 2>"$small_log_err"
small_log_rc=$?
set -e
if [[ "$small_log_rc" -eq 0 ]]; then
  echo "ERROR: expected AVM_LOG_BYTES=4 to reject record-log header" >&2
  cat "$small_log_out" >&2 || true
  cat "$small_log_err" >&2 || true
  exit 1
fi
grep -Fq "AVM_LOG_BYTES too small for log header (need 8)" "$small_log_err" || {
  echo "ERROR: missing small-log header-budget diagnostic" >&2
  cat "$small_log_out" >&2 || true
  cat "$small_log_err" >&2 || true
  exit 1
}

python3 - "$record_out" "$det_out" <<'PY'
import json
import sys
from pathlib import Path

def load_run(path_s):
    path = Path(path_s)
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith("{") and '"schema":"avm.run.v1"' in line:
            return json.loads(line)
    raise SystemExit(f"missing avm.run.v1 JSON in {path}")

record = load_run(sys.argv[1])
if record.get("schema") != "avm.run.v1":
    raise SystemExit("record run JSON schema mismatch")
ledger = record.get("effect_ledger_summary")
if not isinstance(ledger, dict):
    raise SystemExit("record run missing effect_ledger_summary")
if ledger.get("schema") != "oren.effect-ledger-summary.v0":
    raise SystemExit("effect ledger summary schema mismatch")
if ledger.get("backend") != "bytecode" or ledger.get("runtime_profile") != "avm":
    raise SystemExit("effect ledger summary runtime mismatch")
if ledger.get("determinism_grade") != "replayable-host":
    raise SystemExit("record run should report replayable-host summary grade")
if ledger.get("determinism", {}).get("enabled") is not False:
    raise SystemExit("record run should report host determinism mode")
record_info = ledger.get("record", {})
if record_info.get("enabled") is not True or record_info.get("sink") != "mem":
    raise SystemExit(f"unexpected record surface: {record_info}")
if int(record_info.get("bytes", 0)) <= 8:
    raise SystemExit(f"expected record log bytes beyond header, got {record_info}")
replay_info = ledger.get("replay", {})
if replay_info.get("enabled") is not False or replay_info.get("source") != "none":
    raise SystemExit(f"unexpected replay surface: {replay_info}")
budgets = ledger.get("budgets", {})
if budgets.get("log_bytes", {}).get("limit") != 4096:
    raise SystemExit(f"expected log budget limit 4096, got {budgets.get('log_bytes')}")
if budgets.get("log_bytes", {}).get("used") != record_info.get("bytes"):
    raise SystemExit("record bytes should match ledger log byte usage")
if budgets.get("gas", {}).get("executed", 0) <= 0:
    raise SystemExit("expected positive gas execution count")
gas = budgets.get("gas", {})
if gas.get("kind") != "avm_opcode_cost_v0":
    raise SystemExit(f"expected AVM opcode gas kind, got {gas}")
surface = gas.get("surface", {})
if surface.get("schema") != "oren.gas-surface.v0" or surface.get("id") != "avm_opcode_cost_v0":
    raise SystemExit(f"expected AVM opcode gas surface, got {gas}")
if surface.get("unit") != "opcode_cost" or surface.get("granularity") != "opcode_dispatch":
    raise SystemExit(f"expected AVM opcode-dispatch gas surface unit, got {surface}")
if surface.get("unit_scope") != "avm_canonical" or surface.get("runtime_path_aware") is not True:
    raise SystemExit(f"expected runtime-path-aware AVM canonical gas surface, got {surface}")
if surface.get("cross_arch_comparable") is not True or surface.get("conversion_ready") is not True:
    raise SystemExit(f"expected conversion-ready AVM canonical gas surface, got {surface}")
if surface.get("avm_canonical") is not True:
    raise SystemExit(f"expected AVM canonical gas surface marker, got {surface}")
wall = budgets.get("wall_ms", {})
if wall.get("limit") != 1000:
    raise SystemExit(f"expected wall_ms limit 1000, got {wall}")
if int(wall.get("elapsed_ns", -1)) < 0:
    raise SystemExit(f"expected non-negative wall elapsed ns, got {wall}")

det = load_run(sys.argv[2])
det_ledger = det.get("effect_ledger_summary")
if not isinstance(det_ledger, dict):
    raise SystemExit("deterministic run missing effect_ledger_summary")
if det_ledger.get("determinism_grade") != "replayable-host":
    raise SystemExit("deterministic run should report replayable-host summary grade")
det_info = det_ledger.get("determinism", {})
if det_info.get("enabled") is not True:
    raise SystemExit(f"deterministic run should report deterministic mode: {det_info}")
if det_info.get("virtual_now_ns") != 123456 or det_info.get("virtual_step_ns") != 7:
    raise SystemExit(f"deterministic clock metadata mismatch: {det_info}")
trace_info = det_ledger.get("budgets", {}).get("trace_bytes", {})
if trace_info.get("enabled") is not True or trace_info.get("limit") != 4096:
    raise SystemExit(f"unexpected trace bytes budget: {trace_info}")
if int(trace_info.get("used", 0)) <= 8:
    raise SystemExit(f"expected trace bytes beyond header, got {trace_info}")
if trace_info.get("truncated") is not False:
    raise SystemExit(f"trace should not be truncated: {trace_info}")
PY

echo "avm effect ledger JSON verify OK"
