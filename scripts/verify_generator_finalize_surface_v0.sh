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
  echo "verify_generator_finalize_surface_v0: could not determine host platform; set OREN_PLATFORM" >&2
  exit 1
fi

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
tmpdir="build/tmp/generator_finalize_surface_v0_${ts}"
log="build/logs/verify_generator_finalize_surface_v0_${ts}.log"
mkdir -p "$tmpdir"

src="tests/fixtures/generator_finalize_surface_v0.oren"
meta_out="$tmpdir/finalize_meta.json"
dump_out="$tmpdir/finalize_dump.json"
bytecode_out="$tmpdir/finalize_bytecode.obc"
bytecode_meta_out="$tmpdir/finalize_bytecode_meta.json"

run_ok() {
  echo "\$ $*" >>"$log"
  "$@" >>"$log" 2>&1
}

run_ok "$meta_compiler" meta "$src" -o "$meta_out"
run_ok "$meta_compiler" dump linked "$src" --platform "$platform" -o "$dump_out"
run_ok "$compiler" build "$src" --backend bytecode --platform "$platform" --no-cache -o "$bytecode_out"
run_ok python3 scripts/extract_obc_metadata.py "$bytecode_out" -o "$bytecode_meta_out"

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

expected_names = [
    "finalize_manual_explicit",
    "finalize_alias_explicit",
    "finalize_defer_explicit",
    "decl_finalize_manual",
    "decl_finalize_alias",
    "decl_finalize_defer",
]

def assert_visible_function_set(payload, detail_key=False):
    key = "function_details" if detail_key else "functions"
    names = [item["name"] for item in payload[key]]
    if names != expected_names:
        raise SystemExit(f"unexpected {key} names: {names!r}")
    for name in names:
        if name.startswith("_oren_generator_") or name.startswith("oren_generator_"):
            raise SystemExit(f"unexpected hidden generator helper in {key}: {name!r}")

expected_decl_surface = {
    "version": 20,
    "surface": "compiler_generator_object_v4",
    "syntax": "attr_oren.generator",
    "helper_api": "oren_generator_start_v2",
    "caller_api": "generator_handle_v2",
    "object_type": "generator",
    "yield_surface": "generator_context_v0",
    "finalize_surface": "generator_finalize_v0",
    "iter_surface": "for_in_v0",
    "iter_api": "oren_iter_next_v0",
    "iter_resume": "implicit_nil_v0",
    "resume_surface": "next_send_finalize_defer_close_delegate_yield_from_v7",
    "next_api": "oren_generator_next_v2",
    "send_api": "oren_generator_send_v2",
    "on_finalize_api": "oren_generator_on_finalize_v1",
    "on_close_api": "oren_generator_on_close_v1",
    "close_api": "oren_generator_close_v1",
    "delegate_api": "oren_generator_delegate_v1",
    "delegate_step_api": "oren_generator_delegate_step_v1",
    "started_api": "oren_generator_is_started_v1",
    "current_step_api": "oren_generator_current_step_v1",
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

def ordered_unique(values):
    out = []
    for value in values:
        if value not in out:
            out.append(value)
    return out

def assert_finalize(item, *, points, context, is_decl):
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
        raise SystemExit(f"{item['name']} bad generator finalize lifecycle/arity: {surface!r}")
    if surface["syntax_kinds"] != syntax_kinds:
        raise SystemExit(f"{item['name']} bad finalize syntax_kinds: {surface!r}")
    if surface["api_kinds"] != api_kinds:
        raise SystemExit(f"{item['name']} bad finalize api_kinds: {surface!r}")
    if surface["consumer_kinds"] != [context]:
        raise SystemExit(f"{item['name']} bad finalize consumer_kinds: {surface!r}")
    if len(surface["finalize_points"]) != len(points):
        raise SystemExit(f"{item['name']} bad finalize_points len: {surface!r}")
    for idx, ((site, syntax, api), point) in enumerate(zip(points, surface["finalize_points"])):
        if point["id"] != idx or point["site"] != site or point["context"] != context or point["syntax"] != syntax or point["api"] != api:
            raise SystemExit(f"{item['name']} bad finalize point: {point!r}")
    if item["is_generator_decl"] != is_decl:
        raise SystemExit(f"{item['name']} bad is_generator_decl: {item!r}")
    if is_decl:
        if item["generator_decl_surface"] != expected_decl_surface:
            raise SystemExit(f"{item['name']} bad generator_decl_surface: {item['generator_decl_surface']!r}")
    else:
        if item["generator_decl_surface"] is not None:
            raise SystemExit(f"{item['name']} unexpected generator_decl_surface: {item!r}")

for payload, detail_key in [(meta, False), (dump, True), (obc, False)]:
    assert_visible_function_set(payload, detail_key)
    assert_finalize(
        get_func(payload, "finalize_manual_explicit", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:2:40", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
        ],
        context="var_init",
        is_decl=False,
    )
    assert_finalize(
        get_func(payload, "finalize_alias_explicit", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:8:37", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ],
        context="var_init",
        is_decl=False,
    )
    assert_finalize(
        get_func(payload, "finalize_defer_explicit", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:15:5", "defer_in_context_v0", "oren_generator_on_finalize_v1"),
        ],
        context="expr_stmt",
        is_decl=False,
    )
    assert_finalize(
        get_func(payload, "decl_finalize_manual", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:28:40", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
        ],
        context="var_init",
        is_decl=True,
    )
    assert_finalize(
        get_func(payload, "decl_finalize_alias", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:36:37", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ],
        context="var_init",
        is_decl=True,
    )
    assert_finalize(
        get_func(payload, "decl_finalize_defer", detail_key),
        points=[
            ("tests/fixtures/generator_finalize_surface_v0.oren:44:5", "defer_v0", "oren_generator_on_finalize_v1"),
        ],
        context="expr_stmt",
        is_decl=True,
    )

print("generator finalize surface v0 verify OK")
PY

echo "generator finalize surface v0 verify OK" >>"$log"
echo "generator finalize surface v0 verify OK"
