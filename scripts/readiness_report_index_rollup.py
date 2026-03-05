#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Roll up readiness_index.jsonl by day."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_rollup.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_rollup.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--limit-days",
        type=int,
        default=30,
        help="Limit to last N days (default: 30, 0=all)",
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


def day_key(timestamp: str) -> str:
    if not timestamp:
        return "unknown"
    try:
        val = dt.datetime.strptime(timestamp, "%Y%m%d_%H%M%S")
        return val.strftime("%Y-%m-%d")
    except Exception:
        return "unknown"


def compute_rollup(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_day: Dict[str, Dict[str, Any]] = {}
    for entry in entries:
        day = day_key(str(entry.get("timestamp", "")))
        if day not in by_day:
            by_day[day] = {
                "day": day,
                "total": 0,
                "pass": 0,
                "fail": 0,
                "avg_duration_sec": None,
                "max_duration_sec": None,
                "min_duration_sec": None,
            }
        bucket = by_day[day]
        bucket["total"] += 1
        if entry.get("overall") == "PASS":
            bucket["pass"] += 1
        elif entry.get("overall") == "FAIL":
            bucket["fail"] += 1
        dur = entry.get("total_duration_sec")
        if isinstance(dur, int):
            if bucket["avg_duration_sec"] is None:
                bucket["avg_duration_sec"] = 0
                bucket["max_duration_sec"] = dur
                bucket["min_duration_sec"] = dur
                bucket["_dur_count"] = 0
            bucket["avg_duration_sec"] += dur
            bucket["_dur_count"] += 1
            bucket["max_duration_sec"] = max(bucket["max_duration_sec"], dur)
            bucket["min_duration_sec"] = min(bucket["min_duration_sec"], dur)

    rollup = []
    for day in sorted(by_day.keys()):
        bucket = by_day[day]
        dur_count = bucket.pop("_dur_count", 0)
        if dur_count > 0:
            bucket["avg_duration_sec"] = round(bucket["avg_duration_sec"] / dur_count, 1)
        else:
            bucket["avg_duration_sec"] = None
            bucket["max_duration_sec"] = None
            bucket["min_duration_sec"] = None
        total = bucket["total"]
        bucket["pass_rate"] = round((bucket["pass"] / total * 100), 1) if total else 0.0
        rollup.append(bucket)
    return rollup


def write_markdown(path: str, rollup: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness rollup (daily)\n\n")
        f.write("| Day | Total | Pass | Fail | Pass % | Avg Dur (s) | Min | Max |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for row in rollup:
            f.write(
                f"| {row['day']} | {row['total']} | {row['pass']} | {row['fail']} | "
                f"{row['pass_rate']:.1f} | {row['avg_duration_sec'] if row['avg_duration_sec'] is not None else '-'} | "
                f"{row['min_duration_sec'] if row['min_duration_sec'] is not None else '-'} | "
                f"{row['max_duration_sec'] if row['max_duration_sec'] is not None else '-'} |\n"
            )


def write_json(path: str, rollup: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rollup, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    rollup = compute_rollup(entries)
    if args.limit_days and args.limit_days > 0:
        rollup = rollup[-args.limit_days :]
    write_markdown(args.out_md, rollup)
    write_json(args.out_json, rollup)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
