#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute readiness index profile summary."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_profiles.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_profiles.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit to last N entries (0=all)",
    )
    parser.add_argument(
        "--tag",
        default="",
        help="Filter by tag (exact match)",
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


def duration_stats(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    durations = [e.get("total_duration_sec") for e in entries if isinstance(e.get("total_duration_sec"), int)]
    if not durations:
        return {"avg": None, "min": None, "max": None}
    return {
        "avg": round(sum(durations) / len(durations), 1),
        "min": min(durations),
        "max": max(durations),
    }


def summarize(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    pass_rate = round((passes / total * 100), 1) if total else 0.0
    latest = {}
    latest_ts = ""
    for entry in entries:
        ts = str(entry.get("timestamp", ""))
        if ts >= latest_ts:
            latest_ts = ts
            latest = entry
    return {
        "total": total,
        "passes": passes,
        "fails": fails,
        "pass_rate": pass_rate,
        "latest": {
            "timestamp": latest.get("timestamp", ""),
            "overall": latest.get("overall", ""),
            "tag": latest.get("tag", ""),
            "git_rev": latest.get("git_rev", ""),
            "status_overview_md": latest.get("status_overview_md", ""),
        },
        "duration": duration_stats(entries),
    }


def compute_profiles(entries: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    profiles: Dict[str, List[Dict[str, Any]]] = {}
    for entry in entries:
        profile = str(entry.get("profile", "unknown")) or "unknown"
        profiles.setdefault(profile, []).append(entry)
    return {profile: summarize(items) for profile, items in profiles.items()}


def write_markdown(path: str, profiles: Dict[str, Dict[str, Any]], total_entries: int) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index profiles\n\n")
        f.write(f"- total entries: {total_entries}\n\n")
        f.write("| Profile | Total | Pass | Fail | Pass % | Latest | Overview | Duration avg/min/max |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for profile in sorted(profiles.keys()):
            data = profiles[profile]
            latest = data.get("latest", {})
            duration = data.get("duration", {})
            latest_label = latest.get("timestamp", "-")
            if latest.get("overall"):
                latest_label = f"{latest_label} ({latest.get('overall','-')})"
            overview = latest.get("status_overview_md", "-") or "-"
            f.write(
                f"| {profile} | {data.get('total',0)} | {data.get('passes',0)} | {data.get('fails',0)} | "
                f"{data.get('pass_rate',0.0)} | {latest_label} | "
                f"{overview} | {duration.get('avg')} / {duration.get('min')} / {duration.get('max')} |\n"
            )


def write_json(path: str, profiles: Dict[str, Dict[str, Any]], total_entries: int) -> None:
    ensure_parent_dir(path)
    payload = {
        "total": total_entries,
        "profiles": profiles,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    if args.tag:
        entries = [e for e in entries if e.get("tag", "") == args.tag]
    if args.limit and args.limit > 0:
        entries = entries[-args.limit :]
    profiles = compute_profiles(entries)
    write_markdown(args.out_md, profiles, len(entries))
    write_json(args.out_json, profiles, len(entries))
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
