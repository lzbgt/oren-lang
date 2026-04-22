#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
meta_out="build/tmp/meta_yield_surface_${ts}.json"
log="build/logs/verify_yield_metadata_${ts}.log"

{
  echo "writing $meta_out"
  ./oren meta tests/fixtures/meta_yield_surface.oren -o "$meta_out" || exit 1

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
    "exchange_nested_only",
}
if set(by_name) != expected_names:
    raise SystemExit(f"unexpected function names: {sorted(by_name)!r}")

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
    "exchange_var": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:116:32"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["helper_call"],
            "consumer_kinds": ["var_init"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:116:32", "context": "var_init", "syntax": "helper_call", "explicit_value": True},
            ],
        },
    },
    "exchange_return": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:121:31"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["helper_call"],
            "consumer_kinds": ["return_value"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:121:31", "context": "return_value", "syntax": "helper_call", "explicit_value": True},
            ],
        },
    },
    "exchange_stmt": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:125:24"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["helper_call"],
            "consumer_kinds": ["expr_stmt"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:125:24", "context": "expr_stmt", "syntax": "helper_call", "explicit_value": True},
            ],
        },
    },
    "exchange_call_arg": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:130:41"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["helper_call"],
            "consumer_kinds": ["call_arg"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:130:41", "context": "call_arg", "syntax": "helper_call", "explicit_value": True},
            ],
        },
    },
    "exchange_syntax_var": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:134:13"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["yield_in_channels"],
            "consumer_kinds": ["var_init"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:134:13", "context": "var_init", "syntax": "yield_in_channels", "explicit_value": True},
            ],
        },
    },
    "exchange_syntax_nil": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:139:13"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["yield_in_channels"],
            "consumer_kinds": ["var_init"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:139:13", "context": "var_init", "syntax": "yield_in_channels", "explicit_value": False},
            ],
        },
    },
    "exchange_syntax_return": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:144:12"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["yield_in_channels"],
            "consumer_kinds": ["return_value"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:144:12", "context": "return_value", "syntax": "yield_in_channels", "explicit_value": True},
            ],
        },
    },
    "exchange_syntax_stmt": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:148:5"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["yield_in_channels"],
            "consumer_kinds": ["expr_stmt"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:148:5", "context": "expr_stmt", "syntax": "yield_in_channels", "explicit_value": True},
            ],
        },
    },
    "exchange_syntax_call_arg": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
        "contains_yield_exchange": True,
        "yield_exchange_count": 1,
        "yield_exchange_sites": ["tests/fixtures/meta_yield_surface.oren:153:22"],
        "yield_exchange_surface": {
            "version": 1,
            "surface": "channel_resume_v0",
            "yield_value_observer": "explicit_channel_arg",
            "resume_value_source": "explicit_channel_arg",
            "caller_resume_values": True,
            "generator_channel": True,
            "yield_channel_arg_index": 0,
            "resume_channel_arg_index": 1,
            "value_arg_index": 2,
            "syntax_kinds": ["yield_in_channels"],
            "consumer_kinds": ["call_arg"],
            "exchange_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:153:22", "context": "call_arg", "syntax": "yield_in_channels", "explicit_value": True},
            ],
        },
    },
    "exchange_nested_only": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
        "yield_lowering": None,
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
