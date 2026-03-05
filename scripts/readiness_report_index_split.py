#!/usr/bin/env python3
import argparse
import json
import os
import re
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Split readiness_index.jsonl into per-profile or per-tag JSONL files."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-dir",
        default="build/reports/readiness_splits",
        help="Output directory for splits",
    )
    parser.add_argument(
        "--mode",
        choices=["profile", "tag"],
        default="profile",
        help="Split mode (default: profile)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit to last N entries before splitting (0=all)",
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


def slugify(value: str) -> str:
    if not value:
        return "unknown"
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9_.-]+", "-", value)
    return value or "unknown"


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if args.limit and args.limit > 0:
        entries = entries[-args.limit :]

    buckets: Dict[str, List[Dict[str, Any]]] = {}
    for entry in entries:
        key = str(entry.get(args.mode, "")) if args.mode in entry else ""
        bucket = slugify(key)
        buckets.setdefault(bucket, []).append(entry)

    os.makedirs(args.out_dir, exist_ok=True)
    outputs: List[Tuple[str, int]] = []
    for bucket, items in sorted(buckets.items()):
        out_path = os.path.join(args.out_dir, f"{args.mode}_{bucket}.jsonl")
        write_jsonl(out_path, items)
        outputs.append((out_path, len(items)))

    for path, count in outputs:
        print(f"{path}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
