#!/usr/bin/env python3
import argparse
import json
import os
import sys
import csv
from typing import Any, Dict, List


FIELDS = (
    "report",
    "json",
    "log_dir",
    "status_snapshot_md",
    "status_snapshot_json",
    "status_faq_md",
    "status_faq_json",
    "status_matrix_md",
    "status_matrix_json",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit readiness index paths over the latest window."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_audit_trend.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_audit_trend.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--out-csv",
        default="",
        help="Output CSV path (optional)",
    )
    parser.add_argument(
        "--out-samples-csv",
        default="",
        help="Output CSV for missing samples (optional)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Limit to last N entries (0=all, default: 20)",
    )
    parser.add_argument(
        "--include-dry-run",
        action="store_true",
        help="Include dry_run entries (default: skip)",
    )
    parser.add_argument(
        "--max-missing-any",
        type=int,
        default=-1,
        help="Fail if missing_any exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-report",
        type=int,
        default=-1,
        help="Fail if missing report exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-json",
        type=int,
        default=-1,
        help="Fail if missing json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-log-dir",
        type=int,
        default=-1,
        help="Fail if missing log_dir exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-snapshot-md",
        type=int,
        default=-1,
        help="Fail if missing status_snapshot_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-snapshot-json",
        type=int,
        default=-1,
        help="Fail if missing status_snapshot_json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-faq-md",
        type=int,
        default=-1,
        help="Fail if missing status_faq_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-faq-json",
        type=int,
        default=-1,
        help="Fail if missing status_faq_json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-matrix-md",
        type=int,
        default=-1,
        help="Fail if missing status_matrix_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-matrix-json",
        type=int,
        default=-1,
        help="Fail if missing status_matrix_json exceeds this count (disabled if <0)",
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


def file_exists(path: str) -> bool:
    if not path:
        return False
    return os.path.exists(path)


def entry_timestamp(entry: Dict[str, Any]) -> str:
    return str(entry.get("timestamp", ""))


def missing_for_entry(entry: Dict[str, Any]) -> List[str]:
    missing: List[str] = []
    for field in FIELDS:
        value = str(entry.get(field, "") or "")
        if not value:
            continue
        if not file_exists(value):
            missing.append(field)
    return missing


def build_trend(entries: List[Dict[str, Any]], limit: int, include_dry_run: bool) -> Dict[str, Any]:
    filtered = [e for e in entries if include_dry_run or not e.get("dry_run")]
    filtered.sort(key=entry_timestamp)
    if limit and limit > 0:
        filtered = filtered[-limit:]

    counts_by_kind: Dict[str, int] = {field: 0 for field in FIELDS}
    rows: List[Dict[str, Any]] = []
    missing_any = 0
    for entry in filtered:
        missing = missing_for_entry(entry)
        if missing:
            missing_any += 1
            for field in missing:
                counts_by_kind[field] = counts_by_kind.get(field, 0) + 1
        rows.append(
            {
                "timestamp": entry.get("timestamp", ""),
                "profile": entry.get("profile", ""),
                "tag": entry.get("tag", ""),
                "overall": entry.get("overall", ""),
                "missing_any": len(missing),
                "missing": missing,
            }
        )

    return {
        "window": limit if limit else 0,
        "checked": len(filtered),
        "missing_any": missing_any,
        "missing_by_kind": counts_by_kind,
        "entries": rows,
    }


def write_markdown(path: str, trend: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index audit trend\n\n")
        f.write(f"- window: {trend.get('window', 0)}\n")
        f.write(f"- checked: {trend.get('checked', 0)}\n")
        f.write(f"- missing_any: {trend.get('missing_any', 0)}\n\n")
        f.write("## Missing by kind\n\n")
        f.write("| Field | Missing |\n")
        f.write("| --- | --- |\n")
        for field in FIELDS:
            f.write(f"| {field} | {trend.get('missing_by_kind', {}).get(field, 0)} |\n")
        f.write("\n## Entries\n\n")
        f.write("| Timestamp | Profile | Tag | Overall | Missing count | Missing |\n")
        f.write("| --- | --- | --- | --- | --- | --- |\n")
        for entry in trend.get("entries", []):
            missing = entry.get("missing", [])
            if isinstance(missing, list):
                missing = ", ".join(missing)
            f.write(
                f"| {entry.get('timestamp','-')} | {entry.get('profile','-')} | {entry.get('tag','-')} | "
                f"{entry.get('overall','-')} | {entry.get('missing_any','-')} | {missing} |\n"
            )


def write_json(path: str, trend: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(trend, f, indent=2, sort_keys=True)
        f.write("\n")


def write_csv(path: str, trend: Dict[str, Any]) -> None:
    if not path:
        return
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["timestamp", "profile", "tag", "overall", "missing_any", "missing"],
        )
        writer.writeheader()
        for entry in trend.get("entries", []):
            missing = entry.get("missing", [])
            if isinstance(missing, list):
                missing = ",".join(missing)
        writer.writerow(
            {
                    "timestamp": entry.get("timestamp", ""),
                    "profile": entry.get("profile", ""),
                    "tag": entry.get("tag", ""),
                    "overall": entry.get("overall", ""),
                    "missing_any": entry.get("missing_any", ""),
                    "missing": missing,
            }
        )


def write_samples_csv(path: str, trend: Dict[str, Any]) -> None:
    if not path:
        return
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["timestamp", "profile", "tag", "overall", "missing_any", "missing"],
        )
        writer.writeheader()
        for entry in trend.get("entries", []):
            missing = entry.get("missing", [])
            if not missing:
                continue
            if isinstance(missing, list):
                missing = ",".join(missing)
            writer.writerow(
                {
                    "timestamp": entry.get("timestamp", ""),
                    "profile": entry.get("profile", ""),
                    "tag": entry.get("tag", ""),
                    "overall": entry.get("overall", ""),
                    "missing_any": entry.get("missing_any", ""),
                    "missing": missing,
                }
            )


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    trend = build_trend(entries, args.limit, args.include_dry_run)
    write_markdown(args.out_md, trend)
    write_json(args.out_json, trend)
    if args.out_csv:
        write_csv(args.out_csv, trend)
    if args.out_samples_csv:
        write_samples_csv(args.out_samples_csv, trend)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    if args.max_missing_any >= 0 and trend.get("missing_any", 0) > args.max_missing_any:
        print(f"FAIL: missing_any {trend.get('missing_any', 0)} > {args.max_missing_any}", file=sys.stderr)
        return 2
    missing_by_kind = trend.get("missing_by_kind", {})
    thresholds = {
        "report": args.max_missing_report,
        "json": args.max_missing_json,
        "log_dir": args.max_missing_log_dir,
        "status_snapshot_md": args.max_missing_status_snapshot_md,
        "status_snapshot_json": args.max_missing_status_snapshot_json,
        "status_faq_md": args.max_missing_status_faq_md,
        "status_faq_json": args.max_missing_status_faq_json,
        "status_matrix_md": args.max_missing_status_matrix_md,
        "status_matrix_json": args.max_missing_status_matrix_json,
    }
    for field, threshold in thresholds.items():
        if threshold >= 0 and missing_by_kind.get(field, 0) > threshold:
            print(
                f"FAIL: missing_{field} {missing_by_kind.get(field, 0)} > {threshold}",
                file=sys.stderr,
            )
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
