#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-./oren}"
test_src="tests/native/test_quick_integration_native.oren"

uname_s="$(uname -s)"
uname_m="$(uname -m)"

os_key=""
case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac

arch_key=""
case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"

mkdir -p build/tmp build/logs

compiler_base="$(basename "$compiler")"
out="build/tmp/${compiler_base}_native_quick_integration"
log="build/logs/${compiler_base}_native_quick_integration.log"

echo "== native quick integration =="
echo "compiler=$compiler"
echo "platform=$platform"
echo "src=$test_src"
echo "out=$out"
echo "log=$log"

rm -f "$log" "$out" 2>/dev/null || true

"$compiler" build "$test_src" --backend native --platform "$platform" --debug -o "$out" >"$log" 2>&1
"$out" >>"$log" 2>&1

tail -n 5 "$log"
