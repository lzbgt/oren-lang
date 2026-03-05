#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Lint readiness_index.jsonl for ordering and duplicates."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--max-warnings",
        type=int,
        default=50,
        help="Maximum warnings to print (default: 50)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors (non-zero exit)",
    )
    return parser.parse_args()


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


def entry_key(entry: Dict[str, Any]) -> Tuple[str, str, str, str]:
    return (
        str(entry.get("timestamp", "")),
        str(entry.get("profile", "")),
        str(entry.get("git_rev", "")),
        str(entry.get("tag", "")),
    )


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
        return 0

    warnings = 0
    last_ts = ""
    seen_keys = set()
    for idx, entry in enumerate(entries, 1):
        ts = str(entry.get("timestamp", ""))
        if last_ts and ts < last_ts:
            print(f"{args.index}:{idx}: timestamp out of order: {ts} < {last_ts}", file=sys.stderr)
            warnings += 1
        last_ts = ts
        key = entry_key(entry)
        if key in seen_keys:
            print(f"{args.index}:{idx}: duplicate entry key: {key}", file=sys.stderr)
            warnings += 1
        else:
            seen_keys.add(key)
        if warnings >= args.max_warnings:
            break

    if warnings > 0:
        print(f"WARN: {warnings} lint warning(s)", file=sys.stderr)
        return 2 if args.strict else 1

    print("OK: readiness index lint clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
