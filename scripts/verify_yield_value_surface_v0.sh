#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
platform="${OREN_PLATFORM:-}"
source scripts/verify_parallel_jobs.sh
native_build_timeout_secs="${OREN_VERIFY_NATIVE_BUILD_TIMEOUT_SECS:-180}"

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
  echo "verify_yield_value_surface_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/yield_value_surface_v0_${ts}"
log="build/logs/verify_yield_value_surface_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

src="tests/fixtures/yield_value_surface_v0.oren"
meta_out="$tmpdir/value.meta.json"
dump_out="$tmpdir/value.linked.json"
bytecode_out="$tmpdir/value_bytecode.obc"
bytecode_meta_out="$tmpdir/value_bytecode.meta.json"
c_out="$tmpdir/value_c"
native_out="$tmpdir/value_native"

run_ok "$compiler" meta "$src" --platform "$platform" -o "$meta_out"
run_ok "$compiler" dump linked "$src" --platform "$platform" -o "$dump_out"
run_ok env OREN_TRACE_BYTECODE_YIELD_LOWERING=1 "$compiler" build "$src" \
  --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
run_ok ./avm "$bytecode_out"
run_ok python3 scripts/extract_obc_metadata.py "$bytecode_out" -o "$bytecode_meta_out"

run_ok "$compiler" build "$src" \
  --backend c --platform "$platform" --no-cache --no-debug -o "$c_out"
run_ok "$c_out"

run_timeout_logged "$native_build_timeout_secs" "$compiler" build "$src" \
  --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"
run_ok "$native_out"

META_OUT="$meta_out" \
DUMP_OUT="$dump_out" \
BYTECODE_META_OUT="$bytecode_meta_out" \
python3 - >>"$log" <<'PY'
import json
import os


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def by_name(xs):
    return {item["name"]: item for item in xs}


def assert_plain(name, item):
    if item["contains_yield"] is not False:
        raise SystemExit(f"{name} should not contain bare yield: {item!r}")
    if item["yield_stmt_count"] != 0 or item["yield_stmt_sites"] != []:
        raise SystemExit(f"{name} unexpected bare yield metadata: {item!r}")
    if item["contains_yield_value"] is not False:
        raise SystemExit(f"{name} should not contain value yield: {item!r}")
    if item["yield_value_count"] != 0 or item["yield_value_sites"] != []:
        raise SystemExit(f"{name} unexpected value yield metadata: {item!r}")
    if item["yield_value_surface"] is not None:
        raise SystemExit(f"{name} should not expose yield_value_surface: {item!r}")
    if item["yield_lowering"] is not None:
        raise SystemExit(f"{name} should not expose yield_lowering: {item!r}")


def assert_value(name, item, site, explicit_value, context):
    if item["contains_yield"] is not False:
        raise SystemExit(f"{name} should not contain bare yield: {item!r}")
    if item["yield_stmt_count"] != 0 or item["yield_stmt_sites"] != []:
        raise SystemExit(f"{name} unexpected bare yield metadata: {item!r}")
    if item["yield_lowering"] is not None:
        raise SystemExit(f"{name} should not expose bare yield_lowering: {item!r}")
    if item["contains_yield_value"] is not True:
        raise SystemExit(f"{name} missing contains_yield_value: {item!r}")
    if item["yield_value_count"] != 1:
        raise SystemExit(f"{name} bad yield_value_count: {item!r}")
    if item["yield_value_sites"] != [site]:
        raise SystemExit(f"{name} bad yield_value_sites: {item!r}")
    surface = item["yield_value_surface"]
    if surface is None:
        raise SystemExit(f"{name} missing yield_value_surface")
    expected_surface = {
        "version": 1,
        "surface": "local_value_resume_v0",
        "resume_value_source": "local_expression",
        "supports_implicit_nil": True,
        "supports_explicit_value": True,
        "caller_resume_values": False,
        "generator_channel": False,
        "consumer_kinds": [context],
        "yield_points": [{"id": 0, "site": site, "explicit_value": explicit_value, "context": context}],
    }
    if surface != expected_surface:
        raise SystemExit(f"{name} bad yield_value_surface: expected {expected_surface!r}, got {surface!r}")


meta = by_name(load(os.environ["META_OUT"])["functions"])
dump = by_name(load(os.environ["DUMP_OUT"])["function_details"])
obc = by_name(load(os.environ["BYTECODE_META_OUT"])["metadata"]["functions"])

for payloads in (meta, dump, obc):
    assert_plain("add1", payloads["add1"])
    assert_value("yield_nil_expr", payloads["yield_nil_expr"], "tests/fixtures/yield_value_surface_v0.oren:6:14", False, "var_init")
    assert_value("yield_value_expr", payloads["yield_value_expr"], "tests/fixtures/yield_value_surface_v0.oren:12:13", True, "var_init")
    assert_value("return_yield_value", payloads["return_yield_value"], "tests/fixtures/yield_value_surface_v0.oren:17:12", True, "return_value")
    assert_value("call_arg_yield_value", payloads["call_arg_yield_value"], "tests/fixtures/yield_value_surface_v0.oren:21:17", True, "call_arg")
    assert_value("stmt_yield_value", payloads["stmt_yield_value"], "tests/fixtures/yield_value_surface_v0.oren:25:5", True, "expr_stmt")
    assert_plain("main", payloads["main"])

print("yield value metadata verified")
PY

echo "yield value surface v0 verify OK" >>"$log"
echo "yield value surface v0 verify OK"
