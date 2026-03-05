#!/usr/bin/env python3
import argparse
import csv
import json
import os
import sys
from typing import Any, Dict, List


FIELDS = [
    "timestamp",
    "profile",
    "overall",
    "total_duration_sec",
    "git_rev",
    "git_dirty",
    "tag",
    "dry_run",
    "report",
    "json",
    "log_dir",
    "status_snapshot_md",
    "status_snapshot_json",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export readiness_index.jsonl to CSV."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-csv",
        default="build/reports/readiness_index.csv",
        help="Output CSV path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit to last N entries (0=all)",
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


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    if args.limit and args.limit > 0:
        entries = entries[-args.limit :]
    ensure_parent_dir(args.out_csv)
    with open(args.out_csv, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for entry in entries:
            row = {field: entry.get(field, "") for field in FIELDS}
            writer.writerow(row)
    print(f"OK: wrote {args.out_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
