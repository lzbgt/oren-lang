#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List


DEFAULT_SCHEMA = "docs/readiness_index.schema.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate readiness_index.jsonl against JSON schema."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--schema",
        default=DEFAULT_SCHEMA,
        help="Path to JSON schema",
    )
    parser.add_argument(
        "--max-errors",
        type=int,
        default=50,
        help="Maximum errors to print before exiting (default: 50)",
    )
    return parser.parse_args()


def load_schema(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_jsonl(path: str) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    if not os.path.exists(path):
        return entries
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                entries.append(entry)
    return entries


def validate_entry(entry: Dict[str, Any], schema: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    required = schema.get("required", [])
    properties = schema.get("properties", {})

    for key in required:
        if key not in entry:
            errors.append(f"missing required field: {key}")

    for key, spec in properties.items():
        if key not in entry:
            continue
        val = entry[key]
        t = spec.get("type")
        if t == "string":
            if not isinstance(val, str):
                errors.append(f"{key}: expected string, got {type(val).__name__}")
                continue
            pattern = spec.get("pattern")
            if pattern and not re.match(pattern, val):
                errors.append(f"{key}: does not match pattern {pattern}")
            enum_vals = spec.get("enum")
            if enum_vals and val not in enum_vals:
                errors.append(f"{key}: expected one of {enum_vals}, got {val}")
        elif t == "boolean":
            if not isinstance(val, bool):
                errors.append(f"{key}: expected boolean, got {type(val).__name__}")
        elif t == "integer":
            if not isinstance(val, int):
                errors.append(f"{key}: expected integer, got {type(val).__name__}")
                continue
            minimum = spec.get("minimum")
            if minimum is not None and val < minimum:
                errors.append(f"{key}: expected >= {minimum}, got {val}")
    return errors


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.schema):
        print(f"ERROR: schema not found: {args.schema}", file=sys.stderr)
        return 2
    schema = load_schema(args.schema)
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
        return 0
    error_count = 0
    for idx, entry in enumerate(entries, 1):
        errors = validate_entry(entry, schema)
        for err in errors:
            print(f"{args.index}:{idx}: {err}", file=sys.stderr)
            error_count += 1
            if error_count >= args.max_errors:
                break
        if error_count >= args.max_errors:
            break

    if error_count > 0:
        print(f"FAIL: {error_count} schema validation error(s)", file=sys.stderr)
        return 2
    print("OK: readiness index schema validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
