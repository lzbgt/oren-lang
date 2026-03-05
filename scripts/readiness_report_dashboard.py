#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate readiness dashboard HTML from readiness_index.jsonl."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-html",
        default="build/reports/readiness_dashboard.html",
        help="Output HTML path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Max entries to include (default: 20)",
    )
    parser.add_argument(
        "--rollup-days",
        type=int,
        default=30,
        help="Days to include in rollup (default: 30, 0=all)",
    )
    parser.add_argument(
        "--title",
        default="Oren readiness dashboard",
        help="Title for dashboard",
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


def fmt_timestamp(ts: str) -> str:
    if not ts:
        return "-"
    try:
        val = dt.datetime.strptime(ts, "%Y%m%d_%H%M%S")
        return val.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ts


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
                bucket["_dur_count"] = 0
            bucket["avg_duration_sec"] += dur
            bucket["_dur_count"] += 1

    rollup = []
    for day in sorted(by_day.keys()):
        bucket = by_day[day]
        dur_count = bucket.pop("_dur_count", 0)
        if dur_count > 0:
            bucket["avg_duration_sec"] = round(bucket["avg_duration_sec"] / dur_count, 1)
        else:
            bucket["avg_duration_sec"] = None
        total = bucket["total"]
        bucket["pass_rate"] = round((bucket["pass"] / total * 100), 1) if total else 0.0
        rollup.append(bucket)
    return rollup


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
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    entries_sorted = sorted(entries, key=lambda e: str(e.get("timestamp", "")))
    if args.limit and args.limit > 0:
        entries_view = entries_sorted[-args.limit :]
    else:
        entries_view = entries_sorted
    rollup = compute_rollup(entries_sorted)
    if args.rollup_days and args.rollup_days > 0:
        rollup = rollup[-args.rollup_days :]

    total = len(entries_sorted)
    passes = sum(1 for e in entries_sorted if e.get("overall") == "PASS")
    fails = sum(1 for e in entries_sorted if e.get("overall") == "FAIL")
    pass_rate = f"{(passes / total * 100):.1f}%" if total else "-"
    streak = compute_streak(entries_sorted)
    latest = entries_sorted[-1] if entries_sorted else {}

    rows = []
    for entry in reversed(entries_view):
        overall = entry.get("overall", "-")
        cls = "ok" if overall == "PASS" else "fail" if overall == "FAIL" else "unknown"
        rows.append(
            "<tr>"
            f"<td>{fmt_timestamp(entry.get('timestamp',''))}</td>"
            f"<td>{entry.get('profile','-')}</td>"
            f"<td class='{cls}'>{overall}</td>"
            f"<td>{entry.get('total_duration_sec','-')}</td>"
            f"<td>{entry.get('git_rev','-')}</td>"
            f"<td>{entry.get('tag','-')}</td>"
            f"<td><code>{entry.get('report','-')}</code></td>"
            "</tr>"
        )

    rollup_rows = []
    for row in rollup:
        rollup_rows.append(
            "<tr>"
            f"<td>{row['day']}</td>"
            f"<td>{row['total']}</td>"
            f"<td>{row['pass']}</td>"
            f"<td>{row['fail']}</td>"
            f"<td>{row['pass_rate']:.1f}</td>"
            f"<td>{row['avg_duration_sec'] if row['avg_duration_sec'] is not None else '-'}</td>"
            "</tr>"
        )

    latest_text = "-"
    if latest:
        latest_text = f"{fmt_timestamp(latest.get('timestamp',''))} ({latest.get('overall','-')})"

    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>{args.title}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 24px; color: #111; }}
    h1 {{ margin-bottom: 8px; }}
    h2 {{ margin-top: 28px; }}
    .meta {{ margin-bottom: 16px; }}
    .grid {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }}
    .card {{ border: 1px solid #ddd; padding: 12px; border-radius: 6px; background: #fafafa; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; font-size: 13px; }}
    th {{ background: #f2f2f2; text-align: left; }}
    .ok {{ color: #0a7a2f; font-weight: bold; }}
    .fail {{ color: #b00020; font-weight: bold; }}
    .unknown {{ color: #555; }}
    code {{ background: #f7f7f7; padding: 2px 4px; }}
  </style>
</head>
<body>
  <h1>{args.title}</h1>
  <div class="meta">Index: <code>{args.index}</code></div>
  <div class="grid">
    <div class="card">
      <div>Total entries</div>
      <div><strong>{total}</strong></div>
    </div>
    <div class="card">
      <div>Pass rate</div>
      <div><strong>{pass_rate}</strong> ({passes} pass / {fails} fail)</div>
    </div>
    <div class="card">
      <div>Streak</div>
      <div><strong>{streak.get('kind','-')}</strong> x{streak.get('len','-')}</div>
    </div>
    <div class="card">
      <div>Latest</div>
      <div><strong>{latest_text}</strong></div>
    </div>
  </div>

  <h2>Recent runs (latest {len(entries_view)})</h2>
  <table>
    <thead>
      <tr>
        <th>Timestamp</th>
        <th>Profile</th>
        <th>Overall</th>
        <th>Duration</th>
        <th>Git</th>
        <th>Tag</th>
        <th>Report</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows)}
    </tbody>
  </table>

  <h2>Daily rollup (last {len(rollup)})</h2>
  <table>
    <thead>
      <tr>
        <th>Day</th>
        <th>Total</th>
        <th>Pass</th>
        <th>Fail</th>
        <th>Pass %</th>
        <th>Avg Dur (s)</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rollup_rows)}
    </tbody>
  </table>
</body>
</html>
"""

    os.makedirs(os.path.dirname(args.out_html), exist_ok=True)
    with open(args.out_html, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"OK: wrote {args.out_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
