#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Gate readiness index based on pass rate / fail counts."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--window",
        type=int,
        default=0,
        help="Consider last N entries (0=all)",
    )
    parser.add_argument(
        "--min-pass-rate",
        type=float,
        default=-1.0,
        help="Minimum pass rate percentage (disabled if <0)",
    )
    parser.add_argument(
        "--max-fail-count",
        type=int,
        default=-1,
        help="Maximum fail count allowed (disabled if <0)",
    )
    parser.add_argument(
        "--max-fail-streak",
        type=int,
        default=-1,
        help="Maximum consecutive FAIL streak allowed (disabled if <0)",
    )
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Allow empty index without failing",
    )
    parser.add_argument(
        "--out-json",
        default="",
        help="Write JSON summary to this path",
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


def compute_streak(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not entries:
        return {"kind": "-", "len": 0}
    last = entries[-1].get("overall", "")
    if not isinstance(last, str):
        return {"kind": "-", "len": 0}
    length = 0
    for entry in reversed(entries):
        if entry.get("overall") == last:
            length += 1
        else:
            break
    return {"kind": last, "len": length}


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if args.window and args.window > 0:
        entries = entries[-args.window :]
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    pass_rate = (passes / total * 100) if total else 0.0
    streak = compute_streak(entries)

    summary = {
        "total": total,
        "passes": passes,
        "fails": fails,
        "pass_rate": round(pass_rate, 1),
        "streak": streak,
        "window": args.window,
    }

    if args.out_json:
        os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
        with open(args.out_json, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, sort_keys=True)
            f.write("\n")

    if total == 0 and args.allow_empty:
        print("OK: empty index allowed")
        return 0

    failures: List[str] = []
    if args.min_pass_rate >= 0 and pass_rate < args.min_pass_rate:
        failures.append(f"pass_rate {pass_rate:.1f} < {args.min_pass_rate}")
    if args.max_fail_count >= 0 and fails > args.max_fail_count:
        failures.append(f"fail_count {fails} > {args.max_fail_count}")
    if args.max_fail_streak >= 0 and streak["kind"] == "FAIL" and streak["len"] > args.max_fail_streak:
        failures.append(f"fail_streak {streak['len']} > {args.max_fail_streak}")

    if failures:
        for msg in failures:
            print(f"FAIL: {msg}", file=sys.stderr)
        return 2

    print("OK: readiness index gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
