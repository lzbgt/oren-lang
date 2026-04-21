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
                "target": "single_top_level_bare_yield_v0",
                "ready": True,
                "status": "ready",
                "blockers": [],
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
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["multiple_yields", "non_top_level_yield"],
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
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["live_locals_across_yield"],
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
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["live_locals_across_yield"],
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
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["non_top_level_yield"],
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
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["live_locals_across_yield"],
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
            "locals_across_yield": [],
            "yield_points": [
                {"id": 0, "site": "tests/fixtures/meta_yield_surface.oren:56:5", "resume_state": 1},
            ],
            "states": [
                {"id": 0, "kind": "entry"},
                {"id": 1, "kind": "resume", "after_yield_site": "tests/fixtures/meta_yield_surface.oren:56:5"},
            ],
            "lowering_v0": {
                "version": 1,
                "target": "single_top_level_bare_yield_v0",
                "ready": False,
                "status": "blocked",
                "blockers": ["nested_function_literal"],
            },
        },
    },
}

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
