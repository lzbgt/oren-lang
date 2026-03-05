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
    parser.add_argument(
        "--trend-json",
        default="",
        help="Trend JSON path (optional)",
    )
    parser.add_argument(
        "--profiles-json",
        default="",
        help="Profiles JSON path (optional)",
    )
    parser.add_argument(
        "--tags-json",
        default="",
        help="Tags JSON path (optional)",
    )
    parser.add_argument(
        "--audit-json",
        default="",
        help="Audit JSON path (optional)",
    )
    parser.add_argument(
        "--audit-trend-json",
        default="",
        help="Audit trend JSON path (optional)",
    )
    parser.add_argument(
        "--audit-samples-json",
        default="",
        help="Audit samples JSON path (optional)",
    )
    parser.add_argument(
        "--audit-samples-limit",
        type=int,
        default=10,
        help="Max audit samples to render (default: 10, 0=none)",
    )
    parser.add_argument(
        "--audit-samples-only-missing",
        action="store_true",
        help="Only render samples with missing entries.",
    )
    parser.add_argument(
        "--audit-missing-threshold",
        type=int,
        default=-1,
        help="Show alert if audit missing_any exceeds this threshold (disabled if <0).",
    )
    parser.add_argument(
        "--audit-trend-missing-threshold",
        type=int,
        default=-1,
        help="Show alert if audit trend missing_any exceeds this threshold (disabled if <0).",
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


def read_json(path: str) -> Dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def render_profiles(data: Dict[str, Any]) -> str:
    profiles = data.get("profiles") if isinstance(data.get("profiles"), dict) else {}
    if not profiles:
        return ""
    rows = []
    for name in sorted(profiles.keys()):
        entry = profiles[name]
        duration = entry.get("duration", {}) if isinstance(entry, dict) else {}
        latest = entry.get("latest", {}) if isinstance(entry, dict) else {}
        latest_label = latest.get("timestamp", "-")
        if latest.get("overall"):
            latest_label = f"{latest_label} ({latest.get('overall','-')})"
        rows.append(
            "<tr>"
            f"<td>{name}</td>"
            f"<td>{entry.get('total','-')}</td>"
            f"<td>{entry.get('pass_rate','-')}</td>"
            f"<td>{latest_label}</td>"
            f"<td>{duration.get('avg','-')} / {duration.get('min','-')} / {duration.get('max','-')}</td>"
            "</tr>"
        )
    return (
        "<h2>Profiles</h2>\n"
        "<table><thead><tr><th>Profile</th><th>Total</th><th>Pass %</th><th>Latest</th><th>Duration avg/min/max</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def render_tags(data: Dict[str, Any]) -> str:
    tags = data.get("tags") if isinstance(data.get("tags"), dict) else {}
    if not tags:
        return ""
    rows = []
    for name in sorted(tags.keys()):
        entry = tags[name]
        duration = entry.get("duration", {}) if isinstance(entry, dict) else {}
        latest = entry.get("latest", {}) if isinstance(entry, dict) else {}
        latest_label = latest.get("timestamp", "-")
        if latest.get("overall"):
            latest_label = f"{latest_label} ({latest.get('overall','-')})"
        rows.append(
            "<tr>"
            f"<td>{name}</td>"
            f"<td>{entry.get('total','-')}</td>"
            f"<td>{entry.get('pass_rate','-')}</td>"
            f"<td>{latest_label}</td>"
            f"<td>{duration.get('avg','-')} / {duration.get('min','-')} / {duration.get('max','-')}</td>"
            "</tr>"
        )
    return (
        "<h2>Tags</h2>\n"
        "<table><thead><tr><th>Tag</th><th>Total</th><th>Pass %</th><th>Latest</th><th>Duration avg/min/max</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def render_audit(data: Dict[str, Any]) -> str:
    if not data:
        return ""
    summary = {
        "checked": data.get("checked", "-"),
        "missing_any": data.get("missing_any", "-"),
        "missing_report": data.get("missing_report", "-"),
        "missing_json": data.get("missing_json", "-"),
        "missing_log_dir": data.get("missing_log_dir", "-"),
        "missing_status_snapshot_md": data.get("missing_status_snapshot_md", "-"),
        "missing_status_snapshot_json": data.get("missing_status_snapshot_json", "-"),
        "missing_status_matrix_md": data.get("missing_status_matrix_md", "-"),
        "missing_status_matrix_json": data.get("missing_status_matrix_json", "-"),
    }
    rows = []
    for key, label in (
        ("checked", "Checked"),
        ("missing_any", "Missing any"),
        ("missing_report", "Missing report"),
        ("missing_json", "Missing json"),
        ("missing_log_dir", "Missing log_dir"),
        ("missing_status_snapshot_md", "Missing status_snapshot_md"),
        ("missing_status_snapshot_json", "Missing status_snapshot_json"),
        ("missing_status_matrix_md", "Missing status_matrix_md"),
        ("missing_status_matrix_json", "Missing status_matrix_json"),
    ):
        rows.append(f"<tr><td>{label}</td><td>{summary.get(key, '-')}</td></tr>")
    sample_rows = []
    samples = data.get("samples", [])
    if isinstance(samples, list) and samples:
        for sample in samples:
            missing = sample.get("missing", [])
            if isinstance(missing, list):
                missing = ", ".join(missing)
            sample_rows.append(
                "<tr>"
                f"<td>{sample.get('timestamp','-')}</td>"
                f"<td>{sample.get('profile','-')}</td>"
                f"<td>{sample.get('tag','-')}</td>"
                f"<td>{missing}</td>"
                "</tr>"
            )
    samples_table = ""
    if sample_rows:
        samples_table = (
            "<h3>Missing samples</h3>\n"
            "<table><thead><tr><th>Timestamp</th><th>Profile</th><th>Tag</th><th>Missing</th></tr></thead>"
            f"<tbody>{''.join(sample_rows)}</tbody></table>"
        )
    return (
        "<h2>Audit summary</h2>\n"
        "<table><thead><tr><th>Metric</th><th>Value</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
        f"{samples_table}"
    )


def render_audit_trend(data: Dict[str, Any]) -> str:
    if not data:
        return ""
    window = data.get("window", 0)
    checked = data.get("checked", 0)
    missing_any = data.get("missing_any", 0)
    missing_by_kind = data.get("missing_by_kind", {})
    legend = ""
    top_missing = "-"
    if isinstance(missing_by_kind, dict) and missing_by_kind:
        items = []
        for key in sorted(missing_by_kind.keys()):
            items.append(f"{key}: {missing_by_kind.get(key, 0)}")
        top_missing = max(missing_by_kind.items(), key=lambda item: item[1])[0]
        legend = "<div class='meta'>Missing by kind: " + ", ".join(items) + "</div>\n"
    rows = []
    for entry in data.get("entries", []):
        missing = entry.get("missing", [])
        if isinstance(missing, list):
            missing = ", ".join(missing)
        rows.append(
            "<tr>"
            f"<td>{entry.get('timestamp','-')}</td>"
            f"<td>{entry.get('profile','-')}</td>"
            f"<td>{entry.get('tag','-')}</td>"
            f"<td>{entry.get('overall','-')}</td>"
            f"<td>{entry.get('missing_any','-')}</td>"
            f"<td>{missing}</td>"
            "</tr>"
        )
    return (
        "<h2>Audit trend</h2>\n"
        f"<div class='meta'>Window: {window} • Checked: {checked} • Missing any: {missing_any}</div>\n"
        f"<div class='meta'>Top missing: {top_missing}</div>\n"
        f"{legend}"
        "<table><thead><tr><th>Timestamp</th><th>Profile</th><th>Tag</th><th>Overall</th><th>Missing count</th><th>Missing</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def render_audit_samples(data: Dict[str, Any], limit: int, only_missing: bool) -> str:
    if not data or limit == 0:
        return ""
    samples = data.get("samples", [])
    if not isinstance(samples, list) or not samples:
        return (
            "<h2>Audit samples</h2>\n"
            "<div class='meta'>No missing samples recorded.</div>"
        )
    if limit > 0:
        samples = samples[:limit]
    rows = []
    for sample in samples:
        missing = sample.get("missing", [])
        if only_missing and not missing:
            continue
        if isinstance(missing, list):
            missing = ", ".join(missing)
        rows.append(
            "<tr>"
            f"<td>{sample.get('timestamp','-')}</td>"
            f"<td>{sample.get('profile','-')}</td>"
            f"<td>{sample.get('tag','-')}</td>"
            f"<td>{missing}</td>"
            "</tr>"
        )
    return (
        "<h2>Audit samples</h2>\n"
        "<table><thead><tr><th>Timestamp</th><th>Profile</th><th>Tag</th><th>Missing</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def audit_summary(data: Dict[str, Any]) -> Dict[str, Any]:
    if not data:
        return {}
    return {
        "checked": data.get("checked"),
        "missing_any": data.get("missing_any"),
        "missing_report": data.get("missing_report"),
        "missing_json": data.get("missing_json"),
        "missing_log_dir": data.get("missing_log_dir"),
        "missing_status_snapshot_md": data.get("missing_status_snapshot_md"),
        "missing_status_snapshot_json": data.get("missing_status_snapshot_json"),
        "missing_status_matrix_md": data.get("missing_status_matrix_md"),
        "missing_status_matrix_json": data.get("missing_status_matrix_json"),
    }


def audit_top_missing(summary: Dict[str, Any]) -> str:
    if not summary:
        return "-"
    def count_value(val: Any) -> int:
        if isinstance(val, int):
            return val
        return 0
    counts = {
        "report": count_value(summary.get("missing_report", 0)),
        "json": count_value(summary.get("missing_json", 0)),
        "log_dir": count_value(summary.get("missing_log_dir", 0)),
        "status_snapshot_md": count_value(summary.get("missing_status_snapshot_md", 0)),
        "status_snapshot_json": count_value(summary.get("missing_status_snapshot_json", 0)),
        "status_matrix_md": count_value(summary.get("missing_status_matrix_md", 0)),
        "status_matrix_json": count_value(summary.get("missing_status_matrix_json", 0)),
    }
    top = max(counts.items(), key=lambda item: item[1])
    if top[1] == 0:
        return "-"
    return f"{top[0]} ({top[1]})"


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
    trend = read_json(args.trend_json)
    profiles = read_json(args.profiles_json)
    tags = read_json(args.tags_json)
    audit = read_json(args.audit_json)
    audit_trend = read_json(args.audit_trend_json)
    audit_samples = read_json(args.audit_samples_json)
    audit_stats = audit_summary(audit)
    audit_top = audit_top_missing(audit_stats)
    audit_missing_any = audit_stats.get("missing_any") if audit_stats else None

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

    audit_missing = audit_stats.get("missing_any")
    audit_missing_cls = ""
    if isinstance(audit_missing, int):
        audit_missing_cls = "ok" if audit_missing == 0 else "fail"
    trend_top_missing = "-"
    if isinstance(audit_trend, dict):
        missing_by_kind = audit_trend.get("missing_by_kind", {})
        if isinstance(missing_by_kind, dict) and missing_by_kind:
            top_entry = max(missing_by_kind.items(), key=lambda item: item[1])
            if isinstance(top_entry[1], int) and top_entry[1] > 0:
                trend_top_missing = f"{top_entry[0]} ({top_entry[1]})"
    alert = ""
    alert_parts = []
    if isinstance(audit_missing_any, int) and args.audit_missing_threshold >= 0:
        if audit_missing_any > args.audit_missing_threshold:
            alert_parts.append(
                f"Audit missing_any {audit_missing_any} > {args.audit_missing_threshold}"
            )
    if isinstance(audit_trend, dict) and args.audit_trend_missing_threshold >= 0:
        trend_missing_any = audit_trend.get("missing_any")
        if isinstance(trend_missing_any, int) and trend_missing_any > args.audit_trend_missing_threshold:
            alert_parts.append(
                f"Audit trend missing_any {trend_missing_any} > {args.audit_trend_missing_threshold}"
            )
    if alert_parts:
        alert = "<div class='alert'>" + " • ".join(alert_parts) + "</div>"

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
    .card .ok {{ color: #0a7a2f; font-weight: bold; }}
    .card .fail {{ color: #b00020; font-weight: bold; }}
    .alert {{ border: 1px solid #b00020; background: #fff4f4; color: #6b0000; padding: 12px; border-radius: 6px; margin-bottom: 16px; }}
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
  {alert}
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
    <div class="card">
      <div>Trend window</div>
      <div><strong>{trend.get('window','-')}</strong></div>
    </div>
    <div class="card">
      <div>Trend pass rate</div>
      <div><strong>{trend.get('window_pass_rate','-')}</strong>%</div>
    </div>
    {f"<div class='card'><div>Audit missing</div><div><strong class='{audit_missing_cls}'>{audit_stats.get('missing_any','-')}</strong> / {audit_stats.get('checked','-')}</div></div>" if audit_stats else ""}
    {f"<div class='card'><div>Top missing</div><div><strong>{audit_top}</strong></div></div>" if audit_stats else ""}
    {f"<div class='card'><div>Top missing (trend)</div><div><strong>{trend_top_missing}</strong></div></div>" if audit_trend else ""}
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
  {render_profiles(profiles)}
  {render_tags(tags)}
  {render_audit(audit)}
  {render_audit_trend(audit_trend)}
  {render_audit_samples(audit_samples, args.audit_samples_limit, args.audit_samples_only_missing)}
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
