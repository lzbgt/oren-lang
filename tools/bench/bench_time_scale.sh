#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OBC="build/bench_gas.obc"
GAS="${AVM_GAS_BENCH:-50000000}"

echo "== Building benchmark =="
mkdir -p build
./oren build tools/bench/bench_gas.oren --backend bytecode -o "$OBC" >/dev/null

echo "== Running benchmark =="
echo "  AVM_GAS=${GAS}"

# Run with a gas budget; bench program is infinite.
# Use the AVM host wall clock only for measurement; this is NOT consensus semantics.
set +e
out="$(AVM_GAS="$GAS" ./avm --print-run-json "$OBC" 2>/dev/null)"
rc=$?
set -e

# We expect a non-zero exit code because AVM_GAS should abort an infinite loop.
if [ "$rc" -eq 0 ]; then
  echo "WARNING: benchmark exited with code 0 (expected gas budget abort)." >&2
fi
echo "$out"

if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' "$out"
import json, sys
line = sys.argv[1].strip()
obj = json.loads(line)
gas = int(obj.get("gas_executed", 0))
elapsed = int(obj.get("wall_elapsed_ns", 0))
if gas <= 0 or elapsed <= 0:
  print("ERROR: missing gas_executed or wall_elapsed_ns", file=sys.stderr)
  sys.exit(2)
ns_per_gas = elapsed / gas
suggest = int(round(ns_per_gas))
print("")
print("== Calibration suggestion ==")
print(f"Measured: {ns_per_gas:.3f} ns/gas  ({gas} gas over {elapsed} ns)")
print(f"Suggested AVM_TIME_STEP_NS={suggest}  (virtual ns per gas unit)")
print("")
print("Notes:")
print("- This is host-dependent and only for 'virtual time feels like wall time' convenience.")
print("- Consensus / deterministic semantics depend on gas units, not this calibration.")
PY
else
  echo "python3 not found; cannot compute suggested AVM_TIME_STEP_NS automatically." >&2
  echo "You can parse the JSON above and compute: wall_elapsed_ns / gas_executed." >&2
fi
