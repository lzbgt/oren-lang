#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge readiness_index.jsonl files with optional de-duplication."
    )
    parser.add_argument(
        "--out",
        default="build/reports/readiness_index_merged.jsonl",
        help="Output JSONL path",
    )
    parser.add_argument(
        "--dedupe",
        action="store_true",
        help="Deduplicate entries by (timestamp, profile, git_rev, tag)",
    )
    parser.add_argument(
        "--sort",
        default="asc",
        choices=["asc", "desc"],
        help="Sort order by timestamp (default: asc)",
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Input JSONL files",
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


def dedupe_entries(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen: Dict[Tuple[str, str, str, str], Dict[str, Any]] = {}
    for entry in entries:
        key = (
            str(entry.get("timestamp", "")),
            str(entry.get("profile", "")),
            str(entry.get("git_rev", "")),
            str(entry.get("tag", "")),
        )
        seen[key] = entry
    return list(seen.values())


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    entries: List[Dict[str, Any]] = []
    for path in args.inputs:
        entries.extend(parse_jsonl(path))
    if not entries:
        print("WARN: no entries found in inputs", file=sys.stderr)
    if args.dedupe:
        entries = dedupe_entries(entries)
    entries.sort(key=lambda e: str(e.get("timestamp", "")), reverse=(args.sort == "desc"))
    write_jsonl(args.out, entries)
    print(f"OK: wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
