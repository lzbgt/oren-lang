#!/usr/bin/env python3
import argparse
import json
import os
import sys
import tempfile
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prune readiness_index.jsonl to the last N valid entries."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=200,
        help="Keep last N entries (default: 200)",
    )
    parser.add_argument(
        "--out",
        default="",
        help="Output path (default: in-place)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write; only report counts",
    )
    return parser.parse_args()


def load_entries(path: str) -> List[Dict[str, Any]]:
    if not os.path.exists(path):
        return []
    entries: List[Dict[str, Any]] = []
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


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    entries = load_entries(args.index)
    total = len(entries)
    keep = max(args.keep, 0)
    kept_entries = entries[-keep:] if keep else []

    print(f"entries: total={total} keep={len(kept_entries)}")
    if args.dry_run:
        return 0

    out_path = args.out or args.index
    if not out_path:
        print("ERROR: no output path available", file=sys.stderr)
        return 2

    if out_path == args.index:
        if not os.path.exists(args.index):
            print("WARN: index does not exist; nothing to write", file=sys.stderr)
            return 0
        fd, tmp_path = tempfile.mkstemp(prefix="readiness_index_", suffix=".jsonl", dir=os.path.dirname(out_path))
        os.close(fd)
        try:
            write_jsonl(tmp_path, kept_entries)
            os.replace(tmp_path, out_path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    else:
        write_jsonl(out_path, kept_entries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
