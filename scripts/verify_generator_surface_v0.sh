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
coroutine_alias_src="tests/fixtures/coroutine_decl_surface_v0.oren"
blocked_src="tests/fixtures/generator_decl_blocked_nonfunction_var_v0.oren"
coroutine_alias_blocked_src="tests/fixtures/coroutine_decl_blocked_nonfunction_var_v0.oren"
blocked_yield_from_src="tests/fixtures/generator_yield_from_blocked_missing_context_v0.oren"
blocked_defer_src="tests/fixtures/generator_defer_blocked_missing_context_v0.oren"
bytecode_out="$tmpdir/generator_bytecode.obc"
meta_out="$tmpdir/generator_meta.json"
dump_out="$tmpdir/generator_dump.json"
bytecode_meta_out="$tmpdir/generator_bytecode_meta.json"
c_out="$tmpdir/generator_c"
native_out="$tmpdir/generator_native"
coroutine_alias_bytecode_out="$tmpdir/coroutine_decl_bytecode.obc"
coroutine_alias_meta_out="$tmpdir/coroutine_decl_meta.json"
coroutine_alias_dump_out="$tmpdir/coroutine_decl_dump.json"
coroutine_alias_bytecode_meta_out="$tmpdir/coroutine_decl_bytecode_meta.json"
coroutine_alias_c_out="$tmpdir/coroutine_decl_c"
coroutine_alias_native_out="$tmpdir/coroutine_decl_native"

run_ok "$meta_compiler" meta "$src" --platform "$platform" -o "$meta_out"
run_ok "$meta_compiler" dump linked "$src" --platform "$platform" -o "$dump_out"
run_ok "$meta_compiler" meta "$coroutine_alias_src" --platform "$platform" -o "$coroutine_alias_meta_out"
run_ok "$meta_compiler" dump linked "$coroutine_alias_src" --platform "$platform" -o "$coroutine_alias_dump_out"

run_generator_bytecode() {
  run_logged "$compiler" build "$src" \
    --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
  run_logged python3 scripts/extract_obc_metadata.py "$bytecode_out" -o "$bytecode_meta_out"
  run_logged ./avm "$bytecode_out"
}

run_generator_c() {
  run_logged "$compiler" build "$src" \
    --backend c --platform "$platform" --no-cache --no-debug -o "$c_out"
  run_logged "$c_out"
}

run_generator_native() {
  run_logged "$compiler" build "$src" \
    --backend native --platform "$platform" --no-cache --no-debug -o "$native_out"
  run_logged "$native_out"
}

run_coroutine_alias_bytecode() {
  run_logged "$compiler" build "$coroutine_alias_src" \
    --backend bytecode --platform "$platform" --no-cache -o "$coroutine_alias_bytecode_out"
  run_logged python3 scripts/extract_obc_metadata.py "$coroutine_alias_bytecode_out" -o "$coroutine_alias_bytecode_meta_out"
  run_logged ./avm "$coroutine_alias_bytecode_out"
}

run_coroutine_alias_c() {
  run_logged "$compiler" build "$coroutine_alias_src" \
    --backend c --platform "$platform" --no-cache --no-debug -o "$coroutine_alias_c_out"
  run_logged "$coroutine_alias_c_out"
}

run_coroutine_alias_native() {
  run_logged "$compiler" build "$coroutine_alias_src" \
    --backend native --platform "$platform" --no-cache --no-debug -o "$coroutine_alias_native_out"
  run_logged "$coroutine_alias_native_out"
}

verify_parallel_start generator_bytecode run_generator_bytecode
verify_parallel_start generator_c run_generator_c
verify_parallel_start generator_native run_generator_native
verify_parallel_start coroutine_alias_bytecode run_coroutine_alias_bytecode
verify_parallel_start coroutine_alias_c run_coroutine_alias_c
verify_parallel_start coroutine_alias_native run_coroutine_alias_native
verify_parallel_wait "$log"

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

def assert_no_hidden_generator_helpers(payload, detail_key=False):
    key = "function_details" if detail_key else "functions"
    for item in payload[key]:
        name = item["name"]
        if name.startswith("_oren_generator_") or name.startswith("oren_generator_"):
            raise SystemExit(f"unexpected hidden generator helper in {key}: {name!r}")

expected_decl_surface = {
    "version": 23,
    "surface": "compiler_generator_object_v7",
    "syntax": "attr_oren.generator",
    "helper_api": "oren_generator_start_v2",
    "caller_api": "generator_handle_v2",
    "object_type": "generator",
    "yield_surface": "generator_context_v0",
    "finalize_surface": "generator_finalize_v0",
    "iter_surface": "for_in_v0",
    "iter_api": "oren_iter_next_v0",
    "iter_resume": "implicit_nil_v0",
    "resume_surface": "next_send_finalize_defer_close_cancel_delegate_yield_from_v9",
    "next_api": "oren_generator_next_v2",
    "send_api": "oren_generator_send_v2",
    "on_finalize_api": "oren_generator_on_finalize_v1",
    "on_close_api": "oren_generator_on_close_v1",
    "close_api": "oren_generator_close_v1",
    "cancel_api": "oren_generator_cancel_v1",
    "request_cancel_api": "oren_generator_request_cancel_v1",
    "delegate_api": "oren_generator_delegate_v1",
    "delegate_step_api": "oren_generator_delegate_step_v1",
    "started_api": "oren_generator_is_started_v1",
    "closed_api": "oren_generator_is_closed_v1",
    "cancel_requested_api": "oren_generator_is_cancel_requested_v1",
    "current_step_api": "oren_generator_current_step_v1",
    "terminal_error_api": "oren_generator_terminal_error_v1",
    "cancel_reason_api": "oren_generator_cancel_reason_v1",
    "on_finalize_mode": "lifo_zero_arg_on_done_or_close_v1",
    "on_close_mode": "alias_of_on_finalize_v1",
    "close_mode": "propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5",
    "delegate_mode": "track_active_chain_inline_fresh_or_cached_started_step_v3",
    "finalize_source_syntaxes": ["defer_v0", "defer_in_context_v0", "on_finalize_call_v1", "on_close_call_alias_v1"],
    "delegate_source_syntaxes": ["yield_from_v0", "yield_from_in_context_v0"],
    "state_layout": "dedicated_generator_object_kind_v1",
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

def ordered_unique(values):
    out = []
    for value in values:
        if value not in out:
            out.append(value)
    return out

def assert_finalize(item, *, points, context):
    sites = [site for site, _, _ in points]
    syntax_kinds = ordered_unique([syntax for _, syntax, _ in points])
    api_kinds = ordered_unique([api for _, _, api in points])
    if item["contains_generator_finalize"] is not True or item["generator_finalize_count"] != len(points):
        raise SystemExit(f"{item['name']} bad generator_finalize count: {item!r}")
    if item["generator_finalize_sites"] != sites:
        raise SystemExit(f"{item['name']} bad generator_finalize_sites: {item['generator_finalize_sites']!r}")
    surface = item["generator_finalize_surface"]
    if surface is None:
        raise SystemExit(f"{item['name']} missing generator_finalize_surface")
    if surface["version"] != 1 or surface["surface"] != "generator_finalize_v0":
        raise SystemExit(f"{item['name']} bad generator_finalize_surface header: {surface!r}")
    if surface["lifecycle"] != "on_done_or_close_v1" or surface["hook_arity"] != "zero_arg":
        raise SystemExit(f"{item['name']} bad finalize lifecycle/arity: {surface!r}")
    if surface["syntax_kinds"] != syntax_kinds:
        raise SystemExit(f"{item['name']} bad finalize syntax_kinds: {surface!r}")
    if surface["api_kinds"] != api_kinds:
        raise SystemExit(f"{item['name']} bad finalize api_kinds: {surface!r}")
    if surface["consumer_kinds"] != [context]:
        raise SystemExit(f"{item['name']} bad finalize consumer_kinds: {surface!r}")
    if len(surface["finalize_points"]) != len(points):
        raise SystemExit(f"{item['name']} bad finalize_points len: {surface!r}")
    for idx, ((site, syntax, api), point) in enumerate(zip(points, surface["finalize_points"])):
        if point["id"] != idx:
            raise SystemExit(f"{item['name']} bad finalize id: {point!r}")
        if point["site"] != site or point["context"] != context or point["syntax"] != syntax or point["api"] != api:
            raise SystemExit(f"{item['name']} bad finalize point: {point!r}")

for payload, detail_key in [(meta, False), (dump, True), (obc, False)]:
    assert_no_hidden_generator_helpers(payload, detail_key)
    assert_decl(
        get_func(payload, "decl_counter", detail_key),
        count=2,
        sites=[
            "tests/fixtures/generator_surface_v0.oren:195:20",
            "tests/fixtures/generator_surface_v0.oren:196:20",
        ],
        context="var_init",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_nil", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:202:5"],
        context="expr_stmt",
        explicit_value=False,
    )
    assert_decl(
        get_func(payload, "decl_collect", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:210:9"],
        context="expr_stmt",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_var_counter", detail_key),
        count=2,
        sites=[
            "tests/fixtures/generator_surface_v0.oren:218:20",
            "tests/fixtures/generator_surface_v0.oren:219:20",
        ],
        context="var_init",
        explicit_value=True,
    )
    assert_decl(
        get_func(payload, "decl_var_lambda", detail_key),
        count=1,
        sites=["tests/fixtures/generator_surface_v0.oren:225:19"],
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
    assert_finalize(
        get_func(payload, "finalize_hook_worker", detail_key),
        points=[
            ("tests/fixtures/generator_surface_v0.oren:325:29", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:327:40", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:329:26", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ],
        context="var_init",
    )
    assert_finalize(
        get_func(payload, "defer_finalize_worker", detail_key),
        points=[
            ("tests/fixtures/generator_surface_v0.oren:382:5", "defer_in_context_v0", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:383:5", "defer_in_context_v0", "oren_generator_on_finalize_v1"),
        ],
        context="expr_stmt",
    )
    assert_finalize(
        get_func(payload, "decl_finalize_hook", detail_key),
        points=[
            ("tests/fixtures/generator_surface_v0.oren:358:29", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:360:40", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:362:26", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ],
        context="var_init",
    )
    assert_finalize(
        get_func(payload, "decl_defer_finalize", detail_key),
        points=[
            ("tests/fixtures/generator_surface_v0.oren:408:5", "defer_v0", "oren_generator_on_finalize_v1"),
            ("tests/fixtures/generator_surface_v0.oren:409:5", "defer_v0", "oren_generator_on_finalize_v1"),
        ],
        context="expr_stmt",
    )
PY

python3 - "$coroutine_alias_meta_out" "$coroutine_alias_dump_out" "$coroutine_alias_bytecode_meta_out" >>"$log" <<'PY'
import json
import sys

meta_path, dump_path, obc_path = sys.argv[1:4]
meta = json.load(open(meta_path, "r", encoding="utf-8"))
dump = json.load(open(dump_path, "r", encoding="utf-8"))
obc = json.load(open(obc_path, "r", encoding="utf-8"))["metadata"]

expected_decl_surface = {
    "version": 23,
    "surface": "compiler_generator_object_v7",
    "syntax": "attr_oren.generator",
    "helper_api": "oren_generator_start_v2",
    "caller_api": "generator_handle_v2",
    "object_type": "generator",
    "yield_surface": "generator_context_v0",
    "finalize_surface": "generator_finalize_v0",
    "iter_surface": "for_in_v0",
    "iter_api": "oren_iter_next_v0",
    "iter_resume": "implicit_nil_v0",
    "resume_surface": "next_send_finalize_defer_close_cancel_delegate_yield_from_v9",
    "next_api": "oren_generator_next_v2",
    "send_api": "oren_generator_send_v2",
    "on_finalize_api": "oren_generator_on_finalize_v1",
    "on_close_api": "oren_generator_on_close_v1",
    "close_api": "oren_generator_close_v1",
    "cancel_api": "oren_generator_cancel_v1",
    "request_cancel_api": "oren_generator_request_cancel_v1",
    "delegate_api": "oren_generator_delegate_v1",
    "delegate_step_api": "oren_generator_delegate_step_v1",
    "started_api": "oren_generator_is_started_v1",
    "closed_api": "oren_generator_is_closed_v1",
    "cancel_requested_api": "oren_generator_is_cancel_requested_v1",
    "current_step_api": "oren_generator_current_step_v1",
    "terminal_error_api": "oren_generator_terminal_error_v1",
    "cancel_reason_api": "oren_generator_cancel_reason_v1",
    "on_finalize_mode": "lifo_zero_arg_on_done_or_close_v1",
    "on_close_mode": "alias_of_on_finalize_v1",
    "close_mode": "propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5",
    "delegate_mode": "track_active_chain_inline_fresh_or_cached_started_step_v3",
    "finalize_source_syntaxes": ["defer_v0", "defer_in_context_v0", "on_finalize_call_v1", "on_close_call_alias_v1"],
    "delegate_source_syntaxes": ["yield_from_v0", "yield_from_in_context_v0"],
    "state_layout": "dedicated_generator_object_kind_v1",
    "worker_context_type": "generator_context",
    "decl_forms": ["named_function_decl", "function_valued_var"],
}

def get_func(payload, name, detail_key=False):
    key = "function_details" if detail_key else "functions"
    for item in payload[key]:
        if item.get("name") == name:
            return item
    raise SystemExit(f"missing function {name} in {key}")

def assert_decl(item, *, count):
    if item["is_generator_decl"] is not True:
        raise SystemExit(f"{item['name']} missing is_generator_decl: {item!r}")
    if item["generator_decl_surface"] != expected_decl_surface:
        raise SystemExit(f"{item['name']} bad generator_decl_surface: {item['generator_decl_surface']!r}")
    if item["contains_yield_exchange"] is not True or item["yield_exchange_count"] != count:
        raise SystemExit(f"{item['name']} bad yield_exchange count: {item!r}")

def ordered_unique(values):
    out = []
    for value in values:
        if value not in out:
            out.append(value)
    return out

def assert_finalize(item, *, points, context):
    sites = [site for site, _, _ in points]
    syntax_kinds = ordered_unique([syntax for _, syntax, _ in points])
    api_kinds = ordered_unique([api for _, _, api in points])
    if item["contains_generator_finalize"] is not True or item["generator_finalize_count"] != len(points):
        raise SystemExit(f"{item['name']} bad generator_finalize count: {item!r}")
    if item["generator_finalize_sites"] != sites:
        raise SystemExit(f"{item['name']} bad generator_finalize_sites: {item['generator_finalize_sites']!r}")
    surface = item["generator_finalize_surface"]
    if surface is None:
        raise SystemExit(f"{item['name']} missing generator_finalize_surface")
    if surface["version"] != 1 or surface["surface"] != "generator_finalize_v0":
        raise SystemExit(f"{item['name']} bad generator_finalize_surface header: {surface!r}")
    if surface["lifecycle"] != "on_done_or_close_v1" or surface["hook_arity"] != "zero_arg":
        raise SystemExit(f"{item['name']} bad finalize lifecycle/arity: {surface!r}")
    if surface["syntax_kinds"] != syntax_kinds:
        raise SystemExit(f"{item['name']} bad finalize syntax_kinds: {surface!r}")
    if surface["api_kinds"] != api_kinds:
        raise SystemExit(f"{item['name']} bad finalize api_kinds: {surface!r}")
    if surface["consumer_kinds"] != [context]:
        raise SystemExit(f"{item['name']} bad finalize consumer_kinds: {surface!r}")
    if len(surface["finalize_points"]) != len(points):
        raise SystemExit(f"{item['name']} bad finalize_points len: {surface!r}")
    for idx, ((site, syntax, api), point) in enumerate(zip(points, surface["finalize_points"])):
        if point["id"] != idx:
            raise SystemExit(f"{item['name']} bad finalize id: {point!r}")
        if point["site"] != site or point["context"] != context or point["syntax"] != syntax or point["api"] != api:
            raise SystemExit(f"{item['name']} bad finalize point: {point!r}")

for payload, detail_key in [(meta, False), (dump, True), (obc, False)]:
    assert_decl(get_func(payload, "decl_counter", detail_key), count=2)
    assert_decl(get_func(payload, "decl_var_counter", detail_key), count=2)
    assert_decl(get_func(payload, "decl_var_lambda", detail_key), count=1)
    assert_decl(get_func(payload, "decl_defer", detail_key), count=1)
    assert_finalize(
        get_func(payload, "decl_defer", detail_key),
        points=[
            ("tests/fixtures/coroutine_decl_surface_v0.oren:42:5", "defer_v0", "oren_generator_on_finalize_v1"),
        ],
        context="expr_stmt",
    )
PY

blocked_log="$tmpdir/generator_decl_blocked_nonfunction_var.log"
echo "\$ $compiler build $blocked_src --backend bytecode --platform $platform --no-cache -o $tmpdir/blocked_nonfunction_var.obc" >>"$log"
if "$compiler" build "$blocked_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/blocked_nonfunction_var.obc" >>"$blocked_log" 2>&1; then
  cat "$blocked_log" >>"$log"
  echo "verify_generator_surface_v0: expected non-function generator var binding to fail" >&2
  exit 1
fi
cat "$blocked_log" >>"$log"
grep -F "@oren.generator/@oren.coroutine on var requires function value" "$blocked_log" >/dev/null

coroutine_alias_blocked_log="$tmpdir/coroutine_decl_blocked_nonfunction_var.log"
echo "\$ $compiler build $coroutine_alias_blocked_src --backend bytecode --platform $platform --no-cache -o $tmpdir/coroutine_blocked_nonfunction_var.obc" >>"$log"
if "$compiler" build "$coroutine_alias_blocked_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/coroutine_blocked_nonfunction_var.obc" >>"$coroutine_alias_blocked_log" 2>&1; then
  cat "$coroutine_alias_blocked_log" >>"$log"
  echo "verify_generator_surface_v0: expected non-function coroutine var binding to fail" >&2
  exit 1
fi
cat "$coroutine_alias_blocked_log" >>"$log"
grep -F "@oren.generator/@oren.coroutine on var requires function value" "$coroutine_alias_blocked_log" >/dev/null

blocked_yield_from_log="$tmpdir/generator_yield_from_blocked_missing_context.log"
echo "\$ $compiler build $blocked_yield_from_src --backend bytecode --platform $platform --no-cache -o $tmpdir/blocked_yield_from.obc" >>"$log"
if "$compiler" build "$blocked_yield_from_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/blocked_yield_from.obc" >>"$blocked_yield_from_log" 2>&1; then
  cat "$blocked_yield_from_log" >>"$log"
  echo "verify_generator_surface_v0: expected plain yield from without context to fail" >&2
  exit 1
fi
cat "$blocked_yield_from_log" >>"$log"
grep -F "yield from" "$blocked_yield_from_log" >/dev/null
grep -F "requires 'in co' outside @oren.generator/@oren.coroutine declarations" "$blocked_yield_from_log" >/dev/null

blocked_defer_log="$tmpdir/generator_defer_blocked_missing_context.log"
echo "\$ $compiler build $blocked_defer_src --backend bytecode --platform $platform --no-cache -o $tmpdir/blocked_defer.obc" >>"$log"
if "$compiler" build "$blocked_defer_src" --backend bytecode --platform "$platform" --no-cache -o "$tmpdir/blocked_defer.obc" >>"$blocked_defer_log" 2>&1; then
  cat "$blocked_defer_log" >>"$log"
  echo "verify_generator_surface_v0: expected plain defer without context to fail" >&2
  exit 1
fi
cat "$blocked_defer_log" >>"$log"
grep -F "defer" "$blocked_defer_log" >/dev/null
grep -F "requires 'in co' outside @oren.generator/@oren.coroutine declarations" "$blocked_defer_log" >/dev/null

echo "generator surface v0 verify OK" >>"$log"
echo "generator surface v0 verify OK"
