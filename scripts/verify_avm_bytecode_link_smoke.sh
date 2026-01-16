#!/usr/bin/env bash
set -euo pipefail

# Verify bytecode + OBX linking by:
# - building stdlib bundle `.obc` with exports
# - building a tiny program in stdlib-obc mode (no std sources)
# - running it via the host `avm` interpreter
#
# This is a practical guardrail toward:
# - compiler-in-AVM (source -> `.obc` in a sandbox universe)
# - iOS-safe plugin workflows (no host toolchain / no std sources shipped)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin bash
need_bin grep
need_bin tail

mkdir -p build/tmp build/logs build/plugins

COMPILER="${OREN_COMPILER:-./oren_stage2}"
if [[ ! -x "$COMPILER" ]]; then
  echo "== ensure: stage2 compiler ($COMPILER) ==" >&2
  make stage2
fi

if [[ ! -x ./avm ]]; then
  echo "ERROR: missing ./avm binary (expected at repo root)." >&2
  echo "Hint: build it via the repo Makefile/host build workflow, then re-run this script." >&2
  exit 2
fi

echo "== build: plugins (stdlib bundle) ==" >&2
./scripts/build_avm_plugins.sh

stdlib_obc="build/plugins/stdlib_bundle.obc"
test -f "$stdlib_obc" || { echo "FAIL: missing stdlib bundle: $stdlib_obc" >&2; exit 2; }

src="tests/fixtures/avm_obc_link_smoke.oren"
out="build/tmp/avm_obc_link_smoke.obc"
log="build/logs/avm_obc_link_smoke_build.log"
run_log="build/logs/avm_obc_link_smoke_run.log"
rm -f "$out" "$log" "$run_log" 2>/dev/null || true

echo "== build: bytecode app (stdlib-mode obc; no std sources) ==" >&2
"$COMPILER" build "$src" --backend bytecode -o "$out" \
  --stdlib-mode obc --stdlib-obc "$stdlib_obc" >"$log" 2>&1
test -f "$out" || { echo "FAIL: build did not produce $out" >&2; tail -n 120 "$log" >&2 || true; exit 3; }

echo "== run: avm $out ==" >&2
set +e
./avm "$out" >"$run_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: avm run rc=$rc" >&2
  tail -n 200 "$run_log" >&2 || true
  exit "$rc"
fi

grep -F "ok: avm obc link smoke" "$run_log" >/dev/null || {
  echo "FAIL: missing expected output marker" >&2
  tail -n 200 "$run_log" >&2 || true
  exit 4
}

echo "OK: avm bytecode link smoke passed" >&2

