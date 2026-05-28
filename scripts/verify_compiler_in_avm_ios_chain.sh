#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp

COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not executable: $COMPILER" >&2
  exit 2
fi
if [[ ! -x ./avm ]]; then
  echo "ERROR: ./avm not executable; run make avm" >&2
  exit 2
fi

tag="${OREN_VERIFY_TAG:-$(date +%Y%m%d_%H%M%S)}"
plugins_log="build/logs/build_avm_plugins_compiler_obc_${tag}.log"
harness_build_log="build/logs/build_compiler_in_avm_vfs_stdlib_obc_harness_${tag}.log"
harness_run_log="build/logs/run_compiler_in_avm_vfs_stdlib_obc_harness_${tag}.log"
harness_obc="build/tmp/compiler_in_avm_vfs_stdlib_obc_harness_${tag}.obc"

echo "== build AVM stdlib/compiler OBC plugins =="
OREN_COMPILER="$COMPILER" OREN_BUILD_COMPILER_OBC=1 ./scripts/build_avm_plugins.sh >"$plugins_log" 2>&1 || {
  echo "FAIL: plugin OBC build failed" >&2
  tail -n 160 "$plugins_log" >&2 || true
  exit 3
}

cp build/plugins/oren.obc build/oren_compiler.obc
cp build/plugins/stdlib_bundle.obc build/stdlib_bundle.obc

echo "== build compiler-in-AVM harness =="
"$COMPILER" build tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren \
  --backend bytecode -o "$harness_obc" >"$harness_build_log" 2>&1 || {
  echo "FAIL: harness bytecode build failed" >&2
  tail -n 160 "$harness_build_log" >&2 || true
  exit 4
}

echo "== run compiler-in-AVM harness =="
./avm "$harness_obc" >"$harness_run_log" 2>&1 || {
  echo "FAIL: compiler-in-AVM harness failed" >&2
  tail -n 220 "$harness_run_log" >&2 || true
  exit 5
}

if ! grep -q "compiler in avm vfs stdlib obc OK" "$harness_run_log"; then
  echo "FAIL: harness success marker missing" >&2
  tail -n 220 "$harness_run_log" >&2 || true
  exit 6
fi

echo "OK: compiler-in-AVM iOS embedding chain passed"
echo "logs:"
echo "  $plugins_log"
echo "  $harness_build_log"
echo "  $harness_run_log"
