#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize the latest readiness index entries by profile/tag."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_latest.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_latest.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--groups",
        default="profile,tag",
        help="Comma-separated groups to summarize (profile,tag).",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


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


def entry_timestamp(entry: Dict[str, Any]) -> str:
    return str(entry.get("timestamp", ""))


def pick_latest(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    latest = {}
    latest_ts = ""
    for entry in entries:
        ts = entry_timestamp(entry)
        if ts >= latest_ts:
            latest_ts = ts
            latest = entry
    return latest


def group_key(entry: Dict[str, Any], group: str) -> str:
    if group == "profile":
        return str(entry.get("profile", "unknown")) or "unknown"
    if group == "tag":
        return str(entry.get("tag", "none")) or "none"
    return str(entry.get(group, "unknown")) or "unknown"


def summarize(entries: List[Dict[str, Any]], groups: List[str]) -> Dict[str, Any]:
    summary: Dict[str, Any] = {
        "total": len(entries),
        "latest": pick_latest(entries),
        "groups": {},
    }
    for group in groups:
        buckets: Dict[str, List[Dict[str, Any]]] = {}
        for entry in entries:
            key = group_key(entry, group)
            buckets.setdefault(key, []).append(entry)
        group_latest: Dict[str, Dict[str, Any]] = {}
        for key, items in buckets.items():
            group_latest[key] = pick_latest(items)
        summary["groups"][group] = group_latest
    return summary


def write_markdown(path: str, summary: Dict[str, Any], groups: List[str]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index latest\n\n")
        f.write(f"- total entries: {summary.get('total', 0)}\n")
        latest = summary.get("latest", {})
        f.write(f"- latest timestamp: {latest.get('timestamp','-')}\n")
        f.write(f"- latest profile: {latest.get('profile','-')}\n")
        f.write(f"- latest overall: {latest.get('overall','-')}\n")
        f.write("\n")
        for group in groups:
            f.write(f"## Latest by {group}\n\n")
            f.write("| Key | Timestamp | Overall | Profile | Tag | Git | Report |\n")
            f.write("| --- | --- | --- | --- | --- | --- | --- |\n")
            items = summary.get("groups", {}).get(group, {})
            for key in sorted(items.keys()):
                entry = items[key]
                f.write(
                    f"| {key} | {entry.get('timestamp','-')} | {entry.get('overall','-')} | "
                    f"{entry.get('profile','-')} | {entry.get('tag','-')} | {entry.get('git_rev','-')} | "
                    f"{entry.get('report','-')} |\n"
                )
            f.write("\n")


def write_json(path: str, summary: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    summary = summarize(entries, groups)
    write_markdown(args.out_md, summary, groups)
    write_json(args.out_json, summary)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
