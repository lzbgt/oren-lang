#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
meta_compiler="${OREN_META_COMPILER:-./oren}"
platform="${OREN_PLATFORM:-}"
source scripts/verify_parallel_jobs.sh

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
  echo "verify_yield_exchange_surface_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/yield_exchange_surface_v0_${ts}"
log="build/logs/verify_yield_exchange_surface_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

src="tests/fixtures/yield_exchange_surface_v0.oren"
meta_out="$tmpdir/exchange.meta.json"
dump_out="$tmpdir/exchange.linked.json"
bytecode_out="$tmpdir/exchange_bytecode.obc"
bytecode_meta_out="$tmpdir/exchange_bytecode.meta.json"
c_out="$tmpdir/exchange_c"
native_out="$tmpdir/exchange_native"

run_ok "$meta_compiler" meta "$src" --platform "$platform" -o "$meta_out"
run_ok "$meta_compiler" dump linked "$src" --platform "$platform" -o "$dump_out"

run_bytecode() {
  run_logged "$compiler" build "$src" \
    --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
  run_timeout_logged 20 ./avm "$bytecode_out"
  run_logged python3 scripts/extract_obc_metadata.py "$bytecode_out" -o "$bytecode_meta_out"
}

run_c() {
  run_logged "$compiler" build "$src" \
    --backend c --platform "$platform" --no-cache --no-debug -o "$c_out"
  run_timeout_logged 20 "$c_out"
}

run_native() {
  run_logged "$compiler" build "$src" \
    --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"
  run_timeout_logged 20 "$native_out"
}

verify_parallel_start bytecode run_bytecode
verify_parallel_start c run_c
verify_parallel_start native run_native
verify_parallel_wait "$log"

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
    if item["contains_yield"] is not False or item["yield_stmt_count"] != 0 or item["yield_stmt_sites"] != []:
        raise SystemExit(f"{name} unexpected bare yield metadata: {item!r}")
    if item["contains_yield_value"] is not False or item["yield_value_count"] != 0 or item["yield_value_sites"] != []:
        raise SystemExit(f"{name} unexpected value-yield metadata: {item!r}")
    if item["contains_yield_exchange"] is not False:
        raise SystemExit(f"{name} unexpected yield exchange metadata: {item!r}")
    if item["yield_exchange_count"] != 0 or item["yield_exchange_sites"] != []:
        raise SystemExit(f"{name} unexpected yield exchange site metadata: {item!r}")
    if item["yield_value_surface"] is not None or item["yield_exchange_surface"] is not None or item["yield_lowering"] is not None:
        raise SystemExit(f"{name} unexpected yield surface metadata: {item!r}")


def assert_exchange(name, item, site, context, syntax, explicit_value, binding):
    if item["contains_yield"] is not False or item["yield_stmt_count"] != 0 or item["yield_stmt_sites"] != []:
        raise SystemExit(f"{name} unexpected bare yield metadata: {item!r}")
    if item["contains_yield_value"] is not False or item["yield_value_count"] != 0 or item["yield_value_sites"] != []:
        raise SystemExit(f"{name} unexpected value-yield metadata: {item!r}")
    if item["yield_value_surface"] is not None:
        raise SystemExit(f"{name} unexpected value-yield surface: {item!r}")
    if item["yield_lowering"] is not None:
        raise SystemExit(f"{name} unexpected bare-yield lowering surface: {item!r}")
    if item["contains_yield_exchange"] is not True:
        raise SystemExit(f"{name} missing contains_yield_exchange: {item!r}")
    if item["yield_exchange_count"] != 1:
        raise SystemExit(f"{name} bad yield_exchange_count: {item!r}")
    if item["yield_exchange_sites"] != [site]:
        raise SystemExit(f"{name} bad yield_exchange_sites: {item!r}")
    surface = item["yield_exchange_surface"]
    if surface is None:
        raise SystemExit(f"{name} missing yield_exchange_surface")
    if binding == "explicit_channel_pair":
        observer = "explicit_channel_arg"
        resume_source = "explicit_channel_arg"
        yield_idx = 0
        resume_idx = 1
        context_idx = -1
        value_idx = 2
    elif binding == "generator_context":
        observer = "generator_context"
        resume_source = "generator_context"
        yield_idx = -1
        resume_idx = -1
        context_idx = 0
        value_idx = 1
    else:
        raise SystemExit(f"unknown binding {binding!r}")
    expected_surface = {
        "version": 2,
        "surface": "channel_resume_v0",
        "yield_value_observer": observer,
        "resume_value_source": resume_source,
        "caller_resume_values": True,
        "generator_channel": True,
        "yield_channel_arg_index": yield_idx,
        "resume_channel_arg_index": resume_idx,
        "context_arg_index": context_idx,
        "value_arg_index": value_idx,
        "binding_kinds": [binding],
        "syntax_kinds": [syntax],
        "consumer_kinds": [context],
        "exchange_points": [{"id": 0, "site": site, "context": context, "syntax": syntax, "binding": binding, "explicit_value": explicit_value}],
    }
    if surface != expected_surface:
        raise SystemExit(f"{name} bad yield_exchange_surface: expected {expected_surface!r}, got {surface!r}")


meta = by_name(load(os.environ["META_OUT"])["functions"])
dump = by_name(load(os.environ["DUMP_OUT"])["function_details"])
obc = by_name(load(os.environ["BYTECODE_META_OUT"])["metadata"]["functions"])

for payloads in (meta, dump, obc):
    assert_plain("add1_exchange", payloads["add1_exchange"])
    assert_exchange("exchange_var", payloads["exchange_var"], "tests/fixtures/yield_exchange_surface_v0.oren:6:38", "var_init", "helper_call", True, "explicit_channel_pair")
    assert_exchange("exchange_return", payloads["exchange_return"], "tests/fixtures/yield_exchange_surface_v0.oren:11:31", "return_value", "helper_call", True, "explicit_channel_pair")
    assert_exchange("exchange_call_arg", payloads["exchange_call_arg"], "tests/fixtures/yield_exchange_surface_v0.oren:15:45", "call_arg", "helper_call", True, "explicit_channel_pair")
    assert_exchange("exchange_stmt", payloads["exchange_stmt"], "tests/fixtures/yield_exchange_surface_v0.oren:19:24", "expr_stmt", "helper_call", True, "explicit_channel_pair")
    assert_exchange("exchange_syntax_var", payloads["exchange_syntax_var"], "tests/fixtures/yield_exchange_surface_v0.oren:24:19", "var_init", "yield_in_channels", True, "explicit_channel_pair")
    assert_exchange("exchange_syntax_return", payloads["exchange_syntax_return"], "tests/fixtures/yield_exchange_surface_v0.oren:29:12", "return_value", "yield_in_channels", True, "explicit_channel_pair")
    assert_exchange("exchange_syntax_call_arg", payloads["exchange_syntax_call_arg"], "tests/fixtures/yield_exchange_surface_v0.oren:33:26", "call_arg", "yield_in_channels", True, "explicit_channel_pair")
    assert_exchange("exchange_syntax_stmt", payloads["exchange_syntax_stmt"], "tests/fixtures/yield_exchange_surface_v0.oren:37:5", "expr_stmt", "yield_in_channels", True, "explicit_channel_pair")
    assert_exchange("exchange_syntax_nil", payloads["exchange_syntax_nil"], "tests/fixtures/yield_exchange_surface_v0.oren:42:19", "var_init", "yield_in_channels", False, "explicit_channel_pair")
    assert_exchange("exchange_context_var", payloads["exchange_context_var"], "tests/fixtures/yield_exchange_surface_v0.oren:49:19", "var_init", "yield_in_context", True, "generator_context")
    assert_exchange("exchange_context_return", payloads["exchange_context_return"], "tests/fixtures/yield_exchange_surface_v0.oren:56:12", "return_value", "yield_in_context", True, "generator_context")
    assert_exchange("exchange_context_call_arg", payloads["exchange_context_call_arg"], "tests/fixtures/yield_exchange_surface_v0.oren:62:26", "call_arg", "yield_in_context", True, "generator_context")
    assert_exchange("exchange_context_stmt", payloads["exchange_context_stmt"], "tests/fixtures/yield_exchange_surface_v0.oren:68:5", "expr_stmt", "yield_in_context", True, "generator_context")
    assert_exchange("exchange_context_nil", payloads["exchange_context_nil"], "tests/fixtures/yield_exchange_surface_v0.oren:75:19", "var_init", "yield_in_context", False, "generator_context")
    assert_exchange("exchange_context_bad", payloads["exchange_context_bad"], "tests/fixtures/yield_exchange_surface_v0.oren:80:12", "return_value", "yield_in_context", True, "generator_context")
    assert_plain("exchange_host_green_reply_after_yield", payloads["exchange_host_green_reply_after_yield"])
    assert_exchange("exchange_host_green_helper", payloads["exchange_host_green_helper"], "tests/fixtures/yield_exchange_surface_v0.oren:94:38", "var_init", "helper_call", True, "explicit_channel_pair")
    assert_exchange("exchange_host_green_syntax", payloads["exchange_host_green_syntax"], "tests/fixtures/yield_exchange_surface_v0.oren:104:19", "var_init", "yield_in_channels", True, "explicit_channel_pair")
    assert_plain("main", payloads["main"])

print("yield exchange metadata verified")
PY

echo "yield exchange surface v0 verify OK" >>"$log"
echo "yield exchange surface v0 verify OK"
