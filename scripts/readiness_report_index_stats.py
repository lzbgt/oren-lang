#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
from collections import defaultdict
from typing import Any, Dict, List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute readiness index statistics."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_stats.md",
        help="Markdown output path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_stats.json",
        help="JSON output path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=200,
        help="Limit to last N entries (default: 200, 0=all)",
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


def fmt_timestamp(ts: str) -> str:
    if not ts:
        return "-"
    try:
        val = dt.datetime.strptime(ts, "%Y%m%d_%H%M%S")
        return val.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ts


def avg(nums: List[int]) -> Optional[float]:
    if not nums:
        return None
    return sum(nums) / len(nums)


def compute_stats(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(entries)
    overall_counts = defaultdict(int)
    profile_counts = defaultdict(lambda: defaultdict(int))
    tag_counts = defaultdict(lambda: defaultdict(int))
    durations = []
    latest = entries[-1] if entries else {}
    streak_kind = ""
    streak_len = 0
    if entries:
        last_overall = entries[-1].get("overall", "")
        if isinstance(last_overall, str):
            streak_kind = last_overall
            for entry in reversed(entries):
                if entry.get("overall") == last_overall:
                    streak_len += 1
                else:
                    break

    for entry in entries:
        overall = entry.get("overall", "UNKNOWN")
        profile = entry.get("profile", "unknown")
        tag = entry.get("tag", "none")
        overall_counts[overall] += 1
        profile_counts[profile][overall] += 1
        tag_counts[tag][overall] += 1
        dur = entry.get("total_duration_sec")
        if isinstance(dur, int):
            durations.append(dur)

    pass_count = overall_counts.get("PASS", 0)
    fail_count = overall_counts.get("FAIL", 0)
    pass_rate = (pass_count / total * 100) if total else 0.0
    duration_avg = avg(durations)
    duration_max = max(durations) if durations else None
    duration_min = min(durations) if durations else None

    return {
        "total": total,
        "pass_rate": pass_rate,
        "overall_counts": dict(overall_counts),
        "profile_counts": {k: dict(v) for k, v in profile_counts.items()},
        "tag_counts": {k: dict(v) for k, v in tag_counts.items()},
        "duration_avg": duration_avg,
        "duration_min": duration_min,
        "duration_max": duration_max,
        "streak": {
            "kind": streak_kind,
            "len": streak_len,
        },
        "latest": {
            "timestamp": latest.get("timestamp", ""),
            "profile": latest.get("profile", ""),
            "overall": latest.get("overall", ""),
            "git_rev": latest.get("git_rev", ""),
            "tag": latest.get("tag", ""),
            "status_overview_md": latest.get("status_overview_md", ""),
        },
    }


def write_markdown(path: str, stats: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    total = stats["total"]
    pass_rate = stats["pass_rate"]
    overall_counts = stats["overall_counts"]
    duration_avg = stats["duration_avg"]
    duration_min = stats["duration_min"]
    duration_max = stats["duration_max"]
    latest = stats["latest"]
    streak = stats.get("streak", {})

    def fmt_float(val: Optional[float]) -> str:
        if val is None:
            return "-"
        return f"{val:.1f}"

    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index stats\n\n")
        f.write(f"- total entries: {total}\n")
        f.write(f"- pass rate: {pass_rate:.1f}%\n")
        f.write(f"- pass: {overall_counts.get('PASS', 0)}\n")
        f.write(f"- fail: {overall_counts.get('FAIL', 0)}\n")
        if streak:
            f.write(f"- streak: {streak.get('kind','-')} x{streak.get('len','-')}\n")
        f.write("\n")
        f.write("## Duration (sec)\n\n")
        f.write(f"- avg: {fmt_float(duration_avg)}\n")
        f.write(f"- min: {duration_min if duration_min is not None else '-'}\n")
        f.write(f"- max: {duration_max if duration_max is not None else '-'}\n")
        f.write("\n")
        f.write("## Latest\n\n")
        f.write(f"- timestamp: {fmt_timestamp(latest.get('timestamp',''))}\n")
        f.write(f"- profile: {latest.get('profile','-')}\n")
        f.write(f"- overall: {latest.get('overall','-')}\n")
        f.write(f"- git: {latest.get('git_rev','-')}\n")
        f.write(f"- tag: {latest.get('tag','-')}\n")
        if latest.get("status_overview_md"):
            f.write(f"- status overview: {latest.get('status_overview_md')}\n")
        f.write("\n")
        f.write("## By profile\n\n")
        f.write("| Profile | Pass | Fail | Total |\n")
        f.write("| --- | --- | --- | --- |\n")
        for profile, counts in sorted(stats["profile_counts"].items()):
            p = counts.get("PASS", 0)
            fl = counts.get("FAIL", 0)
            tot = sum(counts.values())
            f.write(f"| {profile} | {p} | {fl} | {tot} |\n")
        f.write("\n")
        f.write("## By tag\n\n")
        f.write("| Tag | Pass | Fail | Total |\n")
        f.write("| --- | --- | --- | --- |\n")
        for tag, counts in sorted(stats["tag_counts"].items()):
            p = counts.get("PASS", 0)
            fl = counts.get("FAIL", 0)
            tot = sum(counts.values())
            f.write(f"| {tag} | {p} | {fl} | {tot} |\n")


def write_json(path: str, stats: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    if args.limit and args.limit > 0:
        entries = entries[-args.limit :]
    stats = compute_stats(entries)
    write_markdown(args.out_md, stats)
    write_json(args.out_json, stats)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
