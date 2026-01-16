#!/usr/bin/env bash
set -euo pipefail

# Build AVM-facing `.obc` artifacts (rolling helper).
#
# Primary goal (today):
# - produce a precompiled stdlib bundle `.obc` that can be linked into other bytecode programs
#   without shipping stdlib sources
#
# Future goal:
# - also produce `oren.obc` (compiler-in-AVM) once the compiler-in-AVM entrypoint is stabilized
#
# Outputs:
# - build/plugins/stdlib_bundle.obc
#
# Optional:
# - OREN_BUILD_COMPILER_OBC=1 will attempt to build `oren.obc` (may be heavy/rolling).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/plugins build/logs

COMPILER="${OREN_COMPILER:-./oren_stage2}"
if [[ ! -x "$COMPILER" ]]; then
  echo "== ensure: stage2 compiler ($COMPILER) ==" >&2
  make stage2
fi

STDLIB_ROOT="${OREN_STDLIB_BUNDLE_ROOT:-lib/std/stdlib_avm.oren}"
if [[ ! -f "$STDLIB_ROOT" ]]; then
  echo "ERROR: missing stdlib bundle root: $STDLIB_ROOT" >&2
  exit 2
fi

stdlib_out="build/plugins/stdlib_bundle.obc"
stdlib_log="build/logs/build_stdlib_bundle_obc.log"
rm -f "$stdlib_out" "$stdlib_log" 2>/dev/null || true
echo "== build: stdlib bundle (.obc + OBX exports) ==" >&2
echo "compiler=$COMPILER" >&2
echo "root=$STDLIB_ROOT" >&2
echo "out=$stdlib_out" >&2
"$COMPILER" build "$STDLIB_ROOT" --backend bytecode -o "$stdlib_out" --obc-lib >"$stdlib_log" 2>&1
test -f "$stdlib_out" || { echo "FAIL: did not produce $stdlib_out" >&2; tail -n 120 "$stdlib_log" >&2 || true; exit 2; }

echo "OK: built $stdlib_out" >&2

if [[ "${OREN_BUILD_COMPILER_OBC:-0}" == "1" ]]; then
  # NOTE (rolling): building the full compiler to `.obc` can be slow/large. This is
  # an opt-in path intended for iterative bring-up of compiler-in-AVM.
  comp_src="${OREN_COMPILER_OBC_SRC:-oren.oren}"
  comp_out="build/plugins/oren.obc"
  comp_log="build/logs/build_oren_obc.log"
  rm -f "$comp_out" "$comp_log" 2>/dev/null || true
  echo "== build: compiler (.obc, self-contained) ==" >&2
  echo "src=$comp_src" >&2
  echo "out=$comp_out" >&2
  "$COMPILER" build "$comp_src" --backend bytecode -o "$comp_out" \
    --stdlib-mode obc --stdlib-obc "$stdlib_out" >"$comp_log" 2>&1
  test -f "$comp_out" || { echo "FAIL: did not produce $comp_out" >&2; tail -n 120 "$comp_log" >&2 || true; exit 3; }
  echo "OK: built $comp_out" >&2
fi
