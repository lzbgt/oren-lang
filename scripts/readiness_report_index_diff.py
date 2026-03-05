#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Diff two readiness_index.jsonl files (counts + overlap)."
    )
    parser.add_argument("--left", required=True, help="Left JSONL path")
    parser.add_argument("--right", required=True, help="Right JSONL path")
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_diff.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_diff.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=5,
        help="Sample size for left-only/right-only lists (default: 5)",
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


def summary(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    latest_ts = max((str(e.get("timestamp", "")) for e in entries), default="")
    pass_rate = (passes / total * 100) if total else 0.0
    return {
        "total": total,
        "passes": passes,
        "fails": fails,
        "pass_rate": round(pass_rate, 1),
        "latest_timestamp": latest_ts,
    }


def write_markdown(
    path: str,
    left_path: str,
    right_path: str,
    left_summary: Dict[str, Any],
    right_summary: Dict[str, Any],
    overlap: int,
    left_only: List[Tuple[str, str, str, str]],
    right_only: List[Tuple[str, str, str, str]],
) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index diff\n\n")
        f.write(f"- left: `{left_path}`\n")
        f.write(f"- right: `{right_path}`\n\n")
        f.write("## Summary\n\n")
        f.write("| Side | Total | Pass | Fail | Pass % | Latest |\n")
        f.write("| --- | --- | --- | --- | --- | --- |\n")
        f.write(
            f"| left | {left_summary['total']} | {left_summary['passes']} | {left_summary['fails']} | "
            f"{left_summary['pass_rate']} | {left_summary['latest_timestamp']} |\n"
        )
        f.write(
            f"| right | {right_summary['total']} | {right_summary['passes']} | {right_summary['fails']} | "
            f"{right_summary['pass_rate']} | {right_summary['latest_timestamp']} |\n"
        )
        f.write(f"\n- overlap: {overlap}\n")
        f.write(f"- left-only: {len(left_only)}\n")
        f.write(f"- right-only: {len(right_only)}\n\n")
        f.write("## Samples\n\n")
        f.write("Left-only:\n\n")
        for item in left_only:
            f.write(f"- {item}\n")
        if not left_only:
            f.write("- none\n")
        f.write("\nRight-only:\n\n")
        for item in right_only:
            f.write(f"- {item}\n")
        if not right_only:
            f.write("- none\n")


def write_json(path: str, payload: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    left_entries = parse_jsonl(args.left)
    right_entries = parse_jsonl(args.right)
    if not left_entries:
        print(f"WARN: no entries found in {args.left}", file=sys.stderr)
    if not right_entries:
        print(f"WARN: no entries found in {args.right}", file=sys.stderr)

    left_keys = {entry_key(e) for e in left_entries}
    right_keys = {entry_key(e) for e in right_entries}
    overlap = len(left_keys & right_keys)
    left_only = sorted(left_keys - right_keys)
    right_only = sorted(right_keys - left_keys)

    left_summary = summary(left_entries)
    right_summary = summary(right_entries)
    payload = {
        "left": left_summary,
        "right": right_summary,
        "overlap": overlap,
        "left_only": len(left_only),
        "right_only": len(right_only),
        "left_only_sample": left_only[: args.sample],
        "right_only_sample": right_only[: args.sample],
    }
    write_markdown(
        args.out_md,
        args.left,
        args.right,
        left_summary,
        right_summary,
        overlap,
        left_only[: args.sample],
        right_only[: args.sample],
    )
    write_json(args.out_json, payload)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
