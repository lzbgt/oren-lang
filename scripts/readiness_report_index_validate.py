#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


REQUIRED_FIELDS = {
    "timestamp": str,
    "profile": str,
    "overall": str,
    "dry_run": bool,
    "total_duration_sec": int,
    "git_rev": str,
    "git_dirty": str,
    "report": str,
    "json": str,
    "log_dir": str,
}
OPTIONAL_FIELDS = {
    "tag": str,
    "status_snapshot_md": str,
    "status_snapshot_json": str,
    "status_faq_md": str,
    "status_faq_json": str,
    "status_matrix_md": str,
    "status_matrix_json": str,
    "status_overview_md": str,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate readiness_index.jsonl structure."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--max-errors",
        type=int,
        default=50,
        help="Maximum errors to print before exiting (default: 50)",
    )
    return parser.parse_args()


def load_lines(path: str) -> List[str]:
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def validate_entry(entry: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    for key, expected_type in REQUIRED_FIELDS.items():
        if key not in entry:
            errors.append(f"missing field: {key}")
            continue
        val = entry[key]
        if expected_type is int:
            if not isinstance(val, int):
                errors.append(f"field {key} expected int, got {type(val).__name__}")
        elif expected_type is bool:
            if not isinstance(val, bool):
                errors.append(f"field {key} expected bool, got {type(val).__name__}")
        else:
            if not isinstance(val, expected_type):
                errors.append(f"field {key} expected {expected_type.__name__}, got {type(val).__name__}")
    for key, expected_type in OPTIONAL_FIELDS.items():
        if key not in entry:
            continue
        val = entry[key]
        if val is None:
            errors.append(f"field {key} expected {expected_type.__name__}, got None")
            continue
        if not isinstance(val, expected_type):
            errors.append(f"field {key} expected {expected_type.__name__}, got {type(val).__name__}")
    overall = entry.get("overall")
    if isinstance(overall, str) and overall not in ("PASS", "FAIL"):
        errors.append(f"field overall expected PASS/FAIL, got {overall}")
    return errors


def main() -> int:
    args = parse_args()
    lines = load_lines(args.index)
    if not lines:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
        return 0

    error_count = 0
    for lineno, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"{args.index}:{lineno}: invalid JSON: {exc}", file=sys.stderr)
            error_count += 1
            if error_count >= args.max_errors:
                break
            continue
        if not isinstance(entry, dict):
            print(f"{args.index}:{lineno}: entry is not an object", file=sys.stderr)
            error_count += 1
            if error_count >= args.max_errors:
                break
            continue
        errors = validate_entry(entry)
        for err in errors:
            print(f"{args.index}:{lineno}: {err}", file=sys.stderr)
            error_count += 1
            if error_count >= args.max_errors:
                break
        if error_count >= args.max_errors:
            break

    if error_count > 0:
        print(f"FAIL: {error_count} validation error(s)", file=sys.stderr)
        return 2
    print("OK: readiness index validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
