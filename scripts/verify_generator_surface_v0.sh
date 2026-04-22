#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compiler="${1:-./oren_stage2}"
meta_compiler="${OREN_META_COMPILER:-./oren}"
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
  echo "verify_generator_surface_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/generator_surface_v0_${ts}"
log="build/logs/verify_generator_surface_v0_${ts}.log"
mkdir -p "$tmpdir"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

src="tests/fixtures/generator_surface_v0.oren"
blocked_src="tests/fixtures/generator_decl_blocked_nonfunction_var_v0.oren"
blocked_yield_from_src="tests/fixtures/generator_yield_from_blocked_missing_context_v0.oren"
bytecode_out="$tmpdir/generator_bytecode.obc"
meta_out="$tmpdir/generator_meta.json"
dump_out="$tmpdir/generator_dump.json"
bytecode_meta_out="$tmpdir/generator_bytecode_meta.json"
c_out="$tmpdir/generator_c"
native_out="$tmpdir/generator_native"

run_ok "$meta_compiler" meta "$src" --platform "$platform" -o "$meta_out"
run_ok "$meta_compiler" dump linked "$src" --platform "$platform" -o "$dump_out"
run_ok "$compiler" build "$src" \
  --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
run_ok python3 scripts/extract_obc_metadata.py "$bytecode_out" -o "$bytecode_meta_out"
run_ok ./avm "$bytecode_out"

run_ok "$compiler" build "$src" \
  --backend c --platform "$platform" --no-cache --no-debug -o "$c_out"
run_ok "$c_out"

run_ok "$compiler" build "$src" \
  --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"
run_ok "$native_out"

python3 - "$meta_out" "$dump_out" "$bytecode_meta_out" >>"$log" <<'PY'
import json
import sys

meta_path, dump_path, obc_path = sys.argv[1:4]
meta = json.load(open(meta_path, "r", encoding="utf-8"))
dump = json.load(open(dump_path, "r", encoding="utf-8"))
obc = json.load(open(obc_path, "r", encoding="utf-8"))["metadata"]

def get_func(payload, name, detail_key=False):
    key = "function_details" if detail_key else "functions"
    for item in payload[key]:
        if item.get("name") == name:
            return item
    raise SystemExit(f"missing function {name} in {key}")

expected_decl_surface = {
    "version": 13,
    "surface": "compiler_generator_object_v2",
    "syntax": "attr_oren.generator",
    "helper_api": "oren_generator_start_v2",
    "caller_api": "generator_handle_v2",
    "object_type": "generator",
    "yield_surface": "generator_context_v0",
    "iter_surface": "for_in_v0",
    "iter_api": "oren_iter_next_v0",
    "iter_resume": "implicit_nil_v0",
    "resume_surface": "next_send_close_delegate_yield_from_v4",
    "next_api": "oren_generator_next_v2",
    "send_api": "oren_generator_send_v2",
    "close_api": "oren_generator_close_v1",
    "delegate_api": "oren_generator_delegate_v1",
    "delegate_step_api": "oren_generator_delegate_step_v1",
    "close_mode": "mark_done_detach_live_task_v2",
    "delegate_mode": "inline_fresh_or_cached_started_step_v2",
    "delegate_source_syntaxes": ["yield_from_v0", "yield_from_in_context_v0"],
    "state_layout": "hidden_list_capsule_v2",
    "worker_context_type": "generator_context",
    "decl_forms": ["named_function_decl", "function_valued_var"],
}

def assert_decl(item, *, count, sites, context, explicit_value):
    if item["is_generator_decl"] is not True:
        raise SystemExit(f"{item['name']} missing is_generator_decl: {item!r}")
    if item["generator_decl_surface"] != expected_decl_surface:
        raise SystemExit(f"{item['name']} bad generator_decl_surface: {item['generator_decl_surface']!r}")
    if item["contains_yield_exchange"] is not True or item["yield_exchange_count"] != count:
        raise SystemExit(f"{item['name']} bad yield_exchange count: {item!r}")
    if item["yield_exchange_sites"] != sites:
        raise SystemExit(f"{item['name']} bad yield_exchange_sites: {item['yield_exchange_sites']!r}")
    surface = item["yield_exchange_surface"]
    if surface is None:
        raise SystemExit(f"{item['name']} missing yield_exchange_surface")
    if surface["version"] != 2:
        raise SystemExit(f"{item['name']} bad yield_exchange_surface version: {surface!r}")
    if surface["binding_kinds"] != ["generator_context"]:
        raise SystemExit(f"{item['name']} bad binding_kinds: {surface!r}")
    if surface["syntax_kinds"] != ["generator_decl"]:
        raise SystemExit(f"{item['name']} bad syntax_kinds: {surface!r}")
    if surface["consumer_kinds"] != [context]:
        raise SystemExit(f"{item['name']} bad consumer_kinds: {surface!r}")
    if surface["yield_value_observer"] != "generator_context" or surface["resume_value_source"] != "generator_context":
        raise SystemExit(f"{item['name']} bad generator context observer/source: {surface!r}")
    if surface["yield_channel_arg_index"] != -1 or surface["resume_channel_arg_index"] != -1 or surface["context_arg_index"] != 0 or surface["value_arg_index"] != 1:
        raise SystemExit(f"{item['name']} bad generator context arg indexes: {surface!r}")
    if len(surface["exchange_points"]) != count:
        raise SystemExit(f"{item['name']} bad exchange_points len: {surface!r}")
    for point in surface["exchange_points"]:
        if point["syntax"] != "generator_decl":
            raise SystemExit(f"{item['name']} bad point syntax: {point!r}")
        if point["context"] != context:
            raise SystemExit(f"{item['name']} bad point context: {point!r}")
        if point["binding"] != "generator_context":
            raise SystemExit(f"{item['name']} bad point binding: {point!r}")
        if point["explicit_value"] != explicit_value:
            raise SystemExit(f"{item['name']} bad point explicit_value: {point!r}")

for payload, detail_key in [(meta, False), (dump, True), (obc, False)]:
    assert_decl(
        get_func(payload, "decl_counter", detail_key),
        count=2,
        sites=[
            "tests/fixtures/generator_surface_v0.oren:115:20",
            "tests/fixtures/generator_surface_v0.oren:116:20",
        ],
        context="var_init",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_nil", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:122:5"],
        context="expr_stmt",
        explicit_value=False,
    )
    assert_decl(
        get_func(payload, "decl_collect", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:130:9"],
        context="expr_stmt",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_var_counter", detail_key),
        count=2,
        sites=[
            "tests/fixtures/generator_surface_v0.oren:138:20",
            "tests/fixtures/generator_surface_v0.oren:139:20",
        ],
        context="var_init",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_var_lambda", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:145:19"],
        context="var_init",
        explicit_value=True,
    )
    worker = get_func(payload, "counter_worker", detail_key)
    if worker["is_generator_decl"] is not False or worker["generator_decl_surface"] is not None:
        raise SystemExit(f"counter_worker should not be generator decl: {worker!r}")
    if worker["yield_exchange_surface"]["binding_kinds"] != ["generator_context"]:
        raise SystemExit(f"counter_worker should use generator context binding: {worker!r}")
    if worker["yield_exchange_surface"]["syntax_kinds"] != ["yield_in_context"]:
        raise SystemExit(f"counter_worker should use yield_in_context syntax: {worker!r}")
PY

blocked_log="$tmpdir/generator_decl_blocked_nonfunction_var.log"
echo "\$ $compiler build $blocked_src --backend bytecode --platform $platform --no-cache -o $tmpdir/blocked_nonfunction_var.obc" >>"$log"
if "$compiler" build "$blocked_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/blocked_nonfunction_var.obc" >>"$blocked_log" 2>&1; then
  cat "$blocked_log" >>"$log"
  echo "verify_generator_surface_v0: expected non-function generator var binding to fail" >&2
  exit 1
fi
cat "$blocked_log" >>"$log"
grep -F "@oren.generator on var requires function value" "$blocked_log" >/dev/null

blocked_yield_from_log="$tmpdir/generator_yield_from_blocked_missing_context.log"
echo "\$ $compiler build $blocked_yield_from_src --backend bytecode --platform $platform --no-cache -o $tmpdir/blocked_yield_from.obc" >>"$log"
if "$compiler" build "$blocked_yield_from_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/blocked_yield_from.obc" >>"$blocked_yield_from_log" 2>&1; then
  cat "$blocked_yield_from_log" >>"$log"
  echo "verify_generator_surface_v0: expected plain yield from without context to fail" >&2
  exit 1
fi
cat "$blocked_yield_from_log" >>"$log"
grep -F "yield from" "$blocked_yield_from_log" >/dev/null
grep -F "requires 'in co' outside @oren.generator declarations" "$blocked_yield_from_log" >/dev/null

echo "generator surface v0 verify OK" >>"$log"
echo "generator surface v0 verify OK"
