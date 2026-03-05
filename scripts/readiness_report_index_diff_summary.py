#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare readiness_index.jsonl summaries (stats + streak)."
    )
    parser.add_argument("--left", required=True, help="Left index JSONL")
    parser.add_argument("--right", required=True, help="Right index JSONL")
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_diff_summary.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_diff_summary.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit to last N entries per side (0=all)",
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


def compute_stats(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    pass_rate = (passes / total * 100) if total else 0.0
    durations = [e.get("total_duration_sec") for e in entries if isinstance(e.get("total_duration_sec"), int)]
    avg_dur = round(sum(durations) / len(durations), 1) if durations else None
    latest = max((str(e.get("timestamp", "")) for e in entries), default="")
    streak_kind = ""
    streak_len = 0
    if entries:
        last = entries[-1].get("overall", "")
        if isinstance(last, str):
            streak_kind = last
            for entry in reversed(entries):
                if entry.get("overall") == last:
                    streak_len += 1
                else:
                    break
    return {
        "total": total,
        "passes": passes,
        "fails": fails,
        "pass_rate": round(pass_rate, 1),
        "avg_duration_sec": avg_dur,
        "latest_timestamp": latest,
        "streak": {"kind": streak_kind, "len": streak_len},
    }


def diff_stats(left: Dict[str, Any], right: Dict[str, Any]) -> Dict[str, Any]:
    def delta(a, b):
        if a is None or b is None:
            return None
        try:
            return round(b - a, 1) if isinstance(a, (int, float)) else None
        except TypeError:
            return None

    return {
        "total": right["total"] - left["total"],
        "passes": right["passes"] - left["passes"],
        "fails": right["fails"] - left["fails"],
        "pass_rate": delta(left["pass_rate"], right["pass_rate"]),
        "avg_duration_sec": delta(left["avg_duration_sec"], right["avg_duration_sec"]),
        "streak": {
            "kind": right["streak"]["kind"],
            "len": right["streak"]["len"],
        },
    }


def write_markdown(path: str, left_path: str, right_path: str, left: Dict[str, Any], right: Dict[str, Any], delta: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index summary diff\n\n")
        f.write(f"- left: `{left_path}`\n")
        f.write(f"- right: `{right_path}`\n\n")
        f.write("| Metric | Left | Right | Δ |\n")
        f.write("| --- | --- | --- | --- |\n")
        f.write(f"| total | {left['total']} | {right['total']} | {delta['total']} |\n")
        f.write(f"| passes | {left['passes']} | {right['passes']} | {delta['passes']} |\n")
        f.write(f"| fails | {left['fails']} | {right['fails']} | {delta['fails']} |\n")
        f.write(f"| pass_rate | {left['pass_rate']} | {right['pass_rate']} | {delta['pass_rate']} |\n")
        f.write(f"| avg_duration_sec | {left['avg_duration_sec']} | {right['avg_duration_sec']} | {delta['avg_duration_sec']} |\n")
        f.write(f"| latest_timestamp | {left['latest_timestamp']} | {right['latest_timestamp']} | - |\n")
        f.write(f"| streak | {left['streak']['kind']} x{left['streak']['len']} | {right['streak']['kind']} x{right['streak']['len']} | - |\n")


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
    if args.limit and args.limit > 0:
        left_entries = left_entries[-args.limit :]
        right_entries = right_entries[-args.limit :]
    left_stats = compute_stats(left_entries)
    right_stats = compute_stats(right_entries)
    delta = diff_stats(left_stats, right_stats)
    payload = {"left": left_stats, "right": right_stats, "delta": delta}
    write_markdown(args.out_md, args.left, args.right, left_stats, right_stats, delta)
    write_json(args.out_json, payload)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
