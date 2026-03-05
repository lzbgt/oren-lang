#!/usr/bin/env python3
import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Trim readiness_index.jsonl by timestamp range."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--since",
        default="",
        help="Keep entries with timestamp >= since (YYYYMMDD_HHMMSS)",
    )
    parser.add_argument(
        "--since-days",
        type=int,
        default=-1,
        help="Keep entries from the last N days (computed in local time).",
    )
    parser.add_argument(
        "--until",
        default="",
        help="Keep entries with timestamp <= until (YYYYMMDD_HHMMSS)",
    )
    parser.add_argument(
        "--until-days",
        type=int,
        default=-1,
        help="Keep entries up to N days ago (computed in local time).",
    )
    parser.add_argument(
        "--out",
        default="",
        help="Output path (default: in-place)",
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


def keep_entry(entry: Dict[str, Any], since: str, until: str) -> bool:
    ts = str(entry.get("timestamp", ""))
    if since and ts < since:
        return False
    if until and ts > until:
        return False
    return True


def write_jsonl(path: str, entries: List[Dict[str, Any]]) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main() -> int:
    args = parse_args()
    if args.since and args.since_days >= 0:
        print("ERROR: use only one of --since or --since-days", file=sys.stderr)
        return 2
    if args.until and args.until_days >= 0:
        print("ERROR: use only one of --until or --until-days", file=sys.stderr)
        return 2
    since = args.since
    until = args.until
    if not since and args.since_days >= 0:
        since = (datetime.now() - timedelta(days=args.since_days)).strftime("%Y%m%d_%H%M%S")
    if not until and args.until_days >= 0:
        until = (datetime.now() - timedelta(days=args.until_days)).strftime("%Y%m%d_%H%M%S")
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
        return 0
    trimmed = [e for e in entries if keep_entry(e, since, until)]
    out_path = args.out or args.index
    if out_path == args.index:
        tmp_dir = os.path.dirname(out_path) or "."
        fd, tmp_path = tempfile.mkstemp(prefix="readiness_index_", suffix=".jsonl", dir=tmp_dir)
        os.close(fd)
        try:
            write_jsonl(tmp_path, trimmed)
            os.replace(tmp_path, out_path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    else:
        write_jsonl(out_path, trimmed)
    print(f"OK: wrote {out_path} (kept {len(trimmed)}/{len(entries)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
