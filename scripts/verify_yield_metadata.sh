#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

meta_compiler="${1:-${OREN_META_COMPILER:-./oren}}"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
meta_out="build/tmp/meta_yield_surface_${ts}.json"
log="build/logs/verify_yield_metadata_${ts}.log"

{
  echo "writing $meta_out"
  echo "\$ $meta_compiler meta tests/fixtures/meta_yield_surface.oren -o $meta_out"
  "$meta_compiler" meta tests/fixtures/meta_yield_surface.oren -o "$meta_out" || exit 1
  python3 - "$meta_out" <<'PY' || exit 1
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

funcs = data.get("functions")
if not isinstance(funcs, list):
    raise SystemExit("functions metadata must be a list")

by_name = {}
for item in funcs:
    name = item.get("name")
    if not isinstance(name, str):
        raise SystemExit(f"function entry missing string name: {item!r}")
    by_name[name] = item

expected_names = {
    "no_yield",
    "one_yield",
    "control_yield",
    "nested_only",
    "param_across",
    "local_across",
    "dead_local_after_block",
    "multi_local_order",
    "yield_with_nested_fn",
    "ready_prefix_suffix",
    "multi_top_level_ready",
    "branch_only_yield",
    "value_nil_expr",
    "value_expr",
    "value_stmt",
    "nested_value_only",
    "add1_meta",
    "value_return",
    "value_call_arg",
    "exchange_var",
    "exchange_return",
    "exchange_stmt",
    "exchange_call_arg",
    "exchange_syntax_var",
    "exchange_syntax_nil",
    "exchange_syntax_return",
    "exchange_syntax_stmt",
    "exchange_syntax_call_arg",
    "exchange_context_var",
    "exchange_context_nil",
    "exchange_context_return",
    "exchange_context_stmt",
    "exchange_context_call_arg",
    "exchange_nested_only",
    "meta_decl_var",
    "meta_decl_lambda",
    "finalize_manual_explicit",
    "finalize_alias_explicit",
    "finalize_defer_explicit",
    "meta_decl_finalize_manual",
    "meta_decl_finalize_alias",
    "meta_decl_finalize_defer",
}
expected_hidden_names = {
    "_oren_generator_bind_active_child",
    "_oren_generator_close_active_child",
    "_oren_generator_context_owner",
    "_oren_generator_context_exchange",
    "_oren_generator_ctx",
    "_oren_generator_done_result",
    "_oren_generator_done_step",
    "_oren_generator_ensure_task",
    "_oren_generator_entry",
    "_oren_generator_err",
    "_oren_generator_expect_close_hook",
    "_oren_generator_expect_context",
    "_oren_generator_expect_handle",
    "_oren_generator_expect_step",
    "_oren_generator_finish",
    "_oren_generator_finalize",
    "_oren_generator_get",
    "_oren_generator_is_context",
    "_oren_generator_is_handle",
    "_oren_generator_mark_done",
    "_oren_generator_push_close_hook",
    "_oren_generator_resume",
    "_oren_generator_restore_active_child",
    "_oren_generator_run_close_hooks",
    "_oren_generator_set",
    "_oren_generator_step_value",
    "_oren_generator_terminal_result",
    "_oren_generator_trace",
    "_oren_generator_yield_step",
    "oren_generator_collect",
    "oren_generator_close",
    "oren_generator_delegate",
    "oren_generator_delegate_step",
    "oren_generator_is_done",
    "oren_generator_next",
    "oren_generator_on_finalize",
    "oren_generator_on_close",
    "oren_generator_return_value",
    "oren_generator_send",
    "oren_generator_start",
}
actual_names = set(by_name)
actual_names = set(by_name)
if actual_names != (expected_names | expected_hidden_names):
    raise SystemExit(f"unexpected function names: {sorted(by_name)!r}")

def exchange_surface(site, context, syntax, explicit_value, binding):
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
    return {
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
        "exchange_points": [
            {"id": 0, "site": site, "context": context, "syntax": syntax, "binding": binding, "explicit_value": explicit_value},
        ],
    }

def exchange_expect(site, context, syntax, explicit_value, binding):
    return {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": [site],
        "yield_exchange_surface": exchange_surface(site, context, syntax, explicit_value, binding),
    }

expected_generator_decl_surface = {
    "version": 18,
    "surface": "compiler_generator_object_v2",
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
    "on_finalize_mode": "lifo_zero_arg_on_done_or_close_v1",
    "on_close_mode": "alias_of_on_finalize_v1",
    "close_mode": "propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5",
    "delegate_mode": "track_active_chain_inline_fresh_or_cached_started_step_v3",
    "finalize_source_syntaxes": ["defer_v0", "defer_in_context_v0", "on_finalize_call_v1", "on_close_call_alias_v1"],
    "delegate_source_syntaxes": ["yield_from_v0", "yield_from_in_context_v0"],
    "state_layout": "hidden_list_capsule_v4",
    "worker_context_type": "generator_context",
    "decl_forms": ["named_function_decl", "function_valued_var"],
}

def generator_expect(site, context, explicit_value):
    out = exchange_expect(site, context, "generator_decl", explicit_value, "generator_context")
    out["is_generator_decl"] = True
    out["generator_decl_surface"] = expected_generator_decl_surface
    return out

def finalize_surface(points):
    syntax_kinds = []
    api_kinds = []
    consumer_kinds = []
    for point in points:
        _, context, syntax, api = point
        if syntax not in syntax_kinds:
            syntax_kinds.append(syntax)
        if api not in api_kinds:
            api_kinds.append(api)
        if context not in consumer_kinds:
            consumer_kinds.append(context)
    return {
        "version": 1,
        "surface": "generator_finalize_v0",
        "lifecycle": "on_done_or_close_v1",
        "hook_arity": "zero_arg",
        "syntax_kinds": syntax_kinds,
        "api_kinds": api_kinds,
        "consumer_kinds": consumer_kinds,
        "finalize_points": [
            {"id": idx, "site": site, "context": context, "syntax": syntax, "api": api}
            for idx, (site, context, syntax, api) in enumerate(points)
        ],
    }

def finalize_expect(points):
    return {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_generator_finalize": True,
        "generator_finalize_count": len(points),
        "generator_finalize_sites": [site for site, _, _, _ in points],
        "generator_finalize_surface": finalize_surface(points),
    }

expected = {
    "no_yield": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
    },
    "one_yield": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:6:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:6:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:6:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:6:5",
                "live_slots": [],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": [], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "control_yield": {
        "contains_yield": True,
        "yield_stmt_count": 2,
        "yield_stmt_sites": [
            "tests/fixtures/meta_yield_surface.oren:12:9",
            "tests/fixtures/meta_yield_surface.oren:15:9",
        ],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 3,
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:12:9", "resume_state": 1},
                {"id": 1, "site": "tests/fixtures/meta_yield_surface.oren:15:9", "resume_state": 2},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:12:9"},
                {"id": 2, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:15:9"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "direct_passthrough",
                "state_local": "",
                "entry_state": 0,
                "resume_state": -1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:12:9",
                "live_slots": [],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["ExprStmt", "While", "Return"], "terminator": "return"},
                ],
            },
        },
    },
    "nested_only": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
    },
    "param_across": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:29:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": ["arg"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:29:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:29:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:29:5",
                "live_slots": ["arg"],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": [], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "local_across": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:35:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": ["acc"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:35:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:35:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:35:5",
                "live_slots": ["acc"],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["Var"], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "dead_local_after_block": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:42:9"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:42:9", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:42:9"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "direct_passthrough",
                "state_local": "",
                "entry_state": 0,
                "resume_state": -1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:42:9",
                "live_slots": [],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["Block", "Return"], "terminator": "return"},
                ],
            },
        },
    },
    "multi_local_order": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:50:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": ["y", "x"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:50:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:50:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:50:5",
                "live_slots": ["y", "x"],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["Var", "Var"], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "yield_with_nested_fn": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:56:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": ["f"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:56:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:56:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:56:5",
                "live_slots": ["f"],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["Var"], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "ready_prefix_suffix": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:62:5"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:62:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:62:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:62:5",
                "live_slots": [],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["ExprStmt"], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["ExprStmt", "Return"], "terminator": "return"},
                ],
            },
        },
    },
    "multi_top_level_ready": {
        "contains_yield": True,
        "yield_stmt_count": 2,
        "yield_stmt_sites": [
            "tests/fixtures/meta_yield_surface.oren:69:5",
            "tests/fixtures/meta_yield_surface.oren:71:5",
        ],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 3,
            "locals_across_yield": ["acc"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:69:5", "resume_state": 1},
                {"id": 1, "site": "tests/fixtures/meta_yield_surface.oren:71:5", "resume_state": 2},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:69:5"},
                {"id": 2, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:71:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "split_dispatch",
                "state_local": "__oren_yield_state_v0",
                "entry_state": 0,
                "resume_state": 1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:69:5",
                "live_slots": ["acc"],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["Var"], "terminator": "yield"},
                    {"state": 1, "kind": "resume", "stmt_types": ["Assign"], "terminator": "yield"},
                    {"state": 2, "kind": "resume", "stmt_types": ["Return"], "terminator": "return"},
                ],
            },
        },
    },
    "branch_only_yield": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:77:9"],
        "yield_lowering": {
            "version": 1,
            "surface": "bare_statement_only",
            "entry_state": 0,
            "state_count": 2,
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:77:9", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:77:9"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "bare_yield_dispatch_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
            },
            "prepared_v0": {
                "version": 1,
                "kind": "direct_passthrough",
                "state_local": "",
                "entry_state": 0,
                "resume_state": -1,
                "yield_site": "tests/fixtures/meta_yield_surface.oren:77:9",
                "live_slots": [],
                "segments": [
                    {"state": 0, "kind": "entry", "stmt_types": ["ExprStmt", "Return"], "terminator": "return"},
                ],
            },
        },
    },
    "value_nil_expr": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_value": True,
        "yield_value_count": 1,
        "yield_value_sites": ["tests/fixtures/meta_yield_surface.oren:83:12"],
        "yield_value_surface": {
            "version": 1,
            "surface": "local_value_resume_v0",
            "resume_value_source": "local_expression",
            "supports_implicit_nil": True,
            "supports_explicit_value": True,
            "caller_resume_values": False,
            "generator_channel": False,
            "consumer_kinds": ["return_value"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:83:12", "explicit_value": False, "context": "return_value"},
            ],
        },
    },
    "value_expr": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_value": True,
        "yield_value_count": 1,
        "yield_value_sites": ["tests/fixtures/meta_yield_surface.oren:87:13"],
        "yield_value_surface": {
            "version": 1,
            "surface": "local_value_resume_v0",
            "resume_value_source": "local_expression",
            "supports_implicit_nil": True,
            "supports_explicit_value": True,
            "caller_resume_values": False,
            "generator_channel": False,
            "consumer_kinds": ["var_init"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:87:13", "explicit_value": True, "context": "var_init"},
            ],
        },
    },
    "value_stmt": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_value": True,
        "yield_value_count": 1,
        "yield_value_sites": ["tests/fixtures/meta_yield_surface.oren:92:5"],
        "yield_value_surface": {
            "version": 1,
            "surface": "local_value_resume_v0",
            "resume_value_source": "local_expression",
            "supports_implicit_nil": True,
            "supports_explicit_value": True,
            "caller_resume_values": False,
            "generator_channel": False,
            "consumer_kinds": ["expr_stmt"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:92:5", "explicit_value": True, "context": "expr_stmt"},
            ],
        },
    },
    "nested_value_only": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
    },
    "add1_meta": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
    },
    "value_return": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_value": True,
        "yield_value_count": 1,
        "yield_value_sites": ["tests/fixtures/meta_yield_surface.oren:108:12"],
        "yield_value_surface": {
            "version": 1,
            "surface": "local_value_resume_v0",
            "resume_value_source": "local_expression",
            "supports_implicit_nil": True,
            "supports_explicit_value": True,
            "caller_resume_values": False,
            "generator_channel": False,
            "consumer_kinds": ["return_value"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:108:12", "explicit_value": True, "context": "return_value"},
            ],
        },
    },
    "value_call_arg": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_value": True,
        "yield_value_count": 1,
        "yield_value_sites": ["tests/fixtures/meta_yield_surface.oren:112:22"],
        "yield_value_surface": {
            "version": 1,
            "surface": "local_value_resume_v0",
            "resume_value_source": "local_expression",
            "supports_implicit_nil": True,
            "supports_explicit_value": True,
            "caller_resume_values": False,
            "generator_channel": False,
            "consumer_kinds": ["call_arg"],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:112:22", "explicit_value": True, "context": "call_arg"},
            ],
        },
    },
    "exchange_var": exchange_expect("tests/fixtures/meta_yield_surface.oren:116:32", "var_init", "helper_call", True, "explicit_channel_pair"),
    "exchange_return": exchange_expect("tests/fixtures/meta_yield_surface.oren:121:31", "return_value", "helper_call", True, "explicit_channel_pair"),
    "exchange_stmt": exchange_expect("tests/fixtures/meta_yield_surface.oren:125:24", "expr_stmt", "helper_call", True, "explicit_channel_pair"),
    "exchange_call_arg": exchange_expect("tests/fixtures/meta_yield_surface.oren:130:41", "call_arg", "helper_call", True, "explicit_channel_pair"),
    "exchange_syntax_var": exchange_expect("tests/fixtures/meta_yield_surface.oren:134:13", "var_init", "yield_in_channels", True, "explicit_channel_pair"),
    "exchange_syntax_nil": exchange_expect("tests/fixtures/meta_yield_surface.oren:139:13", "var_init", "yield_in_channels", False, "explicit_channel_pair"),
    "exchange_syntax_return": exchange_expect("tests/fixtures/meta_yield_surface.oren:144:12", "return_value", "yield_in_channels", True, "explicit_channel_pair"),
    "exchange_syntax_stmt": exchange_expect("tests/fixtures/meta_yield_surface.oren:148:5", "expr_stmt", "yield_in_channels", True, "explicit_channel_pair"),
    "exchange_syntax_call_arg": exchange_expect("tests/fixtures/meta_yield_surface.oren:153:22", "call_arg", "yield_in_channels", True, "explicit_channel_pair"),
    "exchange_context_var": exchange_expect("tests/fixtures/meta_yield_surface.oren:157:13", "var_init", "yield_in_context", True, "generator_context"),
    "exchange_context_nil": exchange_expect("tests/fixtures/meta_yield_surface.oren:162:13", "var_init", "yield_in_context", False, "generator_context"),
    "exchange_context_return": exchange_expect("tests/fixtures/meta_yield_surface.oren:167:12", "return_value", "yield_in_context", True, "generator_context"),
    "exchange_context_stmt": exchange_expect("tests/fixtures/meta_yield_surface.oren:171:5", "expr_stmt", "yield_in_context", True, "generator_context"),
    "exchange_context_call_arg": exchange_expect("tests/fixtures/meta_yield_surface.oren:176:22", "call_arg", "yield_in_context", True, "generator_context"),
    "exchange_nested_only": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
    },
    "meta_decl_var": generator_expect("tests/fixtures/meta_yield_surface.oren:188:19", "var_init", True),
    "meta_decl_lambda": generator_expect("tests/fixtures/meta_yield_surface.oren:194:5", "expr_stmt", False),
    "finalize_manual_explicit": {
        **exchange_expect("tests/fixtures/meta_yield_surface.oren:201:12", "return_value", "yield_in_context", True, "generator_context"),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:199:40", "var_init", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
        ]),
    },
    "finalize_alias_explicit": {
        **exchange_expect("tests/fixtures/meta_yield_surface.oren:207:5", "expr_stmt", "yield_in_context", True, "generator_context"),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:205:37", "var_init", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ]),
    },
    "finalize_defer_explicit": {
        **exchange_expect("tests/fixtures/meta_yield_surface.oren:213:5", "expr_stmt", "yield_in_context", True, "generator_context"),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:212:5", "expr_stmt", "defer_in_context_v0", "oren_generator_on_finalize_v1"),
        ]),
    },
    "meta_decl_finalize_manual": {
        **generator_expect("tests/fixtures/meta_yield_surface.oren:221:19", "var_init", True),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:219:40", "var_init", "on_finalize_call_v1", "oren_generator_on_finalize_v1"),
        ]),
    },
    "meta_decl_finalize_alias": {
        **generator_expect("tests/fixtures/meta_yield_surface.oren:229:5", "expr_stmt", True),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:227:37", "var_init", "on_close_call_alias_v1", "oren_generator_on_close_v1"),
        ]),
    },
    "meta_decl_finalize_defer": {
        **generator_expect("tests/fixtures/meta_yield_surface.oren:236:5", "expr_stmt", True),
        **finalize_expect([
            ("tests/fixtures/meta_yield_surface.oren:235:5", "expr_stmt", "defer_v0", "oren_generator_on_finalize_v1"),
        ]),
    },
}

for exp in expected.values():
    exp.setdefault("contains_yield_value", False)
    exp.setdefault("yield_value_count", 0)
    exp.setdefault("yield_value_sites", [])
    exp.setdefault("yield_value_surface", None)
    exp.setdefault("contains_yield_exchange", False)
    exp.setdefault("yield_exchange_count", 0)
    exp.setdefault("yield_exchange_sites", [])
    exp.setdefault("yield_exchange_surface", None)
    exp.setdefault("contains_generator_finalize", False)
    exp.setdefault("generator_finalize_count", 0)
    exp.setdefault("generator_finalize_sites", [])
    exp.setdefault("generator_finalize_surface", None)
    exp.setdefault("is_generator_decl", False)
    exp.setdefault("generator_decl_surface", None)

for name, exp in expected.items():
    item = by_name[name]
    for key, val in exp.items():
        got = item.get(key)
        if got != val:
            raise SystemExit(f"{name}.{key} mismatch: expected {val!r}, got {got!r}")

print("yield metadata JSON verified")
PY

  echo "yield metadata verify OK"
} >"$log" 2>&1 || {
  cat "$log" >&2
  exit 1
}

cat "$log"
