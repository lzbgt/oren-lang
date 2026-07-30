#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
platform="${OREN_PLATFORM:-}"

if [ -z "$platform" ]; then
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  case "$uname_s:$uname_m" in
    Darwin:arm64|Darwin:aarch64) platform="arm64-macos" ;;
    Darwin:x86_64) platform="x64-macos" ;;
    Linux:arm64|Linux:aarch64) platform="arm64-linux" ;;
    Linux:x86_64|Linux:amd64) platform="x64-linux" ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) platform="x64-windows" ;;
  esac
fi

if [ -z "$platform" ]; then
  echo "verify_native_ir_validator: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
src="tests/fixtures/native_ir_validator_v0.oren"
log="build/logs/native_ir_validator_v0.log"
native_log="build/logs/native_ir_validator_v0_native.log"
bytecode_log="build/logs/native_ir_validator_v0_bytecode.log"

{
  echo "compiler=$compiler"
  echo "platform=$platform"
  echo "source=$src"
} >"$log"

echo "== bytecode: native IR validator ==" >>"$log"
"$compiler" test "$src" --backend bytecode --platform "$platform" --no-cache >"$bytecode_log" 2>&1
cat "$bytecode_log" >>"$log"
grep -Fq "native_ir_validator_v0 OK" "$bytecode_log"

echo "== native: native IR validator ==" >>"$log"
"$compiler" test "$src" --backend native --platform "$platform" --no-cache --no-debug >"$native_log" 2>&1
cat "$native_log" >>"$log"
grep -Fq "native_ir_validator_v0 OK" "$native_log"

echo "OK: native IR v0 validator fixture passed on bytecode and native backends"
