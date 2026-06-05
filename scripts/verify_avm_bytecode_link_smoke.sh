#!/usr/bin/env bash
set -euo pipefail

# Verify bytecode + OBX linking with a fast deterministic library/app pair.
# The full stdlib bundle path is still rolling and can be exercised explicitly
# with OREN_VERIFY_FULL_STDLIB_OBC=1.

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

mkdir -p build/tmp build/logs

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

ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/avm_obc_link_smoke_${ts}"
mkdir -p "$tmpdir"

lib_src="$tmpdir/lib.oren"
app_src="$tmpdir/app.oren"
undef_src="$tmpdir/lib_undef.oren"
lib_obc="$tmpdir/lib.obc"
app_obc="$tmpdir/app.obc"
undef_obc="$tmpdir/lib_undef.obc"
bad_obc="$tmpdir/truncated_string_const.obc"
lib_log="build/logs/avm_obc_link_smoke_lib.log"
app_log="build/logs/avm_obc_link_smoke_app.log"
run_log="build/logs/avm_obc_link_smoke_run.log"
undef_log="build/logs/avm_obc_link_smoke_undef.log"
bad_log="build/logs/avm_obc_link_smoke_bad.log"
rm -f "$lib_log" "$app_log" "$run_log" "$undef_log" "$bad_log" 2>/dev/null || true

cat >"$lib_src" <<'OREN'
fn lib_answer() {
    return 41
}
OREN

cat >"$app_src" <<'OREN'
fn main() {
    if lib_answer() + 1 != 42 {
        print("FAIL: linked answer")
        exit(7)
    }
    print("ok: avm obc link smoke")
}
OREN

cat >"$undef_src" <<'OREN'
fn calls_external_runtime_symbol() {
    return definitely_external_symbol()
}
OREN

echo "== build: tiny OBX library ==" >&2
"$COMPILER" build "$lib_src" --backend bytecode --obc-lib -o "$lib_obc" >"$lib_log" 2>&1
test -f "$lib_obc" || { echo "FAIL: build did not produce $lib_obc" >&2; tail -n 120 "$lib_log" >&2 || true; exit 3; }

echo "== build: app linked against tiny OBX library ==" >&2
"$COMPILER" build "$app_src" --backend bytecode --link-obc "$lib_obc" -o "$app_obc" >"$app_log" 2>&1
test -f "$app_obc" || { echo "FAIL: build did not produce $app_obc" >&2; tail -n 120 "$app_log" >&2 || true; exit 4; }

echo "== run: avm $app_obc ==" >&2
set +e
./avm "$app_obc" >"$run_log" 2>&1
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
  exit 5
}

echo "== build: OBX library with unresolved external relo ==" >&2
"$COMPILER" build "$undef_src" --backend bytecode --obc-lib -o "$undef_obc" >"$undef_log" 2>&1
test -f "$undef_obc" || { echo "FAIL: --obc-lib did not preserve unresolved relocs" >&2; tail -n 120 "$undef_log" >&2 || true; exit 6; }

echo "== reject: truncated linked OBC string constant ==" >&2
# Magic CD 0E, one constant, STRING tag, declared length 4, only one payload byte.
printf '\315\016\001\000\004\004\000a' >"$bad_obc"
set +e
"$COMPILER" build "$app_src" --backend bytecode --link-obc "$bad_obc" -o "$tmpdir/bad_app.obc" >"$bad_log" 2>&1
bad_rc=$?
set -e
if [[ "$bad_rc" -eq 0 ]]; then
  echo "FAIL: truncated linked OBC was accepted" >&2
  tail -n 120 "$bad_log" >&2 || true
  exit 8
fi
grep -F "truncated string constant" "$bad_log" >/dev/null || {
  echo "FAIL: missing truncated OBC diagnostic" >&2
  tail -n 120 "$bad_log" >&2 || true
  exit 9
}

if [[ "${OREN_VERIFY_FULL_STDLIB_OBC:-0}" == "1" ]]; then
  echo "== build: full stdlib bundle opt-in ==" >&2
  ./scripts/build_avm_plugins.sh
  stdlib_obc="build/plugins/stdlib_bundle.obc"
  test -f "$stdlib_obc" || { echo "FAIL: missing stdlib bundle: $stdlib_obc" >&2; exit 7; }
fi

echo "OK: avm bytecode link smoke passed" >&2
