#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
from typing import Any, Dict, List, Optional

from status_html_render import (
    limit_status_faq,
    limit_status_matrix,
    limit_status_snapshot,
    render_status_faq,
    render_status_matrix,
    render_status_snapshot,
    status_css,
)
from status_markdown_render import (
    render_status_faq_md,
    render_status_matrix_md,
    render_status_snapshot_md,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate readiness report summary (markdown + HTML) from JSONL index."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Max entries to include (default: 20)",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_summary.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-html",
        default="build/reports/readiness_summary.html",
        help="Output HTML path",
    )
    parser.add_argument(
        "--title",
        default="Oren readiness summary",
        help="Title for summary outputs",
    )
    parser.add_argument(
        "--no-status-sections",
        action="store_true",
        help="Disable embedding status FAQ/snapshot/matrix sections in outputs.",
    )
    parser.add_argument(
        "--status-max-items",
        type=int,
        default=10,
        help="Max items per status section (default: 10, <=0 means no limit).",
    )
    return parser.parse_args()


def parse_jsonl(path: str) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    if not os.path.exists(path):
        return entries
    with open(path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                print(
                    f"WARN: skip invalid JSONL line {lineno}: {exc}",
                    file=sys.stderr,
                )
                continue
            if isinstance(entry, dict):
                entries.append(entry)
    return entries


def read_json(path: str) -> Dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}



def fmt_duration(seconds: Optional[int]) -> str:
    if seconds is None:
        return "-"
    try:
        sec = int(seconds)
    except (TypeError, ValueError):
        return "-"
    if sec < 0:
        return "-"
    mins, secs = divmod(sec, 60)
    if mins == 0:
        return f"{secs}s"
    return f"{mins}m{secs:02d}s"


def fmt_timestamp(ts: str) -> str:
    if not ts:
        return "-"
    try:
        dt_val = dt.datetime.strptime(ts, "%Y%m%d_%H%M%S")
        return dt_val.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ts


def fmt_path_md(value: Any) -> str:
    if value is None:
        return "-"
    text = str(value).strip()
    if not text:
        return "-"
    return f"`{text}`"


def fmt_path_html(value: Any) -> str:
    if value is None:
        return "-"
    text = str(value).strip()
    if not text:
        return "-"
    return f"<code>{text}</code>"


def latest_by(entries: List[Dict[str, Any]], key: str, value: str) -> Optional[Dict[str, Any]]:
    for entry in reversed(entries):
        if entry.get(key) == value:
            return entry
    return None


def write_markdown(
    path: str,
    title: str,
    entries: List[Dict[str, Any]],
    include_status: bool,
    max_items: int,
) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    latest = entries[-1] if entries else None
    last_fail = latest_by(entries, "overall", "FAIL")
    last_pass = latest_by(entries, "overall", "PASS")
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    pass_rate = f"{(passes / total * 100):.1f}%" if total else "-"

    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# {title}\n\n")
        f.write(f"- total entries: {total}\n")
        f.write(f"- pass rate: {pass_rate} ({passes} pass / {fails} fail)\n")
        if latest:
            f.write(f"- latest: {fmt_timestamp(latest.get('timestamp',''))} ({latest.get('overall','-')})\n")
            latest_overview = str(latest.get("status_overview_md", "")).strip()
            if latest_overview:
                f.write(f"- latest status overview: `{latest_overview}`\n")
        if last_fail:
            f.write(
                f"- last fail: {fmt_timestamp(last_fail.get('timestamp',''))} "
                f"(profile={last_fail.get('profile','-')}, git={last_fail.get('git_rev','-')})\n"
            )
        if last_pass:
            f.write(
                f"- last pass: {fmt_timestamp(last_pass.get('timestamp',''))} "
                f"(profile={last_pass.get('profile','-')}, git={last_pass.get('git_rev','-')})\n"
            )
        f.write("\n")
        f.write("| Timestamp | Profile | Overall | Duration | Git | Tag | Report | Overview |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for entry in entries:
            f.write(
                "| "
                + " | ".join(
                    [
                        fmt_timestamp(entry.get("timestamp", "")),
                        str(entry.get("profile", "-")),
                        str(entry.get("overall", "-")),
                        fmt_duration(entry.get("total_duration_sec")),
                        str(entry.get("git_rev", "-")),
                        str(entry.get("tag", "-")),
                        f"`{entry.get('report','-')}`",
                        fmt_path_md(entry.get("status_overview_md")),
                    ]
                )
                + " |\n"
            )
        if include_status and latest:
            status_faq = read_json(str(latest.get("status_faq_json", "")))
            status_snapshot = read_json(str(latest.get("status_snapshot_json", "")))
            status_matrix = read_json(str(latest.get("status_matrix_json", "")))
            sections = [
                render_status_faq_md(status_faq, max_items),
                render_status_snapshot_md(status_snapshot, max_items),
                render_status_matrix_md(status_matrix, max_items),
            ]
            rendered = "\n\n".join(section for section in sections if section)
            if rendered:
                f.write("\n\n")
                f.write(rendered)
                f.write("\n")


def write_html(
    path: str,
    title: str,
    entries: List[Dict[str, Any]],
    include_status: bool,
    max_items: int,
) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    latest = entries[-1] if entries else None
    total = len(entries)
    passes = sum(1 for e in entries if e.get("overall") == "PASS")
    fails = sum(1 for e in entries if e.get("overall") == "FAIL")
    pass_rate = f"{(passes / total * 100):.1f}%" if total else "-"

    def row(entry: Dict[str, Any]) -> str:
        overall = entry.get("overall", "-")
        cls = "ok" if overall == "PASS" else "fail" if overall == "FAIL" else "unknown"
        return (
            "<tr>"
            f"<td>{fmt_timestamp(entry.get('timestamp',''))}</td>"
            f"<td>{entry.get('profile','-')}</td>"
            f"<td class='{cls}'>{overall}</td>"
            f"<td>{fmt_duration(entry.get('total_duration_sec'))}</td>"
            f"<td>{entry.get('git_rev','-')}</td>"
            f"<td>{entry.get('tag','-')}</td>"
            f"<td><code>{entry.get('report','-')}</code></td>"
            f"<td>{fmt_path_html(entry.get('status_overview_md'))}</td>"
            "</tr>"
        )

    summary_latest = "-"
    summary_overview = ""
    if latest:
        summary_latest = f"{fmt_timestamp(latest.get('timestamp',''))} ({latest.get('overall','-')})"
        latest_overview = str(latest.get("status_overview_md", "")).strip()
        if latest_overview:
            summary_overview = f"<div>Latest status overview: <code>{latest_overview}</code></div>"
    status_sections = ""
    if include_status and latest:
        status_faq = read_json(str(latest.get("status_faq_json", "")))
        status_snapshot = read_json(str(latest.get("status_snapshot_json", "")))
        status_matrix = read_json(str(latest.get("status_matrix_json", "")))
        status_faq = limit_status_faq(status_faq, max_items)
        status_snapshot = limit_status_snapshot(status_snapshot, max_items)
        status_matrix = limit_status_matrix(status_matrix, max_items)
        status_sections = (
            render_status_faq(status_faq)
            + render_status_snapshot(status_snapshot)
            + render_status_matrix(status_matrix)
        )

    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>{title}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 24px; color: #111; }}
    h1 {{ margin-bottom: 8px; }}
    .meta {{ margin-bottom: 16px; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; font-size: 13px; }}
    th {{ background: #f2f2f2; text-align: left; }}
    .ok {{ color: #0a7a2f; font-weight: bold; }}
    .fail {{ color: #b00020; font-weight: bold; }}
    .unknown {{ color: #555; }}
    code {{ background: #f7f7f7; padding: 2px 4px; }}
    {status_css()}
  </style>
</head>
<body>
  <h1>{title}</h1>
  <div class="meta">
    <div>Total entries: {total}</div>
    <div>Pass rate: {pass_rate} ({passes} pass / {fails} fail)</div>
    <div>Latest: {summary_latest}</div>
    {summary_overview}
  </div>
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
        <th>Overview</th>
      </tr>
    </thead>
    <tbody>
      {''.join(row(e) for e in entries)}
    </tbody>
  </table>
  {status_sections}
</body>
</html>
"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    if args.limit > 0:
        entries = entries[-args.limit :]
    include_status = not args.no_status_sections
    write_markdown(args.out_md, args.title, entries, include_status, args.status_max_items)
    write_html(args.out_html, args.title, entries, include_status, args.status_max_items)
    print(f"OK: wrote {args.out_md} and {args.out_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
