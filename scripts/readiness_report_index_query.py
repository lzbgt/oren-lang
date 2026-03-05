#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter readiness_index.jsonl by fields and time range."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--profile",
        default="",
        help="Filter by profile (exact match)",
    )
    parser.add_argument(
        "--overall",
        default="",
        help="Filter by overall (PASS/FAIL)",
    )
    parser.add_argument(
        "--tag",
        default="",
        help="Filter by tag",
    )
    parser.add_argument(
        "--git",
        default="",
        help="Filter by git_rev prefix",
    )
    parser.add_argument(
        "--since",
        default="",
        help="Include entries >= timestamp (YYYYMMDD_HHMMSS)",
    )
    parser.add_argument(
        "--until",
        default="",
        help="Include entries <= timestamp (YYYYMMDD_HHMMSS)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit to last N entries after filtering (0=all)",
    )
    parser.add_argument(
        "--sort",
        default="asc",
        choices=["asc", "desc"],
        help="Sort order by timestamp (default: asc)",
    )
    parser.add_argument(
        "--out",
        default="build/reports/readiness_index_query.jsonl",
        help="Output JSONL path (use '-' for stdout)",
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


def match(entry: Dict[str, Any], args: argparse.Namespace) -> bool:
    if args.profile and entry.get("profile") != args.profile:
        return False
    if args.overall and entry.get("overall") != args.overall:
        return False
    if args.tag and entry.get("tag") != args.tag:
        return False
    if args.git:
        git_rev = str(entry.get("git_rev", ""))
        if not git_rev.startswith(args.git):
            return False
    ts = str(entry.get("timestamp", ""))
    if args.since and ts < args.since:
        return False
    if args.until and ts > args.until:
        return False
    return True


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    if path == "-":
        for entry in entries:
            sys.stdout.write(json.dumps(entry, separators=(",", ":")) + "\n")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    filtered = [e for e in entries if match(e, args)]
    filtered.sort(key=lambda e: str(e.get("timestamp", "")), reverse=(args.sort == "desc"))
    if args.limit and args.limit > 0:
        filtered = filtered[-args.limit :] if args.sort == "asc" else filtered[: args.limit]
    write_jsonl(args.out, filtered)
    if args.out != "-":
        print(f"OK: wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
