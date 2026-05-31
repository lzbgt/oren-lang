#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/tmp build/logs

COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: missing compiler: $COMPILER" >&2
  exit 2
fi
if [[ ! -x ./avm ]]; then
  echo "ERROR: missing ./avm binary" >&2
  exit 2
fi

stdlib_obc="build/plugins/stdlib_bundle.obc"
OREN_COMPILER="$COMPILER" ./scripts/build_avm_plugins.sh

tag="$(date +%Y%m%d_%H%M%S)"
src="tests/fixtures/avm_stdlib_obc_surface_smoke.oren"
obc="build/tmp/avm_stdlib_obc_surface_${tag}.obc"
build_log="build/logs/build_avm_stdlib_obc_surface_${tag}.log"
run_log="build/logs/run_avm_stdlib_obc_surface_${tag}.log"

"$COMPILER" build "$src" --backend bytecode --stdlib-mode obc --stdlib-obc "$stdlib_obc" -o "$obc" >"$build_log" 2>&1
test -f "$obc" || {
  echo "FAIL: did not produce $obc" >&2
  tail -n 120 "$build_log" >&2 || true
  exit 3
}

set +e
./avm "$obc" >"$run_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: stdlib OBC surface smoke rc=$rc" >&2
  tail -n 160 "$run_log" >&2 || true
  exit "$rc"
fi

grep -F "avm stdlib obc surface OK" "$run_log" >/dev/null || {
  echo "FAIL: missing stdlib OBC surface marker" >&2
  tail -n 160 "$run_log" >&2 || true
  exit 4
}

echo "OK: AVM stdlib OBC surface smoke passed" >&2
