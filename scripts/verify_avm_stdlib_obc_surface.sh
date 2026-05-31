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

python3 ./scripts/verify_avm_stdlib_obc_surface.py \
  --compiler "$COMPILER" \
  --avm ./avm \
  --manifest tests/fixtures/avm_stdlib_obc_surface_manifest.json \
  --stdlib-obc "$stdlib_obc"
