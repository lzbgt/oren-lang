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

ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/astbin_malformed_decode_${ts}"
mkdir -p "$tmpdir"

src="$tmpdir/empty_u8_decode.oren"
bin="$tmpdir/empty_u8_decode_native"
log="build/logs/astbin_malformed_decode.log"
rm -f "$log"

cat >"$src" <<'OREN'
import astbin "../../../lib/compiler/astbin.oren"

fn main() {
    var bs = oren_u8_buf_new(0)
    astbin.astbin_decode(bs)
    print("FAIL: astbin accepted empty u8_buf")
    exit(2)
}
OREN

echo "== build: astbin empty u8 decode probe ==" >&2
"$COMPILER" build "$src" --backend native -o "$bin" >"$log" 2>&1

echo "== reject: empty u8 astbin decode ==" >&2
set +e
"$bin" >>"$log" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: astbin accepted empty u8_buf" >&2
  tail -n 120 "$log" >&2 || true
  exit 3
fi

grep -F "astbin: input must be non-empty bytes at off=0" "$log" >/dev/null || {
  echo "FAIL: missing expected astbin bounds diagnostic" >&2
  tail -n 120 "$log" >&2 || true
  exit 4
}

echo "OK: astbin malformed decode rejected empty u8_buf" >&2
