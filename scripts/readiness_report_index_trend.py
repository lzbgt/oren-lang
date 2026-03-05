#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute readiness trend metrics over the latest N entries."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--window",
        type=int,
        default=20,
        help="Window size (latest N entries, default: 20).",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_trend.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_trend.json",
        help="Output JSON path",
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


def pass_rate(entries: List[Dict[str, Any]]) -> float:
    total = len(entries)
    if total == 0:
        return 0.0
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    return round(passes / total * 100, 1)


def fail_streak(entries: List[Dict[str, Any]]) -> Tuple[str, int]:
    if not entries:
        return ("-", 0)
    last = entries[-1].get("overall", "")
    if not isinstance(last, str):
        return ("-", 0)
    length = 0
    for entry in reversed(entries):
        if entry.get("overall") == last:
            length += 1
        else:
            break
    return (last, length)


def duration_stats(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    durations = [e.get("total_duration_sec") for e in entries if isinstance(e.get("total_duration_sec"), int)]
    if not durations:
        return {"avg": None, "min": None, "max": None}
    return {
        "avg": round(sum(durations) / len(durations), 1),
        "min": min(durations),
        "max": max(durations),
    }


def compute_trend(entries: List[Dict[str, Any]], window: int) -> Dict[str, Any]:
    total = len(entries)
    if window <= 0:
        window = total
    window_entries = entries[-window:] if window <= total else entries
    if total == 0:
        window_entries = []
    latest = entries[-1] if entries else {}
    streak_kind, streak_len = fail_streak(entries)
    win_streak_kind, win_streak_len = fail_streak(window_entries)
    return {
        "total": total,
        "window": window,
        "window_count": len(window_entries),
        "overall_pass_rate": pass_rate(entries),
        "window_pass_rate": pass_rate(window_entries),
        "latest": {
            "timestamp": latest.get("timestamp", ""),
            "profile": latest.get("profile", ""),
            "overall": latest.get("overall", ""),
            "tag": latest.get("tag", ""),
            "git_rev": latest.get("git_rev", ""),
            "status_overview_md": latest.get("status_overview_md", ""),
        },
        "streak": {
            "kind": streak_kind,
            "len": streak_len,
        },
        "window_streak": {
            "kind": win_streak_kind,
            "len": win_streak_len,
        },
        "duration": {
            "overall": duration_stats(entries),
            "window": duration_stats(window_entries),
        },
    }


def write_markdown(path: str, trend: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index trend\n\n")
        f.write(f"- total entries: {trend['total']}\n")
        f.write(f"- window size: {trend['window']}\n")
        f.write(f"- window entries: {trend['window_count']}\n\n")
        f.write("## Pass rate\n\n")
        f.write(f"- overall: {trend['overall_pass_rate']}%\n")
        f.write(f"- window: {trend['window_pass_rate']}%\n\n")
        f.write("## Streak\n\n")
        f.write(f"- overall: {trend['streak']['kind']} x{trend['streak']['len']}\n")
        f.write(f"- window: {trend['window_streak']['kind']} x{trend['window_streak']['len']}\n\n")
        f.write("## Latest\n\n")
        f.write(f"- timestamp: {trend['latest']['timestamp'] or '-'}\n")
        f.write(f"- profile: {trend['latest']['profile'] or '-'}\n")
        f.write(f"- overall: {trend['latest']['overall'] or '-'}\n")
        f.write(f"- tag: {trend['latest']['tag'] or '-'}\n")
        f.write(f"- git: {trend['latest']['git_rev'] or '-'}\n")
        if trend["latest"].get("status_overview_md"):
            f.write(f"- status overview: {trend['latest']['status_overview_md']}\n")
        f.write("\n")
        f.write("## Duration (sec)\n\n")
        f.write(f"- overall avg/min/max: {trend['duration']['overall']['avg']} / {trend['duration']['overall']['min']} / {trend['duration']['overall']['max']}\n")
        f.write(f"- window avg/min/max: {trend['duration']['window']['avg']} / {trend['duration']['window']['min']} / {trend['duration']['window']['max']}\n")


def write_json(path: str, trend: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(trend, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    trend = compute_trend(entries, args.window)
    write_markdown(args.out_md, trend)
    write_json(args.out_json, trend)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
