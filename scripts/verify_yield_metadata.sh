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

expected_names = {"no_yield", "one_yield", "control_yield", "nested_only"}
if set(by_name) != expected_names:
    raise SystemExit(f"unexpected function names: {sorted(by_name)!r}")

expected = {
    "no_yield": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
    },
    "one_yield": {
        "contains_yield": True,
        "yield_stmt_count": 1,
        "yield_stmt_sites": ["tests/fixtures/meta_yield_surface.oren:6:5"],
    },
    "control_yield": {
        "contains_yield": True,
        "yield_stmt_count": 2,
        "yield_stmt_sites": [
            "tests/fixtures/meta_yield_surface.oren:12:9",
            "tests/fixtures/meta_yield_surface.oren:15:9",
        ],
    },
    "nested_only": {
        "contains_yield": False,
        "yield_stmt_count": 0,
        "yield_stmt_sites": [],
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
