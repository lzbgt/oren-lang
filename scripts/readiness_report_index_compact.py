#!/usr/bin/env python3
import argparse
import json
import os
import sys
import tempfile
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compact readiness_index.jsonl (dedupe + optional keep last N)."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Input JSONL path",
    )
    parser.add_argument(
        "--out",
        default="",
        help="Output path (default: in-place)",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=0,
        help="Keep last N entries after dedupe (0=all)",
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


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
        return 0
    entries = dedupe_entries(entries)
    entries.sort(key=lambda e: str(e.get("timestamp", "")))
    if args.keep and args.keep > 0:
        entries = entries[-args.keep :]
    out_path = args.out or args.index
    if out_path == args.index:
        tmp_dir = os.path.dirname(out_path) or "."
        fd, tmp_path = tempfile.mkstemp(prefix="readiness_index_", suffix=".jsonl", dir=tmp_dir)
        os.close(fd)
        try:
            write_jsonl(tmp_path, entries)
            os.replace(tmp_path, out_path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    else:
        write_jsonl(out_path, entries)
    print(f"OK: wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
